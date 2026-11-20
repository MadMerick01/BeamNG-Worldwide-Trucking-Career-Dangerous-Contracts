-- The road robber: on a delivery, fuel run or contract of MIN_JOB_METRES or more, CHANCE of the time a robber in the
-- base thief's Moonhawk (thief.lua) ambushes the player on the road. Its car is loaded out of sight when the job is
-- taken, at the job board, so putting it on the road later doesn't stutter (thiefCar.lua). Somewhere between
-- EDGE_METRES into the job and EDGE_METRES before its end, once the ground AHEAD_METRES in front has loaded, it is
-- put on the road there, in the player's lane and facing their way, and:
--   lurking: drives in its lane a little slower than the player, so they catch up; if they hang back it slows down more
--     (brake-check). If they turn off, go off road or drop back, it hunts them.
--   hunting: the game's chase AI at the player's speed plus HUNT_EXTRA_KPH, never over HUNT_MAX_KPH.
--   Within STRIKE_METRES it strikes: its EMP cuts the player's engine for PLAYER_EMP_SECONDS (no brake lock), it takes
--     STOLEN and flees (the base thief's flee, fleeSupervisor.lua). Not struck within GIVE_UP_SECONDS, or GIVE_UP_METRES
--     behind: it gives up and goes, and nothing is lost.
--   chasing: the player's EMP (emp.lua) within its range stops it for good: STOLEN back plus TRUNK, and the car goes
--     after CAUGHT_SECONDS. ESCAPE_METRES clear, it gets away with the money. The job carries on throughout, and
--     delivering or abandoning it doesn't end the chase.
-- The player can turn robbers off with the Route tab's "Robbers can rob me" tick box (saved as noRobbers), which the
-- base thief obeys too. ROB ME on the Route tab starts one straight away for testing, ticked or not, and doesn't count
-- as the job's robbery. Never on Mayday Rescue runs, heli flights or the heli's package jobs. Pure Lua: the car is
-- handled by c.thiefCar, which may be missing. An admin on the server can drive a robber himself (adminRobber.lua):
-- self.robber then has admin = true.
local pricing = require('earthFreight/pricing')
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local thief = require('earthFreight/thief')
local emp = require('earthFreight/emp')
local M = {}

M.CHANCE = 0.5
M.MIN_JOB_METRES = 5000
M.EDGE_METRES = 2000
M.AHEAD_METRES = 300
M.STOLEN = 1000
M.TRUNK = 20000
M.STRIKE_METRES = emp.RANGE
M.PLAYER_EMP_SECONDS = 5
M.GIVE_UP_SECONDS = 240
M.GIVE_UP_METRES = 500
M.ESCAPE_METRES = 450
M.CAUGHT_SECONDS = 10
-- Lurking: this much slower than the player, never under LURK_MIN_KPH; when they hang back more than HANG_BACK_METRES,
-- BRAKE_CHECK_KPH slower instead.
M.LURK_SLOWER_KPH = 15
M.LURK_MIN_KPH = 20
M.HANG_BACK_METRES = 80
M.BRAKE_CHECK_KPH = 35
-- It starts hunting when the player drops back DROP_BACK_METRES from the closest they've been, or they point
-- TURNED_DEGREES away from its way for TURNED_SECONDS.
M.DROP_BACK_METRES = 100
M.TURNED_DEGREES = 60
M.TURNED_SECONDS = 3
M.HUNT_EXTRA_KPH = 15
M.HUNT_MAX_KPH = 130
-- How often a refused place (no ground yet) or load is tried again; a ROB ME robber that can't find ground gives up.
M.RETRY_SECONDS = 2
M.ROB_ME_TRIES = 15
M.SPEED_EVERY_SECONDS = 1
-- The car: the base thief's.
M.MODEL = thief.MODEL
M.CONFIG = thief.CONFIG

local dollars = pricing.dollars

-- Lurking speed: a little slower than the player; slower still when they hang back.
function M.lurkKph(playerKph, metres)
  local kph = math.max(0, playerKph or 0)
  if metres and metres > M.HANG_BACK_METRES then return math.max(M.LURK_MIN_KPH * 0.5, kph - M.BRAKE_CHECK_KPH) end
  return math.max(M.LURK_MIN_KPH, kph - M.LURK_SLOWER_KPH)
end

-- Hunting speed: the player's plus HUNT_EXTRA_KPH, capped.
function M.huntKph(playerKph)
  return math.min(M.HUNT_MAX_KPH, math.max(0, playerKph or 0) + M.HUNT_EXTRA_KPH)
end

-- How long the job's road is in metres, or nil.
local function jobMetres(load)
  local from, to = places.get(load.from), places.get(load.to)
  if not from or not to then return nil end
  local ok, m = pcall(jobs.drivenNeeded, from, to)
  return ok and type(m) == 'number' and m or nil
end

function M.attach(c)
  -- The controller keeps:
  --   self.robber: the road robber, or nil: { phase, carId, forced, at, placedAt, metres, turnedFor, amount, struckAt,
  --     empEndAt, caughtAt, nextTry, tries, speedAt }. phase: 'loaded' (out of sight, waiting for its moment), 'lurking',
  --     'hunting', 'chasing' (struck, fleeing), 'caught'.
  --   self.robberJob: the load the 50% roll was made for, and self.robberAtKm: the job's driven km at which it strikes
  --     (nil when this job isn't robbed).
  --   self.noRobbers: true when the player unticked "Robbers can rob me".

  -- Why a robber can't be put on the road now, or nil.
  function c:robberProblem(forced)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Get in your car first.' end
    if not self.thiefCar then return 'Robbers are not available.' end
    if self.onFoot then return 'Get back in your car first.' end
    if self.hire then return 'Not while flying.' end
    if self.thief or self:awayFromJob() then return 'A thief is already about.' end
    if self.robber and self.robber.phase ~= 'loaded' then return 'A robber is already about.' end
    if not self:canAfford(M.STOLEN) then return 'Less than ' .. dollars(M.STOLEN) .. ' in the bank.' end
    if forced then return nil end
    if self.noRobbers then return 'You chose not to be robbed.' end
    if self.maydayRun or self.booking or self.stranded then return 'Busy.' end
    return nil
  end

  -- Whether this job can be robbed: long enough, and not the heli's package.
  function c:robbableJob(load)
    if not load or load.beacon then return false end
    local m = jobMetres(load)
    return m ~= nil and m >= M.MIN_JOB_METRES, m
  end

  -- Loads the robber's car out of sight. Returns true when it did.
  function c:loadRobber(forced)
    local id = self.thiefCar:preload(M.MODEL, M.CONFIG)
    if not id then
      self.diag:event('robber_load_failed', forced and 'rob me' or 'job', 'W')
      return false
    end
    self.robber = { phase = 'loaded', carId = id, forced = forced or nil, at = self.clock, tries = 0 }
    self.diag:event('robber_loaded', tostring(id))
    return true
  end

  -- ROB ME on the Route tab: a robber on the road ahead straight away, for testing. Returns true when one is coming.
  function c:robMe()
    local problem = self:robberProblem(true)
    if problem then
      self.robberFeedback = problem
      return false
    end
    -- A job's robber already loaded is used now; the job won't get another.
    if not (self.robber and self.robber.phase == 'loaded') and not self:loadRobber(true) then
      self.robberFeedback = 'The game would not load the robber. Try again.'
      return false
    end
    self.robber.forced, self.robber.go, self.robber.nextTry = true, true, nil
    self.robberFeedback = 'A robber is coming. Keep driving.'
    self.diag:event('robber_rob_me', '')
    return true
  end

  -- The robber is gone: its car taken away. why goes in the diagnostics.
  function c:dropRobber(why)
    local r = self.robber
    if not r then return end
    -- An admin robber's car is his own (adminRobber.lua): never taken away here.
    if r.carId and self.thiefCar and not r.admin then self.thiefCar:remove(r.carId) end
    if r.empEndAt and self.thiefCar then self.thiefCar:empPlayerEnd() end
    self.robber = nil
    self.diag:event('robber_over', tostring(why))
  end

  -- The player's EMP stopped the robber (emp.lua): shut down for good, the money back plus the trunk.
  function c:catchRobber()
    local r = self.robber
    if not r or r.phase ~= 'chasing' then return false end
    -- An admin's car is shut down by his own game, told through the server.
    if r.admin then self.mp:robNews('caught') else self.thiefCar:emp(r.carId) end
    local paid = (r.amount or 0) + M.TRUNK
    self:addMoney(paid)
    r.phase, r.caughtAt = 'caught', self.clock
    self:showFlash('delivered', 'ROBBER CAUGHT: +' .. dollars(paid), 'The EMP stopped them dead. You got your '
      .. dollars(r.amount or 0) .. ' back, and ' .. dollars(M.TRUNK) .. ' from their trunk.')
    self:autoSaveSoon('catching the robber')
    self.diag:event('robber_caught', tostring(paid))
    return true
  end

  -- The robber's EMP hits the player: STOLEN taken, the engine dead for a few seconds, and it flees.
  function c:robberStrikes()
    local r = self.robber
    if not self:spend(M.STOLEN, 'robber') then
      -- Spent it since: nothing to take, so it just goes.
      self:dropRobber('nothing to take')
      return
    end
    self.thiefCar:empPlayer()
    -- The robber's EMP drains the player's too: it charges from empty before they can fire back (emp.lua).
    self.empFiredAt = self.clock
    self:empSound()
    self.thiefCar:flee(r.carId)
    r.phase, r.amount, r.struckAt, r.empEndAt = 'chasing', M.STOLEN, self.clock, self.clock + M.PLAYER_EMP_SECONDS
    local text = 'A robber hit you with an EMP and took ' .. dollars(M.STOLEN) .. '. Your engine is back in '
      .. M.PLAYER_EMP_SECONDS .. ' s and your EMP is drained: it takes ' .. emp.CHARGE_SECONDS .. ' s to charge. Catch them with your EMP within ' .. emp.RANGE .. ' m to get it back, plus '
      .. dollars(M.TRUNK) .. ' from their trunk.'
    self:showFlash('cancelled', 'ROBBED ON THE ROAD: -' .. dollars(M.STOLEN), text)
    self:toast('warning', 'Robbed on the road', text, 10)
    self:autoSaveSoon('the robbery')
    self.diag:event('robber_struck', tostring(M.STOLEN))
  end

  -- Every tick.
  function c:watchRobber(dt)
    if not self.thiefCar or not self.profile or self.error then return end
    local load = self.load
    -- A new job: the 50% roll, once. A robbed job gets its robber loaded now, at the job board.
    if load ~= self.robberJob then
      self.robberJob, self.robberAtKm = load, nil
      if self.robber and self.robber.phase == 'loaded' and not self.robber.forced then self:dropRobber('job ended') end
      local robbable, metres = self:robbableJob(load)
      if robbable and not self.noRobbers and not self.robber and self.random() < M.CHANCE then
        local span = metres - 2 * M.EDGE_METRES
        self.robberAtKm = (M.EDGE_METRES + self.random() * math.max(0, span)) / 1000
        self.diag:event('robber_planned', string.format('%.1f km', self.robberAtKm))
        self:loadRobber(false)
      end
    end
    -- This job's robber not loaded (the game refused, or ROB ME used it): loaded again while its moment is ahead.
    if not self.robber and self.robberAtKm and load and (load.drivenKm or 0) < self.robberAtKm and not self.noRobbers
      and self.clock >= (self.robberLoadAt or 0) then
      self.robberLoadAt = self.clock + M.RETRY_SECONDS * 5
      self:loadRobber(false)
    end
    local r = self.robber
    if not r then return end
    if r.admin then return self:watchAdminRobber() end
    if r.phase == 'loaded' then
      if not r.go then
        if self.noRobbers or not self.robberAtKm or not load or load ~= self.robberJob or (load.drivenKm or 0) < self.robberAtKm then return end
        r.go = true
      end
      if r.nextTry and self.clock < r.nextTry then return end
      if self:robberProblem(r.forced) then r.nextTry = self.clock + M.RETRY_SECONDS return end
      local ok, why = self.thiefCar:place(r.carId, M.AHEAD_METRES)
      if not ok then
        r.tries = (r.tries or 0) + 1
        r.nextTry = self.clock + M.RETRY_SECONDS
        if why == 'gone' or (r.forced and r.tries >= M.ROB_ME_TRIES) then
          if r.forced then self.robberFeedback = 'No road with loaded ground ahead. Try ROB ME again on a road.' end
          self:dropRobber(why)
        end
        return
      end
      local kph = self.thiefCar:playerKph() or 0
      self.thiefCar:lurk(r.carId, M.lurkKph(kph, M.AHEAD_METRES))
      r.phase, r.placedAt, r.speedAt, r.turnedFor = 'lurking', self.clock, self.clock, 0
      if r.forced then self.robberFeedback = nil else self.robberAtKm = nil end
      self.diag:event('robber_placed', tostring(r.carId))
      return
    end
    local d = self.thiefCar:distance(r.carId)
    r.metres = d
    if r.empEndAt and self.clock >= r.empEndAt then
      r.empEndAt = nil
      self.thiefCar:empPlayerEnd()
    end
    if r.phase == 'lurking' or r.phase == 'hunting' then
      if not d then self:dropRobber('gone') return end
      if d <= M.STRIKE_METRES then self:robberStrikes() return end
      if self.clock - r.placedAt > M.GIVE_UP_SECONDS or d > M.GIVE_UP_METRES then
        self:dropRobber('gave up')
        if r.forced then self:showFlash('delivered', 'THE ROBBER GAVE UP', 'You got away. Nothing was taken.') end
        return
      end
      local kph = self.thiefCar:playerKph() or 0
      if r.phase == 'lurking' then
        local gap = self.thiefCar:headingGap(r.carId)
        r.turnedFor = (gap and gap > M.TURNED_DEGREES) and (r.turnedFor or 0) + dt or 0
        r.closest = math.min(r.closest or d, d)
        if d > r.closest + M.DROP_BACK_METRES or r.turnedFor >= M.TURNED_SECONDS or self.onFoot then
          self.thiefCar:hunt(r.carId, M.huntKph(kph))
          r.phase, r.speedAt = 'hunting', self.clock
          self.diag:event('robber_hunting', string.format('%.0f m', d))
          return
        end
      end
      if self.clock - (r.speedAt or 0) >= M.SPEED_EVERY_SECONDS then
        r.speedAt = self.clock
        self.thiefCar:setSpeed(r.carId, r.phase == 'lurking' and M.lurkKph(kph, d) or M.huntKph(kph))
      end
      return
    end
    if r.phase == 'chasing' then
      r.arrow = d and self.thiefCar.bearing and self.thiefCar:bearing(r.carId) or nil
      if not d or d > M.ESCAPE_METRES then
        self:dropRobber('escaped')
        self:showFlash('cancelled', 'THE ROBBER GOT AWAY', 'They got ' .. M.ESCAPE_METRES .. ' m clear of you and escaped with your '
          .. dollars(r.amount or 0) .. '.')
      end
      return
    end
    if r.phase == 'caught' and self.clock - r.caughtAt > M.CAUGHT_SECONDS then self:dropRobber('caught') end
  end

  -- The tick box: robbers (the road robber and the base thief) can rob the player, or not. Saved with the career.
  function c:setRobbersAllowed(allowed)
    if not self.profile or self.error then return false end
    self.noRobbers = (allowed == false) or nil
    -- A robber waiting for its moment goes; one already on the road carries on.
    if self.noRobbers and self.robber and self.robber.phase == 'loaded' and not self.robber.forced then self:dropRobber('opted out') end
    self:autoSaveSoon('your robber setting')
    return true
  end

  -- The Route tab's ROB ME button and tick box.
  function c:robMeView()
    if not self.profile or self.error then return nil end
    local problem = self:robberProblem(true)
    if self.robber and self.robber.phase == 'loaded' and self.robber.go then problem = 'A robber is coming. Keep driving.' end
    return { allowed = problem == nil, problem = problem, robbersAllowed = not self.noRobbers, amount = M.STOLEN,
      trunk = M.TRUNK, feedback = self.robberFeedback }
  end

  -- The chase card, in the base thief's shape (thief.lua's thiefView) with road = true, or nil.
  function c:robberView()
    local r = self.robber
    if not r or (r.phase ~= 'chasing' and r.phase ~= 'caught') then return nil end
    return {
      road = true, phase = r.phase, amount = r.amount, bounty = M.TRUNK,
      distanceMetres = r.phase == 'chasing' and r.metres and math.floor(r.metres + 0.5) or nil,
      arrow = r.phase == 'chasing' and r.arrow and math.floor(r.arrow + 0.5) or nil,
      empMetres = emp.RANGE, empInRange = r.phase == 'chasing' and r.metres ~= nil and r.metres <= emp.RANGE,
      emp = r.phase == 'chasing' and self:empView() or nil,
      escapeMetres = M.ESCAPE_METRES, engineBackIn = r.empEndAt and math.ceil(r.empEndAt - self.clock) or nil,
    }
  end
end

return M
