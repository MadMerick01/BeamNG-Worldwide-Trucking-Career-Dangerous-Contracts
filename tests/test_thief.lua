local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local thief = require('earthFreight/thief')
local thiefCar = require('earthFreight/thiefCar')
local location = require('earthFreight/location')
local emp = require('earthFreight/emp')

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
  local took = thief.take(before)
  T.eq(took, math.max(1000, math.min(10000, math.floor(before * 0.03 / 10 + 0.5) * 10)), '3% of the bank, $1,000 to $10,000')
  T.eq(c.profile.progression.balance, before - took, 'taken')
  T.eq(c.thief.bounty, thief.bounty(took), 'a real theft has a trunk bonus of half again')
  T.eq(c:view().thief.phase, 'stolen', 'the HUD shows it')
  T.eq(c:view().thief.secondsLeft, thief.CHASE_WINDOW_SECONDS, 'with a 10 minute countdown')
  T.eq(c.flash.title, 'THIEF AT YOUR BASE: -' .. require('earthFreight/pricing').dollars(took), 'and an alert')
  -- Let them go: only before the chase; the money is gone and the card goes.
  T.check(c:thiefLetGo(), 'let them go')
  T.eq(c.thief, nil, 'the card goes'); T.eq(c.flash.title, 'YOU LET THEM GO', 'told')
  T.eq(c.profile.progression.balance, before - took, 'the money stays gone')
  T.check(not c:thiefLetGo(), 'nothing to let go now')
  c.thief = { phase = 'stolen', amount = took, at = c.clock }
  -- Nobody gives chase: the money is gone.
  c:endTheft('late')
  T.eq(c.thief, nil, 'over')
  -- One an hour: no more in this hour, however long they wait in it.
  c:watchThief(1000)
  T.eq(c.thief, nil, 'only one in the hour')
  T.eq(c.thiefClock.due, nil, 'this hour has had its theft')
  c.mp = { state = 'server' }
  T.eq(c:theftProblem(true), nil, 'thieves on a server too'); c.mp = nil
  -- Leaving the map or server doesn't reset the count: the next session carries on.
  c:endMission()
  T.check(c.thiefClock and c.thiefClock.due == nil, 'no fresh theft for rejoining')
end

-- Each hour of play gets one theft at a random moment in it; a blocked one waits, an hour that ends drops it, and
-- two are at least GAP_MINUTES apart.
do
  local c, a = ready({ random = function() return 0.5 end })
  local base = F.copy(a.pose)
  T.check(c:buyBase(base), 'base bought')
  local far = location.destination(base, 90, thief.MIN_AWAY_METRES + 1000)
  a.pose = far
  c.lastSample = c.adapter:sample()
  c.stranded, c.booking = nil, nil
  c:watchThief(0.1)
  local k = c.thiefClock
  T.eq(k.hour, 0, 'the first hour')
  T.near(k.due, thief.HOUR_SECONDS / 2, 1, 'due halfway through it')
  c:watchThief(k.due - k.played - 1)
  T.eq(c.thief, nil, 'not before then')
  -- At the base when it's due: it waits.
  a.pose = F.copy(base); c.lastSample = c.adapter:sample()
  c:watchThief(2)
  T.eq(c.thief, nil, 'not while at the base')
  -- Paused: the count stands still.
  local played = k.played
  c.paused = function() return true end
  c:watchThief(600)
  T.eq(k.played, played, 'paused time is not counted')
  c.paused = function() return false end
  a.pose = far; c.lastSample = c.adapter:sample()
  c.stranded, c.booking = nil, nil
  c:watchThief(600)
  T.check(c.thief ~= nil, 'then as soon as they can be robbed')
  T.eq(k.last, k.played, 'noted')
  c.thief = nil
  -- The next hour's theft, halfway through hour 2 (40 minutes later), is far enough apart.
  c:watchThief(thief.HOUR_SECONDS - k.played + 1)
  T.eq(k.hour, 1, 'the second hour'); T.near(k.due, thief.HOUR_SECONDS * 1.5, 1, 'its own moment')
  T.eq(c.thief, nil, 'not yet')
  -- Saved and loaded as whole seconds.
  local saved = c:savedThiefClock()
  T.eq(saved.played, math.floor(k.played), 'whole seconds'); T.eq(saved.hour, 1, 'the hour kept')
  -- At the base all through hour 2: that theft is dropped, not stacked onto hour 3.
  a.pose = F.copy(base); c.lastSample = c.adapter:sample()
  c:watchThief(thief.HOUR_SECONDS)
  T.eq(c.thief, nil, 'never while at the base')
  T.eq(k.hour, 2, 'the third hour'); T.near(k.due, thief.HOUR_SECONDS * 2.5, 1, 'one new theft, not two')
  -- Too soon after the last: a theft due early in an hour waits for the gap.
  local d, b2 = ready({ random = function() return 0 end })
  local home = F.copy(b2.pose)
  T.check(d:buyBase(home), 'base bought')
  b2.pose = location.destination(home, 90, thief.MIN_AWAY_METRES + 1000); d.lastSample = d.adapter:sample()
  d.stranded, d.booking = nil, nil
  d:watchThief(thief.HOUR_SECONDS - 60)
  T.check(d.thief ~= nil, 'hour 1 theft'); d.thief = nil
  d:watchThief(61)
  T.eq(d.thiefClock.hour, 1, 'hour 2 has begun'); T.eq(d.thief, nil, 'but not 1 minute after the last')
  d:watchThief(thief.GAP_MINUTES * 60)
  T.check(d.thief ~= nil, 'once the gap has passed')
  -- Get robbed doesn't use up the hour's theft.
  local e, b3 = ready({ random = function() return 0.99 end })
  T.check(e:buyBase(F.copy(b3.pose)), 'base bought')
  e:watchThief(0.1)
  T.check(e:startTheft(true), 'Get robbed')
  T.check(e.thiefClock.due ~= nil, 'the hour still has its own theft to come')
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
  local took = thief.take(start)
  T.check(c:startTheft(false), 'a real theft')
  T.check(c:view().thief.chaseAllowed, 'Chase offered')
  T.check(c:thiefChase(), 'Chase pressed')
  T.eq(c.booking.fee, 0, 'the relocation is free')
  T.eq(#a.teleports, 1, 'teleported'); T.eq(c.thief.phase, 'travelling', 'on the way')
  T.eq(c.profile.progression.balance, start - took, 'nothing charged for the trip')
  -- Earth drops the car in 3 km off first while the terrain loads: no countdown yet.
  a.pose = location.destination(base, 0, 3000)
  F.advance(c, 30)
  T.eq(c.thief.phase, 'settling', 'landed: waiting for the world')
  T.eq(c:view().thief.settleLeft, nil, 'no countdown until really at the base')
  T.eq(#car.spawned, 0, 'and no thief')
  a.pose = F.copy(base)
  F.advance(c, 1)
  T.near(c:view().thief.settleLeft, thief.SETTLE_SECONDS - 1, 0.2, 'the 30 s start once there')
  F.advance(c, thief.SETTLE_SECONDS - 3)
  T.eq(#car.spawned, 0, 'no thief while the world loads')
  F.advance(c, 4)
  T.eq(car.spawned[1], 'moonhawk', 'the thief turns up'); T.eq(car.fled[1], 42, 'and flees')
  T.eq(thief.CONFIG, 'vehicles/moonhawk/earth_freight_sightseeing.pc', 'in the sightseeing car for now')
  T.eq(c.thief.phase, 'chasing', 'the chase is on')
  T.eq(c:view().thief.distanceMetres, 60, 'how far away')
  car.arrow = -90.4; F.advance(c, 0.2)
  T.eq(c:view().thief.arrow, -90, 'the arrow points to the thief')
  T.eq(thief.EMP_METRES, 15, 'the EMP reaches 15 m')
  T.check(c:view().thief.emp.ready and not c:view().thief.emp.inRange, 'the button: charged, out of range')
  local sounds = c:view().empSound
  T.check(not c:empThief(), 'too far for the EMP')
  T.eq(c:view().empSound, sounds + 1, 'the EMP sound plays: it fired, even out of range')
  T.check(c.empFeedback:find('within 15 m', 1, true), 'says how close to get')
  -- Every press charges: 20 s before it fires again.
  T.check(not c:view().thief.emp.ready, 'charging after a miss')
  T.eq(c:view().thief.emp.chargeLeft, 20, '20 s to charge')
  -- The Fire EMP hotkey: while charging it says so in a pop-up as well.
  local toasts = {}
  c.trigger = function(name, data) if name == 'toastrMsg' then toasts[#toasts + 1] = data end end
  car.metres = 4
  T.check(not c:empHotkey(), 'hotkey: still charging')
  T.eq(c:view().empSound, sounds + 1, 'no sound while it only charges')
  T.eq(toasts[1] and toasts[1].title, 'EMP CHARGING', 'a pop-up says so')
  F.advance(c, emp.CHARGE_SECONDS + 0.2)
  T.check(c:view().thief.empInRange and c:view().thief.emp.inRange and c:view().thief.emp.ready, 'charged and in range')
  local cash = c:view().cashSound
  T.check(c:empHotkey(), 'the hotkey EMP hits')
  T.eq(c:view().cashSound, cash + 1, 'the money back plays the cha-ching')
  T.eq(car.hit[1], 42, 'on the thief')
  T.eq(c:view().empSound, sounds + 2, 'and the EMP sound for the hit')
  T.eq(c.profile.progression.balance, start + thief.bounty(took), 'money back plus half again')
  T.eq(c.thief.phase, 'caught', 'caught'); T.eq(c:view().thief.paid, took + thief.bounty(took), 'the card says what came back')
  F.advance(c, thief.CAUGHT_SECONDS + 1)
  T.eq(c.thief, nil, 'over'); T.check(car.removed[42], 'the car is taken away')
  local v = c:view().thief
  T.eq(v and v.phase, 'return', 'the way back'); T.eq(v.outcome, 'caught', 'says how it went')
  T.eq(v.paid, took + thief.bounty(took), 'with the money')
  T.eq(v.amount, took, 'and what was taken')
end

-- The thief gets away 450 m clear: their car disappears and the player is told.
do
  local c, a, car = ready()
  local news = {}
  c.robberyNews = function(_, who, what) news[#news + 1] = who .. ' ' .. what end
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  T.check(c:startTheft(true), 'stolen')
  T.eq(table.concat(news, ', '), 'thief struck', 'the live feed is told')
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
  T.eq(table.concat(news, ', '), 'thief struck, thief escaped', 'and that it got away')
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

-- A trailer with part of the job in it: it goes to the base for the chase, and comes back behind the car with its
-- cargo's weight on it.
local function trailerJob(options)
  local places = require('earthFreight/places')
  local stClair
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then stClair = p end end
  local hitched = F.garage(); hitched.fitted.hitch = 'pickup_tow_hitch'
  local car = fakeCar()
  local c, io, a, g, w = F.controller({ garage = hitched, random = function() return 0.99 end })
  c.thiefCar = car
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 2000000
  c:openTrailers(true)
  T.check(c:buyTrailer(1), 'a trailer'); c.trailer.maxKg = 5000; c:readTrailerSpace()
  c:couplerChanged(1, c.trailerOut.id, true)
  local here = F.copy(a.pose)
  c.property = { latitude = here.latitude + 0.5, longitude = here.longitude, paid = 250000 }
  if options and options.parked then
    c.storedCars = { { config = { model = 'pickup', parts = { engine = 'pickup_engine_v8' } }, name = 'Pickup D15', fuelLitres = 30 } }
  end
  T.check(c:takeJob(F.offer(c, stClair, 'parts'), 50), 'on a job'); T.eq(c.load.trailerUnits, 50, 'half of it in the trailer')
  return c, a, g, w, car, here, stClair
end

do
  local c, a, g, w, car, here, stClair = trailerJob()
  local trailerKg = w.trailerWeights[#w.trailerWeights].kg
  T.check(trailerKg > 0, 'the trailer carries its share')
  T.check(c:startTheft(true), 'robbed'); T.check(c:thiefChase(), 'Chase')
  a.pose = { latitude = c.property.latitude, longitude = c.property.longitude }
  F.advance(c, 1)
  T.check(c.trailer.stored and c.trailer.at == 'base', 'the trailer went to the base'); T.eq(c.load.trailerUnits, 50, 'its cargo still in the job')
  F.advance(c, thief.SETTLE_SECONDS + 1)
  car.metres = 3; F.advance(c, 0.2); T.check(c:empThief(), 'caught')
  T.check(c:thiefGoBack(), 'Back to your job')
  a.pose = F.copy(here); F.advance(c, 1)
  local id = c.trailerOut.id
  local last = w.trailerWeights[#w.trailerWeights]
  T.eq(last.id, id, 'the weight is on the trailer that came back'); T.near(last.kg, trailerKg, 1e-9, 'all of its cargo')
  c:couplerChanged(1, id, true)
  F.drive(c, a, stClair)
  T.check(c:deliver(), 'delivered once hitched')
end

-- Chase in a parked car: the truck is parked with the job and the trailer's cargo, the chase car goes to the base and
-- carries none of it, and Back to your job swaps the truck back in at the spot, trailer and all. Free both ways.
do
  local c, a, g, w, car, here, stClair = trailerJob({ parked = true })
  local driven, balance, truck = c.load.drivenKm, nil, c.ownedParts.model
  T.check(c:startTheft(true), 'robbed'); balance = c.profile.progression.balance
  local v = c:view().thief
  T.eq(#v.cars, 1, 'Chase in: the parked car'); T.eq(v.cars[1].name, 'Pickup D15', 'by its name'); T.check(v.cars[1].allowed, 'allowed with the job on')
  T.check(not c:thiefChase(2), 'not an empty slot')
  T.check(c:thiefChase(1), 'Chase in the pickup'); T.eq(c.thief.phase, 'swapping', 'the pickup is on its way')
  T.eq(c.storedCars[1].config.model, truck, 'the truck is parked in its slot')
  T.eq(c:view().thief.cars, nil, 'no more Chase in buttons')
  T.check(c:jobCarParked(), 'with the job in it')
  c:vehicleSpawned(); F.advance(c, 0.3)
  T.eq(c.ownedParts.model, 'pickup', 'driving the pickup'); T.eq(c.thief.phase, 'travelling', 'then off to the base')
  T.eq(w.weights[#w.weights].kg, 0, 'none of the job on the pickup'); T.check(c.load and c.load.trailerUnits == 50, 'the job held')
  a.pose = { latitude = c.property.latitude, longitude = c.property.longitude }
  F.advance(c, 1)
  T.eq(c.thief.phase, 'settling', 'at the base'); T.check(c.trailer.stored, 'the trailer went to the base')
  T.eq(c.profile.progression.balance, balance, 'free')
  T.check(not c:sellParkedCar(1), 'the truck with the job cannot be sold'); T.check(c.fleetFeedback:find('job in it', 1, true), 'says why')
  T.check(not c:manualSave(), 'no saving while away'); T.check(c.feedback:find('Back to your job', 1, true), 'says why')
  T.check(c:loadFits({ parts = {} }), 'the job never has to fit in the chase car')
  F.advance(c, thief.SETTLE_SECONDS + 1)
  car.metres = 3; F.advance(c, 0.2); T.check(c:empThief(), 'caught in the pickup'); balance = c.profile.progression.balance
  local r = c:view().thief
  T.eq(r.phase, 'return', 'the way back'); T.check(r.truck and r.job and r.trailer and r.returnAllowed, 'with the truck, job and trailer')
  T.check(c:thiefGoBack(), 'Back to your job'); a.pose = F.copy(here); F.advance(c, 1)
  T.check(c.thiefReturn and c.thiefReturn.swapAt, 'the truck is coming back'); T.check(c:view().thief.travelling, 'the card says so')
  T.check(not c:thiefGoBack(), 'Back to your job only once')
  c:vehicleSpawned(); F.advance(c, 0.3)
  T.eq(c.thiefReturn, nil, 'back'); T.eq(c.ownedParts.model, truck, 'in the truck again')
  T.eq(c.storedCars[1].config.model, 'pickup', 'the pickup back in its slot')
  T.check(c.trailerOut ~= nil, 'the trailer behind it'); T.eq(w.trailerWeights[#w.trailerWeights].id, c.trailerOut.id, 'with its cargo')
  T.check(w.weights[#w.weights].kg > 0, 'the truck carries its share again')
  T.eq(c.load.drivenKm, driven, 'the job as it was'); T.eq(c.profile.progression.balance, balance, 'nothing charged for the way back')
  T.eq(c.flash.title, 'BACK ON THE ROAD', 'told')
  c:couplerChanged(1, c.trailerOut.id, true)
  F.drive(c, a, stClair)
  T.check(c:deliver(), 'delivered')
end

-- Chase in a parked car from the base: no teleport either way, and Back to your job swaps the truck back in there.
do
  local c, a, g, w, car, here = trailerJob({ parked = true })
  c.property = { latitude = here.latitude, longitude = here.longitude, paid = 250000 }
  T.check(c:atHome(), 'at the base')
  T.check(c:startTheft(true), 'robbed'); T.check(c:thiefChase(1), 'Chase in the pickup')
  c:vehicleSpawned(); F.advance(c, 0.3)
  T.eq(c.thief.phase, 'settling', 'straight into the chase'); T.eq(c.booking, nil, 'no teleport')
  T.check(c.trailerOut ~= nil, 'the trailer stays where it is')
  F.advance(c, thief.SETTLE_SECONDS + 1)
  car.metres = 3; F.advance(c, 0.2); T.check(c:empThief(), 'caught')
  T.check(c:thiefGoBack(), 'Back to your job'); T.eq(c.booking, nil, 'already there: no teleport')
  c:vehicleSpawned(); F.advance(c, 0.3)
  T.eq(c.thiefReturn, nil, 'back'); T.eq(c.storedCars[1].config.model, 'pickup', 'the pickup parked again')
end

-- No robbers during a Mayday Rescue run, not even Get robbed's. A theft already on waits: Chase can't be pressed and
-- its clock stops until the run is over.
do
  local c, a = ready()
  T.check(c:buyBase(F.copy(a.pose)), 'base bought')
  F.drive(c, a, location.destination(a.pose, 0, 6000))
  c.maydayRun = { round = 1, edge = 'n', at = c.clock }
  T.check(not c:startTheft(true), 'no theft on a run'); T.eq(c:view().robbery.problem, 'Not during a Mayday Rescue run.', 'Get robbed says why')
  c.maydayRun = nil
  T.check(c:startTheft(true), 'stolen')
  c.maydayRun = { round = 1, edge = 'n', at = c.clock }
  local left = c:theftSecondsLeft()
  T.check(not c:view().thief.chaseAllowed, 'no Chase on a run'); T.check(c:view().thief.problem:find('Mayday Rescue', 1, true), 'says why')
  F.advance(c, 60)
  T.near(c:theftSecondsLeft(), left, 0.5, 'the clock stopped')
  c.maydayRun = nil
  T.check(c:view().thief.chaseAllowed, 'Chase once the run is over')
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
  -- Stuck off the road: back on it. The thief is at (3, 4), the road runs along x = 20.
  local moved
  local stuck = thiefCar.new({ vehicle = function() return player end, objectById = function() return thiefObj end,
    map = function() return { findClosestRoad = function() return 'r', 'a', 'b', 3 end,
      getMap = function() return { nodes = { a = { pos = vec(20, 200, 0) }, b = { pos = vec(20, 0, 0) } } } end } end,
    spawn = function() return { safeTeleport = function(_, pos, r) moved = { pos = pos, rot = r } end } end, enter = function() end,
    point = vec, upright = function(d) return d end, emp = function() return nil end, bolidesRunning = function() return false end })
  T.check(stuck:unstick(9), 'a car 17 m off the road is moved')
  T.eq(moved.pos.x, 20, 'onto the road'); T.eq(moved.pos.y, 4, 'level with where it was'); T.eq(moved.rot.y, 1, 'facing away from the player')
  thiefObj.getPosition = function() return vec(18, 4, 0) end
  moved = nil
  T.check(not stuck:unstick(9) and moved == nil, 'one already on the road is left to the AI')
  thiefObj.getPosition = function() return vec(3, 4, 0) end
  T.check(not road:unstick(9), 'nothing to move it with: no harm done')
  thiefObj.getVelocity = function() return vec(3, 4, 0) end
  T.eq(stuck:speed(9), 5, 'its speed')
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

-- The thief's car is loaded out of sight while the player waits at the base, and put on the road once the ground there
-- has loaded; if it never does, it is spawned the old way.
do
  for _, ground in ipairs({ true, false }) do
    local c, a, car = ready()
    car.preloaded, car.placed, car.ground = 0, 0, ground
    function car:preload() self.preloaded = self.preloaded + 1; return 77 end
    function car:place(id) if not self.ground then return false, 'no_ground' end; self.placed = self.placed + 1; return true end
    T.check(c:buyBase(F.copy(a.pose)), 'base bought')
    T.check(c:startTheft(true), 'stolen'); T.check(c:thiefChase(), 'chase')
    F.advance(c, 1)
    T.eq(car.preloaded, 1, 'loaded while the player waits')
    T.eq(#car.spawned, 0, 'not spawned')
    F.advance(c, thief.SETTLE_SECONDS + thief.SPAWN_RETRY_SECONDS * (thief.SPAWN_TRIES + 1) + 1)
    T.eq(c.thief.phase, 'chasing', 'the chase is on')
    if ground then
      T.eq(car.placed, 1, 'the loaded car put on the road'); T.eq(c.thief.carId, 77, 'it is the thief')
      T.eq(#car.spawned, 0, 'no new spawn')
    else
      T.check(car.removed[77], 'no ground: the loaded car goes'); T.eq(car.spawned[1], 'moonhawk', 'spawned the old way')
    end
  end
end

T.done('thief')
