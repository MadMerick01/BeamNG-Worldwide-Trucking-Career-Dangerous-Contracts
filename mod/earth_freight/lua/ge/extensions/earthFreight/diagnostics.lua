local M = {}
function M.new(write)
  local last = {}
  local d = {}
  function d:event(key, detail, level)
    detail = tostring(detail or '')
    if last[key] == detail then return end
    last[key] = detail
    if write then pcall(write, level or 'I', 'earthFreight', key .. ': ' .. detail) end
  end
  function d:clear(key) last[key] = nil end
  return d
end
return M
