local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('earthFreight/persistence')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local jobs = require('earthFreight/jobs')
local fuelruns = require('earthFreight/fuelruns')
local location = require('earthFreight/location')
local A = P.DIRECTORY .. 'save-a.json'

-- Pay: the same as a town job up to 20 km, then straight with distance, times the bonus.
do
  T.near(fuelruns.distanceFactor(20), jobs.distanceFactor(20), 1e-9, 'up to 20 km a fuel run pays by the town job curve')
  T.near(fuelruns.distanceFactor(100) / fuelruns.distanceFactor(20), 1 + 0.75 * 4, 1e-9, '100 km pays 4 times 20 km')
  T.check(fuelruns.distanceFactor(100) > 1.5 * jobs.distanceFactor(100), 'well over what the square root gives at 100 km')
  local fuel = goods.get('fuel')
  local units = 34000 / fuel.litres
  local town = jobs.basePay(fuel, units, 20)
  T.near(town, 51500, 600, 'the long tanker of fuel pays about $51,500 over 20 km as a town job')
  local penrith = places.get('gn2153471')
  local far
  for _, p in ipairs(places.within(penrith, 200000)) do
    if p.boost == 1 and math.abs(jobs.roadKm(penrith, p) - 100) < 5 then far = p; break end
  end
  T.check(far ~= nil, 'a flat place about 100 km from Penrith')
  local q = fuelruns.quote({ good = 'fuel', from = penrith.id, to = far.id, km = 100, fuelRun = true }, units)
  T.near(q.pay, 206000, 3000, 'and about $206,000 over 100 km as a fuel run, in flat country')
  T.eq(q.factor, fuelruns.BONUS, 'the fuel run bonus'); T.eq(q.shortage, false, 'never a shortage')
  T.eq(fuelruns.quote({ good = 'fuel', from = penrith.id, to = far.id, km = 100 }, 0).pay, 0, 'nothing for no load')
  -- Half the region bonus: a run between two x2 places pays 1.5 times flat country, where a town job pays 2 times.
  local steep = { id = 'steepA', boost = 2 }
  T.near(fuelruns.roadBonus(steep, steep), 1.5, 1e-9, 'a x2 region pays 1.5 times on a fuel run')
  T.near(fuelruns.roadBonus({ boost = 3 }, { boost = 1 }), 1.5, 1e-9, 'the average of the two ends, halved')
  T.near(fuelruns.roadBonus({ boost = 3 }, { boost = 3 }), 2, 1e-9, 'at most 2 times, at x3 both ends')
  T.near(jobs.roadBonus(steep, steep), 2, 1e-9, 'while a town job there pays 2 times')
end

-- Earth's places answer: the nearest open, named station near the town.
do
  local town = { id = 't', latitude = -33.7, longitude = 150.3 }
  local list = {
    { name = 'Shut', lat = -33.7, lon = 150.3, open = 'permanently_closed' },
    { name = 'Far', lat = -33.0, lon = 150.3 },
    { name = 'Ampol Katoomba', lat = -33.701, lon = 150.301, open = 'open' },
  }
  local b = fuelruns.stationFrom(list, town)
  T.eq(b and b.name, 'Ampol Katoomba', 'the first open station near the town'); T.eq(b and b.kind, 'fuel', 'as a fuel station')
  T.eq(fuelruns.stationFrom({}, town), nil, 'none')
  T.eq(fuelruns.stationFrom(nil, town), nil, 'no list')
end

-- Depots: quiet regional towns, never a big city or its suburbs.
do
  local function hubNear(lat, lon)
    local p = { latitude = lat, longitude = lon }
    places.ensure(p)
    return fuelruns.hub(p)
  end
  for _, c in ipairs({ { -33.87, 151.21, 'Sydney' }, { 48.21, 16.37, 'Vienna' }, { 34.05, -118.25, 'Los Angeles' }, { 47.26, 11.39, 'Innsbruck' } }) do
    local hub = hubNear(c[1], c[2])
    T.check(hub ~= nil, c[3] .. ' has a depot town within reach')
    T.eq(hub.size, 'town', c[3] .. ': the depot is in a town')
    T.check(fuelruns.quiet(hub), c[3] .. ': ' .. hub.name .. ' is quiet')
    local runs = fuelruns.offers(hub, 0)
    T.check(#runs >= 1 and #runs <= #fuelruns.BANDS, c[3] .. ': runs on offer from ' .. hub.name)
    local seen = {}
    for _, r in ipairs(runs) do
      local to = places.get(r.to)
      T.check(r.km >= fuelruns.MIN_KM and r.km <= fuelruns.MAX_KM, c[3] .. ': ' .. to.name .. ' is 60 to 200 km out')
      T.check(to.size ~= 'city', c[3] .. ': ' .. to.name .. ' is not a city')
      T.check(not seen[r.to], 'two different towns'); seen[r.to] = true
    end
    T.check(fuelruns.offers(hub, 0)[1].id == runs[1].id, 'the same offers for the same seed')
  end
  local sydney = places.at({ latitude = -33.8688, longitude = 151.2093 })
  T.check(not sydney or not fuelruns.isHub(sydney), 'Sydney itself is never a depot')
end

-- The controller on an older Earth: the card, GPS, loading at the depot, save and resume, delivery.
do
  local c, io, a, g, w = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local car = c.ownedParts.id
  local v = c:view()
  T.check(v.fuelRuns ~= nil and v.fuelRuns.hub ~= nil, 'the Fuel runs card shows a depot from Penrith')
  local hub = places.get(v.fuelRuns.hub.id)
  T.check(fuelruns.isHub(hub), 'a quiet regional town: ' .. hub.name)
  T.check(not v.fuelRuns.atDepot and v.fuelRuns.problem:find('Drive into') ~= nil, 'told to drive to the depot town')
  T.check(#v.fuelRuns.runs > 0, 'runs on offer'); T.check(not v.fuelRuns.runs[1].allowed, 'not loadable from here')
  T.eq(v.fuelRuns.runs[1].units, 0, 'the starter car has no tank')
  T.check(v.fuelRuns.lookup and v.fuelRuns.lookup.good == 'fuelhub', 'the HUD is asked to find the depot')
  T.check(c:gpsToDepot(), 'GPS to the depot'); T.eq(a.gps[#a.gps].name, hub.name, 'the depot town until one is found')
  T.check(c:view().fuelRuns.gps, 'the GPS button lights')
  -- The HUD finds a fuel terminal on the edge of town.
  local spot = location.destination(hub, 90, 1500)
  T.check(not c:setBusiness('gn1:fuelhub', 'X', 'terminal', spot.latitude, spot.longitude), 'only the depot asked for')
  T.check(c:setBusiness(v.fuelRuns.lookup.key, 'Shell%20Terminal', 'terminal', spot.latitude, spot.longitude), 'the depot is remembered')
  v = c:view()
  T.eq(v.fuelRuns.depot.name, 'Shell Terminal', 'the card names it'); T.eq(v.fuelRuns.depot.kind, 'Fuel terminal', 'as a fuel terminal')
  T.eq(v.fuelRuns.lookup, nil, 'no more lookups for it')
  -- A tanker, then the drive out to the terminal.
  c:tanksRead(car, 12000)
  F.drive(c, a, hub)
  v = c:view()
  T.check(not v.fuelRuns.atDepot, 'in town is not at the terminal'); T.check(v.fuelRuns.problem:find('Shell Terminal') ~= nil, 'told to go to it')
  F.drive(c, a, spot)
  v = c:view()
  T.check(v.fuelRuns.atDepot, 'at the terminal'); T.eq(v.fuelRuns.problem, nil, 'nothing in the way')
  local run = v.fuelRuns.runs[1]
  T.check(run.allowed and run.units == 1200 and run.litres == 12000, 'a full tanker: 12,000 L')
  T.check(c:view().town == nil or #c:view().town.jobs > 0, 'the town board is untouched')
  T.check(not c:takeFuelRun('fuelrun_nowhere'), 'only a run on offer')
  T.check(c:takeFuelRun(run.id), 'fuel run loaded')
  T.check(c.load.fuelRun and c.load.pay == run.pay, 'its pay locked in'); T.eq(c.load.to, run.toId, 'to the station town')
  T.eq(a.gps[#a.gps].name, run.to, 'the GPS goes to the town until a station is found')
  T.eq(w.weights[#w.weights].fluid.litres, 12000, 'poured into the tanker')
  T.eq(c:view().fuelRuns, nil, 'the card is hidden while on a job')
  T.check(c:view().load.fuelRun ~= nil, 'the job card says fuel run')
  T.check(not c:takeFuelRun(run.id), 'one run at a time')
  -- A crash changes nothing.
  g.damage = 8000; c:tick(1)
  T.eq(c:view().load.pay, run.pay, 'a crash does not change the pay')
  g.damage = 0; c:tick(1)
  -- Saved mid-run, and back after a reload.
  T.check(c:manualSave(), 'saved mid-run')
  T.check(io.files[A].load.fuelRun, 'the save keeps the fuel run')
  local r = F.controller({ io = io, adapter = a, garage = g })
  r:tick(0.1); r:tick(0.6); r:tick(0.6)
  T.check(r.load and r.load.fuelRun, 'the run resumes'); T.eq(r.load.pay, run.pay, 'with its pay')
  -- Delivered at the station's town.
  local before = r.profile.progression.balance
  F.drive(r, a, places.get(r.load.to))
  T.check(r:deliver(), 'delivered'); T.eq(r.profile.progression.balance, before + run.pay, 'paid in full')
  T.check(r:view().flash.title:find('FUEL RUN DELIVERED') ~= nil, 'the message says so')
  -- No wait for the next one.
  local next = r:view().fuelRuns
  T.check(next and next.hub and (next.problem == nil or not next.problem:find('Ready in')), 'the next fuel run needs no wait')
end

-- With BeamNG.Earth's places and multi-stop GPS: runs only to towns with a real station, delivered
-- at its pumps; GPS on a run shows the depot then the station; Teleport takes the truck to the depot.
do
  local a = F.adapter()
  a.asks, a.routes = {}, {}
  function a:canFindStations() return true end
  function a:findStations(point, metres, done) self.asks[#self.asks + 1] = { point = point, metres = metres, done = done }; return true end
  function a:setRoute(stops) if self.noRoute then return false, 'route_missing' end self.routes[#self.routes + 1] = stops; return true end
  local c, io, _, g = F.controller({ adapter = a })
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:tanksRead(c.ownedParts.id, 12000)
  local v = c:view()
  local hub = places.get(v.fuelRuns.hub.id)
  T.eq(#v.fuelRuns.runs, 0, 'no runs until Earth says where the stations are')
  c:tick(0.1)
  T.eq(#a.asks, fuelruns.STATION_ASKS, 'Earth is asked a few towns at a time')
  T.check(c:view().fuelRuns.finding, 'the card says it is finding stations')
  T.eq(a.asks[1].metres, fuelruns.STATION_METRES, 'round the town')
  -- The first town has none; every other one has a station 200 m from its middle.
  local none = a.asks[1].point
  local answered, guard = 0, 0
  while answered < #a.asks and guard < 200 do
    guard = guard + 1
    for i = answered + 1, #a.asks do
      local ask = a.asks[i]
      if i == 1 then ask.done({}, true, nil)
      else
        local at = location.destination(ask.point, 0, 200)
        ask.done({ { name = 'Station ' .. i, lat = at.latitude, lon = at.longitude, open = 'open' } }, true, nil)
      end
      answered = i
    end
    c:tick(0.1)
  end
  v = c:view()
  T.check(#v.fuelRuns.runs >= 1, 'runs on offer once the stations are known')
  for _, run in ipairs(v.fuelRuns.runs) do
    T.check(run.toId ~= none.id, 'never to a town with no station')
    T.check(run.station and run.station:find('^Station') ~= nil, 'each names its station')
  end
  T.check(not c.stationAsks or next(c.stationAsks) == nil, 'nothing left to ask')
  local asked = #a.asks; c:tick(0.1); T.eq(#a.asks, asked, 'each town is asked once')
  -- GPS on a run: the whole run as one route.
  local run = v.fuelRuns.runs[1]
  T.check(c:gpsToRun(run.id), 'GPS on the run')
  local route = a.routes[#a.routes]
  T.eq(#route, 2, 'two stops'); T.eq(route[1].name, hub.name, 'the depot first')
  T.check(route[2].name:find(run.station, 1, true) == 1, 'then the station')
  T.check(c:view().fuelRuns.runs[1].gps, 'the run\'s GPS button lights')
  a.noRoute = true
  T.check(c:gpsToRun(run.id), 'an older Earth: GPS still set')
  T.check(a.gps[#a.gps].name:find(run.station, 1, true) == 1, 'straight to the station')
  -- Teleport to the depot: free, and not stranded when it lands.
  local money = c.profile.progression.balance
  T.check(c:view().fuelRuns.teleportAllowed, 'Teleport is offered away from the depot')
  T.check(c:teleportToDepot(), 'teleport asked')
  T.eq(c.profile.progression.balance, money, 'free')
  T.near(a.teleports[#a.teleports].latitude, hub.latitude, 1e-9, 'to the depot town')
  T.check(c:view().fuelRuns.teleporting, 'the card says it is on the way')
  a.pose = F.copy(hub); c:tick(0.1); c:tick(0.6); c:tick(0.6)
  T.eq(c.booking, nil, 'landed'); T.eq(c.stranded, nil, 'not stranded')
  v = c:view()
  T.check(v.fuelRuns.atDepot, 'at the depot'); T.check(not v.fuelRuns.teleportAllowed, 'no teleport once there')
  -- Loaded, then delivered at the station's pumps.
  run = v.fuelRuns.runs[1]
  T.check(c:takeFuelRun(run.id), 'loaded')
  T.eq(c.load.business and c.load.business.name, run.station, 'delivered at the station')
  T.check(a.gps[#a.gps].name:find(run.station, 1, true) == 1, 'the GPS goes to the station')
  F.drive(c, a, c.load.business)
  local before = c.profile.progression.balance
  T.check(c:deliver(), 'delivered at the pumps'); T.eq(c.profile.progression.balance, before + run.pay, 'paid in full')
  local _ = io; local _ = g
end

T.done('fuel runs')
