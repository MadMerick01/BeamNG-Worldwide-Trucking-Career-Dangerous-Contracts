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
}
M.KEYS = M.ROOT .. 'keys.json'
M.LOCAL = M.ROOT .. 'local/'

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
    self.askedAt = clock or 0
    deps.send('wwtcHello', tostring(M.PROTO))
  end

  -- Gives up on the server after WAIT_SECONDS: its career is then kept on this PC.
  function s:tick(clock)
    if self.state == 'waiting' and self.askedAt and (clock or 0) - self.askedAt > M.WAIT_SECONDS then
      self.state, self.dir = 'local', M.LOCAL
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
      self.server, self.season = d.server, d.season
      local key = keys()[d.server]
      deps.send('wwtcJoin', deps.encode({ v = M.PROTO, key = validId(key) and key or nil }))
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
    for _, event in ipairs({ 'wwtcServer', 'wwtcCareer', 'wwtcSaved' }) do
      AddEventHandler(event, function(data) handler(event, data) end, 'earthFreight')
    end
    listening = true
    return true
  end
  return g
end

return M
