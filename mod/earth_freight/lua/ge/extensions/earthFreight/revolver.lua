-- The flat-screen revolver on the special delivery (desertRun.lua): MadMerick's six-shooter from his Tanker mod, for
-- playing without VR (in VR, MadMerick's separate VR revolver mod does the shooting). This is the logic only: drawn
-- or holstered, the six-round cylinder, spare rounds, the time between shots and reloading. aim.lua does the game's
-- side. The rounds are the run's (special.START_ROUNDS, and what the Raiders' boots hold), and they run out.
local M = {}

-- One-line settings. Tune these after testing in game.
M.CYLINDER = 6
-- Seconds between shots, and how long a reload takes: the VR revolver's.
M.SHOT_SECONDS, M.RELOAD_SECONDS = 0.12, 1.5
M.MAX_SPARE = 9999
-- Reloads never use up spare rounds when true (Tanker's testing switch). Off: the rounds run out.
M.INFINITE = false

local function count(n, most)
  return type(n) == 'number' and n == n and n >= 0 and n <= most and n == math.floor(n)
end

-- rounds: how many the run has, all told. The cylinder is filled from them.
function M.new(rounds)
  local g = { drawn = false, lastShot = -math.huge }
  rounds = count(rounds, M.MAX_SPARE + M.CYLINDER) and rounds or 0
  g.loaded = math.min(M.CYLINDER, rounds)
  g.spare = rounds - g.loaded

  -- All the rounds left: in the cylinder and spare.
  function g:rounds() return self.loaded + self.spare end

  function g:ammo() return { loaded = self.loaded, spare = self.spare } end

  function g:setDrawn(on)
    self.drawn = on == true
  end

  -- Starts a reload. Returns true, or false and why: 'full' or 'no_spare'.
  function g:reload(clock)
    if self.reloadAt then return true end
    if self.loaded >= M.CYLINDER then return false, 'full' end
    if self.spare <= 0 and not M.INFINITE then return false, 'no_spare' end
    self.reloadAt = clock + M.RELOAD_SECONDS
    return true
  end

  function g:reloading() return self.reloadAt ~= nil end

  -- Whether there are rounds to reload from.
  function g:hasSpare() return M.INFINITE or self.spare > 0 end

  -- Finishes a reload once its time is up. Returns true when it did.
  function g:step(clock)
    if not self.reloadAt or clock < self.reloadAt then return false end
    self.reloadAt = nil
    if M.INFINITE then
      self.loaded = M.CYLINDER
      return true
    end
    local moved = math.min(M.CYLINDER - self.loaded, self.spare)
    self.loaded, self.spare = self.loaded + moved, self.spare - moved
    return true
  end

  -- A pull of the trigger. Returns true when a round is fired, or false and why: 'holstered',
  -- 'reloading', 'cooldown' or 'empty' (which starts a reload if there are spare rounds).
  function g:fire(clock)
    if not self.drawn then return false, 'holstered' end
    if self.reloadAt then return false, 'reloading' end
    if clock - self.lastShot < M.SHOT_SECONDS then return false, 'cooldown' end
    if self.loaded <= 0 then
      self:reload(clock)
      return false, 'empty'
    end
    self.loaded, self.lastShot = self.loaded - 1, clock
    return true
  end

  -- Rounds found, from loot. Returns how many were taken.
  function g:addRounds(n)
    if type(n) ~= 'number' or n <= 0 then return 0 end
    local taken = math.min(math.floor(n), M.MAX_SPARE - self.spare)
    self.spare = self.spare + taken
    return taken
  end

  return g
end

return M
