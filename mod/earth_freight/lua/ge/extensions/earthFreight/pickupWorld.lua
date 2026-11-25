-- The game side of pickup points (pickups.lua): where the player is in the world, and the nearest
-- road to a spot, to move a town's pickup point onto it. Base-game calls only, every one guarded: a
-- missing or changed one makes the call return nil. Nothing is put into the world.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    map = function() return rawget(_G, 'map') end,
    point = function(x, y, z) return vec3(x, y, z) end,
  }
end

local function point(v) return { x = v.x, y = v.y, z = v.z } end

function M.new(environment)
  local env = environment or defaults()
  local w = {}

  -- Where the player's vehicle (or their walker) is, { x, y, z } with x east, y north and z up.
  -- Nil when there is none.
  function w:where()
    local ok, pos = pcall(function()
      local vehicle = env.vehicle()
      return vehicle and point(vehicle:getPosition()) or nil
    end)
    return ok and pos or nil
  end

  -- The nearest road to x, y, z: the closest point on it, its half width and how far it is. Nil
  -- when the game has no road map here.
  function w:road(x, y, z)
    local ok, result = pcall(function()
      local m = env.map()
      if type(m) ~= 'table' or type(m.findClosestRoad) ~= 'function' or type(m.getMap) ~= 'function' then return nil end
      local _, a, b = m.findClosestRoad(env.point(x, y, z))
      local nodes = a and b and m.getMap().nodes
      local na, nb = nodes and nodes[a], nodes and nodes[b]
      if not (na and nb and na.pos and nb.pos) then return nil end
      local ax, ay, bx, by = na.pos.x, na.pos.y, nb.pos.x, nb.pos.y
      local rx, ry = bx - ax, by - ay
      local len2 = rx * rx + ry * ry
      local u = len2 > 1e-6 and math.max(0, math.min(1, ((x - ax) * rx + (y - ay) * ry) / len2)) or 0
      local px, py = ax + rx * u, ay + ry * u
      local radius = ((tonumber(na.radius) or 3) + (tonumber(nb.radius) or 3)) / 2
      return { x = px, y = py, z = na.pos.z + (nb.pos.z - na.pos.z) * u, radius = radius,
        metres = math.sqrt((px - x) ^ 2 + (py - y) ^ 2) }
    end)
    return ok and result or nil
  end

  return w
end

return M
