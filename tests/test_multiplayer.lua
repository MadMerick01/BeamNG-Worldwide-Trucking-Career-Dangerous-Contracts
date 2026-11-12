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
        elseif m.event == 'wwtcDelivered' then W.onDelivered(pid, m.data)
        elseif m.event == 'wwtcFind' then W.onFind(pid, m.data)
        elseif m.event == 'wwtcHere' then W.onHere(pid, m.data)
        elseif m.event == 'wwtcBaseClaim' then W.onBaseClaim(pid, m.data)
        elseif m.event == 'wwtcCorp' then W.onCorp(pid, m.data) end
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
  for t = 1, MPC.WAIT_SECONDS + 1 do s:tick(t) end
  T.eq(s.state, 'local', 'no answer: the career is kept on this PC')
  T.eq(s:directory(), MPC.LOCAL, 'in a folder of its own')
  T.check(not s:push(F.save()), 'and nothing is sent')
  local hellos = 0
  for _, e in ipairs(sent) do if e == 'wwtcHello' then hellos = hellos + 1 end end
  T.check(hellos >= 4, 'it asked again while waiting')
  s:tick(MPC.LATE_FOR + 100); s:tick(MPC.LATE_FOR + 200)
  local after = 0
  for _, e in ipairs(sent) do if e == 'wwtcHello' then after = after + 1 end end
  T.eq(after, hellos + 0, 'and stops asking in the end')
end

-- A first question lost while BeamMP is still joining: asked again, the server's career comes.
do
  local W, env = server()
  local io = F.io()
  local s
  local dropped = false
  local send, pump = link(W, env, 1, function(event, data) s:receive(event, data) end)
  s = MPC.new({ send = function(e, d) if e == 'wwtcHello' and not dropped then dropped = true; return end; send(e, d) end,
    encode = J.encode, decode = J.decode, io = io })
  s:start(0); pump()
  T.eq(s.state, 'waiting', 'the first question was lost')
  s:tick(MPC.HELLO_EVERY); pump()
  T.eq(s.state, 'server', 'asked again, the server answers')
  local joins = 0
  for _, line in ipairs(env.printed) do if line:find('joined', 1, true) then joins = joins + 1 end end
  T.eq(joins, 1, 'one join')
  s:tick(MPC.HELLO_EVERY * 3)
  local queued = 0
  for _, m in ipairs(env.sent) do if m.pid == 1 then queued = queued + 1 end end
  T.eq(queued, 0, 'and nothing more is asked')
end

-- A server that answers only after the game gave up: its career replaces the one kept on this PC.
do
  local W, env = server()
  local io = F.io({ [F.CONFIG] = F.config() })
  local handler, deaf = nil, true
  local send, pump = link(W, env, 1, function(event, data) handler(event, data) end)
  local mp = { inSession = function() return true end, encode = J.encode, decode = J.decode,
    send = function(e, d) if not deaf then send(e, d) end end, listen = function(h) handler = h; return true end }
  local c = F.controller({ io = io, multiplayer = mp })
  F.advance(c, MPC.WAIT_SECONDS + 2)
  T.eq(c.mp.state, 'local', 'no answer in time: kept on this PC')
  deaf = false
  F.advance(c, MPC.LATE_EVERY + 1); pump()
  T.eq(c.mp.state, 'server', 'a late answer joins the server')
  T.check(c.feedback:find('new career on this server', 1, true) ~= nil, 'and loads its career')
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
  T.eq(c:view().online, true, 'the start page calls it the career on this server')
  T.check(c.feedback:find('new career on this server', 1, true) ~= nil, 'the player is told')
  -- Back in single player, the single-player career is there as it was.
  mp.inSession = function() return false end
  c:endMission(); c:reload()
  T.eq(c.profile.progression.balance, 123, 'single player keeps its own career')
  T.eq(c.mp, nil, 'and talks to no server')
  T.eq(c:view().online, nil, 'and calls it the offline career again')
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

-- Ship Day on the server: a ship every day at the next port, containers first come first served.
do
  local W, env = server(nil, { [1] = 'a1', [2] = 'a2' })
  local first = W.shipAt(env.clock())
  T.eq(first.number, 1, 'the first ship is in port from the start')
  T.eq(first.port.id, W.PORTS[1].id, 'at the first port')
  local later = W.shipAt(env.clock() + W.SHIP_EVERY_HOURS * 3600 + 5)
  T.eq(later.number, 2, 'a new ship every day')
  T.eq(W.SHIP_EVERY_HOURS, 24, 'one new ship a day')
  T.eq(W.SHIP_CONTAINERS, 5, 'with 5 containers')
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
  local jobs = require('earthFreight/jobs')
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
  -- The load slider: a share of a full load, and that share of the pay.
  local full = c:containerQuote(boxes[5])
  T.check(c:takeContainer(5, 50)); pump()
  local half = jobs.share(full.units, full.pay, 50)
  T.eq(c.load.units, half, 'half a load on the slider takes half the units')
  T.check(c.load.units < full.units and c.load.pay < full.pay, 'and pays less than a full load')
  c:abandonJob(); c:abandonJob(); pump()
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
  T.eq(W.status().leaderboard[1].truckValue, 0, 'no truck worth known yet')
  -- Ranked by wealth: money plus the truck's worth, not money alone.
  W.boardCareer(W.players[1], { progression = { balance = 50000, jobsDone = 9 }, vehicle = { worth = 30000 } })
  local richer = { key = string.rep('b', 32), name = 'Cashy' }
  W.boardCareer(richer, { progression = { balance = 70000, jobsDone = 2 }, vehicle = { worth = 1000 } })
  local board = W.status().leaderboard
  T.eq(board[1].wealth, 80000, 'money and truck together'); T.eq(board[1].truckValue, 30000, 'the truck at the last save')
  T.eq(board[2].name, 'Cashy', 'more cash but less wealth ranks below')
  W.boardCareer(richer, { progression = { balance = 70000 }, vehicle = { value = 15000 } })
  T.eq(W.status().leaderboard[1].name, 'Cashy', 'an older game: a second-hand truck counts what was paid')
  W.boardCareer(richer, { progression = { balance = 70000 }, vehicle = { worth = -5 } })
  T.eq(W.status().leaderboard[1].truckValue, 15000, 'a bad worth is ignored')
  -- A base of operations counts as wealth too.
  W.boardCareer(W.players[1], { progression = { balance = 50000 }, vehicle = { worth = 30000 }, property = { paid = 250000 } })
  board = W.status().leaderboard
  T.eq(board[1].baseValue, 250000, 'the base at what was paid'); T.eq(board[1].wealth, 330000, 'cash, truck and base')
  -- So does a trailer, at what was paid for it and its parts.
  W.boardCareer(W.players[1], { progression = { balance = 50000 }, vehicle = { worth = 30000 }, property = { paid = 250000 },
    trailer = { paid = 26000 } })
  board = W.status().leaderboard
  T.eq(board[1].trailerValue, 26000, 'the trailer at what was paid'); T.eq(board[1].wealth, 356000, 'cash, truck, trailer and base')
  W.boardCareer(W.players[1], { progression = { balance = 50000 }, vehicle = { worth = 30000 }, property = { paid = 250000 },
    trailer = { paid = -3 } })
  T.eq(W.status().leaderboard[1].trailerValue, 0, 'a bad trailer price is ignored')
  -- A second trailer kept at the base counts too.
  W.boardCareer(W.players[1], { progression = { balance = 50000 }, vehicle = { worth = 30000 }, property = { paid = 250000 },
    trailer = { paid = 26000 }, spareTrailer = { paid = 4000 } })
  board = W.status().leaderboard
  T.eq(board[1].trailerValue, 30000, 'both trailers at what was paid'); T.eq(board[1].wealth, 360000, 'in wealth')
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

-- Relocate to a player: two truckers on one server, one joins the other for the usual fee, and nobody else learns
-- where anyone is.
do
  local location = require('earthFreight/location')
  local shipping = require('earthFreight/shipping')
  local W, env = server()
  W.SHIP_CONTAINERS = 0
  local function game(pid, pose)
    local io = F.io({ [F.CONFIG] = F.config() })
    local handler
    local send, pump = link(W, env, pid, function(event, data) handler(event, data) end)
    local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
      listen = function(h) handler = h; return true end }
    local a = F.adapter(pose)
    local c = F.controller({ io = io, multiplayer = mp, adapter = a })
    pump()
    F.advance(c, 2)
    if not c.arrived then c:startHere(); F.advance(c, 2) end
    pump()
    return c, a, pump, io
  end
  local penrith = F.copy(F.PENRITH)
  local katoomba = { latitude = -33.7198, longitude = 150.3074 }
  local c1, a1, pump1 = game(1, penrith)
  local c2, a2, pump2, io2 = game(2, katoomba)
  local function pump() for _ = 1, 3 do pump1(); pump2() end end
  F.advance(c2, Core.WHERE_SECONDS + 1); pump()
  W.sendPlayersToAll(); pump()
  local v = c1:view().shipping.players
  T.check(v ~= nil, 'the Relocate tab lists players on a server')
  T.eq(#v.list, 1, 'everyone else, not yourself'); T.eq(v.list[1].name, 'player2', 'by name')
  T.check(v.list[1].town ~= nil, 'and town'); T.check(v.list[1].fee > 0 and v.list[1].allowed, 'with about what it costs')
  T.eq(v.list[1].latitude, nil, 'never their spot')
  T.check(v.findable, 'others can relocate to you, unless you turn it off')
  -- Join: player 2's game says where it is, only player 1 hears, and the usual relocation is booked and taken.
  local sample2 = a2.sample
  a2.sample = function(self) local t = sample2(self); if t.valid then t.heading = 90 end; return t end
  F.advance(c2, 0.2)
  local balance = c1.profile.progression.balance
  local sent = #env.sent
  T.check(c1:findPlayer(2), 'Join asks the server')
  pump()
  for i = sent + 1, #env.sent do
    local m = env.sent[i]
    if m and m.event == 'wwtcFound' then T.eq(m.pid, 1, 'the spot goes to the player who asked only') end
  end
  T.check(c1.booking ~= nil and c1.booking.id == 'player', 'a relocation to the player is booked')
  local fee = c1.booking.fee
  T.eq(fee, shipping.fee(penrith, c1.booking), 'for the usual fee')
  T.eq(c1.profile.progression.balance, balance - fee, 'paid')
  local landed = a1.teleports[#a1.teleports]
  T.check(landed ~= nil, 'and teleported')
  local away = location.distance(landed, katoomba)
  T.check(away > 1 and away < 50, 'next to them (' .. math.floor(away) .. ' m)')
  T.check(c1.shippingFeedback:find('player2', 1, true) ~= nil, 'the player is told who they are going to')
  a1.pose = F.copy(landed); F.advance(c1, 3)
  T.eq(c1.booking, nil, 'arriving uses the booking'); T.eq(c1.stranded, nil, 'and counts as a relocation')
  T.check(location.bearing(katoomba, landed) > 260 and location.bearing(katoomba, landed) < 280, 'behind their car, which faces east')
  T.eq(next(W.asks), nil, 'the server keeps nothing of it')
  -- Turned off: player 2 says no, and it stays off.
  T.check(c2:setFindable(false))
  T.check(not c2:view().shipping.players.findable, 'turned off')
  T.eq(io2.files['/settings/earthFreight/mp/prefs.json'].findable, false, 'kept on the PC')
  a1.pose = F.copy(penrith); c1.stranded = nil; F.advance(c1, 2)
  T.check(c1:findPlayer(2)); pump()
  T.eq(c1.booking, nil, 'no booking'); T.check(c1.shippingFeedback:find('does not let', 1, true) ~= nil, 'told why')
  c2:setFindable(true)
  -- Not in their car.
  c2.onFoot = true
  local onFoot = c2.garage.onFoot
  c2.garage.onFoot = function() return true end
  F.advance(c2, 0.2)
  T.check(c1:findPlayer(2)); pump()
  T.eq(c1.booking, nil, 'no booking while they are on foot')
  T.check(c1.shippingFeedback:find('not driving', 1, true) ~= nil, 'told to try again')
  c2.garage.onFoot = onFoot; F.advance(c2, 0.2)
  -- Not with cargo on board.
  c1.load = { good = 'parts', units = 1 }
  T.check(not c1:findPlayer(2), 'not on a job'); T.check(c1.shippingFeedback:find('cargo', 1, true) ~= nil, 'told why')
  c1.load = nil
  -- A game that never answers.
  local here = c2.mp.here
  c2.mp.here = function() return true end
  T.check(c1:findPlayer(2)); pump()
  T.check(not c1:findPlayer(2), 'one ask at a time')
  F.advance(c1, Core.FIND_WAIT_SECONDS + 1)
  T.eq(c1.finding, nil, 'given up on'); T.check(c1.shippingFeedback:find('did not answer', 1, true) ~= nil, 'and told')
  c2.mp.here = here
  -- Gone.
  W.onLeave(2); pump()
  T.eq(#c1:view().shipping.players.list, 0, 'a player who leaves is off the list')
  T.check(not c1:findPlayer(2), 'and cannot be joined')
  -- A forged answer from someone who wasn't asked goes nowhere.
  W.onFind(1, J.encode({ v = 1, to = 1 }))
  T.eq(next(W.asks), nil, 'you cannot ask for yourself')
  W.onHere(1, J.encode({ v = 1, ask = 999, ok = true, latitude = 1, longitude = 1 }))
  T.eq(next(W.asks), nil, 'an answer nobody asked for is dropped')
end

-- The Magnate update on a server: a base is asked of the server (one a town, 300 km apart), everyone sees everyone's
-- circles, delivering in someone else's turf pays them a 20% toll, and the page shows the circles.
do
  local W, env = server()
  W.SHIP_CONTAINERS = 0
  local function game(pid, pose)
    local io = F.io({ [F.CONFIG] = F.config() })
    local handler
    local send, pump = link(W, env, pid, function(event, data) handler(event, data) end)
    local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
      listen = function(h) handler = h; return true end }
    local a = F.adapter(pose)
    local c = F.controller({ io = io, multiplayer = mp, adapter = a })
    pump()
    F.advance(c, 2)
    if not c.arrived then c:startHere(); F.advance(c, 2) end
    pump()
    return c, a, pump, io
  end
  local ropes = { latitude = -33.7328, longitude = 150.791 } -- Ropes Crossing, 8.6 km from Penrith
  local c1, a1, pump1 = game(1, F.copy(F.PENRITH))
  local c2, a2, pump2 = game(2, ropes)
  local function pump() for _ = 1, 3 do pump1(); pump2() end end
  c1.profile.progression.balance, c2.profile.progression.balance = 400000, 400000
  F.advance(c1, 0.6); F.advance(c2, 0.6)
  local before = {}
  for _, j in ipairs(c2:view().town.jobs) do before[j.id] = j.pay end
  -- Player 1 buys in Penrith: the server is asked first, and says yes.
  T.check(c1:claimHome(), 'Buy asks the server'); T.eq(c1.property, nil, 'nothing bought before it answers')
  T.eq(c1:claimProblem(), 'Asking the server...', 'and Buy waits for it')
  pump()
  T.check(c1.property ~= nil, 'bought once the server says yes'); T.eq(c1.property.town.name, 'Penrith', 'in Penrith')
  T.eq(c1:view().balance, 400000 - 250000, 'paid')
  -- Player 2 sees it, and can't buy within 300 km of it.
  local others = c2:view().home.others
  T.check(others and others[1].name == 'player1' and others[1].town == 'Penrith', 'the other base is listed')
  T.check(others[1].inside, 'and player 2 is inside its circle'); T.eq(others[1].latitude, nil, 'never a spot')
  T.check(c2:claimProblem():find('Too close to player1', 1, true), 'too close to buy')
  -- Player 2's jobs here drop off in player 1's turf: the board shows the 20% toll, and the pay after it.
  local magnate = require('earthFreight/magnate')
  local town, taken = 0, nil
  for _, j in ipairs(c2:view().town.jobs) do
    if not j.contract and j.units > 0 then
      town = town + 1
      T.eq(j.tollTo, 'player1', 'the toll goes to player 1 on ' .. j.id); T.eq(j.tollPercent, 20, 'and is 20%')
      T.eq(j.basePercent, nil, 'no visitors\' bonus on ' .. j.id)
      T.eq(j.pay, (magnate.afterToll(before[j.id])), 'paid 20% less on ' .. j.id)
      if not taken and not j.drop then taken = j end
    end
  end
  T.check(town > 0, 'jobs checked')
  T.check(c2:takeJob(taken.id), 'job taken')
  T.eq(c2.load.toll.owner, 'player1', 'the job keeps who its toll goes to')
  T.eq(c2.load.toll.amount, select(2, magnate.afterToll(before[taken.id])), 'and how much')
  c2:abandonJob()
  -- Player 1's own jobs pay no toll.
  for _, j in ipairs(c1:view().town.jobs) do T.eq(j.tollTo, nil, 'no toll in your own turf on ' .. j.id) end
  -- Even if player 2's game didn't know, the server refuses: one base within 300 km.
  W.onBaseClaim(2, J.encode({ v = 1, town = 'Ropes Crossing', latitude = ropes.latitude, longitude = ropes.longitude, boost = 1 }))
  local answer = J.decode(env.sent[#env.sent].data)
  T.check(not answer.ok and answer.why == 'too_close' and answer.by == 'player1', 'the server refuses too')
  -- The save confirms the base, with its owner's best wealth, and the page shows the circle at the town.
  F.advance(c1, 0.6); T.check(c1:manualSave(), 'saved'); pump()
  local key = c1.mp.key
  T.eq(W.bases[key].asked, nil, 'the base is confirmed by the save'); T.check(W.bases[key].peak >= 400000, 'with the best wealth')
  local st = W.status()
  T.eq(#st.bases, 1, 'one base on the page'); T.eq(st.bases[1].town, 'Penrith', 'at its town')
  T.check(st.bases[1].radiusKm >= 1600, 'with its circle')
  T.near(st.bases[1].latitude, 0, 90, 'a town centre'); T.eq(st.leaderboard[1].baseTown, 'Penrith', 'and the leaderboard names it')
  -- The toll: player 2's delivery from Ropes Crossing to Penrith, in player 1's turf, pays player 1 what player 2's game
  -- took off the pay.
  local town = { latitude = -33.75, longitude = 150.7 }
  local balance1, balance2 = c1.profile.progression.balance, c2.profile.progression.balance
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, from = 'Ropes Crossing', to = 'Penrith', ends = { ropes, town } }))
  T.eq(W.bases[key].batch.amount, 200, 'the toll goes to the turf\'s owner'); T.eq(c2.profile.progression.balance, balance2, 'the server takes nothing more from the driver')
  pump(); F.advance(c1, 0.6)
  T.eq(c1.profile.progression.balance, balance1 + 200, 'paid into the owner\'s money')
  T.eq(c1.profile.commissionId, W.bases[key].batch and W.bases[key].batch.id or c1.profile.commissionId, 'once, by its batch')
  F.advance(c1, 4); pump()
  T.eq(W.bases[key].batch, nil, 'the save tells the server it is paid')
  -- Sent again (a lost answer), it isn't paid twice.
  c1.mp.commission = { id = c1.profile.commissionId, amount = 200, jobs = 1 }; F.advance(c1, 0.6)
  T.eq(c1.profile.progression.balance, balance1 + 200, 'never paid twice')
  -- No toll on the owner's own deliveries, on a drop-off outside every turf (even from inside one), or with none taken.
  local far = { latitude = 10, longitude = 10 }
  W.onDelivered(1, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, ends = { ropes, town } }))
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, ends = { town, far } }))
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 1000, ends = { ropes, town } }))
  T.eq(W.bases[key].batch, nil, 'nothing for your own jobs, far away or without a toll')
  -- A game can't claim a bigger toll than 20% of the pay.
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 5000, ends = { ropes, town } }))
  T.eq(W.bases[key].batch.amount, 210, 'at most 20% of the whole pay')
  -- No daily limit: it's money moving between players.
  for _ = 1, 30 do W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 16000, toll = 4000, ends = { ropes, town } })) end
  local b = W.bases[key]
  T.eq(b.batch.amount + b.owed, 210 + 30 * 4000, 'no daily limit')
  -- Dangerous contracts pay none.
  local owed = b.owed
  W.onDelivered(2, J.encode({ v = 1, kind = 'contract', pay = 5000, toll = 1000, ends = { ropes, town } }))
  T.eq(b.owed, owed, 'no toll on a dangerous contract')
  local W2 = server(env.files)
  T.check(W2.bases[key] ~= nil and W2.bases[key].town == 'Penrith', 'bases survive a restart')
  -- A base asked for but never saved is let go after a while, and the town is free again.
  W.onBaseClaim(2, J.encode({ v = 1, town = 'Faraway', latitude = -31.95, longitude = 115.86, boost = 1 }))
  local held = W.bases[c2.mp.key]
  T.check(held ~= nil and held.asked ~= nil, 'held while the game buys it')
  env.time = env.time + W.BASE_ASK_SECONDS + 1
  W.onBaseClaim(1, J.encode({ v = 1, town = 'Nowhere', latitude = 10, longitude = 10, boost = 1 }))
  T.eq(W.bases[c2.mp.key], nil, 'and let go when no save ever has it')
end

-- Corps (Magnate 3): a player without a base asks to join one, the owner accepts; members pay no toll in its turf,
-- get +0.2 there and a yard at the owner's spot, half their wealth grows the circle, and leaving or being removed
-- trades in the car in the yard and makes them wait before joining another.
do
  local W, env = server()
  W.SHIP_CONTAINERS = 0
  local function game(pid, pose)
    local io = F.io({ [F.CONFIG] = F.config() })
    local handler
    local send, pump = link(W, env, pid, function(event, data) handler(event, data) end)
    local mp = { inSession = function() return true end, send = send, encode = J.encode, decode = J.decode,
      listen = function(h) handler = h; return true end }
    local c = F.controller({ io = io, multiplayer = mp, adapter = F.adapter(pose) })
    pump()
    F.advance(c, 2)
    if not c.arrived then c:startHere(); F.advance(c, 2) end
    pump()
    return c, pump, io
  end
  local magnate = require('earthFreight/magnate')
  local ropes = { latitude = -33.7328, longitude = 150.791 }
  local c1, pump1 = game(1, F.copy(F.PENRITH))
  local c2, pump2, io2 = game(2, ropes)
  local function pump() for _ = 1, 3 do pump1(); pump2() end end
  local function step() pump(); F.advance(c1, 0.6); F.advance(c2, 0.6); pump() end
  c1.profile.progression.balance, c2.profile.progression.balance = 400000, 300000
  F.advance(c1, 0.6); F.advance(c2, 0.6)
  T.check(c1:claimHome(), 'player 1 asks for a base'); pump()
  T.check(c1.property ~= nil, 'and buys it')
  F.advance(c1, 0.6); T.check(c1:manualSave(), 'saved'); pump()
  local key1, key2 = c1.mp.key, c2.mp.key
  local base = W.bases[key1]
  T.check(base.id ~= nil, 'the base has a number')
  T.eq(base.spot.latitude, c1.property.latitude, 'the server knows the owner\'s spot for the yard')
  local radiusAlone = W.circleKm(base)
  -- Player 2's jobs here pay player 1 the toll before joining.
  local before = {}
  for _, j in ipairs(c2:view().town.jobs) do before[j.id] = j end
  local tolled = 0
  for _, j in pairs(before) do if j.tollTo == 'player1' then tolled = tolled + 1 end end
  T.check(tolled > 0, 'a toll before joining')
  -- Asking to join.
  local other = c2:view().home.others[1]
  T.check(other.canAsk and other.askAllowed, 'player 2 can ask to join')
  T.check(c2:askToJoin(other.id), 'asks'); step()
  T.check(base.requests[key2] ~= nil, 'the server has the request')
  T.check(c2:view().home.others[1].asked, 'player 2 sees it is asked')
  local corp = c1:view().home.owned.corp
  T.eq(#corp.requests, 1, 'the owner sees one request'); T.eq(corp.requests[1].name, 'player2', 'from player 2')
  T.eq(corp.size, 1, 'just the owner so far')
  -- The owner accepts. (Player 2 has saved, so the server knows what they're worth.)
  F.advance(c2, 0.6); T.check(c2:manualSave(), 'player 2 saves'); pump()
  T.check(c1:corpAccept(corp.requests[1].id), 'the owner accepts'); step()
  T.check(base.members[key2] ~= nil, 'player 2 is a member'); T.eq(next(base.requests), nil, 'no request left')
  T.check(c2.corp ~= nil and c2.corp.owner == 'player1', 'player 2\'s game knows it')
  T.eq(c2.corp.latitude, c1.property.latitude, 'with the yard at the owner\'s spot')
  T.eq(c2:view().home.corp.owner, 'player1', 'the Base tab shows the corp')
  T.eq(c1:view().home.owned.corp.size, 2, 'the owner sees two truckers')
  T.check(W.circleKm(base) > radiusAlone, 'half of player 2\'s wealth grows the circle')
  T.near(W.circleKm(base), W.baseRadius(math.max(base.peak, W.BASE_PRICE) + math.floor(W.wealthOf(key2) / 2), base.boost), 0.01,
    'by half their wealth')
  T.near(c1:baseCircle().radiusKm, W.circleKm(base), 1, 'the owner\'s game draws the same circle')
  -- No toll for a member, and +0.2 in the corp's turf.
  for _, j in ipairs(c2:view().town.jobs) do
    T.eq(j.tollTo, nil, 'no toll for a member on ' .. j.id)
  end
  T.eq(c2:baseShareAt(F.copy(F.PENRITH)), magnate.MEMBER_SHARE, 'a member gets +0.2 in the turf')
  T.eq(c1:baseShareAt(F.copy(F.PENRITH)), magnate.OWNER_SHARE, 'the owner keeps +0.4')
  local town = { latitude = -33.75, longitude = 150.7 }
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, ends = { ropes, town } }))
  T.eq(base.batch, nil, 'the server takes no toll from a member either'); T.eq(base.owed or 0, 0, 'none owed')
  -- A member can't buy a base, and the server agrees.
  T.check(c2:claimProblem():find('corp', 1, true) ~= nil, 'a member can\'t buy a base')
  W.onBaseClaim(2, J.encode({ v = 1, town = 'Faraway', latitude = -31.95, longitude = 115.86, boost = 1 }))
  T.eq(J.decode(env.sent[#env.sent].data).why, 'in_corp', 'the server refuses too'); pump()
  -- The yard: a member stores a car there and the save keeps the corp.
  T.eq(c2:homeSpot(), c2.corp, 'the yard is the member\'s home spot')
  T.eq(c2:trailersAllowed(), 2, 'a member may own two trailers')
  c2.storedCars = { c2:activeCarRecord() }
  T.check(c2.storedCars[1] ~= nil, 'a car in the yard')
  F.advance(c2, 0.6); T.check(c2:manualSave(), 'the member saves'); pump()
  local saved = J.decode(env.files[W.careerPath(key2)])
  T.eq(saved.corp.owner, 'player1', 'the save keeps the corp'); T.eq(#saved.storedCars, 1, 'and the car in the yard')
  T.check(P.validate(saved) ~= nil, 'a member\'s save with a car in the yard is valid')
  -- The owner removes them: the car in the yard is traded in, and they wait before asking again.
  local money = c2.profile.progression.balance
  local card = c2:storedCarCard()
  local members = c1:view().home.owned.corp.members
  T.check(c1:corpRemove(members[1].id), 'the owner removes player 2'); step()
  T.eq(base.members[key2], nil, 'player 2 is out')
  T.eq(c2.corp, nil, 'player 2\'s game knows it'); T.eq(#c2.storedCars, 0, 'the car in the yard is gone')
  local pricing = require('earthFreight/pricing')
  T.eq(c2.profile.progression.balance, money + math.max(0, math.floor((card.value or 0) * pricing.CAR_TRADE_IN_SHARE - (card.repair or 0) + 0.5)),
    'traded in at the usual price')
  T.check(c2:joinProblem():find('24 hours', 1, true) ~= nil, 'and must wait 24 hours to ask again')
  W.onCorp(2, J.encode({ v = 1, ['do'] = 'ask', base = base.id }))
  T.eq(J.decode(env.sent[#env.sent].data).why, 'wait', 'the server says wait too'); pump()
  local tollAgain = false
  for _, j in ipairs(c2:view().town.jobs) do if j.tollTo == 'player1' then tollAgain = true end end
  T.check(tollAgain, 'the toll is back')
  -- After the wait, asking again, then leaving.
  env.time = env.time + W.CORP_WAIT_SECONDS + 1
  W.sendBasesToAll(); step()
  T.eq(c2:joinProblem(), nil, 'after 24 hours they can ask again')
  T.check(c2:askToJoin(base.id), 'asks again'); step()
  T.check(c2:cancelJoin(), 'and takes it back'); step()
  T.eq(next(base.requests), nil, 'no request left')
  -- A full corp says so.
  W.CORP_MAX = 1
  W.onCorp(2, J.encode({ v = 1, ['do'] = 'ask', base = base.id }))
  T.eq(J.decode(env.sent[#env.sent].data).why, 'full', 'a full corp takes no more'); pump()
  W.CORP_MAX = 5
  W.onCorp(2, J.encode({ v = 1, ['do'] = 'ask', base = base.id })); pump()
  W.onCorp(1, J.encode({ v = 1, ['do'] = 'accept', who = base.requests[key2].id })); step()
  T.check(c2.corp ~= nil, 'back in')
  T.check(not c2:leaveCorp(), 'Leave corp asks first'); T.check(c2.homeFeedback:find('24 hours', 1, true) ~= nil, 'saying what happens')
  T.check(c2:leaveCorp(), 'then leaves'); step()
  T.eq(base.members[key2], nil, 'out of the corp'); T.eq(c2.corp, nil, 'and the game knows')
  T.check(W.corpLeft[key2] ~= nil, 'the wait starts')
  -- Only the owner can accept or remove; corps survive a restart.
  W.onCorp(2, J.encode({ v = 1, ['do'] = 'remove', who = 1 }))
  T.eq(J.decode(env.sent[#env.sent].data).why, 'not_owner', 'a non-owner can\'t remove anyone'); pump()
  base.members[key2] = { name = 'player2', id = 9 }
  W.baseCareer(W.players[1], J.decode(env.files[W.careerPath(key1)]))
  local W2 = server(env.files)
  T.eq(W2.bases[key1].members[key2].name, 'player2', 'members are kept'); T.eq(W2.bases[key1].id, base.id, 'and the base\'s number')
  T.check(W2.corpLeft[key2] ~= nil, 'and the wait')
  local st = W.status()
  T.eq(st.bases[1].members[1], 'player2', 'the page lists the members')
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

-- Only this server's build of the mod may play: an older copy is sent off with a message, its career untouched.
do
  local W, env = server({ ['Resources/Server/WorldwideTrucking/build.txt'] = '160\n' })
  local kicked = {}
  env.kick = function(pid, why) kicked[#kicked + 1] = { pid = pid, why = why } end
  T.eq(W.BUILD, 160, 'the server knows its build')
  W.onHello(1); W.onJoin(1, J.encode({ v = 1 }))
  T.eq(#kicked, 1, 'a copy from before builds were sent is turned away')
  T.check(kicked[1].why:find('an old build', 1, true) ~= nil and kicked[1].why:find('build 160', 1, true) ~= nil,
    'the message says which builds')
  T.check(kicked[1].why:find('Add-ons', 1, true) ~= nil, 'and how to fix it')
  T.eq(env.chats[#env.chats].text, kicked[1].why, 'also said in chat')
  T.eq(W.players[1] == nil or W.players[1].key == nil, true, 'no career is loaded for it')
  local careers = 0
  for _, m in ipairs(env.sent) do if m.event == 'wwtcCareer' then careers = careers + 1 end end
  T.eq(careers, 0, 'no career is sent')
  W.onHello(2); W.onJoin(2, J.encode({ v = 1, build = 159 }))
  T.eq(#kicked, 2, 'an older build is turned away'); T.check(kicked[2].why:find('build 159', 1, true) ~= nil, 'naming it')
  W.onHello(3); W.onJoin(3, J.encode({ v = 1, build = 160 }))
  W.onHello(4); W.onJoin(4, J.encode({ v = 1, build = 161 }))
  T.eq(#kicked, 2, 'the same or a newer build plays')
  T.check(W.players[3].key ~= nil and W.players[4].key ~= nil, 'and gets its career')
  W.REQUIRE_LATEST = false
  W.onHello(5); W.onJoin(5, J.encode({ v = 1 }))
  T.eq(#kicked, 2, 'the check can be turned off')
  -- A server not built by the release workflow checks nothing.
  local W2, env2 = server()
  local kicked2 = 0
  env2.kick = function() kicked2 = kicked2 + 1 end
  T.eq(W2.BUILD, nil, 'no build file, no build')
  W2.onHello(1); W2.onJoin(1, J.encode({ v = 1 }))
  T.eq(kicked2, 0, 'and nobody is turned away')
  -- The game sends its build.
  local sentJoin
  MPC.BUILD = 160
  local s = MPC.new({ send = function(e, d) if e == 'wwtcJoin' then sentJoin = J.decode(d) end end, encode = J.encode,
    decode = J.decode, io = { exists = function() return false end } })
  s:receive('wwtcServer', J.encode({ v = 1, server = string.rep('a', 32), season = 1 }))
  T.eq(sentJoin.build, 160, 'the game says its build on joining')
  MPC.BUILD = nil
end

-- Timed chat messages: one line in turn every ANNOUNCE_EVERY_MINUTES, to everyone, only while someone is on.
do
  local W, env = server()
  local on = {}
  env.players = function() return on end
  W.ANNOUNCE_EVERY_MINUTES = 10
  W.ANNOUNCE = { 'one', 'two' }
  W.announceTick(); env.time = env.time + 3600; W.announceTick()
  T.eq(#env.chats, 0, 'nothing while the server is empty')
  on = { [1] = 'player1' }
  W.announceTick()
  T.eq(#env.chats, 0, 'not straight away when someone joins: the welcome comes first')
  env.time = env.time + 300; W.announceTick()
  T.eq(#env.chats, 0, 'not before the time')
  env.time = env.time + 300; W.announceTick()
  T.eq(env.chats[1].text, 'one', 'the first line after 10 minutes'); T.eq(env.chats[1].pid, -1, 'to everyone')
  env.time = env.time + 600; W.announceTick()
  T.eq(env.chats[2].text, 'two', 'then the next')
  env.time = env.time + 600; W.announceTick()
  T.eq(env.chats[3].text, 'one', 'and round again')
  W.ANNOUNCE = {}
  env.time = env.time + 600; W.announceTick()
  T.eq(#env.chats, 3, 'none when the list is empty')
  local W2 = dofile(SERVER)
  T.check(#W2.ANNOUNCE == 3 and W2.ANNOUNCE[1]:find('HUD', 1, true) and W2.ANNOUNCE[2]:find('discord.gg/', 1, true)
    and W2.ANNOUNCE[3]:find('github.io', 1, true), 'the server comes with the HUD, Discord and live page lines')
end
-- A "ghost" connection: BeamMP lost the player while their game kept running. Their saves never reach the server, the
-- HUD says so, and joining again keeps the newer career on their PC and sends it, instead of the server's older one.
do
  local W, env = server()
  local io = F.io()
  local s, pump = session(W, env, 1, io)
  s:start(0); pump()
  local store = MPC.store(s, io); store:load()
  local save = F.save(); save.progression.balance = 56000
  store:save(save); pump()
  T.eq(s.pending, nil, 'a save the server kept is not pending')
  T.eq(io.files[s:directory() .. MPC.UNCONFIRMED], nil, 'and nothing is noted on the PC')
  -- The server lets them go; what the game sends from now on goes nowhere.
  W.onLeave(1)
  local onSave = W.onSave
  W.onSave = function() end
  s:tick(100)
  save = store:save((function() local x = F.save(); x.progression.balance = 270000; return x end)())
  pump()
  T.check(s.pending ~= nil, 'a save the server never answered is pending')
  T.eq(s:unconfirmed(110), nil, 'not shown straight away')
  local late = s:unconfirmed(100 + MPC.CONFIRM_SECONDS)
  T.eq(late and late.balance, 56000, 'after a while the game says the server has nothing since $56,000')
  local sent = 0
  local send = s.sendText
  s.sendText = function(self, text) sent = sent + 1; return send(self, text) end
  s:tick(100 + MPC.RESEND_EVERY); pump()
  T.eq(sent, 1, 'and sends it again')
  -- Through Core: the save line says so.
  local c = F.controller({ io = F.io({ [F.CONFIG] = F.config() }) })
  c.mp, c.clock = s, 100 + MPC.CONFIRM_SECONDS
  local warning = c:serverSaveWarning()
  T.check(warning and warning:find('since $56,000', 1, true) and warning:find('join the server again', 1, true),
    'the HUD says the server has not got the saves since $56,000')
  -- They join again (a new game session, the same PC).
  W.onSave = onSave
  local s2, pump2 = session(W, env, 2, io)
  s2:start(0); pump2()
  local loaded = MPC.store(s2, io):load()
  T.eq(loaded.progression.balance, 270000, 'the newer career on the PC is kept')
  T.eq(J.decode(env.files[W.careerPath(s.key)]).progression.balance, 270000, 'and the server now has it')
  T.eq(s2.pending, nil, 'confirmed')
  T.eq(io.files[s2:directory() .. MPC.UNCONFIRMED], nil, 'so nothing is noted any more')
  T.eq(s2.recovered.balance, 270000, 'the game can tell the player')
end

-- A copy the game never sent (edited by hand, or noted for an older save) still loses to the server's.
do
  local W, env = server()
  local io = F.io()
  local s, pump = session(W, env, 1, io)
  s:start(0); pump()
  local store = MPC.store(s, io); store:load()
  local save = F.save(); save.progression.balance = 6000
  store:save(save); pump()
  local dir = s:directory()
  local edited = io.files[dir .. 'save-a.json']
  edited.generation, edited.progression.balance = edited.generation + 5, 999999
  io.files[dir .. MPC.UNCONFIRMED] = { generation = edited.generation, balance = 6000 }
  local s2, pump2 = session(W, env, 2, io)
  s2:start(0); pump2()
  T.eq(MPC.store(s2, io):load().progression.balance, 6000, 'money that does not match what was sent is not kept')
end

-- The server lost track of a player still in the game (its plugin reloaded): it asks them to join again, and keeps
-- the save they send again. The same save sent twice is answered ok.
do
  local W, env = server()
  local io = F.io()
  local s
  local handler = function(event, data) s:receive(event, data) end
  local send, pump = link(W, env, 1, handler)
  s = MPC.new({ send = send, encode = J.encode, decode = J.decode, io = io })
  s:start(0); pump()
  local store = MPC.store(s, io); store:load()
  store:save(F.save()); pump()
  W.players = {}
  local save = F.save(); save.progression.balance = 42000
  store:save(save); pump()
  T.eq(s.saveError, nil, 'being lost is not shown as a refused save')
  T.eq(J.decode(env.files[W.careerPath(s.key)]).progression.balance, 42000, 'the save is kept after joining back')
  T.eq(W.players[1].key, s.key, 'with the same career')
  T.eq(s.pending, nil, 'and confirmed')
  local careers = 0
  for _, line in ipairs(env.printed) do if line:find('joined back', 1, true) then careers = careers + 1 end end
  T.eq(careers, 1, 'the server log says so')
  -- The same save again, as a game that never heard back would send it.
  local text = env.files[W.careerPath(s.key)]
  for _, frame in ipairs(W.frames(99, text)) do W.onSave(1, frame) end
  local last = J.decode(env.sent[#env.sent].data)
  T.eq(last.ok, true, 'the same save sent again is answered ok')
end
-- While you were away: tolls, corp news and the leaderboard kept for a player who's off, sent once on their next join.
do
  local W, env = server()
  W.SHIP_CONTAINERS = 0
  local function sentTo(pid, event)
    local found
    for _, m in ipairs(env.sent) do if m.pid == pid and m.event == event then found = J.decode(m.data) end end
    return found
  end
  W.onJoin(1, J.encode({ v = 1 })); W.onJoin(2, J.encode({ v = 1 })); W.onJoin(3, J.encode({ v = 1 }))
  local key1, key2 = W.players[1].key, W.players[2].key
  T.eq(sentTo(1, 'wwtcAway'), nil, 'nothing on a first join')
  W.bases[key1] = { name = 'player1', town = 'Penrith', latitude = -33.75, longitude = 150.7, boost = 1, peak = 400000,
    id = 1, members = {}, requests = {}, nextMember = 0 }
  W.stats.board[key1] = { name = 'player1', balance = 900000 }
  W.stats.board[key2] = { name = 'player2', balance = 100000 }
  -- A toll while the owner is on goes as usual, and isn't kept for later.
  local penrith, ropes = { latitude = -33.75, longitude = 150.7 }, { latitude = -33.7328, longitude = 150.791 }
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, ends = { ropes, penrith } }))
  T.eq(W.away[key1], nil, 'nothing kept while the owner is on')
  env.sent = {}
  W.onLeave(1)
  T.eq(W.away[key1].place, 1, 'their place is kept as they leave')
  -- While they're off: two players pay tolls, one asks to join the corp, and player 2 gets richer.
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 800, toll = 200, ends = { ropes, penrith } }))
  W.onDelivered(2, J.encode({ v = 1, kind = 'job', pay = 1200, toll = 300, ends = { ropes, penrith } }))
  W.onDelivered(3, J.encode({ v = 1, kind = 'job', pay = 400, toll = 100, ends = { ropes, penrith } }))
  W.onCorp(3, J.encode({ v = 1, ['do'] = 'ask', base = 1 }))
  W.stats.board[key2].balance = 2000000
  env.time = env.time + 2 * 86400
  -- The away file survives a restart of the plugin.
  local W2, env2 = server(env.files)
  env2.time = env.time
  W2.SHIP_CONTAINERS = 0
  W2.bases[key1] = W.bases[key1]
  W2.stats.board = W.stats.board
  W2.onJoin(1, J.encode({ v = 1, key = key1 }))
  local away
  for _, m in ipairs(env2.sent) do if m.pid == 1 and m.event == 'wwtcAway' then away = J.decode(m.data) end end
  T.check(away ~= nil, 'the card comes on joining again')
  T.eq(away.since, 2 * 86400, 'with how long they were away')
  T.eq(away.tolls.amount, 600, 'the tolls paid while they were off'); T.eq(away.tolls.jobs, 3, 'from three deliveries')
  T.eq(away.tolls.from[1].name, 'player2', 'biggest payer first'); T.eq(away.tolls.from[1].amount, 500, 'with what they paid')
  T.eq(away.tolls.from[2].name, 'player3', 'then the next')
  T.eq(#away.news, 1, 'one piece of corp news'); T.check(away.news[1]:find('player3 asked to join your corp', 1, true), 'the request')
  T.eq(away.place, 2, 'their place now'); T.eq(away.was, 1, 'and as they left'); T.eq(away.of, 3, 'of everyone on the board')
  T.eq(W2.away[key1], nil, 'and it is only sent once')
  -- A quick drop and rejoin with nothing new sends no card; news for the player who asked comes when they return.
  W2.onLeave(1); env2.time = env2.time + 60; env2.sent = {}
  W2.onJoin(1, J.encode({ v = 1, key = key1 }))
  local again
  for _, m in ipairs(env2.sent) do if m.event == 'wwtcAway' then again = m end end
  T.eq(again, nil, 'no card after a minute away with nothing new')
  local key3 = W2.players[3] and W2.players[3].key
  T.eq(key3, nil, 'player 3 is not on this restarted server')
  -- The game checks what it gets, and the HUD shows it once back on the road, until Got it.
  local clean = MPC.cleanAway({ since = 7200, place = 3, was = 0, of = 9, news = { 'One\nline', 5 },
    tolls = { amount = 1500, jobs = 0, from = { { name = 'Sam', amount = 1000 }, { amount = 'x' } }, others = 2 } })
  T.eq(clean.since, 7200, 'how long'); T.eq(clean.was, nil, 'no place is no place'); T.eq(clean.tolls.jobs, 1, 'at least one job')
  T.eq(#clean.tolls.from, 1, 'bad payers dropped'); T.eq(clean.news[1], 'One line', 'news is one line'); T.eq(#clean.news, 1, 'and text only')
  T.eq(MPC.cleanAway({}), nil, 'an empty message is no card')
  local c = F.controller()
  c.mp = { away = clean }
  T.eq(c:view().away, nil, 'not before the player is back at their save')
  c.arrived = true
  local v = c:view().away
  T.check(v ~= nil and v.tolls.amount == 1500 and v.place == 3, 'shown on the HUD once back on the road')
  T.check(c:dismissAway(), 'Got it'); T.eq(c:view().away, nil, 'closes it')
end
T.done('multiplayer careers')
