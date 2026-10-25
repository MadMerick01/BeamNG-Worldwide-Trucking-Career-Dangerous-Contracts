"""Filesystem/JSON and exported game-hook tests. BeamNG engine APIs are stubs."""
import json
import tempfile
import unittest
from pathlib import Path

from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'mod' / 'earth_freight'
SETTINGS = '/settings/earthFreight/'


class InstalledHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.user = Path(self.temp.name)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.sourceRoot, g.testsRoot = str(MOD / 'lua' / 'ge' / 'extensions'), str(ROOT / 'tests')
        g.pyRead, g.pyWrite = self.read_json, self.write_json
        g.pyExists = lambda p: self.path(p).is_file()
        g.pyDirExists = lambda p: self.path(p).is_dir()
        g.pyMkdir = lambda p: self.path(p).mkdir(parents=True, exist_ok=True)
        g.bootScript = str(MOD / 'scripts' / 'earthFreight' / 'modScript.lua')
        self.lua.execute('''
          package.path = sourceRoot .. '/?.lua;' .. testsRoot .. '/?.lua;' .. package.path
          local F = require('fixtures')
          fakeEarth = F.adapter()
          package.loaded['earthFreight/earthAdapter'] = { new = function() return fakeEarth end }
          FS = {
            fileExists = function(_, p) return pyExists(p) end,
            directoryExists = function(_, p) return pyDirExists(p) end,
            directoryCreate = function(_, p) pyMkdir(p); return true end,
          }
          jsonReadFile = function(p) return pyRead(p) end
          jsonWriteFile = function(p, data) return pyWrite(p, data) end
          log = function() end
          notifications = 0
          guihooks = { trigger = function() notifications = notifications + 1 end }
          setExtensionUnloadMode = function(name, mode) registeredName, registeredMode = name, mode end
          getPlayerVehicle = function() return nil end
          dofile(bootScript)
          earthFreight_core = require('earthFreight/core')
        ''')
        self.core = g.earthFreight_core
        self.partial_write = False

    def path(self, virtual):
        self.assertTrue(virtual.startswith(SETTINGS))
        result = (self.user / virtual.lstrip('/')).resolve()
        self.assertTrue(result.is_relative_to(self.user))
        return result

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.to_lua(v) for k, v in value.items()})
        return value

    def from_lua(self, value):
        if hasattr(value, 'items'):
            return {k: self.from_lua(v) for k, v in value.items()}
        return value

    def read_json(self, path):
        file = self.path(path)
        if not file.exists():
            return None
        return self.to_lua(json.loads(file.read_text()))

    def write_json(self, path, value):
        if self.partial_write:
            self.path(path).write_text('{"schemaVersion":')
            return False
        self.path(path).write_text(json.dumps(self.from_lua(value), allow_nan=False))
        return None  # Exercise the engine's potentially nil success return plus read-back verification.

    def arrive(self):
        self.core.onPreRender(0.1)
        self.assertEqual(self.core.getState()['state'], 'READY')

    def test_loader_uses_penrith_without_configuration_or_writes(self):
        self.assertEqual(self.lua.globals().registeredName, 'earthFreight_core')
        self.assertEqual(self.lua.globals().registeredMode, 'manual')
        self.core.onExtensionLoaded()
        state = self.core.getState()
        self.assertEqual(state['state'], 'EARTH_UNAVAILABLE')
        self.assertEqual(state['base']['latitude'], -33.75)
        self.assertFalse(self.core.save())
        self.arrive()
        self.assertEqual(self.core.getState()['here']['name'], 'Penrith')
        self.assertFalse(list(self.user.rglob('save-*.json')))

    def test_save_restart_and_a_delivery_load_survive_on_disk(self):
        self.core.onExtensionLoaded()
        self.arrive()
        self.core.onPreRender(0.6)
        self.core.onPreRender(0.6)
        state = self.core.getState()
        destination = state['town']['destinations'][1]['id']
        self.assertTrue(self.core.buyLoad('food', destination))
        self.assertFalse(self.core.buyLoad("food') os.exit() --", destination), 'odd ids refused')
        self.assertTrue(self.core.save())
        saved = json.loads(self.path(SETTINGS + 'save-a.json').read_text())
        self.assertEqual(saved['load']['good'], 'food')
        self.assertEqual(saved['load']['to'], destination)
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        self.arrive()
        state = self.core.getState()
        self.assertEqual(state['mode'], 'resume')
        self.assertEqual(state['load']['goodId'], 'food')

    def test_fuel_answers_reach_the_controller(self):
        self.core.onExtensionLoaded()
        self.arrive()
        self.core.fuelReading(1, 20.5, 50)
        self.core.onPreRender(0.1)
        self.assertEqual(self.core.getState()['fuel']['litres'], 20.5)

    def test_partial_disk_write_recovers_previous_generation(self):
        self.core.onExtensionLoaded()
        self.arrive()
        self.assertTrue(self.core.save())
        original = self.path(SETTINGS + 'save-a.json').read_bytes()
        self.partial_write = True
        self.assertFalse(self.core.save())
        self.assertIn('try again', self.core.getState()['saveFeedback'])
        self.assertEqual(original, self.path(SETTINGS + 'save-a.json').read_bytes())
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        self.assertEqual(self.core.getState()['mode'], 'resume')

    def test_mission_end_locks_saving_without_implicit_writes(self):
        self.core.onExtensionLoaded()
        self.arrive()
        self.core.uiMounted(True)
        self.core.onPreRender(0.1)
        self.assertGreater(self.lua.globals().notifications, 0)
        self.core.onClientEndMission()
        self.assertEqual(self.core.getState()['state'], 'EARTH_UNAVAILABLE')
        self.assertFalse(self.core.save())
        self.assertFalse(list(self.user.rglob('save-*.json')))


if __name__ == '__main__':
    unittest.main()
