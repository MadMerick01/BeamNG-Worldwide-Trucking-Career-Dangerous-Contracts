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
  local f = { loaded = 0, placed = 0, removed = {}, fled = {}, hit = {}, passes = {}, hunts = {}, speeds = {}, trail = 0,
    playerHits = 0, playerBack = 0, metres = 300, ground = true, kph = 80, gap = 0, refuse = false }
  function f:preload() if self.refuse then return nil, 'spawn_failed' end; self.loaded = self.loaded + 1; return 70 + self.loaded end
  function f:place(id, metres, behind) if self.removed[id] then return false, 'gone' end; if not self.ground then return false, 'no_ground' end; self.placed = self.placed + 1; self.placedAt = { metres = metres, behind = behind }; return true end
  function f:pass(id, kph) self.passes[#self.passes + 1] = kph; return true end
  function f:noteTrail() self.trail = self.trail + 1 end
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
  function f:bearing() return self.bearingDeg or 10 end
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

-- Speeds: catching up fast from behind, easing off once close, capped.
T.eq(robber.huntKph(60, 100), 100, 'far back: 40 km/h faster')
T.eq(robber.huntKph(60, 40), 75, 'close: 15 km/h faster')
T.eq(robber.huntKph(60), 75, 'unknown distance: 15 km/h faster')
T.eq(robber.huntKph(125, 40), 130, 'capped at 130 km/h')
T.eq(robber.huntKph(110, 100), 130, 'capped far back too')

-- The whole robbery: rolled at the job board, loaded there, put on the road behind the player at its moment once the
-- ground has loaded, catches up, strikes, overtakes, flees, and the EMP catches it.
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
  T.check(car.trail > 0, 'the player\'s trail is noted while the robber waits')
  c.load.drivenKm = c.robberAtKm + 0.01
  car.ground = false
  F.advance(c, 5)
  T.eq(car.placed, 0, 'not until the ground ahead has loaded')
  T.eq(c.robber.phase, 'loaded', 'still waiting')
  car.ground = true
  F.advance(c, 3)
  T.eq(c.robber.phase, 'hunting', 'on the road and coming')
  T.eq(car.placedAt.metres, 100, '100 m back'); T.eq(car.placedAt.behind, true, 'behind the player, on their trail')
  T.eq(car.hunts[1], 120, 'catching up at the player\'s 80 km/h plus 40')
  T.eq(c.robberAtKm, nil, 'the job has had its robber')
  T.eq(c:view().thief, nil, 'no card yet: it looks like traffic')
  -- The EMP can't stop it yet, but the press still charges.
  T.check(not c:fireEmp(), 'nothing to hit yet')
  T.check(c:empChargeLeft() > 19, 'the EMP is charging')
  car.metres = 80
  F.advance(c, 1.2)
  T.eq(car.speeds[#car.speeds], 120, 'still far back: fast')
  -- Close behind: it eases off so it doesn't ram them.
  car.metres = 30
  F.advance(c, 1.2)
  T.eq(car.speeds[#car.speeds], 95, 'close: the player\'s speed plus 15')
  T.eq(c.robber.phase, 'hunting', 'still coming')
  -- It strikes within 15 m.
  local before, sounds = c.profile.progression.balance, c:view().empSound
  local cut = robber.take(c.load.pay, before)
  T.eq(cut, math.max(500, math.min(15000, math.floor(c.load.pay * 0.2 / 10 + 0.5) * 10)), '20% of the job\'s pay, $500 to $15,000')
  car.metres = 12
  F.advance(c, 0.2)
  T.eq(c.robber.phase, 'chasing', 'struck, fleeing')
  T.eq(c.profile.progression.balance, before - cut, 'its cut taken')
  T.eq(c:view().empSound, sounds + 1, 'the EMP sound plays once for the hit')
  T.eq(car.playerHits, 1, 'the player\'s engine is cut')
  T.eq(car.passes[1], robber.PASS_START_KPH, 'it eases off first, so it doesn\'t run into them')
  T.eq(#car.fled, 0, 'not fleeing yet: it overtakes first')
  T.check(c.robber.passing, 'overtaking')
  -- Still behind them: it speeds up to go round, but doesn't flee until it is past.
  car.bearingDeg = 170
  local speeds = #car.speeds
  F.advance(c, robber.PASS_HOLD_SECONDS + 0.2)
  T.eq(car.speeds[speeds + 1], robber.PASS_KPH, 'after a second, round them at up to 100 km/h')
  T.eq(#car.fled, 0, 'still behind: not fleeing yet')
  -- Past them and clear: now it flees.
  car.bearingDeg, car.metres = 5, robber.PASS_CLEAR_METRES + 1
  F.advance(c, 0.2)
  T.eq(car.fled[1], c.robber.carId, 'ahead and clear: it flees'); T.eq(c.robber.passing, nil, 'done overtaking')
  car.metres = 12
  T.eq(c.flash.title, 'ROBBED ON THE ROAD: -' .. require('earthFreight/pricing').dollars(cut), 'told')
  local v = c:view().thief
  T.check(v and v.road and v.phase == 'chasing', 'the chase card, for the robber')
  T.eq(v.bounty, robber.trunk(cut), 'half as much again in the trunk')
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
  T.eq(c.profile.progression.balance, before + robber.trunk(cut), 'money back plus the trunk')
  T.eq(c.flash.title, 'ROBBER CAUGHT: +' .. require('earthFreight/pricing').dollars(cut + robber.trunk(cut)), 'told')
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
  T.eq(c.robber.phase, 'hunting', 'on the road behind straight away')
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
  T.eq(c.robber.phase, 'hunting', 'still coming 400 m back')
  car.metres = robber.GIVE_UP_METRES + 1; F.advance(c, 0.2)
  T.eq(c.robber, nil, 'gave up 500 m behind')
end

-- ROB ME: any time, one at a time. The old "Robbers can rob me" tick box is gone for good.
do
  local c, a, car = ready(0.99)
  T.eq(c:view().robMe.robbersAllowed, nil, 'no old tick box')
  T.eq(c.setRobbersAllowed, nil, 'and not its command')
  T.check(c:view().robMe.allowed, 'ROB ME allowed')
  T.check(c:robMe(), 'ROB ME'); F.advance(c, 0.5)
  T.eq(c.robber.phase, 'hunting', 'a robber on the road')
  T.check(not c:robMe(), 'one at a time')
end

-- Single player: the "Robbers and thieves" switch keeps road robbers and the base thief away, costs nothing, and is saved.
-- ROB ME and Get robbed still work for testing.
do
  local c, a, car = ready(0)
  T.check(c:view().robMe.canSwitch, 'offered in single player')
  T.check(c:view().robMe.robbersOn, 'on by default')
  T.check(c:setRobbersOn(false), 'switched off')
  T.check(not c:view().robMe.robbersOn, 'shown off')
  T.eq(c:robberProblem(false), 'Robbers are switched off.', 'no road robber')
  local id = F.offer(c, townBetween(c, 20, 60), 'food')
  T.check(c:takeJob(id), 'job taken'); c:tick(0.1)
  T.eq(c.robberAtKm, nil, 'no robbery planned'); T.eq(car.loaded, 0, 'nothing loaded')
  T.check(c:robMe(), 'ROB ME still works'); F.advance(c, 0.5)
  T.eq(c.robber.phase, 'hunting', 'a test robber on the road')
end

-- Switching off while a job's robber waits for its moment sends it away; switching on again doesn't bring it back.
do
  local c, a, car = ready(0.1)
  local id = F.offer(c, townBetween(c, 20, 60), 'food')
  T.check(c:takeJob(id), 'job taken'); c:tick(0.1)
  T.check(c.robber and c.robber.phase == 'loaded', 'a robber waiting')
  T.check(c:setRobbersOn(false), 'switched off')
  T.eq(c.robber, nil, 'it went'); T.eq(c.robberAtKm, nil, 'and the job is safe')
  T.check(c:setRobbersOn(true), 'on again')
  F.advance(c, 1)
  T.eq(c.robber, nil, 'no robber for this job')
end

-- The base thief stays away too, and the hour's theft is dropped rather than kept for later.
do
  local c, a = ready()
  T.check(c:setRobbersOn(false), 'switched off')
  T.check(c:buyBase(F.copy(a.pose)), 'a base')
  a.pose = location.destination(a.pose, 90, thief.MIN_AWAY_METRES + 1000); F.advance(c, 1); c.stranded = nil
  T.eq(c:theftProblem(false), 'Robbers are switched off.', 'no base thief')
  T.check(c:robberyView().allowed, 'Get robbed still works')
  c.thiefClock = { played = 100, hour = 0, due = 50 }
  F.advance(c, 0.5)
  T.eq(c.thief, nil, 'no theft'); T.eq(c.thiefClock.due, nil, 'the hour\'s theft dropped')
  T.check(c:setRobbersOn(true), 'on again')
  T.check(c:theftProblem(false) ~= 'Robbers are switched off.', 'thieves are back')
  F.advance(c, 0.5)
  T.eq(c.thief, nil, 'but not the dropped theft')
end

-- The switch is kept through a save and a reload.
do
  local c, io = F.controller({ random = function() return 0.99 end })
  c.thiefCar = fakeCar()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:setRobbersOn(false), 'switched off')
  T.check(c:manualSave(), 'saved')
  local r = F.controller({ io = io })
  r.thiefCar = fakeCar()
  r:tick(0.1); r:tick(0.6)
  T.check(r:robbersOff(), 'still off after a reload')
  local s = F.save(1)
  s.robbersOff = true
  T.check(persistence.validate(s), 'robbersOff saves')
  s.robbersOff = 'yes'
  T.check(not persistence.validate(s), 'only true')
end

-- Online the switch isn't offered, can't be used, and a saved one is ignored: everyone can be robbed.
do
  local c, a, car = ready(0)
  c.mp = { state = 'server' }
  c.robbersOffSaved = true
  T.check(not c:robbersOff(), 'ignored online')
  T.eq(c:robMeView().canSwitch, nil, 'not offered')
  T.check(not c:setRobbersOn(false), 'and refused')
  T.eq(c:robberProblem(false), nil, 'robbers come')
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

-- Short jobs and the heli's packages are never robbed; nor anything without $500.
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
  c.profile.progression.balance = 400
  T.eq(c:robberProblem(true), 'Less than $500 in the bank.', 'nothing to take')
end

-- An old save with the tick box unticked still loads, and robbers come all the same; the setting isn't saved again.
do
  local s = F.save(1)
  s.noRobbers = true
  T.check(persistence.validate(s), 'an old save with noRobbers still loads')
  local c, io = F.controller({ random = function() return 0.1 end })
  c.thiefCar = fakeCar()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.noRobbers = true
  c.profile.progression.balance = 2000000
  T.eq(c:robberProblem(false), nil, 'robbers come anyway')
  T.check(c:manualSave(), 'saved')
  local wrote = false
  for _, data in pairs(io.files) do if type(data) == 'table' and data.noRobbers ~= nil then wrote = true end end
  T.check(not wrote, 'not written again')
end

-- The game side: the commands, and the car put down only where the ground has loaded.
do
  T.check(thiefCar.passCommand(60):find("'traffic'", 1, true), 'overtaking: traffic AI')
  T.check(thiefCar.passCommand(60):find("driveInLane, 'off'", 1, true), 'free to use the whole road to get round')
  T.check(thiefCar.passCommand(60):find("setAvoidCars, 'on'", 1, true), 'steering round cars')
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
  T.check(t:pass(9, 50) and spawned.queued[1]:find("'traffic'", 1, true), 'overtake sent')
  -- Behind the player: on their trail, facing the way they drove. No trail yet: straight back, still facing their way.
  local placedAt
  local t2 = thiefCar.new({ vehicle = function() return veh end, objectById = function(id) return id == 9 and spawned or nil end,
    vehicles = function() return nil end, map = function() return nil end,
    spawn = function() return { safeTeleport = function(_, pos, rot) placedAt = { pos = pos, rot = rot } end } end,
    enter = function() end, point = vec, upright = function(d) return d end, emp = function() return nil end,
    bolidesRunning = function() return false end, groundBelow = function() return 10 end })
  veh.pos, veh.dir = vec(0, 0, 10), vec(0, 1, 0)
  T.check(t2:place(9, 100, true), 'placed with no trail')
  T.near(placedAt.pos.y, -100, 0.01, 'straight back 100 m'); T.near(placedAt.rot.y, 1, 1e-6, 'facing the player\'s way')
  -- The player drives east 60 m, then turns north for 80 m (pointing north now): 100 m back is round the corner.
  for x = 0, 60, 5 do veh.pos = vec(x, 0, 10); t2:noteTrail() end
  for y = 5, 80, 5 do veh.pos = vec(60, y, 10); t2:noteTrail() end
  T.check(t2:place(9, 100, true), 'placed on the trail')
  T.near(placedAt.pos.x, 40, 0.01, 'round the corner, on the road they came along'); T.near(placedAt.pos.y, 0, 0.01, 'not cutting across')
  T.near(placedAt.rot.x, 1, 1e-6, 'facing east, the way they drove there')
  for y = 85, 300, 5 do veh.pos = vec(60, y, 10); t2:noteTrail() end
  T.eq(t2:trailLength(), thiefCar.TRAIL_POINTS, 'only the last 150 m kept')
  -- A teleport: the old trail is no road behind them, so it starts again.
  veh.pos = vec(5000, 5000, 10); t2:noteTrail()
  T.eq(t2:trailLength(), 1, 'trail started again after a jump')
  -- A U-turn: driving north, then back south. The old trail is the road ahead now: started again from the turn.
  t2:clearTrail()
  for y = 0, 150, 10 do veh.pos = vec(0, y, 10); t2:noteTrail() end
  T.eq(t2:trailLength(), 16, 'a long trail north')
  for y = 140, 110, -10 do veh.pos = vec(0, y, 10); t2:noteTrail() end
  T.eq(t2:trailLength(), 5, 'turned round: only from the turn on')
  veh.dir = vec(0, -1, 0)
  T.check(t2:place(9, 100, true), 'placed')
  T.check(placedAt.pos.y > veh.pos.y + 69, 'behind them the new way, never on the road ahead')
  T.near(placedAt.rot.y, -1, 1e-6, 'facing their new way, not head-on')
  -- Never too close: a hairpin, where 100 m back along the road is 20 m away across the bend.
  t2:clearTrail(); veh.dir = vec(0, 1, 0)
  for y = 0, 40, 10 do veh.pos = vec(0, y, 10); t2:noteTrail() end
  for x = 5, 20, 5 do veh.pos = vec(x, 40, 10); t2:noteTrail() end
  for y = 30, -10, -10 do veh.pos = vec(20, y, 10); t2:noteTrail() end
  veh.dir = vec(0, -1, 0)
  local placed = placedAt
  local ok, why = t2:place(9, 100, true)
  T.check(not ok and why == 'unsafe', 'too close across the bend: not placed, tried again later')
  T.eq(placedAt, placed, 'nothing moved')
  veh.dir = vec(0, 1, 0)
end

T.done('road robber')
