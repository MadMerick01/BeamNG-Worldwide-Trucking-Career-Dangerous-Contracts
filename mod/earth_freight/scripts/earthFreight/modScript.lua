-- BeamNG's mod manager runs this once the mod is mounted, then loads manual extensions.
-- First: another copy of the trucking mod already running (BeamMP turned the player's own copy off for a server's,
-- or back on after it): its code is unloaded, so the mod manager loads this copy's (modswap.lua; dofile, as a require
-- would return the running copy's module).
do
  local ok, swap = pcall(dofile, '/lua/ge/extensions/earthFreight/modswap.lua')
  if ok and type(swap) == 'table' and type(swap.check) == 'function' then pcall(swap.check, 'its modScript', false) end
end
setExtensionUnloadMode('earthFreight_core', 'manual')
