#!/usr/bin/env python3
"""Check Earth Freight's position reading and GPS call against real BeamNG.Earth releases in a git checkout.

For each release it runs Earth Freight's adapter with Earth's real geodesy.lua anchor, and reports
which of the adapter's position sources that release still provides, and whether its GPS module
still has setDestination. Read-only.

    python tools/check_earth_versions.py C:\\path\\to\\BeamNG.Earth            # every v* tag + HEAD
    python tools/check_earth_versions.py C:\\path\\to\\BeamNG.Earth HEAD v1.5.5-beta
"""
import argparse
import re
import subprocess
from pathlib import Path

from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
EARTH = 'mod/beamng_earth/lua/ge/extensions/beamngEarth/'
BASE = (-33.60147222, 150.82288889)
CHECK = '''
local geodesySource = ...
local geodesy = assert(loadstring(geodesySource, '@geodesy.lua'))()
local Adapter = require('earthFreight/earthAdapter')
local L = require('earthFreight/location')
local anchor = geodesy.newAnchor(BASE_LAT, BASE_LON)
local pos = { x = 0, y = 1000, z = 0 } -- 1 km north of the anchor origin
local vehicle = { getPosition = function() return pos end, getID = function() return 1 end }
local core = { _state = function() return { anchor = anchor } end }
local s = Adapter.new({ core = function() return core end, module = function() end,
  vehicle = function() return vehicle end }):sample()
if not s.valid then return false, 'adapter: ' .. tostring(s.reason) .. ' ' .. tostring(s.detail) end
local north = L.distance({ latitude = BASE_LAT, longitude = BASE_LON }, s)
if math.abs(north - 1000) > 5 then return false, string.format('anchor conversion off: %.1f m', north) end
return true, s.source
'''


def show(repo, ref, path):
    result = subprocess.run(['git', '-C', str(repo), 'show', f'{ref}:{path}'], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def check(repo, ref):
    geodesy, core, places, gps = (show(repo, ref, EARTH + n) for n in ('geodesy.lua', 'core.lua', 'places.lua', 'gps.lua'))
    if not geodesy or not core:
        return False, 'Earth source files not found'
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.moduleRoot = str(ROOT / 'mod' / 'earth_freight' / 'lua' / 'ge' / 'extensions')
    g.BASE_LAT, g.BASE_LON = BASE
    lua.execute("package.path = moduleRoot .. '/?.lua;' .. package.path")
    ok, detail = lua.execute(CHECK, geodesy)
    if not ok:
        return False, detail
    sources = [name for name, found in (
        ('anchor', 'function M._state' in core and 'function Anchor:enuToGeodetic' in geodesy
         and re.search(r'\banchor\s*=', core)),
        ('player', re.search(r'st\.player\s*=\s*\{[^}]*\blat\s*=', core)),
        ('places', places and 'function M.here' in places),
    ) if found]
    if not sources:
        return False, 'no position source found'
    has_gps = bool(gps and re.search(r'function\s+M\.setDestination\s*\(|M\.setDestination\s*=', gps))
    return True, 'sources: ' + ', '.join(sources) + ('; GPS setDestination found' if has_gps else '; no GPS setDestination (drop-offs need setting by hand)')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('earth_checkout', type=Path)
    parser.add_argument('refs', nargs='*', help='git refs to check (default: every v* tag and HEAD)')
    args = parser.parse_args()
    refs = args.refs or subprocess.run(['git', '-C', str(args.earth_checkout), 'tag', '--list', 'v*', '--sort=version:refname'],
                                       capture_output=True, text=True, check=True).stdout.split() + ['HEAD']
    failures = 0
    for ref in refs:
        ok, detail = check(args.earth_checkout, ref)
        failures += not ok
        print(f'{"OK  " if ok else "FAIL"} {ref:<20} {detail}')
    print(f'{len(refs) - failures}/{len(refs)} Earth versions supported.')
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
