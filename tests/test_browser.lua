local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local B = require('earthFreight/browser')

local URL = 'http://127.0.0.1:47170/radio'

-- A fake ffi whose ShellExecuteA answers with the given code and records the address it got.
local function fakeFfi(code, calls)
  return {
    cdef = function() end,
    load = function() return { ShellExecuteA = function(_, op, file) calls[#calls + 1] = op .. ' ' .. file; return code end } end,
    cast = function(_, value) return value end,
  }
end

do -- only this computer's own pages
  T.check(B.safe(URL), 'the radio page')
  T.check(B.safe('http://127.0.0.1:47170/'), 'the Street View page')
  T.check(B.safe('http://127.0.0.1:47170/bases'), 'the base map')
  T.check(not B.safe('https://example.com/'), 'not other sites')
  T.check(not B.safe('http://127.0.0.1:47170/" & calc & "'), 'nothing a shell would run')
  T.check(not B.safe(nil), 'not nothing')
  local ok, why = B.open('http://evil/', { windows = true, execute = function() error('ran') end })
  T.check(not ok, 'an unsafe address is not opened'); T.eq(why, 'unsafe', 'and says why')
end

do -- Windows opens it in the default browser through ShellExecute
  B._reset()
  local calls, ran = {}, 0
  local ok, how = B.open(URL, { windows = true, ffi = fakeFfi(42, calls), execute = function() ran = ran + 1; return 0 end })
  T.check(ok, 'opened'); T.eq(how, 'shell', 'by ShellExecute')
  T.eq(calls[1], 'open ' .. URL, 'with the address')
  T.eq(ran, 0, 'no console window')
end

do -- ShellExecute refusing falls back to start, then to openWebBrowser
  B._reset()
  local commands = {}
  local ok, how = B.open(URL, { windows = true, ffi = fakeFfi(2, {}), execute = function(c) commands[#commands + 1] = c; return 0 end })
  T.check(ok, 'opened by start'); T.eq(how, 'start', 'how')
  T.eq(commands[1], 'start "" "' .. URL .. '"', 'the start command')
  B._reset()
  local brokenFfi = { cdef = function() end, load = function() error('no shell32') end, cast = function(_, v) return v end }
  local asked
  ok, how = B.open(URL, { windows = true, ffi = brokenFfi, execute = function() return 1 end, openWebBrowser = function(u) asked = u end })
  T.check(ok, 'opened by the game'); T.eq(how, 'openWebBrowser', 'how'); T.eq(asked, URL, 'with the address')
  B._reset()
  ok, how = B.open(URL, { windows = true, ffi = brokenFfi, execute = function() error('blocked') end })
  T.check(not ok, 'false when nothing works'); T.eq(how, 'none', 'and says so')
end

do -- not Windows: only the game's own opener
  local asked
  local ok, how = B.open(URL, { windows = false, ffi = fakeFfi(42, {}), execute = function() error('no') end, openWebBrowser = function(u) asked = u end })
  T.check(ok and how == 'openWebBrowser' and asked == URL, 'openWebBrowser off Windows')
end

do -- the support page, exactly, and nothing that only looks like it
  T.eq(B.SUPPORT, 'https://ko-fi.com/madmerick', 'the Ko-fi page')
  T.check(B.safe(B.SUPPORT), 'is opened')
  for _, other in ipairs({ 'https://ko-fi.com/someoneelse', 'https://ko-fi.com/madmerick" & calc', 'https://ko-fi.com/madmerick/x', 'http://ko-fi.com/madmerick' }) do
    T.check(not B.safe(other), 'not ' .. other)
  end
  B._reset()
  local calls = {}
  local ok, how = B.open(B.SUPPORT, { windows = true, ffi = fakeFfi(42, calls) })
  T.check(ok and how == 'shell', 'Windows opens it in the default browser'); T.eq(calls[1], 'open ' .. B.SUPPORT, 'the Ko-fi page')
end

T.done('browser')
