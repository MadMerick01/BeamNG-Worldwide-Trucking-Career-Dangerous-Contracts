-- The base thief's car (thief.lua): puts it down on the road ahead of the player, sets it fleeing, tells how far it
-- is, cuts its ignition when the EMP hits, and takes it away. Base-game calls, every one guarded.
-- The flee: the game's own flee AI, with MadMerick's smartAI profile when that mod is installed (it adds
-- ai.setSmartProfile), watched over by fleeSupervisor.lua, which slows it and keeps it in lane in traffic. The EMP: the ignition is cut and the AI switched off here; when MadMerick's Bolides – The Cut
-- mod is installed its EMP effect (shockwave, hazards, sound) plays as well.
local M = {}

local fleeSupervisor = require('earthFreight/fleeSupervisor')

-- How the thief drives: the smartAI profile name, and the stock AI's settings.
M.SMART_PROFILE = 'moonhawk'
M.AGGRESSION = 0.5

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    objectById = function(id) return getObjectByID(id) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    -- The road map, to put the car on the nearest road.
    map = function() return rawget(_G, 'map') end,
    -- BeamNG's spawn module, whose safeTeleport puts a car down on the ground.
    spawn = function() return rawget(_G, 'spawn') or (package.loaded and package.loaded.spawn) end,
    enter = function(vehicle) be:enterVehicle(0, vehicle) end,
    point = function(x, y, z) return vec3(x, y, z) end,
    upright = function(dir) return quatFromDir(dir, vec3(0, 0, 1)) end,
    -- Bolides – The Cut's EMP effect, when that mod is installed; and whether Bolides runs it every frame itself.
    emp = function()
      local ok, m = pcall(require, 'lua/ge/extensions/events/emp')
      return ok and type(m) == 'table' and type(m.trigger) == 'function' and m or nil
    end,
    bolidesRunning = function() return extensions ~= nil and extensions.bolidesTheCut ~= nil end,
    -- The height of the ground under a point, or nil where Earth hasn't loaded any yet.
    groundBelow = function(pos)
      if not be or type(be.getSurfaceHeightBelow) ~= 'function' then return pos.z end
      local h = be:getSurfaceHeightBelow(vec3(pos.x, pos.y, pos.z + 50))
      if type(h) ~= 'number' or h ~= h or h < -1e5 then return nil end
      return h
    end,
    -- A random paint for the robber's car, or nil where the game can't make one.
    paint = function(random)
      local make = rawget(_G, 'createVehiclePaint')
      if type(make) ~= 'function' then return nil end
      return make({ x = random(), y = random(), z = random(), w = 1 }, { 0.2 + random() * 0.6, 1, 0.1 + random() * 0.4, 0.4 })
    end,
    random = math.random,
  }
end

-- What the thief's car runs to flee from the player's car (id tid).
function M.fleeCommand(tid)
  return string.format([[
local tid = %d
if not ai then return end
local function try(f, ...) if type(f) == 'function' then pcall(f, ...) end end
try(ai.setSmartProfile, '%s')
try(ai.setMode, 'flee')
try(ai.setTargetObjectID, tid)
try(ai.setAggression, %s)
try(ai.setAvoidCars, 'on')
try(ai.setRecoverOnCrash, true)
]], tid, M.SMART_PROFILE, tostring(M.AGGRESSION))
end

-- The road robber, lurking in the player's lane ahead of them: the game's traffic AI, keeping to its lane, no faster
-- than kph.
function M.lurkCommand(kph)
  return string.format([[
if not ai then return end
local function try(f, ...) if type(f) == 'function' then pcall(f, ...) end end
try(ai.setMode, 'traffic')
try(ai.driveInLane, 'on')
try(ai.setAvoidCars, 'on')
try(ai.setAggression, 0.3)
try(ai.setSpeedMode, 'limit')
try(ai.setSpeed, %s)
]], tostring(math.max(0, kph) / 3.6))
end

-- The road robber hunting the player's car (id tid), at no more than kph.
function M.huntCommand(tid, kph)
  return string.format([[
local tid = %d
if not ai then return end
local function try(f, ...) if type(f) == 'function' then pcall(f, ...) end end
try(ai.setMode, 'chase')
try(ai.setTargetObjectID, tid)
try(ai.setAggression, 0.6)
try(ai.setAvoidCars, 'on')
try(ai.setRecoverOnCrash, true)
try(ai.setSpeedMode, 'limit')
try(ai.setSpeed, %s)
]], tid, tostring(math.max(0, kph) / 3.6))
end

-- A new top speed for the robber's AI.
function M.speedCommand(kph)
  return string.format("if ai and ai.setSpeed then pcall(ai.setSpeed, %s) end", tostring(math.max(0, kph) / 3.6))
end

-- What the player's car runs when the road robber's EMP hits it: hazards on, throttle off, ignition off. No brake lock,
-- so a truck at speed coasts instead of jackknifing.
M.PLAYER_EMP_START = [[
local s = extensions and (extensions.earthFreightEmp or {}) or {}
if extensions then extensions.earthFreightEmp = s end
if electrics and electrics.values then s.ign = electrics.values.ignitionLevel; s.warn = electrics.values.warn_signal end
if electrics and electrics.toggle_warn_signal and electrics.values and not electrics.values.warn_signal then pcall(electrics.toggle_warn_signal) end
if input and input.event then pcall(input.event, 'throttle', 0, 1) end
if electrics and electrics.setIgnitionLevel then pcall(electrics.setIgnitionLevel, 0)
elseif controller and controller.mainController and controller.mainController.setIgnitionLevel then pcall(controller.mainController.setIgnitionLevel, 0) end
]]

-- And when it wears off: the ignition back as it was (on, if unknown), hazards back off.
M.PLAYER_EMP_END = [[
local s = extensions and extensions.earthFreightEmp or {}
local level = s.ign
if level == nil or level < 2 then level = 2 end
if electrics and electrics.setIgnitionLevel then pcall(electrics.setIgnitionLevel, level)
elseif controller and controller.mainController and controller.mainController.setIgnitionLevel then pcall(controller.mainController.setIgnitionLevel, level) end
if electrics and electrics.toggle_warn_signal and electrics.values and electrics.values.warn_signal and not s.warn then pcall(electrics.toggle_warn_signal) end
s.ign, s.warn = nil, nil
]]

-- What the thief's car runs when the EMP hits: AI off, ignition off, handbrake on.
M.EMP_COMMAND = [[
if ai and ai.setMode then pcall(ai.setMode, 'disabled') end
if electrics and electrics.setIgnitionLevel then pcall(electrics.setIgnitionLevel, 0) end
if controller and controller.mainController and controller.mainController.setIgnitionLevel then pcall(controller.mainController.setIgnitionLevel, 0) end
if input and input.event then pcall(input.event, 'parkingbrake', 1, 1) end
]]

function M.new(env)
  env = env or defaults()
  -- Keeps the fleeing car out of the traffic.
  local t = { supervisor = env.supervisor or fleeSupervisor.new() }

  local function object(id)
    if id == nil then return nil end
    local ok, v = pcall(env.objectById, id)
    return ok and v or nil
  end

  local function player()
    local ok, v = pcall(env.vehicle)
    return ok and v or nil
  end

  -- Where the car goes: the nearest road to a point metres in front of the player, lined up with the road and
  -- pointing away from the player. Without a road map, that point itself, facing away.
  local function spot(car, metres)
    local dir, at = car:getDirectionVector(), car:getPosition()
    local dx, dy = dir.x, dir.y
    local size = math.sqrt(dx * dx + dy * dy)
    if size < 1e-3 then dx, dy, size = 0, 1, 1 end
    dx, dy = dx / size, dy / size
    local x, y, z = at.x + dx * metres, at.y + dy * metres, at.z
    local fx, fy = dx, dy
    local m = env.map()
    if type(m) == 'table' and type(m.findClosestRoad) == 'function' and type(m.getMap) == 'function' then
      local ok, _, a, b = pcall(m.findClosestRoad, env.point(x, y, z))
      local nodes = ok and a and b and m.getMap().nodes
      local na, nb = nodes and nodes[a], nodes and nodes[b]
      if na and nb and na.pos and nb.pos then
        -- The point on that stretch of road closest to where it was aimed.
        local ax, ay, bx, by = na.pos.x, na.pos.y, nb.pos.x, nb.pos.y
        local rx, ry = bx - ax, by - ay
        local len2 = rx * rx + ry * ry
        local u = len2 > 1e-6 and math.max(0, math.min(1, ((x - ax) * rx + (y - ay) * ry) / len2)) or 0
        x, y, z = ax + rx * u, ay + ry * u, na.pos.z + (nb.pos.z - na.pos.z) * u
        local len = math.sqrt(len2)
        if len > 1e-3 then
          fx, fy = rx / len, ry / len
          -- Along the road, the way that leads away from the player.
          if fx * (x - at.x) + fy * (y - at.y) < 0 then fx, fy = -fx, -fy end
        end
      end
    end
    return env.point(x, y, z + 0.5), env.upright(env.point(fx, fy, 0)), fx, fy
  end

  -- Spawns the car. Returns its id, or nil and why.
  function t:spawn(model, config, ahead)
    local car = player()
    if not car then return nil, 'vehicle_required' end
    local vehicles = env.vehicles()
    if type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then return nil, 'spawn_unavailable' end
    local ok, id = pcall(function()
      local pos, rot = spot(car, ahead or 100)
      local thief = vehicles.spawnNewVehicle(model, { config = config, pos = pos, rot = rot, autoEnterVehicle = false, cling = true })
      if not thief then return nil end
      local s = env.spawn()
      if type(s) == 'table' and type(s.safeTeleport) == 'function' then pcall(s.safeTeleport, thief, pos, rot) end
      return thief:getID()
    end)
    if not ok or id == nil then return nil, 'spawn_failed' end
    -- If the game put the player in the thief's car, back to their own.
    local now = player()
    local nowOk, nowId = pcall(function() return now and now:getID() end)
    if nowOk and nowId == id then pcall(env.enter, car) end
    return id
  end

  -- Loads the road robber's car out of sight, switched off, so putting it on the road later doesn't stutter: 200 m
  -- under the player, in a random paint. Returns its id, or nil and why.
  function t:preload(model, config)
    local car = player()
    if not car then return nil, 'vehicle_required' end
    local vehicles = env.vehicles()
    if type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then return nil, 'spawn_unavailable' end
    local ok, id = pcall(function()
      local at = car:getPosition()
      local options = { config = config, pos = env.point(at.x, at.y, at.z - 200), rot = env.upright(env.point(0, 1, 0)),
        autoEnterVehicle = false, cling = false }
      local pok, paint = pcall(env.paint, env.random)
      if pok and paint then options.paint, options.paint2, options.paint3 = paint, paint, paint end
      local robber = vehicles.spawnNewVehicle(model, options)
      if not robber then return nil end
      pcall(function() robber:setActive(0) end)
      return robber:getID()
    end)
    if not ok or id == nil then return nil, 'spawn_failed' end
    local now = player()
    local nowOk, nowId = pcall(function() return now and now:getID() end)
    if nowOk and nowId == id then pcall(env.enter, car) end
    return id
  end

  -- Puts the preloaded car on the road metres ahead of the player, in their lane and facing their way, and switches it
  -- on. Only where the ground has loaded: returns false and 'no_ground' when it hasn't yet, to be tried again.
  function t:place(id, metres)
    local robber, car = object(id), player()
    if not robber or not car then return false, 'gone' end
    local ok, pos, rot = pcall(spot, car, metres)
    if not ok or not pos then return false, 'no_spot' end
    local gok, ground = pcall(env.groundBelow, pos)
    if not gok or type(ground) ~= 'number' or math.abs(ground - pos.z) > 30 then return false, 'no_ground' end
    local placed = pcall(function()
      robber:setActive(1)
      local s = env.spawn()
      if type(s) == 'table' and type(s.safeTeleport) == 'function' then s.safeTeleport(robber, pos, rot)
      else robber:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w) end
    end)
    return placed == true, placed and nil or 'teleport_failed'
  end

  -- The admin robber (adminRobber.lua): where the road spot metres ahead of the player is, as metres east and north of
  -- their car and the road's heading in degrees from north (Earth's world is east-north-up, +y north). Only where the
  -- ground has loaded: nil and 'no_ground' when it hasn't yet.
  function t:aheadOffset(metres)
    local car = player()
    if not car then return nil, 'gone' end
    local ok, pos, _, fx, fy = pcall(spot, car, metres)
    if not ok or not pos then return nil, 'no_spot' end
    local gok, ground = pcall(env.groundBelow, pos)
    if not gok or type(ground) ~= 'number' or math.abs(ground - pos.z) > 30 then return nil, 'no_ground' end
    local rok, out = pcall(function()
      local at = car:getPosition()
      return { east = pos.x - at.x, north = pos.y - at.y, heading = (math.deg(math.atan2(fx, fy)) + 360) % 360 }
    end)
    if not rok or type(out) ~= 'table' then return nil, 'no_spot' end
    return out
  end

  -- Turns the player's car to face heading (degrees from north) where it stands, on the ground. Returns true once done.
  function t:face(heading)
    local car = player()
    if not car or type(heading) ~= 'number' or heading ~= heading then return false end
    return pcall(function()
      local at, r = car:getPosition(), math.rad(heading)
      local pos, rot = env.point(at.x, at.y, at.z + 0.5), env.upright(env.point(math.sin(r), math.cos(r), 0))
      local s = env.spawn()
      if type(s) == 'table' and type(s.safeTeleport) == 'function' then s.safeTeleport(car, pos, rot)
      else car:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w) end
    end) == true
  end

  -- The player's own car stops for good: the admin robber caught (the same as the EMP on a thief). True once done.
  function t:shutDownPlayer()
    local car = player()
    if not car then return false end
    return pcall(function() car:queueLuaCommand(M.EMP_COMMAND) end) == true
  end

  -- Lurking: the traffic AI in its lane, at no more than kph.
  function t:lurk(id, kph)
    local robber = object(id)
    if not robber then return false end
    return pcall(function() robber:queueLuaCommand(M.lurkCommand(kph)) end) == true
  end

  -- Hunting the player's car at no more than kph.
  function t:hunt(id, kph)
    local robber, car = object(id), player()
    if not robber or not car then return false end
    local ok, tid = pcall(function() return car:getID() end)
    if not ok or type(tid) ~= 'number' then return false end
    return pcall(function() robber:queueLuaCommand(M.huntCommand(tid, kph)) end) == true
  end

  -- A new top speed while lurking or hunting.
  function t:setSpeed(id, kph)
    local robber = object(id)
    if not robber then return false end
    return pcall(function() robber:queueLuaCommand(M.speedCommand(kph)) end) == true
  end

  -- How fast the player's car goes, in km/h, or nil.
  function t:playerKph()
    local car = player()
    if not car then return nil end
    local ok, v = pcall(function() local u = car:getVelocity(); return math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z) * 3.6 end)
    return ok and type(v) == 'number' and v == v and v or nil
  end

  -- How far apart the two cars point, in degrees from 0 (the same way) to 180 (opposite ways), or nil.
  function t:headingGap(id)
    local robber, car = object(id), player()
    if not robber or not car then return nil end
    local ok, deg = pcall(function()
      local a, b = robber:getDirectionVector(), car:getDirectionVector()
      local la, lb = math.sqrt(a.x * a.x + a.y * a.y), math.sqrt(b.x * b.x + b.y * b.y)
      if la < 1e-3 or lb < 1e-3 then return nil end
      local cos = math.max(-1, math.min(1, (a.x * b.x + a.y * b.y) / (la * lb)))
      return math.deg(math.acos(cos))
    end)
    return ok and type(deg) == 'number' and deg == deg and deg or nil
  end

  -- The road robber's EMP hits the player's car: the engine dies until empPlayerEnd. Returns true once done.
  function t:empPlayer()
    local car = player()
    if not car then return false end
    t.victim = car
    return pcall(function() car:queueLuaCommand(M.PLAYER_EMP_START) end) == true
  end

  -- The player's engine comes back.
  function t:empPlayerEnd()
    local car = t.victim or player()
    t.victim = nil
    if not car then return false end
    return pcall(function() car:queueLuaCommand(M.PLAYER_EMP_END) end) == true
  end

  -- Sets the car fleeing from the player's car. Returns true once asked.
  function t:flee(id)
    local thief, car = object(id), player()
    if not thief or not car then return false end
    local ok, tid = pcall(function() return car:getID() end)
    if not ok or type(tid) ~= 'number' then return false end
    if pcall(function() thief:queueLuaCommand(M.fleeCommand(tid)) end) ~= true then return false end
    t.supervisor:register(id, tid)
    return true
  end

  -- Metres between the player's car and the thief's, or nil when either is gone.
  function t:distance(id)
    local thief, car = object(id), player()
    if not thief or not car then return nil end
    local ok, d = pcall(function()
      local a, b = thief:getPosition(), car:getPosition()
      local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
      return math.sqrt(x * x + y * y + z * z)
    end)
    return ok and type(d) == 'number' and d == d and d or nil
  end

  -- Which way the thief is from the way the player's car points, in degrees: 0 straight ahead, 90 to the right,
  -- -90 to the left, 180 behind. nil when either car is gone.
  function t:bearing(id)
    local thief, car = object(id), player()
    if not thief or not car then return nil end
    local ok, deg = pcall(function()
      local a, b, f = thief:getPosition(), car:getPosition(), car:getDirectionVector()
      local dx, dy = a.x - b.x, a.y - b.y
      if dx * dx + dy * dy < 1e-6 or f.x * f.x + f.y * f.y < 1e-6 then return nil end
      -- Clockwise from ahead: the cross product is positive to the left.
      return math.deg(math.atan2(-(f.x * dy - f.y * dx), f.x * dx + f.y * dy))
    end)
    return ok and type(deg) == 'number' and deg == deg and deg or nil
  end

  -- The EMP hits the thief's car. Returns true once done.
  function t:emp(id)
    local thief, car = object(id), player()
    if not thief then return false end
    -- Nothing more to the car's AI: it is switched off now.
    t.supervisor:unregister(id)
    local effect = env.emp()
    if effect and car then
      pcall(effect.trigger, { playerId = id, sourceId = car:getID(), sourcePos = car:getPosition(), empDurationSec = 10.0,
        shockDurationSec = 0.5, thrusterKickSpeed = 5.0, forceMultiplier = 0.5 })
      t.effect = effect
    end
    return pcall(function() thief:queueLuaCommand(M.EMP_COMMAND) end) == true
  end

  -- Takes the car out of the world.
  function t:remove(id)
    t.supervisor:unregister(id)
    local thief = object(id)
    if not thief then return false end
    return pcall(function() thief:delete() end) == true
  end

  -- Every frame: the supervisor looks at the traffic, and Bolides' EMP effect runs on, unless Bolides itself runs it.
  function t:update(dt)
    t.supervisor:update(dt)
    local effect = t.effect
    if effect and type(effect.onUpdate) == 'function' and not env.bolidesRunning() then pcall(effect.onUpdate, dt, dt, dt) end
  end

  return t
end

return M
