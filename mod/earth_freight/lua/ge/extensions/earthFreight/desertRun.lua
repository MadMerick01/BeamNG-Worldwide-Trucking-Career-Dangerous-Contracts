-- The Raiders on the special delivery (special.lua), and the rounds in their boots. MadMerick's first test (26 Nov):
-- once the run has started at the start in the Rub' al Khali, the rival clans' Raiders just keep coming. FIRST_SECONDS
-- after the start the first turns up, then another every GAP_SECONDS until MAX are up (raiderPack.lua). One that is
-- down (stopped or stuck) or falls 500 m behind is replaced the same way. The load always stays whole: the Raiders
-- can only stop you, and then it is press on or Give up.
--
-- Rounds: the run starts with special.START_ROUNDS. A downed Raider's car stays where it stopped; walk to its boot
-- (within BOOT_REACH metres, in the game's walking mode) and press Open boot for the 0 to 20 rounds inside, once per
-- Raider. They are kept with the load in the save (load.ammo: every round left, in the cylinder and spare).
--
-- The revolver (MadMerick, 26 Nov): on a flat screen, Tanker's mouse-aim six-shooter (revolver.lua and aim.lua): the
-- Draw revolver button or key, aim with the mouse, click to fire, Reload to fill the cylinder from the spare rounds.
-- In VR, MadMerick's own VR revolver mod (BeamngVRcontrollerPoses, a separate download) shoots: the run's rounds are
-- put in it (vrPistol.setAmmo) and read back as it fires and reloads. When the run ends it goes back to its own
-- unlimited rounds. Either revolver's hit comes back as onVrPistolHit or onVrPistolDriverHit: four hits stop a
-- Raider, one through the driver stops it at once (raiderPack.lua).
--
-- Delivered, given up or dropped, the Raiders go and their cars are deleted. Pure Lua: the cars are handled by
-- c.raiderCar (raiderCar.lua), which may be missing, and then there are no Raiders.
local special = require('earthFreight/special')
local raiderPack = require('earthFreight/raiderPack')
local revolver = require('earthFreight/revolver')
local M = {}

-- One-line settings. Tune these after testing in game.
-- The first Raider turns up this long after the run starts, then one every GAP_SECONDS while fewer than MAX are up.
M.FIRST_SECONDS, M.GAP_SECONDS = 30, 8
-- A Raider that can't be sent is tried again after this long.
M.RETRY_SECONDS = 10
-- How often the Raiders think, in seconds (they steer every frame).
M.STEP_SECONDS = 0.5
-- Walking within this many metres of a downed Raider's boot shows Open boot.
M.BOOT_REACH = 4
-- How long a Raider's line stays on the HUD.
M.LINE_SECONDS = 6

function M.attach(c)
  -- The load of a special delivery that has started, or nil.
  function c:desertLoad()
    local load = self.load
    if load and load.cost and load.started and load.contract == special.SECTION.id then return load end
  end

  -- Called every tick.
  function c:watchRaiders(dt)
    local load = self:desertLoad()
    if not load then
      if self.raiders or self.gun then self:endRaiders() end
      return
    end
    if load.ammo == nil then load.ammo = special.START_ROUNDS end
    self:watchGun(load)
    local car = self.raiderCar
    if not car then return end
    -- The truck: what the Raiders go for, even while the player walks.
    if not self.onFoot then
      local me = car:walker()
      self.raiderTruck = me and me.id or self.raiderTruck
      car.targetId = nil
    else
      car.targetId = self.raiderTruck
    end
    if not self.raiders then
      self.raiders = raiderPack.new(car, self.random and function(lo, hi) return lo + self.random() * (hi - lo) end)
      self.raiderNextAt = self.clock + M.FIRST_SECONDS
      self.raiderStepAt = self.clock
      local ready, why = car:preload(raiderPack.MAX)
      self.diag:event('raiders_loaded', ready .. ' cars' .. (why and (', ' .. why) or ''), why and 'W' or 'I')
    end
    local pack = self.raiders
    if self.clock >= self.raiderNextAt and pack:up() < raiderPack.MAX then
      local line, why = pack:add(self.clock)
      if line then
        self:raiderSays(line)
        self.raiderNextAt = self.clock + M.GAP_SECONDS
      else
        self.raiderNextAt = self.clock + M.RETRY_SECONDS
        if why ~= self.raiderWhy then
          self.raiderWhy = why
          self.diag:event('raider_not_sent', tostring(why), 'W')
        end
      end
    end
    if self.clock >= self.raiderStepAt then
      self.raiderStepAt = self.clock + M.STEP_SECONDS
      local line = pack:step(self.clock)
      if line then self:raiderSays(line) end
      -- One that went down or fell behind: the next comes GAP_SECONDS later at the soonest.
      if pack:up() < raiderPack.MAX and self.raiderNextAt < self.clock then
        self.raiderNextAt = self.clock + M.GAP_SECONDS
      end
      if pack.stalled then
        local st = pack.stalled
        pack.stalled = nil
        self.diag:event('raider_stalled', string.format('Raider %d %s %s, %.0f m away', st.n, tostring(st.state),
          tostring(st.slot), st.metres or -1), 'W')
      end
    else
      pack:steer(self.clock)
    end
  end

  function c:raiderSays(line)
    self.raiderLine, self.raiderLineAt = line, self.clock
  end

  -- The downed Raider whose boot the player is standing at, walking, or nil.
  function c:bootHere()
    if not (self.raiders and self.onFoot and self.raiderCar) then return nil end
    local me = self.raiderCar:walker()
    return me and self.raiders:bootNear(me.x, me.y, M.BOOT_REACH)
  end

  -- Open boot: the rounds in the Raider's boot go with the load. Returns how many.
  function c:openBoot()
    local load = self:desertLoad()
    local h = load and self:bootHere()
    if not h then return nil end
    local rounds = self.raiders:openBoot(h) or 0
    load.ammo = (load.ammo or 0) + rounds
    self:gunFound(rounds)
    self:raiderSays(rounds > 0 and ('You found ' .. rounds .. (rounds == 1 and ' round' or ' rounds') .. ' in the boot.')
      or 'The boot is empty.')
    self.diag:event('boot_opened', rounds .. ' rounds, ' .. load.ammo .. ' now')
    self:autoSaveSoon('opening a boot')
    return rounds
  end

  -- The run is over: the Raiders go and their cars are deleted.
  function c:endRaiders()
    if self.raiders then self.raiders:remove() end
    self:endGun()
    self.raiders, self.raiderNextAt, self.raiderStepAt, self.raiderLine, self.raiderWhy = nil, nil, nil, nil, nil
    if self.raiderCar then self.raiderCar.targetId = nil end
  end

  -- A Raider's driver had a problem (lua/vehicle/extensions/earthFreightRaider.lua): logged once each.
  function c:raiderProblem(id, why)
    self.raiderProblems = self.raiderProblems or {}
    why = tostring(why)
    if self.raiderProblems[why] then return end
    self.raiderProblems[why] = true
    self.diag:event('raider_problem', tostring(id) .. ': ' .. why, 'W')
  end

  -- The VR revolver, when the game is in VR and MadMerick's VR revolver mod is installed, or nil.
  function c:vrGun()
    if not (self.aim and self.aim:vr()) then return nil end
    local pistol = self.aim:pistol()
    return pistol and type(pistol.setAmmo) == 'function' and type(pistol.getAmmo) == 'function' and pistol or nil
  end

  -- Called every tick on the run: the revolver's rounds, in step with the load's, and its reload.
  function c:watchGun(load)
    if not self.gun then self.gun = revolver.new(load.ammo) end
    local gun, pistol = self.gun, self:vrGun()
    if pistol then
      gun:setDrawn(false)
      if self.vrGunFor ~= pistol then
        -- The run's rounds go in the VR revolver.
        self.vrGunFor = pistol
        pcall(pistol.setAmmo, gun.loaded, gun.spare)
        self.diag:event('vr_revolver', gun.loaded .. ' loaded, ' .. gun.spare .. ' spare')
      else
        local ok, loaded, _, spare = pcall(pistol.getAmmo)
        if ok and type(loaded) == 'number' and type(spare) == 'number' then
          gun.loaded, gun.spare = math.max(0, math.floor(loaded)), math.max(0, math.floor(spare))
        end
      end
    else
      if self.vrGunFor then self:freeVrGun() end
      gun:step(self.clock)
    end
    load.ammo = gun:rounds()
    if self.raiders then self.raiders.gunDrawn = gun.drawn or (pistol ~= nil and self:vrDrawn(pistol)) end
  end

  function c:vrDrawn(pistol)
    if type(pistol.isEquipped) ~= 'function' then return false end
    local ok, on = pcall(pistol.isEquipped)
    return ok and on == true
  end

  -- The VR revolver back to its own unlimited rounds.
  function c:freeVrGun()
    local pistol = self.vrGunFor
    self.vrGunFor = nil
    if pistol and type(pistol.setAmmo) == 'function' then
      local okCfg, cfg = pcall(function() return pistol.getConfig and pistol.getConfig() end)
      local size = okCfg and type(cfg) == 'table' and cfg.cylinderSize or revolver.CYLINDER
      pcall(pistol.setAmmo, size, nil)
    end
  end

  -- Rounds from a boot: spare rounds, in the VR revolver too.
  function c:gunFound(rounds)
    local gun = self.gun
    if not gun or rounds <= 0 then return end
    gun.spare = gun.spare + rounds
    local pistol = self:vrGun()
    if pistol and self.vrGunFor == pistol then pcall(pistol.setAmmo, gun.loaded, gun.spare) end
  end

  function c:endGun()
    if self.vrGunFor then self:freeVrGun() end
    self.gun, self.vrGunFor = nil, nil
  end

  -- The Draw revolver button or key: the flat-screen revolver, on the run, in the car, without VR.
  function c:toggleRevolver()
    local gun = self.gun
    if not (gun and self:desertLoad()) or self:vrGun() or self.onFoot then return false end
    gun:setDrawn(not gun.drawn)
    self:raiderSays(gun.drawn and 'Revolver drawn. Aim with the mouse and click to shoot.' or 'Revolver holstered.')
    return true
  end

  function c:reloadRevolver()
    local gun = self.gun
    if not (gun and self:desertLoad()) or self:vrGun() then return false end
    local ok, why = gun:reload(self.clock)
    self:raiderSays(ok and 'Reloading.' or why == 'full' and 'The cylinder is full.' or 'No spare rounds left.')
    return ok
  end

  -- Each frame: the crosshair while the revolver is drawn, and a shot on each click (not on the HUD).
  function c:followAim()
    local gun = self.gun
    if not (gun and gun.drawn and self.aim) then return end
    if self.onFoot or self:vrGun() or not self:desertLoad() then gun:setDrawn(false) return end
    local shot = self.aim:aim()
    self.aim:draw(shot)
    if self.hudHover or not self.aim:clicked() then return end
    local fired, why = gun:fire(self.clock)
    local load = self:desertLoad()
    load.ammo = gun:rounds()
    if not fired then
      if why == 'empty' then
        self:raiderSays(gun:reloading() and 'Click. Empty, reloading.' or 'Click. You are out of rounds.')
      end
      return
    end
    -- The hit, if any, comes back from the car a moment later (raiderHit).
    self.shotAt = self.clock
    self.aim:shoot(shot)
  end

  -- A hit from either revolver, the VR one or the flat-screen one: they send the same events.
  function c:raiderHit(vehicleId, driver)
    if not self.raiders then return end
    local line, wasRaider
    if driver then line, wasRaider = self.raiders:driverShot(vehicleId) else line, wasRaider = self.raiders:shot(vehicleId) end
    if line then
      self:raiderSays(line)
      self.diag:event('raider_shot', driver and 'driver' or 'four hits')
    elseif wasRaider and self.shotAt and self.clock - self.shotAt < 2 then
      self:raiderSays('Hit the Raider.')
    end
  end

  -- For the HUD: the rounds, the Raiders up, the latest line and whether Open boot is shown.
  function c:desertView()
    local load = self:desertLoad()
    if not load then return nil end
    local line = self.raiderLine and self.clock - (self.raiderLineAt or 0) <= M.LINE_SECONDS and self.raiderLine or nil
    local gun, vr = self.gun, self:vrGun()
    return { rounds = load.ammo or special.START_ROUNDS, up = self.raiders and self.raiders:up() or 0,
      max = raiderPack.MAX, line = line, boot = self:bootHere() ~= nil or nil,
      loaded = gun and gun.loaded, spare = gun and gun.spare, vr = vr ~= nil or nil,
      drawn = gun and not vr and gun.drawn or nil, reloading = gun and gun:reloading() or nil,
      reloadAllowed = gun and not vr and not gun:reloading() and gun.loaded < revolver.CYLINDER and gun.spare > 0 or nil,
      revolverAllowed = gun ~= nil and not vr and not self.onFoot or nil }
  end
end

return M
