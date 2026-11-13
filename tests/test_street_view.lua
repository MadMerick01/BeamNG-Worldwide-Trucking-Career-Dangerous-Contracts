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
T.eq(SV.encode({ { a = 1 }, { a = 2 } }), '[{"a":1},{"a":2}]', 'a list is a JSON array')
T.eq(SV.encode({ list = { 3 }, none = {} }), '{"list":[3],"none":{}}', 'in an object too, and an empty table is {}')

-- In the game: the Street View button.
do
  local lib = fakeSocket()
  local opened = {}
  local c, io, a = F.controller({ streetView = SV.new({ socket = lib }), openUrl = function(url) opened[#opened + 1] = url; return true end })
  a.pose = F.position(-33.75, 150.7)
  a.names = { street = 'High Street', place = 'Penrith', region = 'New South Wales', country = 'Australia' }
  c:tick(0.1)
  T.check(c:view().streetView ~= nil, 'HUD offers Street View'); T.check(not c:view().streetView.on, 'off at first')
  T.check(c:openStreetView(), 'Street View opens')
  T.eq(opened[1], 'http://127.0.0.1:47170/', 'page opened in the browser')
  T.eq(c:view().streetView.url, 'http://127.0.0.1:47170/', 'HUD has the address for its Copy button')
  T.check(c:view().streetView.feedback:find('copy the address below', 1, true) ~= nil, 'HUD points to the Copy button')
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
  T.check(c3:view().streetView.feedback:find('copy the address below', 1, true) ~= nil, 'address offered when no browser opens')
  local c5 = F.controller({ streetView = SV.new({ socket = fakeSocket() }), openUrl = function() return false end })
  c5:openStreetView()
  T.eq(c5:view().streetView.feedback, 'To see Street View, copy the address below into your web browser.', 'no browser: asked to paste')
  local c6 = F.controller({ streetView = SV.new({ socket = fakeSocket() }), openUrl = function() error('blocked') end })
  T.check(c6:openStreetView(), 'a failing opener does not break the button')
  T.check(c6:view().streetView.feedback:find('copy the address below', 1, true) ~= nil, 'and the address is offered')
  local busy = fakeSocket(); busy.busy = true
  local c4 = F.controller({ streetView = SV.new({ socket = busy }) })
  T.check(not c4:openStreetView(), 'busy port fails')
  T.check(c4:view().streetView.feedback:find('47170', 1, true) ~= nil, 'and says which port')
  T.eq(F.controller():view().streetView, nil, 'no server, no button')

  -- The Base map: the same server, at /bases, with its data at /basemap.
  local libB = fakeSocket()
  local opened2 = {}
  local cb = F.controller({ streetView = SV.new({ socket = libB }), openUrl = function(url) opened2[#opened2 + 1] = url; return true end })
  cb:tick(0.1)
  T.check(cb:view().baseMap ~= nil, 'HUD offers the base map')
  T.check(cb:openBaseMap(), 'base map opens')
  T.eq(opened2[1], 'http://127.0.0.1:47170/bases', 'its page opened in the browser')
  T.eq(cb:view().baseMap.url, 'http://127.0.0.1:47170/bases', 'HUD has its address')
  T.check(cb:view().baseMap.feedback:find('copy the address below', 1, true) ~= nil, 'HUD points to the Copy button')
  local pageReq, dataReq = libB.client(get('/bases')), libB.client(get('/basemap'))
  libB.queue = { pageReq, dataReq }
  cb:tick(0.1); cb:tick(0.1)
  T.eq(body(pageReq), require('earthFreight/baseMapPage').html, 'the base map page')
  T.check(body(dataReq):find('"circles":', 1, true) ~= nil and body(dataReq):find('"ok":true', 1, true) ~= nil, 'and its data')
  -- With a base, its circle reaches the page as a list (it came out as an object of nulls, so none was drawn).
  cb:tick(0.6); cb:tick(0.6)
  cb.profile.progression.balance = 400000
  T.check(cb:claimHome(), 'a base for the map')
  local dataReq2 = libB.client(get('/basemap'))
  libB.queue = { dataReq2 }
  cb:tick(0.1); cb:tick(0.1)
  T.check(body(dataReq2):find('"circles":[{', 1, true) ~= nil, 'the circles are a JSON array of circles')
  T.check(body(dataReq2):find('"town":"Penrith"', 1, true) ~= nil, 'with the base in it')
  local busyB = fakeSocket(); busyB.busy = true
  local cb2 = F.controller({ streetView = SV.new({ socket = busyB }) })
  T.check(not cb2:openBaseMap(), 'busy port fails')
  T.check(cb2:view().baseMap.feedback == nil, 'nothing claimed while off')
end

-- The Radio: the same server, at /radio. The page passes what it plays in ?radio=, for the HUD.
do
  local lib = fakeSocket()
  local opened = {}
  local c = F.controller({ streetView = SV.new({ socket = lib }), openUrl = function(url) opened[#opened + 1] = url; return true end })
  c:tick(0.1)
  T.check(c:view().radio ~= nil and not c:view().radio.open, 'HUD offers the radio, not open yet')
  T.check(c:openRadio(), 'radio opens')
  T.eq(opened[1], 'http://127.0.0.1:47170/radio', 'its page opened in the browser')
  T.eq(c:view().radio.url, 'http://127.0.0.1:47170/radio', 'HUD has its address')
  T.check(c:view().radio.feedback:find('opening in your web browser', 1, true) ~= nil, 'and says where it went')
  local pageReq, posReq = lib.client(get('/radio')), lib.client(get('/position?radio=Lithgow%20Community+Radio'))
  lib.queue = { pageReq, posReq }
  c:tick(0.1); c:tick(0.1)
  T.eq(body(pageReq), require('earthFreight/radioPage').html, 'the radio page')
  T.check(body(posReq):find('"ok":', 1, true) ~= nil, 'the position as usual')
  T.eq(c:view().radio.playing, 'Lithgow Community Radio', 'the HUD shows what is playing')
  T.check(c:view().radio.open, 'and that the page is open')
  local stopped = lib.client(get('/position?radio='))
  lib.queue = { stopped }
  c:tick(0.1); c:tick(0.1)
  T.eq(c:view().radio.playing, nil, 'stopped')
  T.check(c:view().radio.open, 'page still open')
  T.eq(c.streetView:radio(c.clock + 30), nil, 'a page gone quiet is closed')
  local plain = lib.client(get('/position'))
  lib.queue = { plain }
  c:tick(0.1); c:tick(0.1)
  T.check(c:view().radio.open, 'Street View asking does not change the radio')
  local busy = fakeSocket(); busy.busy = true
  local c2 = F.controller({ streetView = SV.new({ socket = busy }) })
  T.check(not c2:openRadio(), 'busy port fails')
  T.check(c2:view().radio.feedback == nil, 'nothing claimed while off')
  T.eq(F.controller():view().radio, nil, 'no server, no radio')
  local page = require('earthFreight/radioPage').html
  for _, part in ipairs({ 'radio-browser.info', "fetch('/position?radio='", 'Follow my truck', 'Play nearest', 'Next station', 'textContent',
      "name: 'Psyndora Chill'", 'Add your own station', 'Remove' }) do
    T.check(page:find(part, 1, true) ~= nil, 'radio page has ' .. part)
  end
  T.check(page:find('innerHTML', 1, true) == nil, 'station names never go in as HTML')
end

-- What the radio page says it plays: decoded, plain text, short.
do
  T.eq(SV.radioParam('/position'), nil, 'nothing said')
  T.eq(SV.radioParam('/position?radio='), '', 'stopped')
  T.eq(SV.radioParam('/position?x=1&radio=Triple%20J%2B'), 'Triple J+', 'decoded')
  T.eq(SV.radioParam('/position?radio=%3Cb%3EHi%3C%2Fb%3E%0A'), 'bHi/b', 'no markup or control characters')
  T.eq(#SV.radioParam('/position?radio=' .. string.rep('a', 200)), 60, 'at most 60 characters')
  T.eq(SV.radioParam('/position?radio=' .. string.rep('a', 59) .. '%C3%A9'), string.rep('a', 59), 'never half a letter')
end

T.done('street view')
