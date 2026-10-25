local dir = (arg[0]:match('^(.*)[/\\]') or '.')
package.path = dir .. '/../mod/earth_freight/lua/ge/extensions/?.lua;' .. dir .. '/?.lua;' .. package.path
local T = { passed = 0, failed = 0 }
function T.check(ok, message)
  if ok then T.passed = T.passed + 1 else T.failed = T.failed + 1; print('FAIL: ' .. message) end
end
function T.eq(actual, expected, message) T.check(actual == expected, message .. ' (got ' .. tostring(actual) .. ')') end
function T.near(actual, expected, tolerance, message)
  T.check(type(actual) == 'number' and math.abs(actual - expected) <= tolerance, message .. ' (got ' .. tostring(actual) .. ')')
end
function T.done(name)
  print(name .. ': ' .. T.passed .. ' passed, ' .. T.failed .. ' failed')
  os.exit(T.failed == 0 and 0 or 1)
end
return T
