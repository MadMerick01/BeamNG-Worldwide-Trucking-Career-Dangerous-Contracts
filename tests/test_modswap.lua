local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local S = require('earthFreight/modswap')

-- The game's pieces, faked on _G for each case and taken away after.
local saved = {}
local function fake(name, value)
  if saved[name] == nil then saved[name] = { v = rawget(_G, name) } end
  rawset(_G, name, value)
end
local function restore()
  for name, s in pairs(saved) do rawset(_G, name, s.v) end
  saved = {}
  rawset(_G, S.FINGERPRINT, nil); rawset(_G, S.OWN_MOD, nil); rawset(_G, S.RESTORE, nil)
end

-- A virtual file system with one copy of the mod mounted: name -> size (nil: none mounted).
local function mount(files)
  local fs = {}
  function fs:findFiles(dir, pattern)
    local out = {}
    for name in pairs(files or {}) do out[#out + 1] = dir .. name end
    return out
  end
  function fs:fileSize(path) return files[path:match('([^/]+)$')] end
  fake('FS', fs)
end

-- The fingerprint: the mounted copy's files and sizes, the same whatever order they come in.
do
  mount({ ['core.lua'] = 100, ['jobs.lua'] = 20 })
  T.eq(S.fingerprint(), 'core.lua:100;jobs.lua:20', 'files and sizes, sorted')
  mount({ ['jobs.lua'] = 20, ['Core.lua'] = 100 })
  T.eq(S.fingerprint(), 'core.lua:100;jobs.lua:20', 'in any order and case')
  mount({})
  T.eq(S.fingerprint(), nil, 'no copy mounted: none')
  fake('FS', nil)
  T.eq(S.fingerprint(), nil, 'no file system: none')
  restore()
end

-- When to swap.
T.check(not S.due(false, 'a', 'b'), 'nothing running: nothing to swap')
T.check(not S.due(true, 'a', nil), 'no copy mounted (between BeamMP turning one off and the other on): wait')
T.check(not S.due(true, 'a', 'a'), 'the same copy: nothing')
T.check(S.due(true, 'a', 'b'), 'another copy: swap')
T.check(S.due(true, nil, 'b'), 'running code older than this: swap')

T.check(S.ownModule('earthFreight/core'), 'our module')
T.check(S.ownModule('earthFreight/tiles/s35e150'), 'and in a folder')
T.check(S.ownModule('lua/ge/extensions/earthFreight/core'), 'by its path')
T.check(S.ownModule('earthFreight.jobs'), 'with dots')
T.check(not S.ownModule('beamngEarth/core'), 'not another mod\'s')
T.check(not S.ownModule('earthFreightish/x'), 'nor a name that only starts the same')
T.check(not S.ownModule(nil), 'nor nothing')

-- The swap: the running copy's extensions unloaded and modules forgotten, the mounted copy's loaded.
do
  local unloaded, loaded = {}, nil
  fake('extensions', {
    getLoadedExtensionsNames = function() return { 'earthFreight_core', 'beamngEarth_core', 'ui_apps' } end,
    unload = function(n) unloaded[#unloaded + 1] = n end,
    load = function(names) loaded = names end,
  })
  fake('earthFreight_core', {})
  package.loaded['earthFreight/fakeModule'] = {}
  package.loaded['someoneElse/module'] = {}
  mount({ ['core.lua'] = 100 })
  S.remember()
  T.eq(rawget(_G, S.FINGERPRINT), 'core.lua:100', 'the running copy is remembered')
  T.check(not S.check('test', true), 'the same copy mounted: no swap')
  T.eq(#unloaded, 0, 'nothing unloaded')
  mount({ ['core.lua'] = 120 })
  T.check(S.check('test', true), 'the server\'s copy mounted: swapped')
  T.eq(#unloaded, 1, 'one extension unloaded'); T.eq(unloaded[1], 'earthFreight_core', 'ours only')
  T.eq(package.loaded['earthFreight/fakeModule'], nil, 'our modules forgotten')
  T.check(package.loaded['someoneElse/module'] ~= nil, 'other mods\' kept')
  T.eq(loaded and loaded[1], 'earthFreight_core', 'the mounted copy\'s code loaded in its place')
  T.eq(rawget(_G, S.FINGERPRINT), nil, 'the new code remembers its own copy as it loads')
  package.loaded['someoneElse/module'] = nil
  -- From a modScript: the mod manager loads the extensions itself.
  loaded = nil
  S.remember('old')
  T.check(S.check('its modScript', false), 'swapped from a modScript')
  T.eq(loaded, nil, 'and left to the mod manager to load')
  -- Our core not running (the game is starting): nothing to swap.
  fake('earthFreight_core', nil); S.remember('old')
  T.check(not S.check('test', true), 'nothing running yet')
  restore()
end

-- The player's own copy: remembered, never a server's.
do
  local owner = 'worldwide-trucking-dangerous-contracts'
  fake('core_modmanager', { getModForFilename = function() return owner end })
  T.eq(S.rememberOwnMod(), owner, 'the player\'s own copy')
  owner = 'multiplayerworldwide-trucking-dangerous-contracts'
  T.eq(S.rememberOwnMod(), 'worldwide-trucking-dangerous-contracts', 'code from a server\'s copy keeps the player\'s')
  restore()
  fake('core_modmanager', { getModForFilename = function() return 'multiplayerworldwide-trucking-dangerous-contracts' end })
  T.eq(S.rememberOwnMod(), nil, 'only a server\'s copy (no download of their own): none')
  restore()
  T.check(S.serverCopy('multiplayerfoo'), 'BeamMP\'s name for a server\'s copy')
  T.check(S.serverCopy('foo', '/mods/multiplayer/'), 'or its folder')
  T.check(not S.serverCopy('foo', '/mods/'), 'a mod in mods/ is the player\'s')
end

-- The restore: BeamMP turning the player's own copy off in a session turns it back on once the session ends.
do
  local inSession, db, activated, jobs = true, { active = true }, 0, {}
  fake('MPCoreNetwork', { isMPSession = function() return inSession end, isGoingMPSession = function() return false end })
  fake('core_modmanager', {
    getModDB = function(name) return name == 'mine' and db or nil end,
    activateMod = function() activated = activated + 1; db.active = true end,
  })
  fake('core_jobsystem', { create = function(f, _, s) jobs[#jobs + 1] = { f = f, s = s } end })
  rawset(_G, S.OWN_MOD, 'mine')
  T.check(not S.onModDeactivated({ modname = 'someone-else' }), 'another mod turned off: nothing')
  T.check(not S.onModDeactivated({ modname = 'multiplayermine' }), 'the server\'s copy turned off: nothing')
  db.active = false
  T.check(S.onModDeactivated({ modname = 'mine' }), 'the player\'s copy turned off in a session: restore started')
  T.eq(#jobs, 1, 'as a job of the game\'s')
  T.check(not S.onModDeactivated({ modname = 'mine' }), 'only one at a time')
  local s = jobs[1].s
  T.check(not S.restoreStep(s), 'still in the session: wait')
  T.eq(activated, 0, 'nothing turned on yet')
  inSession = false
  T.check(not S.restoreStep(s), 'the session is over: turned on')
  T.eq(activated, 1, 'once')
  -- A little past the gap: since + gap - since can come out just under the gap in floating point.
  s.clock = function() return s.since + S.RESTORE_GAP_S + 0.01 end
  T.check(S.restoreStep(s), 'on and staying on: done')
  restore()
end

-- A copy the player turns off themselves stays off, and a restore waiting ends.
do
  local inSession, db, activated = false, { active = false }, 0
  local job
  fake('MPCoreNetwork', { isMPSession = function() return inSession end })
  fake('core_modmanager', { getModDB = function() return db end, activateMod = function() activated = activated + 1 end })
  fake('core_jobsystem', { create = function(f, _, s) job = s end })
  rawset(_G, S.OWN_MOD, 'mine')
  T.check(not S.onModDeactivated({ modname = 'mine' }), 'turned off outside a session: the player\'s choice')
  T.eq(job, nil, 'nothing started')
  inSession = true
  S.onModDeactivated({ modname = 'mine' })
  inSession = false
  S.onModDeactivated({ modname = 'mine' })
  T.check(not job.live, 'turned off again outside the session: the restore ends')
  -- Turned off again and again: given up after a few tries.
  rawset(_G, S.RESTORE, nil); job = nil; inSession = true
  S.onModDeactivated({ modname = 'mine' }); inSession = false
  for _ = 1, S.RESTORE_TRIES do S.restoreStep(job); job.again = true end
  T.eq(activated, S.RESTORE_TRIES, 'tried a few times')
  T.check(S.restoreStep(job), 'then gives up')
  -- The copy deleted meanwhile: done.
  db = nil
  T.check(S.restoreStep({ mod = 'mine', tries = 0 }), 'no copy any more: done')
  restore()
end

-- Nothing of the game there at all: nothing breaks.
T.check(not S.check('test', true), 'no game: no swap')
T.check(not S.onModDeactivated({ modname = 'x' }), 'no game: no restore')
T.check(not S.armRestore('x'), 'no job system: none')

T.done('Mod copies')
