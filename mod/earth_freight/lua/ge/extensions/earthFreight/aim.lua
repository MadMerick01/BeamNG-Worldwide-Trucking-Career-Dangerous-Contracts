-- The game's side of the flat-screen revolver on the special delivery (revolver.lua): aiming with the mouse, the
-- crosshair and the shot. Copied from MadMerick's Tanker mod (its aim.lua).
-- The mouse and crosshair come from MadMerick's Bolides The Cut (FirstPersonShoot.lua). The shot is
-- the VR revolver's own (BeamngVRcontrollerPoses), so a hit is exactly the same as in VR: the
-- bullet must pass within 0.3 m of the car's body, walls stop it, it shoves and dents the car,
-- flattens a tyre it hits near the hub, and a shot through the driver switches the car's AI off.
-- With the VR revolver mod installed its vrPistol.shoot is called; without it this mod's copy of the
-- same code runs (lua/vehicle/extensions/earthFreightHit.lua in the car). Every game call is guarded: a missing or changed one
-- means no shot, never an error.
local M = {}

-- One-line settings, the VR revolver's own defaults. Tune these after testing in game.
M.RANGE_METRES = 300
M.HIT_RADIUS = 0.3
M.IMPACT_FORCE, M.BLAST_RADIUS, M.BLAST_FORCE, M.BLAST_INVERSION = 6000, 1.3, 70, 0.3
M.DEFLATE_TYRES = true
M.DRIVER_BOX, M.DRIVER_DROP, M.DRIVER_BRAKE = 0.5, 0.15, 0.5
-- The crosshair: half its size and its thickness, in pixels, and its colour (amber, ImGui ABGR).
M.CROSSHAIR_SIZE, M.CROSSHAIR_THICKNESS, M.CROSSHAIR_COLOUR = 14, 3, 0xFF00BFFF

local function defaults()
  return {
    imgui = function() return rawget(_G, 'ui_imgui') end,
    vrPistol = function() return rawget(_G, 'vrPistol') or (extensions and extensions.vrPistol) end,
    player = function() return getPlayerVehicle(0) end,
    -- Whether a VR session is running: then the VR revolver does the shooting.
    vr = function()
      local xr = rawget(_G, 'render_openxr')
      if xr and xr.isSessionRunning then
        local ok, running = pcall(xr.isSessionRunning)
        if ok and running ~= nil then return running == true end
      end
      local o = rawget(_G, 'OpenXR')
      if o and o.getEnable then
        local ok, on = pcall(o.getEnable)
        if ok then return on == true end
      end
      return false
    end,
    -- The ray from the camera through the mouse: origin and direction as vec3s.
    mouseRay = function()
      local pos = getCameraPosition and getCameraPosition()
      local ray = getCameraMouseRay and getCameraMouseRay()
      if not (pos and ray and ray.dir) then return nil end
      local dir = vec3(ray.dir)
      if dir:length() < 0.001 then return nil end
      return vec3(pos), dir:normalized()
    end,
    -- How far the ray goes before it meets the ground or a building.
    wall = function(origin, dir, range)
      local d = castRayStatic and castRayStatic(origin, dir, range)
      return type(d) == 'number' and d < range and d or range
    end,
    vehicles = function()
      local out = {}
      if not (be and be.getObjectCount) then return out end
      for i = 0, be:getObjectCount() - 1 do out[#out + 1] = be:getObject(i) end
      return out
    end,
    drawSphere = function(pos, radius)
      if debugDrawer and ColorF then debugDrawer:drawSphere(pos, radius, ColorF(1, 0.75, 0.1, 0.95)) end
    end,
  }
end

-- Ray against an oriented box; the entry distance or nil. From vrPistol.lua.
local function rayBox(origin, dir, center, axes, half, maxDist)
  local tMin, tMax = 0, maxDist
  local d = center - origin
  for i = 1, 3 do
    local e, f = axes[i]:dot(d), axes[i]:dot(dir)
    if math.abs(f) > 1e-9 then
      local t1, t2 = (e + half[i]) / f, (e - half[i]) / f
      if t1 > t2 then t1, t2 = t2, t1 end
      tMin, tMax = math.max(tMin, t1), math.min(tMax, t2)
      if tMin > tMax then return nil end
    elseif -e - half[i] > 0 or -e + half[i] < 0 then
      return nil
    end
  end
  return tMin
end
M.rayBox = rayBox

-- A car's box: centre, axes and half sizes. From vrPistol.lua.
local function vehicleBox(veh)
  local ok, box = pcall(function() return veh:getSpawnWorldOOBB() end)
  if ok and box then
    local h = box:getHalfExtents()
    return vec3(box:getCenter()), { vec3(box:getAxis(0)), vec3(box:getAxis(1)), vec3(box:getAxis(2)) }, { h.x, h.y, h.z }
  end
  local okW, wb = pcall(function() return veh:getWorldBox() end)
  if okW and wb then
    local mn, mx = vec3(wb.minExtents), vec3(wb.maxExtents)
    return (mn + mx) * 0.5, { vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1) },
      { (mx.x - mn.x) / 2, (mx.y - mn.y) / 2, (mx.z - mn.z) / 2 }
  end
end

-- The car-side hit, as vrPistol sends it.
local HIT = "extensions.load('earthFreightHit'); extensions.earthFreightHit.hit(%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.2f,%.3f,%.1f,%.3f,%.1f,%.3f,%s,%.3f,%.3f,%.3f)"

function M.new(environment)
  local env = environment or defaults()
  local a = {}

  local function call(name, ...)
    local f = env[name]
    if type(f) ~= 'function' then return nil end
    local ok, x, y = pcall(f, ...)
    if ok then return x, y end
  end

  function a:vr() return call('vr') == true end

  local function vrPistol()
    local p = call('vrPistol')
    return type(p) == 'table' and type(p.shoot) == 'function' and p or nil
  end

  -- Where the mouse aims: { origin, dir, point }, point being where it meets the ground or a wall.
  function a:aim()
    local origin, dir = call('mouseRay')
    if not (origin and dir) then return nil end
    local wall = call('wall', origin, dir, M.RANGE_METRES) or M.RANGE_METRES
    return { origin = origin, dir = dir, point = wall < M.RANGE_METRES and origin + dir * wall or nil }
  end

  -- MadMerick's VR revolver (vrPistol), when that mod is installed, or nil.
  function a:pistol()
    local p = call('vrPistol')
    return type(p) == 'table' and p or nil
  end

  -- Fires along the aim: the VR revolver's shot and sound when that mod is there, or this mod's copy
  -- of the same shot. The hit comes back later, through onVrPistolHit and onVrPistolDriverHit.
  function a:shoot(shot)
    if not (shot and shot.origin and shot.dir) then return false end
    local pistol = vrPistol()
    if pistol then
      local ok = pcall(pistol.shoot, shot.origin, shot.dir)
      if type(pistol.testSound) == 'function' then pcall(pistol.testSound, 'shot') end
      return ok
    end
    local origin, dir = shot.origin, shot.dir
    local wall = call('wall', origin, dir, M.RANGE_METRES) or M.RANGE_METRES
    local player = call('player')
    local nearest, nearestT
    for _, veh in ipairs(call('vehicles') or {}) do
      if veh and veh ~= player then
        local center, axes, half = vehicleBox(veh)
        local t = center and rayBox(origin, dir, center, axes, half, wall)
        if t and (not nearestT or t < nearestT) then nearest, nearestT = veh, t end
      end
    end
    if not nearest then return true end
    local cmd = string.format(HIT, origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, wall, M.HIT_RADIUS,
      M.IMPACT_FORCE, M.BLAST_RADIUS, M.BLAST_FORCE, M.BLAST_INVERSION, tostring(M.DEFLATE_TYRES),
      M.DRIVER_BOX, M.DRIVER_DROP, M.DRIVER_BRAKE)
    pcall(function() nearest:queueLuaCommand(cmd) end)
    return true
  end

  -- The crosshair at the mouse, and a dot where the shot would land. Hides the mouse pointer.
  function a:draw(shot)
    local imgui = call('imgui')
    if type(imgui) ~= 'table' then return end
    pcall(function()
      if imgui.SetMouseCursor and imgui.MouseCursor_None then imgui.SetMouseCursor(imgui.MouseCursor_None) end
      local viewport = imgui.GetMainViewport and imgui.GetMainViewport()
      local list = viewport and imgui.GetForegroundDrawList2 and imgui.GetForegroundDrawList2(viewport)
      local mouse = imgui.GetMousePos and imgui.GetMousePos()
      if not (list and mouse) then return end
      local s, t, colour = M.CROSSHAIR_SIZE, M.CROSSHAIR_THICKNESS, M.CROSSHAIR_COLOUR
      imgui.ImDrawList_AddLine(list, imgui.ImVec2(mouse.x - s, mouse.y), imgui.ImVec2(mouse.x + s, mouse.y), colour, t)
      imgui.ImDrawList_AddLine(list, imgui.ImVec2(mouse.x, mouse.y - s), imgui.ImVec2(mouse.x, mouse.y + s), colour, t)
    end)
    if shot and shot.point then call('drawSphere', shot.point, 0.06) end
  end

  -- Whether the left mouse button was clicked this frame on the game (not on a game menu).
  function a:clicked()
    local imgui = call('imgui')
    if type(imgui) ~= 'table' then return false end
    local ok, clicked = pcall(function()
      local io = imgui.GetIO and imgui.GetIO()
      if io and io.WantCaptureMouse then return false end
      return imgui.IsMouseClicked and imgui.IsMouseClicked(0) == true
    end)
    return ok and clicked == true
  end

  return a
end

return M
