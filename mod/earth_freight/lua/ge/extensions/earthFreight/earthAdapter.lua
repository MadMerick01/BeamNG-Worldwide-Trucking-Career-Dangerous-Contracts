-- The only Earth Freight module permitted to touch BeamNG.Earth. It never loads/enables Earth or
-- replaces any upstream function. It asks where the player vehicle is geographically and which way
-- it points. Its writes are setting Earth's GPS destination when a job is taken and, when the player
-- presses the button, teleporting back to where they last saved (Earth's own teleport, as its map's Go).
-- Not tied to an Earth version: BeamNG.Earth's modding API (beamngEarth_api, version 1, from
-- BeamNG.Earth 1.9.0), whose names its authors keep stable, is asked first. Older Earths, or an API
-- call that fails, fall back to reading Earth's internals: each source is tried in turn and any
-- missing or changed one is skipped, so Earth updates only break Earth Freight if every way changes.
local location = require('earthFreight/location')
local M = {}
-- Earth's GPS destination counts as the one asked for within this many metres.
M.GPS_MATCH_METRES = 100

local function findCore()
  local core = rawget(_G, 'beamngEarth_core')
  if type(core) == 'table' then return core end
  -- A renamed core extension is still found by its read-only state getter.
  for name, value in pairs(_G) do
    if type(name) == 'string' and name:find('^beamngEarth') and type(value) == 'table'
        and type(value._state) == 'function' then return value end
  end
end

-- BeamNG.Earth's modding API, version 1 only (a new major version may change its names).
local function findApi()
  local api = rawget(_G, 'beamngEarth_api')
  if type(api) ~= 'table' or type(api.version) ~= 'function' then return nil end
  local ok, major = pcall(api.version)
  if ok and major == 1 then return api end
end
M.findApi = findApi

local function defaults()
  return {
    core = findCore,
    api = findApi,
    module = function(name) return package.loaded['beamngEarth/' .. name] end,
    -- Loads one of Earth's modules that is not loaded yet; only asked once Earth's core is found.
    load = function(name) return require('beamngEarth/' .. name) end,
    vehicle = function() return getPlayerVehicle(0) end,
    -- Which way the game's camera looks, for the Street View page; nil if the game cannot say.
    cameraForward = function()
      local f = rawget(_G, 'getCameraForward')
      if type(f) == 'function' then return f() end
    end,
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
  -- The API, or nil (none, the wrong version, or the environment cannot say).
  local function api()
    if not env.api then return nil end
    local ok, value = pcall(env.api)
    if ok and type(value) == 'table' then return value end
  end
  -- Calls the API's function name; ok is false when it is missing or raised an error.
  local function call(name, ...)
    local x = api()
    if not x or type(x[name]) ~= 'function' then return false end
    return pcall(x[name], ...)
  end
  local sources = {
    -- BeamNG.Earth's modding API: the player's position now, in its stable form.
    { name = 'api', read = function()
      local ok, pose = call('pose')
      if ok and type(pose) == 'table' and pose.camera ~= true then
        local p = position(pose.lat, pose.lon)
        if p then p.heading = pose.heading end
        return p
      end
    end },
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
    if type(core) ~= 'table' and not api() then return failed('earth_missing') end
    local vehicle = env.vehicle()
    if not vehicle then return failed('vehicle_required') end
    local st
    if type(core) == 'table' and type(core._state) == 'function' then
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
    -- Which way the car points, in degrees from north: Earth's world is its anchor's east-north-up
    -- frame, so +y is north (within a fraction of a degree near the anchor).
    local heading
    local dirOK, dir = pcall(function() return vehicle:getDirectionVector() end)
    if location.finite(current.heading) then
      -- The API's heading is already measured from true north.
      heading = (current.heading % 360 + 360) % 360
    elseif dirOK and type(dir) ~= 'nil' and location.finite(dir.x) and location.finite(dir.y) and (dir.x ~= 0 or dir.y ~= 0) then
      heading = (math.deg(math.atan2(dir.x, dir.y)) + 360) % 360
    end
    -- Which way the camera looks, the same way: the orbit camera can look anywhere around the car.
    -- Nil when looking straight up or down, or when the game cannot say.
    local cameraHeading
    local camOK, cam = pcall(function() return env.cameraForward and env.cameraForward() end)
    if camOK and type(cam) ~= 'nil' and location.finite(cam.x) and location.finite(cam.y) and math.abs(cam.x) + math.abs(cam.y) > 0.05 then
      cameraHeading = (math.deg(math.atan2(cam.x, cam.y)) + 360) % 360
    end
    return {
      valid = true, available = true, latitude = current.latitude, longitude = current.longitude,
      source = source, vehicle = { id = idOK and id or nil, model = model }, heading = heading, cameraHeading = cameraHeading,
    }
  end

  function a:sample()
    local ok, result = pcall(sample)
    if not ok then return failed('earth_interface_error', tostring(result)) end
    return result
  end

  -- Where the car is, by name, as Earth's own status bar at the top of the screen shows it: the
  -- street from Earth's road data, and the town, state and country Earth looks up online. Read
  -- only, from what Earth already has, so it asks nothing new of Earth or the internet. Each part is
  -- a short string or nil; the whole is nil when Earth has none of them (its status bar or online
  -- place names are off, an older Earth, or nothing found yet after a teleport).
  local function clean(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if value == '' then return nil end
    if #value > 60 then value = value:sub(1, 60):gsub('[\128-\191]*$', ''):gsub('[\192-\255]$', '') end
    return value
  end
  function a:placeNames()
    local ok, l = call('place')
    if not ok or type(l) ~= 'table' then
      local okCore, core = pcall(env.core)
      if not okCore or type(core) ~= 'table' then return nil end
      local bar = env.module and env.module('statusbar')
      if type(bar) ~= 'table' or type(bar.location) ~= 'function' then return nil end
      ok, l = pcall(bar.location)
      if not ok or type(l) ~= 'table' then return nil end
    end
    local names = { street = clean(l.street), place = clean(l.place), region = clean(l.region), country = clean(l.country) }
    if not (names.street or names.place or names.region or names.country) then return nil end
    return names
  end

  -- Sets Earth's GPS destination: Earth plans a road route there, draws it on its map and puts
  -- the game's route arrows on the road. Guarded like the reads: with no Earth, no GPS module or
  -- a changed setDestination it does nothing and returns false and why. Returns true once called.
  function a:setDestination(point, name)
    if not location.valid(point) then return false, 'invalid_destination' end
    local label = type(name) == 'string' and name or nil
    local okApi, set = call('gpsSet', point.latitude, point.longitude, label)
    if okApi and set == true then return true end
    local okCore, core = pcall(env.core)
    if not okCore or type(core) ~= 'table' then return false, 'earth_missing' end
    local gps = env.module and env.module('gps')
    if type(gps) ~= 'table' and env.load then
      local okLoad, loaded = pcall(env.load, 'gps')
      if okLoad then gps = loaded end
    end
    if type(gps) ~= 'table' or type(gps.setDestination) ~= 'function' then return false, 'gps_missing' end
    local ok, why = pcall(gps.setDestination, point.latitude, point.longitude, label)
    if not ok then return false, 'gps_failed', tostring(why) end
    return true
  end

  -- Whether Earth's modding API has a feature (api.has, from API 1.1).
  local function has(name)
    local ok, yes = call('has', name)
    return ok and yes == true
  end

  -- The length in metres of the road route Earth's GPS has planned to point (within GPS_MATCH_METRES
  -- of it), read from what Earth already has: its planned route's length (API 1.6, routeGeometry), or
  -- else the distance left on a planned route. Returns metres, or nil and why: 'none' (no GPS
  -- destination, or no API), 'other' (the GPS goes somewhere else now), 'planning' (no road route
  -- yet: still planning, or Earth's app is offline and it only points the way).
  function a:gpsRouteLength(point)
    if not location.valid(point) then return nil, 'none' end
    local ok, g = call('gps')
    if not ok or type(g) ~= 'table' then return nil, 'none' end
    local target = position(tonumber(g.lat), tonumber(g.lon))
    if not target or (location.distance(target, point) or math.huge) > M.GPS_MATCH_METRES then return nil, 'other' end
    if g.planning == true or not location.finite(g.routeVersion) or g.routeVersion <= 0 then return nil, 'planning' end
    if has('routeGeometry') then
      local okRoute, r = call('gpsRoute')
      if okRoute and type(r) == 'table' and location.finite(r.dist) and r.dist > 0
          and (r.version == nil or r.version == g.routeVersion) then return r.dist end
    end
    if location.finite(g.remaining) and g.remaining > 0 then return g.remaining end
    return nil, 'planning'
  end

  -- GPS through several stops (API 1.2, gpsSetRoute): stops is a list of { point, name }, the last one
  -- the destination. Each is sent as { lat, lon, name } by position and by name. Returns true, or
  -- false and why; on an older Earth, false and 'route_missing', so the caller sets one destination.
  function a:setRoute(stops)
    if type(stops) ~= 'table' or #stops < 2 or #stops > 11 then return false, 'invalid_route' end
    if not has('gpsRoute') then return false, 'route_missing' end
    local points = {}
    for i, stop in ipairs(stops) do
      if type(stop) ~= 'table' or not location.valid(stop.point) then return false, 'invalid_route' end
      local name = type(stop.name) == 'string' and stop.name or nil
      local lat, lon = stop.point.latitude, stop.point.longitude
      points[i] = { lat, lon, name, lat = lat, lon = lon, name = name }
    end
    local ok, set, why = call('gpsSetRoute', points)
    if ok and set == true then return true end
    return false, 'route_refused', why ~= nil and tostring(why) or nil
  end

  -- Whether Earth can be asked for the places round a point (API 1.4, places).
  function a:canFindStations() return has('places') end

  -- Asks Earth for the car parks within metres of a point, as findStations does for petrol stations:
  -- done(list, finished, failed), each { name, category, lat, lon, ... }, nearest first. Earth's map
  -- data has car parks as points, so multi-storey and underground ones are left out by their kind.
  function a:findParking(point, metres, done)
    if not location.valid(point) or type(done) ~= 'function' or not has('places') then return false end
    local opts = { radius = math.min(3000, metres or 1000), categories = { 'parking*' }, limit = 20 }
    local ok, sent = call('places', point.latitude, point.longitude, opts, function(result)
      if type(result) ~= 'table' then return done({}, false, 'no_answer') end
      if result.error ~= nil and result.error ~= false and result.error ~= '' then return done({}, false, tostring(result.error)) end
      local list = {}
      for _, p in ipairs(type(result.places) == 'table' and result.places or {}) do
        local kind = string.lower(tostring(p.category or '') .. ' ' .. tostring(p.name or ''))
        if not (kind:find('garage') or kind:find('structure') or kind:find('underground') or kind:find('multi')
            or kind:find('storey') or kind:find('story') or kind:find('rooftop')) then
          list[#list + 1] = p
        end
      end
      done(list, result.pending ~= true, nil)
    end)
    return ok and sent ~= nil and sent ~= false
  end

  -- Asks Earth for the petrol stations within metres of a point. done(list, finished, failed) is
  -- called with the stations as Earth gives them ({ name, lat, lon, open, ... }, nearest first),
  -- whether Earth has all it will find (more may come in a second answer while its map cells
  -- download), and why it failed, if it did. Returns whether the question was sent.
  function a:findStations(point, metres, done)
    if not location.valid(point) or type(done) ~= 'function' or not has('places') then return false end
    local opts = { radius = math.min(3000, metres or 3000), categories = { 'gas_station' }, limit = 20 }
    local ok, sent = call('places', point.latitude, point.longitude, opts, function(result)
      if type(result) ~= 'table' then return done({}, false, 'no_answer') end
      if result.error ~= nil and result.error ~= false and result.error ~= '' then return done({}, false, tostring(result.error)) end
      done(type(result.places) == 'table' and result.places or {}, result.pending ~= true, nil)
    end)
    return ok and sent ~= nil and sent ~= false
  end

  -- Asks Earth to teleport the player to this point, exactly as its map's Go button does, so the
  -- place also shows in Earth's recent places under this name. Guarded like the reads. True only
  -- means Earth took the request: the terrain loads and the car is placed some seconds later, and
  -- arriving is seen from the position.
  function a:teleport(point, name)
    if not location.valid(point) then return false, 'invalid_destination' end
    local label = type(name) == 'string' and name or nil
    local x = api()
    if x and type(x.teleport) == 'function' then
      -- The API answers true once Earth took it, or false and why (no level loaded, no companion server).
      local ok, sent, why = pcall(x.teleport, point.latitude, point.longitude, label)
      if ok and sent == true then return true end
      if ok and sent == false then return false, 'teleport_refused', why ~= nil and tostring(why) or nil end
    end
    local okCore, core = pcall(env.core)
    if not okCore or type(core) ~= 'table' then return false, 'earth_missing' end
    if type(core.teleport) ~= 'function' then return false, 'teleport_missing' end
    local ok, sent, why = pcall(core.teleport, point.latitude, point.longitude, label)
    if not ok then return false, 'teleport_failed', tostring(sent) end
    -- Earth answers false when it cannot, such as with its companion server not connected.
    if sent == false then return false, 'teleport_refused', why ~= nil and tostring(why) or nil end
    return true
  end
  return a
end

return M
