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
-- Delivered, given up or dropped, the Raiders go and their cars are deleted. Pure Lua: the cars are handled by
-- c.raiderCar (raiderCar.lua), which may be missing, and then there are no Raiders.
local special = require('earthFreight/special')
local raiderPack = require('earthFreight/raiderPack')
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
      if self.raiders then self:endRaiders() end
      return
    end
    if load.emps == nil then load.emps = special.EMP_CHARGES end
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
    self:raiderSays(line)
    return true
  end

  -- The run is over: the Raiders go and their cars are deleted.
  function c:endRaiders()
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
      emp = self:empView() }
  end
end

return M
