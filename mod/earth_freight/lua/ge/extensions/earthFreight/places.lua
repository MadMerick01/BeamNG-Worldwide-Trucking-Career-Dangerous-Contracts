-- The places you trade at, worldwide: the generated region tiles in tiles/ (built offline by
-- tools/make_places.py from GeoNames), loaded as you get near them, and lookups on them. No game
-- globals.
-- A tile is TILE_DEGREES square; ensure(point) loads the one the point is in and the eight around
-- it, so every place within a few hundred km is there. Tiles stay loaded once read. Lookups go
-- through a grid of CELL_DEGREES cells, so they only look at the places close by.
local location = require('earthFreight/location')
local config = require('earthFreight/config')
local index = require('earthFreight/placesIndex')
local M = { list = {}, maxBoost = index.maxBoost }

-- How close you have to be to trade at a place, by its size: a city depot is bigger than a village store.
M.ARRIVAL_METRES = { city = 800, town = 500, village = 300 }
-- The nearby list shows straight-line distance times this, marked as an estimate of the road distance.
M.ROAD_FACTOR = 1.3
M.TILE_DEGREES = index.tileDegrees
local CELL_DEGREES = 0.25
-- The farthest nearest() looks before giving up, in metres.
local SEARCH_LIMIT = 3000000
local SIZES = { c = 'city', t = 'town', v = 'village' }
local floor, max, min, cos, rad = math.floor, math.max, math.min, math.cos, math.rad

-- Reads a tile's module; tests replace it.
M.readTile = function(key)
  local name = 'earthFreight/tiles/' .. key
  local ok, tile = pcall(require, name)
  package.loaded[name] = nil -- the parsed places are kept, not the text
  return ok and tile or nil
end

local byId, cells, loaded = {}, {}, {}

local function cellKey(row, col) return row * 4000 + col end
local function cellOf(lat, lon) return floor((lat + 90) / CELL_DEGREES), floor((lon + 180) / CELL_DEGREES) end
local LON_CELLS = floor(360 / CELL_DEGREES)

-- The tile a point is in, named after its south-west corner, like s35e150.
function M.tileKey(lat, lon)
  local d = M.TILE_DEGREES
  local south = max(-90, min(90 - d, floor(lat / d) * d))
  local west = ((floor(lon / d) * d + 180) % 360) - 180
  return (south < 0 and 's' or 'n') .. math.abs(south) .. (west < 0 and 'w' or 'e') .. math.abs(west)
end

-- Adds a tile's places, once. Returns how many it added.
function M.loadTile(key)
  if loaded[key] then return 0 end
  loaded[key] = true
  if not index.tiles[key] then return 0 end
  local tile = M.readTile(key)
  if type(tile) ~= 'table' or type(tile.places) ~= 'string' then return 0 end
  local added = 0
  for line in tile.places:gmatch('[^\n]+') do
    local id, name, lat, lon, size, boost, region = line:match('^(%d+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(%a)\t(%d+)\t(%d+)$')
    if id and not byId['gn' .. id] then
      local place = { id = 'gn' .. id, name = name, latitude = tonumber(lat), longitude = tonumber(lon),
        size = SIZES[size] or 'village', boost = tonumber(boost) / 10, region = tile.regions[tonumber(region)] }
      byId[place.id] = place
      M.list[#M.list + 1] = place
      local row, col = cellOf(place.latitude, place.longitude)
      local k = cellKey(row, col)
      cells[k] = cells[k] or {}
      table.insert(cells[k], place)
      added = added + 1
    end
  end
  return added
end

-- Loads the tiles in and around the one a point is in. Returns how many places that added.
function M.ensure(point)
  if not location.valid(point) then return 0 end
  local added, d = 0, M.TILE_DEGREES
  for dy = -1, 1 do
    for dx = -1, 1 do
      local lat = point.latitude + dy * d
      if lat >= -90 and lat < 90 then added = added + M.loadTile(M.tileKey(lat, point.longitude + dx * d)) end
    end
  end
  return added
end

function M.get(id) return byId[id] end

-- The loaded places within about this many metres of a point (and some a little farther).
function M.within(point, metres)
  local out = {}
  if not location.valid(point) then return out end
  local dLat = metres / 111000
  local c = cos(rad(point.latitude))
  local row0, col0 = cellOf(max(-90, point.latitude - dLat), point.longitude)
  local row1 = cellOf(min(89.999, point.latitude + dLat), point.longitude)
  local cols = (c <= 0.01 or dLat / c >= 180) and LON_CELLS or (floor(dLat / c / CELL_DEGREES) + 1)
  cols = min(cols, floor(LON_CELLS / 2))
  for row = row0, row1 do
    for col = col0 - cols, col0 + cols do
      local list = cells[cellKey(row, col % LON_CELLS)]
      if list then for _, place in ipairs(list) do out[#out + 1] = place end end
    end
  end
  return out
end

function M.arrivalMetres(place)
  return M.ARRIVAL_METRES[place.size] or M.ARRIVAL_METRES.village
end

-- The place's pay boost, 1 when it has none.
function M.boost(place)
  return place and place.boost or 1
end

-- The place whose arrival circle you are in (the nearest, if circles overlap), and how far its
-- centre is; nil when you are at none.
function M.at(point)
  local best, bestDistance
  for _, place in ipairs(M.within(point, M.ARRIVAL_METRES.city)) do
    local d = location.distance(point, place)
    if d and d <= M.arrivalMetres(place) and (not bestDistance or d < bestDistance) then best, bestDistance = place, d end
  end
  return best, bestDistance
end

local function byDistance(a, b)
  if a.metres ~= b.metres then return a.metres < b.metres end
  return a.place.id < b.place.id
end

-- The n places nearest a point, nearest first, as { place, metres }; except leaves one place out.
function M.nearest(point, n, except)
  local found, radius = {}, 10000
  while true do
    found = {}
    for _, place in ipairs(M.within(point, radius)) do
      if place.id ~= except then
        local d = location.distance(point, place)
        if d and d <= radius then found[#found + 1] = { place = place, metres = d } end
      end
    end
    if #found >= n or radius >= SEARCH_LIMIT then break end
    radius = radius * 2
  end
  table.sort(found, byDistance)
  local out = {}
  for i = 1, min(n, #found) do out[i] = found[i] end
  return out
end

-- The n places whose estimated road distance from point is closest to roadMetres, nearest first,
-- as { place, metres } with metres the straight-line distance like nearest.
function M.around(point, roadMetres, n, except)
  local target = roadMetres / M.ROAD_FACTOR
  local margin, found = 10000, {}
  while true do
    local radius = target + margin
    -- Any place farther than radius is at least this far off the distance asked for.
    local bound = radius * M.ROAD_FACTOR - roadMetres
    found = {}
    local sure = 0
    for _, place in ipairs(M.within(point, radius)) do
      if place.id ~= except then
        local d = location.distance(point, place)
        if d and d <= radius then
          local off = math.abs(d * M.ROAD_FACTOR - roadMetres)
          found[#found + 1] = { place = place, metres = d, off = off }
          if off <= bound then sure = sure + 1 end
        end
      end
    end
    if sure >= n or radius >= SEARCH_LIMIT then break end
    margin = margin * 2
  end
  table.sort(found, function(a, b)
    if a.off ~= b.off then return a.off < b.off end
    return a.place.id < b.place.id
  end)
  local out = {}
  for i = 1, min(n, #found) do out[i] = { place = found[i].place, metres = found[i].metres } end
  table.sort(out, byDistance)
  return out
end

-- The estimated road distance between two points, in metres.
function M.roadEstimate(a, b)
  local d = location.distance(a, b)
  return d and d * M.ROAD_FACTOR or nil
end

-- A new game starts at the start town, so its tiles are always there.
M.ensure(config.START)

return M
