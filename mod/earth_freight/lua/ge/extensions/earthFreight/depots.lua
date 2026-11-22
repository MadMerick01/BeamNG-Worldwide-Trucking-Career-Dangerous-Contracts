-- Depots: where jobs are taken. Every town has one, a small tin shed with a desk and computer in
-- front of it, set back from a road on clear ground near the middle of town; a fuel depot found in
-- OpenStreetMap gets one too. Town jobs, the off-road drop and fuel runs are only taken at its
-- computer: park the truck within TRUCK_METRES of it, get out, walk up to it and press Use computer.
-- Deliveries are not: they stay a Deliver button on the HUD.
--
-- A depot's spot is worked out the same way every time, from the town, so online every player in a
-- town finds it in the same place without the server. Its objects are made on each player's own
-- game only while they are near it (depotWorld.lua). The search is the pure part below; the game
-- calls are depotWorld's.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local jobs = require('earthFreight/jobs')
local M = {}

-- One-line settings. Tune these after testing in game.
-- The truck must be parked within TRUCK_METRES of the computer to load; the player, on foot, within
-- USE_METRES of it for Use computer to show.
M.TRUCK_METRES, M.USE_METRES = 30, 2.5
-- A depot is looked for and put down once its town's middle (or the fuel depot) is within
-- NEAR_METRES of the player, and taken away past FAR_METRES.
M.NEAR_METRES, M.FAR_METRES = 1500, 2500
-- Where to look: RINGS metres from the town's middle, BEARINGS ways round each ring, starting from a
-- way picked by the town's name, nearest first. Each try is moved onto the nearest road, then set
-- back from it.
M.RINGS = { 40, 90, 150, 220, 300 }
M.BEARINGS = 8
-- The desk's front is SETBACK metres from the road's edge, so the strip in front is room to park.
M.SETBACK = 6
-- The shed, desk and parking strip must be ground that rises at most MAX_RISE metres from its lowest
-- to its highest point, the road beside it included: a building, a wall or a tree there, or a steep
-- slope, makes it rise more. No other road may come within ROAD_CLEAR metres of the shed.
M.MAX_RISE, M.ROAD_CLEAR = 2, 3
-- Every CHECK_SECONDS the depots near the player are looked after; TRIES_PER_CHECK spots are tried
-- each time, so the search never holds up a frame. Ground that Earth has not loaded yet is tried
-- again after WAIT_SECONDS.
M.CHECK_SECONDS, M.TRIES_PER_CHECK, M.WAIT_SECONDS = 0.5, 2, 2

-- Where the pieces go, in metres. u runs along the road, v away from it; the desk's corner is at
-- 0, 0. The desk and computer face the road, so the player stands on the road side of the desk and
-- looks at the shed behind it; the shed runs along the road. PC is the computer itself.
M.PIECES = {
  { shape = 'shed', u = -1, v = 6.4, along = true },
  { shape = 'desk', u = 0, v = 0 },
  { shape = 'computer', u = 0, v = 0 },
  { shape = 'screen', u = 0, v = 0 },
}
M.PC = { u = -1.4, v = 1.4, z = 1 }
-- Where the ground is checked: the shed (about 7 by 20 m), the desk and the strip in front of it.
M.SHED_U, M.SHED_V = { -11, -5.5, 0, 5.5, 9 }, { 2.5, 6.4, 10.5 }
M.FRONT_U, M.FRONT_V = { -11, -5.5, 0, 5.5, 9 }, { -4, -1, 1 }

-- The tries for a depot, nearest first: { metres, bearing } from its middle. The same every time
-- for the same key.
function M.tries(key)
  local start = jobs.hash01(tostring(key)) * 360
  local out = {}
  for _, metres in ipairs(M.RINGS) do
    for i = 0, M.BEARINGS - 1 do
      out[#out + 1] = { metres = metres, bearing = (start + i * 360 / M.BEARINGS) % 360 }
    end
  end
  return out
end

-- A spot in the world frame: origin x, y, and n, the way away from the road. Returns the world
-- x, y of a point u, v from it.
function M.at(spot, u, v)
  local dx, dy = spot.ny, -spot.nx
  return spot.x + u * dx + v * spot.nx, spot.y + u * dy + v * spot.ny
end

-- How far the ground rises over a list of heights; nil when any is unknown.
function M.rise(heights)
  local low, high
  for i = 1, #heights do
    local h = heights[i]
    if type(h) ~= 'number' then return nil end
    low, high = math.min(low or h, h), math.max(high or h, h)
  end
  return low and (high - low) or nil, low
end

-- Tries one spot near a depot's middle (cx, cy in the world). Returns the spot when it is clear,
-- false when it is not, or 'wait' when Earth has not loaded the ground there yet.
function M.check(world, cx, cy, cz, try)
  local b = math.rad(try.bearing)
  local px, py = cx + math.sin(b) * try.metres, cy + math.cos(b) * try.metres
  local road = world:road(px, py, cz)
  local spot
  if road then
    local nx, ny = px - road.x, py - road.y
    local len = math.sqrt(nx * nx + ny * ny)
    if len < 0.5 then nx, ny, len = -road.dy, road.dx, 1 end
    nx, ny = nx / len, ny / len
    local back = road.radius + M.SETBACK
    spot = { x = road.x + nx * back, y = road.y + ny * back, nx = nx, ny = ny }
  else
    spot = { x = px, y = py, nx = math.sin(b), ny = math.cos(b) }
  end
  local front, shed, missing = {}, {}, false
  local function measure(list, us, vs)
    for _, u in ipairs(us) do
      for _, v in ipairs(vs) do
        local x, y = M.at(spot, u, v)
        local h = world:ground(x, y, cz)
        if h == nil then missing = true else list[#list + 1] = h end
      end
    end
  end
  measure(front, M.FRONT_U, M.FRONT_V)
  measure(shed, M.SHED_U, M.SHED_V)
  if missing then return 'wait' end
  -- The road itself counts too, so a big flat roof beside it is not taken for flat ground.
  local all = {}
  if road and type(road.z) == 'number' then all[1] = road.z end
  for _, h in ipairs(front) do all[#all + 1] = h end
  for _, h in ipairs(shed) do all[#all + 1] = h end
  local rise = M.rise(all)
  local _, shedLow = M.rise(shed)
  spot.rise, spot.frontRise, spot.shedZ = rise, M.rise(front), shedLow
  if rise > M.MAX_RISE then return false, spot end
  -- No other road through the shed.
  if road then
    for _, u in ipairs({ -11, 9 }) do
      for _, v in ipairs({ 2.5, 10.5 }) do
        local x, y = M.at(spot, u, v)
        local other = world:road(x, y, cz)
        if other and other.metres < other.radius + M.ROAD_CLEAR then return false, spot end
      end
    end
  end
  return spot
end

-- The lowest ground under a spot's shed, where it is put down (its concrete base reaches 1 m down).
function M.shedLow(world, spot, cz)
  local shed = {}
  for _, u in ipairs(M.SHED_U) do
    for _, v in ipairs(M.SHED_V) do
      local x, y = M.at(spot, u, v)
      shed[#shed + 1] = world:ground(x, y, cz)
    end
  end
  local _, low = M.rise(shed)
  return low
end

-- The controller's side: which depots are near, finding their spots, putting them down and taking
-- them away, and whether the player is at a computer with their truck close enough.
function M.attach(c)
  -- Whether depots are in use: only with the game side, and until it fails to put one down.
  function c:depotsOn()
    if self.depotWorld == nil or self.depotsBroken then return false end
    if self.depotsAvailable == nil then
      self.depotsAvailable = self.depotWorld.available == nil or self.depotWorld:available() == true
    end
    return self.depotsAvailable
  end

  -- The player's position in the world and on Earth, to turn one into the other near them.
  local function frame(self)
    local sample = self.lastSample
    if not sample or not sample.valid then return nil end
    local at = self.depotWorld:where(nil)
    if not at then return nil end
    return { x = at.x, y = at.y, z = at.z, geo = sample }
  end

  -- A point on Earth in the world frame near the player (Earth's world is east-north-up).
  local function toWorld(f, geo)
    local d = location.distance(f.geo, geo)
    local b = location.bearing(f.geo, geo)
    if not d or not b then return nil end
    return f.x + math.sin(math.rad(b)) * d, f.y + math.cos(math.rad(b)) * d
  end

  -- The depots wanted now: the town the player is in, and the fuel depot on the Fuel runs card.
  -- Each { key, name, latitude, longitude, town = place id, fuel = hub id }.
  function c:depotsWanted()
    local out, byKey = {}, {}
    local function add(key, name, anchor, town, fuel)
      local d = byKey[key]
      if not d then
        d = { key = key, name = name, latitude = anchor.latitude, longitude = anchor.longitude }
        byKey[key] = d
        out[#out + 1] = d
      end
      d.town = d.town or town
      d.fuel = d.fuel or fuel
    end
    local here = self:here()
    if here then add('town:' .. here.id, here.name, here, here.id, nil) end
    local hub = self.fuelHubId and places.get(self.fuelHubId)
    if hub and self.fuelDepot then
      local depot = self:fuelDepot(hub)
      if depot then add('fuel:' .. hub.id, depot.name, depot, nil, hub.id)
      else add('town:' .. hub.id, hub.name, hub, hub.id, hub.id) end
    end
    return out
  end

  -- Puts a depot down at its spot: each piece on the ground under it. The first one tells whether
  -- the game turns pieces the way asked; if not, the rest are turned round to match.
  local function build(self, f, d, spot)
    local ids = {}
    local pieces = spot.small and { M.PIECES[2], M.PIECES[3], M.PIECES[4] } or M.PIECES
    local dx, dy = M.at(spot, -1, 0.85)
    local deskZ = self.depotWorld:ground(dx, dy, f.z)
    for _, p in ipairs(pieces) do
      local x, y = M.at(spot, p.u, p.v)
      -- Forward: the desk faces the road, the shed runs along it.
      local fx, fy = -spot.nx, -spot.ny
      if p.along then fx, fy = spot.ny, -spot.nx end
      if self.depotFlip then fx, fy = -fx, -fy end
      local z = (p.shape == 'shed' and spot.shedZ) or deskZ or f.z
      local id = self.depotWorld:place(p.shape, x, y, z, fx, fy)
      if not id then
        for _, made in ipairs(ids) do self.depotWorld:remove(made) end
        return nil
      end
      ids[#ids + 1] = id
      if self.depotFlip == nil then
        local got = self.depotWorld:forward(id)
        if got then
          self.depotFlip = (got.x * fx + got.y * fy) < 0
          if self.depotFlip then
            self.depotWorld:remove(id)
            ids[#ids] = nil
            return build(self, f, d, spot)
          end
        end
      end
    end
    local px, py = M.at(spot, M.PC.u, M.PC.v)
    return { ids = ids, pc = { x = px, y = py, z = (deskZ or f.z) + M.PC.z } }
  end

  -- Looks for a depot's spot a few tries at a time. A depot with no clear spot anywhere gets just
  -- its desk and computer, at the try with the flattest ground in front.
  local function search(self, f, d, cx, cy)
    local s = self.depotSearch[d.key]
    if not s then
      s = { next = 1, tries = M.tries(d.key) }
      self.depotSearch[d.key] = s
    end
    if s.waitUntil and self.clock < s.waitUntil then return nil end
    for _ = 1, M.TRIES_PER_CHECK do
      local try = s.tries[s.next]
      if not try then
        if s.best then
          s.best.small = true
          return s.best
        end
        -- Nothing loaded anywhere yet: start again.
        s.next = 1
        s.waitUntil = self.clock + M.WAIT_SECONDS
        return nil
      end
      local spot, near = M.check(self.depotWorld, cx, cy, f.z, try)
      if spot == 'wait' then
        s.waitUntil = self.clock + M.WAIT_SECONDS
        return nil
      end
      s.next = s.next + 1
      if spot then return spot end
      if near and near.frontRise and (not s.best or near.frontRise < s.best.frontRise) then s.best = near end
    end
    return nil
  end

  -- Looks after the depots near the player: finds and puts down the ones wanted, and takes away
  -- the ones left behind. Called every frame; does its work every CHECK_SECONDS.
  function c:watchDepots()
    if not self:depotsOn() then return end
    self.depotSearch = self.depotSearch or {}
    self.depotSpots = self.depotSpots or {}
    self.depotsBuilt = self.depotsBuilt or {}
    if self.depotCheckAt and self.clock - self.depotCheckAt < M.CHECK_SECONDS then return end
    self.depotCheckAt = self.clock
    local ready = self.profile and not self.error and self.state == 'READY' and self.arrived and not self.hire
    local f = ready and frame(self) or nil
    local wanted = {}
    if f then
      for _, d in ipairs(self:depotsWanted()) do
        local metres = location.distance(f.geo, d)
        if metres and metres <= M.NEAR_METRES then wanted[d.key] = d end
      end
    end
    -- Away: taken down once far, or when the player is no longer anywhere (a teleport, the heli).
    for key, built in pairs(self.depotsBuilt) do
      local d = wanted[key]
      local far = not f or not built.geo or (location.distance(f.geo, built.geo) or math.huge) > M.FAR_METRES
      if not d and far then
        for _, id in ipairs(built.ids) do self.depotWorld:remove(id) end
        self.depotsBuilt[key] = nil
      elseif d then
        built.name, built.town, built.fuel = d.name, d.town, d.fuel
      end
    end
    if not f then return end
    for key, d in pairs(wanted) do
      if not self.depotsBuilt[key] then
        local cx, cy = toWorld(f, d)
        if cx then
          local spot = self.depotSpots[key]
          if spot then
            -- Found before, kept by where it is on Earth: back into today's world frame.
            local x, y = toWorld(f, spot.geo)
            spot = { x = x, y = y, nx = spot.nx, ny = spot.ny, small = spot.small, geo = spot.geo }
            spot.shedZ = not spot.small and M.shedLow(self.depotWorld, spot, f.z) or nil
          else
            spot = search(self, f, d, cx, cy)
            if spot then
              local dx, dy = spot.x - f.x, spot.y - f.y
              local geo = location.destination(f.geo, (math.deg(math.atan2(dx, dy)) + 360) % 360, math.sqrt(dx * dx + dy * dy))
              spot.geo = geo
              self.depotSpots[key] = { geo = geo, nx = spot.nx, ny = spot.ny, small = spot.small }
              self.depotSearch[key] = nil
              self.diag:event('depot', string.format('%s %s rise %.1f', key, spot.small and 'desk only' or 'shed',
                spot.small and (spot.frontRise or 0) or (spot.rise or 0)))
            end
          end
          if spot then
            local built = build(self, f, d, spot)
            if built then
              built.key, built.name, built.town, built.fuel, built.geo = key, d.name, d.town, d.fuel, spot.geo
              -- Where its computer is on Earth, for the GPS.
              local px, py = built.pc.x - f.x, built.pc.y - f.y
              built.pcGeo = location.destination(f.geo, (math.deg(math.atan2(px, py)) + 360) % 360, math.sqrt(px * px + py * py))
              self.depotsBuilt[key] = built
            else
              -- The game would not put it down: depots are off for this game, and jobs are taken on the HUD.
              self.depotsBroken = true
              self.diag:event('depot', 'place_failed:' .. key, 'W')
              return
            end
          end
        end
      end
    end
  end

  -- The depot the player is at: on foot within USE_METRES of its computer. With how far their truck
  -- is from the computer (nil when it can't be found). Nil when at none.
  function c:computerHere()
    if not self:depotsOn() or not self.onFoot or not self.depotsBuilt then return nil end
    local me = self.depotWorld:where(nil)
    if not me then return nil end
    for _, built in pairs(self.depotsBuilt) do
      local pc = built.pc
      local d = math.sqrt((me.x - pc.x) ^ 2 + (me.y - pc.y) ^ 2)
      if d <= M.USE_METRES then
        local truck = self.ownedParts and self.depotWorld:where(self.ownedParts.id)
        local away = truck and math.sqrt((truck.x - pc.x) ^ 2 + (truck.y - pc.y) ^ 2) or nil
        return built, away
      end
    end
    return nil
  end

  -- The nearest depot built for a town (or fuel hub), and how far and which way its computer is
  -- from the player.
  function c:depotFor(townId, hubId)
    if not self:depotsOn() or not self.depotsBuilt then return nil end
    local me = self.depotWorld:where(nil)
    for _, built in pairs(self.depotsBuilt) do
      if (townId and built.town == townId) or (hubId and built.fuel == hubId) then
        if not me then return built end
        local dx, dy = built.pc.x - me.x, built.pc.y - me.y
        local metres = math.sqrt(dx * dx + dy * dy)
        local bearing = (math.deg(math.atan2(dx, dy)) + 360) % 360
        return built, metres, metres > 1 and location.compassPoint(bearing) or nil, metres > 1 and bearing or nil
      end
    end
    return nil
  end

  -- Why a job can't be taken from here now, for a town's board (townId) or a fuel depot (hubId);
  -- nil when it can. Only while depots are on.
  function c:computerProblem(townId, hubId)
    local built, truck = self:computerHere()
    if not built or not ((townId and built.town == townId) or (hubId and built.fuel == hubId)) then
      local depot, metres = self:depotFor(townId, hubId)
      if not depot then return 'Finding a spot for the depot. Its shed and computer appear near the middle of town.' end
      return 'Take jobs at the depot computer, ' .. (metres and (math.floor(metres + 0.5) .. ' m away') or 'nearby')
        .. ': park within ' .. M.TRUCK_METRES .. ' m of it, get out and walk up to it.'
    end
    if not truck then return 'Your truck could not be found. Get back in it and park within ' .. M.TRUCK_METRES .. ' m of the computer.' end
    if truck > M.TRUCK_METRES then
      return 'Your truck is ' .. math.floor(truck + 0.5) .. ' m from the computer. Park it within ' .. M.TRUCK_METRES .. ' m to load.'
    end
    return nil
  end

  -- What the HUD shows about the computer: the Use computer button, and the window's header.
  function c:computerView()
    if not self:depotsOn() then return nil end
    local built, truck = self:computerHere()
    local out = { truckMetres = M.TRUCK_METRES, useMetres = M.USE_METRES }
    if built then
      out.near = true
      out.name, out.town, out.fuel = built.name, built.town, built.fuel
      out.truckAway = truck and math.floor(truck + 0.5) or nil
      out.truckOk = truck ~= nil and truck <= M.TRUCK_METRES
    end
    local here = self:here()
    local depot, metres, direction, bearing = self:depotFor(here and here.id, nil)
    if depot and not built then
      -- The arrow: which way to turn, the depot's bearing from the way the player faces, 0 straight ahead.
      local sample = self.lastSample
      local heading = sample and location.finite(sample.heading) and sample.heading or self.heading
      out.depot = { name = depot.name, distanceMetres = metres and math.floor(metres + 0.5) or nil, direction = direction,
        letters = bearing and location.compassLetters(bearing) or nil,
        arrow = bearing and heading and (bearing - heading) % 360 or nil,
        gps = self.gpsTownDepot ~= nil and self.gpsTownDepot == depot.key or nil,
        gpsAllowed = depot.pcGeo ~= nil and self.adapter.setDestination ~= nil and not self.hire }
    end
    return out
  end

  -- Sets the GPS to the computer of the depot in the town the player is in.
  function c:gpsToTownDepot()
    local here = self:here()
    local depot = self:depotFor(here and here.id, nil)
    if not depot or not depot.pcGeo or not self.adapter.setDestination or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local name = depot.name .. ' depot'
    local ok, why = self.adapter:setDestination(depot.pcGeo, name)
    self.diag:event('gps', ok and ('depot:' .. depot.key) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract, self.gpsDepot, self.gpsRun = nil, nil, nil, nil
    self.gpsTownDepot = ok and depot.key or nil
    self.gpsFeedback = ok and ('The GPS is set to the ' .. name .. '.') or 'Could not set the GPS.'
    return ok == true
  end

  -- Takes every depot away, as when the level unloads.
  function c:removeDepots()
    if not self.depotWorld or not self.depotsBuilt then return end
    for key, built in pairs(self.depotsBuilt) do
      for _, id in ipairs(built.ids) do self.depotWorld:remove(id) end
      self.depotsBuilt[key] = nil
    end
  end
end

return M
