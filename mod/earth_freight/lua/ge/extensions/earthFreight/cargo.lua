-- Cargo space and weight. Space comes from the cargo boxes and fluid tanks fitted to the vehicle
-- (BeamNG's own "Cargo Load" parts, fitted in the parts menu and paid for in the garage); a car
-- with no box still takes a couple of parcels in the boot, but fluids need a tank. The load itself is a number in the save, never
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

-- Fluid tanks by size, matched like the boxes on a part that mentions cargo and a fluid tank (the
-- parts menu calls them "Cargo Load Fluid Tank ..."), never the car's own fuel tank. Only XL's
-- 800 L is from BeamNG's docs; the others are guesses to check in game. A tank holds as many kg
-- as litres of water.
M.TANKS = {
  { size = 'xl', label = 'Fluid tank XL', litres = 800 },
  { size = 'l', label = 'Fluid tank L', litres = 400 },
  { size = 'm', label = 'Fluid tank M', litres = 200 },
  { size = 's', label = 'Fluid tank S', litres = 100 },
}

-- The tank a fitted part is, or nil.
function M.tank(partName, displayName)
  local text = (tostring(partName or '') .. ' ' .. tostring(displayName or '')):lower()
  if not text:find('cargo', 1, true) or not (text:find('fluid', 1, true) or text:find('tank', 1, true)) then return nil end
  if text:find('fuel', 1, true) or text:find('box', 1, true) then return nil end
  for _, tank in ipairs(M.TANKS) do
    if text:find('%f[%w]' .. tank.size .. '%f[%W]') then return tank end
  end
  return nil
end

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

-- The space of a parts snapshot (the garage's { parts, names }): { slots, kg, boxes, parts, litres,
-- tankKg, tanks, tankParts }, where boxes and tanks list the labels and parts and tankParts the part
-- names. With no box the parcel space is the boot.
function M.capacity(snapshot)
  local slots, kg, boxes, parts = 0, 0, {}, {}
  local litres, tanks, tankParts = 0, {}, {}
  if type(snapshot) == 'table' and type(snapshot.parts) == 'table' then
    local names = type(snapshot.names) == 'table' and snapshot.names or {}
    local sorted = {}
    for _, part in pairs(snapshot.parts) do if type(part) == 'string' and part ~= '' then sorted[#sorted + 1] = part end end
    table.sort(sorted)
    for _, part in ipairs(sorted) do
      local box = M.box(part, names[part])
      local tank = not box and M.tank(part, names[part])
      if box then
        slots, kg = slots + box.slots, kg + box.kg
        boxes[#boxes + 1], parts[#parts + 1] = box.label, part
      elseif tank then
        litres = litres + tank.litres
        tanks[#tanks + 1], tankParts[#tankParts + 1] = tank.label, part
      end
    end
  end
  local space = { slots = slots, kg = kg, boxes = boxes, parts = parts, boot = false,
    litres = litres, tankKg = litres, tanks = tanks, tankParts = tankParts }
  if slots == 0 then space.slots, space.kg, space.boot = M.BOOT.slots, M.BOOT.kg, true end
  return space
end

-- How many units of a good fit in this space, by slots (litres in a tank, for a fluid) and by
-- weight, and the slots (or litres) and kg they take.
function M.fits(space, good)
  local room, kg = space.slots, space.kg
  if good.kind == 'fluid' then room, kg = space.litres or 0, space.tankKg or 0 end
  local units = math.max(0, math.min(math.floor(room / good.slots), math.floor(kg / good.kg + 1e-9)))
  return units, units * good.slots, units * good.kg
end

-- The part names a good's weight goes on: the tanks for a fluid, the boxes for the rest.
function M.partsFor(space, good)
  if good and good.kind == 'fluid' then return space.tankParts or {} end
  return space.parts
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
