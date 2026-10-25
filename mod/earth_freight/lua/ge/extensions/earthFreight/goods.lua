-- The goods, how they are carried and what they are worth. Each maps onto one of BeamNG's cargo
-- types (parcel, dryBulk, fluid). For now only parcels can be carried: bulk and fluids wait for
-- trays, tanks and trucks. Tune these after testing in game.
local M = {}

-- basePrice: dollars for one parcel slot at an average place. kgPerSlot: what one slot weighs.
-- damageForLoss: the damage points (the car's own damage reading) that destroy the whole load;
-- fragile goods have fewer.
M.list = {
  { id = 'parts', name = 'Parts', kind = 'parcel', basePrice = 150, kgPerSlot = 20, damageForLoss = 3000 },
  { id = 'food', name = 'Food', kind = 'parcel', basePrice = 60, kgPerSlot = 25, damageForLoss = 6000 },
  { id = 'bricks', name = 'Bricks', kind = 'parcel', basePrice = 45, kgPerSlot = 120, damageForLoss = 20000 },
  { id = 'grain', name = 'Grain', kind = 'dryBulk', basePrice = 30, kgPerSlot = 80, damageForLoss = 20000 },
  { id = 'gravel', name = 'Gravel / ore', kind = 'dryBulk', basePrice = 25, kgPerSlot = 160, damageForLoss = 50000 },
  { id = 'water', name = 'Water', kind = 'fluid', basePrice = 20, kgPerSlot = 100, damageForLoss = 30000 },
  { id = 'fuel', name = 'Fuel', kind = 'fluid', basePrice = 120, kgPerSlot = 75, damageForLoss = 3000 },
}
-- The cargo kinds the mod can carry yet.
M.CARRIED = { parcel = true }

local byId = {}
for _, good in ipairs(M.list) do byId[good.id] = good end

function M.get(id) return byId[id] end

-- The goods a vehicle can carry now, in list order.
function M.carried()
  local out = {}
  for _, good in ipairs(M.list) do if M.CARRIED[good.kind] then out[#out + 1] = good end end
  return out
end

return M
