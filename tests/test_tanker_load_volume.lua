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

T.done('Tanker Load Volume')
