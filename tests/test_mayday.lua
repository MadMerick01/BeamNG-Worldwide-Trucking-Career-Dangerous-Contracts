local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local L = require('earthFreight/location')
local M = require('earthFreight/mayday')

-- The server's call, checked before the game uses any of it.
local scene = { latitude = 43.5, longitude = 104.0 }
local function edges()
  local out = {}
  for id, bearing in pairs({ n = 0, e = 90, s = 180, w = 270 }) do out[id] = L.destination(scene, bearing, 40000) end
  return out
end
local function call(extra)
  local d = { round = 3, state = 'open', story = 'A light plane was forced down.\n', radiusKm = 40, edges = edges(),
    spot = { id = 'gobi', name = 'Gobi Desert', region = 'Mongolia', latitude = scene.latitude, longitude = scene.longitude },
    left = 3600, reward = 80000, winner = nil, racers = 2 }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end
local c = M.clean(call(), 100)
T.check(c ~= nil, 'a good call is kept')
T.eq(c.spot.name, 'Gobi Desert', 'with its spot'); T.eq(c.story, 'A light plane was forced down.', 'and its story, on one line')
T.eq(c.reward, 80000, 'the prize'); T.eq(c.racers, 2, 'and how many have set off')
T.eq(M.clean(call({ state = 'maybe' })), nil, 'an unknown state is refused')
T.eq(M.clean(call({ round = 0 })), nil, 'so is round 0')
T.eq(M.clean(call({ radiusKm = -1 })), nil, 'and a circle with no size')
local missing = call(); missing.edges.w = nil
T.eq(M.clean(missing), nil, 'a call needs all four edges')
T.eq(M.clean(call({ spot = { latitude = 200, longitude = 0 } })), nil, 'and a real place')
T.eq(M.clean(call({ reward = 1e12 })).reward, 0, 'a prize nobody could pay is shown as none')

-- The countdown, from the clock when the call came.
T.eq(M.secondsLeft(c, 100), 3600, 'the time left as it came')
T.eq(M.secondsLeft(c, 700), 3000, 'counting down')
T.eq(M.secondsLeft(c, 99999), 0, 'never below zero')

-- Inside the circle: anywhere in it, not its edges, and only while it's open.
T.check(M.inside(c, scene), 'the scene is inside')
T.check(M.inside(c, L.destination(scene, 45, 30000)), '30 km out is inside')
T.check(not M.inside(c, c.edges.n), 'an edge is not')
T.check(not M.inside(c, L.destination(scene, 45, 39500)), 'nor just inside the line')
T.check(not M.inside(c, L.destination(scene, 45, 60000)), 'nor outside')
T.check(not M.inside(M.clean(call({ state = 'won' })), scene), 'a won call bars nothing')
T.check(not M.inside(nil, scene), 'no call bars nothing')

-- The server's answer and its reward.
T.eq(M.cleanAnswer({ round = 3, ok = true, reward = 80000 }).ok, true, 'a win')
T.eq(M.cleanAnswer({ round = 'x' }), nil, 'an answer needs a round')
local r = M.cleanReward({ id = 2, amount = 80000, why = 'mayday' })
T.eq(r.id, 2, 'a reward has an id'); T.eq(r.amount, 80000, 'and an amount')
T.eq(M.cleanReward({ id = 0, amount = 5 }), nil, 'id 0 is no reward')
T.eq(M.cleanReward({ id = 1, amount = 2e7 }), nil, 'nor more than the most the server could pay')
T.eq(M.cleanReward(nil), nil, 'nor nothing')
T.eq(M.edgeName('w'), 'West', 'edges by name')
T.done('Mayday Rescue')
