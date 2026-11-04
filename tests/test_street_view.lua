local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local SV = require('earthFreight/streetView')

-- A fake LuaSocket: a listening socket with a queue of connections, each with its request text,
-- that may arrive in pieces, and the bytes the server sent back.
local function fakeSocket()
  local lib = { listening = nil, queue = {}, binds = 0 }
  local function client(request, chunk, sendChunk)
    local c = { request = request, at = 1, out = '', closed = false }
    function c:settimeout() end
    function c:receive(n)
      if self.at > #self.request then return nil, 'timeout', '' end
      local size = math.min(n, chunk or n)
      local piece = self.request:sub(self.at, self.at + size - 1)
      self.at = self.at + #piece
      return nil, 'timeout', piece
    end
    function c:send(data, from)
      local upto = math.min(#data, from - 1 + (sendChunk or #data))
      self.out = self.out .. data:sub(from, upto)
      if upto < #data then return nil, 'timeout', upto end
      return upto
    end
    function c:close() self.closed = true end
    return c
  end
  lib.client = client
  function lib.tcp()
    local s = { closed = false }
    function s:bind(host, port)
      lib.binds = lib.binds + 1
      if lib.busy then return nil, 'address already in use' end
      s.host, s.port = host, port; return 1
    end
    function s:listen() lib.listening = s; return 1 end
    function s:settimeout() end
    function s:accept()
      local c = table.remove(lib.queue, 1)
      if c then return c end
      return nil, 'timeout'
    end
    function s:close() s.closed = true; if lib.listening == s then lib.listening = nil end end
    return s
  end
  return lib
end
local function get(path, host) return 'GET ' .. path .. ' HTTP/1.1\r\nHost: ' .. (host or '127.0.0.1:47170') .. '\r\nAccept: */*\r\n\r\n' end
local function body(c) return c.out:match('\r\n\r\n(.*)$') end

-- Starting binds this computer only.
do
  local lib = fakeSocket()
  local s = SV.new({ socket = lib })
  T.check(not s.on, 'off until started')
  T.check(s:start(), 'starts'); T.check(s.on, 'on once started')
  T.eq(lib.listening.host, '127.0.0.1', 'listens on this computer only'); T.eq(lib.listening.port, 47170, 'on its port')
  T.check(s:start(), 'starting again is fine'); T.eq(lib.binds, 1, 'and does not bind twice')
  T.eq(s:url(), 'http://127.0.0.1:47170/', 'its address')

  -- The page and the position.
  local page = lib.client(get('/'))
  local pos = lib.client(get('/position?t=1'), 7) -- the request arrives seven bytes at a time
  lib.queue = { page, pos }
  local asked = 0
  local function position() asked = asked + 1; return { ok = true, latitude = -33.75, longitude = 150.7, heading = 90.5, street = 'Great "Western" Hwy' } end
  for i = 1, 40 do s:poll(i * 0.01, position) end
  T.check(page.out:find('^HTTP/1.1 200 OK') ~= nil, 'page served')
  T.check(page.out:find('Content-Type: text/html', 1, true) ~= nil, 'as HTML')
  T.check(body(page):find('Worldwide Trucking Street View', 1, true) ~= nil, 'the Street View page')
  T.check(page.closed, 'connection closed after the page')
  T.check(pos.out:find('application/json', 1, true) ~= nil, 'position is JSON')
  T.eq(body(pos), '{"heading":90.5,"latitude":-33.75,"longitude":150.7,"ok":true,"street":"Great \\"Western\\" Hwy"}', 'position body')
  T.eq(asked, 1, 'position built once, only when asked')
  T.eq(#s.clients, 0, 'no connections left over')

  -- A reply bigger than one send goes out in pieces.
  local slow = lib.client(get('/'), nil, 100)
  lib.queue = { slow }
  for i = 1, 400 do s:poll(1 + i * 0.001, position) end
  T.eq(#body(slow), #require('earthFreight/streetViewPage').html, 'whole page sent in pieces')

  -- Web sites using another name for this computer are refused.
  local evil = lib.client(get('/position', 'evil.example:47170'))
  local local2 = lib.client(get('/position', 'localhost:47170'))
  local nohost = lib.client('GET /position HTTP/1.1\r\n\r\n')
  local post = lib.client('POST /position HTTP/1.1\r\nHost: 127.0.0.1:47170\r\n\r\n')
  local missing = lib.client(get('/secret'))
  lib.queue = { evil, local2, nohost, post, missing }
  for i = 1, 10 do s:poll(2 + i * 0.01, position) end
  T.check(evil.out:find('^HTTP/1.1 403') ~= nil, 'other host names refused')
  T.check(not evil.out:find('latitude', 1, true), 'and told nothing')
  T.check(local2.out:find('^HTTP/1.1 200') ~= nil, 'localhost works too')
  T.check(nohost.out:find('^HTTP/1.1 403') ~= nil, 'no Host refused')
  T.check(post.out:find('^HTTP/1.1 405') ~= nil, 'only GET')
  T.check(missing.out:find('^HTTP/1.1 404') ~= nil, 'unknown path is not found')

  -- A browser that never finishes its request is let go.
  local stuck = lib.client('GET / HTTP/1.1\r\nHost: 127')
  lib.queue = { stuck }
  s:poll(3, position); s:poll(3.1, position)
  T.eq(#s.clients, 1, 'waits for the rest of the request')
  s:poll(3 + SV.CLIENT_SECONDS + 1, position)
  T.eq(#s.clients, 0, 'then gives up'); T.check(stuck.closed, 'and closes it')

  -- A failing position never breaks the server.
  local broken = lib.client(get('/position'))
  lib.queue = { broken }
  for i = 1, 5 do s:poll(20 + i * 0.01, function() error('boom') end) end
  T.eq(body(broken), '{"ok":false,"reason":"internal_error"}', 'a failing position reports an error')

  s:stop()
  T.check(not s.on, 'off once stopped'); T.check(lib.listening == nil, 'port let go')
  s:poll(30, position) -- polling a stopped server does nothing
end

-- A busy port, or no socket library, is reported, not thrown.
do
  local lib = fakeSocket(); lib.busy = true
  local s = SV.new({ socket = lib })
  local ok, why = s:start()
  T.check(not ok, 'busy port fails'); T.eq(why, 'port_busy', 'and says why'); T.check(not s.on, 'stays off')
  local none = SV.new({ socket = {} })
  ok, why = none:start(); T.eq(why, 'no_socket', 'no socket library')
end

-- JSON
T.eq(SV.encode({ a = 0 / 0, b = 1e300 * 1e10, c = 'line\nbreak\1' }), '{"a":null,"b":null,"c":"line\\nbreak\\u0001"}', 'JSON escapes')
T.eq(SV.encode(-33.12345678), '-33.1234568', 'seven decimals')

-- In the game: the Street View button.
do
  local lib = fakeSocket()
  local opened = {}
  local c, io, a = F.controller({ streetView = SV.new({ socket = lib }), openUrl = function(url) opened[#opened + 1] = url end })
  a.pose = F.position(-33.75, 150.7)
  a.names = { street = 'High Street', place = 'Penrith', region = 'New South Wales', country = 'Australia' }
  c:tick(0.1)
  T.check(c:view().streetView ~= nil, 'HUD offers Street View'); T.check(not c:view().streetView.on, 'off at first')
  T.check(c:openStreetView(), 'Street View opens')
  T.eq(opened[1], 'http://127.0.0.1:47170/', 'page opened in the browser')
  T.check(c:view().streetView.on, 'shown as on')
  T.eq(io.files['/settings/earthFreight/streetview.json'].on, true, 'remembered for next time')
  local p = c:streetViewPosition()
  T.check(p.ok, 'position ready'); T.eq(p.latitude, -33.75, 'latitude'); T.eq(p.street, 'High Street', 'street')
  T.eq(p.place, 'Penrith', 'town'); T.eq(p.country, 'Australia', 'country')
  local req = lib.client(get('/position'))
  lib.queue = { req }
  c:tick(0.1)
  T.check(body(req):find('"latitude":-33.75', 1, true) ~= nil, 'served from the game frame')

  a.valid, a.reason = false, 'vehicle_required'
  c:tick(0.1)
  T.eq(c:streetViewPosition().reason, 'vehicle_required', 'no car: says why')
  T.check(c:stopStreetView(), 'turned off'); T.check(not c:view().streetView.on, 'shown as off')
  T.eq(io.files['/settings/earthFreight/streetview.json'].on, false, 'off remembered')

  -- Next game: on again by itself when it was left on.
  io.files['/settings/earthFreight/streetview.json'] = { on = true }
  local sv2 = SV.new({ socket = fakeSocket() })
  F.controller({ io = io, streetView = sv2 })
  T.check(sv2.on, 'starts by itself when left on')

  -- No browser opener: the address is given instead.
  local c3 = F.controller({ streetView = SV.new({ socket = fakeSocket() }) })
  c3:openStreetView()
  T.check(c3:view().streetView.feedback:find('http://127.0.0.1:47170/', 1, true) ~= nil, 'address shown when no browser opens')
  local busy = fakeSocket(); busy.busy = true
  local c4 = F.controller({ streetView = SV.new({ socket = busy }) })
  T.check(not c4:openStreetView(), 'busy port fails')
  T.check(c4:view().streetView.feedback:find('47170', 1, true) ~= nil, 'and says which port')
  T.eq(F.controller():view().streetView, nil, 'no server, no button')
end

T.done('street view')
