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
        elseif m.event == 'wwtcSave' then W.onSave(pid, m.data) end
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

T.done('multiplayer careers')
