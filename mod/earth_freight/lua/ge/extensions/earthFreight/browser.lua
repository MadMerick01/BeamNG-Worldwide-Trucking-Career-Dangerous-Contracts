-- Opens a page of the mod's own little web server (Street View, the radio, the base map) in the
-- player's default web browser, the one Windows opens links in.
--
-- BeamNG 0.40 turned Engine.Platform.openFile into a folder opener that only logs an error, and the
-- game's openWebBrowser does not open http://127.0.0.1 addresses, so neither brings up a browser
-- any more. Windows' own ShellExecute, called through LuaJIT's ffi, opens the address in the
-- default browser with no console window. Then os.execute's start command, which flashes a console
-- window for a moment, and last openWebBrowser. Only addresses on this computer are opened, so
-- nothing typed or fetched can reach the shell.
--
-- The game's pieces are injected (env), so tests can stand in for them.
local M = {}

local SW_SHOWNORMAL = 1

-- Only this computer's own pages: http://127.0.0.1:<port>/<letters, digits, slashes>.
function M.safe(url)
  return type(url) == 'string' and url:match('^http://127%.0%.0%.1:%d+/[%w/%-_]*$') ~= nil
end

local shellExecute
local function windowsOpen(ffi, url)
  if not shellExecute then
    pcall(ffi.cdef, [[
      void* ShellExecuteA(void* hwnd, const char* operation, const char* file, const char* parameters,
        const char* directory, int showCommand);
    ]])
    local shell32 = ffi.load('shell32')
    shellExecute = function(...) return shell32.ShellExecuteA(...) end
  end
  local result = shellExecute(nil, 'open', url, nil, nil, SW_SHOWNORMAL)
  -- Above 32 means Windows handed the address to the browser.
  return tonumber(ffi.cast('intptr_t', result)) > 32
end

-- The game's own pieces, looked up when a page is opened.
function M.gameEnv()
  local jitInfo = rawget(_G, 'jit')
  return {
    windows = (jitInfo and jitInfo.os == 'Windows') or package.config:sub(1, 1) == '\\',
    ffi = rawget(_G, 'ffi') or (pcall(require, 'ffi') and require('ffi')) or nil,
    execute = os and os.execute,
    openWebBrowser = rawget(_G, 'openWebBrowser'),
  }
end

-- True and how, once one way took the address; false and why when none did.
function M.open(url, env)
  if not M.safe(url) then return false, 'unsafe' end
  env = env or M.gameEnv()
  if env.windows and env.ffi then
    local ok, opened = pcall(windowsOpen, env.ffi, url)
    if ok and opened then return true, 'shell' end
  end
  if env.windows and type(env.execute) == 'function' then
    local ok, result = pcall(env.execute, 'start "" "' .. url .. '"')
    if ok and (result == 0 or result == true) then return true, 'start' end
  end
  if type(env.openWebBrowser) == 'function' then
    local ok = pcall(env.openWebBrowser, url)
    if ok then return true, 'openWebBrowser' end
  end
  return false, 'none'
end

-- Forgets the ShellExecute binding, for tests.
function M._reset() shellExecute = nil end

return M
