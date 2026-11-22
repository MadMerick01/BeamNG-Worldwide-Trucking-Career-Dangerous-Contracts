-- The game side of depots (depots.lua): where the player and their truck are in the world, the
-- ground and roads around a spot, and the depot's tin shed, desk and computer, put down and taken
-- away. Base-game calls only, every one guarded: a missing or changed one makes the call return nil
-- or false. The objects are made on this PC only, so online each player's game makes its own and
-- nothing goes through the server.
local M = {}

-- The career garages' desk and computer, and a tin shed, from the game's shared art: on every map.
M.SHAPES = {
  shed = '/assets/meshes/architecture/buildings/industrial/ind_bld_tin_01_shed.dae',
  desk = '/art/shapes/garage_and_dealership/garage/s_office_desk.dae',
  computer = '/art/shapes/garage_and_dealership/garage/s_office_computer.dae',
  screen = '/art/shapes/garage_and_dealership/garage/s_office_computer_ON.dae',
}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    objectById = function(id) return getObjectByID(id) end,
    map = function() return rawget(_G, 'map') end,
    point = function(x, y, z) return vec3(x, y, z) end,
    -- How far down from a point the ground (or anything solid standing on it) is, or nil.
    ray = function(x, y, z, down)
      local cast = rawget(_G, 'castRayStatic')
      if type(cast) ~= 'function' then return nil end
      local d = cast(vec3(x, y, z), vec3(0, 0, -1), down)
      return type(d) == 'number' and d == d and d < down and d or nil
    end,
    -- An upright rotation whose forward points along a direction.
    upright = function(x, y) return quatFromDir(vec3(x, y, 0), vec3(0, 0, 1)) end,
    create = function(kind) return createObject(kind) end,
    group = function() return scenetree and scenetree.MissionGroup end,
    -- The shed's two tin materials, which only some of the game's levels define (BeamNG.Earth does
    -- not): loaded from the mod's own file unless the level already has them.
    materials = function()
      local load = rawget(_G, 'loadJsonMaterialsFile')
      if type(load) ~= 'function' then return false end
      local find = scenetree and scenetree.findObject
      if find and find('ind_tin_01') and find('ind_tin_02') then return true end
      load(M.MATERIALS)
      return true
    end,
    -- Whether this game can put objects down and look at the ground at all.
    available = function()
      return type(rawget(_G, 'createObject')) == 'function' and type(rawget(_G, 'castRayStatic')) == 'function'
        and type(rawget(_G, 'quatFromDir')) == 'function'
    end,
  }
end

M.MATERIALS = '/art/shapes/earth_freight_depot/main.materials.json'

-- Rays look for the ground from RAY_FROM metres above the player, down to RAY_DOWN metres.
M.RAY_FROM, M.RAY_DOWN = 300, 900

local function point(v) return { x = v.x, y = v.y, z = v.z } end

function M.new(environment)
  local env = environment or defaults()
  local w = {}

  -- Whether depots can be made in this game.
  function w:available()
    local ok, yes = pcall(env.available)
    return ok and yes == true
  end

  local function object(id)
    if id == nil then
      local ok, vehicle = pcall(env.vehicle)
      return ok and vehicle or nil
    end
    local ok, found = pcall(env.objectById, id)
    return ok and found or nil
  end

  -- Where a vehicle is, { x, y, z } with x east, y north and z up; the player's (or their walker's)
  -- when id is nil. Nil when it is gone.
  function w:where(id)
    local vehicle = object(id)
    if not vehicle then return nil end
    local ok, pos = pcall(function() return point(vehicle:getPosition()) end)
    return ok and pos or nil
  end

  -- The height of the ground, or the top of whatever stands on it, at x, y; nil where Earth has not
  -- loaded the ground yet.
  function w:ground(x, y, nearZ)
    local top = (nearZ or 0) + M.RAY_FROM
    local ok, d = pcall(env.ray, x, y, top, M.RAY_DOWN)
    if not ok or type(d) ~= 'number' then return nil end
    return top - d
  end

  -- The nearest road to x, y, z: the closest point on it, its direction, its half width and how far
  -- it is. Nil when the game has no road map here.
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
      local len = math.sqrt(len2)
      local dx, dy = 1, 0
      if len > 1e-3 then dx, dy = rx / len, ry / len end
      local radius = ((tonumber(na.radius) or 3) + (tonumber(nb.radius) or 3)) / 2
      return { x = px, y = py, z = na.pos.z + (nb.pos.z - na.pos.z) * u, dx = dx, dy = dy, radius = radius,
        metres = math.sqrt((px - x) ^ 2 + (py - y) ^ 2) }
    end)
    return ok and result or nil
  end

  -- Puts down one of SHAPES at x, y, z, its forward along fx, fy. Returns its id, or nil.
  local made = 0
  local materialsLoaded = false
  function w:place(shape, x, y, z, fx, fy)
    local path = M.SHAPES[shape]
    if not path then return nil end
    if not materialsLoaded and env.materials then
      materialsLoaded = true
      pcall(env.materials)
    end
    local ok, id = pcall(function()
      local o = env.create('TSStatic')
      if not o then return nil end
      o:setField('shapeName', 0, path)
      -- Not solid: BeamNG.Earth puts each building down on whatever solid thing is under it, so a
      -- building that loads after the depot would otherwise be put on the shed's roof. Not solid, it
      -- stands on the ground, and the depot's checks (which only see solid things) find it and move.
      o:setField('collisionType', 0, 'None')
      o:setField('decalType', 0, 'None')
      o:setPosition(env.point(x, y, z))
      o.canSave = false
      made = made + 1
      o:registerObject('earthFreight_depot_' .. shape .. '_' .. made)
      local group = env.group()
      if group then group:addObject(o) end
      -- Turned to face fx, fy: by a rotation where the game has one, else by the angle about the
      -- vertical (depots.lua checks which way it really faces and turns the rest round to match).
      local turned = pcall(function()
        local q = env.upright(fx, fy)
        o:setPosRot(x, y, z, q.x, q.y, q.z, q.w)
      end)
      if not turned then
        o:setField('rotation', 0, string.format('0 0 1 %.3f', math.deg(math.atan2(-fx, fy))))
        o:setPosition(env.point(x, y, z))
      end
      return o:getID()
    end)
    return ok and id or nil
  end

  -- Which way an object put down by place faces: its forward, x and y; nil when unreadable.
  function w:forward(id)
    local o = object(id)
    if not o then return nil end
    local ok, f = pcall(function()
      local v = o:getTransform():getColumn(1)
      return { x = v.x, y = v.y }
    end)
    return ok and f or nil
  end

  -- Takes an object put down by place away again.
  function w:remove(id)
    local o = object(id)
    if not o then return false end
    return (pcall(function() o:delete() end))
  end

  return w
end

return M
