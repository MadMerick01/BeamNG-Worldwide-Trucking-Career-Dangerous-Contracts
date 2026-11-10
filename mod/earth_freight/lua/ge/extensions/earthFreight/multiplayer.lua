-- Careers on a BeamMP server. On a server running the Worldwide Trucking server plugin
-- (server/WorldwideTrucking/main.lua), the career is the server's: it is fetched on joining, kept in a folder of its
-- own on this PC while playing (never the single-player save folder), and every save is sent back to the server.
-- On a server without the plugin, the multiplayer career is kept on this PC only, again apart from the single-player
-- one. The messages and frames are described at the top of the server plugin. No game globals here: the game's
-- sending, JSON and files are given to new().
local persistence = require('earthFreight/persistence')
local M = {
  PROTO = 1, CHUNK = 20000, SAVE_MAX = 4 * 1024 * 1024,
  ROOT = '/settings/earthFreight/mp/',
  -- How long to wait for the server's answer before treating it as a server without the plugin.
  WAIT_SECONDS = 20,
  -- The question is asked again every HELLO_EVERY seconds while waiting: one asked while BeamMP is still joining can
  -- be lost, which left a player on a trucking server with a career kept on their PC instead of the server's. After
  -- giving up it is still asked every LATE_EVERY seconds for LATE_FOR seconds, and a late answer brings the server's
  -- career in.
  HELLO_EVERY = 5, LATE_EVERY = 15, LATE_FOR = 600,
}
-- This copy's build number, written into the ZIP by the release workflow (tools/package.py); nil in a copy not
-- built by it. Sent on joining, so a server can turn away an older copy than its own.
do
  local ok, build = pcall(require, 'earthFreight/build')
  M.BUILD = ok and type(build) == 'number' and build or nil
end
M.KEYS = M.ROOT .. 'keys.json'
M.LOCAL = M.ROOT .. 'local/'
M.PREFS = M.ROOT .. 'prefs.json'

-- Text from the server for the HUD: one line, trimmed, at most max characters.
function M.cleanText(value, max)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value:sub(1, max or 60)
end

-- The server's player list, checked: an id and a name each, and a town where the server knows it.
function M.cleanPlayers(list)
  local out = {}
  for _, p in ipairs(list) do
    if type(p) == 'table' and type(p.id) == 'number' and p.id >= 0 and p.id == math.floor(p.id) and #out < 64 then
      local lat, lon = tonumber(p.latitude), tonumber(p.longitude)
      local spot = lat and lon and math.abs(lat) <= 90 and math.abs(lon) <= 180 and { latitude = lat, longitude = lon } or nil
      out[#out + 1] = { id = p.id, name = M.cleanText(p.name, 32) or 'A trucker', town = M.cleanText(p.town, 40),
        region = M.cleanText(p.region, 60), doing = M.cleanText(p.doing, 80), near = spot }
    end
  end
  return out
end

-- The server's bases of operations, checked: each owner's name, the town, its centre and the circle's radius in km,
-- and whether it is this player's own.
function M.cleanBases(list)
  local out = {}
  for _, b in ipairs(type(list) == 'table' and list or {}) do
    local lat, lon, r = type(b) == 'table' and tonumber(b.latitude), type(b) == 'table' and tonumber(b.longitude),
      type(b) == 'table' and tonumber(b.radiusKm)
    if lat and lon and r and math.abs(lat) <= 90 and math.abs(lon) <= 180 and r > 0 and r <= 100 and #out < 256 then
      out[#out + 1] = { name = M.cleanText(b.name, 32) or 'A trucker', town = M.cleanText(b.town, 40),
        latitude = lat, longitude = lon, radiusKm = r, mine = b.mine == true }
    end
  end
  return out
end

local function validId(k) return type(k) == 'string' and #k == 32 and not k:find('[^0-9a-f]') end

-- Splits text into frames ('v|id|i|n|piece'), as the server does.
function M.frames(id, text, size)
  size = size or M.CHUNK
  local n = math.max(1, math.ceil(#text / size))
  local out = {}
  for i = 1, n do
    out[i] = table.concat({ tostring(M.PROTO), tostring(id), tostring(i), tostring(n), text:sub((i - 1) * size + 1, i * size) }, '|')
  end
  return out
end

-- Adds a frame to an inbox; the whole message once its last piece is in, else nil.
function M.receive(inbox, frame)
  if type(frame) ~= 'string' then return nil end
  local v, id, i, n, piece = frame:match('^(%d+)|(%d+)|(%d+)|(%d+)|(.*)$')
  v, i, n = tonumber(v), tonumber(i), tonumber(n)
  if v ~= M.PROTO or not i or not n or n < 1 or i < 1 or i > n or n * M.CHUNK > M.SAVE_MAX + M.CHUNK then
    inbox.id = nil
    return nil
  end
  if inbox.id ~= id or inbox.n ~= n then inbox.id, inbox.n, inbox.parts, inbox.got = id, n, {}, 0 end
  if not inbox.parts[i] then inbox.parts[i], inbox.got = piece, inbox.got + 1 end
  if inbox.got < n then return nil end
  local text = table.concat(inbox.parts, '', 1, n)
  inbox.id, inbox.parts = nil, nil
  return text
end

-- deps: send(event, text), encode(table) -> text, decode(text) -> table, io (read, exists, write, mkdir, remove),
-- decodeFile(path) -> table (the game's JSON file reader; io.read).
-- state: 'waiting' (asked the server), 'server' (the server's career is here), 'local' (no plugin on this server).
function M.new(deps)
  local s = { state = 'waiting', inbox = {}, sent = 0 }
  local io = deps.io

  local function decode(text)
    local ok, value = pcall(deps.decode, text)
    if ok and type(value) == 'table' then return value end
  end

  function s:start(clock)
    self.askedAt, self.helloAt = clock or 0, clock or 0
    deps.send('wwtcHello', tostring(M.PROTO))
  end

  -- Asks again until the server answers; gives up after WAIT_SECONDS (the career is then kept on this PC), but still
  -- asks now and then for a while.
  function s:tick(clock)
    clock = clock or 0
    if self.server or self.state == 'server' or not self.askedAt then return end
    local since = clock - self.askedAt
    if self.state == 'waiting' and since > M.WAIT_SECONDS then self.state, self.dir = 'local', M.LOCAL end
    local every = self.state == 'waiting' and M.HELLO_EVERY or M.LATE_EVERY
    if since <= M.LATE_FOR and clock - (self.helloAt or self.askedAt) >= every then
      self.helloAt = clock
      deps.send('wwtcHello', tostring(M.PROTO))
    end
  end

  function s:ready() return self.state ~= 'waiting' end
  function s:directory() return self.dir end

  local function keys()
    local ok, present = pcall(io.exists, M.KEYS)
    local list = ok and present and select(2, pcall(io.read, M.KEYS)) or nil
    return type(list) == 'table' and list or {}
  end

  function s:receive(event, data)
    if event == 'wwtcServer' then
      local d = decode(data)
      if not d or tonumber(d.v) ~= M.PROTO or not validId(d.server) or type(d.season) ~= 'number'
          or d.season < 1 or d.season ~= math.floor(d.season) then return false end
      -- Asked more than once, the server answers each time: the game joins once.
      if self.server then return true end
      self.server, self.season = d.server, d.season
      local key = keys()[d.server]
      deps.send('wwtcJoin', deps.encode({ v = M.PROTO, key = validId(key) and key or nil, build = M.BUILD }))
      return true
    elseif event == 'wwtcCareer' then
      if not self.server then return false end
      local text = M.receive(self.inbox, data)
      local d = text and decode(text)
      if not d or not validId(d.key) or d.season ~= self.season then return false end
      -- The key is kept first: losing it loses the career on a guest's next join.
      local list = keys()
      if list[self.server] ~= d.key then
        list[self.server] = d.key
        pcall(io.mkdir, M.ROOT)
        pcall(io.write, M.KEYS, list)
      end
      local dir = M.ROOT .. self.server .. '/season-' .. tostring(self.season) .. '/'
      pcall(io.mkdir, dir)
      -- The server's career replaces whatever this PC kept of it; none on the server means a new career.
      for _, slot in ipairs({ 'save-a.json', 'save-b.json' }) do
        if io.remove then pcall(io.remove, dir .. slot) end
      end
      if type(d.save) == 'table' then pcall(io.write, dir .. 'save-a.json', d.save) end
      self.key, self.dir, self.state = d.key, dir, 'server'
      return true
    elseif event == 'wwtcShip' then
      -- Ship Day: the ship in port and its containers' states (checked by shipday.clean in the game).
      local d = decode(data)
      if not d then return false end
      self.ship = d
      return true
    elseif event == 'wwtcClaimed' then
      -- The server's answer to a claim: { ship, n, ok, why }.
      local d = decode(data)
      if not d then return false end
      self.claimed = d
      return true
    elseif event == 'wwtcSaveNow' then
      -- The server restarts for an update soon: the game saves now (core.lua).
      local d = decode(data)
      if not d then return false end
      self.restartIn = type(d.seconds) == 'number' and d.seconds or nil
      return true
    elseif event == 'wwtcPlayers' then
      -- Everyone else on the server, by name and town, for Relocate to a player.
      local d = decode(data)
      if not d or type(d.players) ~= 'table' then return false end
      self.players = M.cleanPlayers(d.players)
      return true
    elseif event == 'wwtcLocate' then
      -- Someone wants to relocate to this player: the game answers with here() (core.lua).
      local d = decode(data)
      if not d or type(d.ask) ~= 'number' then return false end
      self.locate = { ask = d.ask, name = M.cleanText(d.name, 32) or 'A trucker' }
      return true
    elseif event == 'wwtcBases' then
      -- Every base of operations on the server, for the circles (magnate.lua).
      local d = decode(data)
      if not d or type(d.bases) ~= 'table' then return false end
      self.bases = M.cleanBases(d.bases)
      return true
    elseif event == 'wwtcBaseClaimed' then
      -- The answer to claimBase(): { ok, why, by, town }.
      local d = decode(data)
      if not d then return false end
      self.baseClaimed = { ok = d.ok == true, why = M.cleanText(d.why, 20), by = M.cleanText(d.by, 32), town = M.cleanText(d.town, 40) }
      return true
    elseif event == 'wwtcCommission' then
      -- Commission owed to this player's base: { id, amount, jobs, by }, added to the money in core.lua.
      local d = decode(data)
      if not d then return false end
      local id, amount = tonumber(d.id), tonumber(d.amount)
      if not id or id < 1 or id ~= math.floor(id) or not amount or amount < 0 or amount > 1000000 then return false end
      self.commission = { id = id, amount = math.floor(amount), jobs = math.max(1, math.floor(tonumber(d.jobs) or 1)),
        by = M.cleanText(d.by, 32) }
      return true
    elseif event == 'wwtcFound' then
      -- The answer to find(): the other player's spot, or why not.
      local d = decode(data)
      if not d then return false end
      self.found = d
      return true
    elseif event == 'wwtcSaved' then
      local d = decode(data)
      if not d then return false end
      if d.ok == true then self.saveError, self.savedGeneration = nil, d.generation
      else self.saveError = type(d.why) == 'string' and d.why:sub(1, 40) or 'refused' end
      return true
    end
    return false
  end

  -- Sends a save to the server, after the game wrote it here.
  function s:push(save)
    if self.state ~= 'server' then return false end
    local ok, text = pcall(deps.encode, save)
    if not ok or type(text) ~= 'string' then return false end
    self.sent = self.sent + 1
    for _, frame in ipairs(M.frames(self.sent, text)) do deps.send('wwtcSave', frame) end
    return true
  end

  -- Ship Day: asks for a container, gives one back (an abandoned job), and says one was delivered.
  local function shipEvent(event, body)
    if s.state ~= 'server' then return false end
    body.v = M.PROTO
    local ok, text = pcall(deps.encode, body)
    if not ok or type(text) ~= 'string' then return false end
    deps.send(event, text)
    return true
  end
  function s:claim(ship, n) return shipEvent('wwtcClaim', { ship = ship, n = n }) end
  function s:release(ship, n) return shipEvent('wwtcRelease', { ship = ship, n = n }) end
  -- The server page: where the player is (a town, never exact coordinates) and what they're doing, and each delivery.
  function s:where(t) return shipEvent('wwtcWhere', t) end
  function s:delivered(t) return shipEvent('wwtcDelivered', t) end
  -- Relocate to a player: asks where player id is, and answers the same question about this player.
  function s:find(id) return shipEvent('wwtcFind', { to = id }) end
  function s:here(t) return shipEvent('wwtcHere', t) end
  -- Whether other players may relocate to this one: yes unless turned off, kept on this PC for every server.
  function s:findable()
    if self.findableKept == nil then
      local ok, present = pcall(io.exists, M.PREFS)
      local prefs = ok and present and select(2, pcall(io.read, M.PREFS)) or nil
      self.findableKept = not (type(prefs) == 'table' and prefs.findable == false)
    end
    return self.findableKept
  end
  function s:setFindable(on)
    self.findableKept = on == true
    pcall(io.mkdir, M.ROOT)
    pcall(io.write, M.PREFS, { findable = self.findableKept })
    return self.findableKept
  end
  -- A base of operations: asks the server whether this town is free (one base a town, 10 km apart).
  function s:claimBase(t) return shipEvent('wwtcBaseClaim', t) end
  function s:shipDelivered(ship, n, town, pay, ends) return shipEvent('wwtcShipDone', { ship = ship, n = n, town = town, pay = pay, ends = ends }) end
  return s
end

-- The career store for a session: the usual two save slots, in the session's folder. Loading waits for the server
-- ('mp_waiting'), and every save is also sent to the server.
function M.store(session, io)
  local inner
  local store = { blocked = true }
  function store:load()
    if not session:ready() then
      self.blocked = true
      return nil, 'mp_waiting'
    end
    inner = persistence.new(io, session:directory())
    local save, why = inner:load()
    self.blocked = inner.blocked
    return save, why
  end
  function store:save(candidate)
    if not inner then return nil, 'storage_locked' end
    local saved, why = inner:save(candidate)
    if saved then session:push(saved) end
    return saved, why
  end
  return store
end

-- The game's side: whether this is a BeamMP session, and BeamMP's own sending and event handlers.
function M.game()
  local g = {}
  function g.inSession()
    local net = rawget(_G, 'MPCoreNetwork')
    if type(net) ~= 'table' or type(net.isMPSession) ~= 'function' then return false end
    local ok, on = pcall(net.isMPSession)
    return ok and on == true and type(rawget(_G, 'TriggerServerEvent')) == 'function'
  end
  function g.send(event, text) TriggerServerEvent(event, text) end
  -- Registers handler(event, data) for the server's events, once.
  local listening = false
  function g.listen(handler)
    if listening or type(rawget(_G, 'AddEventHandler')) ~= 'function' then return listening end
    for _, event in ipairs({ 'wwtcServer', 'wwtcCareer', 'wwtcSaved', 'wwtcShip', 'wwtcClaimed', 'wwtcSaveNow',
        'wwtcPlayers', 'wwtcLocate', 'wwtcFound', 'wwtcBases', 'wwtcBaseClaimed', 'wwtcCommission' }) do
      AddEventHandler(event, function(data) handler(event, data) end, 'earthFreight')
    end
    listening = true
    return true
  end
  return g
end

return M
