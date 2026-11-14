local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local MPC = require('earthFreight/multiplayer')

-- The Land Race and Leaderboard tab: the game checks the leaderboard the server sends (wwtcBoard), and the HUD gets it
-- with the land race on a server only.
do
  local clean = MPC.cleanBoard({ season = 2, day = 3, truckers = 5, board = { { rank = 1, name = 'Sam\nX', wealth = 5000, deliveries = 4, wins = 1 },
    { rank = 'x', wealth = 1 }, { rank = 2, name = 'Me', wealth = -5 }, { rank = 3, name = 'You', wealth = 100, mine = true } },
    me = { rank = 14, name = 'Me', wealth = 50 },
    winner = { season = 1, owner = 'Kez', town = 'Wichita', members = { 'Ruby', 7 }, land = 50.4 } })
  T.eq(#clean.board, 2, 'bad rows are dropped'); T.eq(clean.board[1].name, 'Sam X', 'names are one line')
  T.eq(clean.board[1].wins, 1, 'season wins'); T.eq(clean.board[2].mine, true, 'the player\'s own row')
  T.eq(clean.me.rank, 14, 'the player\'s own place further down'); T.eq(clean.me.mine, true, 'is marked theirs')
  T.eq(clean.winner.owner, 'Kez', 'the last winner'); T.eq(#clean.winner.members, 1, 'winner members are names only')
  T.eq(MPC.cleanBoard({}), nil, 'no board, nothing')
  T.eq(MPC.cleanBoard('x'), nil, 'not a table, nothing')
  -- The message is taken by the game's server link.
  local s = MPC.new({ send = function() end, encode = function() return '' end,
    decode = function(text) return text == 'board' and { board = { { rank = 1, name = 'Sam', wealth = 10 } } } or {} end })
  T.check(s:receive('wwtcBoard', 'board'), 'the leaderboard message is taken')
  T.eq(s.board.board[1].name, 'Sam', 'and kept')
  T.check(not s:receive('wwtcBoard', 'nothing'), 'a message without a board is not')
  -- The HUD: the race and the board on a server, nothing in single player.
  local c = F.controller()
  T.eq(c:view().standings, nil, 'single player has no standings, so nothing is asked for')
  c.mp = { state = 'server', now = 0, board = clean, race = { win = 50, left = 86400 * 3, at = 0, leader = 'Sam', leaderLand = 1.6 },
    bases = { { name = 'Sam', town = 'Perth', land = 1.6, outposts = { {} }, members = {} },
      { name = 'player1', town = 'Parramatta', land = 1.1, mine = true, members = {} },
      { name = 'Ruby', town = 'Lithgow', land = 0, members = {} } } }
  local st = c:standingsView()
  T.check(st ~= nil, 'a server has standings')
  T.eq(#st.corps, 2, 'corps holding land'); T.eq(st.corps[1].name, 'Sam', 'most first'); T.eq(st.corps[1].outposts, 1, 'with their outposts')
  T.eq(st.corps[2].mine, true, 'yours marked'); T.eq(st.race.daysLeft, 3, 'days left'); T.eq(#st.board, 2, 'the leaderboard')
  T.eq(st.season, 2, 'the season'); T.eq(st.waiting, nil, 'not waiting')
  c.mp.board = nil
  T.eq(c:standingsView().waiting, true, 'until the leaderboard comes, it says it is waiting')
  c.mp.state = 'joining'
  T.eq(c:standingsView(), nil, 'nothing before the career is in')
end
T.done('land race and leaderboard')
