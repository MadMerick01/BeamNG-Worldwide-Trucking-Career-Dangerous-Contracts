local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local robber = require('earthFreight/roadRobber')
local emp = require('earthFreight/emp')
local thief = require('earthFreight/thief')
local thiefCar = require('earthFreight/thiefCar')
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local persistence = require('earthFreight/persistence')

-- A stand-in for the robber's car: where it is, as metres from the player, set by the test.
local function fakeCar()
  local f = { loaded = 0, placed = 0, removed = {}, fled = {}, hit = {}, lurks = {}, hunts = {}, speeds = {},
    playerHits = 0, playerBack = 0, metres = 300, ground = true, kph = 80, gap = 0, refuse = false }
  function f:preload() if self.refuse then return nil, 'spawn_failed' end; self.loaded = self.loaded + 1; return 70 + self.loaded end
  function f:place(id) if self.removed[id] then return false, 'gone' end; if not self.ground then return false, 'no_ground' end; self.placed = self.placed + 1; return true end
  function f:lurk(id, kph) self.lurks[#self.lurks + 1] = kph; return true end
  function f:hunt(id, kph) self.hunts[#self.hunts + 1] = kph; return true end
  function f:setSpeed(id, kph) self.speeds[#self.speeds + 1] = kph; return true end
  function f:playerKph() return self.kph end
  function f:headingGap() return self.gap end
  function f:empPlayer() self.playerHits = self.playerHits + 1; return true end
  function f:empPlayerEnd() self.playerBack = self.playerBack + 1; return true end
  function f:empPlayerBrakeOff() self.brakesOff = (self.brakesOff or 0) + 1; return true end
  function f:speed() return self.v end
  function f:unstick() self.unstuck = (self.unstuck or 0) + 1; return true end
  function f:flee(id) self.fled[#self.fled + 1] = id; return true end
  function f:distance(id) if self.removed[id] then return nil end; return self.metres end
  function f:bearing() return 10 end
  function f:emp(id) self.hit[#self.hit + 1] = id; return true end
  function f:remove(id) self.removed[id] = true; return true end
  function f:update() end
  return f
end

local function ready(roll)
  local car = fakeCar()
  local c, io, a = F.controller({ random = function() return 0.99 end })
  c.thiefCar = car
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 2000000
  c.random = function() return roll or 0.99 end
  return c, a, car
end

-- A town between min and max km from the start, for a job there.
local function townBetween(c, minKm, maxKm)
  local here = c:here()
  for _, p in ipairs(places.list) do
    local d = location.distance(here, p)
    if d and d > minKm * 1000 and d < maxKm * 1000 and p.id ~= here.id then return p end
  end
end

-- Speeds: lurking a little slower than the player, slower still when they hang back; hunting faster, capped.
T.eq(robber.lurkKph(80, 50), 65, 'lurking: 15 km/h slower')
T.eq(robber.lurkKph(10, 50), 20, 'never under 20 km/h')
T.eq(robber.lurkKph(80, 120), 45, 'brake-check: the player hangs back, it slows right down')
T.eq(robber.huntKph(60), 75, 'hunting: 15 km/h faster')
T.eq(robber.huntKph(125), 130, 'capped at 130 km/h')

-- The whole robbery: rolled at the job board, loaded there, put on the road at its moment once the ground has loaded,
-- lurks, hunts, strikes, flees, and the EMP catches it.
do
  local c, a, car = ready(0.1)
  local news = {}
  c.robberyNews = function(_, who, what) news[#news + 1] = who .. ' ' .. what end
  local to = townBetween(c, 20, 60)
  T.check(to ~= nil, 'a town for a long job')
  local id = F.offer(c, to, 'food')
  T.check(c:takeJob(id), 'job taken')
  c:tick(0.1)
  T.check(c.robberAtKm ~= nil, 'this job is robbed (50%)')
  T.check(c.robberAtKm >= 2, 'after the first 2 km')
  T.eq(car.loaded, 1, 'the robber is loaded at the job board')
  T.eq(c.robber.phase, 'loaded', 'out of sight')
  F.advance(c, 5)
  T.eq(car.placed, 0, 'not before its moment')
  c.load.drivenKm = c.robberAtKm + 0.01
  car.ground = false
  F.advance(c, 5)
  T.eq(car.placed, 0, 'not until the ground ahead has loaded')
  T.eq(c.robber.phase, 'loaded', 'still waiting')
  car.ground = true
  F.advance(c, 3)
  T.eq(c.robber.phase, 'lurking', 'on the road ahead')
  T.eq(car.lurks[1], 45, 'still 300 m ahead: slow, so the player catches up')
  T.eq(c.robberAtKm, nil, 'the job has had its robber')
  T.eq(c:view().thief, nil, 'no card yet: it looks like traffic')
  -- The EMP can't stop it yet, but the press still charges.
  T.check(not c:fireEmp(), 'nothing to hit yet')
  T.check(c:empChargeLeft() > 19, 'the EMP is charging')
  -- The player catches up: a little slower than them.
  car.metres = 50
  F.advance(c, 1.2)
  T.eq(car.speeds[#car.speeds], 65, '15 km/h slower than the player')
  -- The player hangs back: brake-check.
  car.metres = 120
  F.advance(c, 1.2)
  T.eq(car.speeds[#car.speeds], 45, 'slows right down')
  T.eq(c.robber.phase, 'lurking', 'still lurking 70 m back')
  -- The player turns off: it hunts.
  car.gap = 90
  F.advance(c, robber.TURNED_SECONDS + 0.5)
  T.eq(c.robber.phase, 'hunting', 'turned off: hunting')
  T.eq(car.hunts[1], 95, 'at the player\'s speed plus 15')
  -- It strikes within 15 m.
  local before, sounds = c.profile.progression.balance, c:view().empSound
  car.metres = 12
  F.advance(c, 0.2)
  T.eq(c.robber.phase, 'chasing', 'struck, fleeing')
  T.eq(c.profile.progression.balance, before - robber.STOLEN, '$1,000 taken')
  T.eq(c:view().empSound, sounds + 1, 'the EMP sound plays once for the hit')
  T.eq(car.playerHits, 1, 'the player\'s engine is cut'); T.eq(car.fled[1], c.robber.carId, 'and it flees')
  T.eq(c.flash.title, 'ROBBED ON THE ROAD: -$1,000', 'told')
  local v = c:view().thief
  T.check(v and v.road and v.phase == 'chasing', 'the chase card, for the robber')
  T.eq(v.bounty, 20000, '$20,000 in the trunk')
  T.eq(v.emp.ready, false, 'its EMP drained the player\'s: it charges from empty')
  T.check(not c:fireEmp(), 'so they can\'t hit back straight away')
  T.eq(table.concat(news, ', '), 'robber struck', 'the live feed is told it struck')
  car.v = 0
  F.advance(c, robber.PLAYER_EMP_SECONDS + 0.2)
  T.eq(car.playerBack, 1, 'the engine comes back after 10 s')
  T.eq(car.brakesOff, 1, 'the brakes let off once, after half a second')
  T.eq(car.unstuck, 1, 'its car sat still for 5 s: put back on the road, once (then a 10 s wait)')
  car.v = 12; F.advance(c, 0.2); car.v = 0; F.advance(c, 4)
  T.eq(car.unstuck, 1, 'moving again resets the count')
  car.v = nil
  -- Delivering doesn't end the chase.
  c.load = nil
  F.advance(c, 1)
  T.eq(c.robber.phase, 'chasing', 'the chase carries on without the job')
  -- Caught: once the EMP has charged, within 15 m.
  F.advance(c, emp.CHARGE_SECONDS)
  car.metres = 14
  F.advance(c, 0.2)
  T.check(c:view().thief.emp.inRange, 'in range')
  T.check(c:empHotkey(), 'the EMP hits')
  T.eq(car.hit[1], c.robber.carId, 'on the robber')
  T.eq(c.profile.progression.balance, before + robber.TRUNK, 'money back plus $20,000')
  T.eq(c.flash.title, 'ROBBER CAUGHT: +$21,000', 'told')
  T.eq(table.concat(news, ', '), 'robber struck, robber caught', 'and that it was caught')
  local carId = c.robber.carId
  F.advance(c, robber.CAUGHT_SECONDS + 0.5)
  T.eq(c.robber, nil, 'over'); T.check(car.removed[carId], 'gone after 30 s')
end

-- The robber gets away 450 m clear.
do
  local c, a, car = ready()
  car.metres = 200
  T.check(c:robMe(), 'ROB ME')
  F.advance(c, 0.5)
  T.eq(c.robber.phase, 'lurking', 'on the road straight away')
  car.metres = 10; F.advance(c, 0.2)
  T.eq(c.robber.phase, 'chasing', 'struck')
  car.metres = robber.ESCAPE_METRES + 1; F.advance(c, 0.2)
  T.eq(c.robber, nil, 'got away'); T.eq(c.flash.title, 'THE ROBBER GOT AWAY', 'told')
end

-- It gives up: 4 minutes without striking, or 500 m behind. Nothing is lost.
do
  local c, a, car = ready()
  local start = c.profile.progression.balance
  car.metres = 100
  T.check(c:robMe(), 'ROB ME'); F.advance(c, 0.5)
  F.advance(c, robber.GIVE_UP_SECONDS + 1)
  T.eq(c.robber, nil, 'gave up after 4 minutes'); T.eq(c.profile.progression.balance, start, 'nothing taken')
  T.check(c:robMe(), 'again'); F.advance(c, 0.5)
  car.metres = 400; F.advance(c, 0.2)
  T.eq(c.robber.phase, 'hunting', 'dropped back: hunting')
  car.metres = robber.GIVE_UP_METRES + 1; F.advance(c, 0.2)
  T.eq(c.robber, nil, 'gave up 500 m behind')
end

-- ROB ME: any time, ticked or not; it doesn't touch the job's own robbery. The tick box keeps robbers off jobs and the
-- base thief, and is saved.
do
  local c, a, car = ready(0.99)
  T.check(c:view().robMe.robbersAllowed, 'ticked by default')
  T.check(c:setRobbersAllowed(false), 'unticked')
  T.check(not c:view().robMe.robbersAllowed, 'shown unticked')
  T.eq(c:robberProblem(false), 'You chose not to be robbed.', 'no road robber')
  c.random = function() return 0 end
  local id = F.offer(c, townBetween(c, 20, 60), 'food')
  T.check(c:takeJob(id), 'job taken'); c:tick(0.1)
  T.eq(c.robberAtKm, nil, 'no robbery planned'); T.eq(car.loaded, 0, 'nothing loaded')
  T.check(c:view().robMe.allowed, 'ROB ME still allowed')
  T.check(c:robMe(), 'ROB ME works unticked'); F.advance(c, 0.5)
  T.eq(c.robber.phase, 'lurking', 'a robber on the road')
  T.check(not c:robMe(), 'one at a time')
end

-- Unticked, the base thief stays away too.
do
  local c, a = ready()
  T.check(c:setRobbersAllowed(false), 'unticked')
  T.check(c:buyBase(F.copy(a.pose)), 'a base')
  a.pose = location.destination(a.pose, 90, thief.MIN_AWAY_METRES + 1000); F.advance(c, 1); c.stranded = nil
  T.eq(c:theftProblem(false), 'You chose not to be robbed.', 'no base thief either')
  T.check(c:setRobbersAllowed(true), 'ticked again')
  T.check(c:theftProblem(false) ~= 'You chose not to be robbed.', 'thieves are back')
end

-- ROB ME before a robbed job's moment: the job still gets its own robber later.
do
  local c, a, car = ready(0.1)
  local id = F.offer(c, townBetween(c, 20, 60), 'food')
  T.check(c:takeJob(id), 'job taken'); c:tick(0.1)
  local at = c.robberAtKm
  T.check(at ~= nil, 'robbed job')
  car.metres = 100
  T.check(c:robMe(), 'ROB ME uses the loaded car'); F.advance(c, 0.5)
  T.eq(c.robberAtKm, at, 'the job keeps its moment')
  F.advance(c, robber.GIVE_UP_SECONDS + 1)
  T.check(c.robber and c.robber.phase == 'loaded' and not c.robber.forced, 'the test robber gave up, and the job\'s robber is loaded again')
  T.eq(car.loaded, 2, 'a second car')
end

-- Short jobs and the heli's packages are never robbed; nor anything without $1,000.
do
  local c, a, car = ready(0)
  T.check(not c:robbableJob({ from = 'x', to = 'y' }), 'unknown places: no')
  T.check(not c:robbableJob({ beacon = true }), 'heli package: no')
  local near = townBetween(c, 0.5, 6)
  if near then
    local id = F.offer(c, near, 'food')
    T.check(c:takeJob(id), 'short job'); c:tick(0.1)
    T.eq(c.robberAtKm, nil, 'under 5 km: not robbed')
  end
  c.profile.progression.balance = 500
  T.eq(c:robberProblem(true), 'Less than $1,000 in the bank.', 'nothing to take')
end

-- The tick box is kept through a save and a reload.
do
  local c, io = F.controller({ random = function() return 0.99 end })
  c.thiefCar = fakeCar()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:setRobbersAllowed(false), 'unticked')
  T.check(c:manualSave(), 'saved')
  local r = F.controller({ io = io })
  r.thiefCar = fakeCar()
  r:tick(0.1); r:tick(0.6)
  T.eq(r.noRobbers, true, 'still unticked after a reload')
end

-- The saved tick box.
do
  local s = F.save(1)
  s.noRobbers = true
  T.check(persistence.validate(s), 'noRobbers saves')
  s.noRobbers = 'yes'
  T.check(not persistence.validate(s), 'only true')
end

-- The game side: the commands, and the car put down only where the ground has loaded.
do
  T.check(thiefCar.lurkCommand(60):find("'traffic'", 1, true), 'lurking: traffic AI')
  T.check(thiefCar.lurkCommand(60):find("driveInLane, 'on'", 1, true), 'in its lane')
  T.check(thiefCar.huntCommand(5, 90):find("'chase'", 1, true), 'hunting: chase AI')
  T.check(thiefCar.huntCommand(5, 90):find('25', 1, true), '90 km/h is 25 m/s')
  T.check(thiefCar.PLAYER_EMP_START:find("'brake', 1", 1, true), 'the player\'s EMP slams the brakes on')
  T.check(thiefCar.PLAYER_EMP_BRAKE_OFF:find("'brake', 0", 1, true), 'and lets them off after')
  T.check(thiefCar.PLAYER_EMP_START:find('setIgnitionLevel, 0', 1, true), 'the engine cut')
  local function vec(x, y, z) return { x = x, y = y, z = z } end
  local veh = { pos = vec(0, 0, 10), dir = vec(0, 1, 0), active = {} }
  function veh:getPosition() return self.pos end
  function veh:getDirectionVector() return self.dir end
  function veh:getID() return 1 end
  local spawned = { active = {}, queued = {} }
  function spawned:setActive(v) self.active[#self.active + 1] = v end
  function spawned:getID() return 9 end
  function spawned:queueLuaCommand(cmd) self.queued[#self.queued + 1] = cmd end
  local ground = nil
  local opts
  local t = thiefCar.new({ vehicle = function() return veh end, objectById = function(id) return id == 9 and spawned or nil end,
    vehicles = function() return { spawnNewVehicle = function(model, o) opts = o; return spawned end } end,
    map = function() return nil end, spawn = function() return { safeTeleport = function() end } end, enter = function() end,
    point = vec, upright = function(d) return d end, emp = function() return nil end, bolidesRunning = function() return false end,
    groundBelow = function() return ground end, paint = function() return 'paint' end, random = function() return 0.5 end })
  T.eq(t:preload('moonhawk', 'x'), 9, 'preloaded')
  T.eq(opts.pos.z, -190, 'out of sight, under the player'); T.eq(opts.paint, 'paint', 'in a random paint')
  T.eq(spawned.active[1], 0, 'switched off')
  local ok, why = t:place(9, 300)
  T.check(not ok and why == 'no_ground', 'no ground loaded: not yet')
  ground = 10
  T.check(t:place(9, 300), 'placed once the ground is there')
  T.eq(spawned.active[2], 1, 'switched on')
  T.check(t:lurk(9, 50) and spawned.queued[1]:find("'traffic'", 1, true), 'lurk sent')
end

T.done('road robber')
