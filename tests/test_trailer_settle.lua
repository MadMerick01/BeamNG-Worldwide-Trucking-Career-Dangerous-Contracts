local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local TR = require('earthFreight/trailers')

-- A trailer settles like the car: it drops onto its legs when it comes out and the hitch jolts it
-- as it couples. That damage is not billed, and a trailer bent by it is mended where it stands, so
-- a bent coupler cannot leave it bouncing on the hitch (reported after resuming a tanker job).
local function tanker()
  local c, _, a, g = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000, paid = 26000 }
  T.check(c:spawnTrailer(), 'the tanker is out')
  return c, a, g, c.trailerOut.id
end

-- Coming out and hitching: nothing billed.
do
  local c, _, g, id = tanker()
  g.trailers[id].damage = 300; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 0, 'the drop onto its legs is not billed')
  F.advance(c, 30)
  g.trailers[id].damage = 450; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 0, 'nor bumps while the player backs up to it')
  T.eq(g.trailerRepairs, 0, 'a little settling is not mended')
  c:couplerChanged(g.vehicleId, id, true)
  g.trailers[id].damage = 480; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 0, 'nor the jolt of the hitch')
  F.advance(c, TR.SETTLE_SECONDS)
  -- Settled: a crash from here on is billed, on top of what it settled with.
  g.trailers[id].damage = 480 + 2000; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 2000, 'a crash once hitched is billed')
  -- Unhitched and hitched again: what it owes stays.
  c:couplerChanged(g.vehicleId, id, false); c:couplerChanged(g.vehicleId, id, true)
  g.trailers[id].damage = 480 + 2000 + 10; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 2000, 'hitching again keeps what it owes, without the jolt')
  F.advance(c, TR.SETTLE_SECONDS)
  g.trailers[id].damage = 480 + 2000 + 10 + 700; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 2700, 'and bills what comes after')
end

-- A damaged trailer that was stored still owes its repair when it comes out again.
do
  local c, _, g, id = tanker()
  c.trailer.damage = 5000
  g.trailers[id].damage = 200; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 5000, 'the stored damage is still owed, the drop is not added')
end

-- Bent while waiting to hitch (bouncing on the coupler): mended where it stands, for free, and asked
-- to hitch again; it still owes what it owed. Only MENDS times each time it comes out.
do
  local c, _, g, id = tanker()
  c.trailer.damage = 1000
  local hitches = 0
  local hitch = g.hitch
  function g:hitch(...) hitches = hitches + 1; if hitch then return hitch(self, ...) end return true end
  g.trailers[id].damage = TR.MEND_DAMAGE + 4000; F.advance(c, 1.2)
  T.eq(g.trailerRepairs, 0, 'not while it is still dropping onto its legs')
  F.advance(c, TR.SETTLE_SECONDS)
  T.eq(g.trailerRepairs, 1, 'mended once it stands')
  T.eq(hitches, 1, 'and asked to hitch again')
  T.eq(c:trailerDamage(), 1000, 'it still owes its earlier repair, nothing more')
  T.eq(g.vehicleId, 1, 'the player stays in their car')
  for _ = 1, TR.MENDS + 2 do
    g.trailers[id].damage = TR.MEND_DAMAGE + 4000; F.advance(c, TR.SETTLE_SECONDS + 1.2)
  end
  T.eq(g.trailerRepairs, TR.MENDS, 'mended at most MENDS times')
  T.eq(c:trailerDamage(), 1000, 'none of that bouncing is billed')
  -- Once the grace runs out without hitching, damage is billed again.
  F.advance(c, TR.HITCH_GRACE_SECONDS)
  g.trailers[id].damage = TR.MEND_DAMAGE + 4000 + 600; F.advance(c, 1.2)
  T.eq(c:trailerDamage(), 1600, 'after the grace, a crash into it is billed')
end

-- Bent by the jolt of the hitch: mended after it settles, only with the car standing still.
do
  local c, a, g, id = tanker()
  c:couplerChanged(g.vehicleId, id, true)
  g.trailers[id].damage = TR.MEND_DAMAGE + 100; F.advance(c, 1.2)
  local stopped = c.odometer.stopped
  c.odometer.stopped = function() return false end
  F.advance(c, TR.SETTLE_SECONDS)
  T.eq(g.trailerRepairs, 0, 'not while driving')
  c.odometer.stopped = stopped
  F.advance(c, 1.2)
  T.eq(g.trailerRepairs, 1, 'mended once the car stands still')
  T.eq(c:trailerDamage(), 0, 'nothing billed')
end

-- Resuming: the saved trailer comes out only once the car has settled where it stays.
do
  local c, _, a, g = F.controller({ settle = true })
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c.trailer = { model = 'tanker', config = 'vehicles/tanker/empty.pc', maxKg = 34000, paid = 26000, stored = false }
  c.trailerOut, c.trailerRestored = nil, nil
  c:startSettle(true, 15)
  c:watchTrailer()
  T.eq(c.trailerOut, nil, 'not while the car is still settling')
  c.clock = c.clock + 16
  c:watchTrailer()
  T.check(c.trailerOut ~= nil, 'out behind the car once it has settled')
end

T.done('Trailer settling')
