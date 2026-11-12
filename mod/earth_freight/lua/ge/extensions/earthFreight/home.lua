-- The base of operations (the home, before the Magnate update): a spot on Earth the player buys,
-- where they park while they claim it. It keeps one car stored besides the one they drive. Swap cars
-- puts the stored car out in place of the active one, within HOME_METRES of the spot. Repairs there
-- cost REPAIR_SHARE of the usual price, and Relocate lists it at the usual fee. A car bill, with a
-- free space at the base, can keep the old car and send it there instead of trading it in.
-- Around the town it is in is the base's circle of influence (magnate.lua): its size comes from
-- the owner's best wealth and the region, and jobs with an end inside pay the owner more.
local location = require('earthFreight/location')
local pricing = require('earthFreight/pricing')
local places = require('earthFreight/places')
local persistence = require('earthFreight/persistence')
local magnate = require('earthFreight/magnate')
local M = {}

M.PRICE = 250000
M.HOME_METRES = 200
M.REPAIR_SHARE = 0.5
-- How many cars home keeps besides the one the player drives.
M.SPACES = persistence.HOME_SPACES
-- How long the game waits for the server's answer before Buy can be pressed again.
M.ASK_SECONDS = 15
-- How often the game checks whose turf the truck is in, for the messages when it changes.
M.TURF_SECONDS = 3
-- Corps (Magnate 3, server only): at most this many truckers a corp, the owner too, and how long after leaving
-- one before asking to join again. The server decides both; these are for the HUD's words.
M.CORP_MAX = 5
M.CORP_WAIT_HOURS = 24

local MAX_INTEGER = 9007199254740991
local dollars = pricing.dollars

-- The saved home and stored cars are cleaned by persistence.lua.
M.cleanCar = persistence.storedCar

function M.attach(c)
  -- The controller keeps:
  --   self.property: the home owned, as saved, or nil
  --   self.storedCars: the cars kept there, a list of at most SPACES

  --   self.corp: on a server, the corp the player is a member of (Magnate 3), as saved:
  --     { owner, town, latitude, longitude }, the yard being the owner's spot. Kept in step with the server.

  function c:storedCar() return self.storedCars and self.storedCars[1] or nil end

  -- Where the player keeps a second car and trailer: their base's spot, or as a corp member its yard.
  function c:homeSpot()
    return self.property or self.corp or nil
  end

  -- Whether a car bill can send the old car home: a home (or corp yard) is there and has room.
  function c:homeSpaceFree()
    return self:homeSpot() ~= nil and #(self.storedCars or {}) < M.SPACES
  end

  -- How far the player is from home, or nil.
  function c:homeDistance()
    local here, spot = self.lastSample, self:homeSpot()
    if not spot or not here or not here.valid then return nil end
    return location.distance(here, spot)
  end

  function c:atHome()
    local d = self:homeDistance()
    return d ~= nil and d <= M.HOME_METRES
  end

  -- What the player is worth: cash, plus what their truck is worth, plus what they paid for their
  -- trailers (and their parts) and their base.
  function c:wealth()
    local progression = self.profile and self.profile.progression
    if not progression then return 0 end
    local truck = self:carWorth()
    if type(truck) ~= 'number' then
      local saved = self.profile.vehicle
      truck = type(saved) == 'table' and (saved.worth or saved.value) or 0
    end
    local trailer = self.trailerWorth and self:trailerWorth() or 0
    return progression.balance + math.max(0, truck) + trailer + (self.property and self.property.paid or 0)
  end

  -- The town a spot belongs to, for a base's circle: { latitude, longitude, name, boost }, or nil until
  -- a place there is loaded.
  local function townAt(spot)
    local ok, found = pcall(function()
      places.ensure(spot)
      return places.at(spot) or (places.nearest(spot, 1)[1] or {}).place
    end)
    if not ok or type(found) ~= 'table' or not location.valid(found) then return nil end
    return { latitude = found.latitude, longitude = found.longitude, name = found.name, boost = places.boost(found) }
  end

  -- The town a base's circle is around. A base bought before the Magnate update gets it here.
  local function baseTown(self)
    local p = self.property
    if not p.town then p.town = townAt(p) end
    return p.town
  end

  -- The base's circle of influence, or nil: { latitude, longitude, radiusKm, name, boost, peak, mine }.
  -- The circle never shrinks: it is sized by the most wealth the player has had.
  function c:baseCircle()
    local p = self.property
    if not p then return nil end
    local town = baseTown(self)
    if not town then return nil end
    local wealth = math.floor(self:wealth())
    if wealth > (p.peak or 0) then p.peak = wealth end
    -- On a server, half of each corp member's wealth grows it too (the server sends the sum).
    local extra = 0
    for _, b in ipairs(self.mp and self.mp.state == 'server' and self.mp.bases or {}) do
      if b.mine then extra = b.memberWealth or 0 end
    end
    return { latitude = town.latitude, longitude = town.longitude, name = town.name, boost = town.boost,
      radiusKm = magnate.radiusKm(p.peak + extra, town.boost), peak = p.peak, memberWealth = extra, mine = true }
  end

  -- Every circle that counts for this player: their own, and on a server everyone else's, each base's outposts (its
  -- corp's further bases, Magnate 4) too. full: the circle is full size.
  function c:baseCircles()
    local list = {}
    local own = self:baseCircle()
    if own then
      own.full = magnate.isFull(own.radiusKm) or nil
      list[1] = own
    end
    local others = self.mp and self.mp.state == 'server' and self.mp.bases or nil
    for _, b in ipairs(others or {}) do
      if not b.mine then
        list[#list + 1] = { latitude = b.latitude, longitude = b.longitude, radiusKm = b.radiusKm, name = b.town, owner = b.name,
          corp = b.corp or nil, full = magnate.isFull(b.radiusKm) or nil }
      end
      if not b.mine or own then
        for _, o in ipairs(b.outposts or {}) do
          list[#list + 1] = { latitude = o.latitude, longitude = o.longitude, radiusKm = o.radiusKm, name = o.town,
            owner = not b.mine and b.name or nil, mine = b.mine or nil, corp = b.corp or nil, outpost = true,
            full = magnate.isFull(o.radiusKm) or nil }
        end
      end
    end
    return list
  end

  -- The share of the region multiplier bases add at a point for this player: the owner's in their own
  -- turf, a visitor's anywhere else in a circle, 0 outside them all.
  function c:baseShareAt(point)
    return magnate.shareAt(self:baseCircles(), point)
  end

  -- The function jobs.quote takes for that, or nil when there are no circles at all.
  function c:baseShareFunction()
    if #self:baseCircles() == 0 then return nil end
    return function(point) return self:baseShareAt(point) end
  end

  -- Whose turf a point is in, for this player: { town, owner, mine, share } in their own (the bonus there), or
  -- { town, owner, toll } in someone else's (the percent of a delivery's pay that goes to them), or nil outside.
  local function turfInfo(circles, point)
    local t = point and location.valid(point) and magnate.turf(circles, point)
    if not t then return nil end
    if t.mine then return { town = t.name, mine = true, share = magnate.OWNER_SHARE, percent = magnate.percent(magnate.OWNER_SHARE) } end
    if t.corp then return { town = t.name, owner = t.owner, corp = true, share = magnate.MEMBER_SHARE, percent = magnate.percent(magnate.MEMBER_SHARE) } end
    return { town = t.name, owner = t.owner, toll = math.floor(magnate.TOLL * 100 + 0.5) }
  end

  -- Who a delivery to this point pays the turf toll to: the owner's name (or 'another trucker'), or nil.
  function c:baseTollAt(point)
    local t = point and location.valid(point) and magnate.tollAt(self:baseCircles(), point)
    return t and (t.owner or 'another trucker') or nil
  end
  local function round(n, places_) local m = 10 ^ places_; return math.floor(n * m + 0.5) / m end

  -- What the Base map page draws, built only when it asks: every base's circle (town centres only),
  -- the truck, whose turf it is in, and the current job's two ends with whose turf each is in.
  function c:baseMapData()
    local circles = self:baseCircles()
    local out = { ok = true, coreKm = magnate.CORE_KM, circles = {} }
    for _, b in ipairs(circles) do
      out.circles[#out.circles + 1] = { latitude = round(b.latitude, 5), longitude = round(b.longitude, 5),
        radiusKm = round(b.radiusKm, 1), town = b.name, owner = b.owner, mine = b.mine or nil, corp = b.corp or nil,
        full = b.full or nil, outpost = b.outpost or nil }
    end
    out.land = self:landView()
    local sample = self.lastSample
    if sample and sample.valid and location.valid(sample) then
      out.truck = { latitude = sample.latitude, longitude = sample.longitude,
        heading = location.finite(sample.heading) and math.floor(sample.heading + 0.5) or nil }
      out.turf = turfInfo(circles, sample)
    else
      out.waiting = sample and sample.reason or 'earth_starting'
    end
    local load = self.load
    if load then
      local from, to = load.pickup or places.get(load.from), load.drop or load.business or places.get(load.to)
      -- Contracts and beacon packages never get the base bonus or pay the toll. The bonus counts at the pickup
      -- (not on an off-road drop) and the drop-off; the toll only at the drop-off, and is what the job took.
      local counts = not load.contract and not load.beacon
      local function pin(p, name, bonus, toll)
        if not p or not location.valid(p) then return nil end
        local t = turfInfo(circles, p)
        if t then t.counts = ((t.mine or t.corp) and bonus or (not t.mine and not t.corp and toll)) or nil end
        return { latitude = p.latitude, longitude = p.longitude, name = name, turf = t }
      end
      local fromTown, toTown = places.get(load.from), places.get(load.to)
      out.job = {
        pickup = pin(from, fromTown and fromTown.name, counts and not load.drop, false),
        dropoff = pin(to, load.drop and 'Off-road drop' or (load.business and load.business.name) or (toTown and toTown.name), counts, counts),
        toll = load.toll and { owner = load.toll.owner, amount = load.toll.amount } or nil,
      }
    end
    return out
  end

  -- Tells the player when they cross into or out of a turf, checked every TURF_SECONDS. A change only
  -- counts once it is seen twice in a row, so driving along a border doesn't keep sending messages.
  function c:watchTurf()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return end
    if self.turfCheckedAt and self.clock - self.turfCheckedAt < M.TURF_SECONDS then return end
    self.turfCheckedAt = self.clock
    local sample = self.lastSample
    if not sample or not sample.valid or not location.valid(sample) then return end
    local t = turfInfo(self:baseCircles(), sample)
    local key = t and ((t.mine and 'mine' or t.corp and 'corp' or (t.owner or '?')) .. '@' .. (t.town or '')) or ''
    if self.turf == nil then self.turf, self.turfKey = t or false, key; return end -- where you start says nothing
    if key == self.turfKey then self.turfPending = nil; return end
    if self.turfPending ~= key then self.turfPending = key; return end
    local was = self.turf
    self.turf, self.turfKey, self.turfPending = t or false, key, nil
    local where = function(x) return x.town and (' around ' .. x.town) or '' end
    if t and t.mine then
      self:toast('info', 'Your turf', string.format('You are in your turf%s. Jobs that start and end here pay you up to +%d%%.', where(t), t.percent))
    elseif t and t.corp then
      self:toast('info', 'Your corp\'s turf', string.format('You are in your corp\'s turf%s. Jobs that start and end here pay you up to +%d%%, and you pay no toll.',
        where(t), t.percent))
    elseif t then
      self:toast('info', 'Base turf', string.format('You are in %s\'s turf%s. Deliveries here pay %d%% of their pay to %s.',
        t.owner or 'another trucker', where(t), t.toll, t.owner or 'them'))
    elseif was then
      self:toast('info', 'Base turf', was.mine and 'You have left your turf. No base bonus out here.'
        or was.corp and 'You have left your corp\'s turf. No base bonus out here.'
        or string.format('You have left %s\'s turf. No base bonus out here.', was.owner or 'another trucker'))
    end
  end

  -- Another player's base (or one of their outposts) too close to this town for a new one: the base and the town
  -- that's too close, or nil (magnate.MIN_APART_KM).
  local function tooClose(self, town)
    local others = self.mp and self.mp.state == 'server' and self.mp.bases or nil
    for _, b in ipairs(others or {}) do
      if not b.mine then
        if location.distance(b, town) < magnate.MIN_APART_KM * 1000 then return b, b.town end
        for _, o in ipairs(b.outposts or {}) do
          if location.distance(o, town) < magnate.MIN_APART_KM * 1000 then return b, o.town end
        end
      end
    end
    return nil
  end

  -- What a repair of this much damage costs: REPAIR_SHARE of the usual price at home.
  function c:repairPrice(damage, value)
    local cost = pricing.repairCost(damage, value)
    if cost > 0 and self:atHome() then cost = math.floor(cost * M.REPAIR_SHARE + 0.5) end
    return cost
  end

  -- The base as a Relocate destination.
  function c:homeDestination()
    local p = self.property
    if not p then
      local y = self.corp
      if not y then return nil end
      return { id = 'home', name = 'Corp yard', region = (y.owner or 'Your corp') .. '\'s base' .. (y.town and (', ' .. y.town) or ''),
        latitude = y.latitude, longitude = y.longitude }
    end
    return { id = 'home', name = 'Base', region = p.name or string.format('%.5f, %.5f', p.latitude, p.longitude),
      latitude = p.latitude, longitude = p.longitude }
  end

  -- Why the player cannot do anything at home now (claim or swap), or nil.
  local function busy(self)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage then
      return 'Your base is unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return 'Get back in your car first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    if self.booking then return 'Teleport to your relocation booking, or cancel it, first.' end
    if self.pendingCar or self.pendingParts then return 'Pay for or undo the bill on the Garage tab first.' end
    if self.trailerShop then return 'Finish with your trailer parts on the Garage tab first.' end
    if self.secondHand then return 'Bringing the car out...' end
    local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
    if not self.ownedParts or not vehicle or vehicle.id ~= self.ownedParts.id then return 'Get in your own car first.' end
    if not self.odometer:stopped() then return 'Stop the car first.' end
    return nil
  end

  -- Why Buy this spot cannot be pressed now, or nil.
  function c:claimProblem()
    if self.property then return 'You already own a base.' end
    if self.corp then return 'You are in ' .. (self.corp.owner or 'a') .. '\'s corp. Leave it first: a corp member can\'t own a base.' end
    local problem = busy(self)
    if problem then return problem end
    if not self:canAfford(M.PRICE) then
      return 'Not enough money. You need ' .. dollars(M.PRICE - self.profile.progression.balance) .. ' more.'
    end
    if self.baseAsk and self.clock - self.baseAsk.at < M.ASK_SECONDS then return 'Asking the server...' end
    local here = self.lastSample
    local town = here and here.valid and location.valid(here) and townAt(here) or nil
    local near, at = nil, nil
    if town then near, at = tooClose(self, town) end
    if near then
      return string.format('Too close to %s\'s base in %s. Bases must be %d km apart.', near.name, at or 'a town nearby',
        magnate.MIN_APART_KM)
    end
    return nil
  end

  -- Buys the spot where the car is parked as the player's base. On a server, the server is asked first
  -- (one base a town, MIN_APART_KM apart), and the base is bought when it says yes (baseClaimAnswered).
  function c:claimHome()
    local problem = self:claimProblem()
    local here = self.lastSample
    if not problem and not (here and here.valid and location.valid(here)) then problem = 'Waiting for a valid position.' end
    local town = not problem and townAt(here) or nil
    if not problem and not town then problem = 'Waiting for the towns nearby to load.' end
    if problem then
      self.homeFeedback = problem
      return false
    end
    if self.mp and self.mp.state == 'server' then
      self.baseAsk = { at = self.clock, spot = location.copy(here), town = town }
      self.mp:claimBase({ town = town.name, latitude = town.latitude, longitude = town.longitude, boost = town.boost })
      self.homeFeedback = 'Asking the server whether ' .. tostring(town.name) .. ' is free...'
      return true
    end
    return self:buyBase(location.copy(here), town)
  end

  -- The server's answer: the base is bought where the player asked, or they are told who is there.
  function c:baseClaimAnswered(d)
    local ask = self.baseAsk
    if type(d) ~= 'table' or not ask then return end
    self.baseAsk = nil
    if not d.ok then
      self.homeFeedback = d.why == 'too_close'
        and string.format('Too close to %s\'s base in %s. Bases must be %d km apart.', d.by or 'another trucker', d.town or 'a town nearby', magnate.MIN_APART_KM)
        or d.why == 'have_one' and 'The server already has a base for you.'
        or d.why == 'in_corp' and 'You are in a corp. Leave it first: a corp member can\'t own a base.'
        or 'The server said no. Try again in a moment.'
      return
    end
    local problem = self:claimProblem()
    local here = self.lastSample
    if not problem and not (here and here.valid and location.distance(here, ask.spot) <= M.HOME_METRES) then
      problem = 'You moved away from the spot. Park there and press Buy again.'
    end
    if problem then
      self.homeFeedback = problem
      return
    end
    self:buyBase(ask.spot, ask.town)
  end

  -- Pays for the base and makes this spot and town the player's base.
  function c:buyBase(spot, town)
    if not self:spend(M.PRICE, 'home') then
      self.homeFeedback = 'Not enough money.'
      return false
    end
    local near = town and town.name
    self.property = { latitude = spot.latitude, longitude = spot.longitude, paid = M.PRICE,
      name = type(near) == 'string' and near ~= '' and #near <= 256 and not near:find('%c') and near or nil, town = town }
    self.storedCars = self.storedCars or {}
    local circle = self:baseCircle()
    self.homeFeedback = 'This spot is your base of operations. You paid ' .. dollars(M.PRICE) .. '.'
    self.diag:event('home_bought', string.format('%.5f,%.5f', spot.latitude, spot.longitude))
    self:showFlash('delivered', 'BASE BOUGHT', circle
      and string.format('Your circle reaches %d km around %s. Jobs that start or end inside it pay you more.', math.floor(circle.radiusKm + 0.5), circle.name or 'your base')
      or 'Jobs that start or end near your base pay you more.')
    self:autoSaveSoon('your base')
    return true
  end

  -- The active car as home keeps it: what Save would keep of it.
  function c:activeCarRecord()
    local owned = self.ownedParts
    if not owned then return nil end
    local fuelLitres = self.fuel and self.fuel.vehicleId == owned.id and self.fuel.litres or nil
    local used = self:savedVehicleUsed()
    return M.cleanCar({ config = self:savedVehicleConfig(), name = self:savedVehicleName(), damage = self:savedVehicleDamage(),
      fuelLitres = fuelLitres, value = used and owned.value or nil, km = used and owned.km or nil, worth = self:carWorth() })
  end

  -- Why Swap cars cannot be pressed now, or nil.
  function c:swapProblem()
    if not self:homeSpot() then return 'Buy a base first.' end
    if not self:storedCar() then return 'No car is stored at your base yet.' end
    local problem = busy(self)
    if problem then return problem end
    if self.load then return 'Deliver or abandon your job before swapping cars.' end
    if self:towDebtProblem() then return self:towDebtProblem() end
    if not self:atHome() then
      local d = self:homeDistance()
      return 'Drive to your ' .. (self.property and 'base' or 'corp yard') .. ' to swap cars' .. (d and (': it is ' .. string.format('%.1f', d / 1000) .. ' km away.') or '.')
    end
    return nil
  end

  -- Puts the stored car out where the active one stands, and stores the active one at home. The
  -- stored car comes back as a saved car does on loading: with its fuel, wear and the repair it owes.
  function c:swapCars()
    local problem = self:swapProblem()
    if problem then
      self.homeFeedback = problem
      return false
    end
    local outgoing = self:activeCarRecord()
    if not outgoing then
      self.homeFeedback = 'Your car could not be stored. Try again in a moment.'
      self.diag:event('swap_failed', 'unsaved_config', 'W')
      return false
    end
    local stored = self:storedCar()
    local config = stored.config
    local model, configFile = config.model, config.partConfigFilename
    local value, name
    if self.garage.carValue then
      local ok, v, n = pcall(self.garage.carValue, self.garage, model, configFile)
      if ok then value, name = v, n end
    end
    local oldFuel, oldModel = self.fuel, self.ownedParts.model
    self.arrivingModel, self.arrivingValue, self.arrivingConfigFile = model, value, configFile
    self.arrivingName = stored.name or name
    self.arrivingUsed = stored.value and { value = stored.value, km = stored.km } or nil
    self.appliedWeight, self.tankReading = nil, nil
    self.ourRespawn = true
    self.fuel = stored.fuelLitres and { litres = stored.fuelLitres, restore = true } or nil
    local ok, why, detail = self.garage:spawnConfig(model, config)
    if not ok then
      self.ourRespawn, self.fuel = nil, oldFuel
      self.arrivingModel, self.arrivingValue, self.arrivingUsed, self.arrivingName, self.arrivingConfigFile = nil, nil, nil, nil, nil
      self:applyWeight()
      self.homeFeedback = 'Could not bring your stored car out. Try again in a moment.'
      self.diag:event('swap_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.storedCars = { outgoing }
    -- The stored car owes the repair it was stored with; nothing the other car needed carries over.
    self.owedDamage, self.punctureDamage = stored.damage or 0, 0
    self.lastDamage, self.rawDamage, self.quote, self.repairFeedback = nil, nil, nil, nil
    -- Each photo is of one car: both are taken again as the car stands still.
    if self.garage.removePhoto then
      self.garage:removePhoto(oldModel)
      if model ~= oldModel then self.garage:removePhoto(model) end
    end
    self.photoModel, self.photoStamp, self.homeCard = nil, nil, nil
    self:photoSoon()
    self.homeFeedback = 'Swapped. Your ' .. tostring(outgoing.name or oldModel) .. ' is stored at your ' .. (self.property and 'base.' or 'corp yard.')
    self.diag:event('cars_swapped', tostring(oldModel) .. ' -> ' .. tostring(model))
    self:autoSaveSoon('swapping cars')
    return true
  end

  -- The stored car's card: its name, worth, picture and the repair it owes. Worked out once per car.
  function c:storedCarCard()
    local car = self:storedCar()
    if not car then return nil end
    local known = self.homeCard
    if not known or known.from ~= car then
      local model, configFile = car.config.model, car.config.partConfigFilename
      local value, name, preview
      if self.garage and self.garage.carValue then
        local ok, v, n = pcall(self.garage.carValue, self.garage, model, configFile)
        if ok then value, name = v, n end
      end
      -- The game's own picture: our photo of a model is of the car being driven.
      if self.garage and self.garage.preview then
        local ok, found = pcall(self.garage.preview, self.garage, model, configFile)
        if ok and type(found) == 'string' then preview = found end
      end
      -- What it was worth with its parts when it was parked, else its price.
      value = car.worth or car.value or value
      known = { from = car, name = car.name or name or model, value = value, preview = preview, km = car.km,
        repair = car.damage and pricing.repairCost(car.damage, value) or 0 }
      self.homeCard = known
    end
    return { name = known.name, value = known.value, preview = known.preview, km = known.km, repair = known.repair }
  end

  -- ----- Corps (Magnate 3) -----------------------------------------------------------------------------------------
  -- On a server, a player without a base can join someone else's: the owner accepts them on the Base tab. Members
  -- keep a car and a trailer at the owner's spot (the yard), get MEMBER_SHARE in its turf and pay no toll there.

  -- The base whose corp the server says this player is in, or nil.
  function c:corpBase()
    for _, b in ipairs(self.mp and self.mp.state == 'server' and self.mp.bases or {}) do
      if b.corp then return b end
    end
    return nil
  end

  -- Leaving a corp, or being removed: the car in the yard is traded in (as a car bill would), and trailers there go
  -- to the depot for free.
  local function tradeInStored(self)
    local card = self:storedCarCard()
    if not card then return nil end
    local pay = math.max(0, math.floor((card.value or 0) * pricing.CAR_TRADE_IN_SHARE - (card.repair or 0) + 0.5))
    return pay, card.name
  end

  function c:corpGone(was)
    self.corp, self.leaveArmed = nil, nil
    local lines = {}
    local pay, name = tradeInStored(self)
    if pay then
      self.storedCars, self.homeCard = {}, nil
      if pay > 0 then self:addMoney(pay) end
      lines[#lines + 1] = string.format('Your %s in the yard was traded in for %s.', name or 'car', dollars(pay))
    end
    local moved = false
    for _, t in ipairs({ self.trailer, self.spareTrailer }) do
      if t and t.stored and t.at == 'base' then t.at, moved = 'depot', true end
    end
    if moved then lines[#lines + 1] = 'Your trailer there went to the depot for free.' end
    self:showFlash('cancelled', 'OUT OF THE CORP', string.format('You are no longer in %s\'s corp.', was.owner or 'that')
      .. (#lines > 0 and (' ' .. table.concat(lines, ' ')) or ''))
    self.diag:event('corp_left', tostring(was.owner))
    self:autoSaveSoon('leaving the corp')
  end

  -- Keeps self.corp in step with the server's list of bases: joining, the yard moving, and leaving or being removed.
  function c:watchCorp()
    local mp = self.mp
    if not mp or mp.state ~= 'server' or not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return end
    local done = mp.corpDone
    if done then
      mp.corpDone = nil
      self:corpAnswered(done)
    end
    if not mp.bases or mp.bases == self.corpSeen then return end
    self.corpSeen = mp.bases
    self:watchGrown()
    local b, was = self:corpBase(), self.corp
    if b and not self.property then
      local yard = b.yard or { latitude = b.latitude, longitude = b.longitude }
      local now = { latitude = yard.latitude, longitude = yard.longitude, owner = b.name, town = b.town }
      self.corp = now
      if not was then
        self:showFlash('delivered', 'YOU JOINED A CORP', string.format('You are in %s\'s corp. Jobs in its turf pay you up to +%d%%, you pay no toll there, you get an equal share of the tolls others pay there, and its base keeps a car and a trailer for you.',
          b.name or 'their', magnate.percent(magnate.MEMBER_SHARE)))
        self.diag:event('corp_joined', tostring(b.name))
        self:autoSaveSoon('joining the corp')
      elseif was.latitude ~= now.latitude or was.longitude ~= now.longitude or was.owner ~= now.owner then
        self:autoSaveSoon('your corp')
      end
    elseif was then
      self:corpGone(was)
    end
  end

  local function corpSend(self, what, t, waiting)
    if not self.mp or self.mp.state ~= 'server' then
      self.homeFeedback = 'Corps are only on a trucking server.'
      return false
    end
    if self.corpAskedAt and self.clock - self.corpAskedAt < M.ASK_SECONDS then
      self.homeFeedback = 'Asking the server...'
      return false
    end
    self.corpAskedAt = self.clock
    self.mp:corp(what, t)
    self.homeFeedback = waiting
    return true
  end

  -- Hours until the player may ask to join a corp again, or nil.
  function c:corpWaitHours()
    local w = self.mp and self.mp.corpWait
    if not w then return nil end
    local left = w.seconds - ((self.mp.now or 0) - (w.at or 0))
    if left <= 0 then return nil end
    return math.max(1, math.ceil(left / 3600))
  end

  -- Why this player can't ask to join a corp now, or nil.
  function c:joinProblem()
    if not self.mp or self.mp.state ~= 'server' then return 'Corps are only on a trucking server.' end
    if self.property then return 'You own a base, so you can\'t join a corp.' end
    if self.corp then return 'You are already in a corp.' end
    local hours = self:corpWaitHours()
    if hours then return string.format('You left a corp recently. You can ask to join one again in %d hour%s.', hours, hours == 1 and '' or 's') end
    return nil
  end

  function c:askToJoin(id)
    local problem = self:joinProblem()
    local base
    for _, b in ipairs(self.mp and self.mp.bases or {}) do if b.id == id and not b.mine then base = b end end
    if not problem and not base then problem = 'That base is gone.' end
    if not problem and base.full then problem = string.format('%s\'s corp is full: %d truckers at most.', base.name, M.CORP_MAX) end
    if problem then
      self.homeFeedback = problem
      return false
    end
    return corpSend(self, 'ask', { base = id }, 'Asking to join ' .. base.name .. '\'s corp...')
  end

  function c:cancelJoin() return corpSend(self, 'cancel', {}, 'Taking your request back...') end

  -- Leave corp asks once first, saying what happens to what's in the yard.
  function c:leaveCorp()
    if not self.corp then
      self.homeFeedback = 'You are not in a corp.'
      return false
    end
    if not self.leaveArmed then
      self.leaveArmed = true
      local pay, name = tradeInStored(self)
      self.homeFeedback = string.format('Leave %s\'s corp? You can\'t join another for %d hours.', self.corp.owner or 'the', M.CORP_WAIT_HOURS)
        .. (pay and string.format(' Your %s in the yard is traded in for %s.', name or 'car', dollars(pay)) or '')
        .. ' Press Yes, leave to go ahead.'
      return false
    end
    self.leaveArmed = nil
    return corpSend(self, 'leave', {}, 'Leaving the corp...')
  end

  function c:cancelLeaveCorp()
    self.leaveArmed, self.homeFeedback = nil, nil
    return true
  end

  function c:corpAccept(id) return corpSend(self, 'accept', { who = id }, 'Accepting...') end
  function c:corpRefuse(id) return corpSend(self, 'refuse', { who = id }, 'Turning them down...') end
  function c:corpRemove(id) return corpSend(self, 'remove', { who = id }, 'Removing them from your corp...') end

  -- The server's answer to a corp button.
  function c:corpAnswered(d)
    self.corpAskedAt = nil
    if d.ok then
      self.homeFeedback = d.what == 'ask' and 'Asked to join. The owner sees your request on their Base tab.'
        or d.what == 'cancel' and 'Request taken back.'
        or d.what == 'leave' and 'You left the corp.'
        or d.what == 'accept' and 'Accepted. They are in your corp now.'
        or d.what == 'refuse' and 'Turned down.'
        or d.what == 'remove' and string.format('Removed from your corp. They can\'t join another for %d hours.', M.CORP_WAIT_HOURS)
        or nil
      return
    end
    local hours = d.wait and math.max(1, math.ceil(d.wait / 3600))
    self.homeFeedback = d.why == 'have_base' and (d.what == 'accept' and 'They own a base now, so they can\'t join.' or 'You own a base, so you can\'t join a corp.')
      or d.why == 'in_corp' and (d.what == 'accept' and 'They joined another corp.' or 'You are already in a corp.')
      or d.why == 'wait' and string.format('You left a corp recently. You can ask to join one again in %d hour%s.', hours or M.CORP_WAIT_HOURS, hours == 1 and '' or 's')
      or d.why == 'full' and string.format('That corp is full: %d truckers at most.', M.CORP_MAX)
      or d.why == 'gone' and 'They are no longer there.'
      or d.why == 'busy' and 'That base has too many requests waiting. Try again later.'
      or 'The server said no. Try again in a moment.'
  end

  -- ----- The land race (Magnate 4) ---------------------------------------------------------------------------------
  -- On a server, once the newest circle of the player's corp (their own base's, or the one they're a member of) is
  -- full size, anyone in it can open the corp's next base, free, in a town outside all of its circles. The first corp
  -- to hold the server's winning share of Earth's land wins the season.

  -- The server's entry for this player's corp: their own base, else the one they're a member of, or nil.
  function c:myCorpEntry()
    for _, b in ipairs(self.mp and self.mp.state == 'server' and self.mp.bases or {}) do
      if b.mine or b.corp then return b end
    end
    return nil
  end

  -- The land race for the HUD and the Base map: the share of Earth's land this player's corp holds (nil without
  -- one), what wins, who leads and the days left. nil off a server.
  function c:landView()
    local mp = self.mp
    if not mp or mp.state ~= 'server' or not mp.race then return nil end
    local r = mp.race
    local mine = self:myCorpEntry()
    local left = r.left and math.max(0, r.left - ((mp.now or 0) - (r.at or 0)))
    return { percent = mine and mine.land or nil, who = mine and (mine.mine and #(mine.members or {}) == 0 and 'You hold' or 'Your corp holds') or nil,
      win = r.win, leader = r.leader, leaderLand = r.leaderLand, daysLeft = left and math.max(1, math.ceil(left / 86400)) or nil }
  end

  -- The newest base's town of a corp entry.
  local function newestTown(entry)
    local list = entry.outposts or {}
    return #list > 0 and list[#list].town or entry.town
  end

  -- Why Open a base here cannot be pressed now, or nil.
  function c:openBaseProblem()
    if not self.mp or self.mp.state ~= 'server' then return 'New bases are only on a trucking server.' end
    local mine = self:myCorpEntry()
    if not mine then return 'Buy a base or join a corp first.' end
    if not mine.grown then
      return string.format('Your newest base is not full size yet. It is full at %s of wealth, and your corp has %s.',
        dollars(mine.fullAt or 0), dollars(mine.wealth or 0))
    end
    local problem = busy(self)
    if problem then return problem end
    if self.outpostAsk and self.clock - self.outpostAsk < M.ASK_SECONDS then return 'Asking the server...' end
    local here = self.lastSample
    local town = here and here.valid and location.valid(here) and townAt(here) or nil
    if not town then return 'Waiting for the towns nearby to load.' end
    for _, circle in ipairs(self:baseCircles()) do
      if (circle.mine or circle.corp) and location.distance(circle, town) <= circle.radiusKm * 1000 then
        return 'Inside your corp\'s turf. Go further out: a new base must be outside all of your circles.'
      end
    end
    local near, at = tooClose(self, town)
    if near then
      return string.format('Too close to %s\'s base in %s. Bases must be %d km apart.', near.name, at or 'a town nearby',
        magnate.MIN_APART_KM)
    end
    return nil
  end

  -- Opens the corp's next base in the town the truck is in: the server says yes or no (outpostAnswered).
  function c:openBase()
    local problem = self:openBaseProblem()
    if problem then
      self.homeFeedback = problem
      return false
    end
    local town = townAt(self.lastSample)
    self.outpostAsk = self.clock
    self.mp:openBase({ town = town.name, latitude = town.latitude, longitude = town.longitude, boost = town.boost })
    self.homeFeedback = 'Asking the server to open a base in ' .. tostring(town.name) .. '...'
    return true
  end

  function c:outpostAnswered(d)
    self.outpostAsk = nil
    if type(d) ~= 'table' then return end
    if d.ok then
      self.homeFeedback = nil
      self:showFlash('delivered', 'NEW BASE', string.format('Your corp has a new base in %s. Its circle starts at %d km and grows as your corp gets richer.',
        d.town or 'this town', magnate.START_KM))
      self.diag:event('outpost_opened', tostring(d.town))
      return
    end
    self.homeFeedback = d.why == 'not_full' and 'Your newest base is not full size yet.'
      or d.why == 'inside_own' and 'Inside your corp\'s turf. Go further out: a new base must be outside all of your circles.'
      or d.why == 'too_close' and string.format('Too close to %s\'s base in %s. Bases must be %d km apart.', d.by or 'another trucker',
        d.town or 'a town nearby', magnate.MIN_APART_KM)
      or d.why == 'no_base' and 'Buy a base or join a corp first.'
      or d.why == 'max' and 'Your corp has as many bases as it can have.'
      or 'The server said no. Try again in a moment.'
  end

  -- Says so when the corp's newest circle becomes full size while the player is on (the server tells anyone away).
  function c:watchGrown()
    local entry = self:myCorpEntry()
    local now = { grown = entry and entry.grown or false, count = entry and (1 + #(entry.outposts or {})) or 0 }
    local was = self.grownSeen
    self.grownSeen = now
    if not was or not now.grown or (was.grown and was.count == now.count) then return end
    self:showFlash('delivered', 'BASE FULL SIZE', string.format('Your base in %s is full size. Anyone in your corp can now open a new base in a town outside your turf, on the Base tab.',
      newestTown(entry) or 'your newest town'))
    self.diag:event('base_full', tostring(newestTown(entry)))
  end

  -- The land race card on the Base tab, for a player with a base or in a corp on a server.
  function c:conquestView()
    local entry = self:myCorpEntry()
    if not entry then return nil end
    local list = { { town = entry.town, radiusKm = math.floor(entry.radiusKm + 0.5), full = magnate.isFull(entry.radiusKm) or nil } }
    if entry.mine then
      local own = self:baseCircle()
      if own then list[1].radiusKm, list[1].full = math.floor(own.radiusKm + 0.5), magnate.isFull(own.radiusKm) or nil end
    end
    for _, o in ipairs(entry.outposts or {}) do
      list[#list + 1] = { town = o.town, radiusKm = math.floor(o.radiusKm + 0.5), full = magnate.isFull(o.radiusKm) or nil }
    end
    local problem = self:openBaseProblem()
    local fullAt, wealth = entry.fullAt, entry.wealth or 0
    return { land = entry.land, bases = list, newest = newestTown(entry), grown = entry.grown or nil, fullAt = fullAt, wealth = wealth,
      progress = fullAt and fullAt > 0 and math.min(100, math.floor(wealth * 100 / fullAt)) or nil,
      startKm = magnate.START_KM, maxKm = magnate.MAX_KM,
      openAllowed = problem == nil or nil, openProblem = entry.grown and problem or nil, race = self:landView() }
  end

  -- The Home tab.
  function c:homeView(current)
    if self.state ~= 'READY' or not self.arrived or not self.profile or self.error then return nil end
    local view = { price = M.PRICE, radiusMetres = M.HOME_METRES, repairShare = math.floor(M.REPAIR_SHARE * 100 + 0.5),
      spaces = M.SPACES, feedback = self.homeFeedback }
    -- On a server, everyone else's bases, nearest first.
    local others = {}
    local joinProblem = self:joinProblem()
    local canAsk = not self.property and not self.corp
    for _, b in ipairs(self.mp and self.mp.state == 'server' and self.mp.bases or {}) do
      if not b.mine then
        local names = {}
        for _, m in ipairs(b.members or {}) do names[#names + 1] = m.name end
        others[#others + 1] = { id = b.id, name = b.name, town = b.town, radiusKm = math.floor(b.radiusKm + 0.5),
          distanceMetres = current and location.distance(current, b) or nil,
          inside = current and location.distance(current, b) <= b.radiusKm * 1000 or false,
          members = #names > 0 and table.concat(names, ', ') or nil, corp = b.corp or nil, asked = b.asked or nil,
          full = b.full or nil, canAsk = canAsk and b.id ~= nil and not b.held and not b.asked or nil,
          askAllowed = joinProblem == nil and b.id ~= nil and not b.held and not b.full and not b.asked or nil }
      end
    end
    table.sort(others, function(a, b) return (a.distanceMetres or math.huge) < (b.distanceMetres or math.huge) end)
    while #others > 5 do table.remove(others) end
    view.others = #others > 0 and others or nil
    view.tollPercent = math.floor(magnate.TOLL * 100 + 0.5)
    view.corpMax, view.memberBonus = M.CORP_MAX, magnate.percent(magnate.MEMBER_SHARE)
    view.joinProblem = canAsk and joinProblem or nil
    view.online = self.mp ~= nil and self.mp.state == 'server' or nil
    view.conquest = view.online and self:conquestView() or nil
    local p = self.property
    if not p then
      local problem = self:claimProblem()
      view.claimAllowed, view.claimProblem = problem == nil, problem
      local balance = self.profile.progression.balance
      view.short = balance < M.PRICE and M.PRICE - balance or nil
      local y = self.corp
      if y then
        local base = self:corpBase()
        local names = {}
        for _, m in ipairs(base and base.members or {}) do names[#names + 1] = m.name end
        local d = current and location.distance(current, y) or nil
        view.corp = { owner = y.owner, town = y.town, latitude = y.latitude, longitude = y.longitude,
          members = #names > 0 and table.concat(names, ', ') or nil, radiusKm = base and math.floor(base.radiusKm + 0.5) or nil,
          share = magnate.MEMBER_SHARE, percent = magnate.percent(magnate.MEMBER_SHARE), distanceMetres = d, here = d ~= nil and d <= M.HOME_METRES,
          leaveArmed = self.leaveArmed or nil }
        local owned = self.ownedParts
        view.active = owned and { name = owned.name or owned.model, value = self:carWorth() } or nil
        view.stored = self:storedCarCard()
        local swap = self:swapProblem()
        view.swapAllowed, view.swapProblem = swap == nil, view.stored and swap or nil
      end
      return view
    end
    local d = current and location.distance(current, p) or nil
    view.owned = { latitude = p.latitude, longitude = p.longitude, name = p.name, paid = p.paid, distanceMetres = d,
      here = d ~= nil and d <= M.HOME_METRES }
    local owned = self.ownedParts
    view.active = owned and { name = owned.name or owned.model, value = self:carWorth() } or nil
    view.stored = self:storedCarCard()
    if self.mp and self.mp.state == 'server' then
      local mine
      for _, b in ipairs(self.mp.bases or {}) do if b.mine then mine = b end end
      view.owned.corp = { members = mine and mine.members or {}, requests = mine and mine.requests or {},
        size = 1 + #(mine and mine.members or {}), max = M.CORP_MAX, share = magnate.MEMBER_SHARE,
        percent = magnate.percent(magnate.MEMBER_SHARE) }
    end
    local circle = self:baseCircle()
    if circle then
      local radius = math.floor(circle.radiusKm + 0.5)
      local next = radius < magnate.MAX_KM and math.min(magnate.MAX_KM, (math.floor(radius / 500) + 1) * 500) or nil
      view.circle = { town = circle.name, radiusKm = radius, boost = circle.boost, wealth = math.floor(self:wealth()),
        memberWealth = circle.memberWealth and circle.memberWealth > 0 and circle.memberWealth or nil,
        peak = circle.peak, share = magnate.OWNER_SHARE, percent = magnate.percent(magnate.OWNER_SHARE),
        nextKm = next, nextWealth = next and math.ceil((magnate.wealthFor(next, circle.boost) - (circle.memberWealth or 0)) / 1000) * 1000 or nil,
        maxKm = magnate.MAX_KM, commission = self.mp ~= nil and self.mp.state == 'server' or nil, inside = current and location.distance(current, circle) <= circle.radiusKm * 1000 or false }
    end
    local problem = self:swapProblem()
    view.swapAllowed, view.swapProblem = problem == nil, view.stored and problem or nil
    return view
  end
end

return M
