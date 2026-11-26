-- The Raiders on the special delivery (special.lua): rival clans' cars that come for you across the dunes. This is
-- MadMerick's Hoon pack from his Tanker mod (its pack.lua), desert mode only: no roads out there, and nothing to rob,
-- since the load always stays whole. Each Raider moves between eight slots around your truck, named as on MadMerick's
-- diagram: L or R (your left or right), F or R (front or rear), then N or F (near or far). RFF is right, front, far;
-- LRN is left, rear, near.
--
--   LFF . . . . . . . . RFF       far: 60 m out to the side, 10 m beyond your front or back
--         LFN  []  RFN            near: 10 m out to the side, level with your front or back
--         LRN  []  RRN
--   LRF . . . . . . . . RRF
--
-- A new Raider sizes you up first, circling the far slots like a hyena, then closes in to a near slot, lines up and
-- attacks. Some attacks swipe you and drive back out to a far slot; others try to box you in as a team: one gets in
-- front and the others close in on both sides and behind, then they all slow down together to stop you. Only one
-- attack happens at a time; Raiders not in it hold their slots and wait.
--
-- For the first test (MadMerick, 26 Nov) they just keep coming: at most MAX Raiders are up at once, and one that is
-- down (stopped or stuck) or falls ESCAPE_METRES behind is replaced (desertRun.lua sends the next). A downed
-- Raider's car stays where it stopped, with BOOT_MIN to BOOT_MAX rounds in its boot, until you are LEAVE_METRES
-- away. This is the logic only; raiderCar.lua does the game's side.
local M = {}
local behind = require('earthFreight/behind')

-- One-line settings. Tune these after testing in game.
-- At most this many Raiders up at once, and at most MAX_DOWN downed cars left standing for their boots.
M.MAX, M.MAX_DOWN = 4, 4
-- The slots: near is NEAR_SIDE metres out to the side, level with your front or back; far is
-- FAR_SIDE metres out and FAR_BEYOND metres beyond your front or back. HALF_LENGTH is half your
-- truck's length, from its middle to its front or back.
M.NEAR_SIDE, M.FAR_SIDE, M.FAR_BEYOND, M.HALF_LENGTH = 10, 60, 10, 3
-- Half your truck's width, in metres.
M.HALF_WIDTH = 1.3
-- The rear far slots (LRF, RRF) sit only this far out, so a Raider behind you stays close (MadMerick,
-- 6 Nov): about 30 m from you.
M.REAR_FAR_SIDE = 30
-- A Raider is at a far slot within this many metres of it, at a near slot within NEAR_ARRIVE.
M.FAR_ARRIVE, M.NEAR_ARRIVE = 15, 6
-- Driving to a slot uses the Raiders' own desert driver in the car (lua/vehicle/extensions/earthFreightRaider.lua), fed a new
-- point and speed every STEER_SECONDS (it brakes to a stop if it gets none for 0.6 s).
-- The speed is yours, plus GAIN metres a second for every metre the Raider is behind its slot
-- along your heading (less if it is ahead), plus SIDE_GAIN for every metre it is out to the
-- side, but never more than CATCH_UP_MPS faster than you. The point is LEAD_SECONDS of your
-- speed beyond the slot (between MIN_LEAD and MAX_LEAD metres), so the Raider runs alongside you
-- instead of turning in at the slot.
M.STEER_SECONDS = 0.2
M.GAIN, M.SIDE_GAIN, M.CATCH_UP_MPS = 0.6, 0.15, 15
M.LEAD_SECONDS, M.MIN_LEAD, M.MAX_LEAD = 1, 6, 25
-- Crossing in front of or behind you from one side to the other, a Raider swings this many metres
-- further out ahead or behind, so it doesn't cut across your nose.
M.CROSS_METRES = 30
-- How long a Raider waits at a far slot, then at a near slot, in seconds (picked between the two).
M.HOLD_FAR, M.HOLD_NEAR = { 2, 5 }, { 1.5, 3 }
-- A Raider never stops (MadMerick, 6 Nov): it always drives at MIN_MPS at least. One that would go
-- slower, because it is at its point or past it (you stopped, or you are chasing it), circles
-- the point ORBIT_METRES out instead, aiming ORBIT_STEP radians further round, like a hyena
-- pacing. Only a box parks in front of you on purpose.
M.MIN_MPS, M.ORBIT_METRES, M.ORBIT_STEP = 8, 20, 0.8
-- Changing spot is done by speeding up, not braking (MadMerick, 6 Nov): circling only ever moves
-- forward (a rear slot to the front slot on its side, a front slot round your nose to the other
-- front slot), and a Raider getting into place never asks for more than DROP_MPS below your
-- speed, so it drops back by easing off, not on the brakes. A Raider getting into place, lining up
-- or swiping never uses its brakes at all (MadMerick, 6 Nov): its driver lifts off instead, and it
-- asks for at most DROP_MPS less than your speed, so it moves round you sideways or forwards,
-- and only ever eases back slowly.
M.DROP_MPS = 1
-- How many far slots a new Raider circles through before closing in (picked between the two). A
-- bold one (BOLD_CHANCE of them) moves in after one at most. After an attack it circles 0 to 2.
M.CIRCLES, M.BOLD_CHANCE, M.CIRCLES_AFTER = { 2, 6 }, 0.3, { 0, 2 }
-- Before it strikes, a Raider edges in to this many metres off your side for WINDUP_SECONDS, so
-- you can see it coming.
M.WINDUP_SIDE, M.WINDUP_SECONDS = 6, 1.5
-- A swipe is the Raiders' own driver aimed into the corner of your truck by its slot: SWIPE_INTO
-- metres from your middle on that side (inside your bodywork, so it hits), level with your
-- front or back, only STRIKE_LEAD metres ahead of that point so it turns in hard. It matches
-- your speed and turns in suddenly, with no brake (MadMerick, 6 Nov). It lasts up to
-- SWIPE_SECONDS; within CONTACT_METRES it has hit you, and it peels off AFTER_CONTACT_SECONDS
-- later.
M.SWIPE_INTO, M.STRIKE_LEAD = 0.5, 2
M.SWIPE_SECONDS, M.CONTACT_METRES, M.AFTER_CONTACT_SECONDS = 4, 5, 1
-- The PIT (MadMerick, 6 Nov): a Raider at one of your rear near slots goes for your back wheel instead
-- of swiping, PIT_CHANCE of the time (PIT_GUN_CHANCE while your revolver is drawn, since your
-- back corners are hardest to shoot at). It lines up PIT_SIDE metres off your back corner, then
-- matches your speed plus PIT_PUSH and steers its nose through your back wheel, PIT_WHEEL metres
-- ahead of your back, aiming PIT_INTO metres past your middle, so your back end is shoved
-- sideways and you spin. No brake, as in a swipe.
M.PIT_CHANCE, M.PIT_GUN_CHANCE = 0.5, 0.8
M.PIT_SIDE, M.PIT_PUSH, M.PIT_WHEEL, M.PIT_INTO = 3, 2, 1.5, 1
-- Aiming where you'll be (MadMerick, 6 Nov): while you turn faster than TURN_RAD_S (radians a
-- second), a Raider aims at its spot around where you will be, following your turn, up to
-- PREDICT_SECONDS ahead (the time it needs to get there), so it cuts inside your turn instead
-- of chasing round the outside. Your turn rate is smoothed by TURN_SMOOTH each reading.
M.TURN_RAD_S, M.PREDICT_SECONDS, M.TURN_SMOOTH = 0.05, 2.5, 0.5
-- Respecting your revolver (MadMerick, 6 Nov): while it is drawn, Raiders getting into place weave
-- WEAVE_METRES side to side every WEAVE_SECONDS, Raiders at your rear slots stay there instead of
-- moving up to your front, and more attacks are PITs. A Raider you hit but don't stop drops back:
-- for SHY_SECONDS it peels off to a far slot, keeps further out (SHY_SIDE times the usual), may
-- ease off up to SHY_DROP_MPS below your speed, and won't attack.
M.WEAVE_METRES, M.WEAVE_SECONDS = 4, 2.5
M.SHY_SECONDS, M.SHY_SIDE, M.SHY_DROP_MPS = 6, 1.5, 4
-- This share of attacks are a box instead of a swipe. The lead Raider gets BOX_AHEAD metres in
-- front of you and drives at BOX_SLOW of your speed; a second Raider, if there is one, sits
-- BOX_SIDE metres off your side. A box lasts up to BOX_SECONDS. Slower than STOPPED_MPS for
-- BOXED_SECONDS and you are boxed in; they hold you there for BOX_HOLD_SECONDS, then peel off.
M.BOX_CHANCE, M.BOX_AHEAD, M.BOX_SLOW, M.BOX_SIDE = 0.35, 8, 0.6, 4
M.BOX_SECONDS, M.STOPPED_MPS, M.BOXED_SECONDS, M.BOX_HOLD_SECONDS = 15, 2, 3, 5
-- A box is teamwork (MadMerick, 6 Nov): it needs at least one other Raider, and every free Raider joins.
-- The first takes the side it is already on, the next the other side, a third sits BOX_AHEAD
-- behind you, so with three or four Raiders you are boxed in on both sides. With two or more
-- helpers free, a box is TEAM_BOX_CHANCE of attacks. First they gather: the lead runs in front
-- at your speed while the others get alongside (within BOX_ARRIVE metres of their spot), or for
-- at most GATHER_SECONDS. Then they squeeze: all of them slow to BOX_SLOW of your speed together.
-- A Raider that goes down or is lost is replaced: a helper takes over the lead, and the team
-- keeps the box going.
M.TEAM_BOX_CHANCE, M.BOX_ARRIVE, M.GATHER_SECONDS = 0.6, 8, 8
-- A Raider that goes slower than STUCK_MPS for DOWN_SECONDS while you drive is down (wrecked or stuck). You must be
-- going at least DRIVING_MPS for that to count, since Raiders wait when you stop. One that hasn't hit you yet gets one
-- second chance: after STALL_SECONDS its path is sent again and the stall is logged, and then its clock starts over.
M.STUCK_MPS, M.DOWN_SECONDS, M.DRIVING_MPS, M.STALL_SECONDS = 1, 12, 3, 5
-- Caught on a bush out of sight (MadMerick, 6 Nov): a Raider slower than STUCK_MPS for UNSTICK_SECONDS
-- while you drive, at least UNSTICK_METRES from you and behind the camera (behind.lua), is
-- lifted UNSTICK_HOP metres on towards where it was heading, past what it is caught on. It lands
-- behind the camera too, so you never see it jump. At most UNSTICK_TRIES times before it gets
-- going again; a wrecked Raider that still doesn't move is down as before.
M.UNSTICK_SECONDS, M.UNSTICK_METRES, M.UNSTICK_HOP, M.UNSTICK_TRIES = 4, 50, 8, 3
-- Further than ESCAPE_METRES from you for ESCAPE_SECONDS, and it has fallen behind: it is gone (MadMerick: 500 m).
M.ESCAPE_METRES, M.ESCAPE_SECONDS = 500, 0
-- A downed Raider's car is put away once you are this far from it, and its boot with it.
M.LEAVE_METRES = 400
-- This many hits from your revolver stop a Raider.
M.SHOTS_TO_STOP = 4
-- What a downed Raider's boot holds, in rounds, picked at random between the two (MadMerick: a gamble).
M.BOOT_MIN, M.BOOT_MAX = 0, 20

-- A new Raider starts at a free far slot behind the camera (behind.lua). With none free
-- there, it starts this many metres straight behind the camera and drives to its slot.
M.HIDDEN_METRES = 60

-- side: -1 left, 1 right. ahead: 1 front, -1 rear.
M.SLOTS = {
  LFF = { side = -1, ahead = 1, far = true }, RFF = { side = 1, ahead = 1, far = true },
  RRF = { side = 1, ahead = -1, far = true }, LRF = { side = -1, ahead = -1, far = true },
  LFN = { side = -1, ahead = 1 }, RFN = { side = 1, ahead = 1 },
  RRN = { side = 1, ahead = -1 }, LRN = { side = -1, ahead = -1 },
}
-- The far slots in a ring, clockwise seen from above, for circling.
M.RING = { 'LFF', 'RFF', 'RRF', 'LRF' }

local WHERE = { L = 'left', R = 'right' }
local function where(slot)
  return WHERE[slot:sub(1, 1)] .. ' ' .. (slot:sub(2, 2) == 'F' and 'front' or 'rear')
end
M.DOING = {
  CIRCLING = 'sizing you up', CLOSING = 'closing in', WINDUP = 'lining up', SWIPE = 'attacking',
  PIT_WINDUP = 'lining up on your back wheel', PIT = 'going for your back wheel', SHY = 'backing off from your gun',
  PEEL = 'peeling off', BOXING = 'boxing you in, in front', BOX_SIDE = 'boxing you in, beside you', DOWN = 'down',
  BOX_REAR = 'boxing you in, behind you',
}
local LINES = {
  arrived = function(slot) return 'A Raider has turned up out on your ' .. where(slot) .. '. It is sizing you up.' end,
  windup = function(slot) return 'A Raider is lining up on your ' .. where(slot) .. '!' end,
  pit = function(slot) return 'A Raider is lining up on your ' .. WHERE[slot:sub(1, 1)] .. ' back wheel to spin you!' end,
  shy = 'You hit a Raider. It\'s backing off.',
  box = 'A Raider is getting in front of you to box you in!',
  teamBox = function(n) return n .. ' Raiders are working together to box you in!' end,
  squeeze = 'The Raiders are closing the box. Get out or get stopped!',
  boxed = 'The Raiders have boxed you in.',
  swiped = 'The Raider hit you and peeled off.',
  pitted = 'The Raider shoved your back end and peeled off.',
  missed = 'The Raider missed and peeled off.',
  down = 'A Raider is down. Its boot may hold rounds.',
  shotDown = 'You shot a Raider to a stop. Its boot may hold rounds.',
  driverShot = 'You shot a Raider\'s driver. Its boot may hold rounds.',
  escaped = 'A Raider fell more than 500 m behind and is gone.',
  gone = 'A Raider is gone.',
  full = 'That\'s as many Raiders as there can be at once.',
  cleared = 'The Raiders are gone.',
}
M.LINES = LINES

local function distance2d(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The slot's offset from your middle: metres to your right, metres ahead.
function M.offset(slot)
  local s = M.SLOTS[slot]
  local side = s.far and (s.ahead < 0 and M.REAR_FAR_SIDE or M.FAR_SIDE) or M.NEAR_SIDE
  local ahead = M.HALF_LENGTH + (s.far and M.FAR_BEYOND or 0)
  return s.side * side, s.ahead * ahead
end

-- Where an offset (right, ahead) from you will be in t seconds, if you keep going at speed.
function M.at(me, right, ahead, t, speed)
  local go = (speed or me.speed or 0) * (t or 0) + ahead
  return me.x + me.dx * go + me.dy * right, me.y + me.dy * go - me.dx * right
end

-- Where you will be in t seconds if you keep turning as you are: a pose like me.
function M.future(me, yaw, t)
  if math.abs(yaw or 0) < M.TURN_RAD_S or not (t and t > 0) then return me end
  local v = me.speed or 0
  local h0 = math.atan2(me.dy, me.dx)
  local h1 = h0 + yaw * t
  return { id = me.id, z = me.z, speed = v, dx = math.cos(h1), dy = math.sin(h1),
    x = me.x + v / yaw * (math.sin(h1) - math.sin(h0)), y = me.y - v / yaw * (math.cos(h1) - math.cos(h0)) }
end

-- The next far slot when circling, always forwards: rear to the front on the same side, front to
-- the front on the other side (round your nose).
function M.forward(slot)
  local side, endOf = slot:sub(1, 1), slot:sub(2, 2)
  if endOf == 'R' then return side .. 'FF' end
  return (side == 'L' and 'R' or 'L') .. 'FF'
end

local function near(slot) return slot:sub(1, 2) .. 'N' end
local function far(slot) return slot:sub(1, 2) .. 'F' end

-- car is packCar (or a fake), random(lo, hi) a number between them.
function M.new(car, random)
  random = random or function(lo, hi) return lo + math.random() * (hi - lo) end
  local p = { raiders = {}, count = 0 }

  local function pick(range) return random(range[1], range[2]) end
  local function whole(range) return math.min(range[2], math.floor(random(range[1], range[2] + 1))) end
  local function chance(share) return random(0, 1) < share end

  -- Whether a slot is taken by another Raider that is still up.
  local function taken(slot, except)
    for _, h in ipairs(p.raiders) do
      if h ~= except and h.state ~= 'DOWN' and h.slot == slot then return true end
    end
    return false
  end
  local function strikers()
    local n = 0
    for _, h in ipairs(p.raiders) do
      if h.state == 'WINDUP' or h.state == 'SWIPE' or h.state == 'BOXING' then n = n + 1 end
    end
    return n
  end
  local function ringIndex(slot)
    for i, s in ipairs(M.RING) do if s == slot then return i end end
  end
  local function freeFar(except)
    local free = {}
    for _, s in ipairs(M.RING) do if not taken(s, except) then free[#free + 1] = s end end
    return free
  end

  -- The offset a Raider drives to now, and the speed factor and crossing point on the way.
  -- The offset a Raider drives to now (right, ahead), the share of your speed to match there, how
  -- far ahead of the point to aim (nil: the usual lead), and any extra speed on top.
  local function target(h)
    local boxLead = h.state == 'BOXING' and h or h.lead
    local squeeze = boxLead and boxLead.squeeze and M.BOX_SLOW or 1
    if h.state == 'BOXING' then return 0, M.HALF_LENGTH + M.BOX_AHEAD, squeeze end
    if h.state == 'BOX_SIDE' then return h.side * M.BOX_SIDE, 0, squeeze end
    if h.state == 'BOX_REAR' then return 0, -(M.HALF_LENGTH + M.BOX_AHEAD), squeeze end
    local right, ahead = M.offset(h.slot)
    local side = M.SLOTS[h.slot].side
    if h.pit and h.state == 'WINDUP' then return side * (M.HALF_WIDTH + M.PIT_SIDE), ahead, 1 end
    if h.pit and h.state == 'SWIPE' then
      return -side * M.PIT_INTO, ahead + M.PIT_WHEEL, 1, M.STRIKE_LEAD
    end
    if h.state == 'WINDUP' then right = side * M.WINDUP_SIDE end
    if h.state == 'SWIPE' then return side * M.SWIPE_INTO, ahead, 1, M.STRIKE_LEAD end
    if h.shyUntil and p.clock and p.clock < h.shyUntil then right = right * M.SHY_SIDE end
    -- Weaving while your revolver is drawn, so it is harder to hit.
    if p.gunDrawn and (h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL') then
      right = right + M.WEAVE_METRES * math.sin(2 * math.pi * (p.clock or 0) / M.WEAVE_SECONDS + h.n)
    end
    return right, ahead, 1
  end

  -- Your turn rate, smoothed, from your heading each time it is read (radians a second, left
  -- positive).
  local function track(me, clock)
    local heading = math.atan2(me.dy, me.dx)
    local last = p.heading
    if last and clock > last.clock then
      local dt = clock - last.clock
      if dt <= 2 then
        local turn = heading - last.value
        if turn > math.pi then turn = turn - 2 * math.pi elseif turn < -math.pi then turn = turn + 2 * math.pi end
        p.yaw = (p.yaw or 0) + M.TURN_SMOOTH * (turn / dt - (p.yaw or 0))
      else p.yaw = 0 end
    end
    if not last or clock > last.clock then p.heading = { value = heading, clock = clock } end
    p.clock = clock
  end


  -- Where the Raider is from you: metres to your right and ahead.
  local function relative(me, st)
    local x, y = st.x - me.x, st.y - me.y
    st.ahead = x * me.dx + y * me.dy
    st.right = x * me.dy - y * me.dx
  end

  -- Tells the Raider where to drive now and how fast: its slot, or round the front or back of you
  -- first when it is crossing to your other side.
  local function drive(h, me, st, clock)
    if h.replanAt and clock < h.replanAt then return end
    h.replanAt = clock + M.STEER_SECONDS
    relative(me, st)
    local right, ahead, slow, strikeLead = target(h)
    local mine = me.speed or 0
    local aimRight, aimAhead = right, ahead
    local hr, ha = st.right, st.ahead
    if hr * right < 0 and math.abs(hr) > M.NEAR_SIDE and math.abs(right) > M.NEAR_SIDE then
      local sign = (ahead + ha) >= 0 and 1 or -1
      aimRight, aimAhead = 0, sign * (math.max(math.abs(ahead), math.abs(ha)) + M.CROSS_METRES)
    end
    local speed = mine * slow + M.GAIN * (aimAhead - ha) + M.SIDE_GAIN * math.abs(aimRight - hr)
    -- A swipe matches your speed and turns in suddenly; a PIT pushes on through your back wheel.
    if h.state == 'SWIPE' then speed = mine + (h.pit and M.PIT_PUSH or 0) end
    local coasting = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL' or h.state == 'WINDUP'
      or h.state == 'SWIPE'
    local shy = h.shyUntil and clock < h.shyUntil
    if coasting then speed = math.max(speed, mine - (shy and M.SHY_DROP_MPS or M.DROP_MPS)) end
    speed = math.max(0, math.min(speed, mine + M.CATCH_UP_MPS))
    local lead = strikeLead or math.max(M.MIN_LEAD, math.min(M.MAX_LEAD, mine * M.LEAD_SECONDS))
    -- Never aim behind the Raider: its driver would turn round for a point behind it, slowly, and
    -- fall far behind you. A point it has passed is aimed at a little ahead of it instead, and the
    -- speed law drops it back.
    local aimAt = math.max(aimAhead + lead, ha + (strikeLead or M.MIN_LEAD))
    -- Turning: aim round your turn, where you will be by the time it gets there.
    local soon = M.future(me, p.yaw, math.min(M.PREDICT_SECONDS,
      distance2d(st.x, st.y, M.at(me, right, ahead, 0)) / math.max(mine, M.MIN_MPS)))
    local x, y = M.at(soon, aimRight, aimAt, 0)
    local sx, sy = M.at(me, right, ahead, 0)
    local boxing = h.state == 'BOXING' or h.state == 'BOX_SIDE' or h.state == 'BOX_REAR'
    h.spotMetres = distance2d(st.x, st.y, sx, sy)
    local placing = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL'
    h.orbiting = false
    if speed < M.MIN_MPS and not boxing then
      -- Never stop: near its point, circle it; further off, keep its aim (back to its point, or
      -- round you to your other side) at MIN_MPS. A windup or swipe only keeps its speed up.
      local ox, oy = st.x - sx, st.y - sy
      local r = math.sqrt(ox * ox + oy * oy)
      if placing and r < 2 * M.ORBIT_METRES then
        h.orbiting = true
        local angle = (r > 0.5 and math.atan2(oy, ox) or 0) + (h.dir or 1) * M.ORBIT_STEP
        x, y = sx + M.ORBIT_METRES * math.cos(angle), sy + M.ORBIT_METRES * math.sin(angle)
      end
      speed = M.MIN_MPS
    end
    local mode = h.state == 'SWIPE' and 'swipe' or (coasting and 'coast' or nil)
    h.aimX, h.aimY = x, y
    car:goTo(h.id, { x = x, y = y, z = car:ground(x, y, me.z) or me.z, speed = speed, slotX = sx, slotY = sy, mode = mode })
  end

  local function arrived(h, me, st)
    local right, ahead = target(h)
    local x, y = M.at(me, right, ahead, 0)
    local reach = (h.state == 'CIRCLING' or h.state == 'PEEL') and M.FAR_ARRIVE or M.NEAR_ARRIVE
    -- Circling its point because you are slow or stopped counts as being there.
    if h.orbiting then reach = math.max(reach, M.ORBIT_METRES + 5) end
    return distance2d(st.x, st.y, x, y) <= reach
  end

  local function peel(h, clock)
    local back = h.slot and far(h.slot)
    if not back or taken(back, h) then
      local free = freeFar(h)
      back = free[1] or back or M.RING[1]
    end
    h.state, h.slot, h.holdUntil, h.replanAt, h.side, h.lead, h.pit = 'PEEL', back, nil, nil, nil, nil, nil
    h.movesLeft = whole(M.CIRCLES_AFTER)
    h.since = clock
  end

  -- The Raiders helping h's box.
  local function helpers(h)
    local list = {}
    for _, o in ipairs(p.raiders) do if o ~= h and o.lead == h then list[#list + 1] = o end end
    return list
  end
  -- h is out of its box (down or gone). If it led, a helper takes over the lead, front first.
  local function leaveBox(h)
    local team = helpers(h)
    h.lead = nil
    if h.state ~= 'BOXING' or #team == 0 then return end
    local next = team[1]
    for _, o in ipairs(team) do if o.state == 'BOX_SIDE' then next = o break end end
    next.state, next.lead, next.side, next.replanAt = 'BOXING', nil, nil, nil
    next.since, next.squeeze, next.squeezeSince = h.since, h.squeeze, h.squeezeSince
    next.boxedSince, next.holdTill = h.boxedSince, h.holdTill
    for _, o in ipairs(team) do if o ~= next then o.lead = next end end
  end

  -- Hides the car for next time and forgets the Raider.
  local function release(h)
    leaveBox(h)
    car:release(h.id, h.source)
    for i, other in ipairs(p.raiders) do
      if other == h then table.remove(p.raiders, i) break end
    end
  end

  -- h is down: it stops where it is, with BOOT_MIN to BOOT_MAX rounds in its boot. With more than MAX_DOWN downed
  -- cars standing, the one down longest is put away.
  local function down(h, line)
    leaveBox(h)
    h.state, h.slot, h.downAt = 'DOWN', nil, p.clock or 0
    h.boot = whole({ M.BOOT_MIN, M.BOOT_MAX })
    car:calm(h.id)
    local downed = {}
    for _, o in ipairs(p.raiders) do if o.state == 'DOWN' then downed[#downed + 1] = o end end
    if #downed > M.MAX_DOWN then
      table.sort(downed, function(a, b) return a.downAt < b.downAt end)
      release(downed[1])
    end
    return line
  end

  -- How many Raiders are up: not down.
  function p:up()
    local n = 0
    for _, h in ipairs(self.raiders) do if h.state ~= 'DOWN' then n = n + 1 end end
    return n
  end

  -- Brings in one more Raider at a free far slot, in a Raider car (a hidden one, or a new one loaded). Returns the
  -- line to show, or nil and why not.
  function p:add(clock)
    if self:up() >= M.MAX then return nil, 'full' end
    local me = car:player()
    if not me then return nil, 'no_player' end
    local free = freeFar()
    if #free == 0 then return nil, 'full' end
    -- Out of sight (MadMerick, 6 Nov): only a slot behind the camera, else straight behind it.
    local view = behind.view(car, me)
    local hidden = {}
    for _, s in ipairs(free) do
      local sx, sy = M.at(me, M.offset(s))
      if behind.isBehind(view, sx, sy) then hidden[#hidden + 1] = s end
    end
    local pickFrom = #hidden > 0 and hidden or free
    local slot = pickFrom[math.min(#pickFrom, math.floor(random(1, #pickFrom + 1)))]
    local id, source = car:take(me)
    if not id then return nil, source or 'no_car' end
    local right, ahead = M.offset(slot)
    local x, y = M.at(me, right, ahead, 0)
    if #hidden == 0 then x, y = behind.point(view, M.HIDDEN_METRES) end
    local z = car:ground(x, y, me.z) or me.z
    local ok, why = car:place(id, x, y, z, me.dx, me.dy)
    if not ok then
      car:release(id, source)
      return nil, why
    end
    self.count = self.count + 1
    local h = { n = self.count, id = id, source = source, state = 'CIRCLING', slot = slot, since = clock,
      hits = 0, dir = chance(0.5) and 1 or -1 }
    h.movesLeft = chance(M.BOLD_CHANCE) and whole({ 0, 1 }) or whole(M.CIRCLES)
    self.raiders[#self.raiders + 1] = h
    return LINES.arrived(slot)
  end

  -- One Raider's next move.
  local function think(h, me, st, clock)
    local line
    if h.state == 'CIRCLING' or h.state == 'PEEL' then
      if h.state == 'PEEL' and arrived(h, me, st) then h.state = 'CIRCLING' end
      if h.state == 'CIRCLING' then
        if not h.holdUntil and arrived(h, me, st) then h.holdUntil = clock + pick(M.HOLD_FAR) end
        if h.holdUntil and clock >= h.holdUntil then
          h.holdUntil = nil
          if h.shyUntil and clock < h.shyUntil then
            h.holdUntil = clock + 1
          elseif p.gunDrawn and M.SLOTS[h.slot].ahead < 0 and h.movesLeft > 0 then
            -- Your revolver is drawn: it stays at your back corner, out of your line of fire.
            h.movesLeft = h.movesLeft - 1
          elseif h.movesLeft > 0 then
            local nextSlot = M.forward(h.slot)
            if not taken(nextSlot, h) then h.slot, h.replanAt = nextSlot, nil end
            h.movesLeft = h.movesLeft - 1
          elseif not taken(near(h.slot), h) then
            h.state, h.slot, h.replanAt, h.since = 'CLOSING', near(h.slot), nil, clock
          else
            h.holdUntil = clock + 1
          end
        end
      end
    elseif h.state == 'CLOSING' then
      if not h.holdUntil and arrived(h, me, st) then h.holdUntil = clock + pick(M.HOLD_NEAR) end
      if h.holdUntil and clock >= h.holdUntil then
        h.holdUntil = nil
        if strikers() > 0 or (h.shyUntil and clock < h.shyUntil) then
          h.holdUntil = clock + 1
        elseif (function()
          -- Every other Raider still up and not attacking can help, nearest first.
          local free = {}
          for _, o in ipairs(p.raiders) do
            if o ~= h and (o.state == 'CIRCLING' or o.state == 'CLOSING' or o.state == 'PEEL') and o.metres then
              free[#free + 1] = o
            end
          end
          table.sort(free, function(x, y) return x.metres < y.metres end)
          if #free == 0 then return false end
          if not chance(#free >= 2 and M.TEAM_BOX_CHANCE or M.BOX_CHANCE) then return false end
          h.state, h.since, h.replanAt, h.boxedSince, h.holdTill = 'BOXING', clock, nil, nil, nil
          h.squeeze, h.squeezeSince, h.slot = false, nil, h.slot
          local firstSide
          for i, o in ipairs(free) do
            o.lead, o.replanAt, o.holdUntil = h, nil, nil
            if i == 1 then
              firstSide = o.slot and M.SLOTS[o.slot].side or 1
              o.state, o.side = 'BOX_SIDE', firstSide
            elseif i == 2 then
              o.state, o.side = 'BOX_SIDE', -firstSide
            else
              o.state, o.side = 'BOX_REAR', nil
            end
            o.slot = nil
          end
          line = #free >= 2 and LINES.teamBox(#free + 1) or LINES.box
          return true
        end)() then
          -- the box is on
        else
          h.state, h.since, h.replanAt = 'WINDUP', clock, nil
          h.pit = M.SLOTS[h.slot].ahead < 0 and chance(p.gunDrawn and M.PIT_GUN_CHANCE or M.PIT_CHANCE)
          line = h.pit and LINES.pit(h.slot) or LINES.windup(h.slot)
        end
      end
    elseif h.state == 'WINDUP' then
      if clock - h.since >= M.WINDUP_SECONDS then
        h.state, h.since, h.contactAt, h.replanAt = 'SWIPE', clock, nil, nil
      end
    elseif h.state == 'SWIPE' then
      if not h.contactAt and h.metres and h.metres <= M.CONTACT_METRES then h.contactAt, h.hasHit = clock, true end
      if h.contactAt and clock - h.contactAt >= M.AFTER_CONTACT_SECONDS then
        line = h.pit and LINES.pitted or LINES.swiped
        peel(h, clock)
      elseif clock - h.since >= M.SWIPE_SECONDS then
        peel(h, clock); line = LINES.missed
      end
    elseif h.state == 'BOXING' then
      local team = helpers(h)
      if not h.squeeze then
        -- Gathering: squeeze once everyone is alongside, or after GATHER_SECONDS.
        local ready = true
        for _, o in ipairs(team) do
          if not (o.spotMetres and o.spotMetres <= M.BOX_ARRIVE) then ready = false end
        end
        if ready or clock - h.since >= M.GATHER_SECONDS then
          h.squeeze, h.squeezeSince, h.replanAt = true, clock, nil
          for _, o in ipairs(team) do o.replanAt = nil end
          line = LINES.squeeze
        end
      end
      if (me.speed or 0) < M.STOPPED_MPS then h.boxedSince = h.boxedSince or clock else h.boxedSince = nil end
      if h.boxedSince and not h.holdTill and clock - h.boxedSince >= M.BOXED_SECONDS then
        h.holdTill = clock + M.BOX_HOLD_SECONDS
        line = LINES.boxed
      end
      local over = h.holdTill and clock >= h.holdTill
      if not h.holdTill and h.squeezeSince and clock - h.squeezeSince >= M.BOX_SECONDS then over = true end
      if over then
        for _, o in ipairs(team) do peel(o, clock) end
        peel(h, clock)
      end
    elseif h.state == 'BOX_SIDE' or h.state == 'BOX_REAR' then
      -- A helper whose box is over (its lead peeled off or left) peels off too.
      if not (h.lead and h.lead.state == 'BOXING') then peel(h, clock) end
    end
    if h.state ~= 'DOWN' then drive(h, me, st, clock) end
    return line
  end

  -- Lifts a Raider caught on something out of sight a few metres on, towards where it was heading.
  -- Returns true if it did.
  local function unstick(h, me, st, clock)
    if h.state == 'BOXING' or h.state == 'BOX_SIDE' or h.state == 'BOX_REAR' then return false end
    if (h.hops or 0) >= M.UNSTICK_TRIES or (h.hopAt and clock - h.hopAt < M.UNSTICK_SECONDS) then return false end
    if not h.aimX or (h.metres or 0) < M.UNSTICK_METRES then return false end
    local view = behind.view(car, me)
    if not behind.isBehind(view, st.x, st.y) then return false end
    local dx, dy = h.aimX - st.x, h.aimY - st.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return false end
    dx, dy = dx / len, dy / len
    local x, y = st.x + dx * M.UNSTICK_HOP, st.y + dy * M.UNSTICK_HOP
    if not behind.isBehind(view, x, y) then return false end
    local z = car:ground(x, y, st.z or me.z)
    if not z then return false end
    if not (car.hop and car:hop(h.id, x, y, z, dx, dy) or (not car.hop and car:place(h.id, x, y, z, dx, dy))) then return false end
    h.hops, h.hopAt, h.replanAt = (h.hops or 0) + 1, clock, nil
    p.unstuck = (p.unstuck or 0) + 1
    return true
  end

  function p:step(clock)
    if #self.raiders == 0 then return nil end
    local me = car:player()
    if not me then return nil end
    track(me, clock)
    local line
    for _, h in ipairs({ unpack(self.raiders) }) do
      local st = car:state(h.id)
      if not st then
        release(h); line = LINES.gone
      else
        relative(me, st)
        h.metres = distance2d(me.x, me.y, st.x, st.y)
        h.speed = st.speed
        if h.metres <= M.CONTACT_METRES then h.hasHit = true end
        if h.state == 'DOWN' then
          if h.metres > M.LEAVE_METRES then release(h) end
        else
          local driving = (me.speed or 0) >= M.DRIVING_MPS
          if driving and st.speed < M.STUCK_MPS then h.slow = h.slow or clock else h.slow = nil end
          if st.speed >= M.DRIVING_MPS then h.hops, h.hopAt = nil, nil end
          if h.metres > M.ESCAPE_METRES then h.far = h.far or clock else h.far = nil end
          if h.slow and clock - h.slow >= M.UNSTICK_SECONDS and unstick(h, me, st, clock) then
            -- lifted past what it was caught on; the down and stall clocks run on
          elseif h.slow and not h.hasHit and (h.stalls or 0) < 1 and clock - h.slow >= M.STALL_SECONDS then
            h.slow, h.replanAt, h.stalls = nil, nil, (h.stalls or 0) + 1
            p.stalled = { n = h.n, state = h.state, slot = h.slot, source = h.source, metres = h.metres, stalls = h.stalls }
            line = think(h, me, st, clock)
          elseif h.slow and clock - h.slow >= M.DOWN_SECONDS then
            line = down(h, LINES.down)
          elseif h.far and clock - h.far >= M.ESCAPE_SECONDS then
            release(h); line = LINES.escaped
          else
            line = think(h, me, st, clock) or line
          end
        end
      end
    end
    return line
  end

  -- Called every frame: keeps each moving Raider's point and speed fresh.
  function p:steer(clock)
    if #self.raiders == 0 then return end
    local me = car:player()
    if not me then return end
    track(me, clock)
    for _, h in ipairs(self.raiders) do
      if h.state ~= 'DOWN' then
        local st = car:state(h.id)
        if st then drive(h, me, st, clock) end
      end
    end
  end

  local function find(id)
    for _, h in ipairs(p.raiders) do if h.id == id and h.state ~= 'DOWN' then return h end end
  end

  -- A round from your revolver hit car id. Returns a line when it stops a Raider, and whether the car was one of
  -- the Raiders.
  function p:shot(id)
    local h = find(id)
    if not h then return nil, false end
    h.hits = h.hits + 1
    if h.hits >= M.SHOTS_TO_STOP then return down(h, LINES.shotDown), true end
    -- Hit but still going: it backs off for a while, unless it is boxing.
    local placing = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL'
    if not (placing or h.state == 'WINDUP' or h.state == 'SWIPE') then return nil, true end
    local clock = self.clock or 0
    local already = h.shyUntil and clock < h.shyUntil
    h.shyUntil = clock + M.SHY_SECONDS
    if h.state ~= 'CIRCLING' and h.state ~= 'PEEL' then peel(h, clock) end
    if already then return nil, true end
    return LINES.shy, true
  end

  function p:driverShot(id)
    local h = find(id)
    if not h then return nil, false end
    return down(h, LINES.driverShot), true
  end

  -- The downed Raider whose boot is nearest x, y within metres, that hasn't been opened: the Raider, or nil. Its
  -- boot is at the back of the car (raiderCar.lua's boot).
  function p:bootNear(x, y, metres)
    local best, bestD
    for _, h in ipairs(self.raiders) do
      if h.state == 'DOWN' and not h.opened then
        local b = car:boot(h.id)
        if b then
          local d = distance2d(x, y, b.x, b.y)
          if d <= metres and (not bestD or d < bestD) then best, bestD = h, d end
        end
      end
    end
    return best
  end

  -- Opens h's boot: the rounds in it, once.
  function p:openBoot(h)
    if not h or h.state ~= 'DOWN' or h.opened then return nil end
    h.opened = true
    return h.boot or 0
  end

  -- The distance to the nearest Raider still up, or nil.
  function p:nearest()
    local best
    for _, h in ipairs(self.raiders) do
      if h.state ~= 'DOWN' and h.metres and (not best or h.metres < best) then best = h.metres end
    end
    return best
  end

  -- For the HUD: each Raider, its slot and what it is doing.
  function p:view()
    local list = {}
    for _, h in ipairs(self.raiders) do
      local doing = M.DOING[h.state]
      if h.pit and h.state == 'WINDUP' then doing = M.DOING.PIT_WINDUP elseif h.pit and h.state == 'SWIPE' then doing = M.DOING.PIT end
      if h.shyUntil and self.clock and self.clock < h.shyUntil and h.state ~= 'DOWN' then doing = M.DOING.SHY end
      list[#list + 1] = { n = h.n, slot = h.slot, doing = doing, state = h.state, metres = h.metres,
        opened = h.opened or nil }
    end
    return list
  end

  -- Sends every Raider away: the run is over.
  function p:clear()
    for _, h in ipairs({ unpack(self.raiders) }) do release(h) end
  end

  function p:remove()
    self:clear()
    car:removeAll()
  end

  return p
end

return M
