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
-- A trailer put back as it was sold: another vehicle, by id, respawned from its .pc path.
do
  local trailer = { getID = function() return 42 end, getJBeamFilename = function() return 'tiltdeck' end }
  local tg = G.new(env({ objectById = function(id) return id == 42 and trailer or nil end,
    manager = function() return { getVehicleData = function(id) return id == 42 and { config = { model = 'tiltdeck', parts = { box = 'x' } } } or nil end } end }))
  T.check(tg:repair('vehicles/tiltdeck/earth_freight_22ft_boxes.pc', 42), 'trailer respawn accepted')
  T.eq(replaced.veh:getID(), 42, 'the trailer, not the player vehicle'); T.eq(replaced.model, 'tiltdeck', 'its own model')
  T.eq(replaced.options.config, 'vehicles/tiltdeck/earth_freight_22ft_boxes.pc', 'as its .pc file sets it up')
  T.eq(select(2, tg:repair('x.pc', 43)), 'vehicle_required', 'a vehicle that is gone is refused')
end

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
-- Insurance: the recovery menu's teleport to the last road, guarded.
do
  local sent
  local roads = G.new(env({ spawn = function() return { teleportToLastRoad = function(veh) sent = veh:getID() end } end }))
  T.check(roads:toRoad(), 'sent back to the road'); T.eq(sent, 7, 'the player vehicle')
  T.eq(select(2, G.new(env()):toRoad()), 'road_unavailable', 'no spawn module, no move')
  T.eq(select(2, G.new(env({ spawn = function() return { teleportToLastRoad = function() error('x') end } end })):toRoad()), 'road_failed', 'errors contained')
end
-- Walking mode and the tow: the car is brought 4 m in front of the player, upright, and they are put back in.
do
  local function at(id, model, x, y)
    return { getID = function() return id end, getJBeamFilename = function() return model end,
      getPosition = function() return { x = x, y = y, z = 0 } end, getDirectionVector = function() return { x = 0, y = 2, z = 0 } end }
  end
  local walker, car = at(99, 'unicycle', 10, 0), at(7, 'pickup', 40, 40)
  local teleported, entered, walking
  local e = env({ vehicle = function() return walker end, objectById = function(id) return ({ [99] = walker, [7] = car })[id] end,
    objects = function() return { [7] = { damage = 500 }, [99] = { damage = 0 } } end,
    point = function(x, y, z) return { x = x, y = y, z = z } end, upright = function(dir) return { dir = dir } end,
    spawn = function() return { safeTeleport = function(veh, pos, rot) teleported = { id = veh:getID(), pos = pos, rot = rot } end } end,
    walk = function() return { isWalking = function() return walking end, setWalkingMode = function(on) walking = on end,
      getInVehicle = function(veh) entered = veh:getID() end } end })
  local w = G.new(e)
  T.check(w:isWalker(99) and not w:isWalker(7), 'the unicycle is walking mode')
  T.check(w:onFoot(), 'in the unicycle is on foot'); walking = true; T.check(w:onFoot(), 'and so is walking mode')
  T.eq(w:inspect(7).damage, 500, 'the parked car is read by its id')
  T.near(w:carDistance(7), 50, 1e-9, 'how far the car is')
  T.check(w:towHere(7), 'towed'); T.eq(teleported.id, 7, 'the car')
  T.eq(teleported.pos.x, 10, 'in front of the player'); T.eq(teleported.pos.y, 4, '4 m ahead'); T.eq(teleported.rot.dir.y, 1, 'facing their way')
  T.eq(entered, 7, 'and the player is put back in it')
  walking = false; T.check(w:getOut(), 'getting out'); T.check(walking, 'asks walking mode')
  T.eq(select(2, G.new(env({ vehicle = function() return walker end, objectById = function() return car end })):towHere(7)), 'tow_unavailable', 'no spawn module, no tow')
  T.eq(select(2, G.new(env({ vehicle = function() return walker end, objectById = function() return nil end })):towHere(7)), 'vehicle_gone', 'no car, no tow')
  T.check(not G.new(env()):onFoot(), 'not on foot without walking mode')
end
-- Traffic: on foot, the parked car is taken out of the game's traffic, which would otherwise
-- respawn it elsewhere in a new paint, and given back once the player is in it again.
do
  local inTraffic, removed, inserted, driving = { [7] = {} }, {}, {}, 99
  local car = { getID = function() return driving end }
  local e = env({ vehicle = function() return car end, traffic = function() return {
    getTrafficData = function() return inTraffic end,
    removeTraffic = function(id) removed[#removed + 1] = id; inTraffic[id] = nil end,
    insertTraffic = function(id, ignoreAi) inserted[#inserted + 1] = { id = id, ignoreAi = ignoreAi }; inTraffic[id] = {} end } end })
  local w = G.new(e)
  T.check(w:keepParked(7), 'the parked car leaves traffic'); T.eq(removed[1], 7, 'by its id')
  T.check(not w:keepParked(7), 'once'); T.eq(#removed, 1, 'not again')
  T.check(not w:releaseParked(), 'not given back while the player is on foot'); T.eq(#inserted, 0, 'nothing inserted')
  driving = 7
  T.check(w:releaseParked(), 'given back once in it'); T.eq(inserted[1].id, 7, 'the car'); T.check(inserted[1].ignoreAi, 'without the AI driving it')
  T.check(not w:releaseParked(), 'only once')
  T.check(not G.new(env()):keepParked(7), 'no traffic, nothing to do')
  T.check(not G.new(env({ traffic = function() return { getTrafficData = function() error('x') end, removeTraffic = function() end } end })):keepParked(7), 'errors contained')
end
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
T.eq(parts.slots['/pickup_engine/pickup_intake/'], 'pickup_intake', 'slot names kept')
T.eq(parts.parents['/pickup_engine/pickup_intake/'], '/pickup_engine/', 'with the slot above')
T.eq(parts.slots['/'], '', 'the root has no slot name')
-- The parts the car's own config comes with, lined up with the fitted slots.
local stockEnv = env({
  manager = partsEnv.manager,
  jbeam = function() return { getPart = function(_, name)
    if name == 'pickup_engine_i6' then return { information = { value = 3000, name = 'I6 Engine' } } end
    if name == 'pickup_intake_race' then return { information = { value = 800, name = 'Race Intake' } } end
  end } end,
  read = function(path)
    if path == 'vehicles/pickup/base.pc' then return { format = 2, mainPartName = 'pickup', parts = {
      pickup_engine = 'pickup_engine_i6', pickup_bumper = 'pickup_bumper_f', pickup_i6_intake = 'pickup_i6_intake_stock' } } end
    if path == 'vehicles/pickup/tree.pc' then return { partsTree = { chosenPartName = 'pickup', path = '/', children = {
      pickup_engine = { chosenPartName = 'pickup_engine_v8', path = '/pickup_engine/' } } } } end
    error('missing')
  end,
})
local sg = G.new(stockEnv)
local snap = sg:parts(); snap.configFile = 'vehicles/pickup/base.pc'
local stock = sg:stockParts(snap)
T.eq(stock['/'], 'pickup', 'the root is the main part')
T.eq(stock['/pickup_engine/'], 'pickup_engine_i6', 'a slot the config names, by slot name')
T.eq(stock['/pickup_bumper/'], 'pickup_bumper_f', 'an emptied slot keeps the part it came with')
T.eq(stock['/pickup_engine/pickup_intake/'], '', 'a slot under a changed part came with it')
T.eq(stock['#pickup_i6_intake'], 'pickup_i6_intake_stock', 'a config slot the car no longer has')
T.eq(snap.values.pickup_engine_i6, 3000, 'stock parts priced'); T.eq(snap.names.pickup_engine_i6, 'I6 Engine', 'and named')
snap.stock = stock
T.eq(require('earthFreight/pricing').partsWorth(snap), 250 + 800 - 3000 - 250 - 250,
  'the V8 and its intake added, the I6, its intake and the bumper taken off')
snap = sg:parts(); snap.configFile = 'vehicles/pickup/tree.pc'
stock = sg:stockParts(snap)
T.eq(stock['/pickup_engine/'], 'pickup_engine_v8', 'a config with a tree lines up by path')
T.eq(stock['/pickup_engine/pickup_intake/'], 'pickup_intake_race', 'slots it does not have stay as fitted')
snap.configFile = 'vehicles/pickup/gone.pc'; T.eq(sg:stockParts(snap), nil, 'an unreadable config, no stock parts')
snap.configFile = nil; T.eq(sg:stockParts(snap), nil, 'nor without a config')
T.eq(G.new(partsEnv):stockParts(sg:parts()), nil, 'nor without a way to read it')
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
-- The game's car list, read once, with each config's .pc path, full name and price.
local listCalls = 0
local listEnv = env({ vehicles = function() return { getConfigList = function()
  listCalls = listCalls + 1
  return { configs = {
    pickup_d15 = { model_key = 'pickup', key = 'd15', Name = 'D-Series', Brand = 'Gavril', Configuration = 'D15', Value = 33000,
      Type = 'Truck', Source = 'BeamNG - Official', preview = '/vehicles/pickup/d15.jpg' },
    broken = { model_key = 'pickup' },
    junk = 'not a config',
  } }
end } end })
local lg = G.new(listEnv)
local configs = lg:configs()
T.eq(#configs, 1, 'only whole configs listed'); T.eq(configs[1].config, 'vehicles/pickup/d15.pc', 'its .pc path')
T.eq(configs[1].name, 'Gavril D-Series D15', 'brand, name and configuration'); T.eq(configs[1].value, 33000, 'its price')
T.eq(configs[1].type, 'Truck', 'its type'); T.eq(configs[1].preview, '/vehicles/pickup/d15.jpg', 'its picture')
lg:configs(); T.eq(listCalls, 1, 'read once')
T.eq(#G.new(env({ vehicles = function() return { getConfigList = function() error('changed') end } end })):configs(), 0, 'list errors contained')
-- Worn looks: the game's part condition, queued on the player vehicle.
local queued
local wearEnv = env({ vehicle = function() local v = vehicle(7); v.queueLuaCommand = function(_, cmd) queued = cmd end; return v end })
T.check(G.new(wearEnv):wear(120000, 0.92), 'wear queued')
T.check(queued:find('partCondition.initConditions(nil, 120000000, nil, 0.920)', 1, true), 'odometer in metres and the look')
T.check(queued:find('if partCondition and partCondition.initConditions then', 1, true), 'guarded in the car')
T.check(not G.new(env({ vehicle = function() return nil end })):wear(1, 1), 'no vehicle, no wear')
-- Names come from the model's brand and name plus the version, not the Name the game makes up
-- from the file name; our starter car has its own.
local nameEnv = env({ vehicles = function() return {
  getModel = function(model) return { model = model == 'burnside' and { Brand = 'Burnside', Name = 'Special' } or nil } end,
  getConfig = function(model, key)
    if key == 'earth_freight_starter' then return { Value = 3500, Name = 'Special Earth_freight_starter', Configuration = 'Earth_Freight_Starter' } end
    return { Value = 9000, Name = 'Special Junk_key', Configuration = 'Custom_Coupe' }
  end } end })
local ng = G.new(nameEnv)
T.eq(select(2, ng:carValue('burnside', 'vehicles/burnside/earth_freight_starter.pc')), 'Burnside Rusty', 'the starter is the Burnside Rusty')
T.eq(select(2, ng:carValue('burnside', 'vehicles/burnside/custom.pc')), 'Burnside Special Custom Coupe', 'brand, model and a tidy version')
-- A config without its model's Type gets it from the model, so trailers and props can be left out.
local typedEnv = env({ vehicles = function() return {
  getModel = function(model) return { model = ({ flatbed = { Name = 'Flatbed', Type = 'Trailer' }, cones = { Name = 'Cones', Type = 'Prop' } })[model] } end,
  getConfigList = function() return { configs = {
    a = { model_key = 'flatbed', key = 'long', Value = 5000 }, b = { model_key = 'cones', key = 'big', Value = 50 },
    c = { model_key = 'pickup', key = 'd15', Value = 33000, Type = 'Truck' } } } end } end })
local types = {}
for _, info in ipairs(G.new(typedEnv):configs()) do types[info.model] = info.type end
T.eq(types.flatbed, 'Trailer', 'trailer type from the model'); T.eq(types.cones, 'Prop', 'prop type from the model')
T.eq(types.pickup, 'Truck', 'the config type kept')
local U = require('earthFreight/usedCars')
T.eq(#U.candidates(G.new(typedEnv):configs()), 1, 'only the truck is for sale')
-- Trailers: spawned behind the car facing the same way, nose to its tail; containers read by type.
do
  local function box(length) return { getHalfExtents = function() return { x = 1, y = length / 2, z = 1 } end } end
  local commands, spawned, teleported = {}, nil, nil
  local car = { getID = function() return 7 end, getPosition = function() return { x = 0, y = 0, z = 10 } end,
    getDirectionVector = function() return { x = 0, y = 1, z = 0 } end, getSpawnWorldOOBB = function() return box(4) end,
    queueLuaCommand = function(_, c) commands[#commands + 1] = 'car:' .. c end }
  local trailer = { getID = function() return 42 end, getSpawnWorldOOBB = function() return box(8) end,
    queueLuaCommand = function(_, c) commands[#commands + 1] = 'trailer:' .. c end }
  local tg = G.new(env({
    vehicle = function() return car end,
    objectById = function(id) return id == 42 and trailer or nil end,
    point = function(x, y, z) return { x = x, y = y, z = z } end,
    upright = function(dir) return dir end,
    vehicles = function() return { spawnNewVehicle = function(model, options) spawned = { model = model, options = options }; return trailer end } end,
    spawn = function() return { safeTeleport = function(veh, pos) teleported = pos end } end,
    manager = function() return { getVehicleData = function(id)
      return id == 42 and { config = {}, vdata = { cargoStorage = {
        { capacity = 60, cargoTypes = { 'parcel' } }, { capacity = 800, cargoTypes = { 'fluid' } },
        { capacity = 5, cargoTypes = { 'unknown' } }, { capacity = 0 / 0, cargoTypes = { 'parcel' } } } } } or nil end } end,
  }))
  T.eq(tg:spawnTrailer('flatbed', 'vehicles/flatbed/long.pc'), 42, 'the trailer spawned')
  T.eq(spawned.options.config, 'vehicles/flatbed/long.pc', 'its config'); T.eq(spawned.options.autoEnterVehicle, false, 'the player stays in the car')
  T.near(teleported.y, -(2 + G.TRAILER_GAP + 4), 1e-9, 'nose up to the car tail'); T.eq(teleported.x, 0, 'straight behind')
  T.check(commands[1]:find('activateAutoCoupling') and commands[2]:find('activateAutoCoupling'), 'both asked to couple')
  local storage = tg:cargoStorage(42)
  T.eq(#storage, 2, 'parcel and fluid containers kept'); T.eq(storage[1].kind, 'parcel', 'parcel'); T.eq(storage[2].capacity, 800, 'tank litres')
  T.check(tg:exists(42) and not tg:exists(43), 'knows which vehicles exist')
  T.eq(select(2, G.new(env()):spawnTrailer('x', 'y')), 'spawn_unavailable', 'no spawn function, no trailer')
end
-- The Your truck card's picture: the config's, else the model's, else our own for the starter.
do
  local asked = 0
  local list = { pickup = { d15 = { preview = '/vehicles/pickup/d15.jpg' }, bare = {} } }
  local pg = G.new(env({ vehicles = function() return {
    getConfig = function(model, key) asked = asked + 1; return list[model] and list[model][key] end,
    getModel = function(model) return model == 'pickup' and { model = { preview = '/vehicles/pickup/default.jpg' } } or nil end } end }))
  T.eq(pg:preview('pickup', 'vehicles/pickup/d15.pc'), '/vehicles/pickup/d15.jpg', 'the config picture')
  pg:preview('pickup', 'vehicles/pickup/d15.pc'); T.eq(asked, 1, 'read once')
  T.eq(pg:preview('pickup', 'vehicles/pickup/bare.pc'), '/vehicles/pickup/default.jpg', 'else the model picture')
  T.eq(pg:preview('burnside', 'vehicles/burnside/earth_freight_starter.pc'), G.PREVIEWS['burnside/earth_freight_starter'], 'our starter picture')
  T.eq(pg:preview(nil), nil, 'no model, no picture')
  T.eq(G.new(env({ vehicles = function() error('changed') end })):preview('pickup', 'vehicles/pickup/d15.pc'), nil, 'a broken game list gives none')
end

-- The photo of the player's car: the parts menu's Save, guarded, and one config per model.
do
  local saved, shots, files, gone = {}, {}, {}, {}
  local pm = { saveLocal = function(f) saved[#saved + 1] = f end, saveLocalScreenshot = function(f) shots[#shots + 1] = f end }
  local photo = G.new(env({ partmgmt = function() return pm end, exists = function(p) return files[p] == true end,
    remove = function(p) gone[#gone + 1] = p; files[p] = nil end }))
  T.check(photo:takePhoto(), 'photo asked for'); T.eq(saved[1], G.PHOTO_KEY .. '.pc', 'one config, always the same name')
  T.eq(shots[1], G.PHOTO_KEY .. '.pc', 'with its picture')
  T.eq(photo:photo('pickup'), nil, 'none until the picture is written')
  files['/vehicles/pickup/' .. G.PHOTO_KEY .. '.png'] = true
  T.eq(photo:photo('pickup'), '/vehicles/pickup/' .. G.PHOTO_KEY .. '.png', 'then found')
  T.eq(photo:photo('../x'), nil, 'only plain model names')
  files['/vehicles/pickup/' .. G.PHOTO_KEY .. '.pc'] = true
  photo:removePhoto('pickup'); T.eq(#gone, 2, 'config and picture removed'); T.eq(photo:photo('pickup'), nil, 'gone')
  local ok, why = G.new(env({ partmgmt = function() return {} end })):takePhoto(); T.check(not ok, 'no Save in this game'); T.eq(why, 'photo_unavailable', 'says why')
  ok, why = G.new(env({ partmgmt = function() return { saveLocal = function() error('x') end, saveLocalScreenshot = pm.saveLocalScreenshot } end })):takePhoto()
  T.eq(why, 'save_failed', 'a failed save is caught')
  ok, why = G.new(env({ vehicle = function() return nil end, partmgmt = function() return pm end })):takePhoto(); T.eq(why, 'vehicle_required', 'needs a car')
  local list = G.new(env({ vehicles = function() return { getConfigList = function() return { configs = {
    a = { model_key = 'pickup', key = 'd15', Value = 1 }, b = { model_key = 'pickup', key = G.PHOTO_KEY, Value = 1 } } } end } end }))
  local configs = list:configs(); T.eq(#configs, 1, 'the photo config is not for sale'); T.eq(configs[1].key, 'd15', 'the real one is')
end

T.done('garage')
