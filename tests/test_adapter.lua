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
T.done('Earth adapter (mocked engine)')
