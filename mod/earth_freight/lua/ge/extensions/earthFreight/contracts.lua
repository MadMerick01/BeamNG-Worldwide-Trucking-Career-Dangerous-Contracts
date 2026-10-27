-- Dangerous contracts: about 2 km of a treacherous Earth Enduro stage, driven with a load for a big
-- pay day. Every town's board carries one; which section it is changes from town to town and after
-- every job. Taking it pays FEE to be relocated to the section's start; the load is delivered
-- stopped within the finish circle, once the section has been driven. Pure data and maths.
local location = require('earthFreight/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- The relocation to the start, paid when the contract is taken.
M.FEE = 200
-- An insurance claim on a dangerous contract costs this instead of the usual fee.
M.INSURANCE_FEE = 4000
-- The finish circle, in metres.
M.FINISH_RADIUS = 100
-- Arriving within this many metres of the start (by the teleport) starts the contract.
M.START_RADIUS = 1000

-- The sections: the most dramatic ~2 km of a treacherous Enduro stage, with start and finish
-- checked in game. km is the road length, shown on the board. pay is how many times what the same
-- load pays at the base rate over a normal 5 km job. Only checked roads are offered: left
-- out for now are Fairy Meadows Road (no dangerous 2 km found), Skippers Canyon (not dangerous
-- enough), Atigun Pass and Transfăgărășan (not checked).
M.LIST = {
  { id = 'death_road', name = 'Death Road', region = 'North Yungas Road, Bolivia', km = 2, pay = 8,
    summary = 'One-lane cliff shelf below Chuspipata, with drops of 400 m and waterfalls over the road.',
    start = { latitude = -16.2900, longitude = -67.8100 }, finish = { latitude = -16.276316, longitude = -67.794078 } },
  { id = 'sani_pass', name = 'Sani Pass', region = 'South Africa and Lesotho', km = 2, pay = 3,
    summary = 'The last stack of loose, steep hairpins up to Sani Top.',
    start = { latitude = -29.589268, longitude = 29.294417 }, finish = { latitude = -29.584964, longitude = 29.287562 } },
  { id = 'zoji_la', name = 'Zoji La', region = 'Kashmir and Ladakh, India', km = 2, pay = 4,
    summary = 'Muddy one-lane ledge climbing out of Baltal over the Sind valley.',
    start = { latitude = 34.261686, longitude = 75.423010 }, finish = { latitude = 34.261200, longitude = 75.442761 } },
}

local byId = {}
for _, s in ipairs(M.LIST) do byId[s.id] = s end

function M.get(id) return byId[id] end

-- The section a town's board offers for a seed (the controller's count of jobs done), from a number
-- in [0, 1) fixed for the town: neighbouring towns land on different sections, and each job done
-- moves every board on to the next one. Sections already delivered (done, a list of ids) are not
-- offered again; with all of them done there is none.
function M.pick(h, seed, done)
  local left, skip = {}, {}
  for _, id in ipairs(done or {}) do skip[id] = true end
  for _, s in ipairs(M.LIST) do if not skip[s.id] then left[#left + 1] = s end end
  if #left == 0 then return nil end
  local turn = math.floor(h * #left) + (tonumber(seed) or 0)
  return left[turn % #left + 1]
end

-- Whether a point is at a section's start.
function M.atStart(point, section)
  local d = section and location.distance(point, section.start)
  return d ~= nil and d <= M.START_RADIUS
end

return M
