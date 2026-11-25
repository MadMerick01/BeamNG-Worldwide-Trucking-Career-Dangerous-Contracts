-- Pickup points: where a town's jobs are taken, and where a job that has no real business to go to
-- is delivered. Every town has one: the town's own point in the place list, moved onto the nearest
-- road once the player is close enough for the game to have that road. Stop within RADIUS metres
-- of it. Nothing is put into the world. The place list is the same for every player, and so are
-- Earth's roads, so online everyone has the same pickup point in a town.
-- The pure part is first; the controller's side below. The game calls are pickupWorld's.
local location = require('earthFreight/location')
local places = require('earthFreight/places')
local M = {}

-- One-line settings. Tune these after testing in game.
-- Take a job, or deliver one, stopped within this many metres of the pickup point.
M.RADIUS = 50
-- The roads round a town's point are looked at once the player is within SNAP_NEAR_METRES of it,
-- SETTLE_SECONDS after they first came that close (Earth brings the roads in as the player nears),
-- and then every CHECK_SECONDS until the point is settled.
M.SNAP_NEAR_METRES, M.SETTLE_SECONDS, M.CHECK_SECONDS = 1500, 4, 1
-- The point moves onto a road at most MAX_SNAP_METRES from it, so it stays well inside its town
-- (a village's circle is 300 m). With no road that close once the player is within LOCK_METRES of
-- the point, it stays where it is.
M.MAX_SNAP_METRES, M.LOCK_METRES = 200, 400
-- On a job, the HUD counts down the metres and shows the needle once the drop-off point is this close.
M.COUNTDOWN_METRES = 500

-- The point on the road for a town, from the player's place in the world (x, y on Earth's east-north
-- frame, and their position on Earth) and the game side's nearest road. Returns the point, or false
-- when there is no road close enough, or nil when the roads can't be read.
function M.snap(world, me, geo, town)
  local d, b = location.distance(geo, town), location.bearing(geo, town)
  if not d or not b then return nil end
  local x, y = me.x + math.sin(math.rad(b)) * d, me.y + math.cos(math.rad(b)) * d
  local road = world:road(x, y, me.z)
  if not road or not location.finite(road.metres) then return nil end
  if road.metres > M.MAX_SNAP_METRES then return false end
  local dx, dy = road.x - me.x, road.y - me.y
  local spot = location.destination(geo, (math.deg(math.atan2(dx, dy)) + 360) % 360, math.sqrt(dx * dx + dy * dy))
  return spot and location.valid(spot) and spot or nil
end

function M.attach(c)
  -- A town's pickup point: on the road once settled, else the town's own point.
  function c:pickupSpot(place)
    if not place then return nil end
    local spot = self.pickupSpots and self.pickupSpots[place.id]
    if spot then return spot end
    return { latitude = place.latitude, longitude = place.longitude }
  end

  -- How far the player is from a town's pickup point, and whether they are within RADIUS of it.
  function c:atPickup(place, current)
    current = current or (self.lastSample and self.lastSample.valid and self.lastSample or nil)
    local spot = current and self:pickupSpot(place)
    local away = spot and location.distance(current, spot)
    return away ~= nil and away <= M.RADIUS, away
  end

  -- Why the player is not at a town's pickup point, to take a job ('take') or deliver one, or nil
  -- when they are.
  function c:pickupProblem(place, deliver)
    local inside, away = self:atPickup(place)
    if inside then return nil end
    local what = deliver and 'drop-off point' or 'pickup point'
    return 'Drive to the ' .. what .. ' in ' .. place.name .. (away and (', ' .. math.floor(away + 0.5) .. ' m away,') or '')
      .. ' and stop within ' .. M.RADIUS .. ' m of it to ' .. (deliver and 'deliver.' or 'take a job.')
  end

  -- Moves the pickup points of the towns near the player onto their roads. Called every frame; does
  -- its work every CHECK_SECONDS, one town at a time.
  function c:watchPickups()
    if not self.pickupWorld then return end
    if self.pickupCheckAt and self.clock - self.pickupCheckAt < M.CHECK_SECONDS then return end
    self.pickupCheckAt = self.clock
    local sample = self.lastSample
    if self.state ~= 'READY' or not self.arrived or self.hire or self.onFoot or not sample or not sample.valid then return end
    self.pickupSpots = self.pickupSpots or {}
    self.pickupSeen = self.pickupSeen or {}
    for _, place in ipairs(places.within(sample, M.SNAP_NEAR_METRES)) do
      if not self.pickupSpots[place.id] and (location.distance(sample, place) or math.huge) <= M.SNAP_NEAR_METRES then
        local seen = self.pickupSeen[place.id]
        if not seen then
          self.pickupSeen[place.id] = self.clock
        elseif self.clock - seen >= M.SETTLE_SECONDS then
          local me = self.pickupWorld:where()
          if not me then return end
          local spot = M.snap(self.pickupWorld, me, sample, place)
          if spot == false and (location.distance(sample, place) or math.huge) <= M.LOCK_METRES then
            spot = { latitude = place.latitude, longitude = place.longitude }
          end
          if spot then
            self.pickupSpots[place.id] = { latitude = spot.latitude, longitude = spot.longitude }
            self.pickupSeen[place.id] = nil
            self.diag:event('pickup', string.format('%s %.0f m from the town point', place.id,
              location.distance(place, spot) or 0))
            -- A GPS set to the town follows its point onto the road.
            if self.gpsTown == place.id then
              if self.load and self.load.to == place.id and not self.load.business then self:gpsToJob()
              else self:gpsToTown(place.id) end
            end
            if self.gpsPickup == place.id then self:gpsToPickup() end
            return
          end
        end
      end
    end
  end

  -- The pickup point of the town the player is in, for the Town tab and the minimised strip, while
  -- they have no job: how far, which way, and the needle that points to it.
  function c:pickupView(place, current)
    if not place or not current or self.load then return nil end
    local spot = self:pickupSpot(place)
    local away = location.distance(current, spot)
    local bearing = away and away > 1 and location.bearing(current, spot) or nil
    local sample = self.lastSample
    local heading = sample and location.finite(sample.heading) and sample.heading or self.heading
    return {
      name = place.name, radiusMetres = M.RADIUS, inZone = away ~= nil and away <= M.RADIUS,
      distanceMetres = away and math.floor(away + 0.5) or nil,
      direction = bearing and location.compassPoint(bearing) or nil,
      letters = bearing and location.compassLetters(bearing) or nil,
      -- Which way to turn: the point's bearing from the way the player faces, 0 straight ahead.
      arrow = bearing and heading and (bearing - heading) % 360 or nil,
      gps = self.gpsPickup == place.id or nil,
      gpsAllowed = self.adapter.setDestination ~= nil and not self.hire,
    }
  end

  -- The drop-off point of a job with no business to go to: its town's pickup point, with the same
  -- needle once the player is within COUNTDOWN_METRES of it.
  function c:dropPointView(current)
    local load = self.load
    if not load or load.drop or load.business or not current then return nil end
    local town = places.get(load.to)
    local spot = town and self:pickupSpot(town)
    local away = spot and location.distance(current, spot)
    if not away then return nil end
    local bearing = away > 1 and location.bearing(current, spot) or nil
    local sample = self.lastSample
    local heading = sample and location.finite(sample.heading) and sample.heading or self.heading
    return {
      distanceMetres = math.floor(away + 0.5), radiusMetres = M.RADIUS,
      near = away <= M.COUNTDOWN_METRES, inZone = away <= M.RADIUS,
      arrow = bearing and heading and (bearing - heading) % 360 or nil,
    }
  end

  -- Sets the GPS to the pickup point of the town the player is in.
  function c:gpsToPickup()
    local place = self:here()
    if not place or not self.adapter.setDestination or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local name = place.name .. ' pickup point'
    local ok, why = self.adapter:setDestination(self:pickupSpot(place), name)
    self.diag:event('gps', ok and ('pickup:' .. place.id) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract, self.gpsDepot, self.gpsRun = nil, nil, nil, nil
    self.gpsPickup = ok and place.id or nil
    self.gpsFeedback = ok and ('The GPS is set to the ' .. name .. '.') or 'Could not set the GPS.'
    return ok == true
  end
end

return M
