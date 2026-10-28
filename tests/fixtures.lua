local F = {}
function F.copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = F.copy(v) end
  return out
end
function F.position(lat, lon) return { latitude = lat == nil and 0 or lat, longitude = lon == nil and 0 or lon } end
-- Penrith, where a new game starts, and St Clair, its nearest neighbour in the place list.
F.PENRITH = { latitude = -33.75, longitude = 150.7 }
F.CONFIG = '/settings/earthFreight/config.json'
function F.config(base) return { base = F.copy(base or F.PENRITH), resumeRadiusMetres = 50 } end
function F.save(generation, lat, lon)
  return {
    schemaVersion = 1, generation = generation or 1, profileId = 'default', base = F.copy(F.PENRITH),
    resume = F.position(lat, lon), progression = { balance = 0, totalDistanceKm = 0 }, vehicle = { model = 'pickup' },
  }
end
function F.io(files)
  local io = { files = files or {}, writes = 0, directories = 0 }
  io.exists = function(path)
    if io.existsFails then error('permission denied') end
    return io.files[path] ~= nil
  end
  io.read = function(path)
    if io.readFails == path then error('unreadable') end
    return F.copy(io.files[path])
  end
  io.mkdir = function() io.directories = io.directories + 1; return not io.mkdirFails end
  io.write = function(path, data)
    io.writes = io.writes + 1
    if io.writeFails then io.files[path] = 'partial JSON'; return false end
    io.files[path] = F.copy(data)
    if io.writeMismatch then io.files[path].generation = 99 end
    if io.writeRounds then io.files[path].resume.latitude = io.files[path].resume.latitude + 1e-9 end
    if io.readbackFails then io.readFails = path end
    if io.writeReturnsNil then return nil end
    return true
  end
  return io
end
-- Stand-in for Earth: the vehicle position, the GPS destinations set and the teleports asked for.
function F.adapter(pose)
  local a = { pose = pose or F.copy(F.PENRITH), valid = true, vehicle = { id = 1, model = 'pickup' }, gps = {}, teleports = {} }
  function a:invalidate() end
  function a:sample()
    if not self.valid then return { valid = false, reason = self.reason or 'vehicle_required' } end
    return {
      valid = true, latitude = self.pose.latitude, longitude = self.pose.longitude, vehicle = F.copy(self.vehicle),
    }
  end
  function a:setDestination(point, name)
    if self.gpsMissing then return false, 'gps_missing' end
    self.gps[#self.gps + 1] = { latitude = point.latitude, longitude = point.longitude, name = name }
    return true
  end
  function a:teleport(point, name)
    if self.teleportRefused then return false, 'teleport_refused' end
    self.teleports[#self.teleports + 1] = { latitude = point.latitude, longitude = point.longitude, name = name }
    return true
  end
  return a
end
-- Stand-in for the garage: damage to report, fitted parts and whether the game accepts a respawn.
function F.garage()
  local g = { damage = 0, vehicleId = 1, model = 'pickup', repairs = 0, accepts = true,
    fitted = { engine = 'pickup_engine_v8', intake = 'pickup_intake_stock' },
    values = { pickup_engine_v8 = 4000, pickup_intake_stock = 100, pickup_turbo = 2400, pickup_intake_race = 800,
      pickup_cargo_load_box_m = 600, pickup_cargo_load_box_l = 1500 },
    names = { pickup_cargo_load_box_m = 'Cargo Load Box M', pickup_cargo_load_box_l = 'Cargo Load Box L' },
    carValues = { pickup = 20000, burnside = 3500, sport = 40000 }, parked = {} }
  function g:carValue(model) return self.carValues[model], model end
  function g:enter(id)
    local car = self.parked[id]
    if not car then return false, 'vehicle_gone' end
    self.parked[id] = nil
    self.vehicleId, self.model, self.fitted, self.damage = id, car.model, car.fitted, car.damage
    return true
  end
  function g:inspect()
    if self.unreadable then return nil, 'damage_unavailable' end
    return { id = self.vehicleId, damage = self.damage }
  end
  function g:parts()
    if self.partsUnreadable then return nil, 'parts_unavailable' end
    local names = {}
    for _, part in pairs(self.fitted) do names[part] = self.names[part] or part end
    return { id = self.vehicleId, model = self.model, config = { model = self.model, parts = F.copy(self.fitted) },
      parts = F.copy(self.fitted), values = F.copy(self.values), names = names,
      value = self.carValues[self.model], name = self.model }
  end
  -- Parts menu stand-in: fits parts for free and respawns, which mends the damage.
  function g:fit(slot, part)
    self.fitted[slot], self.damage = part, 0
  end
  g.spawns = {}
  function g:spawnConfig(model, config)
    if not self.accepts then return false, 'spawn_failed', 'rejected' end
    self.spawns[#self.spawns + 1] = { model = model, config = F.copy(config) }
    if type(config) == 'table' then
      self.model, self.fitted, self.damage = model, F.copy(config.parts), 0
    elseif self.configParts[config] then
      self.model, self.fitted, self.damage = model, F.copy(self.configParts[config]), 0
    elseif self.starter then
      self.model, self.fitted, self.damage = model, F.copy(self.starter), 0
    end
    return true
  end
  -- The game's car list, as garage:configs() gives it, and the parts each .pc file fits.
  g.configList = {
    { model = 'sport', key = 'gt', config = 'vehicles/sport/gt.pc', name = 'Sport GT', value = 40000, type = 'Car', source = 'BeamNG - Official' },
    { model = 'pickup', key = 'd15', config = 'vehicles/pickup/d15.pc', name = 'Pickup D15', value = 20000, type = 'Truck', source = 'BeamNG - Official' },
    { model = 'flatbed', key = 'long', config = 'vehicles/flatbed/long.pc', name = 'Flatbed', value = 5000, type = 'Trailer', source = 'BeamNG - Official' },
    { model = 'modcar', key = 'x', config = 'vehicles/modcar/x.pc', name = 'Mod car', value = 1000, type = 'Car', source = 'Mod' },
  }
  g.configParts = { ['vehicles/sport/gt.pc'] = { engine = 'sport_engine' }, ['vehicles/pickup/d15.pc'] = { engine = 'pickup_engine_v8' } }
  function g:configs() return self.configList end
  g.wears = {}
  function g:wear(km, look) self.wears[#self.wears + 1] = { km = km, look = look, model = self.model }; return true end
  -- The recovery menu's teleport to the last road: moves the car back to the road it was on.
  g.roadTrips = 0
  function g:toRoad()
    if self.noRoad then return false, 'road_unavailable' end
    self.roadTrips = self.roadTrips + 1
    return true
  end
  function g:repair(config)
    if not self.accepts then return false, 'repair_failed', 'rejected' end
    self.repairs, self.damage = self.repairs + 1, 0
    if config then self.fitted = F.copy(config.parts) end
    return true
  end
  return g
end
-- Stand-in for the puncture maker: counts bursts; tests set whether the car is off road.
function F.punctures()
  local p = { bursts = 0, off = false, checks = 0 }
  function p:burst()
    if self.fails then return false, 'burst_failed', 'rejected' end
    self.bursts = self.bursts + 1
    return true
  end
  function p:offRoad() self.checks = self.checks + 1; return self.off end
  return p
end
-- Stand-in for the cargo weight: records each weight set and each ask for the tanks' size. Tests
-- answer through the controller's tanksRead, as the car would.
function F.cargo()
  local c = { weights = {}, tankReads = 0 }
  function c:setWeight(kg, parts, fluid) self.weights[#self.weights + 1] = { kg = kg, parts = F.copy(parts), fluid = F.copy(fluid) }; return true end
  function c:readTanks() self.tankReads = self.tankReads + 1; return true end
  return c
end
-- Stand-in for the fuel tank: records reads and sets. Tests answer through the controller's
-- fuelReading and fuelSet, as the car would.
function F.fuel()
  local f = { reads = 0, sets = {} }
  function f:read() self.reads = self.reads + 1; return true end
  function f:set(litres, serial) self.sets[#self.sets + 1] = { litres = litres, serial = serial }; return true end
  return f
end
-- Stand-in for the heli loads: each load is a world position and damage by id; the player's
-- vehicle stands at player. Tests move them and answer through the controller's loadMass.
function F.aircraft()
  local a = { player = { x = 0, y = 0, z = 0 }, loads = {}, spawned = {}, masses = {}, removed = {}, nextId = 100, ground = 0 }
  function a:where(id)
    if id == nil then return F.copy(self.player) end
    local load = self.loads[id]
    return load and F.copy(load.pos) or nil
  end
  function a:height(id)
    if id == nil then return self.ground end
    return self.loads[id] and (self.loads[id].height or 0) or nil
  end
  function a:damage(id) return self.loads[id] and self.loads[id].damage or nil end
  function a:spawnLoad(model, config, ahead)
    if self.fails then return nil, 'spawn_failed' end
    self.nextId = self.nextId + 1
    self.loads[self.nextId] = { model = model, config = config, damage = 0,
      pos = { x = self.player.x, y = self.player.y + ahead, z = 0 } }
    self.spawned[#self.spawned + 1] = self.nextId
    return self.nextId
  end
  function a:setMass(id, kg) self.masses[#self.masses + 1] = { id = id, kg = kg }; return true end
  function a:remove(id) self.loads[id] = nil; self.removed[#self.removed + 1] = id; return true end
  return a
end
function F.controller(options)
  local Core = require('earthFreight/core')
  options = options or {}
  local io = options.io or F.io({ [F.CONFIG] = F.config(options.base) })
  local adapter = options.adapter or F.adapter()
  local garage = options.garage or F.garage()
  local cargo = options.cargo or F.cargo()
  local fuel = options.fuel or F.fuel()
  local events, logs = {}, {}
  local c = Core.new({ io = io, adapter = adapter, garage = garage, paused = options.paused, random = options.random,
    punctures = options.punctures, cargo = cargo, fuel = fuel, aircraft = options.aircraft,
    trigger = function(name, view) events[#events + 1] = { name = name, data = F.copy(view) } end,
    log = function(level, tag, message) logs[#logs + 1] = message end })
  return c, io, adapter, garage, cargo, fuel, logs
end
-- Puts a job on every board, first: a good from wherever the board is to the place given. Returns its id.
function F.offer(c, to, good)
  local jobs = require('earthFreight/jobs')
  local board = c.board
  c.board = function(self, place)
    local list = board(self, place)
    if place.id ~= to.id then
      table.insert(list, 1, { id = good .. '_' .. to.id, good = good, from = place.id, to = to.id, km = jobs.roadKm(place, to) })
    end
    return list
  end
  return good .. '_' .. to.id
end
function F.advance(c, seconds)
  for _ = 1, math.ceil(seconds * 10) do c:tick(0.1) end
end
-- Drives from where the adapter is to a point in steps of at most 100 m at 50 m/s, then stops.
function F.drive(c, a, to)
  local location = require('earthFreight/location')
  local left = location.distance(a.pose, to)
  while left > 100 do
    a.pose = location.destination(a.pose, location.bearing(a.pose, to), 100)
    c:tick(2)
    left = location.distance(a.pose, to)
  end
  a.pose = F.copy(to); c:tick(2)
  c:tick(0.6); c:tick(0.6)
end
return F
