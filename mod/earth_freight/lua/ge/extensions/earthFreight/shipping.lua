-- Shipping (Relocate): the cheap way to take your vehicle to another region. The base is booked on the
-- Relocate tab, paid, then reached with Teleport (Earth's own teleport, as its map's Go). Anywhere else is
-- reached with the BeamNG.Earth map's Teleport here and paid for after, in a pop-up; until it is paid, or the
-- player is back where they jumped from, they are stranded.
-- Pure maths; no game globals.
local location = require('earthFreight/location')
local M = {}

-- The fee: a flat amount plus a little per km. Tune after testing in game.
M.BASE_FEE, M.FEE_PER_KM = 100, 0.02
-- A teleport that lands this close to the booked destination uses up the booking.
M.ARRIVE_METRES = 5000
-- After a teleport without a booking, getting back this close to where you jumped from frees you.
M.RETURN_METRES = 1000

-- The paid-shipping offer: a town in one of the hardest regions pays back your shipping fee once
-- you deliver within OFFER_RADIUS_METRES of it. A new town is offered every OFFER_SECONDS.
M.OFFER_SECONDS = 300
M.OFFER_RADIUS_METRES = 50000

-- The offer showing at a time (seconds), from a list of places, and the seconds until the next.
-- The pick is a hash of the time window, so it is the same for everyone in that window.
function M.offer(now, list)
  if type(now) ~= 'number' or not list or #list == 0 then return nil end
  local window = math.floor(now / M.OFFER_SECONDS)
  local h = (window * 2654435761) % 4294967296
  h = (h * 1103515245 + 12345) % 2147483648
  return list[h % #list + 1], M.OFFER_SECONDS - (now - window * M.OFFER_SECONDS)
end

-- Whether a delivery at a place pays back an offer's shipping.
function M.offerPays(place, offer)
  local d = offer and location.distance(place, offer)
  return d ~= nil and d <= M.OFFER_RADIUS_METRES
end

-- Whole dollars to ship from a point to a destination.
function M.fee(from, destination)
  local d = location.distance(from, destination)
  if not d then return nil end
  return math.floor(M.BASE_FEE + d / 1000 * M.FEE_PER_KM + 0.5)
end

function M.arrived(point, booking)
  local d = booking and location.distance(point, booking)
  return d ~= nil and d <= M.ARRIVE_METRES
end

function M.returned(point, from)
  local d = from and location.distance(point, from)
  return d ~= nil and d <= M.RETURN_METRES
end

return M
