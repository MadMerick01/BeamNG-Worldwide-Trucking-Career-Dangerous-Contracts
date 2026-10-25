local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local places = require('earthFreight/places')
local market = require('earthFreight/market')
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

-- Prices are fixed per place and good, within the spread, and the same every time.
local food = goods.get('food')
local p1, p2 = market.price(penrith, food), market.price(penrith, food)
T.eq(p1, p2, 'prices are stable')
local differ = false
for _, n in ipairs(near) do
  local f = market.factor(n.place, food)
  T.check(f >= market.MIN_FACTOR * 0.9 - 1e-9 and f <= market.MAX_FACTOR * 1.1 + 1e-9, 'factor within the spread')
  if market.price(n.place, food) ~= p1 then differ = true end
end
T.check(differ, 'prices differ between places')
T.eq(market.payout(penrith, food, 3, 0.5), math.floor(p1 * 3 * 0.5 + 0.5), 'payout cut by condition')
-- Freight pay: per tonne, per estimated road km from where the load was bought.
do
  local far = places.nearest(penrith, 1, penrith.id)[1].place
  local km = location.distance(penrith, far) / 1000 * places.ROAD_FACTOR
  local rate = market.FREIGHT_PER_TONNE_KM * (1 + km / market.LONG_HAUL_KM)
  local perSlot = km * food.kgPerSlot / 1000 * rate
  T.near(market.freightPerSlot(penrith, far, food), perSlot, 1e-9, 'freight is per tonne per road km')
  T.near(market.freightPerSlot(penrith, far, goods.get('bricks')), km * 0.12 * rate, 1e-9, 'heavier goods earn more')
  T.eq(market.freightPerSlot(penrith, penrith, food), 0, 'no freight for no distance')
  T.near(market.freightRate(0), market.FREIGHT_PER_TONNE_KM, 1e-9, 'short runs pay the base rate')
  T.near(market.freightRate(market.LONG_HAUL_KM), 2 * market.FREIGHT_PER_TONNE_KM, 1e-9, 'a long haul pays twice the rate per km')
  T.eq(market.freightPerSlot(nil, far, food), 0, 'no freight without an origin')
  local price = market.price(far, food)
  T.eq(market.payout(far, food, 4, 1, penrith), math.floor((price + perSlot) * 4 + 0.5), 'payout adds freight')
  T.eq(market.payout(far, food, 4, 0.5, penrith), math.floor((price + perSlot) * 4 * 0.5 + 0.5), 'damage cuts freight too')
end
T.near(market.drivenNeeded(penrith, near[1].place), near[1].metres * 0.7, 1e-6, '70% of the straight line must be driven')
T.done('places and market')

-- Drop-offs around a delivery distance.
do
  for _, km in ipairs({ 5, 25, 50 }) do
    local list = places.around(penrith, km * 1000, 6, penrith.id)
    T.eq(#list, 6, km .. ' km: six drop-offs')
    local worst = 0
    for i, d in ipairs(list) do
      T.check(d.place.id ~= penrith.id, 'never the place itself')
      if i > 1 then T.check(d.metres >= list[i - 1].metres, 'nearest first') end
      worst = math.max(worst, math.abs(d.metres * places.ROAD_FACTOR - km * 1000))
    end
    T.check(worst < 4000, km .. ' km: all within 4 km of the distance (worst ' .. math.floor(worst) .. ' m)')
  end
end
