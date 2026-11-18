-- Mayday Rescue (multiplayer, on a server running the Worldwide Trucking plugin). The server sends out a call for help
-- from a remote spot, with a circle around it. Players teleport for free to its north, east, south or west edge and
-- race any car they like to the scene in the middle: the first one there wins the reward, and the call goes out from
-- somewhere else. While a call is out, nobody can relocate inside its circle, and any other teleport ends a run.
-- The server keeps the rounds, the starts and the winner; this file checks what it sends and does the sums. Pure Lua:
-- no game globals.
local location = require('earthFreight/location')
local M = {}

-- How close to the scene counts as there.
M.WIN_METRES = 250
-- The edge buttons, in the order they show.
M.EDGES = { { id = 'n', name = 'North' }, { id = 'e', name = 'East' }, { id = 's', name = 'South' }, { id = 'w', name = 'West' } }
-- A relocation landing within this of its edge starts the run (tighter than other relocations, which land anywhere in
-- a town), and a player this close to an edge already starts from where they are.
M.LAND_METRES = 500
-- Each edge teleport lands somewhere this far from the edge's own point, in a random direction, so two players who
-- pick the same edge at once don't land on top of each other. Well inside LAND_METRES.
M.SPREAD_MIN_METRES = 30
M.SPREAD_MAX_METRES = 250
-- The edges sit on the circle's line: a spot this far inside it is still outside, so the edges aren't barred.
M.INSIDE_MARGIN_METRES = 1000
-- A jump of the car further than this (and not a teleport the game already deals with) ends a run. BeamNG's own
-- recover button moves the car a few metres back, which is fine.
M.HOP_METRES = 300
-- How often a game on a run tells the server how far it is from the scene, for the standings.
M.POS_SECONDS = 10
-- How long the game waits for the server to answer "I'm at the scene" before asking again.
M.WIN_WAIT_SECONDS = 15
-- The most the server could ever pay for one, so a garbled number is never added to anyone's money.
M.MAX_REWARD = 10000000

local function text(value, max)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value:sub(1, max)
end

local function point(t)
  if type(t) ~= 'table' or not location.valid(t) then return nil end
  return { latitude = t.latitude, longitude = t.longitude }
end

local function whole(v, max)
  v = tonumber(v)
  return v and v >= 0 and v <= max and math.floor(v) or nil
end

-- The server's call (wwtcMayday), checked, with now (the game's clock) to count down from. Returns a clean copy, or nil.
function M.clean(d, now)
  if type(d) ~= 'table' then return nil end
  local round = whole(d.round, 1e9)
  local spot = point(d.spot)
  local radius = tonumber(d.radiusKm)
  if not round or round < 1 or not spot or not radius or radius <= 0 or radius > 1000 then return nil end
  if d.state ~= 'open' and d.state ~= 'won' then return nil end
  local edges = {}
  for _, e in ipairs(M.EDGES) do
    edges[e.id] = point(type(d.edges) == 'table' and d.edges[e.id] or nil)
    if not edges[e.id] then return nil end
  end
  -- The standings: everyone on a run, nearest the scene first, with this player's own line marked.
  local standings = {}
  for _, e in ipairs(type(d.standings) == 'table' and d.standings or {}) do
    local km = type(e) == 'table' and tonumber(e.km)
    if km and km >= 0 and km < 100000 and #standings < 20 then
      standings[#standings + 1] = { name = text(e.name, 32) or 'A trucker', km = math.floor(km * 10 + 0.5) / 10,
        you = e.you == true or nil }
    end
  end
  spot.name = text(d.spot.name, 40) or 'Somewhere remote'
  spot.region = text(d.spot.region, 60) or ''
  return { round = round, state = d.state, spot = spot, radiusKm = radius, edges = edges,
    story = text(d.story, 160) or 'Someone needs help.', reward = whole(d.reward, M.MAX_REWARD) or 0,
    winner = text(d.winner, 32), racers = whole(d.racers, 1000) or 0,
    left = whole(d.left, 30 * 86400) or 0, at = now or 0, standings = standings }
end

-- The server's answer to "I'm at the scene" (wwtcMaydayWon), checked.
function M.cleanAnswer(d)
  if type(d) ~= 'table' then return nil end
  local round = whole(d.round, 1e9)
  if not round then return nil end
  return { round = round, ok = d.ok == true, why = text(d.why, 20), reward = whole(d.reward, M.MAX_REWARD),
    winner = text(d.winner, 32) }
end

-- Money the server owes this player (wwtcReward), checked: { id, amount, why }, or nil.
function M.cleanReward(d)
  if type(d) ~= 'table' then return nil end
  local id, amount = whole(d.id, 1e12), whole(d.amount, M.MAX_REWARD)
  if not id or id < 1 or not amount then return nil end
  return { id = id, amount = amount, why = text(d.why, 20) }
end

-- Seconds until an open call moves on, or until the next one goes out after a win.
function M.secondsLeft(call, now)
  if not call then return 0 end
  return math.max(0, call.left - ((now or call.at) - call.at))
end

-- Whether a point is inside an open call's circle (the edges themselves are not).
function M.inside(call, p)
  if not call or call.state ~= 'open' or type(p) ~= 'table' or not location.valid(p) then return false end
  local d = location.distance(p, call.spot)
  return d ~= nil and d < call.radiusKm * 1000 - M.INSIDE_MARGIN_METRES
end

-- Where an edge teleport lands: a random spot SPREAD_MIN_METRES to SPREAD_MAX_METRES from the edge. random() gives a
-- number in [0, 1).
function M.landing(edge, random)
  random = random or math.random
  local metres = M.SPREAD_MIN_METRES + (M.SPREAD_MAX_METRES - M.SPREAD_MIN_METRES) * math.sqrt(random())
  return location.destination(edge, random() * 360, metres)
end

-- 1st, 2nd, 3rd, 4th...
function M.ordinal(n)
  local tens = n % 100
  local last = n % 10
  local suffix = (tens >= 11 and tens <= 13) and 'th' or last == 1 and 'st' or last == 2 and 'nd' or last == 3 and 'rd' or 'th'
  return n .. suffix
end

-- An edge's name ('North') from its id ('n').
function M.edgeName(id)
  for _, e in ipairs(M.EDGES) do if e.id == id then return e.name end end
end

return M
