-- The Earth Freight controller: ties the Earth position, the save, the garage, the places and the
-- market together, and builds the HUD's state. The garage side lives in workshop.lua.
local location = require('earthFreight/location')
local config = require('earthFreight/config')
local persistence = require('earthFreight/persistence')
local diagnostics = require('earthFreight/diagnostics')
local hud = require('earthFreight/hud')
local earthAdapter = require('earthFreight/earthAdapter')
local garage = require('earthFreight/garage')
local punctures = require('earthFreight/punctures')
local pricing = require('earthFreight/pricing')
local odometer = require('earthFreight/odometer')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local market = require('earthFreight/market')
local cargo = require('earthFreight/cargo')
local fuel = require('earthFreight/fuel')
local workshop = require('earthFreight/workshop')
local shipping = require('earthFreight/shipping')
local M = {}
-- Money a new game starts with, and the amount the HUD test button adds.
local STARTING_MONEY = 2500 -- enough for the radiator the starter car needs, and a first load
local TEST_MONEY = 10000
local MAX_BALANCE = 9007199254740991
M.STARTING_MONEY = STARTING_MONEY
M.STARTER_MODEL, M.STARTER_CONFIG = workshop.STARTER_MODEL, workshop.STARTER_CONFIG
-- How many places the nearby list and a town's delivery list show.
local NEARBY_COUNT = 6
-- The delivery distance the player picks on the Town tab, in road km: drop-offs are the places
-- closest to it.
local RANGE = { min = 5, max = 50, step = 5, default = 5 }
M.RANGE = RANGE
-- How long the HUD shows a delivery, a cancelled load or a puncture.
local FLASH_SECONDS = 8
-- A puncture's tyre repair, as damage points, so every repair quote and bill includes it. Like
-- other damage it is priced by the car's Value: TYRE_REPAIR_COST on a REFERENCE_CAR_VALUE car.
local PUNCTURE_DAMAGE = punctures.TYRE_REPAIR_COST / pricing.REPAIR_COST_PER_DAMAGE
local dollars = pricing.dollars

local labels = {
  CONFIG_REQUIRED = 'BASE CONFIGURATION REQUIRED', EARTH_UNAVAILABLE = 'EARTH UNAVAILABLE',
  READY = 'READY', ERROR = 'FREIGHT PAUSED',
}
-- What the HUD asks of the player until they reach the resume point.
local goLabels = { resume = 'GO TO YOUR LAST SAVE', start = 'GO TO ' .. config.START_TOWN:upper() }
local goMessages = {
  resume = 'Copy these coordinates, paste them into the BeamNG.Earth map and teleport there to carry on.',
  start = 'Copy these coordinates, paste them into the BeamNG.Earth map and teleport there to start. You get your starter car when you arrive.',
}
local messages = {
  earth_missing = 'Enable BeamNG.Earth to continue.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_interface_error = 'Earth information is unavailable. Load the level again when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
}
-- What the player sees for each problem that pauses Earth Freight.
local errorMessages = {
  newer_version = 'Your save was made by a newer version of Earth Freight Sim. Update the mod to keep playing.',
  storage_unavailable = 'Earth Freight Sim could not open its save folder. Load the level again to try again.',
  internal_error = 'Earth Freight Sim hit a problem and paused. Load the level again to carry on from your last save.',
}
local loadMessages = {
  loaded = 'Loaded your last save.',
  missing = 'No save yet. Press Save to keep your progress.',
  unreadable = 'Your save file could not be read, so this is a fresh start. Saving will replace it.',
}

local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- Controller dependencies permit deterministic headless tests. No game globals below this factory.
function M.new(deps)
  local c = {
    state = 'CONFIG_REQUIRED', clock = 0, sessionVerified = false,
    diag = diagnostics.new(deps.log), adapter = deps.adapter,
    store = persistence.new(deps.io), ui = hud.new(deps.trigger),
    feedback = 'Not saved this session.', garage = deps.garage,
    paused = deps.paused or function() return false end,
    random = deps.random or math.random,
    -- Wall-clock seconds, which the paid-shipping offers rotate by.
    now = deps.now or os.time,
    -- Bursts tyres and tells whether the car is off road; without it there are no punctures.
    punctures = deps.punctures,
    -- Adds the load's weight to the car, and reads and sets its fuel; without them the load has no
    -- weight and there is no Refuel.
    cargo = deps.cargo, fuelTank = deps.fuel,
    odometer = odometer.new(),
    punctureDamage = 0, owedDamage = 0, refuelSerial = 0,
  }
  workshop.attach(c)

  function c:transition(nextState, reason)
    if self.state == nextState and self.reason == reason then return end
    self.state, self.reason = nextState, reason
    self.diag:event('state', nextState .. ':' .. tostring(reason or ''))
  end

  -- A saved load is kept only when its good and the place it came from are known to this version.
  local function knownLoad(l)
    if type(l) ~= 'table' or not goods.get(l.good) or not places.get(l.from) then return nil end
    if l.to ~= nil and not places.get(l.to) then l.to = nil end
    return copy(l)
  end

  function c:reload()
    self.adapter:invalidate()
    self.odometer:reset()
    self.sessionVerified, self.lastSample, self.error = false, nil, nil
    self.quote, self.repairFeedback = nil, nil
    self.partsFeedback, self.carFeedback, self.tradeFeedback = nil, nil, nil
    self.vehicleProvided, self.arrivingModel, self.arrivingValue, self.arrived = false, nil, nil, false
    self.newGameArmed, self.dumpArmed, self.flash = false, false, nil
    -- Shipping booked and not yet used, and where an unbooked teleport left from. Neither is saved:
    -- Save waits until both are settled.
    self.booking, self.stranded, self.shippingFeedback, self.lastDriven = nil, nil, nil, nil
    self.shippingSearch = nil
    -- A puncture not yet repaired; a reload respawns the car, so its tyre repair is owed instead.
    self.punctureDamage, self.offRoad, self.offRoadCheckedAt = 0, nil, nil
    self.fuel, self.fuelReadAt, self.refuelPending, self.appliedWeight = nil, nil, nil, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    self.profile, self.loadStatus = self.store:load()
    -- A paid-shipping offer the player shipped in on, paid back by their first delivery near it.
    self.offer = self.profile and copy(self.profile.offer) or nil
    -- The saved load's places are near where the player left off.
    if self.profile then places.ensure(self.profile.resume) end
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = loadMessages[self.loadStatus] or ''
    if not self.profile and not loadMessages[self.loadStatus] then self.error = self.loadStatus end
    self.load = self.profile and knownLoad(self.profile.load) or nil
    if self.profile and self.profile.load and not self.load then self.diag:event('load_dropped', tostring(self.profile.load.good), 'W') end
    self.savedDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0
    -- Before the first save the starting money counts as saved, since it was not earned.
    self.savedBalance = self.profile and self.profile.progression.balance or STARTING_MONEY
    -- A restored car looks new, but the repair it needed when saved is still owed.
    self.owedDamage = self.profile and self.profile.vehicle and self.profile.vehicle.damage or 0
    -- The name typed on the start page; like money, a changed name is kept by Save.
    self.playerName = self.profile and self.profile.playerName or nil
    self.savedName = self.playerName
    self.mode = (self.profile and not self.profile.atStart) and 'resume' or 'start'
    self.creationBase = location.copy(self.profile and self.profile.base or self.unsavedBase
      or (self.configuration and self.configuration.base))
    self.startupTarget = location.copy(self.profile and not self.profile.atStart and self.profile.resume or self.creationBase)
    if self.startupTarget then
      self.diag:event('target', self.mode .. ':' .. string.format('%.8f,%.8f', self.startupTarget.latitude, self.startupTarget.longitude))
    end
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration')
    elseif self.error then self:transition('ERROR', self.error)
    else self:transition('EARTH_UNAVAILABLE', 'position_invalid') end
  end

  function c:interrupt(reason)
    self.odometer:reset()
    if self.configuration and not self.error then self:transition('EARTH_UNAVAILABLE', reason) end
  end

  function c:endMission()
    self.sessionVerified, self.lastSample = false, nil
    self:interrupt('earth_level_required')
    self.adapter:invalidate()
  end

  function c:addMoney(amount)
    local progression = self.profile.progression
    progression.balance = math.min(MAX_BALANCE, progression.balance + math.floor(amount))
  end

  function c:canAfford(amount)
    return self.profile ~= nil and not self.error and type(amount) == 'number' and amount >= 0
      and amount == math.floor(amount) and amount <= self.profile.progression.balance
  end

  -- Every purchase pays through here: refuses when the balance is short, never goes below zero.
  -- Like earnings, the new balance is only kept on disk by Save.
  function c:spend(amount, label)
    if not self:canAfford(amount) then
      self.diag:event('spend_rejected', tostring(label) .. ':' .. tostring(amount), 'W')
      return false
    end
    self.profile.progression.balance = self.profile.progression.balance - amount
    self.diag:event('spend', tostring(label) .. ':' .. tostring(amount))
    return true
  end

  function c:showFlash(kind, title, text)
    self.flash = { kind = kind, title = title, text = text, at = self.clock }
  end

  -- Adds the player's name to a greeting: "Welcome back" becomes "Welcome back, Sam".
  function c:named(greeting)
    return self.playerName and (greeting .. ', ' .. self.playerName) or greeting
  end

  -- Sets the player's name. Spaces are tidied, and an empty name clears it. Returns false when the
  -- name is too long or has characters a save cannot hold.
  function c:setPlayerName(name)
    if type(name) ~= 'string' then return false end
    name = name:gsub('%s+', ' '):match('^ ?(.-) ?$')
    if name == '' then self.playerName = nil; return true end
    if not persistence.validName(name) then
      self.diag:event('name_rejected', tostring(#name), 'W')
      return false
    end
    self.playerName = name
    return true
  end

  -- The cargo space of the car the player owns, from its paid-for parts.
  function c:space()
    return cargo.capacity(self.ownedParts)
  end

  -- Puts the load's weight on the car, when it changed or the car respawned.
  function c:applyWeight(force)
    if not self.cargo then return end
    local kg = self.load and self.load.kg or 0
    if not force and self.appliedWeight == kg then return end
    local ok, why, detail = self.cargo:setWeight(kg, self:space().parts)
    if ok then self.appliedWeight = kg
    else self.diag:event('weight_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'W') end
  end

  -- A respawn (repair, part change or reverted car) fills the tank and drops the load's weight;
  -- the fuel the car had is put back once it has spawned, and so is the weight.
  function c:beforeRespawn()
    if self.fuel and self.ownedParts and self.fuel.vehicleId == self.ownedParts.id then self.fuel.restore = true end
    self.appliedWeight = nil
  end

  -- The respawn did not happen, so the car keeps its fuel and weight.
  function c:respawnFailed()
    if self.fuel then self.fuel.restore = nil end
    self:applyWeight()
  end

  -- After a spawn of the player's own car: puts its fuel back and the load's weight on.
  function c:afterRespawn()
    if not self.respawned or self.partsCheckDue or not self.ownedParts then return end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if vehicleId ~= nil and vehicleId ~= self.ownedParts.id then return end
    self.respawned = false
    if self.fuel and self.fuel.restore and self.fuelTank then
      self.fuel.restore = nil
      local ok, why = self.fuelTank:set(self.fuel.litres, 0)
      if not ok then self.diag:event('fuel_restore_failed', tostring(why), 'W') end
    end
    self:applyWeight(true)
  end

  -- Driving. Distance counts only once the player has arrived. A teleport-sized jump never counts;
  -- one longer than a short hop goes through teleported. While stranded nothing counts.
  function c:drive(sample, dt)
    -- Earth can pause while it teleports, which resets the odometer, so the last place driven to
    -- is kept as well.
    local fresh = self.odometer.last == nil
    local before = location.copy(self.odometer.last or self.lastDriven)
    local metres, jump = self.odometer:step(sample, dt)
    self.lastDriven = location.copy(sample)
    if fresh and before then
      local gap = location.distance(before, sample)
      if gap and gap > odometer.SHORT_HOP_METRES then jump = gap end
    end
    if jump then
      if jump > odometer.SHORT_HOP_METRES then self:teleported(before, sample) end
      return
    end
    if self.stranded then
      if shipping.returned(sample, self.stranded) then self:unstrand() end
      return
    end
    if metres <= 0 then return end
    local progression = self.profile.progression
    progression.totalDistanceKm = progression.totalDistanceKm + metres / 1000
    if self.load then self.load.drivenKm = self.load.drivenKm + metres / 1000 end
    self:roadPuncture(sample, metres, dt)
  end

  local function coordinates(p) return string.format('%.5f, %.5f', p.latitude, p.longitude) end

  function c:unstrand()
    self.stranded = nil
    self:showFlash('delivered', 'BACK ON THE ROAD', 'You are back where you teleported from. Deliveries and driving count again.')
    self.diag:event('unstranded', '')
  end

  -- A long teleport. Any load on board is lost, with the money paid for it. A booked one that lands
  -- at the destination is shipping; a jump back to where an unbooked one left from undoes it;
  -- anything else strands the player until they go back or book shipping.
  function c:teleported(from, to)
    local lost = ''
    if self.load then
      local good = goods.get(self.load.good)
      lost = ' The ' .. good.name:lower() .. ' on board is gone, and the ' .. dollars(self.load.paid) .. ' you paid for it is lost.'
      self.diag:event('load_cancelled', 'teleport:' .. self.load.good)
      self.load, self.dumpArmed = nil, false
      self:applyWeight()
    end
    if self.booking and shipping.arrived(to, self.booking) then
      local b = self.booking
      self.booking, self.stranded = nil, nil
      local paid = ''
      if b.offer then
        self.offer = { latitude = b.latitude, longitude = b.longitude, name = b.name, fee = b.fee }
        paid = ' ' .. b.name .. ' pays back your ' .. dollars(b.fee) .. ' shipping when you deliver within '
          .. math.floor(shipping.OFFER_RADIUS_METRES / 1000) .. ' km of it.'
      end
      self:showFlash(lost ~= '' and 'cancelled' or 'delivered', 'SHIPPED TO ' .. b.name:upper(),
        'Welcome to ' .. b.region .. '. Find a load in town.' .. paid .. lost)
      self.diag:event('shipped', b.id)
    elseif self.stranded and shipping.returned(to, self.stranded) then
      self:unstrand()
      if lost ~= '' then self:showFlash('cancelled', 'LOAD LOST', 'You are back where you teleported from.' .. lost) end
    else
      self.stranded = self.stranded or from
      self:showFlash('cancelled', 'SHIPPING NOT BOOKED', 'Deliveries and driving do not count until you go back to '
        .. coordinates(self.stranded) .. ' (copy them on the Route tab), or book shipping on the Garage tab.' .. lost)
      self.diag:event('stranded', coordinates(self.stranded), 'W')
    end
  end

  -- Why booking shipping is not possible now, or nil when it is.
  function c:shippingProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Shipping is unavailable right now.' end
    if self.load then return 'Deliver or dump your load first: cargo cannot be shipped.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.booking then return 'You already have shipping booked to ' .. self.booking.name .. '.' end
    return nil
  end

  -- A place as a shipping destination.
  local function placeDestination(place)
    return place and { id = place.id, name = place.name, region = place.region,
      latitude = place.latitude, longitude = place.longitude } or nil
  end

  -- Books shipping to one of the listed regions or any place by its id.
  function c:bookShipping(destinationId)
    return self:book(shipping.get(destinationId) or placeDestination(places.get(destinationId)))
  end

  -- Books shipping to any coordinates; the region is the nearest place's.
  function c:bookShippingTo(latitude, longitude)
    local point = { latitude = latitude, longitude = longitude }
    if not location.valid(point) then
      self.shippingFeedback = 'Those are not coordinates. Use latitude, longitude, like -16.19, -67.73.'
      return false
    end
    places.ensure(point)
    local near = places.nearest(point, 1)[1]
    return self:book({ id = 'coordinates', name = string.format('%.5f, %.5f', latitude, longitude),
      region = near and (near.metres < 50000 and ('near ' .. near.place.name .. ', ' .. near.place.region) or near.place.region) or 'somewhere remote',
      latitude = latitude, longitude = longitude })
  end

  -- The paid-shipping offer showing now, and the seconds until the next one.
  function c:currentOffer()
    return shipping.offer(self.now(), places.hardest())
  end

  -- Books the offer showing now. The fee is paid as usual and paid back by a delivery there.
  function c:bookOffer()
    local offer = self:currentOffer()
    if not offer then
      self.shippingFeedback = 'No offer right now.'
      return false
    end
    if not self:book({ id = offer.id, name = offer.name, region = offer.region,
      latitude = offer.latitude, longitude = offer.longitude }) then return false end
    self.booking.offer = true
    self.shippingFeedback = self.shippingFeedback .. ' ' .. offer.name .. ' pays it back when you deliver there.'
    return true
  end

  -- Finds places by name to ship to.
  function c:searchShipping(query)
    local found = places.search(query, shipping.SEARCH_RESULTS)
    self.shippingSearch = { query = query, results = {} }
    for _, place in ipairs(found) do self.shippingSearch.results[#self.shippingSearch.results + 1] = placeDestination(place) end
    self.shippingFeedback = #found == 0 and ('No town called ' .. tostring(query) .. '. Try the start of its name, or paste coordinates.') or nil
    return #found > 0
  end

  -- Books shipping to a destination: pay the fee, then teleport there with the coordinates.
  function c:book(destination)
    local here = self.lastSample
    local problem = self:shippingProblem()
    if not problem and not destination then problem = 'Pick a destination.' end
    if not problem and shipping.arrived(here, destination) then problem = 'You are already in ' .. destination.name .. '.' end
    local fee = not problem and shipping.fee(here, destination) or nil
    if not problem and not self:spend(fee, 'shipping') then problem = 'Not enough money. Shipping to ' .. destination.name .. ' costs ' .. dollars(fee) .. '.' end
    if problem then
      self.shippingFeedback = problem
      return false
    end
    self.booking = { id = destination.id, name = destination.name, region = destination.region, fee = fee,
      latitude = destination.latitude, longitude = destination.longitude }
    self.shippingFeedback = 'Booked to ' .. destination.name .. ' for ' .. dollars(fee) .. '. Copy the coordinates, paste them into the BeamNG.Earth map and teleport there.'
    self.diag:event('shipping_booked', destination.id .. ':' .. fee)
    return true
  end

  -- Cancels a booking not yet used and refunds its fee.
  function c:cancelShipping()
    if not self.booking or not self.profile or self.error then return false end
    self:addMoney(self.booking.fee)
    self.shippingFeedback = 'Booking cancelled. ' .. dollars(self.booking.fee) .. ' refunded.'
    self.diag:event('shipping_cancelled', self.booking.id)
    self.booking = nil
    return true
  end

  -- Road punctures. Each stretch driven has a small chance of bursting a tyre (see punctures.lua):
  -- more at speed, double off road, never within GAP_KM of the last one or SAFE_FINISH_METRES of
  -- the drop-off. The tyre repair is added to the repair, which mends it.
  function c:roadPuncture(sample, metres, dt)
    if not self.punctures or self.paused() or self.pendingParts or self.pendingCar then return end
    local progression = self.profile.progression
    if progression.lastPunctureKm and progression.totalDistanceKm - progression.lastPunctureKm < punctures.GAP_KM then return end
    local goal = self.load and self.load.to and places.get(self.load.to)
    local left = goal and location.distance(sample, goal)
    if left and left <= punctures.SAFE_FINISH_METRES then return end
    if not self.offRoadCheckedAt or self.clock - self.offRoadCheckedAt >= punctures.OFF_ROAD_CHECK_SECONDS then
      local ok, offRoad = pcall(self.punctures.offRoad, self.punctures)
      self.offRoad, self.offRoadCheckedAt = ok and offRoad == true, self.clock
    end
    if self.random() >= punctures.chance(metres, metres / dt * 3.6, self.offRoad) then return end
    local ok, why, detail = self.punctures:burst()
    if not ok then
      self.diag:event('puncture_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return
    end
    progression.lastPunctureKm = progression.totalDistanceKm
    self.punctureDamage = self.punctureDamage + PUNCTURE_DAMAGE
    self.quote = nil
    self:showFlash('puncture', 'PUNCTURE!', 'A tyre burst on the road. Repair it on the Garage tab.')
    self.diag:event('puncture', string.format('%.1f km%s', progression.totalDistanceKm, self.offRoad and ' off road' or ''))
  end

  function c:observe(sample, dt)
    self.lastSample = sample
    self.diag:event('earth', tostring(sample.reason or 'available') .. ':' .. tostring(sample.detail or sample.source or ''))
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration'); return end
    if self.error then self:transition('ERROR', self.error); return end
    if not sample.valid or not location.valid(sample) then
      self:interrupt(sample.reason or 'position_invalid'); return
    end
    -- The places around the player, wherever in the world they are.
    places.ensure(sample)
    -- Any valid vehicle position starts the session: saving and driving work wherever the vehicle is.
    if not self.profile then
      self.profile = persistence.newProfile(self.creationBase, sample, sample.vehicle, STARTING_MONEY)
      self.profile.atStart = true
      self.unsavedBase = location.copy(self.profile.base)
      self.diag:event('profile_initialised', 'default (in memory, not yet saved)')
    end
    self.sessionVerified = true
    -- Arriving within the radius of the resume point, usually by teleporting there from the map,
    -- confirms the player is back where they left off.
    if not self.arrived and self.startupTarget then
      local away = location.distance(sample, self.startupTarget)
      if away and away <= self.configuration.resumeRadiusMetres then
        self.arrived = true
        self.odometer:reset()
        if self.mode == 'start' then
          self:showFlash('delivered', self:named('Welcome to ' .. config.START_TOWN):upper(),
            'Your starter car needs a radiator: fit one in the parts menu (Ctrl+W), then pay on the Garage tab.')
        else
          self:showFlash('delivered', self:named('Welcome back'):upper(), 'You are where you last saved.')
        end
        self.diag:event('arrived', string.format('%.1f m', away))
      end
    end
    if self.arrived then self:drive(sample, dt) end
    self:transition('READY', 'verified')
  end

  -- Where the player is trading: the place whose arrival circle they are in, once arrived.
  function c:here()
    local sample = self.lastSample
    if self.state ~= 'READY' or not self.arrived or not sample or not sample.valid then return nil end
    return places.at(sample)
  end

  -- Why trading at this place is not possible now, or nil when it is.
  function c:tradeProblem(place)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Trading is unavailable right now.' end
    if not place then return 'Drive into a town to trade.' end
    if not self.odometer:stopped() then return 'Stop the car to trade.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.stranded then return 'You teleported without booking shipping. Go back to where you left from, or book shipping on the Garage tab.' end
    return nil
  end

  -- How many slots of a good the player can buy here: what fits, and what they can pay for.
  function c:buyQuote(place, good)
    local slots = cargo.fits(self:space(), good)
    local price = market.price(place, good)
    local affordable = self.profile and math.floor(self.profile.progression.balance / price) or 0
    local n = math.max(0, math.min(slots, affordable))
    return { slots = n, fits = slots, price = price, cost = n * price, kg = n * good.kgPerSlot }
  end

  -- Buys count slots of a good for a drop-off; with no count it fills the space as far as the money goes.
  function c:buy(goodId, destinationId, count)
    local place = self:here()
    local problem = self:tradeProblem(place)
    local good, destination = goods.get(goodId), places.get(destinationId)
    if not problem and self.load then problem = 'You already have a load on board. Deliver it or dump it first.' end
    if not problem and (not good or not goods.CARRIED[good.kind]) then problem = 'Your vehicle cannot carry that yet.' end
    if not problem and (not destination or destination.id == place.id) then problem = 'Pick somewhere else to deliver it.' end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local quote = self:buyQuote(place, good)
    if quote.fits == 0 then
      self.tradeFeedback = 'Not enough cargo space or payload for ' .. good.name:lower() .. '. Fit a cargo box in the parts menu.'
      return false
    end
    if count and count > quote.fits then
      self.tradeFeedback = 'Only room for ' .. quote.fits .. ' ' .. good.name:lower() .. (quote.fits == 1 and ' parcel.' or ' parcels.')
      return false
    end
    if count then quote.slots, quote.cost, quote.kg = count, count * quote.price, count * good.kgPerSlot end
    if quote.slots == 0 or not self:spend(quote.cost, 'load') then
      self.tradeFeedback = 'Not enough money. One slot of ' .. good.name:lower() .. ' costs ' .. dollars(quote.price) .. '.'
      return false
    end
    self.load = { good = good.id, slots = quote.slots, kg = quote.kg, paid = quote.cost, from = place.id, to = destination.id,
      drivenKm = 0 }
    self.dumpArmed = false
    self:applyWeight()
    local gps = ''
    if self.configuration.autoGps and self.adapter.setDestination then
      local ok, why = self.adapter:setDestination(destination, destination.name)
      gps = ok and ' The GPS is set to ' .. destination.name .. '.' or ' Set the GPS yourself: copy the drop-off coordinates on the Route tab.'
      self.diag:event('gps', ok and destination.id or tostring(why), ok and 'I' or 'W')
    end
    self.tradeFeedback = 'Loaded ' .. quote.slots .. ' ' .. good.name:lower() .. (quote.slots == 1 and ' parcel' or ' parcels') .. ' ('
      .. quote.kg .. ' kg) for ' .. dollars(quote.cost) .. '.' .. gps
    self.diag:event('load_bought', string.format('%s x%d %s -> %s for %d', good.id, quote.slots, place.id, destination.id, quote.cost))
    return true
  end

  -- What delivering the load here would pay, and why it cannot be sold here yet (nil when it can).
  function c:saleQuote(place)
    if not self.load or not place then return nil end
    local good, from = goods.get(self.load.good), places.get(self.load.from)
    local quote = { payout = market.payout(place, good, self.load.slots, from) }
    if place.id == from.id then quote.problem = 'You bought this load here. Deliver it somewhere else.'
    else
      local needed = market.drivenNeeded(from, place)
      if self.load.drivenKm * 1000 < needed then
        quote.problem = 'Drive it here: you have driven ' .. string.format('%.1f', self.load.drivenKm) .. ' km of the '
          .. string.format('%.1f', needed / 1000) .. ' km this delivery needs.'
      end
    end
    return quote
  end

  function c:sell()
    local place = self:here()
    local problem = self:tradeProblem(place)
    if not problem and not self.load then problem = 'You have nothing to deliver.' end
    local quote = not problem and self:saleQuote(place) or nil
    if quote and quote.problem then problem = quote.problem end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local load, good = self.load, goods.get(self.load.good)
    self:addMoney(quote.payout)
    self.load, self.dumpArmed = nil, false
    self:applyWeight()
    local refund = ''
    if self.offer and shipping.offerPays(place, self.offer) then
      self:addMoney(self.offer.fee)
      refund = ' ' .. self.offer.name .. ' paid back your ' .. dollars(self.offer.fee) .. ' shipping.'
      self.diag:event('offer_paid', self.offer.name .. ':' .. self.offer.fee)
      self.offer = nil
    end
    local profit = quote.payout - load.paid
    self:showFlash('delivered', 'DELIVERED: +' .. dollars(quote.payout), load.slots .. ' ' .. good.name:lower() .. ' to ' .. place.name
      .. '. ' .. (profit >= 0 and (self:named('Nice driving') .. '. Profit ' .. dollars(profit)) or ('Loss ' .. dollars(-profit))) .. ' on the ' .. dollars(load.paid) .. ' load.' .. refund .. ' Save to keep it.')
    self.tradeFeedback = nil
    self.diag:event('load_delivered', string.format('%s x%d -> %s for %d', good.id, load.slots, place.id, quote.payout))
    return true
  end

  -- Throws the load away, to free the car; the money paid for it is lost. Asks once first.
  function c:dumpLoad()
    if not self.load or not self.profile or self.error then return false end
    if not self.dumpArmed then
      self.dumpArmed = true
      self.tradeFeedback = 'Press Confirm dump to throw the load away. The ' .. dollars(self.load.paid) .. ' you paid for it is lost.'
      return false
    end
    self.diag:event('load_dumped', self.load.good)
    self.load, self.dumpArmed = nil, false
    self:applyWeight()
    self.tradeFeedback = 'Load dumped.'
    return true
  end

  -- Fuel. The car is asked for its tank every READ_EVERY_SECONDS once arrived; the answer comes back
  -- through fuelReading. Refuel fills the tank as far as the money goes, inside a place's arrival
  -- circle, stopped, and is charged when the car reports how much went in.
  function c:watchFuel()
    if not self.fuelTank or self.state ~= 'READY' or not self.arrived or self.partsCheckDue then return end
    if self.fuelReadAt and self.clock - self.fuelReadAt < fuel.READ_EVERY_SECONDS then return end
    self.fuelReadAt = self.clock
    local ok, why = self.fuelTank:read()
    if not ok then self.diag:event('fuel_read_failed', tostring(why), 'W') end
  end

  function c:fuelReading(vehicleId, litres, capacity)
    if not location.finite(litres) or not location.finite(capacity) or capacity <= 0 or litres < 0 then return end
    local current = self.lastSample and self.lastSample.vehicle and self.lastSample.vehicle.id
    if current ~= nil and vehicleId ~= current then return end
    -- A reading taken before a respawn's restore has gone in would undo it.
    if self.fuel and self.fuel.restore then return end
    self.fuel = { vehicleId = vehicleId, litres = math.min(litres, capacity), capacity = capacity, at = self.clock }
  end

  function c:refuelQuote()
    local f = self.fuel
    if not f or self.clock - f.at > fuel.STALE_SECONDS then return nil end
    local wanted = math.max(0, f.capacity - f.litres)
    local balance = self.profile and self.profile.progression.balance or 0
    local litres = math.min(wanted, math.floor(balance / fuel.PRICE_PER_LITRE))
    return { wanted = wanted, litres = litres, cost = fuel.cost(litres), full = wanted <= fuel.FULL_MARGIN_LITRES }
  end

  function c:refuel()
    local place = self:here()
    local problem = self:tradeProblem(place)
    local quote = self:refuelQuote()
    if not problem and not quote then problem = 'Could not read your fuel gauge. Try again in a moment.' end
    if not problem and quote.full then problem = 'Your tank is already full.' end
    if not problem and quote.litres <= 0 then problem = 'Not enough money for fuel: ' .. string.format('$%.2f', fuel.PRICE_PER_LITRE) .. ' a litre.' end
    if not problem and self.refuelPending then problem = 'Refuelling...' end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    self.refuelSerial = self.refuelSerial + 1
    self.refuelPending = { serial = self.refuelSerial, at = self.clock }
    local ok, why = self.fuelTank:set(self.fuel.litres + quote.litres, self.refuelSerial)
    if not ok then
      self.refuelPending = nil
      self.tradeFeedback = 'Could not refuel. You have not been charged.'
      self.diag:event('refuel_failed', tostring(why), 'E')
      return false
    end
    self.tradeFeedback = 'Refuelling...'
    return true
  end

  -- The car's answer to a fuel change: a refuel is charged for what went in; a restore is free.
  function c:fuelSet(vehicleId, serial, before, after, capacity)
    if not location.finite(before) or not location.finite(after) or not location.finite(capacity) then return end
    local pending = self.refuelPending
    if pending and serial == pending.serial then
      self.refuelPending = nil
      local litres = math.max(0, after - before)
      local cost = math.min(fuel.cost(litres), self.profile and self.profile.progression.balance or 0)
      if cost > 0 then self:spend(cost, 'fuel') end
      self.tradeFeedback = 'Refuelled ' .. string.format('%.1f', litres) .. ' L for ' .. dollars(cost) .. '.'
      self.diag:event('refuelled', string.format('%.1f L, %d', litres, cost))
    end
    if capacity > 0 then self.fuel = { vehicleId = vehicleId, litres = math.min(after, capacity), capacity = capacity, at = self.clock } end
  end

  function c:tick(dtReal)
    local dt = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + dt
    self:observe(self.adapter:sample(), dt)
    self:provideVehicle()
    self:watchParts()
    self:afterRespawn()
    self:watchFuel()
    -- A refuel the car never answered is given up, uncharged.
    if self.refuelPending and self.clock - self.refuelPending.at > fuel.STALE_SECONDS then
      self.refuelPending, self.tradeFeedback = nil, 'Refuelling did not go through. You have not been charged.'
    end
    self.ui:publish(self:view(), self.clock)
  end

  -- The best run from a place for a new player: the good and nearby drop-off that make the most.
  function c:bestRun(place, destinations)
    local best
    for _, good in ipairs(goods.carried()) do
      local quote = self:buyQuote(place, good)
      if quote.slots > 0 then
        for _, d in ipairs(destinations) do
          local profit = math.floor(quote.slots * (market.price(d.place, good) + market.freightPerSlot(place, d.place, good) - quote.price) + 0.5)
          if profit > 0 and (not best or profit > best.profit) then
            best = { good = good.name, from = place.name, to = d.place.name, toId = d.place.id, goodId = good.id, profit = profit }
          end
        end
      end
    end
    return best
  end

  local function dots(place)
    local out = {}
    for _, good in ipairs(goods.carried()) do out[#out + 1] = { id = good.id, name = good.name, level = market.level(place, good) } end
    return out
  end

  -- Sets the delivery distance the Town tab's drop-offs are picked around, in road km.
  function c:setDeliveryRange(km)
    if type(km) ~= 'number' or km ~= km then return false end
    self.rangeKm = math.max(RANGE.min, math.min(RANGE.max, math.floor(km / RANGE.step + 0.5) * RANGE.step))
    return true
  end

  -- The drop-offs offered from a place: the places nearest the picked delivery distance.
  function c:destinationsFrom(place)
    return places.around(place, (self.rangeKm or RANGE.default) * 1000, NEARBY_COUNT, place.id)
  end

  function c:tradeView(current)
    local place = current and self:here()
    local anchor = place or (current and (places.nearest(current, 1)[1] or {}).place)
    local nearby = {}
    if current then
      for _, n in ipairs(places.nearest(current, NEARBY_COUNT, place and place.id)) do
        nearby[#nearby + 1] = { id = n.place.id, name = n.place.name, size = n.place.size,
          distanceMetres = n.metres * places.ROAD_FACTOR, dots = dots(n.place),
          destination = self.load ~= nil and self.load.to == n.place.id }
      end
    end
    local town
    if place then
      local problem = self:tradeProblem(place)
      local destinations = self:destinationsFrom(place)
      local goodsHere = {}
      for _, good in ipairs(goods.carried()) do
        local quote = self:buyQuote(place, good)
        local prices = {}
        for _, d in ipairs(destinations) do
          local sell = market.price(d.place, good)
          local freight = market.freightPerSlot(place, d.place, good)
          prices[#prices + 1] = { id = d.place.id, price = sell, freight = freight,
            profit = math.floor(quote.slots * (sell + freight - quote.price) + 0.5), level = market.level(d.place, good) }
        end
        goodsHere[#goodsHere + 1] = { id = good.id, name = good.name, price = quote.price, level = market.level(place, good),
          kgPerSlot = good.kgPerSlot, slots = quote.slots, fits = quote.fits, cost = quote.cost, prices = prices }
      end
      local destList = {}
      for _, d in ipairs(destinations) do
        destList[#destList + 1] = { id = d.place.id, name = d.place.name, size = d.place.size, distanceMetres = d.metres * places.ROAD_FACTOR,
          boost = places.boost(d.place) }
      end
      local sale = self:saleQuote(place)
      local refuel = self:refuelQuote()
      town = {
        id = place.id, name = place.name, size = place.size, stopped = self.odometer:stopped(), problem = problem,
        region = place.region, boost = places.boost(place),
        goods = goodsHere, destinations = destList, freightPerTonneKm = market.FREIGHT_PER_TONNE_KM,
        range = { km = self.rangeKm or RANGE.default, min = RANGE.min, max = RANGE.max, step = RANGE.step },
        buyAllowed = problem == nil and not self.load,
        sale = sale and { payout = sale.payout, problem = sale.problem } or nil,
        sellAllowed = problem == nil and sale ~= nil and sale.problem == nil,
        refuel = refuel and { litres = refuel.litres, cost = refuel.cost, full = refuel.full } or nil,
        refuelAllowed = problem == nil and self.fuelTank ~= nil and refuel ~= nil and not refuel.full and refuel.litres > 0
          and not self.refuelPending,
      }
    end
    local loadView
    if self.load then
      local good, to, from = goods.get(self.load.good), self.load.to and places.get(self.load.to), places.get(self.load.from)
      loadView = {
        good = good.name, goodId = good.id, slots = self.load.slots, kg = self.load.kg, paid = self.load.paid,
        drivenKm = self.load.drivenKm,
        from = from.name, to = to and to.name or nil, destination = to and location.copy(to) or nil,
        distanceMetres = to and current and places.roadEstimate(current, to) or nil,
        direction = to and current and location.compassPoint(location.bearing(current, to)) or nil,
        payout = to and market.payout(to, good, self.load.slots, from) or nil,
      }
    end
    local destinations = anchor and self:destinationsFrom(anchor) or {}
    return {
      here = place and { id = place.id, name = place.name, size = place.size } or nil,
      -- The region you are in, from the nearest place, and its pay boost.
      region = anchor and { name = anchor.region, boost = places.boost(anchor) } or nil,
      nearby = nearby, town = town, load = loadView,
      bestRun = not self.load and anchor and self:bestRun(anchor, destinations) or nil,
      dumpAllowed = self.load ~= nil, dumpArmed = self.dumpArmed,
    }
  end

  function c:shippingView(current)
    if not current or self.state ~= 'READY' or not self.arrived then return nil end
    local problem = self:shippingProblem()
    local list = {}
    for _, d in ipairs(shipping.DESTINATIONS) do
      local here, fee = shipping.arrived(current, d), shipping.fee(current, d)
      list[#list + 1] = { id = d.id, name = d.name, region = d.region, fee = fee, here = here,
        allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local found = {}
    for _, d in ipairs(self.shippingSearch and self.shippingSearch.results or {}) do
      local here, fee = shipping.arrived(current, d), shipping.fee(current, d)
      found[#found + 1] = { id = d.id, name = d.name, region = d.region, fee = fee, here = here,
        allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local offer, left = self:currentOffer()
    local offerView
    if offer then
      local here, fee = shipping.arrived(current, offer), shipping.fee(current, offer)
      offerView = { id = offer.id, name = offer.name, region = offer.region, boost = offer.boost, fee = fee,
        secondsLeft = left, here = here, allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local b = self.booking
    return {
      offer = offerView, destinations = list, found = found, query = self.shippingSearch and self.shippingSearch.query or nil,
      problem = problem, feedback = self.shippingFeedback,
      pending = self.offer and { name = self.offer.name, fee = self.offer.fee, radiusKm = shipping.OFFER_RADIUS_METRES / 1000,
        distanceMetres = location.distance(current, self.offer) } or nil,
      booking = b and { id = b.id, name = b.name, region = b.region, fee = b.fee, offer = b.offer == true, latitude = b.latitude, longitude = b.longitude,
        distanceMetres = location.distance(current, b) } or nil,
    }
  end

  function c:view()
    local current = self.lastSample and self.lastSample.valid and location.copy(self.lastSample) or nil
    -- Where the player goes to carry on: the last save, or the start before the first save.
    local resume = not self.arrived and not self.error and location.copy(self.startupTarget) or nil
    local base = location.copy(self.profile and self.profile.base or self.creationBase)
    local status = messages[self.reason]
    -- A quote only stands for the vehicle it was made for.
    local quote = self.quote
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if quote and (self.error or vehicleId ~= quote.vehicleId) then quote = nil end
    if self.state == 'CONFIG_REQUIRED' then
      status = 'Set valid base coordinates in the Earth Freight Sim configuration, then load the level again.'
    elseif self.state == 'ERROR' then
      status = errorMessages[self.error] or errorMessages.internal_error
    elseif self.state == 'READY' and not self.arrived then
      status = goMessages[self.mode]
    elseif self.state == 'READY' then
      status = nil
    elseif not status then status = messages.position_invalid end
    local label = labels[self.state]
    if self.state == 'READY' and not self.arrived then label = goLabels[self.mode] end
    local active = self.profile ~= nil and not self.error
    local flashShown = self.flash ~= nil and self.clock - self.flash.at < FLASH_SECONDS
    local space = self:space()
    local trade = (self.state == 'READY' and self.arrived) and self:tradeView(current) or {}
    return {
      state = self.state, stateLabel = label, mode = self.mode,
      sessionStatus = status, arrived = self.arrived,
      -- The base is not shown; it stays in the state for tools and tests.
      base = base,
      resume = resume,
      resumeDistanceMetres = current and resume and location.distance(current, resume) or nil,
      resumeRadiusMetres = self.configuration and self.configuration.resumeRadiusMetres or nil,
      startTown = config.START_TOWN,
      playerName = self.playerName,
      nameUnsaved = self.playerName ~= self.savedName,
      newGameAllowed = self:newGameAllowed(),
      newGameArmed = self.newGameArmed,
      vehicle = current and self.lastSample.vehicle and {
        model = self.lastSample.vehicle.model, id = self.lastSample.vehicle.id,
      } or nil,
      balance = self.profile and self.profile.progression.balance or STARTING_MONEY,
      totalDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0,
      unsavedDistanceKm = self.profile and math.max(0, self.profile.progression.totalDistanceKm - self.savedDistanceKm) or 0,
      unsavedBalance = self.profile and math.max(0, self.profile.progression.balance - self.savedBalance) or 0,
      unsavedSpending = self.profile and math.max(0, self.savedBalance - self.profile.progression.balance) or 0,
      -- Cargo space from the boxes on the car, the fuel in the tank, and trading.
      space = { slots = space.slots, kg = space.kg, boxes = space.boxes, boot = space.boot },
      fuel = self.fuel and { litres = self.fuel.litres, capacity = self.fuel.capacity, pricePerLitre = fuel.PRICE_PER_LITRE } or nil,
      here = trade.here, region = trade.region, nearby = trade.nearby, town = trade.town, load = trade.load, bestRun = trade.bestRun,
      dumpAllowed = trade.dumpAllowed, dumpArmed = trade.dumpArmed,
      tradeFeedback = self.tradeFeedback,
      flash = flashShown and { kind = self.flash.kind, title = self.flash.title, text = self.flash.text } or nil,
      testMoneyAllowed = active,
      repairQuoteAllowed = active and self.garage ~= nil,
      repairQuote = quote and quote.cost or nil,
      repairOwed = self.owedDamage > 0 and pricing.repairCost(self.owedDamage, self:carValueOf(self.ownedParts and self.ownedParts.id)) or nil,
      repairAllowed = quote ~= nil and not self.pendingParts and not self.pendingCar,
      repairFeedback = self.repairFeedback,
      partsChange = self.pendingParts and {
        added = self.pendingParts.added, removed = self.pendingParts.removed,
        partsCost = self.pendingParts.partsCost, repair = self.pendingParts.repair, cost = self.pendingParts.cost,
      } or nil,
      buyPartsAllowed = self:buyPartsAllowed(),
      revertPartsAllowed = self.pendingParts ~= nil,
      partsFeedback = self.partsFeedback,
      carChange = self.pendingCar and {
        name = self.pendingCar.name, price = self.pendingCar.price, extras = self.pendingCar.extras,
        tradeIn = self.pendingCar.tradeIn, repair = self.pendingCar.repair, cost = self.pendingCar.cost,
        oldName = self.ownedParts and self.ownedParts.name or nil,
      } or nil,
      buyCarAllowed = self:buyCarAllowed(),
      revertCarAllowed = self.pendingCar ~= nil,
      carFeedback = self.carFeedback,
      saveAllowed = self.state == 'READY' and self.arrived and not self.stranded and not self.booking,
      shipping = self:shippingView(current),
      stranded = self.stranded and current and {
        latitude = self.stranded.latitude, longitude = self.stranded.longitude,
        distanceMetres = location.distance(current, self.stranded),
      } or nil,
      saveFeedback = self.feedback,
      puncture = self.punctureDamage > 0 and {
        tyreCost = math.floor(self.punctureDamage / PUNCTURE_DAMAGE + 0.5)
          * math.floor(PUNCTURE_DAMAGE * pricing.repairRate(self:carValueOf(self.ownedParts and self.ownedParts.id)) + 0.5),
      } or nil,
    }
  end

  -- Writes a save of this profile and makes it the loaded one. Returns it, or nil and why.
  function c:record(candidate)
    candidate.schemaVersion, candidate.profileId = persistence.SCHEMA, 'default'
    local saved, why = self.store:save(candidate)
    if not saved then return nil, why end
    self.profile, self.unsavedBase = saved, nil
    self.savedName = saved.playerName
    self.savedDistanceKm = saved.progression.totalDistanceKm
    self.savedBalance = saved.progression.balance
    return saved
  end

  function c:manualSave()
    if self.state ~= 'READY' or not self.profile or self.error then
      self.feedback = 'Save is unavailable right now. Check the status above.'
      self.diag:event('manual_save_rejected', tostring(self.state), 'W')
      return false
    end
    -- Until the player reaches the resume point they are not in their own car, so a Save would
    -- replace the saved car and location with the stand-in vehicle and wherever it is.
    if self.stranded or self.booking then
      self.feedback = self.stranded and 'Go back to where you teleported from, or book shipping, before saving.'
        or 'Teleport to your shipping booking, or cancel it, before saving.'
      self.diag:event('manual_save_rejected', self.stranded and 'stranded' or 'booking', 'W')
      return false
    end
    if not self.arrived then
      self.feedback = 'Go to the coordinates above before saving.'
      self.diag:event('manual_save_rejected', 'not_arrived', 'W')
      return false
    end
    -- Read the vehicle position at click time so the saved location is current.
    local fresh = self.adapter:sample()
    if not fresh.valid or not location.valid(fresh) then
      self.lastSample = fresh
      self:interrupt(fresh.reason or 'position_invalid')
      self.feedback = 'Save paused. Waiting for a valid vehicle position.'
      self.diag:event('manual_save_rejected', fresh.reason or 'position_invalid', 'W')
      return false
    end
    local fuelLitres = self.fuel and self.ownedParts and self.fuel.vehicleId == self.ownedParts.id and self.fuel.litres or nil
    local progression = self.profile.progression
    local saved, why = self:record({
      base = self.profile.base, resume = location.copy(fresh),
      progression = { balance = progression.balance, totalDistanceKm = progression.totalDistanceKm, lastPunctureKm = progression.lastPunctureKm },
      vehicle = { model = fresh.vehicle and fresh.vehicle.model, config = self:savedVehicleConfig(),
        damage = self:savedVehicleDamage(), fuelLitres = fuelLitres },
      load = copy(self.load), offer = copy(self.offer), playerName = self.playerName,
    })
    if not saved then
      -- Nothing is lost: the last save is untouched and the session carries on, so Save can be tried again.
      self.feedback = 'Could not save just now. Your last save is still safe. Press Save to try again.'
      self.diag:clear('manual_save_failed'); self.diag:event('manual_save_failed', why, 'E')
      return false
    end
    self.lastSample = fresh
    self.mode = 'resume'
    self.feedback = self:named('Saved') .. '.'
    self.diag:clear('manual_save_succeeded'); self.diag:event('manual_save_succeeded', 'generation ' .. saved.generation)
    return true
  end

  function c:newGameAllowed()
    return self.configuration ~= nil and not self.store.blocked
  end

  function c:newGame()
    if not self:newGameAllowed() then
      self.feedback = 'New game is unavailable right now. Check the status above.'
      return false
    end
    if not self.newGameArmed then
      self.newGameArmed = true
      self.feedback = 'Press Confirm new game to start over in ' .. config.START_TOWN .. ' in the starter car with '
        .. dollars(STARTING_MONEY) .. '. Your car, load and every dollar you have now are lost.'
      return false
    end
    local start = location.copy(self.configuration.base)
    local saved, why = self:record({ base = start, resume = start,
      progression = { balance = STARTING_MONEY, totalDistanceKm = 0 }, vehicle = {}, atStart = true,
      playerName = self.playerName })
    if not saved then
      self.newGameArmed = false
      self.feedback = 'Could not start a new game just now. Your save is unchanged. Press New game to try again.'
      self.diag:event('new_game_failed', tostring(why), 'E')
      return false
    end
    self.diag:event('new_game', config.START_TOWN)
    self:reload()
    self.feedback = string.format('New game started. Teleport to %s at %.8f, %.8f (Copy is just below) to get your starter car.',
      config.START_TOWN, start.latitude, start.longitude)
    return true
  end

  -- Testing aid: adds money to the in-memory balance. Like earnings, it is kept by Save.
  function c:addTestMoney()
    if not self.profile or self.error then
      self.diag:event('test_money_rejected', tostring(self.state), 'W')
      return false
    end
    self:addMoney(TEST_MONEY)
    self.diag:event('test_money_added', tostring(TEST_MONEY))
    return true
  end

  function c:mount(on)
    if self.ui:mount(on, self.clock) then
      self.diag:clear('ui_initialised'); self.diag:event('ui_initialised', 'Earth Freight HUD')
    end
  end

  c:reload()
  return c
end

local active
local function gameIO()
  return {
    read = function(path) return jsonReadFile(path) end,
    exists = function(path) return FS:fileExists(path) end,
    mkdir = function(path)
      if not FS:directoryExists(path) then FS:directoryCreate(path, true) end
      return FS:directoryExists(path)
    end,
    -- Compact JSON: the pretty writer may round coordinates.
    write = function(path, data) return jsonWriteFile(path, data, false) end,
  }
end
-- Whether the game is paused; punctures wait while it is.
local function gamePaused()
  for _, name in ipairs({ 'bullettime', 'simTimeAuthority' }) do
    local timing = rawget(_G, name)
    if type(timing) == 'table' and type(timing.getPause) == 'function' then return timing.getPause() == true end
  end
  return false
end
local function ensure()
  if not active then
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), garage = garage.new(),
      punctures = punctures.new(), cargo = cargo.new(), fuel = fuel.new(),
      log = rawget(_G, 'log'),
      paused = gamePaused, trigger = function(event, payload) if guihooks then guihooks.trigger(event, payload) end end })
  end
  return active
end
local function safely(f)
  local ok, result = pcall(f)
  if not ok then
    if active then
      active.error, active.feedback = 'internal_error', 'Anything since your last save is lost when you reload.'
      active:transition('ERROR', 'internal_error')
      active.diag:event('internal_error', tostring(result), 'E')
    elseif log then log('E', 'earthFreight', tostring(result)) end
    return false
  end
  return result
end
-- Ids the HUD may send: place and good ids are short lowercase words and digits.
local function id(value)
  return type(value) == 'string' and value:match('^[a-z0-9_]+$') and #value <= 64 and value or nil
end

function M.onExtensionLoaded()
  return safely(function() local c = ensure(); c.diag:event('extension_loaded', 'Earth Freight') end)
end
function M.onPreRender(dtReal)
  return safely(function() ensure():tick(dtReal) end)
end
function M.save() return safely(function() return ensure():manualSave() end) end
function M.addTestMoney() return safely(function() return ensure():addTestMoney() end) end
function M.requestRepairQuote() return safely(function() return ensure():requestRepairQuote() end) end
function M.repairVehicle() return safely(function() return ensure():repairVehicle() end) end
function M.buyParts() return safely(function() return ensure():buyParts() end) end
function M.revertParts() return safely(function() return ensure():revertParts(false) end) end
function M.buyCar() return safely(function() return ensure():buyCar() end) end
function M.revertCar() return safely(function() return ensure():revertCar(false) end) end
function M.newGame() return safely(function() return ensure():newGame() end) end
-- count is how many slots to buy; anything but a whole number from 1 to 999 buys as many as fit and are affordable.
function M.buyLoad(good, destination, count)
  local n = type(count) == 'number' and count == math.floor(count) and count >= 1 and count <= 999 and count or nil
  return safely(function() return ensure():buy(id(good), id(destination), n) end)
end
function M.sellLoad() return safely(function() return ensure():sell() end) end
function M.dumpLoad() return safely(function() return ensure():dumpLoad() end) end
function M.refuel() return safely(function() return ensure():refuel() end) end
function M.bookShipping(destination) return safely(function() return ensure():bookShipping(id(destination)) end) end
-- latitude and longitude are numbers; the query is letters, digits, spaces, dots and hyphens.
function M.bookShippingTo(latitude, longitude)
  if type(latitude) ~= 'number' or type(longitude) ~= 'number' then return false end
  return safely(function() return ensure():bookShippingTo(latitude, longitude) end)
end
function M.searchShipping(query)
  if type(query) ~= 'string' or #query > 60 or query:find('[^%w %.%-]') then return false end
  return safely(function() return ensure():searchShipping(query) end)
end
function M.bookOffer() return safely(function() return ensure():bookOffer() end) end
function M.cancelShipping() return safely(function() return ensure():cancelShipping() end) end
function M.setPlayerName(name) return safely(function() return ensure():setPlayerName(name) end) end
function M.setDeliveryRange(km) return safely(function() return ensure():setDeliveryRange(km) end) end
-- The player car's answers to fuel.lua's commands.
function M.fuelReading(vehicleId, litres, capacity)
  return safely(function() if active then active:fuelReading(vehicleId, litres, capacity) end end)
end
function M.fuelSet(vehicleId, serial, before, after, capacity)
  return safely(function() if active then active:fuelSet(vehicleId, serial, before, after, capacity) end end)
end
function M.onVehicleSpawned() return safely(function() if active then active:vehicleSpawned() end end) end
function M.reload() return safely(function() ensure():reload() end) end
function M.uiMounted(on) return safely(function() ensure():mount(on == true) end) end
function M.getState() return safely(function() return ensure():view() end) end
function M.onClientStartMission() return M.reload() end
function M.onClientEndMission()
  return safely(function() if active then active:endMission() end end)
end
function M.onFilesChanged(files)
  return safely(function()
    if not active then return end
    for _, f in pairs(type(files) == 'table' and files or {}) do
      if type(f) == 'table' and type(f.filename) == 'string' and f.filename:lower() == config.FILE:lower() then
        active:reload(); return
      end
    end
  end)
end
function M.onExtensionUnloaded() active = nil end -- no implicit save on shutdown

return M
