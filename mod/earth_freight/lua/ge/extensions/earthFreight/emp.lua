-- The player's EMP, shared by every robber: the base thief (thief.lua) and the road robber (roadRobber.lua), and
-- later the weekend PvP raids. It reaches RANGE metres. Every press fires and starts the CHARGE_SECONDS charge, hit or
-- miss, and while it charges it can't fire again. It only fires when there is something to fire at: a thief or robber
-- being chased. A road robber that hasn't struck yet can't be stopped, but the press still uses the charge.
-- The HUD's EMP button shows the charge filling, then IN RANGE (green) or OUT OF RANGE with the distance (yellow).
-- Pure Lua.
local M = {}

M.RANGE = 15
M.CHARGE_SECONDS = 20

function M.attach(c)
  -- The controller keeps self.empFiredAt: the clock when the EMP last fired, or nil.

  -- The EMP sound (the HUD's emp.wav): played once for each, when the player fires and when a robber's EMP hits them.
  function c:empSound() self.empSounds = (self.empSounds or 0) + 1 end

  -- Seconds until the EMP is charged again, 0 when ready.
  function c:empChargeLeft()
    if not self.empFiredAt then return 0 end
    return math.max(0, M.CHARGE_SECONDS - (self.clock - self.empFiredAt))
  end

  -- What the EMP would fire at now: { kind = 'thief' | 'robber', metres, stoppable }, or nil when nothing is about.
  -- stoppable is false for a road robber that hasn't struck yet.
  function c:empTarget()
    local t = self.thief
    if t and t.phase == 'chasing' then return { kind = 'thief', metres = t.metres, stoppable = true } end
    local r = self.robber
    if r and (r.phase == 'lurking' or r.phase == 'hunting') then return { kind = 'robber', metres = r.metres, stoppable = false } end
    if r and r.phase == 'chasing' then return { kind = 'robber', metres = r.metres, stoppable = true } end
    return nil
  end

  -- Fires the EMP. Returns true when it stopped a thief or robber; the reason it didn't is in self.empFeedback.
  function c:fireEmp()
    local target = self:empTarget()
    if not target then
      self.empFeedback = nil
      return false
    end
    local left = self:empChargeLeft()
    if left > 0 then
      self.empFeedback = 'EMP charging: ' .. math.ceil(left) .. ' s.'
      return false
    end
    self.empFiredAt = self.clock
    self:empSound()
    local d = target.metres
    if not target.stoppable then
      self.empFeedback = 'Nothing to hit yet. The EMP is charging.'
      self.diag:event('emp', 'nothing')
      return false
    end
    if not d or d > M.RANGE then
      self.empFeedback = 'Missed: get within ' .. M.RANGE .. ' m.' .. (d and (' They are ' .. math.floor(d + 0.5) .. ' m away.') or '')
        .. ' The EMP is charging.'
      self.diag:event('emp', 'missed')
      return false
    end
    self.empFeedback = nil
    self.diag:event('emp', 'hit ' .. target.kind)
    if target.kind == 'thief' then return self:catchThief() end
    return self:catchRobber()
  end

  -- The EMP button on the chase card.
  function c:empView()
    local target = self:empTarget()
    if not target then return nil end
    local left = self:empChargeLeft()
    local d = target.metres
    return {
      ready = left <= 0, chargeLeft = left > 0 and math.ceil(left) or nil,
      charged = math.floor((1 - left / M.CHARGE_SECONDS) * 100 + 0.5),
      inRange = d ~= nil and d <= M.RANGE, metres = d and math.floor(d + 0.5) or nil, range = M.RANGE,
      feedback = self.empFeedback,
    }
  end

  -- The Fire EMP hotkey (Options > Controls > Bindings, no key by default). Does nothing unless there is something to
  -- fire at; when it doesn't hit it says why in a pop-up too, since the HUD may be minimised.
  function c:empHotkey()
    -- Driving the admin robber (adminRobber.lua): the key fires his EMP at the player.
    local a = self.adminDrive
    if a and a.stage == 'ready' and not a.struck then
      if self:adminEmp() then return true end
      self:toast('warning', 'EMP CHARGING', self.adminFeedback or '', 4)
      return false
    end
    if not self:empTarget() then return false end
    if self:fireEmp() then return true end
    local charging = self.empFeedback and self.empFeedback:find('^EMP charging') ~= nil
    self:toast('warning', charging and 'EMP CHARGING' or 'EMP MISSED', self.empFeedback or '', 4)
    return false
  end
end

return M
