-- The garage side of the controller, lifted from Enduro's core: repair quotes, parts bills, buying
-- cars and giving the player their car on arrival. attach(c) adds these methods to a controller
-- made by core.new; they share its state (profile, garage, ownedParts, owedDamage and so on).
-- Like Enduro, repairs are priced by the car's game Value, and BeamNG's own parts menu and vehicle
-- selector change the car for free, with the bill shown on the HUD.
local location = require('earthFreight/location')
local persistence = require('earthFreight/persistence')
local pricing = require('earthFreight/pricing')
local cargo = require('earthFreight/cargo')
local M = {}

-- Driving this far from where the parts were changed, without paying, puts the paid parts back.
M.UNPAID_PARTS_DRIVE_LIMIT = 25
-- A fresh start puts the player in this car; they upgrade it from there.
M.STARTER_MODEL = 'burnside'
M.STARTER_CONFIG = 'vehicles/burnside/earth_freight_starter.pc'

local dollars = pricing.dollars

function M.attach(c)
  function c:inspectDamage()
    local vehicle, why = self.garage:inspect()
    if not vehicle then return nil, why end
    return { id = vehicle.id, damage = vehicle.damage + self.owedDamage + self.punctureDamage }
  end

  -- The game Value of the player's own car, when vehicleId is that car; repairs are priced from it.
  function c:carValueOf(vehicleId)
    local owned = self.ownedParts
    if owned and vehicleId ~= nil and owned.id == vehicleId then return owned.value end
  end

  -- Reads the player vehicle's damage now and prices it. Returns the inspection and cost, or nil and a reason.
  function c:priceRepair()
    if not self.profile or self.error then return nil, 'unavailable' end
    if not self.garage then return nil, 'repair_unavailable' end
    local vehicle, why = self:inspectDamage()
    if not vehicle then return nil, why end
    return vehicle, pricing.repairCost(vehicle.damage, self:carValueOf(vehicle.id))
  end

  local repairMessages = {
    unavailable = 'Repairs are unavailable right now. Check the status above.',
    vehicle_required = 'Enter a vehicle to get a repair quote.',
  }
  local function repairProblem(why)
    return repairMessages[why] or 'Could not read the vehicle damage. Try again in a moment.'
  end

  function c:requestRepairQuote()
    local vehicle, cost = self:priceRepair()
    if not vehicle then
      self.quote, self.repairFeedback = nil, repairProblem(cost)
      self.diag:event('repair_quote_failed', tostring(cost), 'W')
      return false
    end
    self.diag:event('repair_quote', string.format('%.1f damage, %d', vehicle.damage, cost))
    if cost == 0 then
      self.quote, self.repairFeedback = nil, 'No damage to repair.'
      return true
    end
    self.quote = { vehicleId = vehicle.id, cost = cost }
    self.repairFeedback = self:canAfford(cost) and 'Press Repair to fix every damaged part.'
      or ('Not enough money yet. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.')
    return true
  end

  -- Charges the quoted price and repairs. A changed vehicle or new damage needs a fresh quote first,
  -- and the player is only charged once the game has accepted the repair.
  function c:repairVehicle()
    if self.pendingCar then
      self.repairFeedback = 'Buy or revert the new car first.'
      return false
    end
    if self.pendingParts then
      self.repairFeedback = 'Buy or revert your part changes first. Their bill includes the repair.'
      return false
    end
    if not self.quote then
      self.repairFeedback = 'Get a repair quote first.'
      return false
    end
    local vehicle, cost = self:priceRepair()
    if not vehicle then
      self.quote, self.repairFeedback = nil, repairProblem(cost)
      self.diag:event('repair_rejected', tostring(cost), 'W')
      return false
    end
    if vehicle.id ~= self.quote.vehicleId or cost ~= self.quote.cost then
      self.quote = nil
      self:requestRepairQuote()
      if self.quote then
        self.repairFeedback = 'The damage changed, so the quote was updated. Press Repair again to accept it.'
      end
      return false
    end
    if not self:canAfford(cost) then
      self.repairFeedback = 'Not enough money. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.'
      self.diag:event('repair_rejected', 'insufficient_funds', 'W')
      return false
    end
    -- The repair respawns the car, which would fill its tank and drop the load's weight; both are
    -- put back once it has spawned.
    self:beforeRespawn()
    local ok, why, detail = self.garage:repair()
    if not ok then
      self:respawnFailed()
      self.repairFeedback = 'Repair failed. You have not been charged.'
      self.diag:event('repair_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self:spend(cost, 'repair')
    self.quote, self.owedDamage, self.punctureDamage = nil, 0, 0
    self.repairFeedback = 'Repaired for ' .. dollars(cost) .. '. Save to keep the new balance.'
    return true
  end

  -- Parts. The parts menu is BeamNG's own and changes parts for free; every change respawns the
  -- vehicle, so the HUD compares the fitted parts with the ones paid for after each spawn. The
  -- difference is billed on Buy, or the paid parts are put back on Revert. The respawn also mends
  -- all damage, so the bill includes the repair the car needed just before its first change.
  function c:vehicleSpawned()
    self.partsCheckDue, self.respawned = true, true
  end

  -- Adopts the fitted parts as paid for, when there is nothing to charge against.
  function c:adoptParts(snapshot)
    self.ownedParts, self.pendingParts, self.pendingCar = snapshot, nil, nil
    self.diag:event('parts_owned', tostring(snapshot.model) .. ' #' .. tostring(snapshot.id))
  end

  function c:checkParts()
    local snapshot = self.garage:parts()
    if not snapshot then return false end
    self.fittedParts = snapshot
    local owned = self.ownedParts
    -- The starter or saved car comes as paid for, even when it replaced a car of the same model.
    if self.arrivingModel and snapshot.model == self.arrivingModel then
      snapshot.value = snapshot.value or self.arrivingValue
      self.arrivingModel, self.arrivingValue = nil, nil
      self:adoptParts(snapshot)
      return true
    end
    if not self.profile or self.error or not owned then
      self:adoptParts(snapshot)
      return true
    end
    -- A different vehicle, or a different model in place of this one, is a car the player is buying.
    if owned.id ~= snapshot.id or owned.model ~= snapshot.model then return self:quoteCar(snapshot) end
    if self.pendingCar then
      self.pendingCar = nil
      self.carFeedback = 'Back in your own car. Nothing to pay.'
    end
    local diff = pricing.partsDiff(owned, snapshot)
    if not diff then
      if self.pendingParts then self.partsFeedback = 'Part changes undone. Nothing to pay.' end
      self.pendingParts = nil
      return true
    end
    local previous = self.pendingParts
    local damage = previous and previous.damage
      or (self.lastDamage and self.lastDamage.id == snapshot.id and self.lastDamage.damage) or (self.owedDamage + self.punctureDamage)
    local repair = pricing.repairCost(damage, self:carValueOf(snapshot.id))
    local position = previous and previous.position
      or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil
    self.pendingParts = {
      id = snapshot.id, added = diff.added, removed = diff.removed, partsCost = diff.cost,
      repair = repair, damage = damage, cost = diff.cost + repair, position = position,
    }
    self.quote = nil
    self.partsFeedback = self:canAfford(self.pendingParts.cost) and 'Press Buy to keep these parts, or Revert.'
      or ('Not enough money. You need ' .. dollars(self.pendingParts.cost - self.profile.progression.balance)
        .. ' more. Revert, or the parts go back when you drive off.')
    self.diag:event('parts_quote', string.format('%d parts, %d repair', diff.cost, repair))
    return true
  end

  -- Cars. Picking a car in the game's vehicle selector, or getting into any car that is not the
  -- player's, opens a bill: the car's price, plus parts changed on it since, less the trade-in of
  -- the player's car. The swap mends the old car, so its damage is frozen into the bill.
  function c:quoteCar(snapshot)
    local owned, previous = self.ownedParts, self.pendingCar
    local sameCar = previous and previous.id == snapshot.id and previous.model == snapshot.model
    local oldDamage = previous and previous.oldDamage
      or (self.pendingParts and self.pendingParts.damage)
      or (self.lastDamage and self.lastDamage.id == owned.id and self.lastDamage.damage) or (self.owedDamage + self.punctureDamage)
    local base = sameCar and previous.base or snapshot
    local extras = pricing.partsDiff(base, snapshot)
    local price = math.floor((base.value or pricing.DEFAULT_CAR_PRICE) + 0.5)
    local repair = pricing.repairCost(oldDamage, owned.value)
    local tradeIn = math.max(0, math.floor((owned.value or pricing.DEFAULT_CAR_PRICE) * pricing.CAR_TRADE_IN_SHARE + 0.5) - repair)
    local extrasCost = extras and extras.cost or 0
    self.pendingParts, self.quote = nil, nil
    self.pendingCar = {
      id = snapshot.id, model = snapshot.model, name = base.name or snapshot.model, base = base,
      price = price, extras = extrasCost, tradeIn = tradeIn, repair = repair, oldDamage = oldDamage,
      cost = math.max(0, price + extrasCost - tradeIn), fromId = owned.id,
      position = previous and previous.position
        or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil,
    }
    local cost = self.pendingCar.cost
    if self.load then
      self.carFeedback = 'Deliver or dump your load before changing cars. Revert, or your car comes back when you drive off.'
    else
      self.carFeedback = self:canAfford(cost) and 'Press Buy car to keep it, or Revert to get your car back.'
        or ('Not enough money. You need ' .. dollars(cost - self.profile.progression.balance)
          .. ' more. Revert, or your car comes back when you drive off.')
    end
    self.diag:event('car_quote', string.format('%s %d, trade-in %d', tostring(snapshot.model), cost, tradeIn))
    return true
  end

  function c:buyCarAllowed()
    return self.pendingCar ~= nil and not self.load and self:canAfford(self.pendingCar.cost)
  end

  function c:buyCar()
    if not self.profile or self.error then
      self.carFeedback = 'Buying cars is unavailable right now. Check the status above.'
      return false
    end
    local pending = self.pendingCar
    if not pending then
      self.carFeedback = 'No car to pay for.'
      return false
    end
    if self.load then
      self.carFeedback = 'Deliver or dump your load before changing cars.'
      return false
    end
    if not self:checkParts() then
      self.carFeedback = 'Could not read the car. Try again in a moment.'
      return false
    end
    if not self.pendingCar then return false end
    if self.pendingCar.cost ~= pending.cost or self.pendingCar.id ~= pending.id then
      self.carFeedback = 'The car changed, so the bill was updated. Press Buy car again to accept it.'
      return false
    end
    if not self:spend(pending.cost, 'car') then
      self.carFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    -- Later part changes are priced against what was paid for, so the car keeps its own Value.
    local snapshot = self.fittedParts
    snapshot.value = pending.base.value
    self:adoptParts(snapshot)
    self.owedDamage, self.punctureDamage, self.fuel = 0, 0, nil
    self.carFeedback = 'Bought ' .. tostring(pending.name) .. ' for ' .. dollars(pending.cost) .. '. Save to keep it.'
    return true
  end

  -- Puts the player back in their own car: the one they left, if it is still there, or else their
  -- car respawned in place. A respawned car looks new, but the repair it needed is still owed.
  function c:revertCar(droveOff)
    local pending, owned = self.pendingCar, self.ownedParts
    if not pending or not owned then
      self.carFeedback = 'No car to revert.'
      return false
    end
    local ok, why, detail
    local respawned = pending.id == pending.fromId
    if not respawned then
      ok = self.garage:enter(pending.fromId)
      respawned = not ok
    end
    if respawned then
      self.arrivingModel, self.arrivingValue = owned.model, owned.value
      self:beforeRespawn()
      ok, why, detail = self.garage:spawnConfig(owned.model, owned.config)
      if not ok then
        self:respawnFailed()
        self.arrivingModel, self.arrivingValue = nil, nil
        self.carFeedback = 'Could not bring your car back. Try again in a moment.'
        self.diag:event('car_revert_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
        return false
      end
      self.owedDamage, self.punctureDamage = pending.oldDamage, 0
    end
    self.pendingCar = nil
    self.carFeedback = droveOff and 'You drove off without paying, so your own car is back.' or 'Your own car is back.'
    return true
  end

  -- Called every tick: checks parts after a spawn or vehicle switch, notes the damage the vehicle has
  -- before a change, and puts the paid parts back if the player drives off without paying.
  function c:watchParts()
    if not self.garage then return end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    local expected = self.pendingCar and self.pendingCar.id or (self.ownedParts and self.ownedParts.id)
    if vehicleId ~= nil and expected ~= nil and vehicleId ~= expected then self.partsCheckDue = true end
    if not self.ownedParts then self.partsCheckDue = true end
    if self.partsCheckDue then
      -- Damage is frozen until the check: the respawn has already reset it.
      if self:checkParts() then self.partsCheckDue = false end
      return
    end
    local inspected = self:inspectDamage()
    if inspected then self.lastDamage = inspected end
    local pending = self.pendingCar or self.pendingParts
    if pending and self.lastSample and self.lastSample.valid then
      if not pending.position then pending.position = location.copy(self.lastSample)
      else
        local moved = location.distance(pending.position, self.lastSample)
        local revert = self.pendingCar and self.revertCar or self.revertParts
        -- A failed revert is retried after another stretch of driving, not every frame.
        if moved and moved > M.UNPAID_PARTS_DRIVE_LIMIT and not revert(self, true) then
          pending.position = location.copy(self.lastSample)
        end
      end
    end
  end

  -- Confirms the bill still matches what is fitted. Returns the pending change, or nil after re-quoting.
  local function currentBill(self)
    local pending = self.pendingParts
    if not pending then
      self.partsFeedback = 'No part changes to pay for.'
      return nil
    end
    local before = pending.cost
    if not self:checkParts() then
      self.partsFeedback = 'Could not read the fitted parts. Try again in a moment.'
      return nil
    end
    if not self.pendingParts then return nil end
    if self.pendingParts.cost ~= before then
      self.partsFeedback = 'The parts changed, so the bill was updated. Press Buy again to accept it.'
      return nil
    end
    return self.pendingParts
  end

  -- Whether the load on board still fits the space these parts give.
  function c:loadFits(snapshot)
    if not self.load then return true end
    local space = cargo.capacity(snapshot)
    return self.load.slots <= space.slots and self.load.kg <= space.kg
  end

  function c:buyPartsAllowed()
    return self.pendingParts ~= nil and self:canAfford(self.pendingParts.cost)
      and (not self.fittedParts or self:loadFits(self.fittedParts))
  end

  function c:buyParts()
    if not self.profile or self.error then
      self.partsFeedback = 'Buying parts is unavailable right now. Check the status above.'
      return false
    end
    local pending = currentBill(self)
    if not pending then return false end
    if not self:loadFits(self.fittedParts) then
      self.partsFeedback = 'Your load would not fit with these parts. Deliver it first, or Revert.'
      return false
    end
    if not self:spend(pending.cost, 'parts') then
      self.partsFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    self:adoptParts(self.fittedParts)
    self.owedDamage, self.punctureDamage = 0, 0
    self.partsFeedback = 'Bought for ' .. dollars(pending.cost) .. '. Save to keep the new balance.'
    return true
  end

  -- Respawns the vehicle with the paid parts. Nothing is charged: the change already mended the
  -- damage, so, as with a reverted car, the car looks new but its repair is still owed.
  function c:revertParts(droveOff)
    local pending = self.pendingParts
    if not pending or not self.ownedParts then
      self.partsFeedback = 'No part changes to revert.'
      return false
    end
    self:beforeRespawn()
    local ok, why, detail = self.garage:repair(self.ownedParts.config)
    if not ok then
      self:respawnFailed()
      self.partsFeedback = 'Could not put the paid parts back. Try again in a moment.'
      self.diag:event('parts_revert_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    -- The bill's damage already includes what was owed before the change.
    self.pendingParts, self.owedDamage, self.punctureDamage = nil, pending.damage or 0, 0
    self.partsFeedback = (droveOff and 'You drove off without paying, so the paid parts were put back.'
      or 'The paid parts were put back.') .. (pending.repair > 0 and ' Its repair is still owed.' or '')
    return true
  end

  -- Once per load, when the player reaches the resume point, their vehicle is swapped, where it
  -- stands, for the car of the last save, or the starter car on a fresh start. Like money, part
  -- changes since the last Save are undone by a reload. A save without a car config leaves the vehicle alone.
  function c:provideVehicle()
    if self.vehicleProvided or not self.garage or self.state ~= 'READY' or not self.arrived then return end
    self.vehicleProvided = true
    local model, config, label, configFile
    local saved = self.profile and self.profile.vehicle
    if self.mode == 'start' or not (saved and saved.config) then
      if self.mode ~= 'start' then return end
      model, config, label, configFile = M.STARTER_MODEL, M.STARTER_CONFIG, 'starter_car', M.STARTER_CONFIG
    else
      config = saved.config
      model, label, configFile = config.model, 'saved_car', config.partConfigFilename
      -- The saved car comes back with the fuel it was saved with.
      if saved.fuelLitres then self.fuel = { litres = saved.fuelLitres, restore = true } end
    end
    self.arrivingModel = model
    -- A car respawned from a saved config may not know its .pc file, so its price is looked up here.
    self.arrivingValue = self.garage.carValue and (self.garage:carValue(model, configFile)) or nil
    local ok, why, detail = self.garage:spawnConfig(model, config)
    if not ok then
      self.arrivingModel = nil
      self.diag:event(label .. '_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return
    end
    if why == 'already_fitted' then self.arrivingModel = nil end
    self.diag:event(label, why or 'spawned')
  end

  -- The car Save keeps: the paid-for parts, with the paint and tuning fitted now. Only the fields
  -- a respawn needs are kept; nil when the game's config cannot be stored as plain data.
  function c:savedVehicleConfig()
    local owned = self.ownedParts
    if not owned or type(owned.config) ~= 'table' then return nil end
    local source, look = owned.config, owned.config
    local fitted = self.fittedParts
    if fitted and fitted.id == owned.id and type(fitted.config) == 'table' then look = fitted.config end
    local config = persistence.plainConfig({ model = source.model or owned.model, parts = source.parts,
      partsTree = source.partsTree, partConfigFilename = source.partConfigFilename or owned.configFile, vars = look.vars, paints = look.paints, licenseName = look.licenseName })
    if not config then self.diag:event('vehicle_config_unsaved', tostring(owned.model), 'W') end
    return config
  end

  -- The damage Save keeps with the car: what it has now plus what is still owed, or, with a parts
  -- bill open, what it had before the change mended it. A restored car owes its repair.
  function c:savedVehicleDamage()
    local damage = self.owedDamage + self.punctureDamage
    if self.pendingCar then damage = self.pendingCar.oldDamage
    elseif self.pendingParts then damage = self.pendingParts.damage
    elseif self.garage and self.ownedParts then
      local inspected = self:inspectDamage()
      if inspected and inspected.id == self.ownedParts.id then damage = inspected.damage end
    end
    return damage > 0 and math.min(9007199254740991, damage) or nil
  end
end

return M
