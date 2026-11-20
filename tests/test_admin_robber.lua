local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local MPC = require('earthFreight/multiplayer')
local admin = require('earthFreight/adminRobber')
local emp = require('earthFreight/emp')
local flights = require('earthFreight/flights')
local location = require('earthFreight/location')
local places = require('earthFreight/places')

-- A server link that keeps what the game sends: { event, body } each.
local function server()
  -- Messages are kept as they are: encode hands back a name for each, which send looks up.
  local sent, kept = {}, {}
  local s = MPC.new({ send = function(event, text) sent[#sent + 1] = { event = event, body = kept[text] or text } end,
    encode = function(t) kept[#kept + 1] = t; return '#' .. #kept end, decode = function(t) return t end, io = F.io() })
  setmetatable(kept, { __index = function(_, k) return type(k) == 'string' and k:match('^#%d+$') and rawget(kept, tonumber(k:sub(2))) or nil end })
  s.state = 'server'
  function s.last(event)
    for i = #sent, 1, -1 do if sent[i].event == event then return sent[i].body end end
  end
  return s, sent
end

-- A stand-in for the cars: the admin's car is metres from the player, set by the test.
local function fakeCar()
  local f = { loaded = 0, removed = {}, hit = {}, playerHits = 0, playerBack = 0, metres = 300, ground = true, faced = {}, shut = 0 }
  function f:preload() self.loaded = self.loaded + 1; return 70 + self.loaded end
  function f:place() return true end
  function f:lurk() return true end
  function f:hunt() return true end
  function f:setSpeed() return true end
  function f:playerKph() return 80 end
  function f:headingGap() return 0 end
  function f:empPlayer() self.playerHits = self.playerHits + 1; return true end
  function f:empPlayerEnd() self.playerBack = self.playerBack + 1; return true end
  function f:flee() return true end
  function f:distance(id) if self.removed[id] then return nil end; return self.metres end
  function f:bearing() return 10 end
  function f:emp(id) self.hit[#self.hit + 1] = id; return true end
  function f:remove(id) self.removed[id] = true; return true end
  function f:update() end
  function f:aheadOffset(metres)
    if not self.ground then return nil, 'no_ground' end
    return { east = 0, north = metres, heading = 0 }
  end
  function f:face(heading) self.faced[#self.faced + 1] = heading; return true end
  function f:shutDownPlayer() self.shut = self.shut + 1; return true end
  return f
end

local function townBetween(c, minKm, maxKm)
  local here = c:here()
  for _, p in ipairs(places.list) do
    local d = location.distance(here, p)
    if d and d > minKm * 1000 and d < maxKm * 1000 and p.id ~= here.id then return p end
  end
end

-- ===== The multiplayer messages ======================================================================================
do
  local list = MPC.cleanTargets({ { id = 3, name = 'Sam\nX', town = 'Perth', doing = 'Carrying food' }, { id = -1 }, { id = 1.5 }, 'x' })
  T.eq(#list, 1, 'only good rows'); T.eq(list[1].name, 'Sam X', 'names are one line'); T.eq(list[1].town, 'Perth', 'with the town')
  local s, sent = server()
  T.check(s:receive('wwtcAdmin', { targets = { { id = 3, name = 'Sam' } } }), 'the admin list is taken')
  T.eq(s.admin.targets[1].name, 'Sam', 'and kept')
  T.check(s:receive('wwtcAdminSpot', { to = 3, ok = true }), 'the drop-in spot is taken'); T.eq(s.adminSpot.to, 3, 'kept')
  T.check(s:receive('wwtcAdminState', { state = 'struck' }), 'how it went is taken'); T.eq(s.adminState.state, 'struck', 'kept')
  T.check(s:receive('wwtcRob', { state = 'go', car = '2-0' }), 'the robbery is taken'); T.eq(s.rob.car, '2-0', 'kept')
  T.check(s:receive('wwtcRobAsk', { ask = 7 }), 'the question is taken'); T.eq(s.robAsk.ask, 7, 'kept')
  T.check(not s:receive('wwtcRobAsk', { ask = 'x' }), 'a bad question is not')
  s:adminRob('start', { to = 3 })
  T.eq(sent[#sent].event, 'wwtcAdminRob', 'Rob goes to the server'); T.eq(sent[#sent].body['do'], 'start', 'as start'); T.eq(sent[#sent].body.to, 3, 'with who')
  s:robNews('struck'); T.eq(s.last('wwtcRobNews').what, 'struck', 'the player\'s game says how it went')
end

-- ===== The robbed player's side ======================================================================================

-- The player on a long job, on a server.
local function target()
  local car = fakeCar()
  local c, io, a = F.controller({ random = function() return 0.99 end })
  c.thiefCar = car
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 100000
  local s, sent = server()
  c.mp = s
  c.mpGame = { gameCarId = function(id) return id == '2-0' and 500 or nil end }
  local to = townBetween(c, 20, 60)
  T.check(c:takeJob(F.offer(c, to, 'food')), 'a long job')
  c:tick(0.1)
  return c, a, car, s, sent
end

-- Rob, struck, caught, revealed.
do
  local c, a, car, s = target()
  T.eq(c:adminRobProblem(), nil, 'on a long job with robbers allowed, an admin can rob them')
  c.whereSent = nil; c:reportWhere(c.lastSample)
  T.eq(s.last('wwtcWhere').robbable, true, 'the server is told')
  c:answerRobAsk({ ask = 4 })
  local spot = s.last('wwtcRobSpot')
  T.eq(spot.ask, 4, 'the answer'); T.eq(spot.ok, true, 'yes')
  T.near(location.distance(c.lastSample, spot), admin.AHEAD_METRES, 2, 'the road spot 300 m ahead')
  T.near(location.bearing(c.lastSample, spot), 0, 1, 'the way the road goes'); T.eq(spot.heading, 0, 'facing the player\'s way')
  c:robNews({ state = 'go', car = '2-0' })
  T.check(c.robber and c.robber.admin, 'the admin robber is on'); T.eq(c.robber.phase, 'lurking', 'lurking')
  T.eq(c:adminRobProblem(), 'busy', 'nobody else can rob them meanwhile')
  T.check(not c:fireEmp(), 'the player can\'t EMP it before it strikes')
  local before = c.profile.progression.balance
  car.metres = 5; F.advance(c, 2)
  T.eq(c.robber.phase, 'lurking', 'close by, nothing happens until he fires: he has full control')
  car.metres = 40
  c:robNews({ state = 'emp' })
  T.eq(c.robber.phase, 'lurking', 'his EMP from 40 m misses'); T.eq(s.last('wwtcRobNews').what, 'missed', 'he is told')
  T.eq(s.last('wwtcRobNews').metres, 40, 'with how far off'); T.eq(c.profile.progression.balance, before, 'nothing taken')
  car.metres = 10
  c:robNews({ state = 'emp' })
  T.eq(c.robber.phase, 'chasing', 'within 15 m his EMP strikes')
  T.eq(c.profile.progression.balance, before - admin.STOLEN, '$1,000 taken'); T.eq(car.playerHits, 1, 'the engine cut')
  T.eq(s.last('wwtcRobNews').what, 'struck', 'the server is told')
  T.eq(c:view().thief.road, true, 'the chase card'); T.eq(c:view().thief.distanceMetres, 10, 'with how far')
  F.advance(c, emp.CHARGE_SECONDS + 0.2)
  T.eq(car.playerBack, 1, 'the engine back after 5 s')
  T.check(c:fireEmp(), 'the EMP within range catches them')
  T.eq(c.profile.progression.balance, before + admin.TRUNK, 'the $1,000 back plus $20,000')
  T.eq(#car.hit, 0, 'the admin\'s car is not touched here: his own game shuts it down')
  T.eq(s.last('wwtcRobNews').what, 'caught', 'the server is told')
  c:robNews({ state = 'caught', name = 'MadMerick' })
  T.eq(c:view().flash.title, 'YOU CAUGHT MADMERICK!', 'his name is shown')
  F.advance(c, admin.CAUGHT_SECONDS + 0.5)
  T.eq(c.robber, nil, 'over after 10 s'); T.eq(next(car.removed), nil, 'his car is never taken away')
end

-- Escaped: 450 m clear, the money is gone.
do
  local c, a, car, s = target()
  c:robNews({ state = 'go', car = '2-0' })
  local before = c.profile.progression.balance
  car.metres = 5; c:robNews({ state = 'emp' })
  car.metres = 460; c:tick(0.1)
  T.eq(c.robber, nil, 'escaped'); T.eq(s.last('wwtcRobNews').what, 'escaped', 'the server is told')
  T.eq(c.profile.progression.balance, before - admin.STOLEN, 'the money is gone')
  T.eq(c:view().flash.title, 'THE ROBBER GOT AWAY', 'told so')
end

-- Not struck in 10 minutes: it gives up and nothing is lost; no distance limit before that.
do
  local c, a, car, s = target()
  c:robNews({ state = 'go', car = '2-0' })
  car.metres = 5000
  F.advance(c, 300)
  T.eq(c.robber.phase, 'lurking', 'far behind is no reason to give up')
  F.advance(c, admin.STRIKE_SECONDS - 300 + 1)
  T.eq(c.robber, nil, 'after 10 minutes it gives up'); T.eq(s.last('wwtcRobNews').what, 'gave_up', 'the server is told')
end

-- The admin's car never turns up in this game: it gives up after a minute.
do
  local c, a, car, s = target()
  c:robNews({ state = 'go', car = '9-0' })
  F.advance(c, admin.CAR_WAIT_SECONDS + 1)
  T.eq(c.robber, nil, 'no car, no robbery'); T.eq(s.last('wwtcRobNews').what, 'gave_up', 'the server is told')
end

-- The admin stops: before the strike quietly, after it the money is gone.
do
  local c, a, car = target()
  c:robNews({ state = 'go', car = '2-0' })
  c:robNews({ state = 'off' })
  T.eq(c.robber, nil, 'gone')
  c:robNews({ state = 'go', car = '2-0' })
  car.metres = 5; c:robNews({ state = 'emp' })
  c:robNews({ state = 'off' })
  T.eq(c.robber, nil, 'gone'); T.eq(c:view().flash.title, 'THE ROBBER GOT AWAY', 'with the money')
end

-- Who can't be robbed: robbers unticked, too little money, a short job; asked anyway, the game says no.
do
  local c, a, car, s = target()
  c:setRobbersAllowed(false)
  T.eq(c:adminRobProblem(), 'off', 'robbers unticked')
  c:answerRobAsk({ ask = 1 })
  T.eq(s.last('wwtcRobSpot').ok, false, 'asked anyway, no'); T.eq(s.last('wwtcRobSpot').why, 'off', 'and why')
  c:robNews({ state = 'go', car = '2-0' })
  T.eq(c.robber, nil, 'a go is refused too'); T.eq(s.last('wwtcRobNews').what, 'gone', 'and the server told')
  c:setRobbersAllowed(true)
  c.profile.progression.balance = 500
  T.eq(c:adminRobProblem(), 'off', 'less than $1,000')
  c.profile.progression.balance = 100000
  car.ground = false
  c:answerRobAsk({ ask = 2 })
  T.eq(s.last('wwtcRobSpot').why, 'no_ground', 'no loaded road ahead yet')
  c.load = nil
  T.eq(c:adminRobProblem(), 'off', 'not on a job')
end

-- An AI robber waiting for this job goes while the admin robs, and comes back after.
do
  local c, a, car = target()
  c:loadRobber(false)
  c.robberAtKm = 3
  T.eq(c.robber.phase, 'loaded', 'the AI robber is waiting')
  c:robNews({ state = 'go', car = '2-0' })
  T.check(c.robber.admin, 'the admin takes its place')
  c:robNews({ state = 'off' })
  F.advance(c, 11)
  T.check(c.robber and not c.robber.admin and c.robber.phase == 'loaded', 'the job\'s own robber is loaded again')
end

-- ===== The admin's side ==============================================================================================

-- The admin in his pickup in Penrith, with the list from the server.
local function adminGame()
  local car = fakeCar()
  local c, io, a, g = F.controller({ aircraft = F.aircraft() })
  g.configParts[flights.SIGHTSEEING.config] = { body = 'moonhawk_body' }
  local tick = c.tick
  c.tick = function(self, dt)
    a.vehicle = { id = g.vehicleId, model = g.model }
    return tick(self, dt)
  end
  c.thiefCar = car
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 5000
  c:fuelReading(1, 30, 50)
  local s, sent = server()
  c.mp = s
  c.mpGame = { serverCarId = function(id) return '2-' .. tostring(id) end }
  return c, a, g, car, s, sent
end

do
  local c = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.eq(c:view().admin, nil, 'not an admin: nothing shown')
end

do
  local c, a, g, car, s = adminGame()
  T.eq(c:view().admin, nil, 'nothing until the server sends the list')
  s:receive('wwtcAdmin', { targets = { { id = 3, name = 'Sam', town = 'Parramatta', doing = 'Carrying food to Lithgow' } } })
  local v = c:view().admin
  T.check(v ~= nil, 'the admin sees the list'); T.eq(v.targets[1].name, 'Sam', 'with Sam'); T.check(v.targets[1].allowed, 'who can be robbed')
  T.check(not c:adminRob(9), 'not someone off the list')
  T.check(c:adminRob(3), 'Rob'); T.eq(s.last('wwtcAdminRob')['do'], 'start', 'the server is asked'); T.eq(s.last('wwtcAdminRob').to, 3, 'about Sam')
  T.eq(c:view().admin.drive.stage, 'asking', 'asking')
  local drop = location.destination(F.PENRITH, 90, 50000)
  c:multiplayerEvent('wwtcAdminSpot', { to = 3, ok = true, latitude = drop.latitude, longitude = drop.longitude, heading = 90 })
  T.check(c.hire and c.hire.admin, 'the robber\'s car takes his car\'s place'); T.eq(g.model, 'moonhawk', 'the Moonhawk')
  T.eq(c.adminDrive.stage, 'leaving', 'leaving')
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c.adminDrive.stage, 'going', 'teleporting'); T.eq(a.teleports[#a.teleports].latitude, drop.latitude, 'to the spot ahead of Sam')
  T.check(c:view().flash == nil or c:view().flash.title ~= 'SIGHTSEEING', 'not told it is sightseeing')
  a.pose = F.copy(drop); c:tick(0.1)
  local km = c.profile.progression.totalDistanceKm
  F.advance(c, admin.SETTLE_SECONDS + 0.5)
  T.eq(c.adminDrive.stage, 'ready', 'in place once the car has settled'); T.eq(car.faced[1], 90, 'turned to face Sam\'s way')
  T.eq(s.last('wwtcAdminRob')['do'], 'ready', 'the server is told'); T.eq(s.last('wwtcAdminRob').car, '2-' .. tostring(g.vehicleId), 'with his car')
  T.eq(c.stranded, nil, 'not a teleport for the career'); T.eq(c.profile.progression.totalDistanceKm, km, 'no distance counted')
  T.check(c:view().admin.drive.secondsLeft > 590, '10 minutes to strike')
  T.check(c:view().admin.drive.emp.ready, 'his EMP is ready')
  T.check(c:adminEmp(), 'he fires it'); T.eq(s.last('wwtcAdminRob')['do'], 'emp', 'the server is told')
  T.eq(c:view().admin.drive.emp.ready, false, 'then it charges'); T.check(not c:adminEmp(), 'not again while it charges')
  T.check(c:view().admin.feedback:find('charging', 1, true) ~= nil, 'and says so')
  c:multiplayerEvent('wwtcAdminState', { state = 'missed', metres = 42 })
  T.check(c:view().admin.feedback:find('42 m away', 1, true) ~= nil, 'a miss says how far off he was')
  F.advance(c, emp.CHARGE_SECONDS + 0.2)
  T.check(c:empHotkey(), 'the Fire EMP key fires it too'); T.eq(s.last('wwtcAdminRob')['do'], 'emp', 'the server is told')
  c:multiplayerEvent('wwtcAdminState', { state = 'struck' })
  T.eq(c:view().flash.title, 'YOU ROBBED SAM', 'told'); T.eq(c.profile.progression.balance, 5000, 'he gets nothing')
  c:multiplayerEvent('wwtcAdminState', { state = 'caught' })
  T.eq(c.adminDrive.stage, 'caught', 'caught'); T.check(car.shut >= 1, 'his car is shut down')
  T.check(not c:view().admin.drive.stopAllowed, 'no stopping now')
  F.advance(c, admin.CAUGHT_SECONDS + 0.5)
  T.check(car.shut >= 5, 'kept shut down'); T.eq(c.adminDrive.stage, 'back', 'then back to his car')
  T.eq(a.teleports[#a.teleports].latitude, F.PENRITH.latitude, 'teleported back to where it is')
  a.pose = F.copy(F.PENRITH)
  F.advance(c, 5)
  T.eq(g.model, 'pickup', 'his pickup is back'); T.eq(c.hire, nil, 'out of the robber\'s car'); T.eq(c.adminDrive, nil, 'over')
  T.eq(c.profile.progression.balance, 5000, 'for free')
end

-- Stop, and Return to your job, call it off; a no from the player's game says why.
do
  local c, a, g, car, s = adminGame()
  s:receive('wwtcAdmin', { targets = { { id = 3, name = 'Sam' } } })
  c:adminRob(3)
  c:multiplayerEvent('wwtcAdminSpot', { to = 3, ok = false, why = 'no_ground' })
  T.eq(c.adminDrive, nil, 'no robbery'); T.check(c:view().admin.feedback:find('loaded ground', 1, true) ~= nil, 'says why')
  T.eq(c.hire, nil, 'still in his car')
  c:adminRob(3)
  local drop = location.destination(F.PENRITH, 90, 50000)
  c:multiplayerEvent('wwtcAdminSpot', { to = 3, ok = true, latitude = drop.latitude, longitude = drop.longitude })
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.check(c:returnToJob(), 'Return to your job calls it off'); T.eq(s.last('wwtcAdminRob')['do'], 'stop', 'the server is told')
  T.eq(c.adminDrive.stage, 'back', 'going back')
  a.pose = F.copy(F.PENRITH); F.advance(c, 5)
  T.eq(c.adminDrive, nil, 'over'); T.eq(g.model, 'pickup', 'back in his pickup')
  -- The player's game never answers.
  c:adminRob(3); F.advance(c, admin.ASK_SECONDS + 1)
  T.eq(c.adminDrive, nil, 'given up'); T.check(c:view().admin.feedback:find('did not answer', 1, true) ~= nil, 'says so')
end

T.done('admin robber')
