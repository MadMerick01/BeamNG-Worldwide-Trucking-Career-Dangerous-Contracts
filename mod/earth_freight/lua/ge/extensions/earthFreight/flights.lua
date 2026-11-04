-- The Heli tab's side of the controller: hiring the Bell 407 to see the world, the signal beacons
-- picked up from it, and getting the player back in their car. attach(c) adds these methods to a
-- controller made by core.new; they share its state. Nothing about a hire is saved: Save waits
-- until the player is back in their car. A beacon found is kept like money, by the next Save.
-- The helicopter takes the car's place where it stands, as a new car from the vehicle selector
-- would; Back to my car brings the car back there, with its job, fuel, parts and damage, and
-- Earth teleports the helicopter back first when it is far away.
local location = require('earthFreight/location')
local pricing = require('earthFreight/pricing')
local heli = require('earthFreight/heli')
local beacons = require('earthFreight/beacons')
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local M = {}

local dollars = pricing.dollars
-- Sightseeing: a free Moonhawk takes the car's place, the same way a hired helicopter does, and
-- Return to your job brings the car back. It is a hire with sightseeing = true: no fee, no
-- beacons and no crash bill. The game is saved first, so nothing can be lost while away.
M.SIGHTSEEING = { model = 'moonhawk', key = 'earth_freight_sightseeing',
  config = 'vehicles/moonhawk/earth_freight_sightseeing.pc', name = 'Moonhawk Sightseeing' }

function M.attach(c)
  -- The Bell 407 config to hire, looked up once in the game's list; nil without the mod.
  function c:heliConfig()
    if self.heliFound == nil and self.garage and self.garage.configs then
      local list = self.garage:configs()
      if #list > 0 then self.heliFound = heli.findHeli(list) or false end
    end
    return self.heliFound or nil
  end

  -- Why a helicopter cannot be hired now, or nil when it can.
  function c:hireProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage or not self.aircraft then
      return 'Heli flights are unavailable right now.'
    end
    if not self:heliConfig() then return 'Install the ' .. heli.MOD_NAME .. ' mod to hire a helicopter.' end
    if self.hire then return self.hire.sightseeing and 'Return to your job first.' or 'You already have a helicopter.' end
    local problem = self:leaveCarProblem('hire a helicopter')
    if problem then return problem end
    if not self:canAfford(heli.HIRE_FEE) then
      return 'Not enough money. A hire costs ' .. dollars(heli.HIRE_FEE) .. ': you need '
        .. dollars(heli.HIRE_FEE - self.profile.progression.balance) .. ' more.'
    end
    return nil
  end

  -- Why the player cannot leave their car for a helicopter or the sightseeing car, or nil.
  function c:leaveCarProblem(doing)
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    if self.booking then return 'Teleport to your relocation booking, or cancel it, first.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.insurancePending then return 'Wait for your car to reach the road first.' end
    if self.trailerOut then return 'Store your trailer on the Garage tab first.' end
    local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
    if not self.ownedParts or not vehicle or vehicle.id ~= self.ownedParts.id then return 'Get in your own car first.' end
    if not self.odometer:stopped() then return 'Stop the car to ' .. doing .. '.' end
    return nil
  end

  -- Why Go sightseeing is off, or nil when it is on.
  function c:sightseeingProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage then
      return 'Sightseeing is unavailable right now.'
    end
    if self.hire then return self.hire.sightseeing and 'You are already sightseeing.' or 'Press Back to my car on the Heli tab first.' end
    return self:leaveCarProblem('go sightseeing')
  end

  -- Go sightseeing: saves the game, then the Moonhawk takes the car's place where it stands. The car,
  -- its job, fuel and damage wait for Return to your job.
  function c:goSightseeing()
    local problem = self:sightseeingProblem()
    if problem then self.sightseeingFeedback = problem; return false end
    if not self:manualSave() then
      self.sightseeingFeedback = 'Could not save your game, so you have not left. ' .. tostring(self.feedback or '')
      return false
    end
    local car, owned = M.SIGHTSEEING, self.ownedParts
    self.hire = { sightseeing = true, stage = 'spawning', at = self.clock, model = car.model, name = car.name, carModel = owned.model,
      spot = location.copy(self.lastSample), carDamage = self:carDamageNow(),
      fuel = self.fuel and self.fuel.vehicleId == owned.id and self.fuel.litres or nil, airborne = 0, rolls = 0 }
    self.appliedWeight, self.tankReading, self.ourRespawn = nil, nil, true
    local ok, why, detail = self.garage:spawnConfig(car.model, car.config)
    if not ok then
      self.hire, self.ourRespawn = nil, nil
      self:applyWeight(true)
      self.sightseeingFeedback = 'Could not bring out the sightseeing car. Your game is saved; try again.'
      self.diag:event('sightseeing_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.quote, self.lastDamage, self.sightseeingFeedback = nil, nil, nil
    self.diag:event('sightseeing_started', '')
    return true
  end

  -- Return to your job: no confirming, as nothing is lost. Earth teleports the Moonhawk back to the
  -- car first when it is far away.
  function c:returnToJob()
    if not self.hire or not self.hire.sightseeing then return false end
    return self:backToCar(false)
  end

  -- What the player is told when a career button is pressed while away from their car.
  function c:awayText()
    if self.hire and self.hire.sightseeing then return 'You are sightseeing. Press Return to your job first.' end
    return 'You are flying a hired helicopter. Press Back to my car on the Heli tab first.'
  end

  -- Hire helicopter: the first press asks to confirm. The helicopter takes the car's place where it
  -- stands; the car, its job and its fuel wait for Back to my car.
  function c:hireHeli()
    local problem = self:hireProblem()
    if problem then
      self.heliArmed, self.heliFeedback = false, problem
      return false
    end
    if not self.heliArmed then
      self.heliArmed = true
      self.heliFeedback = 'Press Confirm hire: ' .. dollars(heli.HIRE_FEE) .. ' for the helicopter until you go back to your car.'
        .. ' Your car waits here' .. (self.load and ' with its job' or '') .. '.'
      return false
    end
    self.heliArmed = false
    local config, owned = self:heliConfig(), self.ownedParts
    self.hire = { stage = 'spawning', at = self.clock, model = config.model, name = config.name, carModel = owned.model,
      spot = location.copy(self.lastSample), carDamage = self:carDamageNow(),
      fuel = self.fuel and self.fuel.vehicleId == owned.id and self.fuel.litres or nil, airborne = 0, rolls = 0 }
    -- The car's weight and tank reading go with it.
    self.appliedWeight, self.tankReading, self.ourRespawn = nil, nil, true
    local ok, why, detail = self.garage:spawnConfig(config.model, config.config)
    if not ok then
      self.hire, self.ourRespawn = nil, nil
      self:applyWeight(true)
      self.heliFeedback = 'Could not bring the helicopter out. You have not been charged.'
      self.diag:event('heli_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self:spend(heli.HIRE_FEE, 'heli')
    self.quote, self.lastDamage, self.heliFeedback = nil, nil, nil
    self.diag:event('heli_hired', tostring(config.model) .. '/' .. tostring(config.key))
    return true
  end

  -- Called every tick while flying: counts the time spent at least MIN_HEIGHT up, and every
  -- FIND_SECONDS of it may pick up a beacon, unless one is waiting or on board already.
  function c:watchBeacons()
    local h = self.hire
    local dt = self.clock - (h.watchedAt or self.clock)
    h.watchedAt = self.clock
    local height = self.aircraft:height()
    if not height or height < beacons.MIN_HEIGHT then return end
    h.airborne = h.airborne + dt
    if h.airborne < (h.rolls + 1) * beacons.FIND_SECONDS then return end
    h.rolls = h.rolls + 1
    if self.beacon or (self.load and self.load.beacon) then return end
    if self.random() >= beacons.FIND_CHANCE then return end
    local found = beacons.find(self.lastSample, h.spot, self.random, self.lastBeaconLine)
    if not found then
      self.diag:event('beacon_out_of_reach', '')
      return
    end
    self.beacon, self.lastBeaconLine = found, found.line
    local text = 'You just received signal beacon coordinates for a "don\'t ask questions" job. ' .. dollars(beacons.PAY)
      .. ', no weight, no questions. Check the job board: it is on the Route tab. It goes quiet in 1 hour.'
    self:showFlash('delivered', 'SIGNAL BEACON PICKED UP', text)
    if self.trigger then pcall(self.trigger, 'EarthFreightBeacon', { title = 'SIGNAL BEACON PICKED UP', text = text }) end
    self.diag:event('beacon_found', string.format('%.5f,%.5f -> %.5f,%.5f', found.pickup.latitude, found.pickup.longitude,
      found.drop.latitude, found.drop.longitude))
  end

  -- A crash ends the hire: it costs the crash fee (or all the money, if less),
  -- and the player is put back in their car.
  function c:heliCrashed()
    local h = self.hire
    h.crashed = true
    local fee = math.min(heli.CRASH_FEE, self.profile.progression.balance)
    if fee > 0 then self:spend(fee, 'heli_crash') end
    self.diag:event('heli_crashed', tostring(fee))
    self:showFlash('cancelled', 'HELICOPTER CRASHED', 'The insurance cost ' .. dollars(fee) .. ' and your hire is over.'
      .. ' Taking you back to your car.')
    self:backToCar(true)
  end

  -- Back to my car: the first press asks to confirm. Near the car, landed, the car takes the
  -- helicopter's place; farther away, Earth teleports the helicopter back first. forced is a crash,
  -- which goes back without asking and, with no teleport, swaps where the helicopter lies.
  function c:backToCar(forced)
    local h = self.hire
    if not h or h.stage == 'spawning' or h.stage == 'swapping' then return false end
    if h.stage == 'teleporting' and not forced then
      self:awayFeedback('Teleporting back to your car. The terrain takes a few seconds to load.')
      return false
    end
    if not forced and not h.sightseeing and not self.backArmed then
      self.backArmed = true
      self.heliFeedback = 'Press Confirm: the helicopter goes back and your hire ends. Hiring again costs ' .. dollars(heli.HIRE_FEE) .. '.'
      return false
    end
    self.backArmed = false
    local sample = self.lastSample
    local away = sample and sample.valid and location.distance(sample, h.spot)
    if away and away <= heli.RETURN_METRES then
      local height = not h.sightseeing and self.aircraft and self.aircraft:height()
      if not forced and height and height > heli.LANDED_METRES then
        self.heliFeedback = 'Land first: your car comes back where the helicopter stands.'
        return false
      end
      return self:swapBack()
    end
    if self.adapter.teleport then
      local ok, why, detail = self.adapter:teleport(h.spot, 'Worldwide Trucking: your car')
      self.diag:event('heli_teleport', ok and 'requested' or (tostring(why) .. ':' .. tostring(detail or '')), ok and 'I' or 'W')
      if ok then
        h.stage, h.teleportAt, h.arrivedAt = 'teleporting', self.clock, nil
        self:awayFeedback('Teleporting back to your car. The terrain takes a few seconds to load.')
        return true
      end
    end
    if forced then return self:swapBack() end
    if h.sightseeing then
      self.sightseeingFeedback = 'BeamNG.Earth could not teleport you. Drive back to your car' .. (away and (', '
        .. string.format('%.1f', away / 1000) .. ' km ' .. (location.compassPoint(location.bearing(sample, h.spot)) or '')) or '')
        .. ', then press Return to your job again.'
      return false
    end
    self.heliFeedback = 'Fly back to your car' .. (away and (', ' .. string.format('%.1f', away / 1000) .. ' km '
      .. (location.compassPoint(location.bearing(sample, h.spot)) or '')) or '') .. ', and land within '
      .. heli.RETURN_METRES .. ' m of it. Then press Back to my car again.'
    return false
  end

  -- Feedback for the Heli tab, or for the sightseeing panel while sightseeing.
  function c:awayFeedback(text)
    if self.hire and self.hire.sightseeing then self.sightseeingFeedback = text else self.heliFeedback = text end
  end

  -- The car takes the helicopter's place, with the parts, fuel and damage it had; like a reverted
  -- car it looks new, but its repair is still owed.
  function c:swapBack()
    local h, owned = self.hire, self.ownedParts
    self.arrivingModel, self.arrivingValue = owned.model, owned.value
    self.arrivingUsed = owned.used and { value = owned.value, km = owned.km } or nil
    self.appliedWeight, self.tankReading, self.ourRespawn = nil, nil, true
    local ok, why, detail = self.garage:spawnConfig(owned.model, owned.config)
    if not ok then
      self.arrivingModel, self.arrivingValue, self.arrivingUsed, self.ourRespawn = nil, nil, nil, nil
      h.stage = 'flying'
      self:awayFeedback(h.sightseeing and 'Could not bring your car back. Press Return to your job again.'
        or 'Could not bring your car back. Press Back to my car again.')
      self.diag:event('heli_return_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.fuel = h.fuel and { vehicleId = owned.id, litres = h.fuel, restore = true } or nil
    self.owedDamage, self.punctureDamage, self.lastDamage, self.quote = h.carDamage or 0, 0, nil, nil
    h.stage, h.swapAt, h.respawned = 'swapping', self.clock, nil
    self:awayFeedback(nil)
    return true
  end

  -- Called every tick before the garage: moves a hire along. The garage leaves the helicopter
  -- alone; once the car is back, it takes the car as the player's own again.
  function c:watchHire()
    local h = self.hire
    if not h then
      self.heliArmed = self.heliArmed and self:hireProblem() == nil
      return
    end
    local sample = self.lastSample
    local vehicle = sample and sample.valid and sample.vehicle or nil
    local model = vehicle and vehicle.model
    if h.stage == 'spawning' then
      if model and (model ~= h.carModel or (h.respawned and model == h.model)) then
        h.stage, h.heliId, h.respawned = 'flying', vehicle.id, nil
        if h.sightseeing then
          self:showFlash('delivered', 'SIGHTSEEING', 'Your game is saved. Go anywhere you like: use the BeamNG.Earth map to'
            .. ' teleport, and Street View to look around. Nothing here costs money. Press Return to your job when you are done.')
          return
        end
        self:showFlash('delivered', 'HELICOPTER HIRED', 'Fly anywhere you like and scout the towns, the terrain and their'
          .. ' jobs on the Heli tab. Keep your eyes open for signal beacons. Press Back to my car there when you are done.')
      elseif self.clock - h.at >= heli.SPAWN_SECONDS and h.sightseeing then
        self.hire, self.ourRespawn = nil, nil
        self:applyWeight(true)
        self.sightseeingFeedback = 'The sightseeing car did not turn up. Your game is saved; try again.'
        self.diag:event('sightseeing_missing', '', 'W')
      elseif self.clock - h.at >= heli.SPAWN_SECONDS then
        self.hire, self.ourRespawn = nil, nil
        self:addMoney(heli.HIRE_FEE)
        self:applyWeight(true)
        self.heliFeedback = 'The helicopter did not turn up. Your ' .. dollars(heli.HIRE_FEE) .. ' is refunded.'
        self.diag:event('heli_missing', '', 'W')
      end
      return
    end
    if h.stage == 'swapping' then
      local back = model == h.carModel and (h.model ~= h.carModel or h.respawned)
      if back and h.sightseeing then
        self.hire = nil
        self:showFlash('delivered', 'BACK TO WORK', 'Your car is just as you left it, with your job, money and fuel.')
        self.diag:event('sightseeing_returned', '')
      elseif back then
        self.hire = nil
        self:showFlash('delivered', 'BACK IN YOUR CAR', 'Your car is just as you left it.'
          .. (self.beacon and ' Your beacon is on the Route tab. Save to keep it.' or ''))
        self.diag:event('heli_returned', string.format('%.0f s up', h.airborne))
      elseif self.clock - h.swapAt >= heli.SPAWN_SECONDS then
        self.arrivingModel, self.arrivingValue, self.arrivingUsed, self.ourRespawn = nil, nil, nil, nil
        h.stage = 'flying'
        self:awayFeedback(h.sightseeing and 'Your car did not come back. Press Return to your job again.'
          or 'Your car did not come back. Press Back to my car again.')
      end
      return
    end
    if h.stage == 'flying' and not h.sightseeing and vehicle and model == h.model then
      local d = self.garage:inspect()
      if d and d.id == vehicle.id and d.damage >= heli.CRASH_DAMAGE then return self:heliCrashed() end
    end
    if h.stage == 'teleporting' then
      local away = vehicle and location.distance(sample, h.spot)
      if away and away <= heli.RETURN_METRES then
        h.arrivedAt = h.arrivedAt or self.clock
        if self.clock - h.arrivedAt >= heli.SETTLE_SECONDS then self:swapBack() end
      elseif self.clock - h.teleportAt >= heli.TELEPORT_SECONDS then
        h.stage = 'flying'
        self:awayFeedback(h.sightseeing and 'Not back yet? Press Return to your job again.'
          or 'Not back yet? Press Back to my car again, or fly back to your car and land by it.')
      end
      return
    end
    if self.backArmed and h.stage ~= 'flying' then self.backArmed = false end
    if h.stage == 'flying' and not h.sightseeing then self:watchBeacons() end
  end

  -- The sightseeing button and, while sightseeing, the HUD's sightseeing panel.
  function c:sightseeingView(current)
    if self.state ~= 'READY' or not self.arrived or not self.profile or not self.garage then return nil end
    local h = self.hire
    if not h or not h.sightseeing then
      local problem = self:sightseeingProblem()
      -- A helicopter has its own way back.
      if self.hire then return nil end
      return { allowed = problem == nil, problem = problem, feedback = self.sightseeingFeedback }
    end
    local away = current and location.distance(current, h.spot)
    return { on = true, stage = h.stage, returnAllowed = h.stage == 'flying', feedback = self.sightseeingFeedback,
      car = { distanceMetres = away, direction = away and away > 0 and location.compassPoint(location.bearing(current, h.spot)) or nil } }
  end

  -- The Heli tab.
  function c:heliView(current)
    if self.state ~= 'READY' or not self.arrived or not self.profile then return nil end
    local config = self:heliConfig()
    local out = {
      fee = heli.HIRE_FEE, crashFee = heli.CRASH_FEE, installed = config ~= nil, modName = heli.MOD_NAME, modAuthor = heli.MOD_AUTHOR,
      modPage = heli.MOD_PAGE, name = config and config.name or nil, feedback = self.heliFeedback,
      beaconPay = beacons.PAY, beaconMinutes = beacons.FIND_SECONDS / 60, beaconChance = beacons.FIND_CHANCE * 100,
      beaconHeight = beacons.MIN_HEIGHT, beaconKm = beacons.CAR_METRES / 1000,
    }
    local h = self.hire
    if not h or h.sightseeing then
      out.problem = self:hireProblem()
      out.hireAllowed, out.armed = out.problem == nil, self.heliArmed
      return out
    end
    local away = current and location.distance(current, h.spot)
    local heading = self.lastSample and location.finite(self.lastSample.heading) and self.lastSample.heading or self.heading
    local bearing = away and away > 0 and location.bearing(current, h.spot) or nil
    local hired = {
      stage = h.stage, backArmed = self.backArmed, crashed = h.crashed or nil, backAllowed = h.stage == 'flying',
      car = { distanceMetres = away, direction = bearing and location.compassPoint(bearing) or nil,
        arrow = bearing and heading and (bearing - heading) % 360 or nil,
        near = away ~= nil and away <= heli.RETURN_METRES, radiusMetres = heli.RETURN_METRES },
      height = h.stage == 'flying' and self.aircraft:height() or nil,
      -- Every FIND_SECONDS up high may bring a beacon: how long until the next chance.
      nextChanceSeconds = math.max(0, (h.rolls + 1) * beacons.FIND_SECONDS - h.airborne),
      towns = {},
    }
    if current and h.stage == 'flying' then
      local list = places.nearest(current, heli.TOWNS)
      for _, n in ipairs(list) do
        hired.towns[#hired.towns + 1] = { name = n.place.name, size = n.place.size, distanceMetres = n.metres,
          direction = n.metres > 0 and location.compassPoint(location.bearing(current, n.place)) or nil }
      end
      local nearest = list[1] and list[1].place
      if nearest then
        hired.here = { name = nearest.name, region = nearest.region, boost = jobs.roadBonusFor(places.boost(nearest)),
          distanceMetres = list[1].metres }
        -- Its job board, as it would pay the car: to plan the next run. Nothing can be taken from the air.
        hired.board = self:boardView(nearest, false)
      end
    end
    out.hired = hired
    return out
  end
end

return M
