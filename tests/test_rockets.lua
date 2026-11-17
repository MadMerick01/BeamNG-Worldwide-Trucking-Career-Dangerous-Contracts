local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local places = require('earthFreight/places')
local rockets = require('earthFreight/rockets')
local garageModule = require('earthFreight/garage')

local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
local stClair = placeNamed('St Clair')

-- Which parts are rockets: anything called jato, or fitted in a jato slot. Empty slots hold nothing.
T.check(rockets.isRocket('jato'), 'the game\'s own'); T.check(rockets.isRocket('pickup_JATO_rack'), 'any case, any car')
T.check(rockets.isRocket('booster', '/jato/'), 'in a jato slot')
T.check(not rockets.isRocket('', '/jato/'), 'an empty jato slot is fine')
T.check(not rockets.isRocket('pickup_engine_v8', '/engine/'), 'an engine is not a rocket')
T.check(rockets.inParts({ engine = 'pickup_engine_v8', jato = 'jato' }), 'found in a parts list')
T.check(not rockets.inParts({ engine = 'pickup_engine_v8', jato = '' }), 'none fitted')
local tree = { path = '/', chosenPartName = 'pickup', children = {
  engine = { path = '/engine/', chosenPartName = 'pickup_engine_v8' },
  jato = { path = '/jato/', chosenPartName = '' } } }
T.check(not rockets.inTree(tree), 'a tree with an empty rocket slot')
tree.children.jato.chosenPartName = 'jato'
T.check(rockets.inTree(tree), 'a tree with rockets fitted')

-- The real garage reads the car's partsTree.
do
  local data = { config = { partsTree = tree } }
  local g = garageModule.new({
    vehicle = function() return { getID = function() return 7 end } end,
    manager = function() return { getVehicleData = function(id) return id == 7 and data or nil end } end,
  })
  T.eq(g:rockets(), true, 'rockets on the player car'); T.eq(g:rockets(8), nil, 'another car unreadable')
  tree.children.jato.chosenPartName = ''
  T.eq(g:rockets(), false, 'and taken off')
end

-- A started controller in Penrith with a box on the car, online.
local function online()
  local c, io, a, g = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 50000 end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.rocketsBanned = function() return true end
  return c, io, a, g
end

-- Single player: rockets change nothing.
do
  local c, _, a, g = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 50000 end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  g.fitted.jato = 'jato'
  c:tick(3)
  T.eq(c:view().rockets, nil, 'no warning in single player')
  local before = c:view().balance
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'jobs as usual')
  F.drive(c, a, stClair)
  T.check(c:deliver(), 'delivered'); T.check(c:view().balance > before, 'and paid')
end

-- Online with rockets fitted: no job can be taken, and the HUD says why.
do
  local c, _, _, g = online()
  g.fitted.jato = 'jato'
  c:tick(3)
  T.eq(c:view().rockets, true, 'the HUD warns')
  local id = F.offer(c, stClair, 'food')
  T.check(not c:takeJob(id), 'no job with rockets'); T.eq(c.tradeFeedback, rockets.TAKE_PROBLEM, 'says why')
  g.fitted.jato = ''
  c:tick(3)
  T.eq(c:view().rockets, nil, 'taken off, the warning goes')
  T.check(c:takeJob(id), 'and jobs can be taken again')
end

-- Rockets fitted on a job, even if taken off before the drop-off: the job pays nothing.
do
  local c, io, a, g = online()
  local before = c:view().balance
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'job taken')
  g.fitted.jato = 'jato'
  c:tick(3)
  T.eq(c.load.rockets, true, 'the job is marked')
  T.eq(c:view().flash.title, 'NO PAY FOR THIS JOB', 'and the player told at once')
  T.eq(c:view().load.pay, 0, 'the HUD shows no pay'); T.eq(c:view().load.rockets, true, 'and why')
  g.fitted.jato = ''
  c:tick(3)
  T.check(c:manualSave(), 'saved')
  local r = F.controller({ io = io })
  r:tick(0.1); r:tick(0.6); r:tick(0.6)
  T.eq(r.load and r.load.rockets, true, 'the mark is kept in the save')
  F.drive(c, a, stClair)
  T.check(c:deliver(), 'still delivered')
  T.eq(c:view().balance, before, 'for nothing')
  T.check(c:view().flash.text:find(rockets.PAID_NOTHING, 1, true) ~= nil, 'the delivery says why')
end

-- Rockets on the hitched trailer count too.
do
  local c, _, _, g = online()
  g.trailers = g.trailers or {}
  g.trailers[600] = { model = 'flatbed', fitted = { jato = 'jato' }, damage = 0 }
  c.trailerOut = { id = 600, at = 0, spawned = true, hitched = true, damage = 0 }
  c:tick(3)
  T.eq(c:view().rockets, true, 'seen on the trailer')
  c.trailerOut.hitched = false
  c:tick(3)
  T.eq(c:view().rockets, nil, 'not once unhitched')
end

-- A Mayday Rescue run ends when rockets are seen.
do
  local c, _, _, g = online()
  c.maydayRun = { round = 1, edge = 'north' }
  g.fitted.jato = 'jato'
  c:tick(3)
  T.eq(c.maydayRun, nil, 'the run is over')
  T.check(c.maydayFeedback:find('JATO', 1, true) ~= nil, 'and says why')
end

T.done('rockets')
