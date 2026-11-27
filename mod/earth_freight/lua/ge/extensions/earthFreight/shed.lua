-- The game's side of the shed at the end of the Shed in the Desert (desertRun.lua): MadMerick's shed (27 Nov), a rusty
-- corrugated iron shed open at its south end, put down at the finish when the player nears it. Its shape is
-- art/shapes/earth_freight_shed, built by tools/build_shed.py. Every game call is guarded: a missing or changed one
-- means no shed, never an error. The shed is the game's own static object, not saved with the level.
local M = {}

M.SHAPE = '/art/shapes/earth_freight_shed/shed.dae'
M.MATERIALS = '/art/shapes/earth_freight_shed/main.materials.json'
M.NAME = 'earthFreightDesertShed'
-- The ground is looked for from this far above the player's height, and this far down.
M.ABOVE, M.DOWN = 300, 600
-- Where the ground is looked for, from the shed's middle: just outside its walls and roof (12 m by 18 m, with a 0.6 m
-- overhang), so a ray never lands on the shed itself. The lowest is used: the walls go 1.5 m into the sand, and a shed
-- sunk a little into a dune looks right where one standing on its crest floats (MadMerick, 27 Nov).
M.PROBES = { { 7.5, 10.5 }, { -7.5, 10.5 }, { 7.5, -10.5 }, { -7.5, -10.5 }, { 7.5, 0 }, { -7.5, 0 }, { 0, 10.5 }, { 0, -10.5 } }

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    find = function(name) return scenetree and scenetree.findObject(name) end,
    exists = function(path) return FS and FS:fileExists(path) end,
    loadMaterials = function(path) return loadJsonMaterialsFile(path) end,
    create = function() return createObject('TSStatic') end,
    -- The height of the ground under x, y, from high above z.
    ground = function(x, y, z)
      local top = z + M.ABOVE
      if type(castRayStatic) == 'function' then
        local d = castRayStatic(vec3(x, y, top), vec3(0, 0, -1), M.DOWN)
        if type(d) == 'number' and d < M.DOWN then return top - d end
      end
      if be and be.getSurfaceHeightBelow then
        local h = be:getSurfaceHeightBelow(vec3(x, y, top))
        if type(h) == 'number' and h > -1e6 then return h end
      end
    end,
  }
end

function M.new(environment)
  local env = environment or defaults()
  local s = {}
  local materials = false

  -- Where the player's car (or walker) is, { x, y, z } with x east, y north and z up, or nil.
  function s:where()
    local ok, x, y, z = pcall(function()
      local p = env.player():getPosition()
      return p.x, p.y, p.z
    end)
    if ok and finite(x) and finite(y) and finite(z) then return { x = x, y = y, z = z } end
  end

  -- Whether the shed is in the world.
  function s:there()
    local ok, o = pcall(env.find, M.NAME)
    return ok and o ~= nil
  end

  function s:remove()
    local ok, o = pcall(env.find, M.NAME)
    if ok and o then pcall(function() o:delete() end) end
  end

  -- The height of the ground around a shed at x, y (from near height z): the lowest of PROBES, or nil.
  function s:groundAt(x, y, z)
    local low
    for _, p in ipairs(M.PROBES) do
      local ok, g = pcall(env.ground, x + p[1], y + p[2], z)
      if ok and finite(g) and (not low or g < low) then low = g end
    end
    return low
  end

  -- Moves the shed already down to height z at x, y. Returns true, or false.
  function s:move(x, y, z)
    local ok, o = pcall(env.find, M.NAME)
    if not ok or not o then return false end
    return (pcall(function() o:setPosRot(x, y, z, 0, 0, 0, 1) end))
  end

  -- Puts the shed down at x, y (near height z), open end south, at height ground, or else on the ground found
  -- around it. Any shed already there goes first. Returns the height it was put at, or false and why.
  function s:place(x, y, z, ground)
    self:remove()
    local okFile, has = pcall(env.exists, M.SHAPE)
    if not okFile or not has then return false, 'no_shed_shape' end
    local g = finite(ground) and ground or self:groundAt(x, y, z)
    if not finite(g) then return false, 'no_ground' end
    if not materials then
      materials = true
      pcall(env.loadMaterials, M.MATERIALS)
    end
    local ok, why = pcall(function()
      local o = env.create()
      o.shapeName = M.SHAPE
      o:setField('collisionType', 0, 'Visible Mesh')
      o:setField('decalType', 0, 'None')
      o:setField('castShadows', 0, '1')
      o:setField('canSave', 0, '0')
      o:registerObject(M.NAME)
      o:setPosRot(x, y, g, 0, 0, 0, 1)
    end)
    if not ok then
      self:remove()
      return false, 'shed_failed: ' .. tostring(why)
    end
    return g
  end

  return s
end

return M
