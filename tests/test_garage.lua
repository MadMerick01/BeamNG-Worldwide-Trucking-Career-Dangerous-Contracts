local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local G = require('earthFreight/garage')

local function vehicle(id)
  return { getID = function() return id end, getJBeamFilename = function() return 'pickup' end }
end
local replaced
local function env(overrides)
  local e = {
    vehicle = function() return vehicle(7) end,
    objects = function() return { [7] = { damage = 1234 } } end,
    manager = function() return { getVehicleData = function(id) return id == 7 and { config = { model = 'pickup', parts = {} } } or nil end } end,
    vehicles = function() return { replaceVehicle = function(model, options, veh) replaced = { model = model, options = options, veh = veh } end } end,
  }
  for k, v in pairs(overrides or {}) do e[k] = v end
  return e
end

local g = G.new(env())
local info = g:inspect()
T.eq(info.id, 7, 'reads the player vehicle id'); T.eq(info.damage, 1234, 'reads damage from map.objects')
T.check(g:repair(), 'repair accepted'); T.eq(replaced.model, 'pickup', 'respawns the same model')
T.eq(replaced.options.config.model, 'pickup', 'respawns with the current parts config'); T.eq(replaced.veh:getID(), 7, 'replaces the player vehicle in place')

local _, why = G.new(env({ vehicle = function() return nil end })):inspect()
T.eq(why, 'vehicle_required', 'no vehicle, no quote')
_, why = G.new(env({ objects = function() return {} end })):inspect()
T.eq(why, 'damage_unavailable', 'missing damage reported')
_, why = G.new(env({ objects = function() error('changed') end })):inspect()
T.eq(why, 'damage_unavailable', 'damage read errors contained')
_, why = G.new(env({ objects = function() return { [7] = { damage = 0/0 } } end })):inspect()
T.eq(why, 'damage_unavailable', 'invalid damage rejected')
local ok
ok, why = G.new(env({ vehicles = function() return {} end })):repair()
T.check(not ok, 'missing replaceVehicle fails'); T.eq(why, 'repair_unavailable', 'reason given')
ok, why = G.new(env({ manager = function() return { getVehicleData = function() return nil end } end })):repair()
T.eq(why, 'config_unavailable', 'no config, no repair')
ok, why = G.new(env({ vehicles = function() return { replaceVehicle = function() error('boom') end } end })):repair()
T.check(not ok, 'respawn error contained'); T.eq(why, 'repair_failed', 'respawn error reported')
-- Parts: flattens the 0.39 partsTree and prices parts from their jbeam information.value.
local tree = { chosenPartName = 'pickup', path = '/', children = {
  pickup_engine = { chosenPartName = 'pickup_engine_v8', path = '/pickup_engine/', children = {
    pickup_intake = { chosenPartName = 'pickup_intake_race', path = '/pickup_engine/pickup_intake/' } } },
  pickup_bumper = { chosenPartName = '', path = '/pickup_bumper/' } } }
local partsEnv = env({
  manager = function() return { getVehicleData = function() return { ioCtx = {}, config = {
    model = 'pickup', partsTree = tree, vars = { ['$tune'] = 2 }, paints = { 'red' } } } end } end,
  jbeam = function() return { getPart = function(_, name)
    if name == 'pickup_intake_race' then return { information = { value = 800, name = 'Race Intake' } } end
    if name == 'pickup_engine_v8' then return { information = { value = 'bad' } } end
    if name == 'pickup' then error('changed') end
  end } end,
})
local parts = G.new(partsEnv):parts()
T.eq(parts.id, 7, 'parts for the player vehicle'); T.eq(parts.model, 'pickup', 'parts model')
T.eq(parts.parts['/pickup_engine/pickup_intake/'], 'pickup_intake_race', 'nested slot flattened')
T.eq(parts.parts['/pickup_bumper/'], '', 'empty slot kept as empty')
T.eq(parts.values.pickup_intake_race, 800, 'part value read'); T.eq(parts.names.pickup_intake_race, 'Race Intake', 'part name read')
T.eq(parts.values.pickup_engine_v8, nil, 'unreadable value left out'); T.eq(parts.names.pickup, 'pickup', 'lookup errors contained')
_, why = G.new(env()):parts()
T.eq(why, 'parts_unavailable', 'no parts tree, no parts')
local revert = { model = 'pickup', partsTree = { chosenPartName = 'pickup' }, vars = { ['$tune'] = 1 }, paints = { 'blue' } }
T.check(G.new(partsEnv):repair(revert), 'respawn with given parts accepted')
T.eq(replaced.options.config.partsTree.chosenPartName, 'pickup', 'respawns with the given parts')
T.eq(replaced.options.config.vars['$tune'], 2, 'keeps the current tuning'); T.eq(replaced.options.config.paints[1], 'red', 'keeps the current paint')
T.eq(revert.vars['$tune'], 1, 'given config left unchanged')
-- Starter car: spawns a .pc file in place, even when the vehicle already came from it.
T.check(G.new(env()):spawnConfig('burnside', 'vehicles/burnside/starter.pc'), 'starter spawn accepted')
T.eq(replaced.model, 'burnside', 'spawns the starter model'); T.eq(replaced.options.config, 'vehicles/burnside/starter.pc', 'spawns from the config file')
T.eq(replaced.veh:getID(), 7, 'replaces the player vehicle in place')
replaced = nil
local fromStarter = env({ manager = function() return { getVehicleData = function() return { config = {
  model = 'burnside', partConfigFilename = '/vehicles/burnside/Starter.pc' } } end } end })
local spawned = G.new(fromStarter):spawnConfig('burnside', 'vehicles/burnside/starter.pc')
T.check(spawned, 'already the starter is fine'); T.eq(replaced.options.config, 'vehicles/burnside/starter.pc', 'respawned fresh, in case parts were changed')
replaced = nil
local savedCar = { model = 'burnside', partsTree = { chosenPartName = 'burnside' } }
T.check(G.new(fromStarter):spawnConfig('burnside', savedCar), 'saved config spawned even from the starter file')
T.eq(replaced.options.config.partsTree.chosenPartName, 'burnside', 'spawns the saved parts')
T.check(replaced.options.config ~= savedCar, 'saved config copied, not handed to the game')
ok, why = G.new(env({ vehicle = function() return nil end })):spawnConfig('burnside', 'x.pc')
T.eq(why, 'vehicle_required', 'no vehicle, no starter spawn')
ok, why = G.new(env({ vehicles = function() return {} end })):spawnConfig('burnside', 'x.pc')
T.eq(why, 'spawn_unavailable', 'missing replaceVehicle reported')
ok, why = G.new(env({ vehicles = function() return { replaceVehicle = function() error('boom') end } end })):spawnConfig('burnside', 'x.pc')
T.check(not ok, 'spawn error contained'); T.eq(why, 'spawn_failed', 'spawn error reported')
-- Car prices come from the config's info Value, looked up by the .pc file's name.
local carEnv = env({ vehicles = function() return { getConfig = function(model, key)
  if model == 'pickup' and key == 'offroad' then return { Value = 21000, Name = 'Gavril D-Series', Configuration = 'Offroad' } end
  if key == 'broken' then error('changed') end
end } end })
local value, name = G.new(carEnv):carValue('pickup', 'vehicles/pickup/offroad.pc')
T.eq(value, 21000, 'car Value read'); T.eq(name, 'Gavril D-Series Offroad', 'car name read')
T.eq((G.new(carEnv):carValue('pickup', 'vehicles/pickup/broken.pc')), nil, 'lookup errors contained')
T.eq((G.new(carEnv):carValue('pickup', nil)), nil, 'no config file, no Value')
local entered
local enterEnv = env({ objectById = function(id) return id == 3 and vehicle(3) or nil end, enter = function(v) entered = v:getID() end })
T.check(G.new(enterEnv):enter(3), 'enters a parked car'); T.eq(entered, 3, 'player put in that car')
ok, why = G.new(enterEnv):enter(4)
T.check(not ok, 'missing car not entered'); T.eq(why, 'vehicle_gone', 'reason given')
T.done('garage')
