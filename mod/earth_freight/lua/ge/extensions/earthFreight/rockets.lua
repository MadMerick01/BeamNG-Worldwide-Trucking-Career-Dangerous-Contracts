-- JATO rockets. Online they win races and pile up jobs far faster than any truck could drive them, so on a BeamMP
-- server: while rockets are fitted to the car or its hitched trailer no job can be taken, and a job that had them
-- fitted at any point pays nothing when it is delivered. A Mayday Rescue run ends as soon as they are seen. Single
-- player is left alone. No game globals here: the garage reads the parts (garage.lua g:rockets).
local M = {}

M.CHECK_SECONDS = 2 -- how often the car's parts are looked at

M.TAKE_PROBLEM = 'JATO rockets are not allowed online. Remove them in the parts menu to take jobs.'
M.MAYDAY_PROBLEM = 'JATO rockets are not allowed online. Remove them in the parts menu to start a Mayday Rescue run.'
M.PAID_NOTHING = 'JATO rockets were fitted on this job, so it paid nothing.'
M.JOB_LOST = 'JATO rockets were fitted on this job, so it pays nothing when you deliver it. Remove them before your next job.'

-- Whether a part (or the slot it sits in) is a JATO rocket: any part with "jato" in its name, so modded rockets
-- named after the game's own are caught too. An empty slot ('') holds nothing.
function M.isRocket(partName, slotPath)
  if type(partName) ~= 'string' or partName == '' then return false end
  if partName:lower():find('jato', 1, true) then return true end
  return type(slotPath) == 'string' and slotPath:lower():find('jato', 1, true) ~= nil
end

-- Whether a flat { [slot] = part name } list has a rocket in it.
function M.inParts(parts)
  if type(parts) ~= 'table' then return false end
  for slot, part in pairs(parts) do
    if M.isRocket(part, tostring(slot)) then return true end
  end
  return false
end

-- Whether a partsTree (BeamNG 0.39: { path, chosenPartName, children = { ... } }) has a rocket fitted anywhere.
function M.inTree(node, depth)
  depth = depth or 1
  if type(node) ~= 'table' or depth > 64 then return false end
  if M.isRocket(node.chosenPartName, node.path or node.id) then return true end
  if type(node.children) == 'table' then
    for _, child in pairs(node.children) do
      if M.inTree(child, depth + 1) then return true end
    end
  end
  return false
end

return M
