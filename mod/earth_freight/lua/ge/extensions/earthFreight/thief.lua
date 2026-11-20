-- Base thief (trial): while the player is out on the road, a thief breaks into their base and steals STOLEN dollars.
-- The HUD shows the alert and a CHASE_WINDOW_SECONDS countdown. Chase relocates the player to their base for free,
-- waits SETTLE_SECONDS for the world to load and the car to settle, then the thief's car turns up nearby and flees
-- (thiefCar.lua drives it with the game's flee AI, or MadMerick's smartAI when it is installed). Within EMP_METRES the
-- EMP button cuts the thief's ignition: the player gets the money back plus BOUNTY from the thief's trunk. The thief
-- gets away with the money once ESCAPE_METRES clear, and their car disappears. Single player only for now: nothing happens on a
-- server. Pure Lua: the car itself is handled by c.thiefCar (thiefCar.lua), which may be missing.
local pricing = require('earthFreight/pricing')
local flights = require('earthFreight/flights')
local M = {}

M.STOLEN = 1000
M.BOUNTY = 5000
-- How long the player has to press Chase after the theft.
M.CHASE_WINDOW_SECONDS = 600
-- After landing at the base, how long the world gets to load and the car to settle before the thief turns up.
M.SETTLE_SECONDS = 20
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
-- When thefts happen: only with a base, at least MIN_AWAY_METRES from it, with STOLEN in the bank, not on a
-- server. On average one every MEAN_MINUTES of such play, and never within GAP_SECONDS of the last.
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

  local function onServer(self) return self.mp ~= nil and self.mp.state == 'server' end

  -- Why a theft can't happen now (forced: the test command, which skips distance, chance and the gap), or nil.
  function c:theftProblem(forced)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Not ready yet.' end
    if onServer(self) then return 'No thieves on a server yet.' end
    if not self.property then return 'You need a base first.' end
    if self.thief then return 'A thief is already about.' end
    if not self:canAfford(M.STOLEN) then return 'Less than ' .. dollars(M.STOLEN) .. ' in the bank.' end
    if forced then return nil end
    if self.hire or self.onFoot or self.maydayRun or self.booking or self.stranded then return 'Busy.' end
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
    if self:atHome() then return self.onFoot and 'Get back in your car first.' or nil end
    return self:shippingProblem()
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
    if not self:book(self:homeDestination(), true, true) then
      t.feedback = self.shippingFeedback
      return false
    end
    self.booking.thief = true
    if not self:teleportToBooking() then
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
    t.phase, t.settleAt, t.feedback, t.tries = 'settling', self.clock, nil, 0
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
    self:showFlash('delivered', 'THIEF CAUGHT: +' .. dollars(paid), 'The EMP stopped them dead. You got your '
      .. dollars(t.amount) .. ' back, and ' .. dollars(M.BOUNTY) .. ' from their trunk.')
    self:autoSaveSoon('catching the thief')
    self.diag:event('thief_caught', tostring(paid))
    return true
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
      if self.clock - t.settleAt < M.SETTLE_SECONDS or self.onFoot or type(sample) ~= 'table' or not sample.valid then return end
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
      if not d then self:endTheft('escaped') return end
      if d > M.ESCAPE_METRES then self:endTheft('escaped') end
      return
    end
    if t.phase == 'caught' and self.clock - t.caughtAt > M.CAUGHT_SECONDS then
      if t.carId and self.thiefCar then self.thiefCar:remove(t.carId) end
      self.thief = nil
    end
  end

  -- The HUD's card, or nil.
  function c:thiefView()
    local t = self.thief
    if not t then return nil end
    local settleLeft = t.phase == 'settling' and math.max(0, M.SETTLE_SECONDS - (self.clock - t.settleAt)) or nil
    local problem = t.phase == 'stolen' and self:thiefChaseProblem() or nil
    return {
      phase = t.phase, amount = t.amount, bounty = M.BOUNTY, secondsLeft = self:theftSecondsLeft(),
      chaseAllowed = t.phase == 'stolen' and problem == nil, problem = problem,
      settleLeft = settleLeft,
      distanceMetres = t.phase == 'chasing' and t.metres and math.floor(t.metres + 0.5) or nil,
      empMetres = M.EMP_METRES, empInRange = t.phase == 'chasing' and t.metres ~= nil and t.metres <= M.EMP_METRES,
      escapeMetres = M.ESCAPE_METRES, feedback = t.feedback,
    }
  end
end

return M
