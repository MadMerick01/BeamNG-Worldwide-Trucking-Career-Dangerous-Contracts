local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('earthFreight/persistence')
local Core = require('earthFreight/core')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local market = require('earthFreight/market')
local fuel = require('earthFreight/fuel')
local location = require('earthFreight/location')
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
end

-- Cargo space comes from the cargo boxes fitted; with none it is the boot.
do
  local cargo = require('earthFreight/cargo')
  local boot = cargo.capacity({ parts = { engine = 'x' }, names = {} })
  T.eq(boot.slots, cargo.BOOT.slots, 'no box: boot slots'); T.check(boot.boot, 'marked as the boot')
  local m = cargo.capacity({ parts = { a = 'pickup_cargo_load_box_m', b = 'x' }, names = { pickup_cargo_load_box_m = 'Cargo Load Box M' } })
  T.eq(m.slots, 4, 'box M holds 4 slots'); T.eq(m.kg, 200, 'box M weight limit'); T.eq(m.boxes[1], 'Cargo box M', 'box listed')
  T.eq(cargo.box('van_cargo_load_box_xl').slots, 128, 'XL matched before L')
  T.eq(cargo.box('cargo_load_box_l').slots, 16, 'L')
  T.eq(cargo.box('x', 'Cargo Load Box S').slots, 1, 'matched on the display name')
  T.eq(cargo.box('pickup_bed_cargo_net'), nil, 'a part without a box is not a box')
  T.eq(cargo.box('cargo_load_fluid_tank_xl'), nil, 'tanks are not parcel boxes')
  -- The starter Burnside: a holder in the boot seating five M boxes.
  local starter = cargo.capacity({ parts = {
    burnside_trunk_load = 'burnside_cargo_load_box_5M_trunk',
    a = 'cargo_load_box_M_trunk_A_90deg', b = 'cargo_load_box_M_trunk_B_90deg', c = 'cargo_load_box_M_trunk_C_90deg',
    d = 'cargo_load_box_M_trunk_D_90deg', e = 'cargo_load_box_M_trunk_E' },
    names = { burnside_cargo_load_box_5M_trunk = '5x Cargo Load Box M' } })
  T.eq(#starter.boxes, 5, 'five M boxes, holder not counted')
  T.eq(starter.slots, 20, 'five M boxes of slots')
  local slots, kg = cargo.fits({ slots = 16, kg = 600 }, goods.get('bricks'))
  T.eq(slots, 5, 'bricks run out of weight before space'); T.eq(kg, 600, 'their weight')
  T.near(cargo.damaged(1, 1500, goods.get('parts')), 0.5, 1e-9, 'half the damage for loss halves the load')
  T.eq(cargo.damaged(0.1, 1e9, goods.get('parts')), 0, 'never below ruined')
end

-- The delivery loop: buy parcels in Penrith, the GPS goes to the drop-off, drive there, get paid.
do
  local c, io, a, g, w, f = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local v = c:view()
  T.eq(v.here.name, 'Penrith', 'in Penrith'); T.check(v.town.stopped, 'stopped')
  T.eq(v.region.name, 'Australia', 'the region is named'); T.near(v.region.boost, 1, 1e-9, 'flat Sydney pays 1x')
  T.near(v.town.boost, 1, 1e-9, 'the town shows its boost')
  T.eq(v.space.slots, 4, 'the box gives 4 slots')
  T.eq(#v.nearby, 6, 'nearby list shows 6 places'); T.check(v.nearby[1].distanceMetres > 5000, 'distances are road estimates')
  T.eq(v.town.destinations[1].name, 'Jordan Springs', 'Jordan Springs is the nearest drop-off')
  T.eq(v.town.range.km, 5, 'drop-offs start around 5 km')
  T.check(c:setDeliveryRange(23), 'distance set'); T.eq(c:view().town.range.km, 25, 'rounded to 5 km steps')
  local far = c:view().town.destinations
  T.check(far[1].distanceMetres > 20000 and far[#far].distanceMetres < 30000, 'drop-offs around 25 km')
  c:setDeliveryRange(999); T.eq(c:view().town.range.km, 50, 'at most 50 km')
  T.check(not c:setDeliveryRange('x'), 'odd values refused')
  c:setDeliveryRange(5)
  T.check(v.bestRun ~= nil and v.bestRun.from == 'Penrith', 'a best run is suggested')
  T.check(v.town.buyAllowed, 'buying allowed')
  local parts = goods.get('parts')
  local price = market.price(penrith, parts)
  T.check(c:buy('parts', stClair.id), 'bought a load')
  T.eq(c.load.slots, 4, 'filled the box'); T.eq(c.load.kg, 4 * parts.kgPerSlot, 'real weight')
  T.eq(c:view().balance, Core.STARTING_MONEY - 4 * price, 'paid for the load')
  T.eq(a.gps[1].name, 'St Clair', 'GPS set to the drop-off'); T.near(a.gps[1].latitude, stClair.latitude, 1e-9, 'at its coordinates')
  T.eq(w.weights[#w.weights].kg, 4 * parts.kgPerSlot, 'weight put on the car')
  T.eq(w.weights[#w.weights].parts[1], 'pickup_cargo_load_box_m', 'on the box')
  T.check(not c:buy('food', stClair.id), 'one load at a time')
  T.check(not c:sell(), 'cannot sell where it was bought')
  T.check(c:view().town.sale.problem:find('somewhere else'), 'told why')
  T.eq(c:view().load.to, 'St Clair', 'HUD shows the drop-off')
  -- Moving makes trading wait until the car stops.
  F.drive(c, a, stClair)
  v = c:view()
  T.eq(v.here.name, 'St Clair', 'arrived at St Clair')
  T.check(v.load.drivenKm > 9, 'distance driven with the load counted')
  local payout = market.payout(stClair, parts, 4, 1, penrith)
  T.eq(v.town.sale.payout, payout, 'payout quoted'); T.check(v.town.sellAllowed, 'sell allowed')
  T.check(c:sell(), 'delivered')
  T.eq(c:view().balance, Core.STARTING_MONEY - 4 * price + payout, 'paid on delivery')
  T.eq(c.load, nil, 'load gone'); T.eq(w.weights[#w.weights].kg, 0, 'weight taken off')
  T.check(c:view().flash.title:find('DELIVERED'), 'delivery shown')
  T.check(c:manualSave(), 'saved after the run')
end

-- Trading needs the car stopped in a place, and a delivery must be driven.
do
  local c, _, a = F.controller()
  c:tick(0.1)
  T.check(not c:buy('parts', stClair.id), 'not before the car has stopped')
  c:tick(0.6); c:tick(0.6)
  T.check(not c:buy('parts', penrith.id), 'not to the place you are at')
  T.check(not c:buy('grain', stClair.id), 'not bulk goods yet')
  T.check(not c:buy('nope', stClair.id), 'not an unknown good')
  -- Buying a chosen number of slots.
  local food = goods.get('food')
  T.check(not c:buy('food', stClair.id, 3), 'not more than fits in the boot')
  T.check(c:view().tradeFeedback:find('Only room for 2'), 'told how many fit')
  local before = c:view().balance
  T.check(c:buy('food', stClair.id, 1), 'one parcel bought')
  T.eq(c.load.slots, 1, 'one slot'); T.eq(c.load.kg, food.kgPerSlot, 'one slot of weight')
  T.eq(c:view().balance, before - market.price(penrith, food), 'paid for one')
  c.load = nil
  c.profile.progression.balance = market.price(penrith, food)
  T.check(not c:buy('food', stClair.id, 2), 'not more than the money covers')
  T.check(c:view().tradeFeedback:find('Not enough money'), 'told it is the money')
  T.eq(c:view().balance, market.price(penrith, food), 'nothing spent')
  c.profile.progression.balance = before
  T.check(c:buy('food', stClair.id), 'food bought for the boot')
  -- A short hop (under 2 km) keeps the load but is not driving.
  a.pose = location.destination(F.PENRITH, 90, 1500); c:tick(0.1)
  T.check(c.load ~= nil, 'short hop keeps the load'); T.eq(c.load.drivenKm, 0, 'and does not count')
  c.load.drivenKm = 1; a.pose = F.copy(stClair); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.load == nil, 'a long teleport cancels the load')
  T.eq(c:view().flash.kind, 'cancelled', 'player told the load was lost')
  T.check(c:view().stranded ~= nil, 'an unbooked teleport strands the player')
  T.check(c:tradeProblem(c:here()):find('without booking shipping'), 'and stops trading')
  -- Teleporting back to where they left from frees them.
  a.pose = location.destination(F.PENRITH, 90, 1500); c:tick(0.1)
  T.eq(c.stranded, nil, 'back where they left from'); T.eq(c:view().flash.title, 'BACK ON THE ROAD', 'told so')
  a.pose = F.copy(stClair); c.stranded = nil; c.odometer:reset(); c.lastDriven = nil; c:tick(0.1); c:tick(0.6); c:tick(0.6)
  -- A load not driven far enough does not sell.
  c:buy('food', penrith.id); c.load.from = penrith.id; c.load.drivenKm = 2
  T.check(not c:sell(), 'not driven far enough'); T.check(c:view().town.sale.problem:find('Drive it here'), 'told to drive')
  c.load.drivenKm = 9; T.check(c:sell(), 'sells once driven')
  T.check(c:buy('food', penrith.id), 'bought again')
  T.check(not c:dumpLoad(), 'dump asks first'); T.check(c:view().dumpArmed, 'armed')
  T.check(c:dumpLoad(), 'dumped'); T.eq(c.load, nil, 'load gone')
end

-- Rough driving damages the cargo and cuts the payout.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:buy('parts', stClair.id)
  g.damage = 600; c:tick(0.1); g.damage = 1500; c:tick(0.1)
  T.near(c.load.condition, 1 - 1500 / goods.get('parts').damageForLoss, 1e-9, 'damage taken counts against the load')
  g.damage = 0; c:vehicleSpawned(); c:tick(0.1); g.damage = 100; c:tick(0.1)
  T.near(c.load.condition, 1 - 1600 / goods.get('parts').damageForLoss, 1e-9, 'a repair resets the reading, not the load')
  local condition = c.load.condition
  F.drive(c, a, stClair)
  T.eq(c:view().town.sale.payout, market.payout(stClair, goods.get('parts'), c.load.slots, condition, penrith), 'payout cut by damage')
end

-- Saves keep the load, and an unknown good in a save is dropped.
do
  local c, io = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:buy('food', stClair.id)
  T.check(c:manualSave(), 'saved with a load'); T.eq(io.files[A].load.good, 'food', 'load saved')
  local r = F.controller({ io = io })
  T.eq(r.load.good, 'food', 'load restored'); T.eq(r.load.to, stClair.id, 'with its drop-off')
  io.files[A].load.good = 'unobtainium'
  r = F.controller({ io = io })
  T.eq(r.load, nil, 'unknown good dropped')
  local bad = F.copy(io.files[A]); bad.load = { good = 'food', slots = 0, paid = 1, from = 'x', condition = 1 }
  T.eq(P.validate(bad), nil, 'a load with no slots is refused')
  bad.load = { good = 'food', slots = 1, paid = 1, from = 'x', condition = 2 }
  T.eq(P.validate(bad), nil, 'a condition over 1 is refused')
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
  T.check(not c:refuel(), 'one refuel at a time')
  local before = c:view().balance
  c:fuelSet(1, f.sets[1].serial, 20, 50, 50)
  T.eq(c:view().balance, before - fuel.cost(30), 'charged for 30 L')
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

-- The GPS is optional: with Earth's GPS missing, or turned off, the delivery still works.
do
  local a = F.adapter(); a.gpsMissing = true
  local c = F.controller({ adapter = a })
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c:buy('food', stClair.id), 'bought without a GPS'); T.check(c:view().tradeFeedback:find('Set the GPS yourself'), 'told to set it')
  local cfg = F.config(); cfg.autoGps = false
  local a2 = F.adapter()
  local c2 = F.controller({ adapter = a2, io = F.io({ [F.CONFIG] = cfg }) })
  c2:tick(0.1); c2:tick(0.6); c2:tick(0.6)
  T.check(c2:buy('food', stClair.id), 'bought with the GPS turned off'); T.eq(#a2.gps, 0, 'GPS left alone')
end

-- Garage: parts bills (copied from Enduro), and a cargo box is a part like any other.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  g:fit('box', 'pickup_cargo_load_box_m'); c:vehicleSpawned(); c:tick(0.1)
  local bill = c:view().partsChange
  T.eq(bill.partsCost, 600, 'box billed at its part value'); T.eq(bill.added[1].name, 'Cargo Load Box M', 'by its name')
  T.eq(c:view().space.slots, 2, 'space stays the boot until it is paid for')
  T.check(not c:buy('food', stClair.id), 'no trading with a bill open')
  T.check(c:buyParts(), 'box bought'); T.eq(c:view().space.slots, 4, 'box space now usable')
  c:tick(0.6); c:tick(0.6)
  T.check(c:buy('parts', stClair.id), 'loaded the box')
  g:fit('box', ''); c:vehicleSpawned(); c:tick(0.1)
  T.check(not c:view().buyPartsAllowed, 'cannot keep a change the load no longer fits')
  T.check(not c:buyParts(), 'refused'); T.check(c:view().partsFeedback:find('would not fit'), 'told why')
  T.check(c:revertParts(false), 'reverted')
  -- A car picked in the selector is billed, but not while carrying a load.
  g.vehicleId, g.model, a.vehicle = 2, 'sport', { id = 2, model = 'sport' }; c:tick(0.1)
  T.check(c:view().carChange ~= nil, 'car billed'); T.check(not c:view().buyCarAllowed, 'not with a load on board')
  T.check(not c:buyCar(), 'refused with a load')
  T.eq(Core.STARTER_MODEL, 'burnside', 'starter model')
end

-- Repairs are priced by the car's Value, as in Enduro.
do
  local pricing = require('earthFreight/pricing')
  T.eq(pricing.repairCost(1000, 25000), 600, 'moderate damage on a $25,000 car')
  T.eq(pricing.repairCost(1000, 5000), 200, 'a $5,000 car pays a fifth as much per point')
  T.eq(pricing.repairCost(49, 100000), 0, 'a scratch is free')
  T.eq(pricing.dollars(1234567), '$1,234,567', 'dollars formatted')
end

-- New game: asks once, then starts over in Penrith with the starting money.
do
  local c, io = F.controller()
  c:tick(0.1); c:addTestMoney(); T.check(c:manualSave(), 'saved')
  T.check(not c:newGame(), 'asks first'); T.check(c:newGame(), 'confirmed')
  T.eq(c:view().balance, Core.STARTING_MONEY, 'starting money'); T.eq(c.mode, 'start', 'back to the start')
  T.eq(io.files[B].atStart, true, 'saved at the start')
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
  c:buy('food', stClair.id)
  T.check(not c:bookShipping('coroico'), 'not with a load on board'); T.check(c:view().shipping.feedback:find('cargo cannot'), 'told why')
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
  T.eq(c:view().flash.title, 'SHIPPED TO COROICO', 'told they arrived')
  T.eq(c:view().region.name, 'Death Road', 'in the Death Road region'); T.check(c:view().region.boost >= 2.7, 'paying near 3x')
  T.check(c:view().saveAllowed, 'Save works again')
  -- Teleporting on without a booking strands you, and the coordinates to go back are shown.
  a.pose = shipping.get('bormio'); c:tick(0.1); c:tick(0.6)
  local stranded = c:view().stranded
  T.check(stranded ~= nil and location.distance(stranded, coroico) < 1500, 'go back to where you left')
  T.eq(c:view().flash.title, 'SHIPPING NOT BOOKED', 'told why')
  local km = c:view().totalDistanceKm
  a.pose = location.destination(shipping.get('bormio'), 0, 200); c:tick(1)
  T.eq(c:view().totalDistanceKm, km, 'driving does not count while stranded')
  T.check(not c:manualSave(), 'and nothing saves')
  -- Booking shipping from where you are frees you once you land.
  T.check(c:bookShipping('leh'), 'shipping can be booked while stranded')
  a.pose = shipping.get('leh'); c:tick(0.1); c:tick(0.6)
  T.eq(c.stranded, nil, 'shipped on, no longer stranded')
end

T.done('Earth Freight controller')
