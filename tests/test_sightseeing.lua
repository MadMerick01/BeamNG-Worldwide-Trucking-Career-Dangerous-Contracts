local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local flights = require('earthFreight/flights')
local places = require('earthFreight/places')
local location = require('earthFreight/location')

local SIGHT = flights.SIGHTSEEING
T.eq(SIGHT.config, 'vehicles/moonhawk/earth_freight_sightseeing.pc', 'the Moonhawk config shipped with the mod')
do
  local f = io.open('mod/earth_freight/' .. SIGHT.config, 'r')
  T.check(f ~= nil, 'and the file is there'); if f then f:close() end
end

-- The player in their pickup in Penrith, fuel read, settled in.
local function game()
  local c, io, a, g, cargo = F.controller({ aircraft = F.aircraft() })
  g.configParts[SIGHT.config] = { body = 'moonhawk_body' }
  local tick = c.tick
  c.tick = function(self, dt)
    a.vehicle = { id = g.vehicleId, model = g.model }
    return tick(self, dt)
  end
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.profile.progression.balance = 5000
  c:fuelReading(1, 30, 50)
  return c, a, g, io, cargo
end
local function stClair()
  for _, p in ipairs(places.list) do if p.name == 'St Clair' then return p end end
end

-- Go sightseeing: saves, swaps the car for the Moonhawk for free, and the career waits.
do
  local c, a, g, io, cargo = game()
  T.check(c:takeJob(F.offer(c, stClair(), 'food')), 'a job on board')
  local v = c:view().sightseeing
  T.check(v ~= nil and v.allowed, 'Go sightseeing on offer'); T.check(not v.on, 'not sightseeing yet')
  local writes = io.writes
  local weights = #cargo.weights
  T.check(c:goSightseeing(), 'gone sightseeing')
  T.check(io.writes > writes, 'the game was saved first'); T.eq(c.savedBalance, 5000, 'with the money')
  T.check(c.profile.load ~= nil or c.load ~= nil, 'and the job')
  T.eq(g.spawns[#g.spawns].config, SIGHT.config, 'the Moonhawk spawned'); T.eq(g.model, 'moonhawk', 'in place of the car')
  T.eq(c.profile.progression.balance, 5000, 'for free')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(c.hire.stage, 'flying', 'out sightseeing'); T.eq(c:view().flash.title, 'SIGHTSEEING', 'told so')
  T.eq(c.pendingCar, nil, 'no car bill for the Moonhawk'); T.eq(c.ownedParts.model, 'pickup', 'the pickup is still yours')
  T.eq(#cargo.weights, weights, 'the job weight stays with the truck')
  v = c:view().sightseeing
  T.check(v.on and v.returnAllowed, 'the HUD shows sightseeing, with Return to your job')
  T.check(not c:view().saveAllowed, 'no Save while sightseeing')
  T.check(not c:manualSave(), 'Save refuses'); T.check(c.feedback:find('Return to your job', 1, true) ~= nil, 'and says why')
  T.check(c:tradeProblem(c:here()):find('sightseeing', 1, true) ~= nil, 'no jobs while sightseeing')
  T.check(c:shippingProblem() ~= nil, 'no relocation')
  T.check(not c:view().repairQuoteAllowed, 'no repairs')
  T.check(not c:goSightseeing(), 'not twice')
  T.check(c:view().heli.hired == nil, 'the Heli tab does not show it as a hire')
  T.check(not c:view().heli.hireAllowed, 'and no helicopter meanwhile')
  -- Far away through Earth's map: not a teleport, not driving.
  local km = c.profile.progression.totalDistanceKm
  a.pose = location.destination(F.PENRITH, 90, 800000); c:tick(0.1); c:tick(0.1)
  T.eq(c.stranded, nil, 'not stranded'); T.check(c.load ~= nil, 'the job is not cancelled')
  T.eq(c.profile.progression.totalDistanceKm, km, 'sightseeing distance does not count')
  T.near(c:view().sightseeing.car.distanceMetres, 800000, 5000, 'how far away the truck is')
  -- A crash in the Moonhawk costs nothing.
  g.damage = 1e9; c:tick(0.1)
  T.check(c.hire ~= nil and c.hire.stage == 'flying', 'still sightseeing after a crash'); T.eq(c.profile.progression.balance, 5000, 'nothing charged')
  g.damage = 0
  -- Return to your job: one press, Earth teleports back, the truck comes back.
  T.check(c:returnToJob(), 'returning'); T.eq(c.hire.stage, 'teleporting', 'teleport asked for')
  T.eq(a.teleports[#a.teleports].latitude, F.PENRITH.latitude, 'back to where the truck was')
  a.pose = F.copy(F.PENRITH)
  F.advance(c, 5)
  T.eq(g.spawns[#g.spawns].model, 'pickup', 'the pickup comes back')
  T.eq(c.hire, nil, 'back at work'); T.eq(c:view().flash.title, 'BACK TO WORK', 'told so')
  T.check(c.load ~= nil, 'with the job'); T.eq(c.profile.progression.balance, 5000, 'and the money')
  T.check(c:view().sightseeing.allowed, 'can go again'); T.check(c:view().saveAllowed, 'Save is back')
end

-- Close by, Return swaps straight back without a teleport.
do
  local c, a, g = game()
  c:goSightseeing(); c:vehicleSpawned(); c:tick(0.1)
  local teleports = #a.teleports
  T.check(c:returnToJob(), 'returning'); T.eq(#a.teleports, teleports, 'no teleport needed')
  T.eq(c.hire.stage, 'swapping', 'swapping')
  c:vehicleSpawned(); c:tick(0.1); T.eq(c.hire, nil, 'back')
end

-- A Moonhawk of your own: the respawn, not the model, says the swap happened.
do
  local c, a, g = game()
  c.ownedParts.model, g.model = 'moonhawk', 'moonhawk'
  c:tick(0.1)
  T.check(c:goSightseeing(), 'gone')
  c:tick(0.1); T.eq(c.hire.stage, 'spawning', 'waits for the respawn')
  c:vehicleSpawned(); c:tick(0.1); T.eq(c.hire.stage, 'flying', 'then sightseeing')
  c:returnToJob(); T.eq(c.hire.stage, 'swapping', 'swapping back')
  c:tick(0.1); T.eq(c.hire.stage, 'swapping', 'waits for the respawn back')
  c:vehicleSpawned(); c:tick(0.1); T.eq(c.hire, nil, 'back in your own Moonhawk')
end

-- Off when it cannot be done, and a failed save stops it.
do
  local c, a, g, io = game()
  F.drive(c, a, location.destination(F.PENRITH, 0, 300))
  a.pose = location.destination(F.PENRITH, 0, 400); c:tick(0.1)
  local v = c:view().sightseeing
  if not v.allowed then T.check(v.problem:find('Stop the car', 1, true) ~= nil, 'stop first') end
  F.advance(c, 5)
  io.writeFails = true
  T.check(not c:goSightseeing(), 'no save, no sightseeing'); T.eq(c.hire, nil, 'still in the truck')
  T.check(c:view().sightseeing.feedback:find('Could not save', 1, true) ~= nil, 'says why')
  io.writeFails = false
  g.accepts = false
  T.check(not c:goSightseeing(), 'spawn refused'); T.eq(c.hire, nil, 'still in the truck')
  T.check(c:view().sightseeing.feedback:find('try again', 1, true) ~= nil, 'says so')
end

T.done('sightseeing')
