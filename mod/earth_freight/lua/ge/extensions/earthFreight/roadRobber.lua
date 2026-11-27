-- The road robber: on a delivery, fuel run or contract of MIN_JOB_METRES or more, CHANCE of the time a robber in the
-- base thief's Moonhawk (thief.lua) ambushes the player on the road. Its car is loaded out of sight when the job is
-- taken, at the job board, so putting it on the road later doesn't stutter (thiefCar.lua). While it waits, the game
-- notes the player's trail (a point every 10 m, the last 150 m). Somewhere between EDGE_METRES into the job and
-- EDGE_METRES before its end, once the ground there has loaded, it is put on the road BEHIND_METRES behind the player,
-- on that trail and facing their way (MadMerick's call: coming from behind, the AI never has to turn round), and:
--   hunting: the game's chase AI at the player's speed plus HUNT_FAR_EXTRA_KPH to catch up, easing to plus
--     HUNT_EXTRA_KPH within CLOSE_METRES, never over HUNT_MAX_KPH.
--   Within STRIKE_METRES it strikes: its EMP cuts the player's engine for PLAYER_EMP_SECONDS and jams their brakes for
--     PLAYER_BRAKE_SECONDS, and it takes its cut (M.take: SHARE of the job's pay, MIN_TAKE to MAX_TAKE). Not struck within GIVE_UP_SECONDS, or GIVE_UP_METRES behind: it gives
--     up and goes, and nothing is lost.
--   chasing: first it overtakes (passing): it eases off to PASS_START_KPH for PASS_HOLD_SECONDS so it doesn't run into
--     the braking player, then goes round them at up to PASS_KPH. Once it is ahead of them and PASS_CLEAR_METRES clear
--     (or after PASS_MAX_SECONDS) it flees (the base thief's flee, fleeSupervisor.lua). The player's EMP (emp.lua)
--     within its range stops it for good: the cut back plus TRUNK_SHARE of it again from the trunk (none on ROB ME,
--     a test), and the car goes after CAUGHT_SECONDS.
--     ESCAPE_METRES clear, it gets away with the money. The job carries on throughout, and delivering or abandoning it
--     doesn't end the chase.
-- Online, every player can be robbed (MadMerick, 21 Nov: the old "Robbers can rob me" opt-out was too big an
-- advantage; an old save's noRobbers is ignored). In single player only (MadMerick, 22 Nov), the Route tab's "Robbers
-- and thieves" switch turns off road robbers and the base thief, saved as robbersOff, with no cost to the player. On a
-- BeamMP server the switch isn't shown and a saved robbersOff is ignored (robbersOff below). c:robMe starts one straight away for the tests (the Route tab's ROB ME button is gone: MadMerick, 23 Nov), and doesn't count as the
-- job's robbery. Never on Mayday Rescue runs, heli flights or the heli's package jobs. Pure Lua: the car is
-- handled by c.thiefCar, which may be missing. An admin on the server can drive a robber himself (adminRobber.lua):
-- self.robber then has admin = true.
local pricing = require('earthFreight/pricing')
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local thief = require('earthFreight/thief')
local emp = require('earthFreight/emp')
local M = {}

-- Road robbers are off for now (MadMerick, 27 Nov): no robber comes for a job, the admin robber can't pick anyone, and
-- the Route tab doesn't show the Road robbers card or its switch. Everything else is kept, so setting ON back to true
-- (and putting the help page's lines back) brings them back. c:robMe (the tests' robber) still works. The EMP code the
-- desert run's Raiders use (thiefCar.lua's empPlayer, emp.lua) isn't affected.
M.ON = false

M.CHANCE = 0.35
M.MIN_JOB_METRES = 5000
M.EDGE_METRES = 2000
M.BEHIND_METRES = 100
-- The robber's cut (MadMerick, 21 Nov): SHARE of the job's pay, at least MIN_TAKE and at most MAX_TAKE, never more
-- than the bank; so a big load is a big prize. Catching it pays the cut back plus TRUNK_SHARE of it from the trunk.
M.SHARE = 0.2
M.MIN_TAKE = 500
M.MAX_TAKE = 15000
M.TRUNK_SHARE = 0.5
M.STRIKE_METRES = emp.RANGE
M.PLAYER_EMP_SECONDS = 10
-- ...and jams their brakes on for this long, for a jolt.
M.PLAYER_BRAKE_SECONDS = 0.5
M.GIVE_UP_SECONDS = 240
M.GIVE_UP_METRES = 500
M.ESCAPE_METRES = 450
M.CAUGHT_SECONDS = 30
-- A robber's or thief's car that hardly moves (under STUCK_SPEED m/s) for STUCK_SECONDS, off the road, is put back on
-- the nearest road (thiefCar.lua unstick), at most once every UNSTICK_EVERY_SECONDS.
M.STUCK_SECONDS = 5
M.STUCK_SPEED = 1.5
M.UNSTICK_EVERY_SECONDS = 10
-- After a robbery ends, its card shows how it went (and the money) for this long.
M.RESULT_SECONDS = 20
-- Catching up: the player's speed plus HUNT_FAR_EXTRA_KPH while more than CLOSE_METRES back, then plus HUNT_EXTRA_KPH.
M.HUNT_FAR_EXTRA_KPH = 40
M.HUNT_EXTRA_KPH = 15
M.CLOSE_METRES = 50
M.HUNT_MAX_KPH = 130
-- Overtaking after the strike (see the top).
M.PASS_START_KPH = 30
M.PASS_HOLD_SECONDS = 1
M.PASS_KPH = 100
M.PASS_CLEAR_METRES = 30
M.PASS_MAX_SECONDS = 15
-- How often a refused place (no ground yet) or load is tried again; a ROB ME robber that can't find ground gives up.
M.RETRY_SECONDS = 2
M.ROB_ME_TRIES = 15
M.SPEED_EVERY_SECONDS = 1
-- The car: the base thief's.
M.MODEL = thief.MODEL
M.CONFIG = thief.CONFIG

local dollars = pricing.dollars

-- Hunting speed: the player's plus HUNT_FAR_EXTRA_KPH while far back (metres), plus HUNT_EXTRA_KPH once close, capped.
function M.huntKph(playerKph, metres)
  local extra = (metres and metres > M.CLOSE_METRES) and M.HUNT_FAR_EXTRA_KPH or M.HUNT_EXTRA_KPH
  return math.min(M.HUNT_MAX_KPH, math.max(0, playerKph or 0) + extra)
end

local function round10(n) return math.floor(n / 10 + 0.5) * 10 end

-- The robber's cut of a job paying pay, with balance in the bank (0 when there's nothing to take).
function M.take(pay, balance)
  local cut = round10(math.max(M.MIN_TAKE, math.min(M.MAX_TAKE, (tonumber(pay) or 0) * M.SHARE)))
  return math.max(0, math.min(cut, math.floor(tonumber(balance) or 0)))
end

-- What the trunk pays on top when the robber with this cut is caught.
function M.trunk(amount) return round10((amount or 0) * M.TRUNK_SHARE) end

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
  --     empEndAt, caughtAt, nextTry, tries, speedAt, passing, fastAt }. phase: 'loaded' (out of sight, waiting for its
  --     moment), 'hunting', 'chasing' (struck: overtaking while passing, then fleeing), 'caught'. The admin robber
  --     (adminRobber.lua) uses 'lurking' until he strikes.
  --   self.robberJob: the load the CHANCE roll was made for, and self.robberAtKm: the job's driven km at which it strikes
  --     (nil when this job isn't robbed).
  --   self.robbedLoad: the load a robber (this game's or the admin's) has already robbed: one robbery a delivery.
  --   self.robbersOffSaved: true when the player switched robbers off (single player only: see robbersOff).

  -- Whether robbers and thieves are switched off: only in single player, never on a BeamMP server.
  function c:robbersOff()
    return self.robbersOffSaved == true and self.mp == nil
  end

  -- Why a robber can't be put on the road now, or nil.
  function c:robberProblem(forced)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Get in your car first.' end
    if not self.thiefCar then return 'Robbers are not available.' end
    if self.onFoot then return 'Get back in your car first.' end
    if self.hire then return 'Not while flying.' end
    if self.thief or self:awayFromJob() then return 'A thief is already about.' end
    if self.robber and self.robber.phase ~= 'loaded' then return 'A robber is already about.' end
    if not self:canAfford(M.MIN_TAKE) then return 'Less than ' .. dollars(M.MIN_TAKE) .. ' in the bank.' end
    -- No robbers during a Mayday Rescue run (MadMerick, 22 Nov), not even ROB ME's.
    if self.maydayRun then return 'Not during a Mayday Rescue run.' end
    if forced then return nil end
    if not M.ON then return 'Road robbers are off for now.' end
    if self:robbersOff() then return 'Robbers are switched off.' end
    if self.booking or self.stranded then return 'Busy.' end
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

  -- ROB ME: a robber on the road behind straight away, for the tests only (no button any more). Returns true when one is coming.
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

  -- How a robbery of this player went: kept a while for the HUD's card (robberyResultView), and told to the server's
  -- live feed (multiplayer.lua robbed) on a server.
  -- taken: what the robber or thief took; paid: what catching them paid (the money back plus the trunk).
  function c:robberyNews(who, what, taken, paid)
    if what ~= 'struck' then
      self.robberyResult = { road = who == 'robber' or nil, outcome = what, at = self.clock, amount = taken, paid = paid }
    end
    if self.mp and self.mp.robbed then self.mp:robbed(who, what, taken, paid) end
  end

  -- The money in a robbery's outcome, for the HUD: what was taken, and what the player got back.
  local function robberyMoney(r)
    local got = (r.outcome == 'caught' and r.paid) or (r.outcome == 'dropped' and r.amount) or nil
    return r.amount, got
  end

  -- The card's last word once a robbery is over and its car gone: who, how it ended and the money, for RESULT_SECONDS.
  function c:robberyResultView()
    local r = self.robberyResult
    if not r or self.clock - r.at > M.RESULT_SECONDS then return nil end
    local taken, got = robberyMoney(r)
    return { road = r.road, phase = 'over', outcome = r.outcome, amount = taken, paid = got }
  end
  -- For the thief's Back to your job card: how it ended, while that card waits.
  function c:robberyOutcome(road)
    local r = self.robberyResult
    if not r or (r.road or false) ~= (road or false) then return nil end
    local _, got = robberyMoney(r)
    return r.outcome, got
  end

  -- Watches a fleeing or driving robber's or thief's car (r: the robber or the theft) for getting stuck off the road.
  function c:watchStuck(r, dt, who)
    local car = self.thiefCar
    if not r.carId or not car or not car.speed or not car.unstick then return end
    local v = car:speed(r.carId)
    if not v or v >= M.STUCK_SPEED then r.stillFor = 0 return end
    r.stillFor = (r.stillFor or 0) + (dt or 0)
    if r.stillFor < M.STUCK_SECONDS or self.clock < (r.unstickAt or 0) then return end
    r.stillFor, r.unstickAt = 0, self.clock + M.UNSTICK_EVERY_SECONDS
    if car:unstick(r.carId) then self.diag:event(who .. '_unstuck', '') end
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
    local trunk = r.trunk or 0
    local paid = (r.amount or 0) + trunk
    self:addMoney(paid)
    self:cashSound()
    r.phase, r.caughtAt = 'caught', self.clock
    self:showFlash('delivered', 'ROBBER CAUGHT: +' .. dollars(paid), 'The EMP stopped them dead. You got your '
      .. dollars(r.amount or 0) .. ' back' .. (trunk > 0 and (', and ' .. dollars(trunk) .. ' from their trunk.')
      or '. ROB ME is a test, so there is no trunk bonus.'))
    self:autoSaveSoon('catching the robber')
    self:robberyNews('robber', 'caught', r.amount, paid)
    self.diag:event('robber_caught', tostring(paid))
    return true
  end

  -- The robber's cut of the job the player is on now (MIN_TAKE without a job: ROB ME).
  function c:robberTake()
    local balance = self.profile and self.profile.progression.balance or 0
    return M.take(self.load and self.load.pay or 0, balance)
  end

  -- The robber's EMP hits the player: its cut taken, the engine dead for a few seconds, and it flees.
  function c:robberStrikes()
    local r = self.robber
    local amount = self:robberTake()
    if amount <= 0 or not self:spend(amount, 'robber') then
      -- Spent it since: nothing to take, so it just goes.
      self:dropRobber('nothing to take')
      return
    end
    self.thiefCar:empPlayer()
    -- The robber's EMP drains the player's too: it charges from empty before they can fire back (emp.lua).
    self.empFiredAt = self.clock
    self:empSound()
    -- It came from behind: it eases off, then overtakes before it flees (see the top).
    if self.thiefCar.pass then self.thiefCar:pass(r.carId, M.PASS_START_KPH) else self.thiefCar:flee(r.carId) end
    r.passing = self.thiefCar.pass ~= nil or nil
    r.phase, r.amount, r.struckAt, r.empEndAt = 'chasing', amount, self.clock, self.clock + M.PLAYER_EMP_SECONDS
    r.trunk = (not r.forced) and M.trunk(amount) or 0
    -- One robbery a delivery: the admin robber can't rob this job now either (adminRobber.lua).
    if not r.forced then self.robbedLoad = self.load end
    local text = 'A robber hit you with an EMP and took ' .. dollars(amount) .. '. Your engine is back in '
      .. M.PLAYER_EMP_SECONDS .. ' s and your EMP is drained: it takes ' .. emp.CHARGE_SECONDS .. ' s to charge. Catch them with your EMP within ' .. emp.RANGE .. ' m to get it back'
      .. (r.trunk > 0 and (', plus ' .. dollars(r.trunk) .. ' from their trunk.') or '.')
    self:showFlash('cancelled', 'ROBBED ON THE ROAD: -' .. dollars(amount), text)
    self:toast('warning', 'Robbed on the road', text, 10)
    self:autoSaveSoon('the robbery')
    self:robberyNews('robber', 'struck', amount)
    self.diag:event('robber_struck', tostring(amount))
  end

  -- Every tick.
  function c:watchRobber(dt)
    if not self.thiefCar or not self.profile or self.error then return end
    local load = self.load
    -- A new job: the CHANCE roll, once (not when the admin robber already robbed it: one robbery a delivery). A robbed job gets its robber loaded now, at the job board.
    if load ~= self.robberJob then
      self.robberJob, self.robberAtKm = load, nil
      if self.robber and self.robber.phase == 'loaded' and not self.robber.forced then self:dropRobber('job ended') end
      local robbable, metres = self:robbableJob(load)
      if robbable and M.ON and not self:robbersOff() and not self.robber and self.robbedLoad ~= load and self.random() < M.CHANCE then
        local span = metres - 2 * M.EDGE_METRES
        self.robberAtKm = (M.EDGE_METRES + self.random() * math.max(0, span)) / 1000
        self.diag:event('robber_planned', string.format('%.1f km', self.robberAtKm))
        self:loadRobber(false)
      end
    end
    -- This job's robber not loaded (the game refused, or ROB ME used it): loaded again while its moment is ahead.
    if not self.robber and self.robberAtKm and load and (load.drivenKm or 0) < self.robberAtKm and M.ON and not self:robbersOff()
      and self.clock >= (self.robberLoadAt or 0) then
      self.robberLoadAt = self.clock + M.RETRY_SECONDS * 5
      self:loadRobber(false)
    end
    local r = self.robber
    -- The trail the robber is put on, behind the player: only noted on a job or while a robber waits (thiefCar.lua).
    if (load or (r and r.phase == 'loaded')) and not self.onFoot and self.thiefCar.noteTrail then self.thiefCar:noteTrail() end
    if not r then return end
    if r.admin then return self:watchAdminRobber() end
    if r.phase == 'loaded' then
      if not r.go then
        if not M.ON or self:robbersOff() or not self.robberAtKm or not load or load ~= self.robberJob or (load.drivenKm or 0) < self.robberAtKm then return end
        r.go = true
      end
      if r.nextTry and self.clock < r.nextTry then return end
      if self:robberProblem(r.forced) then r.nextTry = self.clock + M.RETRY_SECONDS return end
      local ok, why = self.thiefCar:place(r.carId, M.BEHIND_METRES, true)
      if not ok then
        r.tries = (r.tries or 0) + 1
        r.nextTry = self.clock + M.RETRY_SECONDS
        if why == 'gone' or (r.forced and r.tries >= M.ROB_ME_TRIES) then
          if r.forced then self.robberFeedback = 'No clear road behind you. Drive on along a road and try ROB ME again.' end
          self:dropRobber(why)
        end
        return
      end
      local kph = self.thiefCar:playerKph() or 0
      self.thiefCar:hunt(r.carId, M.huntKph(kph, M.BEHIND_METRES))
      r.phase, r.placedAt, r.speedAt = 'hunting', self.clock, self.clock
      if r.forced then self.robberFeedback = nil else self.robberAtKm = nil end
      self.diag:event('robber_placed', tostring(r.carId))
      return
    end
    local d = self.thiefCar:distance(r.carId)
    r.metres = d
    if r.empEndAt and self.clock >= r.empEndAt then
      r.empEndAt = nil
      self.thiefCar:empPlayerEnd()
    elseif r.empEndAt and r.struckAt and not r.brakesOff and self.clock - r.struckAt >= M.PLAYER_BRAKE_SECONDS then
      -- The brakes were jammed on for a jolt only (thiefCar.lua); the engine stays dead.
      r.brakesOff = true
      if self.thiefCar.empPlayerBrakeOff then self.thiefCar:empPlayerBrakeOff() end
    end
    if r.phase == 'hunting' or (r.phase == 'chasing' and not r.passing) then self:watchStuck(r, dt, 'robber') end
    if r.phase == 'hunting' then
      if not d then self:dropRobber('gone') return end
      if d <= M.STRIKE_METRES then self:robberStrikes() return end
      if self.clock - r.placedAt > M.GIVE_UP_SECONDS or d > M.GIVE_UP_METRES then
        self:dropRobber('gave up')
        if r.forced then self:showFlash('delivered', 'THE ROBBER GAVE UP', 'You got away. Nothing was taken.') end
        return
      end
      if self.clock - (r.speedAt or 0) >= M.SPEED_EVERY_SECONDS then
        r.speedAt = self.clock
        self.thiefCar:setSpeed(r.carId, M.huntKph(self.thiefCar:playerKph() or 0, d))
      end
      return
    end
    if r.phase == 'chasing' and r.passing and d then
      local since = self.clock - (r.struckAt or self.clock)
      if not r.fastAt and since >= M.PASS_HOLD_SECONDS then
        r.fastAt = self.clock
        self.thiefCar:setSpeed(r.carId, M.PASS_KPH)
      end
      -- Ahead of the player (within 90 degrees of where their car points) and clear of them: now it flees.
      local bearing = self.thiefCar.bearing and self.thiefCar:bearing(r.carId)
      local past = bearing ~= nil and math.abs(bearing) < 90 and d >= M.PASS_CLEAR_METRES
      if past or since >= M.PASS_MAX_SECONDS then
        r.passing = nil
        self.thiefCar:flee(r.carId)
        self.diag:event('robber_passed', past and 'past' or 'timed out')
      end
    end
    if r.phase == 'chasing' then
      r.arrow = d and self.thiefCar.bearing and self.thiefCar:bearing(r.carId) or nil
      if not d or d > M.ESCAPE_METRES then
        self:dropRobber('escaped')
        self:robberyNews('robber', 'escaped', r.amount)
        self:showFlash('cancelled', 'THE ROBBER GOT AWAY', 'They got ' .. M.ESCAPE_METRES .. ' m clear of you and escaped with your '
          .. dollars(r.amount or 0) .. '.')
      end
      return
    end
    if r.phase == 'caught' and self.clock - r.caughtAt > M.CAUGHT_SECONDS then self:dropRobber('caught') end
  end

  -- The Route tab's "Robbers and thieves" switch (single player only): on (true) or off (false). Saved with the career.
  function c:setRobbersOn(on)
    if not self.profile or self.error or self.mp then return false end
    self.robbersOffSaved = (on == false) or nil
    -- A robber waiting for its moment goes; one already on the road, or a theft under way, carries on.
    if self.robbersOffSaved and self.robber and self.robber.phase == 'loaded' and not self.robber.forced then
      self:dropRobber('switched off')
    end
    if self.robbersOffSaved then self.robberAtKm = nil end
    self:autoSaveSoon('your robber setting')
    return true
  end

  -- The Route tab's Road robbers card and its switch (only offered in single player). allowed and problem are what
  -- ROB ME would say; the HUD no longer has that button.
  function c:robMeView()
    if not M.ON or not self.profile or self.error then return nil end
    local problem = self:robberProblem(true)
    if self.robber and self.robber.phase == 'loaded' and self.robber.go then problem = 'A robber is coming. Keep driving.' end
    -- What a robber takes is never shown here (MadMerick): only the amount, once it happens.
    return { allowed = problem == nil, problem = problem, feedback = self.robberFeedback,
      canSwitch = self.mp == nil or nil, robbersOn = not self:robbersOff() }
  end

  -- The chase card, in the base thief's shape (thief.lua's thiefView) with road = true, or nil.
  function c:robberView()
    local r = self.robber
    if not r or (r.phase ~= 'chasing' and r.phase ~= 'caught') then return nil end
    return {
      road = true, phase = r.phase, amount = r.amount, bounty = r.trunk or 0,
      paid = r.phase == 'caught' and (r.amount or 0) + (r.trunk or 0) or nil,
      distanceMetres = r.phase == 'chasing' and r.metres and math.floor(r.metres + 0.5) or nil,
      arrow = r.phase == 'chasing' and r.arrow and math.floor(r.arrow + 0.5) or nil,
      empMetres = emp.RANGE, empInRange = r.phase == 'chasing' and r.metres ~= nil and r.metres <= emp.RANGE,
      emp = r.phase == 'chasing' and self:empView() or nil,
      escapeMetres = M.ESCAPE_METRES, engineBackIn = r.empEndAt and math.ceil(r.empEndAt - self.clock) or nil,
    }
  end
end

return M
