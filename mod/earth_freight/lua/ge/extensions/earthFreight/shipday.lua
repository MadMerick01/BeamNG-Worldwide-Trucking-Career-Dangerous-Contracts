-- Ship Day (multiplayer, on a server running the Worldwide Trucking plugin). Every few days the server docks a ship at
-- the next port on its list, with a number of containers. Players go to the port, each takes a container (first come,
-- first served: the server keeps who has which) and drives it to a town inland for high pay.
-- The server only says which ship, which port and how many containers; what is in each container, where it goes and
-- what it pays are worked out here, the same on every player's game (the same places, the same hash). Pure Lua: no
-- game globals.
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local goods = require('earthFreight/goods')
local location = require('earthFreight/location')
local M = {}

M.GOOD = 'container'
-- Containers go to towns this far from the port by road (km). With none that far, the nearest towns instead.
M.MIN_KM, M.MAX_KM = 15, 70
-- How close to the port's town a player must be to load a container.
M.AT_PORT_METRES = 3000
-- No ship carries more than this.
M.MAX_CONTAINERS = 60
-- How long the game waits for the server to answer a claim before giving up.
M.CLAIM_WAIT_SECONDS = 15

local function text(value, max)
  if type(value) ~= 'string' or value == '' then return nil end
  return value:gsub('[%c]', ' '):sub(1, max)
end

-- The server's ship message, checked. Returns a clean copy, or nil.
function M.clean(d)
  if type(d) ~= 'table' or type(d.ship) ~= 'number' or d.ship ~= math.floor(d.ship) then return nil end
  local p = d.port
  if type(p) ~= 'table' or not text(p.id, 32) or not text(p.name, 40) or not location.valid(p) then return nil end
  local n = d.containers
  if type(n) ~= 'number' or n < 1 or n > M.MAX_CONTAINERS or n ~= math.floor(n) then return nil end
  local states = {}
  if type(d.taken) == 'table' then
    for _, t in ipairs(d.taken) do
      local i = type(t) == 'table' and t.n
      if type(i) == 'number' and i >= 1 and i <= n and i == math.floor(i) and (t.state == 'taken' or t.state == 'delivered') then
        states[i] = { state = t.state, mine = t.mine == true, by = text(t.by, 32) }
      end
    end
  end
  return { ship = d.ship, name = text(d.name, 40) or 'The ship', containers = n, states = states,
    left = type(d.left) == 'number' and d.left > 0 and d.left or 0,
    port = { id = text(p.id, 32), name = text(p.name, 40), region = text(p.region, 60) or '',
      latitude = p.latitude, longitude = p.longitude } }
end

-- The town the ship docks at: the nearest place to the port's coordinates. Go to port teleports to that town's
-- centre, which is always on land, never to the port's own coordinates, which could be on the water.
function M.portTown(ship)
  if not ship or not location.valid(ship.port) then return nil end
  places.ensure(ship.port)
  local n = places.nearest(ship.port, 1)[1]
  return n and n.place or nil
end

-- A number from text, the same on every game.
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return h
end

-- Every container of a ship: { n, from, to, km }, from the port's town to a town inland. The port's tiles of places
-- are loaded first, and every destination is within them, so every game picks the same towns.
local cache = {}
function M.containers(ship)
  local town = M.portTown(ship)
  if not town then return {} end
  local key = ship.ship .. ':' .. ship.port.id .. ':' .. ship.containers .. ':' .. town.id
  if cache.key == key then return cache.list end
  local towns = {}
  for _, d in ipairs(jobs.destinations(town, M.MAX_KM)) do
    if d.km >= M.MIN_KM then towns[#towns + 1] = d end
  end
  if #towns == 0 then towns = jobs.destinations(town, M.MAX_KM) end
  local list = {}
  if #towns > 0 then
    for i = 1, ship.containers do
      local d = towns[hash(key .. ':' .. i) % #towns + 1]
      list[i] = { n = i, from = town.id, to = d.place.id, km = d.km }
    end
  end
  cache.key, cache.list = key, list
  return list
end

function M.container(ship, n)
  return M.containers(ship)[n]
end

local function round10(n) return math.floor(n / 10 + 0.5) * 10 end

-- What a container pays for this many units of its cargo: the usual pay by weight and distance (the cargo's rate is
-- twice the usual), with the rough road bonus, and nothing for town need.
function M.pay(box, units)
  if units <= 0 then return 0 end
  local good = goods.get(M.GOOD)
  local road = jobs.roadBonus(places.get(box.from), places.get(box.to))
  return math.max(10, round10(jobs.basePay(good, units, box.km) * road))
end

return M
