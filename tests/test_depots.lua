local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local depots = require('earthFreight/depots')
local places = require('earthFreight/places')
local location = require('earthFreight/location')

-- The tries: the same every time for a town, nearest first, all the way round.
do
  local a, b = depots.tries('town:x'), depots.tries('town:x')
  T.eq(#a, #depots.RINGS * depots.BEARINGS, 'every ring, every way round')
  T.eq(a[1].bearing, b[1].bearing, 'the same start for the same town')
  T.check(a[1].bearing ~= depots.tries('town:y')[1].bearing, 'another town starts another way')
  T.eq(a[1].metres, depots.RINGS[1], 'nearest first')
end

-- A spot: set back from the road on flat ground; a building or unloaded ground there is not.
do
  local w = F.depotWorld()
  local spot = depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 })
  T.check(type(spot) == 'table', 'flat ground beside the road is clear')
  T.near(spot.y, w.roadRadius + depots.SETBACK, 1e-6, 'the desk is set back from the road')
  T.near(spot.ny, 1, 1e-6, 'facing the road, on the side the try was')
  w.boxes = { { -30, 5, 30, 40, 8 } }
  local blocked, near = depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 })
  T.eq(blocked, false, 'a building behind the desk blocks it'); T.check(near.rise > depots.MAX_RISE, 'it rises too much')
  T.check(type(depots.check(w, 0, 0, 0, { metres = 40, bearing = 180 })) == 'table', 'the other side of the road is clear')
  w.unloaded = true
  T.eq(depots.check(w, 0, 0, 0, { metres = 40, bearing = 180 }), 'wait', 'unloaded ground is tried again later')
end

-- A town's depot: put down near the middle of town, taken at its computer on foot with the truck close.
do
  local w = F.depotWorld()
  local c, _, a, g, cargo = F.controller({ depotWorld = w })
  w.follow, w.origin = a, F.copy(F.PENRITH)
  g.fitted.box = 'pickup_cargo_load_box_m'
  c.now = function() return 50000 end
  w.cars[1] = { x = 0, y = 0, z = 0 }
  for _ = 1, 40 do c:tick(0.6) end
  T.eq(w:count(), 4, 'the shed, desk, computer and its screen are put down')
  local shapes = {}
  for _, o in pairs(w.objects) do shapes[o.shape] = o end
  T.check(shapes.shed and shapes.desk and shapes.computer and shapes.screen, 'one of each')
  T.near(shapes.shed.fx * shapes.shed.fx, 1, 1e-6, 'the shed runs along the road')
  T.near(math.abs(shapes.desk.fy), 1, 1e-6, 'the desk faces the road')
  local v = c:view()
  T.eq(v.here.name, 'Penrith', 'in Penrith')
  T.check(v.town.takeProblem and v.town.takeProblem:find('depot computer'), 'in the car, jobs are taken at the depot computer')
  T.check(v.computer and v.computer.depot and v.computer.depot.distanceMetres, 'the HUD says how far it is')
  T.check(v.computer.depot.letters ~= nil, 'and which way')
  T.eq(v.computer.depot.arrow, nil, 'no arrow before the game says which way the player faces')
  c.heading = 90
  local d = c:view().computer.depot
  local b = location.bearing(F.PENRITH, c.depotsBuilt[next(c.depotsBuilt)].pcGeo)
  T.near(d.arrow, (b - 90) % 360, 1, 'the arrow turns with the way the player faces')
  T.check(v.computer.depot.gpsAllowed, 'and a GPS button')
  T.check(c:gpsToTownDepot(), 'the GPS is set to the depot')
  T.eq(a.gps[#a.gps].name, 'Penrith depot', 'by name')
  local built0 = c.depotsBuilt[next(c.depotsBuilt)]
  T.near(location.distance(a.gps[#a.gps], built0.pcGeo), 0, 1e-6, 'at its computer')
  T.check(location.distance(F.PENRITH, built0.pcGeo) > 30, 'which is away from the middle of town')
  T.check(c:view().computer.depot.gps, 'the GPS button shows it is set')
  for _, j in ipairs(v.town.jobs) do T.check(not j.allowed, j.id .. ' cannot be taken from the car') end
  local id = v.town.jobs[1].id
  T.check(not c:takeJob(id), 'Take job from the car is refused')
  local key = next(c.depotsBuilt)
  T.eq(key, 'town:' .. v.here.id, "it is Penrith's")
  local pc = c.depotsBuilt[key].pc
  -- Out and walking up to it, the truck parked 10 m from the computer.
  g.walking = true
  w.cars[1] = { x = pc.x, y = pc.y - 10, z = 0 }
  w.me = { x = pc.x + depots.USE_METRES + 1, y = pc.y, z = 0 }
  c:tick(0.6)
  T.check(not c:view().computer.near, 'a step too far: no Use computer yet')
  w.me = { x = pc.x + 1, y = pc.y - 1, z = 0 }
  c:tick(0.6)
  v = c:view()
  T.check(v.computer.near, 'at the desk: Use computer')
  T.eq(v.computer.name, 'Penrith', 'the depot is named after the town'); T.eq(v.computer.town, v.town.id, 'with its jobs')
  T.eq(v.computer.truckAway, 10, 'the truck is 10 m away'); T.check(v.computer.truckOk, 'close enough')
  T.check(v.town.jobs[1].allowed, 'the job can be taken now')
  -- The truck too far: no load.
  w.cars[1] = { x = pc.x, y = pc.y - 35, z = 0 }
  c:tick(0.6)
  T.check(not c:takeJob(id), 'refused with the truck 35 m away')
  T.check(c:view().tradeFeedback:find('35 m'), 'told how far it is')
  w.cars[1] = { x = pc.x, y = pc.y - 25, z = 0 }
  c:tick(0.6)
  local weights = #cargo.weights
  T.check(c:takeJob(id), 'taken at the computer with the truck 25 m away')
  T.check(c.load ~= nil, 'loaded')
  T.eq(#cargo.weights, weights, 'no weight while on foot')
  g.walking = false
  c:tick(0.6); c:tick(0.6)
  T.eq(#cargo.weights, weights, 'not the moment you get back in')
  c:tick(0.6); c:tick(0.6); c:tick(0.6)
  T.check(#cargo.weights > weights, 'the weight goes on 2 seconds after getting back in')
  T.eq(cargo.weights[#cargo.weights].kg, c.load.kg, 'all of it')
  -- Delivering is the HUD's Deliver, as before: drive there in the truck.
  local to = places.get(c.load.to)
  F.drive(c, a, to)
  T.check(c:deliver(), 'delivered with Deliver on the HUD, no computer')
  F.drive(c, a, location.destination(F.PENRITH, 90, 10000))
  T.eq(c.depotsBuilt[key], nil, 'driving away takes the depot down')
  -- Back in Penrith the depot comes back at the same spot.
  w.me = { x = 0, y = 0, z = 0 }
  F.drive(c, a, F.PENRITH)
  for _ = 1, 10 do c:tick(0.6) end
  T.check(c.depotsBuilt[key] ~= nil, 'back in Penrith it is put down again')
  T.near(c.depotsBuilt[key].pc.x, pc.x, 0.5, 'at the same spot'); T.near(c.depotsBuilt[key].pc.y, pc.y, 0.5, 'the same spot')
end

-- A house just behind the shed, or right against its side, blocks the spot too.
do
  local w = F.depotWorld()
  local spot = depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 })
  local bx, by = depots.at(spot, -1, depots.SHED_V[#depots.SHED_V] + depots.MARGIN)
  w.boxes = { { bx - 1, by - 0.5, bx + 1, by + 0.5, 6 } }
  T.eq(depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 }), false, 'a house behind the shed blocks it')
  local sx, sy = depots.at(spot, 4, 5.5)
  w.boxes = { { sx - 1.1, sy - 1.1, sx + 1.1, sy + 1.1, 6 } }
  T.eq(depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 }), false, 'a corner only 2 m across is not missed')
end

-- The town's buildings load after its ground: the depot waits for them, and checks its spot twice.
do
  local w = F.depotWorld()
  local c = F.controller({ depotWorld = w })
  for _ = 1, 5 do c:tick(0.6) end
  T.eq(w:count(), 0, 'nothing put down the moment the town is reached')
  for _ = 1, 30 do c:tick(0.6) end
  local built = c.depotsBuilt[next(c.depotsBuilt)]
  T.check(built ~= nil and built.spot ~= nil, 'put down once the town has settled')
  -- A clear spot that a house loads onto before it is taken is passed over.
  local w2 = F.depotWorld()
  local c2 = F.controller({ depotWorld = w2 })
  local first
  for _ = 1, 40 do
    c2:tick(0.6)
    local s = c2.depotSearch and c2.depotSearch[next(c2.depotSearch or {}) or '']
    if s and s.pending and not first then
      first = depots.check(w2, 0, 0, 0, s.pending)
      local hx, hy = depots.at(first, -1, 6.4)
      w2.boxes = { { hx - 3, hy - 3, hx + 3, hy + 3, 7 } }
    end
  end
  local built2 = c2.depotsBuilt[next(c2.depotsBuilt)]
  T.check(first ~= nil and built2 ~= nil, 'still put down')
  T.check(math.abs(built2.spot.x - first.x) + math.abs(built2.spot.y - first.y) > 1, 'somewhere else')
end

-- A house that loads after the depot is down: it moves, but not while the player is at it.
do
  local w = F.depotWorld()
  local c = F.controller({ depotWorld = w })
  for _ = 1, 40 do c:tick(0.6) end
  local key = next(c.depotsBuilt)
  local built = c.depotsBuilt[key]
  local spot = built.spot
  local hx, hy = depots.at(spot, -1, depots.SHED_V[#depots.SHED_V] + depots.MARGIN)
  w.boxes = { { hx - 4, hy - 1, hx + 4, hy + 4, 7 } }
  w.me = { x = built.pc.x + 20, y = built.pc.y, z = 0 }
  for _ = 1, 20 do c:tick(0.6) end
  T.eq(c.depotsBuilt[key], built, 'near it, the depot stays put')
  w.me = { x = built.pc.x + depots.MOVE_METRES + 50, y = built.pc.y, z = 0 }
  for _ = 1, 12 do c:tick(0.6) end
  T.check(c.depotsBuilt[key] ~= built, 'once they walk off, it is taken away')
  for _ = 1, 40 do c:tick(0.6) end
  local moved = c.depotsBuilt[key]
  T.check(moved ~= nil, 'and put down again')
  T.check(math.abs(moved.spot.x - spot.x) + math.abs(moved.spot.y - spot.y) > 1, 'at another spot')
  T.eq(c.depotMoves[key], 1, 'once')
  T.eq(w:count(), 4, 'with nothing left behind')
end

-- The depot's pieces aren't solid, so a late building stands on the ground inside the shed, and the
-- check sees it there too.
do
  local w = F.depotWorld()
  local spot = depots.check(w, 0, 0, 0, { metres = 40, bearing = 0 })
  T.eq(depots.stillClear(w, spot, 0), true, 'clear ground is still clear')
  local x, y = depots.at(spot, -1, 6.4)
  w.boxes = { { x - 2, y - 2, x + 2, y + 2, 8 } }
  T.eq(depots.stillClear(w, spot, 0), false, 'a building inside the shed is found')
  w.unloaded = true
  T.eq(depots.stillClear(w, spot, 0), 'wait', 'unloaded ground: no answer yet')
end

-- No clear ground anywhere: just the desk and computer, at the flattest try.
do
  local w = F.depotWorld()
  w.boxes = { { -1000, -1000, 1000, -0.5, 4 }, { -1000, 9.5, 1000, 1000, 4 } }
  local c = F.controller({ depotWorld = w })
  for _ = 1, 200 do c:tick(0.6) end
  T.eq(w:count(), 3, 'the desk, computer and screen, no shed')
  local built = c.depotsBuilt[next(c.depotsBuilt)]
  T.check(built ~= nil, 'and it is a depot with a computer')
end

-- The game can't put objects down: depots are off and jobs are taken on the HUD, as before.
do
  local w = F.depotWorld()
  w.placeFails = true
  local c = F.controller({ depotWorld = w })
  for _ = 1, 20 do c:tick(0.6) end
  T.check(not c:depotsOn(), 'depots off')
  T.eq(c:view().town.takeProblem, nil, 'no depot message')
  T.eq(c:view().computer, nil, 'no computer')
  local w2 = F.depotWorld()
  function w2:available() return false end
  local c2 = F.controller({ depotWorld = w2 })
  for _ = 1, 5 do c2:tick(0.6) end
  T.check(not c2:depotsOn(), 'nor in a game that cannot make them')
end

-- Fuel runs are loaded at a computer too.
do
  local w = F.depotWorld()
  local c = F.controller({ depotWorld = w })
  for _ = 1, 20 do c:tick(0.6) end
  local hub = places.at(F.PENRITH)
  local problem = c:fuelRunProblem(location.copy(F.PENRITH), hub, nil)
  T.check(problem and problem:find('computer'), 'a fuel run is loaded at the computer: ' .. tostring(problem))
end

-- The game side: pieces are put down not solid, and the shed's tin materials are loaded once first.
do
  local depotWorld = require('earthFreight/depotWorld')
  local fields, loads, objects = {}, 0, {}
  local env = {
    create = function()
      local o = { id = #objects + 1 }
      function o:setField(k, _, v) fields[#objects .. k] = v; self[k] = v end
      function o:setPosition() end
      function o:setPosRot() end
      function o:registerObject() end
      function o:getID() return self.id end
      objects[#objects + 1] = o
      return o
    end,
    point = function(x, y, z) return { x = x, y = y, z = z } end,
    upright = function() return { x = 0, y = 0, z = 0, w = 1 } end,
    group = function() return nil end,
    materials = function() loads = loads + 1 end,
  }
  local w = depotWorld.new(env)
  T.check(w:place('shed', 0, 0, 0, 1, 0) ~= nil, 'the shed is put down')
  T.check(w:place('desk', 0, 0, 0, 1, 0) ~= nil, 'and the desk')
  T.eq(objects[1].collisionType, 'None', 'the shed is not solid')
  T.eq(objects[2].collisionType, 'None', 'nor the desk')
  T.eq(loads, 1, 'the tin materials are loaded once, before the first piece')
end

T.done('depots')
