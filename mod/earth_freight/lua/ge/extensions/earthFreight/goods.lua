-- The goods, how they are carried and what a job pays for them. Each maps onto one of BeamNG's
-- cargo types (parcel, dryBulk, fluid). For now only parcels can be carried: bulk and fluids wait
-- for trays, tanks and trucks. Tune these after testing in game.
local M = {}

-- A unit of a good takes this many slots and weighs this many kg. pay: dollars a unit earns on a
-- 5 km job at the base rate. A job fills every slot the vehicle has, so on the starter Burnside
-- (20 slots, 1,000 kg) a full load over 5 km pays about $1,700 of parts, $2,000 of food and
-- $2,400 of bricks (6 units: the weight runs out first).
M.list = {
  { id = 'parts', name = 'Parts', kind = 'parcel', slots = 1, kg = 15, pay = 85 },
  { id = 'food', name = 'Food', kind = 'parcel', slots = 2, kg = 50, pay = 200 },
  { id = 'bricks', name = 'Bricks', kind = 'parcel', slots = 3, kg = 150, pay = 400 },
  { id = 'grain', name = 'Grain', kind = 'dryBulk', slots = 1, kg = 80 },
  { id = 'gravel', name = 'Gravel / ore', kind = 'dryBulk', slots = 1, kg = 160 },
  { id = 'water', name = 'Water', kind = 'fluid', slots = 1, kg = 100 },
  { id = 'fuel', name = 'Fuel', kind = 'fluid', slots = 1, kg = 75 },
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
