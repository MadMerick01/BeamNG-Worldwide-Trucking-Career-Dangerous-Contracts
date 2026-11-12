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
--                   With "again": true, a player the server lost (see 'rejoin') joins back without their career
--                   being sent, answered by
--   server -> game  wwtcRejoined '{"v","key"}'
--   server -> game  wwtcCareer frames of '{"v","key","season","save"}'  the player's key and career (save null: none)
--   game -> server  wwtcSave   frames of the save document (JSON), sent after every save in game
--   server -> game  wwtcSaved  '{"v","ok","generation","why"}'  why 'rejoin': the server doesn't know this player
--                   (BeamMP lost them, or this plugin was reloaded): the game joins again and sends the save again.
--                   The same save sent twice is answered ok, so a game can send again one it never heard back about.
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
--   server -> game  wwtcAway   '{"v","since","place","was","of","tolls","news"}'  on joining: what happened while this
--                   player was off the server (see 'While you were away')
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
  'Your career is kept on this server. It saves itself every 5 minutes, or press Save in the HUD. Type !hud to see this again.',
}
-- Posted in chat to everyone, one line at a time in turn, every ANNOUNCE_EVERY_MINUTES while anyone is on. Change
-- the lines as you like, add more, or make it {} to send nothing. Codes starting with ^ colour the text after them:
-- ^c red, ^6 gold, ^e yellow, ^a green, ^b aqua, ^9 blue, ^d pink, ^f white, ^l bold, ^r back to normal.
W.ANNOUNCE_EVERY_MINUTES = 10
W.ANNOUNCE = {
  '^e^lNo trucking HUD on screen?^r^e Press Esc > System > HUD Apps > .Earth (edit layout) > + Add app, pick '
    .. '"BeamNG Worldwide Trucking Career: Dangerous Contracts", + Add to layout, Save. Type ^b!hud^e for the steps.',
  '^b^lJoin our Discord:^r^a discord.gg/eYJCfXNGbP ^b for news, help and Ship Day calls.',
  '^6^lLive trucking career page:^r^a madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts ^6 '
    .. 'for who\'s driving, Ship Day and the leaderboard.',
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

local function payOf(value)
  local n = tonumber(value)
  if not n or n < 0 or n > 100000000 then return nil end
  return math.floor(n)
end

-- A player's career came in (join) or was saved: their money, truck's, trailer's and base's worth and jobs done on the leaderboard.
function W.boardCareer(p, save)
  if not p or not p.key or type(save) ~= 'table' or type(save.progression) ~= 'table' then return end
  local e = boardEntry(p)
  if type(save.progression.balance) == 'number' then e.balance = save.progression.balance end
  if type(save.progression.jobsDone) == 'number' then e.deliveries = save.progression.jobsDone end
  -- The truck's worth: what the game says it is worth now, else (an older game) what a second-hand one cost.
  local car = type(save.vehicle) == 'table' and save.vehicle or {}
  local worth = payOf(car.worth) or payOf(car.value)
  if worth then e.truckValue = worth end
  -- What they paid for their trailers and their parts: the one in use and a second one kept stored.
  local trailer = type(save.trailer) == 'table' and payOf(save.trailer.paid) or nil
  local spare = type(save.spareTrailer) == 'table' and payOf(save.spareTrailer.paid) or nil
  e.trailerValue = (trailer or spare) and ((trailer or 0) + (spare or 0)) or nil
  -- What they paid for their base of operations, if they have one.
  e.baseValue = type(save.property) == 'table' and payOf(save.property.paid) or nil
  local town = e.baseValue and type(save.property.town) == 'table' and save.property.town.name or (e.baseValue and save.property.name)
  e.baseTown = e.baseValue and clean(town, 40) or nil
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
  if d.kind == 'job' or d.kind == 'drop' then W.commission(p, pay, d.ends, d.toll) end
end

-- ----- Bases of operations (the Magnate update) ---------------------------------------------------------------------
-- Kept in careers/season-N/bases.json, by career key: { name, town, latitude, longitude, boost, peak, asked }. A base sits
-- at its town's centre (public), never at the spot its owner parked on. The game sizes and draws the circles the same
-- way (mod magnate.lua): 1,600 km at $250,000 in a flat region, area in line with wealth, × √(region multiplier), with
-- no cap (BASE_MAX_KM is half way round the world). One base a town, at least BASE_APART_KM apart.
W.BASE_APART_KM = 300
W.BASE_START_WEALTH, W.BASE_START_KM, W.BASE_MAX_KM = 250000, 1600, 20000
W.BASE_PRICE = 250000
W.BASE_ASK_SECONDS = 600   -- a base asked for, but not yet in a save, is held this long

local function basesPath() return W.seasonDir() .. '/bases.json' end

function W.baseRadius(peak, boost)
  peak = math.max(0, tonumber(peak) or 0)
  boost = math.max(1, tonumber(boost) or 1)
  return math.min(W.BASE_MAX_KM, W.BASE_START_KM * math.sqrt(peak / W.BASE_START_WEALTH) * math.sqrt(boost))
end

-- Kilometres between two { latitude, longitude } on the Earth's surface.
function W.km(a, b)
  local r = math.pi / 180
  local dLat, dLon = (b.latitude - a.latitude) * r, (b.longitude - a.longitude) * r
  local h = math.sin(dLat / 2) ^ 2 + math.cos(a.latitude * r) * math.cos(b.latitude * r) * math.sin(dLon / 2) ^ 2
  return 2 * 6371.0088 * math.asin(math.min(1, math.sqrt(h)))
end

local function spotOf(t)
  if type(t) ~= 'table' then return nil end
  local lat, lon = tonumber(t.latitude), tonumber(t.longitude)
  if not lat or not lon or math.abs(lat) > 90 or math.abs(lon) > 180 then return nil end
  return lat, lon
end

-- A base's members or join requests as kept: career key -> { name, id, at }. Anything odd is dropped.
function W.cleanCorpList(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for key, m in pairs(list) do
    if W.validKey(key) and type(m) == 'table' and payOf(m.id) then
      out[key] = { name = clean(m.name, 32) or 'A trucker', id = payOf(m.id), at = tonumber(m.at) }
    end
  end
  return out
end

-- A { latitude, longitude } checked, or nil.
function W.spotTable(t)
  local lat, lon = spotOf(t)
  return lat and { latitude = lat, longitude = lon } or nil
end

-- The next free base number.
function W.newBaseId()
  local top = 0
  for _, b in pairs(W.bases or {}) do if b.id and b.id > top then top = b.id end end
  return top + 1
end

function W.loadBases()
  local text = W.env.read(basesPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  W.bases = {}
  for _, b in ipairs(ok and type(d) == 'table' and d or {}) do
    local lat, lon = spotOf(b)
    if lat and type(b) == 'table' and W.validKey(b.key) then
      local batch = type(b.batch) == 'table' and payOf(b.batch.id) and payOf(b.batch.amount)
        and { id = payOf(b.batch.id), amount = payOf(b.batch.amount), jobs = payOf(b.batch.jobs) or 1, by = clean(b.batch.by, 32) } or nil
      W.bases[b.key] = { name = clean(b.name, 32) or 'A trucker', town = clean(b.town, 40), latitude = lat, longitude = lon,
        boost = tonumber(b.boost) or 1, peak = payOf(b.peak) or 0, asked = tonumber(b.asked),
        owed = payOf(b.owed) or 0, jobs = payOf(b.jobs) or 0, by = clean(b.by, 32), batch = batch, lastId = payOf(b.lastId) or 0,
        day = type(b.day) == 'string' and b.day or nil, dayTotal = payOf(b.dayTotal) or 0,
        id = payOf(b.id), spot = W.spotTable(b.spot),
        members = W.cleanCorpList(b.members), requests = W.cleanCorpList(b.requests), nextMember = payOf(b.nextMember) or 0 }
    end
  end
  -- Every base has a number, which the corp buttons use (an older bases.json has none).
  for _, b in pairs(W.bases) do if not b.id or b.id < 1 then b.id = W.newBaseId() end end
end

local function saveBases()
  local list = {}
  for key, b in pairs(W.bases) do
    list[#list + 1] = { key = key, name = b.name, town = b.town, latitude = b.latitude, longitude = b.longitude,
      boost = b.boost, peak = b.peak, asked = b.asked, owed = b.owed, jobs = b.jobs, by = b.by, batch = b.batch,
      lastId = b.lastId, day = b.day, dayTotal = b.dayTotal, id = b.id, spot = b.spot,
      members = next(b.members or {}) and b.members or nil, requests = next(b.requests or {}) and b.requests or nil,
      nextMember = b.nextMember }
  end
  table.sort(list, function(a, b) return a.key < b.key end)
  W.env.write(basesPath(), W.env.encode(list))
end

-- Bases asked for but never saved are let go after BASE_ASK_SECONDS.
local function dropStaleBases()
  local now, changed = W.env.clock(), false
  for key, b in pairs(W.bases) do
    if b.asked and now - b.asked > W.BASE_ASK_SECONDS then W.bases[key] = nil; changed = true end
  end
  if changed then saveBases() end
  return changed
end

-- Every base, for one player's game: owner, town, centre, radius, whether it's theirs, and its corp: the members'
-- names, whether this player is one (then also the base's own spot, its yard) or has asked to join, and for the
-- owner the requests waiting. corp.wait: the seconds before this player may ask to join a corp again.
function W.basesMessage(pid)
  local p = W.players[pid]
  local me = p and p.key
  local list = {}
  for key, b in pairs(W.bases) do
    local e = { id = b.id, name = b.name, town = b.town, latitude = b.latitude, longitude = b.longitude,
      radiusKm = W.circleKm(b), memberWealth = W.membersWealth(b), mine = me ~= nil and me == key,
      members = W.memberList(b.members), full = W.corpFull(b) or nil, held = b.asked ~= nil or nil }
    if me and b.members and b.members[me] then
      e.corp = true
      e.yard = b.spot or { latitude = b.latitude, longitude = b.longitude }
    end
    if me and b.requests and b.requests[me] then e.asked = true end
    if e.mine then e.requests = W.memberList(b.requests) end
    list[#list + 1] = e
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  local wait = me and W.corpWait(me)
  return W.env.encode({ v = W.PROTO, bases = list, corp = wait and { wait = wait } or nil })
end

function W.sendBases(pid)
  local p = W.players[pid]
  if p and p.key then W.env.send(pid, 'wwtcBases', W.basesMessage(pid)) end
end

function W.sendBasesToAll()
  for pid, p in pairs(W.players) do if p.key then W.sendBases(pid) end end
  W.statsChanged = true
end

-- A player asks for a base in a town: theirs unless another base is within BASE_APART_KM.
function W.onBaseClaim(pid, data)
  local p = W.players[pid]
  if not p or not p.key then return end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' then return end
  local lat, lon = spotOf(d)
  if not lat then return end
  dropStaleBases()
  local town = clean(d.town, 40)
  local why, by, near
  local mine = W.bases[p.key]
  if mine and not mine.asked then why = 'have_one' end
  if not why and W.corpOf(p.key) then why = 'in_corp' end
  if not why then
    for key, b in pairs(W.bases) do
      if key ~= p.key and W.km(b, { latitude = lat, longitude = lon }) < W.BASE_APART_KM then why, by, near = 'too_close', b.name, b.town end
    end
  end
  if not why then
    local boost = tonumber(d.boost) or 1
    W.bases[p.key] = { name = clean(p.name, 32) or 'A trucker', town = town, latitude = lat, longitude = lon,
      boost = math.max(1, math.min(3, boost)), peak = 0, asked = W.env.clock(), id = (mine and mine.id) or W.newBaseId(),
      members = {}, requests = {}, nextMember = 0 }
    W.dropRequests(p.key)
    saveBases()
  end
  W.env.send(pid, 'wwtcBaseClaimed', W.env.encode({ v = W.PROTO, ok = why == nil, why = why, by = by, town = near or town }))
  if not why then W.sendBasesToAll() end
end

-- A career came in (join) or was saved: its base, as the save has it. A base the server held for a claim becomes
-- the player's when a save has it; a save without one lets go of a base that isn't still being asked for.
function W.baseCareer(p, save)
  if not p or not p.key or type(save) ~= 'table' then return end
  local had = W.bases[p.key]
  local property = type(save.property) == 'table' and save.property or nil
  local town = property and type(property.town) == 'table' and property.town or nil
  -- Only the town's centre is ever used: a save from before the game worked out the town (an older home) shows no
  -- circle until the game's next save, rather than the spot where its owner parks.
  local lat, lon = spotOf(town)
  if lat then
    local b = had or {}
    -- A base already held keeps its town; one from a save made before the server knew of it takes the save's.
    if not had or had.asked then
      b.latitude, b.longitude = (had and had.latitude) or lat, (had and had.longitude) or lon
      b.town = (had and had.town) or clean(town.name, 40)
      b.boost = (had and had.boost) or math.max(1, math.min(3, tonumber(town.boost) or 1))
    end
    b.name, b.asked = clean(p.name, 32) or b.name or 'A trucker', nil
    b.peak = math.max(b.peak or 0, payOf(property.peak) or 0)
    -- The spot the owner parks on: the corp's yard, sent to its members only.
    local spotLat, spotLon = spotOf(property)
    b.spot = spotLat and { latitude = spotLat, longitude = spotLon } or b.spot
    b.id = b.id or W.newBaseId()
    b.members, b.requests, b.nextMember = b.members or {}, b.requests or {}, b.nextMember or 0
    if W.corpOf(p.key) then
      -- A base can't be in a corp: a member who has one (an old save) leaves the corp.
      W.corpLeave(p.key, false)
    end
    W.bases[p.key] = b
    saveBases()
    W.sendBasesToAll()
    W.sendCommission(p.key)
  elseif had and not had.asked and not property then
    W.bases[p.key] = nil
    saveBases()
    W.sendBasesToAll()
  elseif W.corpOf(p.key) then
    -- A member's wealth sizes their corp's circle: every save can change it.
    local b = W.corpOf(p.key)
    b.members[p.key].name = clean(p.name, 32) or b.members[p.key].name
    W.sendBasesToAll()
  end
end

-- ----- The turf toll (Magnate 2) -------------------------------------------------------------------------------------
-- A delivery by someone else whose drop-off is in a base's turf pays TOLL of its pay to that base's owner. The driver's
-- game takes it off their pay (so the job board already shows the pay after it) and says how much it took; the server
-- pays the owner that (split with their corp, see W.commission), at most what TOLL of the pay could be. There is no
-- daily limit: it's money moving between players, not new money.
W.TOLL = 0.2
W.BASE_CORE_KM = 100

-- Whose turf a spot is: a base's own core first, else the circle with the smallest distance ÷ radius.
function W.turfAt(spot)
  local best, bestScore
  for key, b in pairs(W.bases or {}) do
    if not b.asked then
      local km, r = W.km(b, spot), W.circleKm(b)
      if km <= W.BASE_CORE_KM then return key end
      if km <= r and (not bestScore or km / r < bestScore) then best, bestScore = key, km / r end
    end
  end
  return best
end

-- Turf tolls owed, by career key: { owed, jobs, by, batch, lastId }, kept in tolls.json. A solo base's owner gets
-- every toll in their turf; a corp's tolls are split equally between the owner and every member (Magnate 3). What a
-- player is owed builds up while they're away and goes to their game as a batch (wwtcCommission { id, amount, jobs,
-- by }); their game adds it to their money and saves with commissionId = id, and that save marks it paid. Someone who
-- leaves a corp keeps what they're already owed.
local function tollsPath() return W.seasonDir() .. '/tolls.json' end

local function cleanToll(t)
  if type(t) ~= 'table' then return nil end
  local batch = type(t.batch) == 'table' and payOf(t.batch.id) and payOf(t.batch.amount)
    and { id = payOf(t.batch.id), amount = payOf(t.batch.amount), jobs = payOf(t.batch.jobs) or 1, by = clean(t.batch.by, 32) } or nil
  return { owed = payOf(t.owed) or 0, jobs = payOf(t.jobs) or 0, by = clean(t.by, 32), batch = batch, lastId = payOf(t.lastId) or 0 }
end

local function saveTolls() W.env.write(tollsPath(), W.env.encode(W.tolls)) end

-- Loads tolls.json, and moves what bases kept before it (a base owner's owed and batch) into it.
function W.loadTolls()
  local text = W.env.read(tollsPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  W.tolls = {}
  for key, t in pairs(ok and type(d) == 'table' and d or {}) do
    if W.validKey(key) then W.tolls[key] = cleanToll(t) end
  end
  local moved = false
  for key, b in pairs(W.bases or {}) do
    if (b.owed or 0) > 0 or b.batch or (b.lastId or 0) > 0 then
      local t = W.tolls[key] or { owed = 0, jobs = 0, lastId = 0 }
      t.owed, t.jobs = (t.owed or 0) + (b.owed or 0), (t.jobs or 0) + (b.jobs or 0)
      t.by, t.batch = t.by or b.by, t.batch or b.batch
      t.lastId = math.max(t.lastId or 0, b.lastId or 0)
      W.tolls[key] = t
      b.owed, b.jobs, b.by, b.batch, b.lastId = nil, nil, nil, nil, nil
      moved = true
    end
  end
  if moved then saveTolls(); saveBases() end
end

-- A save came in: the batch it carries the id of is paid.
function W.tollsPaid(key, save)
  local t = W.tolls and W.tolls[key]
  if t and t.batch and type(save) == 'table' and (payOf(save.commissionId) or 0) >= t.batch.id then
    t.batch = nil
    saveTolls()
  end
end

-- Sends a player what they're owed, if they're on: the batch already sent, else a new one.
function W.sendCommission(key)
  local t = W.tolls and W.tolls[key]
  if not t then return end
  local pid
  for id, p in pairs(W.players) do if p.key == key then pid = id end end
  if not pid then return end
  if not t.batch and (t.owed or 0) > 0 then
    t.lastId = (t.lastId or 0) + 1
    t.batch = { id = t.lastId, amount = t.owed, jobs = t.jobs or 1, by = t.by }
    t.owed, t.jobs, t.by = 0, 0, nil
    saveTolls()
  end
  if t.batch then
    W.env.send(pid, 'wwtcCommission', W.env.encode({ v = W.PROTO, id = t.batch.id, amount = t.batch.amount,
      jobs = t.batch.jobs, by = t.batch.by }))
  end
end

-- Who shares a base's tolls: its owner, then its members by number.
function W.tollShares(key, b)
  local keys = { key }
  local members = {}
  for k, m in pairs(b.members or {}) do members[#members + 1] = { key = k, id = m.id or 0 } end
  table.sort(members, function(x, y) return x.id < y.id end)
  for _, m in ipairs(members) do keys[#keys + 1] = m.key end
  return keys
end

-- A delivery's turf toll: ends are the town centres { latitude, longitude } at each end, the second the drop-off. pay
-- is what the driver was paid after the toll, and toll what their game took. Split equally between everyone in the
-- turf's corp (a solo owner gets it all); what doesn't split into whole dollars goes to the owner.
function W.commission(p, pay, ends, toll)
  if not p or not p.key or not pay or pay < 0 or type(ends) ~= 'table' or not W.bases then return end
  toll = type(toll) == 'number' and toll == toll and math.floor(toll) or 0
  -- No more than TOLL of the whole pay (pay + toll), with a little room for rounding.
  toll = math.min(toll, math.floor(pay * W.TOLL / (1 - W.TOLL)) + 10)
  if toll <= 0 then return end
  local lat, lon = spotOf(ends[2])
  local key = lat and W.turfAt({ latitude = lat, longitude = lon })
  if not key or key == p.key then return end
  local b = W.bases[key]
  if b.members and b.members[p.key] then return end
  local driver = clean(p.name, 32) or 'A trucker'
  local shares = W.tollShares(key, b)
  local each = math.floor(toll / #shares)
  W.tolls = W.tolls or {}
  for i, k in ipairs(shares) do
    local amount = each + (i == 1 and toll - each * #shares or 0)
    if amount > 0 then
      local t = W.tolls[k] or { owed = 0, jobs = 0, lastId = 0 }
      t.owed, t.jobs, t.by = (t.owed or 0) + amount, (t.jobs or 0) + 1, driver
      W.tolls[k] = t
      W.awayToll(k, driver, amount)
    end
  end
  W.feed('commission', #shares > 1
    and string.format("%s paid %s's corp a %s turf toll, %s each.", driver, b.name, dollars(toll), dollars(each))
    or string.format("%s paid %s a %s turf toll.", driver, b.name, dollars(toll)))
  saveTolls()
  for _, k in ipairs(shares) do W.sendCommission(k) end
end

-- ----- Corps (Magnate 3) --------------------------------------------------------------------------------------------
-- Other players join a base as members of its corp. The owner (who built it) keeps it; tolls from non-members are
-- split equally between the owner and every member; members pay no toll in its turf, get the owner's spot as a yard for a car and a trailer, and +0.2 in
-- its turf (the game works that out). Half of each member's wealth now adds to the owner's best wealth in sizing the
-- circle. A corp holds CORP_MAX truckers (the owner too); a player is in one at a time and can't own a base while
-- they are; after leaving or being removed they wait CORP_WAIT_SECONDS before asking to join again.
--   game -> server  wwtcCorp '{"v","do","base","who"}'  do: ask (base id), cancel, leave, accept / refuse / remove (who:
--                   the member or request number, owner only); answered by
--   server -> game  wwtcCorpDone '{"v","do","ok","why","wait"}'  and everyone's wwtcBases again on a change
-- corps.json keeps when each player last left one: { left = { key = time } }.
W.CORP_MAX = 5
W.CORP_WAIT_SECONDS = 24 * 3600
W.CORP_MEMBER_SHARE = 0.5   -- the share of a member's wealth that sizes the circle
W.CORP_REQUESTS_MAX = 20

local function corpsPath() return W.seasonDir() .. '/corps.json' end

function W.loadCorps()
  local text = W.env.read(corpsPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  W.corpLeft = {}
  for key, at in pairs(ok and type(d) == 'table' and type(d.left) == 'table' and d.left or {}) do
    if W.validKey(key) and tonumber(at) then W.corpLeft[key] = tonumber(at) end
  end
end

local function saveCorps()
  W.env.write(corpsPath(), W.env.encode({ left = next(W.corpLeft or {}) and W.corpLeft or nil }))
end

-- The corp (base) a player is a member of, and its owner's key, or nil.
function W.corpOf(key)
  for owner, b in pairs(W.bases or {}) do
    if b.members and b.members[key] then return b, owner end
  end
  return nil
end

function W.corpSize(b)
  local n = 1
  for _ in pairs(b.members or {}) do n = n + 1 end
  return n
end
function W.corpFull(b) return W.corpSize(b) >= W.CORP_MAX end

-- What a player is worth now, as the leaderboard has it: cash, truck, trailers and base.
function W.wealthOf(key)
  local e = W.stats and W.stats.board and W.stats.board[key]
  if not e then return 0 end
  return (e.balance or 0) + (e.truckValue or 0) + (e.trailerValue or 0) + (e.baseValue or 0)
end

-- Half of every member's wealth now, which adds to the owner's best wealth in sizing the circle.
function W.membersWealth(b)
  local sum = 0
  for key in pairs(b.members or {}) do sum = sum + W.wealthOf(key) end
  return math.floor(sum * W.CORP_MEMBER_SHARE)
end

-- The circle's radius in km: the owner's best wealth (at least the base's price) and half of each member's.
function W.circleKm(b)
  return W.baseRadius(math.max(b.peak or 0, W.BASE_PRICE) + W.membersWealth(b), b.boost)
end

-- Members or requests, for the games and the page: { id, name }, by number.
function W.memberList(list)
  local out = {}
  for _, m in pairs(list or {}) do out[#out + 1] = { id = m.id, name = m.name } end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
function W.memberNames(b)
  local out = {}
  for _, m in ipairs(W.memberList(b.members)) do out[#out + 1] = m.name end
  return #out > 0 and out or nil
end

-- Seconds before this player may ask to join a corp again, or nil.
function W.corpWait(key)
  local at = W.corpLeft and W.corpLeft[key]
  if not at then return nil end
  local left = at + W.CORP_WAIT_SECONDS - W.env.clock()
  if left <= 0 then W.corpLeft[key] = nil; return nil end
  return math.ceil(left)
end

-- Takes back every request this player has out.
function W.dropRequests(key)
  for _, b in pairs(W.bases or {}) do if b.requests then b.requests[key] = nil end end
end

-- Takes a player out of their corp; counted (true) starts their wait before joining another.
function W.corpLeave(key, counted)
  local b = W.corpOf(key)
  if not b then return nil end
  local m = b.members[key]
  b.members[key] = nil
  if counted then
    W.corpLeft = W.corpLeft or {}
    W.corpLeft[key] = W.env.clock()
    saveCorps()
  end
  saveBases()
  return b, m
end

local function numbered(list, id)
  for key, m in pairs(list or {}) do if m.id == id then return key, m end end
  return nil
end

function W.onCorp(pid, data)
  local p = W.players[pid]
  if not p or not p.key then return end
  local ok, d = pcall(W.env.decode, data or '')
  if not ok or type(d) ~= 'table' or type(d['do']) ~= 'string' then return end
  local what = d['do']
  local name = clean(p.name, 32) or 'A trucker'
  local why, wait, changed
  local mine = W.bases[p.key]
  if what == 'ask' then
    local b, owner
    for k, x in pairs(W.bases) do if not x.asked and x.id == payOf(d.base) then b, owner = x, k end end
    if not b then why = 'no_base'
    elseif mine then why = 'have_base'
    elseif W.corpOf(p.key) then why = 'in_corp'
    elseif W.corpWait(p.key) then why, wait = 'wait', W.corpWait(p.key)
    elseif W.corpFull(b) then why = 'full'
    else
      local n = 0
      for _ in pairs(b.requests) do n = n + 1 end
      if n >= W.CORP_REQUESTS_MAX and not b.requests[p.key] then why = 'busy' end
    end
    if not why then
      W.dropRequests(p.key)
      b.nextMember = (b.nextMember or 0) + 1
      b.requests[p.key] = { name = name, id = b.nextMember, at = W.env.clock() }
      saveBases()
      W.awayNote(owner, name .. ' asked to join your corp. Accept or turn them down on the Base tab.')
      changed = true
    end
  elseif what == 'cancel' then
    W.dropRequests(p.key)
    saveBases()
    changed = true
  elseif what == 'leave' then
    local _, owner = W.corpOf(p.key)
    local b = W.corpLeave(p.key, true)
    if not b then why = 'not_in_corp' else
      W.feed('corp', string.format('%s left %s\'s corp.', name, b.name))
      W.awayNote(owner, name .. ' left your corp.')
      changed = true
    end
  elseif what == 'accept' or what == 'refuse' or what == 'remove' then
    local id = payOf(d.who)
    if not mine or mine.asked then why = 'not_owner'
    elseif what == 'remove' then
      local key, m = numbered(mine.members, id)
      if not key then why = 'gone' else
        W.corpLeave(key, true)
        W.feed('corp', string.format('%s removed %s from their corp.', mine.name, m.name))
        W.awayNote(key, mine.name .. ' removed you from their corp.')
        changed = true
      end
    else
      local key, m = numbered(mine.requests, id)
      if not key then why = 'gone'
      elseif what == 'refuse' then
        mine.requests[key] = nil
        saveBases()
        W.awayNote(key, mine.name .. ' turned down your request to join their corp.')
        changed = true
      elseif W.bases[key] then why = 'have_base'; mine.requests[key] = nil; changed = true
      elseif W.corpOf(key) then why = 'in_corp'; mine.requests[key] = nil; changed = true
      elseif W.corpFull(mine) then why = 'full'
      else
        W.dropRequests(key)
        mine.members[key] = { name = m.name, id = m.id, at = W.env.clock() }
        saveBases()
        W.feed('corp', string.format('%s joined %s\'s corp.', m.name, mine.name))
        W.awayNote(key, mine.name .. ' let you into their corp. Your corp yard is at their base: see the Base tab.')
        changed = true
      end
    end
  else
    return
  end
  W.env.send(pid, 'wwtcCorpDone', W.env.encode({ v = W.PROTO, ['do'] = what, ok = why == nil, why = why, wait = wait }))
  if changed then W.sendBasesToAll() end
end

-- ----- While you were away ---------------------------------------------------------------------------------------------
-- What happens to a player while they're off the server, kept in careers/season-N/away.json by career key: { seen =
-- when they left, place = their leaderboard place then, tolls = { amount, jobs, from = { name = amount } }, news =
-- { text, ... } }. On their next join the game gets it all as one wwtcAway message for the HUD's "While you were
-- away" card, and the record is cleared. A quick rejoin (under AWAY_MIN_SECONDS) with nothing to say sends nothing.
W.AWAY_MIN_SECONDS = 15 * 60
W.AWAY_NEWS_MAX = 10
W.AWAY_FROM_MAX = 3

local function awayPath() return W.seasonDir() .. '/away.json' end

function W.loadAway()
  local text = W.env.read(awayPath())
  local ok, d = false, nil
  if text and text ~= '' then ok, d = pcall(W.env.decode, text) end
  W.away = {}
  for key, a in pairs(ok and type(d) == 'table' and d or {}) do
    if W.validKey(key) and type(a) == 'table' then
      local tolls = type(a.tolls) == 'table' and a.tolls or nil
      local from = {}
      for name, amount in pairs(tolls and type(tolls.from) == 'table' and tolls.from or {}) do
        local n = clean(name, 32)
        if n and payOf(amount) then from[n] = payOf(amount) end
      end
      local news = {}
      for _, line in ipairs(type(a.news) == 'table' and a.news or {}) do
        local t = clean(line, 160)
        if t and #news < W.AWAY_NEWS_MAX then news[#news + 1] = t end
      end
      W.away[key] = { seen = tonumber(a.seen), place = payOf(a.place),
        tolls = tolls and payOf(tolls.amount) and { amount = payOf(tolls.amount), jobs = payOf(tolls.jobs) or 1, from = from } or nil,
        news = news }
    end
  end
end

local function saveAway() W.env.write(awayPath(), W.env.encode(W.away)) end

-- Whether a career is on the server right now.
function W.isOn(key)
  for _, p in pairs(W.players) do if p.key == key then return true end end
  return false
end

local function awayOf(key)
  local a = W.away[key]
  if not a then a = { news = {} }; W.away[key] = a end
  return a
end

-- Something to tell a player who isn't on: kept for their next join (the newest AWAY_NEWS_MAX).
function W.awayNote(key, text)
  if not W.away or not W.validKey(key) or W.isOn(key) then return end
  local news = awayOf(key).news
  news[#news + 1] = clean(text, 160)
  while #news > W.AWAY_NEWS_MAX do table.remove(news, 1) end
  saveAway()
end

-- A turf toll paid to an owner who isn't on.
function W.awayToll(key, name, amount)
  if not W.away or not W.validKey(key) or W.isOn(key) or not payOf(amount) or amount <= 0 then return end
  local a = awayOf(key)
  a.tolls = a.tolls or { amount = 0, jobs = 0, from = {} }
  a.tolls.amount, a.tolls.jobs = a.tolls.amount + amount, a.tolls.jobs + 1
  a.tolls.from[name] = (a.tolls.from[name] or 0) + amount
  saveAway()
end

-- A career's place on the season leaderboard by wealth (1 is the top), the number of truckers on it, or nil.
function W.placeOf(key)
  local me = W.stats and W.stats.board and W.stats.board[key]
  if not me then return nil end
  local mine, place, of = W.wealthOf(key), 1, 0
  for k, e in pairs(W.stats.board) do
    of = of + 1
    local w = W.wealthOf(k)
    if k ~= key and (w > mine or (w == mine and (e.name or '') < (me.name or ''))) then place = place + 1 end
  end
  return place, of
end

-- A player left: when, and where they stood, for their next join.
function W.awayLeft(key)
  if not W.away or not W.validKey(key) then return end
  local a = awayOf(key)
  a.seen, a.place = W.env.clock(), W.placeOf(key)
  saveAway()
end

-- The wwtcAway message for a player joining, or nil when there's nothing to tell them; the record is cleared.
function W.awayMessage(key)
  local a = W.away and W.away[key]
  if not a then return nil end
  W.away[key] = nil
  saveAway()
  local since = a.seen and math.max(0, W.env.clock() - a.seen) or nil
  local news = #(a.news or {}) > 0 and a.news or nil
  if not a.tolls and not news and (not since or since < W.AWAY_MIN_SECONDS) then return nil end
  local tolls
  if a.tolls then
    local from, others = {}, 0
    for name, amount in pairs(a.tolls.from or {}) do from[#from + 1] = { name = name, amount = amount } end
    table.sort(from, function(x, y) if x.amount ~= y.amount then return x.amount > y.amount end return x.name < y.name end)
    while #from > W.AWAY_FROM_MAX do table.remove(from); others = others + 1 end
    tolls = { amount = a.tolls.amount, jobs = a.tolls.jobs, from = from, others = others > 0 and others or nil }
  end
  local place, of = W.placeOf(key)
  return W.env.encode({ v = W.PROTO, since = since, place = place, was = a.place, of = of, tolls = tolls, news = news })
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
    local balance, truck, trailer, base = e.balance or 0, e.truckValue or 0, e.trailerValue or 0, e.baseValue or 0
    board[#board + 1] = { name = e.name, balance = balance, truckValue = truck, trailerValue = trailer, baseValue = base,
      baseTown = e.baseTown, wealth = balance + truck + trailer + base,
      deliveries = e.deliveries or 0, containers = e.containers or 0 }
  end
  -- Ranked by wealth: money plus what the truck, trailer and base are worth, so buying one doesn't drop you down.
  table.sort(board, function(a, b) if a.wealth ~= b.wealth then return a.wealth > b.wealth end return a.name < b.name end)
  while #board > 20 do table.remove(board) end
  -- Every base's town and circle, for the map (town centres only).
  local bases = {}
  for _, b in pairs(W.bases or {}) do
    bases[#bases + 1] = { name = b.name, town = b.town, latitude = math.floor(b.latitude * 100 + 0.5) / 100,
      longitude = math.floor(b.longitude * 100 + 0.5) / 100, radiusKm = math.floor(W.circleKm(b) * 10 + 0.5) / 10, members = W.memberNames(b) }
  end
  table.sort(bases, function(a, b) return a.name < b.name end)
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
    ship = ship, players = players, feed = W.stats.feed, leaderboard = board, bases = bases,
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
  W.loadBases()
  W.loadCorps()
  W.loadTolls()
  W.loadAway()
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
  if d.again == true then return W.rejoin(pid, p, account, d.key) end
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
  if save then W.tollsPaid(key, save); W.baseCareer(p, save) end
  W.sendBases(pid)
  W.sendCommission(key)
  W.sendShip(pid)
  if save then W.boardCareer(p, save) end
  local away = W.awayMessage(key)
  if away then W.env.send(pid, 'wwtcAway', away) end
  W.feed('join', (clean(p.name, 32) or 'A trucker') .. ' joined the server.')
  W.env.print(string.format('[Trucking] %s joined: %s, %s', tostring(p.name), account and 'signed in' or 'guest',
    save and ('balance $' .. tostring(save.progression.balance)) or 'new career'))
end

-- A player the server had lost joins back, still in the same game: they keep the career they have (their key; a
-- signed-in player's must be their account's), and nothing is sent but the answer.
function W.rejoin(pid, p, account, key)
  if not W.validKey(key) or (account and W.accounts[account] and W.accounts[account] ~= key) then return end
  if account and not W.accounts[account] then
    W.accounts[account] = key
    W.env.write(W.DIR .. '/accounts.json', W.env.encode(W.accounts))
  end
  local was = p.key
  p.key, p.account, p.name = key, account, W.env.name(pid)
  local _, save = readSave(key)
  p.balance = save and save.progression and save.progression.balance or nil
  W.env.send(pid, 'wwtcRejoined', W.env.encode({ v = W.PROTO, key = key }))
  -- They never really left, so nothing is kept for a "while you were away" card.
  if W.away and W.away[key] then W.away[key] = nil; saveAway() end
  if not was then
    W.env.print(string.format('[Trucking] %s joined back after the server lost track of them', tostring(p.name)))
    W.statsChanged = true
    W.sendPlayersToAll()
  end
end

local function answer(pid, ok, generation, why)
  W.env.send(pid, 'wwtcSaved', W.env.encode({ v = W.PROTO, ok = ok, generation = generation, why = why }))
end

function W.onSave(pid, frame)
  local p = player(pid)
  local text = W.receive(p.inbox, frame)
  if not text then return end
  -- A save from a player this server doesn't know (it lost them, or was reloaded) is never dropped without a word:
  -- the game is told to join again, and then sends it again.
  if not p.key then
    W.env.print(string.format('[Trucking] a save from %s, who the server had lost: asked to join again',
      tostring(W.env.name(pid))))
    return answer(pid, false, nil, 'rejoin')
  end
  if #text > W.SAVE_MAX then return answer(pid, false, nil, 'too_big') end
  local ok, save = pcall(W.env.decode, text)
  if not ok then return answer(pid, false, nil, 'not_a_save') end
  local kept, previous = readSave(p.key)
  -- The save already kept, sent again by a game that never heard back about it.
  if kept == text and type(save) == 'table' then return answer(pid, true, save.generation) end
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
  W.tollsPaid(p.key, save)
  W.baseCareer(p, save)
  W.sendCommission(p.key)
  answer(pid, true, save.generation)
end

function W.onLeave(pid)
  local was = W.players[pid]
  if was then W.statsChanged = true end
  W.players[pid] = nil
  if was and was.key and not W.isOn(was.key) then W.awayLeft(was.key) end
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

-- Every timer tick: the next ANNOUNCE line in chat once every ANNOUNCE_EVERY_MINUTES, while anyone is on. The first
-- comes a whole period after someone joins an empty server, so it never lands on top of the welcome lines.
function W.announceTick()
  local lines = type(W.ANNOUNCE) == 'table' and W.ANNOUNCE or {}
  local every = (tonumber(W.ANNOUNCE_EVERY_MINUTES) or 0) * 60
  if #lines == 0 or every <= 0 or not W.env.chat then return end
  local _, n = W.online()
  local now = W.env.clock()
  if n == 0 then W.announcedAt = nil; return end
  if not W.announcedAt then W.announcedAt = now; return end
  if now - W.announcedAt < every then return end
  W.announceNext = (W.announceNext or 0) % #lines + 1
  W.env.chat(-1, tostring(lines[W.announceNext]))
  W.announcedAt = now
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
    W.commission(p, pay, d.ends, d.toll)
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
  WWTC_onShipTimer = guarded('ship', function() W.shipTick(); W.statsTick(); W.restartTick(); W.sendPlayersToAll(); W.announceTick() end)
  WWTC_onWhere = guarded('where', W.onWhere)
  WWTC_onDelivered = guarded('delivered', W.onDelivered)
  WWTC_onFind = guarded('find', W.onFind)
  WWTC_onHere = guarded('here', W.onHere)
  WWTC_onBaseClaim = guarded('base claim', W.onBaseClaim)
  WWTC_onCorp = guarded('corp', W.onCorp)
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
  MP.RegisterEvent('wwtcBaseClaim', 'WWTC_onBaseClaim')
  MP.RegisterEvent('wwtcCorp', 'WWTC_onCorp')
  MP.RegisterEvent('WWTC_shipTimer', 'WWTC_onShipTimer')
  if MP.CreateEventTimer then MP.CreateEventTimer('WWTC_shipTimer', 15000) end
  WWTC_onShipTimer()
  MP.RegisterEvent('onChatMessage', 'WWTC_onChat')
  MP.RegisterEvent('onConsoleInput', 'WWTC_onConsole')
  print(string.format('[Trucking] plugin loaded: season %d, careers in %s (type "trucking" to list players)',
    W.SEASON, W.seasonDir()))
end

return W
