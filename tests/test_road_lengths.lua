local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local Core = require('earthFreight/core')
local places = require('earthFreight/places')
local location = require('earthFreight/location')
local roads = require('earthFreight/roadLengths')
local P = require('earthFreight/persistence')

local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
local stClair = placeNamed('St Clair')

local function boardJob(c, id)
  for _, j in ipairs(c:view().town.jobs) do if j.id == id then return j end end
end

-- The pure rules: pairs both ways, odd routes refused, pay never below the estimate.
do
  T.eq(roads.key('b', 'a'), roads.key('a', 'b'), 'a pair is the same both ways')
  T.eq(roads.key('a', 'a'), nil, 'a town to itself is no pair')
  T.eq(roads.accept(20000, 6000), 20, 'a winding road is believed')
  T.eq(roads.accept(5000, 6000), nil, 'shorter than the straight line is not a road')
  T.eq(roads.accept(30000, 6000), nil, 'five times the straight line is a ferry or a wrong route')
  T.eq(roads.accept(200, 100), nil, 'already at the town')
  T.eq(roads.accept(0 / 0, 6000), nil, 'not a number')
  T.eq(roads.payKm(7.8, 20), 20, 'paid by the longer road')
  T.eq(roads.payKm(7.8, 6.5), 7.8, 'never by less than the estimate')
  local list = {}
  T.check(roads.remember(list, 'x', 'y', 12.345, 5), 'remembered')
  T.eq(roads.lookup(list, 'y', 'x'), 12.35, 'and found the other way')
  local clean = roads.clean({ pairs = { ['a>b'] = { km = 3, at = 1 }, bad = { km = 2 }, ['c>d'] = { km = -1 }, ['e>f'] = 'x' } })
  T.eq(roads.lookup(clean, 'a', 'b'), 3, 'a saved pair is kept')
  T.eq(clean.bad, nil, 'odd entries are dropped'); T.eq(clean['c>d'], nil, 'and odd lengths')
  local old = roads.MAX_PAIRS
  roads.MAX_PAIRS = 2
  local few = {}
  roads.remember(few, 'a', 'b', 1, 1); roads.remember(few, 'c', 'd', 1, 2); roads.remember(few, 'e', 'f', 1, 3)
  T.eq(roads.lookup(few, 'a', 'b'), nil, 'the oldest goes first'); T.eq(roads.lookup(few, 'e', 'f'), 1, 'the newest stays')
  roads.MAX_PAIRS = old
end

-- The job's GPS button measures the road: the board then shows the real km and pays for it, and the
-- road is remembered in its file.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local id = F.offer(c, stClair, 'food')
  local before = boardJob(c, id)
  T.check(not before.byRoad and not before.measuring, 'an estimate at first')
  local straight = location.distance(a.pose, stClair)
  T.check(c:gpsToTown(stClair.id), 'GPS set from the job')
  c:tick(0.5)
  T.check(boardJob(c, id).measuring, 'measuring while Earth plans the route')
  a.routeMetres = straight * 3
  c:tick(1.1)
  local after = boardJob(c, id)
  T.check(after.byRoad and not after.measuring, 'measured')
  T.near(after.distanceMetres, straight * 3, 10, 'the board shows the road')
  T.check(after.pay > before.pay, 'and pays more for it')
  T.near(io.files[Core.ROADS_FILE].pairs[roads.key(after.from or c:here().id, stClair.id)].km, straight * 3 / 1000, 0.01, 'remembered in its file')
  -- Taken now, the job is paid what the board showed, and needs no measuring.
  T.check(c:takeJob(id), 'job taken')
  T.eq(c.load.pay, after.pay, 'paid the measured price')
  T.near(c.load.roadKm, straight * 3 / 1000, 0.01, 'by the road'); T.eq(c.load.estimateKm, nil, 'nothing left to measure')
  T.eq(c.roadMeasure, nil, 'and the GPS is not measuring')
  -- A new game on this PC reads the remembered road.
  local c2 = F.controller({ io = io })
  c2:tick(0.1); c2:tick(0.6); c2:tick(0.6)
  T.near(c2:jobRoadKm({ from = c:here().id, to = stClair.id, km = 1 }), straight * 3 / 1000, 0.01, 'read back from the file')
end

-- A road measured shorter than the estimate shows the real km but keeps the estimate's pay.
do
  local c, _, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local id = F.offer(c, stClair, 'food')
  local before = boardJob(c, id)
  c:gpsToTown(stClair.id)
  a.routeMetres = location.distance(a.pose, stClair) * 1.0
  c:tick(1.1)
  local after = boardJob(c, id)
  T.check(after.byRoad, 'measured'); T.check(after.distanceMetres < before.distanceMetres, 'shorter than the estimate')
  T.eq(after.pay, before.pay, 'pay never goes down')
end

-- A job taken without measuring is measured once the GPS plans it, and its pay goes up.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local id = F.offer(c, stClair, 'food')
  local quoted = boardJob(c, id).pay
  T.check(c:takeJob(id), 'job taken')
  T.eq(c.load.pay, quoted, 'at the board price'); T.check(c.load.estimateKm ~= nil, 'still to be measured')
  T.check(c.roadMeasure ~= nil, 'the GPS to the drop-off measures it')
  c:tick(1.1)
  T.eq(c.load.pay, quoted, 'nothing while Earth plans')
  a.routeMetres = location.distance(a.pose, stClair) * 2.5
  c:tick(1.1)
  T.check(c.load.pay > quoted, 'paid more for the longer road')
  T.eq(c.load.pay % 10, 0, 'in tens of dollars')
  T.check(c.load.roadKm ~= nil and c.load.estimateKm == nil, 'measured')
  T.check(c:view().tradeFeedback:find('went up') ~= nil, 'and says so')
  -- The measured job survives a save.
  T.check(c:manualSave(), 'saved')
  local doc
  for _, name in ipairs({ 'save-a.json', 'save-b.json' }) do
    local f = io.files[P.DIRECTORY .. name]
    if f and (not doc or f.generation > doc.generation) then doc = f end
  end
  local v = P.validate(F.copy(doc))
  T.near(v.load.roadKm, c.load.roadKm, 1e-9, 'its road km is saved'); T.eq(v.load.estimateKm, nil, 'and nothing left to measure')
  doc.load.roadKm, doc.load.estimateKm = nil, 7.5
  T.eq(P.validate(F.copy(doc)).load.estimateKm, 7.5, 'an unmeasured job keeps its estimate')
end

-- An odd route, a GPS sent elsewhere, an error or no route in time: the job keeps its board price.
do
  local c, _, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local id = F.offer(c, stClair, 'food')
  local quoted = boardJob(c, id).pay
  c:takeJob(id)
  a.routeMetres = location.distance(a.pose, stClair) * 6
  c:tick(1.1)
  T.eq(c.load.pay, quoted, 'a ferry route is not believed'); T.eq(c.roadMeasure, nil, 'and measuring stops')
  T.eq(c:jobRoadKm({ from = c.load.from, to = stClair.id, km = 1 }), nil, 'nor remembered')
  -- No route in time.
  a.routeMetres = nil
  c:gpsToJob()
  T.check(c.roadMeasure ~= nil, 'measuring again')
  F.advance(c, 62)
  T.eq(c.roadMeasure, nil, 'given up after a minute'); T.eq(c.load.pay, quoted, 'board price kept')
  -- An Earth whose GPS call breaks.
  c:gpsToJob(); a.routeError = 'changed'
  c:tick(1.1)
  T.eq(c.roadMeasure, nil, 'an error stops it'); a.routeError = nil
  -- The GPS sent somewhere else.
  c:gpsToJob(); a:setDestination({ latitude = 0, longitude = 0 }, 'elsewhere')
  a.routeMetres = location.distance(a.pose, stClair) * 2
  c:tick(1.1)
  T.eq(c.roadMeasure, nil, 'another destination stops it'); T.eq(c.load.pay, quoted, 'board price kept')
end

-- An Earth that cannot say how long a route is: nothing is measured and jobs pay as before.
do
  local a = F.adapter(); a.gpsRouteLength = nil
  local c = F.controller({ adapter = a })
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local id = F.offer(c, stClair, 'food')
  local quoted = boardJob(c, id).pay
  T.check(c:gpsToTown(stClair.id), 'GPS still set'); T.eq(c.roadMeasure, nil, 'nothing measured')
  T.check(c:takeJob(id), 'job taken'); T.eq(c.load.pay, quoted, 'at the board price')
end

T.done('Road lengths')
