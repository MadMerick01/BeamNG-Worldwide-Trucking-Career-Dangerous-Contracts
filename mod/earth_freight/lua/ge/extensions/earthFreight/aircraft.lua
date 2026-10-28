-- The game side of heli flights: reads where the player's helicopter is and how high it flies.
-- Base-game calls only, each guarded: a missing or changed one makes the call return nil.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    objectById = function(id) return getObjectByID(id) end,
    -- The distance down to the ground or a building from a point, or nil when nothing is below.
    ground = function(x, y, z)
      local ray = rawget(_G, 'castRayStatic')
      if type(ray) ~= 'function' then return nil end
      local d = ray(vec3(x, y, z), vec3(0, 0, -1), 2000)
      return type(d) == 'number' and d < 2000 and d or nil
    end,
  }
end

local function point(v) return { x = v.x, y = v.y, z = v.z } end

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

  return a
end

return M
