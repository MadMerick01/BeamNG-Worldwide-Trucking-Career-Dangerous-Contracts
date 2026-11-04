local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local location = require('earthFreight/location')
local locals = require('earthFreight/locals')

-- The chance: none below rough roads x1.4, twice as likely with a "Don't ask questions" load.
T.eq(locals.chance(1000, 1.3, false), 0, 'not on easier roads')
T.near(locals.chance(1000, 1.4, false), 1 / locals.AVERAGE_KM, 1e-12, 'one in AVERAGE_KM per km at x1.4')
T.near(locals.chance(1000, 2, false), 1 / locals.AVERAGE_KM, 1e-12, 'the same on rougher roads')
T.near(locals.chance(1000, 1.4, true), 2 / locals.AVERAGE_KM, 1e-12, 'twice with a dont-ask load')
T.eq(locals.chance(0, 2, false), 0, 'no distance, no chance')

-- The plan and the spot: out to one side, a little ahead.
local function fixed(value) return function() return value end end
local left = locals.plan(fixed(0))
T.eq(left.side, 'left', 'low roll is left'); T.eq(left.shots, locals.SHOTS_MIN, 'fewest shots')
local right = locals.plan(fixed(0.999))
T.eq(right.side, 'right', 'high roll is right'); T.eq(right.shots, locals.SHOTS_MAX, 'most shots')
T.eq(#right.gaps, right.shots, 'a gap per shot')
-- Heading north (+y): right is +x, left is -x.
local north = { x = 0, y = 1, z = 0 }
local spot = locals.spot({ x = 0, y = 0, z = 0 }, north, { side = 'right', across = 50, ahead = 10 })
T.near(spot.x, 50, 1e-9, 'right of a car heading north is east'); T.near(spot.y, 10, 1e-9, 'ahead')
spot = locals.spot({ x = 0, y = 0, z = 0 }, north, { side = 'left', across = 50, ahead = 0 })
T.near(spot.x, -50, 1e-9, 'left is west')

-- Aim: at the middle with no spread, and never more than SPREAD off.
local dir, reach, target = locals.aim({ x = 50, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, fixed(0.5))
T.near(dir.x, -1, 1e-9, 'straight at the car'); T.near(reach, 55, 1e-9, 'a little past it'); T.near(target.x, 0, 1e-9, 'the middle')
_, _, target = locals.aim({ x = 50, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, fixed(1))
T.near(target.y, locals.SPREAD, 1e-9, 'spread at most SPREAD'); T.near(target.z, locals.SPREAD / 2, 1e-9, 'half that up')

-- The game side: the shot goes into the player car, and the sound plays at the spot.
do
  local sent, played = {}, {}
  local car = { commands = sent }
  function car:queueLuaCommand(c) self.commands[#self.commands + 1] = c end
  function car:getSpawnWorldOOBB() return { getCenter = function() return { x = 0, y = 0, z = 1 } end } end
  function car:getDirectionVector() return { x = 0, y = 1, z = 0 } end
  local l = locals.new({
    player = function() return car end,
    down = function(x, y, z) return z - 3 end, -- ground at z = 3
    wall = function(_, _, range) return range end,
    exists = function(path) return path:match('%.ogg$') ~= nil end,
    play = function(path, at) played[#played + 1] = { path = path, at = at }; return true end,
  })
  local at = l:place({ side = 'right', across = 40, ahead = 0 })
  T.near(at.x, 40, 1e-9, 'beside the car'); T.near(at.z, 3 + locals.SHOOTER_HEIGHT, 1e-9, 'standing on the ground')
  T.check(l:fire(at, fixed(0.5)), 'fired')
  T.eq(#sent, 1, 'one hit sent to the car')
  T.check(sent[1]:find("extensions.earthFreightShot.hit(", 1, true) ~= nil, 'the car-side hit')
  T.check(sent[1]:sub(-6) == ',true)', 'tyres can go')
  T.eq(#played, 1, 'a gunshot'); T.eq(played[1].path, locals.SOUNDS[1], 'the ogg'); T.eq(played[1].at, at, 'at the spot')
  local quiet = locals.new({ player = function() return car end, exists = function() return false end,
    play = function() error('no sound file, nothing to play') end })
  T.check(quiet:fire(at, fixed(0.5)), 'fires without a sound file')
  T.eq(select(2, locals.new({ player = function() return nil end }):fire(at)), 'vehicle_required', 'needs a car')
end

-- Stand-in for the game side: the car stays at centre; counts shots.
local function standIn()
  local s = { shots = 0, centre = { x = 0, y = 0, z = 1 } }
  function s:car() return { centre = self.centre, forward = { x = 0, y = 1, z = 0 } } end
  function s:place(plan) return locals.spot(self.centre, { x = 0, y = 1, z = 0 }, plan) end
  function s:fire() self.shots = self.shots + 1; return true end
  return s
end

-- The test button: nothing for TEST_DELAY seconds, then the warning and the whole burst.
do
  local s = standIn()
  local c = F.controller({ locals = s, random = fixed(0) })
  c:tick(0.1)
  T.check(c:testLocals(), 'armed')
  T.eq(c:view().locals.testIn, locals.TEST_DELAY, 'counting down')
  c:tick(locals.TEST_DELAY - 0.5)
  T.eq(s.shots, 0, 'not yet')
  c:tick(0.6)
  local flash = c:view().flash
  T.eq(flash.kind, 'shots', 'warning shown'); T.eq(flash.title, 'HIT THE GAS, THE LOCALS ARE SHOOTING AT YOU', 'the words')
  T.eq(s.shots, 1, 'first shot at once'); T.check(c:view().locals.shooting, 'shooting')
  T.check(not c:testLocals(), 'not again while shooting')
  for _ = 1, 40 do c:tick(0.25) end
  T.eq(s.shots, locals.SHOTS_MIN, 'the whole burst'); T.eq(c:view().locals.shooting, nil, 'over')
  -- A shot that flattens a tyre adds its repair, as a puncture does.
  c:localsTyre()
  T.check(c:view().puncture.tyreCost > 0, 'tyre repair owed')
end

-- Driving out of range ends the burst early.
do
  local s = standIn()
  local c = F.controller({ locals = s, random = fixed(0) })
  c:tick(0.1); c:testLocals(); c:tick(locals.TEST_DELAY + 0.1)
  T.eq(s.shots, 1, 'shooting')
  s.centre = { x = 0, y = locals.RANGE + 100, z = 1 }
  for _ = 1, 20 do c:tick(0.25) end
  T.eq(s.shots, 1, 'out of range'); T.eq(c:view().locals.shooting, nil, 'over')
end

-- Without the game side there is no test button.
do
  local c = F.controller({})
  c:tick(0.1)
  T.eq(c:view().locals, nil, 'no button'); T.check(not c:testLocals(), 'nothing to test')
end

-- Driving: only where the roads are rough enough.
do
  local s = standIn()
  local c, _, a = F.controller({ locals = s, random = fixed(0) })
  c:tick(0.1)
  local start = F.copy(a.pose)
  for step = 1, 10 do a.pose = location.destination(start, 180, step * 100); c:tick(1) end
  local places = require('earthFreight/places')
  local jobs = require('earthFreight/jobs')
  local bonus = jobs.roadBonusFor(places.boost(places.nearest(a.pose, 1)[1].place))
  if bonus < locals.ROUGH_ROADS then
    T.eq(s.shots, 0, 'nobody shoots on easy roads (x' .. bonus .. ')')
  else
    T.check(s.shots > 0, 'shots on rough roads')
  end
  -- Forced rough: the road bonus is read from the nearest place.
  local roadBonusFor = jobs.roadBonusFor
  jobs.roadBonusFor = function() return 1.5 end
  local r = standIn()
  local d, _, b = F.controller({ locals = r, random = fixed(0) })
  d:tick(0.1)
  start = F.copy(b.pose)
  b.pose = location.destination(start, 180, 100); d:tick(1)
  T.eq(d:view().flash.kind, 'shots', 'an attack on rough roads')
  jobs.roadBonusFor = roadBonusFor
end
T.done('locals')
