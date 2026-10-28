-- Second-hand cars: each town has OFFER_COUNT cars for sale, picked from every vanilla car config
-- the game has, at PRICE_LOW to PRICE_HIGH of its new price. The picks are fixed for the town (a
-- hash of its id), so the player has to drive to another town to see different ones. Cheaper cars
-- have more kilometres on them, and are spawned looking worn to match. Pure maths; no game globals.
local jobs = require('earthFreight/jobs')
local M = {}

M.OFFER_COUNT = 2
M.PRICE_LOW, M.PRICE_HIGH = 0.70, 1.05
-- Prices are rounded to this many dollars.
M.PRICE_STEP = 100
-- A car at PRICE_HIGH has done KM_LOW; one at PRICE_LOW has done KM_HIGH.
M.KM_LOW, M.KM_HIGH = 20000, 300000
-- How worn a car looks, from 1 (new) down to LOOK_WORN at KM_HIGH and beyond.
M.LOOK_WORN = 0.8
-- Model types that are never for sale. The unicycle is the game's walking mode, not a car.
M.EXCLUDED_TYPES = { trailer = true, prop = true }
M.EXCLUDED_MODELS = { unicycle = true }

-- Whether a config from the game's list can be sold: a vanilla car or truck with a price.
function M.sellable(info)
  if type(info) ~= 'table' or type(info.model) ~= 'string' or type(info.key) ~= 'string' then return false end
  if M.EXCLUDED_MODELS[info.model] then return false end
  if type(info.type) == 'string' and M.EXCLUDED_TYPES[info.type:lower()] then return false end
  -- Mods and the player's own saved configs name another source; configs with none are kept.
  if type(info.source) == 'string' and not info.source:find('BeamNG', 1, true) then return false end
  local value = tonumber(info.value)
  return value ~= nil and value == value and value > 0 and value ~= math.huge
end

-- The sellable configs, in a fixed order, so the same town picks the same cars on every machine.
function M.candidates(list)
  local out = {}
  for _, info in ipairs(list or {}) do
    if M.sellable(info) then out[#out + 1] = info end
  end
  table.sort(out, function(a, b) return a.model .. '/' .. a.key < b.model .. '/' .. b.key end)
  return out
end

-- How worn a car with this many kilometres looks, for the game's part condition.
function M.look(km)
  local t = math.max(0, math.min(1, (km or 0) / M.KM_HIGH))
  return 1 - (1 - M.LOOK_WORN) * t
end

-- The cars for sale in a town: { id, model, key, name, preview, newPrice, price, share, km }. The
-- same place always offers the same configs; two offers are never the same config.
function M.offers(placeId, candidates)
  local out, taken = {}, {}
  local n = #(candidates or {})
  if type(placeId) ~= 'string' or n == 0 then return out end
  for slot = 1, math.min(M.OFFER_COUNT, n) do
    local pick = math.floor(jobs.hash01(placeId .. ':used:' .. slot) * n) + 1
    -- Steps on to the next config the town has not already offered.
    while taken[pick] do pick = pick % n + 1 end
    taken[pick] = true
    local info = candidates[pick]
    local t = jobs.hash01(placeId .. ':used:' .. slot .. ':price')
    local share = M.PRICE_LOW + (M.PRICE_HIGH - M.PRICE_LOW) * t
    local newPrice = math.floor(tonumber(info.value) + 0.5)
    local price = math.max(M.PRICE_STEP, math.floor(newPrice * share / M.PRICE_STEP + 0.5) * M.PRICE_STEP)
    local km = math.floor((M.KM_HIGH - (M.KM_HIGH - M.KM_LOW) * t) / 1000 + 0.5) * 1000
    out[#out + 1] = {
      id = placeId .. ':' .. slot, model = info.model, key = info.key, config = info.config,
      name = info.name or info.model, preview = info.preview,
      newPrice = newPrice, price = price, share = math.floor(price / newPrice * 100 + 0.5), km = km,
    }
  end
  return out
end

return M
