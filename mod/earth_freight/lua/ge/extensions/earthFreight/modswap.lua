-- The player's own copy of the mod and a BeamMP server's copy.
--
-- A BeamMP server sends its own copy of the mod (mods/multiplayer/<name>.zip). Joining, BeamMP turns the server's copy
-- on and turns off every mod the server didn't send, the player's own copy among them (their download in mods/, or the
-- one from BeamNG.Earth's Add-ons page). The game swaps the files, not the code that runs: earthFreight_core is a
-- 'manual' extension (modScript.lua) and stays loaded, with every module it required. So the player's own copy kept
-- running on the server's files, told the server its own build, and a server running a newer build sent them off.
-- Leaving, BeamMP deletes the server's copy and leaves the player's own copy off, so the mod was gone in single player
-- until they turned it on again in the Mod Manager. (BeamNG.Earth found and fixed both for itself: its codeswap.lua
-- and beammp.lua, 1.10.)
--
-- 1. The code swap. The running code remembers the copy it was loaded from (its fingerprint: every Lua file of
--    lua/ge/extensions/earthFreight with its size). When a mod is turned on or off (core.lua's onModActivated and
--    onModDeactivated) or a copy's modScript runs, and the copy mounted now is another one, our extensions are unloaded
--    and our modules forgotten, and the mounted copy's code is loaded in their place. Nothing is swapped while no copy
--    is mounted, nor when the mounted copy is the same.
-- 2. The restore. When BeamMP turns the player's own copy off in a session, a job in the game's own job system (not
--    one of our modules, so the swap doesn't take it away) waits for the session to end and turns that copy back on;
--    its modScript then brings its own code back. A copy the player turns off outside a session stays off.
--
-- Self-contained: modScript.lua runs it with dofile, since a require would return the running copy's module.
local M = {}

M.DIR = '/lua/ge/extensions/earthFreight/'
M.MODSCRIPT = '/scripts/earthFreight/modScript.lua'
M.PREFIX = 'earthFreight'
-- Globals, as they outlive the modules: a copy loaded later (after a swap) reads what the first one left.
M.FINGERPRINT = 'earthFreightCodeFingerprint'
M.OWN_MOD = 'earthFreightOwnMod'
M.RESTORE = 'earthFreightRestore'
M.RESTORE_TRIES = 3        -- turned on again this many times if something turns it off again meanwhile
M.RESTORE_GAP_S = 1.0      -- on, and still on this long: done

-- The game's pieces, read when used (tests set them on _G).
local function g(name) return rawget(_G, name) end
local function say(level, text)
  local log = g('log')
  if type(log) == 'function' then pcall(log, level, 'earthFreight', text) end
end

-- The mounted copy's fingerprint: its Lua files with their sizes, sorted ("name:size;..."), or nil when none is.
function M.fingerprint()
  local fs = g('FS')
  if type(fs) ~= 'table' and type(fs) ~= 'userdata' then return nil end
  local ok, files = pcall(function() return fs:findFiles(M.DIR, '*.lua', 0, false, false) end)
  if not ok or type(files) ~= 'table' or #files == 0 then return nil end
  local parts = {}
  for _, path in ipairs(files) do
    local name = type(path) == 'string' and (path:match('([^/]+)$') or path):lower()
    if name then
      local okSize, size = pcall(function() return fs:fileSize(path) end)
      parts[#parts + 1] = name .. ':' .. tostring(okSize and size or '?')
    end
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return table.concat(parts, ';')
end

-- The running code's copy: called as core.lua loads.
function M.remember(fingerprint)
  rawset(_G, M.FINGERPRINT, fingerprint or M.fingerprint())
end

-- Pure: swap? running (our core is loaded), had (the fingerprint it remembers, nil for a copy older than this),
-- now (the mounted copy's, nil for none).
function M.due(running, had, now)
  if not running or now == nil then return false end
  return had ~= now
end

-- Our extensions that are loaded (named earthFreight_*).
function M.ours()
  local ext = g('extensions')
  local out = {}
  if type(ext) ~= 'table' or type(ext.getLoadedExtensionsNames) ~= 'function' then return out end
  local ok, names = pcall(ext.getLoadedExtensionsNames, true)
  for _, n in ipairs(ok and type(names) == 'table' and names or {}) do
    if type(n) == 'string' and n:sub(1, #M.PREFIX + 1) == M.PREFIX .. '_' then out[#out + 1] = n end
  end
  return out
end

-- Is k one of our modules (a package.loaded key)?
function M.ownModule(k)
  if type(k) ~= 'string' then return false end
  local s = k:gsub('%.', '/')
  return s:sub(1, #M.PREFIX + 1) == M.PREFIX .. '/' or s:sub(1, #M.DIR - 1) == M.DIR:sub(2)
end

-- Our extensions unloaded and our modules forgotten; with reload, the mounted copy's extensions loaded in their place
-- (from a hook; after a modScript, the mod manager does it). -> the extensions unloaded.
function M.swap(why, reload, stopping)
  local names = M.ours()
  local ext = g('extensions')
  if stopping then
    say('I', string.format('%s: its code stopped (%d extensions)', tostring(why), #names))
  else
    say('W', string.format('another copy of the trucking mod is mounted (%s): its code loaded in place of the running '
      .. 'one (%d extensions)', tostring(why), #names))
  end
  if type(ext) == 'table' and type(ext.unload) == 'function' then
    for _, n in ipairs(names) do pcall(ext.unload, n) end
  end
  for k in pairs(package.loaded) do
    if M.ownModule(k) then package.loaded[k] = nil end
  end
  rawset(_G, M.FINGERPRINT, nil)
  if reload and type(ext) == 'table' and type(ext.load) == 'function' and #names > 0 then pcall(ext.load, names) end
  return names
end

-- The check (a mod turned on or off, a copy's modScript). -> true when it swapped.
function M.check(why, reload)
  local now = M.fingerprint()
  if not M.due(g(M.PREFIX .. '_core') ~= nil, rawget(_G, M.FINGERPRINT), now) then return false end
  M.swap(why, reload)
  return true
end

-- The player turned the mod off (core.lua's onModDeactivated, and again the next frame): with no copy of it mounted and
-- no BeamMP session on (in one, no copy is the moment between BeamMP turning one off and the other on: wait), our
-- extensions are unloaded, so nothing of the mod runs until it is turned on again, when its modScript loads it. Before,
-- the 'manual' extension stayed loaded and kept running (its HUD pop-up among it) with the mod off. -> true when it
-- unloaded.
function M.offCheck(why)
  if g(M.PREFIX .. '_core') == nil or M.sessionOn() or M.fingerprint() ~= nil then return false end
  M.swap(why, false, true)
  return true
end

-- ----- The player's own copy back on after a server --------------------------------------------------------------

local function modManager()
  local mm = g('core_modmanager')
  if type(mm) ~= 'table' or type(mm.getModDB) ~= 'function' or type(mm.activateMod) ~= 'function' then return nil end
  return mm
end

-- A BeamMP server's copy (BeamMP names them multiplayer<name>, in mods/multiplayer/).
function M.serverCopy(name, dir)
  return (type(name) == 'string' and name:sub(1, 11) == 'multiplayer') or dir == '/mods/multiplayer/'
end

-- The name of the mod the running code came from, kept only for the player's own copy (not a server's): called as
-- core.lua loads. -> that name, or nil.
function M.rememberOwnMod()
  local mm = g('core_modmanager')
  if type(mm) ~= 'table' or type(mm.getModForFilename) ~= 'function' then return rawget(_G, M.OWN_MOD) end
  local ok, name = pcall(mm.getModForFilename, M.MODSCRIPT)
  if ok and type(name) == 'string' and name ~= '' and not M.serverCopy(name) then rawset(_G, M.OWN_MOD, name) end
  return rawget(_G, M.OWN_MOD)
end

-- BeamMP in a session, or on its way into one.
function M.sessionOn()
  local mp = g('MPCoreNetwork')
  if type(mp) ~= 'table' then return false end
  for _, f in ipairs({ mp.isMPSession, mp.isGoingMPSession }) do
    if type(f) == 'function' then
      local ok, v = pcall(f)
      if ok and v == true then return true end
    end
  end
  return false
end

local function clock()
  local c0 = os.clock()
  return function() return os.clock() - c0 end
end

-- One frame of a restore. -> true when done (on and still on, on already, gave up, or nothing to do).
function M.restoreStep(s)
  if M.sessionOn() then return false end
  local mm = modManager()
  if not mm then return true end
  local ok, entry = pcall(mm.getModDB, s.mod)
  if not ok or type(entry) ~= 'table' then return true end     -- the copy has gone
  if entry.active then
    if s.tries == 0 then return true end                        -- turned on by someone else
    return (s.clock() - s.since) >= M.RESTORE_GAP_S
  end
  if s.tries > 0 and not s.again then return true end           -- off again, not by BeamMP: the player's choice
  if s.tries >= M.RESTORE_TRIES then
    say('W', 'left the server: the trucking mod (' .. s.mod .. ') was turned off again ' .. s.tries .. ' times: left '
      .. 'off (turn it on in the Mod Manager)')
    return true
  end
  s.tries, s.since, s.again = s.tries + 1, s.clock(), false
  say('I', 'left the server: the trucking mod (' .. s.mod .. ') turned back on')
  local okOn, err = pcall(mm.activateMod, s.mod)
  if not okOn then say('W', 'turning the trucking mod back on: ' .. tostring(err)) end
  return false
end

local function restoreJob(job, s)
  while s.live do
    local ok, done = pcall(M.restoreStep, s)
    if not ok or done then break end
    job.sleep(0)
  end
  s.live = false
end
M._restoreJob = restoreJob

-- Starts the restore for mod (nothing when one is waiting). -> true when started now.
function M.armRestore(mod)
  local cur = rawget(_G, M.RESTORE)
  if type(cur) == 'table' and cur.live then return false end
  local js = g('core_jobsystem')
  if type(js) ~= 'table' or type(js.create) ~= 'function' then return false end
  local s = { live = true, mod = mod, tries = 0, since = 0, clock = clock() }
  if not pcall(js.create, restoreJob, 1, s) then return false end
  rawset(_G, M.RESTORE, s)
  say('I', 'the trucking mod (' .. mod .. ') is off for the server: turned back on when you leave')
  return true
end

-- core.lua's onModDeactivated, before the swap: BeamMP turning the player's own copy off in a session starts the
-- restore (or marks a waiting one to go again). Outside a session it is the player: a waiting restore ends.
-- -> true when a restore was started.
function M.onModDeactivated(mod)
  local own = rawget(_G, M.OWN_MOD)
  if type(mod) ~= 'table' or not own or mod.modname ~= own then return false end
  local cur = rawget(_G, M.RESTORE)
  local live = type(cur) == 'table' and cur.live
  if not M.sessionOn() then
    if live then cur.live = false end
    return false
  end
  if live then cur.again = true; return false end
  return M.armRestore(own)
end

return M
