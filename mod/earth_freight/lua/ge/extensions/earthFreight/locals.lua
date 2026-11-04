-- Locals shooting at the truck. In rough country (a road bonus of ROUGH_ROADS or more where the car
-- is) a stretch driven now and then brings a burst of shots from one fixed spot off to the left or
-- right of the car. Each shot is aimed at the car with some spread, so a few miss; a hit dents the
-- body and can flatten a tyre (earthFreightShot.lua in the car, a milder copy of Tanker's revolver
-- hit). The spot stays put, so driving on gets the car out of range. The core controller decides
-- when; this file holds the settings, the maths, and the game calls that fire a shot and play its
-- sound. Every game call is guarded: a missing or changed one means no shot, never an error.
local M = {}

-- One-line settings. Tune these after testing in game.
-- Only where the HUD shows "rough roads x1.4" or more.
M.ROUGH_ROADS = 1.4
M.AVERAGE_KM = 25 -- about one attack per this many km driven there
M.DONT_ASK_MULTIPLIER = 2 -- twice as likely with a "Don't ask questions" load on board
M.GAP_KM = 5 -- no second attack within this far of the last one
M.TEST_DELAY = 5 -- seconds from the test button to the first shot
-- The shooter's spot: this far out to one side, this far ahead along the car's way, standing on
-- the ground there at this height.
M.SIDE_MIN, M.SIDE_MAX = 30, 80
M.AHEAD_MIN, M.AHEAD_MAX = 0, 40
M.SHOOTER_HEIGHT = 1.5
-- The burst: this many shots, each this many seconds after the last; it stops early once the car
-- is further than RANGE metres from the spot.
M.SHOTS_MIN, M.SHOTS_MAX = 4, 8
M.SHOT_GAP_MIN, M.SHOT_GAP_MAX = 0.35, 1.0
M.RANGE = 150
-- Each shot aims at a point up to this many metres from the middle of the car (half that up or
-- down), so some go wide.
M.SPREAD = 1.2
-- The hit, milder than Tanker's revolver (6000, 1.3, 70, 0.3): a softer push, a smaller and
-- shallower dent. A hit near a wheel hub flattens that tyre. Raised by half after the first test
-- in game (was 2500 and 30).
M.HIT_RADIUS = 0.3
M.IMPACT_FORCE, M.BLAST_RADIUS, M.BLAST_FORCE, M.BLAST_INVERSION = 3750, 0.8, 45, 0.3
M.DEFLATE_TYRES = true
-- The gunshot, played at the shooter's spot: the first of these files that exists. The mod ships
-- Rowan's distant gunshot as a mono WAV, so the game can place it in the world.
M.SOUNDS = { 'art/sound/earthFreight/locals_shot.ogg', 'art/sound/earthFreight/locals_shot.wav' }

-- The chance of an attack starting over this many metres, for the road bonus where the car is and
-- whether a "Don't ask questions" load is on board.
function M.chance(metres, roadBonus, dontAsk)
  if type(metres) ~= 'number' or metres <= 0 or type(roadBonus) ~= 'number' then return 0 end
  if roadBonus < M.ROUGH_ROADS - 1e-9 then return 0 end
  return math.min(1, metres * (dontAsk and M.DONT_ASK_MULTIPLIER or 1) / (M.AVERAGE_KM * 1000))
end

local function between(random, low, high) return low + (high - low) * random() end

-- A new attack's plan, from random (0 to 1): which side, how far out and ahead, and the burst.
function M.plan(random)
  local shots = M.SHOTS_MIN + math.floor(random() * (M.SHOTS_MAX - M.SHOTS_MIN + 1))
  local gaps = {}
  for i = 1, math.min(shots, M.SHOTS_MAX) do gaps[i] = between(random, M.SHOT_GAP_MIN, M.SHOT_GAP_MAX) end
  return { side = random() < 0.5 and 'left' or 'right', across = between(random, M.SIDE_MIN, M.SIDE_MAX),
    ahead = between(random, M.AHEAD_MIN, M.AHEAD_MAX), shots = math.min(shots, M.SHOTS_MAX), gaps = gaps }
end

-- The shooter's spot ({ x, y }, ground level unknown) beside a car at centre heading along forward,
-- both { x, y, z } in the world (z up).
function M.spot(centre, forward, plan)
  local fx, fy = forward.x, forward.y
  local length = math.sqrt(fx * fx + fy * fy)
  if length < 1e-6 then fx, fy, length = 0, 1, 1 end
  fx, fy = fx / length, fy / length
  -- To the car's right is forward turned a quarter clockwise, seen from above.
  local rx, ry = fy, -fx
  local sign = plan.side == 'left' and -1 or 1
  return { x = centre.x + fx * plan.ahead + rx * plan.across * sign, y = centre.y + fy * plan.ahead + ry * plan.across * sign }
end

-- A shot from the spot at the car: the point it aims at (the car's middle, moved by up to SPREAD),
-- its direction and how far it goes (a little past the car).
function M.aim(from, centre, random)
  local function off(size) return (random() * 2 - 1) * size end
  local target = { x = centre.x + off(M.SPREAD), y = centre.y + off(M.SPREAD), z = centre.z + off(M.SPREAD / 2) }
  local dx, dy, dz = target.x - from.x, target.y - from.y, target.z - from.z
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length < 1e-6 then return nil end
  return { x = dx / length, y = dy / length, z = dz / length }, length + 5, target
end

function M.distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    -- How far down from a point the ground or a building is, or nil.
    down = function(x, y, z, range)
      if not (castRayStatic and vec3) then return nil end
      local d = castRayStatic(vec3(x, y, z), vec3(0, 0, -1), range)
      return type(d) == 'number' and d < range and d or nil
    end,
    -- How far along a ray before it meets the ground or a building.
    wall = function(origin, dir, range)
      if not (castRayStatic and vec3) then return range end
      local d = castRayStatic(vec3(origin.x, origin.y, origin.z), vec3(dir.x, dir.y, dir.z), range)
      return type(d) == 'number' and d < range and d or range
    end,
    exists = function(path) return FS and FS:fileExists(path) == true end,
    -- A sound at a spot in the world. AudioDefault3D is the game's positional channel.
    play = function(path, at)
      local audio = Engine and Engine.Audio
      if not (audio and audio.playOnce) then return false end
      local ok = pcall(audio.playOnce, 'AudioDefault3D', path, { position = vec3(at.x, at.y, at.z) })
      if not ok then ok = pcall(audio.playOnce, 'AudioGui', path) end
      return ok
    end,
  }
end

-- The car-side hit, as Tanker sends it, without the driver box.
local HIT = "extensions.load('earthFreightShot'); extensions.earthFreightShot.hit(%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.2f,%.3f,%.1f,%.3f,%.1f,%.3f,%s)"

function M.new(environment)
  local env = environment or defaults()
  local l = {}

  local function call(name, ...)
    local f = env[name]
    if type(f) ~= 'function' then return nil end
    local ok, x = pcall(f, ...)
    if ok then return x end
  end

  local function player()
    local ok, vehicle = pcall(env.player)
    if ok and vehicle then return vehicle end
  end

  -- The player car's middle and which way it points: { centre, forward } as { x, y, z }, or nil.
  function l:car()
    local vehicle = player()
    if not vehicle then return nil end
    local ok, centre, forward = pcall(function()
      local box = vehicle:getSpawnWorldOOBB()
      local c = box and box:getCenter() or vehicle:getPosition()
      local f = vehicle:getDirectionVector()
      return { x = c.x, y = c.y, z = c.z }, { x = f.x, y = f.y, z = f.z }
    end)
    if ok and centre and forward then return { centre = centre, forward = forward } end
  end

  -- The shooter's spot for a plan, standing on the ground there: { x, y, z }, or nil without a car.
  function l:place(plan)
    local car = self:car()
    if not car then return nil end
    local at = M.spot(car.centre, car.forward, plan)
    local top = car.centre.z + 100
    local down = call('down', at.x, at.y, top, 400)
    at.z = (down and top - down or car.centre.z - 1) + M.SHOOTER_HEIGHT
    return at
  end

  -- One shot from the spot at the player car, with its sound. Returns true once it was fired, or
  -- false and why. A shot blocked by the ground or a building on the way does no harm.
  function l:fire(from, random)
    local vehicle, car = player(), self:car()
    if not (vehicle and car) then return false, 'vehicle_required' end
    self:sound(from)
    local dir, reach = M.aim(from, car.centre, random or math.random)
    if not dir then return false, 'too_close' end
    reach = math.min(reach, call('wall', from, dir, reach) or reach)
    local cmd = string.format(HIT, from.x, from.y, from.z, dir.x, dir.y, dir.z, reach, M.HIT_RADIUS,
      M.IMPACT_FORCE, M.BLAST_RADIUS, M.BLAST_FORCE, M.BLAST_INVERSION, tostring(M.DEFLATE_TYRES))
    local ok, why = pcall(function() vehicle:queueLuaCommand(cmd) end)
    if not ok then return false, 'shot_failed', tostring(why) end
    return true
  end

  -- The gunshot at the spot, when a sound file is in the mod. Returns whether one played.
  function l:sound(at)
    for _, path in ipairs(M.SOUNDS) do
      if call('exists', path) then return call('play', path, at) == true end
    end
    return false
  end

  return l
end

return M
