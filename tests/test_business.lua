local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local B = require('earthFreight/business')
local P = require('earthFreight/persistence')
local Core = require('earthFreight/core')
local places = require('earthFreight/places')
local location = require('earthFreight/location')
local FILE = '/settings/earthFreight/businesses.json'

local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
local stClair = placeNamed('St Clair')
local function enc(text) return (text:gsub('[^%w%-_%.!~%*\'%(%)]', function(c) return string.format('%%%02X', c:byte()) end)) end

-- The checks on what the HUD sends.
T.eq(B.decode('Bunnings%20Warehouse'), 'Bunnings Warehouse', 'percent-encoding decoded')
T.eq(B.decode('Caf%C3%A9'), 'Café', 'any alphabet')
T.eq(B.decode('a"b'), nil, 'quotes refused'); T.eq(B.decode('a%2'), nil, 'half an escape refused'); T.eq(B.decode('a%zz'), nil, 'not hex')
T.eq(B.decode(42), nil, 'only text')
local spot = location.destination(stClair, 90, 600)
local ok = B.clean({ name = '  Bunnings\nWarehouse ', kind = 'hardware', latitude = spot.latitude, longitude = spot.longitude }, stClair)
T.eq(ok.name, 'Bunnings Warehouse', 'name tidied'); T.eq(ok.kind, 'hardware', 'kind kept')
T.eq(B.clean({ name = 'X', kind = 'casino', latitude = spot.latitude, longitude = spot.longitude }, stClair), nil, 'unknown kind refused')
local far = location.destination(stClair, 90, B.MAX_FROM_TOWN + 100)
T.eq(B.clean({ name = 'X', kind = 'hardware', latitude = far.latitude, longitude = far.longitude }, stClair), nil, 'too far from town refused')
T.eq(B.clean({ name = '   ', kind = 'hardware', latitude = spot.latitude, longitude = spot.longitude }, stClair), nil, 'a name is needed')
T.eq(#B.clean({ name = string.rep('a', 59) .. 'é', kind = 'farm', latitude = 1, longitude = 1 }).name, 59, 'long names cut, never half a letter')
-- The remembered list forgets the oldest when full.
do
  local list = {}
  local old = B.MAX_REMEMBERED; B.MAX_REMEMBERED = 2
  B.remember(list, 'a', { none = true }, 1); B.remember(list, 'b', { none = true }, 2); B.remember(list, 'c', { none = true }, 3)
  T.eq(list.a, nil, 'oldest forgotten'); T.check(list.b and list.c, 'newest kept')
  B.MAX_REMEMBERED = old
  local back = B.remembered({ towns = { x = { none = true, at = 5 }, y = { name = 'Shop', kind = 'garage', latitude = 1, longitude = 2 },
    z = { name = 'Bad', kind = 'nope', latitude = 1, longitude = 2 } } })
  T.check(back.x.none and back.y.name == 'Shop' and back.z == nil, 'list read back cleaned')
  T.eq(next((B.remembered('junk'))), nil, 'a broken file is an empty list')
end

-- In the game: a town job, its business found by the HUD, delivered at the spot.
local function setup(io)
  local c, fio, a, g, w = F.controller({ io = io })
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 50000 end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  return c, fio, a, g, w
end
do
  local c, io, a = setup()
  local id = F.offer(c, stClair, 'parts')
  T.check(c:takeJob(id), 'job taken')
  T.eq(a.gps[#a.gps].name, 'St Clair', 'GPS to the town until a business is found')
  local want = c:view().load.lookup
  T.check(want ~= nil, 'the HUD is asked to look one up'); T.eq(want.key, stClair.id .. ':parts', 'for the town and good')
  T.near(want.latitude, stClair.latitude, 1e-9, 'around the town'); T.eq(want.good, 'parts', 'the good named')
  T.check(not c:setBusiness('other:parts', enc('Bunnings Warehouse'), 'hardware', spot.latitude, spot.longitude), 'only for this job')
  T.check(not c:setBusiness(want.key, enc('Far Away'), 'hardware', far.latitude, far.longitude), 'not too far from town')
  T.check(c:setBusiness(want.key, enc('Bunnings Warehouse'), 'hardware', spot.latitude, spot.longitude), 'business set')
  T.eq(c:view().load.lookup, nil, 'no more lookups')
  T.eq(a.gps[#a.gps].name, 'Bunnings Warehouse, St Clair', 'GPS moved to the business')
  T.near(a.gps[#a.gps].latitude, spot.latitude, 1e-9, 'at its spot')
  T.eq(io.files[FILE].towns[want.key].name, 'Bunnings Warehouse', 'remembered for next time')
  local v = c:view().load
  T.eq(v.business.name, 'Bunnings Warehouse', 'HUD names it'); T.eq(v.business.kind, 'Hardware store', 'and its kind')
  T.eq(v.business.radiusMetres, 25, '25 m circle'); T.near(v.destination.latitude, spot.latitude, 1e-9, 'coordinates are the business')
  T.check(not v.business.inZone, 'not there yet')

  -- In the middle of town is not enough.
  F.drive(c, a, stClair)
  T.check(not c:deliver(), 'not delivered in the middle of town')
  T.check(c:view().tradeFeedback:find('Bunnings Warehouse', 1, true) and c:view().tradeFeedback:find('25 m', 1, true), 'told where and how close')
  T.check(c:view().town.delivery and not c:view().town.delivery.allowed, 'the Town tab says so too')
  -- 30 m off: still not.
  F.drive(c, a, location.destination(spot, 0, 30))
  T.check(c:view().load.business.near, 'countdown shown'); T.check(not c:view().load.business.inZone, 'outside the circle')
  T.check(not c:deliver(), 'not at 30 m')
  -- 20 m off: delivered.
  F.drive(c, a, location.destination(spot, 0, 20))
  T.check(c:view().load.business.inZone, 'inside the circle'); T.check(c:view().load.business.delivery.allowed, 'delivery allowed')
  local before = c:view().balance
  T.check(c:deliver(), 'delivered at the business')
  T.check(c:view().balance > before, 'paid'); T.check(c:view().flash.text:find('Bunnings Warehouse, St Clair', 1, true), 'the flash names it')
  T.eq(c.load, nil, 'job done')

  -- Next time the same town and good: the business is known straight away, from the file.
  local c2, _, a2 = setup(io)
  local id2 = F.offer(c2, stClair, 'parts')
  T.check(c2:takeJob(id2), 'second job')
  T.eq(c2:view().load.lookup, nil, 'no lookup: remembered')
  T.eq(c2:view().load.business.name, 'Bunnings Warehouse', 'same business')
  T.eq(a2.gps[#a2.gps].name, 'Bunnings Warehouse, St Clair', 'GPS straight to it')
  -- It is saved with the job and comes back.
  T.check(c2:manualSave(), 'saved with the job')
  local r = F.controller({ io = io })
  T.eq(r.load.business.name, 'Bunnings Warehouse', 'business loaded with the job')
end

-- Nothing found: the town's usual drop-off, remembered so it is not asked again.
do
  local c, io, a = setup()
  local id = F.offer(c, stClair, 'bricks')
  T.check(c:takeJob(id), 'job taken')
  local key = c:view().load.lookup.key
  T.check(c:noBusiness(key), 'nothing found')
  T.eq(c:view().load.lookup, nil, 'not asked again'); T.eq(c:view().load.business, nil, 'no business')
  T.eq(io.files[FILE].towns[key].none, true, 'remembered')
  F.drive(c, a, stClair)
  T.check(c:deliver(), 'delivered in town as before')
end

-- Off-road drops never look one up.
do
  local c = setup()
  local drop
  for _, j in ipairs(c:view().town.jobs) do if j.drop and not j.contract then drop = j.id end end
  T.check(c:takeJob(drop), 'drop taken'); T.eq(c:view().load.lookup, nil, 'no lookup for a drop')
  T.check(not c:setBusiness(stClair.id .. ':parts', 'X', 'hardware', spot.latitude, spot.longitude), 'and none taken')
end

-- The game's entry points refuse anything odd before it reaches the controller.
T.eq(Core.setBusiness('a b', 'X', 'hardware', 1, 2), false, 'odd key refused')
T.eq(Core.setBusiness('a:b', 'X', 'casino', 1, 2), false, 'odd kind refused')
T.eq(Core.setBusiness('a:b', 'X', 'hardware', 0 / 0, 2), false, 'odd coordinates refused')
T.eq(Core.noBusiness({}), false, 'odd key refused')

-- Saves: a load's business is checked like the rest.
do
  local base = { good = 'parts', slots = 1, kg = 15, from = 'a', to = 'b', drivenKm = 0, pay = 100 }
  local function with(b) local l = F.copy(base); l.business = b; return l end
  local function check(l)
    local s = F.save(1); s.load = l
    return P.validate(s)
  end
  T.check(check(with({ name = 'Shop', kind = 'garage', latitude = 1, longitude = 2 })), 'a business saves')
  T.check(not check(with({ name = 'Shop', kind = 'garage', latitude = 99, longitude = 2 })), 'a bad spot is refused')
  T.check(not check(with('Shop')), 'only a table')
end

T.done('Real business drop-offs')
