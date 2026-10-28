local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local heli = require('earthFreight/heli')
local aircraft = require('earthFreight/aircraft')
local places = require('earthFreight/places')
local location = require('earthFreight/location')

-- Pay: $3 a kg, in full from 10 km, never more than $3,000.
T.eq(heli.pay(1000, 25), 3000, '1,000 kg pays $3,000')
T.eq(heli.pay(1000, 400), 3000, 'however far it goes')
T.eq(heli.pay(1500, 25), 3000, 'more than the hook takes pays no more')
T.eq(heli.pay(500, 12), 1500, '500 kg pays $1,500')
T.eq(heli.pay(1000, 5), 1500, 'half pay at 5 km')
T.eq(heli.pay(0, 10), 0, 'nothing for nothing')
T.eq(heli.pay(1000, 0 / 0), 0, 'a broken distance pays nothing')
T.check(heli.MAX_PAY - heli.HIRE_FEE <= 2000, 'a hire never makes more than $2,000 on one load')

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
T.eq(heli.findLoad({ { model = 'woodcrate', key = 'a' }, { model = 'boxutility', key = 'b' } }).model, 'boxutility', 'a trailer first')
T.eq(heli.findLoad({ list[1] }), nil, 'nothing to carry without one')

-- A flight: a town 4 to 40 km away, a weight the hook takes, and its pay.
do
  local penrith = F.copy(F.PENRITH)
  places.ensure(penrith)
  local seen = {}
  for i = 1, 40 do
    local n = 0
    local f = heli.flight(penrith, function(count) n = n + 1; return ((i * 7 + n * 3) % count) + 1 end)
    T.check(f.km >= heli.MIN_KM and f.km <= heli.MAX_KM, 'drop-off within reach ' .. f.km)
    T.check(f.kg > 0 and f.kg <= heli.MAX_KG, 'a weight the hook takes')
    T.eq(f.pay, heli.pay(f.kg, f.km), 'paid by the rules')
    T.check(f.to.id ~= nil, 'a town')
    seen[f.to.id] = true
  end
  local towns = 0
  for _ in pairs(seen) do towns = towns + 1 end
  T.check(towns > 5, 'many different towns')
  -- Out at sea there are no towns: a spot in open country, named by its direction.
  local f = heli.flight({ latitude = -40, longitude = -140 }, function() return 1 end)
  T.check(f.to.id == nil and f.to.name:find('km') ~= nil, 'a named spot ' .. f.to.name)
end

-- The game side: the load goes down on the ground in front of the helicopter, gets its mass, and
-- is taken away; every call is guarded.
do
  local spawned, commands, deleted = {}, {}, 0
  local function vec(x, y, z) return { x = x, y = y, z = z } end
  local load = { getID = function() return 77 end, getPosition = function() return vec(10, 30, 5) end,
    queueLuaCommand = function(_, cmd) commands[#commands + 1] = cmd end, delete = function() deleted = deleted + 1 end }
  local player = { getPosition = function() return vec(10, 5, 105) end, getDirectionVector = function() return vec(0, 2, 0) end,
    getID = function() return 1 end }
  local a = aircraft.new({
    vehicle = function() return player end,
    objectById = function(id) return id == 77 and load or nil end,
    objects = function() return { [77] = { damage = 12 } } end,
    ground = function(_, _, z) return z - 0 end,
    spawn = function(model, options) spawned[#spawned + 1] = { model = model, options = options }; return load end,
    position = vec, rotation = function(x, y) return { x = x, y = y } end,
  })
  local id = a:spawnLoad('boxutility', 'vehicles/boxutility/a.pc', 25)
  T.eq(id, 77, 'the load spawned')
  T.eq(spawned[1].options.pos.y, 30, '25 m in front'); T.eq(spawned[1].options.pos.z, 0.5, 'on the ground')
  T.eq(spawned[1].options.autoEnterVehicle, false, 'the player stays in the helicopter')
  T.eq(a:height(), 105, 'height above the ground')
  T.eq(a:damage(77), 12, 'its damage'); T.eq(a:damage(5), nil, 'none for one that is gone')
  T.eq(a:where(77).y, 30, 'where it is'); T.eq(a:where(5), nil, 'nowhere when gone'); T.eq(a:where().z, 105, 'the player too')
  T.check(a:setMass(77, 550), 'mass sent'); T.check(commands[1]:find('local id, target = 77, 550.0', 1, true) ~= nil, 'for 550 kg')
  T.check(commands[1]:find('earthFreight_core.loadMass(%d, %.1f)', 1, true) ~= nil, 'and reports back')
  T.check(a:remove(77), 'removed'); T.eq(deleted, 1, 'deleted'); T.check(a:remove(5), 'one already gone is fine')
  local broken = aircraft.new({ vehicle = function() error('no') end, objectById = function() error('no') end,
    objects = function() error('no') end, ground = function() error('no') end, spawn = function() error('no') end,
    position = vec, rotation = vec })
  T.eq(broken:spawnLoad('x', 'y', 25), nil, 'no spawn without the game'); T.eq(broken:height(), nil, 'no height')
  T.eq(broken:damage(1), nil, 'no damage'); T.check(not broken:setMass(1, 10), 'no mass')
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
  table.insert(g.configList, { model = 'boxutility', key = 'a', config = 'vehicles/boxutility/a.pc', name = 'Box Utility', value = 3000, type = 'Trailer' })
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
  c:vehicleSpawned()
  F.advance(c, heli.NEXT_LOAD_SECONDS + 0.5)
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
  F.advance(c, heli.NEXT_LOAD_SECONDS + 0.2)
  T.eq(#ac.spawned, 1, 'a load in front of the helicopter'); T.eq(ac.loads[ac.spawned[1]].model, 'boxutility', 'the trailer')
  local load = c:view().heli.hired.load
  T.check(load ~= nil and load.to ~= nil, 'with a drop-off'); T.eq(ac.masses[1].kg, load.kg, 'its mass set')
  T.check(load.status:find('hook', 1, true) ~= nil, 'hook it on')
  -- Flying far does not count as driving, nor as a teleport.
  local km = c.profile.progression.totalDistanceKm
  a.pose = location.destination(F.PENRITH, 90, 30000); c:tick(0.1); c:tick(0.1)
  T.eq(c.stranded, nil, 'not stranded'); T.check(c.load ~= nil, 'the job is not cancelled')
  T.eq(c.profile.progression.totalDistanceKm, km, 'flying does not count')
end

-- Delivering: the load flown to its drop-off and set down still pays; then the next one turns up.
do
  local c, a, g, ac = game()
  hire(c, g)
  local h = c.hire
  local id = h.load.id
  c:loadMass(id, 700.4)
  T.eq(h.load.kg, 700, 'weighs what the load says'); T.eq(h.load.pay, heli.pay(700, h.load.km), 'paid by that weight')
  c:couplerChanged(1, id, true)
  T.check(c:view().heli.hired.load.hooked, 'hooked on')
  -- Fly it there: the helicopter over the drop-off, the load 10 m east of it.
  a.pose = F.copy(h.load.to); ac.player = { x = 0, y = 0, z = 20 }; ac.loads[id].pos = { x = 10, y = 0, z = 0 }
  F.advance(c, 5)
  T.eq(c.hire.load and c.hire.load.id, id, 'not paid while it hangs on the hook')
  T.check(c:view().heli.hired.load.inZone, 'in the drop zone')
  local before = c.profile.progression.balance
  c:couplerChanged(id, 1, false)
  F.advance(c, 1)
  T.eq(c.profile.progression.balance, before, 'not until it rests')
  local pay = h.load.pay
  -- Hanging still in the air, as when the hook lets go unseen, is not set down.
  ac.loads[id].height = 10
  F.advance(c, heli.REST_SECONDS + 1)
  T.eq(c.profile.progression.balance, before, 'not while it is still in the air')
  ac.loads[id].height = 0.8
  F.advance(c, heli.REST_SECONDS)
  T.eq(c.profile.progression.balance, before + pay, 'paid')
  T.eq(c.hire.flights, 1, 'one load flown'); T.eq(c.hire.earned, pay, 'earned')
  T.eq(c:view().flash.title:sub(1, 10), 'DELIVERED:', 'told so'); T.eq(ac.loads[id], nil, 'the load is taken away')
  F.advance(c, heli.NEXT_LOAD_SECONDS + 0.2)
  T.eq(#ac.spawned, 2, 'the next load turns up')
  T.check(c.hire.load.to.id ~= h.lastTo, 'going somewhere else')
end

-- A load that is not flown there, or hits the ground too hard, pays nothing.
do
  local c, a, g, ac = game()
  hire(c, g)
  local h = c.hire
  local before = c.profile.progression.balance
  -- Already at the drop-off when it turns up: it has not been flown, so it does not pay.
  local id = h.load.id
  ac.loads[id].damage = 0
  h.load.pickup, h.load.flown = F.copy(h.load.to), nil
  a.pose = F.copy(h.load.to); ac.player = { x = 0, y = 0, z = 0 }; ac.loads[id].pos = { x = 5, y = 0, z = 0 }
  F.advance(c, heli.REST_SECONDS + 1)
  T.eq(c.profile.progression.balance, before, 'a load that was not flown does not pay')
  ac.loads[id].damage = heli.SMASH_DAMAGE + 1; c:tick(0.1)
  T.eq(c:view().flash.title, 'LOAD LOST', 'smashed'); T.eq(c.hire.load, nil, 'gone'); T.eq(c.profile.progression.balance, before, 'unpaid')
  F.advance(c, heli.NEXT_LOAD_SECONDS + 0.2)
  T.check(c.hire.load ~= nil, 'another one turns up')
end

-- Back to my car near the car: lands, swaps back with the car's fuel, damage and job.
do
  local c, a, g, ac, cargo, f = game()
  local stClair
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then stClair = p end end
  T.check(c:takeJob(F.offer(c, stClair, 'food')), 'a truck job on board')
  g.damage = 2000; c:tick(0.1)
  hire(c, g)
  local loadId = c.hire.load.id
  ac.ground = 30
  T.check(not c:backToCar(), 'asks first'); T.check(c:view().heli.hired.backArmed, 'Confirm shown')
  T.check(not c:backToCar(), 'not while flying over it'); T.check(c.heliFeedback:find('Land first', 1, true) ~= nil, 'land first')
  ac.ground = 0
  c:backToCar(); T.check(c:backToCar(), 'swapping back')
  T.eq(ac.loads[loadId], nil, 'the load is taken away')
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

-- A crash ends the hire: $1,000 insurance, the load and the hire are lost, back in the car.
do
  local c, a, g, ac = game()
  hire(c, g)
  local loadId = c.hire.load.id
  local before = c.profile.progression.balance
  a.pose = location.destination(F.PENRITH, 0, 8000); c:tick(0.1)
  g.damage = heli.CRASH_DAMAGE + 10; c:tick(0.1)
  T.eq(c.profile.progression.balance, before - 1000, '$1,000 insurance')
  T.eq(c:view().flash.title, 'HELICOPTER CRASHED', 'told so'); T.eq(ac.loads[loadId], nil, 'the load is lost')
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

-- A reload while flying: the hire is not saved, and its load is taken away.
do
  local c, a, g, ac = game()
  hire(c, g)
  local loadId = c.hire.load.id
  c:reload()
  T.eq(c.hire, nil, 'no hire after a reload'); T.eq(ac.loads[loadId], nil, 'the load is gone')
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
