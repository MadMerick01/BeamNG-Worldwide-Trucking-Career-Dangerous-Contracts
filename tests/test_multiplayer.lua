local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local F = require('fixtures')
local J = require('json')
local P = require('earthFreight/persistence')
local MPC = require('earthFreight/multiplayer')
local Core = require('earthFreight/core')
local SERVER = dir .. '/../server/WorldwideTrucking/main.lua'

-- A fresh server plugin with its files in memory. accounts: pid -> BeamMP account id (nil: a guest).
local function server(files, accounts)
  local W = dofile(SERVER)
  local env = { files = files or {}, sent = {}, printed = {}, counter = 0 }
  env.read = function(path) return env.files[path] end
  env.write = function(path, text) env.files[path] = text; return true end
  env.append = function(path, text) env.files[path] = (env.files[path] or '') .. text end
  env.mkdir = function() end
  env.send = function(pid, event, text) env.sent[#env.sent + 1] = { pid = pid, event = event, data = text } end
  env.encode, env.decode = J.encode, J.decode
  env.bytes = function(i) env.counter = env.counter + 1; return (env.counter * 37 + i) % 256 end
  env.now = function() return '2026-11-08T01:00:00Z' end
  env.account = function(pid) return accounts and accounts[pid] end
  env.name = function(pid) return 'player' .. pid end
  env.time = 1000000
  env.clock = function() return env.time end
  env.epoch = function() return 1000000 end
  env.chats = {}
  env.chat = function(pid, text) env.chats[#env.chats + 1] = { pid = pid, text = text } end
  env.print = function(text) env.printed[#env.printed + 1] = text end
  W.start(env)
  return W, env
end

-- Joins a pid's game to the server: messages go both ways until neither has anything left to say.
local function link(W, env, pid, deliver)
  local queue = {}
  local function send(event, data) queue[#queue + 1] = { event = event, data = data } end
  local function pump()
    for _ = 1, 1000 do
      if #queue > 0 then
        local m = table.remove(queue, 1)
        if m.event == 'wwtcHello' then W.onHello(pid)
        elseif m.event == 'wwtcJoin' then W.onJoin(pid, m.data)
        elseif m.event == 'wwtcSave' then W.onSave(pid, m.data)
        elseif m.event == 'wwtcClaim' then W.onClaim(pid, m.data)
        elseif m.event == 'wwtcRelease' then W.onRelease(pid, m.data)
        elseif m.event == 'wwtcShipDone' then W.onShipDone(pid, m.data)
        elseif m.event == 'wwtcWhere' then W.onWhere(pid, m.data)
        elseif m.event == 'wwtcDelivered' then W.onDelivered(pid, m.data) end
      else
        local found
        for i, m in ipairs(env.sent) do if m.pid == pid then found = i; break end end
        if not found then return end
        local m = table.remove(env.sent, found)
        deliver(m.event, m.data)
      end
    end
    error('the messages never settle')
  end
  return send, pump
end

-- Frames: a long message is split and put back together, in any order, and a bad frame starts over.
do
  local W = server()
  local text = ('abc|def'):rep(10000)
  local frames = W.frames(7, text)
  T.check(#frames > 1, 'a long message is split into frames')
  local inbox, whole = {}, nil
  for i = #frames, 1, -1 do whole = W.receive(inbox, frames[i]) or whole end
  T.eq(whole, text, 'and comes back whole, even out of order')
  T.eq(MPC.receive({}, MPC.frames(1, 'short')[1]), 'short', 'the game reads the same frames')
  T.eq(W.receive({}, 'nonsense'), nil, 'a bad frame is ignored')
  T.eq(W.receive({}, '1|1|1|99999|x'), nil, 'a message bigger than any save is refused')
end

-- Checking a save before keeping it.
do
  local W = server()
  T.check(W.checkSave(F.save(2)), 'a normal save is kept')
  T.eq(select(2, W.checkSave('x')), 'not_a_save', 'text is not a save')
  local bad = F.save(2); bad.progression.balance = 1.5
  T.eq(select(2, W.checkSave(bad)), 'bad_money', 'money must be whole dollars')
  bad = F.save(2); bad.progression.balance = -5
  T.eq(select(2, W.checkSave(bad)), 'bad_money', 'money cannot be below zero')
  T.eq(select(2, W.checkSave(F.save(2), F.save(3))), 'out_of_date', 'an older save than the kept one is refused')
  T.check(W.checkSave(F.save(4), F.save(3)), 'a newer one is kept')
  T.eq(W.ledgerLine('t', 'k', 'Sam\tthe\nTrucker', 5, 10, 3), 't\tk\tSam the Trucker\t5\t10\t3\n', 'ledger lines are one line each')
end

-- The server remembers who it is between restarts, and a first start reads no empty files.
do
  local decoded = {}
  local decode = J.decode
  J.decode = function(text) decoded[#decoded + 1] = text; return decode(text) end
  local W, env = server()
  J.decode = decode
  T.eq(#decoded, 0, 'a first start decodes nothing (BeamMP logs an error for empty text)')
  T.check(W.validKey(W.serverId), 'the server has an id')
  local W2 = server(env.files)
  T.eq(W2.serverId, W.serverId, 'and keeps it after a restart')
end

-- A game on its own, against the server: a guest's first join, a save, and coming back with the key.
local function session(W, env, pid, io)
  local s
  local send, pump = link(W, env, pid, function(event, data) s:receive(event, data) end)
  s = MPC.new({ send = send, encode = J.encode, decode = J.decode, io = io })
  return s, pump
end
do
  local W, env = server()
  local io = F.io()
  local s, pump = session(W, env, 1, io)
  s:start(0); pump()
  T.eq(s.state, 'server', 'the server answers and the game has its career')
  T.check(MPC.store(s, io):load() == nil, 'a new player has no career yet')
  local key = s.key
  T.check(W.validKey(key), 'the guest is given a career key')
  T.eq(io.files[MPC.KEYS][W.serverId], key, 'the game keeps the key for this server')
  T.eq(s:directory(), MPC.ROOT .. W.serverId .. '/season-1/', 'the career is kept in its own folder')
  local store = MPC.store(s, io); store:load()
  local save = F.save(); save.progression.balance = 6000
  T.check(store:save(save), 'a save is written'); pump()
  T.eq(io.files[P.DIRECTORY .. 'save-a.json'], nil, 'the single-player save is never touched')
  T.eq(J.decode(env.files[W.careerPath(key)]).progression.balance, 6000, 'the server keeps the save')
  T.eq(s.saveError, nil, 'and says so')
  T.check(env.files[W.seasonDir() .. '/ledger.tsv']:find('\t6000\t', 1, true) ~= nil, 'the money goes in the ledger')
  T.check(W.report():find('player1 (guest): $6000', 1, true) ~= nil, 'the trucking command lists the player')
  -- The player edits the copy on their PC; the server's career wins on the next join.
  io.files[s:directory() .. 'save-a.json'].progression.balance = 999999
  local s2, pump2 = session(W, env, 2, io)
  s2:start(0); pump2()
  T.eq(s2.key, key, 'the same PC joining again gets the same career')
  local loaded = MPC.store(s2, io):load()
  T.eq(loaded.progression.balance, 6000, 'with the money the server kept, not an edited copy')
  -- Another PC with no key is someone else.
  local s3, pump3 = session(W, env, 3, F.io())
  s3:start(0); pump3()
  T.check(s3.key ~= key, 'another PC is a new guest')
end

-- A signed-in player gets their career back on another PC.
do
  local W, env = server(nil, { [1] = 'acct42', [2] = 'acct42' })
  local s, pump = session(W, env, 1, F.io())
  s:start(0); pump()
  local s2, pump2 = session(W, env, 2, F.io())
  s2:start(0); pump2()
  T.eq(s2.key, s.key, 'a signed-in player has the same career on any PC')
  T.eq(J.decode(env.files[W.DIR .. '/accounts.json']).acct42, s.key, 'the account is remembered')
end

-- The server refuses a save that would roll the career back, and the game says so.
do
  local W, env = server()
  local io = F.io()
  local s, pump = session(W, env, 1, io)
  s:start(0); pump()
  local store = MPC.store(s, io); store:load()
  store:save(F.save()); pump()
  env.files[W.careerPath(s.key)] = J.encode(F.save(50))
  store:save(F.save()); pump()
  T.eq(s.saveError, 'out_of_date', 'an old save does not replace a newer one on the server')
end

-- A new season starts everyone over, and keeps the old season's careers.
do
  local W, env = server()
  local io = F.io()
  local s, pump = session(W, env, 1, io)
  s:start(0); pump()
  local store = MPC.store(s, io); store:load()
  local save = F.save(); save.progression.balance = 50000
  store:save(save); pump()
  local old = W.careerPath(s.key)
  local W2, env2 = server(env.files)
  W2.SEASON = 2
  local s2, pump2 = session(W2, env2, 1, io)
  s2:start(0); pump2()
  T.eq(s2.season, 2, 'the game is told the new season')
  T.eq(MPC.store(s2, io):load(), nil, 'and starts a new career')
  T.check(env2.files[old] ~= nil, 'the last season is kept')
end

-- A server without the plugin: after a wait, the career is kept on this PC, apart from single player.
do
  local io = F.io()
  local sent = {}
  local s = MPC.new({ send = function(e) sent[#sent + 1] = e end, encode = J.encode, decode = J.decode, io = io })
  s:start(0)
  T.eq(sent[1], 'wwtcHello', 'the game asks the server')
  local store = MPC.store(s, io)
  T.eq(select(2, store:load()), 'mp_waiting', 'and waits for its answer')
  T.check(store.blocked, 'nothing can be saved while waiting')
  s:tick(MPC.WAIT_SECONDS + 1)
  T.eq(s.state, 'local', 'no answer: the career is kept on this PC')
  T.eq(s:directory(), MPC.LOCAL, 'in a folder of its own')
  T.check(not s:push(F.save()), 'and nothing is sent')
end

-- The whole game: joining a server shows a wait, then the server's career.
do
  local W, env = server()
  local io = F.io({ [F.CONFIG] = F.config(), [P.DIRECTORY .. 'save-a.json'] = F.save(3) })
  io.files[P.DIRECTORY .. 'save-a.json'].progression.balance = 123
  local c
  local handler
  local send, pump = link(W, env, 1, function(event, data) handler(event, data) end)
  local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
    listen = function(h) handler = h; return true end }
  c = F.controller({ io = io, multiplayer = mp })
  T.eq(c.state, 'ERROR', 'joining waits for the server')
  T.eq(c.loadStatus, 'mp_waiting', 'getting the career')
  pump()
  T.eq(c.loadStatus, 'missing', 'a new player gets a new career on the server')
  T.check(c:view().balance ~= 123, 'not the single-player money')
  T.check(c.feedback:find('new career on this server', 1, true) ~= nil, 'the player is told')
  -- Back in single player, the single-player career is there as it was.
  mp.inSession = function() return false end
  c:endMission(); c:reload()
  T.eq(c.profile.progression.balance, 123, 'single player keeps its own career')
  T.eq(c.mp, nil, 'and talks to no server')
end

-- BeamMP drops a joining player in with no car: after a few seconds the starter car is put down for them, once.
do
  local W, env = server()
  local io = F.io({ [F.CONFIG] = F.config() })
  local handler
  local send, pump = link(W, env, 1, function(event, data) handler(event, data) end)
  local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
    listen = function(h) handler = h; return true end }
  local adapter = F.adapter(); adapter.valid, adapter.reason = false, 'vehicle_required'
  local garage = F.garage()
  local spawned = {}
  function garage:spawnFirst(model, config) spawned[#spawned + 1] = { model = model, config = config }; return true end
  local c = F.controller({ io = io, multiplayer = mp, adapter = adapter, garage = garage })
  F.advance(c, 5)
  T.eq(#spawned, 0, 'no car while the career is still coming from the server')
  pump()
  F.advance(c, 1)
  T.eq(#spawned, 0, 'not straight away')
  F.advance(c, Core.FIRST_CAR_SECONDS + 1)
  T.eq(#spawned, 1, 'a player with no car gets one')
  T.eq(spawned[1].config, Core.STARTER_CONFIG, 'the starter car')
  F.advance(c, 30)
  T.eq(#spawned, 1, 'only once a level')
  c:endMission(); mp.inSession = function() return false end; c:reload()
  F.advance(c, 10)
  T.eq(#spawned, 1, 'never in single player')
end

-- A joining player is told in chat how to turn on the HUD, and !hud says it again, to them alone.
do
  local W, env = server()
  W.welcome(4)
  T.eq(#env.chats, #W.WELCOME, 'every welcome line is sent')
  T.check(env.chats[1].pid == 4, 'to the player who joined')
  local all = ''
  for _, c in ipairs(env.chats) do all = all .. c.text .. '\n' end
  T.check(all:find('+ Add app', 1, true) ~= nil, 'with the steps to add the HUD')
  T.check(W.onChat(5, ' !HUD '), '!hud is answered and hidden from everyone')
  T.eq(env.chats[#env.chats].pid, 5, 'answered to whoever asked')
  T.eq(#env.chats, #W.WELCOME * 2, 'with the same lines')
  T.check(not W.onChat(5, 'hello all'), 'other chat goes through')
  W.WELCOME = {}
  W.welcome(6)
  T.eq(#env.chats, 8, 'an empty welcome sends nothing')
end

-- Ship Day on the server: a ship every few days at the next port, containers first come first served.
do
  local W, env = server(nil, { [1] = 'a1', [2] = 'a2' })
  local first = W.shipAt(env.clock())
  T.eq(first.number, 1, 'the first ship is in port from the start')
  T.eq(first.port.id, W.PORTS[1].id, 'at the first port')
  local later = W.shipAt(env.clock() + W.SHIP_EVERY_HOURS * 3600 + 5)
  T.eq(later.number, 2, 'a new ship every few days')
  T.eq(later.port.id, W.PORTS[2].id, 'at the next port')
  T.near(first.left, W.SHIP_EVERY_HOURS * 3600, 1, 'the first stays the whole time')
  -- Two players on the server.
  for pid = 1, 2 do
    W.onHello(pid); W.onJoin(pid, J.encode({ v = 1 }))
  end
  local function last(pid, event)
    for i = #env.sent, 1, -1 do
      local m = env.sent[i]
      if m.pid == pid and m.event == event then return J.decode(m.data) end
    end
  end
  local ship = last(1, 'wwtcShip')
  T.eq(ship.ship, 1, 'a joining player is told the ship')
  T.eq(ship.containers, W.SHIP_CONTAINERS, 'and how many containers')
  T.eq(ship.port.name, W.PORTS[1].name, 'and the port')
  W.onClaim(1, J.encode({ v = 1, ship = 1, n = 3 }))
  T.check(last(1, 'wwtcClaimed').ok, 'a free container is the first player\'s')
  W.onClaim(2, J.encode({ v = 1, ship = 1, n = 3 }))
  T.eq(last(2, 'wwtcClaimed').why, 'taken', 'and not the second\'s')
  local seen = last(2, 'wwtcShip').taken[1]
  T.check(seen.n == 3 and seen.state == 'taken' and not seen.mine, 'everyone sees it is taken')
  T.check(last(1, 'wwtcShip').taken[1].mine, 'and whose it is')
  W.onClaim(2, J.encode({ v = 1, ship = 9, n = 4 }))
  T.eq(last(2, 'wwtcClaimed').why, 'sailed', 'a container from another ship is refused')
  W.onClaim(1, J.encode({ v = 1, ship = 1, n = 5 }))
  T.eq(#last(2, 'wwtcShip').taken, 1, 'one container at a time: the first goes back')
  W.onRelease(1, J.encode({ v = 1, ship = 1, n = 5 }))
  T.eq(#last(2, 'wwtcShip').taken, 0, 'an abandoned container is free again')
  W.onClaim(1, J.encode({ v = 1, ship = 1, n = 5 }))
  W.onShipDone(1, J.encode({ v = 1, ship = 1, n = 5, town = 'Katoomba', pay = 12340 }))
  T.eq(last(2, 'wwtcShip').taken[1].state, 'delivered', 'a delivered container')
  T.check(env.chats[#env.chats].pid == -1 and env.chats[#env.chats].text:find('Katoomba for $12340', 1, true),
    'is announced to everyone')
  W.onRelease(1, J.encode({ v = 1, ship = 1, n = 5 }))
  T.eq(last(2, 'wwtcShip').taken[1].state, 'delivered', 'and stays delivered')
  -- A restart keeps the ship's containers.
  local W2, env2 = server(env.files)
  env2.time = env.time
  W2.onHello(1); W2.onJoin(1, J.encode({ v = 1 }))
  local after = J.decode(env2.sent[#env2.sent].data)
  T.check(#after.taken == 1 and after.taken[1].state == 'delivered', 'a restart keeps the ship\'s containers')
  local kept = J.decode(env.files[W.seasonDir() .. '/ships.json'])
  T.eq(kept.ship, 1, 'the ship is kept on disk'); T.eq(#kept.boxes, 1, 'with its containers')
  -- The next ship.
  local chats = #env.chats
  env.time = env.time + W.SHIP_EVERY_HOURS * 3600 + 1
  W.shipTick()
  T.check(env.chats[chats + 1] and env.chats[chats + 1].text:find('Ship Day!', 1, true), 'a new ship is announced')
  T.eq(last(2, 'wwtcShip').ship, 2, 'everyone is told')
  T.eq(#last(2, 'wwtcShip').taken, 0, 'with every container free')
  W.SHIP_CONTAINERS = 0
  local before = #env.sent
  W.sendShipToAll()
  T.eq(#env.sent, before, 'no containers: Ship Day is off')
end

-- Ship Day in the game: go to the port, take a container, drive it inland, get paid, and the server hears of it.
do
  local SD = require('earthFreight/shipday')
  local places = require('earthFreight/places')
  local W, env = server()
  W.PORTS = { { id = 'sydney', name = 'Port Jackson', region = 'Sydney', latitude = -33.86, longitude = 151.21 } }
  local io = F.io({ [F.CONFIG] = F.config() })
  local handler
  local send, pump = link(W, env, 1, function(event, data) handler(event, data) end)
  local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
    listen = function(h) handler = h; return true end }
  local c, _, a, g = F.controller({ io = io, multiplayer = mp })
  g.fitted.box = 'pickup_cargo_load_box_m'
  pump()
  F.advance(c, 2)
  if not c.arrived then c:startHere(); F.advance(c, 2) end
  local v = c:view().shipDay
  T.check(v ~= nil, 'the Town tab shows Ship Day')
  T.eq(v.port, 'Port Jackson', 'with the port'); T.eq(v.total, W.SHIP_CONTAINERS, 'and its containers')
  T.eq(v.free, W.SHIP_CONTAINERS, 'all free')
  T.check(not v.atPort and v.goAllowed, 'Go to port, from Penrith')
  T.check(not c:takeContainer(1), 'no container away from the port')
  local town = SD.portTown(c.ship)
  T.check(town ~= nil and places.get(town.id) ~= nil, 'the ship docks at a town')
  -- Every game works out the same containers.
  local boxes = SD.containers(c.ship)
  T.eq(#boxes, W.SHIP_CONTAINERS, 'a destination for every container')
  for _, box in ipairs(boxes) do
    T.check(box.km >= SD.MIN_KM and box.km <= SD.MAX_KM, 'container ' .. box.n .. ' goes inland, ' .. math.floor(box.km) .. ' km')
  end
  local balance = c.profile.progression.balance
  T.check(c:goToPort(), 'Go to port')
  T.eq(a.teleports[#a.teleports].latitude, town.latitude, 'teleports to the port town centre, on land')
  T.eq(c.profile.progression.balance, balance, 'for free')
  a.pose = F.copy(town); F.advance(c, 3)
  v = c:view().shipDay
  T.check(v.atPort, 'at the port')
  T.check(v.containers[1].allowed, 'a container can be taken')
  T.check(v.containers[1].pay > 0, 'and pays')
  T.check(c:takeContainer(1), 'asks for container 1')
  T.eq(c.load, nil, 'loaded only once the server says so')
  pump()
  T.check(c.load ~= nil and c.load.ship and c.load.ship.n == 1, 'container 1 is loaded')
  T.eq(c.load.to, boxes[1].to, 'bound for its town')
  T.eq(c:view().shipDay.containers[1].state, 'mine', 'and shows as mine')
  T.eq(c:view().shipDay.carrying, 1, 'the card says which one is on board')
  F.advance(c, Core.WHERE_SECONDS + 1); pump()
  local where = W.players[1].where
  T.check(where and where.town == town.name, 'the server page is told the town, by name')
  T.check(where.doing:find('container 1', 1, true) ~= nil, 'and what the player is doing')
  T.eq(where.latitude, math.floor(town.latitude * 100 + 0.5) / 100, 'the town centre, never the player\'s own spot')
  -- A save keeps the container on board.
  T.check(c:manualSave(), 'saved with a container on board'); pump()
  local kept = J.decode(env.files[W.careerPath(c.mp.key)])
  T.eq(kept.load.ship.n, 1, 'the server keeps the container on board')
  T.eq(P.validate(kept).load.ship.n, 1, 'and a save with one loads again')
  local pay = c.load.pay
  F.drive(c, a, places.get(boxes[1].to))
  balance = c.profile.progression.balance
  T.check(c:deliver(), 'delivered inland')
  T.eq(c.profile.progression.balance, balance + pay, 'paid')
  pump()
  T.check(env.chats[#env.chats].text:find(places.get(boxes[1].to).name, 1, true) ~= nil, 'the server tells everyone')
  T.check(W.stats.feed[1].text:find('container 1', 1, true) ~= nil, 'the delivery is in the page\'s feed')
  T.eq(W.status().today.deliveries, 1, 'and in today\'s totals')
  T.eq(c:view().shipDay.containers[1].state, 'delivered', 'and it shows delivered')
  -- Another claim the server refuses.
  F.drive(c, a, town)
  W.claims.boxes[2] = { key = 'f' .. ('0'):rep(31), name = 'Sam', delivered = false }
  T.check(c:takeContainer(2), 'asks for container 2 (taken by now)')
  pump()
  T.eq(c.load, nil, 'not loaded')
  T.check(c:view().shipDay.feedback:find('first', 1, true) ~= nil, 'someone else got it first')
  -- An abandoned container goes back to the dock.
  T.check(c:takeContainer(3)); pump()
  c:abandonJob(); c:abandonJob(); pump()
  T.eq(W.claims.boxes[3], nil, 'an abandoned container is free again')
  -- A dock that never answers.
  local quiet = c.mp.claim
  c.mp.claim = function() return true end
  T.check(c:takeContainer(4))
  F.advance(c, SD.CLAIM_WAIT_SECONDS + 1)
  T.eq(c.shipClaim, nil, 'a claim the server never answers is dropped')
  c.mp.claim = quiet
end

-- The server page's stats: who's on and where, the feed, today's totals and the leaderboard; sent to GitHub.
do
  local W, env = server(nil, { [1] = 'a1' })
  env.date = function() return '2026-11-08' end
  W.onHello(1); W.onJoin(1, J.encode({ v = 1 }))
  T.eq(W.stats.feed[1].text, 'player1 joined the server.', 'a join is in the feed')
  W.onWhere(1, J.encode({ town = 'Quillota', region = 'Chile', latitude = -32.8812345, longitude = -71.2498765, doing = 'Carrying\n parts' }))
  local st = W.status()
  T.eq(st.players[1].town, 'Quillota', 'players are shown by town')
  T.eq(st.players[1].latitude, -32.88, 'at the town, to a kilometre or so')
  T.eq(st.players[1].doing, 'Carrying  parts', 'no line breaks from a game')
  W.onDelivered(1, J.encode({ kind = 'job', what = '12 parts', from = 'Penrith', to = 'St Clair', pay = 3400 }))
  T.eq(W.stats.feed[1].text, 'player1 delivered 12 parts from Penrith to St Clair for $3,400.', 'a delivery in the feed')
  W.onDelivered(1, J.encode({ kind = 'contract', to = 'Death Road', pay = 1234567 }))
  T.eq(W.stats.feed[1].text, 'player1 finished the Death Road dangerous contract for $1,234,567.', 'a dangerous contract')
  W.onDelivered(1, J.encode({ kind = 'job', pay = -5 }))
  st = W.status()
  T.eq(st.today.deliveries, 3, 'today\'s deliveries'); T.eq(st.today.earned, 3400 + 1234567, 'and money, never below zero')
  T.eq(st.leaderboard[1].deliveries, 3, 'counted on the leaderboard')
  T.eq(st.season.number, W.SEASON, 'the season'); T.eq(st.season.day, 1, 'its first day'); T.eq(st.season.truckers, 1, 'one trucker')
  T.check(st.ship and st.ship.port == W.PORTS[1].name and st.ship.sailsAt:match('^%d+%-%d+%-%d+T'), 'Ship Day with when it sails')
  T.eq(st.ship.next.port, W.PORTS[2].name, 'and the next port')
  env.date = function() return '2026-11-09' end
  T.eq(W.status().today.deliveries, 0, 'today starts again at midnight')
  -- A save puts the money on the leaderboard.
  W.boardCareer(W.players[1], { progression = { balance = 50000, jobsDone = 9 } })
  T.eq(W.status().leaderboard[1].balance, 50000, 'the money at the last save')
  -- Kept over a restart.
  local W2 = server(env.files)
  T.eq(#W2.stats.feed, #W.stats.feed, 'the feed survives a restart')
  for i = 1, W.FEED_MAX + 5 do W.feed('join', 'x' .. i) end
  T.eq(#W.stats.feed, W.FEED_MAX, 'the feed keeps the latest few')
  -- base64, for GitHub.
  T.eq(W.base64('Man'), 'TWFu', 'base64'); T.eq(W.base64('Ma'), 'TWE=', 'base64 2'); T.eq(W.base64('M'), 'TQ==', 'base64 1')
  T.eq(W.base64('é'), 'w6k=', 'and UTF-8')
  -- Sending to GitHub.
  local runs = {}
  env.run = function(cmd)
    runs[#runs + 1] = cmd
    if cmd:find('-X PUT', 1, true) then return '{"content":{"sha":"new1"}}' end
    return '{"sha":"old1"}'
  end
  W.STATS_REPO = ''
  T.check(not W.pushStats('{}'), 'nothing is sent without a repo')
  W.STATS_REPO = 'MadMerick01/trucking-server-stats'
  T.check(not W.pushStats('{}'), 'or without a token'); T.eq(#runs, 0, 'and curl never runs')
  env.files[W.DIR .. '/github-token.txt'] = 'github_pat_ABC123\n'
  T.check(W.pushStats('{"a":1}'), 'sent once there is a token')
  T.eq(#runs, 2, 'reads the file\'s version, then sends it')
  T.check(runs[2]:find('https://api.github.com/repos/MadMerick01/trucking-server-stats/contents/status.json', 1, true) ~= nil, 'to the repo')
  for _, cmd in ipairs(runs) do T.check(not cmd:find('ABC123', 1, true), 'the token is never on the command line') end
  local body = J.decode(env.files[W.DIR .. '/.github-body.json'])
  T.eq(body.sha, 'old1', 'replacing the version it read'); T.eq(body.content, W.base64('{"a":1}'), 'with the stats')
  T.check(W.pushStats('{}'), 'sent again'); T.eq(#runs, 3, 'next time it already knows the version')
  -- GitHub refuses: it reads the version again and tries once more, then gives up quietly.
  env.run = function(cmd) runs[#runs + 1] = cmd; return '{"message":"Bad credentials"}' end
  local before = #runs
  T.check(not W.pushStats('{}'), 'refused')
  T.eq(#runs - before, 3, 'one more try after reading the version again')
  -- The timer: status.json is written here, and sent when due.
  W.statsSentAt, W.statsChanged = nil, true
  env.run = function() return '{"content":{"sha":"x"}}' end
  W.statsTick()
  T.check(J.decode(env.files[W.DIR .. '/status.json']).version == 1, 'status.json is written next to the plugin')
  local sent = W.statsSentAt
  env.time = env.time + 60; W.statsTick()
  T.eq(W.statsSentAt, sent, 'not again straight away')
  env.time = env.time + 600; W.statsTick()
  T.check(W.statsSentAt > sent, 'but every 10 minutes even when nothing changed')
end

-- Restarting for an update: warnings in chat, every game saves itself, everyone is sent off, and the script is told.
do
  local W, env = server()
  local kicked = {}
  env.kick = function(pid, why) kicked[#kicked + 1] = { pid = pid, why = why } end
  env.remove = function(path) env.files[path] = nil end
  env.players = function() return {} end
  env.files[W.RESTART_FILE] = J.encode({ at = env.time + 600, why = 'BeamNG.Earth 1.9.1-beta' })
  W.restartTick()
  T.eq(env.files[W.RESTART_FILE], nil, 'with nobody on, the server is ready for the update straight away')
  T.eq(#env.chats, 0, 'and says nothing')
  -- With a player on.
  local io = F.io({ [F.CONFIG] = F.config() })
  local handler
  local send, pump = link(W, env, 1, function(event, data) handler(event, data) end)
  local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
    listen = function(h) handler = h; return true end }
  local c = F.controller({ io = io, multiplayer = mp })
  pump()
  F.advance(c, 2)
  if not c.arrived then c:startHere(); F.advance(c, 2) end
  T.check(c:manualSave()); pump()
  env.players = function() return { [1] = 'player1' } end
  env.chats = {}
  env.files[W.RESTART_FILE] = J.encode({ at = env.time + 600, why = 'BeamNG.Earth 1.9.1-beta' })
  W.restartTick()
  T.eq(#env.chats, 1, 'everyone is warned')
  T.check(env.chats[1].text:find('10 minutes (BeamNG.Earth 1.9.1-beta)', 1, true) ~= nil, 'when, and why')
  env.time = env.time + 15; W.restartTick()
  T.eq(#env.chats, 1, 'once')
  env.time = env.time + 300; W.restartTick()
  T.check(env.chats[#env.chats].text:find('5 minutes', 1, true) ~= nil, 'and again at 5 minutes')
  T.check(env.files[W.RESTART_FILE] ~= nil, 'not ready yet')
  -- A minute and a half before, every game saves itself.
  c.profile.progression.balance = 7777
  local generation = c.profile.generation
  env.time = env.time + 200; W.restartTick(); pump()
  T.check(c.profile.generation > generation, 'the game saved itself')
  T.eq(J.decode(env.files[W.careerPath(c.mp.key)]).progression.balance, 7777, 'and the server has it')
  T.check(c.feedback:find('Saved for the server update', 1, true) ~= nil, 'the player is told')
  T.eq(#kicked, 0, 'nobody is sent off early')
  env.time = env.time + 100; W.restartTick()
  T.eq(#kicked, 1, 'at the time, everyone is sent off')
  T.check(kicked[1].why:find('career is kept', 1, true) ~= nil, 'with a message')
  T.eq(env.files[W.RESTART_FILE], nil, 'and the script is told the server is ready')
  -- An update called off.
  env.chats = {}
  env.files[W.RESTART_FILE] = J.encode({ at = env.time + 600 })
  W.restartTick()
  env.files[W.RESTART_FILE] = nil
  W.restartTick()
  T.check(env.chats[#env.chats].text:find('update is off', 1, true) ~= nil, 'a cancelled update is called off in chat')
end

T.done('multiplayer careers')
