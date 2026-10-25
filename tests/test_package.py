"""Validate the distributed layout/assets, not just the development checkout."""
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from zipfile import ZipFile

from lupa.luajit21 import LuaRuntime

from tools.package import build

ROOT = Path(__file__).resolve().parents[1]


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = build(Path(self.temp.name) / 'freight.zip')

    def test_archive_layout_is_standalone_and_excludes_user_data(self):
        with ZipFile(self.output) as archive:
            names = set(archive.namelist())
            for name in ('scripts/earthFreight/modScript.lua', 'lua/ge/extensions/earthFreight/core.lua',
                         'lua/ge/extensions/earthFreight/placesIndex.lua', 'lua/ge/extensions/earthFreight/tiles/s35e150.lua',
                         'ui/modules/apps/EarthFreightHUD/app.json',
                         'README.md', 'docs/DESIGN.md', 'config.example.json'):
                self.assertIn(name, names)
            self.assertFalse(any(n.startswith(('settings/', 'tests/', 'tools/', 'earth_freight/', 'docs/beamng-api/')) for n in names))
            self.assertFalse(any('save-a.json' in n or 'save-b.json' in n or n.endswith('.pyc') for n in names))
            self.assertIsNone(archive.testzip())

    def test_manifest_configuration_and_app_assets_are_consistent(self):
        prefix = 'ui/modules/apps/EarthFreightHUD/'
        with ZipFile(self.output) as archive:
            manifest = json.loads(archive.read(prefix + 'app.json'))
            config = json.loads(archive.read('config.example.json'))
            self.assertEqual(manifest['appName'], 'EarthFreightHUD')
            self.assertEqual(manifest['name'], 'Earth Freight Sim')
            self.assertEqual(manifest['directive'], 'earthFreightHud')
            self.assertIn('earth-freight-hud', manifest['domElement'])
            self.assertEqual(config['base'], {'latitude': -33.75, 'longitude': 150.7})
            self.assertIn(b'/ui/modules/apps/EarthFreightHUD/app.html', archive.read(prefix + 'app.js'))
            self.assertIn(b'earthFreight_core', archive.read('scripts/earthFreight/modScript.lua'))

    def test_starter_car_config_is_packaged(self):
        prefix = 'vehicles/burnside/'
        with ZipFile(self.output) as archive:
            config = json.loads(archive.read(prefix + 'earth_freight_starter.pc'))
            info = json.loads(archive.read(prefix + 'info_earth_freight_starter.json'))
            thumbnail = archive.read(prefix + 'earth_freight_starter.jpg')
            workshop = archive.read('lua/ge/extensions/earthFreight/workshop.lua')
        self.assertEqual(config['model'], 'burnside')
        self.assertIsInstance(config['parts'], dict)
        self.assertEqual(info['Configuration'], 'Earth_Freight_Starter')
        self.assertEqual(thumbnail[:3], b'\xff\xd8\xff')
        self.assertIn(b"'" + (prefix + 'earth_freight_starter.pc').encode() + b"'", workshop)

    def test_png_is_complete_with_valid_checksums(self):
        with ZipFile(self.output) as archive:
            data = archive.read('ui/modules/apps/EarthFreightHUD/app.png')
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        offset, ended = 8, False
        while offset < len(data):
            size, = struct.unpack('>I', data[offset:offset + 4])
            kind = data[offset + 4:offset + 8]
            body = data[offset + 8:offset + 8 + size]
            checksum, = struct.unpack('>I', data[offset + 8 + size:offset + 12 + size])
            self.assertEqual(checksum, zlib.crc32(kind + body))
            if kind == b'IEND':
                ended = True
            offset += 12 + size
        self.assertTrue(ended)
        self.assertEqual(offset, len(data))

    def test_packaged_lua_loads_on_its_own(self):
        prefix = 'lua/ge/extensions/'
        with ZipFile(self.output) as archive:
            sources = {name[len(prefix):-4]: archive.read(name).decode('utf-8')
                       for name in archive.namelist() if name.startswith(prefix) and name.endswith('.lua')}
        lua = LuaRuntime()
        lua.globals().zipModules = lua.table_from(sources)
        lua.execute('''
          package.path = '' -- Do not allow fallback to the development checkout.
          table.insert(package.loaders, 2, function(name)
            local code = zipModules[name]
            if not code then return '\\nmodule absent from ZIP: ' .. name end
            return assert(loadstring(code, '@ZIP/' .. name .. '.lua'))
          end)
          packagedDefaults = require('earthFreight/config').load({
            exists = function() return false end,
            read = function() error('missing configuration must not be read') end,
          })
          packagedCore = require('earthFreight/core')
          packagedPlaces = #require('earthFreight/places').list
        ''')
        g = lua.globals()
        self.assertEqual(g.packagedDefaults['base']['latitude'], -33.75)
        self.assertEqual(g.packagedDefaults['resumeRadiusMetres'], 50)
        self.assertTrue(g.packagedDefaults['autoGps'])
        self.assertGreater(g.packagedPlaces, 30)

    def test_package_is_reproducible(self):
        second = build(Path(self.temp.name) / 'second.zip')
        self.assertEqual(hashlib.sha256(self.output.read_bytes()).digest(),
                         hashlib.sha256(second.read_bytes()).digest())

    def test_place_list_matches_its_generator(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / 'make_places.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
