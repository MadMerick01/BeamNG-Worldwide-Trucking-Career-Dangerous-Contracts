local location = require('earthFreight/location')
local M = { FILE = '/settings/earthFreight/config.json' }
-- Penrith, NSW: on the edge of Sydney, with the Blue Mountains next door. The place list is built
-- around it. Players choose their own start with Start here; a base in config.json fixes one.
M.START_PLACE = 'gn2153471'
M.START_TOWN = 'Penrith'
M.START = { latitude = -33.75, longitude = 150.7 }

function M.defaults()
  -- Each caller receives a fresh table. There is no base: the player picks their start with Start
  -- here. A base in config.json makes every new game start there, which is handy for testing.
  -- autoGps sets BeamNG.Earth's GPS to the drop-off when a load is bought.
  return {
    resumeRadiusMetres = 50,
    autoGps = true,
  }
end

function M.validate(data)
  if type(data) ~= 'table' or (data.base ~= nil and not location.valid(data.base)) then return nil, 'base_coordinates' end
  local radius = data.resumeRadiusMetres == nil and 50 or data.resumeRadiusMetres
  if not location.finite(radius) or radius < 1 or radius > 1000 then return nil, 'verification_radius' end
  if data.autoGps ~= nil and type(data.autoGps) ~= 'boolean' then return nil, 'auto_gps' end
  return { base = data.base and location.copy(data.base), resumeRadiusMetres = radius, autoGps = data.autoGps ~= false }
end

function M.load(io)
  local existsOK, exists = pcall(io.exists, M.FILE)
  if not existsOK or type(exists) ~= 'boolean' then return nil, 'configuration_unreadable' end
  if not exists then return M.defaults() end
  -- A present but invalid/unreadable override must never be ignored or replaced.
  local ok, data = pcall(io.read, M.FILE)
  if not ok or data == nil then return nil, 'configuration_unreadable' end
  return M.validate(data)
end

return M
