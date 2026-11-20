-- Keeps the base thief (thiefCar.lua) from ploughing into traffic while it flees. Copied from MadMerick's
-- RobberFleeSupervisor in Bolides – The Cut, so it works without that mod installed.
--
-- Eight times a second it looks down a corridor ahead of the thief (55 m, plus 0.7 m for every km/h, up to 120 m,
-- 4.2 m either side of its line) for traffic: how many cars are queued in it, how close the nearest is and how fast
-- the thief is closing on it. It adds how steep the road is and how hard the thief is turning, and from that picks
-- one of four ways to drive, each with a top speed, an aggression and whether to keep to its lane:
--   FreeFlow 75 km/h, 0.28, any lane; ModerateRisk 62 km/h, 0.20, any lane;
--   HeavyRisk 45 km/h, 0.12, own lane; EmergencyAvoid 30 km/h, 0.05, own lane.
-- Each way has an enter and a lower exit level, and is held at least 0.75 s, so it doesn't flicker between two.
-- Stuck behind a queue of 3 or more for 2.5 s in HeavyRisk or worse, it plans its escape again (at most every 3 s).
-- While a thief is out the game's traffic is halved, and it comes back when the last one is gone.
--
-- Changes from the Bolides copy: the command sent to the car was not valid Lua there (it opened with "[[]"), so
-- it never reached the car; the top speed now uses the AI's 'limit' speed mode and setSpeed, which exist (there is no
-- ai.setMaxSpeedKph, and 'legal' mode would ignore the cap); the turn rate is measured over the time between looks,
-- not one frame, which made every bend look eight times sharper; traffic alone can now reach every way of driving
-- (see M.risk); and the replan is acted on here, since Bolides left
-- it to its escape planner. Pure Lua with numbers, so it can be tested; the game is reached through env.
local M = {}

M.CONFIG = {
  evalHz = 8,
  corridorBase = 55,
  corridorSpeedGain = 0.7,
  corridorMax = 120,
  corridorHalfWidth = 4.2,
  moderateEnter = 0.42, moderateExit = 0.32,
  heavyEnter = 0.70, heavyExit = 0.56,
  emergencyEnter = 0.90, emergencyExit = 0.78,
  minStateDwell = 0.75,
  smoothingAlpha = 0.35,
  rerouteHeavyMinTime = 2.5,
  rerouteCooldown = 3.0,
  rerouteMinQueue = 3,
  trafficShare = 0.5,
}

M.PROFILES = {
  FreeFlow = { maxSpeedKph = 75, aggression = 0.28, driveInLane = 'off' },
  ModerateRisk = { maxSpeedKph = 62, aggression = 0.20, driveInLane = 'off' },
  HeavyRisk = { maxSpeedKph = 45, aggression = 0.12, driveInLane = 'on' },
  EmergencyAvoid = { maxSpeedKph = 30, aggression = 0.05, driveInLane = 'on' },
}

local cfg = M.CONFIG

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

-- What the car runs to drive the way state says.
function M.profileCommand(state)
  local p = M.PROFILES[state] or M.PROFILES.FreeFlow
  return string.format([[
if not ai then return end
local function try(f, ...) if type(f) == 'function' then pcall(f, ...) end end
try(ai.setSpeedMode, 'limit')
try(ai.setSpeed, %.3f)
try(ai.setAggression, %.2f)
try(ai.driveInLane, '%s')
]], p.maxSpeedKph / 3.6, p.aggression, p.driveInLane)
end

-- What the car runs to plan its escape again from where it is, still fleeing the player's car (id tid).
function M.rerouteCommand(tid)
  return string.format([[
if not ai then return end
local function try(f, ...) if type(f) == 'function' then pcall(f, ...) end end
try(ai.setMode, 'flee')
try(ai.setTargetObjectID, %d)
]], tid or -1)
end

-- How risky the road ahead is, 0 to 1, from what was seen; with the traffic and the terrain parts.
function M.risk(obs)
  local queueNorm = clamp01((obs.queueCount or 0) / 5)
  local closeNorm = clamp01((obs.closingKph or 0) / 80)
  local nearNorm = 1 - clamp01((obs.nearestLeadDist or 200) / 40)
  local lanePenalty = clamp01(obs.laneBlockedPenalty or 0)
  local pitchNorm = clamp01(math.abs(obs.pitchDeg or 0) / 15)
  local cornerNorm = clamp01((obs.yawRateDegPerSec or 0) / 35)
  local congestion = queueNorm * 0.40 + closeNorm * 0.25 + nearNorm * 0.25 + lanePenalty * 0.10
  local terrain = clamp01(pitchNorm * 0.55 + cornerNorm * 0.45)
  -- Bolides weighs traffic 0.70 and terrain 0.30, so traffic alone tops out at exactly 0.70, the HeavyRisk line, and
  -- the careful ways never come on for traffic on a flat straight road. Here traffic counts in full and terrain adds.
  return clamp01(congestion + terrain * 0.30), congestion, terrain
end

-- The next way to drive, from the smoothed risk, the current way and how long it has been held.
function M.chooseState(risk, cur, held)
  local settled = held >= cfg.minStateDwell
  if cur == 'EmergencyAvoid' then
    return (risk <= cfg.emergencyExit and settled) and 'HeavyRisk' or cur
  elseif cur == 'HeavyRisk' then
    if risk >= cfg.emergencyEnter and settled then return 'EmergencyAvoid' end
    if risk <= cfg.heavyExit and settled then return 'ModerateRisk' end
    return cur
  elseif cur == 'ModerateRisk' then
    if risk >= cfg.emergencyEnter and settled then return 'EmergencyAvoid' end
    if risk >= cfg.heavyEnter and settled then return 'HeavyRisk' end
    if risk <= cfg.moderateExit and settled then return 'FreeFlow' end
    return cur
  end
  if risk >= cfg.emergencyEnter then return 'EmergencyAvoid' end
  if risk >= cfg.heavyEnter then return 'HeavyRisk' end
  if risk >= cfg.moderateEnter then return 'ModerateRisk' end
  return 'FreeFlow'
end

local function defaults()
  local function traffic() return rawget(_G, 'gameplay_traffic') end
  return {
    objectById = function(id) return getObjectByID(id) end,
    -- The game's traffic: the cars' ids, and where they are and how fast they go when the game says.
    traffic = function()
      local g = traffic()
      if type(g) ~= 'table' then return {}, {} end
      local okL, list = pcall(function() return g.getTrafficList and g.getTrafficList() end)
      local okD, data = pcall(function() return g.getTrafficData and g.getTrafficData() end)
      return (okL and type(list) == 'table') and list or {}, (okD and type(data) == 'table') and data or {}
    end,
    trafficAmount = function()
      local g = traffic()
      if type(g) ~= 'table' then return nil end
      for _, name in ipairs({ 'getTrafficAmount', 'getNumOfTraffic' }) do
        if type(g[name]) == 'function' then
          local ok, v = pcall(g[name])
          if ok and type(v) == 'number' then return v end
        end
      end
      return nil
    end,
    setTrafficAmount = function(n)
      local g = traffic()
      if type(g) ~= 'table' or type(g.setActiveAmount) ~= 'function' then return false end
      return pcall(g.setActiveAmount, n) == true
    end,
  }
end

function M.new(env)
  env = env or defaults()
  local s = { robbers = {}, clock = 0, trafficBefore = nil }

  local function call(obj, name)
    if not obj or type(obj[name]) ~= 'function' then return nil end
    local ok, v = pcall(obj[name], obj)
    return ok and v or nil
  end

  local function object(id)
    if type(id) ~= 'number' then return nil end
    local ok, v = pcall(env.objectById, id)
    return ok and v or nil
  end

  local function send(obj, cmd)
    pcall(function() obj:queueLuaCommand(cmd) end)
  end

  local function count()
    local n = 0
    for _ in pairs(s.robbers) do n = n + 1 end
    return n
  end

  -- Half the traffic while a thief is out.
  local function thinTraffic()
    if s.trafficBefore then return end
    local ok, before = pcall(env.trafficAmount)
    if not ok or type(before) ~= 'number' then return end
    before = math.max(0, math.floor(before + 0.5))
    if env.setTrafficAmount(math.ceil(before * cfg.trafficShare)) then s.trafficBefore = before end
  end

  local function restoreTraffic()
    if not s.trafficBefore or count() > 0 then return end
    pcall(env.setTrafficAmount, s.trafficBefore)
    s.trafficBefore = nil
  end

  -- Starts watching the car (id) fleeing from the player's car (targetId).
  function s:register(id, targetId)
    if type(id) ~= 'number' then return false end
    self.robbers[id] = { id = id, targetId = targetId, state = 'FreeFlow', since = self.clock, heavySince = nil,
      nextEval = 0, nextReroute = 0, risk = 0, congestion = 0, terrain = 0, obs = {} }
    thinTraffic()
    local car = object(id)
    if car then send(car, M.profileCommand('FreeFlow')) end
    return true
  end

  -- Stops watching it (caught, escaped or gone), so nothing more is sent to the car.
  function s:unregister(id)
    if not self.robbers[id] then return false end
    self.robbers[id] = nil
    restoreTraffic()
    return true
  end

  -- How the car is driving now, or nil when it isn't watched.
  function s:status(id)
    local r = self.robbers[id]
    if not r then return nil end
    return { state = r.state, risk = r.risk, congestion = r.congestion, terrain = r.terrain,
      queueCount = r.obs.queueCount, leadMetres = r.obs.nearestLeadDist, closingKph = r.obs.closingKph }
  end

  local function evaluate(r, list, data)
    local car = object(r.id)
    if not car then s:unregister(r.id) return end
    local pos, dir, vel = call(car, 'getPosition'), call(car, 'getDirectionVector'), call(car, 'getVelocity')
    if not pos or not dir then return end
    vel = vel or { x = 0, y = 0, z = 0 }
    local fx, fy = dir.x, dir.y
    local size = math.sqrt(fx * fx + fy * fy)
    if size < 1e-6 then fx, fy = 0, 1 else fx, fy = fx / size, fy / size end
    local kph = math.sqrt(vel.x * vel.x + vel.y * vel.y + (vel.z or 0) * (vel.z or 0)) * 3.6
    local corridor = math.min(cfg.corridorMax, cfg.corridorBase + kph * cfg.corridorSpeedGain)
    local myForward = vel.x * fx + vel.y * fy
    local nearest, queue, slow, closing = nil, 0, 0, 0

    for _, tid in ipairs(list) do
      if tid ~= r.id and tid ~= r.targetId then
        local row = data[tid]
        local tp, tv = row and row.pos, row and row.vel
        if not tp then
          local other = object(tid)
          tp, tv = call(other, 'getPosition'), tv or call(other, 'getVelocity')
        end
        if tp then
          local rx, ry = tp.x - pos.x, tp.y - pos.y
          local ahead = rx * fx + ry * fy
          if ahead > 0 and ahead <= corridor and math.abs(rx * fy - ry * fx) <= cfg.corridorHalfWidth then
            queue = queue + 1
            tv = tv or { x = 0, y = 0, z = 0 }
            if not nearest or ahead < nearest then
              nearest = ahead
              closing = math.max(0, myForward - (tv.x * fx + tv.y * fy)) * 3.6
            end
            if math.sqrt(tv.x * tv.x + tv.y * tv.y + (tv.z or 0) * (tv.z or 0)) < 3 then slow = slow + 1 end
          end
        end
      end
    end

    local pitch = math.deg(math.asin(math.max(-1, math.min(1, dir.z or 0))))
    -- How fast it is turning, in degrees a second, since the last look.
    local yawRate = 0
    if r.prevDir and r.lastEval and s.clock > r.lastEval then
      local px, py = r.prevDir.x, r.prevDir.y
      local plen = math.sqrt(px * px + py * py)
      if plen > 1e-6 then
        local dot = math.max(-1, math.min(1, (px * fx + py * fy) / plen))
        yawRate = math.deg(math.acos(dot)) / (s.clock - r.lastEval)
      end
    end
    r.prevDir = { x = fx, y = fy }

    local lane = 0
    if queue >= 3 then lane = 0.6 end
    if slow >= 2 then lane = math.min(1, lane + 0.2) end
    r.obs = { queueCount = queue, slowCount = slow, nearestLeadDist = nearest, closingKph = closing,
      laneBlockedPenalty = lane, pitchDeg = pitch, yawRateDegPerSec = yawRate }

    local risk, congestion, terrain = M.risk(r.obs)
    local a = cfg.smoothingAlpha
    r.risk = r.risk * (1 - a) + risk * a
    r.congestion = r.congestion * (1 - a) + congestion * a
    r.terrain = r.terrain * (1 - a) + terrain * a

    local nextState = M.chooseState(r.risk, r.state, s.clock - r.since)
    if nextState ~= r.state then
      r.state, r.since = nextState, s.clock
      if nextState == 'HeavyRisk' or nextState == 'EmergencyAvoid' then
        r.heavySince = r.heavySince or s.clock
      else
        r.heavySince = nil
      end
      send(car, M.profileCommand(nextState))
    end

    -- Stuck in a queue: plan the escape again, then drive the way it was.
    if r.heavySince and s.clock - r.heavySince >= cfg.rerouteHeavyMinTime and s.clock >= r.nextReroute
      and queue >= cfg.rerouteMinQueue then
      r.nextReroute = s.clock + cfg.rerouteCooldown
      r.reroutes = (r.reroutes or 0) + 1
      send(car, M.rerouteCommand(r.targetId))
      send(car, M.profileCommand(r.state))
    end

    r.lastEval = s.clock
    r.nextEval = s.clock + 1 / cfg.evalHz
  end

  -- Every frame.
  function s:update(dt)
    if next(self.robbers) == nil then return end
    self.clock = self.clock + (dt or 0)
    local list, data
    for id, r in pairs(self.robbers) do
      if self.clock >= r.nextEval then
        if not list then
          local ok, l, d = pcall(env.traffic)
          list, data = ok and type(l) == 'table' and l or {}, ok and type(d) == 'table' and d or {}
        end
        evaluate(r, list, data)
      end
    end
  end

  return s
end

return M
