-- The admin robber: on MadMerick's server, an admin (listed in the server's own settings, never in this mod) can drive
-- the road robber himself, under its rules. The server tells only an admin's game who can be robbed now: players on a
-- job the road robber could rob (roadRobber.lua), with "Robbers can rob me" ticked. Everyone else's game never shows it.
--
-- The admin's side: Rob asks the server, which asks that player's game for the road spot AHEAD_METRES in front of their
-- car. The admin's car is swapped for the robber's Moonhawk where it stands, the same way the sightseeing car is
-- (flights.lua), and BeamNG.Earth teleports it to that spot; once the ground has loaded it is turned to face the
-- player's way and the robbery is on. When it ends he goes back to his own car where he left it, for free, with its job.
-- Caught, his car is shut down for CAUGHT_SECONDS first.
--
-- The robbed player's side: their game runs the robbery, as it does the AI robber, with the admin's car in place of
-- the robber's. The admin drives the whole time and fires his EMP himself (his HUD button or the Fire EMP key, with the
-- same 20-second charge as everyone's): the player's game checks it reached, within STRIKE_METRES it strikes (engine
-- out, STOLEN taken), and tells him how far off a miss was. The player's EMP catches it (STOLEN
-- back plus TRUNK), ESCAPE_METRES clear it gets away, and not struck within STRIKE_SECONDS it gives up. The admin's name
-- is only shown when he's caught. The STOLEN money just disappears: the admin gets nothing. It doesn't use up the job's
-- 50% roll for the AI robber. Pure Lua: BeamMP's car names come from c.mpGame, which may be missing.
local location = require('earthFreight/location')
local roadRobber = require('earthFreight/roadRobber')
local pricing = require('earthFreight/pricing')
local emp = require('earthFreight/emp')
local M = {}

M.AHEAD_METRES = roadRobber.AHEAD_METRES
M.STRIKE_METRES = roadRobber.STRIKE_METRES
M.STOLEN = roadRobber.STOLEN
M.TRUNK = roadRobber.TRUNK
M.ESCAPE_METRES = roadRobber.ESCAPE_METRES
M.CAUGHT_SECONDS = roadRobber.CAUGHT_SECONDS
-- The admin has this long from being in place to strike; there's no distance limit.
M.STRIKE_SECONDS = 600
-- The admin's game waits this long for the player's answer, and for the teleport to land.
M.ASK_SECONDS = 15
M.GOING_SECONDS = 90
-- Landed within ARRIVE_METRES of the spot, the car settles SETTLE_SECONDS before it's turned and the robbery starts.
M.ARRIVE_METRES = 150
M.SETTLE_SECONDS = 3
-- The robbed player's game waits this long for the admin's car to turn up on the server before giving up.
M.CAR_WAIT_SECONDS = 60

local dollars = pricing.dollars

-- Why the server's answer said no, for the admin.
local WHY = {
  gone = 'is not on the server any more.', off = 'cannot be robbed right now.', busy = 'is already being robbed.',
  no_ground = 'has no road with loaded ground ahead. Try again in a moment.', away = 'is not driving right now.',
}

function M.attach(c)
  -- The controller keeps:
  --   self.adminDrive: the admin's own robbery, or nil: { stage, to, name, at, spot, arrivedAt, struck, caughtAt }.
  --     stage: 'asking' (the player's game is asked where), 'leaving' (the robber's car takes his car's place), 'going'
  --     (BeamNG.Earth teleports it), 'ready' (in place), 'caught' (shut down), 'back' (going back to his car).
  --   self.robber with admin = true: a robbery by an admin on this player (see roadRobber.lua), with serverCar, the
  --     admin's car as BeamMP names it.

  -- ===== The admin's side ===========================================================================================

  -- The admin's list, or nil when this player isn't an admin.
  function c:adminTargets()
    return self.mp and self.mp.state == 'server' and self.mp.admin and self.mp.admin.targets or nil
  end

  -- Why the admin can't start a robbery now, or nil.
  function c:adminDriveProblem()
    if not self:adminTargets() then return 'Only for the server\'s admins.' end
    if self.adminDrive then return 'You are already robbing ' .. self.adminDrive.name .. '.' end
    if self.thief or (self.robber and self.robber.phase ~= 'loaded') then return 'Not while a robber is after you.' end
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage then return 'Get in your car first.' end
    if self.hire then return 'Get back in your own car first.' end
    return self:leaveCarProblem('drop in as the robber')
  end

  -- Rob: asks the server to rob player id.
  function c:adminRob(id)
    local who
    for _, p in ipairs(self:adminTargets() or {}) do if p.id == id then who = p end end
    local problem = self:adminDriveProblem()
    if not problem and not who then problem = 'That player can\'t be robbed any more.' end
    if problem then
      self.adminFeedback = problem
      return false
    end
    self.adminDrive = { stage = 'asking', to = id, name = who.name, at = self.clock }
    self.mp.adminSpot, self.mp.adminState = nil, nil
    self.mp:adminRob('start', { to = id })
    self.adminFeedback = 'Asking ' .. who.name .. '\'s game where to drop you in...'
    self.diag:event('admin_rob', tostring(id))
    return true
  end

  -- Stop: the admin calls it off (also Return to your job while robbing). The player is told the robber has gone.
  function c:adminStop()
    local a = self.adminDrive
    if not a or a.stage == 'back' then return false end
    self.mp:adminRob('stop')
    self:adminGoBack('You called it off.')
    return true
  end

  -- Back to his own car. why is told on the panel.
  function c:adminGoBack(why)
    local a = self.adminDrive
    if not a then return end
    self.adminFeedback = why
    if not self.hire or not self.hire.admin then
      self.adminDrive = nil
      return
    end
    a.stage = 'back'
    self:backToCar(true)
  end

  -- The player's game answered: where to drop in, or why not.
  function c:adminSpotAnswered(d)
    local a = self.adminDrive
    if not a or a.stage ~= 'asking' or type(d) ~= 'table' or tonumber(d.to) ~= a.to then return false end
    local spot = d.ok == true and location.valid(d) and location.copy(d) or nil
    if not spot then
      self.adminDrive = nil
      self.adminFeedback = a.name .. ' ' .. (WHY[d.why] or WHY.off)
      return false
    end
    a.spot, a.heading = spot, location.finite(d.heading) and d.heading or nil
    -- The robber's Moonhawk takes his car's place, saved first, as the sightseeing car does.
    if not self:goSightseeing() then
      self.mp:adminRob('stop')
      self.adminDrive = nil
      self.adminFeedback = self.sightseeingFeedback or 'Could not bring out the robber\'s car.'
      return false
    end
    self.hire.admin = true
    a.stage, a.at = 'leaving', self.clock
    self.adminFeedback = 'Getting in the robber\'s car...'
    return true
  end

  -- Seconds until the admin's EMP is charged again, 0 when ready. Every press starts the charge, hit or miss.
  function c:adminEmpLeft()
    local a = self.adminDrive
    if not a or not a.empAt then return 0 end
    return math.max(0, emp.CHARGE_SECONDS - (self.clock - a.empAt))
  end

  -- The admin fires his EMP (his panel's button, or the Fire EMP key): the player's game says whether it reached.
  -- Returns true when it was fired; why not is in self.adminFeedback.
  function c:adminEmp()
    local a = self.adminDrive
    if not a or a.stage ~= 'ready' or a.struck then return false end
    local left = self:adminEmpLeft()
    if left > 0 then
      self.adminFeedback = 'EMP charging: ' .. math.ceil(left) .. ' s.'
      return false
    end
    a.empAt = self.clock
    self:empSound()
    self.mp:adminRob('emp')
    self.adminFeedback = 'EMP fired...'
    self.diag:event('admin_emp', '')
    return true
  end

  -- How it went, from the player's game: 'missed', 'struck', 'caught', 'escaped', 'gave_up', 'gone', 'refused'.
  function c:adminStateChanged(d)
    local a = self.adminDrive
    if not a or type(d) ~= 'table' or a.stage == 'back' then return false end
    local state = d.state
    if state == 'missed' then
      local metres = tonumber(d.metres)
      self.adminFeedback = 'Missed: get within ' .. M.STRIKE_METRES .. ' m.'
        .. (metres and metres >= 0 and (' They were ' .. math.floor(metres + 0.5) .. ' m away.') or '') .. ' The EMP is charging.'
      self:toast('warning', 'EMP MISSED', self.adminFeedback, 4)
      return true
    end
    if state == 'struck' then
      a.struck = true
      self.adminFeedback = nil
      self:showFlash('cancelled', 'YOU ROBBED ' .. a.name:upper(), 'Your EMP hit them and took ' .. dollars(M.STOLEN)
        .. '. Get ' .. M.ESCAPE_METRES .. ' m clear before they catch you with theirs.')
    elseif state == 'caught' then
      a.stage, a.caughtAt = 'caught', self.clock
      if self.thiefCar then self.thiefCar:shutDownPlayer() end
      self:showFlash('cancelled', a.name:upper() .. ' CAUGHT YOU', 'Their EMP stopped you dead, and they know it was you.'
        .. ' Back to your car in ' .. M.CAUGHT_SECONDS .. ' s.')
    elseif state == 'escaped' then
      self:showFlash('delivered', 'YOU GOT AWAY', 'You got clear of ' .. a.name .. ' with the ' .. dollars(M.STOLEN)
        .. '. They never knew it was you. Back to your car.')
      self:adminGoBack(nil)
    elseif state == 'gave_up' then
      self:adminGoBack('Time ran out before you hit ' .. a.name .. '. Back to your car.')
    elseif d.why == 'no_car' then
      self:adminGoBack('The server could not see your robber car, so the robbery is off. Back to your car.')
    else
      self:adminGoBack(a.name .. ' ' .. (WHY[d.why] or 'left, so the robbery is over.'))
    end
    self.diag:event('admin_rob_state', tostring(state))
    return true
  end

  -- Every tick: moves the admin's robbery along.
  function c:watchAdminDrive()
    local a = self.adminDrive
    if not a then return end
    local h = self.hire
    if a.stage == 'asking' then
      if self.clock - a.at > M.ASK_SECONDS then
        self.mp:adminRob('stop')
        self.adminDrive, self.adminFeedback = nil, a.name .. '\'s game did not answer. Try again.'
      end
      return
    end
    if a.stage == 'back' then
      if not h then
        self.adminDrive = nil
        self.diag:event('admin_rob_back', '')
      end
      return
    end
    -- The robber's car went (the sightseeing car didn't turn up, or he got back to his car some other way).
    if not h or not h.admin then
      self.mp:adminRob('stop')
      self.adminDrive = nil
      return
    end
    if a.stage == 'leaving' then
      if h.stage ~= 'flying' then return end
      local ok = self.adapter.teleport and self.adapter:teleport(a.spot, 'Worldwide Trucking: ' .. a.name)
      if not ok then
        self.mp:adminRob('stop')
        return self:adminGoBack('BeamNG.Earth did not take the teleport.')
      end
      a.stage, a.at, a.arrivedAt = 'going', self.clock, nil
      self.adminFeedback = 'Dropping you in ahead of ' .. a.name .. '. The terrain takes a few seconds to load.'
      return
    end
    if a.stage == 'going' then
      local sample = self.lastSample
      local away = sample and sample.valid and location.distance(sample, a.spot)
      if away and away <= M.ARRIVE_METRES then
        a.arrivedAt = a.arrivedAt or self.clock
        if self.clock - a.arrivedAt < M.SETTLE_SECONDS then return end
        if a.heading and self.thiefCar then self.thiefCar:face(a.heading) end
        local vehicle = sample.vehicle
        local car = vehicle and vehicle.id ~= nil and self.mpGame and self.mpGame.serverCarId and self.mpGame.serverCarId(vehicle.id)
        self.mp:adminRob('ready', { car = car or nil })
        a.stage, a.at = 'ready', self.clock
        self.adminFeedback = nil
        self:showFlash('delivered', 'YOU ARE THE ROBBER', a.name .. ' is coming up behind you in your lane. Get within '
          .. M.STRIKE_METRES .. ' m and fire your EMP: the button here or the Fire EMP key. You have '
          .. math.floor(M.STRIKE_SECONDS / 60) .. ' minutes.')
        return
      end
      if self.clock - a.at > M.GOING_SECONDS then
        self.mp:adminRob('stop')
        self:adminGoBack('You didn\'t get there in time. Back to your car.')
      end
      return
    end
    if a.stage == 'ready' and not a.struck and self.clock - a.at > M.STRIKE_SECONDS + 30 then
      -- The player's game never said: the robbery is over anyway.
      self.mp:adminRob('stop')
      return self:adminGoBack('Time ran out. Back to your car.')
    end
    if a.stage == 'caught' then
      if self.clock - a.caughtAt >= M.CAUGHT_SECONDS then return self:adminGoBack(nil) end
      -- The car stays dead: switched off again every second in case it was started.
      if self.thiefCar and self.clock - (a.shutAt or a.caughtAt) >= 1 then
        a.shutAt = self.clock
        self.thiefCar:shutDownPlayer()
      end
    end
  end

  -- The admin's panel on the Route tab (his list), and while robbing the panel in place of the sightseeing one.
  function c:adminView()
    local targets = self:adminTargets()
    if not targets then return nil end
    local a = self.adminDrive
    local problem = self:adminDriveProblem()
    local out = { feedback = self.adminFeedback, problem = not a and problem or nil, targets = {} }
    for _, p in ipairs(targets) do
      out.targets[#out.targets + 1] = { id = p.id, name = p.name, town = p.town, doing = p.doing, allowed = problem == nil }
    end
    if a then
      out.drive = { stage = a.stage, name = a.name, struck = a.struck or nil, stopAllowed = a.stage ~= 'back' and a.stage ~= 'caught',
        secondsLeft = a.stage == 'ready' and not a.struck and math.max(0, math.ceil(M.STRIKE_SECONDS - (self.clock - a.at))) or nil,
        strikeMetres = M.STRIKE_METRES, escapeMetres = M.ESCAPE_METRES }
      if a.stage == 'ready' and not a.struck then
        local left = self:adminEmpLeft()
        -- In the shape of emp.lua's empView, for the same button; how far away only the player's game knows.
        out.drive.emp = { ready = left <= 0, chargeLeft = left > 0 and math.ceil(left) or nil,
          charged = math.floor((1 - left / emp.CHARGE_SECONDS) * 100 + 0.5), range = M.STRIKE_METRES }
      end
    end
    return out
  end

  -- ===== The robbed player's side ====================================================================================

  -- Why an admin can't rob this player now, or nil. The server only lists players for whom this is nil.
  function c:adminRobProblem()
    if not self.mp or self.mp.state ~= 'server' then return 'off' end
    if self.robber and self.robber.admin then return 'busy' end
    if self:robberProblem(false) then return 'off' end
    -- Any job, however short: the admin picks each target himself (the AI robber keeps its 5 km minimum).
    if not self.load or self.load.beacon then return 'off' end
    return nil
  end

  -- An admin wants to rob this player: the road spot ahead of their car, or why not.
  function c:answerRobAsk(ask)
    if not ask or not self.mp then return end
    local why = self:adminRobProblem()
    local sample = self.lastSample
    if not why and not (type(sample) == 'table' and sample.valid) then why = 'away' end
    local ahead
    if not why then
      local reason
      ahead, reason = self.thiefCar:aheadOffset(M.AHEAD_METRES)
      if not ahead then why = reason == 'no_ground' and 'no_ground' or 'away' end
    end
    if why then
      self.mp:robSpot({ ask = ask.ask, ok = false, why = why })
      return
    end
    local metres = math.sqrt(ahead.east * ahead.east + ahead.north * ahead.north)
    local bearing = (math.deg(math.atan2(ahead.east, ahead.north)) + 360) % 360
    local spot = location.destination(sample, bearing, metres) or location.copy(sample)
    self.mp:robSpot({ ask = ask.ask, ok = true, latitude = spot.latitude, longitude = spot.longitude, heading = ahead.heading })
    self.robAskedAt = self.clock
    self.diag:event('rob_asked', '')
  end

  -- The robbery from the server: 'go' (the admin is in place, in car), 'emp' (he fired), 'off' (he stopped or left),
  -- 'caught' (his name).
  function c:robNews(d)
    if type(d) ~= 'table' then return end
    local r = self.robber
    if d.state == 'go' then
      if type(d.car) ~= 'string' or not d.car:match('^%d+%-%d+$') or self:adminRobProblem() then
        self.mp:robNews('gone')
        return
      end
      -- An AI robber waiting for its moment goes for now; the job's own is loaded again afterwards (roadRobber.lua).
      if r and r.phase == 'loaded' then self:dropRobber('admin robber') end
      self.robber = { admin = true, phase = 'lurking', serverCar = d.car, placedAt = self.clock }
      self.diag:event('admin_robber_on', d.car)
    elseif d.state == 'off' then
      if not r or not r.admin or r.phase == 'caught' then return end
      local struck = r.phase == 'chasing'
      self:dropRobber('admin off')
      if struck then
        self:robberyNews('robber', 'escaped')
        self:showFlash('cancelled', 'THE ROBBER GOT AWAY', 'They vanished with your ' .. dollars(r.amount or 0) .. '.')
      end
    elseif d.state == 'emp' then
      -- The admin fired his EMP: it reaches within STRIKE_METRES, as this game sees his car.
      if not r or not r.admin or r.phase ~= 'lurking' then return end
      local metres = self:adminCar(r) and self.thiefCar:distance(r.carId) or nil
      r.metres = metres
      if metres and metres <= M.STRIKE_METRES then return self:adminStrikes() end
      self.mp:robNews('missed', metres and math.floor(metres + 0.5) or nil)
    elseif d.state == 'caught' then
      local name = type(d.name) == 'string' and d.name:gsub('%c', ''):sub(1, 32) or nil
      if not name or name == '' then return end
      self:showFlash('delivered', 'YOU CAUGHT ' .. name:upper() .. '!', 'The robber was ' .. name .. ' all along. You got your '
        .. dollars(M.STOLEN) .. ' back, and ' .. dollars(M.TRUNK) .. ' from their trunk.')
      self:toast('info', 'You caught ' .. name .. '!', 'The robber was ' .. name .. ' all along.', 10)
    end
  end

  -- The admin's car in this game, or nil until BeamMP has it here.
  function c:adminCar(r)
    if not r.carId and self.mpGame and self.mpGame.gameCarId then r.carId = self.mpGame.gameCarId(r.serverCar) end
    return r.carId
  end

  -- The admin's EMP reached: the engine dies for a few seconds, STOLEN is taken, and the chase is on.
  function c:adminStrikes()
    local r = self.robber
    if not self:spend(M.STOLEN, 'robber') then
      self.mp:robNews('gave_up')
      self:dropRobber('nothing to take')
      return
    end
    self.thiefCar:empPlayer()
    -- The robber's EMP drains the player's too: it charges from empty before they can fire back (emp.lua).
    self.empFiredAt = self.clock
    self:empSound()
    r.phase, r.amount, r.struckAt, r.empEndAt = 'chasing', M.STOLEN, self.clock, self.clock + roadRobber.PLAYER_EMP_SECONDS
    local text = 'A robber hit you with an EMP and took ' .. dollars(M.STOLEN) .. '. Your engine is back in '
      .. roadRobber.PLAYER_EMP_SECONDS .. ' s and your EMP is drained: it takes ' .. emp.CHARGE_SECONDS .. ' s to charge. Catch them with your EMP within ' .. emp.RANGE .. ' m to get it back, plus '
      .. dollars(M.TRUNK) .. ' from their trunk.'
    self:showFlash('cancelled', 'ROBBED ON THE ROAD: -' .. dollars(M.STOLEN), text)
    self:toast('warning', 'Robbed on the road', text, 10)
    self:autoSaveSoon('the robbery')
    self.mp:robNews('struck')
    self:robberyNews('robber', 'struck')
    self.diag:event('admin_robber_struck', '')
  end

  -- Every tick while an admin robs this player (from watchRobber).
  function c:watchAdminRobber()
    local r = self.robber
    local d = self:adminCar(r) and self.thiefCar:distance(r.carId) or nil
    -- A car id kept from before can go stale: looked up again.
    if r.carId and not d then r.carId = nil end
    r.metres = d
    if r.empEndAt and self.clock >= r.empEndAt then
      r.empEndAt = nil
      self.thiefCar:empPlayerEnd()
    end
    if r.phase == 'lurking' then
      if self.clock - r.placedAt > M.STRIKE_SECONDS or (not d and self.clock - r.placedAt > M.CAR_WAIT_SECONDS) then
        self.mp:robNews('gave_up')
        self:dropRobber('admin gave up')
        return
      end
      return
    end
    if r.phase == 'chasing' then
      r.arrow = d and self.thiefCar.bearing and self.thiefCar:bearing(r.carId) or nil
      if not d or d > M.ESCAPE_METRES then
        self.mp:robNews('escaped')
        self:dropRobber('admin escaped')
        self:robberyNews('robber', 'escaped')
        self:showFlash('cancelled', 'THE ROBBER GOT AWAY', 'They got ' .. M.ESCAPE_METRES .. ' m clear of you and escaped with your '
          .. dollars(r.amount or 0) .. '.')
      end
      return
    end
    if r.phase == 'caught' and self.clock - r.caughtAt > M.CAUGHT_SECONDS then self:dropRobber('admin caught') end
  end
end

return M
