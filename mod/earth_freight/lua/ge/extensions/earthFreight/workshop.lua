-- The garage side of the controller, lifted from Enduro's core: repair quotes, parts bills, buying
-- cars and giving the player their car on arrival. attach(c) adds these methods to a controller
-- made by core.new; they share its state (profile, garage, ownedParts, owedDamage and so on).
-- Like Enduro, repairs are priced by the car's game Value, and BeamNG's own parts menu and vehicle
-- selector change the car for free, with the bill shown on the HUD.
local location = require('earthFreight/location')
local persistence = require('earthFreight/persistence')
local pricing = require('earthFreight/pricing')
local cargo = require('earthFreight/cargo')
local goods = require('earthFreight/goods')
local contracts = require('earthFreight/contracts')
local beacons = require('earthFreight/beacons')
local places = require('earthFreight/places')
local usedCars = require('earthFreight/usedCars')
local M = {}

-- Driving this far from where the parts were changed, without paying, puts the paid parts back.
M.UNPAID_PARTS_DRIVE_LIMIT = 25
-- A fresh start puts the player in this car; they upgrade it from there.
M.STARTER_MODEL = 'burnside'
M.STARTER_CONFIG = 'vehicles/burnside/earth_freight_starter.pc'
-- Insurance: from this much damage (half of what BeamNG calls major) a crash is serious, and the
-- player can claim instead of paying for the repair. A claim costs INSURANCE_FEE, or all the
-- player's money if less. The car is first sent back to the road, then fixed ROAD_SECONDS later
-- where it landed; jumps in the GRACE_SECONDS after a claim are not teleports.
M.SERIOUS_DAMAGE = 15000
M.INSURANCE_FEE = 1000
M.ROAD_SECONDS, M.GRACE_SECONDS = 1.5, 10
-- Tow to road: BeamNG's "teleport to last road" for a flat fee, charged once the car has moved
-- further than TOW_MOVED_METRES; a car that has not moved in TOW_SECONDS is not charged.
M.TOW_FEE = 500
M.TOW_SECONDS, M.TOW_MOVED_METRES = 5, 0.5
-- A drop in the car's damage bigger than this, with no repair or respawn, is the game resetting it.
M.RESET_DAMAGE_DROP = 1
-- How long the HUD app has to show the parts bill box before a corner pop-up shows it instead.
M.BILL_FALLBACK_SECONDS = 1.5
-- How long a second-hand car has to spawn before its sale is dropped.
M.USED_SPAWN_SECONDS = 5

local dollars = pricing.dollars

-- What a parts bill charges for, so the same bill priced again does not pop up twice.
local function billKey(bill)
  local names = {}
  for _, part in ipairs(bill.added) do names[#names + 1] = '+' .. part.name end
  for _, part in ipairs(bill.removed) do names[#names + 1] = '-' .. part.name end
  return table.concat(names, '|') .. '=' .. bill.cost
end

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
    if self.hire then return nil, 'heli' end
    local vehicle, why = self:inspectDamage()
    if not vehicle then return nil, why end
    return vehicle, pricing.repairCost(vehicle.damage, self:carValueOf(vehicle.id))
  end

  local repairMessages = {
    unavailable = 'Repairs are unavailable right now. Check the status above.',
    heli = 'Repairs are for your own car. Press Back to my car on the Heli tab first.',
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
      self.repairFeedback = 'Pay for the new car or get your own back first.'
      return false
    end
    if self.pendingParts then
      self.repairFeedback = 'Pay for your part changes or undo them first. Their bill includes the repair.'
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

  -- Insurance. After a serious crash the player can claim instead of paying for the repair: the car
  -- is put back on the nearest road and fixed for a flat fee, but the job and its cargo are lost.
  -- The normal repair stays on offer and keeps the job.
  function c:seriousCrash()
    local d, owned = self.lastDamage, self.ownedParts
    return d ~= nil and owned ~= nil and d.id == owned.id and d.damage >= M.SERIOUS_DAMAGE
  end

  -- On a dangerous contract, or a beacon's package, a claim costs more instead.
  function c:insuranceFee()
    local fee = self.load and (self.load.contract and contracts.INSURANCE_FEE or self.load.beacon and beacons.INSURANCE_FEE) or M.INSURANCE_FEE
    return math.min(fee, self.profile and self.profile.progression.balance or 0)
  end

  function c:insuranceAllowed()
    return self.profile ~= nil and not self.error and self.garage ~= nil and self.arrived and self:seriousCrash()
      and not self.hire and not self.pendingParts and not self.pendingCar and not self.insurancePending
  end

  -- Claims: the first press asks to confirm. The car goes back to the road (BeamNG's own "teleport
  -- to last road", where the game has one), then is fixed where it lands; without it, in place.
  function c:claimInsurance()
    if not self:insuranceAllowed() then
      self.insuranceArmed = false
      self.repairFeedback = self.insurancePending and 'Your claim is going through.' or 'Insurance is only for a serious crash.'
      return false
    end
    if not self.insuranceArmed then
      self.insuranceArmed = true
      self.repairFeedback = 'Press Confirm claim: your car is fixed and put back on the road for ' .. dollars(self:insuranceFee())
        .. (self.load and ', but your job and its cargo are lost.' or '.')
      return false
    end
    self.insuranceArmed = false
    self.insuredUntil = self.clock + M.GRACE_SECONDS
    local moved, why = false, 'road_unavailable'
    if self.garage.toRoad then moved, why = self.garage:toRoad() end
    if moved then
      self.insurancePending = { at = self.clock }
      self.repairFeedback = 'Towing your car back to the road...'
      self.diag:event('insurance_claimed', 'to road')
      return true
    end
    self.diag:event('insurance_road', tostring(why), 'W')
    return self:finishInsurance()
  end

  -- Fixes the car after a claim and charges for it; the job is lost.
  function c:finishInsurance()
    self.insurancePending = nil
    self:beforeRespawn()
    local ok, why, detail = self.garage:repair()
    if not ok then
      self:respawnFailed()
      self.repairFeedback = 'The insurance repair did not go through. You have not been charged.'
      self.diag:event('insurance_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    local fee = self:insuranceFee()
    if fee > 0 then self:spend(fee, 'insurance') end
    local lost = ''
    if self.load then
      lost = ' Your job and its cargo are lost.'
      self.diag:event('job_lost', 'insurance:' .. self.load.good)
      self:finishJob()
    end
    self.quote, self.owedDamage, self.punctureDamage, self.lastDamage = nil, 0, 0, nil
    self.insuredUntil = self.clock + M.GRACE_SECONDS
    self.repairFeedback = nil
    self:showFlash('delivered', 'INSURANCE CLAIMED', 'Your car is fixed and back on the road for ' .. dollars(fee) .. '.' .. lost .. ' Save to keep it.')
    return true
  end

  -- Called every tick: fixes the car once the move to the road has had time to happen.
  function c:watchInsurance()
    if self.insurancePending and self.clock - self.insurancePending.at >= M.ROAD_SECONDS then self:finishInsurance() end
    if self.insuranceArmed and not self:insuranceAllowed() then self.insuranceArmed = false end
  end

  -- The insurance card on the HUD, after a serious crash.
  function c:insuranceView()
    if not self.insurancePending and not (self.garage and self.arrived and self:seriousCrash()) then return nil end
    local d = self.lastDamage
    return { fee = self:insuranceFee(), armed = self.insuranceArmed, pending = self.insurancePending ~= nil,
      allowed = self:insuranceAllowed(), loseJob = self.load ~= nil,
      repair = d and pricing.repairCost(d.damage, self:carValueOf(d.id)) or nil }
  end

  -- Tow to road, on the Garage tab's Repair card: the car goes back to the road it was last on
  -- for M.TOW_FEE. Towing fixes nothing: if the game resets the car on the way, watchResets keeps
  -- the damage owed, as after Insert.
  function c:towAllowed()
    return self.profile ~= nil and not self.error and self.garage ~= nil and self.arrived and not self.hire
      and not self.pendingParts and not self.pendingCar and not self.insurancePending and not self.towPending
  end

  -- The first press asks to confirm; the fee is taken once the car has moved.
  function c:towToRoad()
    if not self:towAllowed() then
      self.towArmed = false
      self.repairFeedback = self.towPending and 'Your car is being towed.'
        or ((self.pendingParts or self.pendingCar) and 'Pay for your changes or undo them first.' or 'Towing is unavailable right now.')
      return false
    end
    if not self:canAfford(M.TOW_FEE) then
      self.towArmed = false
      self.repairFeedback = 'Not enough money. A tow to the road costs ' .. dollars(M.TOW_FEE) .. '.'
      return false
    end
    if not self.towArmed then
      self.towArmed = true
      self.repairFeedback = 'Press Confirm tow: your car is put back on the road for ' .. dollars(M.TOW_FEE)
        .. '. Towing does not fix any damage.'
      return false
    end
    self.towArmed = false
    local from = self.lastSample and location.valid(self.lastSample) and location.copy(self.lastSample) or nil
    local moved, why, detail = false, 'road_unavailable', nil
    if self.garage.toRoad then moved, why, detail = self.garage:toRoad() end
    if not moved then
      self.repairFeedback = 'There is no road to tow your car to. You have not been charged.'
      self.diag:event('tow_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'W')
      return false
    end
    -- The move back to the road is a jump, but not a teleport.
    self.insuredUntil = self.clock + M.GRACE_SECONDS
    self.towPending = { at = self.clock, from = from }
    self.repairFeedback = 'Towing your car back to the road...'
    self.diag:event('tow_requested', 'to road')
    return true
  end

  -- Called every tick: charges for the tow once the car has moved, or gives up uncharged.
  function c:watchTow()
    if self.towArmed and not self:towAllowed() then self.towArmed = false end
    local pending = self.towPending
    if not pending then return end
    local here = self.lastSample
    local gap = pending.from and here and location.valid(here) and location.distance(pending.from, here) or nil
    if gap and gap > M.TOW_MOVED_METRES then
      self.towPending = nil
      self.insuredUntil = self.clock + M.GRACE_SECONDS
      self:spend(M.TOW_FEE, 'tow')
      self.repairFeedback = nil
      self.diag:event('towed', string.format('%.0f m', gap))
      self:showFlash('delivered', 'TOWED TO THE ROAD', 'Your car is back on the road for ' .. dollars(M.TOW_FEE)
        .. '. Towing does not fix damage: repair it on the Garage tab. Save to keep the new balance.')
    elseif self.clock - pending.at >= M.TOW_SECONDS then
      self.towPending = nil
      self.repairFeedback = 'The game could not find a road to tow your car to. You have not been charged.'
      self.diag:event('tow_failed', 'not_moved', 'W')
    end
  end

  -- The Tow to road button on the Repair card.
  function c:towView()
    if not self.garage or not self.arrived then return nil end
    return { fee = M.TOW_FEE, armed = self.towArmed, pending = self.towPending ~= nil, allowed = self:towAllowed() }
  end

  -- Parts. The parts menu is BeamNG's own and changes parts for free; every change respawns the
  -- vehicle, so the HUD compares the fitted parts with the ones paid for after each spawn. The
  -- difference is billed on Pay, or the paid parts are put back on Undo. The respawn also mends
  -- all damage, so the bill includes the repair the car needed just before its first change.
  function c:vehicleSpawned()
    self.partsCheckDue, self.respawned, self.wearDue = true, true, true
    if self.secondHand then self.secondHand.spawned = true end
  end

  -- Insert, and the game's own recovery, put the car back as new without a respawn: the tank is
  -- filled and the load's weight drops off, so both are put back as after a respawn. The damage it
  -- had stays owed (see watchResets).
  function c:vehicleReset(vehicleId)
    local owned = self.ownedParts
    if not owned or vehicleId ~= owned.id then return end
    if self.fuel and self.fuel.vehicleId == owned.id then self.fuel.restore = true end
    self.appliedWeight, self.respawned = nil, true
  end

  -- Called every tick: when the car's damage drops with no repair or respawn of ours going on, the
  -- game has reset it. The car looks new, but, as after a reload, the repair it needed is still
  -- owed, so the repair bill and the insurance offer stay as they were. Relocating resets it too
  -- (Earth's teleport places the car with a reset); its damage can be unreadable while Earth loads
  -- the terrain, so the last reading is kept until it can be read again.
  function c:watchResets()
    local raw, owned = self.garage:inspect(), self.ownedParts
    if not raw and owned and not self.ourRespawn and not self.insurancePending then return end
    if not raw or not owned or raw.id ~= owned.id or self.ourRespawn or self.insurancePending then
      self.rawDamage = nil
      return
    end
    local before = self.rawDamage
    self.rawDamage = raw
    if not before or before.id ~= raw.id or before.damage - raw.damage <= M.RESET_DAMAGE_DROP then return end
    self.owedDamage = self.owedDamage + before.damage - raw.damage
    self.quote = nil
    self.diag:event('reset_owed', string.format('%.1f damage', before.damage - raw.damage))
    local owed = pricing.repairCost(self.owedDamage, owned.value)
    if owed > 0 then
      self:showFlash('cancelled', 'REPAIR STILL OWED', 'Resetting the car does not fix it for free. '
        .. dollars(owed) .. ' is still owed on the Garage tab.')
    end
  end

  -- Adopts the fitted parts as paid for, when there is nothing to charge against.
  function c:adoptParts(snapshot)
    self.ownedParts, self.pendingParts, self.pendingCar = snapshot, nil, nil
    self.diag:event('parts_owned', tostring(snapshot.model) .. ' #' .. tostring(snapshot.id))
  end

  function c:checkParts()
    local snapshot = self.garage:parts()
    if not snapshot then return false end
    -- A second-hand car is priced once it has spawned (watchParts drops one that never does).
    -- Another car picked since is billed at its own price.
    local used = self.secondHand
    if used and not used.spawned then return false
    elseif used and snapshot.model ~= used.model then
      self.secondHand, used = nil, nil
    end
    self.fittedParts = snapshot
    local owned = self.ownedParts
    self:applyWear(snapshot)
    -- The starter or saved car comes as paid for, even when it replaced a car of the same model.
    if self.arrivingModel and snapshot.model == self.arrivingModel then
      snapshot.value = snapshot.value or self.arrivingValue
      -- A second-hand car is worth what was paid for it, not the price of a new one.
      local arriving = self.arrivingUsed
      if arriving then snapshot.value, snapshot.used, snapshot.km = arriving.value, true, arriving.km end
      self.arrivingModel, self.arrivingValue, self.arrivingUsed = nil, nil, nil
      self:adoptParts(snapshot)
      return true
    end
    if not self.profile or self.error or not owned then
      self:adoptParts(snapshot)
      return true
    end
    -- A different vehicle, or a different model in place of this one, is a car the player is buying.
    if used or owned.id ~= snapshot.id or owned.model ~= snapshot.model then return self:quoteCar(snapshot) end
    -- Part changes keep a second-hand car's value and kilometres.
    if owned.used then snapshot.value, snapshot.used, snapshot.km = owned.value, true, owned.km end
    if self.pendingCar then
      self.pendingCar = nil
      self.carFeedback = 'Back in your own car. Nothing to pay.'
    end
    local diff = pricing.partsDiff(owned, snapshot)
    if not diff then
      if self.pendingParts then
        self.partsFeedback = 'Part changes undone. Nothing to pay.'
        -- Undone in the parts menu, where the HUD is hidden; Undo on the HUD says so itself.
        if not self.ourRespawn then self:toast('info', 'Parts bill', 'Part changes undone. Nothing to pay.') end
        -- Undoing them in the parts menu respawned the car again: the bill's repair is still owed.
        local pending = self.pendingParts
        if not self.ourRespawn then
          self.owedDamage = (pending.damage or 0) + math.max(0, self.owedDamage - (pending.owedBefore or self.owedDamage))
          self.punctureDamage = 0
        end
      elseif self.respawned and not self.ourRespawn then
        -- The game reloaded the car with the same parts, which mends it: its repair is still owed.
        local d = self.lastDamage
        if d and d.id == snapshot.id then self.owedDamage, self.punctureDamage = d.damage, 0 end
      end
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
      -- What was owed when the bill opened, which its repair covers; a reset since adds to it.
      owedBefore = previous and previous.owedBefore or self.owedDamage,
    }
    self.quote = nil
    -- The bill on the HUD shows the total, what the player is short and what to press.
    self.partsFeedback = nil
    self.diag:event('parts_quote', string.format('%d parts, %d repair', diff.cost, repair))
    if not previous or billKey(previous) ~= billKey(self.pendingParts) then self:showPartsBill() end
    return true
  end

  -- The HUD is hidden while the game's parts menu is open, so each change to the bill also opens a
  -- box over the menu: the total so far, how it splits, the player's money and what they are short. It stays until
  -- the player closes it, the bill is paid or undone, or the menu closes and the HUD is back. The
  -- HUD app shows the box and says so; if it has not within BILL_FALLBACK_SECONDS, a corner pop-up
  -- shows the bill instead.
  function c:showPartsBill()
    local bill = self.pendingParts
    local balance = self.profile and self.profile.progression.balance
    local short = balance and bill.cost - balance
    short = short and short > 0 and short or nil
    self.partsBillSerial = (self.partsBillSerial or 0) + 1
    local popup = {
      open = true, serial = self.partsBillSerial,
      total = bill.cost < 0 and ('You get back ' .. dollars(-bill.cost)) or ('Parts bill so far: ' .. dollars(bill.cost)),
      detail = (bill.partsCost < 0 and ('Parts refund ' .. dollars(-bill.partsCost)) or ('Parts ' .. dollars(bill.partsCost)))
        .. ', repair ' .. dollars(bill.repair) .. '.',
      money = balance and ('You have ' .. dollars(balance) .. '.') or nil,
      short = short and ('You are ' .. dollars(short) .. ' short.') or nil,
      hint = 'You can also pay or undo on the Garage tab.',
      lines = {}, cost = bill.cost, payAllowed = self:buyPartsAllowed() and true or false,
    }
    -- The same lines as the bill on the Garage tab.
    for _, part in ipairs(bill.added) do popup.lines[#popup.lines + 1] = { label = '+ ' .. part.name, amount = dollars(part.price) } end
    for _, part in ipairs(bill.removed) do
      popup.lines[#popup.lines + 1] = { label = '- ' .. part.name .. ' (sold back)', amount = '-' .. dollars(part.refund) }
    end
    if bill.repair > 0 then popup.lines[#popup.lines + 1] = { label = 'Repair (damage before the change)', amount = dollars(bill.repair) } end
    if not popup.payAllowed and not short then popup.payWhy = 'Your job would not fit with these parts. Deliver it first, or undo the changes.' end
    self.partsBill = { serial = popup.serial, at = self.clock, popup = popup }
    if self.trigger then pcall(self.trigger, 'EarthFreightPartsBill', popup) end
  end

  -- Pay on the parts bill box. Only pays the bill the box showed; says how it went in a corner pop-up.
  function c:payPartsBill(serial)
    if not self.partsBill or self.partsBill.serial ~= serial then
      self:toast('warning', 'Parts bill', 'The bill changed. Check the new one and pay again.')
      return false
    end
    local ok = self:buyParts()
    self:toast(ok and 'success' or 'warning', 'Parts bill', self.partsFeedback or 'Could not pay. Try again on the Garage tab.')
    return ok
  end

  -- The HUD app showed the parts bill box.
  function c:partsBillShown(serial)
    if self.partsBill and self.partsBill.serial == serial then self.partsBill.shown = true end
  end

  -- Called every tick: closes the parts bill box once the bill is paid or undone, and falls back to
  -- a corner pop-up when the box did not show.
  function c:watchPartsBill()
    local open = self.partsBill
    if not open then return end
    if not self.pendingParts then
      self.partsBill = nil
      if self.trigger then pcall(self.trigger, 'EarthFreightPartsBill', { open = false }) end
    elseif not open.shown and not open.fellBack and self.clock - open.at >= M.BILL_FALLBACK_SECONDS then
      open.fellBack = true
      local p = open.popup
      self:toast(p.short and 'warning' or 'info', 'Parts bill',
        p.total .. ' (' .. p.detail:gsub('%.$', ''):lower() .. ').' .. (p.money and (' ' .. p.money) or '')
          .. (p.short and (' ' .. p.short) or '') .. ' ' .. p.hint)
    end
  end

  -- Cars. Picking a car in the game's vehicle selector, or getting into any car that is not the
  -- player's, opens a bill: the car's price, plus parts changed on it since, less the trade-in of
  -- the player's car. The swap mends the old car, so its damage is frozen into the bill.
  -- What the player's car trades in for, less the repair its damage needs: the trade-in and repair.
  function c:tradeIn(oldDamage)
    local owned = self.ownedParts
    local repair = pricing.repairCost(oldDamage, owned.value)
    return math.max(0, math.floor((owned.value or pricing.DEFAULT_CAR_PRICE) * pricing.CAR_TRADE_IN_SHARE + 0.5) - repair), repair
  end

  -- The damage the player's car has now, frozen into a car bill when it opens.
  function c:carDamageNow()
    local owned = self.ownedParts
    return (self.pendingParts and self.pendingParts.damage)
      or (self.lastDamage and self.lastDamage.id == owned.id and self.lastDamage.damage) or (self.owedDamage + self.punctureDamage)
  end

  function c:quoteCar(snapshot)
    local owned, previous = self.ownedParts, self.pendingCar
    local sameCar = previous and previous.id == snapshot.id and previous.model == snapshot.model
    local oldDamage = previous and previous.oldDamage or self:carDamageNow()
    local base = sameCar and previous.base or snapshot
    -- A second-hand car's price is the one it was offered at.
    local used = self.secondHand
    if used and not sameCar then base.value, base.name = used.price, used.name end
    local extras = pricing.partsDiff(base, snapshot)
    local price = math.floor((base.value or pricing.DEFAULT_CAR_PRICE) + 0.5)
    local tradeIn, repair = self:tradeIn(oldDamage)
    local extrasCost = extras and extras.cost or 0
    self.pendingParts, self.quote = nil, nil
    self.pendingCar = {
      id = snapshot.id, model = snapshot.model, name = base.name or snapshot.model, base = base, used = used,
      price = price, extras = extrasCost, tradeIn = tradeIn, repair = repair, oldDamage = oldDamage,
      cost = math.max(0, price + extrasCost - tradeIn), fromId = owned.id,
      position = previous and previous.position
        or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil,
    }
    -- The bill on the HUD shows the total, what the player is short and any load in the way.
    self.carFeedback = nil
    self.diag:event('car_quote', string.format('%s %d, trade-in %d', tostring(snapshot.model), self.pendingCar.cost, tradeIn))
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
      self.carFeedback = 'Deliver or abandon your job before changing cars.'
      return false
    end
    if not self:checkParts() then
      self.carFeedback = 'Could not read the car. Try again in a moment.'
      return false
    end
    if not self.pendingCar then return false end
    if self.pendingCar.cost ~= pending.cost or self.pendingCar.id ~= pending.id then
      self.carFeedback = 'The car changed, so the bill was updated. Check it and buy again.'
      return false
    end
    if not self:spend(pending.cost, 'car') then
      self.carFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    -- Later part changes are priced against what was paid for, so the car keeps its own Value. A
    -- second-hand car's value is its price, and it keeps the kilometres it came with.
    local snapshot = self.fittedParts
    snapshot.value = pending.base.value
    if pending.used then
      snapshot.used, snapshot.km = true, pending.used.km
      self.soldUsed[pending.used.id] = true
      self.secondHand = nil
    end
    self:adoptParts(snapshot)
    self.owedDamage, self.punctureDamage, self.fuel = 0, 0, nil
    self.carFeedback = 'Bought ' .. tostring(pending.name) .. ' for ' .. dollars(pending.cost) .. '. Save to keep it.'
    return true
  end

  -- Second-hand cars. Buy second hand on the Garage tab lists the cars for sale in the town the
  -- player is in, or the nearest one; each town always has the same ones. Buying one spawns it in
  -- place of the player's car, looking worn, and opens the usual car bill at its second-hand price.
  c.soldUsed = c.soldUsed or {}

  -- The town whose cars are for sale: the one the player is in, or else the nearest.
  function c:usedCarTown()
    local sample = self.lastSample
    if not sample or not sample.valid then return nil end
    return self:here() or (places.nearest(sample, 1)[1] or {}).place
  end

  -- The cars for sale in that town, worked out once per town.
  function c:usedOffers()
    local town = self:usedCarTown()
    if not town or not self.garage or not self.garage.configs then return nil end
    if not self.usedCache or self.usedCache.town ~= town.id then
      self.usedCache = { town = town.id, offers = usedCars.offers(town.id, usedCars.candidates(self.garage:configs())) }
    end
    return town, self.usedCache.offers
  end

  -- Why a second-hand car cannot be bought now, or nil when it can.
  function c:usedCarProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.ownedParts then
      return 'Second-hand cars are unavailable right now.'
    end
    if self.hire then return 'Press Back to my car on the Heli tab first.' end
    if self.load then return 'Deliver or abandon your job before changing cars.' end
    if self.pendingCar or self.pendingParts then return 'Pay for or undo the bill above first.' end
    if self.secondHand then return 'Bringing the car out...' end
    if not self.odometer:stopped() then return 'Stop the car to look at second-hand cars.' end
  end

  function c:openUsedCars(open)
    self.usedCarsOpen = open
    self.carFeedback = nil
  end

  -- The Buy second hand list for the Garage tab, while it is open.
  function c:usedCarsView()
    if not self.usedCarsOpen then return nil end
    local town, offers = self:usedOffers()
    if not town then return { problem = 'Second-hand cars are unavailable right now.', offers = {} } end
    local problem = self:usedCarProblem()
    local tradeIn = self.ownedParts and self:tradeIn(self:carDamageNow()) or 0
    local balance = self.profile and self.profile.progression.balance or 0
    local list = {}
    for slot, offer in ipairs(offers) do
      local cost = math.max(0, offer.price - tradeIn)
      local sold = self.soldUsed[offer.id] == true
      list[slot] = { slot = slot, name = offer.name, preview = offer.preview, price = offer.price, newPrice = offer.newPrice,
        share = offer.share, km = offer.km, cost = cost, sold = sold, short = cost > balance and cost - balance or nil,
        allowed = problem == nil and not sold and self:canAfford(cost) }
    end
    return { town = town.name, tradeIn = tradeIn, oldName = self.ownedParts and self.ownedParts.name or nil,
      offers = list, problem = problem }
  end

  -- Spawns the second-hand car in this slot of the list in place of the player's car. The bill
  -- for it then shows up as for any other car: Buy keeps it, Get my car back undoes it.
  function c:buyUsedCar(slot)
    local town, offers = self:usedOffers()
    local offer = town and offers[slot]
    if not offer then
      self.carFeedback = 'That car is no longer for sale here.'
      return false
    end
    local problem = self:usedCarProblem()
    if problem then
      self.carFeedback = problem
      return false
    end
    if self.soldUsed[offer.id] then
      self.carFeedback = 'You already bought that car.'
      return false
    end
    local cost = math.max(0, offer.price - self:tradeIn(self:carDamageNow()))
    if not self:canAfford(cost) then
      self.carFeedback = 'Not enough money. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    -- Set before the spawn: the game may report it before spawnConfig returns.
    self.secondHand = { id = offer.id, model = offer.model, name = offer.name, price = offer.price, newPrice = offer.newPrice,
      km = offer.km, at = self.clock }
    self.ourRespawn = true
    local ok, why, detail = self.garage:spawnConfig(offer.model, offer.config)
    if not ok then
      self.secondHand, self.ourRespawn = nil, nil
      self.carFeedback = 'Could not bring that car out. Try again in a moment.'
      self.diag:event('used_car_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.usedCarsOpen, self.carFeedback = false, nil
    self.diag:event('used_car', offer.model .. '/' .. offer.key .. ' ' .. offer.price)
    return true
  end

  -- Second-hand cars look worn. A spawn makes a car look new, so after each one the player's
  -- second-hand car, or the one being bought, gets the wear of its kilometres back.
  function c:applyWear(snapshot)
    if not self.wearDue then return end
    self.wearDue = nil
    local used, owned, arriving = self.secondHand, self.ownedParts, self.arrivingUsed
    local km
    if used and used.spawned and snapshot.model == used.model then km = used.km
    elseif arriving and self.arrivingModel == snapshot.model then km = arriving.km
    elseif owned and owned.used and owned.id == snapshot.id and owned.model == snapshot.model then km = owned.km end
    if not km or not self.garage.wear then return end
    local ok, why = self.garage:wear(km, usedCars.look(km))
    if not ok then self.diag:event('wear_failed', tostring(why), 'W') end
  end

  -- Whether Save should keep the car's second-hand value and kilometres.
  function c:savedVehicleUsed()
    return self.ownedParts ~= nil and self.ownedParts.used == true
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
    self.secondHand = nil
    if respawned then
      self.arrivingModel, self.arrivingValue = owned.model, owned.value
      self.arrivingUsed = owned.used and { value = owned.value, km = owned.km } or nil
      self:beforeRespawn()
      ok, why, detail = self.garage:spawnConfig(owned.model, owned.config)
      if not ok then
        self:respawnFailed()
        self.arrivingModel, self.arrivingValue, self.arrivingUsed = nil, nil, nil
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
    -- A hired helicopter is not a car the player is buying: the garage waits for their car.
    if not self.garage or self.hire then return end
    local used = self.secondHand
    if used and not used.spawned and self.clock - used.at >= M.USED_SPAWN_SECONDS then
      self.secondHand, self.ourRespawn = nil, nil
      self.carFeedback = 'That car did not turn up. Try again in a moment.'
    end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    local expected = self.pendingCar and self.pendingCar.id or (self.ownedParts and self.ownedParts.id)
    if vehicleId ~= nil and expected ~= nil and vehicleId ~= expected then self.partsCheckDue = true end
    if not self.ownedParts then self.partsCheckDue = true end
    if self.partsCheckDue then
      -- Damage is frozen until the check: the respawn has already reset it.
      if self:checkParts() then self.partsCheckDue, self.ourRespawn, self.rawDamage = false, nil, nil end
      return
    end
    self:watchResets()
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
      self.partsFeedback = 'The parts changed, so the bill was updated. Check it and pay again.'
      return nil
    end
    return self.pendingParts
  end

  -- Whether the load on board still fits the space these parts give.
  function c:loadFits(snapshot)
    if not self.load then return true end
    local space = cargo.capacity(snapshot)
    local good = goods.get(self.load.good)
    if good and good.kind == 'fluid' then return self.load.slots <= space.litres and self.load.kg <= space.tankKg end
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
      self.partsFeedback = 'Your job would not fit with these parts. Deliver it first, or undo the changes.'
      return false
    end
    if not self:spend(pending.cost, 'parts') then
      self.partsFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    self:adoptParts(self.fittedParts)
    -- The bill paid the repair owed when it opened; a reset since then is still owed.
    self.owedDamage, self.punctureDamage = math.max(0, self.owedDamage - (pending.owedBefore or self.owedDamage)), 0
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
    self.pendingParts, self.punctureDamage = nil, 0
    self.owedDamage = (pending.damage or 0) + math.max(0, self.owedDamage - (pending.owedBefore or self.owedDamage))
    self.partsFeedback = (droveOff and 'You drove off without paying, so the paid parts were put back.'
      or 'Changes undone: your paid parts are back.') .. (pending.repair > 0 and ' Its repair is still owed.' or '')
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
      -- A second-hand car comes back at what was paid for it, looking as worn as it was.
      if saved.value then self.arrivingUsed = { value = saved.value, km = saved.km } end
    end
    self.arrivingModel = model
    -- A car respawned from a saved config may not know its .pc file, so its price is looked up here.
    self.arrivingValue = self.garage.carValue and (self.garage:carValue(model, configFile)) or nil
    self.ourRespawn = true
    local ok, why, detail = self.garage:spawnConfig(model, config)
    if not ok then
      self.arrivingModel, self.arrivingUsed, self.ourRespawn = nil, nil, nil
      self.diag:event(label .. '_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return
    end
    self.diag:event(label, 'spawned')
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
