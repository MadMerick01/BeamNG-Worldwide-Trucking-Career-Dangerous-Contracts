#!/usr/bin/env python3
"""Search the BeamNG API dump: list a table's functions or grep function names."""
import argparse
import json
import re
from pathlib import Path

DUMP = Path(__file__).resolve().parents[1] / 'docs' / 'beamng-api' / 'raw' / 'api_dump_0.39.json'


def tables(dump: Path) -> dict:
    found = {}

    def walk(node, path):
        if not isinstance(node, dict):
            return
        functions = node.get('functions')
        if isinstance(functions, dict):
            functions = list(functions.values())
        if functions and path not in found:
            found[path] = sorted(functions)
        for key, child in (node.get('children') or {}).items():
            walk(child, path + '.' + key)

    for key, root in json.loads(dump.read_text(encoding='utf-8'))['roots'].items():
        walk(root, key)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dump', type=Path, default=DUMP)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--table', help='table path suffix, e.g. extensions.core_vehicles')
    group.add_argument('--grep', help='regex matched against function names (case-insensitive)')
    args = parser.parse_args()
    found = tables(args.dump)
    if args.table:
        matches = [path for path in found if path == args.table or path.endswith('.' + args.table)]
        for path in matches:
            print(f'{path} ({len(found[path])} functions)')
            print('  ' + ', '.join(found[path]))
        return 0 if matches else 1
    pattern = re.compile(args.grep, re.I)
    hits = 0
    for path, functions in found.items():
        names = [name for name in functions if pattern.search(name)]
        if names:
            hits += 1
            print(f'{path}: {", ".join(names)}')
    return 0 if hits else 1


if __name__ == '__main__':
    raise SystemExit(main())
