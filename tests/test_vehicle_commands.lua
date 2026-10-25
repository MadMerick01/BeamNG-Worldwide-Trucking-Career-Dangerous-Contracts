local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
-- The cargo weight and fuel commands run inside the car. Each is run here against a stand-in car:
-- nodes with masses, fuel tanks, and obj:queueGameEngineLua answering the game side.
local cargo = require('earthFreight/cargo')
local fuel = require('earthFreight/fuel')

local function car(id)
  local c = { commands = {}, id = id or 7 }
  function c:getID() return self.id end
  function c:queueLuaCommand(command) self.commands[#self.commands + 1] = command end
  return c
end
-- Runs a car command with its own globals; returns what it sent back to the game side.
local function run(command, world)
  local replies = {}
  world.obj = world.obj or {}
  world.obj.queueGameEngineLua = function(_, text) replies[#replies + 1] = text end
  setmetatable(world, { __index = _G })
  local chunk = assert(loadstring(command))
  setfenv(chunk, world)
  chunk()
  return replies
end

-- Weight: spread over the box's nodes, put back to the nodes' own masses when it changes.
do
  local vehicle = car()
  local w = cargo.new({ player = function() return vehicle end })
  T.check(w:setWeight(100, { 'pickup_cargo_load_box_m' }), 'weight sent')
  local masses = { [0] = 10, [1] = 10, [2] = 5 }
  local world = {
    v = { data = { nodes = { [0] = { cid = 0, partOrigin = 'pickup_cargo_load_box_m' }, [1] = { cid = 1, partOrigin = 'pickup_cargo_load_box_m' },
      [2] = { cid = 2, partOrigin = 'pickup_body' } } } },
    obj = { setNodeMass = function(_, cid, m) masses[cid] = m end, getNodeMass = function(_, cid) return masses[cid] end },
  }
  run(vehicle.commands[1], world)
  T.eq(masses[0], 60, 'half the load on each box node'); T.eq(masses[2], 5, 'body node untouched')
  w:setWeight(40, { 'pickup_cargo_load_box_m' }); run(vehicle.commands[2], world)
  T.eq(masses[0], 30, 'a new weight replaces the old, not added to it')
  w:setWeight(0, {}); run(vehicle.commands[3], world)
  T.eq(masses[0], 10, 'no load: own mass back'); T.eq(masses[1], 10, 'both nodes')
  -- No box: over the whole car.
  w:setWeight(25, {}); run(vehicle.commands[4], world)
  T.eq(masses[2], 5 + 25 / 3, 'boot load spread over the car')
  T.check(not vehicle.commands[5], 'nothing else sent')
  w:setWeight(10, { 'bad"]] os.exit() --' }); T.check(not vehicle.commands[5]:find('os.exit', 1, true), 'part names are never pasted into the command unchecked')
  T.eq(select(2, cargo.new({ player = function() return nil end }):setWeight(10, {})), 'vehicle_required', 'needs a car')
  run(vehicle.commands[5], { v = {}, obj = {} }) -- a car without nodes: nothing happens, no error
end

-- Fuel: read adds up the fuel tanks, leaving out batteries; set fills them and reports.
do
  local vehicle = car(7)
  local f = fuel.new({ player = function() return vehicle end })
  local function tank(volume, capacity, energyType)
    local t = { remainingVolume = volume, capacity = capacity, energyType = energyType or 'gasoline' }
    function t:setRemainingRatio(r) self.remainingVolume = r * self.capacity end
    return t
  end
  local storages = { main = tank(10, 40), aux = tank(5, 20), battery = tank(1, 1, 'electricEnergy') }
  local world = { energyStorage = { getStorages = function() return storages end } }
  T.check(f:read(), 'read sent')
  local replies = run(vehicle.commands[1], world)
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelReading(7, 15.000, 60.000) end', 'reports litres and capacity')
  T.check(f:set(45, 3), 'set sent')
  replies = run(vehicle.commands[2], world)
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelSet(7, 3, 15.000, 45.000, 60.000) end', 'reports before and after')
  T.eq(storages.main.remainingVolume, 30, 'tanks filled to the same share'); T.eq(storages.aux.remainingVolume, 15, 'both tanks')
  T.eq(storages.battery.remainingVolume, 1, 'battery left alone')
  T.check(f:set(500, 4), 'over-full request sent'); run(vehicle.commands[3], world)
  T.eq(storages.main.remainingVolume, 40, 'never past full')
  replies = run(vehicle.commands[1], {})
  T.eq(replies[1], 'if earthFreight_core then earthFreight_core.fuelReading(7, 0.000, 0.000) end', 'a car with no tank reads empty')
  T.eq(select(2, f:set(-1)), 'invalid_litres', 'negative litres refused')
  T.eq(fuel.cost(10), math.floor(10 * fuel.PRICE_PER_LITRE + 0.5), 'cost per litre')
end
T.done('vehicle commands')
