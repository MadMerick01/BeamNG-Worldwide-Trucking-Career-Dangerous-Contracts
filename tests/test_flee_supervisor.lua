local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local S = require('earthFreight/fleeSupervisor')
local thiefCar = require('earthFreight/thiefCar')

local function vec(x, y, z) return { x = x, y = y, z = z or 0 } end

-- Every command sent to the car must be Lua the car can run.
local function compiles(cmd) return (load or loadstring)(cmd) ~= nil end

-- A world: the thief (id 9) heading north at speed, the player (id 1), and traffic cars set by the test.
local function world()
  local w = { sent = {}, traffic = {}, amount = 20, setTo = {} }
  w.thief = { pos = vec(0, 0, 0), dir = vec(0, 1, 0), vel = vec(0, 20, 0) }
  local thiefObj = {
    getPosition = function() return w.thief.pos end,
    getDirectionVector = function() return w.thief.dir end,
    getVelocity = function() return w.thief.vel end,
    queueLuaCommand = function(_, c) w.sent[#w.sent + 1] = c end,
  }
  w.env = {
    objectById = function(id) if id == 9 and not w.gone then return thiefObj end end,
    traffic = function()
      local list, data = {}, {}
      for id, car in pairs(w.traffic) do list[#list + 1] = id; data[id] = { pos = car.pos, vel = car.vel } end
      return list, data
    end,
    trafficAmount = function() return w.amount end,
    setTrafficAmount = function(n) w.setTo[#w.setTo + 1] = n; w.amount = n; return true end,
  }
  w.s = S.new(w.env)
  return w
end

local function run(w, seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do w.s:update(1 / 60) end
end

local function last(w) return w.sent[#w.sent] end

-- The commands: valid Lua, a real speed cap, the lane setting.
do
  for state in pairs(S.PROFILES) do T.check(compiles(S.profileCommand(state)), state .. ' command is valid Lua') end
  T.check(compiles(S.rerouteCommand(1)), 'replan command is valid Lua')
  T.check(compiles(thiefCar.fleeCommand(1)), 'flee command is valid Lua')
  local free = S.profileCommand('FreeFlow')
  T.check(free:find("ai.setSpeedMode, 'limit'", 1, true), 'caps the speed')
  T.check(free:find('ai.setSpeed, 20.833', 1, true), '75 km/h in metres a second')
  T.check(free:find("ai.driveInLane, 'off'", 1, true), 'any lane in free flow')
  T.check(S.profileCommand('HeavyRisk'):find("ai.driveInLane, 'on'", 1, true), 'own lane in heavy traffic')
  T.check(S.profileCommand('EmergencyAvoid'):find('ai.setSpeed, 8.333', 1, true), '30 km/h in an emergency')
end

-- The risk sums and the choice of way to drive.
do
  T.eq(S.risk({}), 0, 'nothing ahead, no risk')
  T.eq(S.risk({ queueCount = 5, closingKph = 80, nearestLeadDist = 0, laneBlockedPenalty = 1 }), 1,
    'a packed queue alone is the top of the scale')
  T.near(S.risk({ queueCount = 1, closingKph = 30, nearestLeadDist = 30 }), 0.2364, 1e-3, 'one car well ahead is little')
  T.near(S.risk({ pitchDeg = 15, yawRateDegPerSec = 35 }), 0.3, 1e-9, 'steep and tight adds up to 0.3')
  T.eq(S.chooseState(0.5, 'FreeFlow', 0), 'ModerateRisk', 'free flow goes straight up')
  T.eq(S.chooseState(0.95, 'FreeFlow', 0), 'EmergencyAvoid', 'or straight to emergency')
  T.eq(S.chooseState(0.1, 'HeavyRisk', 0.2), 'HeavyRisk', 'held at least 0.75 s')
  T.eq(S.chooseState(0.6, 'HeavyRisk', 2), 'HeavyRisk', 'between exit and enter it stays')
  T.eq(S.chooseState(0.5, 'HeavyRisk', 2), 'ModerateRisk', 'then eases off one step')
  T.eq(S.chooseState(0.1, 'EmergencyAvoid', 2), 'HeavyRisk', 'one step at a time')
end

-- An open road: free flow, traffic halved while it runs and back after.
do
  local w = world()
  T.check(w.s:register(9, 1), 'registered')
  T.eq(w.setTo[1], 10, 'traffic halved')
  T.check(last(w):find("'off'", 1, true), 'told to drive free')
  run(w, 3)
  T.eq(w.s:status(9).state, 'FreeFlow', 'open road, free flow')
  local sent = #w.sent
  run(w, 3)
  T.eq(#w.sent, sent, 'nothing re-sent while nothing changes')
  -- A car behind, or off to the side, or the player chasing, is not in the way.
  w.traffic[20] = { pos = vec(0, -20), vel = vec(0, 20) }
  w.traffic[21] = { pos = vec(10, 30), vel = vec(0, 0) }
  w.traffic[1] = { pos = vec(0, 10), vel = vec(0, 0) }
  run(w, 3)
  T.eq(w.s:status(9).queueCount, 0, 'only cars in the corridor ahead count')
  T.check(w.s:unregister(9), 'unregistered')
  T.eq(w.amount, 20, 'traffic back')
  T.eq(w.s:status(9), nil, 'no longer watched')
end

-- A queue of stopped cars ahead: it slows down step by step, keeps to its lane, and replans when it stays stuck.
do
  local w = world()
  w.s:register(9, 1)
  for i = 1, 5 do w.traffic[100 + i] = { pos = vec(1, 8 * i), vel = vec(0, 0) } end
  run(w, 0.5)
  local st = w.s:status(9)
  T.eq(st.queueCount, 5, 'five cars queued ahead'); T.near(st.leadMetres, 8, 1e-9, 'the nearest 8 m ahead')
  T.near(st.closingKph, 72, 1e-6, 'closing at 72 km/h')
  run(w, 4)
  T.check(w.s:status(9).state == 'HeavyRisk' or w.s:status(9).state == 'EmergencyAvoid', 'slowed right down')
  local found
  for _, c in ipairs(w.sent) do if c:find("'on'", 1, true) then found = true end end
  T.check(found, 'kept to its lane')
  local replans = 0
  for _, c in ipairs(w.sent) do if c:find("ai.setMode, 'flee'", 1, true) then replans = replans + 1 end end
  T.check(replans >= 1, 'replanned its escape')
  T.check(replans <= 2, 'but not more than every 3 s')
  T.check(last(w):find('setSpeed', 1, true), 'and drives the careful way again after a replan')
  -- The queue clears: back up to free flow, one step at a time.
  w.traffic = {}
  local seen = {}
  for _ = 1, 600 do w.s:update(1 / 60); seen[w.s:status(9).state] = true end
  T.eq(w.s:status(9).state, 'FreeFlow', 'free flow once clear')
  T.check(seen.ModerateRisk, 'by way of moderate')
end

-- Turning: measured over the time between looks, so a gentle bend isn't a hazard.
do
  local w = world()
  w.s:register(9, 1)
  local angle = 0
  for _ = 1, 240 do
    angle = angle + math.rad(10) / 60
    w.thief.dir = vec(math.sin(angle), math.cos(angle))
    w.s:update(1 / 60)
  end
  T.eq(w.s:status(9).state, 'FreeFlow', 'a 10 degree a second bend on an open road is fine')
end

-- The car disappearing stops the watching and gives the traffic back.
do
  local w = world()
  w.s:register(9, 1)
  w.gone = true
  run(w, 0.5)
  T.eq(w.s:status(9), nil, 'gone')
  T.eq(w.amount, 20, 'traffic back')
end

-- No traffic system: nothing breaks.
do
  local s = S.new({ objectById = function() return nil end, traffic = function() error('none') end,
    trafficAmount = function() return nil end, setTrafficAmount = function() return false end })
  s:register(5, 1)
  s:update(0.5)
  T.eq(s:status(5), nil, 'no car, not watched')
end

-- The thief's car hands the flee to the supervisor, and takes it back for the EMP and on removal.
do
  local calls = {}
  local sup = { register = function(_, id, tid) calls[#calls + 1] = 'register ' .. id .. ' ' .. tid end,
    unregister = function(_, id) calls[#calls + 1] = 'unregister ' .. id end,
    update = function(_, dt) calls[#calls + 1] = 'update' end }
  local thiefObj = { getID = function() return 9 end, getPosition = function() return vec(3, 4) end,
    queueLuaCommand = function() end, delete = function() end }
  local player = { getID = function() return 1 end, getPosition = function() return vec(0, 0) end,
    getDirectionVector = function() return vec(0, 1) end }
  local t = thiefCar.new({ vehicle = function() return player end, objectById = function() return thiefObj end,
    emp = function() return nil end, bolidesRunning = function() return false end, supervisor = sup })
  t:flee(9); t:update(0.1); t:emp(9); t:remove(9)
  T.eq(table.concat(calls, ', '), 'register 9 1, update, unregister 9, unregister 9', 'flee, watch, EMP, remove')
end

T.done('flee supervisor')
