local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local Adapter = require('earthFreight/earthAdapter')

local anchor={enuToGeodetic=function(_,x,y,z) return y/111195.0802,x/111195.0802,z end}
local st={ anchor=anchor, player={lat=5,lon=6} }
local vehiclePresent=true
local pos={x=0,y=0,z=1}
local vehicle={ getID=function() return 1 end, getPosition=function() return pos end,
  getPath=function() return 'vehicles/pickup/' end }
local core={_state=function() return st end, teleport=function() error('reading the position must never teleport') end}
local modules={ places={here=function() return 7,8 end} }
local env={ core=function() return core end, module=function(name) return modules[name] end,
  vehicle=function() return vehiclePresent and vehicle or nil end }
local a=Adapter.new(env)
local function sample() return a:sample() end

local s=sample()
T.check(s.valid,'Earth anchor plus vehicle yields valid sample'); T.eq(s.source,'anchor','live anchor preferred')
T.eq(s.vehicle.model,'pickup','model path normalized'); T.eq(s.vehicle.id,1,'vehicle id reported')
pos.y=10; s=sample(); T.near(s.latitude,10/111195.0802,1e-12,'live vehicle position converted through anchor'); pos.y=0
local oldCore=core; core=nil
T.eq(sample().reason,'earth_missing','missing mod detected without enabling it'); core=oldCore
T.check(sample().valid,'mod restored')
vehiclePresent=false; T.eq(sample().reason,'vehicle_required','no active vehicle blocks'); vehiclePresent=true

-- Fallbacks for Earth versions whose internals differ.
st.anchor=nil; s=sample(); T.eq(s.source,'player','no anchor falls back to Earth player pose'); T.eq(s.latitude,5,'player pose latitude')
st.anchor={}; T.eq(sample().source,'player','anchor without converter falls back')
st.anchor={enuToGeodetic=function() error('changed signature') end}; T.eq(sample().source,'player','failing converter falls back')
st.anchor={enuToGeodetic=function() return 0/0,0 end}; T.eq(sample().source,'player','invalid conversion falls back')
st.anchor=anchor; vehicle.getPosition=function() error('no position API') end
T.eq(sample().source,'player','missing vehicle position API falls back'); vehicle.getPosition=function() return pos end
st.anchor=nil; st.player={latitude=1,longitude=2}; s=sample()
T.eq(s.source,'player','renamed latitude/longitude pose fields accepted'); T.eq(s.longitude,2,'renamed longitude')
st.player=nil; s=sample(); T.eq(s.source,'places','places.here used when state has no pose'); T.eq(s.latitude,7,'places latitude')
core._state=nil; T.eq(sample().source,'places','missing state getter still uses places.here')
modules.places.here=function() error('changed') end
T.eq(sample().reason,'earth_starting','no working source waits instead of failing'); T.check(not sample().valid,'no source is invalid')
modules.places=nil; T.eq(sample().reason,'earth_starting','missing places module waits')
core._state=function() return st end; st.anchor=anchor; st.player={lat=0/0,lon=0}
T.eq(sample().source,'anchor','invalid player pose ignored when anchor works')

local oldPath=vehicle.getPath; vehicle.getPath=nil
T.check(sample().valid,'optional model API failure is nonfatal'); T.eq(sample().vehicle.model,nil,'unavailable model omitted')
vehicle.getPath=oldPath
vehicle.getID=function() error('no id') end
T.check(sample().valid,'optional id API failure is nonfatal'); vehicle.getID=function() return 1 end
env.vehicle=function() error('engine fault') end
T.eq(sample().reason,'earth_interface_error','engine exception isolated')
env.vehicle=function() return vehicle end
-- Earth loading/transition/pause state does not matter: only the vehicle position does.
st.pending, st.rebasing, st.paused, st.inOurLevel = true, true, true, false
T.check(sample().valid,'Earth transition flags do not block the position check')

-- The default environment finds a renamed core extension by its state getter.
local d=Adapter.new()
_G.getPlayerVehicle=function() return vehicle end
_G.beamngEarth_core=nil; _G.beamngEarth_coreV2={_state=function() return {anchor=anchor} end}
T.eq(d:sample().source,'anchor','renamed core extension discovered')
_G.beamngEarth_coreV2=nil; T.eq(d:sample().reason,'earth_missing','no Earth global reported missing')
-- Earth's GPS: set when a load is bought, guarded like the reads.
do
  local set
  local gps = { setDestination = function(lat, lon, name) set = { lat, lon, name } end }
  local mods = { gps = gps }
  local g = Adapter.new({ core = function() return core end, module = function(name) return mods[name] end,
    vehicle = function() return vehicle end })
  T.check(g:setDestination({ latitude = -33.7, longitude = 150.8 }, 'St Clair'), 'destination set')
  T.eq(set[1], -33.7, 'latitude'); T.eq(set[2], 150.8, 'longitude'); T.eq(set[3], 'St Clair', 'name')
  T.eq(select(2, g:setDestination({ latitude = 91, longitude = 0 })), 'invalid_destination', 'invalid point refused')
  mods.gps = nil; T.eq(select(2, g:setDestination({ latitude = 1, longitude = 1 })), 'gps_missing', 'no GPS module')
  local loaded = Adapter.new({ core = function() return core end, module = function() end, load = function() return gps end,
    vehicle = function() return vehicle end })
  T.check(loaded:setDestination({ latitude = 1, longitude = 2 }), 'GPS module loaded when not loaded yet')
  mods.gps = { setDestination = function() error('changed') end }
  T.eq(select(2, g:setDestination({ latitude = 1, longitude = 1 })), 'gps_failed', 'errors contained')
  mods.gps = { setDestination = 'nope' }; T.eq(select(2, g:setDestination({ latitude = 1, longitude = 1 })), 'gps_missing', 'changed API skipped')
  local none = Adapter.new({ core = function() return nil end, module = function() return gps end, vehicle = function() return vehicle end })
  T.eq(select(2, none:setDestination({ latitude = 1, longitude = 1 })), 'earth_missing', 'no Earth, no GPS')
end
-- Teleporting to the last save goes through Earth's own teleport, guarded.
do
  local sent
  local tcore = { _state = function() return st end }
  local g = Adapter.new({ core = function() return tcore end, module = function() end, vehicle = function() return vehicle end })
  T.eq(select(2, g:teleport({ latitude = 1, longitude = 2 })), 'teleport_missing', 'an Earth without teleport is skipped')
  tcore.teleport = function(lat, lon, name, opts) sent = { lat, lon, name, opts }; return true end
  T.check(g:teleport({ latitude = -33.7, longitude = 150.8 }, 'Worldwide Trucking: last save'), 'teleport asked')
  T.eq(sent[1], -33.7, 'latitude'); T.eq(sent[2], 150.8, 'longitude'); T.eq(sent[3], 'Worldwide Trucking: last save', 'name')
  T.eq(sent[4], nil, 'as Earth\'s map Go button')
  T.eq(select(2, g:teleport({ latitude = 91, longitude = 0 })), 'invalid_destination', 'invalid point refused')
  tcore.teleport = function() return false end
  T.eq(select(2, g:teleport({ latitude = 1, longitude = 2 })), 'teleport_refused', 'Earth saying no is reported')
  tcore.teleport = function() error('changed') end
  T.eq(select(2, g:teleport({ latitude = 1, longitude = 2 })), 'teleport_failed', 'errors contained')
  local none = Adapter.new({ core = function() return nil end, module = function() end, vehicle = function() return vehicle end })
  T.eq(select(2, none:teleport({ latitude = 1, longitude = 2 })), 'earth_missing', 'no Earth, no teleport')
end
-- Which way the car points.
do
  local car = { getPosition = function() return { x = 0, y = 0, z = 5 } end, getID = function() return 1 end,
    getDirectionVector = function() return { x = 1, y = 0, z = 0 } end }
  local g = Adapter.new({ core = function() return { _state = function() return { anchor = anchor } end } end, module = function() end,
    vehicle = function() return car end })
  T.near(g:sample().heading, 90, 1e-9, 'pointing east is 90 degrees')
  car.getDirectionVector = function() return { x = 0, y = -1, z = 0 } end
  T.near(g:sample().heading, 180, 1e-9, 'south is 180')
  car.getDirectionVector = function() error('changed') end
  T.check(g:sample().valid and g:sample().heading == nil, 'no heading without the call, and the sample still stands')
end
-- Earth's status bar names, read only and tidied; nil when Earth has none.
do
  local bar = { loc = { street = '  Thames\nStreet ', place = 'Baltimore', region = 'Maryland', country = '' } }
  bar.location = function() return bar.loc end
  local mods = { statusbar = bar }
  local e = Adapter.new({ core = function() return {} end, module = function(n) return mods[n] end, vehicle = function() return nil end,
    load = function() error('never loads an Earth module for names') end })
  local n = e:placeNames()
  T.eq(n.street, 'Thames Street', 'street tidied'); T.eq(n.place, 'Baltimore', 'town'); T.eq(n.region, 'Maryland', 'state')
  T.eq(n.country, nil, 'empty parts left out')
  bar.loc = { street = '', place = '', region = '', country = '' }; T.eq(e:placeNames(), nil, 'nothing found yet')
  bar.loc = { place = string.rep('a', 80) }; T.eq(#e:placeNames().place, 60, 'long names cut short')
  bar.loc = { place = string.rep('a', 59) .. 'é' }; T.eq(e:placeNames().place, string.rep('a', 59), 'never half a letter')
  bar.loc = { place = 42 }; T.eq(e:placeNames(), nil, 'only text')
  bar.location = function() error('changed') end; T.eq(e:placeNames(), nil, 'a changed status bar is skipped')
  mods.statusbar = nil; T.eq(e:placeNames(), nil, 'no status bar loaded')
  local gone = Adapter.new({ core = function() return nil end, module = function(n) return mods[n] end, vehicle = function() return nil end })
  T.eq(gone:placeNames(), nil, 'no Earth')
end

-- Which way the camera looks, for Street View: +y is north, +x east.
do
  local cam
  local st2 = { anchor = { enuToGeodetic = function(_, x, y) return y / 111195, x / 111195 end } }
  local v = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 0, z = 0 } end }
  local ca = Adapter.new({ core = function() return { _state = function() return st2 end } end, module = function() end,
    vehicle = function() return v end, cameraForward = function() return cam end })
  cam = { x = -1, y = 0, z = 0 }; T.near(ca:sample().cameraHeading, 270, 1e-9, 'camera looking west')
  cam = { x = 0, y = 1, z = -0.2 }; T.near(ca:sample().cameraHeading, 0, 1e-9, 'camera looking north')
  cam = { x = 0, y = 0, z = -1 }; T.eq(ca:sample().cameraHeading, nil, 'straight down has no direction')
  cam = nil; T.eq(ca:sample().cameraHeading, nil, 'no camera, no direction')
  local broken = Adapter.new({ core = function() return { _state = function() return st2 end } end, module = function() end,
    vehicle = function() return v end, cameraForward = function() error('no camera') end })
  T.check(broken:sample().valid, 'a failing camera does not break the position'); T.eq(broken:sample().cameraHeading, nil, 'and gives no direction')
end

-- BeamNG.Earth's modding API (1.9.0 on) comes first; the internals stand in when it is missing or fails.
do
  local pose = { lat = -41.29, lon = 174.78, heading = 45, camera = false }
  local calls = {}
  local api = { version = function() return 1, 1 end,
    pose = function() return pose end,
    place = function() return { place = 'Wellington', country = 'New Zealand' } end,
    gpsSet = function(lat, lon, name) calls.gps = { lat, lon, name }; return true end,
    teleport = function(lat, lon, name) calls.tp = { lat, lon, name }; return true end }
  local icore = { _state = function() return { anchor = anchor } end,
    teleport = function() calls.coreTp = true; return true end }
  local mods = { gps = { setDestination = function() calls.coreGps = true end },
    statusbar = { location = function() return { place = 'From the status bar' } end } }
  local car = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 111195.0802, z = 0 } end,
    getDirectionVector = function() return { x = 0, y = 1, z = 0 } end }
  local apiOn = true
  local g = Adapter.new({ core = function() return icore end, api = function() return apiOn and api or nil end,
    module = function(n) return mods[n] end, vehicle = function() return car end })
  local s = g:sample()
  T.eq(s.source, 'api', 'the API is asked first'); T.eq(s.latitude, -41.29, 'API latitude')
  T.eq(s.heading, 45, 'the API heading (true north) is used')
  T.eq(g:placeNames().place, 'Wellington', 'place names from the API')
  T.check(g:setDestination({ latitude = 1, longitude = 2 }, 'Depot'), 'GPS through the API')
  T.eq(calls.gps[3], 'Depot', 'GPS name through the API'); T.eq(calls.coreGps, nil, 'internals not touched')
  T.check(g:teleport({ latitude = 3, longitude = 4 }, 'Port'), 'teleport through the API')
  T.eq(calls.tp[1], 3, 'teleport latitude'); T.eq(calls.coreTp, nil, 'core teleport not touched')
  api.teleport = function() return false, 'Companion server not connected' end
  local ok, why, detail = g:teleport({ latitude = 3, longitude = 4 })
  T.check(not ok and why == 'teleport_refused' and detail == 'Companion server not connected', 'the API saying no is reported')
  T.eq(calls.coreTp, nil, 'a refusal is not retried through the internals')
  -- A failing or changed API falls back to the internals.
  api.pose = function() error('changed') end; api.place = function() error('changed') end
  api.gpsSet = function() error('changed') end; api.teleport = function() error('changed') end
  T.eq(g:sample().source, 'anchor', 'a failing API pose falls back to the anchor')
  T.near(g:sample().latitude, 1, 1e-9, 'anchor position'); T.near(g:sample().heading, 0, 1e-9, 'heading from the car')
  T.eq(g:placeNames().place, 'From the status bar', 'a failing API place falls back to the status bar')
  T.check(g:setDestination({ latitude = 1, longitude = 2 }) and calls.coreGps, 'a failing API GPS falls back')
  T.check(g:teleport({ latitude = 1, longitude = 2 }) and calls.coreTp, 'a failing API teleport falls back')
  api.pose = function() return { lat = 1, lon = 2, camera = true } end
  T.eq(g:sample().source, 'anchor', 'the free camera is not the car')
  api.pose = function() return nil end
  T.eq(g:sample().source, 'anchor', 'no API pose yet falls back')
  apiOn = false; T.eq(g:sample().source, 'anchor', 'no API (older Earth) uses the internals')
  -- The API alone counts as Earth being there.
  local only = Adapter.new({ core = function() return nil end, api = function() return { version = function() return 1 end,
    pose = function() return { lat = 5, lon = 6 } end } end, module = function() end, vehicle = function() return car end })
  T.eq(only:sample().source, 'api', 'the API without a core global still works')
  -- Only version 1 of the API is used.
  _G.beamngEarth_api = { version = function() return 2, 0 end }; T.eq(Adapter.findApi(), nil, 'a new major version is not used')
  _G.beamngEarth_api = { version = function() error('x') end }; T.eq(Adapter.findApi(), nil, 'a broken version check')
  _G.beamngEarth_api = { version = function() return 1, 0 end }; T.check(Adapter.findApi() ~= nil, 'version 1 found')
  _G.beamngEarth_api = nil
end

T.done('Earth adapter (mocked engine)')
