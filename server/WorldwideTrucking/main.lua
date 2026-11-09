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
--   game -> server  wwtcJoin   '{"v","key","build"}'      the game's key for this server, or none, and the mod's build
--                   (none from a copy older than this check, or not made by the release workflow)
--   server -> game  wwtcCareer frames of '{"v","key","season","save"}'  the player's key and career (save null: none)
--   game -> server  wwtcSave   frames of the save document (JSON), sent after every save in game
--   server -> game  wwtcSaved  '{"v","ok","generation","why"}'
--   server -> game  wwtcShip   '{"v","ship","name","port","containers","left","taken"}'  Ship Day: the ship in port
--   game -> server  wwtcClaim  '{"v","ship","n"}'  asks for container n; answered by
--   server -> game  wwtcClaimed '{"v","ship","n","ok","why"}'
--   game -> server  wwtcRelease '{"v","ship","n"}'  gives it back (job abandoned)
--   game -> server  wwtcShipDone '{"v","ship","n","town","pay"}'  delivered; announced in chat
--   server -> game  wwtcSaveNow '{"v","seconds"}'  the server restarts for an update soon: save now
--   server -> game  wwtcPlayers '{"v","players":[{"id","name","town","region","latitude","longitude","doing"}]}'
--                   everyone else on the server, by town (its centre), for Relocate to a player
--   game -> server  wwtcFind   '{"v","to"}'  asks to relocate to player 'to'; the server asks that player's game:
--   server -> game  wwtcLocate '{"v","ask","name"}'  someone (name) wants to relocate to you: where are you?
--   game -> server  wwtcHere   '{"v","ask","ok","latitude","longitude","heading","why"}'  ('off' or 'away' when not ok)
--   server -> game  wwtcFound  '{"v","to","name","ok","latitude","longitude","heading","why"}'  to the asker only
-- A frame is 'v|id|i|n|piece': piece i of n of message id. The server keeps the save's own JSON text as it came, so
-- nothing about it is rounded or reordered on the way through.
--
-- This version keeps careers and checks the simple things (the save's shape, money a whole number, saves arriving in
-- order) and writes every change of money to a ledger. It does not yet work out what a delivery should pay.
local W = {}

-- Ship Day: every SHIP_EVERY_HOURS (one a day) a ship docks at the next port on this list, carrying SHIP_CONTAINERS
-- containers (5, so they go quickly).
-- The first docks at SHIP_START (this PC's local time). Players are sent to the town nearest the coordinates, so a
-- point just off the coast is still safe, but keep each one on the port's land side. Add, remove or reorder ports
-- freely; set SHIP_CONTAINERS to 0 to turn Ship Day off.
W.SHIP_START = { year = 2026, month = 11, day = 8, hour = 20 }
W.SHIP_EVERY_HOURS = 24
W.SHIP_CONTAINERS = 5
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
-- The server page (GitHub Pages): every STATS_EVERY_SECONDS the server sends its stats (who's on and in which town,
-- Ship Day, the live feed, today's totals and the leaderboard) to status.json in STATS_REPO on GitHub. Make STATS_REPO
-- '' to send nothing. The GitHub token goes in github-token.txt next to this file, never in here. The stats are also
-- written to status.json next to this file.
W.STATS_REPO = 'MadMerick01/trucking-server-stats'
W.STATS_BRANCH = 'main'
W.STATS_EVERY_SECONDS = 180
-- Players must run this server's own build of the trucking mod. A player whose game runs an older copy (their own
-- download or BeamNG.Earth's Add-ons page, loaded instead of the one this server hands out) is sent off with a message
-- saying how to fix it. Make it false to let older copies play.
W.REQUIRE_LATEST = true
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

-- ----- The server page's stats --------------------------------------------------------------------------------------
-- Kept in careers/season-N/stats.json: when the season started, the leaderboard (by career key), the live feed and
-- today's totals. Only town names are ever kept or sent, never a player's position.
W.FEED_MAX = 30

local function clean(value, max)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value:sub(1, max or 60)
end

local function dollars(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return '$' .. out:gsub('^,', '')
end

local function statsPath() return W.seasonDir() .. '/stats.json' end

function W.loadStats()
  local text = W.env.read(statsPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  d = ok and type(d) == 'table' and d or {}
  W.stats = {
    started = type(d.started) == 'number' and d.started or W.env.clock(),
    board = type(d.board) == 'table' and d.board or {},
    feed = type(d.feed) == 'table' and d.feed or {},
    today = type(d.today) == 'table' and d.today or {},
  }
  if not d.started then W.saveStats() end
end

function W.saveStats()
  W.env.write(statsPath(), W.env.encode(W.stats))
  W.statsChanged = true
end

-- Today's totals start again at midnight (this PC's time).
local function today()
  local date = W.env.date and W.env.date() or ''
  local t = W.stats.today
  if t.date ~= date then
    t.date, t.deliveries, t.earned = date, 0, 0
  end
  return t
end

function W.feed(kind, text)
  table.insert(W.stats.feed, 1, { at = W.env.now(), kind = kind, text = text })
  while #W.stats.feed > W.FEED_MAX do table.remove(W.stats.feed) end
  W.saveStats()
end

local function boardEntry(p)
  local e = W.stats.board[p.key]
  if not e then e = { deliveries = 0, containers = 0 }; W.stats.board[p.key] = e end
  e.name = clean(p.name, 32) or e.name or 'A trucker'
  return e
end

-- A player's career came in (join) or was saved: their money and jobs done on the leaderboard.
function W.boardCareer(p, save)
  if not p or not p.key or type(save) ~= 'table' or type(save.progression) ~= 'table' then return end
  local e = boardEntry(p)
  if type(save.progression.balance) == 'number' then e.balance = save.progression.balance end
  if type(save.progression.jobsDone) == 'number' then e.deliveries = save.progression.jobsDone end
  W.saveStats()
end

-- Where a player is, from their game: a town (its centre) and what they're doing.
function W.onWhere(pid, data)
  local p = W.players[pid]
  if not p or not p.key then return end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' then return end
  local lat, lon = tonumber(d.latitude), tonumber(d.longitude)
  if not lat or not lon or math.abs(lat) > 90 or math.abs(lon) > 180 then lat, lon = nil, nil end
  p.where = { town = clean(d.town, 40), region = clean(d.region, 60), doing = clean(d.doing, 80),
    latitude = lat and math.floor(lat * 100 + 0.5) / 100, longitude = lon and math.floor(lon * 100 + 0.5) / 100 }
  W.statsChanged = true
end

local function payOf(value)
  local n = tonumber(value)
  if not n or n < 0 or n > 100000000 then return nil end
  return math.floor(n)
end

-- Counts a delivery for today and the leaderboard.
local function counted(p, pay, container)
  local t = today()
  t.deliveries = (t.deliveries or 0) + 1
  t.earned = (t.earned or 0) + (pay or 0)
  local e = boardEntry(p)
  e.deliveries = (e.deliveries or 0) + 1
  if container then e.containers = (e.containers or 0) + 1 end
end

-- A delivery in the game (not a Ship Day container: those come as wwtcShipDone).
function W.onDelivered(pid, data)
  local p = W.players[pid]
  if not p or not p.key then return end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' then return end
  local pay = payOf(d.pay)
  local name, what, from, to = clean(p.name, 32) or 'A trucker', clean(d.what, 40), clean(d.from, 40), clean(d.to, 40)
  local paid = pay and (' for ' .. dollars(pay)) or ''
  local text
  if d.kind == 'contract' then text = name .. ' finished the ' .. (to or 'dangerous') .. ' dangerous contract' .. paid .. '.'
  elseif d.kind == 'drop' then text = name .. ' made an off-road drop' .. (what and (' of ' .. what) or '') .. paid .. '.'
  elseif d.kind == 'beacon' then text = name .. ' dropped off a package, no questions asked' .. paid .. '.'
  else
    text = name .. ' delivered ' .. (what or 'a load') .. (from and (' from ' .. from) or '') .. (to and (' to ' .. to) or '') .. paid .. '.'
  end
  counted(p, pay, false)
  W.feed('delivery', text)
end

-- The stats file the page reads.
function W.status()
  local now = W.env.clock()
  local players = {}
  for _, p in pairs(W.players) do
    if p.key then
      local w = p.where or {}
      players[#players + 1] = { name = clean(p.name, 32) or 'A trucker', town = w.town, region = w.region,
        latitude = w.latitude, longitude = w.longitude, doing = w.doing }
    end
  end
  table.sort(players, function(a, b) return a.name < b.name end)
  local board, truckers = {}, 0
  for _, e in pairs(W.stats.board) do
    truckers = truckers + 1
    board[#board + 1] = { name = e.name, balance = e.balance or 0, deliveries = e.deliveries or 0, containers = e.containers or 0 }
  end
  table.sort(board, function(a, b) if a.balance ~= b.balance then return a.balance > b.balance end return a.name < b.name end)
  while #board > 20 do table.remove(board) end
  local t = today()
  local ship
  if W.shipOn() then
    local at = W.shipAt(now)
    local taken = 0
    if W.claims and W.claims.ship == at.number then
      for n in pairs(W.claims.boxes) do if n <= W.SHIP_CONTAINERS then taken = taken + 1 end end
    end
    local nextPort = W.PORTS[at.number % #W.PORTS + 1]
    ship = { number = at.number, name = at.name, port = at.port.name, region = at.port.region,
      latitude = at.port.latitude, longitude = at.port.longitude, containers = W.SHIP_CONTAINERS,
      left = math.max(0, W.SHIP_CONTAINERS - taken), sailsAt = os.date('!%Y-%m-%dT%H:%M:%SZ', now + at.left),
      next = { port = nextPort.name, region = nextPort.region } }
  end
  return {
    version = 1, updated = W.env.now(),
    server = { name = W.env.setting and W.env.setting('name') or nil, online = true,
      maxPlayers = W.env.setting and W.env.setting('maxPlayers') or nil },
    season = { number = W.SEASON, day = math.floor((now - W.stats.started) / 86400) + 1, truckers = truckers },
    today = { deliveries = t.deliveries or 0, earned = t.earned or 0 },
    ship = ship, players = players, feed = W.stats.feed, leaderboard = board,
  }
end

-- ----- Sending the stats to GitHub ----------------------------------------------------------------------------------
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function W.base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d1, d2, d3, d4 = math.floor(n / 262144), math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
      .. (b and B64:sub(d3 + 1, d3 + 1) or '=') .. (c and B64:sub(d4 + 1, d4 + 1) or '=')
  end
  return table.concat(out)
end

local function readToken()
  local text = W.env.read(W.DIR .. '/github-token.txt')
  local token = text and text:match('^%s*([%w_]+)%s*$')
  return token
end

local function curl(args)
  local auth = W.DIR .. '/.github-auth.txt'
  return W.env.run('curl -s -m 20 -H "@' .. auth .. '" -H "Accept: application/vnd.github+json" '
    .. '-H "User-Agent: worldwide-trucking-server" ' .. args)
end

local function decoded(text)
  if type(text) ~= 'string' or text == '' then return nil end
  local ok, d = pcall(W.env.decode, text)
  return ok and type(d) == 'table' and d or nil
end

-- Sends status.json to STATS_REPO. Returns true when GitHub took it.
function W.pushStats(text)
  if not W.env.run or not W.STATS_REPO or not W.STATS_REPO:match('^[%w._-]+/[%w._-]+$') then return false end
  local token = readToken()
  if not token then
    if not W.tokenWarned then W.env.print('[Trucking] server page: put a GitHub token in github-token.txt to send stats') end
    W.tokenWarned = true
    return false
  end
  W.env.write(W.DIR .. '/.github-auth.txt', 'Authorization: Bearer ' .. token)
  local url = 'https://api.github.com/repos/' .. W.STATS_REPO .. '/contents/status.json'
  local branch = W.STATS_BRANCH:gsub('[^%w._/-]', '')
  for attempt = 1, 2 do
    if not W.statsSha then
      local found = decoded(curl('"' .. url .. '?ref=' .. branch .. '"'))
      W.statsSha = found and found.sha or nil
    end
    local body = { message = 'Server stats', content = W.base64(text), branch = branch, sha = W.statsSha }
    W.env.write(W.DIR .. '/.github-body.json', W.env.encode(body))
    local answer = decoded(curl('-X PUT --data-binary "@' .. W.DIR .. '/.github-body.json" "' .. url .. '"'))
    if answer and type(answer.content) == 'table' and answer.content.sha then
      W.statsSha = answer.content.sha
      if W.pushFailed then W.env.print('[Trucking] server page: sending stats again') end
      W.pushFailed = false
      return true
    end
    -- Someone else changed the file, or it was never read: read it again and try once more.
    W.statsSha = nil
    if attempt == 2 and not W.pushFailed then
      W.env.print('[Trucking] server page: GitHub did not take the stats: ' .. tostring(answer and answer.message or 'no answer'))
      W.pushFailed = true
    end
  end
  return false
end

-- Every timer tick: writes status.json here, and sends it every STATS_EVERY_SECONDS (every 10 minutes even when
-- nothing changed, so the page knows the server is on).
function W.statsTick()
  local now = W.env.clock()
  local due = now - (W.statsSentAt or -math.huge) >= (W.statsChanged and W.STATS_EVERY_SECONDS or 600)
  if not due then return end
  local text = W.env.encode(W.status())
  W.env.write(W.DIR .. '/status.json', text)
  W.statsSentAt, W.statsChanged = now, false
  W.pushStats(text)
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
  -- The build of the mod this server hands out, written by the release workflow (tools/package.py). None: a copy
  -- not built by it, which checks no player's build.
  local build = tonumber((env.read(W.DIR .. '/build.txt') or ''):match('^%s*(%d+)%s*$'))
  W.BUILD = build and build > 0 and build or nil
  W.loadClaims()
  W.loadStats()
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

-- Whether a game's build of the mod is older than this server's: no build at all is a copy from before the check.
function W.outdated(build)
  if not W.REQUIRE_LATEST or not W.BUILD then return false end
  build = tonumber(build)
  return build == nil or build < W.BUILD
end

-- Sends off a player whose game runs an older copy of the mod, saying why and how to fix it. Their career is not
-- loaded, so nothing of it changes.
function W.turnAway(pid, build)
  local have = tonumber(build) and ('build ' .. math.floor(tonumber(build))) or 'an old build'
  local why = string.format('Your Worldwide Trucking mod is out of date (%s; this server runs build %d). Turn off your'
    .. ' own copy of it in the Mod Manager and on the BeamNG.Earth Add-ons page, close BeamNG completely and join'
    .. ' again: the server then gives you the right one. Your career is safe.', have, W.BUILD)
  W.env.chat(pid, why)
  W.env.print(string.format('[Trucking] %s sent off: their game runs %s of the mod, this server build %d',
    tostring(W.env.name(pid)), have, W.BUILD))
  if W.env.kick then W.env.kick(pid, why) end
end

-- Finds the player's career key: their account's, else the one their game sent, else a new one.
function W.onJoin(pid, data)
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' or tonumber(d.v) ~= W.PROTO then return end
  if W.outdated(d.build) then return W.turnAway(pid, d.build) end
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
  W.sendPlayersToAll()
  W.shipTick()
  W.sendShip(pid)
  if save then W.boardCareer(p, save) end
  W.feed('join', (clean(p.name, 32) or 'A trucker') .. ' joined the server.')
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
  W.boardCareer(p, save)
  answer(pid, true, save.generation)
end

function W.onLeave(pid)
  local was = W.players[pid]
  if was then W.statsChanged = true end
  W.players[pid] = nil
  for n, a in pairs(W.asks or {}) do
    if a.from == pid or a.to == pid then W.asks[n] = nil end
  end
  if was and was.key and W.sendPlayersToAll then W.sendPlayersToAll() end
end

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
    W.feed('ship', string.format('Ship Day! The %s has docked at %s, %s with %d containers.',
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
  local fresh = c and c.key == p.key and not c.delivered
  if fresh then
    c.delivered = true
    saveClaims()
    W.sendShipToAll()
  end
  local town = type(d.town) == 'string' and d.town:gsub('%c', ' '):sub(1, 40) or 'inland'
  local pay = type(d.pay) == 'number' and d.pay >= 0 and math.floor(d.pay) or nil
  local from = d.ship == ship.number and ship.port.name or 'the docks'
  say(string.format('%s delivered container %d from %s to %s%s.', tostring(p.name), math.floor(d.n), from, town,
    pay and (' for $' .. tostring(pay)) or ''))
  if fresh then
    counted(p, pay, true)
    W.feed('delivery', string.format('%s delivered container %d from %s to %s%s.', clean(p.name, 32) or 'A trucker',
      math.floor(d.n), from, town, pay and (' for ' .. dollars(pay)) or ''))
  end
end


-- ----- Relocate to a player ----------------------------------------------------------------------------------------
-- The Relocate tab lists everyone else on the server by name and town (never their position). A player who picks one
-- asks the server (wwtcFind), the server asks that player's game where it is (wwtcLocate), and that game answers
-- (wwtcHere) with its exact spot, or a no: the player has turned it off, or isn't in their car. The spot goes only to
-- the player who asked (wwtcFound), is never kept or written down, and their game books the usual relocation there.
W.FIND_WAIT_SECONDS = 30

-- The list for one player: everyone else whose career is in, with their town.
function W.playersMessage(pid)
  local list = {}
  for other, p in pairs(W.players) do
    if other ~= pid and p.key then
      local w = p.where or {}
      list[#list + 1] = { id = other, name = clean(p.name, 32) or 'A trucker', town = w.town, region = w.region,
        latitude = w.latitude, longitude = w.longitude, doing = w.doing }
    end
  end
  table.sort(list, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
  return W.env.encode({ v = W.PROTO, players = list })
end

function W.sendPlayersToAll()
  for pid, p in pairs(W.players) do
    if p.key then W.env.send(pid, 'wwtcPlayers', W.playersMessage(pid)) end
  end
end

W.asks, W.nextAsk = {}, 0

local function found(pid, to, name, fields)
  local message = { v = W.PROTO, to = to, name = name }
  for k, v in pairs(fields) do message[k] = v end
  W.env.send(pid, 'wwtcFound', W.env.encode(message))
end

-- A player asks to relocate to another: that player's game is asked where it is.
function W.onFind(pid, data)
  local p = W.players[pid]
  if not p or not p.key then return end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' then return end
  local to = tonumber(d.to)
  local target = to and W.players[to]
  if not target or not target.key or to == pid then return found(pid, to, nil, { ok = false, why = 'gone' }) end
  local now = W.env.clock()
  for n, a in pairs(W.asks) do
    if now - a.at > W.FIND_WAIT_SECONDS or a.from == pid then W.asks[n] = nil end
  end
  W.nextAsk = W.nextAsk + 1
  W.asks[W.nextAsk] = { from = pid, to = to, at = now }
  W.env.send(to, 'wwtcLocate', W.env.encode({ v = W.PROTO, ask = W.nextAsk, name = clean(p.name, 32) or 'A trucker' }))
end

local function number(v, limit)
  v = tonumber(v)
  if v and v == v and math.abs(v) <= limit then return v end
end

-- That player's game answers: its spot goes to the player who asked, and nowhere else.
function W.onHere(pid, data)
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' then return end
  local n = tonumber(d.ask)
  local a = n and W.asks[n]
  if not a or a.to ~= pid then return end
  W.asks[n] = nil
  local asker = W.players[a.from]
  if not asker or not asker.key then return end
  local name = clean((W.players[pid] or {}).name, 32) or 'A trucker'
  local lat, lon = number(d.latitude, 90), number(d.longitude, 180)
  if d.ok == true and lat and lon then
    found(a.from, pid, name, { ok = true, latitude = lat, longitude = lon, heading = number(d.heading, 360) })
  else
    local why = (d.why == 'off' or d.why == 'away') and d.why or 'away'
    found(a.from, pid, name, { ok = false, why = why })
  end
end

-- ----- Restarting for an update -----------------------------------------------------------------------------------
-- The update script (update-server.ps1) asks for a restart by writing restart.json next to this file:
-- {"at": when to stop, in seconds since 1970 (UTC), "why": "what's being updated"}. Everyone is warned in chat, every
-- game saves itself RESTART_SAVE_AHEAD seconds before, and at the time everyone is sent off with a message. Then the
-- file is deleted, which tells the script the server is ready to stop. With nobody on, that happens straight away.
-- Deleting the file before then calls the update off.
W.RESTART_FILE = W.DIR .. '/restart.json'
W.RESTART_WARN = { 1800, 900, 600, 300, 120, 60 }
W.RESTART_SAVE_AHEAD = 90

local function minutes(seconds)
  local m = math.max(1, math.floor((seconds + 30) / 60))
  return m == 1 and '1 minute' or (tostring(m) .. ' minutes')
end

-- Everyone on the server, joined to the career or not: pid -> name.
function W.online()
  local list = W.env.players and W.env.players() or nil
  if type(list) ~= 'table' then
    list = {}
    for pid, p in pairs(W.players) do list[pid] = p.name or '' end
  end
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return list, n
end

function W.restartTick()
  local env = W.env
  local text = env.read(W.RESTART_FILE)
  local ok, r = false, nil
  if text and text ~= '' then ok, r = pcall(env.decode, text) end
  if not ok or type(r) ~= 'table' or type(r.at) ~= 'number' then
    if W.restart and W.restart.told then say('The server update is off. Carry on trucking!') end
    W.restart = nil
    return
  end
  if not W.restart or W.restart.at ~= r.at then W.restart = { at = r.at, warned = {}, told = false } end
  local R = W.restart
  local why = clean(r.why, 120)
  local list, n = W.online()
  local left = r.at - env.clock()
  if n == 0 or left <= 0 then
    if n > 0 then
      say('The server is restarting for an update now. Your career is kept on the server. Join again in a few minutes.')
      for pid in pairs(list) do
        if env.kick then pcall(env.kick, pid, 'The server is updating. Your career is kept. Join again in a few minutes.') end
      end
    end
    env.print(string.format('[Trucking] ready for the update (%d player(s) sent off)', n))
    if env.remove then env.remove(W.RESTART_FILE) else env.write(W.RESTART_FILE, '') end
    W.restart = nil
    return
  end
  local due = not R.told
  for _, s in ipairs(W.RESTART_WARN) do
    if left <= s and not R.warned[s] then due = true end
  end
  if due then
    for _, s in ipairs(W.RESTART_WARN) do if left <= s + 14 then R.warned[s] = true end end
    R.told = true
    say(string.format('The server restarts for an update in %s%s. Your career is kept on the server, and your game '
      .. 'saves itself a minute before. Join again a few minutes after.', minutes(left), why and (' (' .. why .. ')') or ''))
  end
  if left <= W.RESTART_SAVE_AHEAD and not R.saveAsked then
    R.saveAsked = true
    for pid, p in pairs(W.players) do
      if p.key then env.send(pid, 'wwtcSaveNow', env.encode({ v = W.PROTO, seconds = math.floor(left) })) end
    end
  end
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
    clock = os.time, epoch = function(t) return os.time(t) end, date = function() return os.date('%Y-%m-%d') end,
    -- Runs a command (curl, to send the server page's stats) and returns what it printed.
    run = function(command)
      local f = io.popen and io.popen(command)
      if not f then return nil end
      local out = f:read('*a')
      f:close()
      return out
    end,
    setting = function(which)
      local ids = MP.Settings
      if not ids or not MP.Get then return nil end
      local ok, value = pcall(MP.Get, which == 'name' and ids.Name or ids.MaxPlayers)
      return ok and value or nil
    end,
    account = function(pid)
      local ok, ids = pcall(MP.GetPlayerIdentifiers, pid)
      local id = ok and type(ids) == 'table' and ids.beammp or nil
      if id ~= nil and tostring(id) ~= '' then return tostring(id) end
    end,
    name = function(pid) return MP.GetPlayerName(pid) end,
    chat = function(pid, text) MP.SendChatMessage(pid, text) end,
    players = function() return MP.GetPlayers and MP.GetPlayers() or nil end,
    kick = function(pid, reason) MP.DropPlayer(pid, reason) end,
    remove = function(path) os.remove(path) end,
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
  WWTC_onShipTimer = guarded('ship', function() W.shipTick(); W.statsTick(); W.restartTick(); W.sendPlayersToAll() end)
  WWTC_onWhere = guarded('where', W.onWhere)
  WWTC_onDelivered = guarded('delivered', W.onDelivered)
  WWTC_onFind = guarded('find', W.onFind)
  WWTC_onHere = guarded('here', W.onHere)
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
  MP.RegisterEvent('wwtcWhere', 'WWTC_onWhere')
  MP.RegisterEvent('wwtcDelivered', 'WWTC_onDelivered')
  MP.RegisterEvent('wwtcFind', 'WWTC_onFind')
  MP.RegisterEvent('wwtcHere', 'WWTC_onHere')
  MP.RegisterEvent('WWTC_shipTimer', 'WWTC_onShipTimer')
  if MP.CreateEventTimer then MP.CreateEventTimer('WWTC_shipTimer', 15000) end
  WWTC_onShipTimer()
  MP.RegisterEvent('onChatMessage', 'WWTC_onChat')
  MP.RegisterEvent('onConsoleInput', 'WWTC_onConsole')
  print(string.format('[Trucking] plugin loaded: season %d, careers in %s (type "trucking" to list players)',
    W.SEASON, W.seasonDir()))
end

return W
