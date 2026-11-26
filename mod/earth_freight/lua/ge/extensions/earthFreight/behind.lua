-- Out of sight (MadMerick, 6 Nov, from Tanker): Raiders never appear where you can see them. Each new
-- one is put somewhere in the half of the world behind the camera, the 180 degrees you are not
-- looking at. With no camera to read, the truck's facing stands in for it.
local M = {}

-- One-line settings. Tune these after testing in game.
-- A spawn point must be at least this many metres behind the camera, so nothing pops in at the
-- very edge of the screen.
M.MARGIN_METRES = 5

-- The view to spawn behind: { x, y, dx, dy }, from car:camera() if it has one, else the player
-- me (from car:player()).
function M.view(car, me)
  local cam = car and car.camera and car:camera()
  if cam then return cam end
  if me then return { x = me.x, y = me.y, dx = me.dx, dy = me.dy } end
end

-- Whether x, y is in the half behind the view. No view, no limit.
function M.isBehind(view, x, y)
  if not view then return true end
  return (x - view.x) * view.dx + (y - view.y) * view.dy <= -M.MARGIN_METRES
end

-- The point metres straight behind the camera.
function M.point(view, metres)
  return view.x - view.dx * metres, view.y - view.dy * metres
end

-- Reads the camera from the game: position and facing, flat. Every call guarded; nil if unknown.
function M.camera(env)
  local function read(f)
    if type(f) ~= 'function' then return nil end
    local ok, v = pcall(f)
    if ok and (type(v) == 'table' or type(v) == 'userdata') then return v end
  end
  local pos = read(env.cameraPosition)
  local fwd = read(env.cameraForward)
  if not (pos and fwd) then return nil end
  local ok, x, y, fx, fy = pcall(function() return pos.x, pos.y, fwd.x, fwd.y end)
  if not ok or type(x) ~= 'number' or type(fx) ~= 'number' or x ~= x or fx ~= fx then return nil end
  local len = math.sqrt(fx * fx + fy * fy)
  -- Looking straight up or down: no facing to go by.
  if len < 1e-3 then return nil end
  return { x = x, y = y, dx = fx / len, dy = fy / len }
end

return M
