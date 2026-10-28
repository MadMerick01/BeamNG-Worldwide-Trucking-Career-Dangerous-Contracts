-- Shipping: the cheap way to take your vehicle to another region. Book with an empty vehicle, pay,
-- then press Teleport (Earth's own teleport, as its map's Go) or paste the coordinates into the
-- BeamNG.Earth map. A teleport without a booking strands you until you are back where you jumped from.
-- Pure maths and the destination list; no game globals.
local location = require('earthFreight/location')
local M = {}

-- Where you can ship to: a town in each region worth the trip. id is what the HUD sends.
M.DESTINATIONS = {
  { id = 'penrith', name = 'Penrith', region = 'Sydney, Australia', latitude = -33.75, longitude = 150.7 },
  { id = 'katoomba', name = 'Katoomba', region = 'Blue Mountains, Australia', latitude = -33.7198, longitude = 150.3074 },
  { id = 'lapaz', name = 'La Paz', region = 'Top of Death Road, Bolivia', latitude = -16.5, longitude = -68.15 },
  { id = 'coroico', name = 'Coroico', region = 'Death Road, Yungas, Bolivia', latitude = -16.1939, longitude = -67.73 },
  { id = 'bormio', name = 'Bormio', region = 'Stelvio Pass, Italy', latitude = 46.4672, longitude = 10.3701 },
  { id = 'zermatt', name = 'Zermatt', region = 'Swiss Alps', latitude = 46.02, longitude = 7.7486 },
  { id = 'gilgit', name = 'Gilgit', region = 'Karakoram Highway, Pakistan', latitude = 35.9187, longitude = 74.3124 },
  { id = 'leh', name = 'Leh', region = 'Ladakh, India', latitude = 34.165, longitude = 77.584 },
}
-- How many towns a search by name shows.
M.SEARCH_RESULTS = 6
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

local byId = {}
for _, d in ipairs(M.DESTINATIONS) do byId[d.id] = d end

function M.get(id) return byId[id] end

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
