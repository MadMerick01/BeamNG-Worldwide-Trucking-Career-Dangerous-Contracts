local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('earthFreight/persistence')
local Core = require('earthFreight/core')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local jobs = require('earthFreight/jobs')
local fuel = require('earthFreight/fuel')
local location = require('earthFreight/location')
local contracts = require('earthFreight/contracts')
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'
local north = 1 / 111195.0802 -- degrees latitude per metre

local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
local penrith, stClair = placeNamed('Penrith'), placeNamed('St Clair')

-- A fresh start: go to Penrith, get the starter car there, save.
do
  local c, io, a, g = F.controller()
  a.pose = F.position(-33.9, 151.2); g.starter = { engine = 'burnside_engine_i6' }
  T.eq(c.state, 'EARTH_UNAVAILABLE', 'waits for the first vehicle position')
  c:tick(0.1)
  T.eq(c.state, 'READY', 'any valid position starts the session')
  T.eq(c:view().stateLabel, 'GO TO PENRITH', 'player told to go to Penrith')
  T.eq(c:view().resume.latitude, F.PENRITH.latitude, 'Penrith coordinates shown')
  T.check(not c:manualSave(), 'save locked until the player arrives'); T.eq(io.writes, 0, 'no writes')
  T.eq(c:view().balance, Core.STARTING_MONEY, 'a new game starts with the starting money')
  T.eq(#g.spawns, 0, 'no starter car away from Penrith')
  a.pose = F.copy(F.PENRITH); c:tick(0.1)
  T.check(c:view().arrived, 'arrived in Penrith'); T.eq(#g.spawns, 1, 'starter car given on arrival')
  T.eq(g.spawns[1].config, Core.STARTER_CONFIG, 'the Earth Freight starter config')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.ownedParts.parts.engine, 'burnside_engine_i6', 'starter parts taken as paid for')
  T.eq(c:view().here.name, 'Penrith', 'in Penrith')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].atStart, nil, 'the save is no longer at the start')
  local r = F.controller({ io = io })
  T.eq(r.mode, 'resume', 'a reload resumes'); T.eq(r:view().balance, Core.STARTING_MONEY, 'money kept')
  r.adapter = F.adapter(F.position(-33.9, 151.2)); r:tick(0.1)
  T.eq(r:view().stateLabel, 'GO TO YOUR LAST SAVE', 'a reload asks to go back to the save')
  T.eq(r:view().resume.latitude, F.PENRITH.latitude, 'with its coordinates')
  T.check(not r:manualSave(), 'save locked until back at the save')
  r.adapter.pose = F.copy(F.PENRITH); r:tick(0.1)
  T.check(r:view().arrived, 'back at the save'); T.eq(r:view().flash.title, 'WELCOME BACK', 'welcomed back')
  T.check(r:manualSave(), 'saving works again')
end

-- Teleport there: Earth is asked to take the player to the save, or to the start town.
do
  local c, io, a = F.controller()
  a.pose = F.position(-33.9, 151.2)
  T.check(not c:teleportToResume(), 'nothing to teleport to before Earth is ready')
  c:tick(0.1)
  T.check(c:view().teleportAllowed, 'offered on the way to Penrith')
  T.check(c:teleportToResume(), 'asked'); T.eq(#a.teleports, 1, 'one teleport asked of Earth')
  T.eq(a.teleports[1].latitude, F.PENRITH.latitude, 'to Penrith'); T.eq(a.teleports[1].name, 'Earth Freight: Penrith', 'named for Earth')
  T.check(not c:view().teleportAllowed, 'the button rests while Earth loads')
  T.check(c:view().teleportFeedback:find('Teleporting') ~= nil, 'the player is told it is on its way')
  c:tick(31)
  T.check(c:view().teleportAllowed, 'offered again if the car never got there')
  T.check(c:view().teleportFeedback:find('Not there yet') ~= nil, 'and told to try again')
  a.pose = F.copy(F.PENRITH); c:tick(0.1)
  T.check(c:view().arrived, 'arriving works as after pasting the coordinates')
  T.check(not c:view().teleportAllowed and c:view().teleportFeedback == nil, 'no button once there')
  T.check(not c:teleportToResume(), 'no teleport once there'); T.eq(#a.teleports, 1, 'nothing more asked')
  c:manualSave()
  local r = F.controller({ io = io })
  local ra = F.adapter(F.position(-33.9, 151.2)); r.adapter = ra; r:tick(0.1)
  T.check(r:teleportToResume(), 'a reload offers the teleport to the save')
  T.eq(ra.teleports[1].name, 'Earth Freight: last save', 'named as the last save')
  T.near(ra.teleports[1].latitude, io.files[A].resume.latitude, 1e-12, 'to where it was saved')
  local f = F.controller({ io = io })
  local fa = F.adapter(F.position(-33.9, 151.2)); fa.teleportRefused = true; f.adapter = fa; f:tick(0.1)
  T.check(not f:teleportToResume(), 'Earth refusing is reported')
  T.check(f:view().teleportAllowed, 'the button stays')
  T.check(f:view().teleportFeedback:find('did not take') ~= nil, 'the player is told to copy the coordinates')
  local n = F.controller({ io = io }); n.adapter = F.adapter(F.position(-33.9, 151.2)); n.adapter.teleport = nil; n:tick(0.1)
  T.check(not n:view().teleportAllowed, 'no button without Earth\'s teleport')
end

-- Cargo space comes from the cargo boxes fitted; with none it is the boot.
do
  local cargo = require('earthFreight/cargo')
  local boot = cargo.capacity({ parts = { engine = 'x' }, names = {} })
  T.eq(boot.slots, cargo.BOOT.slots, 'no box: boot slots'); T.check(boot.boot, 'marked as the boot')
  local m = cargo.capacity({ parts = { a = 'pickup_cargo_load_box_m', b = 'x' }, names = { pickup_cargo_load_box_m = 'Cargo Load Box M' } })
  T.eq(m.slots, 4, 'box M holds 4 slots'); T.eq(m.kg, 130, 'box M weight limit'); T.eq(m.boxes[1], 'Cargo box M', 'box listed')
  T.eq(cargo.box('van_cargo_load_box_xl').slots, 128, 'XL matched before L')
  T.eq(cargo.box('cargo_load_box_l').slots, 16, 'L')
  T.eq(cargo.box('x', 'Cargo Load Box S').slots, 1, 'matched on the display name')
  T.eq(cargo.box('pickup_bed_cargo_net'), nil, 'a part without a box is not a box')
  T.eq(cargo.box('cargo_load_fluid_tank_xl'), nil, 'tanks are not parcel boxes')
  T.eq(cargo.tank('pickup_cargo_load_fluid_tank_xl').litres, 800, 'a fluid tank XL holds 800 L')
  T.eq(cargo.tank('x', 'Cargo Load Fluid Tank M').litres, 200, 'matched on the display name')
  T.eq(cargo.tank('pickup_fueltank_xl', 'Fuel Tank XL'), nil, 'the car fuel tank is not cargo')
  T.eq(cargo.tank('cargo_load_box_l'), nil, 'a box is not a tank')
  local both = cargo.capacity({ parts = { a = 'pickup_cargo_load_box_m', t = 'pickup_cargo_load_fluid_tank_l' }, names = {} })
  T.eq(both.slots, 4, 'the box gives slots'); T.eq(both.litres, 400, 'the tank gives litres')
  T.eq(both.tankParts[1], 'pickup_cargo_load_fluid_tank_l', 'the tank part is known')
  T.eq(cargo.partsFor(both, goods.get('water'))[1], 'pickup_cargo_load_fluid_tank_l', 'fluid weight goes in the tank')
  T.eq(cargo.partsFor(both, goods.get('parts'))[1], 'pickup_cargo_load_box_m', 'parcels in the box')
  T.eq(cargo.capacity({ parts = { t = 'pickup_cargo_load_fluid_tank_s' }, names = {} }).boot, true, 'a tank alone leaves parcels in the boot')
  -- The starter Burnside: a holder in the boot seating five M boxes.
  local starter = cargo.capacity({ parts = {
    burnside_trunk_load = 'burnside_cargo_load_box_5M_trunk',
    a = 'cargo_load_box_M_trunk_A_90deg', b = 'cargo_load_box_M_trunk_B_90deg', c = 'cargo_load_box_M_trunk_C_90deg',
    d = 'cargo_load_box_M_trunk_D_90deg', e = 'cargo_load_box_M_trunk_E' },
    names = { burnside_cargo_load_box_5M_trunk = '5x Cargo Load Box M' } })
  T.eq(#starter.boxes, 5, 'five M boxes, holder not counted')
  T.eq(starter.slots, 20, 'five M boxes of slots')
  local units, slots, kg = cargo.fits({ slots = 16, kg = 600 }, goods.get('bricks'))
  T.eq(units, 4, 'bricks in a Cargo box L run out of weight first'); T.eq(slots, 12, 'in 12 slots'); T.eq(kg, 600, 'their weight')
  units = cargo.fits({ slots = 128, kg = 2500 }, goods.get('parts'))
  T.eq(units, 128, 'parts fill a Cargo box XL')
end

-- The job board: take a job in Penrith, the GPS goes to the drop-off, drive there, get paid in full.
do
  local c, io, a, g, w = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 50000 end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local v = c:view()
  T.eq(v.here.name, 'Penrith', 'in Penrith'); T.check(v.town.stopped, 'stopped')
  T.eq(v.region.name, 'Australia', 'the region is named'); T.near(v.region.boost, 1, 1e-9, 'flat Sydney roads add nothing')
  T.eq(v.space.slots, 4, 'the box gives 4 slots')
  T.eq(#v.nearby, 6, 'nearby list shows 6 places'); T.check(v.nearby[1].distanceMetres > 5000, 'distances are road estimates')
  T.eq(#v.nearby[1].dots, 4, 'a dot per good: parts, bricks, water and fuel')
  T.eq(#v.town.jobs, 5, 'the board lists parts, bricks, a fluid, the off-road drop and a dangerous contract')
  T.eq(v.town.jobs[1].goodId, 'parts', 'parts first'); T.eq(v.town.jobs[2].goodId, 'bricks', 'then bricks')
  T.eq(v.town.jobs[3].goodId, jobs.fluid(penrith).id, 'then the town fluid'); T.check(v.town.jobs[4].drop, 'then the drop')
  T.check(v.town.jobs[5].contract ~= nil, 'then the dangerous contract')
  T.check(v.town.jobs[3].fluid and v.town.jobs[3].units == 0 and not v.town.jobs[3].allowed, 'a fluid needs a tank')
  for _, j in ipairs(v.town.jobs) do
    -- A brick (150 kg) is too heavy for one box M (130 kg).
    if j.goodId == 'bricks' then T.check(j.units == 0 and not j.allowed, j.id .. ' does not fit one box M')
    elseif not j.fluid then T.check(j.pay > 0 and j.allowed, j.id .. ' pays and can be taken') end
    T.check(j.distanceMetres <= 20000 + 1e-6, j.id .. ' within 20 km')
  end
  T.check(v.bestJob ~= nil and v.bestJob.from == 'Penrith', 'the best job is suggested')
  local id = F.offer(c, stClair, 'food')
  local job = c:board(penrith)[1]
  local pay = jobs.quote(job, 2, c.needs, 50000).pay
  T.eq(c:view().town.jobs[1].pay, pay, 'the board shows one total pay for the car')
  T.eq(c:view().town.jobs[1].units, 2, 'food fills the box: 2 units of 2 slots')
  local before = c:view().balance
  T.check(c:takeJob(id), 'job taken')
  T.eq(c:view().balance, before, 'nothing to pay')
  T.eq(c.load.units, 2, 'filled the box'); T.eq(c.load.kg, 100, 'real weight'); T.eq(c.load.pay, pay, 'pay locked in')
  T.eq(a.gps[1].name, 'St Clair', 'GPS set to the drop-off'); T.near(a.gps[1].latitude, stClair.latitude, 1e-9, 'at its coordinates')
  T.eq(w.weights[#w.weights].kg, 100, 'weight put on the car')
  T.eq(w.weights[#w.weights].parts[1], 'pickup_cargo_load_box_m', 'on the box')
  T.check(not c:takeJob(c:view().town.jobs[2].id), 'one job at a time')
  T.check(not c:view().town.jobs[2].allowed, 'the board says so')
  T.check(not c:deliver(), 'not delivered in Penrith'); T.check(c:view().tradeFeedback:find('St Clair'), 'told where it goes')
  T.eq(c:view().load.to, 'St Clair', 'HUD shows the drop-off'); T.eq(c:view().load.pay, pay, 'and the pay')
  -- A shortage there would not change the pay now.
  c.now = function() return 50100 end
  F.drive(c, a, stClair)
  v = c:view()
  T.eq(v.here.name, 'St Clair', 'arrived at St Clair')
  T.check(v.load.drivenKm > 9, 'distance driven with the job counted')
  T.eq(v.town.delivery.pay, pay, 'the pay shown'); T.check(v.town.delivery.allowed, 'delivery allowed')
  local need = jobs.need(stClair, goods.get('food'), c.needs, 50100)
  T.check(c:deliver(), 'delivered')
  T.eq(c:view().balance, before + pay, 'paid in full')
  T.eq(c.load, nil, 'job done'); T.eq(w.weights[#w.weights].kg, 0, 'weight taken off')
  T.check(c:view().flash.title:find('DELIVERED'), 'delivery shown')
  T.eq(c.profile.progression.jobsDone, 1, 'one job done')
  T.check(jobs.need(stClair, goods.get('food'), c.needs, 50100) < need, 'St Clair wants food a little less')
  T.check(c:manualSave(), 'saved after the run')
  T.eq(io.files[A].progression.jobsDone, 1, 'jobs done saved'); T.eq(io.files[A].needs[1].place, stClair.id, 'the delivery saved')
  local r = F.controller({ io = io })
  T.near(jobs.need(stClair, goods.get('food'), r.needs, 50100), jobs.need(stClair, goods.get('food'), c.needs, 50100), 1e-9, 'and loaded')
end

-- Jobs need the car stopped in a town, fit the car, and must be driven.
do
  local c, _, a = F.controller()
  c:tick(0.1)
  local id = F.offer(c, stClair, 'food')
  T.check(not c:takeJob(id), 'not before the car has stopped')
  c:tick(0.6); c:tick(0.6)
  T.check(not c:takeJob('food_nowhere'), 'not a job that is not on the board')
  local bricks = F.offer(c, stClair, 'bricks')
  T.check(not c:takeJob(bricks), 'bricks do not fit the boot')
  T.check(c:view().tradeFeedback:find('3 slots'), 'told how much room bricks need')
  T.check(not c:view().town.jobs[1].allowed, 'the board greys it out')
  T.check(c:takeJob(id), 'food fits the boot'); T.eq(c.load.units, 1, 'one unit of food')
  -- A short hop (under 2 km) keeps the job but is not driving.
  a.pose = location.destination(F.PENRITH, 90, 1500); c:tick(0.1)
  T.check(c.load ~= nil, 'short hop keeps the job'); T.eq(c.load.drivenKm, 0, 'and does not count')
  local balance = c:view().balance
  c.load.drivenKm = 1; a.pose = F.copy(stClair); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.load == nil, 'a long teleport cancels the job')
  T.eq(c:view().balance, balance - jobs.ABANDON_FEE, 'for the abandon fee')
  T.eq(c:view().flash.kind, 'cancelled', 'player told the job was lost')
  T.check(c:view().stranded ~= nil, 'an unbooked teleport strands the player')
  T.check(c:tradeProblem(c:here()):find('without booking a relocation'), 'and stops jobs')
  -- Teleporting back to where they left from frees them.
  a.pose = location.destination(F.PENRITH, 90, 1500); c:tick(0.1)
  T.eq(c.stranded, nil, 'back where they left from'); T.eq(c:view().flash.title, 'BACK ON THE ROAD', 'told so')
  a.pose = F.copy(stClair); c.stranded = nil; c.odometer:reset(); c.lastDriven = nil; c:tick(0.1); c:tick(0.6); c:tick(0.6)
  -- A job not driven far enough does not deliver.
  local back = F.offer(c, penrith, 'parts')
  T.check(c:takeJob(back), 'job to Penrith'); a.pose = F.copy(F.PENRITH); c.odometer:reset(); c.lastDriven = nil
  c:tick(0.1); c:tick(0.6); c:tick(0.6); c.load.drivenKm = 2
  T.check(not c:deliver(), 'not driven far enough'); T.check(c:view().town.delivery.problem:find('Drive it here'), 'told to drive')
  c.load.drivenKm = 9; T.check(c:deliver(), 'delivers once driven')
  -- Abandoning asks first, then costs $1,000, or all the money when there is less.
  c:takeJob(F.offer(c, stClair, 'parts'))
  balance = c:view().balance
  T.check(not c:abandonJob(), 'abandon asks first'); T.check(c:view().abandonArmed, 'armed')
  T.check(c:abandonJob(), 'abandoned'); T.eq(c.load, nil, 'job gone')
  T.eq(c:view().balance, balance - 1000, 'it cost $1,000')
  c:takeJob(F.offer(c, stClair, 'parts')); c.profile.progression.balance = 400
  c:abandonJob(); T.check(c:abandonJob(), 'abandoned with little money'); T.eq(c:view().balance, 0, 'took what there was')
end

-- Rough driving damages the car, never the cargo: a delivery pays in full.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:takeJob(F.offer(c, stClair, 'parts'))
  local pay = c.load.pay
  g.damage = 600; c:tick(0.1); g.damage = 5000; c:tick(0.1)
  F.drive(c, a, stClair)
  T.eq(c:view().town.delivery.pay, pay, 'paid in full after damage')
  T.eq(c:view().insurance, nil, 'no insurance for a dent')
  T.check(c:deliver(), 'delivered')
end

-- Saves keep the job; an unknown good is dropped; cargo bought before the job board is refunded.
do
  local c, io = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:takeJob(F.offer(c, stClair, 'food'))
  T.check(c:manualSave(), 'saved with a job'); T.eq(io.files[A].load.good, 'food', 'job saved'); T.check(io.files[A].load.pay > 0, 'with its pay')
  local r = F.controller({ io = io })
  T.eq(r.load.good, 'food', 'job restored'); T.eq(r.load.to, stClair.id, 'with its drop-off'); T.eq(r.load.pay, c.load.pay, 'and its pay')
  io.files[A].load.good = 'unobtainium'
  r = F.controller({ io = io })
  T.eq(r.load, nil, 'unknown good dropped')
  local bad = F.copy(io.files[A]); bad.load = { good = 'food', slots = 0, pay = 1, from = 'x' }
  T.eq(P.validate(bad), nil, 'a job with no slots is refused')
  bad.load = { good = 'food', slots = 1, from = 'x' }
  T.eq(P.validate(bad), nil, 'a job with no pay is refused')
  bad.load = { good = 'food', slots = 1, paid = 1, from = 'x', condition = 0.4 }
  T.check(P.validate(bad) ~= nil, 'an old save with a cargo condition still loads')
  T.eq(P.validate(bad).load.condition, nil, 'and the condition is dropped')
  -- An old save with bought cargo on board: the cargo is taken off and its money given back.
  local old = F.copy(io.files[A])
  old.load = { good = 'food', slots = 2, kg = 16, paid = 120, from = penrith.id, to = stClair.id, drivenKm = 1 }
  old.progression.balance = 500
  local o = F.controller({ io = F.io({ [F.CONFIG] = F.config(), [A] = old }) })
  T.eq(o.load, nil, 'the bought cargo is taken off')
  T.eq(o:view().balance, 620, 'its money is refunded'); T.eq(o:view().unsavedBalance, 120, 'and Save keeps it')
  local oa = F.adapter(F.copy(old.resume)); o.adapter = oa; o:tick(0.1)
  T.check(o:view().flash.text:find('refunded', 1, true), 'the player is told')
end

-- Insurance after a serious crash: the car back on the road and fixed for $1,000, the job lost.
do
  local c, io, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:takeJob(F.offer(c, stClair, 'food'))
  g.damage = 14000; c:tick(0.1)
  T.eq(c:view().insurance, nil, 'not for a moderate crash')
  T.check(not c:claimInsurance(), 'refused')
  g.damage = 20000; c:tick(0.1)
  local ins = c:view().insurance
  T.check(ins ~= nil and ins.allowed, 'offered after a serious crash'); T.eq(ins.fee, 1000, 'for $1,000')
  T.check(ins.loseJob, 'the job would be lost'); T.check(ins.repair > 0, 'the repair is shown to compare')
  local balance = c:view().balance
  T.check(not c:claimInsurance(), 'asks first'); T.check(c:view().insurance.armed, 'armed')
  T.check(c:claimInsurance(), 'claimed'); T.eq(g.roadTrips, 1, 'the car is sent back to the road')
  T.check(c:view().insurance.pending, 'towing'); T.eq(g.repairs, 0, 'fixed once it lands')
  -- The move back to the road is a jump, but not a teleport.
  a.pose = location.destination(F.PENRITH, 0, 3000); c:tick(0.5); c:tick(0.5); c:tick(0.6)
  T.eq(g.repairs, 1, 'fixed'); T.eq(c.stranded, nil, 'not stranded')
  T.eq(c:view().balance, balance - 1000, 'charged $1,000'); T.eq(c.load, nil, 'the job is lost')
  T.eq(c:view().flash.title, 'INSURANCE CLAIMED', 'told so')
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c:view().insurance, nil, 'no more offer once fixed')
  -- Where the game cannot find a road the car is fixed where it is, and a short balance is all taken.
  g.noRoad = true; g.damage = 40000; c.profile.progression.balance = 300; c:tick(0.1)
  c:claimInsurance(); T.check(c:claimInsurance(), 'claimed again')
  T.eq(g.repairs, 2, 'fixed straight away'); T.eq(c:view().balance, 0, 'took what there was')
  -- The normal repair keeps the job.
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 50000
  a.pose = F.copy(F.PENRITH); c.odometer:reset(); c.lastDriven = nil; c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a new job')
  g.damage = 30000; c:tick(0.1)
  c:requestRepairQuote(); T.check(c:repairVehicle(), 'repaired instead'); T.check(c.load ~= nil, 'the job is kept')
end

-- Insert, or the game's recovery, puts the car back as new: the repair it needed is still owed,
-- a serious crash still offers insurance, and the fuel and the load's weight are put back.
do
  local c, io, a, g, cargo, f = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a job')
  c:fuelReading(1, 12, 50)
  g.damage = 30000; c:tick(0.1)
  local owed = c:view().insurance.repair
  T.check(owed > 0, 'a serious crash')
  local weights = #cargo.weights
  c:vehicleReset(1); g.damage = 0; c:tick(0.1); c:tick(0.1)
  T.eq(c.owedDamage, 30000, 'the damage is still owed')
  T.eq(c:view().repairOwed, owed, 'shown as repair still owed')
  T.eq(c:view().flash.title, 'REPAIR STILL OWED', 'told so')
  T.check(c:view().insurance ~= nil, 'insurance still offered'); T.eq(c:view().insurance.repair, owed, 'for the same repair')
  T.near(f.sets[#f.sets].litres, 12, 1e-9, 'the fuel it had is put back')
  T.eq(#cargo.weights, weights + 1, 'the load weight is put back on')
  -- A second crash and reset adds to it; a repair pays the lot.
  g.damage = 1000; c:tick(0.1); c:vehicleReset(1); g.damage = 0; c:tick(0.1)
  T.eq(c.owedDamage, 31000, 'both crashes owed')
  c.profile.progression.balance = 100000; c:requestRepairQuote()
  T.eq(c.quote.cost, require('earthFreight/pricing').repairCost(31000, c:carValueOf(1)), 'the quote covers both')
  T.check(c:repairVehicle(), 'repaired'); T.eq(c.owedDamage, 0, 'nothing owed')
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c.owedDamage, 0, 'our own respawn is not a reset')
  -- A reset with no damage owes nothing; one saved keeps it.
  c:vehicleReset(1); c:tick(0.1); T.eq(c.owedDamage, 0, 'nothing to owe')
  g.damage = 4000; c:tick(0.1); g.damage = 0; c:tick(0.1)
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].vehicle.damage, 4000, 'saved as owed')
  -- The game reloading the car with the same parts mends it too; the repair is still owed.
  g.damage = 2000; c:tick(0.1); g.damage = 0; c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(c.owedDamage, 6000, 'a reload is not a free repair')
  -- So does undoing part changes in the parts menu.
  c:abandonJob(); c:addMoney(10000)
  g.damage = 1000; c:tick(0.1); g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.pendingParts.damage, 7000, 'the bill holds the repair')
  g.damage = 500; c:tick(0.1); c:vehicleReset(1); g.damage = 0; c:tick(0.1)
  g:fit('turbo', nil); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.pendingParts, nil, 'changes undone'); T.eq(c.owedDamage, 7500, 'the repair and the later crash are still owed')
  -- Paying a parts bill pays the repair in it, not a crash reset since.
  g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  g.damage = 800; c:tick(0.1); c:vehicleReset(1); g.damage = 0; c:tick(0.1)
  T.check(c:buyParts(), 'parts paid'); T.eq(c.owedDamage, 800, 'the later crash is still owed')
end

-- Fuel: read from the car, Refuel fills it in a town, charged for what went in.
do
  local c, io, a, g, _, f = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(f.reads > 0, 'the car is asked for its fuel')
  T.check(not c:view().town.refuelAllowed, 'no Refuel without a reading')
  c:fuelReading(1, 20, 50); c:tick(0.1)
  local quote = c:view().town.refuel
  T.near(quote.litres, 30, 1e-9, 'fills the tank'); T.eq(quote.cost, fuel.cost(30), 'priced per litre')
  T.check(c:view().town.refuelAllowed, 'Refuel offered in town')
  T.check(c:refuel(), 'refuel sent'); T.near(f.sets[1].litres, 50, 1e-9, 'tank set to full')
  T.check(not c:refuel(), 'one refuel at a time'); T.eq(c:view().fuelFeedback, 'Refuelling...', 'told on the Garage tab')
  local before = c:view().balance
  c:fuelSet(1, f.sets[1].serial, 20, 50, 50)
  T.eq(c:view().balance, before - fuel.cost(30), 'charged for 30 L')
  T.check(c:view().fuelFeedback:find('Refuelled 30.0 L'), 'told what it cost'); T.eq(c:view().tradeFeedback, nil, 'not on the Town tab')
  T.check(c:view().town.refuel.full, 'tank now full'); T.check(not c:view().town.refuelAllowed, 'nothing to fill')
  c:fuelSet(1, f.sets[1].serial, 20, 50, 50); T.eq(c:view().balance, before - fuel.cost(30), 'a repeated answer is not charged twice')
  -- Short of money: fills as far as it goes.
  c.profile.progression.balance = 21; c:fuelReading(1, 10, 50)
  T.near(c:view().town.refuel.litres, 10, 1e-9, 'only what the money buys')
  -- Away from a town there is no Refuel.
  a.pose = location.destination(F.PENRITH, 0, 1900); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.eq(c:view().town, nil, 'no town panel out of town'); T.check(not c:refuel(), 'no refuel out of town')
  -- A repair respawns the car with a full tank; the fuel it had is put back, free.
  c.profile.progression.balance = 10000; g.damage = 2000; c:tick(0.1)
  c:fuelReading(1, 12, 50)
  c:requestRepairQuote(); T.check(c:repairVehicle(), 'repaired')
  local sets = #f.sets
  c:vehicleSpawned(); c:tick(0.1); c:tick(0.1)
  T.eq(#f.sets, sets + 1, 'fuel put back after the respawn'); T.near(f.sets[#f.sets].litres, 12, 1e-9, 'as it was')
  T.eq(f.sets[#f.sets].serial, 0, 'a restore is not a refuel')
  local balance = c:view().balance
  c:fuelSet(1, 0, 50, 12, 50); T.eq(c:view().balance, balance, 'a restore is free')
  -- A repair the game refused leaves the fuel readings going.
  g.damage = 2000; c:tick(0.1); c:requestRepairQuote(); g.accepts = false
  T.check(not c:repairVehicle(), 'repair refused'); g.accepts = true
  c:fuelReading(1, 11, 50); T.near(c.fuel.litres, 11, 1e-9, 'readings carry on after a failed repair')
  c:fuelReading(1, 12, 50)
  -- Save keeps the fuel, and the saved car gets it back.
  T.check(c:manualSave(), 'saved'); T.near(io.files[A].vehicle.fuelLitres, 12, 1e-9, 'fuel saved')
  local r, _, ra, rg, _, rf = F.controller({ io = io })
  ra.pose = F.copy(io.files[A].resume); r:tick(0.1)
  T.eq(#rg.spawns, 1, 'saved car given back'); r:vehicleSpawned(); r:tick(0.1); r:tick(0.1)
  T.near(rf.sets[#rf.sets].litres, 12, 1e-9, 'with the fuel it was saved with')
end

-- Saved in a town with fuel: until the car reports its tank, the saved fuel is only waiting to go
-- back in, so the town shows no refuel and the game does not pause.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:fuelReading(1, 12, 50)
  T.check(c:manualSave(), 'saved in town with fuel'); T.near(io.files[A].vehicle.fuelLitres, 12, 1e-9, 'fuel saved')
  local r, _, ra = F.controller({ io = io })
  ra.pose = F.copy(io.files[A].resume); r:tick(0.1); r:tick(0.6); r:tick(0.6)
  local v = r:view()
  T.eq(v.state, 'READY', 'not paused'); T.check(v.town ~= nil, 'back in town')
  T.eq(v.town.refuel, nil, 'no refuel quote before a tank reading')
  r:vehicleSpawned(); r:tick(0.1); r:tick(0.1); r:fuelReading(1, 12, 50)
  T.check(r:view().town.refuel ~= nil, 'a reading brings the refuel quote back')
end

-- The GPS is optional: with Earth's GPS missing, or turned off, the delivery still works.
do
  local a = F.adapter(); a.gpsMissing = true
  local c = F.controller({ adapter = a })
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'job taken without a GPS'); T.check(c:view().tradeFeedback:find('Set the GPS yourself'), 'told to set it')
  local cfg = F.config(); cfg.autoGps = false
  local a2 = F.adapter()
  local c2 = F.controller({ adapter = a2, io = F.io({ [F.CONFIG] = cfg }) })
  c2:tick(0.1); c2:tick(0.6); c2:tick(0.6)
  T.check(c2:takeJob(F.offer(c2, stClair, 'food')), 'job taken with the GPS turned off'); T.eq(#a2.gps, 0, 'GPS left alone')
end

-- Garage: parts bills (copied from Enduro), and a cargo box is a part like any other.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  g:fit('box', 'pickup_cargo_load_box_m'); c:vehicleSpawned(); c:tick(0.1)
  local bill = c:view().partsChange
  T.eq(bill.partsCost, 600, 'box billed at its part value'); T.eq(bill.added[1].name, 'Cargo Load Box M', 'by its name')
  T.eq(c:view().space.slots, 2, 'space stays the boot until it is paid for')
  local food = F.offer(c, stClair, 'food')
  T.check(not c:takeJob(food), 'no jobs with a bill open')
  T.check(c:buyParts(), 'box bought'); T.eq(c:view().space.slots, 4, 'box space now usable')
  c:tick(0.6); c:tick(0.6)
  T.check(c:takeJob(food), 'filled the box'); T.eq(c.load.units, 2, 'two food in the box')
  local full = c.load.pay
  c.load = nil; c.profile.load = nil
  T.check(c:takeJob(F.offer(c, stClair, 'food'), 50), 'half the food'); T.eq(c.load.units, 1, 'one food')
  T.eq(c.load.kg, 50, 'half the weight'); T.eq(c.load.slots, 2, 'half the slots'); T.check(math.abs(c.load.pay - full / 2) <= 5, 'half the pay, to the nearest $10')
  c.load = nil; c.profile.load = nil
  T.check(c:takeJob(F.offer(c, stClair, 'food'), 10), 'a tenth of the food'); T.eq(c.load.units, 1, 'still at least one unit')
  c.load = nil; c.profile.load = nil
  T.check(c:takeJob(food), 'filled the box again')
  g:fit('box', ''); c:vehicleSpawned(); c:tick(0.1)
  T.check(not c:view().buyPartsAllowed, 'cannot keep a change the load no longer fits')
  T.check(not c:buyParts(), 'refused'); T.check(c:view().partsFeedback:find('would not fit'), 'told why')
  T.eq(c:view().partsChange.removed[1].refund, 180, 'the box sold back is shown with its refund')
  T.check(c:revertParts(false), 'reverted')
  -- A car picked in the selector is billed, but not while carrying a load.
  g.vehicleId, g.model, a.vehicle = 2, 'sport', { id = 2, model = 'sport' }; c:tick(0.1)
  T.check(c:view().carChange ~= nil, 'car billed'); T.check(c:view().carChange.oldName ~= nil, 'names the car traded in')
  T.check(c:view().carChange.repair ~= nil, 'shows what its damage took off the trade-in'); T.check(not c:view().buyCarAllowed, 'not with a job on board')
  T.check(not c:buyCar(), 'refused with a job')
  T.eq(Core.STARTER_MODEL, 'burnside', 'starter model')
end

-- Repairs are priced by the car's Value, as in Enduro.
do
  local pricing = require('earthFreight/pricing')
  local diff = pricing.partsDiff({ parts = { a = 'x', b = 'y' }, values = { x = 105, y = 105 } },
    { parts = { a = 'z', b = '' }, values = { z = 100 } })
  T.eq(diff.removed[1].refund + diff.removed[2].refund, 64, 'each refund rounded on its own')
  T.eq(diff.cost, 100 - 64, 'the bill adds up line by line')
  T.eq(pricing.repairCost(1000, 25000), 600, 'moderate damage on a $25,000 car')
  T.eq(pricing.repairCost(1000, 5000), 200, 'a $5,000 car pays a fifth as much per point')
  T.eq(pricing.repairCost(49, 100000), 0, 'a scratch is free')
  T.eq(pricing.dollars(1234567), '$1,234,567', 'dollars formatted')
end

-- New game: asks once, then starts over in Penrith with the starting money.
do
  local c, io = F.controller()
  c:tick(0.1); c:addMoney(10000); T.check(c:manualSave(), 'saved')
  T.check(not c:cancelNewGame(), 'nothing to cancel yet')
  T.check(not c:newGame(), 'asks first'); T.eq(c:view().newGameArmed, true, 'asking')
  T.check(c:cancelNewGame(), 'Keep my game'); T.eq(c:view().newGameArmed, false, 'no longer asking')
  T.check(not c:newGame(), 'asks again after a cancel'); T.check(c:newGame(), 'confirmed')
  T.eq(c:view().startingMoney, Core.STARTING_MONEY, 'the HUD knows the starting money')
  T.eq(c:view().balance, Core.STARTING_MONEY, 'starting money'); T.eq(c.mode, 'start', 'back to the start')
  T.eq(io.files[B].atStart, true, 'saved at the start')
  local v = c:view()
  T.check(v.saveFeedback:find('-33.75000000, 150.70000000', 1, true), 'the new-game message gives the coordinates')
  T.near(v.resume.latitude, -33.75, 1e-9, 'the HUD shows where to go'); T.eq(v.startTown, 'Penrith', 'named')
end

-- New game while still in an upgraded starter car, on the start spot: a fresh starter car replaces
-- it, so the paid-for parts are not carried into the new game.
do
  local c, io, a, g = F.controller()
  g.starter = { engine = 'burnside_engine_i6' }
  a.pose = F.copy(F.PENRITH); c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  c:addMoney(10000); g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  T.check(c:buyParts(), 'turbo paid for'); c:tick(0.1); T.eq(c.ownedParts.parts.turbo, 'pickup_turbo', 'turbo owned')
  T.check(c:manualSave(), 'saved'); c:newGame(); T.check(c:newGame(), 'new game')
  c:tick(0.1)
  T.check(c:view().arrived, 'arrives straight away on the start spot')
  T.eq(c:view().flash.title, 'WELCOME TO PENRITH', 'welcomed')
  T.eq(#g.spawns, 2, 'a fresh starter car is spawned'); T.eq(g.fitted.turbo, nil, 'the turbo is gone')
  c:vehicleSpawned(); c:tick(0.6); c:tick(0.6)
  T.eq(c.ownedParts.parts.turbo, nil, 'the turbo is not owned'); T.eq(c.pendingParts, nil, 'no bill')
  T.eq(c:view().balance, Core.STARTING_MONEY, 'starting money')
  T.eq(c:view().town.problem, nil, 'can trade in Penrith')
end

-- Off the start spot, the card says how far and that driving there counts too.
do
  local c, io, a = F.controller()
  a.pose = F.position(-33.75 + 300 * north, 150.7); c:tick(0.1)
  local v = c:view()
  T.near(v.resumeDistanceMetres, 300, 0.01, 'distance to the spot'); T.eq(v.resumeRadiusMetres, 50, 'how close counts')
  F.drive(c, a, F.PENRITH); T.check(c:view().arrived, 'driving onto the spot arrives')
end

-- Shipping: book with an empty car, teleport to the coordinates, arrive with the booking used up.
do
  local shipping = require('earthFreight/shipping')
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local v = c:view()
  T.eq(#v.shipping.destinations, #shipping.DESTINATIONS, 'destinations listed')
  local coroico = shipping.get('coroico')
  T.eq(v.shipping.destinations[1].here, true, 'Penrith is where you are')
  local fee = shipping.fee(F.PENRITH, coroico)
  T.check(fee > 100 and fee < 500, 'shipping is cheap: ' .. fee)
  c:takeJob(F.offer(c, stClair, 'food'))
  T.check(not c:bookShipping('coroico'), 'not with a job on board'); T.check(c:view().shipping.feedback:find('cargo cannot'), 'told why')
  c.load = nil
  T.check(not c:bookShipping('penrith'), 'not to where you are')
  T.check(not c:bookShipping('nowhere'), 'not to an unknown place')
  local before = c:view().balance
  T.check(c:bookShipping('coroico'), 'booked'); T.eq(c:view().balance, before - fee, 'fee paid')
  T.check(not c:bookShipping('bormio'), 'one booking at a time')
  T.check(not c:view().saveAllowed, 'no Save while a booking is open'); T.check(not c:manualSave(), 'save refused')
  T.check(c:cancelShipping(), 'cancelled'); T.eq(c:view().balance, before, 'refunded')
  T.check(c:bookShipping('coroico'), 'booked again')
  T.eq(c:view().shipping.booking.latitude, coroico.latitude, 'coordinates to paste')
  -- Earth pauses while it teleports; the jump still counts as one.
  a.valid = false; c:tick(0.1)
  a.valid = true; a.pose = location.destination(coroico, 0, 1000); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.eq(c.booking, nil, 'booking used up'); T.eq(c.stranded, nil, 'not stranded')
  T.eq(c:view().flash.title, 'RELOCATED TO COROICO', 'told they arrived')
  T.eq(c:view().region.name, 'Death Road', 'in the Death Road region'); T.check(c:view().region.boost >= 1.85, 'rough roads pay nearly double')
  T.check(c:view().saveAllowed, 'Save works again')
  -- Teleporting on without a booking strands you, and the coordinates to go back are shown.
  a.pose = shipping.get('bormio'); c:tick(0.1); c:tick(0.6)
  local stranded = c:view().stranded
  T.check(stranded ~= nil and location.distance(stranded, coroico) < 1500, 'go back to where you left')
  T.eq(c:view().flash.title, 'RELOCATION NOT BOOKED', 'told why')
  local km = c:view().totalDistanceKm
  a.pose = location.destination(shipping.get('bormio'), 0, 200); c:tick(1)
  T.eq(c:view().totalDistanceKm, km, 'driving does not count while stranded')
  T.check(not c:manualSave(), 'and nothing saves')
  -- Booking shipping from where you are frees you once you land.
  T.check(c:bookShipping('leh'), 'shipping can be booked while stranded')
  a.pose = shipping.get('leh'); c:tick(0.1); c:tick(0.6)
  T.eq(c.stranded, nil, 'shipped on, no longer stranded')
  -- Any town by name, or any coordinates.
  T.check(c:searchShipping('chamonix'), 'a town found by name')
  local found = c:view().shipping.found
  T.check(#found >= 1 and found[1].name:find('Chamonix') ~= nil, 'listed with its fee'); T.check(found[1].fee > 100, 'priced')
  T.check(not c:searchShipping('qqqqzzzz'), 'nothing found'); T.check(c:view().shipping.feedback:find('No town called'), 'told so')
  c:searchShipping('chamonix')
  T.check(c:bookShipping(found[1].id), 'booked to a found town'); T.eq(c.booking.name, found[1].name, 'by its name')
  c:cancelShipping()
  T.check(not c:bookShippingTo(95, 0), 'not past the pole')
  T.check(c:bookShippingTo(-16.3, -67.82), 'booked to coordinates')
  T.check(c.booking.region:find('Death Road') ~= nil, 'named after the nearest place: ' .. c.booking.region)
  a.pose = { latitude = -16.3, longitude = -67.82 }; c:tick(0.1); c:tick(0.6)
  T.eq(c.booking, nil, 'arrived at the coordinates')
end

-- The paid-shipping offer: a town in one of the hardest regions, a new one every 5 minutes; its
-- shipping fee comes back with the first delivery near it, and a Save keeps that.
do
  local shipping = require('earthFreight/shipping')
  local hardest = places.hardest()
  T.check(#hardest > 100, 'hundreds of hard places: ' .. #hardest)
  for _, p in ipairs(hardest) do
    T.check(p.boost >= 2.3 and p.boost <= 3, p.name .. ' pays 2.3x to 3x')
    places.ensure(p)
    local near = places.nearest(p, 1, p.id)[1]
    T.check(near and near.metres * places.ROAD_FACTOR <= 7000, p.name .. ' has a delivery within 7 km')
  end
  T.eq(shipping.offer(1000, hardest), shipping.offer(1199, hardest), 'the same offer within 5 minutes')
  local changed = false
  for w = 1, 5 do if shipping.offer(w * 300, hardest) ~= shipping.offer(0, hardest) then changed = true end end
  T.check(changed, 'and a new one after')
  local _, left = shipping.offer(1000, hardest); T.eq(left, 200, 'seconds until the next')
  local c, io, a, g = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 1000 end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local offer = c:view().shipping.offer
  T.eq(offer.name, shipping.offer(1000, hardest).name, 'the offer is on the HUD'); T.eq(offer.secondsLeft, 200, 'with its time left')
  T.check(offer.boost >= 1.65, 'from the hardest places'); T.check(offer.allowed, 'bookable')
  local before = c:view().balance
  T.check(c:bookOffer(), 'offer booked'); T.eq(c:view().balance, before - offer.fee, 'the fee is paid now')
  T.check(c:view().shipping.booking.offer, 'the booking is the offer')
  c.now = function() return 5000 end -- the offer moves on; the booking still counts
  local target = places.hardest()[1]
  for _, p in ipairs(places.hardest()) do if p.name == offer.name then target = p end end
  a.pose = { latitude = target.latitude, longitude = target.longitude }; c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.eq(c.booking, nil, 'shipped'); T.eq(c.offer.fee, offer.fee, 'the refund is waiting')
  T.check(c:view().flash.text:find('pays back'), 'told how to get it back')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].offer.fee, offer.fee, 'the save keeps it')
  local r = F.controller({ io = io }); T.eq(r.offer.name, offer.name, 'and a reload has it back')
  -- A delivery near the town pays it back.
  local here = c:here()
  T.check(here ~= nil, 'arrived in ' .. offer.name)
  local nearby = places.nearest(here, 1, here.id)[1].place
  T.check(c:takeJob(F.offer(c, nearby, 'food')), 'a job taken')
  c.load.from, c.load.drivenKm = here.id, 1000
  a.pose = { latitude = nearby.latitude, longitude = nearby.longitude }; c.odometer:reset(); c.lastDriven = nil
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local balance = c:view().balance
  local payout = c.load.pay
  T.check(c:deliver(), 'delivered')
  T.eq(c:view().balance, balance + payout + offer.fee, 'the shipping is paid back')
  T.check(c:view().flash.text:find('paid back'), 'told so'); T.eq(c.offer, nil, 'only once')
end

-- The player's name: set on the start page, kept by Save and by New game, used in greetings.
do
  local c, io, a = F.controller()
  a.pose = F.position(-33.9, 151.2); c:tick(0.1)
  T.check(c:setPlayerName('  Sam   Lee '), 'name set'); T.eq(c:view().playerName, 'Sam Lee', 'spaces tidied')
  T.check(c:view().nameUnsaved, 'not saved yet')
  T.check(not c:setPlayerName('Sam"); os.exit() --'), 'quotes refused'); T.eq(c.playerName, 'Sam Lee', 'name unchanged')
  T.check(not c:setPlayerName(('x'):rep(81)), 'too long refused'); T.check(not c:setPlayerName(7), 'not text refused')
  a.pose = F.copy(F.PENRITH); c:tick(0.1)
  T.eq(c:view().flash.title, 'WELCOME TO PENRITH, SAM LEE', 'greeted on arrival')
  T.check(c:manualSave(), 'saved'); T.eq(c:view().saveFeedback, 'Saved, Sam Lee.', 'saved by name')
  T.eq(io.files[A].playerName, 'Sam Lee', 'name in the save'); T.check(not c:view().nameUnsaved, 'name saved')
  local r = F.controller({ io = io })
  T.eq(r:view().playerName, 'Sam Lee', 'name loaded')
  r:newGame(); T.check(r:newGame(), 'new game')
  T.eq(r:view().playerName, 'Sam Lee', 'New game keeps the name'); T.eq(r.mode, 'start', 'at the start again')
  T.check(r:setPlayerName(''), 'cleared'); T.eq(r:view().playerName, nil, 'no name'); T.check(r:view().nameUnsaved, 'clearing is unsaved too')
end


-- The load slider: a straight share of a full load, in whole units and tens of dollars.
do
  T.eq(jobs.SHARE_STEP, 10, 'slider steps of 10%')
  local u, p = jobs.share(6, 2400, 50); T.eq(u, 3, 'half of 6 bricks'); T.eq(p, 1200, 'for half the pay')
  u, p = jobs.share(20, 1700, 70); T.eq(u, 14, '70% of 20 parts'); T.eq(p, 1190, 'for 70% of the pay')
  u, p = jobs.share(6, 2400, 100); T.eq(u, 6, 'all of it'); T.eq(p, 2400, 'for all the pay')
  u, p = jobs.share(1, 500, 10); T.eq(u, 1, 'never less than one unit'); T.eq(p, 500, 'one unit is the whole job')
  u, p = jobs.share(3, 1000, 50); T.eq(u, 2, 'shares round to whole units'); T.eq(p, 670, 'paid for the units taken')
  u, p = jobs.share(0, 0, 50); T.eq(u, 0, 'nothing fits'); T.eq(p, 0, 'nothing paid')
end

-- Fluid jobs: a tank bought in the garage, a load in litres, its weight in the tank.
do
  local c, io, a, g, w = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local fluid = jobs.fluid(penrith)
  local row = c:view().town.jobs[3]
  T.check(row.fluid and row.units == 0, 'no tank: the fluid job cannot be filled')
  local id = F.offer(c, stClair, fluid.id)
  T.check(not c:takeJob(id), 'not without a tank'); T.check(c:view().tradeFeedback:find('needs a fluid tank'), 'told to fit a tank')
  g.values.pickup_cargo_load_fluid_tank_l = 900; g.names.pickup_cargo_load_fluid_tank_l = 'Cargo Load Fluid Tank L'
  g:fit('tank', 'pickup_cargo_load_fluid_tank_l'); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c:view().partsChange.added[1].name, 'Cargo Load Fluid Tank L', 'the tank is billed in the garage')
  T.check(c:buyParts(), 'tank bought'); T.eq(c:view().space.litres, 400, 'the HUD shows 400 L of tank')
  c:tick(0.6); c:tick(0.6)
  T.eq(c:view().town.jobs[1].units, 400 / fluid.litres, 'the offered job fills the tank'); T.check(c:view().town.jobs[1].fluid, 'as a fluid')
  T.eq(c:view().town.jobs[1].litres, 400, 'in litres')
  T.check(c:takeJob(id, 50), 'half a tank'); T.eq(c.load.slots, 200, '200 L'); T.near(c.load.kg, 200 * fluid.kg / fluid.litres, 1e-9, 'its weight')
  T.eq(c:view().load.litres, 200, 'the HUD shows litres')
  T.check(c:view().tradeFeedback:find('200 L of ' .. fluid.name:lower()), 'told in litres')
  T.eq(w.weights[#w.weights].parts[1], 'pickup_cargo_load_fluid_tank_l', 'the weight goes in the tank')
  T.eq(w.weights[#w.weights].fluid.litres, 200, 'poured in as 200 L'); T.near(w.weights[#w.weights].fluid.density, fluid.kg / fluid.litres, 1e-9, 'at its density')
  T.eq(w.weights[#w.weights].fluid.tanks[1], 'pickup_cargo_load_fluid_tank_l', 'into the fitted tank')
  -- The car says how big its tank really is, which replaces the guess.
  T.check(w.tankReads > 0, 'the car is asked how big its tank is')
  local car = c.ownedParts.id
  c:tanksRead(car + 1, 300); T.eq(c:space().litres, 400, 'another car\'s answer is ignored')
  c:tanksRead(car, 0); T.eq(c:space().litres, 400, 'no fluid container: the guess stays')
  c:tanksRead(car, 299.6); T.eq(c:space().litres, 300, 'the real size'); T.eq(c:space().tankKg, 300, 'and its weight limit')
  local reads = w.tankReads; c:tick(fuel.READ_EVERY_SECONDS + 1); T.eq(w.tankReads, reads, 'asked once per car')
  c:beforeRespawn(); T.eq(c:space().litres, 400, 'a respawn asks again')
  g:fit('tank', ''); c:vehicleSpawned(); c:tick(0.1)
  T.check(not c:view().buyPartsAllowed, 'the tank cannot go while it holds the load')
  T.check(c:revertParts(false), 'put back')
end

-- The off-road drop: no GPS, an arrow to a spot about 2 km out, delivered stopped within 100 m.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local job = jobs.dropJob(penrith, 0)
  job.good, job.id, job.jackpot = 'parts', 'drop_parts_' .. penrith.id, nil
  local board = c.board
  c.board = function(self, place) local list = board(self, place); list[#list] = F.copy(job); return list end
  local row = c:view().town.jobs[#c:view().town.jobs]
  T.check(row.drop, 'the board ends with the off-road drop'); T.eq(row.to, 'Off-road drop', 'named so')
  T.eq(row.direction, location.compassPoint(location.bearing(penrith, job.drop)), 'with its direction')
  T.near(row.distanceMetres, location.distance(penrith, job.drop), 1e-6, 'and its distance')
  local gps = #a.gps
  T.check(c:takeJob(job.id), 'drop taken'); T.eq(#a.gps, gps, 'no GPS route')
  T.check(c:view().tradeFeedback:find('Follow the arrow'), 'told to follow the arrow')
  T.near(c.load.drop.latitude, job.drop.latitude, 1e-12, 'the spot is on the load')
  local v = c:view()
  T.eq(v.load.to, 'off-road drop', 'the HUD shows an off-road drop'); T.eq(v.load.destination, nil, 'with no coordinates to copy')
  T.check(not v.load.drop.inZone and not v.load.drop.delivery.allowed, 'not in the drop zone yet')
  T.eq(v.town.delivery, nil, 'nothing to deliver in town')
  T.check(not c:deliver(), 'not delivered in town'); T.check(c:view().tradeFeedback:find('100 m'), 'told to drive to the spot')
  -- Driven there with no GPS, the arrow points the way.
  local half = location.destination(penrith, location.bearing(penrith, job.drop), 1000)
  F.drive(c, a, half)
  T.check(c:view().load.drop.arrow < 1 or c:view().load.drop.arrow > 359, 'the arrow points straight ahead')
  F.drive(c, a, job.drop)
  -- Saved and loaded, the job keeps its spot.
  T.check(c:manualSave(), 'saved'); T.near(io.files[A].load.drop.latitude, job.drop.latitude, 1e-12, 'the spot is in the save')
  local r = F.controller({ io = io })
  T.near(r.load.drop.latitude, c.load.drop.latitude, 1e-12, 'a reload keeps the spot')
  -- Delivered stopped in the zone, once driven.
  c.odometer:reset(); c:tick(0.1)
  T.check(not c:view().load.drop.delivery.allowed, 'not while moving')
  c:tick(0.6); c:tick(0.6)
  local balance, pay, done = c:view().balance, c.load.pay, c.profile.progression.jobsDone or 0
  T.check(c:view().load.drop.inZone and c:view().load.drop.delivery.allowed, 'in the zone and stopped')
  T.check(c:deliver(), 'delivered'); T.eq(c:view().balance, balance + pay, 'paid in full')
  T.eq(c.load, nil, 'job done'); T.eq(c.profile.progression.jobsDone, done + 1, 'the boards move on')
  T.check(c:view().flash.title:find('DELIVERED'), 'told so')
  -- A job not driven does not deliver at the spot.
  local d, d2 = F.controller()
  d:tick(0.1); d:tick(0.6); d:tick(0.6)
  local j2 = jobs.dropJob(penrith, 0); j2.good, j2.id = 'parts', 'drop_parts_' .. penrith.id
  local b2 = d.board
  d.board = function(self, place) local list = b2(self, place); list[#list] = F.copy(j2); return list end
  T.check(d:takeJob(j2.id), 'another drop')
  d2.pose = F.copy(j2.drop); d.odometer:reset(); d.lastDriven = nil; d:tick(0.1); d:tick(0.6); d:tick(0.6)
  T.check(not d:deliver(), 'a lift to the spot does not deliver')
end

-- Dangerous contracts: on every board, relocated to the start for the fee, paid the road's multiple of a 5 km job
-- at the finish once the section is driven. A claim costs $4,000; abandoning before the start pays
-- the relocation back.
local function onContract(c)
  local job = jobs.contractJob(penrith, 0)
  job.good, job.id = 'parts', 'contract_parts_' .. job.contract
  local board = c.board
  c.board = function(self, place) local list = board(self, place); list[#list] = F.copy(job); return list end
  return job, contracts.get(job.contract)
end
do
  local c, io, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 10000
  local job, section = onContract(c)
  local row = c:view().town.jobs[#c:view().town.jobs]
  T.check(row.contract ~= nil and not row.drop, 'the board ends with a dangerous contract'); T.eq(row.to, section.name, 'named for its section')
  T.eq(row.contract.fee, contracts.FEE, 'with its relocation fee'); T.eq(row.contract.pays, section.pay, 'and its pay multiple'); T.eq(row.contract.insurance, 4000, 'and its $4,000 insurance')
  T.eq(row.distanceMetres, 2000, 'about 2 km'); T.check(row.allowed, 'can be taken')
  local q = c:jobQuote(job)
  T.eq(q.pay, math.floor(jobs.basePay(goods.get('parts'), q.units, 5) * section.pay / 10 + 0.5) * 10, 'its multiple of a 5 km job')
  T.eq(c:bestJob(penrith).to ~= section.name, true, 'not suggested as the best job on the Route tab')
  T.check(c:takeJob(job.id, 50), 'taken at half load'); T.eq(c.load.units, math.floor(q.units / 2 + 0.5), 'half the load')
  T.eq(c:view().balance, 10000 - contracts.FEE, 'the relocation is paid')
  T.eq(#a.teleports, 1, 'Earth is asked to teleport'); T.near(a.teleports[1].latitude, section.start.latitude, 1e-12, 'to the start')
  T.eq(a.teleports[1].name, 'Earth Freight: ' .. section.name, 'named for Earth')
  local v = c:view()
  T.check(v.load.contract and not v.load.contract.started, 'the HUD shows the contract, not started')
  T.check(not v.load.drop.delivery.allowed, 'nothing to deliver yet'); T.check(not c:deliver(), 'not delivered in town')
  T.check(c:view().tradeFeedback:find('Teleport to the start'), 'told to go to the start')
  -- Saved before the start, the contract is kept.
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].load.contract, section.id, 'the section is in the save')
  local r = F.controller({ io = io })
  T.eq(r.load.contract, section.id, 'a reload keeps the contract'); T.eq(r.load.started, nil, 'not started')
  -- The teleport lands at the start: no load lost, not stranded, the contract starts.
  a.pose = F.copy(section.start); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.load and c.load.started, 'started at the start'); T.eq(c.stranded, nil, 'not stranded')
  T.check(c:view().flash.title:find('DANGEROUS CONTRACT'), 'told so'); T.eq(c:view().balance, 10000 - contracts.FEE, 'no abandon fee')
  T.near(a.gps[#a.gps].latitude, section.finish.latitude, 1e-12, 'the GPS is set to the finish')
  T.check(c:view().flash.text:find('GPS', 1, true), 'and the player is told')
  T.check(not c:teleportToContract(), 'no more teleport once started')
  -- Driven to the finish and stopped there, it delivers.
  F.drive(c, a, section.finish)
  T.check(c:view().load.drop.inZone and c:view().load.drop.delivery.allowed, 'at the finish and stopped')
  local pay = c.load.pay
  T.check(c:deliver(), 'delivered'); T.eq(c:view().balance, 10000 - contracts.FEE + pay, 'paid in full')
  T.check(c:view().flash.text:find(section.name, 1, true), 'over the section')
  -- A delivered road is not offered again in this game, even after a save and reload.
  T.eq(c.profile.progression.contractsDone[1], section.id, 'the road is marked done')
  c.board = nil
  for seed = 0, 20 do
    local last = jobs.board(penrith, seed, {}, 0, c.profile.progression.contractsDone)
    last = last[#last]
    T.check(last.contract ~= section.id, 'not on the board again (seed ' .. seed .. ')')
  end
  T.check(c:manualSave(), 'saved'); T.eq(io.files[B].progression.contractsDone[1], section.id, 'kept in the save')
  local r2 = F.controller({ io = io })
  T.eq(r2.profile.progression.contractsDone[1], section.id, 'and after a reload')
  -- A lift to the finish does not deliver.
  local d, da = F.controller()
  d:tick(0.1); d:tick(0.6); d:tick(0.6)
  d.profile.progression.balance = 10000
  local j2, s2 = onContract(d)
  T.check(d:takeJob(j2.id), 'another contract')
  da.pose = F.copy(s2.start); d:tick(0.1); d:tick(0.6); d:tick(0.6)
  da.pose = F.copy(s2.finish); d.odometer:reset(); d.lastDriven = nil; d:tick(0.1); d:tick(0.6); d:tick(0.6)
  T.check(not d:deliver(), 'a lift to the finish does not deliver')
end

-- A crash on a dangerous contract: the claim costs $4,000 and the contract is lost.
do
  local c, io, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 10000
  local job, section = onContract(c)
  T.check(c:takeJob(job.id), 'taken')
  a.pose = F.copy(section.start); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  g.damage = 20000; c:tick(0.1)
  T.eq(c:view().insurance.fee, 4000, 'the claim costs $4,000')
  c:claimInsurance(); T.check(c:claimInsurance(), 'claimed')
  a.pose = location.destination(section.start, 0, 50); c:tick(0.5); c:tick(0.5); c:tick(0.6)
  T.eq(c.load, nil, 'the contract is lost'); T.eq(c:view().balance, 10000 - contracts.FEE - 4000, 'charged $4,000')
end

-- Abandoned before the start, the relocation is paid back; not enough money, no contract.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 5000
  local job = onContract(c)
  T.check(c:takeJob(job.id), 'taken')
  c:abandonJob(); T.check(c:view().tradeFeedback:find('paid back'), 'the player is told the relocation comes back')
  T.check(c:abandonJob(), 'abandoned'); T.eq(c:view().balance, 5000 - jobs.ABANDON_FEE, 'only the abandon fee is lost')
  c.profile.progression.balance = 100
  T.check(not c:view().town.jobs[#c:view().town.jobs].allowed, 'the contract needs the relocation fee')
  T.check(not c:takeJob(job.id), 'refused'); T.check(c:view().tradeFeedback:find('relocation'), 'told why')
end

-- With every road delivered, boards carry no dangerous contract; a new game offers them all again.
do
  local done = {}
  for _, sec in ipairs(contracts.LIST) do done[#done + 1] = sec.id end
  local board = jobs.board(penrith, 0, {}, 0, done)
  T.check(board[#board].contract == nil and board[#board].drop ~= nil, 'the board ends with the drop')
  local keep = {}
  for i = 1, #contracts.LIST - 1 do keep[i] = contracts.LIST[i].id end
  for seed = 0, 10 do
    local b = jobs.board(penrith, seed, {}, 0, keep)
    T.eq(b[#b].contract, contracts.LIST[#contracts.LIST].id, 'only the road left is offered')
  end
  local c, io = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.contractsDone = done; T.check(c:manualSave(), 'saved with every road done')
  local n = F.controller({ io = io }); n:tick(0.1); n:tick(0.6); n:tick(0.6)
  n:newGame(); T.check(n:newGame(), 'a new game')
  T.eq(n.profile.progression.contractsDone, nil, 'starts with no roads done')
end

-- Carhuaz's finish is about 50 m from its start: it delivers only after its 1.5 km climb.
do
  local c, io, a = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 10000
  local section = contracts.get('carhuaz')
  T.eq(section.pay, 8, 'Carhuaz pays 8 times'); T.eq(section.driveKm, 1.5, 'and needs 1.5 km driven')
  local job = onContract(c)
  job.contract, job.drop, job.id = section.id, F.copy(section.finish), 'contract_parts_carhuaz'
  local board = c.board
  c.board = function(self, place) local list = board(self, place); list[#list] = F.copy(job); return list end
  T.check(c:takeJob(job.id), 'taken')
  a.pose = F.copy(section.start); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.load and c.load.started, 'started')
  T.check(c:view().load.drop.inZone, 'the start is inside the finish circle')
  T.check(not c:deliver(), 'but it does not deliver from the start')
  T.check(c:view().tradeFeedback:find('1.5 km', 1, true), 'told the 1.5 km it needs')
  c.load.drivenKm = 1.6; c:tick(0.6)
  T.check(c:deliver(), 'delivers once the climb is driven')
end

-- Each checked road pays its own multiple: Death Road 8, Zoji La 4, Sani Pass 3.
do
  T.eq(contracts.get('death_road').pay, 8, 'Death Road pays 8 times'); T.eq(contracts.get('zoji_la').pay, 4, 'Zoji La 4 times')
  T.eq(contracts.get('sani_pass').pay, 3, 'Sani Pass 3 times')
  local job = jobs.contractJob(penrith, 0)
  job.good, job.contract = 'parts', 'sani_pass'
  T.eq(jobs.quote(job, 10, {}, 0).pay, math.floor(jobs.basePay(goods.get('parts'), 10, 5) * 3 / 10 + 0.5) * 10, 'a Sani Pass job pays 3 times')
end

T.done('Earth Freight controller')
