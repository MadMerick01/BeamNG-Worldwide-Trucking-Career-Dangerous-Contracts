-- Heli flights: the rules for hiring stefan750's Revamped Bell 407 (a mod the player installs
-- themselves) and flying loads under its tow hook. A fun way to see the world, not a rival to the
-- trucks: a hire costs HIRE_FEE until the player goes back to their car, and a load pays at most
-- MAX_PAY however far it goes. Pure maths; no game globals.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local M = {}

M.MOD_NAME = 'Revamped Bell 407'
M.MOD_AUTHOR = 'stefan750'
M.MOD_PAGE = 'https://www.beamng.com/threads/revamped-bell-407-with-weapons.98195/'
-- A hire lasts until the player is back in their car; hiring again costs the fee again.
M.HIRE_FEE = 1000
-- A crash ends the hire and loses the load, and costs this (or all the player's money, if less).
M.CRASH_FEE = 1000
-- From this much damage the helicopter has crashed: half of what BeamNG calls major, as for cars.
M.CRASH_DAMAGE = 15000
-- A load with this much damage hit the ground too hard and is lost.
M.SMASH_DAMAGE = 5000
-- Pay: PAY_PER_KG for each kg, in full from FULL_PAY_KM, capped at MAX_PAY (MAX_KG, the hook's limit).
M.PAY_PER_KG, M.FULL_PAY_KM, M.MAX_KG = 3, 10, 1000
M.MAX_PAY = M.PAY_PER_KG * M.MAX_KG
-- The weights a load can be, in kg.
M.WEIGHTS = { 250, 400, 550, 700, 850, 1000 }
-- Drop-offs are towns MIN_KM to MAX_KM away in a straight line.
M.MIN_KM, M.MAX_KM = 4, 40
-- A load delivers once it rests on the ground within DROP_RADIUS metres of the drop-off, still
-- for REST_SECONDS (moving less than REST_METRES), and let go of. It must have been flown there:
-- moved at least FLOWN_METRES from where it was picked up.
M.DROP_RADIUS, M.REST_SECONDS, M.REST_METRES, M.FLOWN_METRES = 40, 3, 0.3, 1000
-- A load counts as on the ground below this height (its reference point sits a little up).
M.GROUND_METRES = 3
-- A new load turns up LOAD_AHEAD metres in front of the helicopter, NEXT_LOAD_SECONDS after the last.
M.LOAD_AHEAD, M.NEXT_LOAD_SECONDS = 25, 4
-- Back to my car swaps in place within RETURN_METRES of the car, landed; farther, Earth teleports
-- there first and the swap waits for the terrain for SETTLE_SECONDS, giving up after TELEPORT_SECONDS.
M.RETURN_METRES, M.LANDED_METRES, M.SETTLE_SECONDS, M.TELEPORT_SECONDS = 150, 3, 2, 30
-- How long the helicopter, or the car coming back, has to turn up before the swap is called off.
M.SPAWN_SECONDS = 10
-- What hangs under the hook: the first of these the game has. A trailer has a tow hitch, which the
-- hook's coupler can take; any other load is lifted with BeamNG's node grabber.
M.LOAD_MODELS = { 'boxutility', 'woodcrate', 'metal_box', 'haybale' }

local function round10(n) return math.floor(n / 10 + 0.5) * 10 end

-- What a load pays: PAY_PER_KG a kg, a share of it below FULL_PAY_KM, never more than MAX_PAY.
function M.pay(kg, km)
  if not location.finite(kg) or not location.finite(km) or kg <= 0 or km <= 0 then return 0 end
  return math.min(M.MAX_PAY, round10(M.PAY_PER_KG * math.min(kg, M.MAX_KG) * math.min(1, km / M.FULL_PAY_KM)))
end

local function lower(s) return type(s) == 'string' and s:lower() or '' end
-- Configs fitted with guns are left for when nothing else is installed.
local ARMED = { 'weapon', 'armed', 'gun', 'rocket', 'military', 'missile' }
local function armed(info)
  local name = lower(info.name) .. ' ' .. lower(info.key)
  for _, word in ipairs(ARMED) do if name:find(word, 1, true) then return true end end
  return false
end

-- Whether a config from the game's list is a Bell 407: its model or name says Bell and 407.
function M.isHeli(info)
  if type(info) ~= 'table' or type(info.model) ~= 'string' or type(info.key) ~= 'string' then return false end
  local text = lower(info.model) .. ' ' .. lower(info.name)
  return text:find('407', 1, true) ~= nil and text:find('bell', 1, true) ~= nil
end

-- The Bell 407 config to hire from the game's config list, or nil when the mod is not installed:
-- one without weapons if there is one (one with a hook first), then the cheapest.
function M.findHeli(list)
  local best, bestScore
  for _, info in ipairs(list or {}) do
    if M.isHeli(info) then
      local score = (armed(info) and 2 or 0) + ((lower(info.name) .. lower(info.key)):find('hook', 1, true) and 0 or 1)
      local value = tonumber(info.value) or math.huge
      if not best or score < bestScore or (score == bestScore and (value < (tonumber(best.value) or math.huge)
          or (value == (tonumber(best.value) or math.huge) and info.model .. '/' .. info.key < best.model .. '/' .. best.key))) then
        best, bestScore = info, score
      end
    end
  end
  return best and { model = best.model, key = best.key, config = best.config, name = best.name } or nil
end

-- The load to hang under the hook: the first of LOAD_MODELS in the game's list, its cheapest config.
function M.findLoad(list)
  for _, model in ipairs(M.LOAD_MODELS) do
    local best
    for _, info in ipairs(list or {}) do
      if type(info) == 'table' and info.model == model and type(info.key) == 'string'
          and (not best or info.key < best.key) then best = info end
    end
    if best then return { model = best.model, key = best.key, config = best.config, name = best.name } end
  end
  return nil
end

-- A flight from a point: a town MIN_KM to MAX_KM away, a weight, and its pay. pick(n) gives a
-- whole number from 1 to n. Away from towns it is a spot in open country, named by its direction.
function M.flight(from, pick, except)
  local towns = {}
  for _, p in ipairs(places.within(from, M.MAX_KM * 1000)) do
    local d = location.distance(from, p)
    if p.id ~= except and d and d >= M.MIN_KM * 1000 and d <= M.MAX_KM * 1000 then towns[#towns + 1] = p end
  end
  table.sort(towns, function(a, b) return a.id < b.id end)
  local kg = M.WEIGHTS[pick(#M.WEIGHTS)]
  local to
  if #towns > 0 then
    local p = towns[pick(#towns)]
    to = { id = p.id, name = p.name, region = p.region, latitude = p.latitude, longitude = p.longitude }
  else
    local km = M.MIN_KM + pick(M.MAX_KM - M.MIN_KM)
    local bearing = (pick(8) - 1) * 45
    local spot = location.destination(from, bearing, km * 1000)
    to = { name = 'A spot ' .. km .. ' km ' .. location.compassPoint(bearing), latitude = spot.latitude, longitude = spot.longitude }
  end
  local km = location.distance(from, to) / 1000
  return { to = to, kg = kg, km = km, pay = M.pay(kg, km) }
end

return M
