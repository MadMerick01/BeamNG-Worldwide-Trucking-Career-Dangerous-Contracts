-- The Heli tab's side of the controller: hiring the Bell 407, the loads it flies and getting the
-- player back in their car. attach(c) adds these methods to a controller made by core.new; they
-- share its state. Nothing here is saved: Save waits until the player is back in their car.
-- The helicopter takes the car's place where it stands, as a new car from the vehicle selector
-- would; Back to my car brings the car back there, with its job, fuel, parts and damage, and
-- Earth teleports the helicopter back first when it is far away.
local location = require('earthFreight/location')
local pricing = require('earthFreight/pricing')
local heli = require('earthFreight/heli')
local M = {}

local dollars = pricing.dollars

local function kgText(kg) return tostring(math.floor(kg + 0.5)) .. ' kg' end

function M.attach(c)
  -- The Bell 407 config to hire, looked up once in the game's list; nil without the mod.
  function c:heliConfig()
    if self.heliFound == nil and self.garage and self.garage.configs then
      local list = self.garage:configs()
      if #list > 0 then self.heliFound = heli.findHeli(list) or false end
    end
    return self.heliFound or nil
  end

  -- What hangs under the hook, looked up once.
  function c:loadConfig()
    if self.loadFound == nil and self.garage and self.garage.configs then
      local list = self.garage:configs()
      if #list > 0 then self.loadFound = heli.findLoad(list) or false end
    end
    return self.loadFound or nil
  end

  -- Why a helicopter cannot be hired now, or nil when it can.
  function c:hireProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage or not self.aircraft then
      return 'Heli flights are unavailable right now.'
    end
    if not self:heliConfig() then return 'Install the ' .. heli.MOD_NAME .. ' mod to hire a helicopter.' end
    if self.hire then return 'You already have a helicopter.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    if self.booking then return 'Teleport to your relocation booking, or cancel it, first.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.insurancePending or self.towPending then return 'Wait for your car to reach the road first.' end
    local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
    if not self.ownedParts or not vehicle or vehicle.id ~= self.ownedParts.id then return 'Get in your own car first.' end
    if not self.odometer:stopped() then return 'Stop the car to hire a helicopter.' end
    if not self:canAfford(heli.HIRE_FEE) then
      return 'Not enough money. A hire costs ' .. dollars(heli.HIRE_FEE) .. ': you need '
        .. dollars(heli.HIRE_FEE - self.profile.progression.balance) .. ' more.'
    end
    return nil
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
      fuel = self.fuel and self.fuel.vehicleId == owned.id and self.fuel.litres or nil, flights = 0, earned = 0 }
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

  -- The coupler on the helicopter's hook took hold of the load, or let it go.
  function c:couplerChanged(a, b, attached)
    local h = self.hire
    local load = h and h.load
    if not load or (a ~= load.id and b ~= load.id) then return end
    load.hooked = attached == true
    if attached then load.lifted = true end
  end

  -- The load's answer: what it weighs now its mass is set. Its pay goes by that weight.
  function c:loadMass(id, kg)
    local load = self.hire and self.hire.load
    if not load or load.id ~= id or not location.finite(kg) or kg <= 0 then return end
    load.kg = math.floor(kg + 0.5)
    load.pay = heli.pay(load.kg, load.km)
  end

  local function pick(self)
    return function(n) return math.max(1, math.min(n, math.floor(self.random() * n) + 1)) end
  end

  -- Puts the next load down in front of the helicopter, with a drop-off picked from where it is.
  function c:newLoad()
    local h, sample = self.hire, self.lastSample
    local config = self:loadConfig()
    if not config then
      h.nextLoadAt = self.clock + 30
      self.heliFeedback = 'The game has nothing to hang under the hook. Free flying only.'
      return
    end
    if not sample or not sample.valid then return end
    local flight = heli.flight(sample, pick(self), h.lastTo)
    local id, why, detail = self.aircraft:spawnLoad(config.model, config.config, heli.LOAD_AHEAD)
    if not id then
      h.nextLoadAt = self.clock + heli.NEXT_LOAD_SECONDS
      self.diag:event('heli_load_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'W')
      return
    end
    h.load = { id = id, kg = flight.kg, km = flight.km, pay = flight.pay, to = flight.to, at = self.clock }
    h.nextLoadAt = nil
    local ok, massWhy = self.aircraft:setMass(id, flight.kg)
    if not ok then self.diag:event('heli_mass_failed', tostring(massWhy), 'W') end
    self.diag:event('heli_load', string.format('%d kg to %s, %.1f km, %d', flight.kg, flight.to.name, flight.km, flight.pay))
  end

  local function dropLoad(self, wait)
    local h = self.hire
    if h.load then
      local ok, why = self.aircraft:remove(h.load.id)
      if not ok then self.diag:event('heli_remove_failed', tostring(why), 'W') end
    end
    h.load = nil
    h.nextLoadAt = wait and self.clock + heli.NEXT_LOAD_SECONDS or nil
  end

  -- Where the load is on Earth: the helicopter's position, moved by the load's offset from it in
  -- the world (x east, y north).
  local function loadPoint(self, pos)
    local sample, here = self.lastSample, self.aircraft:where()
    if not sample or not sample.valid or not here then return nil end
    local dx, dy = pos.x - here.x, pos.y - here.y
    local metres = math.sqrt(dx * dx + dy * dy)
    if metres < 0.01 then return location.copy(sample) end
    return location.destination(sample, (math.deg(math.atan2(dx, dy)) + 360) % 360, metres)
  end

  -- Called every tick while flying: follows the load to its drop-off, pays it once it is set down
  -- there and let go, and puts out the next one.
  function c:watchLoad()
    local h = self.hire
    local load = h.load
    if not load then
      if h.nextLoadAt and self.clock >= h.nextLoadAt then self:newLoad() end
      return
    end
    local pos = self.aircraft:where(load.id)
    if not pos then
      dropLoad(self, true)
      self:showFlash('cancelled', 'LOAD GONE', 'Your load disappeared. A new one is waiting in front of you.')
      return
    end
    local damage = self.aircraft:damage(load.id)
    if damage and damage >= heli.SMASH_DAMAGE then
      self.diag:event('heli_load_smashed', string.format('%.0f', damage))
      dropLoad(self, true)
      self:showFlash('cancelled', 'LOAD LOST', 'It hit the ground too hard, so it pays nothing. A new one is waiting in front of you.')
      return
    end
    local point = loadPoint(self, pos)
    load.point = point
    if point and not load.pickup then load.pickup = location.copy(point) end
    if point and load.pickup and (location.distance(load.pickup, point) or 0) >= heli.FLOWN_METRES then load.flown = true end
    -- Resting: let go of, and moved less than REST_METRES since rest.at.
    local rest = load.rest
    if not rest or load.hooked or math.abs(pos.x - rest.x) + math.abs(pos.y - rest.y) + math.abs(pos.z - rest.z) > heli.REST_METRES then
      load.rest = { x = pos.x, y = pos.y, z = pos.z, at = self.clock }
    end
    local away = point and location.distance(point, load.to)
    load.inZone = away ~= nil and away <= heli.DROP_RADIUS
    local height = self.aircraft:height(load.id)
    load.resting = self.clock - load.rest.at >= heli.REST_SECONDS and (height == nil or height <= heli.GROUND_METRES)
    if load.inZone and load.flown and load.resting and not load.hooked then self:deliverLoad() end
  end

  function c:deliverLoad()
    local h = self.hire
    local load = h.load
    self:addMoney(load.pay)
    h.flights, h.earned, h.lastTo = h.flights + 1, h.earned + load.pay, load.to.id
    dropLoad(self, true)
    self:showFlash('delivered', 'DELIVERED: +' .. dollars(load.pay), kgText(load.kg) .. ' flown to ' .. load.to.name .. '. '
      .. self:named('Nice flying') .. '. A new load is waiting in front of you. Save in your car to keep the money.')
    self.diag:event('heli_delivered', string.format('%d kg to %s for %d', load.kg, load.to.name, load.pay))
  end

  -- A crash ends the hire: it costs the crash fee (or all the money, if less), the load is lost,
  -- and the player is put back in their car.
  function c:heliCrashed()
    local h = self.hire
    h.crashed = true
    local fee = math.min(heli.CRASH_FEE, self.profile.progression.balance)
    if fee > 0 then self:spend(fee, 'heli_crash') end
    local lost = h.load and ' Your load is lost.' or ''
    dropLoad(self, false)
    self.diag:event('heli_crashed', tostring(fee))
    self:showFlash('cancelled', 'HELICOPTER CRASHED', 'The insurance cost ' .. dollars(fee) .. ' and your hire is over.'
      .. lost .. ' Taking you back to your car.')
    self:backToCar(true)
  end

  -- Back to my car: the first press asks to confirm. Near the car, landed, the car takes the
  -- helicopter's place; farther away, Earth teleports the helicopter back first. forced is a crash,
  -- which goes back without asking and, with no teleport, swaps where the helicopter lies.
  function c:backToCar(forced)
    local h = self.hire
    if not h or h.stage == 'spawning' or h.stage == 'swapping' then return false end
    if h.stage == 'teleporting' and not forced then
      self.heliFeedback = 'Teleporting back to your car. The terrain takes a few seconds to load.'
      return false
    end
    if not forced and not self.backArmed then
      self.backArmed = true
      self.heliFeedback = 'Press Confirm: the helicopter goes back and your hire ends.'
        .. (h.load and ' The load you have now is left behind, unpaid.' or '') .. ' Hiring again costs ' .. dollars(heli.HIRE_FEE) .. '.'
      return false
    end
    self.backArmed = false
    local sample = self.lastSample
    local away = sample and sample.valid and location.distance(sample, h.spot)
    if away and away <= heli.RETURN_METRES then
      local height = self.aircraft:height()
      if not forced and height and height > heli.LANDED_METRES then
        self.heliFeedback = 'Land first: your car comes back where the helicopter stands.'
        return false
      end
      dropLoad(self, false)
      return self:swapBack()
    end
    if self.adapter.teleport then
      local ok, why, detail = self.adapter:teleport(h.spot, 'Worldwide Trucking: your car')
      self.diag:event('heli_teleport', ok and 'requested' or (tostring(why) .. ':' .. tostring(detail or '')), ok and 'I' or 'W')
      if ok then
        dropLoad(self, false)
        h.stage, h.teleportAt, h.arrivedAt = 'teleporting', self.clock, nil
        self.heliFeedback = 'Teleporting back to your car. The terrain takes a few seconds to load.'
        return true
      end
    end
    if forced then
      dropLoad(self, false)
      return self:swapBack()
    end
    self.heliFeedback = 'Fly back to your car' .. (away and (', ' .. string.format('%.1f', away / 1000) .. ' km '
      .. (location.compassPoint(location.bearing(sample, h.spot)) or '')) or '') .. ', and land within '
      .. heli.RETURN_METRES .. ' m of it. Then press Back to my car again.'
    return false
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
      self.heliFeedback = 'Could not bring your car back. Press Back to my car again.'
      self.diag:event('heli_return_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.fuel = h.fuel and { vehicleId = owned.id, litres = h.fuel, restore = true } or nil
    self.owedDamage, self.punctureDamage, self.lastDamage, self.quote = h.carDamage or 0, 0, nil, nil
    h.stage, h.swapAt = 'swapping', self.clock
    self.heliFeedback = nil
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
      if model and model ~= h.carModel then
        h.stage, h.heliId, h.nextLoadAt = 'flying', vehicle.id, self.clock + heli.NEXT_LOAD_SECONDS
        self:showFlash('delivered', 'HELICOPTER HIRED', 'A load turns up in front of you in a moment: hook it on and fly it'
          .. ' to the drop-off on the Heli tab. Press Back to my car there when you are done.')
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
      if model == h.carModel then
        self.hire = nil
        self:showFlash('delivered', 'BACK IN YOUR CAR', h.flights > 0
          and ('You flew ' .. h.flights .. (h.flights == 1 and ' load' or ' loads') .. ' and earned ' .. dollars(h.earned) .. '. Save to keep it.')
          or 'Your car is just as you left it.')
        self.diag:event('heli_returned', tostring(h.flights) .. ':' .. tostring(h.earned))
      elseif self.clock - h.swapAt >= heli.SPAWN_SECONDS then
        self.arrivingModel, self.arrivingValue, self.arrivingUsed, self.ourRespawn = nil, nil, nil, nil
        h.stage = 'flying'
        self.heliFeedback = 'Your car did not come back. Press Back to my car again.'
      end
      return
    end
    if h.stage == 'flying' and vehicle and model == h.model then
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
        self.heliFeedback = 'Not back yet? Press Back to my car again, or fly back to your car and land by it.'
      end
      return
    end
    if self.backArmed and h.stage ~= 'flying' then self.backArmed = false end
    self:watchLoad()
  end

  -- The Heli tab.
  function c:heliView(current)
    if self.state ~= 'READY' or not self.arrived or not self.profile then return nil end
    local config = self:heliConfig()
    local out = {
      fee = heli.HIRE_FEE, crashFee = heli.CRASH_FEE, payPerKg = heli.PAY_PER_KG, maxPay = heli.MAX_PAY, maxKg = heli.MAX_KG,
      fullPayKm = heli.FULL_PAY_KM, installed = config ~= nil, modName = heli.MOD_NAME, modAuthor = heli.MOD_AUTHOR,
      modPage = heli.MOD_PAGE, name = config and config.name or nil, feedback = self.heliFeedback,
    }
    local h = self.hire
    if not h then
      out.problem = self:hireProblem()
      out.hireAllowed, out.armed = out.problem == nil, self.heliArmed
      return out
    end
    local away = current and location.distance(current, h.spot)
    local heading = self.lastSample and location.finite(self.lastSample.heading) and self.lastSample.heading or self.heading
    local hired = {
      stage = h.stage, flights = h.flights, earned = h.earned, backArmed = self.backArmed, crashed = h.crashed or nil,
      backAllowed = h.stage == 'flying',
      car = { distanceMetres = away, direction = away and away > 0 and location.compassPoint(location.bearing(current, h.spot)) or nil,
        near = away ~= nil and away <= heli.RETURN_METRES, radiusMetres = heli.RETURN_METRES },
      height = h.stage == 'flying' and self.aircraft:height() or nil,
    }
    local load = h.load
    if load then
      local from = load.point or current
      local bearing = current and location.bearing(current, load.to)
      local status
      if load.inZone then status = load.hooked and 'Lower it to the ground and let go of it.' or 'Set it down and leave it still to deliver.'
      elseif load.hooked or load.flown then status = 'Fly it to ' .. load.to.name .. '.'
      else status = 'Hover over the load and hook it on, or lift it with the node grabber.' end
      hired.load = {
        kg = load.kg, pay = load.pay, to = load.to.name, region = load.to.region, km = load.km, hooked = load.hooked or nil,
        inZone = load.inZone or nil, radiusMetres = heli.DROP_RADIUS, status = status,
        distanceMetres = from and location.distance(from, load.to) or nil,
        direction = bearing and location.compassPoint(bearing) or nil,
        arrow = bearing and heading and (bearing - heading) % 360 or nil,
        loadMetres = load.point and current and location.distance(current, load.point) or nil,
        destination = location.copy(load.to),
      }
    else
      hired.waiting = h.stage == 'flying'
    end
    out.hired = hired
    return out
  end
end

return M
