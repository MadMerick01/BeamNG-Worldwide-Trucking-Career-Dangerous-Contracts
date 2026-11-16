-- Your cars: the car being driven takes slot 1 and the rest are parked. A career starts with START_SLOTS
-- slots; a base, or being in a corp, gives BASE_SLOTS; and with a base or corp one more slot can be bought
-- for SLOT_PRICE (kept in the save as extraCarSlot, and counted only while there is a base or corp). Cars
-- over the limit (an older save, or after leaving a corp) are kept: they can be driven and sold, but no
-- car can be kept until there is room again. A car bill can keep the old car in a free slot instead of trading it in. Drive
-- puts a parked car out in place of the one being driven, anywhere, for SWAP_FEE (a driver brings it to
-- you), and parks the one being driven in its slot. Sell gets the trade-in price for a parked car:
-- CAR_TRADE_IN_SHARE of its worth, less the repair it needs. Each car keeps its own parts, fuel, wear
-- and the repair it owes. The saved list is self.storedCars, cleaned by persistence.lua.
local pricing = require('earthFreight/pricing')
local persistence = require('earthFreight/persistence')
local M = {}

-- The most cars a save keeps parked besides the one being driven.
M.SLOTS = persistence.PARKED_SLOTS
-- Slots, counting the one being driven: at the start, with a base or corp, and with the bought slot too.
M.START_SLOTS, M.BASE_SLOTS, M.BOUGHT_SLOTS = 2, 3, 4
-- What the extra slot costs, with a base or corp.
M.SLOT_PRICE = 200000
-- What Drive costs: a driver brings the parked car to wherever the player is.
M.SWAP_FEE = 250

local dollars = pricing.dollars

-- What a parked car sells for: its trade-in price.
function M.sale(value, repair)
  return math.max(0, math.floor((value or 0) * pricing.CAR_TRADE_IN_SHARE - (repair or 0) + 0.5))
end

function M.attach(c)
  -- The controller keeps:
  --   self.storedCars: the parked cars, a list of at most SLOTS
  --   self.carCards: each parked car's card, worked out once per car
  --   self.fleetFeedback: the last line Drive or Sell left for Your cars

  function c:parkedCars() return self.storedCars or {} end

  -- How many slots the player has, counting the car being driven.
  function c:carSlots()
    if not self:homeSpot() then return M.START_SLOTS end
    return self.extraCarSlot and M.BOUGHT_SLOTS or M.BASE_SLOTS
  end

  -- Whether a car bill can keep the old car: a slot is free.
  function c:carSlotFree()
    return 1 + #self:parkedCars() < self:carSlots()
  end

  -- How to get another slot, when every slot is taken; nil when there is no other way.
  function c:slotHint()
    if not self:homeSpot() then return 'Buy or join a base to get a 3rd slot.' end
    if not self.extraCarSlot then return 'Buy a 4th slot on Your cars for ' .. dollars(M.SLOT_PRICE) .. '.' end
    return nil
  end

  -- Why Buy a 4th slot cannot be pressed now, or nil.
  function c:buySlotProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Your cars are unavailable right now.' end
    if self.extraCarSlot then return 'You already bought it.' end
    if not self:homeSpot() then return 'Buy or join a base first.' end
    if not self:canAfford(M.SLOT_PRICE) then
      return 'Not enough money. You need ' .. dollars(M.SLOT_PRICE - self.profile.progression.balance) .. ' more.'
    end
    return nil
  end

  -- Buys the extra slot for SLOT_PRICE.
  function c:buyCarSlot()
    local problem = self:buySlotProblem()
    if problem then
      self.fleetFeedback = problem
      return false
    end
    if not self:spend(M.SLOT_PRICE, 'car_slot') then return false end
    self.extraCarSlot = true
    self.fleetFeedback = 'Bought a 4th car slot for ' .. dollars(M.SLOT_PRICE) .. '.'
    self.diag:event('car_slot_bought', tostring(M.SLOT_PRICE))
    self:autoSaveSoon('buying a car slot')
    return true
  end

  -- The car being driven as a parked car keeps it: what Save would keep of it.
  function c:activeCarRecord()
    local owned = self.ownedParts
    if not owned then return nil end
    local fuelLitres = self.fuel and self.fuel.vehicleId == owned.id and self.fuel.litres or nil
    local used = self:savedVehicleUsed()
    return persistence.storedCar({ config = self:savedVehicleConfig(), name = self:savedVehicleName(), damage = self:savedVehicleDamage(),
      fuelLitres = fuelLitres, value = used and owned.value or nil, km = used and owned.km or nil, worth = self:carWorth() })
  end

  -- A parked car's card: its name, worth, picture and the repair it owes.
  function c:parkedCard(index)
    local car = self:parkedCars()[index]
    if not car then return nil end
    self.carCards = self.carCards or setmetatable({}, { __mode = 'k' })
    local known = self.carCards[car]
    if not known then
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
      known = { name = car.name or name or model, value = value, preview = preview, km = car.km, fuelLitres = car.fuelLitres,
        repair = car.damage and value and pricing.repairCost(car.damage, value) or 0 }
      self.carCards[car] = known
    end
    return known
  end

  -- What the parked cars are worth together, for wealth.
  function c:parkedWorth()
    local sum = 0
    for i = 1, #self:parkedCars() do
      local card = self:parkedCard(i)
      sum = sum + math.max(0, card and card.value or 0)
    end
    return sum
  end

  -- Why no car can be changed now, or nil.
  local function busy(self)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage then
      return 'Your cars are unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return 'Get back in your car first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    if self.booking then return 'Teleport to your relocation booking, or cancel it, first.' end
    if self.pendingCar or self.pendingParts then return 'Pay for or undo the bill above first.' end
    if self.secondHand then return 'Bringing the car out...' end
    local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
    if not self.ownedParts or not vehicle or vehicle.id ~= self.ownedParts.id then return 'Get in your own car first.' end
    if not self.odometer:stopped() then return 'Stop the car first.' end
    return nil
  end

  -- Why Drive cannot be pressed now (for any parked car), or nil.
  function c:swapProblem()
    local problem = busy(self)
    if problem then return problem end
    if self.load then return 'Deliver or abandon your job before changing cars.' end
    if self:towDebtProblem() then return self:towDebtProblem() end
    if not self:canAfford(M.SWAP_FEE) then
      return 'Not enough money. Bringing a car to you costs ' .. dollars(M.SWAP_FEE) .. '.'
    end
    return nil
  end

  -- Puts the parked car in this slot out where the one being driven stands, for SWAP_FEE, and parks the
  -- one being driven in its slot. The parked car comes back as a saved car does on loading: with its fuel,
  -- wear and the repair it owes.
  function c:swapCars(index)
    local stored = type(index) == 'number' and self:parkedCars()[index] or nil
    local problem = not stored and 'That slot is empty.' or self:swapProblem()
    if problem then
      self.fleetFeedback = problem
      return false
    end
    local outgoing = self:activeCarRecord()
    if not outgoing then
      self.fleetFeedback = 'Your car could not be parked. Try again in a moment.'
      self.diag:event('swap_failed', 'unsaved_config', 'W')
      return false
    end
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
      self.fleetFeedback = 'Could not bring your parked car out. Try again in a moment.'
      self.diag:event('swap_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self:spend(M.SWAP_FEE, 'car_swap')
    -- A Mayday Rescue run is one car, even one of the same model.
    self:endMaydayRun('car')
    self.storedCars[index] = outgoing
    -- The parked car owes the repair it was parked with; nothing the other car needed carries over.
    self.owedDamage, self.punctureDamage = stored.damage or 0, 0
    self.lastDamage, self.rawDamage, self.quote, self.repairFeedback = nil, nil, nil, nil
    -- Each photo is of one car: both are taken again as the car stands still.
    if self.garage.removePhoto then
      self.garage:removePhoto(oldModel)
      if model ~= oldModel then self.garage:removePhoto(model) end
    end
    self.photoModel, self.photoStamp = nil, nil
    self:photoSoon()
    self.fleetFeedback = 'Your ' .. tostring(stored.name or name or model) .. ' was brought to you for ' .. dollars(M.SWAP_FEE)
      .. '. Your ' .. tostring(outgoing.name or oldModel) .. ' is parked in slot ' .. tostring(index + 1) .. '.'
    self.diag:event('cars_swapped', tostring(oldModel) .. ' -> ' .. tostring(model))
    self:autoSaveSoon('changing cars')
    return true
  end

  -- Why Sell cannot be pressed now, or nil.
  function c:sellCarProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Your cars are unavailable right now.' end
    if self.pendingCar then return 'Pay for or undo the car bill first.' end
    return nil
  end

  -- Sells the parked car in this slot for its trade-in price.
  function c:sellParkedCar(index)
    local cars = self:parkedCars()
    local card = type(index) == 'number' and cars[index] and self:parkedCard(index) or nil
    local problem = not card and 'That slot is empty.' or self:sellCarProblem()
    if problem then
      self.fleetFeedback = problem
      return false
    end
    local pay = M.sale(card.value, card.repair)
    table.remove(self.storedCars, index)
    if pay > 0 then self:addMoney(pay) end
    self.fleetFeedback = 'Sold your ' .. tostring(card.name) .. ' for ' .. dollars(pay) .. '.'
    self.diag:event('parked_car_sold', tostring(card.name) .. ':' .. tostring(pay))
    self:autoSaveSoon('selling a car')
    return true
  end

  -- Your cars on the Garage tab.
  function c:fleetView()
    if self.state ~= 'READY' or not self.arrived or not self.profile or self.error then return nil end
    local owned = self.ownedParts
    local swap = self:swapProblem()
    local sellProblem = self:sellCarProblem()
    local parked, worth = {}, 0
    for i = 1, #self:parkedCars() do
      local card = self:parkedCard(i)
      worth = worth + math.max(0, card.value or 0)
      parked[i] = { index = i, slot = i + 1, name = card.name, value = card.value, preview = card.preview, km = card.km,
        fuelLitres = card.fuelLitres and math.floor(card.fuelLitres + 0.5) or nil, repair = card.repair > 0 and card.repair or nil,
        sale = M.sale(card.value, card.repair), driveAllowed = swap == nil, sellAllowed = sellProblem == nil }
    end
    local driving = owned and { name = owned.name or owned.model, value = self:carWorth() } or nil
    if driving and type(driving.value) == 'number' then worth = worth + driving.value end
    local slots, used = self:carSlots(), (driving and 1 or 0) + #parked
    local buy = nil
    if self:homeSpot() and not self.extraCarSlot then
      local problem = self:buySlotProblem()
      buy = { price = M.SLOT_PRICE, allowed = problem == nil or nil, problem = problem }
    end
    return { slots = slots, used = used, over = used > slots and used - slots or nil, fee = M.SWAP_FEE,
      buySlot = buy, hint = not self:homeSpot() and 'Buy or join a base to get a 3rd slot.' or nil,
      baseSlots = M.BASE_SLOTS, boughtSlots = M.BOUGHT_SLOTS, slotPrice = M.SLOT_PRICE,
      sharePercent = math.floor(pricing.CAR_TRADE_IN_SHARE * 100 + 0.5), driving = driving, parked = parked, worth = worth,
      swapProblem = #parked > 0 and swap or nil, feedback = self.fleetFeedback }
  end
end

return M
