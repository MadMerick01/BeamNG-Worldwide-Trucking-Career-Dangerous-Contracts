-- Dangerous contracts: about 2 km of a treacherous Earth Enduro stage, driven with a load for a big
-- pay day. Every town's board carries one; which section it is changes from town to town and after
-- every job. Taking it pays FEE to be relocated to the section's start; the load is delivered
-- stopped within the finish circle, once the section has been driven. Pure data and maths.
local location = require('earthFreight/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- Pay: PAY times what the same load pays at the base rate over a normal 5 km job.
M.PAY = 8
-- The relocation to the start, paid when the contract is taken.
M.FEE = 200
-- An insurance claim on a dangerous contract costs this instead of the usual fee.
M.INSURANCE_FEE = 4000
-- The finish circle, in metres.
M.FINISH_RADIUS = 100
-- Arriving within this many metres of the start (by the teleport) starts the contract.
M.START_RADIUS = 1000

-- The sections: the most dramatic ~2 km of each treacherous Enduro stage. Coordinates are
-- estimates, not yet checked in game, except Death Road's and Sani Pass's. km is the road length, shown on the
-- board. Fairy Meadows Road is left out until a dangerous 2 km of it is found in game.
M.LIST = {
  { id = 'death_road', name = 'Death Road', region = 'North Yungas Road, Bolivia', km = 2,
    summary = 'One-lane cliff shelf below Chuspipata, with drops of 400 m and waterfalls over the road.',
    start = { latitude = -16.2900, longitude = -67.8100 }, finish = { latitude = -16.276316, longitude = -67.794078 } },
  { id = 'sani_pass', name = 'Sani Pass', region = 'South Africa and Lesotho', km = 2,
    summary = 'The last stack of loose, steep hairpins up to Sani Top.',
    start = { latitude = -29.589268, longitude = 29.294417 }, finish = { latitude = -29.584964, longitude = 29.287562 } },
  { id = 'skippers_canyon', name = 'Skippers Canyon', region = 'Otago, New Zealand', km = 2,
    summary = 'One-lane rock-cut road down to the Skippers Bridge, high above the Shotover.',
    start = { latitude = -44.8580, longitude = 168.6950 }, finish = { latitude = -44.8444, longitude = 168.6868 } },
  { id = 'atigun_pass', name = 'Atigun Pass', region = 'Dalton Highway, Alaska', km = 2,
    summary = 'The steepest climb on the Arctic haul road, under avalanche chutes.',
    start = { latitude = 68.1180, longitude = -149.5000 }, finish = { latitude = 68.1300, longitude = -149.4790 } },
  { id = 'transfagarasan', name = 'Transfăgărășan', region = 'Făgăraș Mountains, Romania', km = 2,
    summary = 'The hairpin ladder up to the glacial lake at Bâlea Lac.',
    start = { latitude = 45.6150, longitude = 24.6110 }, finish = { latitude = 45.6033, longitude = 24.6172 } },
  { id = 'zoji_la', name = 'Zoji La', region = 'Kashmir and Ladakh, India', km = 2,
    summary = 'Muddy one-lane ledge climbing out of Baltal over the Sind valley.',
    start = { latitude = 34.2620, longitude = 75.4250 }, finish = { latitude = 34.2700, longitude = 75.4400 } },
}

local byId = {}
for _, s in ipairs(M.LIST) do byId[s.id] = s end

function M.get(id) return byId[id] end

-- The section a town's board offers for a seed (the controller's count of jobs done), from a number
-- in [0, 1) fixed for the town: neighbouring towns land on different sections, and each job done
-- moves every board on to the next one.
function M.pick(h, seed)
  local turn = math.floor(h * #M.LIST) + (tonumber(seed) or 0)
  return M.LIST[turn % #M.LIST + 1]
end

-- Whether a point is at a section's start.
function M.atStart(point, section)
  local d = section and location.distance(point, section.start)
  return d ~= nil and d <= M.START_RADIUS
end

return M
