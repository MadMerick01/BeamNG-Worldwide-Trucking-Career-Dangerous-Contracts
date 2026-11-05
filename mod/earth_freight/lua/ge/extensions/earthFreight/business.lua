-- Real businesses as drop-offs. A town job's load can end at one real business in its town, found
-- in OpenStreetMap by the HUD (which runs in a browser and can ask the web; the game cannot).
-- One business per town and good, the same for every player, remembered so a town is only asked
-- about once. The drop-off spot is on the road outside the business, and the load is delivered
-- stopped within RADIUS metres of it. Off-road drops and dangerous contracts never use one.
-- Pure checks; the controller keeps the remembered list and the load. No game globals.
local location = require('earthFreight/location')
local M = {}

-- One-line settings.
-- Deliver stopped within this many metres of the spot outside the business.
M.RADIUS = 25
-- The HUD looks this far from the middle of the town, then once more at WIDER_METRES.
M.SEARCH_METRES, M.WIDER_METRES = 1500, 3000
-- A business further than this from its town is refused, whatever the HUD sends.
M.MAX_FROM_TOWN = 4000
-- The HUD counts down the metres once the spot is this close.
M.COUNTDOWN_METRES = 500
-- The most towns remembered; the oldest are forgotten first.
M.MAX_REMEMBERED = 3000
-- The longest name kept, in bytes.
M.MAX_NAME = 60

-- The kinds the HUD may send, and how the HUD names them.
M.KINDS = {
  supermarket = 'Supermarket', hardware = 'Hardware store', builders = "Builders' merchant",
  car_parts = 'Car parts', garage = 'Garage', warehouse = 'Warehouse', factory = 'Factory',
  fuel = 'Fuel station', farm = 'Farm', garden = 'Garden centre', depot = 'Depot',
}

function M.key(townId, goodId) return tostring(townId) .. ':' .. tostring(goodId) end

-- Text the HUD sent percent-encoded (as encodeURIComponent writes it), decoded; nil if it is not.
function M.decode(text)
  if type(text) ~= 'string' or #text > 600 or text:find("[^%w%%%-_%.!~%*'%(%)]") then return nil end
  if text:find('%%%X') or text:find('%%%x%X') or text:find('%%.?$') then return nil end
  return (text:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

local function tidyName(name)
  if type(name) ~= 'string' then return nil end
  name = name:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if #name > M.MAX_NAME then
    name = name:sub(1, M.MAX_NAME):gsub('[\128-\191]*$', ''):gsub('[\192-\255]$', ''):match('^(.-)%s*$')
  end
  if name == '' then return nil end
  return name
end

-- A clean copy of a business, or nil: a name, a known kind and a spot near its town.
function M.clean(b, town)
  if type(b) ~= 'table' or not M.KINDS[b.kind] or not location.valid(b) then return nil end
  local name = tidyName(b.name)
  if not name then return nil end
  if town then
    local d = location.distance(town, b)
    if not d or d > M.MAX_FROM_TOWN then return nil end
  end
  return { name = name, kind = b.kind, latitude = b.latitude, longitude = b.longitude }
end

-- The remembered list from its file, cleaned: { [key] = business or { none = true, at } }.
function M.remembered(saved)
  local out, count = {}, 0
  if type(saved) ~= 'table' or type(saved.towns) ~= 'table' then return out, 0 end
  for key, b in pairs(saved.towns) do
    if type(key) == 'string' and #key <= 200 and count < M.MAX_REMEMBERED then
      local at = location.finite(type(b) == 'table' and b.at) and b.at or 0
      if type(b) == 'table' and b.none == true then out[key], count = { none = true, at = at }, count + 1
      else
        local clean = M.clean(b)
        if clean then clean.at = at; out[key], count = clean, count + 1 end
      end
    end
  end
  return out, count
end

-- Adds one town to the list, forgetting the oldest when it is full.
function M.remember(list, key, entry, now)
  entry.at = now or 0
  list[key] = entry
  local keys = {}
  for k in pairs(list) do keys[#keys + 1] = k end
  if #keys <= M.MAX_REMEMBERED then return end
  table.sort(keys, function(a, b)
    if list[a].at ~= list[b].at then return list[a].at < list[b].at end
    return a < b
  end)
  for i = 1, #keys - M.MAX_REMEMBERED do list[keys[i]] = nil end
end

-- The HUD's line for a business: "Bunnings Warehouse" and its kind.
function M.label(b) return M.KINDS[b.kind] end

return M
