"""The server update script (server/update/update-server.ps1), run with PowerShell 7 where it's installed (GitHub's
runners have it). A pretend server stands in for BeamMP: a shell script that writes the log lines the real one does."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'server' / 'update' / 'update-server.ps1'
PWSH = shutil.which('pwsh')

TRUCKING_LUA = (ROOT / 'server' / 'WorldwideTrucking' / 'main.lua').read_text(encoding='utf-8')

# The pretend BeamMP server: writes the plugin lines the files in its folder would print, does what the trucking
# plugin does with restart.json (sends everyone off and deletes it), and runs until it's stopped.
FAKE_SERVER = '''#!/bin/sh
cd "$(dirname "$0")"
: > Server.log
grep -q 'G.MEET_M' Resources/Server/BeamNGEarth/main.lua && echo '[LUA] [BeamNG.Earth] plugin loaded (time real)' >> Server.log
grep -q 'BROKEN' Resources/Server/WorldwideTrucking/main.lua || echo '[LUA] [Trucking] plugin loaded: season 1' >> Server.log
while true; do
  [ -f Resources/Server/WorldwideTrucking/restart.json ] && cp Resources/Server/WorldwideTrucking/restart.json seen-restart.json && rm Resources/Server/WorldwideTrucking/restart.json
  sleep 1
done
'''

EARTH_LUA = '''local G = {}
G.MEET_M = 3000             -- a joining player farther than this from the others is sent to them
G.SHARE_OUT_KBPS = 1024     -- KB/s
G.TIME = 'real'
'''


def powershell(*args, cwd=None):
    return subprocess.run([PWSH, '-NoProfile', '-NonInteractive', *args], capture_output=True, text=True, cwd=cwd,
                          timeout=300)


def write_zip(path, files):
    with ZipFile(path, 'w') as z:
        for name, text in files.items():
            z.writestr(name, text)


@unittest.skipUnless(PWSH, 'PowerShell 7 (pwsh) is not installed')
class UpdateScriptFunctions(unittest.TestCase):
    def run_lib(self, code):
        result = powershell('-Command', f". '{SCRIPT}' -LibraryOnly; {code}")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_trucking_settings_are_kept(self):
        with tempfile.TemporaryDirectory() as d:
            old = TRUCKING_LUA.replace('W.SEASON = 1', 'W.SEASON = 4') \
                .replace("'Welcome to the Worldwide Trucking Career!',", "'Welcome, {truckers} -- \"G\\'day\"',") \
                .replace('W.SHIP_CONTAINERS = 5', 'W.SHIP_CONTAINERS = 0')
            new = TRUCKING_LUA.replace('W.PROTO = 1', 'W.PROTO = 1 -- new version')
            Path(d, 'old.lua').write_text(old, encoding='utf-8')
            Path(d, 'new.lua').write_text(new, encoding='utf-8')
            out = self.run_lib(
                f"$c = Copy-LuaSettings (Read-Text '{d}/old.lua') (Read-Text '{d}/new.lua') $DefaultTruckingSettings; "
                f"Write-Text '{d}/out.lua' $c.Text; $c.Carried -join ','")
            merged = Path(d, 'out.lua').read_text(encoding='utf-8')
        self.assertEqual(out.strip(), 'W.SEASON,W.WELCOME,W.SHIP_CONTAINERS')
        self.assertIn('W.SEASON = 4', merged)
        self.assertIn('W.SHIP_CONTAINERS = 0', merged)
        self.assertIn("'Welcome, {truckers} -- \"G\\'day\"',", merged, 'braces and quotes in a string are fine')
        self.assertIn('W.PROTO = 1 -- new version', merged, 'the rest is the new version')
        self.assertIn('Valparaíso', merged, 'and stays UTF-8')
        self.assertEqual(merged.count('W.WELCOME = {'), 1)
        self.assertEqual(len(merged), len(new) + len(old) - len(TRUCKING_LUA))

    def test_earth_settings_are_put_back(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'main.lua').write_text(EARTH_LUA, encoding='utf-8')
            self.run_lib(
                f"$v = [ordered]@{{ 'G.MEET_M' = '100000000'; 'G.SHARE_OUT_KBPS' = '256'; 'G.TIME' = \"'20:30'\" }}; "
                f"Write-Text '{d}/main.lua' (Set-LuaValues (Read-Text '{d}/main.lua') $v)")
            text = Path(d, 'main.lua').read_text(encoding='utf-8')
            self.assertIn('G.MEET_M = 100000000             -- a joining player', text)
            self.assertIn('G.SHARE_OUT_KBPS = 256     -- KB/s', text)
            self.assertIn("G.TIME = '20:30'", text)
            result = powershell('-Command', f". '{SCRIPT}' -LibraryOnly; "
                                f"Set-LuaValues (Read-Text '{d}/main.lua') @{{ 'G.GONE' = '1' }}")
            self.assertNotEqual(result.returncode, 0, 'a setting BeamNG.Earth no longer has stops the update')
            self.assertIn('G.GONE', result.stdout + result.stderr)


@unittest.skipUnless(PWSH and os.name != 'nt', 'needs PowerShell 7 on Linux or macOS')
class UpdateScriptRun(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = Path(self.temp.name)
        self.server = base / 'server'
        self.backups = base / 'server-backups'
        self.releases = base / 'releases'
        self.releases.mkdir()
        files = {
            'BeamMP-Server': FAKE_SERVER,
            'ServerConfig.toml': 'AuthKey = "my-secret-key"\nName = "Worldwide Trucking Career"\n',
            'Resources/Server/BeamNGEarth/main.lua': EARTH_LUA.replace('3000', '100000000').replace('1024', '256'),
            'Resources/Server/BeamNGEarth/store/area1.bin': 'road plans',
            'Resources/Client/beamng_earth.zip': 'earth 1.9.0',
            'Resources/Server/WorldwideTrucking/main.lua': TRUCKING_LUA.replace('W.SEASON = 1', 'W.SEASON = 2'),
            'Resources/Server/WorldwideTrucking/careers/season-2/abc.json': '{"money": 1234}',
            'Resources/Client/worldwide-trucking-dangerous-contracts.zip': 'build 155',
            'update-state.json': json.dumps({'earth': 'v1.9.0-beta', 'trucking': 'build-155'}),
        }
        for name, text in files.items():
            path = self.server / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        (self.server / 'BeamMP-Server').chmod(0o755)
        self.settings = base / 'update-settings.json'
        self.settings.write_text(json.dumps({'ServerFolder': str(self.server), 'StartSeconds': 8, 'KeepBackups': 2}))

    def tearDown(self):
        subprocess.run(['pkill', '-f', str(self.server)], capture_output=True)
        self.temp.cleanup()

    def release(self, which, tag, asset, files):
        write_zip(self.releases / asset, files)
        (self.releases / f'{which}.json').write_text(json.dumps({
            'tag_name': tag, 'published_at': '2026-01-01T00:00:00Z',
            'assets': [{'name': asset, 'browser_download_url': str(self.releases / asset)}]}))

    def new_releases(self, broken=False):
        self.release('earth', 'v1.9.1-beta', 'BeamNG.Earth-Host-1.9.1-beta-Linux-x86_64.zip', {
            'BeamMP-Server': FAKE_SERVER,
            'ServerConfig.toml': 'AuthKey = ""\n',
            'Resources/Server/BeamNGEarth/main.lua': EARTH_LUA + 'G.NEW = 1\n',
            'Resources/Client/beamng_earth.zip': 'earth 1.9.1',
        })
        self.release('trucking', 'build-156', 'worldwide-trucking-server.zip', {
            'Resources/Server/WorldwideTrucking/main.lua': TRUCKING_LUA + ('-- BROKEN\n' if broken else '-- build 156\n'),
            'Resources/Client/worldwide-trucking-dangerous-contracts.zip': 'build 156',
            'update-server.ps1': SCRIPT.read_text(encoding='utf-8'),
        })

    def update(self, *args):
        return powershell('-File', str(SCRIPT), '-SettingsFile', str(self.settings), '-ReleasesFrom',
                          str(self.releases), *args)

    def read(self, name):
        return (self.server / name).read_text(encoding='utf-8')

    def test_up_to_date_changes_nothing(self):
        self.release('earth', 'v1.9.0-beta', 'BeamNG.Earth-Host-1.9.0-beta-Linux-x86_64.zip', {'x': ''})
        self.release('trucking', 'build-155', 'worldwide-trucking-server.zip', {'x': ''})
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Up to date: BeamNG.Earth 1.9.0-beta and trucking build 155', result.stdout)
        self.assertEqual([p for p in self.backups.iterdir() if p.name[0].isdigit()], [], 'no backup, nothing touched')

    def test_check_only(self):
        self.new_releases()
        result = self.update('-CheckOnly')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('New: BeamNG.Earth 1.9.1-beta and trucking build 156', result.stdout)
        self.assertEqual(self.read('Resources/Client/beamng_earth.zip'), 'earth 1.9.0', 'nothing changed')

    def test_update_while_running(self):
        self.new_releases()
        subprocess.Popen([str(self.server / 'BeamMP-Server')], cwd=self.server, start_new_session=True)
        result = self.update('-Now')
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, out)
        self.assertTrue((self.server / 'seen-restart.json').exists(), 'the plugin was asked to send everyone off')
        self.assertIn('BeamNG.Earth 1.9.1-beta', json.loads(self.read('seen-restart.json'))['why'])
        self.assertEqual(self.read('Resources/Client/beamng_earth.zip'), 'earth 1.9.1', 'the new BeamNG.Earth')
        self.assertEqual(self.read('Resources/Client/worldwide-trucking-dangerous-contracts.zip'), 'build 156')
        self.assertIn('my-secret-key', self.read('ServerConfig.toml'), 'ServerConfig.toml is never replaced')
        earth = self.read('Resources/Server/BeamNGEarth/main.lua')
        self.assertIn('G.MEET_M = 100000000', earth, 'MEET_M put back')
        self.assertIn('G.SHARE_OUT_KBPS = 256', earth, 'SHARE_OUT_KBPS put back')
        self.assertIn('G.NEW = 1', earth, 'the rest is the new version')
        trucking = self.read('Resources/Server/WorldwideTrucking/main.lua')
        self.assertIn('W.SEASON = 2', trucking, 'the season is kept')
        self.assertIn('-- build 156', trucking)
        self.assertEqual(self.read('Resources/Server/WorldwideTrucking/careers/season-2/abc.json'), '{"money": 1234}')
        self.assertEqual(self.read('Resources/Server/BeamNGEarth/store/area1.bin'), 'road plans')
        state = json.loads(self.read('update-state.json'))
        self.assertEqual((state['earth'], state['trucking']), ('v1.9.1-beta', 'build-156'))
        backups = [p for p in self.backups.iterdir() if p.name[0].isdigit()]
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'Resources/Client/beamng_earth.zip').read_text(), 'earth 1.9.0', 'the old version is backed up')
        self.assertTrue((backups[0] / 'Resources/Server/WorldwideTrucking/careers/season-2/abc.json').exists(), 'with the careers')
        self.assertFalse((backups[0] / 'Resources/Server/BeamNGEarth/store').exists(), 'but not the big road store')
        self.assertIn('Done. The server is up', out)
        # Running again: up to date.
        again = self.update()
        self.assertIn('Up to date', again.stdout)

    def test_failed_start_rolls_back(self):
        self.new_releases(broken=True)
        result = self.update('-Now')
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, out)
        self.assertIn('Putting the backup back', out)
        self.assertIn('back up on the old version', out)
        self.assertEqual(self.read('Resources/Client/beamng_earth.zip'), 'earth 1.9.0', 'the old BeamNG.Earth is back')
        self.assertNotIn('BROKEN', self.read('Resources/Server/WorldwideTrucking/main.lua'))
        self.assertEqual(json.loads(self.read('update-state.json'))['earth'], 'v1.9.0-beta')
        self.assertTrue(list(self.backups.glob('failed-*.log')), 'the failed log is kept')
        self.assertIn('[Trucking] plugin loaded', self.read('Server.log'), 'the old version is running again')

    def test_refuses_a_folder_that_is_not_a_server(self):
        self.new_releases()
        elsewhere = Path(self.temp.name) / 'downloads'
        elsewhere.mkdir()
        self.settings.write_text(json.dumps({'ServerFolder': str(elsewhere)}))
        result = self.update('-Now')
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 2, out)
        self.assertIn("this isn't a server folder", out)
        self.assertEqual([p.name for p in elsewhere.iterdir()], [], 'nothing is put in it')

    def test_the_settings_example_ships_blank(self):
        example = json.loads((ROOT / 'server' / 'update' / 'update-settings.example.json').read_text())
        self.assertEqual(example['DiscordWebhook'], '', 'no webhook in the download')
        self.assertNotIn('ServerFolder', [k for k, v in example.items() if v], 'and no one\'s own folder')

    def test_a_missing_earth_setting_stops_before_touching_the_server(self):
        self.new_releases()
        self.settings.write_text(json.dumps({'ServerFolder': str(self.server), 'EarthSettings': {'G.GONE': '1'}}))
        result = self.update('-Now')
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 2, out)
        self.assertIn('The server was not changed', out)
        self.assertEqual(self.read('Resources/Client/beamng_earth.zip'), 'earth 1.9.0')


if __name__ == '__main__':
    unittest.main()
