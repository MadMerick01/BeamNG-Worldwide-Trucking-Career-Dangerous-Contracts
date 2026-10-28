-- Reads and repairs the player vehicle. Base-game calls only, so it works outside career mode
-- (career's repair modules are not loaded in Earth Freeroam). Every call is guarded: a missing
-- or changed game function makes the quote or repair fail without touching the balance.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    -- GE keeps each vehicle's beamstate damage in map.objects[id].damage.
    objects = function() local m = rawget(_G, 'map'); return type(m) == 'table' and m.objects or nil end,
    manager = function() return rawget(_G, 'core_vehicle_manager') or (extensions and extensions.core_vehicle_manager) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    -- jbeam/io looks up a part's jbeam data, whose information.value is the price career uses.
    jbeam = function() return require('jbeam/io') end,
    objectById = function(id) return getObjectByID(id) end,
    enter = function(vehicle) be:enterVehicle(0, vehicle) end,
    -- BeamNG's spawn module, whose teleportToLastRoad is the recovery menu's "teleport to last road".
    spawn = function() return rawget(_G, 'spawn') or (package.loaded and package.loaded.spawn) end,
  }
end

local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- Flattens a 0.39 partsTree into { [slot path] = part name }; an empty slot has part name ''.
local function fitted(node, out)
  if type(node) ~= 'table' then return out end
  if type(node.chosenPartName) == 'string' then out[tostring(node.path or node.id or '')] = node.chosenPartName end
  if type(node.children) == 'table' then
    for _, child in pairs(node.children) do fitted(child, out) end
  end
  return out
end

function M.new(environment)
  local env = environment or defaults()
  local g = {}

  local function current()
    local ok, vehicle = pcall(env.vehicle)
    if not ok or not vehicle then return nil end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or id == nil then return nil end
    return vehicle, id
  end

  -- Returns { id, damage } for the player vehicle, or nil and a reason.
  function g:inspect()
    local vehicle, id = current()
    if not vehicle then return nil, 'vehicle_required' end
    local ok, objects = pcall(env.objects)
    local entry = ok and type(objects) == 'table' and objects[id] or nil
    local damage = type(entry) == 'table' and tonumber(entry.damage) or nil
    if not damage or damage ~= damage or damage == math.huge or damage < 0 then return nil, 'damage_unavailable' end
    return { id = id, damage = damage }
  end

  local function vehicleData(id)
    local manager = env.manager()
    if type(manager) ~= 'table' or type(manager.getVehicleData) ~= 'function' then return nil end
    local ok, data = pcall(manager.getVehicleData, id)
    return ok and type(data) == 'table' and type(data.config) == 'table' and data or nil
  end

  -- Returns { value, name } from the part's jbeam information, or nothing when unreadable.
  local function partInfo(data, partName)
    local ok, jbeam = pcall(env.jbeam)
    if not ok or type(jbeam) ~= 'table' or type(jbeam.getPart) ~= 'function' or data.ioCtx == nil then return nil end
    local partOK, part = pcall(jbeam.getPart, data.ioCtx, partName)
    local info = partOK and type(part) == 'table' and part.information or nil
    if type(info) ~= 'table' then return nil end
    local value = tonumber(info.value)
    if value and (value ~= value or value < 0 or value == math.huge) then value = nil end
    return value, type(info.name) == 'string' and info.name or nil
  end

  -- Returns the game's price (the Value in the config's info file) and a display name for a car
  -- config, given its .pc path. The price is nil when the config has none.
  function g:carValue(model, configFile)
    if type(model) ~= 'string' or model == '' then return nil end
    local key = type(configFile) == 'string' and configFile:match('([^/\\]+)%.pc$') or nil
    local vehicles = env.vehicles()
    local info
    if key and type(vehicles) == 'table' and type(vehicles.getConfig) == 'function' then
      local ok, result = pcall(vehicles.getConfig, model, key)
      info = ok and type(result) == 'table' and result or nil
    end
    local value = info and tonumber(info.Value)
    if value and (value ~= value or value < 0 or value == math.huge) then value = nil end
    local name = info and type(info.Name) == 'string' and info.Name or model
    if info and type(info.Configuration) == 'string' then name = name .. ' ' .. info.Configuration end
    return value, name
  end

  -- Every car config the game has, read once: a list of { model, key, config (its .pc path), name,
  -- value, type, source, preview }. Empty when the game's list is unreadable.
  local configList
  function g:configs()
    if configList then return configList end
    local vehicles = env.vehicles()
    if type(vehicles) ~= 'table' or type(vehicles.getConfigList) ~= 'function' then return {} end
    local ok, result = pcall(vehicles.getConfigList)
    if not ok or type(result) ~= 'table' then return {} end
    local out = {}
    for _, info in pairs(type(result.configs) == 'table' and result.configs or result) do
      local model, key = type(info) == 'table' and info.model_key, type(info) == 'table' and info.key
      if type(model) == 'string' and model ~= '' and type(key) == 'string' and key ~= '' then
        local name = type(info.Name) == 'string' and info.Name or model
        if type(info.Brand) == 'string' and info.Brand ~= '' and name:sub(1, #info.Brand) ~= info.Brand then
          name = info.Brand .. ' ' .. name
        end
        if type(info.Configuration) == 'string' then name = name .. ' ' .. info.Configuration end
        out[#out + 1] = { model = model, key = key, config = 'vehicles/' .. model .. '/' .. key .. '.pc', name = name,
          value = tonumber(info.Value), type = type(info.Type) == 'string' and info.Type or nil,
          source = type(info.Source) == 'string' and info.Source or nil,
          preview = type(info.preview) == 'string' and info.preview or nil }
      end
    end
    if #out > 0 then configList = out end
    return out
  end

  -- Makes the player vehicle look used: the game's part condition is set to this many kilometres,
  -- with the paint faded to look (1 is new). Only the looks change. Returns true once queued.
  function g:wear(km, look)
    local vehicle = current()
    if not vehicle then return false, 'vehicle_required' end
    local command = string.format('if partCondition and partCondition.initConditions then '
      .. 'partCondition.initConditions(nil, %d, nil, %.3f) end', math.floor((km or 0) * 1000), look or 1)
    local ok, why = pcall(function() vehicle:queueLuaCommand(command) end)
    if not ok then return false, 'wear_failed', tostring(why) end
    return true
  end

  -- Returns the player vehicle's fitted parts:
  -- { id, model, config, parts = { [slot] = part }, values = { [part] = price or nil }, names = { [part] = name },
  --   configFile, value, name } where value is the car's own price from carValue.
  function g:parts()
    local vehicle, id = current()
    if not vehicle then return nil, 'vehicle_required' end
    local data = vehicleData(id)
    if not data or type(data.config.partsTree) ~= 'table' then return nil, 'parts_unavailable' end
    local parts = fitted(data.config.partsTree, {})
    local values, names = {}, {}
    for _, partName in pairs(parts) do
      if partName ~= '' and names[partName] == nil then
        local value, name = partInfo(data, partName)
        values[partName], names[partName] = value, name or partName
      end
    end
    local model = data.config.model
    if type(model) ~= 'string' or model == '' then
      local ok, filename = pcall(function() return vehicle:getJBeamFilename() end)
      model = ok and filename or nil
    end
    local configFile = type(data.config.partConfigFilename) == 'string' and data.config.partConfigFilename or nil
    local value, name = g:carValue(model, configFile)
    return { id = id, model = model, config = copy(data.config), parts = parts, values = values, names = names,
      configFile = configFile, value = value, name = name or model }
  end

  -- Respawns the vehicle where it stands, which leaves every part new. With no config it keeps the
  -- current parts, tuning and paint; with one, it fits that config's parts but keeps the current
  -- tuning and paint. Returns true once the game accepted the respawn.
  function g:repair(withConfig)
    local vehicle, id = current()
    if not vehicle then return false, 'vehicle_required' end
    local vehicles = env.vehicles()
    if type(env.manager()) ~= 'table' or type(vehicles) ~= 'table' or type(vehicles.replaceVehicle) ~= 'function' then
      return false, 'repair_unavailable'
    end
    local data = vehicleData(id)
    if not data then return false, 'config_unavailable' end
    local config = data.config
    if type(withConfig) == 'table' then
      config = copy(withConfig)
      config.vars, config.paints = copy(data.config.vars), copy(data.config.paints)
    end
    local modelOK, model = pcall(function() return vehicle:getJBeamFilename() end)
    if not modelOK or type(model) ~= 'string' or model == '' then model = config.model end
    if type(model) ~= 'string' or model == '' then return false, 'config_unavailable' end
    local ok, why = pcall(vehicles.replaceVehicle, model, { config = config, keepOtherVehRotation = true }, vehicle)
    if not ok then return false, 'repair_failed', tostring(why) end
    return true
  end

  -- Puts the player vehicle back on the road it was last on, as the game's recovery menu does.
  -- Returns true once the game was asked; the move happens a moment later.
  function g:toRoad()
    local vehicle = current()
    if not vehicle then return false, 'vehicle_required' end
    local ok, spawn = pcall(env.spawn)
    if not ok or type(spawn) ~= 'table' or type(spawn.teleportToLastRoad) ~= 'function' then return false, 'road_unavailable' end
    local moved, why = pcall(spawn.teleportToLastRoad, vehicle)
    if not moved then return false, 'road_failed', tostring(why) end
    return true
  end

  -- Replaces the player vehicle where it stands with a config: a .pc file path, such as the
  -- starter car, or a saved config table. Returns true once the game accepted the spawn. A car
  -- spawned from the same file is respawned too: it may have had parts changed since.
  function g:spawnConfig(model, config)
    local vehicle = current()
    if not vehicle then return false, 'vehicle_required' end
    local vehicles = env.vehicles()
    if type(vehicles) ~= 'table' or type(vehicles.replaceVehicle) ~= 'function' then return false, 'spawn_unavailable' end
    if type(config) ~= 'string' then config = copy(config) end
    local ok, why = pcall(vehicles.replaceVehicle, model, { config = config, keepOtherVehRotation = true }, vehicle)
    if not ok then return false, 'spawn_failed', tostring(why) end
    return true
  end

  -- A part's slot types: a 0.39 part's slotType is a string, or a list of them.
  local function slotTypes(part)
    local t = type(part) == 'table' and part.slotType or nil
    if type(t) == 'string' then return { t } end
    local out = {}
    if type(t) == 'table' then
      for _, v in ipairs(t) do if type(v) == 'string' then out[#out + 1] = v end end
    end
    return out
  end

  -- The names of every part the game has for a slot type. jbeam/io's slot map is asked first,
  -- then its per-slot list; both are guarded, as their shapes are not in the API dump.
  local function partsForSlot(jbeam, ioCtx, slotType, cache)
    if cache[slotType] then return cache[slotType] end
    local names = {}
    local function add(list)
      if type(list) ~= 'table' then return end
      for k, v in pairs(list) do
        if type(v) == 'string' then names[#names + 1] = v
        elseif type(k) == 'string' and v then names[#names + 1] = k end
      end
    end
    if cache.slotMap == nil then
      local ok, map = false, nil
      if type(jbeam.getAvailableSlotNameMap) == 'function' then ok, map = pcall(jbeam.getAvailableSlotNameMap, ioCtx) end
      cache.slotMap = ok and type(map) == 'table' and map or false
    end
    if cache.slotMap then add(cache.slotMap[slotType]) end
    if #names == 0 and type(jbeam.getAvailablePartNamesForSlot) == 'function' then
      local ok, list = pcall(jbeam.getAvailablePartNamesForSlot, ioCtx, slotType)
      if ok then add(list) end
    end
    cache[slotType] = names
    return names
  end

  -- Better parts for the player vehicle: for each fitted part whose slot category(slotType) names,
  -- the cheapest part of the same slot type with a higher jbeam value. Returns a list of
  -- { path, label, current, part, name, value }, or nil and a reason.
  function g:upgrades(category)
    local vehicle, id = current()
    if not vehicle then return nil, 'vehicle_required' end
    local data = vehicleData(id)
    if not data or type(data.config.partsTree) ~= 'table' then return nil, 'parts_unavailable' end
    local ok, jbeam = pcall(env.jbeam)
    if not ok or type(jbeam) ~= 'table' or type(jbeam.getPart) ~= 'function' or data.ioCtx == nil then
      return nil, 'parts_unavailable'
    end
    local function getPart(name)
      local partOK, part = pcall(jbeam.getPart, data.ioCtx, name)
      return partOK and type(part) == 'table' and part or nil
    end
    local cache, out = {}, {}
    local function visit(node)
      if type(node) ~= 'table' then return end
      local chosen = node.chosenPartName
      local part = type(chosen) == 'string' and chosen ~= '' and getPart(chosen) or nil
      local types = slotTypes(part)
      local label = category(types[1])
      if label then
        local currentValue = tonumber(type(part.information) == 'table' and part.information.value) or 0
        local best
        for _, name in ipairs(partsForSlot(jbeam, data.ioCtx, types[1], cache)) do
          if name ~= chosen then
            local candidate = getPart(name)
            local info = candidate and candidate.information
            local value = type(info) == 'table' and tonumber(info.value) or nil
            local fits = false
            for _, t in ipairs(slotTypes(candidate)) do if t == types[1] then fits = true end end
            if fits and value and value == value and value > currentValue and value ~= math.huge
                and (not best or value < best.value) then
              best = { path = tostring(node.path or node.id or ''), label = label, current = chosen, part = name,
                name = type(info.name) == 'string' and info.name or name, value = value }
            end
          end
        end
        if best then out[#out + 1] = best end
      end
      if type(node.children) == 'table' then
        for _, child in pairs(node.children) do visit(child) end
      end
    end
    visit(data.config.partsTree)
    return out
  end

  -- Fits one part in the slot at this path and respawns the vehicle where it stands, which also
  -- mends every part. The new part's own slots are left for the game to fill with its defaults.
  -- Returns true once the game accepted the respawn.
  function g:fitPart(path, partName)
    local vehicle, id = current()
    if not vehicle then return false, 'vehicle_required' end
    local data = vehicleData(id)
    if not data or type(data.config.partsTree) ~= 'table' then return false, 'config_unavailable' end
    local config = copy(data.config)
    -- The slot's name is its key in the parent's children (and its id, when the node has one).
    local found, slotName
    local function visit(node, key)
      if type(node) ~= 'table' or found then return end
      if tostring(node.path or node.id or '') == path then found, slotName = node, node.id or key; return end
      if type(node.children) == 'table' then
        for childKey, child in pairs(node.children) do visit(child, childKey) end
      end
    end
    visit(config.partsTree)
    if not found then return false, 'slot_not_found' end
    found.chosenPartName, found.children = partName, nil
    -- The flat parts list, by slot name or path, is kept in step with the tree.
    if type(config.parts) == 'table' then
      for slot in pairs(config.parts) do
        if slot == path or slot == slotName then config.parts[slot] = partName end
      end
    end
    return g:repair(config)
  end

  -- Puts the player back in the vehicle with this id, if it still exists.
  function g:enter(id)
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle then return false, 'vehicle_gone' end
    local entered, why = pcall(env.enter, vehicle)
    if not entered then return false, 'enter_failed', tostring(why) end
    return true
  end

  return g
end

return M
