-- One state payload at <= 4 Hz; periodic snapshots resync a remounted UI.
local M = {}
function M.new(trigger)
  local h = { mountedUntil = -1, lastSend = -math.huge, lastFull = -math.huge }
  local previous
  local function key(value)
    if type(value) ~= 'table' then return type(value) .. ':' .. tostring(value) end
    local keys, pieces = {}, {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do pieces[#pieces + 1] = tostring(k) .. '=' .. key(value[k]) end
    return '{' .. table.concat(pieces, '|') .. '}'
  end
  function h:mount(on, now)
    local fresh = now > self.mountedUntil
    self.mountedUntil = on and now + 5 or -1
    if fresh and on then previous = nil end
    return fresh and on
  end
  function h:publish(view, now)
    if now > self.mountedUntil or now - self.lastSend < 0.25 then return false end
    local nextKey = key(view)
    if nextKey == previous and now - self.lastFull < 2 then return false end
    if trigger then
      local ok = pcall(trigger, 'EarthFreightState', view)
      if not ok then return false end
    end
    previous, self.lastSend, self.lastFull = nextKey, now, now
    return true
  end
  return h
end
return M
