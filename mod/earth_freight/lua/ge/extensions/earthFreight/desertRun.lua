-- The Raiders on the special delivery (special.lua), and the player's EMP against them. MadMerick's first test
-- (26 Nov): once the run has started at the start in the Rub' al Khali, the rival clans' Raiders just keep coming.
-- FIRST_SECONDS after the start the first turns up, then another every GAP_SECONDS until MAX are up (raiderPack.lua).
-- One that is down (stopped or stuck) or falls 500 m behind is replaced the same way. The load always stays whole: the
-- Raiders can only stop you, and then it is press on or Give up.
--
-- The EMP (MadMerick, 27 Nov, in place of the revolver): the player's own EMP device, the one every robber is
-- caught with (emp.lua), with special.EMP_CHARGES charges for the whole run and no more. Each press uses one, hit or
-- miss, and then it charges for emp.CHARGE_SECONDS before it can fire again. It hits the nearest Raider still up within
-- emp.RANGE metres: its engine is cut (Bolides' EMP effect when that mod is installed) and it is down. The charges
-- left are kept with the load in the save (load.emps).
--
-- The Raiders' EMP (MadMerick, 27 Nov): every Raider has one too, but only fires it at a truck doing
-- RAIDER_EMP_KMH or less, from within RAIDER_EMP_METRES, once it has been that slow for RAIDER_EMP_SECONDS. That ends the run
-- as Give up does: the load and what it cost are lost. The truck's engine dies and the HUD shows a message with a Close
-- button. The Raiders stay: those still up speed away and go once 500 m off (raiderPack's flee). Only once it is closed is the player taken back to where they took the load (raiderCaught). The game saves
-- as the message opens, with the message, so a reload shows it again.
--
-- Delivered, given up or dropped, the Raiders go and their cars are deleted. Pure Lua: the cars are handled by
-- c.raiderCar (raiderCar.lua), which may be missing, and then there are no Raiders.
local special = require('earthFreight/special')
local raiderPack = require('earthFreight/raiderPack')
local location = require('earthFreight/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- The first Raider turns up this long after the run starts, then one every GAP_SECONDS while fewer than MAX are up.
M.FIRST_SECONDS, M.GAP_SECONDS = 30, 8
-- A Raider that can't be sent is tried again after this long.
M.RETRY_SECONDS = 10
-- How often the Raiders think, in seconds (they steer every frame).
M.STEP_SECONDS = 0.5
-- How long a Raider's line stays on the HUD.
M.LINE_SECONDS = 6
-- The Raiders' EMP: fired at a truck at this speed or less, from within this far, once it has been that slow this long.
M.RAIDER_EMP_KMH, M.RAIDER_EMP_METRES, M.RAIDER_EMP_SECONDS = 15, 15, 2
-- With less than this many km left to the shed, a Raider fires at any speed (MadMerick, 27 Nov). Each Raider has one
-- EMP (h.empUsed). Fired at a truck going faster than RAIDER_EMP_KMH it doesn't end the run: like the road robber's, it
-- kills the engine for STALL_SECONDS and jams the brakes for BRAKE_SECONDS, and the player has to deal with it.
M.RAIDER_EMP_ANY_SPEED_KM = 10
M.STALL_SECONDS, M.BRAKE_SECONDS = 10, 0.5

function M.attach(c)
  -- The load of a special delivery that has started, or nil.
  function c:desertLoad()
    local load = self.load
    if load and load.cost and load.started and load.contract == special.SECTION.id then return load end
  end

  -- Called every tick.
  function c:watchRaiders(dt)
    local load = self:desertLoad()
    if not load then
      -- A Raider's EMP ended the run: the Raiders speed away, and go once far off or the message is closed.
      if self.raiders and self.raiderCaught then
        if self.clock >= (self.raiderStepAt or 0) then
          self.raiderStepAt = self.clock + M.STEP_SECONDS
          self.raiders:step(self.clock)
        end
      elseif self.raiders then
        self:endRaiders()
      end
      return
    end
    if load.emps == nil then load.emps = special.EMP_CHARGES end
    self:raiderStallTick()
    local car = self.raiderCar
    if not car then return end
    -- The truck: what the Raiders go for, even while the player walks.
    if not self.onFoot then
      local me = car:walker()
      self.raiderTruck = me and me.id or self.raiderTruck
      car.targetId = nil
    else
      car.targetId = self.raiderTruck
    end
    if not self.raiders then
      self.raiders = raiderPack.new(car, self.random and function(lo, hi) return lo + self.random() * (hi - lo) end)
      self.raiderNextAt = self.clock + M.FIRST_SECONDS
      self.raiderStepAt = self.clock
      local ready, why = car:preload(raiderPack.MAX)
      self.diag:event('raiders_loaded', ready .. ' cars' .. (why and (', ' .. why) or ''), why and 'W' or 'I')
    end
    local pack = self.raiders
    if self.clock >= self.raiderNextAt and pack:up() < raiderPack.MAX then
      local line, why = pack:add(self.clock)
      if line then
        self:raiderSays(line)
        self.raiderNextAt = self.clock + M.GAP_SECONDS
      else
        self.raiderNextAt = self.clock + M.RETRY_SECONDS
        if why ~= self.raiderWhy then
          self.raiderWhy = why
          self.diag:event('raider_not_sent', tostring(why), 'W')
        end
      end
    end
    if self.clock >= self.raiderStepAt then
      self.raiderStepAt = self.clock + M.STEP_SECONDS
      local line = pack:step(self.clock)
      if line then self:raiderSays(line) end
      if self:raiderEmpWatch(car, pack) then return end
      -- One that went down or fell behind: the next comes GAP_SECONDS later at the soonest.
      if pack:up() < raiderPack.MAX and self.raiderNextAt < self.clock then
        self.raiderNextAt = self.clock + M.GAP_SECONDS
      end
      if pack.stalled then
        local st = pack.stalled
        pack.stalled = nil
        self.diag:event('raider_stalled', string.format('Raider %d %s %s, %.0f m away', st.n, tostring(st.state),
          tostring(st.slot), st.metres or -1), 'W')
      end
    else
      pack:steer(self.clock)
    end
  end

  -- The Raiders' EMP: true once a Raider fired it and the run is over.
  function c:raiderEmpWatch(car, pack)
    local truck = car:player()
    local near = pack:nearestRaider(true)
    local slow = truck and type(truck.speed) == 'number' and truck.speed * 3.6 <= M.RAIDER_EMP_KMH
    local sample = self.lastSample
    local left = sample and sample.valid ~= false and location.distance(sample, special.FINISH)
    local closing = left ~= nil and left < M.RAIDER_EMP_ANY_SPEED_KM * 1000
    if not ((slow or closing) and near and near.metres <= M.RAIDER_EMP_METRES) then
      self.raiderSlowSince = nil
      return false
    end
    self.raiderSlowSince = self.raiderSlowSince or self.clock
    if self.clock - self.raiderSlowSince < M.RAIDER_EMP_SECONDS then return false end
    self.raiderSlowSince = nil
    near.empUsed = true
    -- The EMP sound on the HUD, and the truck shoved away from the Raider that fired.
    local function hit()
      if self.thiefCar and self.thiefCar.empPlayer then pcall(self.thiefCar.empPlayer, self.thiefCar) end
      self:empSound()
      local from = car:state(near.id)
      if truck and from and car.shove then pcall(car.shove, car, truck.id, from.x, from.y, true) end
    end
    if not slow then
      -- At speed: the engine dies for a while, and the run goes on.
      hit()
      self.raiderStall = { brakeAt = self.clock + M.BRAKE_SECONDS, endAt = self.clock + M.STALL_SECONDS }
      self.diag:event('raider_emp_stall', string.format('Raider %d at %.0f m', near.n or 0, near.metres))
      self:raiderSays('A Raider\'s EMP hit you: your engine is dead for ' .. M.STALL_SECONDS
        .. ' s. Don\'t let them catch you at ' .. M.RAIDER_EMP_KMH .. ' km/h or less.')
      return false
    end
    local load = self.load
    local back = load.back
    self.raiderStall = nil
    hit()
    self.diag:event('raider_emp', string.format('Raider %d at %.0f m', near.n or 0, near.metres))
    self:dropJob('raider_emp')
    self.raiderCaught = { cost = load.cost, back = back }
    pack:flee(self.clock)
    self:saveNowOrSoon('the dangerous contract lost to a Raider')
    return true
  end

  -- For the HUD: the message after a Raider's EMP, until it is closed.
  function c:raiderCaughtView()
    local g = self.raiderCaught
    return g and { cost = g.cost } or nil
  end

  -- Close on that message: the engine comes back and the player is taken back to where they took the load.
  function c:closeRaiderCaught()
    local g = self.raiderCaught
    if not g then return false end
    self.raiderCaught = nil
    self:endRaiders()
    if self.thiefCar and self.thiefCar.empPlayerEnd then pcall(self.thiefCar.empPlayerEnd, self.thiefCar) end
    self.tradeFeedback = 'A Raider\'s EMP ended the dangerous contract and you lost the load.'
    self:returnFromDesert(g.back)
    self:saveNowOrSoon('the dangerous contract lost to a Raider')
    return true
  end

  -- A Raider's EMP at speed: the brakes let off after BRAKE_SECONDS, the engine back after STALL_SECONDS.
  function c:raiderStallTick()
    local s = self.raiderStall
    if not s then return end
    local t = self.thiefCar
    if not s.brakesOff and self.clock >= s.brakeAt then
      s.brakesOff = true
      if t and t.empPlayerBrakeOff then pcall(t.empPlayerBrakeOff, t) end
    end
    if self.clock >= s.endAt then
      self.raiderStall = nil
      if t and t.empPlayerEnd then pcall(t.empPlayerEnd, t) end
    end
  end

  function c:raiderSays(line)
    self.raiderLine, self.raiderLineAt = line, self.clock
  end

  -- What the EMP would fire at on the run: the nearest Raider still up, as emp.lua's empTarget gives it, or nil.
  function c:raiderEmpTarget()
    if not (self.raiders and self:desertLoad()) then return nil end
    local best = self.raiders:nearestRaider()
    if not best then return nil end
    return { kind = 'raider', metres = best.metres, stoppable = true, id = best.id, charges = self.load.emps or 0 }
  end

  -- The EMP hit Raider id (emp.lua's fireEmp): its engine is cut and it is down.
  function c:empRaider(id)
    local line = self.raiders and self.raiders:emped(id)
    if not line then return false end
    if self.thiefCar and self.thiefCar.emp then pcall(self.thiefCar.emp, self.thiefCar, id) end
    -- Shoved away from the player (raiderCar.lua's shove).
    local car = self.raiderCar
    local me = car and car.walker and car:walker()
    if me and car.shove then pcall(car.shove, car, id, me.x, me.y) end
    self:raiderSays(line)
    return true
  end

  -- The run is over: the Raiders go and their cars are deleted.
  function c:endRaiders()
    if self.raiderStall then
      self.raiderStall = nil
      if self.thiefCar and self.thiefCar.empPlayerEnd then pcall(self.thiefCar.empPlayerEnd, self.thiefCar) end
    end
    if self.raiders then self.raiders:remove() end
    self.raiders, self.raiderNextAt, self.raiderStepAt, self.raiderLine, self.raiderWhy = nil, nil, nil, nil, nil
    if self.raiderCar then self.raiderCar.targetId = nil end
  end

  -- A Raider's driver had a problem (lua/vehicle/extensions/earthFreightRaider.lua): logged once each.
  function c:raiderProblem(id, why)
    self.raiderProblems = self.raiderProblems or {}
    why = tostring(why)
    if self.raiderProblems[why] then return end
    self.raiderProblems[why] = true
    self.diag:event('raider_problem', tostring(id) .. ': ' .. why, 'W')
  end

  -- For the HUD: the Raiders up, the latest line, and the EMP: its charges left and its button (emp.lua's empView).
  function c:desertView()
    local load = self:desertLoad()
    if not load then return nil end
    local line = self.raiderLine and self.clock - (self.raiderLineAt or 0) <= M.LINE_SECONDS and self.raiderLine or nil
    return { up = self.raiders and self.raiders:up() or 0, max = raiderPack.MAX, line = line,
      charges = load.emps or special.EMP_CHARGES, totalCharges = special.EMP_CHARGES,
      emp = self:empView(), noRepairs = true }
  end
end

return M
