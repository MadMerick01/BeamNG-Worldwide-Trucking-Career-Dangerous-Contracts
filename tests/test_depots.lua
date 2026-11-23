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

-- Car parks from OpenStreetMap are tried first; the HUD is asked once per town.
do
  local w = F.depotWorld()
  local c = F.controller({ depotWorld = w })
  c:tick(0.6); c:tick(0.6)
  local want = c:view().computer.lots
  T.check(want and want.key and want.latitude and want.metres == depots.LOT_METRES, 'the HUD is asked for car parks round the town')
  for _ = 1, 10 do c:tick(0.6) end
  T.eq(w:count(), 0, 'the depot waits for the answer')
  T.check(not c:setDepotLots('town:nowhere', {}), 'an answer for a town not wanted is refused')
  local d = c:depotsWanted()[1]
  local lot = location.destination(d, 90, 250)
  local far = location.destination(d, 0, 5000)
  T.check(c:setDepotLots(want.key, { lot, far }), 'the answer is taken')
  T.eq(#c.depotLots[want.key], 1, 'a car park far from town is left out')
  local again = c:view().computer.lots
  T.check(not again or again.key ~= want.key, 'and not asked again')
  for _ = 1, 20 do c:tick(0.6) end
  local built = c.depotsBuilt[want.key]
  T.check(built and built.spot.lot, 'the depot is in the car park')
  T.check(location.distance(lot, built.pcGeo) < 30, 'next to it')
  -- No answer from the HUD: after a while the roads are searched as before.
  local w2 = F.depotWorld()
  local c2 = F.controller({ depotWorld = w2 })
  for _ = 1, 40 do c2:tick(0.6) end
  local built2 = c2.depotsBuilt[next(c2.depotsBuilt)]
  T.check(built2 and not built2.spot.lot, 'without car parks the depot still goes down')
end

-- With BeamNG.Earth's own map data, the game asks Earth for the car parks itself (the HUD's web
-- lookup can be blocked by the game), and the HUD is not asked.
do
  local w = F.depotWorld()
  local c, _, a = F.controller({ depotWorld = w })
  a.asks = {}
  function a:canFindStations() return true end
  function a:findParking(point, metres, done) self.asks[#self.asks + 1] = { point = point, metres = metres, done = done }; return true end
  c:tick(0.6); c:tick(0.6)
  T.eq(#a.asks, 1, 'Earth is asked once for the car parks round the town')
  T.eq(a.asks[1].metres, depots.LOT_METRES, 'as far out as the HUD would look')
  T.eq(c:view().computer.lots, nil, 'and the HUD is not asked')
  c:tick(0.6)
  T.eq(#a.asks, 1, 'not again')
  local d = c:depotsWanted()[1]
  local lot = location.destination(d, 90, 250)
  a.asks[1].done({}, false, nil)
  T.eq(c.depotLots[d.key], nil, 'an empty first answer while Earth is still looking is not the end')
  a.asks[1].done({ { name = 'Car park', category = 'parking', lat = lot.latitude, lon = lot.longitude } }, true, nil)
  for _ = 1, 30 do c:tick(0.6) end
  local built = c.depotsBuilt[d.key]
  T.check(built and built.spot.lot, 'the depot is in the car park Earth knows')
  T.check(location.distance(lot, built.pcGeo) < 30, 'next to it')
end

-- Earth leaves out multi-storey and underground car parks.
do
  local earthAdapter = require('earthFreight/earthAdapter')
  local asked
  local api = {
    has = function(name) return name == 'places' end,
    places = function(lat, lon, opts, cb) asked = opts; cb({ places = {
      { name = 'Town Square', category = 'parking', lat = 1, lon = 2 },
      { name = 'Mall', category = 'parking_garage', lat = 1, lon = 2 },
      { name = 'Underground Car Park', category = 'parking', lat = 1, lon = 2 },
    } }); return 1 end,
  }
  local g = earthAdapter.new({ core = function() return nil end, api = function() return api end, module = function() end })
  local got
  T.check(g:findParking({ latitude = 1, longitude = 2 }, 400, function(list, done) got = { list = list, done = done } end), 'asked')
  T.eq(asked.categories[1], 'parking*', 'for car parks')
  T.eq(#got.list, 1, 'only the open one'); T.eq(got.list[1].name, 'Town Square', 'the town square')
  T.check(got.done, 'and that is all')
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

-- A packed town: flat roofs right up to the road. The desk goes at the road's edge, at road height,
-- never on a roof.
do
  local w = F.depotWorld()
  w.boxes = { { -1000, -1000, 1000, -3.5, 8 }, { -1000, 3.5, 1000, 1000, 8 } }
  local c = F.controller({ depotWorld = w })
  for _ = 1, 200 do c:tick(0.6) end
  T.eq(w:count(), 3, 'just the desk, computer and screen')
  for _, o in pairs(w.objects) do
    T.eq(o.z, 0, o.shape .. ' at the height of the road, not the roofs')
    T.check(math.abs(o.y) <= 3 + depots.EDGE_METRES + 0.01, o.shape .. ' at the edge of the road')
  end
end

-- Ground that never loads (water, a gap in Earth's tiles) where the first spots are: they are passed
-- over and the depot still goes down, well before the search gives up.
do
  local w = F.depotWorld()
  w.hole = function(_, y) return y > 0 end
  local c = F.controller({ depotWorld = w })
  for _ = 1, math.ceil(depots.GIVE_UP_SECONDS / 0.6) - 2 do c:tick(0.6) end
  local built = c.depotsBuilt[next(c.depotsBuilt)]
  T.check(built ~= nil, 'put down on the side of the road that loaded')
  T.eq(w:count(), 4, 'with its shed')
  T.check(built.spot.y < 0, 'on the loaded side')
end

-- Nothing ever loads: the search gives up and puts the desk and computer at the road nearest the
-- middle of town, so the town's jobs are never locked.
do
  local w = F.depotWorld()
  w.unloaded = true
  local c = F.controller({ depotWorld = w })
  for _ = 1, math.ceil(depots.GIVE_UP_SECONDS / 0.6) - 5 do c:tick(0.6) end
  T.eq(w:count(), 0, 'still looking before it gives up')
  T.check(c:view().town.takeProblem:find('Finding a spot'), 'and the board says so')
  for _ = 1, 12 do c:tick(0.6) end
  T.eq(w:count(), 3, 'then the desk, computer and screen go down')
  for _, o in pairs(w.objects) do
    T.check(math.abs(o.y) <= w.roadRadius + depots.EDGE_METRES + 2, o.shape .. ' beside the road')
  end
  T.check(not c:view().town.takeProblem:find('Finding a spot'), 'and jobs point to the computer')
end

-- No shed fits, but there is flat ground set back from the road (it could be a creek or the trees,
-- which the checks can't see): the desk still goes right beside the road.
do
  local w = F.depotWorld()
  w.boxes = { { -1000, -1000, 1000, -0.5, 4 }, { -1000, 9.5, 1000, 1000, 4 } }
  local c = F.controller({ depotWorld = w })
  for _ = 1, 200 do c:tick(0.6) end
  for _, o in pairs(w.objects) do
    T.check(math.abs(o.y) <= w.roadRadius + depots.EDGE_METRES + 2, o.shape .. ' beside the road, not set back')
    T.eq(o.z, 0, o.shape .. ' at the height of the road')
  end
end

-- The game can't put objects down: depots are off and jobs are taken on the HUD, as before.
do
  local w = F.depotWorld()
  w.placeFails = true
  local c = F.controller({ depotWorld = w })
  for _ = 1, 40 do c:tick(0.6) end
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

-- Pieces left behind by an earlier load of the mod (a reload, or an older version) are taken away
-- when the mod starts and every little while after, and the depots built now are kept.
do
  local w = F.depotWorld()
  local old = { w:leftover('shed'), w:leftover('desk') }
  local c, _, a = F.controller({ depotWorld = w })
  w.follow, w.origin = a, F.copy(F.PENRITH)
  c.now = function() return 50000 end
  w.cars[1] = { x = 0, y = 0, z = 0 }
  c:tick(0.6)
  T.eq(w.objects[old[1]], nil, 'a shed left behind is taken away at the start')
  T.eq(w.objects[old[2]], nil, 'and its desk')
  for _ = 1, 40 do c:tick(0.6) end
  T.eq(w:count(), 4, 'the depot of this town is put down')
  local another = w:leftover('shed')
  for _ = 1, math.ceil(depots.SWEEP_SECONDS / 0.6) + 1 do c:tick(0.6) end
  T.eq(w.objects[another], nil, 'one that turns up later goes too')
  T.eq(w:count(), 4, 'and the depot built now stays')
  c:removeDepots()
  T.eq(w:count(), 0, 'a reload of the mod takes its depots away')
end

-- The game side finds the pieces by name, put down by this load or any earlier one.
do
  local depotWorld = require('earthFreight/depotWorld')
  local objects, names = {}, {}
  local env = {
    create = function()
      local o = { id = #objects + 1 }
      function o:setField() end
      function o:setPosition() end
      function o:setPosRot() end
      function o:registerObject(name) names[self.id] = name end
      function o:getID() return self.id end
      function o:delete() objects[self.id] = nil end
      objects[#objects + 1] = o
      return o
    end,
    objectById = function(id) return objects[id] end,
    point = function(x, y, z) return { x = x, y = y, z = z } end,
    upright = function() return { x = 0, y = 0, z = 0, w = 1 } end,
    group = function() return nil end,
    named = function(prefix)
      local ids = {}
      for id, name in pairs(names) do
        if objects[id] and name:sub(1, #prefix) == prefix then ids[#ids + 1] = id end
      end
      table.sort(ids)
      return ids
    end,
  }
  local w = depotWorld.new(env)
  local kept = w:place('shed', 0, 0, 0, 1, 0)
  local lost = w:place('desk', 0, 0, 0, 1, 0)
  T.check(names[kept]:sub(1, #depotWorld.PREFIX) == depotWorld.PREFIX, 'named so it can be found again')
  T.check(names[kept] ~= names[lost], 'every piece has its own name')
  T.eq(w:sweep({ [kept] = true }), 1, 'one piece not kept is taken away')
  T.check(objects[kept] ~= nil and objects[lost] == nil, 'the kept one stays')
  T.eq(depotWorld.new({ named = function() error('no scenetree') end }):sweep({}), 0, 'a game without the call takes nothing')
end

-- The game's lookup by id only knows vehicles: a piece put down can still be taken away, so a
-- depot that moves never leaves its old shed and desk behind.
do
  local depotWorld = require('earthFreight/depotWorld')
  local objects = {}
  local env = {
    create = function()
      local o = { id = #objects + 1 }
      function o:setField() end
      function o:setPosition() end
      function o:setPosRot() end
      function o:registerObject() end
      function o:getID() return self.id end
      function o:delete() objects[self.id] = nil end
      objects[#objects + 1] = o
      return o
    end,
    objectById = function() return nil end,
    point = function(x, y, z) return { x = x, y = y, z = z } end,
    upright = function() return { x = 0, y = 0, z = 0, w = 1 } end,
    group = function() return nil end,
  }
  local w = depotWorld.new(env)
  local id = w:place('shed', 0, 0, 0, 1, 0)
  T.check(w:remove(id), 'taken away')
  T.eq(objects[id], nil, 'and gone from the world')
  T.check(not w:remove(id), 'not twice')
end

T.done('depots')
