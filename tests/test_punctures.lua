local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local location = require('earthFreight/location')
local punctures = require('earthFreight/punctures')
local pricing = require('earthFreight/pricing')
local places = require('earthFreight/places')
local north = 1 / 111195.0802 -- degrees latitude per metre
T.eq(punctures.AVERAGE_KM, 40, 'about one every 40 km'); T.eq(punctures.GAP_KM, 5, 'none within 5 km of the last')
T.eq(punctures.SAFE_FINISH_METRES, 1000, 'none in the last km before the drop-off'); T.eq(punctures.OFF_ROAD_MULTIPLIER, 2, 'double off road')

-- The chance: one per AVERAGE_KM at the reference speed, more at speed, double off road.
T.near(punctures.chance(1000, 70, false), 1 / 40, 1e-12, '1 in 40 per km at 70 km/h')
T.near(punctures.chance(1000, 140, false), 2 / 40, 1e-12, 'twice as likely at 140 km/h')
T.near(punctures.chance(1000, 70, true), 2 / 40, 1e-12, 'twice as likely off road')
T.near(punctures.chance(1000, 1000, true), 2.5 * 2 / 40, 1e-12, 'speed factor capped')
T.near(punctures.chance(1000, 1, false), 0.25 / 40, 1e-12, 'crawling still has a small chance')
T.eq(punctures.chance(0, 70, false), 0, 'no distance, no chance')
-- Over a 15 km run on road at 70 km/h, about a 1 in 3 chance.
T.near(1 - math.exp(-15 * punctures.chance(1000, 70, false)), 0.31, 0.01, 'about 1 in 3 over 15 km on road')

-- Game side: the burst runs the car's own deflate call; off road is read from the road map.
do
  local commands = {}
  local car = { queueLuaCommand = function(_, command) commands[#commands + 1] = command end,
    getPosition = function() return { x = 1, y = 2, z = 3 } end }
  local road = { distance = 30 }
  local roads = { findClosestRoad = function() return 'n1', 'n2', road.distance end,
    getMap = function() return { nodes = { n1 = { radius = 4 } } } end }
  local p = punctures.new({ player = function() return car end, map = function() return roads end })
  T.check(p:burst(), 'burst sent'); T.check(commands[1]:find('beamstate.deflateRandomTire()', 1, true), 'deflates a random tyre')
  T.check(load(commands[1]) ~= nil, 'the command is valid Lua')
  T.eq(p:offRoad(), true, '30 m from a 4 m road is off road')
  road.distance = 12; T.eq(p:offRoad(), false, 'within 10 m of the road edge is on road')
  roads.findClosestRoad = function() return nil end; T.eq(p:offRoad(), nil, 'no road map, unknown')
  T.eq(punctures.new({ player = function() return car end, map = function() return nil end }):offRoad(), nil, 'no map module, unknown')
  T.eq(select(2, punctures.new({ player = function() return nil end, map = function() return roads end }):burst()), 'vehicle_required', 'needs a car')
  car.queueLuaCommand = function() error('boom') end
  T.eq(select(2, p:burst()), 'burst_failed', 'errors contained')
end

-- On the road: a burst adds the tyre repair to the repair quote; none within GAP_KM of the last,
-- and none in the last km before the drop-off.
local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
do
  local p = F.punctures()
  local c, _, a, g = F.controller({ punctures = p, random = function() return 0 end })
  c:tick(0.1)
  local start = F.copy(a.pose)
  a.pose = location.destination(start, 180, 100); c:tick(1)
  T.eq(p.bursts, 1, 'a burst on the road'); T.eq(c:view().flash.kind, 'puncture', 'puncture shown')
  for step = 2, 20 do a.pose = location.destination(start, 180, step * 100); c:tick(1) end
  T.eq(p.bursts, 1, 'none within the gap')
  T.check(c:view().puncture.tyreCost > 0, 'tyre repair owed')
  c:requestRepairQuote()
  T.eq(c:view().repairQuote, pricing.repairCost(punctures.TYRE_REPAIR_COST / 0.5, g.carValues.pickup), 'quote includes the tyre')
  -- With a load on, none in the last km before its drop-off.
  local q = F.punctures()
  local d, _, b = F.controller({ punctures = q, random = function() return 0 end })
  d:tick(0.1); d:tick(0.6); d:tick(0.6)
  local stClair = placeNamed('St Clair')
  T.check(d:takeJob(F.offer(d, stClair, 'food')), 'loaded')
  -- Short hops (under 2 km each) keep the load, so it can be carried close without driving.
  local away = location.distance(b.pose, stClair)
  while away > 2400 do b.pose = location.destination(b.pose, location.bearing(b.pose, stClair), 1500); d:tick(0.1); away = location.distance(b.pose, stClair) end
  local side = location.bearing(stClair, b.pose)
  b.pose = location.destination(stClair, side, 900); d:tick(0.1)
  T.check(d.load ~= nil, 'still loaded')
  local driven = d.profile.progression.totalDistanceKm
  for step = 1, 5 do b.pose = location.destination(stClair, side, 900 - step * 100); d:tick(1) end
  T.near(d.profile.progression.totalDistanceKm - driven, 0.5, 1e-6, 'driven, not hopped')
  T.eq(q.bursts, 0, 'none within a km of the drop-off')
end
T.done('punctures')
