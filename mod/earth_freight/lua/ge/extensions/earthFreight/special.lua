-- The special delivery (MadMerick, 26 Nov): rival clans are fighting for control of the Rub' al Khali, the Empty
-- Quarter, south of the Strait of Hormuz. A sheikh needs precursor ordnance chemicals dropped at the Shed in the
-- Desert, and pays PAY_TIMES the wholesale price. The player buys the precursors with their own money, solid in
-- cargo boxes or fluid in a tank, as much as their car carries; is moved to START with a full tank; and drives
-- KM north across the dunes, by the arrow, to the shed. The load always stays whole: either it reaches the shed
-- and is paid, or the player gives up, loses the lot and is put back where they took it.
--
-- It rides on the dangerous contract's code (contracts.lua): SECTION is a contract section that contracts.get
-- finds but the boards' rotation never picks. Hidden while it is tested: only shown when OPEN is true, to the
-- server's admins online, or in single player with "specialDelivery": true in settings/earthFreight/config.json.
-- The Raiders and the player's EMP against them are in desertRun.lua; the shed itself comes in a later build. Pure
-- data and maths.
local location = require('earthFreight/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- true shows the special delivery to everyone.
M.OPEN = true
-- What the shed pays, as a multiple of what the load cost.
M.PAY_TIMES = 6
-- What the precursors cost: solid by the kg, fluid by the litre.
M.PRICE_PER_KG, M.PRICE_PER_LITRE = 60, 45
-- The most a load may cost (MadMerick, 27 Nov: a cap, so no truck or tank pays a fortune). The shed pays at most
-- PAY_TIMES this. A car that carries more takes only as many units as this buys. The server checks it too.
M.MAX_COST = 100000
-- The start, and how far north the shed is.
M.START = { latitude = 21.177270, longitude = 53.517038 }
M.KM = 20
M.FINISH = location.destination(M.START, 0, M.KM * 1000)
-- After the free full tank at the start goes in, a rise in the fuel gauge for this long is that fill, not a reset to
-- undo (core.lua's fuelReading).
M.FILL_SECONDS = 15
-- The EMP charges the player has for the whole run, and no more (MadMerick, 27 Nov, in place of the revolver).
M.EMP_CHARGES = 3
-- At most this many runs delivered in any DAY_SECONDS, by the real clock (MadMerick, 27 Nov).
M.RUNS_PER_DAY, M.DAY_SECONDS = 2, 86400
-- The two loads, as goods (goods.lua): solid and fluid.
M.GOODS = { 'precursors', 'precursors_fluid' }

-- Dollars as players read them: $100,000.
local function money(n)
  local digits = tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return '$' .. digits
end

-- Online, MadMerick's server checks the special delivery's money in every save (the private trucking-server repo):
-- why it refused one, in words for the HUD.
M.REFUSED = {
  special_hidden = 'the dangerous contract is only open to the server\'s admins for now',
  special_price = 'the precursors cost less than the sheikh\'s price',
  special_pay = 'it was paid more than ' .. M.PAY_TIMES .. ' times what the load cost',
  special_too_big = 'the load cost more than the ' .. money(M.MAX_COST) .. ' a run may carry',
  special_too_fast = 'the load reached the shed too soon to have driven the ' .. M.KM .. ' km',
}

M.SECTION = {
  id = 'shed_in_the_desert', name = 'the Shed in the Desert', region = "Rub' al Khali, the Empty Quarter",
  km = M.KM, special = true,
  summary = 'Rival clans are fighting for control of the Empty Quarter, south of the Strait of Hormuz. A sheikh needs '
    .. 'precursor ordnance chemicals dropped at the Shed in the Desert, ' .. M.KM .. ' km north across the dunes. Expect hostile Raiders. Your EMP has ' .. M.EMP_CHARGES .. ' charges for the whole run. At most '
    .. M.RUNS_PER_DAY .. ' successful runs a day. You can take up to ' .. money(M.MAX_COST) .. ' of precursors, so a run pays at most '
    .. money(M.MAX_COST * M.PAY_TIMES) .. '.',
  start = M.START, finish = M.FINISH,
}

-- Whether the special delivery is shown. admin: this player is one of the server's admins. online: playing on a
-- BeamMP server, where the config switch doesn't count. switch: config.json's specialDelivery.
function M.visible(online, admin, switch)
  if M.OPEN then return true end
  if online then return admin == true end
  return switch == true
end

-- The runs delivered in the last DAY_SECONDS before now (times in seconds), oldest first, and when the next run opens
-- if none are left (nil otherwise).
function M.recentRuns(times, now)
  local recent = {}
  for _, t in ipairs(times or {}) do
    if type(t) == 'number' and now - t < M.DAY_SECONDS and t <= now then recent[#recent + 1] = t end
  end
  table.sort(recent)
  local opensAt = #recent >= M.RUNS_PER_DAY and recent[#recent - M.RUNS_PER_DAY + 1] + M.DAY_SECONDS or nil
  return recent, opensAt
end

-- What one unit of a good costs, in dollars: its weight for solid precursors, its litres for fluid.
function M.unitPrice(good)
  if not good then return 0 end
  if good.kind == 'fluid' then return (good.litres or 0) * M.PRICE_PER_LITRE end
  return math.floor(good.kg * M.PRICE_PER_KG + 0.5)
end

-- The most units of a good one run may take: as many as MAX_COST buys.
function M.maxUnits(good)
  local price = M.unitPrice(good)
  if price <= 0 then return 0 end
  return math.floor(M.MAX_COST / price)
end

-- What this many units cost, and what the shed pays for them.
function M.cost(good, units) return M.unitPrice(good) * math.max(0, math.floor(units or 0)) end
function M.pay(cost) return cost * M.PAY_TIMES end

-- The special delivery's jobs on a board: one for each form, taken here and delivered at the shed.
function M.jobs(from)
  local out = {}
  for _, id in ipairs(M.GOODS) do
    out[#out + 1] = { id = 'special_' .. id, good = id, from = from.id, to = from.id, km = M.KM,
      contract = M.SECTION.id, special = true, drop = location.copy(M.FINISH) }
  end
  return out
end

return M
