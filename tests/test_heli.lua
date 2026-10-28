local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local heli = require('earthFreight/heli')
local aircraft = require('earthFreight/aircraft')
local beacons = require('earthFreight/beacons')
local jobs = require('earthFreight/jobs')
local persistence = require('earthFreight/persistence')
local places = require('earthFreight/places')
local location = require('earthFreight/location')

-- Finding the helicopter: a Bell 407 without weapons, else any Bell 407; nothing without the mod.
local list = {
  { model = 'pickup', key = 'd15', config = 'vehicles/pickup/d15.pc', name = 'Pickup D15', value = 20000 },
  { model = 'bell407', key = 'armed', config = 'vehicles/bell407/armed.pc', name = 'Bell 407 Armed', value = 900000 },
  { model = 'bell407', key = 'civ', config = 'vehicles/bell407/civ.pc', name = 'Bell 407 Civilian', value = 1200000 },
  { model = 'bell407', key = 'medic', config = 'vehicles/bell407/medic.pc', name = 'Bell 407 Medical', value = 1000000 },
}
T.eq(heli.findHeli(list).key, 'medic', 'the cheapest config without weapons')
T.eq(heli.findHeli({ list[1], list[2] }).key, 'armed', 'an armed one when there is nothing else')
T.eq(heli.findHeli({ list[1] }), nil, 'no helicopter without the mod')
T.check(heli.isHeli({ model = 'b407_revamp', key = 'x', name = 'Bell 407 (Revamped)' }), 'found by its name too')
T.check(not heli.isHeli({ model = 'bell', key = 'x', name = 'Bell 206' }), 'not another helicopter')
local withHook = { list[3], { model = 'bell407', key = 'hook', config = 'vehicles/bell407/hook.pc', name = 'Bell 407 Tow Hook', value = 1300000 } }
T.eq(heli.findHeli(withHook).key, 'hook', 'a config with a hook first')
-- The game side: where the helicopter is and how high, every call guarded.
do
  local function vec(x, y, z) return { x = x, y = y, z = z } end
  local player = { getPosition = function() return vec(10, 5, 105) end }
  local a = aircraft.new({ vehicle = function() return player end, objectById = function() return nil end,
    ground = function(_, _, z) return z end })
  T.eq(a:height(), 105, 'height above the ground'); T.eq(a:where().z, 105, 'where it is'); T.eq(a:where(5), nil, 'nothing else')
  local broken = aircraft.new({ vehicle = function() error('no') end, objectById = function() error('no') end,
    ground = function() error('no') end })
  T.eq(broken:height(), nil, 'no height'); T.eq(broken:where(), nil, 'nowhere')
end

-- Finding a beacon: a pickup near the helicopter and within reach of the car, a drop 2 to 5 km
-- from it, and a line that is never the last one.
do
  places.ensure(F.PENRITH)
  local n = 0
  local function rnd() n = n + 1; return ((n * 0.37) % 1) end
  local car = F.copy(F.PENRITH)
  local heliAt = location.destination(car, 45, 5000)
  for i = 1, 30 do
    local b = beacons.find(heliAt, car, rnd, (i % #beacons.LINES) + 1)
    T.check(b ~= nil, 'found')
    local fromHeli = location.distance(heliAt, b.pickup)
    T.check(fromHeli >= beacons.SPOT_MIN - 1 and fromHeli <= beacons.SPOT_MAX + 1, 'near the helicopter ' .. fromHeli)
    T.check(location.distance(car, b.pickup) <= beacons.CAR_METRES, 'within reach of the car')
    local drop = location.distance(b.pickup, b.drop)
    T.check(drop >= beacons.DROP_MIN - 1 and drop <= beacons.DROP_MAX + 1, 'a drop 2 to 5 km on ' .. drop)
    T.check(b.line >= 1 and b.line <= #beacons.LINES and b.line ~= (i % #beacons.LINES) + 1, 'a new line ' .. b.line)
    T.eq(b.left, beacons.EXPIRE_SECONDS, 'an hour to go')
  end
  T.eq(beacons.find(location.destination(car, 0, 40000), car, rnd), nil, 'none out of reach of the car')
  T.eq(#beacons.LINES, 19, 'nineteen lines')
  for _, line in ipairs(beacons.LINES) do T.check(not line:lower():find('school', 1, true), 'no school bag') end
  T.eq(beacons.line(99), 'A package nobody wants to talk about.', 'a line this version lacks')
  T.eq(beacons.PAY, 12000, '$12,000'); T.eq(beacons.INSURANCE_FEE, 4000, '$4,000 claims')
end

local HELI_CONFIG = 'vehicles/bell407/civ.pc'
-- A game with the Bell 407 installed, the player in their pickup in Penrith with fuel read.
local function game(options)
  options = options or {}
  local ac = F.aircraft()
  local c, io, a, g, cargo, f = F.controller({ aircraft = ac })
  if not options.noMod then
    table.insert(g.configList, { model = 'bell407', key = 'civ', config = HELI_CONFIG, name = 'Bell 407 Civilian', value = 1200000, source = 'Mod' })
  end
  g.configParts[HELI_CONFIG] = { body = 'bell407_body' }
  -- The sample names the vehicle the garage has.
  local tick = c.tick
  c.tick = function(self, dt)
    a.vehicle = { id = g.vehicleId, model = g.model }
    return tick(self, dt)
  end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 5000
  c:fuelReading(1, 30, 50)
  return c, a, g, ac, cargo, f, io
end
-- Hires: two presses, then the helicopter spawns and the first load turns up.
local function hire(c, g)
  c:hireHeli(); c:hireHeli()
  c:vehicleSpawned(); c:tick(0.1)
end


-- Without the mod there is nothing to hire, and the tab says what to install.
do
  local c = game({ noMod = true })
  local v = c:view().heli
  T.check(not v.installed, 'not installed'); T.check(not v.hireAllowed, 'no hire')
  T.check(v.problem:find('Revamped Bell 407', 1, true) ~= nil, 'names the mod')
  T.check(v.modPage:find('beamng.com', 1, true) ~= nil, 'with its page')
  T.check(not c:hireHeli(), 'hiring does nothing'); T.eq(c.profile.progression.balance, 5000, 'nothing charged')
end

-- Hiring: asks to confirm, costs $1,000, swaps the car for the helicopter, and the garage does not
-- bill the helicopter as a car. The car waits with its job.
do
  local c, a, g, ac, cargo = game()
  local stClair
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then stClair = p end end
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a truck job on board')
  local v = c:view().heli
  T.check(v.installed and v.hireAllowed, 'a hire is on offer'); T.eq(v.fee, 1000, 'for $1,000')
  T.check(not c:hireHeli(), 'the first press asks'); T.check(c:view().heli.armed, 'Confirm hire shown')
  T.check(c:view().heli.feedback:find('with its job', 1, true) ~= nil, 'says the job waits')
  local weights = #cargo.weights
  T.check(c:hireHeli(), 'hired'); T.eq(c.profile.progression.balance, 4000, '$1,000 paid')
  T.eq(g.spawns[#g.spawns].config, HELI_CONFIG, 'the Bell 407 spawned'); T.eq(g.model, 'bell407', 'in place of the car')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.hire.stage, 'flying', 'flying'); T.eq(c.pendingCar, nil, 'no car bill for the helicopter')
  T.eq(c:view().carChange, nil, 'none shown'); T.eq(c.ownedParts.model, 'pickup', 'the pickup is still the player\'s car')
  T.eq(c:view().flash.title, 'HELICOPTER HIRED', 'told so')
  T.eq(#cargo.weights, weights, 'the job weight is not put on the helicopter')
  T.check(c.load ~= nil, 'the job waits'); T.check(not c:view().saveAllowed, 'no Save while flying')
  T.check(not c:manualSave(), 'Save refuses'); T.check(c.feedback:find('Back to my car', 1, true) ~= nil, 'and says why')
  T.check(c:tradeProblem(c:here()) ~= nil, 'no truck jobs from the helicopter')
  T.check(not c:view().repairQuoteAllowed, 'no repair quote for the helicopter')
  T.check(c:shippingProblem() ~= nil, 'no relocation')
  T.check(not c:hireHeli(), 'no second hire'); T.eq(c.profile.progression.balance, 4000, 'nothing more paid')
  -- The Heli tab: where you are, your car, the towns around and the nearest one's board, read-only.
  local hired = c:view().heli.hired
  T.eq(hired.here.name, 'Penrith', 'over Penrith'); T.check(hired.here.region ~= nil, 'its region')
  T.eq(#hired.towns, heli.TOWNS, 'the nearest towns'); T.eq(hired.towns[1].name, 'Penrith', 'nearest first')
  T.check(#hired.board > 0, 'Penrith\'s jobs'); for _, j in ipairs(hired.board) do T.check(not j.allowed, 'none can be taken') end
  T.check(hired.car.near, 'the car is right here'); T.eq(hired.load, nil, 'no loads to carry')
  -- Flying far does not count as driving, nor as a teleport.
  local km = c.profile.progression.totalDistanceKm
  a.pose = location.destination(F.PENRITH, 90, 30000); c:tick(0.1); c:tick(0.1)
  T.eq(c.stranded, nil, 'not stranded'); T.check(c.load ~= nil, 'the job is not cancelled')
  T.eq(c.profile.progression.totalDistanceKm, km, 'flying does not count')
end

-- Beacons while flying: every 5 minutes up high, a 50% chance; one at a time.
local function rolls(list)
  local i = 0
  return function() i = i + 1; return list[(i - 1) % #list + 1] end
end
do
  local c, a, g, ac = game()
  local trig = {}
  c.trigger = function(name, data) trig[#trig + 1] = { name = name, data = data } end
  hire(c, g)
  -- Low down, the time does not count.
  ac.ground = 10
  F.advance(c, beacons.FIND_SECONDS + 5)
  T.eq(c.beacon, nil, 'nothing found low down'); T.eq(c.hire.airborne, 0, 'no time counted')
  -- Up high: a miss, then a find.
  ac.ground = 200
  c.random = rolls({ 0.9 })
  F.advance(c, beacons.FIND_SECONDS + 1)
  T.eq(c.hire.rolls, 1, 'one chance'); T.eq(c.beacon, nil, 'missed')
  T.near(c:view().heli.hired.nextChanceSeconds, beacons.FIND_SECONDS - 1, 1, 'the next chance in about 5 minutes')
  c.random = rolls({ 0.1, 0.3, 0.6, 0.2, 0.7, 0.4 })
  F.advance(c, beacons.FIND_SECONDS)
  T.check(c.beacon ~= nil, 'a beacon found'); T.eq(c:view().flash.title, 'SIGNAL BEACON PICKED UP', 'told so')
  local popup = trig[#trig]
  T.eq(popup.name, 'EarthFreightBeacon', 'the centre-screen box'); T.check(popup.data.text:find('$12,000', 1, true) ~= nil, 'with the pay')
  local view = c:view().beacon
  T.check(view ~= nil and view.pickup ~= nil, 'on the HUD'); T.eq(view.pay, 12000, 'paying $12,000')
  T.check(view.distanceMetres <= beacons.SPOT_MAX + 1, 'near the helicopter'); T.check(not view.pickUpAllowed, 'not from the air')
  -- One at a time.
  local first = c.beacon.line
  c.random = rolls({ 0 })
  F.advance(c, beacons.FIND_SECONDS * 2)
  T.eq(c.beacon.line, first, 'no second beacon while one waits')
  -- Back in the car, the beacon stays, and is kept by Save.
  ac.ground = 0
  a.pose = F.copy(F.PENRITH)
  c:backToCar(); c:backToCar(); c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c.hire, nil, 'back in the car'); T.check(c.beacon ~= nil, 'the beacon waits')
  T.check(c:manualSave(), 'saved'); T.check(c.profile.beacon ~= nil, 'with the beacon')
  T.check(persistence.validate(c.profile) ~= nil, 'a valid save')
  local left = c.beacon.left
  c:reload(); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.beacon ~= nil, 'still there after a reload'); T.near(c.beacon.left, left, 2, 'with its time left')
  -- It counts down while playing and goes quiet after an hour.
  c.beacon.left = 5
  F.advance(c, 6)
  T.eq(c.beacon, nil, 'gone quiet'); T.eq(c:view().flash.title, 'BEACON WENT QUIET', 'told so')
end

-- The job: drive to the pickup, pick it up, drive it to the drop off road and get $12,000.
do
  local c, a, g, ac, cargo = game()
  c.beacon = { pickup = location.destination(F.PENRITH, 90, 3000), drop = nil, line = 2, left = 3000 }
  c.beacon.drop = location.destination(c.beacon.pickup, 0, 3000)
  local drop = F.copy(c.beacon.drop)
  T.check(not c:pickUpBeacon(), 'not from town'); T.check(c.tradeFeedback:find('Drive to the beacon', 1, true) ~= nil, 'drive there')
  F.drive(c, a, c.beacon.pickup)
  local view = c:view().beacon
  T.check(view.inZone and view.pickUpAllowed, 'at the beacon')
  T.check(c:pickUpBeacon(), 'picked up'); T.eq(c.beacon, nil, 'the beacon is used')
  T.check(c.load.beacon and c.load.kg == 0, 'a job with no weight'); T.eq(c.load.pay, 12000, 'for $12,000')
  T.check(c.tradeFeedback:find('cooler box', 1, true) ~= nil, 'says what it is')
  T.eq(cargo.weights[#cargo.weights].kg, 0, 'no weight on the car')
  local load = c:view().load
  T.check(load.beacon and load.drop ~= nil, 'the Route tab shows the drop'); T.eq(load.insurance, 4000, 'a $4,000 claim')
  T.eq(c:insuranceFee(), 4000, 'a claim costs $4,000')
  T.check(c:manualSave(), 'saved on the way'); T.check(persistence.validate(c.profile) ~= nil, 'a valid save')
  T.check(c.profile.load.beacon and c.profile.load.pickup ~= nil, 'the job is kept')
  c:reload(); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.load and c.load.beacon, 'the job after a reload')
  local before = c.profile.progression.balance
  F.drive(c, a, drop)
  T.check(c:view().load.drop.delivery.allowed, 'delivery allowed at the drop')
  T.check(c:deliver(), 'delivered'); T.eq(c.profile.progression.balance, before + 12000, '$12,000 paid')
  T.eq(c:view().flash.title, 'DELIVERED: +$12,000', 'told so'); T.eq(c.load, nil, 'job done')
end

-- Picking up needs no other job, a stopped car and no hire; ignoring it is free.
do
  local c, a, g = game()
  local stClair
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then stClair = p end end
  c.beacon = { pickup = F.copy(F.PENRITH), drop = location.destination(F.PENRITH, 0, 3000), line = 1, left = 3000 }
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a truck job on board')
  T.check(not c:pickUpBeacon(), 'not with a job on'); T.check(c.tradeFeedback:find('Deliver or abandon', 1, true) ~= nil, 'says why')
  c:abandonJob(); c:abandonJob()
  T.check(c:pickUpBeacon(), 'picked up once the job is gone')
  -- Abandoning it after pickup costs the usual fee.
  local before = c.profile.progression.balance
  c:abandonJob(); c:abandonJob()
  T.eq(c.profile.progression.balance, before - jobs.ABANDON_FEE, 'abandon fee')
  -- Ignoring a beacon: asked once, then gone for nothing.
  c.beacon = { pickup = F.copy(F.PENRITH), drop = location.destination(F.PENRITH, 0, 3000), line = 1, left = 3000 }
  before = c.profile.progression.balance
  T.check(not c:ignoreBeacon(), 'asks first'); T.check(c:view().beacon.ignoreArmed, 'Confirm shown')
  T.check(c:ignoreBeacon(), 'ignored'); T.eq(c.beacon, nil, 'gone'); T.eq(c.profile.progression.balance, before, 'free')
end

-- A save with a broken beacon is refused; one without is fine.
do
  local ok = persistence.validate
  local c = game()
  c:manualSave()
  local save = F.copy(c.profile)
  save.beacon = { pickup = { latitude = 91, longitude = 0 }, drop = F.copy(F.PENRITH), line = 1, left = 10 }
  T.eq(select(2, ok(save)), 'invalid_beacon', 'a bad pickup')
  save.beacon = { pickup = F.copy(F.PENRITH), drop = F.copy(F.PENRITH), line = 0, left = 10 }
  T.eq(select(2, ok(save)), 'invalid_beacon', 'a bad line')
  save.beacon = nil
  T.check(ok(save) ~= nil, 'no beacon is fine')
end

-- Back to my car near the car: lands, swaps back with the car's fuel, damage and job.
do
  local c, a, g, ac, cargo, f = game()
  local stClair
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then stClair = p end end
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a truck job on board')
  g.damage = 2000; c:tick(0.1)
  hire(c, g)
  ac.ground = 30
  T.check(not c:backToCar(), 'asks first'); T.check(c:view().heli.hired.backArmed, 'Confirm shown')
  T.check(not c:backToCar(), 'not while flying over it'); T.check(c.heliFeedback:find('Land first', 1, true) ~= nil, 'land first')
  ac.ground = 0
  c:backToCar(); T.check(c:backToCar(), 'swapping back')
  T.eq(g.model, 'pickup', 'the pickup is back'); T.eq(#a.teleports, 0, 'no teleport needed nearby')
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c.hire, nil, 'the hire is over'); T.eq(c:view().flash.title, 'BACK IN YOUR CAR', 'told so')
  T.eq(c.pendingCar, nil, 'no car bill'); T.eq(c.ownedParts.model, 'pickup', 'still the player\'s car')
  T.eq(c.owedDamage, 2000, 'its damage still owed')
  T.near(f.sets[#f.sets].litres, 30, 1e-9, 'its fuel put back')
  T.eq(cargo.weights[#cargo.weights].kg, c.load.kg, 'its job weight put back')
  T.check(c:view().saveAllowed, 'Save works again')
  T.check(c:view().heli.hireAllowed, 'hiring again is offered'); T.eq(c:view().heli.fee, 1000, 'for another $1,000')
end

-- Back to my car far away: Earth teleports the helicopter back, then the car takes its place.
do
  local c, a, g = game()
  hire(c, g)
  a.pose = location.destination(F.PENRITH, 0, 20000); c:tick(0.1)
  T.eq(c:view().heli.hired.car.direction, 'south', 'the car is to the south')
  c:backToCar(); T.check(c:backToCar(), 'going back'); T.eq(#a.teleports, 1, 'Earth teleports')
  T.near(a.teleports[1].latitude, F.PENRITH.latitude, 1e-6, 'to the car')
  T.eq(g.model, 'bell407', 'still in the helicopter while the terrain loads')
  a.pose = F.copy(F.PENRITH); F.advance(c, heli.SETTLE_SECONDS + 0.2)
  T.eq(g.model, 'pickup', 'the car takes its place')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.hire, nil, 'back in the car'); T.eq(c.stranded, nil, 'not stranded')
  -- With no teleport, the player flies back.
  local d, da, dg = game()
  hire(d, dg)
  da.teleportRefused = true
  da.pose = location.destination(F.PENRITH, 0, 20000); d:tick(0.1)
  d:backToCar(); T.check(not d:backToCar(), 'cannot teleport'); T.check(d.heliFeedback:find('Fly back', 1, true) ~= nil, 'fly back')
  T.eq(dg.model, 'bell407', 'still flying')
end

-- A crash ends the hire: $1,000 insurance, the hire is lost, back in the car.
do
  local c, a, g, ac = game()
  hire(c, g)
  local before = c.profile.progression.balance
  a.pose = location.destination(F.PENRITH, 0, 8000); c:tick(0.1)
  g.damage = heli.CRASH_DAMAGE + 10; c:tick(0.1)
  T.eq(c.profile.progression.balance, before - 1000, '$1,000 insurance')
  T.eq(c:view().flash.title, 'HELICOPTER CRASHED', 'told so')
  T.eq(#a.teleports, 1, 'taken back to the car')
  a.pose = F.copy(F.PENRITH); F.advance(c, heli.SETTLE_SECONDS + 0.2)
  T.eq(g.model, 'pickup', 'the car is back')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.hire, nil, 'the hire is over'); T.eq(c.profile.progression.balance, before - 1000, 'nothing more charged')
  -- With less than $1,000, the crash takes what there is.
  local d, da, dg = game()
  hire(d, dg)
  d.profile.progression.balance = 300
  dg.damage = heli.CRASH_DAMAGE + 10; d:tick(0.1)
  T.eq(d.profile.progression.balance, 0, 'all the money')
end

-- A reload while flying: the hire is not saved.
do
  local c, a, g = game()
  hire(c, g)
  c:reload()
  T.eq(c.hire, nil, 'no hire after a reload')
end

-- The helicopter that never turns up is refunded.
do
  local c, a, g = game()
  g.configParts[HELI_CONFIG] = nil
  c:hireHeli(); c:hireHeli()
  T.eq(c.profile.progression.balance, 4000, 'paid')
  F.advance(c, heli.SPAWN_SECONDS + 0.5)
  T.eq(c.hire, nil, 'given up'); T.eq(c.profile.progression.balance, 5000, 'refunded')
end

T.done('heli flights')
