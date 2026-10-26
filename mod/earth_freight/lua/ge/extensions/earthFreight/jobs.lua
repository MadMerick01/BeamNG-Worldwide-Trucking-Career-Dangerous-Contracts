-- The job board: what each town offers and what a job pays. Nothing is bought: a job fills every
-- slot the vehicle has with one good, for one total pay, locked in when it is taken. Pay grows
-- faster than distance, varies with the drop-off town's need for the good, and pays more on
-- treacherous roads, in shortages and on the odd jackpot job. Pure maths; the time (wall-clock
-- seconds) and the need record come from the controller. No game globals.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local M = {}

-- One-line settings. Tune these after testing in game.
-- Pay by weight: a full load of PAY_KG kg (the starter Burnside's 52 slots of parts) pays
-- PAY_DOLLARS over 5 km. Heavier loads pay more, but less a kg: pay grows as (kg / PAY_KG) ^
-- WEIGHT_POWER, so 2,000 kg pays about $3,600, 8,000 kg about $8,700, 10,000 kg about $10,000
-- and 12,000 kg about $11,200. Lighter loads pay a straight share by weight, so 300 kg pays
-- about $770 and a car boot of parts doesn't out-earn a cargo box. PAY_PERCENT
-- scales every job's pay, for balance testing: 120 pays a fifth more, 80 a fifth less. A good's
-- rate (goods.lua) scales its own pay.
M.PAY_PERCENT = 100
M.PAY_DOLLARS, M.PAY_KG, M.WEIGHT_POWER = 2000, 780, 0.63
-- Pay grows as (km / 5) ^ DISTANCE_POWER up to FLAT_KM, so 20 km pays 6 times 5 km; past that it
-- only grows with the square root.
M.BASE_KM, M.FLAT_KM = 5, 20
M.DISTANCE_POWER = math.log(6) / math.log(4)
-- Jobs go at most this far by road (the straight line times places.ROAD_FACTOR).
M.MAX_KM = 20
-- A board shows one job each of parts, bricks and the town's fluid, then the off-road drop. The
-- three town jobs take these road-distance bands in turn, from a seeded start, where the towns allow.
M.BANDS = { { 0, 8 }, { 8, 13 }, { 13, 20 } }
-- Town need: a seeded start between NEED_LOW and NEED_HIGH, plus CHARACTER_BONUS for the good the
-- town is known for, less what deliveries took. Always between MIN_NEED and MAX_NEED. The start
-- leans a little above the base, so most towns have something worth carrying and red is rare
-- until you have delivered there.
M.NEED_LOW, M.NEED_HIGH, M.CHARACTER_BONUS = 0.85, 1.25, 0.1
M.MIN_NEED, M.MAX_NEED = 0.7, 1.3
-- Each delivery lowers the town's need for that good by this much, recovering by half every
-- NEED_HALF_LIFE seconds.
M.DELIVERY_DROP, M.NEED_HALF_LIFE = 0.15, 3600
-- The board's colours: a job paying at least HIGH times its base is green, below LOW red.
M.HIGH, M.LOW = 1.1, 0.9
-- Shortages: each town and good has SHORTAGE_CHANCE of one in each SHORTAGE_SECONDS window, paying
-- SHORTAGE_PAY times. With about 30 towns within 20 km, a little over half the boards carry one.
M.SHORTAGE_CHANCE, M.SHORTAGE_SECONDS, M.SHORTAGE_PAY = 0.01, 3600, 2
-- About one job in 20 is a jackpot, paying 2 to 3 times.
M.JACKPOT_CHANCE, M.JACKPOT_MIN, M.JACKPOT_MAX = 0.05, 2, 3
-- The region pay boost (1 to 3) becomes a road bonus of 1 + (boost - 1) * ROAD_SHARE, at most 2.
M.ROAD_SHARE, M.MAX_ROAD = 0.5, 2
-- A job only delivers once you have driven at least this share of the straight-line distance
-- from where it was taken, so a teleport or a lift never delivers.
M.DRIVEN_SHARE = 0.7
-- The load slider: a job can be taken in shares of SHARE_STEP percent, from SHARE_STEP to 100.
M.SHARE_STEP = 10
-- What abandoning a job costs (or all the player's money, if less).
M.ABANDON_FEE = 1000
-- The off-road drop: one job on every board to a spot a random DROP_MIN to DROP_MAX metres from
-- town, off the roads, with no GPS route. It pays like a DROP_KM job, times the steep-ground
-- bonus: the region boost (1 to 3) as 1 + (boost - 1) * DROP_STEEP_SHARE, at most MAX_ROAD. It is
-- delivered stopped within DROP_RADIUS metres of the spot. The spot is not checked for water or
-- cliffs: reaching it is the player's risk.
M.DROP_MIN, M.DROP_MAX, M.DROP_KM, M.DROP_STEEP_SHARE, M.DROP_RADIUS = 1800, 3200, 5, 1, 100
-- The spot heads for a place within DROP_TOWARD metres, give or take DROP_SPREAD degrees, so it
-- leans inland rather than out to sea.
M.DROP_TOWARD, M.DROP_SPREAD = 15000, 30

-- A number in [0, 1) fixed for this text: a small polynomial hash, mixed so that texts differing
-- only at the end land far apart. The same on every machine.
local function hash01(text)
  local h = 7
  for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
  for _ = 1, 4 do h = (h * 48271) % 2147483647 end
  return h / 2147483647
end
M.hash01 = hash01

-- How much more than a 5 km job a job of this many road km pays.
function M.distanceFactor(km)
  km = math.max(0, km or 0)
  if km <= M.FLAT_KM then return (km / M.BASE_KM) ^ M.DISTANCE_POWER end
  return (M.FLAT_KM / M.BASE_KM) ^ M.DISTANCE_POWER * math.sqrt(km / M.FLAT_KM)
end

-- The estimated road km between two places.
function M.roadKm(from, to)
  local metres = places.roadEstimate(from, to)
  return metres and metres / 1000 or 0
end

-- The road bonus for a region pay boost: half the boost above 1, at most 2x.
function M.roadBonusFor(boost)
  return math.min(M.MAX_ROAD, 1 + ((boost or 1) - 1) * M.ROAD_SHARE)
end

-- The road bonus of a job: from the region boost at the average of its two ends.
function M.roadBonus(from, to)
  return M.roadBonusFor((places.boost(from) + places.boost(to)) / 2)
end

-- What a town is known for: cities want parts, and other towns are seeded as building towns
-- (bricks), farming towns (water) or neither. Returns the kind and the good, or nil.
function M.character(place)
  if place.size == 'city' then return 'city', 'parts' end
  local h = hash01(place.id .. ':character')
  if h < 0.3 then return 'building', 'bricks' end
  if h < 0.6 then return 'farming', 'water' end
  return nil
end

local function clampNeed(n) return math.max(M.MIN_NEED, math.min(M.MAX_NEED, n)) end

-- The town's need for a good before any deliveries.
function M.baseNeed(place, good)
  local _, known = M.character(place)
  return clampNeed(M.NEED_LOW + (M.NEED_HIGH - M.NEED_LOW) * hash01(place.id .. ':' .. good.id .. ':need')
    + (known == good.id and M.CHARACTER_BONUS or 0))
end

local function needKey(place, good) return place.id .. ':' .. good.id end

-- How much of a town's need for a good recent deliveries still take away, now.
function M.saturation(needs, place, good, now)
  local entry = needs and needs[needKey(place, good)]
  if not entry then return 0 end
  local age = math.max(0, (now or 0) - entry.at)
  return entry.drop * 0.5 ^ (age / M.NEED_HALF_LIFE)
end

-- The town's need for a good now, from MIN_NEED to MAX_NEED.
function M.need(place, good, needs, now)
  return clampNeed(M.baseNeed(place, good) - M.saturation(needs, place, good, now))
end

-- Records a delivery: the town's need for that good drops, then recovers over time. Entries
-- that have all but recovered are cleared, so the save only keeps recent deliveries.
function M.delivered(needs, place, good, now)
  needs[needKey(place, good)] = { drop = M.saturation(needs, place, good, now) + M.DELIVERY_DROP, at = now }
  for key, entry in pairs(needs) do
    if entry.drop * 0.5 ^ (math.max(0, now - entry.at) / M.NEED_HALF_LIFE) < 0.005 then needs[key] = nil end
  end
end

-- Whether a town is short of a good now, and the seconds the shortage has left.
function M.shortage(place, good, now)
  local window = math.floor((now or 0) / M.SHORTAGE_SECONDS)
  if hash01(place.id .. ':' .. good.id .. ':short:' .. window) >= M.SHORTAGE_CHANCE then return false end
  return true, (window + 1) * M.SHORTAGE_SECONDS - now
end

-- Dollars a load of this many kg pays over 5 km at the base rate, before PAY_PERCENT.
function M.weightPay(kg)
  kg = math.max(0, kg or 0)
  if kg <= M.PAY_KG then return M.PAY_DOLLARS * kg / M.PAY_KG end
  return M.PAY_DOLLARS * (kg / M.PAY_KG) ^ M.WEIGHT_POWER
end

-- Dollars a job pays at the base rate: this many units of the good, by their weight, over this many km.
function M.basePay(good, units, km)
  return M.weightPay(units * good.kg) * (good.rate or 1) * M.PAY_PERCENT / 100 * M.distanceFactor(km)
end

-- 'high', 'normal' or 'low': a job's pay compared with its base, for the board's colours.
function M.level(factor)
  if factor >= M.HIGH then return 'high' end
  if factor < M.LOW then return 'low' end
  return 'normal'
end

local function round10(n) return math.floor(n / 10 + 0.5) * 10 end

-- The steep-ground bonus of an off-road drop from this place.
function M.steepBonus(place)
  return math.min(M.MAX_ROAD, 1 + (places.boost(place) - 1) * M.DROP_STEEP_SHARE)
end

-- What a job pays for this many units, now. Returns { pay, base, factor, need, road, shortage,
-- jackpot, level }: factor is the need, shortage and jackpot together, which the colour is from.
-- An off-road drop goes to no town, so it has no need or shortage: road is its steep-ground bonus.
function M.quote(job, units, needs, now)
  local good, from, to = goods.get(job.good), places.get(job.from), places.get(job.to)
  if job.drop then
    local factor, road = job.jackpot or 1, M.steepBonus(from)
    local base = M.basePay(good, units, M.DROP_KM)
    return { pay = units > 0 and math.max(10, round10(base * factor * road)) or 0, base = round10(base),
      factor = factor, need = 1, road = road, shortage = false, jackpot = job.jackpot,
      level = job.jackpot and 'sweet' or 'normal' }
  end
  local need = M.need(to, good, needs, now)
  if job.decent then need = math.max(1, need) end
  local short = M.shortage(to, good, now)
  local factor = need * (short and M.SHORTAGE_PAY or 1) * (job.jackpot or 1)
  local road = M.roadBonus(from, to)
  local base = M.basePay(good, units, job.km)
  return { pay = units > 0 and math.max(10, round10(base * factor * road)) or 0, base = round10(base),
    factor = factor, need = need, road = road, shortage = short, jackpot = job.jackpot,
    level = (short or job.jackpot) and 'sweet' or M.level(factor) }
end

-- The towns a board can send jobs to: every loaded place within MAX_KM by road, as { place, km };
-- with none that close, the three nearest.
function M.destinations(from)
  local out = {}
  for _, place in ipairs(places.within(from, M.MAX_KM * 1000 / places.ROAD_FACTOR)) do
    local km = M.roadKm(from, place)
    if place.id ~= from.id and km <= M.MAX_KM then out[#out + 1] = { place = place, km = km } end
  end
  if #out == 0 then
    for _, n in ipairs(places.nearest(from, 3, from.id)) do out[#out + 1] = { place = n.place, km = n.metres * places.ROAD_FACTOR / 1000 } end
  end
  table.sort(out, function(a, b) if a.km ~= b.km then return a.km < b.km end return a.place.id < b.place.id end)
  return out
end

local function jackpotFor(key)
  local h = hash01(key .. ':jackpot')
  if h >= M.JACKPOT_CHANCE then return nil end
  return math.floor((M.JACKPOT_MIN + (M.JACKPOT_MAX - M.JACKPOT_MIN) * h / M.JACKPOT_CHANCE) * 10 + 0.5) / 10
end

local function job(from, d, good, seed)
  local jackpot = jackpotFor(from.id .. ':' .. seed .. ':' .. d.place.id .. ':' .. good.id)
  return { id = good.id .. '_' .. d.place.id, good = good.id, from = from.id, to = d.place.id, km = d.km, jackpot = jackpot }
end

-- The fluid a town's board posts: water or fuel, fixed for the town.
function M.fluid(place)
  local fluids = goods.ofKind('fluid')
  return fluids[math.floor(hash01(place.id .. ':fluid') * #fluids) + 1]
end

-- The goods a town's board posts jobs for: the parcels (parts and bricks), then its fluid.
function M.boardGoods(place)
  local out = goods.ofKind('parcel')
  out[#out + 1] = M.fluid(place)
  return out
end

-- The board of a town: one job each for its goods, then the off-road drop, fixed for a seed (the
-- controller's count of jobs done), so it changes after every delivery or abandoned job. A good
-- short in a town close by goes there; otherwise each job goes to a town in its distance band. At
-- least one job is decent: if none pays its base rate, the best one is raised to it.
function M.board(from, seed, needs, now)
  local list = M.destinations(from)
  local wanted = M.boardGoods(from)
  if #list == 0 or #wanted == 0 then return {} end
  seed = tostring(seed or 0)
  local start = math.floor(hash01(from.id .. ':' .. seed .. ':band') * #M.BANDS)
  local out = {}
  for i, good in ipairs(wanted) do
    local d
    for _, x in ipairs(list) do if not d and M.shortage(x.place, good, now) then d = x end end
    if not d then
      local band = M.BANDS[(start + i - 1) % #M.BANDS + 1]
      local pool = {}
      for _, x in ipairs(list) do if x.km > band[1] and x.km <= band[2] then pool[#pool + 1] = x end end
      if #pool == 0 then pool = list end
      d = pool[math.floor(hash01(from.id .. ':' .. seed .. ':' .. good.id .. ':to') * #pool) + 1]
    end
    out[#out + 1] = job(from, d, good, seed)
  end
  local best, bestFactor
  for _, j in ipairs(out) do
    local f = M.quote(j, 1, needs, now).factor
    if not bestFactor or f > bestFactor then best, bestFactor = j, f end
  end
  if bestFactor < 1 then best.decent = true end
  out[#out + 1] = M.dropJob(from, seed)
  return out
end

-- Where a board's off-road drop is, for a seed: DROP_MIN to DROP_MAX metres out, heading for a
-- place nearby (give or take DROP_SPREAD degrees), or any way when there is none.
function M.dropPoint(from, seed)
  local key = from.id .. ':' .. tostring(seed or 0) .. ':drop'
  local toward = {}
  for _, p in ipairs(places.within(from, M.DROP_TOWARD)) do if p.id ~= from.id then toward[#toward + 1] = p end end
  table.sort(toward, function(a, b) return a.id < b.id end)
  local bearing
  if #toward > 0 then
    local p = toward[math.floor(hash01(key .. ':toward') * #toward) + 1]
    bearing = location.bearing(from, p) + (hash01(key .. ':spread') * 2 - 1) * M.DROP_SPREAD
  else
    bearing = hash01(key .. ':bearing') * 360
  end
  return location.destination(from, bearing % 360, M.DROP_MIN + (M.DROP_MAX - M.DROP_MIN) * hash01(key .. ':metres'))
end

-- A board's off-road drop job: parts or bricks, taken and paid like any job, delivered at the spot.
function M.dropJob(from, seed)
  seed = tostring(seed or 0)
  local carried = goods.ofKind('parcel')
  local good = carried[math.floor(hash01(from.id .. ':' .. seed .. ':drop:good') * #carried) + 1]
  local drop = M.dropPoint(from, seed)
  return { id = 'drop_' .. good.id .. '_' .. from.id, good = good.id, from = from.id, to = from.id,
    km = location.distance(from, drop) / 1000, drop = drop, jackpot = jackpotFor(from.id .. ':' .. seed .. ':drop:' .. good.id) }
end

-- A share of a job: the whole units it comes to (at least one) and their pay, a straight share
-- of the full load's pay in tens of dollars. share is a percentage.
function M.share(units, pay, share)
  if units <= 0 then return 0, 0 end
  local taken = math.max(1, math.min(units, math.floor(units * share / 100 + 0.5)))
  if taken == units then return units, pay end
  return taken, math.max(10, round10(pay * taken / units))
end

-- The distance a job must have been driven before it delivers, in metres.
function M.drivenNeeded(from, to)
  local d = location.distance(from, to)
  return d and d * M.DRIVEN_SHARE or math.huge
end

return M
