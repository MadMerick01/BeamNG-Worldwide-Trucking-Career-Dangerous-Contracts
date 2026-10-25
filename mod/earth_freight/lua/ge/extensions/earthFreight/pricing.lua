-- Garage prices, lifted from Enduro: repairs scaled by the car's game Value, parts bills and car
-- trade-ins. Pure maths; no game globals. Tune these after testing in game.
local M = {}

-- Repair pricing from the vehicle's overall damage (BeamNG's own traffic code treats about 50 as a
-- scratch, 1000 as moderate and 30000 as major), scaled by what the car is worth: a car with a
-- game Value of REFERENCE_CAR_VALUE pays REPAIR_COST_PER_DAMAGE per point, a car worth half that
-- pays half. A repair never costs more than MAX_REPAIR_SHARE of the car's Value (the call-out fee
-- aside).
M.REPAIR_MIN_DAMAGE = 50
M.REPAIR_CALLOUT_FEE = 100
M.REPAIR_COST_PER_DAMAGE = 0.5
M.REFERENCE_CAR_VALUE = 25000
M.MAX_REPAIR_SHARE = 0.75
-- Part pricing: a part's jbeam value, or a flat price when it has none. Parts taken off in the same
-- change are traded in for a share of their value, which can lower the bill but never pays out.
M.DEFAULT_PART_PRICE = 250
M.PART_TRADE_IN_SHARE = 0.3
-- Car pricing: a car config's game Value, or a flat price when it has none. The car you leave is
-- traded in for a share of its Value, less the repair it needs; a trade-in is never below $0.
M.DEFAULT_CAR_PRICE = 10000
M.CAR_TRADE_IN_SHARE = 0.5

-- The car's Value for repair pricing: its game Value, or the dealer's flat price when it has none.
local function repairValue(value)
  if type(value) ~= 'number' or value ~= value or value <= 0 or value == math.huge then return M.DEFAULT_CAR_PRICE end
  return value
end

-- Dollars per damage point for a car worth this much.
function M.repairRate(value)
  return M.REPAIR_COST_PER_DAMAGE * repairValue(value) / M.REFERENCE_CAR_VALUE
end

-- Whole-dollar price to repair a car worth carValue with this much damage; 0 means nothing to repair.
function M.repairCost(damage, carValue)
  if type(damage) ~= 'number' or damage ~= damage or damage < M.REPAIR_MIN_DAMAGE then return 0 end
  local value = repairValue(carValue)
  local parts = math.min(damage * M.repairRate(value), value * M.MAX_REPAIR_SHARE)
  return math.floor(M.REPAIR_CALLOUT_FEE + parts + 0.5)
end

-- Compares the paid-for parts with the fitted ones. Returns { added, removed, cost } or nil when
-- they match; added and removed list { name, price }.
function M.partsDiff(owned, fitted)
  local added, removed, seen = {}, {}, {}
  local function price(snapshot, part)
    local value = snapshot.values and snapshot.values[part]
    return math.floor((value or M.DEFAULT_PART_PRICE) + 0.5)
  end
  local function name(snapshot, part) return snapshot.names and snapshot.names[part] or part end
  local function compare(slot)
    if seen[slot] then return end
    seen[slot] = true
    local before, after = owned.parts[slot] or '', fitted.parts[slot] or ''
    if before == after then return end
    if after ~= '' then added[#added + 1] = { name = name(fitted, after), price = price(fitted, after) } end
    if before ~= '' then removed[#removed + 1] = { name = name(owned, before), price = price(owned, before) } end
  end
  for slot in pairs(owned.parts) do compare(slot) end
  for slot in pairs(fitted.parts) do compare(slot) end
  if #added == 0 and #removed == 0 then return nil end
  local byName = function(a, b) return a.name < b.name end
  table.sort(added, byName); table.sort(removed, byName)
  local total = 0
  for _, part in ipairs(added) do total = total + part.price end
  for _, part in ipairs(removed) do total = total - part.price * M.PART_TRADE_IN_SHARE end
  return { added = added, removed = removed, cost = math.max(0, math.floor(total + 0.5)) }
end

-- Whole dollars with thousands separators, such as $12,500.
function M.dollars(amount)
  local text = tostring(math.floor(amount))
  repeat
    local n
    text, n = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
  until n == 0
  return '$' .. text
end

return M
