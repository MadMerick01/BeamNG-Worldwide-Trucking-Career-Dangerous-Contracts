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

local MAX_INTEGER = 9007199254740991
local dollars = pricing.dollars

-- The saved home and stored cars are cleaned by persistence.lua.
M.cleanCar = persistence.storedCar

function M.attach(c)
  -- The controller keeps:
  --   self.property: the home owned, as saved, or nil
  --   self.storedCars: the cars kept there, a list of at most SPACES

  function c:storedCar() return self.storedCars and self.storedCars[1] or nil end

  -- Whether a car bill can send the old car home: a home is owned and has room.
  function c:homeSpaceFree()
    return self.property ~= nil and #(self.storedCars or {}) < M.SPACES
  end

  -- How far the player is from home, or nil.
  function c:homeDistance()
    local here = self.lastSample
    if not self.property or not here or not here.valid then return nil end
    return location.distance(here, self.property)
  end

  function c:atHome()
    local d = self:homeDistance()
    return d ~= nil and d <= M.HOME_METRES
  end

  -- What the player is worth: cash, plus what their truck is worth, plus what they paid for their base.
  function c:wealth()
    local progression = self.profile and self.profile.progression
    if not progression then return 0 end
    local truck = self.ownedParts and self.ownedParts.value
    if type(truck) ~= 'number' then
      local saved = self.profile.vehicle
      truck = type(saved) == 'table' and (saved.worth or saved.value) or 0
    end
    return progression.balance + math.max(0, truck) + (self.property and self.property.paid or 0)
  end

  -- The town a base's circle is around, from the places near its spot: { latitude, longitude, name,
  -- boost }, or nil until a place there is loaded. A base bought before the Magnate update gets it here.
  local function baseTown(self)
    local p = self.property
    if p.town then return p.town end
    local ok, found = pcall(function()
      places.ensure(p)
      return places.at(p) or (places.nearest(p, 1)[1] or {}).place
    end)
    if not ok or type(found) ~= 'table' or not location.valid(found) then return nil end
    p.town = { latitude = found.latitude, longitude = found.longitude, name = found.name, boost = places.boost(found) }
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
    return { latitude = town.latitude, longitude = town.longitude, name = town.name, boost = town.boost,
      radiusKm = magnate.radiusKm(p.peak, town.boost), peak = p.peak, mine = true }
  end

  -- The share of the region multiplier the player's base adds at a point (0 outside its circle).
  function c:baseShareAt(point)
    local circle = self:baseCircle()
    return circle and magnate.shareAt({ circle }, point) or 0
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
    if not p then return nil end
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
    local problem = busy(self)
    if problem then return problem end
    if not self:canAfford(M.PRICE) then
      return 'Not enough money. You need ' .. dollars(M.PRICE - self.profile.progression.balance) .. ' more.'
    end
    return nil
  end

  -- Buys the spot where the car is parked as the player's home.
  function c:claimHome()
    local problem = self:claimProblem()
    local here = self.lastSample
    if not problem and not (here and here.valid and location.valid(here)) then problem = 'Waiting for a valid position.' end
    if problem then
      self.homeFeedback = problem
      return false
    end
    if not self:spend(M.PRICE, 'home') then
      self.homeFeedback = 'Not enough money.'
      return false
    end
    local spot = location.copy(here)
    local ok, near = pcall(function()
      places.ensure(spot)
      local found = places.at(spot) or (places.nearest(spot, 1)[1] or {}).place
      return found and found.name or nil
    end)
    self.property = { latitude = spot.latitude, longitude = spot.longitude, paid = M.PRICE,
      name = ok and type(near) == 'string' and near ~= '' and #near <= 256 and not near:find('%c') and near or nil }
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
      fuelLitres = fuelLitres, value = used and owned.value or nil, km = used and owned.km or nil })
  end

  -- Why Swap cars cannot be pressed now, or nil.
  function c:swapProblem()
    if not self.property then return 'Buy a base first.' end
    if not self:storedCar() then return 'No car is stored at your base yet.' end
    local problem = busy(self)
    if problem then return problem end
    if self.load then return 'Deliver or abandon your job before swapping cars.' end
    if self:towDebtProblem() then return self:towDebtProblem() end
    if not self:atHome() then
      local d = self:homeDistance()
      return 'Drive to your base to swap cars' .. (d and (': it is ' .. string.format('%.1f', d / 1000) .. ' km away.') or '.')
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
    self.homeFeedback = 'Swapped. Your ' .. tostring(outgoing.name or oldModel) .. ' is stored at your base.'
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
      value = car.value or value
      known = { from = car, name = car.name or name or model, value = value, preview = preview, km = car.km,
        repair = car.damage and pricing.repairCost(car.damage, value) or 0 }
      self.homeCard = known
    end
    return { name = known.name, value = known.value, preview = known.preview, km = known.km, repair = known.repair }
  end

  -- The Home tab.
  function c:homeView(current)
    if self.state ~= 'READY' or not self.arrived or not self.profile or self.error then return nil end
    local view = { price = M.PRICE, radiusMetres = M.HOME_METRES, repairShare = math.floor(M.REPAIR_SHARE * 100 + 0.5),
      spaces = M.SPACES, feedback = self.homeFeedback }
    local p = self.property
    if not p then
      local problem = self:claimProblem()
      view.claimAllowed, view.claimProblem = problem == nil, problem
      local balance = self.profile.progression.balance
      view.short = balance < M.PRICE and M.PRICE - balance or nil
      return view
    end
    local d = current and location.distance(current, p) or nil
    view.owned = { latitude = p.latitude, longitude = p.longitude, name = p.name, paid = p.paid, distanceMetres = d,
      here = d ~= nil and d <= M.HOME_METRES }
    local owned = self.ownedParts
    view.active = owned and { name = owned.name or owned.model, value = owned.value } or nil
    view.stored = self:storedCarCard()
    local circle = self:baseCircle()
    if circle then
      local radius = math.floor(circle.radiusKm + 0.5)
      local next = radius < magnate.MAX_KM and math.min(magnate.MAX_KM, radius + 10) or nil
      view.circle = { town = circle.name, radiusKm = radius, boost = circle.boost, wealth = math.floor(self:wealth()),
        peak = circle.peak, share = magnate.OWNER_SHARE, bonus = math.floor(magnate.OWNER_SHARE * circle.boost * 10 + 0.5) / 10,
        nextKm = next, nextWealth = next and math.ceil(magnate.wealthFor(next, circle.boost) / 1000) * 1000 or nil,
        maxKm = magnate.MAX_KM, inside = current and location.distance(current, circle) <= circle.radiusKm * 1000 or false }
    end
    local problem = self:swapProblem()
    view.swapAllowed, view.swapProblem = problem == nil, view.stored and problem or nil
    return view
  end
end

return M
