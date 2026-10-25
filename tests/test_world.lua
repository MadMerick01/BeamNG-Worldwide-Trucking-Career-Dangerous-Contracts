local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local goods = require('earthFreight/goods')
local config = require('earthFreight/config')
local location = require('earthFreight/location')

local function named(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end

-- Only the tiles around the start are there at first.
local penrith = places.get(config.START_PLACE)
T.eq(penrith.region, 'Australia', 'Penrith is named after its country')
T.near(places.boost(penrith), 1, 1e-9, 'flat Sydney pays 1x')
T.eq(places.get('gn3919085'), nil, 'Coroico is not loaded yet')
T.eq(places.tileKey(-33.75, 150.7), 's35e150', 'tile names')
T.eq(places.tileKey(-16.19, -67.73), 's20w70', 'tile names west of Greenwich')
T.eq(places.tileKey(46.5, 10.4), 'n45e10', 'tile names north')
T.eq(places.tileKey(0, 179.9), 'n0e175', 'tile names at the date line')
T.eq(places.tileKey(0, 180), 'n0w180', 'longitude 180 wraps')

-- The Blue Mountains pay about 1.5x.
local katoomba = named('Katoomba')
T.eq(katoomba.region, 'Blue Mountains', 'Katoomba is in the Blue Mountains')
T.check(katoomba.boost >= 1.3 and katoomba.boost <= 1.7, 'Katoomba pays about 1.5x: ' .. katoomba.boost)
for _, p in ipairs(places.list) do
  T.check(p.boost >= 1 and p.boost <= places.maxBoost, p.name .. ' boost is from 1x to 3x')
  T.check(type(p.region) == 'string' and #p.region > 0, p.name .. ' has a region')
end

-- Driving to Bolivia loads the tiles there.
local coroicoPoint = { latitude = -16.19386, longitude = -67.72998 }
T.check(places.ensure(coroicoPoint) > 0, 'tiles load near the player')
T.eq(places.ensure(coroicoPoint), 0, 'and only once')
local coroico = places.get('gn3919085')
T.eq(coroico.name, 'Coroico', 'Coroico is loaded')
T.eq(coroico.region, 'Death Road', 'Coroico is on Death Road')
T.check(coroico.boost >= 2.7, 'Death Road pays near 3x: ' .. coroico.boost)
T.eq(places.at(coroicoPoint).id, coroico.id, 'at Coroico')
local laPaz = places.get('gn3911925')
T.check(laPaz.boost > 1.5 and laPaz.boost < coroico.boost, 'La Paz pays less than the road down from it')

-- Lookups match a scan of every loaded place.
local function scanNearest(point, n, except)
  local found = {}
  for _, p in ipairs(places.list) do
    if p.id ~= except then found[#found + 1] = { place = p, metres = location.distance(point, p) } end
  end
  table.sort(found, function(a, b) if a.metres ~= b.metres then return a.metres < b.metres end return a.place.id < b.place.id end)
  return found
end
for _, point in ipairs({ coroicoPoint, config.START, { latitude = -20.5, longitude = -68.9 } }) do
  local fast, slow = places.nearest(point, 6), scanNearest(point, 6)
  for i = 1, 6 do T.eq(fast[i].place.id, slow[i].place.id, 'nearest matches a full scan ' .. i) end
  for _, km in ipairs({ 5, 25, 50 }) do
    local list = places.around(point, km * 1000, 6)
    local byOff = {}
    for _, p in ipairs(slow) do byOff[#byOff + 1] = { id = p.place.id, off = math.abs(p.metres * places.ROAD_FACTOR - km * 1000) } end
    table.sort(byOff, function(a, b) if a.off ~= b.off then return a.off < b.off end return a.id < b.id end)
    local want = {}
    for i = 1, 6 do want[byOff[i].id] = true end
    local same = #list == 6
    for _, d in ipairs(list) do same = same and want[d.place.id] == true end
    T.check(same, km .. ' km drop-offs match a full scan')
  end
end

-- The boost becomes a road bonus on a job's pay, at the average of its two ends.
local yolosaRun = places.nearest(coroico, 1, coroico.id)[1].place
T.near(jobs.roadBonus(coroico, laPaz), math.min(2, 1 + ((coroico.boost + laPaz.boost) / 2 - 1) / 2), 1e-9, 'the road bonus is from the average boost')
local run = { id = 'food_' .. yolosaRun.id, good = 'food', from = coroico.id, to = yolosaRun.id, km = jobs.roadKm(coroico, yolosaRun) }
local q = jobs.quote(run, 10, {}, 0)
T.check(q.road > 1.8, 'Death Road jobs pay nearly double: ' .. q.road)
T.near(q.pay, jobs.basePay(goods.get('food'), 10, run.km) * q.factor * q.road, 5, 'the road bonus is in the pay')

-- Searching by name loads the places found, biggest first, and folds accents and case.
do
  local found = places.search('La Paz', 6)
  T.eq(#found, 6, 'six La Pazes'); T.eq(found[1].name, 'La Paz', 'exact names first')
  T.eq(found[1].size, 'city', 'the biggest first')
  local zurich = places.search('zurich', 3)
  T.check(#zurich > 0 and zurich[1].name:find('rich') ~= nil, 'zurich finds Zürich: ' .. tostring(zurich[1] and zurich[1].name))
  T.eq(places.search('CHAMONIX', 1)[1].region, 'France', 'any case, with the region')
  local prefix = places.search('Coroi', 6)
  T.check(#prefix >= 1 and prefix[1].name == 'Coroico', 'the start of a name is enough')
  T.eq(#places.search('x', 6), 0, 'one letter is too short')
  T.eq(#places.search('qqqqzzzz', 6), 0, 'nothing for a made-up name')
  T.eq(places.searchKey('  Saint-Jean, du Gard '), 'saint jean du gard', 'queries fold like the list')
  local first = places.search('1 decembrie', 1)
  T.eq(#first, 1, 'the first line of the list is found too')
end

-- A tile with nothing in it (the sea) loads nothing.
T.eq(places.ensure({ latitude = -40, longitude = -130 }), 0, 'the open sea has no places')
T.done('worldwide places')
