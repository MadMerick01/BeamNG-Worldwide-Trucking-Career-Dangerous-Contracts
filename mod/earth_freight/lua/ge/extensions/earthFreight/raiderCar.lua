-- The game's side of the Raiders (raiderPack.lua) on the special delivery. Copied from MadMerick's Tanker mod, where
-- the Hoons do the same (its hoonCar.lua and packCar.lua). Each Raider drives one of MadMerick's four Raider cars, shipped in
-- this mod, in equal amounts (27 Nov): the rusty and the fast Barstow (vehicles/barstow), a black 4WD Roamer
-- (vehicles/roamer) and a white front-cab van (vehicles/van). If the game lacks the one picked, the next is used;
-- with none, a plain one of FALLBACKS, in order. The cars are loaded when the run starts and kept hidden
-- (switched off, high above the player, so they cost nothing and are not drawn) until a Raider needs one: switching a
-- car back on is instant, where loading one mid-drive hitches the frame rate. A Raider that is done goes back into
-- hiding for the next.
--
-- Driving uses the Raiders' own desert driver (lua/vehicle/extensions/earthFreightRaider.lua, Tanker's driver),
-- which drives at a point at a speed, road or no road. Every game call is guarded: a missing or changed one means no
-- Raider, never an error.
--
-- The Raiders go for the truck: while the player is out walking, targetId is the car they got out of, so the
-- Raiders keep circling it rather than chasing the walker.
local behind = require('earthFreight/behind')
local M = {}

M.RAIDERS = {
  { model = 'barstow', config = 'earth_freight_raider_old1' },
  { model = 'barstow', config = 'earth_freight_raider_fast2' },
  { model = 'roamer', config = 'earth_freight_raider_black4wd' },
  { model = 'van', config = 'earth_freight_raider_frontcab' },
}
M.FALLBACKS = { 'moonhawk', 'burnside' }
local function configPath(r) return 'vehicles/' .. r.model .. '/' .. r.config .. '.pc' end
-- How high above the player the cars wait while hidden, in metres.
M.HIDE_LIFT = 2000

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    random = function() return math.random() end,
    byId = function(id) return be and be:getObjectByID(id) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    map = function() return rawget(_G, 'map') end,
    spawn = function() return rawget(_G, 'spawn') end,
    vec3 = function(x, y, z) return vec3(x, y, z) end,
    quatFromDir = function(dir, up) return quatFromDir(dir, up) end,
    -- Where the camera is and which way it looks (behind.lua keeps spawns out of its view).
    cameraPosition = function()
      if type(getCameraPosition) == 'function' then return getCameraPosition() end
      if core_camera and core_camera.getPosition then return core_camera.getPosition() end
    end,
    cameraForward = function()
      if type(getCameraForward) == 'function' then return getCameraForward() end
      if core_camera and core_camera.getForward then return core_camera.getForward() end
    end,
    -- The height of whatever is solid under x, y, from a few metres above z.
    ground = function(x, y, z)
      if be and be.getSurfaceHeightBelow then
        local h = be:getSurfaceHeightBelow(vec3(x, y, z + 5))
        if type(h) == 'number' and h > -1e6 then return h end
      end
      if type(castRayStatic) == 'function' then
        local d = castRayStatic(vec3(x, y, z + 5), vec3(0, 0, -1), 50)
        if type(d) == 'number' and d < 50 then return z + 5 - d end
      end
    end,
  }
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function xyz(p)
  if not p then return nil end
  local ok, x, y, z = pcall(function() return p.x, p.y, p.z end)
  if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
end

-- Runs inside a Raider's car: drive at this point at this speed with the Raiders' own driver. With no driver, it
-- tells the game (logged once).
local DRIVE = [[
if extensions and not extensions.earthFreightRaider then pcall(extensions.load, 'earthFreightRaider') end
if extensions and extensions.earthFreightRaider then
  extensions.earthFreightRaider.target(%.2f, %.2f, %.2f, %.2f, %s)
elseif obj then
  obj:queueGameEngineLua('if earthFreight_core then earthFreight_core.raiderProblem(%d, "no_raider_driver") end')
end
]]
-- The driving modes a point may ask for (see earthFreightRaider.control), as Lua in the command.
local MODES = { coast = '"coast"', swipe = '"swipe"' }
-- Hands the car back from the driver and switches the game's AI off.
local STOP = [[
if extensions and extensions.earthFreightRaider then extensions.earthFreightRaider.stop() end
if ai then pcall(ai.setMode, 'disabled') end
]]

function M.new(environment)
  local env = environment or defaults()
  local h = { targetId = nil }
  local spares, loaded = {}, {}

  local function playerId()
    local ok, c = pcall(env.player)
    if not (ok and c) then return nil end
    local okId, id = pcall(function() return c:getID() end)
    if okId then return id end
  end
  -- A Raider's car, never the player's own vehicle or the truck they got out of.
  local function car(id)
    if id == nil or id == playerId() or id == h.targetId then return nil end
    local ok, c = pcall(env.byId, id)
    return ok and c or nil
  end
  local function notForPlayer(c) pcall(function() c.playerUsable = false end) end

  local function pose(c)
    if not c then return nil end
    local okId, id = pcall(function() return c:getID() end)
    local okPos, pos = pcall(function() return c:getPosition() end)
    local okDir, dir = pcall(function() return c:getDirectionVector() end)
    local okVel, vel = pcall(function() return c:getVelocity() end)
    local x, y, z = xyz(okPos and pos)
    if not (okId and type(id) == 'number' and x) then return nil end
    local dx, dy = 0, 1
    local fx, fy = xyz(okDir and dir)
    if fx then
      local len = math.sqrt(fx * fx + fy * fy)
      if len > 1e-6 then dx, dy = fx / len, fy / len end
    end
    local vx, vy, vz = xyz(okVel and vel)
    return { id = id, x = x, y = y, z = z, dx = dx, dy = dy,
      speed = vx and math.sqrt(vx * vx + vy * vy + vz * vz) or 0 }
  end

  -- What the Raiders go for: the truck (targetId while the player walks), else the player's vehicle.
  function h:player()
    if self.targetId then
      local ok, c = pcall(env.byId, self.targetId)
      local p = ok and pose(c)
      if p then return p end
    end
    local ok, c = pcall(env.player)
    return ok and pose(c) or nil
  end

  -- Where the player is: the walker, when they are out walking.
  function h:walker()
    local ok, c = pcall(env.player)
    return ok and pose(c) or nil
  end

  -- The car for the next Raider: its model, and its config path or nil for a plain one.
  function h:model()
    local ok, vehicles = pcall(env.vehicles)
    if not ok or type(vehicles) ~= 'table' then return nil end
    local function has(name)
      if type(vehicles.getModel) ~= 'function' then return true end
      local okModel, found = pcall(vehicles.getModel, name)
      return okModel and type(found) == 'table' and next(found) ~= nil
    end
    local okRoll, roll = pcall(env.random)
    local n = #M.RAIDERS
    local first = (okRoll and type(roll) == 'number' and roll >= 0 and roll < 1) and math.floor(roll * n) or 0
    for k = 0, n - 1 do
      local r = M.RAIDERS[(first + k) % n + 1]
      if has(r.model) then return r.model, configPath(r) end
    end
    for _, name in ipairs(M.FALLBACKS) do
      if has(name) then return name end
    end
  end

  -- Stops the car's driver and switches it off, above wherever the player is.
  function h:hide(id)
    local c = car(id)
    if not c then return false end
    notForPlayer(c)
    pcall(function() c:queueLuaCommand(STOP) end)
    local me = self:player()
    if me then pcall(function() c:setPositionRotation(me.x, me.y, me.z + M.HIDE_LIFT, 0, 0, 0, 1) end) end
    return (pcall(function() c:setActive(0) end))
  end

  -- Loads one Raider's car high above the player and hides it. Returns its id, or nil and why.
  function h:load()
    local me = self:player()
    if not me then return nil, 'vehicle_required' end
    local name, config = self:model()
    if not name then return nil, 'no_raider_model' end
    local okVehicles, vehicles = pcall(env.vehicles)
    if not okVehicles or type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then
      return nil, 'spawn_unavailable'
    end
    local okPos, pos = pcall(env.vec3, me.x, me.y, me.z + M.HIDE_LIFT)
    local ok, c = pcall(vehicles.spawnNewVehicle, name,
      { config = config, pos = okPos and pos or nil, autoEnterVehicle = false })
    if not ok or not c then return nil, 'spawn_failed', tostring(c) end
    local okId, id = pcall(function() return c:getID() end)
    if not okId or type(id) ~= 'number' then return nil, 'spawn_failed' end
    loaded[#loaded + 1] = id
    self:hide(id)
    return id
  end

  -- Loads cars until count are hidden and ready. Returns how many are ready, and the last problem, if any.
  function h:preload(count)
    local why
    while #spares < count do
      local id, problem, detail = self:load()
      if not id then why = tostring(problem) .. (detail and (': ' .. detail) or ''); break end
      spares[#spares + 1] = id
    end
    return #spares, why
  end

  -- A car for a new Raider: a hidden one, else one loaded now. Returns its id and 'own', or nil and why.
  function h:take()
    local id = table.remove(spares)
    while id and not car(id) do id = table.remove(spares) end
    if id then return id, 'own' end
    local why, detail
    id, why, detail = self:load()
    if not id then return nil, tostring(why) .. (detail and (': ' .. detail) or '') end
    return id, 'own'
  end

  function h:camera() return behind.camera(env) end

  function h:ground(x, y, z)
    local ok, g = pcall(env.ground, x, y, z)
    if ok and finite(g) then return g end
  end

  -- Switches car id on and puts it down at x, y, z facing along dx, dy. Returns true, or false and why.
  function h:place(id, x, y, z, dx, dy)
    local c = car(id)
    if not c then return false, 'no_car' end
    notForPlayer(c)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then dx, dy, len = 0, 1, 1 end
    local okActive = pcall(function() c:setActive(1) end)
    if not okActive then return false, 'activate_failed' end
    local placed = false
    local okPos, pos = pcall(env.vec3, x, y, z + 0.5)
    local okDir, dir = pcall(env.vec3, dx / len, dy / len, 0)
    local okUp, up = pcall(env.vec3, 0, 0, 1)
    local okRot, rot = false, nil
    if okDir and okUp then okRot, rot = pcall(env.quatFromDir, dir, up) end
    local okSpawn, spawn = pcall(env.spawn)
    if okPos and okRot and okSpawn and type(spawn) == 'table' and type(spawn.safeTeleport) == 'function' then
      placed = pcall(spawn.safeTeleport, c, pos, rot)
    end
    if not placed then
      placed = pcall(function() c:setPositionRotation(x, y, z + 0.5, 0, 0, 0, 1) end)
    end
    if not placed then return false, 'place_failed' end
    return true
  end

  -- Moves car id a little way to x, y, z without resetting it, so its damage stays as it was: for lifting a car past
  -- a bush out of sight. Falls back to place().
  function h:hop(id, x, y, z, dx, dy)
    local c = car(id)
    if not c then return false, 'no_car' end
    local okPos, pos = pcall(env.vec3, x, y, z + 0.5)
    if okPos and pcall(function() c:setPositionNoPhysicsReset(pos) end) then return true end
    return self:place(id, x, y, z, dx, dy)
  end

  -- aim: x, y, z to drive at and speed in metres a second.
  function h:goTo(id, aim)
    local c = car(id)
    if not (c and aim and finite(aim.x) and finite(aim.y) and finite(aim.z) and finite(aim.speed)) then return false end
    return (pcall(function() c:queueLuaCommand(string.format(DRIVE, aim.x, aim.y, aim.z, aim.speed, MODES[aim.mode] or 'nil', id)) end))
  end

  -- Calms a downed Raider so a wreck does not keep revving.
  function h:calm(id)
    local c = car(id)
    return c ~= nil and (pcall(function() c:queueLuaCommand(STOP) end))
  end

  -- Where the Raider is and how fast it goes, or nil if the car is gone.
  function h:state(id)
    local p = pose(car(id))
    if p then return { x = p.x, y = p.y, z = p.z, speed = p.speed } end
  end

  -- Hides the Raider's car for the next Raider.
  function h:release(id)
    if not car(id) then return false end
    self:hide(id)
    spares[#spares + 1] = id
    return true
  end

  -- Deletes the cars it loaded: the run is over.
  function h:removeAll()
    for _, id in ipairs(loaded) do
      local c = car(id)
      if c then pcall(function() c:delete() end) end
    end
    loaded, spares = {}, {}
  end

  return h
end

return M
