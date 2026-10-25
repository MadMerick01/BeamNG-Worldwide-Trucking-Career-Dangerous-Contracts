#!/usr/bin/env python3
"""Run each Lua test in a fresh LuaJIT process; use native LuaJIT or pinned Lupa."""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def child(path: str) -> None:
    from lupa.luajit21 import LuaRuntime
    lua = LuaRuntime()
    lua.globals().arg = lua.table_from({0: str(Path(path).resolve())})
    lua.execute('dofile(arg[0])')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child')
    args = parser.parse_args()
    if args.child:
        child(args.child)
        return 0
    luajit = shutil.which('luajit')
    if not luajit:
        try:
            import lupa.luajit21  # noqa: F401
        except ImportError:
            print('Install LuaJIT or run: python -m pip install -r tests/requirements.txt', file=sys.stderr)
            return 2
    files = sorted((ROOT / 'tests').glob('test_*.lua'))
    if not files:
        print('No Lua tests found', file=sys.stderr)
        return 2
    failures = 0
    for path in files:
        command = [luajit, str(path)] if luajit else [sys.executable, str(Path(__file__).resolve()), '--child', str(path)]
        result = subprocess.run(command, cwd=ROOT)
        failures += result.returncode != 0
    print(f'{len(files)} Lua suites executed; {failures} failed.', flush=True)
    node = shutil.which('node')
    if not node:
        print('Node.js is required for the HUD lifecycle tests.', file=sys.stderr)
        return 2
    failures += subprocess.run([node, '--test', str(ROOT / 'tests' / 'test_hud.mjs')], cwd=ROOT).returncode != 0
    failures += subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests',
                               '-p', 'test_*.py', '-v'], cwd=ROOT).returncode != 0
    return int(failures != 0)


if __name__ == '__main__':
    raise SystemExit(main())
