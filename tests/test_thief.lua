local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local thief = require('earthFreight/thief')
local thiefCar = require('earthFreight/thiefCar')
local location = require('earthFreight/location')

-- A stand-in for the thief's car: where it is, as metres from the player, set by the test.
local function fakeCar()
  local f = { spawned = {}, removed = {}, fled = {}, hit = {}, metres = 60, refuse = false }
  function f:spawn(model) if self.refuse then return nil, 'spawn_failed' end; self.spawned[#self.spawned + 1] = model; return 42 end
  function f:flee(id) self.fled[#self.fled + 1] = id; return true end
  function f:distance(id) if self.removed[id] then return nil end; return self.metres end
  function f:emp(id) self.hit[#self.hit + 1] = id; return true end
  function f:bearing() return self.arrow end
  function f:remove(id) self.removed[id] = true; return true end
  function f:update() end
  return f
end

local function ready(options)
  options = options or {}
  local car = fakeCar()
  local c, io, a = F.controller({ random = options.random or function() return 0.99 end })
  c.thiefCar = car
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 2000000
  return c, a, car
end

-- No base, no theft; the test command needs a base too.
do
  local c, a = ready({ random = function() return 0 end })
  F.advance(c, 5)
  T.eq(c.thief, nil, 'no base: no thief')
  T.check(not c:startTheft(true), 'the test command needs a base')
  local r = c:view().robbery
  T.check(r and not r.allowed and r.problem == 'You need a base first.', 'Get robbed says why not')
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  T.check(c:view().robbery.allowed, 'Get robbed offered with a base, even at it')
  T.check(c:startTheft(true), 'pressed')
  T.eq(c:view().robbery.problem, 'A thief is already about.', 'one at a time')
  c.mp = { state = 'server' }
  T.check(c:robberyView() ~= nil, 'the button on a server too'); c.mp = nil
end

-- Random thefts: only with a base and far from it, on a server too.
do
  local c, a = ready({ random = function() return 0 end })
  local base = F.copy(a.pose)
  T.check(c:buyBase(base), 'base bought')
  F.advance(c, 2)
  T.eq(c.thief, nil, 'not at the base itself')
  a.pose = location.destination(base, 90, thief.MIN_AWAY_METRES + 1000)
  c.stranded, c.booking = nil, nil
  c.lastSample = c.adapter:sample()
  T.check(c:theftProblem(false) == nil or c:theftProblem(false) == 'Busy.', 'far enough away')
  c.stranded = nil
  local before = c.profile.progression.balance
  c:watchThief(1)
  T.check(c.thief ~= nil, 'a thief strikes')
  T.eq(c.profile.progression.balance, before - thief.STOLEN, '$1,000 taken')
  T.eq(c:view().thief.phase, 'stolen', 'the HUD shows it')
  T.eq(c:view().thief.secondsLeft, thief.CHASE_WINDOW_SECONDS, 'with a 10 minute countdown')
  T.eq(c.flash.title, 'THIEF AT YOUR BASE: -$1,000', 'and an alert')
  -- Nobody gives chase: the money is gone.
  c:endTheft('late')
  T.eq(c.thief, nil, 'over')
  -- One a session: no more, however long they play.
  c.clock = c.clock + 5 * 3600
  c:watchThief(1)
  T.eq(c.thief, nil, 'only one a session')
  T.check(c.theftPlan.done, 'this session has had its theft')
  c.mp = { state = 'server' }
  T.eq(c:theftProblem(true), nil, 'thieves on a server too'); c.mp = nil
  -- Leaving the map or server ends the session; the next one gets its own.
  c:endMission()
  T.eq(c.theftPlan, nil, 'a new session, a new theft to come')
end

-- The session's theft comes at a random moment in the first 45 minutes, or as soon as it can after that.
do
  local c, a = ready({ random = function() return 0.5 end })
  local base = F.copy(a.pose)
  T.check(c:buyBase(base), 'base bought')
  a.pose = location.destination(base, 90, thief.MIN_AWAY_METRES + 1000)
  c.lastSample = c.adapter:sample()
  c.stranded, c.booking = nil, nil
  c:watchThief(0.1)
  local due = c.theftPlan.at
  T.near(due - c.clock, thief.WINDOW_MINUTES * 60 / 2, 5, 'due halfway through the first 45 minutes')
  c.clock = due - 1; c:watchThief(0.1)
  T.eq(c.thief, nil, 'not before then')
  -- At the base when it's due: it waits.
  a.pose = F.copy(base); c.lastSample = c.adapter:sample()
  c.clock = due + 1; c:watchThief(0.1)
  T.eq(c.thief, nil, 'not while at the base')
  a.pose = location.destination(base, 90, thief.MIN_AWAY_METRES + 1000); c.lastSample = c.adapter:sample()
  c.clock = due + 600; c.stranded, c.booking = nil, nil; c:watchThief(0.1)
  T.check(c.thief ~= nil, 'then as soon as they can be robbed')
  -- Get robbed doesn't use up the session's theft.
  local d = ready({ random = function() return 0.99 end })
  T.check(d:buyBase(F.copy(a.pose)), 'base bought')
  d:watchThief(0.1)
  T.check(d:startTheft(true), 'Get robbed')
  T.check(not d.theftPlan.done, 'the session still has its own theft to come')
end

-- The whole chase: Chase relocates to the base for free, the world settles, the thief turns up and flees, the EMP
-- needs to be close, and catching them pays the money back plus the bounty.
do
  local c, a, car = ready()
  local base = F.copy(a.pose)
  T.check(c:buyBase(base), 'base bought')
  a.pose = location.destination(base, 90, 50000)
  F.advance(c, 1)
  c.stranded = nil
  local start = c.profile.progression.balance
  T.check(c:startTheft(true), 'the test command')
  T.check(c:view().thief.chaseAllowed, 'Chase offered')
  T.check(c:thiefChase(), 'Chase pressed')
  T.eq(c.booking.fee, 0, 'the relocation is free')
  T.eq(#a.teleports, 1, 'teleported'); T.eq(c.thief.phase, 'travelling', 'on the way')
  T.eq(c.profile.progression.balance, start - thief.STOLEN, 'nothing charged for the trip')
  -- Earth drops the car in 3 km off first while the terrain loads: no countdown yet.
  a.pose = location.destination(base, 0, 3000)
  F.advance(c, 30)
  T.eq(c.thief.phase, 'settling', 'landed: waiting for the world')
  T.eq(c:view().thief.settleLeft, nil, 'no countdown until really at the base')
  T.eq(#car.spawned, 0, 'and no thief')
  a.pose = F.copy(base)
  F.advance(c, 1)
  T.near(c:view().thief.settleLeft, thief.SETTLE_SECONDS - 1, 0.2, 'the 20 s start once there')
  F.advance(c, thief.SETTLE_SECONDS - 3)
  T.eq(#car.spawned, 0, 'no thief while the world loads')
  F.advance(c, 4)
  T.eq(car.spawned[1], 'moonhawk', 'the thief turns up'); T.eq(car.fled[1], 42, 'and flees')
  T.eq(thief.CONFIG, 'vehicles/moonhawk/earth_freight_sightseeing.pc', 'in the sightseeing car for now')
  T.eq(c.thief.phase, 'chasing', 'the chase is on')
  T.eq(c:view().thief.distanceMetres, 60, 'how far away')
  car.arrow = -90.4; F.advance(c, 0.2)
  T.eq(c:view().thief.arrow, -90, 'the arrow points to the thief')
  T.check(not c:empThief(), 'too far for the EMP')
  T.check(c.thief.feedback:find('within 5 m', 1, true), 'says how close to get')
  -- The Fire EMP hotkey: out of range it says so in a pop-up as well.
  local toasts = {}
  c.trigger = function(name, data) if name == 'toastrMsg' then toasts[#toasts + 1] = data end end
  T.check(not c:empHotkey(), 'hotkey: too far')
  T.eq(toasts[1] and toasts[1].title, 'EMP OUT OF RANGE', 'a pop-up says so')
  T.check(toasts[1].msg:find('within 5 m', 1, true), 'and how close to get')
  car.metres = 4
  F.advance(c, 0.2)
  T.check(c:view().thief.empInRange, 'in range')
  T.check(c:empHotkey(), 'the hotkey EMP hits')
  T.eq(car.hit[1], 42, 'on the thief')
  T.eq(c.profile.progression.balance, start + thief.BOUNTY, 'money back plus $5,000')
  T.eq(c.thief.phase, 'caught', 'caught')
  F.advance(c, thief.CAUGHT_SECONDS + 1)
  T.eq(c.thief, nil, 'over'); T.check(car.removed[42], 'the car is taken away')
end

-- The thief gets away 450 m clear: their car disappears and the player is told.
do
  local c, a, car = ready()
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  T.check(c:startTheft(true), 'stolen')
  T.check(c:thiefChase(), 'already at the base: the chase starts here')
  T.eq(c.thief.phase, 'settling', 'no teleport needed'); T.eq(#a.teleports, 0, 'none')
  F.advance(c, thief.SETTLE_SECONDS + 1)
  car.metres = 440
  F.advance(c, 60)
  T.eq(c.thief.phase, 'chasing', 'still on at 440 m, however long')
  car.metres = thief.ESCAPE_METRES + 1
  F.advance(c, 0.2)
  T.eq(c.thief, nil, 'got away'); T.eq(c.flash.title, 'THE THIEF GOT AWAY', 'told')
  T.check(c.flash.text:find('450 m clear', 1, true), 'how')
  T.check(car.removed[42], 'its car taken away')
end

-- Chase never pressed: the countdown runs out.
do
  local c, a = ready()
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  T.check(c:startTheft(true), 'stolen')
  F.advance(c, thief.CHASE_WINDOW_SECONDS + 1)
  T.eq(c.thief, nil, 'too late'); T.eq(c.flash.title, 'THE THIEF GOT AWAY', 'told')
end

-- The game won't put the thief's car down: after a few tries the money comes back.
do
  local c, a, car = ready()
  car.refuse = true
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  local start = c.profile.progression.balance
  T.check(c:startTheft(true), 'stolen'); T.check(c:thiefChase(), 'chase')
  F.advance(c, thief.SETTLE_SECONDS + thief.SPAWN_RETRY_SECONDS * thief.SPAWN_TRIES + 2)
  T.eq(c.thief, nil, 'given up'); T.eq(c.profile.progression.balance, start, 'money back')
end

-- Chase holds a job: the cargo, the distance driven and the trailer wait, and Back to your job goes back to the spot.
do
  local places = require('earthFreight/places')
  local function placeNamed(name)
    for _, p in ipairs(places.list) do if p.name == name then return p end end
  end
  local c, a, car = ready()
  local g = c.garage
  local here = F.copy(a.pose)
  c.property = { latitude = here.latitude + 0.5, longitude = here.longitude, paid = 250000 }
  T.check(c:buyTrailer(1), 'a trailer'); local trailerId = c.trailerOut.id
  local id = F.offer(c, placeNamed('St Clair'), 'food')
  T.check(c:takeJob(id), 'on a job')
  local driven = c.load.drivenKm
  T.check(c:startTheft(true), 'robbed while on the job')
  T.eq(c:view().thief.problem, nil, 'Chase allowed with cargo on board')
  T.check(c:thiefChase(), 'Chase')
  T.check(c:view().thief.held.job, 'the job is held')
  a.pose = { latitude = c.property.latitude, longitude = c.property.longitude }
  F.advance(c, 1)
  T.check(c.load ~= nil, 'the cargo is kept'); T.eq(c.thief.phase, 'settling', 'at the base')
  T.check(c.trailer.stored, 'the trailer went to the base')
  T.eq(c.stranded, nil, 'not stranded')
  F.advance(c, thief.SETTLE_SECONDS + 1)
  F.drive(c, a, location.destination(a.pose, 0, 300))
  T.eq(c.load.drivenKm, driven, 'chasing does not count as driving the job')
  T.check(not c:deliver(), 'no delivering while away'); T.check(c.tradeFeedback:find('Go back to it first', 1, true), 'says why')
  T.check(not c:autoSaveSettled(), 'nothing saves by itself while away')
  car.metres = 3; F.advance(c, 0.2)
  T.check(c:empThief(), 'caught')
  local v = c:view().thief
  T.eq(v.phase, 'return', 'the card offers the way back'); T.check(v.job and v.trailer and v.returnAllowed, 'with the job and trailer')
  T.check(c:thiefGoBack(), 'Back to your job')
  T.eq(c.booking.fee, 0, 'free')
  a.pose = F.copy(here)
  F.advance(c, 1)
  T.eq(c.thiefReturn, nil, 'back')
  T.check(c.load ~= nil and c.load.drivenKm == driven, 'the job carries on as it was')
  T.check(c.trailerOut ~= nil, 'the trailer is out behind the car')
  T.eq(c.flash.title, 'BACK ON THE ROAD', 'told')
  T.eq(c.stranded, nil, 'not stranded')
  F.drive(c, a, location.destination(a.pose, 0, 300))
  T.check(c.load.drivenKm > driven, 'driving counts again')
end

-- The Fire EMP hotkey does nothing when no chase is on.
do
  local c, a, car = ready()
  local toasts = {}
  c.trigger = function(name, data) if name == 'toastrMsg' then toasts[#toasts + 1] = data end end
  T.check(not c:empHotkey(), 'no thief: nothing')
  T.eq(#toasts, 0, 'and no pop-up'); T.eq(#car.hit, 0, 'no EMP')
end

-- The Fire EMP action: in the game's Controls list, with no key, calling the hotkey.
do
  local json = require('json')
  local f = assert(io.open((arg[0]:match('^(.*)[/\\]') or '.') .. '/../mod/earth_freight/lua/ge/extensions/core/input/actions/earthFreight.json'))
  local actions = json.decode(f:read('*a')); f:close()
  local fire = actions.earthFreightFireEmp
  T.eq(fire.title, 'Fire EMP', 'named Fire EMP'); T.eq(fire.ctx, 'tlua', 'runs in the game engine')
  T.check(fire.onDown:find('earthFreight_core.empHotkey()', 1, true), 'calls the hotkey')
  T.eq(fire.cat, 'gameplay', 'under Gameplay')
end

-- The game side: the flee and EMP commands, and the car put down ahead of the player.
do
  local cmd = thiefCar.fleeCommand(7)
  T.check(cmd:find("ai.setMode, 'flee'", 1, true) and cmd:find('local tid = 7', 1, true), 'flee from the player')
  T.check(cmd:find("ai.setSmartProfile, 'moonhawk'", 1, true), 'smartAI when installed')
  T.check(thiefCar.EMP_COMMAND:find('setIgnitionLevel, 0', 1, true), 'the EMP cuts the ignition')
  local function vec(x, y, z) return { x = x, y = y, z = z } end
  local queued, spawnedAt, deleted = {}, nil, false
  local thiefObj = { getID = function() return 9 end, getPosition = function() return vec(3, 4, 0) end,
    queueLuaCommand = function(_, c) queued[#queued + 1] = c end, delete = function() deleted = true end }
  local player = { getID = function() return 1 end, getPosition = function() return vec(0, 0, 0) end,
    getDirectionVector = function() return vec(0, 1, 0) end }
  local t = thiefCar.new({ vehicle = function() return player end,
    objectById = function(id) return id == 9 and thiefObj or nil end,
    vehicles = function() return { spawnNewVehicle = function(model, o) spawnedAt = o.pos; return thiefObj end } end,
    map = function() return nil end, spawn = function() return nil end, enter = function() end,
    point = vec, upright = function(d) return d end, emp = function() return nil end, bolidesRunning = function() return false end })
  T.eq(t:spawn('moonhawk', nil, 100), 9, 'spawned')
  T.eq(spawnedAt.y, 100, '100 m ahead without a road map')
  -- On the nearest road, lined up with it and pointing away from the player.
  local rot
  local road = thiefCar.new({ vehicle = function() return player end, objectById = function() return thiefObj end,
    vehicles = function() return { spawnNewVehicle = function(model, o) spawnedAt, rot = o.pos, o.rot; return thiefObj end } end,
    map = function() return { findClosestRoad = function() return 'r', 'a', 'b', 3 end,
      getMap = function() return { nodes = { a = { pos = vec(20, 200, 0) }, b = { pos = vec(20, 0, 0) } } } end } end,
    spawn = function() return nil end, enter = function() end, point = vec, upright = function(d) return d end,
    emp = function() return nil end, bolidesRunning = function() return false end })
  road:spawn('moonhawk', nil, 100)
  T.eq(spawnedAt.x, 20, 'moved onto the road'); T.eq(spawnedAt.y, 100, 'at the closest point of it')
  T.eq(rot.x, 0, 'lined up with the road'); T.eq(rot.y, 1, 'facing away from the player')
  T.check(t:flee(9) and queued[1]:find('local tid = 1', 1, true), 'fleeing from the player')
  T.eq(t:distance(9), 5, 'distance')
  T.near(t:bearing(9), 36.87, 0.01, 'the arrow: ahead and to the right')
  player.getDirectionVector = function() return vec(0, -1, 0) end
  T.near(t:bearing(9), -143.13, 0.01, 'behind and to the left when facing the other way')
  player.getDirectionVector = function() return vec(0, 1, 0) end
  T.check(t:emp(9) and queued[2] == thiefCar.EMP_COMMAND, 'EMP')
  T.check(t:remove(9) and deleted, 'removed')
  T.eq(t:distance(10), nil, 'no car, no distance')
end

T.done('thief')
