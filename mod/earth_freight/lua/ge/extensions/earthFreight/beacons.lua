-- "Don't ask questions" jobs. Flying a hired helicopter, the player may pick up a signal beacon: a
-- package lying off road somewhere near where their car waits. Driven from there to a second spot
-- off road, it pays PAY, whatever it is: nobody asks. Pure maths; no game globals.
local location = require('earthFreight/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- Every FIND_SECONDS flown at least MIN_HEIGHT metres above the ground, a beacon turns up with
-- FIND_CHANCE, unless one is already waiting or on board.
M.FIND_SECONDS, M.FIND_CHANCE, M.MIN_HEIGHT = 300, 0.5, 30
-- What it pays, and what an insurance claim costs while it is on board (as on a dangerous contract).
M.PAY, M.INSURANCE_FEE = 12000, 4000
-- A beacon not picked up within EXPIRE_SECONDS of play goes quiet.
M.EXPIRE_SECONDS = 3600
-- The pickup is SPOT_MIN to SPOT_MAX metres from the helicopter, and no more than CAR_METRES from
-- the car, so it can be driven to; TRIES directions are tried before giving up for this time.
M.SPOT_MIN, M.SPOT_MAX, M.CAR_METRES, M.TRIES = 500, 3000, 15000, 8
-- The drop is DROP_MIN to DROP_MAX metres from the pickup, any way.
M.DROP_MIN, M.DROP_MAX = 2000, 5000
-- Picked up and delivered stopped within RADIUS metres of the spot.
M.RADIUS = 100

-- What is waiting at the pickup, one picked at random each time, never the same twice running.
M.LINES = {
  'A duffel bag behind a burnt-out car.',
  'A cooler box at an old campsite.',
  'A sports bag tucked under a fallen tree.',
  'A taped-up suitcase in a dry creek bed.',
  "A toolbox that's far too heavy to hold tools.",
  'A backpack hanging from a fence post.',
  'A sealed drum half-buried in the dirt.',
  'A gym bag inside an abandoned shed.',
  'A briefcase under a pile of rocks.',
  'A cardboard box marked "spare parts".',
  'A wrapped package wedged inside a hollow log.',
  'A locked cash box beside an old water tank.',
  "A bundle of tarps that's not hiding tarps.",
  'A guitar case with no guitar in it.',
  'A fishing tackle box nowhere near any water.',
  'A plastic crate under a camouflage net.',
  "A pizza box that's been here for days.",
  'A suitcase dumped beside a rusted-out tractor.',
  'A sack of "fertiliser" that smells wrong.',
}

local function point(p) return { latitude = p.latitude, longitude = p.longitude } end

-- A beacon found from the helicopter at heli, for a car waiting at car: { pickup, drop, line,
-- left }, or nil when no spot near enough to the car turns up. random() gives a number in [0, 1);
-- last is the line used last time, which is not used again.
function M.find(heli, car, random, last)
  if not location.valid(heli) or not location.valid(car) then return nil end
  for _ = 1, M.TRIES do
    local pickup = location.destination(heli, random() * 360, M.SPOT_MIN + (M.SPOT_MAX - M.SPOT_MIN) * random())
    local away = pickup and location.distance(pickup, car)
    if away and away <= M.CAR_METRES then
      local drop = location.destination(pickup, random() * 360, M.DROP_MIN + (M.DROP_MAX - M.DROP_MIN) * random())
      local count = (last and last >= 1 and last <= #M.LINES) and #M.LINES - 1 or #M.LINES
      local line = math.min(count, math.floor(random() * count) + 1)
      if last and line >= last and count < #M.LINES then line = line + 1 end
      return { pickup = point(pickup), drop = point(drop), line = line, left = M.EXPIRE_SECONDS }
    end
  end
  return nil
end

-- The words for a line number; a general one for a number this version does not have.
function M.line(n) return M.LINES[n] or 'A package nobody wants to talk about.' end

return M
