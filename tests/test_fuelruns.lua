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
  T.near(fuelruns.distanceFactor(100) / fuelruns.distanceFactor(20), 1 + 0.9 * 4, 1e-9, '100 km pays 4.6 times 20 km')
  T.check(fuelruns.distanceFactor(100) > 2 * jobs.distanceFactor(100), 'twice what the square root gives at 100 km')
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
  T.near(q.pay, 284000, 3000, 'and about $284,000 over 100 km as a fuel run, in flat country')
  T.eq(q.factor, fuelruns.BONUS, 'the fuel run bonus'); T.eq(q.shortage, false, 'never a shortage')
  T.eq(fuelruns.quote({ good = 'fuel', from = penrith.id, to = far.id, km = 100 }, 0).pay, 0, 'nothing for no load')
end

-- Spills: nothing for a scrape, then a growing share up to the cap.
do
  T.eq(fuelruns.spillShare(0), 0, 'no damage, no spill'); T.eq(fuelruns.spillShare(900), 0, 'a scrape spills nothing')
  T.check(fuelruns.spillShare(5000) > 0 and fuelruns.spillShare(5000) < 0.2, 'a dent spills a little')
  T.eq(fuelruns.spillShare(30000), fuelruns.MAX_SPILL, 'a major crash spills the most')
  T.eq(fuelruns.spillShare(90000), fuelruns.MAX_SPILL, 'and no more')
  T.eq(fuelruns.payAfterSpill(1000, 0.25), 750, 'pay drops by the share spilled')
  T.eq(fuelruns.payAfterSpill(1000, 0), 1000, 'nothing spilled, full pay')
  T.eq(fuelruns.cooldownLeft(nil, 50), 0, 'never delivered: no wait')
  T.eq(fuelruns.cooldownLeft(100, 100 + fuelruns.COOLDOWN_SECONDS - 5), 5, 'seconds left')
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

-- The controller: the card, loading at the depot, a spill, save and resume, delivery and the wait.
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
  -- A crash spills fuel.
  c:tick(1)
  g.damage = 8000; c:tick(1)
  local share = c:spilled()
  T.check(share > 0, 'a crash spills fuel'); T.eq(c:view().load.pay, fuelruns.payAfterSpill(run.pay, share), 'the job card shows less pay')
  T.eq(c:view().load.fuelRun.spilledPercent, math.floor(share * 100 + 0.5), 'and how much spilled')
  g.damage = 0; c:tick(1)
  T.eq(c:spilled(), share, 'a repair puts nothing back')
  -- Saved mid-run, and back after a reload.
  T.check(c:manualSave(), 'saved mid-run')
  T.check(io.files[A].load.fuelRun, 'the save keeps the fuel run'); T.check(io.files[A].load.crashDamage > 0, 'and its spill')
  local r = F.controller({ io = io, adapter = a, garage = g })
  r:tick(0.1); r:tick(0.6); r:tick(0.6)
  T.check(r.load and r.load.fuelRun, 'the run resumes'); T.near(r:spilled(), share, 1e-9, 'with its spill')
  -- Delivered at the station's town.
  local before = r.profile.progression.balance
  F.drive(r, a, places.get(r.load.to))
  local pay = r:loadPay()
  T.check(r:deliver(), 'delivered'); T.eq(r.profile.progression.balance, before + pay, 'paid less what spilled')
  T.check(r:view().flash.title:find('FUEL RUN DELIVERED') ~= nil, 'the message says so')
  T.check(r:view().flash.text:find('spilled') ~= nil, 'and mentions the spill')
  T.check(r.profile.progression.fuelRunAt ~= nil, 'the wait starts')
  T.check(r:manualSave(), 'saved'); T.eq(io.files[A].progression.fuelRunAt, r.profile.progression.fuelRunAt, 'the wait is saved')
  -- Back at a depot, the next run waits.
  local next = r:view().fuelRuns
  T.check(next and next.cooldownSeconds > 0, 'the next fuel run waits')
end

T.done('fuel runs')
