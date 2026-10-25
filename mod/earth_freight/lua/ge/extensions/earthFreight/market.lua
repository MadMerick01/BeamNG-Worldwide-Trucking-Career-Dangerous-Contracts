-- Prices. For now every price is fixed: a place's price for a good is the good's base price times
-- a factor from a seeded hash of the place and the good, the place's size, and its region pay
-- boost. Nothing is stored and nothing changes as you trade; supply and demand come later. No game
-- globals.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local M = {}

-- One-line settings. Tune these after testing in game.
M.MIN_FACTOR, M.MAX_FACTOR = 0.7, 1.3 -- the seeded spread of a place's prices
-- Big places pay less per load; small ones pay more.
M.SIZE_FACTOR = { city = 0.9, town = 1, village = 1.1 }
-- The HUD's dots: a factor below CHEAP is stocked (green, good to buy), above SHORT is short (red, pays well).
M.CHEAP, M.SHORT = 0.9, 1.1
-- Freight pay: every delivery also pays this much per tonne carried for each estimated road km
-- (straight line times the road factor) from where the load was bought, so every run is worth
-- driving and heavy loads earn more for the distance (and burn more fuel getting there).
M.FREIGHT_PER_TONNE_KM = 20
-- Longer runs pay more per km, to make the risk worth it: the rate grows by its own size every
-- LONG_HAUL_KM, so a 50 km run pays twice the per-km rate of a very short one.
M.LONG_HAUL_KM = 50
-- The region pay boost (1x on flat, busy ground up to 3x in steep, remote, high places, scored by
-- tools/make_places.py) multiplies everything a place pays and charges, and the freight pay of a
-- run at the average of its two ends: runs within a steep region pay that much more, and a run
-- up into one pays more than the run back down.
-- A load only sells at a place once you have driven at least this share of the straight-line
-- distance from where it was bought, so a teleport or a lift never delivers.
M.DRIVEN_SHARE = 0.7

-- A number in [0, 1) fixed for this text: a small polynomial hash, the same on every machine.
local function hash01(text)
  local h = 7
  for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
  return h / 2147483647
end

-- How dear a good is at a place compared with its base price.
function M.factor(place, good)
  local spread = M.MIN_FACTOR + (M.MAX_FACTOR - M.MIN_FACTOR) * hash01(place.id .. ':' .. good.id)
  return spread * (M.SIZE_FACTOR[place.size] or 1)
end

-- Whole dollars for one slot of a good at a place; what you pay to buy it there and what you are
-- paid to deliver it there.
function M.price(place, good)
  return math.max(1, math.floor(good.basePrice * M.factor(place, good) * places.boost(place) + 0.5))
end

-- The pay boost of a run from one place to another: the average of its two ends.
function M.runBoost(from, to)
  return (places.boost(from) + places.boost(to)) / 2
end

-- 'cheap', 'short' or 'normal', for the HUD's dots.
function M.level(place, good)
  local f = M.factor(place, good)
  if f < M.CHEAP then return 'cheap' end
  if f > M.SHORT then return 'short' end
  return 'normal'
end

-- The distance a load must have been driven before it sells at a place, in metres.
function M.drivenNeeded(from, to)
  local d = location.distance(from, to)
  return d and d * M.DRIVEN_SHARE or math.huge
end

-- The freight rate per tonne per km for a run of this many road km.
function M.freightRate(roadKm)
  return M.FREIGHT_PER_TONNE_KM * (1 + math.max(0, roadKm) / M.LONG_HAUL_KM)
end

-- Freight pay for one slot of a good carried from one place to another, in dollars (not rounded).
function M.freightPerSlot(from, to, good)
  local d = from and to and good and location.distance(from, to)
  if not d then return 0 end
  local km = d / 1000 * places.ROAD_FACTOR
  return km * good.kgPerSlot / 1000 * M.freightRate(km) * M.runBoost(from, to)
end

-- What a load bought at from pays on delivery at a place: its slots at the place's price plus the
-- freight pay, all cut by cargo damage.
function M.payout(place, good, slots, condition, from)
  local c = type(condition) == 'number' and math.max(0, math.min(1, condition)) or 1
  return math.floor((M.price(place, good) + M.freightPerSlot(from, place, good)) * slots * c + 0.5)
end

return M
