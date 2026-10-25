local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local config = require('earthFreight/config')
local location = require('earthFreight/location')

-- The generated list: the Sydney region around Penrith, about 4 km apart.
T.check(#places.list > 30, 'a useful number of places'); T.eq(places.list[1].id:sub(1, 2), 'gn', 'GeoNames ids')
local seen, names = {}, {}
for _, p in ipairs(places.list) do
  T.check(location.valid(p), p.name .. ' has valid coordinates')
  T.check(places.ARRIVAL_METRES[p.size] ~= nil, p.name .. ' has a known size')
  T.check(not seen[p.id], p.name .. ' id is unique'); seen[p.id] = true; names[p.name] = p
end
for _, name in ipairs({ 'Penrith', 'Katoomba', 'Lithgow', 'Richmond', 'Sydney', 'Parramatta' }) do
  T.check(names[name] ~= nil, name .. ' is in the list')
end
local closest = math.huge
for i, a in ipairs(places.list) do
  for j = i + 1, #places.list do closest = math.min(closest, location.distance(a, places.list[j])) end
end
T.check(closest >= 4000, 'places are at least 4 km apart')

-- The start is Penrith.
local penrith = places.get(config.START_PLACE)
T.eq(penrith.name, config.START_TOWN, 'start place is Penrith')
T.eq(penrith.latitude, config.START.latitude, 'start coordinates are Penrith')

-- Lookups.
T.eq(places.at(penrith).id, penrith.id, 'at Penrith')
T.eq(places.at(location.destination(penrith, 0, 400)).id, penrith.id, 'inside the town circle')
T.eq(places.at(location.destination(penrith, 0, 3000)), nil, 'outside every circle')
local near = places.nearest(penrith, 6, penrith.id)
T.eq(#near, 6, 'six nearest'); T.check(near[1].metres <= near[6].metres, 'nearest first')
for _, n in ipairs(near) do T.check(n.place.id ~= penrith.id, 'the place itself left out') end
T.near(places.roadEstimate(penrith, near[1].place), near[1].metres * 1.3, 1e-6, 'road estimate is 1.3 times straight line')

-- Job pay: a good's pay per unit, for every unit the car takes, growing faster than distance.
local jobs = require('earthFreight/jobs')
local cargo = require('earthFreight/cargo')
local food, parts, bricks = goods.get('food'), goods.get('parts'), goods.get('bricks')
T.near(jobs.distanceFactor(5), 1, 1e-9, '5 km is the base')
T.near(jobs.distanceFactor(20), 6, 1e-9, '20 km pays six times 5 km')
T.check(jobs.distanceFactor(10) > 2 and jobs.distanceFactor(15) > 3 * jobs.distanceFactor(5), 'pay grows faster than distance')
T.near(jobs.distanceFactor(40), 6 * math.sqrt(2), 1e-9, 'and flattens past 20 km')
local starter = { slots = 20, kg = 1000 }
T.eq(cargo.fits(starter, parts), 20, 'the starter car takes 20 parts')
T.eq(cargo.fits(starter, food), 10, '10 food')
local units, slots, kg = cargo.fits(starter, bricks)
T.eq(units, 6, '6 bricks: the weight runs out first'); T.eq(slots, 18, 'in 18 slots'); T.eq(kg, 900, 'weighing 900 kg')
T.eq(cargo.fits({ slots = 2, kg = 60 }, bricks), 0, 'no bricks in the boot')
T.near(jobs.basePay(parts, 20, 5), 1700, 1e-6, 'a full load of parts pays $1,700 over 5 km')
T.near(jobs.basePay(food, 10, 5), 2000, 1e-6, 'food $2,000')
T.near(jobs.basePay(bricks, 6, 5), 2400, 1e-6, 'bricks $2,400')
T.near(jobs.basePay(food, 10, 20), 12000, 1e-6, 'food $12,000 over 20 km')
-- Rough roads: half the region boost above 1, at most 2x.
T.near(jobs.roadBonusFor(1), 1, 1e-9, 'flat roads add nothing'); T.near(jobs.roadBonusFor(1.5), 1.25, 1e-9, 'the Blue Mountains')
T.near(jobs.roadBonusFor(3), 2, 1e-9, 'Death Road doubles'); T.near(jobs.roadBonusFor(5), 2, 1e-9, 'never more than 2x')

-- Town need: within 30% of the base, lowered by each delivery, recovering over the hours after.
do
  local differ = false
  for _, n in ipairs(near) do
    for _, good in ipairs(goods.carried()) do
      local need = jobs.need(n.place, good, {}, 0)
      T.check(need >= 0.7 - 1e-9 and need <= 1.3 + 1e-9, n.place.name .. ' needs ' .. good.id .. ' within 30%')
      if math.abs(need - jobs.need(penrith, food, {}, 0)) > 1e-6 then differ = true end
    end
  end
  T.check(differ, 'needs differ between towns')
  local town, needs, now = near[1].place, {}, 100000
  local first = jobs.need(town, food, needs, now)
  jobs.delivered(needs, town, food, now); local second = jobs.need(town, food, needs, now)
  jobs.delivered(needs, town, food, now); local third = jobs.need(town, food, needs, now)
  T.check(second < first and third < second, 'each delivery lowers the need')
  T.check(first - third >= 0.25 or third <= jobs.MIN_NEED + 1e-9, 'the third run pays clearly less')
  T.near(jobs.saturation(needs, town, food, now + 3600), jobs.saturation(needs, town, food, now) / 2, 1e-9, 'half recovers in an hour')
  T.eq(jobs.need(town, parts, needs, now), jobs.need(town, parts, {}, now), 'other goods are not touched')
  jobs.delivered(needs, town, parts, now + 86400)
  T.eq(needs[town.id .. ':food'], nil, 'recovered deliveries are cleared')
  T.eq(select(2, jobs.character({ id = 'x', size = 'city' })), 'parts', 'cities want parts')
end

-- Shortages: rare, fixed for their hour, and paying double.
do
  local count, total = 0, 0
  for hour = 0, 199 do
    for _, n in ipairs(near) do
      total = total + 1
      local short, left = jobs.shortage(n.place, food, hour * 3600 + 10)
      if short then
        count = count + 1
        T.eq(left, 3590, 'a shortage lasts to the end of its hour')
        T.eq(jobs.shortage(n.place, food, hour * 3600 + 3000), true, 'the whole hour')
      end
    end
  end
  T.check(count > 0 and count < total * 0.03, 'shortages are rare: ' .. count .. ' of ' .. total)
end

-- The board: 3 to 5 jobs within 20 km, always one decent, the same until a job is done.
do
  local jackpots, jobsSeen, sweet = 0, 0, 0
  for _, n in ipairs(places.nearest(penrith, 20)) do
    for seed = 0, 9 do
      local board = jobs.board(n.place, seed, {}, 5000)
      local drop = table.remove(board)
      T.check(drop.drop ~= nil and drop.to == n.place.id and drop.id:match('^drop_%l+_[%w_]+$') ~= nil, n.place.name .. ' ends its board with an off-road drop')
      local metres = location.distance(n.place, drop.drop)
      T.check(metres >= jobs.DROP_MIN - 1 and metres <= jobs.DROP_MAX + 1, 'the drop spot is 1.8 to 3.2 km out: ' .. math.floor(metres))
      T.near(drop.km, metres / 1000, 1e-9, 'its distance is the straight line')
      T.check(#board >= 3 and #board <= 5, n.place.name .. ' posts 3 to 5 jobs')
      local ids, decent = { [drop.id] = true }, false
      for _, j in ipairs(board) do
        T.check(not ids[j.id], 'each job once'); ids[j.id] = true
        T.check(j.km <= jobs.MAX_KM + 1e-9 and j.to ~= n.place.id, 'jobs go to another town within 20 km')
        local q = jobs.quote(j, 10, {}, 5000)
        if q.factor >= 1 then decent = true end
        if j.jackpot then
          jackpots = jackpots + 1
          T.check(j.jackpot >= 2 and j.jackpot <= 3, 'a jackpot pays 2x to 3x')
        end
        jobsSeen = jobsSeen + 1
      end
      T.check(decent, n.place.name .. ' has a decent job')
    end
  end
  T.check(jackpots > 0 and jackpots < jobsSeen * 0.12, 'about one job in 20 is a jackpot: ' .. jackpots .. ' of ' .. jobsSeen)
  local a, b = jobs.board(penrith, 3, {}, 5000), jobs.board(penrith, 3, {}, 5000)
  T.eq(a[1].id, b[1].id, 'a board stays the same')
  local changed = false
  for seed = 4, 8 do if jobs.board(penrith, seed, {}, 5000)[1].id ~= a[1].id then changed = true end end
  T.check(changed, 'and changes after a job')
  -- A job's pay: base times need, shortage and jackpot, times the road bonus, in tens of dollars.
  local j = a[1]
  local q = jobs.quote(j, 10, {}, 5000)
  T.eq(q.pay % 10, 0, 'whole tens of dollars')
  T.near(q.pay, jobs.basePay(goods.get(j.good), 10, j.km) * q.factor * q.road, 5, 'pay is the base times the bonuses')
  T.eq(jobs.quote(j, 0, {}, 5000).pay, 0, 'nothing for an empty car')
  local bigger = jobs.quote(j, 20, {}, 5000).pay
  T.check(bigger > q.pay * 1.9, 'a bigger car earns more')
end
-- The off-road drop: any good, fixed for a seed, paying like a 5 km job times the steep-ground bonus.
do
  local seen, bearings = {}, {}
  for seed = 0, 59 do
    local d = jobs.dropJob(penrith, seed)
    seen[d.good] = true
    bearings[math.floor(location.bearing(penrith, d.drop) / 90)] = true
    T.check(goods.get(d.good).kind == 'parcel', 'a good that can be carried')
  end
  T.check(seen.parts and seen.food and seen.bricks, 'parts, food and bricks all come up')
  T.check(bearings[0] and bearings[1] and bearings[2] and bearings[3], 'the spot can be any way out of town')
  local a, b = jobs.dropJob(penrith, 7), jobs.dropJob(penrith, 7)
  T.eq(a.drop.latitude, b.drop.latitude, 'the same spot for the same board'); T.eq(a.id, b.id, 'and the same job')
  T.check(jobs.dropJob(penrith, 8).drop.latitude ~= a.drop.latitude, 'a new spot after a job')
  local good = goods.get(a.good)
  local q = jobs.quote(a, 6, {}, 5000)
  T.near(q.pay, jobs.basePay(good, 6, 5) * (a.jackpot or 1) * jobs.steepBonus(penrith), 5, 'pays like a 5 km job')
  T.eq(q.shortage, false, 'no shortages off road'); T.eq(q.need, 1, 'and no town need')
  T.eq(jobs.steepBonus({ id = 'x', boost = 1 }), 1, 'flat ground pays the base')
  T.eq(jobs.steepBonus({ id = 'x', boost = 1.5 }), 1.5, 'steep ground pays the whole region boost')
  T.eq(jobs.steepBonus({ id = 'x', boost = 3 }), 2, 'at most twice')
end
T.near(jobs.drivenNeeded(penrith, near[1].place), near[1].metres * 0.7, 1e-6, '70% of the straight line must be driven')
T.done('places and jobs')
