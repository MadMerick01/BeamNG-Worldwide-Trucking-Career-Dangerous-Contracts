-- The goods, how they are carried and what a job pays for them. Each maps onto one of BeamNG's
-- cargo types (parcel, dryBulk, fluid). Parcels go in cargo boxes and fluids in fluid tanks; dry
-- bulk waits for trays and trucks. Tune these after testing in game.
local M = {}

-- A parcel unit takes this many slots and weighs this many kg. A fluid unit is `litres` litres
-- (its slots are those litres too, so a load's slots are its litres) of this many kg. pay: dollars
-- a unit earns on a 5 km job at the base rate. A job fills every slot or litre the vehicle has, so
-- on the starter Burnside (20 slots, 1,000 kg) a full load over 5 km pays about $1,700 of parts
-- and $2,400 of bricks (6 units: the weight runs out first). Fluids pay about a quarter more than
-- bricks for the same weight: a full 800 L tank over 5 km pays about $2,640 of water and $2,880 of
-- fuel. Food is no longer posted; it stays known so a food job in an older save still delivers.
M.list = {
  { id = 'parts', name = 'Parts', kind = 'parcel', slots = 1, kg = 15, pay = 85 },
  { id = 'food', name = 'Food', kind = 'parcel', slots = 2, kg = 50, pay = 200, retired = true },
  { id = 'bricks', name = 'Bricks', kind = 'parcel', slots = 3, kg = 150, pay = 400 },
  { id = 'grain', name = 'Grain', kind = 'dryBulk', slots = 1, kg = 80 },
  { id = 'gravel', name = 'Gravel / ore', kind = 'dryBulk', slots = 1, kg = 160 },
  { id = 'water', name = 'Water', kind = 'fluid', litres = 10, slots = 10, kg = 10, pay = 33 },
  { id = 'fuel', name = 'Fuel', kind = 'fluid', litres = 10, slots = 10, kg = 7.5, pay = 36 },
}
-- The cargo kinds the mod can carry yet.
M.CARRIED = { parcel = true, fluid = true }

local byId = {}
for _, good in ipairs(M.list) do byId[good.id] = good end

function M.get(id) return byId[id] end

-- The goods jobs are posted for, in list order.
function M.carried()
  local out = {}
  for _, good in ipairs(M.list) do if M.CARRIED[good.kind] and not good.retired then out[#out + 1] = good end end
  return out
end

-- The goods of one kind that jobs are posted for, in list order.
function M.ofKind(kind)
  local out = {}
  for _, good in ipairs(M.carried()) do if good.kind == kind then out[#out + 1] = good end end
  return out
end

return M
