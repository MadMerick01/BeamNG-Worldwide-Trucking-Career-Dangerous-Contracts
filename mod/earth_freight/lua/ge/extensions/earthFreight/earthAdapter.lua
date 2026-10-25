-- The only Earth Freight module permitted to touch BeamNG.Earth. It never calls teleport,
-- loads/enables Earth, or replaces any upstream function. It asks where the player vehicle is
-- geographically, and its one write is setting Earth's GPS destination when a load is bought.
-- Not tied to an Earth version: each position source is tried in turn and any missing or
-- changed one is skipped, so Earth updates only break Earth Freight if every source changes.
local location = require('earthFreight/location')
local M = {}

local function findCore()
  local core = rawget(_G, 'beamngEarth_core')
  if type(core) == 'table' then return core end
  -- A renamed core extension is still found by its read-only state getter.
  for name, value in pairs(_G) do
    if type(name) == 'string' and name:find('^beamngEarth') and type(value) == 'table'
        and type(value._state) == 'function' then return value end
  end
end

local function defaults()
  return {
    core = findCore,
    module = function(name) return package.loaded['beamngEarth/' .. name] end,
    -- Loads one of Earth's modules that is not loaded yet; only asked once Earth's core is found.
    load = function(name) return require('beamngEarth/' .. name) end,
    vehicle = function() return getPlayerVehicle(0) end,
  }
end

local function failed(reason, detail)
  return { valid = false, available = false, reason = reason, detail = detail }
end

local function position(lat, lon)
  local p = { latitude = lat, longitude = lon }
  if location.valid(p) then return p end
end

function M.new(environment)
  local env = environment or defaults()
  local a = {}
  function a:invalidate() end

  -- Each source returns a position or nil; errors from a changed interface are contained.
  local function try(f, ...)
    local ok, lat, lon = pcall(f, ...)
    if ok then return position(lat, lon) end
  end
  local sources = {
    -- Live vehicle position through Earth's current anchor (most accurate, every release so far).
    { name = 'anchor', read = function(st, pos)
      if type(st) == 'table' and type(st.anchor) == 'table' and type(st.anchor.enuToGeodetic) == 'function' and pos then
        return try(st.anchor.enuToGeodetic, st.anchor, pos.x, pos.y, pos.z)
      end
    end },
    -- Earth's own last recorded player position.
    { name = 'player', read = function(st)
      if type(st) == 'table' and type(st.player) == 'table' then
        return position(st.player.lat or st.player.latitude, st.player.lon or st.player.longitude)
      end
    end },
    -- Earth's places helper, used by its settings page.
    { name = 'places', read = function()
      local places = env.module and env.module('places')
      if type(places) == 'table' and type(places.here) == 'function' then return try(places.here) end
    end },
  }

  local function sample()
    local core = env.core()
    if type(core) ~= 'table' then return failed('earth_missing') end
    local vehicle = env.vehicle()
    if not vehicle then return failed('vehicle_required') end
    local st
    if type(core._state) == 'function' then
      local ok, value = pcall(core._state)
      if ok then st = value end
    end
    local posOK, pos = pcall(function() return vehicle:getPosition() end)
    if not posOK then pos = nil end
    local current, source
    for _, s in ipairs(sources) do
      current = s.read(st, pos)
      if current then source = s.name; break end
    end
    if not current then return failed('earth_starting') end
    local model
    local pathOK, path = pcall(function() return vehicle:getPath() end)
    if pathOK and type(path) == 'string' then model = path:match('^/?vehicles/([^/\\]+)/?') end
    local idOK, id = pcall(function() return vehicle:getID() end)
    return {
      valid = true, available = true, latitude = current.latitude, longitude = current.longitude,
      source = source, vehicle = { id = idOK and id or nil, model = model },
    }
  end

  function a:sample()
    local ok, result = pcall(sample)
    if not ok then return failed('earth_interface_error', tostring(result)) end
    return result
  end

  -- Sets Earth's GPS destination: Earth plans a road route there, draws it on its map and puts
  -- the game's route arrows on the road. Guarded like the reads: with no Earth, no GPS module or
  -- a changed setDestination it does nothing and returns false and why. Returns true once called.
  function a:setDestination(point, name)
    if not location.valid(point) then return false, 'invalid_destination' end
    local okCore, core = pcall(env.core)
    if not okCore or type(core) ~= 'table' then return false, 'earth_missing' end
    local gps = env.module and env.module('gps')
    if type(gps) ~= 'table' and env.load then
      local okLoad, loaded = pcall(env.load, 'gps')
      if okLoad then gps = loaded end
    end
    if type(gps) ~= 'table' or type(gps.setDestination) ~= 'function' then return false, 'gps_missing' end
    local ok, why = pcall(gps.setDestination, point.latitude, point.longitude, type(name) == 'string' and name or nil)
    if not ok then return false, 'gps_failed', tostring(why) end
    return true
  end
  return a
end

return M
