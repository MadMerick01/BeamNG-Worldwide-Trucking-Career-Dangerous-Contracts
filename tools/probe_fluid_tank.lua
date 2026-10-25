-- Probe: how does BeamNG fill its own fluid tanks? Earth Freight Sim only adds a load's weight to
-- the tank part today. If the game's cargo code can fill the tank instead, fluid loads would get
-- BeamNG's own sloshing. This finds out which calls and data the car has.
--
-- How to run it (once, in BeamNG.drive):
--   1. Fit a Cargo Load fluid tank to your car in the parts menu (Ctrl+W).
--   2. Open the console (the ~ key), set it to GE Lua (bottom left), paste this whole file and
--      press Enter.
--   3. Open the log (Documents/BeamNG.drive/beamng.log, or the console) and copy every line that
--      starts with "earthFreightProbe" into the project thread.
-- It only reads: nothing on the car or in your save changes.

local car = getPlayerVehicle(0)
if not car then log('E', 'earthFreightProbe', 'no player vehicle: get in a car with a fluid tank first') return end
log('I', 'earthFreightProbe', 'vehicle ' .. tostring(car.getJBeamFilename and car:getJBeamFilename()))
car:queueLuaCommand([[
local function say(text) obj:queueGameEngineLua('log("I", "earthFreightProbe", ' .. string.format('%q', text) .. ')') end
local function keys(t)
  local out = {}
  for k, v in pairs(type(t) == 'table' and t or {}) do out[#out + 1] = tostring(k) .. ':' .. type(v) end
  table.sort(out)
  return table.concat(out, ' ')
end
say('v.data keys with cargo, fluid or slosh: ' .. (function()
  local out = {}
  for k in pairs(v.data or {}) do
    local s = tostring(k):lower()
    if s:find('cargo') or s:find('fluid') or s:find('slosh') or s:find('liquid') then out[#out + 1] = tostring(k) end
  end
  return table.concat(out, ' ')
end)())
for k, section in pairs(v.data or {}) do
  local s = tostring(k):lower()
  if s:find('cargo') or s:find('fluid') or s:find('slosh') or s:find('liquid') then
    say('v.data.' .. tostring(k) .. ' = ' .. (dumps and dumps(section) or keys(section)):sub(1, 3000))
  end
end
local mods = {}
for name in pairs(package.loaded) do
  local s = tostring(name):lower()
  if s:find('cargo') or s:find('fluid') or s:find('slosh') or s:find('liquid') or s:find('delivery') then mods[#mods + 1] = tostring(name) end
end
table.sort(mods)
say('loaded modules: ' .. table.concat(mods, ' '))
for _, name in ipairs(mods) do say('module ' .. name .. ': ' .. keys(package.loaded[name])) end
if extensions then
  for name, ext in pairs(extensions) do
    local s = tostring(name):lower()
    if s:find('cargo') or s:find('fluid') or s:find('slosh') or s:find('liquid') then say('extension ' .. tostring(name) .. ': ' .. keys(ext)) end
  end
end
if energyStorage and energyStorage.getStorages then
  for name, storage in pairs(energyStorage.getStorages() or {}) do
    say('energy storage ' .. tostring(name) .. ' type ' .. tostring(storage.type) .. ': ' .. keys(storage))
  end
end
local n = 0
for _, node in pairs(v.data.nodes or {}) do
  if type(node) == 'table' and (node.cargoGroup or node.cargoGroups) then n = n + 1 end
end
say('nodes in a cargo group: ' .. n)
say('done')
]])
