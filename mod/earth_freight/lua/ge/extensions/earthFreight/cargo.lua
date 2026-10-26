-- Cargo space and weight. Space comes from the cargo boxes and fluid tanks fitted to the vehicle
-- (BeamNG's own "Cargo Load" parts, fitted in the parts menu and paid for in the garage); a car
-- with no box still takes a couple of parcels in the boot, but fluids need a tank. The load itself is a number in the save, never
-- objects in the tray, but its weight is added to the vehicle's nodes so a heavy load really is
-- slower, brakes later and burns more fuel. A fluid is poured into the tank's own container, so it
-- sloshes. Every game call is guarded: a missing or changed one
-- means no added weight, and the delivery carries on.
local M = {}

-- One-line settings. Tune these after testing in game.
-- A car with no cargo box: parcels in the boot.
M.BOOT = { slots = 2, kg = 60 }
-- Parcel boxes by size, matched on the part's name and its display name. Slots are BeamNG's own
-- parcel slots for the Cargo Load boxes; the weight limits are ours. The first size that matches wins.
M.BOXES = {
  { size = 'xl', label = 'Cargo box XL', slots = 128, kg = 2500 },
  { size = 'l', label = 'Cargo box L', slots = 16, kg = 400 },
  { size = 'm', label = 'Cargo box M', slots = 4, kg = 200 },
  { size = 's', label = 'Cargo box S', slots = 1, kg = 50 },
}

-- Fluid tanks by size, matched like the boxes on a part that mentions cargo and a fluid tank (the
-- parts menu calls them "Cargo Load Fluid Tank ..."), never the car's own fuel tank. Only XL's
-- 800 L is from BeamNG's docs; the others are guesses until the car reports its tank's size. A tank holds as many kg
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

-- Runs inside the car. Finds the car's fluid containers: the cargoStorage entries of its jbeam
-- whose cargo types include fluid, or that sit on a fitted tank part. Each one's nodes and beams
-- (same cargoGroup and partPath) carry expressions in $volume and $density, so the part's author
-- decides how the fluid weighs and sloshes; legacy containers only list weightNodes, which share
-- the fluid's weight. tanks is the fluid part names, a set.
local CONTAINERS = [[
local okParser, parser = pcall(require, 'jbeam/expressionParser')
-- Without the parser the expressions cannot be worked out, and only legacy containers fill.
okParser = okParser and type(parser) == 'table' and type(parser.compileSafe) == 'function'
local function isFluid(c)
  for _, t in pairs(type(c.cargoTypes) == 'table' and c.cargoTypes or {}) do
    if type(t) == 'string' and t:lower():find('fluid', 1, true) then return true end
  end
  return tanks[c.partOrigin] == true
end
local function member(e, c)
  return e.cargoGroup ~= nil and tostring(e.cargoGroup) == tostring(c.groupId) and tostring(e.partPath or '') == tostring(c.partPath or '')
end
local containers, capacity = {}, 0
local storage = v and v.data and type(v.data.cargoStorage) == 'table' and v.data.cargoStorage or {}
for _, c in pairs(storage) do
  if type(c) == 'table' and c.groupId ~= nil and isFluid(c) then
    local entry = { size = math.max(0, tonumber(c.capacity) or 0), nodes = {}, beams = {}, legacy = {} }
    for _, n in pairs(okParser and type(v.data.nodes) == 'table' and v.data.nodes or {}) do
      if type(n) == 'table' and n.cid and type(n.nodeWeightFunction) == 'string' and member(n, c) then entry.nodes[#entry.nodes + 1] = n end
    end
    for _, b in pairs(okParser and type(v.data.beams) == 'table' and v.data.beams or {}) do
      if type(b) == 'table' and b.cid and member(b, c) then entry.beams[#entry.beams + 1] = b end
    end
    local weightNodes = c['weightNodes:'] or c.weightNodes
    if #entry.nodes == 0 and type(weightNodes) == 'table' then
      for _, ref in pairs(weightNodes) do
        for _, n in pairs(type(v.data.nodes) == 'table' and v.data.nodes or {}) do
          if type(n) == 'table' and n.cid and (n.cid == ref or (n.name ~= nil and n.name == ref)) then entry.legacy[#entry.legacy + 1] = n break end
        end
      end
    end
    if entry.size > 0 and (#entry.nodes + #entry.beams + #entry.legacy) > 0 then
      containers[#containers + 1] = entry
      capacity = capacity + entry.size
    end
  end
end
local function report()
  if id then obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.tanksRead(%d, %.3f) end', id, capacity)) end
end
]]

-- Runs inside the car after CONTAINERS. Puts every node it has spread weight over back to its own
-- mass and empties every fluid container. Then a fluid load fills the containers, each to the same
-- share of full, by working out their expressions; anything else (or a tank with no container)
-- spreads its weight over the nodes of the box or tank parts (each jbeam node knows its
-- partOrigin), or over the whole car when there is none. The nodes' own masses are kept in a
-- vehicle global, which a respawn clears along with the added weight.
local LOAD = [[
local extra, litres, density = %s, %s, %s
if not (v and v.data and type(v.data.nodes) == 'table' and obj and obj.setNodeMass) then return end
local base = earthFreightNodeMass or {}
earthFreightNodeMass = base
for cid, mass in pairs(base) do obj:setNodeMass(cid, mass) end
local compiled = {}
local function value(expr, volume)
  if type(expr) ~= 'string' or not okParser then return nil end
  local f = compiled[expr]
  if f == nil then
    local ok, fun, vars = pcall(parser.compileSafe, '$' .. expr)
    f = (ok and type(fun) == 'function' and type(vars) == 'table') and { fun = fun, vars = vars } or false
    compiled[expr] = f
  end
  if not f then return nil end
  f.vars['$volume'], f.vars['$density'], f.vars['$load'] = volume, density, volume * density
  local ok, result = pcall(f.fun)
  if ok and type(result) == 'number' and result == result then return result end
  return nil
end
local function call(name, ...)
  if type(obj[name]) == 'function' then pcall(obj[name], obj, ...) end
end
local function fill(c, volume)
  for _, n in ipairs(c.nodes) do
    local mass = value(n.nodeWeightFunction, volume)
    if mass then obj:setNodeMass(n.cid, mass) end
  end
  for _, n in ipairs(c.legacy) do
    if type(n.nodeWeight) == 'number' then obj:setNodeMass(n.cid, n.nodeWeight + volume * density / #c.legacy) end
  end
  for _, b in ipairs(c.beams) do
    if b.beamSpringFunction or b.beamDampFunction then
      call('setBeamSpringDamp', b.cid, value(b.beamSpringFunction, volume) or b.beamSpring or -1, value(b.beamDampFunction, volume) or b.beamDamp or -1, -1, -1)
    end
    if b.beamLimitSpringFunction or b.beamLimitDampFunction then
      call('setBoundedBeamSpringDampLimits', b.cid, value(b.beamLimitSpringFunction, volume) or b.beamLimitSpring or -1, value(b.beamLimitDampFunction, volume) or b.beamLimitDamp or -1, -1)
    end
    local strength, deform = value(b.beamStrengthFunction, volume), value(b.beamDeformFunction, volume)
    if strength then call('setBeamStrength', b.cid, strength) end
    if deform then call('setBeamDeform', b.cid, deform) end
    local short, long = value(b.beamShortBoundFunction, volume), value(b.beamLongBoundFunction, volume)
    if short then call('setBoundedBeamShortBound', b.cid, short) end
    if long then call('setBoundedBeamLongBound', b.cid, long) end
    local precompression = value(b.beamPrecompressionFunction, volume)
    if precompression then call('setPrecompressionRatio', b.cid, precompression) end
  end
end
for _, c in ipairs(containers) do fill(c, 0) end
local poured = litres > 0 and capacity > 0
if poured then
  local share = math.min(1, litres / capacity)
  for _, c in ipairs(containers) do fill(c, c.size * share) end
  extra = math.max(0, extra - math.min(litres, capacity) * density)
end
report()
if extra <= 0.001 then return end
local list = {}
for _, n in pairs(v.data.nodes) do if type(n) == 'table' and n.cid and parts[n.partOrigin] then list[#list + 1] = n end end
if #list == 0 then for _, n in pairs(v.data.nodes) do if type(n) == 'table' and n.cid then list[#list + 1] = n end end end
if #list == 0 then return end
local share = extra / #list
for _, n in ipairs(list) do
  if base[n.cid] == nil then base[n.cid] = (obj.getNodeMass and obj:getNodeMass(n.cid)) or n.nodeWeight end
  if type(base[n.cid]) == 'number' then obj:setNodeMass(n.cid, base[n.cid] + share) end
end
]]

local function partSet(list)
  local names = {}
  for _, part in ipairs(type(list) == 'table' and list or {}) do
    if type(part) == 'string' and part:match('^[%w_%-]+$') then names[#names + 1] = '["' .. part .. '"] = true' end
  end
  return '{ ' .. table.concat(names, ', ') .. ' }'
end

local function number(x)
  return string.format('%.3f', (type(x) == 'number' and x == x and x > 0 and x < math.huge) and x or 0)
end

function M.new(environment)
  local env = environment or defaults()
  local c = {}

  local function send(build)
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local idOK, id = pcall(function() return vehicle:getID() end)
    local ok, why = pcall(function() vehicle:queueLuaCommand(build(idOK and type(id) == 'number' and tostring(id) or 'nil')) end)
    if not ok then return false, 'weight_failed', tostring(why) end
    return true
  end

  -- Sets the weight the load adds to the player car, in kg (0 takes it off). parts are the names
  -- of the fitted box or tank parts it goes on. fluid is { litres, density, tanks }, tanks being
  -- the fitted tank part names: a fluid load pours into the car's fluid containers so it sloshes,
  -- and every other load empties them. The car reports its fluid capacity through tanksRead.
  -- Returns true once the command was sent.
  function c:setWeight(kg, parts, fluid)
    fluid = type(fluid) == 'table' and fluid or {}
    return send(function(id)
      return 'local id, tanks, parts = ' .. id .. ', ' .. partSet(fluid.tanks) .. ', ' .. partSet(parts) .. '\n'
        .. CONTAINERS .. string.format(LOAD, number(kg), number(fluid.litres), number(fluid.density or 1))
    end)
  end

  -- Asks the player car how many litres its fluid containers hold; the answer comes back through
  -- tanksRead. tankParts are the fitted tank part names.
  function c:readTanks(tankParts)
    return send(function(id)
      return 'local id, tanks = ' .. id .. ', ' .. partSet(tankParts) .. '\n' .. CONTAINERS .. 'report()\n'
    end)
  end

  return c
end

return M
