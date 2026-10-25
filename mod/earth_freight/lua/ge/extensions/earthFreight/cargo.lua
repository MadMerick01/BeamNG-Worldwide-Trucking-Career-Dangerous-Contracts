-- Cargo space and weight. Space comes from the cargo boxes fitted to the vehicle (BeamNG's own
-- "Cargo Load" parts, fitted in the parts menu and paid for in the garage); a car with no box
-- still takes a couple of parcels in the boot. The load itself is a number in the save, never
-- objects in the tray, but its weight is added to the vehicle's nodes so a heavy load really is
-- slower, brakes later and burns more fuel. Every game call is guarded: a missing or changed one
-- means no added weight, and the delivery carries on.
local M = {}

-- One-line settings. Tune these after testing in game.
-- A car with no cargo box: parcels in the boot.
M.BOOT = { slots = 2, kg = 60 }
-- Parcel boxes by size, matched on the part's name and its display name. Slots are BeamNG's own
-- parcel slots for the Cargo Load boxes; the weight limits are ours. The first size that matches wins.
M.BOXES = {
  { size = 'xl', label = 'Cargo box XL', slots = 128, kg = 2500 },
  { size = 'l', label = 'Cargo box L', slots = 16, kg = 600 },
  { size = 'm', label = 'Cargo box M', slots = 4, kg = 200 },
  { size = 's', label = 'Cargo box S', slots = 1, kg = 50 },
}

-- The box a fitted part is, or nil. A box's part name or display name mentions cargo and a box
-- (internal names contain cargo_load_; the parts menu calls them "Cargo Load Box S" and so on),
-- and ends in its size. A holder that seats several boxes (burnside_cargo_load_box_5M_trunk) is
-- not a box itself: its boxes are fitted as parts of their own and counted one by one.
function M.box(partName, displayName)
  if tostring(partName or ''):lower():find('box_%d') then return nil end
  local text = (tostring(partName or '') .. ' ' .. tostring(displayName or '')):lower()
  if not text:find('cargo', 1, true) or not (text:find('box', 1, true) or text:find('parcel', 1, true)) then return nil end
  for _, box in ipairs(M.BOXES) do
    if text:find('%f[%w]' .. box.size .. '%f[%W]') then return box end
  end
  return nil
end

-- The parcel space of a parts snapshot (the garage's { parts, names }): { slots, kg, boxes, parts },
-- where boxes lists the box labels and parts the box part names. With no box it is the boot.
function M.capacity(snapshot)
  local slots, kg, boxes, parts = 0, 0, {}, {}
  if type(snapshot) == 'table' and type(snapshot.parts) == 'table' then
    local names = type(snapshot.names) == 'table' and snapshot.names or {}
    local sorted = {}
    for _, part in pairs(snapshot.parts) do if type(part) == 'string' and part ~= '' then sorted[#sorted + 1] = part end end
    table.sort(sorted)
    for _, part in ipairs(sorted) do
      local box = M.box(part, names[part])
      if box then
        slots, kg = slots + box.slots, kg + box.kg
        boxes[#boxes + 1], parts[#parts + 1] = box.label, part
      end
    end
  end
  if slots == 0 then return { slots = M.BOOT.slots, kg = M.BOOT.kg, boxes = {}, parts = {}, boot = true } end
  return { slots = slots, kg = kg, boxes = boxes, parts = parts, boot = false }
end

-- How many units of a good fit in this space, by slots and by weight, and the slots and kg they take.
function M.fits(space, good)
  local units = math.max(0, math.min(math.floor(space.slots / good.slots), math.floor(space.kg / good.kg)))
  return units, units * good.slots, units * good.kg
end

local function defaults()
  return { player = function() return getPlayerVehicle(0) end }
end

-- Runs inside the car. Puts every node it has changed back to its own mass, then spreads the
-- load's weight over the nodes of the cargo box parts (each jbeam node knows its partOrigin), or
-- over the whole car when there is no box. The nodes' own masses are kept in a vehicle global,
-- which a respawn clears along with the added weight.
local WEIGHT = [[
local extra, boxes = %s, { %s }
if not (v and v.data and type(v.data.nodes) == 'table' and obj and obj.setNodeMass) then return end
local base = earthFreightNodeMass or {}
earthFreightNodeMass = base
for cid, mass in pairs(base) do obj:setNodeMass(cid, mass) end
if extra <= 0 then return end
local list = {}
for _, n in pairs(v.data.nodes) do if type(n) == 'table' and n.cid and boxes[n.partOrigin] then list[#list + 1] = n end end
if #list == 0 then for _, n in pairs(v.data.nodes) do if type(n) == 'table' and n.cid then list[#list + 1] = n end end end
if #list == 0 then return end
local share = extra / #list
for _, n in ipairs(list) do
  if base[n.cid] == nil then base[n.cid] = (obj.getNodeMass and obj:getNodeMass(n.cid)) or n.nodeWeight end
  if type(base[n.cid]) == 'number' then obj:setNodeMass(n.cid, base[n.cid] + share) end
end
]]

function M.new(environment)
  local env = environment or defaults()
  local c = {}

  -- Sets the weight the load adds to the player car, in kg (0 takes it off). boxParts are the
  -- names of the fitted box parts it goes on. Returns true once the command was sent.
  function c:setWeight(kg, boxParts)
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local names = {}
    for _, part in ipairs(type(boxParts) == 'table' and boxParts or {}) do
      if type(part) == 'string' and part:match('^[%w_%-]+$') then names[#names + 1] = '["' .. part .. '"] = true' end
    end
    local weight = (type(kg) == 'number' and kg == kg and kg > 0) and kg or 0
    local command = string.format(WEIGHT, string.format('%.3f', weight), table.concat(names, ', '))
    local ok, why = pcall(function() vehicle:queueLuaCommand(command) end)
    if not ok then return false, 'weight_failed', tostring(why) end
    return true
  end

  return c
end

return M
