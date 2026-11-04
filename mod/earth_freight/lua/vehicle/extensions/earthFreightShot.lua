-- earthFreightShot: a local's bullet hitting the player's car. Copied from Tanker's tankerHit.lua
-- (itself a copy of the VR revolver mod's vrPistolHit.lua, BeamngVRcontrollerPoses), without the
-- driver box: finds where the bullet ray meets the car's nodes and applies the impact model from
-- Bolides' BulletDamage.lua, a mass-scaled push on the struck node along the bullet plus a falloff
-- blast on nearby nodes that dents the body. A hit near a wheel hub can also flatten that tyre,
-- which is reported back once per tyre so the Garage tab charges its repair.

local M = {}

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- Tyres this script has flattened since the car was spawned: each is reported once.
local flattened = {}

local function deflateNearbyTyre(hitPos)
  if not (v.data.wheels and beamstate and beamstate.deflateTire) then return end
  for wheelId, wheel in pairs(v.data.wheels) do
    if wheel.node1 and wheel.node2 and wheel.radius then
      local hub = (obj:getNodePosition(wheel.node1) + obj:getNodePosition(wheel.node2)) * 0.5
      if (hitPos - hub):length() < wheel.radius * 1.05 then
        if flattened[wheelId] then return end
        if pcall(beamstate.deflateTire, wheelId) then
          flattened[wheelId] = true
          obj:queueGameEngineLua('if earthFreight_core then earthFreight_core.onLocalsTyre() end')
        end
        return
      end
    end
  end
end

-- Origin arrives in world space; node positions are relative to obj:getPosition().
function M.hit(ox, oy, oz, dx, dy, dz, maxDist, hitRadius, impactForce, blastRadius, blastForce,
               blastInversion, deflateTyres)
  local origin = vec3(ox, oy, oz) - obj:getPosition()
  local dir = vec3(dx, dy, dz)
  local hitR2 = hitRadius * hitRadius

  local hitNode, hitT
  for _, node in pairs(v.data.nodes) do
    local p = obj:getNodePosition(node.cid)
    local t = (p - origin):dot(dir)
    if t > 0 and t < maxDist and (not hitT or t < hitT) then
      if (p - (origin + dir * t)):squaredLength() < hitR2 then hitNode, hitT = node.cid, t end
    end
  end
  if not hitNode then return end

  -- Impact point on the ray itself, beside the struck node.
  local impact = origin + dir * hitT

  local mass = 1
  if obj.getNodeMass then mass = obj:getNodeMass(hitNode) or 1 end
  obj:applyForceVector(hitNode, dir * impactForce * mass)

  if blastRadius > 0 then
    local inner = blastRadius * 0.5
    local forceBase = blastForce * 2000
    for _, node in pairs(v.data.nodes) do
      local offset = obj:getNodePosition(node.cid) - impact
      local distance = offset:length()
      if distance <= blastRadius and distance > 1e-6 then
        local sign = fsign(math.random() - blastInversion)
        local force = forceBase * clamp(1 - (distance - inner) / (blastRadius - inner), 0, 1)
        obj:applyForceVector(node.cid, offset * (sign * force / distance))
      end
    end
  end

  if deflateTyres then deflateNearbyTyre(impact) end
  obj:queueGameEngineLua('if earthFreight_core then earthFreight_core.onLocalsHit() end')
end

return M
