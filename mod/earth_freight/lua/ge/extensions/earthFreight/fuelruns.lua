-- Fuel runs: the long haul. A tanker of fuel loaded at a depot in a quiet regional town and driven
-- 60 to 200 km out to a country town's petrol station, the reason to leave the big cities, which
-- BeamNG.Earth draws roughly, for the hills. Shown on their own Fuel runs card, never on a town's
-- board. Pay grows in a straight line with distance past 20 km, where a town job's only grows with
-- the square root, times a flat bonus, so a long run pays more per hour than town jobs without
-- being a money printer. The region and base bonuses come on top as for town jobs; shortages and
-- jackpots never do. A crash spills fuel, and the pay drops by the share spilled. Pure maths and
-- picks; the controller keeps the run, its depot and the spill. No game globals.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local jobs = require('earthFreight/jobs')
local business = require('earthFreight/business')
local trailers = require('earthFreight/trailers')
local pricing = require('earthFreight/pricing')
local M = {}

-- One-line settings. Tune these after testing in game.
-- A run is this many km by road (the straight line times places.ROAD_FACTOR), from the depot's town
-- to the station's.
M.MIN_KM, M.MAX_KM = 60, 200
-- Past jobs.FLAT_KM (20 km) each km pays PER_KM_SHARE of what an average km of a 20 km job pays,
-- so 100 km pays about 4.6 times 20 km, not 2.2. Then every run pays BONUS times that. With
-- jobs.PAY_PERCENT at 75, the 34,000 L long tanker of fuel pays about $51,500 over 20 km as a town
-- job and about $284,000 over 100 km as a fuel run, before the region and base bonuses.
M.PER_KM_SHARE, M.BONUS = 0.9, 1.2
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
-- After a fuel run is delivered, the next can be loaded this many seconds later (wall clock).
M.COOLDOWN_SECONDS = 600
-- Loaded stopped within DEPOT_RADIUS metres of the depot's spot (a real fuel terminal, depot or
-- truck stop the HUD found in OpenStreetMap), or anywhere in the town when it has none.
M.DEPOT_RADIUS = 40
-- A depot town stays the card's once the truck is within KEEP_HUB_KM of it, so a closer town over
-- the hill doesn't take its place while the player is driving in to load.
M.KEEP_HUB_KM = 8
-- How often, in seconds, the truck's damage is read for spills.
M.SPILL_EVERY_SECONDS = 0.5
-- Spills: crash damage taken with the load on (the truck's and its trailer's, as BeamNG counts it:
-- about 1,000 is moderate, 30,000 major) spills nothing up to SPILL_FREE_DAMAGE, then a growing share
-- until SPILL_ALL_DAMAGE, which spills MAX_SPILL of the load. The pay drops by the share spilled.
M.SPILL_FREE_DAMAGE, M.SPILL_ALL_DAMAGE, M.MAX_SPILL = 1000, 30000, 0.75

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
-- from each band's pool, where it has any, nearest first.
function M.offers(hub, seed)
  local out = {}
  seed = tostring(seed or 0)
  for i, pool in ipairs(M.pool(hub)) do
    if #pool > 0 then
      local x = pool[math.floor(jobs.hash01(hub.id .. ':' .. seed .. ':fuelrun:' .. i) * #pool) + 1]
      out[#out + 1] = { id = 'fuelrun_' .. x.place.id, good = 'fuel', from = hub.id, to = x.place.id, km = x.km, fuelRun = true }
    end
  end
  table.sort(out, function(a, b) if a.km ~= b.km then return a.km < b.km end return a.to < b.to end)
  return out
end

-- What a fuel run pays for this many units of fuel: its distance, BONUS and the road and base
-- bonuses of a town job (see jobs.quote; shareAt is the same). Shaped like jobs.quote's answer.
function M.quote(job, units, shareAt)
  local good, from, to = goods.get(job.good), places.get(job.from), places.get(job.to)
  local extra = jobs.baseExtra(shareAt, from, to)
  local road = jobs.roadBonus(from, to) + extra
  local base = jobs.weightPay(units * (good.payKg or good.kg)) * (good.rate or 1) * jobs.PAY_PERCENT / 100 * M.distanceFactor(job.km)
  return { pay = units > 0 and math.max(10, round10(base * M.BONUS * road)) or 0, base = round10(base), factor = M.BONUS,
    need = 1, road = road, baseBonus = extra > 0 and extra or nil, shortage = false, level = 'fuel' }
end

-- The share of the load spilled after this much crash damage, 0 to MAX_SPILL.
function M.spillShare(damage)
  local over = (damage or 0) - M.SPILL_FREE_DAMAGE
  if over <= 0 then return 0 end
  return math.min(M.MAX_SPILL, M.MAX_SPILL * over / (M.SPILL_ALL_DAMAGE - M.SPILL_FREE_DAMAGE))
end

-- What a run pays after a spill: the pay less the share spilled, in tens of dollars.
function M.payAfterSpill(pay, share)
  if not share or share <= 0 then return pay end
  return math.max(10, round10(pay * (1 - share)))
end

-- The seconds before the next fuel run can be loaded, 0 when it can.
function M.cooldownLeft(lastAt, now)
  if not lastAt or not now then return 0 end
  return math.max(0, lastAt + M.COOLDOWN_SECONDS - now)
end

-- The business key the depot of a town is remembered under (business.lua), the same for everyone.
function M.depotKey(hub) return business.key(hub.id, 'fuelhub') end

local dollars = pricing.dollars
local ON_FOOT = 'You are on foot. Get back in your car first.'

local function clock(seconds)
  seconds = math.max(0, math.ceil(seconds))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- The controller's side: the Fuel runs card, loading at the depot, the spill watch and the pay on
-- delivery. Delivery itself is a town job's (core.lua deliver), at the station or the town.
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

  -- The seconds before the next fuel run can be loaded.
  function c:fuelCooldown()
    local p = self.profile and self.profile.progression
    return M.cooldownLeft(p and p.fuelRunAt, self.now())
  end

  -- Why a fuel run cannot be loaded now, or nil when it can.
  function c:fuelRunProblem(current, hub, depot)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Fuel runs are unavailable right now.' end
    if self.load then return 'Deliver or abandon your job first.' end
    if not hub then return 'There is no fuel depot within ' .. M.HUB_REACH_KM .. ' km.' end
    local wait = self:fuelCooldown()
    if wait > 0 then return 'The depot is filling the next tanker. Ready in ' .. clock(wait) .. '.' end
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
    return M.offers(hub, p and p.jobsDone or 0)
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
    out.cooldownSeconds = self:fuelCooldown()
    out.gps = self.gpsDepot == hub.id or nil
    out.lookup = self:fuelDepotWanted()
    out.problem = problem
    out.runs = {}
    for _, job in ipairs(self:fuelRunOffers(hub)) do
      local q, to, good = self:jobQuote(job), places.get(job.to), goods.get(job.good)
      local road = q.road - (q.baseBonus or 0)
      out.runs[#out.runs + 1] = { id = job.id, to = to.name, toId = to.id, region = to.region, size = to.size,
        distanceMetres = job.km * 1000, pay = q.pay, units = q.units, kg = q.kg, litres = q.units * good.litres,
        road = road > 1.005 and road or nil,
        basePercent = q.baseBonus and math.floor(q.baseBonus / road * 100 + 0.5) or nil,
        tollTo = q.toll and q.toll.owner or nil,
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

  -- Loads a fuel run at the depot: the truck and its trailer filled with fuel, the pay locked in,
  -- and the GPS set to the station (or the town, until one is found).
  function c:takeFuelRun(jobId)
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
    self.load = { good = good.id, units = quote.units, slots = quote.slots, kg = quote.kg, pay = quote.pay,
      from = hub.id, to = destination.id, drivenKm = 0, toll = quote.toll, fuelRun = true, crashDamage = 0 }
    if (quote.trailerUnits or 0) > 0 then self.load.trailerUnits = quote.trailerUnits end
    self.abandonArmed, self.spillSeen, self.gpsDepot = false, nil, nil
    self:applyWeight()
    self.tradeFeedback = nil
    local known = self:businesses()[business.key(destination.id, good.id)]
    if known and not known.none then self.load.business = business.clean(known, destination) end
    self:gpsToJob()
    self.diag:event('job_taken', string.format('fuel run %d L %s -> %s %.0f km for %d', quote.units * good.litres, hub.id,
      destination.id, job.km, quote.pay))
    return true
  end

  -- The share of the fuel run's load spilled so far, 0 when nothing has.
  function c:spilled()
    local load = self.load
    return load and load.fuelRun and M.spillShare(load.crashDamage) or 0
  end

  -- What the job on board pays now: a fuel run less what it has spilled.
  function c:loadPay()
    local load = self.load
    if not load then return 0 end
    return load.fuelRun and M.payAfterSpill(load.pay, self:spilled()) or load.pay
  end

  -- Counts the crash damage the truck and its trailer take with fuel on board. A repair or a reset
  -- lowers the damage, which spills nothing back: only rises count.
  function c:watchSpill()
    local load = self.load
    if not load or not load.fuelRun or self.hire or self.onFoot or not self.garage or not self.ownedParts then
      self.spillSeen = nil
      return
    end
    if self.spillReadAt and self.clock - self.spillReadAt < M.SPILL_EVERY_SECONDS then return end
    self.spillReadAt = self.clock
    local car = self:vehicleDamage()
    if not car or car.id ~= self.ownedParts.id then return end
    local total = car.damage + (self.trailerOut and self.trailerOut.damage or 0)
    local seen = self.spillSeen
    if seen and total > seen then
      local before = M.spillShare(load.crashDamage)
      load.crashDamage = (load.crashDamage or 0) + total - seen
      local after = M.spillShare(load.crashDamage)
      if after > before and math.floor(after * 100) > math.floor(before * 100) then
        local litres = math.floor(load.units * goods.get(load.good).litres * after + 0.5)
        self:toast('warning', 'FUEL SPILLED', 'About ' .. litres .. ' L lost in the crash. The run now pays '
          .. dollars(self:loadPay()) .. '.', 6)
      end
    end
    self.spillSeen = total
  end

  -- The fuel run's part of the job card: what has spilled and what the full load paid.
  function c:fuelRunLoadView()
    local load = self.load
    if not load or not load.fuelRun then return nil end
    local share = self:spilled()
    local litres = load.units * goods.get(load.good).litres
    return { fullPay = load.pay, spilledPercent = math.floor(share * 100 + 0.5),
      spilledLitres = math.floor(litres * share + 0.5), from = places.get(load.from).name }
  end
end

return M
