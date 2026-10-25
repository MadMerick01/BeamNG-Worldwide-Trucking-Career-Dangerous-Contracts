local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local Adapter = require('earthFreight/earthAdapter')

local anchor={enuToGeodetic=function(_,x,y,z) return y/111195.0802,x/111195.0802,z end}
local st={ anchor=anchor, player={lat=5,lon=6} }
local vehiclePresent=true
local pos={x=0,y=0,z=1}
local vehicle={ getID=function() return 1 end, getPosition=function() return pos end,
  getPath=function() return 'vehicles/pickup/' end }
local core={_state=function() return st end, teleport=function() error('Earth Freight must never teleport') end}
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
-- Which way the car points, and the ground at an off-road drop spot.
do
  local k = 111195.0802
  local flat = { enuToGeodetic = function(_, x, y, z) return y / k, x / k, z end,
    geodeticToEnu = function(_, lat, lon) return lon * k, lat * k, 0 end }
  local car = { getPosition = function() return { x = 0, y = 0, z = 5 } end, getID = function() return 1 end,
    getDirectionVector = function() return { x = 1, y = 0, z = 0 } end }
  local height = function(x) return x * 0.5 end
  local reach, waters = 1000, {}
  local e = { core = function() return { _state = function() return { anchor = flat } end } end, module = function() end,
    vehicle = function() return car end,
    ray = function(x, y, z, length)
      if math.abs(x) > reach or math.abs(y) > reach then return nil end
      local d = z - height(x, y)
      if d < length then return d end
    end,
    waters = function() return waters end }
  local g = Adapter.new(e)
  T.near(g:sample().heading, 90, 1e-9, 'pointing east is 90 degrees')
  car.getDirectionVector = function() return { x = 0, y = -1, z = 0 } end
  T.near(g:sample().heading, 180, 1e-9, 'south is 180')
  car.getDirectionVector = function() error('changed') end
  T.check(g:sample().valid and g:sample().heading == nil, 'no heading without the call, and the sample still stands')
  local spot = { latitude = 0, longitude = 100 / k }
  local ground = g:ground(spot)
  T.near(ground.slope, math.deg(math.atan(0.5)), 1e-6, 'the slope from the heights around the spot')
  T.eq(ground.water, false, 'dry')
  T.eq(g:ground({ latitude = 0, longitude = 2000 / k }), nil, 'ground that has not loaded reads nothing')
  height = function() return 0 end
  waters = { { x = 100, y = 0, z = 1, width = 50, depth = 50 } }
  T.eq(g:ground(spot).water, true, 'under a sea or lake tile is water')
  T.eq(g:ground({ latitude = 0, longitude = 200 / k }).water, false, 'beside it is not')
  waters = { { x = 100, y = 0, z = 0.1, width = 50, depth = 50 } }
  T.eq(g:ground(spot).water, false, 'a tile below the ground is not water')
  waters = { { x = 0, y = 0, z = 3 } }
  T.eq(g:ground(spot).water, true, 'a water plane covers everything below it')
  T.eq(g:ground({ latitude = 0 / 0, longitude = 0 }), nil, 'not a position')
  e.ray = function() error('changed') end
  T.eq(g:ground(spot), nil, 'a changed ray call reads nothing')
  T.eq(Adapter.new({ core = function() return nil end, vehicle = function() return car end, ray = e.ray }):ground(spot), nil, 'no Earth, no ground')
end
T.done('Earth adapter (mocked engine)')
