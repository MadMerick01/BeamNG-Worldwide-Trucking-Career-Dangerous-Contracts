-- Counts the distance driven between position readings and spots teleports, lifted from Enduro's
-- mileage check. Pure maths; no game globals.
local location = require('earthFreight/location')
local M = {}

-- Faster movement between two readings is treated as a teleport, not driving (150 m/s = 540 km/h).
M.MAX_DRIVING_SPEED = 150
-- A teleport this short (past a cliff or a river) keeps the load; a longer one cancels it.
M.SHORT_HOP_METRES = 2000
-- The vehicle counts as stopped once it has moved slower than this for STOPPED_SECONDS.
M.STOPPED_SPEED = 1 -- m/s
M.STOPPED_SECONDS = 1

function M.new()
  local o = { stillSeconds = 0 }

  -- Forgets the last reading, so the next one starts counting afresh (a reload, or Earth pausing).
  function o:reset()
    self.last, self.stillSeconds = nil, 0
  end

  -- Takes a reading. Returns how far was driven since the last one in metres (0 for the first
  -- reading or a paused frame), and, for a teleport-sized jump, the jump's length as a second value.
  function o:step(sample, dt)
    local previous = self.last
    self.last = location.copy(sample)
    if not previous or not location.finite(dt) or dt <= 0 then return 0 end
    local metres = location.distance(previous, sample)
    if not metres then return 0 end
    if metres > M.MAX_DRIVING_SPEED * dt then
      self.stillSeconds = 0
      return 0, metres
    end
    if metres / dt < M.STOPPED_SPEED then self.stillSeconds = self.stillSeconds + dt else self.stillSeconds = 0 end
    return metres
  end

  function o:stopped()
    return self.last ~= nil and self.stillSeconds >= M.STOPPED_SECONDS
  end

  return o
end

return M
