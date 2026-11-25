local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local pickups = require('earthFreight/pickups')
local places = require('earthFreight/places')
local location = require('earthFreight/location')

local function placeNamed(name)
  for _, p in ipairs(places.list) do if p.name == name then return p end end
end
places.ensure(F.PENRITH)
local penrith, stClair = placeNamed('Penrith'), placeNamed('St Clair')

-- Stand-in for the game side (pickupWorld.lua): the player in the world as the adapter moves on
-- Earth (east-north-up from origin), and one straight road running east-west, roadNorth metres
-- north of origin.
local function world(a, origin, roadNorth)
  local w = { roadNorth = roadNorth or 0, asked = 0 }
  function w:where()
    local d = location.distance(origin, a.pose) or 0
    local b = math.rad(location.bearing(origin, a.pose) or 0)
    return { x = math.sin(b) * d, y = math.cos(b) * d, z = 0 }
  end
  function w:road(x, y)
    self.asked = self.asked + 1
    if self.noRoads then return nil end
    return { x = x, y = self.roadNorth, z = 0, radius = 3, metres = math.abs(y - self.roadNorth) }
  end
  return w
end

-- The pure snap: the town's point moved straight onto the road, or false when the road is too far.
do
  local a = { pose = F.copy(F.PENRITH) }
  local town = location.destination(F.PENRITH, 0, 500)
  local w = world(a, F.PENRITH, 620)
  local spot = pickups.snap(w, w:where(), a.pose, town)
  T.near(location.distance(town, spot), 120, 0.5, 'moved 120 m onto the road')
  T.near(location.bearing(town, spot), 0, 0.5, 'straight north')
  w.roadNorth = 500 + pickups.MAX_SNAP_METRES + 50
  T.eq(pickups.snap(w, w:where(), a.pose, town), false, 'a road too far away is not used')
  w.noRoads = true
  T.eq(pickups.snap(w, w:where(), a.pose, town), nil, 'no road map: nothing yet')
end

-- Taking a job: stopped within 50 m of the town's pickup point, never just anywhere in town.
do
  local c, _, a, g = F.controller()
  g.fitted.box = 'pickup_cargo_load_box_m'
  a.pose = F.copy(penrith)
  F.advance(c, 3)
  local v = c:view()
  T.eq(v.here.name, 'Penrith', 'in Penrith')
  T.eq(v.town.takeProblem, nil, 'at the pickup point jobs can be taken')
  T.check(v.town.pickup.inZone, 'the HUD says you are there')
  T.eq(v.town.pickup.radiusMetres, pickups.RADIUS, 'and how close to stop')
  -- 150 m east: still in Penrith, but not at its pickup point.
  a.pose = location.destination(penrith, 90, 150)
  F.advance(c, 3)
  v = c:view()
  T.eq(v.here.name, 'Penrith', 'still in Penrith')
  T.check(v.town.takeProblem and v.town.takeProblem:find('pickup point in Penrith', 1, true), 'told to drive to the pickup point')
  T.check(v.town.takeProblem:find('150 m away', 1, true), 'and how far it is')
  T.check(not v.town.pickup.inZone, 'not there')
  T.eq(v.town.pickup.distanceMetres, 150, 'how far'); T.eq(v.town.pickup.letters, 'W', 'which way')
  T.eq(v.town.pickup.arrow, nil, 'no needle before the game says which way the player faces')
  for _, j in ipairs(v.town.jobs) do T.check(not j.allowed, j.id .. ' cannot be taken here') end
  T.check(not c:takeJob(v.town.jobs[1].id), 'nor taken')
  c.heading = 0
  T.near(c:view().town.pickup.arrow, 270, 1, 'the needle points left when facing north')
  c.heading = 180
  T.near(c:view().town.pickup.arrow, 90, 1, 'and right when facing south')
  T.check(v.town.pickup.gpsAllowed, 'a GPS button')
  T.check(c:gpsToPickup(), 'the GPS is set to the pickup point')
  T.eq(a.gps[#a.gps].name, 'Penrith pickup point', 'by name')
  T.near(location.distance(a.gps[#a.gps], penrith), 0, 1e-6, 'at the town\'s point')
  T.check(c:view().town.pickup.gps, 'the GPS button lights')
  -- Back at the point: the job is taken.
  a.pose = location.destination(penrith, 0, pickups.RADIUS - 5)
  F.advance(c, 3)
  local id = F.offer(c, stClair, 'food')
  T.eq(c:view().town.takeProblem, nil, 'within 50 m it can be taken')
  T.check(c:takeJob(id), 'job taken')
  T.eq(c:view().town.pickup, nil, 'no pickup card while on a job')
  T.near(location.distance(a.gps[#a.gps], stClair), 0, 1e-6, 'the GPS goes to St Clair\'s drop-off point')
  -- Delivering with no business: at the drop-off point, St Clair's pickup point.
  F.drive(c, a, location.destination(stClair, 180, 200))
  v = c:view()
  T.eq(v.here.name, 'St Clair', 'in St Clair')
  T.check(not v.town.delivery.allowed, 'not at the drop-off point')
  T.check(v.town.delivery.problem:find('drop-off point in St Clair', 1, true), 'told where to go')
  T.check(v.load.point.near and not v.load.point.inZone, 'the job card counts down to it')
  T.eq(v.load.point.distanceMetres, 200, 'exactly')
  T.check(not c:deliver(), 'not delivered 200 m away')
  F.drive(c, a, location.destination(stClair, 180, 20))
  v = c:view()
  T.check(v.load.point.inZone, 'at the drop-off point')
  T.check(v.town.delivery.allowed, 'delivery allowed')
  T.check(c:deliver(), 'delivered')
end

-- The pickup point moves onto the nearest road once the player is close, the same for every
-- player; the GPS follows it.
do
  local c, _, a = F.controller({ pickupWorld = {} })
  local w = world(a, penrith, 60)
  c.pickupWorld = w
  c:tick(0.6); c:tick(0.6)
  T.check(c.arrived, 'arrived'); T.eq(c.state, 'READY', 'ready')
  c.pickupWorld = nil
  F.drive(c, a, location.destination(penrith, 180, 1200))
  c.pickupWorld = w
  T.check(c:gpsToTown(penrith.id), 'GPS to Penrith from outside it')
  T.near(location.distance(a.gps[#a.gps], penrith), 0, 1e-6, 'its point, until the road is known')
  F.advance(c, pickups.SETTLE_SECONDS + 2)
  local spot = c:pickupSpot(penrith)
  T.near(location.distance(spot, penrith), 60, 0.5, 'moved 60 m onto the road')
  T.near(location.bearing(penrith, spot), 0, 0.5, 'north, where the road is')
  T.near(location.distance(a.gps[#a.gps], spot), 0, 1e-6, 'the GPS follows it')
  local asked = w.asked
  F.advance(c, 5)
  T.eq(w.asked, asked, 'settled: the roads are not asked again')
  -- No road near the point: it stays at the town's own point once the player is close.
  local c2, _, a2 = F.controller()
  local w2 = world(a2, penrith, 900)
  c2.pickupWorld = w2
  c2.pickupWorld = nil
  c2:tick(0.6); c2:tick(0.6)
  F.drive(c2, a2, location.destination(penrith, 180, 1200))
  c2.pickupWorld = w2
  F.advance(c2, pickups.SETTLE_SECONDS + 2)
  T.eq(c2.pickupSpots and c2.pickupSpots[penrith.id], nil, 'far off: tried again later')
  F.drive(c2, a2, location.destination(penrith, 180, 100))
  F.advance(c2, 2)
  T.near(location.distance(c2:pickupSpot(penrith), penrith), 0, 1e-6, 'close by with no road near: the town\'s own point')
end

T.done('pickup points')
