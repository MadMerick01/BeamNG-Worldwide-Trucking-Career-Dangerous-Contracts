local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local goods = require('earthFreight/goods')

-- The game's own tanker trailers weigh their load by a tuning setting, Load Volume, not by a tank
-- the mod can fill. A fluid load in one sets that setting (a respawn where it stands), the mod puts
-- none of its own weight on top, and the setting goes back to empty when the load is gone.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000, paid = 26000 }
  T.check(c:spawnTrailer(), 'the tanker is out')
  local id = c.trailerOut.id
  local volume, asks = 0, {}
  function g:loadVolume(vehicleId)
    if vehicleId ~= id then return nil end
    return { name = '$load_volume', max = 34000, value = volume }
  end
  function g:setLoadVolume(vehicleId, name, litres)
    asks[#asks + 1] = { id = vehicleId, name = name, litres = litres }
    return true
  end
  local hitches = 0
  local hitch = g.hitch
  function g:hitch(...) hitches = hitches + 1; if hitch then return hitch(self, ...) end return true end
  -- Hitched and settled: damage from here on is billed.
  c:couplerChanged(g.vehicleId, id, true); c.clock = c.clock + 5
  g.trailers[id].damage = 4000

  local fuel = goods.get('fuel')
  c.load = { good = 'fuel', units = 3400, trailerUnits = 3200, kg = 3400 * fuel.kg }
  c:applyWeight(true)
  T.eq(#asks, 1, 'the Load Volume is set'); T.eq(asks[1].litres, 32000, 'to the litres in the trailer')
  T.eq(asks[1].name, '$load_volume', 'by its own setting'); T.eq(hitches, 1, 'and the tanker hitched again')
  local sent = cargo.trailerWeights[#cargo.trailerWeights]
  T.eq(sent.kg, 0, 'no weight of the mod on top'); T.eq(sent.fluid.litres, 0, 'nor fluid of its own')
  T.near(cargo.weights[#cargo.weights].kg, 200 * fuel.kg, 1e-9, 'the truck carries only its own share')
  T.eq(c:trailerDamage(), 4000, 'the respawn does not mend the damage it had')
  g.trailers[id].damage = 0
  c.trailerOut.checkedAt = nil; c:watchTrailer()
  T.eq(c:trailerDamage(), 4000, 'still owed once the new trailer reads as new')

  -- The game has not taken it yet: not asked again.
  c:applyWeight(true)
  T.eq(#asks, 1, 'one respawn for each amount')
  -- Now it has: nothing more to do.
  volume = 32000
  c:applyWeight(true)
  T.eq(#asks, 1, 'already filled')
  T.eq(cargo.trailerWeights[#cargo.trailerWeights].kg, 0, 'still no weight of the mod')

  -- Delivered: the tanker is emptied.
  c.load = nil
  c:applyWeight(true)
  T.eq(#asks, 2, 'emptied after the job'); T.eq(asks[2].litres, 0, 'to 0 L')
end

-- A tanker with no Load Volume setting keeps the mod's own weight, as before.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000 }
  T.check(c:spawnTrailer(), 'a tanker without the setting')
  function g:loadVolume() return nil end
  local water = goods.get('water')
  c.load = { good = 'water', units = 100, trailerUnits = 80, kg = 100 * water.kg }
  c:applyWeight(true)
  local sent = cargo.trailerWeights[#cargo.trailerWeights]
  T.near(sent.kg, 80 * water.kg, 1e-9, 'its share on the trailer'); T.eq(sent.fluid.litres, 800, 'poured into its tank')
end

-- A respawn the game refuses falls back to the mod's own weight.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000 }
  T.check(c:spawnTrailer(), 'out')
  function g:loadVolume() return { name = '$load_volume', max = 34000, value = 0 } end
  function g:setLoadVolume() return false, 'respawn_failed' end
  local fuel = goods.get('fuel')
  c.load = { good = 'fuel', units = 100, trailerUnits = 100, kg = 100 * fuel.kg }
  c:applyWeight(true)
  T.near(cargo.trailerWeights[#cargo.trailerWeights].kg, 100 * fuel.kg, 1e-9, 'the mod weighs it instead')
end

-- A tanker truck with its own Load Volume setting carries its fluid the same way: the setting
-- is filled with a respawn where it stands, the damage it had stays owed and its fuel is kept.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.check(c.ownedParts ~= nil, 'the truck is known')
  local id = c.ownedParts.id
  local volume, asks = 0, {}
  function g:loadVolume(vehicleId)
    if vehicleId ~= id then return nil end
    return { name = '$load_volume', max = 1600, value = volume }
  end
  function g:setLoadVolume(vehicleId, name, litres)
    asks[#asks + 1] = { id = vehicleId, litres = litres }
    return true
  end
  g.damage = 2500
  local owed = c.owedDamage or 0
  local water = goods.get('water')
  c.load = { good = 'water', units = 150, kg = 150 * water.kg }
  c:applyWeight(true)
  T.eq(#asks, 1, 'the truck\'s Load Volume is set'); T.eq(asks[1].id, id, 'on the truck')
  T.eq(asks[1].litres, 150 * water.litres, 'to the litres it carries')
  T.near((c.owedDamage or 0) - owed, 2500, 1e-9, 'the damage it had stays owed')
  c:applyWeight(true)
  T.eq(#asks, 1, 'one respawn for each amount')
  volume = 150 * water.litres
  c:applyWeight(true)
  T.eq(#asks, 1, 'already filled')
  T.eq(cargo.weights[#cargo.weights].kg, 0, 'no weight of the mod on top')
  T.eq(cargo.weights[#cargo.weights].fluid.litres, 0, 'nor fluid of its own')
  c.load = nil
  c:applyWeight(true)
  T.eq(#asks, 2, 'emptied after the job'); T.eq(asks[2].litres, 0, 'to 0 L')
end

-- A truck whose respawn the game refuses keeps the mod's own weight.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  function g:loadVolume() return { name = '$load_volume', max = 1600, value = 0 } end
  function g:setLoadVolume() return false, 'respawn_failed' end
  local water = goods.get('water')
  c.load = { good = 'water', units = 100, kg = 100 * water.kg }
  c:applyWeight(true)
  T.near(cargo.weights[#cargo.weights].kg, 100 * water.kg, 1e-9, 'the mod weighs it instead')
  T.check(not c.ourRespawn, 'no respawn is waited for')
end

-- The short 17,700 L tanker: a respawn the mod did not ask for (Apply in the game's Vehicle
-- Config, or its parts put back as bought) can leave the Load Volume at another amount. It is
-- filled again, rather than the load weighing nothing for the rest of the job.
do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty_short.pc', maxKg = 17700, paid = 20000 }
  T.check(c:spawnTrailer(), 'the short tanker is out')
  local id = c.trailerOut.id
  c:watchTrailerParts()
  local volume, asks = 0, {}
  function g:loadVolume(vehicleId)
    if vehicleId ~= id then return nil end
    return { name = '$loadVolume', max = 17700, value = volume }
  end
  function g:setLoadVolume(vehicleId, name, litres)
    asks[#asks + 1] = { id = vehicleId, name = name, litres = litres }
    return true
  end
  local fuel = goods.get('fuel')
  c.load = { good = 'fuel', units = 17700, trailerUnits = 17700, kg = 17700 * fuel.kg }
  c:applyWeight(true)
  T.eq(#asks, 1, 'filled'); T.eq(asks[1].litres, 17700, 'to the whole tank'); T.eq(asks[1].name, '$loadVolume', 'by its setting')

  -- The respawn the mod asked for: nothing more to do.
  volume = 17700
  c:vehicleSpawned(id); c:watchTrailerParts()
  T.eq(#asks, 1, 'its own respawn is not asked again')
  T.eq(cargo.trailerWeights[#cargo.trailerWeights].kg, 0, 'the game carries the weight')

  -- The player moves the slider in Vehicle Config and applies it: filled again.
  volume = 0
  c:vehicleSpawned(id); c:watchTrailerParts()
  T.eq(#asks, 2, 'asked again after a respawn of the player'); T.eq(asks[2].litres, 17700, 'to the load')
  volume = 17700
  c:vehicleSpawned(id); c:watchTrailerParts()
  T.eq(#asks, 2, 'and not again once filled')

  -- Its parts changed and put back as bought, which empties the setting: filled again too.
  g.trailers[id].fitted = { deck = 'something_else' }
  c:vehicleSpawned(id); c:watchTrailerParts()
  T.eq(g.trailerRepairs, 1, 'the parts are put back')
  volume = 0
  c:vehicleSpawned(id); c:watchTrailerParts()
  T.eq(#asks, 3, 'filled again after the parts are put back'); T.eq(asks[3].litres, 17700, 'to the load')

  -- A respawn the game did not take is still asked for only once.
  c:applyWeight(true); c:applyWeight(true)
  T.eq(#asks, 3, 'not over and over')
end

T.done('Tanker Load Volume')
