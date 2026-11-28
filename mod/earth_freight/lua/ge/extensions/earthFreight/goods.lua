-- The goods, how they are carried and what a job pays for them. Each maps onto one of BeamNG's
-- cargo types (parcel, dryBulk, fluid). Parcels go in cargo boxes and fluids in fluid tanks; dry
-- bulk waits for trays and trucks. Tune these after testing in game.
local M = {}

-- A parcel unit takes this many slots and weighs this many kg. A fluid unit is `litres` litres
-- (its slots are those litres too, so a load's slots are its litres) of this many kg. Pay goes by
-- the load's weight (jobs.weightPay); rate is a good's pay against that, 1 being the curve as is.
-- A job fills every slot or litre the vehicle has. Before jobs.PAY_PERCENT (75, so a quarter less), a Burnside with 52 slots of boxes carries
-- 780 kg of parts for $2,000 over 5 km, or 1,200 kg of bricks (8 units with 3 L boxes and an
-- M: the weight runs out first) for about $2,480; a full 800 L tank is 800 kg of water for about $2,030, or the same weight of
-- fuel for about $1,540 (fuel weighs as water but pays by 600 kg). Parcels are heavy for their slots (bricks 50 kg
-- a slot), so a big box runs out of weight before space. Food is no longer posted; it stays known
-- so a food job in an older save still delivers.
-- WEIGHT_PERCENT scales what every good weighs (85: everything 15% lighter, MadMerick, 3 Nov). Pay
-- still goes by the full weight (payKg), so a unit pays what it did; the lighter load just fits
-- more bricks in a box and sits easier on the car.
M.WEIGHT_PERCENT = 85
M.list = {
  { id = 'parts', name = 'Parts', kind = 'parcel', slots = 1, kg = 15, rate = 1 },
  { id = 'food', name = 'Food', kind = 'parcel', slots = 2, kg = 50, rate = 1, retired = true },
  { id = 'bricks', name = 'Bricks', kind = 'parcel', slots = 3, kg = 150, rate = 1 },
  { id = 'grain', name = 'Grain', kind = 'dryBulk', slots = 1, kg = 80 },
  { id = 'gravel', name = 'Gravel / ore', kind = 'dryBulk', slots = 1, kg = 160 },
  { id = 'water', name = 'Water', kind = 'fluid', litres = 10, slots = 10, kg = 10, rate = 1 },
  -- Fuel weighs as much as water (MadMerick, 18 Nov: simpler, and the game's tankers weigh their
  -- Load Volume that way too), but still pays by its old 7.5 kg a unit, so its pay is unchanged.
  { id = 'fuel', name = 'Fuel', kind = 'fluid', litres = 10, slots = 10, kg = 10, payKg = 7.5, rate = 1 },
  -- What a "don't ask questions" job carries (beacons.lua): never posted on a board, and no weight.
  { id = 'package', name = 'Package', kind = 'package', slots = 1, kg = 0 },
  -- The special delivery's precursor chemicals (special.lua), solid in cargo boxes or fluid in a tank: only on its
  -- own card, never posted on a board. A unit of crates is heavy for its slot, so a box fills by weight: 100 kg, 85
  -- after WEIGHT_PERCENT (MadMerick, 28 Nov: 4 times the old 25 kg), so an XL box takes 29 and a full run needs a truck.
  { id = 'precursors', name = 'Precursor chemicals', kind = 'parcel', slots = 1, kg = 100, rate = 1, special = true },
  { id = 'precursors_fluid', name = 'Liquid precursor chemicals', kind = 'fluid', litres = 10, slots = 10, kg = 10, rate = 1, special = true },
  -- Ship Day's container cargo, from before Mayday Rescue replaced it: kept so a container still on board delivers.
  { id = 'container', name = 'Container cargo', kind = 'parcel', slots = 2, kg = 30, rate = 2, retired = true },
}
-- The cargo kinds the mod can carry yet.
M.CARRIED = { parcel = true, fluid = true }

local byId = {}
for _, good in ipairs(M.list) do
  good.payKg = good.payKg or good.kg
  good.kg = good.kg * M.WEIGHT_PERCENT / 100
  byId[good.id] = good
end

function M.get(id) return byId[id] end

-- The goods jobs are posted for, in list order.
function M.carried()
  local out = {}
  for _, good in ipairs(M.list) do if M.CARRIED[good.kind] and not good.retired and not good.special then out[#out + 1] = good end end
  return out
end

-- The goods of one kind that jobs are posted for, in list order.
function M.ofKind(kind)
  local out = {}
  for _, good in ipairs(M.carried()) do if good.kind == kind then out[#out + 1] = good end end
  return out
end

return M
