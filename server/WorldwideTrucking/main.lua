-- Worldwide Trucking Career's BeamMP server plugin (Resources/Server/WorldwideTrucking/main.lua; BeamMP server Lua 5.3).
-- It sits next to BeamNG.Earth's own plugin and changes nothing of it.
--
-- It keeps every player's multiplayer career on this server: the same save document the game writes on a player's PC
-- in single player, kept here per season and handed back when they join. Players are known by a career key, a random
-- id this server gives each player the first time and their game keeps (one per server). A signed-in BeamMP player is
-- also known by their account, so their career follows them to another PC; a guest's stays with the PC they started on.
--
-- The game talks to it with these events (each message is one string; a long one comes in frames, see below):
--   game -> server  wwtcHello  'v'                         asks who this server is
--   server -> game  wwtcServer '{"v","server","season"}'   this server's id and season
--   game -> server  wwtcJoin   '{"v","key"}'              the game's key for this server, or none
--   server -> game  wwtcCareer frames of '{"v","key","season","save"}'  the player's key and career (save null: none)
--   game -> server  wwtcSave   frames of the save document (JSON), sent after every save in game
--   server -> game  wwtcSaved  '{"v","ok","generation","why"}'
-- A frame is 'v|id|i|n|piece': piece i of n of message id. The server keeps the save's own JSON text as it came, so
-- nothing about it is rounded or reordered on the way through.
--
-- This version keeps careers and checks the simple things (the save's shape, money a whole number, saves arriving in
-- order) and writes every change of money to a ledger. It does not yet work out what a delivery should pay.
local W = {}

-- ===== Settings: edit here, then restart the BeamMP server ========================================================
-- The season. Raise it by one to start everyone over on their next join: rusty starter car and the starting money.
-- The old season's careers stay in their folder (careers/season-N), untouched.
W.SEASON = 1
-- Sent in chat to each player as they finish joining, one message per line. Anyone can type !hud to see them again.
-- Change the lines as you like, or make it {} to send nothing.
W.WELCOME = {
  'Welcome to the Worldwide Trucking Career!',
  'No trucking HUD on screen? Press Esc > System > HUD Apps > .Earth (edit layout) > + Add app.',
  'Pick "BeamNG Worldwide Trucking Career: Dangerous Contracts" near the bottom, press + Add to layout, then Save.',
  'Your career is kept on this server. Press Save in the HUD to keep your progress. Type !hud to see this again.',
}
-- ==================================================================================================================

W.DIR = 'Resources/Server/WorldwideTrucking'
W.PROTO = 1
W.CHUNK = 20000                    -- characters of a message per frame
W.SAVE_MAX = 4 * 1024 * 1024       -- a save bigger than this is refused (a normal one is tens of KB)
W.MAX_BALANCE = 9007199254740991

W.players = {}                     -- pid -> { key, name, account, inbox, balance }
W.accounts = {}                    -- BeamMP account id -> career key
W.serverId = nil
W.nextId = 0

-- ----- Pure helpers (no BeamMP below this line until the glue) ----------------------------------------------------

function W.validKey(k) return type(k) == 'string' and #k == 32 and not k:find('[^0-9a-f]') end

-- 32 hex characters from 16 random bytes; random(n) gives a whole number from 0 to n - 1.
function W.newKey(bytes)
  local out = {}
  for i = 1, 16 do out[i] = string.format('%02x', bytes(i) % 256) end
  return table.concat(out)
end

function W.seasonDir() return W.DIR .. '/careers/season-' .. tostring(W.SEASON) end
function W.careerPath(key) return W.seasonDir() .. '/' .. key .. '.json' end

-- Splits text into frames of at most size characters.
function W.frames(id, text, size)
  size = size or W.CHUNK
  local n = math.max(1, math.ceil(#text / size))
  local out = {}
  for i = 1, n do
    out[i] = table.concat({ tostring(W.PROTO), tostring(id), tostring(i), tostring(n), text:sub((i - 1) * size + 1, i * size) }, '|')
  end
  return out
end

-- Adds a frame to an inbox. Returns the whole message once its last piece is in, or nil (more to come, or a bad
-- frame, which starts the inbox over). A new message id drops an unfinished one.
function W.receive(inbox, frame, maxBytes)
  if type(frame) ~= 'string' then return nil end
  local v, id, i, n, piece = frame:match('^(%d+)|(%d+)|(%d+)|(%d+)|(.*)$')
  v, i, n = tonumber(v), tonumber(i), tonumber(n)
  if v ~= W.PROTO or not i or not n or n < 1 or i < 1 or i > n or n * W.CHUNK > (maxBytes or W.SAVE_MAX) + W.CHUNK then
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

local function wholeNumber(n, minimum)
  return type(n) == 'number' and n == n and n >= minimum and n <= W.MAX_BALANCE and n == math.floor(n)
end

-- Whether a save the game sent can be kept, given the one kept now (or nil). Returns true, or nil and why. The game
-- checks the whole document itself when it loads it; this checks what the server relies on.
function W.checkSave(save, previous)
  if type(save) ~= 'table' then return nil, 'not_a_save' end
  if type(save.schemaVersion) ~= 'number' then return nil, 'not_a_save' end
  if not wholeNumber(save.generation, 1) then return nil, 'not_a_save' end
  if type(save.progression) ~= 'table' or not wholeNumber(save.progression.balance, 0) then return nil, 'bad_money' end
  if type(previous) == 'table' and wholeNumber(previous.generation, 0) and save.generation <= previous.generation then
    return nil, 'out_of_date'
  end
  return true
end

-- One ledger line: when, whose, their name, money before and after, and the save's generation. Tabs and line breaks
-- in a name are made spaces.
function W.ledgerLine(time, key, name, before, after, generation)
  name = tostring(name or ''):gsub('[%c]', ' ')
  return table.concat({ time, key, name, tostring(before or ''), tostring(after), tostring(generation) }, '\t') .. '\n'
end

-- ----- The server's state, with storage and sending given to it (env), so tests can run it -----------------------
-- env: read(path) -> text|nil, write(path, text) -> bool, append(path, text), mkdir(path), send(pid, event, text),
--      encode(table) -> text, decode(text) -> table, bytes(i) -> number, now() -> 'YYYY-MM-DDTHH:MM:SSZ',
--      account(pid) -> BeamMP account id or nil (a guest), name(pid) -> text, print(text)

function W.start(env)
  W.env = env
  env.mkdir(W.DIR)
  env.mkdir(W.DIR .. '/careers')
  env.mkdir(W.seasonDir())
  -- (Nothing is decoded that isn't there: BeamMP's JsonDecode logs an error for empty text, as on a first start.)
  local server = env.read(W.DIR .. '/server.json')
  local ok, info = false, nil
  if server and server ~= '' then ok, info = pcall(env.decode, server) end
  if ok and type(info) == 'table' and W.validKey(info.id) then
    W.serverId = info.id
  else
    W.serverId = W.newKey(env.bytes)
    env.write(W.DIR .. '/server.json', env.encode({ id = W.serverId }))
  end
  local accountsText = env.read(W.DIR .. '/accounts.json')
  local okA, accounts = false, nil
  if accountsText and accountsText ~= '' then okA, accounts = pcall(env.decode, accountsText) end
  W.accounts = {}
  if okA and type(accounts) == 'table' then
    for id, key in pairs(accounts) do if W.validKey(key) then W.accounts[tostring(id)] = key end end
  end
end

local function player(pid)
  local p = W.players[pid]
  if not p then p = { inbox = {} }; W.players[pid] = p end
  return p
end

local function readSave(key)
  local text = W.env.read(W.careerPath(key))
  if not text then return nil, nil end
  local ok, save = pcall(W.env.decode, text)
  if not ok or type(save) ~= 'table' then return nil, nil end
  return text, save
end

function W.onHello(pid)
  player(pid)
  W.env.send(pid, 'wwtcServer', W.env.encode({ v = W.PROTO, server = W.serverId, season = W.SEASON }))
end

-- Finds the player's career key: their account's, else the one their game sent, else a new one.
function W.onJoin(pid, data)
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' or tonumber(d.v) ~= W.PROTO then return end
  local p = player(pid)
  local account = W.env.account(pid)
  local key = account and W.accounts[account] or (W.validKey(d.key) and d.key) or W.newKey(W.env.bytes)
  if account and W.accounts[account] ~= key then
    W.accounts[account] = key
    W.env.write(W.DIR .. '/accounts.json', W.env.encode(W.accounts))
  end
  p.key, p.account, p.name = key, account, W.env.name(pid)
  local text, save = readSave(key)
  p.balance = save and save.progression and save.progression.balance or nil
  W.nextId = W.nextId + 1
  local message = '{"v":' .. W.PROTO .. ',"key":"' .. key .. '","season":' .. W.SEASON .. ',"save":' .. (text or 'null') .. '}'
  for _, frame in ipairs(W.frames(W.nextId, message)) do W.env.send(pid, 'wwtcCareer', frame) end
  W.env.print(string.format('[Trucking] %s joined: %s, %s', tostring(p.name), account and 'signed in' or 'guest',
    save and ('balance $' .. tostring(save.progression.balance)) or 'new career'))
end

local function answer(pid, ok, generation, why)
  W.env.send(pid, 'wwtcSaved', W.env.encode({ v = W.PROTO, ok = ok, generation = generation, why = why }))
end

function W.onSave(pid, frame)
  local p = W.players[pid]
  if not p or not p.key then return end
  local text = W.receive(p.inbox, frame)
  if not text then return end
  if #text > W.SAVE_MAX then return answer(pid, false, nil, 'too_big') end
  local ok, save = pcall(W.env.decode, text)
  if not ok then return answer(pid, false, nil, 'not_a_save') end
  local _, previous = readSave(p.key)
  local fine, why = W.checkSave(save, previous)
  if not fine then
    W.env.print(string.format('[Trucking] save from %s refused: %s', tostring(p.name), why))
    return answer(pid, false, nil, why)
  end
  if not W.env.write(W.careerPath(p.key), text) then return answer(pid, false, nil, 'write_failed') end
  local before = previous and previous.progression and previous.progression.balance
  if before ~= save.progression.balance then
    W.env.append(W.seasonDir() .. '/ledger.tsv',
      W.ledgerLine(W.env.now(), p.key, p.name, before, save.progression.balance, save.generation))
  end
  p.balance = save.progression.balance
  answer(pid, true, save.generation)
end

function W.onLeave(pid) W.players[pid] = nil end

-- The welcome lines in chat, to a player who has just finished joining.
function W.welcome(pid)
  if not W.env.chat then return end
  for _, line in ipairs(W.WELCOME or {}) do W.env.chat(pid, tostring(line)) end
end

-- A chat message: !hud sends the welcome again, to that player only, and isn't shown to everyone. True: hide it.
function W.onChat(pid, message)
  if tostring(message or ''):lower():match('^%s*!hud%s*$') then
    W.welcome(pid)
    return true
  end
  return false
end

-- The 'trucking' command in the server window: who is on and their money at their last save.
function W.report()
  local lines = { string.format('[Trucking] season %d, %d player(s)', W.SEASON, (function()
    local n = 0
    for _, p in pairs(W.players) do if p.key then n = n + 1 end end
    return n
  end)()) }
  for _, p in pairs(W.players) do
    if p.key then
      lines[#lines + 1] = string.format('  %s (%s): %s', tostring(p.name), p.account and 'signed in' or 'guest',
        p.balance and ('$' .. tostring(p.balance)) or 'not saved yet')
    end
  end
  return table.concat(lines, '\n')
end

-- ----- BeamMP glue ------------------------------------------------------------------------------------------------
if MP and MP.RegisterEvent then
  local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local t = f:read('*a')
    f:close()
    return t
  end
  local entropy
  math.randomseed(os.time() + math.floor(os.clock() * 1000000))
  W.start({
    read = readFile,
    write = function(path, text)
      local tmp = path .. '.tmp'
      local f = io.open(tmp, 'wb')
      if not f then return false end
      f:write(text)
      f:close()
      os.remove(path)
      return os.rename(tmp, path) ~= nil
    end,
    append = function(path, text)
      local f = io.open(path, 'ab')
      if f then f:write(text); f:close() end
    end,
    mkdir = function(dir) if FS and FS.CreateDirectory then pcall(FS.CreateDirectory, dir) end end,
    send = function(pid, event, text) MP.TriggerClientEvent(pid, event, text) end,
    encode = Util.JsonEncode, decode = Util.JsonDecode,
    -- The system's random bytes where there are any (Linux), mixed with Lua's own random numbers.
    bytes = function(i)
      if i == 1 then
        local f = io.open('/dev/urandom', 'rb')
        entropy = f and f:read(16) or nil
        if f then f:close() end
      end
      local extra = entropy and #entropy >= i and entropy:byte(i) or 0
      return (math.random(0, 255) + extra) % 256
    end,
    now = function() return os.date('!%Y-%m-%dT%H:%M:%SZ') end,
    account = function(pid)
      local ok, ids = pcall(MP.GetPlayerIdentifiers, pid)
      local id = ok and type(ids) == 'table' and ids.beammp or nil
      if id ~= nil and tostring(id) ~= '' then return tostring(id) end
    end,
    name = function(pid) return MP.GetPlayerName(pid) end,
    chat = function(pid, text) MP.SendChatMessage(pid, text) end,
    print = print,
  })

  local function guarded(name, f)
    return function(...)
      local ok, err = pcall(f, ...)
      if not ok then print('[Trucking] ' .. name .. ': ' .. tostring(err)) end
    end
  end
  WWTC_onHello = guarded('hello', function(pid) W.onHello(pid) end)
  WWTC_onJoin = guarded('join', W.onJoin)
  WWTC_onSave = guarded('save', W.onSave)
  WWTC_onLeave = guarded('leave', W.onLeave)
  WWTC_onPlayerJoin = guarded('welcome', W.welcome)
  WWTC_onChat = function(pid, name, message)
    local ok, hide = pcall(W.onChat, pid, message)
    if ok and hide then return 1 end
  end
  WWTC_onConsole = function(text)
    if tostring(text):match('^%s*trucking%s*$') then return W.report() end
  end
  MP.RegisterEvent('wwtcHello', 'WWTC_onHello')
  MP.RegisterEvent('wwtcJoin', 'WWTC_onJoin')
  MP.RegisterEvent('wwtcSave', 'WWTC_onSave')
  MP.RegisterEvent('onPlayerDisconnect', 'WWTC_onLeave')
  MP.RegisterEvent('onPlayerJoin', 'WWTC_onPlayerJoin')
  MP.RegisterEvent('onChatMessage', 'WWTC_onChat')
  MP.RegisterEvent('onConsoleInput', 'WWTC_onConsole')
  print(string.format('[Trucking] plugin loaded: season %d, careers in %s (type "trucking" to list players)',
    W.SEASON, W.seasonDir()))
end

return W
