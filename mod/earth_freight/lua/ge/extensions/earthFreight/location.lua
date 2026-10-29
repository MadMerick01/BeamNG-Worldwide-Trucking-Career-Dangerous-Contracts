-- Pure geographic math; no game globals.
local M = {}
local rad, sin, cos, sqrt, atan2, asin = math.rad, math.sin, math.cos, math.sqrt, math.atan2, math.asin
local EARTH_MEAN_RADIUS = 6371008.8 -- metres; spherical short-range approximation for WGS84 coordinates

function M.finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end

function M.valid(p)
  return type(p) == 'table' and M.finite(p.latitude) and M.finite(p.longitude)
    and p.latitude >= -90 and p.latitude <= 90 and p.longitude >= -180 and p.longitude <= 180
end

function M.copy(p)
  if not M.valid(p) then return nil end
  return { latitude = p.latitude, longitude = p.longitude }
end

function M.distance(a, b)
  if not M.valid(a) or not M.valid(b) then return nil end
  local dlat, dlon = rad(b.latitude - a.latitude), rad(b.longitude - a.longitude)
  local h = sin(dlat / 2)^2 + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dlon / 2)^2
  h = math.max(0, math.min(1, h))
  return 2 * EARTH_MEAN_RADIUS * atan2(sqrt(h), sqrt(1 - h))
end

-- Initial great-circle bearing from a to b in degrees clockwise from north (0 to 360).
function M.bearing(a, b)
  if not M.valid(a) or not M.valid(b) then return nil end
  local lat1, lat2, dlon = rad(a.latitude), rad(b.latitude), rad(b.longitude - a.longitude)
  local y = sin(dlon) * cos(lat2)
  local x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
  return (math.deg(atan2(y, x)) + 360) % 360
end

-- The point this many metres from p along a great circle starting on this bearing (degrees).
function M.destination(p, bearing, metres)
  if not M.valid(p) or not M.finite(bearing) or not M.finite(metres) then return nil end
  local d, theta = metres / EARTH_MEAN_RADIUS, rad(bearing)
  local lat1, lon1 = rad(p.latitude), rad(p.longitude)
  local lat2 = asin(math.max(-1, math.min(1, sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(theta))))
  local lon2 = lon1 + atan2(sin(theta) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
  return { latitude = math.deg(lat2), longitude = (math.deg(lon2) + 540) % 360 - 180 }
end

local POINTS = { 'north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west' }
local LETTERS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }

-- The nearest of the eight compass points to a bearing in degrees.
function M.compassPoint(bearing)
  if not M.finite(bearing) then return nil end
  return POINTS[math.floor(((bearing % 360) + 22.5) / 45) % 8 + 1]
end

-- The same compass point as letters: N, NE, E and so on.
function M.compassLetters(bearing)
  if not M.finite(bearing) then return nil end
  return LETTERS[math.floor(((bearing % 360) + 22.5) / 45) % 8 + 1]
end

return M
