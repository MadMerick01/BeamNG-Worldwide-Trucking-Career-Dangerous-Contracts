local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
-- The cargo weight and fuel commands run inside the car. Each is run here against a stand-in car:
-- nodes with masses, fuel tanks, and obj:queueGameEngineLua answering the game side.
local cargo = require('earthFreight/cargo')
local fuel = require('earthFreight/fuel')

local function car(id)
  local c = { commands = {}, id = id or 7 }
  function c:getID() return self.id end
  function c:queueLuaCommand(command) self.commands[#self.commands + 1] = command end
  return c
end
-- Runs a car command with its own globals; returns what it sent back to the game side.
local function run(command, world)
  local replies = {}
  world.obj = world.obj or {}
  world.obj.queueGameEngineLua = function(_, text) replies[#replies + 1] = text end
  setmetatable(world, { __index = _G })
  local chunk = assert(loadstring(command))
  setfenv(chunk, world)
  chunk()
  return replies
end

-- Weight: spread over the box's nodes, put back to the nodes' own masses when it changes.
do
  local vehicle = car()
  local w = cargo.new({ player = function() return vehicle end })
  T.check(w:setWeight(100, { 'pickup_cargo_load_box_m' }), 'weight sent')
  local masses = { [0] = 10, [1] = 10, [2] = 5 }
  local world = {
    v = { data = { nodes = { [0] = { cid = 0, partOrigin = 'pickup_cargo_load_box_m' }, [1] = { cid = 1, partOrigin = 'pickup_cargo_load_box_m' },
      [2] = { cid = 2, partOrigin = 'pickup_body' } } } },
    obj = { setNodeMass = function(_, cid, m) masses[cid] = m end, getNodeMass = function(_, cid) return masses[cid] end },
  }
  run(vehicle.commands[1], world)
  T.eq(masses[0], 60, 'half the load on each box node'); T.eq(masses[2], 5, 'body node untouched')
  w:setWeight(40, { 'pickup_cargo_load_box_m' }); run(vehicle.commands[2], world)
  T.eq(masses[0], 30, 'a new weight replaces the old, not added to it')
  w:setWeight(0, {}); run(vehicle.commands[3], world)
  T.eq(masses[0], 10, 'no load: own mass back'); T.eq(masses[1], 10, 'both nodes')
  -- No box: over the whole car.
  w:setWeight(25, {}); run(vehicle.commands[4], world)
  T.eq(masses[2], 5 + 25 / 3, 'boot load spread over the car')
  T.check(not vehicle.commands[5], 'nothing else sent')
  w:setWeight(10, { 'bad"]] os.exit() --' }); T.check(not vehicle.commands[5]:find('os.exit', 1, true), 'part names are never pasted into the command unchecked')
  T.eq(select(2, cargo.new({ player = function() return nil end }):setWeight(10, {})), 'vehicle_required', 'needs a car')
  run(vehicle.commands[5], { v = {}, obj = {} }) -- a car without nodes: nothing happens, no error
end

-- A trailer's load is centred just ahead of its axles, so hitchShare of it rests on the hitch.
do
  local trailer = car(42)
  local w = cargo.new({ byId = function(id) return id == 42 and trailer or nil end })
  -- A trailer facing -y: hitch node at y = -4 (tagged), axle hubs at y = 2, deck nodes from -3 to 4.
  local masses, nodes = {}, {}
  local function node(cid, y, extra)
    local n = { cid = cid, pos = { x = 0, y = y, z = 1 } }
    for k, v in pairs(extra or {}) do n[k] = v end
    nodes[cid], masses[cid] = n, 5
  end
  node(0, -4, { couplerTag = 'tow_hitch' })
  for i = 1, 8 do node(i, -4 + i) end
  node(20, 2); node(21, 2); node(22, 2.3, { wheelID = 0 })
  local world = { v = { data = { nodes = nodes, wheels = { [0] = { node1 = 20, node2 = 21 } } } },
    obj = { setNodeMass = function(_, cid, m) masses[cid] = m end, getNodeMass = function(_, cid) return masses[cid] end } }
  T.check(w:setWeightOn(42, 1000, {}, {}, 0.12), 'sent')
  run(trailer.commands[1], world)
  local total, moment = 0, 0
  for cid, n in pairs(nodes) do
    local added = masses[cid] - 5
    total, moment = total + added, moment + added * n.pos.y
  end
  T.near(total, 1000, 1e-6, 'all the weight is on the trailer')
  local centre = moment / total
  T.near((2 - centre) / (2 - -4), 0.12, 1e-3, '12% of it rests on the hitch')
  T.check(centre < 2, 'the load sits ahead of the axles')
  T.eq(masses[0], 5, 'none on the coupler'); T.eq(masses[20], 5, 'none on the hubs'); T.eq(masses[22], 5, 'nor the tyres')
  local most, least = 0, math.huge
  for i = 1, 8 do most, least = math.max(most, masses[i] - 5), math.min(least, masses[i] - 5) end
  T.check(most / least <= 20 + 1e-6, 'no node takes more than 20 times another')
  -- Without wheels to find the axles, it is spread evenly as before.
  world.v.data.wheels = nil
  w:setWeightOn(42, 900, {}, {}, 0.12); run(trailer.commands[2], world)
  T.near(masses[1] - 5, 900 / 12, 1e-6, 'even spread over every node')
  -- A share outside 0..1 is never sent: the load is then spread evenly.
  w:setWeightOn(42, 10, {}, {}, 2)
  T.check(trailer.commands[3]:match('^[^\n]*') :sub(-5) == ', nil', 'a share outside 0..1 is sent as none')
end

-- Fluid: the tank's own container is filled through its jbeam expressions, so it sloshes.
do
  -- A stand-in for BeamNG's expression parser: "$=" then Lua arithmetic in $names.
  local parser = { compileSafe = function(text)
    local vars = {}
    local body = text:gsub('^%$=', ''):gsub('%$(%w+)', function(name) return 'V["$' .. name .. '"]' end)
    local f = assert(loadstring('local V = ...; return ' .. body))
    return function() return f(vars) end, vars
  end }
  local vehicle = car(9)
  local w = cargo.new({ player = function() return vehicle end })
  local masses, limits, bounds = { [0] = 10, [1] = 10, [2] = 5, [3] = 4 }, {}, {}
  local tank = 'pickup_cargo_load_fluid_tank_l'
  local function world()
    return {
      require = function(name) if name == 'jbeam/expressionParser' then return parser end error('no ' .. name) end,
      v = { data = {
        cargoStorage = { { groupId = 'tank', partPath = '/bed/tank/', cargoTypes = { 'fluid' }, capacity = 500 },
          { groupId = 'box', partPath = '/bed/box/', cargoTypes = { 'parcel' }, capacity = 4 } },
        nodes = {
          [0] = { cid = 0, cargoGroup = 'tank', partPath = '/bed/tank/', nodeWeightFunction = '=10+$volume*$density', partOrigin = tank },
          [1] = { cid = 1, partOrigin = tank },
          [2] = { cid = 2, partOrigin = 'pickup_body' },
          [3] = { cid = 3, cargoGroup = 'box', partPath = '/bed/box/', nodeWeightFunction = '=4+$load', partOrigin = 'box' } },
        beams = { [5] = { cid = 5, cargoGroup = 'tank', partPath = '/bed/tank/', beamLimitSpringFunction = '=100+$load', beamLimitDamp = 7,
          beamShortBoundFunction = '=0.5-$volume/1000' } } } },
      obj = { setNodeMass = function(_, cid, m) masses[cid] = m end, getNodeMass = function(_, cid) return masses[cid] end,
        setBoundedBeamSpringDampLimits = function(_, cid, s, d) limits[cid] = { s, d } end,
        setBoundedBeamShortBound = function(_, cid, b) bounds[cid] = b end },
    }
  end
  local here = world()
  T.check(w:setWeight(150, { tank }, { litres = 200, density = 0.75, tanks = { tank } }), 'fluid sent')
  local replies = run(vehicle.commands[1], here)
  T.eq(masses[0], 10 + 200 * 0.75, 'the fluid weighs on the container node'); T.eq(masses[1], 10, 'not spread over the tank as well')
  T.eq(limits[5][1], 100 + 150, 'the slosh beam follows the load'); T.eq(limits[5][2], 7, 'its own damping kept')
  T.near(bounds[5], 0.3, 1e-9, 'and its bound'); T.eq(masses[3], 4, 'the parcel container left alone')
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.tanksRead(9, 500.000) end', 'reports the real tank size')
  -- More than fits: the container is full and the rest goes over the tank's nodes.
  w:setWeight(600, { tank }, { litres = 600, density = 1, tanks = { tank } }); run(vehicle.commands[2], here)
  T.eq(masses[0], 10 + 500 + 50, 'full, plus a share of the rest'); T.eq(masses[1], 10 + 50, 'the rest over the tank')
  -- A box load empties the tank.
  w:setWeight(40, { 'box' }, { litres = 0, tanks = { tank } }); run(vehicle.commands[3], here)
  T.eq(masses[0], 10, 'tank emptied'); T.eq(masses[1], 10, 'its spread taken off'); T.eq(limits[5][1], 100, 'the slosh beam back to empty')
  T.eq(masses[3], 44, 'the box load on the box')
  -- No expression parser: the fluid still weighs, spread over the tank.
  local plain = world(); plain.require = function() error('no parser') end
  masses = { [0] = 10, [1] = 10, [2] = 5, [3] = 4 }
  w:setWeight(100, { tank }, { litres = 100, density = 1, tanks = { tank } }); run(vehicle.commands[4], plain)
  T.eq(masses[0] + masses[1], 120, 'weight still on the tank')
  -- A legacy container lists its weight nodes; they share the fluid.
  local legacy = world()
  legacy.v.data.cargoStorage = { { groupId = 'old', partOrigin = tank, cargoTypes = {}, capacity = 300, ['weightNodes:'] = { 0, 1 } } }
  legacy.v.data.nodes[0].nodeWeight, legacy.v.data.nodes[1].nodeWeight = 10, 10
  masses = { [0] = 10, [1] = 10, [2] = 5, [3] = 4 }
  w:setWeight(100, { tank }, { litres = 100, density = 1, tanks = { tank } }); replies = run(vehicle.commands[5], legacy)
  T.eq(masses[0], 60, 'half on each weight node'); T.eq(masses[1], 60, 'both')
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.tanksRead(9, 300.000) end', 'found by its part')
  -- Asking only: reports the size, changes nothing.
  masses = { [0] = 10, [1] = 10, [2] = 5, [3] = 4 }
  T.check(w:readTanks({ tank }), 'read sent'); replies = run(vehicle.commands[6], world())
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.tanksRead(9, 500.000) end', 'tank size read'); T.eq(masses[0], 10, 'nothing changed')
  replies = run(vehicle.commands[6], { v = {}, obj = {} })
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.tanksRead(9, 0.000) end', 'a car with no tank reads 0')
end

-- Fuel: read adds up the fuel tanks, leaving out batteries; set fills them and reports.
do
  local vehicle = car(7)
  local f = fuel.new({ player = function() return vehicle end })
  local function tank(volume, capacity, energyType)
    local t = { remainingVolume = volume, capacity = capacity, energyType = energyType or 'gasoline' }
    function t:setRemainingRatio(r) self.remainingVolume = r * self.capacity end
    return t
  end
  local storages = { main = tank(10, 40), aux = tank(5, 20), battery = tank(1, 1, 'electricEnergy') }
  local world = { energyStorage = { getStorages = function() return storages end } }
  T.check(f:read(), 'read sent')
  local replies = run(vehicle.commands[1], world)
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelReading(7, 15.000, 60.000, "gasoline") end', 'reports litres, capacity and fuel')
  T.check(f:set(45, 3), 'set sent')
  replies = run(vehicle.commands[2], world)
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelSet(7, 3, 15.000, 45.000, 60.000) end', 'reports before and after')
  T.eq(storages.main.remainingVolume, 30, 'tanks filled to the same share'); T.eq(storages.aux.remainingVolume, 15, 'both tanks')
  T.eq(storages.battery.remainingVolume, 1, 'battery left alone')
  T.check(f:set(500, 4), 'over-full request sent'); run(vehicle.commands[3], world)
  T.eq(storages.main.remainingVolume, 40, 'never past full')
  replies = run(vehicle.commands[1], {})
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelReading(7, 0.000, 0.000, "gasoline") end', 'a car with no tank reads empty')
  T.eq(select(2, f:set(-1)), 'invalid_litres', 'negative litres refused')
  T.eq(fuel.cost(10, 1.25), 13, 'cost per litre, to the dollar'); T.eq(fuel.cost(10, nil), 0, 'no price, no cost')
  -- A diesel tank says so.
  storages.main.energyType = 'diesel'; f:read()
  replies = run(vehicle.commands[#vehicle.commands], world)
  T.check(replies[1]:find('"diesel"', 1, true), 'a diesel car reads as diesel')
end
-- The pump the car stands at: the nearest within reach, from the game's gas station list.
do
  local pos = { x = 0, y = 0, z = 0 }
  local vehicle = { getPosition = function() return pos end }
  local gathered, gen = 0, 1
  local f = fuel.new({ player = function() return vehicle end, generation = function() return gen end,
    pumps = function()
      gathered = gathered + 1
      return { { x = 30, y = 0, z = 0, name = 'Far', energy = { diesel = true } },
               { x = 4, y = 3, z = 0, name = 'Shell Newtown', brand = 'Shell', energy = { gasoline = true } } }
    end,
    stationsShown = function() return false end, showStations = function() end })
  local p = f:pumpNear(0)
  T.eq(p and p.brand, 'Shell', 'the pump within reach'); T.near(p.metres, 5, 1e-9, 'its distance')
  f:pumpNear(1); T.eq(gathered, 1, 'the list is kept between looks')
  gen = 2; f:pumpNear(1.5); T.eq(gathered, 2, 'gathered again when the stations change')
  f:pumpNear(1.5 + fuel.STATIONS_EVERY_SECONDS); T.eq(gathered, 3, 'and every few seconds')
  pos = { x = 100, y = 0, z = 0 }; T.eq(f:pumpNear(20), nil, 'none in reach')
  T.check(f:showStations(), 'the freeroam gas stations are turned on when off')
  local broken = fuel.new({ player = function() return vehicle end, pumps = function() error('no POIs') end,
    generation = function() error('none') end, stationsShown = function() return true end, showStations = function() end })
  T.eq(broken:pumpNear(0), nil, 'a broken station list is no pump'); T.check(not broken:showStations(), 'already on: left alone')
end
T.done('vehicle commands')
