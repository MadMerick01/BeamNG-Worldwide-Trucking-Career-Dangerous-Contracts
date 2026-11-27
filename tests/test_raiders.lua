local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local P = require('earthFreight/raiderPack')
local RC = require('earthFreight/raiderCar')
local special = require('earthFreight/special')

-- A pretend game: goTo puts the Raider straight at its slot, unless frozen.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100,
    released = {}, calmed = 0 }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take()
    self.next = self.next + 1
    return self.next, 'own'
  end
  function car:place(id, px, py, pz) self.cars[id] = { x = px, y = py, z = pz, speed = 20 }; return true end
  function car:goTo(id, aim)
    local c = self.cars[id]
    if c and not c.frozen then c.x, c.y = aim.slotX, aim.slotY end
    return true
  end
  function car:state(id) return self.cars[id] end
  function car:calm() self.calmed = self.calmed + 1 end
  function car:release(id) self.released[#self.released + 1] = id; self.cars[id] = nil end
  function car:removeAll() self.removedAll = true end
  return car
end
local function random(lo, hi) if lo == 0 and hi == 1 then return 0.9 end return lo end

-- MadMerick's rules for the first test: at most four up at once.
T.eq(P.MAX, 4, 'at most four Raiders up at once')
T.eq(P.ESCAPE_METRES, 500, 'one that falls 500 m behind is gone')
T.eq(special.EMP_CHARGES, 10, 'the EMP has ten charges for the run')
local car = fakeCar()
local p = P.new(car, random)
for i = 1, 4 do T.check(p:add(i) ~= nil, 'Raider ' .. i .. ' turns up') end
local line, why = p:add(5)
T.eq(line, nil, 'a fifth is not sent'); T.eq(why, 'full', 'four is the most')
T.eq(p:up(), 4, 'four are up')
T.check(P.LINES.arrived('RFF'):find('Raider') ~= nil, 'they are called Raiders')

-- One that is stuck while you drive is down, even if it never hit you, and the next can come.
local r = p.raiders[1]
car.cars[r.id].frozen = true
car.cars[r.id].speed = 0
car.cars[r.id].x, car.cars[r.id].y = 30, 0
local t = 10
for _ = 1, 80 do t = t + 0.5; p:step(t) end
T.eq(r.state, 'DOWN', 'a stuck Raider is down')
T.eq(p:up(), 3, 'three are up')
T.check(p:add(t) ~= nil, 'so another can come')
T.eq(#p.raiders, 5, 'the downed car stays where it stopped')

-- One that falls 500 m behind is gone.
local back = p.raiders[2]
car.cars[back.id].frozen = true
car.cars[back.id].x, car.cars[back.id].y = 0, -600
local lines = {}
for _ = 1, 2 do t = t + 0.5; lines[#lines + 1] = p:step(t) end
T.eq(car.cars[back.id], nil, 'the Raider 600 m behind is put away')
local said = false
for _, l in ipairs(lines) do if l == P.LINES.escaped then said = true end end
T.check(said, 'and the HUD says it fell behind')

-- The EMP: it goes for the nearest Raider still up, and one hit stops it.
local target = p.raiders[#p.raiders]
for _, h in ipairs(p.raiders) do if h.state ~= 'DOWN' then h.metres = 80 end end
target.metres = 12
local best = p:nearestRaider()
T.eq(best.id, target.id, 'the nearest Raider'); T.eq(best.metres, 12, 'and how far')
T.eq(p:emped(target.id), P.LINES.emped, 'an EMP hit')
T.eq(target.state, 'DOWN', 'stops a Raider')
T.eq(p:emped(target.id), nil, 'and a downed one is not hit again')
T.eq(p:emped(9999), nil, 'nor a car that is not a Raider')
T.check(p:nearestRaider().id ~= target.id, 'the next nearest is another')

-- At most MAX_DOWN downed cars stand: the one down longest goes.
local car2 = fakeCar()
local p2 = P.new(car2, random)
for i = 1, P.MAX do p2:add(i) end
local first
for i = 1, P.MAX_DOWN + 1 do
  if p2:up() < P.MAX then p2:add(10 + i) end
  local up
  for _, h in ipairs(p2.raiders) do if h.state ~= 'DOWN' then up = h break end end
  first = first or up
  p2.clock = 10 + i
  p2:emped(up.id)
end
local downed = 0
for _, h in ipairs(p2.raiders) do if h.state == 'DOWN' then downed = downed + 1 end end
T.eq(downed, P.MAX_DOWN, 'only MAX_DOWN downed cars stand')
T.eq(car2.cars[first.id], nil, 'the first one down is put away')

p:clear()
T.eq(#p.raiders, 0, 'the run over, the Raiders go')
p:remove()
T.check(car.removedAll, 'and their cars are deleted')

-- raiderCar: never the player's car, nor the truck they walked away from.
local cars = {}
local function fake(id, x, y)
  local c = { id = id, x = x, y = y, active = 1, commands = {} }
  function c:getID() return self.id end
  function c:getPosition() return { x = self.x, y = self.y, z = 0 } end
  function c:getDirectionVector() return { x = 0, y = 1, z = 0 } end
  function c:getVelocity() return { x = 0, y = 0, z = 0 } end
  function c:getInitialLength() return 5 end
  function c:setActive(a) self.active = a end
  function c:queueLuaCommand(cmd) self.commands[#self.commands + 1] = cmd end
  function c:setPositionRotation(px, py) self.x, self.y = px, py end
  function c:delete() self.deleted = true; cars[self.id] = nil end
  cars[id] = c
  return c
end
local walker, truck = fake(1, 5, 5), fake(2, 0, 0)
local spawned = 50
local env = {
  player = function() return walker end,
  byId = function(id) return cars[id] end,
  random = function() return 0.2 end,
  vehicles = function()
    return { getModel = function(name) return (name == 'roamer' or name == 'van' or name == 'barstow') and { model = name } or nil end,
      spawnNewVehicle = function(name, options)
        spawned = spawned + 1
        local c = fake(spawned, 0, 0)
        c.model, c.config = name, options.config
        return c
      end }
  end,
  vec3 = function(x, y, z) return { x = x, y = y, z = z } end,
  quatFromDir = function() return {} end,
  spawn = function() return nil end,
  ground = function() return 0 end,
}
local rc = RC.new(env)
T.eq(rc:player().id, 1, 'driving, the Raiders go for the player')
rc.targetId = 2
T.eq(rc:player().id, 2, 'walking, they go for the truck')
T.eq(rc:walker().id, 1, 'the walker is still the player')
local ready = rc:preload(2)
T.eq(ready, 2, 'two cars loaded and hidden')
T.eq(cars[51].config, 'vehicles/barstow/earth_freight_raider_old1.pc', "MadMerick's rusty Barstow")
local function pick(roll, models)
  local pc = RC.new({ random = function() return roll end, vehicles = function()
    return { getModel = function(name) return models[name] and { model = name } or nil end } end })
  return pc:model()
end
local all = { barstow = true, roamer = true, van = true }
local _, cfg = pick(0.3, all)
T.eq(cfg, 'vehicles/barstow/earth_freight_raider_fast2.pc', 'the fast Barstow, a quarter of the time')
_, cfg = pick(0.6, all)
T.eq(cfg, 'vehicles/roamer/earth_freight_raider_black4wd.pc', 'the black 4WD, a quarter')
local m
m, cfg = pick(0.9, all)
T.eq(m, 'van', 'the front-cab van, a quarter'); T.eq(cfg, 'vehicles/van/earth_freight_raider_frontcab.pc', 'with its config')
T.eq(pick(0.9, { roamer = true }), 'roamer', 'without the van, the next one the game has')
m, cfg = pick(0.2, { moonhawk = true })
T.eq(m, 'moonhawk', 'with neither, a plain car'); T.eq(cfg, nil, 'with no config')
T.eq(cars[51].active, 0, 'switched off while hidden')
local id = rc:take()
T.check(id == 51 or id == 52, 'a Raider takes a hidden car')
local other = rc:take()
T.check(other ~= id and other ~= nil, 'the other hidden car next')
T.eq(rc:take(), 53, 'then one is loaded as needed')
T.eq(rc:state(2), nil, 'the truck is never a Raider')
T.eq(rc:state(1), nil, 'nor the player')
T.check(rc:place(id, 10, 10, 0, 0, 1), 'a Raider is put down')
T.eq(cars[id].active, 1, 'switched on')
T.check(rc:goTo(id, { x = 1, y = 2, z = 0, speed = 10 }), 'and driven')
T.check(cars[id].commands[#cars[id].commands]:find('earthFreightRaider.target', 1, true) ~= nil, 'by its own driver')
T.check(rc:shove(id, 10, 0), 'an EMP shoves a Raider')
T.check(cars[id].commands[#cars[id].commands]:find('applyForceVector', 1, true) ~= nil, 'with a force on its nodes')
T.eq(rc:shove(2, 0, 0), false, 'never the truck by mistake')
T.check(rc:shove(2, 0, 0, true), 'only when it is meant')
rc:removeAll()
T.eq(cars[id], nil, 'its cars deleted when the run is over')

T.done('Raiders')
