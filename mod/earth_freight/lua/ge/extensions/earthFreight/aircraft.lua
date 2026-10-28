-- The game side of heli flights: puts a load down in front of the player's helicopter, takes it
-- away, and reads where it is, how damaged it is and how high the helicopter flies. Base-game
-- calls only, each guarded: a missing or changed one makes the call fail and return why.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    objectById = function(id) return getObjectByID(id) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    objects = function() local m = rawget(_G, 'map'); return type(m) == 'table' and m.objects or nil end,
    -- The distance down to the ground or a building from a point, or nil when nothing is below.
    ground = function(x, y, z)
      local ray = rawget(_G, 'castRayStatic')
      if type(ray) ~= 'function' then return nil end
      local d = ray(vec3(x, y, z), vec3(0, 0, -1), 2000)
      return type(d) == 'number' and d < 2000 and d or nil
    end,
    spawn = function(model, options) return (rawget(_G, 'core_vehicles') or extensions.core_vehicles).spawnNewVehicle(model, options) end,
    position = function(x, y, z) return vec3(x, y, z) end,
    rotation = function(x, y) return quatFromDir(vec3(x, y, 0), vec3(0, 0, 1)) end,
  }
end

local function point(v) return { x = v.x, y = v.y, z = v.z } end

-- Runs inside the load: sets its whole mass to the kg asked for, by spreading what is missing
-- over its nodes, and reports the mass it ends up with. A load already heavier keeps its mass.
local MASS = [[
local id, target = %s, %s
if not (v and v.data and type(v.data.nodes) == 'table' and obj and obj.setNodeMass and obj.getNodeMass) then return end
local list, total = {}, 0
for _, n in pairs(v.data.nodes) do
  if type(n) == 'table' and n.cid then list[#list + 1] = n.cid; total = total + (obj:getNodeMass(n.cid) or 0) end
end
if #list > 0 and target > total then
  local share = (target - total) / #list
  for _, cid in ipairs(list) do obj:setNodeMass(cid, (obj:getNodeMass(cid) or 0) + share) end
  total = target
end
obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.loadMass(%%d, %%.1f) end', id, total))
]]

function M.new(environment)
  local env = environment or defaults()
  local a = {}

  local function object(id)
    if id == nil then
      local ok, vehicle = pcall(env.vehicle)
      return ok and vehicle or nil
    end
    local ok, vehicle = pcall(env.objectById, id)
    return ok and vehicle or nil
  end

  -- Where a vehicle is in the world, { x, y, z } with x east, y north and z up; the player's
  -- vehicle when id is nil. Nil when it is gone.
  function a:where(id)
    local vehicle = object(id)
    if not vehicle then return nil end
    local ok, pos = pcall(function() return point(vehicle:getPosition()) end)
    return ok and pos or nil
  end

  -- How high a vehicle is above the ground, in metres: the player's when id is nil. Nil when unknown.
  function a:height(id)
    local pos = self:where(id)
    if not pos then return nil end
    local ok, d = pcall(env.ground, pos.x, pos.y, pos.z + 0.5)
    return ok and type(d) == 'number' and math.max(0, d - 0.5) or nil
  end

  -- A vehicle's damage, as BeamNG counts it; nil when it is gone or unreadable.
  function a:damage(id)
    local ok, objects = pcall(env.objects)
    local entry = ok and type(objects) == 'table' and objects[id] or nil
    local damage = type(entry) == 'table' and tonumber(entry.damage) or nil
    if not damage or damage ~= damage or damage < 0 or damage == math.huge then return nil end
    return damage
  end

  -- Puts a load down on the ground ahead metres in front of the player's vehicle, the player staying
  -- where they are. Returns its id, or nil and why.
  function a:spawnLoad(model, config, ahead)
    local vehicle = object()
    if not vehicle then return nil, 'vehicle_required' end
    local ok, pos, dir = pcall(function() return point(vehicle:getPosition()), point(vehicle:getDirectionVector()) end)
    if not ok then return nil, 'position_unavailable' end
    local flat = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if flat < 0.01 then dir, flat = { x = 0, y = 1 }, 1 end
    local x, y = pos.x + dir.x / flat * ahead, pos.y + dir.y / flat * ahead
    local okGround, down = pcall(env.ground, x, y, pos.z + 100)
    local z = (okGround and type(down) == 'number') and (pos.z + 100 - down + 0.5) or pos.z
    local spawned, result = pcall(env.spawn, model, { config = config, pos = env.position(x, y, z),
      rot = env.rotation(dir.x, dir.y), autoEnterVehicle = false })
    if not spawned or not result then return nil, 'spawn_failed', tostring(result) end
    local idOK, id = pcall(function() return result:getID() end)
    if not idOK or id == nil then return nil, 'spawn_failed' end
    return id
  end

  -- Sets a load's whole mass in kg; it reports what it weighs through loadMass.
  function a:setMass(id, kg)
    local vehicle = object(id)
    if not vehicle then return false, 'load_gone' end
    local ok, why = pcall(function() vehicle:queueLuaCommand(string.format(MASS, tostring(id), string.format('%.1f', kg))) end)
    if not ok then return false, 'mass_failed', tostring(why) end
    return true
  end

  -- Takes a load away. True once it is gone, or was already.
  function a:remove(id)
    local vehicle = object(id)
    if not vehicle then return true end
    local ok, why = pcall(function() vehicle:delete() end)
    if not ok then return false, 'remove_failed', tostring(why) end
    return true
  end

  return a
end

return M
