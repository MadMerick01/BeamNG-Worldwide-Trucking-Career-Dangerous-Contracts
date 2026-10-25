# BeamNG 0.39 API dump

Reference only. Nothing in `docs/beamng-api/` ships in the mod ZIP; `tools/package.py`
packages an explicit list of docs, and `tests/test_package.py` checks this folder stays out.

## Files

- `raw/api_dump_0.39.txt`: indented text dump of the game-engine (GE) Lua state, max depth 5.
  Fastest to grep.
- `raw/api_dump_0.39.json`: the same dump as JSON (`roots` → `_G`, `be`, `core_vehicle_manager`,
  `extensions`, `scenetree`). Use it when you need structure.
- Copied unchanged from `MadMerick01/BolidesTheCutbyAbleMerick` `docs/beamng-api/raw` at commit
  `d27bd74`. SHA-256: json `6369eea1…f4b47a4`, txt `60a32bb3…ce5cf01`.

## Searching

```
python tools/api_lookup.py --table extensions.core_vehicles   # every function on a table
python tools/api_lookup.py --grep 'repair|spawnNew'           # function names matching a regex
```

Verify each BeamNG symbol here before calling it. If it is missing, guard the call
(`if core_vehicles and core_vehicles.spawnNewVehicle then`) rather than assuming it exists.

## What the dump covers, and what it does not

- It was taken **outside career mode**. No `career_modules_*` tables are present, so career's
  own repair, insurance, vehicle shop, part shop and part inventory modules cannot be confirmed
  from it. Only `career_career`, `career_saveSystem` and `career_branches` are loaded.
- It is **GE Lua only**. Vehicle-side Lua (`obj:`, `beamstate`, `partCondition`, `damageTracker`)
  is not in it; vehicle-context calls go through `be:getPlayerVehicle(0):queueLuaCommand(...)`
  and need checking in game.
- Tables the dump had already visited elsewhere appear as `"visited": true` with no functions;
  `tools/api_lookup.py` picks the first full copy (for example `_G.extensions.core_vehicles`
  rather than `_G.core_vehicles`).

## Where the HUD's next features live

### Repair vehicle

| Symbol | Notes |
| --- | --- |
| `extensions.core_vehicle_manager.reloadVehicle` | Respawns physics for a vehicle, which restores it undamaged. |
| `extensions.core_vehicles.reloadVehicle` | Same idea via the vehicles extension. |
| `package.loaded["vehicle/recovery"]`: `recoverInPlace`, `startRecovering`, `stopRecovering`, `saveHome`, `loadHome` | Recovery/rewind helpers. |
| `extensions.core_recoveryPrompt`: `addButton`, `removeButtonById`, `setButtonEnabledById`, `setButtonLimits`, `handleCurrRecoveryOption`, `setDefaultsForFreeroam` | The game's recovery menu; a place to hang a paid "repair" option. |
| `extensions.gameplay_util_damageAssessment`: `getOverallDamageLevel`, `getSectionsDamageInfoRaw`, `calculateDamageVariation`, `getTextualBeamDamageLocations` | Read damage to price a repair. |
| `extensions.gameplay_missions_missionScreen.getRepairCostForStartingRepairType` | The game's own repair pricing for missions. |
| `_G.vehicleReset`, `_G.resetGameplay` | Global reset hooks. |

### Purchase / spawn vehicle

| Symbol | Notes |
| --- | --- |
| `extensions.core_vehicles.spawnNewVehicle`, `replaceVehicle`, `spawnDefault`, `cloneCurrent` | Spawn a new vehicle or swap the player's current one. |
| `extensions.core_vehicles.getModelList`, `getModel`, `getConfigList`, `getConfig`, `getVehicleDetails`, `getCurrentVehicleDetails` | Build the "for sale" list; config data carries values such as price. |
| `extensions.core_vehicles.removeCurrent`, `removeAll`, `removeAllExceptCurrent` | Remove vehicles. |
| `package.loaded.spawn`: `spawnVehicle`, `spawnPlayer`, `pickSpawnPoint`, `safeTeleport`, `placeTrailer` | Lower-level spawn placement. |
| `extensions.core_multiSpawn`: `spawnGroup`, `setVehicleSpawnData` | Groups of vehicles. |
| `_G`: `canSpawnAnotherVehicle`, `fillVehicleSpawnOptionDefaults`, `sanitizeVehicleSpawnOptions`, `getPlayerVehicle` | Spawn option helpers. |
| `extensions.core_vehicle_manager`: `getPlayerVehicleData`, `getVehicleData` | Read a spawned vehicle's config. |

### Purchase / fit parts

| Symbol | Notes |
| --- | --- |
| `core_vehicle_partmgmt`: `getConfig`, `setConfig`, `setPartsConfig`, `setPartsTreeConfig`, `setNewParts`, `selectParts`, `hasAvailablePart`, `getConfigOfVehicle`, `setConfigOfVehicle` | Read and change fitted parts. |
| `core_vehicle_partmgmt`: `resetPartsToLoadedConfig`, `resetAllToLoadedConfig`, `setConfigVars`, `setConfigPaints` | Revert parts, tuning vars and paint. |
| `extensions.core_vehicles.openPartsSelectorUI` | Opens the game's own parts UI. |
| `core_inventory`: `addItem`, `getItem`, `getItemList`, `removeItem` (field `itemsTable`) | Generic item inventory; a candidate store for owned parts. |
| `extensions.util_richPresence`: `onPartShoppingStarted`, `onPartShoppingTransactionComplete`, `onPartShoppingCancelled` | Hook names show a part-shopping flow exists in career, even though its module is not in this dump. |
