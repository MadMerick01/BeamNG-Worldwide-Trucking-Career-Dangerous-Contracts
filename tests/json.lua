-- A small JSON encoder and decoder for tests, standing in for the game's jsonEncode/jsonDecode and BeamMP's
-- Util.JsonEncode/JsonDecode. Tables with keys 1..n are arrays; other tables are objects with sorted keys.
local J = {}

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return n > 0
end

function J.encode(v)
  local kind = type(v)
  if v == nil then return 'null'
  elseif kind == 'boolean' then return tostring(v)
  elseif kind == 'number' then
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format('%d', v) end
    return string.format('%.17g', v)
  elseif kind == 'string' then
    return '"' .. v:gsub('[%c"\\]', function(c)
      local named = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return named[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
  elseif kind == 'table' then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = J.encode(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local value = v[k]
      if value == nil then value = v[tonumber(k)] end
      out[#out + 1] = J.encode(k) .. ':' .. J.encode(value)
    end
    return '{' .. table.concat(out, ',') .. '}'
  end
  error('cannot encode ' .. kind)
end

function J.decode(text)
  if type(text) ~= 'string' then error('not text') end
  local i = 1
  local function space() i = text:find('[^ \t\r\n]', i) or #text + 1 end
  local value
  local function str()
    local out = {}
    i = i + 1
    while true do
      local c = text:sub(i, i)
      if c == '' then error('unterminated string') end
      if c == '"' then i = i + 1; return table.concat(out) end
      if c == '\\' then
        local e = text:sub(i + 1, i + 1)
        if e == 'u' then
          out[#out + 1] = string.char(tonumber(text:sub(i + 2, i + 5), 16) % 256); i = i + 6
        else
          out[#out + 1] = ({ n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' })[e] or e; i = i + 2
        end
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function value()
    space()
    local c = text:sub(i, i)
    if c == '{' then
      local t = {}
      i = i + 1; space()
      if text:sub(i, i) == '}' then i = i + 1; return t end
      while true do
        space(); local k = str(); space()
        if text:sub(i, i) ~= ':' then error('expected :') end
        i = i + 1
        t[k] = value(); space()
        local d = text:sub(i, i); i = i + 1
        if d == '}' then return t elseif d ~= ',' then error('expected , or }') end
      end
    elseif c == '[' then
      local t = {}
      i = i + 1; space()
      if text:sub(i, i) == ']' then i = i + 1; return t end
      while true do
        t[#t + 1] = value(); space()
        local d = text:sub(i, i); i = i + 1
        if d == ']' then return t elseif d ~= ',' then error('expected , or ]') end
      end
    elseif c == '"' then return str()
    elseif text:sub(i, i + 3) == 'true' then i = i + 4; return true
    elseif text:sub(i, i + 4) == 'false' then i = i + 5; return false
    elseif text:sub(i, i + 3) == 'null' then i = i + 4; return nil
    end
    local number = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not number or number == '' then error('bad JSON at ' .. i) end
    i = i + #number
    return tonumber(number)
  end
  local result = value()
  space()
  if i <= #text then error('trailing text') end
  return result
end

return J
