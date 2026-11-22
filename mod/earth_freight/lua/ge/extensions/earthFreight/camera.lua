-- The camera. The game's parts menu, a respawn and BeamNG.Earth's teleports can leave the player on
-- the free camera, or on the car's default camera, instead of the one they were driving with. While
-- they drive, the camera they use is remembered for each car (driver, chase, orbit...); after one of
-- those it is put back. A player who chose the free camera themselves (Shift+C) is left on it.
local M = {}

-- One-line settings. Tune these after testing in game.
-- After the parts menu closes, a respawn or an Insert, the camera is checked at these times
-- (seconds), as the game can turn the free camera back on a moment later.
M.CHECKS = { 0, 0.5, 1.5, 3 }
-- After a teleport lands, or the player is put in another car, for longer: Earth can keep the free
-- camera on while the terrain loads.
M.LONG_CHECKS = { 0, 0.5, 1.5, 3, 6, 10 }
-- The free camera on this long, with nothing of the game's or the mod's going on, is the player's
-- own choice.
M.FREE_CHOICE_SECONDS = 2
-- A teleport that lands this soon after the free camera came on turned it on itself (Earth's map
-- does), so it is not the player's choice.
M.TELEPORT_FREE_SECONDS = 30
-- A car put on another camera than the player's (as a respawn does) is only put back this long
-- after it started; later on, only the free camera is, so a player changing camera keeps their choice.
M.NAME_SECONDS = 2
-- Buy parts noted, but the car's own camera still on this long after: the menu never opened.
M.MENU_GONE_SECONDS = 5
-- A HUD rebuilt this soon after Buy parts was pressed is the menu opening, not closing.
M.PARTS_MENU_MIN_SECONDS = 1

-- Which car the player is in: the same car keeps its id through a respawn, while the helicopter
-- or sightseeing car can take the car's id, so the model is part of it.
function M.carKey(vehicle)
  if type(vehicle) ~= 'table' or vehicle.id == nil then return nil end
  return tostring(vehicle.id) .. '|' .. tostring(vehicle.model or '')
end

function M.attach(c)
  c.cameras = {}

  local function call(name, ...)
    local cam = c.camera
    if not cam or type(cam[name]) ~= 'function' then return nil end
    local ok, value = pcall(cam[name], ...)
    if ok then return value end
    return nil
  end

  function c:cameraFree() return call('isFree') == true end

  -- Whether this vehicle is the car the player drives (not a trailer, a thief or traffic).
  function c:playerCar(vehicleId)
    if vehicleId == nil then return false end
    local id = tostring(vehicleId)
    if self.ownedParts and tostring(self.ownedParts.id) == id then return true end
    return self.cameraCar ~= nil and self.cameraCar:match('^(.-)|') == id
  end

  -- Starts the camera checks: put back what the player had, at each of these times from now.
  -- teleport: Earth's teleport may have turned the free camera on, even long enough to look chosen.
  function c:cameraSettle(times, teleport)
    if not self.camera then return false end
    if teleport and self.cameraFreeSince and self.clock - self.cameraFreeSince < M.TELEPORT_FREE_SECONDS then
      self.cameraChosenFree = false
    end
    local due = {}
    for i, after in ipairs(times or M.CHECKS) do due[i] = self.clock + after end
    -- Checks already waiting carry on as well.
    for _, at in ipairs(self.cameraChecks or {}) do
      if at > self.clock then due[#due + 1] = at end
    end
    table.sort(due)
    -- The first check runs on the next tick, once the car the player is in has been read again.
    self.cameraChecks, self.cameraSettleAt = due, self.clock
    return true
  end

  -- Puts the player back on the camera they last used in this car, if they are not on it.
  function c:restoreCamera()
    if self.cameraChosenFree or self.onFoot or self.partsCamera then return false end
    local want = self.cameraCar and self.cameras[self.cameraCar] or nil
    local early = self.cameraSettleAt ~= nil and self.clock - self.cameraSettleAt <= M.NAME_SECONDS
    if self:cameraFree() or (early and want and call('name') ~= want) then
      local back = call('backToCar', want) == true
      if back then self.cameraFreeSince = nil end
      return back
    end
    return false
  end

  -- Called every tick: remembers the camera the player drives with, and runs the checks.
  function c:watchCamera()
    if not self.camera then return end
    local sample = self.lastSample
    local key = sample and sample.valid and M.carKey(sample.vehicle) or nil
    -- In another car than a moment ago, such as back from the helicopter: its own camera back.
    if key and self.cameraCar and key ~= self.cameraCar and not self.onFoot then
      self.cameraCar = key
      if self.cameras[key] then self:cameraSettle(M.LONG_CHECKS, true) end
    end
    if key and not self.onFoot then self.cameraCar = key end
    local checks = self.cameraChecks
    if checks then
      local ran = false
      while checks[1] and self.clock >= checks[1] do
        table.remove(checks, 1)
        if not ran then self:restoreCamera(); ran = true end
      end
      if not checks[1] then self.cameraChecks = nil end
      return
    end
    -- Buy parts pressed but no menu came up (it turns the free camera on): nothing is open.
    local p = self.partsCamera
    if p and self.clock - p.at >= M.MENU_GONE_SECONDS and not self:cameraFree() then self.partsCamera = nil end
    -- Nothing going on: note the player's camera. Not on foot, nor while the parts menu is open.
    if self.onFoot or self.partsCamera or not key then return end
    if self:cameraFree() then
      self.cameraFreeSince = self.cameraFreeSince or self.clock
      if self.clock - self.cameraFreeSince >= M.FREE_CHOICE_SECONDS then self.cameraChosenFree = true end
      return
    end
    self.cameraFreeSince, self.cameraChosenFree = nil, false
    local name = call('name')
    if type(name) == 'string' and name ~= '' and name ~= 'free' then self.cameras[key] = name end
  end

  -- The parts menu is opening, from Buy parts on the HUD or from the game (fromGame), as Ctrl+W does. Buy parts
  -- asks before the menu turns the free camera on, so a player on it already is seen to be.
  function c:partsMenuOpening(fromGame)
    if self.partsCamera then return true end
    if not fromGame and self:cameraFree() then self.cameraChosenFree = true end
    -- The menu's own free camera is not the player's.
    if not self.cameraChosenFree then self.cameraFreeSince = nil end
    self.partsCamera = { at = self.clock }
    self.cameraChecks = nil
    return true
  end

  -- The parts menu closed: the game said so (fromGame), or the HUD was built again. The car's own
  -- camera back, unless the player was on the free camera before.
  function c:partsMenuClosed(fromGame)
    local p = self.partsCamera
    if not p then return false end
    if not fromGame and self.clock - p.at < M.PARTS_MENU_MIN_SECONDS then return false end
    self.partsCamera = nil
    if self.cameraChosenFree then return false end
    return self:cameraSettle(M.CHECKS)
  end
end

return M
