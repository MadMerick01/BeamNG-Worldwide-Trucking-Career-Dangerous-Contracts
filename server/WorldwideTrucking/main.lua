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
--   server -> game  wwtcShip   '{"v","ship","name","port","containers","left","taken"}'  Ship Day: the ship in port
--   game -> server  wwtcClaim  '{"v","ship","n"}'  asks for container n; answered by
--   server -> game  wwtcClaimed '{"v","ship","n","ok","why"}'
--   game -> server  wwtcRelease '{"v","ship","n"}'  gives it back (job abandoned)
--   game -> server  wwtcShipDone '{"v","ship","n","town","pay"}'  delivered; announced in chat
-- A frame is 'v|id|i|n|piece': piece i of n of message id. The server keeps the save's own JSON text as it came, so
-- nothing about it is rounded or reordered on the way through.
--
-- This version keeps careers and checks the simple things (the save's shape, money a whole number, saves arriving in
-- order) and writes every change of money to a ledger. It does not yet work out what a delivery should pay.
local W = {}

-- Ship Day: every SHIP_EVERY_HOURS a ship docks at the next port on this list, carrying SHIP_CONTAINERS containers.
-- The first docks at SHIP_START (this PC's local time). Players are sent to the town nearest the coordinates, so a
-- point just off the coast is still safe, but keep each one on the port's land side. Add, remove or reorder ports
-- freely; set SHIP_CONTAINERS to 0 to turn Ship Day off.
W.SHIP_START = { year = 2026, month = 11, day = 8, hour = 20 }
W.SHIP_EVERY_HOURS = 72
W.SHIP_CONTAINERS = 20
W.PORTS = {
  { id = 'valparaiso', name = 'Valparaíso', region = 'Chile', latitude = -33.0458, longitude = -71.6197 },
  { id = 'kotor', name = 'Kotor', region = 'Montenegro', latitude = 42.4247, longitude = 18.7712 },
  { id = 'hobart', name = 'Hobart', region = 'Tasmania, Australia', latitude = -42.8821, longitude = 147.3272 },
  { id = 'reykjavik', name = 'Reykjavík', region = 'Iceland', latitude = 64.1466, longitude = -21.9426 },
  { id = 'rio', name = 'Rio de Janeiro', region = 'Brazil', latitude = -22.8960, longitude = -43.1810 },
  { id = 'hongkong', name = 'Hong Kong', region = 'China', latitude = 22.3570, longitude = 114.1270 },
  { id = 'capetown', name = 'Cape Town', region = 'South Africa', latitude = -33.9249, longitude = 18.4241 },
  { id = 'vancouver', name = 'Vancouver', region = 'British Columbia, Canada', latitude = 49.2870, longitude = -123.1110 },
  { id = 'naples', name = 'Naples', region = 'Italy', latitude = 40.8400, longitude = 14.2520 },
  { id = 'wellington', name = 'Wellington', region = 'New Zealand', latitude = -41.2865, longitude = 174.7762 },
  { id = 'cabo', name = 'Cabo San Lucas', region = 'Baja California Sur, Mexico', latitude = 22.8905, longitude = -109.9167 },
  { id = 'tromso', name = 'Tromsø', region = 'Arctic Norway', latitude = 69.6492, longitude = 18.9553 },
  { id = 'stgeorges', name = "St George's", region = 'Grenada', latitude = 12.0561, longitude = -61.7486 },
  { id = 'anchorage', name = 'Anchorage', region = 'Alaska, USA', latitude = 61.2181, longitude = -149.9003 },
  { id = 'botany', name = 'Port Botany', region = 'Sydney, Australia', latitude = -33.9711, longitude = 151.2131 },
}
W.SHIP_NAMES = { 'MV Pacific Star', 'MV Southern Cross', 'MV Northern Light', 'MV Cape Runner', 'MV Ocean Pride',
  'MV Trade Wind', 'MV Iron Gull', 'MV Long Haul' }
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
--      account(pid) -> BeamMP account id or nil (a guest), name(pid) -> text, print(text),
--      clock() -> seconds (os.time), epoch(date table) -> seconds, chat(pid or -1 for everyone, text)

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
  W.shipStart = env.epoch and env.epoch(W.SHIP_START) or nil
  W.loadClaims()
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
  W.shipTick()
  W.sendShip(pid)
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


-- ----- Ship Day ---------------------------------------------------------------------------------------------------
-- The ship in port at a time (seconds, as os.time): its number (1, 2, ...), port, name and the seconds until the next.
function W.shipAt(now)
  local period = W.SHIP_EVERY_HOURS * 3600
  local first = W.shipStart or now
  local number = math.max(1, math.floor((now - first) / period) + 1)
  local port = W.PORTS[(number - 1) % #W.PORTS + 1]
  local name = W.SHIP_NAMES[(number - 1) % #W.SHIP_NAMES + 1]
  local left = math.max(1, first + number * period - now)
  return { number = number, port = port, name = name, left = left }
end

local function shipsPath() return W.seasonDir() .. '/ships.json' end

-- The containers of the ship in port: n -> { key, name, delivered }. A new ship starts with none taken.
local function claimsFor(number)
  if W.claims and W.claims.ship == number then return W.claims end
  W.claims = { ship = number, boxes = {} }
  return W.claims
end

local function saveClaims()
  local list = {}
  for n, c in pairs(W.claims.boxes) do list[#list + 1] = { n = n, key = c.key, name = c.name, delivered = c.delivered } end
  W.env.write(shipsPath(), W.env.encode({ ship = W.claims.ship, boxes = list }))
end

function W.loadClaims()
  local text = W.env.read(shipsPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  W.claims = { ship = 0, boxes = {} }
  if ok and type(d) == 'table' and type(d.ship) == 'number' and type(d.boxes) == 'table' then
    W.claims.ship = d.ship
    for _, c in ipairs(d.boxes) do
      if type(c) == 'table' and type(c.n) == 'number' and W.validKey(c.key) then
        W.claims.boxes[c.n] = { key = c.key, name = tostring(c.name or ''), delivered = c.delivered == true }
      end
    end
  end
end

function W.shipOn() return W.SHIP_CONTAINERS > 0 and #W.PORTS > 0 end

-- The ship message for one player: which containers are taken, and which are theirs.
function W.shipMessage(pid)
  local ship = W.shipAt(W.env.clock())
  local claims = claimsFor(ship.number)
  local p = W.players[pid]
  local taken = {}
  for n, c in pairs(claims.boxes) do
    taken[#taken + 1] = { n = n, state = c.delivered and 'delivered' or 'taken', mine = p ~= nil and c.key == p.key, by = c.name }
  end
  table.sort(taken, function(a, b) return a.n < b.n end)
  local port = ship.port
  return W.env.encode({ v = W.PROTO, ship = ship.number, name = ship.name, containers = W.SHIP_CONTAINERS,
    left = ship.left, taken = taken,
    port = { id = port.id, name = port.name, region = port.region, latitude = port.latitude, longitude = port.longitude } })
end

function W.sendShip(pid)
  if not W.shipOn() then return end
  local p = W.players[pid]
  if p and p.key then W.env.send(pid, 'wwtcShip', W.shipMessage(pid)) end
end

function W.sendShipToAll()
  for pid, p in pairs(W.players) do if p.key then W.sendShip(pid) end end
end

local function say(text) if W.env.chat then W.env.chat(-1, text) end end

-- Every few seconds: a new ship docks when it's time, and everyone hears about it.
function W.shipTick()
  if not W.shipOn() then return end
  local ship = W.shipAt(W.env.clock())
  if W.claims and W.claims.ship == ship.number then return end
  local first = W.claims == nil or W.claims.ship == 0
  claimsFor(ship.number)
  saveClaims()
  W.env.print(string.format('[Trucking] ship %d, %s, docked at %s', ship.number, ship.name, ship.port.name))
  if not first then
    say(string.format('Ship Day! The %s has docked at %s, %s with %d containers. Press Go to port on the Town tab.',
      ship.name, ship.port.name, ship.port.region, W.SHIP_CONTAINERS))
  end
  W.sendShipToAll()
end

local function shipRequest(pid, data)
  local p = W.players[pid]
  if not p or not p.key or not W.shipOn() then return nil end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' or type(d.n) ~= 'number' or type(d.ship) ~= 'number' then return nil end
  return p, d
end

-- A player asks for a container: theirs if it's free (or already theirs), on the ship in port now.
function W.onClaim(pid, data)
  local p, d = shipRequest(pid, data)
  if not p then return end
  local ship = W.shipAt(W.env.clock())
  local claims = claimsFor(ship.number)
  local n = d.n
  local why
  if d.ship ~= ship.number then why = 'sailed'
  elseif n < 1 or n > W.SHIP_CONTAINERS or n ~= math.floor(n) then why = 'no_such_container'
  elseif claims.boxes[n] and claims.boxes[n].key ~= p.key then why = 'taken' end
  -- One container at a time: a player's own earlier claim that isn't delivered is given back.
  if not why then
    for other, c in pairs(claims.boxes) do
      if other ~= n and c.key == p.key and not c.delivered then claims.boxes[other] = nil end
    end
    claims.boxes[n] = { key = p.key, name = tostring(p.name or ''), delivered = false }
    saveClaims()
  end
  W.env.send(pid, 'wwtcClaimed', W.env.encode({ v = W.PROTO, ship = d.ship, n = n, ok = why == nil, why = why }))
  if not why then W.sendShipToAll() end
end

-- A player gives a container back (an abandoned job): it's free for someone else.
function W.onRelease(pid, data)
  local p, d = shipRequest(pid, data)
  if not p then return end
  local claims = claimsFor(W.shipAt(W.env.clock()).number)
  local c = d.ship == claims.ship and claims.boxes[d.n]
  if c and c.key == p.key and not c.delivered then
    claims.boxes[d.n] = nil
    saveClaims()
    W.sendShipToAll()
  end
end

-- A container delivered: everyone hears about it.
function W.onShipDone(pid, data)
  local p, d = shipRequest(pid, data)
  if not p then return end
  local ship = W.shipAt(W.env.clock())
  local claims = claimsFor(ship.number)
  local c = d.ship == claims.ship and claims.boxes[d.n]
  if c and c.key == p.key and not c.delivered then
    c.delivered = true
    saveClaims()
    W.sendShipToAll()
  end
  local town = type(d.town) == 'string' and d.town:gsub('%c', ' '):sub(1, 40) or 'inland'
  local pay = type(d.pay) == 'number' and d.pay >= 0 and math.floor(d.pay) or nil
  local from = d.ship == ship.number and ship.port.name or 'the docks'
  say(string.format('%s delivered container %d from %s to %s%s.', tostring(p.name), math.floor(d.n), from, town,
    pay and (' for $' .. tostring(pay)) or ''))
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
    clock = os.time, epoch = function(t) return os.time(t) end,
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
  WWTC_onClaim = guarded('claim', W.onClaim)
  WWTC_onRelease = guarded('release', W.onRelease)
  WWTC_onShipDone = guarded('ship delivered', W.onShipDone)
  WWTC_onShipTimer = guarded('ship', W.shipTick)
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
  MP.RegisterEvent('wwtcClaim', 'WWTC_onClaim')
  MP.RegisterEvent('wwtcRelease', 'WWTC_onRelease')
  MP.RegisterEvent('wwtcShipDone', 'WWTC_onShipDone')
  MP.RegisterEvent('WWTC_shipTimer', 'WWTC_onShipTimer')
  if MP.CreateEventTimer then MP.CreateEventTimer('WWTC_shipTimer', 15000) end
  WWTC_onShipTimer()
  MP.RegisterEvent('onChatMessage', 'WWTC_onChat')
  MP.RegisterEvent('onConsoleInput', 'WWTC_onConsole')
  print(string.format('[Trucking] plugin loaded: season %d, careers in %s (type "trucking" to list players)',
    W.SEASON, W.seasonDir()))
end

return W
