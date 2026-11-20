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
    return env.point(x, y, z + 0.5), env.upright(env.point(fx, fy, 0))
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
