-- Heli flights: the rules for hiring stefan750's Revamped Bell 407 (a mod the player installs
-- themselves) to see the world and scout it: towns, terrain and the jobs on their boards. A hire
-- earns nothing and costs HIRE_FEE until the player goes back to their car. While flying, the
-- player may pick up the signal of a "don't ask questions" job (beacons.lua). Pure maths; no game
-- globals.
local M = {}

M.MOD_NAME = 'Revamped Bell 407'
M.MOD_AUTHOR = 'stefan750'
M.MOD_PAGE = 'https://www.beamng.com/threads/revamped-bell-407-with-weapons.98195/'
-- A hire lasts until the player is back in their car; hiring again costs the fee again.
M.HIRE_FEE = 1000
-- A crash ends the hire, and costs this (or all the player's money, if less).
M.CRASH_FEE = 1000
-- From this much damage the helicopter has crashed: half of what BeamNG calls major, as for cars.
M.CRASH_DAMAGE = 15000
-- The towns listed on the Heli tab, nearest first.
M.TOWNS = 5
-- Back to my car swaps in place within RETURN_METRES of the car, landed; farther, Earth teleports
-- there first and the swap waits for the terrain for SETTLE_SECONDS, giving up after TELEPORT_SECONDS.
M.RETURN_METRES, M.LANDED_METRES, M.SETTLE_SECONDS, M.TELEPORT_SECONDS = 150, 3, 2, 30
-- How long the helicopter, or the car coming back, has to turn up before the swap is called off.
M.SPAWN_SECONDS = 10

local function lower(s) return type(s) == 'string' and s:lower() or '' end
-- Configs fitted with guns are left for when nothing else is installed.
local ARMED = { 'weapon', 'armed', 'gun', 'rocket', 'military', 'missile' }
local function armed(info)
  local name = lower(info.name) .. ' ' .. lower(info.key)
  for _, word in ipairs(ARMED) do if name:find(word, 1, true) then return true end end
  return false
end

-- Whether a config from the game's list is a Bell 407: its model or name says Bell and 407.
function M.isHeli(info)
  if type(info) ~= 'table' or type(info.model) ~= 'string' or type(info.key) ~= 'string' then return false end
  local text = lower(info.model) .. ' ' .. lower(info.name)
  return text:find('407', 1, true) ~= nil and text:find('bell', 1, true) ~= nil
end

-- The Bell 407 config to hire from the game's config list, or nil when the mod is not installed:
-- one without weapons if there is one (one with a hook first), then the cheapest.
function M.findHeli(list)
  local best, bestScore
  for _, info in ipairs(list or {}) do
    if M.isHeli(info) then
      local score = (armed(info) and 2 or 0) + ((lower(info.name) .. lower(info.key)):find('hook', 1, true) and 0 or 1)
      local value = tonumber(info.value) or math.huge
      if not best or score < bestScore or (score == bestScore and (value < (tonumber(best.value) or math.huge)
          or (value == (tonumber(best.value) or math.huge) and info.model .. '/' .. info.key < best.model .. '/' .. best.key))) then
        best, bestScore = info, score
      end
    end
  end
  return best and { model = best.model, key = best.key, config = best.config, name = best.name } or nil
end

return M
