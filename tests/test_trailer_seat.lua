local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local goods = require('earthFreight/goods')

-- Filling a tanker's Load Volume respawns the trailer, and the game can put the player in it as it
-- spawns. Sitting in their own trailer is never a car they are buying, and after the mod's own
-- respawn they go back to their truck.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local car = g.vehicleId
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000, paid = 26000 }
  T.check(c:spawnTrailer(), 'the tanker is out')
  local id = c.trailerOut.id
  function g:loadVolume(vehicleId)
    if vehicleId ~= id then return nil end
    return { name = '$load_volume', max = 34000, value = 0 }
  end
  function g:setLoadVolume() return true end
  local fuel = goods.get('fuel')
  c.load = { good = 'fuel', units = 3400, trailerUnits = 3400, kg = 3400 * fuel.kg }
  c:applyWeight(true)
  T.check(c.trailerOut.loadVolumeAsked == 34000, 'the Load Volume asked for')
  c.load = nil -- the bare load above has no towns for the HUD; the respawn is already asked for
  -- The respawned tanker takes the player a moment later, after the mod put them back.
  g.inTrailer = { id = g.vehicleId, model = g.model, fitted = g.fitted }
  g.vehicleId = id
  -- The world follows the player's seat: whatever vehicle the garage says they are in.
  local enter = g.enter
  function g:enter(target)
    local ok = enter(self, target)
    a.vehicle = { id = self.vehicleId, model = self.vehicleId == id and 'tanker' or 'pickup' }
    return ok
  end
  a.vehicle = { id = id, model = 'tanker' }
  for _ = 1, 4 do c:tick(0.6) end
  T.eq(g.vehicleId, car, 'back in the truck')
  T.eq(c.pendingCar, nil, 'no car bill for the tanker')
end

-- Getting into the trailer on purpose is left alone, and is not billed as a car either.
do
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tiltdeck', config = 'vehicles/tiltdeck/x.pc', maxKg = 3000, paid = 5000 }
  T.check(c:spawnTrailer(), 'out')
  local id = c.trailerOut.id
  for _ = 1, 3 do c:tick(0.6) end
  g:enter(id)
  a.vehicle = { id = id, model = 'tiltdeck' }
  for _ = 1, 4 do c:tick(0.6) end
  T.eq(g.vehicleId, id, 'still in the trailer')
  T.eq(c.pendingCar, nil, 'no car bill')
end

T.done('trailer seat')
