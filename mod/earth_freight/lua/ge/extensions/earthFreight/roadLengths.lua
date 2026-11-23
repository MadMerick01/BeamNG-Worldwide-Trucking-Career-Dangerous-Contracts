-- Real road lengths between towns, measured by BeamNG.Earth's GPS. The board's distances are an
-- estimate (the straight line times places.ROAD_FACTOR), which pays winding mountain roads far too
-- little (MadMerick, 22 Nov: "a 6 km winding rough road job might be 20 km of road"). Earth's GPS
-- plans the whole road route on its companion app however far it goes, so when the player presses a
-- job's GPS button, or takes a job, the route Earth plans gives the real length. It is remembered for
-- that pair of towns, both ways, and from then on the job is shown and paid by it: never less than the
-- estimate, so a job never pays less than the board said.
-- Which towns a board sends jobs to, its Short, Medium and Long bands and its Distance filter stay on
-- the estimate, so measuring a road never moves a job off the board under the player.
local M = {}

-- A measured route is only believed between MIN_RATIO and MAX_RATIO times the straight line from
-- where it was planned: shorter is not a road, much longer is a ferry or a road Earth could not
-- reach. Routes under MIN_METRES straight (already at the town) are not measured.
M.MIN_RATIO, M.MAX_RATIO, M.MIN_METRES = 0.9, 4, 300
-- How long to wait for Earth to plan a route before giving up, and how often to look.
M.WAIT_SECONDS, M.CHECK_SECONDS = 60, 1
-- At most this many town pairs are kept: the oldest measured go first.
M.MAX_PAIRS = 2000

local function finite(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

-- The key of a pair of towns, the same both ways.
function M.key(a, b)
  if type(a) ~= 'string' or type(b) ~= 'string' or a == b then return nil end
  if a > b then a, b = b, a end
  return a .. '>' .. b
end

-- A route's length in km if it is believable for this straight-line distance, else nil.
function M.accept(routeMetres, straightMetres)
  if not finite(routeMetres) or not finite(straightMetres) or straightMetres < M.MIN_METRES then return nil end
  local ratio = routeMetres / straightMetres
  if ratio < M.MIN_RATIO or ratio > M.MAX_RATIO then return nil end
  return routeMetres / 1000
end

-- The road km of a pair, or nil when it has not been measured.
function M.lookup(list, a, b)
  local key = M.key(a, b)
  local entry = key and type(list) == 'table' and list[key]
  return type(entry) == 'table' and finite(entry.km) and entry.km > 0 and entry.km or nil
end

-- Remembers a pair's road km, measured at time now. Keeps the newest MAX_PAIRS.
function M.remember(list, a, b, km, now)
  local key = M.key(a, b)
  if not key or not finite(km) or km <= 0 then return false end
  list[key] = { km = math.floor(km * 100 + 0.5) / 100, at = finite(now) and now or 0 }
  local keys = {}
  for k in pairs(list) do keys[#keys + 1] = k end
  if #keys > M.MAX_PAIRS then
    table.sort(keys, function(x, y)
      local ax, ay = list[x].at or 0, list[y].at or 0
      if ax ~= ay then return ax < ay end
      return x < y
    end)
    for i = 1, #keys - M.MAX_PAIRS do list[keys[i]] = nil end
  end
  return true
end

-- The saved list, cleaned: anything odd in the file is left out.
function M.clean(saved)
  local out = {}
  local pairsTable = type(saved) == 'table' and saved.pairs
  if type(pairsTable) ~= 'table' then return out end
  for key, entry in pairs(pairsTable) do
    if type(key) == 'string' and #key <= 200 and key:find('>', 1, true) and type(entry) == 'table'
        and finite(entry.km) and entry.km > 0 and entry.km < 100000 then
      out[key] = { km = entry.km, at = finite(entry.at) and entry.at or 0 }
    end
  end
  return out
end

-- The km a job is paid by: the measured road, but never less than the board's estimate.
function M.payKm(estimateKm, roadKm)
  if not finite(roadKm) then return estimateKm end
  return math.max(estimateKm or 0, roadKm)
end

return M
