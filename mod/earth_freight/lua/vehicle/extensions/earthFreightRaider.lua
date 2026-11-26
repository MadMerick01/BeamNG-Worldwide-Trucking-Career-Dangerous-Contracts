-- earthFreightRaider: the Raiders' driver on the special delivery, run inside a Raider's car. Copied from MadMerick's
-- Tanker mod (its tankerDriver.lua), where the same driver runs the Hoons. Off road, the game sends it a
-- point to drive at and a speed, a few times a second (target below). On the roads it hunts a
-- car by itself (chase below, and road mode further down): it catches up along the roads,
-- overtakes, cuts in front and brake-checks; every frame it works out steering,
-- throttle and brake itself and drives the car with them, the way BeamNG's AI does. It takes over
-- from BeamNG's AI while it drives (the AI is switched off) and hands back on stop().
--
-- Its limits come from MadMerick's logged driving (BeamngAdvancedSelfDriving, smartAI's
-- moonhawk_country profile): about 0.9 g cornering, 0.65 g braking and 0.45 g accelerating, all
-- capped by the grip of the ground under the car.
--
-- Steering is pure pursuit: the arc from the car to the point gives a curvature, and the wheelbase
-- turns that into a wheel angle, with yaw-rate damping so it doesn't weave. Speed is the asked-for
-- speed, capped by what the arc allows at the cornering limit. If the car pushes for a while
-- without moving it backs off and tries again, as smartAI does.
--
-- The maths (M.control) uses no game calls, so it can be tested outside the game.
local M = {}

-- One-line settings. Tune these after testing in game.
local G = 9.81
-- Cornering, braking and accelerating limits, in g (MadMerick's country driving).
M.LAT_G, M.BRAKE_G, M.ACCEL_G = 0.9, 0.65, 0.45
-- The front wheels' full lock, in radians, used to turn a wheel angle into a steering input.
M.STEER_LOCK = 0.6
-- How fast the steering input may move, per second (a person turns the wheel, they don't flick it).
M.STEER_RATE = 2.5
-- Yaw-rate damping: steering taken off per radian a second of turning more than the arc needs.
M.YAW_DAMP = 0.15
-- The speed controller: how quickly it closes a speed gap (seconds), and pedal gains per m/s².
M.SPEED_TAU = 0.8
-- Wheel speed above the car's speed by more than this share (plus 2 m/s) is wheelspin: ease off.
M.SPIN_SHARE = 0.25
-- Pushing for STUCK_SECONDS at under 1 m/s, it reverses (steering the other way) for
-- BACK_SECONDS; after STUCK_TRIES of those it rests REST_SECONDS and starts again: a Raider never
-- gives up while it can still drive (MadMerick, 6 Nov).
M.STUCK_SECONDS, M.BACK_SECONDS, M.STUCK_TRIES, M.REST_SECONDS = 2.5, 2.5, 4, 3
-- With no new point for this long, it brakes to a stop.
M.STALE_SECONDS = 0.6
-- Asked for up to this much below its speed, it lifts off instead of braking, in m/s.
M.COAST_MPS = 3
-- A point behind the car is turned towards at this speed at most, in m/s.
M.TURN_MPS = 6
-- Steering round solid bushes, rocks and trees (MadMerick, 6 Nov). Five feelers: straight ahead,
-- FEEL_ANGLE radians either side, and two straight ahead along the car's edges (EDGE_METRES out
-- from its middle) so it doesn't squeeze into a gap narrower than itself. They look FEEL_SECONDS
-- of its speed ahead (FEEL_MIN to FEEL_MAX metres) every FEEL_EVERY seconds, starting
-- FEEL_HEIGHT above the car's middle, and follow the ground: each one aims at the same height
-- above the ground at its far end as it starts at, so going uphill it doesn't hit the slope
-- early, and over a crest it doesn't pass over the bushes beyond. A hit only counts when whatever
-- was hit stands more than FEEL_TALL metres above where the feeler touched it, so a hillside
-- doesn't count and a bush does. The nearer the hit, the harder it steers away, up to AVOID_GAIN
-- of full lock, towards the clearer side. Once it picks a side it keeps to it for
-- COMMIT_SECONDS, unless that side is worse by more than SWITCH_MARGIN, so it doesn't weave
-- between clumps. Something straight ahead (or on both edges) in the nearest FEEL_SLOW share of
-- the look also holds its speed to AVOID_MPS (lifting off, never braking in the desert). A swipe
-- holds its line.
M.FEEL_ANGLE, M.FEEL_SECONDS, M.FEEL_MIN, M.FEEL_MAX, M.FEEL_EVERY = 0.35, 1.2, 8, 30, 0.1
M.FEEL_HEIGHT, M.FEEL_TALL, M.EDGE_METRES = 0.3, 0.3, 1.1
M.AVOID_GAIN, M.FEEL_SLOW, M.AVOID_MPS = 0.8, 0.4, 10
M.COMMIT_SECONDS, M.SWITCH_MARGIN = 1, 0.3
M.FEEL_SEGMENTS = 3

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- Which way to steer round what the feelers found. feel is { left, centre, right, edgeLeft,
-- edgeRight, look }: metres to something solid on each feeler (nil when clear) and how far they
-- looked. side is where the point it is driving at is (positive: to its right). keep is the side
-- it chose a moment ago (1 right, -1 left) or nil. Returns a steering nudge (positive: right),
-- whether to hold its speed down, and the side it chose.
function M.avoid(feel, side, keep)
  local look = feel and feel.look
  if not look or look <= 0 then return 0, false end
  local function near(d) return d and clamp(1 - d / look, 0, 1) or 0 end
  local c = near(feel.centre)
  local el, er = near(feel.edgeLeft), near(feel.edgeRight)
  local l, r = math.max(near(feel.left), el), math.max(near(feel.right), er)
  local worst = math.max(l, c, r)
  if worst <= 0 then return 0, false end
  -- l is how blocked the left is: steer right (1) away from it, and the other way round.
  local dir
  if l > r then dir = 1 elseif r > l then dir = -1 else dir = (side or 0) >= 0 and 1 or -1 end
  if keep and keep ~= dir then
    local towardKeep = keep > 0 and r or l
    local towardDir = dir > 0 and r or l
    if towardKeep - towardDir < M.SWITCH_MARGIN then dir = keep end
  end
  local slow = c >= 1 - M.FEEL_SLOW or (el >= 1 - M.FEEL_SLOW and er >= 1 - M.FEEL_SLOW)
  return dir * M.AVOID_GAIN * worst, slow, dir
end

-- The driver's memory between frames.
function M.newState()
  return { steer = 0, pushing = 0, backing = 0, tries = 0, age = math.huge }
end

-- One frame. s is the state, car what the car senses now:
--   x, y (centre), fx, fy (facing, unit), rx, ry (right, unit), speed (m/s, forward positive),
--   yawRate (rad/s, right turn positive), wheelSpeed (m/s), mu (ground grip), wheelBase (m)
-- s.target is { x, y, speed, mode }. mode 'coast' never brakes (MadMerick, 6 Nov): it lifts off
-- instead, so a desert Raider never drops back on the brakes. mode 'swipe' never brakes either and
-- turns in as hard as it asks, without slowing for the arc. Returns steering (-1 left .. 1 right), throttle, brake and
-- parking brake (0 .. 1). In BeamNG's arcade gearbox the brake held at a standstill drives
-- backwards, so holding still uses the parking brake instead.
function M.control(s, car, dt)
  s.age = s.age + dt
  local t = s.target
  if not t or s.age > M.STALE_SECONDS then
    s.steer = s.steer + clamp(-s.steer, -M.STEER_RATE * dt, M.STEER_RATE * dt)
    if car.speed > 0.5 then return s.steer, 0, 0.5, 0 end
    return s.steer, 0, 0, 1
  end
  local mu = clamp(car.mu or 1, 0.2, 1.5)
  local dx, dy = t.x - car.x, t.y - car.y
  local side = dx * car.rx + dy * car.ry
  local ahead = dx * car.fx + dy * car.fy
  local dist2 = math.max(1, side * side + ahead * ahead)

  -- Pure pursuit: the curvature of the arc through the point, then a wheel angle for it.
  local curvature = 2 * side / dist2
  local want = math.atan(car.wheelBase * curvature) / M.STEER_LOCK
  local speedCap = math.huge
  if ahead < 0 then
    -- Behind: full lock towards it, slowly.
    want = side >= 0 and 1 or -1
    speedCap = M.TURN_MPS
  elseif t.mode == 'swipe' then
    speedCap = math.huge
  else
    speedCap = math.sqrt(M.LAT_G * math.min(1, mu) * G / math.max(math.abs(curvature), 1e-4))
  end
  -- Turning faster than the arc needs: take some steering off.
  local yawWanted = car.speed * curvature
  want = want - M.YAW_DAMP * ((car.yawRate or 0) - yawWanted)
  -- Round a bush, rock or tree the feelers found.
  s.keepFor = (s.keepFor or 0) - dt
  if s.keepFor <= 0 then s.keep = nil end
  if s.feel and t.mode ~= 'swipe' then
    local nudge, slow, dir = M.avoid(s.feel, side, s.keep)
    if dir then
      if dir ~= s.keep then s.keep = dir end
      s.keepFor = M.COMMIT_SECONDS
    end
    want = want + nudge
    if slow then speedCap = math.min(speedCap, M.AVOID_MPS) end
  end

  -- Stuck: pushing without moving; reverse for a bit, steering the other way.
  local reverse = false
  if s.backing > 0 then
    s.backing = s.backing - dt
    reverse = true
    want = -want
  elseif s.tries < M.STUCK_TRIES and s.lastThrottle and s.lastThrottle > 0.3 and math.abs(car.speed) < 1 then
    s.pushing = s.pushing + dt
    if s.pushing >= M.STUCK_SECONDS then
      s.pushing, s.backing, s.tries = 0, M.BACK_SECONDS, s.tries + 1
      s.stuckEvent = s.tries
    end
  else
    s.pushing = 0
    if math.abs(car.speed) > 3 then s.tries = 0 end
  end

  want = clamp(want, -1, 1)
  s.steer = s.steer + clamp(want - s.steer, -M.STEER_RATE * dt, M.STEER_RATE * dt)

  if reverse then
    -- In BeamNG's arcade gearbox, brake when stopped drives backwards.
    s.lastThrottle = 0
    return s.steer, 0, 0.4 + 0.15 * s.tries, 0
  end
  if s.tries >= M.STUCK_TRIES and math.abs(car.speed) < 1 then
    s.resting = (s.resting or 0) + dt
    if s.resting < M.REST_SECONDS then
      s.lastThrottle = 0
      return s.steer, 0, 0, 1
    end
    s.resting, s.tries, s.pushing = 0, 0, 0
  end

  local speed = math.max(0, math.min(t.speed or 0, speedCap))
  local accel = clamp((speed - car.speed) / M.SPEED_TAU, -M.BRAKE_G * mu * G, M.ACCEL_G * mu * G)
  local throttle, brake = 0, 0
  if speed < 0.5 and car.speed < 0.5 then
    s.lastThrottle = 0
    return s.steer, 0, 0, 1
  elseif accel >= 0 then
    throttle = clamp(accel / (M.ACCEL_G * G), 0, 1)
    -- A little throttle to hold speed against drag and the slope.
    if speed > 1 then throttle = math.max(throttle, 0.15) end
    if car.wheelSpeed and car.wheelSpeed > car.speed * (1 + M.SPIN_SHARE) + 2 then throttle = throttle * 0.5 end
  elseif car.speed - speed > M.COAST_MPS and t.mode ~= 'coast' and t.mode ~= 'swipe' then
    brake = clamp(-accel / (M.BRAKE_G * G), 0, 1)
  end
  s.lastThrottle = throttle
  return s.steer, throttle, brake, 0
end

-- ------------------------------------------------------------ road mode ---
-- Chasing you on the roads, like BeamNG's chase mode: a route along the road map to you, driven
-- with a speed plan from MadMerick's country limits, then a ram once it is close. The road maths is
-- here; the route itself comes from the game's road map (in the car, below).

-- MadMerick's country cornering limit by speed (smartAI moonhawk_country): {km/h, g}.
M.LAT_TABLE = { { 0, 0.9 }, { 40, 0.95 }, { 200, 0.95 } }
-- How far along the route it aims: LOOK_SECONDS of its speed, between LOOK_MIN and LOOK_MAX m.
M.LOOK_SECONDS, M.LOOK_MIN, M.LOOK_MAX = 0.8, 6, 30
-- The road attack (MadMerick, 6 Nov): no ramming. Further than ENGAGE_METRES it catches up along the
-- route. Closer, it overtakes in the lane PASS_SIDE metres to your right (Australia drives on the
-- left), PASS_MPS faster than you; once CUT_AHEAD metres clear of your front it cuts in front of
-- you, settles for SETTLE_SECONDS, then brake-checks: down to BRAKE_SHARE of your speed for
-- BRAKE_SECONDS. It drives on ahead for RECOVER_SECONDS and does it again, or overtakes again if
-- you got past. If you stop (under STOPPED_MPS), it parks BLOCK_AHEAD metres in front of you.
-- Further than LOSE_METRES, it goes back to catching up.
M.ENGAGE_METRES, M.LOSE_METRES = 50, 80
M.PASS_SIDE, M.PASS_MPS, M.PASS_LOOK = 3.5, 8, 15
M.CUT_AHEAD, M.SETTLE_SECONDS, M.IN_LANE = 10, 1, 1.5
M.BRAKE_SHARE, M.BRAKE_SECONDS, M.RECOVER_SECONDS = 0.2, 1.5, 4
M.STOPPED_MPS, M.BLOCK_AHEAD = 2, 6
-- Catching up with no route, it aims this far behind you, up to CATCH_MPS faster than you.
M.FOLLOW_BEHIND, M.CATCH_MPS = 15, 15
-- How often the route is worked out again, in seconds.
M.ROUTE_SECONDS = 0.5
-- The speed to plan for at the end of the route, where you are: your speed plus a little.
M.END_EXTRA_MPS = 5

-- The cornering limit at this speed, in g.
function M.latG(speed)
  local kmh, t = speed * 3.6, M.LAT_TABLE
  if kmh <= t[1][1] then return t[1][2] end
  for i = 2, #t do
    if kmh <= t[i][1] then
      local a, b = t[i - 1], t[i]
      return a[2] + (b[2] - a[2]) * (kmh - a[1]) / (b[1] - a[1])
    end
  end
  return t[#t][2]
end

-- The curvature (1 / radius) of the circle through three points on the ground.
function M.curvature(a, b, c)
  local abx, aby, bcx, bcy = b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y
  local cax, cay = a.x - c.x, a.y - c.y
  local d = math.sqrt((abx * abx + aby * aby) * (bcx * bcx + bcy * bcy) * (cax * cax + cay * cay))
  if d < 1e-9 then return 0 end
  return math.abs(2 * (abx * bcy - aby * bcx) / d)
end

-- The fastest it can take each point of a route: the corner there at the speed-dependent
-- cornering limit, and no faster than it can brake from to make the corners after it. endSpeed
-- is the speed at the last point. mu is the ground's grip.
function M.speedPlan(points, mu, endSpeed)
  local n, speeds = #points, {}
  mu = math.min(1, mu or 1)
  for i = 1, n do
    local k = (i > 1 and i < n) and M.curvature(points[i - 1], points[i], points[i + 1]) or 0
    local v = 80
    if k > 1e-5 then
      -- The limit depends on speed, so settle it: speed from the limit, the limit from the speed.
      local lat = M.LAT_TABLE[1][2]
      for _ = 1, 4 do
        v = math.sqrt(lat * mu * G / k)
        lat = M.latG(v)
      end
      v = math.min(80, math.sqrt(lat * mu * G / k))
    end
    speeds[i] = v
  end
  if n > 0 and endSpeed then speeds[n] = math.min(speeds[n], endSpeed) end
  for i = n - 1, 1, -1 do
    local a, b = points[i], points[i + 1]
    local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    speeds[i] = math.min(speeds[i], math.sqrt(speeds[i + 1] ^ 2 + 2 * M.BRAKE_G * mu * G * d))
  end
  return speeds
end

-- The point dist metres along the route from where x, y is nearest it, and the index of the
-- route point just past it.
function M.along(points, x, y, dist)
  local n = #points
  if n == 0 then return nil end
  if n == 1 then return points[1].x, points[1].y, 1 end
  local best, bestD2, bestT = 1, math.huge, 0
  for i = 1, n - 1 do
    local a, b = points[i], points[i + 1]
    local sx, sy = b.x - a.x, b.y - a.y
    local len2 = sx * sx + sy * sy
    local t = len2 > 1e-9 and clamp(((x - a.x) * sx + (y - a.y) * sy) / len2, 0, 1) or 0
    local px, py = a.x + sx * t, a.y + sy * t
    local d2 = (px - x) ^ 2 + (py - y) ^ 2
    if d2 < bestD2 then best, bestD2, bestT = i, d2, t end
  end
  local i, t, left = best, bestT, dist
  while i < n do
    local a, b = points[i], points[i + 1]
    local seg = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local rest = seg * (1 - t)
    if rest >= left and seg > 1e-9 then
      local u = t + left / seg
      return a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, i + 1
    end
    left, i, t = left - rest, i + 1, 0
  end
  return points[n].x, points[n].y, n
end

-- Where to drive along the route and how fast: a point LOOK_SECONDS of speed along it, at the
-- slowest planned speed between here and there.
function M.routeAim(car, route, speeds)
  local look = clamp(math.max(car.speed, 0) * M.LOOK_SECONDS, M.LOOK_MIN, M.LOOK_MAX)
  local x, y, i = M.along(route, car.x, car.y, look)
  local _, _, here = M.along(route, car.x, car.y, 0)
  local speed = math.huge
  for j = math.max(1, here - 1), i do speed = math.min(speed, speeds[j] or speed) end
  return { x = x, y = y, speed = speed }
end

-- The road attack, one frame. s keeps the phase; them is the target (x, y, vx, vy, fx, fy).
-- Returns the target for M.control ({ x, y, speed }) and the phase: CATCH, PASS, CUT_IN,
-- BRAKE_CHECK, RECOVER or BLOCK.
function M.roadAttack(s, car, route, speeds, them, dt)
  local vx, vy = them.vx or 0, them.vy or 0
  local theirSpeed = math.sqrt(vx * vx + vy * vy)
  local hx, hy = them.fx or 0, them.fy or 1
  if theirSpeed > 1 then hx, hy = vx / theirSpeed, vy / theirSpeed end
  local h = math.sqrt(hx * hx + hy * hy)
  if h < 1e-6 then hx, hy, h = 0, 1, 1 end
  hx, hy = hx / h, hy / h
  local rx, ry = hy, -hx
  local dx, dy = car.x - them.x, car.y - them.y
  local along, right = dx * hx + dy * hy, dx * rx + dy * ry
  local metres = math.sqrt(dx * dx + dy * dy)
  -- A point from them: right metres to their right, ahead metres ahead.
  local function at(r, a) return them.x + hx * a + rx * r, them.y + hy * a + ry * r end

  s.phase = s.phase or 'CATCH'
  s.phaseTime = (s.phaseTime or 0) + dt
  local function go(phase) if s.phase ~= phase then s.phase, s.phaseTime = phase, 0 end end

  if metres > M.LOSE_METRES then go('CATCH') end
  if s.phase == 'CATCH' and metres <= M.ENGAGE_METRES then go(along >= M.CUT_AHEAD and 'CUT_IN' or 'PASS') end
  if s.phase ~= 'CATCH' and theirSpeed < M.STOPPED_MPS and along > 0 then go('BLOCK') end
  if s.phase == 'BLOCK' and theirSpeed >= M.STOPPED_MPS * 2 then go(along > 0 and 'CUT_IN' or 'PASS') end
  if s.phase == 'PASS' and along >= M.CUT_AHEAD then go('CUT_IN') end
  if s.phase == 'CUT_IN' then
    if along < 0 then go('PASS')
    elseif math.abs(right) <= M.IN_LANE and along <= M.CUT_AHEAD * 2.5 then
      s.settled = (s.settled or 0) + dt
      if s.settled >= M.SETTLE_SECONDS then s.settled = 0; go('BRAKE_CHECK') end
    else s.settled = 0 end
  end
  if s.phase == 'BRAKE_CHECK' and s.phaseTime >= M.BRAKE_SECONDS then go('RECOVER') end
  if s.phase == 'RECOVER' and s.phaseTime >= M.RECOVER_SECONDS then go(along > 0 and 'CUT_IN' or 'PASS') end

  local x, y, speed
  if s.phase == 'CATCH' then
    if route and #route >= 2 and speeds then return M.routeAim(car, route, speeds), s.phase end
    x, y = at(0, -M.FOLLOW_BEHIND)
    speed = theirSpeed + clamp((-M.FOLLOW_BEHIND - along) * 0.6, -theirSpeed, M.CATCH_MPS)
  elseif s.phase == 'PASS' then
    x, y = at(M.PASS_SIDE, along + M.PASS_LOOK)
    speed = theirSpeed + M.PASS_MPS
  elseif s.phase == 'CUT_IN' then
    x, y = at(0, M.CUT_AHEAD + M.PASS_LOOK)
    speed = theirSpeed + clamp((M.CUT_AHEAD - along) * 0.6, -5, M.PASS_MPS)
  elseif s.phase == 'BRAKE_CHECK' then
    x, y = at(0, along + M.PASS_LOOK)
    speed = theirSpeed * M.BRAKE_SHARE
  elseif s.phase == 'RECOVER' then
    x, y = at(0, along + M.PASS_LOOK)
    speed = theirSpeed + clamp((M.CUT_AHEAD - along) * 0.6, -5, 3)
  else -- BLOCK
    x, y = at(0, M.BLOCK_AHEAD + M.PASS_LOOK)
    speed = along > M.BLOCK_AHEAD and 0 or 2
  end
  return { x = x, y = y, speed = math.max(0, speed) }, s.phase
end

-- ------------------------------------------------------------ in the car ---

local state, active, savedGearbox
local lastDir

local chasing -- the id of the car being chased on the roads, or nil
local route, routeSpeeds, routeAt

local function takeOver()
  state = state or M.newState()
  if not active then
    active = true
    state.tries, state.pushing, state.backing = 0, 0, 0
    if ai and ai.setMode then pcall(ai.setMode, 'disabled') end
    if controller and controller.mainController and controller.mainController.setGearboxMode then
      savedGearbox = electrics and electrics.values and electrics.values.gearboxMode
      pcall(controller.mainController.setGearboxMode, 'arcade')
    end
  end
end

-- The game's command: drive at x, y, z at speed m/s; mode as in control (nil may brake).
function M.target(x, y, z, speed, mode)
  takeOver()
  chasing = nil
  state.target = { x = x, y = y, z = z, speed = speed, mode = mode }
  state.age = 0
end

-- The game's command: chase car id on the roads, and ram it.
function M.chase(id)
  takeOver()
  chasing, route, routeAt = id, nil, nil
  state.road = {}
  if mapmgr and mapmgr.requestMap then pcall(mapmgr.requestMap) end
end

local function drive(steer, throttle, brake, parking)
  if not input or not input.event then return end
  input.event('steering', steer, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('throttle', throttle, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('brake', brake, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('parkingbrake', parking or 0, 'FILTER_AI', nil, nil, nil, 'ai')
end

-- Hands the car back: pedals off, wheel straight, gearbox as it was.
function M.stop()
  if not active then return end
  active, chasing, route = false, nil, nil
  if state then state.target = nil end
  drive(0, 0, 0, 0)
  if savedGearbox and controller and controller.mainController and controller.mainController.setGearboxMode then
    pcall(controller.mainController.setGearboxMode, savedGearbox)
  end
  savedGearbox = nil
end

function M.active() return active == true end

local function wheelBase()
  if state.wheelBase then return state.wheelBase end
  local length = obj.getInitialLength and obj:getInitialLength() or 4.5
  state.wheelBase = clamp(length * 0.6, 2, 6)
  return state.wheelBase
end

-- The feelers (see FEEL_ANGLE): what is solid ahead, from the car at px, py, pz facing fx, fy.
-- Every game call is guarded; with no ray to cast, the car simply doesn't feel.
local FEELERS = {
  { key = 'centre', angle = 0, off = 0 }, { key = 'left', angle = -1, off = 0 }, { key = 'right', angle = 1, off = 0 },
  { key = 'edgeLeft', angle = 0, off = -1 }, { key = 'edgeRight', angle = 0, off = 1 },
}
local function feel(px, py, pz, fx, fy, speed)
  if not (obj and obj.castRayStatic and vec3) then return nil end
  local function ray(x, y, z, dx, dy, dz, len)
    return pcall(function() return obj:castRayStatic(vec3(x, y, z), vec3(dx, dy, dz), len) end)
  end
  -- The ground below a point, looking down from up to `above` metres over z; nil if none.
  local function ground(x, y, z, above)
    local ok, d = ray(x, y, z + above, 0, 0, -1, above * 2 + 3)
    if ok and type(d) == 'number' and d < above * 2 + 3 - 0.01 then return z + above - d end
  end
  local look = clamp(math.abs(speed) * M.FEEL_SECONDS, M.FEEL_MIN, M.FEEL_MAX)
  local out = { look = look }
  local z = pz + M.FEEL_HEIGHT
  local okTest = ray(px, py, z, fx, fy, 0, 0.1)
  if not okTest then return nil, 'no_feelers' end
  -- How high the feelers start above the ground under the car.
  local under = ground(px, py, z, 1)
  local height = under and (z - under) or M.FEEL_HEIGHT
  local rx, ry = fy, -fx
  for _, f in ipairs(FEELERS) do
    local a = f.angle * M.FEEL_ANGLE
    local c, sn = math.cos(a), math.sin(a)
    local dx, dy = fx * c + rx * sn, fy * c + ry * sn
    local ox, oy = px + rx * f.off * M.EDGE_METRES, py + ry * f.off * M.EDGE_METRES
    -- Follow the ground: aim at the same height above it at the far end (no ground found there,
    -- straight on). A feeler that touches the ground on the way (a crest, or a hill steeper than
    -- the aim) carries on from just past that spot, at its height again, up to FEEL_SEGMENTS times.
    local ex, ey = ox + dx * look, oy + dy * look
    local endGround = ground(ex, ey, z, look)
    local ez = endGround and clamp(endGround + height, z - look, z + look) or z
    local sx, sy, sz, done = ox, oy, z, 0
    for _ = 1, M.FEEL_SEGMENTS do
      local hx, hy, hz = ex - sx, ey - sy, ez - sz
      local flat = math.sqrt(hx * hx + hy * hy)
      if flat < 1 then break end
      local len = math.sqrt(flat * flat + hz * hz)
      local ux, uy, uz = hx / len, hy / len, hz / len
      local ok, d = ray(sx, sy, sz, ux, uy, uz, len)
      if not (ok and type(d) == 'number' and d < len - 0.01) then break end
      local px2, py2, pz2 = sx + ux * d, sy + uy * d, sz + uz * d
      local along = done + d * flat / len
      -- Standing up (a bush) or the ground (a hill or crest)? Look down on the spot just past it.
      local okDown, down = ray(px2 + dx * 0.2, py2 + dy * 0.2, pz2 + 3, 0, 0, -1, 6)
      if okDown and type(down) == 'number' and (pz2 + 3 - down) - pz2 > M.FEEL_TALL then
        out[f.key] = along
        break
      end
      -- The ground: carry on from just past it, at the feelers' height above the ground there.
      sx, sy, done = px2 + dx * 0.3, py2 + dy * 0.3, along + 0.3
      local g = ground(sx, sy, pz2, 2)
      sz = (g or pz2) + height
    end
  end
  return out
end
M.feel = feel

function M.updateGFX(dt)
  if not active or not state or not obj or dt <= 0 then return end
  local px, py
  if obj.getPositionXYZ then px, py = obj:getPositionXYZ() else local p = obj:getPosition(); px, py = p.x, p.y end
  local fx, fy
  if obj.getDirectionVectorXYZ then fx, fy = obj:getDirectionVectorXYZ() else local d = obj:getDirectionVector(); fx, fy = d.x, d.y end
  local len = math.sqrt(fx * fx + fy * fy)
  if len < 1e-6 then return end
  fx, fy = fx / len, fy / len
  local vx, vy
  if obj.getSmoothRefVelocityXYZ then vx, vy = obj:getSmoothRefVelocityXYZ() else local v = obj:getVelocity(); vx, vy = v.x, v.y end
  local yawRate = 0
  if lastDir then
    -- Positive turning right: the facing moved towards the right vector.
    local cross = lastDir[1] * fy - lastDir[2] * fx
    yawRate = -math.asin(clamp(cross, -1, 1)) / dt
  end
  lastDir = { fx, fy }
  local car = {
    x = px, y = py, fx = fx, fy = fy, rx = fy, ry = -fx,
    speed = vx * fx + vy * fy, yawRate = yawRate,
    wheelSpeed = electrics and electrics.values and electrics.values.wheelspeed,
    mu = obj.getStaticFrictionCoef and obj:getStaticFrictionCoef() * 0.95 or 1,
    wheelBase = wheelBase(),
  }
  state.feelAt = (state.feelAt or 0) - dt
  if state.feelAt <= 0 and not state.noFeelers then
    state.feelAt = M.FEEL_EVERY
    local pz = 0
    if obj.getPositionXYZ then pz = select(3, obj:getPositionXYZ()) or 0 else pz = obj:getPosition().z end
    local found, why = feel(px, py, pz, fx, fy, car.speed)
    state.feel = found
    if why then
      state.noFeelers = true
      obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.raiderProblem(%d, "%s") end', obj:getID(), why))
    end
  end
  if chasing then
    local them = mapmgr and mapmgr.getObjects and mapmgr.getObjects()[chasing]
    if them and them.pos then
      local tvx, tvy = them.vel and them.vel.x or 0, them.vel and them.vel.y or 0
      local t = { x = them.pos.x, y = them.pos.y, vx = tvx, vy = tvy,
        fx = them.dirVec and them.dirVec.x, fy = them.dirVec and them.dirVec.y }
      routeAt = (routeAt or 0) - dt
      if routeAt <= 0 then
        routeAt = M.ROUTE_SECONDS
        route = nil
        local ok, points = pcall(function()
          local data = mapmgr.mapData
          if not (data and mapmgr.findBestRoad and data.getChasePath) then return nil end
          local me = vec3(px, py, 0)
          local wp1, wp2 = mapmgr.findBestRoad(obj:getPosition(), obj:getDirectionVector())
          local pl1, pl2 = mapmgr.findBestRoad(them.pos, them.vel and them.vel:length() > 1 and them.vel or them.dirVec)
          if not (wp1 and wp2 and pl1 and pl2) then return nil end
          local path = data:getChasePath(wp1, wp2, pl1, pl2, obj:getPosition(), obj:getVelocity(), them.pos, them.vel, 1)
          if not path then return nil end
          local list = { { x = me.x, y = me.y } }
          for _, node in ipairs(path) do
            local p = data.positions[node]
            -- Road points just behind the car are skipped, so it doesn't aim back at them.
            local behind = p and #list == 1 and ((p.x - px) * fx + (p.y - py) * fy) < 0
            if p and not behind then list[#list + 1] = { x = p.x, y = p.y } end
          end
          list[#list + 1] = { x = t.x, y = t.y }
          return list
        end)
        if ok and points and #points >= 2 then
          route = points
          routeSpeeds = M.speedPlan(route, car.mu, math.sqrt(tvx * tvx + tvy * tvy) + M.END_EXTRA_MPS)
        end
      end
      local aim, phase = M.roadAttack(state.road, car, route, routeSpeeds, t, dt)
      state.target, state.age = aim, 0
      if phase ~= state.lastPhase then
        state.lastPhase = phase
        obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.raiderProblem(%d, "%s") end', obj:getID(), phase))
      end
    end
  end
  local steer, throttle, brake, parking = M.control(state, car, dt)
  drive(steer, throttle, brake, parking)
  if state.stuckEvent then
    local tries = state.stuckEvent
    state.stuckEvent = nil
    obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.raiderProblem(%d, "stuck_try_%d") end', obj:getID(), tries))
  end
end

function M.onReset()
  if state then state.tries, state.pushing, state.backing = 0, 0, 0 end
  lastDir = nil
end

return M
