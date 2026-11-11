-- The Magnate update: a base of operations has a circle of influence around its town, sized by the
-- owner's wealth (cash, truck and base) and the region's steepness. Jobs with an end in the owner's own
-- turf pay them OWNER_SHARE more of the region multiplier there. A delivery whose drop-off is in someone
-- else's turf pays TOLL of its pay to that turf's owner (Magnate 2). Where circles overlap, the bigger
-- one pushes the border towards the smaller one, and every base keeps a CORE_KM core. Pure Lua: no game
-- globals. Design: docs/baseofoperations.md.
local location = require('earthFreight/location')
local M = {}

-- A base worth START_WEALTH in a flat region (×1.0) reaches START_KM; its area grows in line with
-- wealth, and steep regions reach further by √(multiplier). There is no cap: MAX_KM is half way round
-- the world, past which a circle covers the whole planet anyway.
M.START_WEALTH, M.START_KM, M.MAX_KM = 250000, 1600, 20000
M.OWNER_SHARE = 0.4
-- The share of a delivery's pay that goes to the owner of the turf its drop-off is in, when that's not you.
M.TOLL = 0.2
M.CORE_KM = 100
-- On a server, bases are at least this far apart, town centre to town centre, so cores never overlap.
M.MIN_APART_KM = 300

-- The circle's radius in km for this much wealth, at a base whose region multiplier is boost.
function M.radiusKm(wealth, boost)
  wealth = math.max(0, tonumber(wealth) or 0)
  boost = math.max(1, tonumber(boost) or 1)
  return math.min(M.MAX_KM, M.START_KM * math.sqrt(wealth / M.START_WEALTH) * math.sqrt(boost))
end

-- The wealth a base at this multiplier needs to reach this radius (for "grows to N km at $X").
function M.wealthFor(radiusKm, boost)
  boost = math.max(1, tonumber(boost) or 1)
  return M.START_WEALTH * (radiusKm / (M.START_KM * math.sqrt(boost))) ^ 2
end

-- Whose turf a point is: among the circles it is inside, a base's own core first, else the one with
-- the smallest distance ÷ radius, which puts each border in proportion to the two circles' sizes.
-- circles: { latitude, longitude, radiusKm, mine }. Returns the circle, or nil outside them all.
function M.turf(circles, point)
  if not point or not location.valid(point) then return nil end
  local best, bestScore
  for _, c in ipairs(circles or {}) do
    local km = location.distance(c, point) / 1000
    if km <= M.CORE_KM then return c end
    if km <= c.radiusKm then
      local score = km / c.radiusKm
      if not bestScore or score < bestScore then best, bestScore = c, score end
    end
  end
  return best
end

-- The share of the region multiplier a point adds for this player: OWNER_SHARE in their own turf, 0
-- anywhere else.
function M.shareAt(circles, point)
  local owner = M.turf(circles, point)
  return owner and owner.mine and M.OWNER_SHARE or 0
end

-- The circle a delivery to this point pays the toll to: someone else's turf, or nil (your own, or none).
function M.tollAt(circles, point)
  local owner = M.turf(circles, point)
  if owner and not owner.mine then return owner end
  return nil
end

-- What a delivery paying this much leaves the driver, and the toll, when its drop-off is in someone else's turf.
function M.afterToll(pay)
  local toll = math.floor(pay * M.TOLL / 10 + 0.5) * 10
  return pay - toll, toll
end

return M
