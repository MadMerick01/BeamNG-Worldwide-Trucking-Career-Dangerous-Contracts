-- The places you trade at: the generated list in placesData.lua (built offline by
-- tools/make_places.py from GeoNames) and lookups on it. No game globals.
-- The list is small for now (the Sydney region), so lookups scan it; a lat/lon grid index can
-- come with the worldwide list.
local location = require('earthFreight/location')
local data = require('earthFreight/placesData')
local M = { list = data.places, centre = data.centre }

-- How close you have to be to trade at a place, by its size: a city depot is bigger than a village store.
M.ARRIVAL_METRES = { city = 800, town = 500, village = 300 }
-- The nearby list shows straight-line distance times this, marked as an estimate of the road distance.
M.ROAD_FACTOR = 1.3

local byId = {}
for _, place in ipairs(M.list) do byId[place.id] = place end

function M.get(id) return byId[id] end

function M.arrivalMetres(place)
  return M.ARRIVAL_METRES[place.size] or M.ARRIVAL_METRES.village
end

-- The place whose arrival circle you are in (the nearest, if circles overlap), and how far its
-- centre is; nil when you are at none.
function M.at(point)
  local best, bestDistance
  for _, place in ipairs(M.list) do
    local d = location.distance(point, place)
    if d and d <= M.arrivalMetres(place) and (not bestDistance or d < bestDistance) then best, bestDistance = place, d end
  end
  return best, bestDistance
end

-- The n places nearest a point, nearest first, as { place, metres }; except leaves one place out.
function M.nearest(point, n, except)
  local found = {}
  for _, place in ipairs(M.list) do
    if place.id ~= except then
      local d = location.distance(point, place)
      if d then found[#found + 1] = { place = place, metres = d } end
    end
  end
  table.sort(found, function(a, b)
    if a.metres ~= b.metres then return a.metres < b.metres end
    return a.place.id < b.place.id
  end)
  local out = {}
  for i = 1, math.min(n, #found) do out[i] = found[i] end
  return out
end

-- The n places whose estimated road distance from point is closest to roadMetres, nearest first,
-- as { place, metres } with metres the straight-line distance like nearest.
function M.around(point, roadMetres, n, except)
  local found = {}
  for _, place in ipairs(M.list) do
    if place.id ~= except then
      local d = location.distance(point, place)
      if d then found[#found + 1] = { place = place, metres = d, off = math.abs(d * M.ROAD_FACTOR - roadMetres) } end
    end
  end
  table.sort(found, function(a, b)
    if a.off ~= b.off then return a.off < b.off end
    return a.place.id < b.place.id
  end)
  local out = {}
  for i = 1, math.min(n, #found) do out[i] = { place = found[i].place, metres = found[i].metres } end
  table.sort(out, function(a, b)
    if a.metres ~= b.metres then return a.metres < b.metres end
    return a.place.id < b.place.id
  end)
  return out
end

-- The estimated road distance between two points, in metres.
function M.roadEstimate(a, b)
  local d = location.distance(a, b)
  return d and d * M.ROAD_FACTOR or nil
end

return M
