-- Road punctures: now and then a tyre bursts, as bad luck from the road.
-- The chance is per kilometre driven, goes up with speed and doubles off road. The core controller
-- decides when; this file holds the settings and the game calls that burst a tyre and tell whether
-- the car is off road. Every game call is guarded, so a missing or changed function means no
-- puncture (or no off-road bonus) and the drive carries on.
local M = {}

-- One-line settings. Tune these after testing in game.
M.AVERAGE_KM = 40 -- about one puncture per this many km, at REFERENCE_KMH on the road
M.REFERENCE_KMH = 70
-- The speed factor is the speed over REFERENCE_KMH, kept within these, so crawling still has a
-- small chance and flat out is at most this much riskier.
M.MIN_SPEED_FACTOR, M.MAX_SPEED_FACTOR = 0.25, 2.5
M.OFF_ROAD_MULTIPLIER = 2
-- Off road: further than this from the edge of the nearest road in the game's road map.
M.OFF_ROAD_METRES = 10
M.OFF_ROAD_CHECK_SECONDS = 1 -- how often the road map is asked
M.GAP_KM = 5 -- no second puncture within this far of the last one
M.SAFE_FINISH_METRES = 1000 -- none this close to the delivery destination
M.TYRE_REPAIR_COST = 300 -- added to the repair, which puts the tyre right; on a $25,000 car, scaled by Value
M.SHOWN_FOR = 6 -- seconds the HUD shows "Puncture!"

-- The chance of a puncture over this many metres at this speed (km/h), on or off road.
function M.chance(metres, kmh, offRoad)
  if type(metres) ~= 'number' or metres <= 0 or type(kmh) ~= 'number' or kmh ~= kmh then return 0 end
  local speed = math.max(M.MIN_SPEED_FACTOR, math.min(M.MAX_SPEED_FACTOR, kmh / M.REFERENCE_KMH))
  local rate = speed * (offRoad and M.OFF_ROAD_MULTIPLIER or 1) / (M.AVERAGE_KM * 1000)
  return math.min(1, metres * rate)
end

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    map = function() return rawget(_G, 'map') end,
  }
end

-- Runs inside the car. beamstate.deflateRandomTire is what the game's own "deflate random tyre"
-- fun-stuff action calls (core_funstuff in the 0.39 dump); deflateTire on a random wheel is the
-- fallback. Both are the car's own puncture, so it pulls to one side and the tyre flops on the rim.
local BURST = 'if beamstate then if beamstate.deflateRandomTire then beamstate.deflateRandomTire() '
  .. 'elseif beamstate.deflateTire and wheels and wheels.wheelRotators then '
  .. 'local n = tableSizeC and tableSizeC(wheels.wheelRotators) or 0 '
  .. 'if n > 0 then beamstate.deflateTire(math.random(0, n - 1)) end end end'

function M.new(environment)
  local env = environment or defaults()
  local p = {}

  local function player()
    local ok, vehicle = pcall(env.player)
    if ok and vehicle then return vehicle end
  end

  -- Bursts a random tyre on the player car. Returns true once the command was sent.
  function p:burst()
    local vehicle = player()
    if not vehicle then return false, 'vehicle_required' end
    local ok, why = pcall(function() vehicle:queueLuaCommand(BURST) end)
    if not ok then return false, 'burst_failed', tostring(why) end
    return true
  end

  -- Whether the player car is off road: further than OFF_ROAD_METRES from the edge of the nearest
  -- road in the game's road map (map.findClosestRoad). nil when there is no road map to ask.
  function p:offRoad()
    local vehicle = player()
    local okMap, roads = pcall(env.map)
    if not vehicle or not okMap or type(roads) ~= 'table' or type(roads.findClosestRoad) ~= 'function' then return nil end
    local okPos, pos = pcall(function() return vehicle:getPosition() end)
    if not okPos or not pos then return nil end
    local found = { pcall(roads.findClosestRoad, pos) }
    if not found[1] then return nil end
    -- It returns the two nodes of the nearest road segment and the distance to it.
    local nodeA, distance
    for i = 2, #found do
      local value = found[i]
      if type(value) == 'number' and distance == nil then distance = value
      elseif value ~= nil and nodeA == nil and type(value) ~= 'number' then nodeA = value end
    end
    if type(distance) ~= 'number' or distance ~= distance then return nil end
    local halfWidth = 0
    if nodeA ~= nil and type(roads.getMap) == 'function' then
      local okGraph, graph = pcall(roads.getMap)
      local node = okGraph and type(graph) == 'table' and type(graph.nodes) == 'table' and graph.nodes[nodeA]
      if type(node) == 'table' and type(node.radius) == 'number' then halfWidth = node.radius end
    end
    return distance > halfWidth + M.OFF_ROAD_METRES
  end

  return p
end

return M
