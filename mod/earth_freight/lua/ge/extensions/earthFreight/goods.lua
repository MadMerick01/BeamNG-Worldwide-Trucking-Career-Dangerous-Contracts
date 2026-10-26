-- The goods, how they are carried and what a job pays for them. Each maps onto one of BeamNG's
-- cargo types (parcel, dryBulk, fluid). Parcels go in cargo boxes and fluids in fluid tanks; dry
-- bulk waits for trays and trucks. Tune these after testing in game.
local M = {}

-- A parcel unit takes this many slots and weighs this many kg. A fluid unit is `litres` litres
-- (its slots are those litres too, so a load's slots are its litres) of this many kg. Pay goes by
-- the load's weight (jobs.weightPay); rate is a good's pay against that, 1 being the curve as is.
-- A job fills every slot or litre the vehicle has, so a Burnside with 52 slots of boxes carries
-- 780 kg of parts for $2,000 over 5 km, or about 2,000 kg of bricks (13 units with 3 L boxes and
-- an M) for about $3,600; a full 800 L tank is 800 kg of water for about $2,030, or 600 kg of
-- fuel for about $1,540. Parcels are heavy for their slots (bricks 50 kg
-- a slot), so a big box runs out of weight before space. Food is no longer posted; it stays known
-- so a food job in an older save still delivers.
M.list = {
  { id = 'parts', name = 'Parts', kind = 'parcel', slots = 1, kg = 15, rate = 1 },
  { id = 'food', name = 'Food', kind = 'parcel', slots = 2, kg = 50, rate = 1, retired = true },
  { id = 'bricks', name = 'Bricks', kind = 'parcel', slots = 3, kg = 150, rate = 1 },
  { id = 'grain', name = 'Grain', kind = 'dryBulk', slots = 1, kg = 80 },
  { id = 'gravel', name = 'Gravel / ore', kind = 'dryBulk', slots = 1, kg = 160 },
  { id = 'water', name = 'Water', kind = 'fluid', litres = 10, slots = 10, kg = 10, rate = 1 },
  { id = 'fuel', name = 'Fuel', kind = 'fluid', litres = 10, slots = 10, kg = 7.5, rate = 1 },
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
