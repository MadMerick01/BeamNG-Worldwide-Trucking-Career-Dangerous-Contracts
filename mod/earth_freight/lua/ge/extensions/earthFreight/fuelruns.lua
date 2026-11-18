-- Fuel runs: the long haul. A tanker of fuel loaded at a depot in a quiet regional town and driven
-- 60 to 200 km out to a country town's petrol station, the reason to leave the big cities, which
-- BeamNG.Earth draws roughly, for the hills. Shown on their own Fuel runs card, never on a town's
-- board. Pay grows in a straight line with distance past 20 km, where a town job's only grows with
-- the square root, so a long run pays a little more per hour than town jobs without being a money
-- printer. Half the region bonus and the base bonus come on top; shortages and jackpots never do. With BeamNG.Earth's places (its modding API 1.4 and later) a run is only offered
-- to a town where Earth knows a real petrol station, delivered at its pumps, and its GPS shows the
-- whole run, depot then station, as one route (API 1.2). On an older Earth the HUD's OpenStreetMap
-- lookup and the town centre stand in. Pure maths and picks, and the controller's side below.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local jobs = require('earthFreight/jobs')
local business = require('earthFreight/business')
local trailers = require('earthFreight/trailers')
local rockets = require('earthFreight/rockets')
local M = {}

-- One-line settings. Tune these after testing in game.
-- A run is this many km by road (the straight line times places.ROAD_FACTOR), from the depot's town
-- to the station's.
M.MIN_KM, M.MAX_KM = 60, 200
-- Past jobs.FLAT_KM (20 km) each km pays PER_KM_SHARE of what an average km of a 20 km job pays,
-- so 100 km pays 4 times 20 km, not 2.2. Then every run pays BONUS times that. With
-- jobs.PAY_PERCENT at 75, the 34,000 L long tanker of fuel pays about $51,500 over 20 km as a town
-- job and about $206,000 over 100 km as a fuel run, before the region and base bonuses.
-- They were 0.9 and 1.2 ($284,000) until fuel runners earned 2 to 3 times as much an hour as town
-- job players on the server (MadMerick, 17 Nov: about 40% off).
M.PER_KM_SHARE, M.BONUS = 0.75, 1
-- The region boost (1 to 3) at the run's two ends becomes a road bonus of 1 + (boost - 1) *
-- ROAD_SHARE, half a town job's: the runs are picked for the steepest destinations, but most of a
-- 100 km run is main road. A base's bonus is added in full, as for town jobs.
M.ROAD_SHARE = 0.5
-- Fuel runs leave from towns (5,000 to 50,000 people) with at most HUB_NEIGHBOURS other towns or
-- cities within QUIET_KM, so never from a big city or its suburbs: Katoomba and Richmond for
-- Sydney, Tulln for Vienna. The card shows the nearest within HUB_REACH_KM of the truck.
M.QUIET_KM, M.HUB_NEIGHBOURS, M.HUB_REACH_KM = 10, 1, 100
-- The stations go to villages and towns (never cities) that are just as quiet. The card offers one
-- run in each of BANDS (road km), so there is a shorter and a longer one; in each band the PICK_FROM
-- with the highest region boost are the pool, so runs lean into steep, remote country. The runs
-- change after every job.
M.BANDS = { { 60, 120 }, { 120, 200 } }
M.PICK_FROM = 6
-- Loaded stopped within DEPOT_RADIUS metres of the depot's spot (a real fuel terminal, depot or
-- truck stop the HUD found in OpenStreetMap), or anywhere in the town when it has none.
M.DEPOT_RADIUS = 40
-- A depot town stays the card's once the truck is within KEEP_HUB_KM of it, so a closer town over
-- the hill doesn't take its place while the player is driving in to load.
M.KEEP_HUB_KM = 8
-- Earth's places: each candidate town is asked once for petrol stations within STATION_METRES of
-- its middle, at most STATION_ASKS at a time; a question with no answer is asked again after
-- STATION_RETRY_SECONDS.
M.STATION_METRES, M.STATION_ASKS, M.STATION_RETRY_SECONDS = 3000, 2, 120

local function round10(n) return math.floor(n / 10 + 0.5) * 10 end

-- How much more than a 5 km job a fuel run of this many road km pays: as jobs.distanceFactor up to
-- 20 km, then in a straight line.
function M.distanceFactor(km)
  km = math.max(0, km or 0)
  if km <= jobs.FLAT_KM then return jobs.distanceFactor(km) end
  return jobs.distanceFactor(jobs.FLAT_KM) * (1 + M.PER_KM_SHARE * (km - jobs.FLAT_KM) / jobs.FLAT_KM)
end

-- How many other towns and cities are within QUIET_KM of a place, counting up to limit + 1.
local function neighbours(place, limit)
  local n, metres = 0, M.QUIET_KM * 1000
  for _, other in ipairs(places.within(place, metres)) do
    if other.id ~= place.id and other.size ~= 'village' then
      local d = location.distance(place, other)
      if d and d <= metres then
        n = n + 1
        if n > limit then return n end
      end
    end
  end
  return n
end

-- Whether a place is quiet: out of the cities and their suburbs.
function M.quiet(place) return neighbours(place, M.HUB_NEIGHBOURS) <= M.HUB_NEIGHBOURS end

-- Whether fuel runs leave from a place.
function M.isHub(place) return place ~= nil and place.size == 'town' and M.quiet(place) end

-- The depot town nearest a point, within HUB_REACH_KM, and how far it is in a straight line; nil
-- when there is none. Kept until the point moves HUB_MOVE metres or more places load, since the HUD
-- asks many times a second.
M.HUB_MOVE = 1000
local hubCache
function M.hub(point)
  if not location.valid(point) then return nil end
  local c = hubCache
  if c and c.count == #places.list and location.distance(c.point, point) < M.HUB_MOVE then
    if not c.place then return nil end
    return c.place, location.distance(point, c.place)
  end
  local list = {}
  for _, p in ipairs(places.within(point, M.HUB_REACH_KM * 1000)) do
    if p.size == 'town' then
      local d = location.distance(point, p)
      if d and d <= M.HUB_REACH_KM * 1000 then list[#list + 1] = { place = p, metres = d } end
    end
  end
  table.sort(list, function(a, b) if a.metres ~= b.metres then return a.metres < b.metres end return a.place.id < b.place.id end)
  local found
  for _, x in ipairs(list) do
    if M.quiet(x.place) then found = x; break end
  end
  hubCache = { point = location.copy(point), count = #places.list, place = found and found.place or nil }
  if not found then return nil end
  return found.place, found.metres
end

-- The stations a depot's runs can go to, one list per band: quiet villages and towns that far by
-- road, the PICK_FROM with the highest region boost, as { place, km }. Kept per depot.
local poolCache, poolCount = {}, -1
function M.pool(hub)
  if poolCount ~= #places.list then poolCache, poolCount = {}, #places.list end
  if poolCache[hub.id] then return poolCache[hub.id] end
  local list = {}
  for _, p in ipairs(places.within(hub, M.MAX_KM * 1000 / places.ROAD_FACTOR)) do
    if p.id ~= hub.id and p.size ~= 'city' then
      local km = jobs.roadKm(hub, p)
      if km >= M.MIN_KM and km <= M.MAX_KM then list[#list + 1] = { place = p, km = km } end
    end
  end
  table.sort(list, function(a, b)
    local ab, bb = places.boost(a.place), places.boost(b.place)
    if ab ~= bb then return ab > bb end
    return a.place.id < b.place.id
  end)
  local out = {}
  for i, band in ipairs(M.BANDS) do
    out[i] = {}
    for _, x in ipairs(list) do
      if #out[i] >= M.PICK_FROM then break end
      if x.km > band[1] and x.km <= band[2] and M.quiet(x.place) then table.insert(out[i], x) end
    end
  end
  local n = 0
  for _ in pairs(poolCache) do n = n + 1 end
  if n >= 8 then poolCache = {} end
  poolCache[hub.id] = out
  return out
end

-- The runs on offer from a depot for a seed (the controller's count of jobs done): one station
-- from each band's pool, where it has any, nearest first. hasStation, when given, keeps only the
-- towns it says have a real station.
function M.offers(hub, seed, hasStation)
  local out = {}
  seed = tostring(seed or 0)
  for i, all in ipairs(M.pool(hub)) do
    local pool = all
    if hasStation then
      pool = {}
      for _, x in ipairs(all) do if hasStation(x.place) then pool[#pool + 1] = x end end
    end
    if #pool > 0 then
      local x = pool[math.floor(jobs.hash01(hub.id .. ':' .. seed .. ':fuelrun:' .. i) * #pool) + 1]
      out[#out + 1] = { id = 'fuelrun_' .. x.place.id, good = 'fuel', from = hub.id, to = x.place.id, km = x.km, fuelRun = true }
    end
  end
  table.sort(out, function(a, b) if a.km ~= b.km then return a.km < b.km end return a.to < b.to end)
  return out
end

-- The road bonus of a fuel run: from the region boost at the average of its two ends, at ROAD_SHARE.
function M.roadBonus(from, to)
  local boost = (places.boost(from) + places.boost(to)) / 2
  return math.min(jobs.MAX_ROAD, 1 + (boost - 1) * M.ROAD_SHARE)
end

-- What a fuel run pays for this many units of fuel: its distance, BONUS, its road bonus and the
-- base bonus of a town job (see jobs.quote; shareAt is the same). Shaped like jobs.quote's answer.
function M.quote(job, units, shareAt)
  local good, from, to = goods.get(job.good), places.get(job.from), places.get(job.to)
  local extra = jobs.baseExtra(shareAt, from, to)
  local road = M.roadBonus(from, to) + extra
  local base = jobs.weightPay(units * (good.payKg or good.kg)) * (good.rate or 1) * jobs.PAY_PERCENT / 100 * M.distanceFactor(job.km)
  return { pay = units > 0 and math.max(10, round10(base * M.BONUS * road)) or 0, base = round10(base), factor = M.BONUS,
    need = 1, road = road, baseBonus = extra > 0 and extra or nil, shortage = false, level = 'fuel' }
end

-- The station Earth's places answer gives for a town: the nearest open, named petrol station
-- within business.MAX_FROM_TOWN, as a business, or nil.
function M.stationFrom(list, town)
  for _, p in ipairs(type(list) == 'table' and list or {}) do
    if type(p) == 'table' and p.open ~= 'permanently_closed' and p.open ~= 'temporarily_closed' then
      local b = business.clean({ name = p.name, kind = 'fuel', latitude = p.lat, longitude = p.lon }, town)
      if b then return b end
    end
  end
  return nil
end

-- The business key the depot of a town is remembered under (business.lua), the same for everyone.
function M.depotKey(hub) return business.key(hub.id, 'fuelhub') end

local ON_FOOT = 'You are on foot. Get back in your car first.'

-- The controller's side: the Fuel runs card, the stations, the GPS and teleport to the depot and
-- loading there. Delivery itself is a town job's (core.lua deliver), at the station or the town.
function M.attach(c)
  -- The depot town for the card: the one already shown while the truck is near it, else the nearest.
  function c:fuelHub(current)
    local kept = self.fuelHubId and places.get(self.fuelHubId)
    if kept then
      local d = location.distance(current, kept)
      if d and d <= M.KEEP_HUB_KM * 1000 then return kept, d end
    end
    local hub, metres = M.hub(current)
    self.fuelHubId = hub and hub.id or nil
    return hub, metres
  end

  -- The real depot found for a town, or nil (none found yet, or none there).
  function c:fuelDepot(hub)
    local known = hub and self:businesses()[M.depotKey(hub)]
    return known and not known.none and business.clean(known, hub) or nil
  end

  -- What the HUD should look up for the depot town on the card: its depot, while none is known.
  function c:fuelDepotWanted()
    local hub = self.fuelHubId and places.get(self.fuelHubId)
    if not hub or self.load then return nil end
    local key = M.depotKey(hub)
    if self:businesses()[key] then return nil end
    return { key = key, town = hub.name, latitude = hub.latitude, longitude = hub.longitude, good = 'fuelhub',
      metres = business.WIDER_METRES, widerMetres = business.MAX_FROM_TOWN }
  end

  -- The HUD found a depot for the depot town on the card (name and kind as for a business).
  function c:setFuelDepot(key, name, kind, latitude, longitude)
    local wanted = self:fuelDepotWanted()
    if not wanted or key ~= wanted.key then return false end
    local hub = places.get(self.fuelHubId)
    local found = business.clean({ name = business.decode(name), kind = kind, latitude = latitude, longitude = longitude }, hub)
    if not found then
      self.diag:event('fuel_depot', 'refused:' .. key, 'W')
      return false
    end
    self:rememberBusiness(key, found)
    self.diag:event('fuel_depot', key .. ':' .. found.kind)
    return true
  end

  function c:noFuelDepot(key)
    local wanted = self:fuelDepotWanted()
    if not wanted or key ~= wanted.key then return false end
    self:rememberBusiness(key, { none = true })
    self.diag:event('fuel_depot', 'none:' .. key)
    return true
  end

  -- Whether the truck is where it loads: at the depot's spot, or in the town when it has none.
  function c:atFuelDepot(current, hub, depot)
    if not current or not hub then return false end
    if depot then
      local d = location.distance(current, depot)
      return d ~= nil and d <= M.DEPOT_RADIUS
    end
    local here = places.at(current)
    return here ~= nil and here.id == hub.id
  end

  -- Whether Earth's places can be asked for stations; without them, runs go to any town in the pool.
  function c:earthStations()
    return self.adapter.findStations ~= nil and self.adapter:canFindStations() == true
  end

  -- Whether a town has a known real petrol station (Earth's, or one the HUD found before).
  function c:hasStation(town)
    local known = self:businesses()[business.key(town.id, 'fuel')]
    return known ~= nil and not known.none
  end

  -- Asks Earth for the petrol stations of the depot's candidate towns not yet known, a few at a time.
  -- Each answer is remembered with the businesses, so a town is only asked once.
  function c:watchStations()
    if self.load or not self.fuelHubId or not self:earthStations() then return end
    local hub = places.get(self.fuelHubId)
    if not hub then return end
    self.stationAsks = self.stationAsks or {}
    local open = 0
    for key, at in pairs(self.stationAsks) do
      if self.clock - at < M.STATION_RETRY_SECONDS then open = open + 1 else self.stationAsks[key] = nil end
    end
    for _, band in ipairs(M.pool(hub)) do
      for _, x in ipairs(band) do
        if open >= M.STATION_ASKS then return end
        local town = x.place
        local key = business.key(town.id, 'fuel')
        if not self:businesses()[key] and not self.stationAsks[key] then
          local sent = self.adapter:findStations(town, M.STATION_METRES, function(found, done, failed)
            self:stationsFound(town, found, done, failed)
          end)
          if sent then
            self.stationAsks[key] = self.clock
            open = open + 1
          end
        end
      end
    end
  end

  -- Earth answered for a town: a station is remembered as its fuel drop-off; a complete answer with
  -- none marks the town as having none. A failed answer is asked again later.
  function c:stationsFound(town, found, done, failed)
    local key = business.key(town.id, 'fuel')
    if failed then
      self.diag:event('stations', 'failed:' .. key .. ':' .. tostring(failed), 'W')
      return
    end
    local station = M.stationFrom(found, town)
    if station then
      self:rememberBusiness(key, station)
      if self.stationAsks then self.stationAsks[key] = nil end
      self.diag:event('stations', key .. ':found')
    elseif done then
      local known = self:businesses()[key]
      if not known then self:rememberBusiness(key, { none = true }) end
      if self.stationAsks then self.stationAsks[key] = nil end
      self.diag:event('stations', key .. ':none')
    end
  end

  -- Why a fuel run cannot be loaded now, or nil when it can.
  function c:fuelRunProblem(current, hub, depot)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Fuel runs are unavailable right now.' end
    if self.load then return 'Deliver or abandon your job first.' end
    if self.rockets then return rockets.TAKE_PROBLEM end
    if not hub then return 'There is no fuel depot within ' .. M.HUB_REACH_KM .. ' km.' end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    if not self:atFuelDepot(current, hub, depot) then
      return depot and ('Drive to ' .. depot.name .. ' in ' .. hub.name .. ' and stop within ' .. M.DEPOT_RADIUS .. ' m to load.')
        or ('Drive into ' .. hub.name .. ' and stop to load.')
    end
    if not self.odometer:stopped() then return 'Stop the truck to load.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from, or book a relocation on the Relocate tab.' end
    return nil
  end

  -- The runs on offer from the depot town now.
  function c:fuelRunOffers(hub)
    local p = self.profile and self.profile.progression
    local filter = self:earthStations() and function(town) return self:hasStation(town) end or nil
    return M.offers(hub, p and p.jobsDone or 0, filter)
  end

  -- The Fuel runs card on the Route tab: the depot, how far, and the runs with what they pay this
  -- truck. Not shown while on a job.
  function c:fuelRunsView(current)
    if not current or self.load or not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return nil end
    local out = { minKm = M.MIN_KM, maxKm = M.MAX_KM, reachKm = M.HUB_REACH_KM, bonus = M.BONUS }
    local hub = self:fuelHub(current)
    if not hub then return out end
    local depot = self:fuelDepot(hub)
    local spot = depot or hub
    local away = location.distance(current, spot)
    local problem = self:fuelRunProblem(current, hub, depot)
    out.hub = { id = hub.id, name = hub.name, region = hub.region }
    out.depot = depot and { name = depot.name, kind = business.label(depot) } or nil
    out.spot = location.copy(spot)
    out.distanceMetres = away
    out.direction = away and away > 0 and location.compassPoint(location.bearing(current, spot)) or nil
    out.atDepot = self:atFuelDepot(current, hub, depot)
    out.gps = self.gpsDepot == hub.id or nil
    out.teleportAllowed = not out.atDepot and self:depotTripProblem(current, hub) == nil
    out.teleporting = self.booking ~= nil and self.booking.id == 'depot' and self.bookingTeleportAt ~= nil
      and self.clock - self.bookingTeleportAt < 30 or nil
    out.stations = self:earthStations() or nil
    out.finding = self:earthStations() and self.stationAsks ~= nil and next(self.stationAsks) ~= nil or nil
    out.lookup = self:fuelDepotWanted()
    out.problem = problem
    out.runs = {}
    for _, job in ipairs(self:fuelRunOffers(hub)) do
      local q, to, good = self:jobQuote(job), places.get(job.to), goods.get(job.good)
      local road = q.road - (q.baseBonus or 0)
      out.runs[#out.runs + 1] = { id = job.id, to = to.name, toId = to.id, region = to.region, size = to.size,
        distanceMetres = job.km * 1000, pay = q.pay, units = q.units, kg = q.kg, litres = q.units * good.litres,
        unitKg = good.kg, unitLitres = good.litres,
        road = road > 1.005 and road or nil,
        basePercent = q.baseBonus and math.floor(q.baseBonus / road * 100 + 0.5) or nil,
        tollTo = q.toll and q.toll.owner or nil, station = self:station(to) and self:station(to).name or nil,
        gps = self.gpsRun == job.id or nil,
        allowed = problem == nil and q.units > 0 }
    end
    return out
  end

  -- Sets the GPS to the depot on the card, or the middle of its town.
  function c:gpsToDepot()
    local current = self.lastSample and self.lastSample.valid and self.lastSample or nil
    local hub = current and self:fuelHub(current)
    if not hub or not self.adapter.setDestination or self.state ~= 'READY' or not self.arrived or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local depot = self:fuelDepot(hub)
    local spot = depot or hub
    local name = depot and (depot.name .. ', ' .. hub.name) or hub.name
    local ok, why = self.adapter:setDestination(spot, name)
    self.diag:event('gps', ok and ('fuel_depot:' .. hub.id) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract, self.gpsDepot = nil, nil, ok and hub.id or nil
    self.gpsFeedback = ok and ('The GPS is set to ' .. name .. '.')
      or ('Could not set the GPS. Paste ' .. string.format('%.5f, %.5f', spot.latitude, spot.longitude) .. ' into the BeamNG.Earth map instead.')
    return ok == true
  end

  -- The known station of a town, or nil.
  function c:station(town)
    local known = self:businesses()[business.key(town.id, 'fuel')]
    return known and not known.none and business.clean(known, town) or nil
  end

  -- GPS on a run, to check the route before going: the whole run, depot then station, as one route
  -- where Earth can plan through stops; else straight to the station (or its town).
  function c:gpsToRun(jobId)
    local current = self.lastSample and self.lastSample.valid and self.lastSample or nil
    local hub = current and self:fuelHub(current)
    local job
    for _, j in ipairs(hub and self:fuelRunOffers(hub) or {}) do if j.id == jobId then job = j end end
    if not job or not self.adapter.setDestination or self.state ~= 'READY' or not self.arrived or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local town = places.get(job.to)
    local depot = self:fuelDepot(hub)
    local start, stop = depot or hub, self:station(town) or town
    local startName = depot and (depot.name .. ', ' .. hub.name) or hub.name
    local stopName = stop ~= town and (stop.name .. ', ' .. town.name) or town.name
    local ok, why, both
    if self.adapter.setRoute then
      ok, why = self.adapter:setRoute({ { point = start, name = startName }, { point = stop, name = stopName } })
      both = ok
    end
    if not ok then ok, why = self.adapter:setDestination(stop, stopName) end
    self.diag:event('gps', ok and ('fuel_run:' .. job.id .. (both and ':route' or '')) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract, self.gpsDepot, self.gpsRun = nil, nil, nil, ok and job.id or nil
    self.gpsFeedback = ok and (both and ('The GPS shows the whole run: ' .. startName .. ', then ' .. stopName .. '.')
      or ('The GPS is set to ' .. stopName .. '.')) or 'Could not set the GPS.'
    return ok == true
  end

  -- Why the truck cannot be teleported to the depot now, or nil.
  function c:depotTripProblem(current, hub)
    if not hub then return 'There is no fuel depot within ' .. M.HUB_REACH_KM .. ' km.' end
    if not self.adapter.teleport then return 'BeamNG.Earth cannot teleport right now.' end
    if self:atFuelDepot(current, hub, self:fuelDepot(hub)) then return 'You are at the depot.' end
    if self.booking and self.booking.id == 'depot' then return nil end
    return self:shippingProblem()
  end

  -- Teleport to the depot: a free relocation to the depot (or its town), and the teleport there, in
  -- one press, so the player starts the run there.
  function c:teleportToDepot()
    local current = self.lastSample and self.lastSample.valid and self.lastSample or nil
    local hub = current and self:fuelHub(current)
    local problem = self:depotTripProblem(current, hub)
    if not problem and not self.booking then
      local depot = self:fuelDepot(hub)
      local spot = depot or hub
      if not self:book({ id = 'depot', name = depot and (depot.name .. ', ' .. hub.name) or hub.name, region = hub.region,
        latitude = spot.latitude, longitude = spot.longitude }, true) then problem = self.shippingFeedback end
    end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    -- The card stays on this depot while the truck is away.
    self.fuelHubId = hub.id
    local ok = self:teleportToBooking()
    self.tradeFeedback = ok and ('Off to the depot in ' .. hub.name .. '. The terrain takes a few seconds to load.')
      or (self.shippingFeedback or 'BeamNG.Earth did not take the teleport.')
    return ok
  end

  -- Loads a fuel run at the depot: the truck and its trailer filled with fuel, or the share of a
  -- full load picked on the slider (a percentage, 100 when not given) for that share of the pay,
  -- the pay locked in, and the GPS set to the station (or the town, until one is found).
  function c:takeFuelRun(jobId, share)
    share = share or 100
    local current = self.lastSample and self.lastSample.valid and self.lastSample or nil
    local hub = current and self:fuelHub(current)
    local depot = hub and self:fuelDepot(hub)
    local problem = self:fuelRunProblem(current, hub, depot)
    local job
    if not problem then
      for _, j in ipairs(self:fuelRunOffers(hub)) do if j.id == jobId then job = j end end
      if not job then problem = 'That fuel run is no longer on offer.' end
    end
    local quote = job and not problem and self:jobQuote(job) or nil
    if quote and quote.units == 0 then
      problem = 'A fuel run needs a tanker: a truck with a fluid tank, or a tanker trailer. Fit a Cargo Load fluid tank with Buy parts on the Garage tab, or buy a tanker.'
    end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local good, destination = goods.get(job.good), places.get(job.to)
    local full = quote.units
    local units, pay = jobs.share(quote.units, quote.pay, share)
    quote.units, quote.slots, quote.kg, quote.pay = units, units * good.slots, units * good.kg, pay
    self.load = { good = good.id, units = quote.units, slots = quote.slots, kg = quote.kg, pay = quote.pay,
      from = hub.id, to = destination.id, drivenKm = 0, toll = quote.toll, fuelRun = true }
    -- Split between the truck and the trailer, each filled to the same share of its room.
    local inTrailer = trailers.split(units, full, quote.trailerUnits)
    if inTrailer > 0 then self.load.trailerUnits = inTrailer end
    self.abandonArmed, self.gpsDepot, self.gpsRun = false, nil, nil
    self:applyWeight()
    self.tradeFeedback = nil
    local known = self:businesses()[business.key(destination.id, good.id)]
    if known and not known.none then self.load.business = business.clean(known, destination) end
    self:gpsToJob()
    self.diag:event('job_taken', string.format('fuel run %d L %s -> %s %.0f km for %d', quote.units * good.litres, hub.id,
      destination.id, job.km, quote.pay))
    return true
  end

  -- The fuel run's part of the job card.
  function c:fuelRunLoadView()
    local load = self.load
    if not load or not load.fuelRun then return nil end
    return { from = places.get(load.from).name }
  end
end

return M
