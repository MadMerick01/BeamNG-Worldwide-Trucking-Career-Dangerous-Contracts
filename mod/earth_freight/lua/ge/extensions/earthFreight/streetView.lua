-- The Street View window: a tiny web server on this computer only (127.0.0.1), so any browser can
-- show Google Street View of where the car is. It serves the page itself and the car's latest
-- position as JSON; the page asks for the position every 6, 10 or 20 seconds. Nothing is sent anywhere by
-- the game: the browser fetches the pictures from Google.
-- The same server serves the Base map (/bases, baseMapPage.lua): an overhead map of the bases' circles
-- and the truck, whose data (/basemap) the page asks for every few seconds.
-- And the Radio (/radio, radioPage.lua): live stations near the truck, played by the browser. It asks
-- /position?radio=<station> every few seconds, so the HUD can show what is playing.
-- Driven from the game's frame: every call is non-blocking (timeouts of 0), so a slow or stuck
-- browser never holds the game up. The socket library is injected so tests can fake it.
local page = require('earthFreight/streetViewPage')
local baseMapPage = require('earthFreight/baseMapPage')
local radioPage = require('earthFreight/radioPage')
local M = { HOST = '127.0.0.1', PORT = 47170, MAX_CLIENTS = 8, MAX_REQUEST = 8192, CLIENT_SECONDS = 5, RADIO_SECONDS = 20 }

-- The station the Radio page says it is playing: decoded from the address, plain text, at most 60 characters.
function M.radioParam(path)
  local query = path:match('%?([^#]*)')
  if not query then return nil end
  for pair in query:gmatch('[^&]+') do
    local k, v = pair:match('^([^=]*)=?(.*)$')
    if k == 'radio' then
      v = v:gsub('%+', ' '):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
      v = v:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
      if #v > 60 then v = v:sub(1, 60):gsub('[\128-\191]+$', ''):gsub('[\192-\255]$', '') end
      return v
    end
  end
  return nil
end

local function encode(value)
  local t = type(value)
  if t == 'nil' then return 'null' end
  if t == 'boolean' then return value and 'true' or 'false' end
  if t == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return 'null' end
    if value == math.floor(value) and math.abs(value) < 1e15 then return string.format('%d', value) end
    local text = string.format('%.7f', value):gsub('0+$', ''):gsub('%.$', '')
    return text
  end
  if t == 'string' then
    return '"' .. value:gsub('[%c"\\]', function(c)
      local named = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return named[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
  end
  if t == 'table' then
    -- A list (keys 1..n, as the Base map's circles are) is a JSON array. Before, a list came out as an object
    -- of nulls, so the Base map never drew any circle.
    local n = #value
    if n > 0 then
      local count = 0
      for _ in pairs(value) do count = count + 1 end
      if count == n then
        local parts = {}
        for i = 1, n do parts[i] = encode(value[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
      end
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = encode(k) .. ':' .. encode(value[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end
M.encode = encode

local function response(status, contentType, body)
  return table.concat({
    'HTTP/1.1 ' .. status,
    'Content-Type: ' .. contentType,
    'Content-Length: ' .. #body,
    'Cache-Control: no-store',
    'X-Content-Type-Options: nosniff',
    'Connection: close',
    '', body }, '\r\n')
end

function M.new(env)
  env = env or {}
  local s = { on = false, error = nil, port = env.port or M.PORT, clients = {} }
  local server

  function s:url() return 'http://' .. M.HOST .. ':' .. self.port .. '/' end

  -- Opens the listening socket. True when it is listening (or already was); false and why if not.
  function s:start()
    if server then return true end
    local socketLib = env.socket or rawget(_G, 'socket')
    if type(socketLib) ~= 'table' or type(socketLib.tcp) ~= 'function' then
      self.error = 'no_socket'; return false, self.error
    end
    local ok, sock = pcall(socketLib.tcp)
    if not ok or not sock then self.error = 'no_socket'; return false, self.error end
    local bound = pcall(function()
      -- Bound to this computer only: nothing on the network can reach it.
      local done, why = sock:bind(M.HOST, self.port)
      if not done then error(why or 'bind') end
      done, why = sock:listen(M.MAX_CLIENTS)
      if not done then error(why or 'listen') end
      sock:settimeout(0)
    end)
    if not bound then
      pcall(function() sock:close() end)
      self.error = 'port_busy'; return false, self.error
    end
    server, self.on, self.error = sock, true, nil
    return true
  end

  function s:stop()
    for _, c in ipairs(self.clients) do pcall(function() c.sock:close() end) end
    self.clients = {}
    if server then pcall(function() server:close() end) end
    server, self.on = nil, false
  end

  -- Only pages that asked for this computer by name or number are answered, so a web site that
  -- points its own name at 127.0.0.1 cannot read where the car is.
  local function allowedHost(head)
    local host = head:match('\r\n[Hh][Oo][Ss][Tt]:%s*([^\r\n]*)')
    if not host then return false end
    host = host:lower():gsub('%s+$', '')
    local port = tostring(s.port)
    return host == M.HOST .. ':' .. port or host == 'localhost:' .. port
  end

  local function json(build)
    local ok, value = pcall(build or error)
    if not ok or type(value) ~= 'table' then value = { ok = false, reason = 'internal_error' } end
    return response('200 OK', 'application/json; charset=utf-8', encode(value))
  end

  local function answer(head, position, baseMap)
    local method, path = head:match('^(%u+) (%S+) HTTP/1%.%d\r\n')
    if not method then return response('400 Bad Request', 'text/plain', 'Bad request') end
    if not allowedHost(head) then return response('403 Forbidden', 'text/plain', 'Forbidden') end
    if method ~= 'GET' then return response('405 Method Not Allowed', 'text/plain', 'GET only') end
    local radio = M.radioParam(path)
    if radio then s.radioPlaying, s.radioSeen = radio ~= '' and radio or nil, s.clock end
    path = path:match('^[^?#]*')
    if path == '/' or path == '/index.html' then
      return response('200 OK', 'text/html; charset=utf-8', page.html)
    elseif path == '/position' then
      return json(position)
    elseif path == '/bases' then
      return response('200 OK', 'text/html; charset=utf-8', baseMapPage.html)
    elseif path == '/basemap' then
      return json(baseMap)
    elseif path == '/radio' then
      return response('200 OK', 'text/html; charset=utf-8', radioPage.html)
    end
    return response('404 Not Found', 'text/plain', 'Not found')
  end

  local function closeClient(i)
    local c = table.remove(s.clients, i)
    if c then pcall(function() c.sock:close() end) end
  end

  -- Called every frame. position() and baseMap() build the JSON bodies; each is only called when a page asks.
  function s:poll(now, position, baseMap)
    self.clock = now
    if not server then return end
    for _ = 1, M.MAX_CLIENTS do
      if #self.clients >= M.MAX_CLIENTS then break end
      local ok, sock = pcall(server.accept, server)
      if not ok or not sock then break end
      pcall(sock.settimeout, sock, 0)
      self.clients[#self.clients + 1] = { sock = sock, buffer = '', since = now }
    end
    for i = #self.clients, 1, -1 do
      local c = self.clients[i]
      local finished = false
      if not c.reply then
        local ok, data, why, partial = pcall(c.sock.receive, c.sock, M.MAX_REQUEST)
        local got = ok and (data or partial) or nil
        if got and got ~= '' then c.buffer = c.buffer .. got end
        if not ok or why == 'closed' then finished = true
        elseif c.buffer:find('\r\n\r\n', 1, true) then c.reply, c.sent = answer(c.buffer, position, baseMap), 0
        elseif #c.buffer >= M.MAX_REQUEST then c.reply, c.sent = response('431 Request Header Fields Too Large', 'text/plain', 'Too large'), 0 end
      end
      if c.reply and not finished then
        local ok, last, why, partialLast = pcall(c.sock.send, c.sock, c.reply, c.sent + 1)
        if not ok then finished = true
        else
          c.sent = last or partialLast or c.sent
          if c.sent >= #c.reply or (why and why ~= 'timeout') then finished = true end
        end
      end
      if finished or now - c.since > M.CLIENT_SECONDS then closeClient(i) end
    end
  end

  -- The Radio page's station, while the page is still asking; nil once it has gone quiet or stopped.
  function s:radio(now)
    if not self.on or not self.radioSeen or (now or self.clock or 0) - self.radioSeen > M.RADIO_SECONDS then return nil end
    return { playing = self.radioPlaying }
  end

  return s
end

return M
