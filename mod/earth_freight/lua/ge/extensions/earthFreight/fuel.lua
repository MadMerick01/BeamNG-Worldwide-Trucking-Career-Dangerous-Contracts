-- Fuel. BeamNG already burns fuel as you drive (more with a heavy load); this reads the player
-- car's tank and sets it, for the Refuel button and to put the tank back as it was after a
-- respawn (a repair or a part change would otherwise fill it for free). The car answers through
-- earthFreight_core.fuelReading and earthFreight_core.fuelSet. Every game call is guarded: a
-- missing or changed one means no reading, and the Refuel button stays off.
local M = {}

-- One-line settings. Tune these after testing in game.
M.PRICE_PER_LITRE = 2.10
M.READ_EVERY_SECONDS = 2
-- A reading older than this is not trusted for a refuel.
M.STALE_SECONDS = 10
-- Tanks within this many litres of full count as full.
M.FULL_MARGIN_LITRES = 0.5

local function defaults()
  return { player = function() return getPlayerVehicle(0) end }
end

-- Runs inside the car: adds up its fuel tanks (energy storages with a volume and capacity in
-- litres, leaving out batteries, nitrous and air) into litres and capacity.
local TANKS = [[
local litres, capacity, tanks = 0, 0, {}
if energyStorage and energyStorage.getStorages then
  for _, s in pairs(energyStorage.getStorages() or {}) do
    if type(s) == 'table' and type(s.capacity) == 'number' and s.capacity > 0 and type(s.remainingVolume) == 'number'
        and s.energyType ~= 'electricEnergy' and s.energyType ~= 'n2o' and s.energyType ~= 'air' then
      litres, capacity = litres + s.remainingVolume, capacity + s.capacity
      tanks[#tanks + 1] = s
    end
  end
end
]]
-- The outer string.format fills in the car's id; %% escapes the car's own format string.
local READ = TANKS .. [[
obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.fuelReading(%%d, %%.3f, %%.3f) end', %d, litres, capacity))
]]
-- Sets every tank to the same share of full, so the total is the target, and reports before and
-- after. The outer string.format fills in the target, the car's id and the serial; %% escapes the
-- car's own format string.
local SET = TANKS .. [[
local before, target = litres, math.max(0, math.min(capacity, %.3f))
for _, s in ipairs(tanks) do
  local ratio = capacity > 0 and target / capacity or 0
  if s.setRemainingRatio then s:setRemainingRatio(ratio) elseif s.setRemainingVolume then s:setRemainingVolume(ratio * s.capacity) end
end
local after = 0
for _, s in ipairs(tanks) do after = after + (s.remainingVolume or 0) end
obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.fuelSet(%%d, %%d, %%.3f, %%.3f, %%.3f) end', %d, %d, before, after, capacity))
]]

-- Whole dollars for this many litres.
function M.cost(litres)
  if type(litres) ~= 'number' or litres ~= litres or litres <= 0 then return 0 end
  return math.floor(litres * M.PRICE_PER_LITRE + 0.5)
end

function M.new(environment)
  local env = environment or defaults()
  local f = {}

  local function send(command)
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or type(id) ~= 'number' then return false, 'vehicle_required' end
    local ok, why = pcall(function() vehicle:queueLuaCommand(command(id)) end)
    if not ok then return false, 'fuel_failed', tostring(why) end
    return true
  end

  -- Asks the player car for its fuel. The answer comes back through fuelReading.
  function f:read()
    return send(function(id) return string.format(READ, id) end)
  end

  -- Sets the player car's fuel to this many litres in all. serial ties the answer, which comes
  -- back through fuelSet, to this request.
  function f:set(litres, serial)
    if type(litres) ~= 'number' or litres ~= litres or litres < 0 then return false, 'invalid_litres' end
    return send(function(id) return string.format(SET, litres, id, serial or 0) end)
  end

  return f
end

return M
