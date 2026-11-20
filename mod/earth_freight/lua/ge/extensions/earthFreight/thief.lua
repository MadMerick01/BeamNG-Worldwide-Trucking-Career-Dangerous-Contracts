-- Base thief (trial): while the player is out on the road, a thief breaks into their base and steals STOLEN dollars.
-- The HUD shows the alert and a CHASE_WINDOW_SECONDS countdown. Chase relocates the player to their base for free,
-- waits SETTLE_SECONDS for the world to load and the car to settle, then the thief's car turns up nearby and flees
-- (thiefCar.lua drives it with the game's flee AI, or MadMerick's smartAI when it is installed). Within EMP_METRES the
-- EMP button cuts the thief's ignition: the player gets the money back plus BOUNTY from the thief's trunk. The thief
-- gets away with the money once ESCAPE_METRES clear, and their car disappears. It works the same on a server: each
-- player's own game runs their thief (BeamMP shows its car to everyone), and the money goes into the career the server
-- keeps like any other. The thief's car needs a free car slot (the server's MaxCars). Pure Lua: the car itself is handled by c.thiefCar (thiefCar.lua), which may be missing.
-- Chase holds whatever the player was doing: a delivery keeps its cargo and the distance driven, a Mayday Rescue run
-- stays on, and a trailer goes to the base. Once the chase is over, Back to your job takes them (free) to the exact
-- spot they left from, brings the trailer out behind them, and everything carries on. While they're away the job's
-- distance doesn't count, it can't be delivered, the run can't be won, and nothing saves by itself.
local pricing = require('earthFreight/pricing')
local flights = require('earthFreight/flights')
local M = {}

M.STOLEN = 1000
M.BOUNTY = 5000
-- How long the player has to press Chase after the theft.
M.CHASE_WINDOW_SECONDS = 600
-- After landing at the base, how long the world gets to load and the car to settle before the thief turns up. The
-- count starts only once the car is really there: within ARRIVED_METRES of the base, in the car, with Earth reading
-- its position. A jump away again while Earth loads (the car can turn up somewhere near first) starts it over.
M.SETTLE_SECONDS = 20
M.ARRIVED_METRES = 500
-- How far from the player the thief's car turns up: on the nearest road, lined up with it.
M.SPAWN_METRES = 100
-- How often a spawn the game refused is tried again, and how many times.
M.SPAWN_RETRY_SECONDS = 5
M.SPAWN_TRIES = 3
-- The chase: the thief gets away with the money this far from the player.
M.ESCAPE_METRES = 450
-- The EMP works this close to the thief.
M.EMP_METRES = 5
-- A caught thief's car stays this long before it is taken away.
M.CAUGHT_SECONDS = 20
-- When thefts happen: only with a base, at least MIN_AWAY_METRES from it, with STOLEN in the bank. On average one every MEAN_MINUTES of such play, and never within GAP_SECONDS of the last.
M.MIN_AWAY_METRES = 5000
M.MEAN_MINUTES = 45
M.GAP_SECONDS = 30 * 60
-- The thief's car: for now the same Moonhawk as the sightseeing car, until MadMerick supplies the real one.
M.MODEL = flights.SIGHTSEEING.model
M.CONFIG = flights.SIGHTSEEING.config

local dollars = pricing.dollars

function M.attach(c)
  -- The controller keeps:
  --   self.thief: the theft going on, or nil: { phase, amount, at, settleAt, carId, chaseAt, caughtAt, tries,
  --     nextTry, metres, feedback }. phase: 'stolen' (Chase not pressed yet), 'travelling' (relocating to the base),
  --     'settling' (at the base, waiting for the world), 'chasing', 'caught'.
  --   self.lastTheftAt: the clock when the last theft happened.
  --   self.thiefReturn: once the chase is over, where Back to your job goes: { latitude, longitude, load, mayday,
  --     trailer, feedback }. While the chase is on, it waits in self.thief.returnTo.

  -- Why a theft can't happen now (forced: the test command, which skips distance, chance and the gap), or nil.
  function c:theftProblem(forced)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Not ready yet.' end
    if not self.property then return 'You need a base first.' end
    if self.thief then return 'A thief is already about.' end
    if self.thiefReturn then return 'Go back to your job first.' end
    if not self:canAfford(M.STOLEN) then return 'Less than ' .. dollars(M.STOLEN) .. ' in the bank.' end
    if forced then return nil end
    if self.thiefReturn or self.hire or self.onFoot or self.maydayRun or self.booking or self.stranded then return 'Busy.' end
    if self.lastTheftAt and self.clock - self.lastTheftAt < M.GAP_SECONDS then return 'Too soon.' end
    local away = self:homeDistance()
    if not away or away < M.MIN_AWAY_METRES then return 'Too close to the base.' end
    return nil
  end

  -- A thief takes the money now. Returns true when it did.
  function c:startTheft(forced)
    if self:theftProblem(forced) then return false end
    if not self:spend(M.STOLEN, 'thief') then return false end
    self.thief = { phase = 'stolen', amount = M.STOLEN, at = self.clock }
    self.lastTheftAt = self.clock
    local text = 'A thief broke into your base and took ' .. dollars(M.STOLEN) .. '. Press Chase within '
      .. math.floor(M.CHASE_WINDOW_SECONDS / 60) .. ' minutes to go after them. Catch them with the EMP and you get it back, plus '
      .. dollars(M.BOUNTY) .. ' from their trunk.'
    self:showFlash('cancelled', 'THIEF AT YOUR BASE: -' .. dollars(M.STOLEN), text)
    self:toast('warning', 'Thief at your base', text, 15)
    self:autoSaveSoon('the theft')
    self.diag:event('thief_stole', tostring(M.STOLEN))
    return true
  end

  -- Seconds left to press Chase, or nil once the chase is under way.
  function c:theftSecondsLeft()
    local t = self.thief
    if not t or (t.phase ~= 'stolen' and t.phase ~= 'travelling') then return nil end
    return math.max(0, M.CHASE_WINDOW_SECONDS - (self.clock - t.at))
  end

  -- Why Chase can't be pressed now, or nil.
  function c:thiefChaseProblem()
    local t = self.thief
    if not t or t.phase ~= 'stolen' then return nil end
    if not self:homeDestination() then return 'You no longer have a base.' end
    if self.onFoot then return 'Get back in your car first.' end
    if self:atHome() then return nil end
    -- As for any relocation, except that a job or a Mayday Rescue run is held, not lost.
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Relocation is unavailable right now.' end
    if self.hire then return self:awayText() end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.booking then return 'You already have a relocation booked to ' .. self.booking.name .. '. Cancel it on the Relocate tab first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    return nil
  end

  -- Chase: off to the base (free), or straight into the chase when already there.
  function c:thiefChase()
    local t = self.thief
    if not t or t.phase ~= 'stolen' then return false end
    local problem = self:thiefChaseProblem()
    if problem then
      t.feedback = problem
      return false
    end
    if self:atHome() then
      self:thiefLanded()
      return true
    end
    local home, here = self:homeDestination(), self.lastSample
    -- Where to come back to, with what was going on.
    t.returnTo = { latitude = here.latitude, longitude = here.longitude, load = self.load ~= nil,
      mayday = self.maydayRun ~= nil, trailer = self.trailerOut ~= nil }
    self.booking = { id = 'home', name = home.name, region = home.region, fee = 0, latitude = home.latitude,
      longitude = home.longitude, thief = true }
    self.bookingTeleportAt = nil
    if not self:teleportToBooking() then
      self.booking, t.returnTo = nil, nil
      t.feedback = self.shippingFeedback
      return false
    end
    t.phase, t.feedback = 'travelling', 'Off to your base. The thief is still there.'
    self.diag:event('thief_chase', 'relocating')
    return true
  end

  -- At the base: the world gets SETTLE_SECONDS to load before the thief shows.
  function c:thiefLanded()
    local t = self.thief
    if not t then return end
    t.phase, t.settleAt, t.feedback, t.tries = 'settling', nil, nil, 0
    self:showFlash('delivered', 'BACK AT YOUR BASE', 'Get ready. The thief makes a run for it in a few seconds.')
    self.diag:event('thief_chase', 'at base')
  end

  -- The theft is over. outcome: 'caught', 'escaped', 'late' (Chase never pressed) or 'lost' (no car to chase).
  function c:endTheft(outcome)
    local t = self.thief
    if not t then return end
    if t.carId and self.thiefCar then self.thiefCar:remove(t.carId) end
    if self.booking and self.booking.thief then self.booking, self.bookingTeleportAt = nil, nil end
    self.thief = nil
    if t.returnTo then self.thiefReturn = t.returnTo end
    if outcome == 'late' then
      self:showFlash('cancelled', 'THE THIEF GOT AWAY', 'Nobody went after them. Your ' .. dollars(t.amount) .. ' is gone.')
    elseif outcome == 'escaped' then
      self:showFlash('cancelled', 'THE THIEF GOT AWAY', 'They got ' .. M.ESCAPE_METRES .. ' m clear of you and escaped with your '
        .. dollars(t.amount) .. '.')
    elseif outcome == 'lost' then
      -- The game wouldn't put the thief's car down: not the player's fault, so the money comes back.
      self:addMoney(t.amount)
      self:showFlash('delivered', 'THE THIEF DROPPED IT', 'They ran off on foot and left your ' .. dollars(t.amount) .. ' behind.')
    end
    self.diag:event('thief_over', tostring(outcome))
  end

  -- EMP: within EMP_METRES of the thief, cuts their ignition and the player is paid. Returns true when it hit.
  function c:empThief()
    local t = self.thief
    if not t or t.phase ~= 'chasing' or not self.thiefCar then return false end
    local d = self.thiefCar:distance(t.carId)
    if not d or d > M.EMP_METRES then
      t.feedback = 'Too far for the EMP: get within ' .. M.EMP_METRES .. ' m.'
        .. (d and (' The thief is ' .. math.floor(d + 0.5) .. ' m away.') or '')
      return false
    end
    self.thiefCar:emp(t.carId)
    local paid = t.amount + M.BOUNTY
    self:addMoney(paid)
    t.phase, t.caughtAt, t.feedback = 'caught', self.clock, nil
    if t.returnTo then self.thiefReturn, t.returnTo = t.returnTo, nil end
    self:showFlash('delivered', 'THIEF CAUGHT: +' .. dollars(paid), 'The EMP stopped them dead. You got your '
      .. dollars(t.amount) .. ' back, and ' .. dollars(M.BOUNTY) .. ' from their trunk.')
    if not self:awayFromJob() then self:autoSaveSoon('catching the thief') end
    self.diag:event('thief_caught', tostring(paid))
    return true
  end

  -- The Fire EMP hotkey (Options > Controls > Bindings, no key by default). Does nothing unless a chase is on; out of
  -- range it says so in a pop-up too, since the HUD may be minimised.
  function c:empHotkey()
    local t = self.thief
    if not t or t.phase ~= 'chasing' then return false end
    if self:empThief() then return true end
    self:toast('warning', 'EMP OUT OF RANGE', t.feedback or ('Get within ' .. M.EMP_METRES .. ' m of the thief.'), 4)
    return false
  end

  -- Every tick.
  function c:watchThief(dt)
    if self.thiefCar and self.thiefCar.update then self.thiefCar:update(dt) end
    local t = self.thief
    if not t then
      -- A random theft: on average one every MEAN_MINUTES while one could happen.
      if dt > 0 and not self:theftProblem(false) and self.random() < dt / (M.MEAN_MINUTES * 60) then self:startTheft(false) end
      return
    end
    if t.phase == 'stolen' or t.phase == 'travelling' then
      if self:theftSecondsLeft() <= 0 then self:endTheft('late') end
      return
    end
    if t.phase == 'settling' then
      local sample = self.lastSample
      local away = self:homeDistance()
      local there = not self.onFoot and not self.booking and type(sample) == 'table' and sample.valid
        and away ~= nil and away <= M.ARRIVED_METRES
      if not there then t.settleAt = nil return end
      t.settleAt = t.settleAt or self.clock
      if self.clock - t.settleAt < M.SETTLE_SECONDS then return end
      if t.nextTry and self.clock < t.nextTry then return end
      local id = self.thiefCar and self.thiefCar:spawn(M.MODEL, M.CONFIG, M.SPAWN_METRES)
      if not id then
        t.tries = (t.tries or 0) + 1
        t.nextTry = self.clock + M.SPAWN_RETRY_SECONDS
        self.diag:event('thief_spawn_failed', tostring(t.tries), 'W')
        if t.tries >= M.SPAWN_TRIES then self:endTheft('lost') end
        return
      end
      self.thiefCar:flee(id)
      t.phase, t.carId, t.chaseAt = 'chasing', id, self.clock
      self:showFlash('cancelled', 'THERE THEY GO', 'Chase the thief down and hit the EMP within ' .. M.EMP_METRES .. ' m.')
      self.diag:event('thief_spawned', tostring(id))
      return
    end
    if t.phase == 'chasing' then
      local d = self.thiefCar and self.thiefCar:distance(t.carId)
      t.metres = d
      t.arrow = d and self.thiefCar.bearing and self.thiefCar:bearing(t.carId) or nil
      if not d then self:endTheft('escaped') return end
      if d > M.ESCAPE_METRES then self:endTheft('escaped') end
      return
    end
    if t.phase == 'caught' and self.clock - t.caughtAt > M.CAUGHT_SECONDS then
      if t.carId and self.thiefCar then self.thiefCar:remove(t.carId) end
      self.thief = nil
    end
  end

  -- The Base tab's Get robbed button, which starts a theft whenever the rules allow.
  function c:robberyView()
    if not self.profile or self.error then return nil end
    local problem = self:theftProblem(true)
    if problem == 'Not ready yet.' then problem = 'Get in your car first.' end
    return { allowed = problem == nil, problem = problem, amount = M.STOLEN, bounty = M.BOUNTY }
  end

  -- Whether the player left a job, run or spot to chase a thief and hasn't gone back yet.
  function c:awayFromJob()
    return self.thiefReturn ~= nil or (self.thief ~= nil and self.thief.returnTo ~= nil)
  end

  -- Why Back to your job can't be pressed now, or nil.
  function c:thiefReturnProblem()
    local r = self.thiefReturn
    if not r then return nil end
    if self.booking and self.booking.thiefReturn then return nil end
    if self.onFoot then return 'Get back in your car first.' end
    if self.hire then return self:awayText() end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.booking then return 'You have a relocation booked to ' .. self.booking.name .. '. Cancel it on the Relocate tab first.' end
    return nil
  end

  -- Back to your job: a free teleport to the spot the player left from.
  function c:thiefGoBack()
    local r = self.thiefReturn
    if not r then return false end
    local problem = self:thiefReturnProblem()
    if problem then
      r.feedback = problem
      return false
    end
    if not (self.booking and self.booking.thiefReturn) then
      self.booking = { id = 'return', name = 'where you left off', region = 'back on the road', fee = 0,
        latitude = r.latitude, longitude = r.longitude, thiefReturn = true }
      self.bookingTeleportAt = nil
    end
    if not self:teleportToBooking() then
      r.feedback = self.shippingFeedback
      return false
    end
    r.feedback = 'On your way back. The terrain takes a few seconds to load.'
    self.diag:event('thief_return', 'teleport')
    return true
  end

  -- Landed back where the player left off: the trailer comes out behind them and the job carries on.
  function c:thiefReturned()
    local r = self.thiefReturn
    self.thiefReturn = nil
    if not r then return end
    local trailer = ''
    if r.trailer and self.trailer and self.trailer.stored and not self.trailerOut then
      trailer = self:spawnTrailer() and ' Your trailer is behind you: back up to it slowly and it hitches itself.'
        or ' Bring your trailer out on the Garage tab.'
    end
    local what = r.load and 'Your job carries on from here.' or r.mayday and 'Your Mayday Rescue run carries on from here.'
      or 'You are back where you left off.'
    self:showFlash('delivered', 'BACK ON THE ROAD', what .. trailer)
    self:autoSaveSoon('your trip back')
    self.diag:event('thief_return', 'landed')
  end

  -- The HUD's card, or nil.
  function c:thiefView()
    local t = self.thief
    local r = self.thiefReturn
    if r and (not t or t.phase == 'caught') then
      local problem = self:thiefReturnProblem()
      return { phase = 'return', job = r.load, mayday = r.mayday, trailer = r.trailer, returnAllowed = problem == nil,
        problem = problem, travelling = self.booking ~= nil and self.booking.thiefReturn == true or nil, feedback = r.feedback }
    end
    if not t then return nil end
    local settleLeft = t.phase == 'settling' and t.settleAt and math.max(0, M.SETTLE_SECONDS - (self.clock - t.settleAt)) or nil
    local problem = t.phase == 'stolen' and self:thiefChaseProblem() or nil
    return {
      phase = t.phase, amount = t.amount, bounty = M.BOUNTY, secondsLeft = self:theftSecondsLeft(),
      chaseAllowed = t.phase == 'stolen' and problem == nil, problem = problem,
      settleLeft = settleLeft,
      distanceMetres = t.phase == 'chasing' and t.metres and math.floor(t.metres + 0.5) or nil,
      arrow = t.phase == 'chasing' and t.arrow and math.floor(t.arrow + 0.5) or nil,
      empMetres = M.EMP_METRES, empInRange = t.phase == 'chasing' and t.metres ~= nil and t.metres <= M.EMP_METRES,
      escapeMetres = M.ESCAPE_METRES, feedback = t.feedback,
      held = t.returnTo and { job = t.returnTo.load, mayday = t.returnTo.mayday } or nil,
    }
  end
end

return M
