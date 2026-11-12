#!/usr/bin/env python3
"""Build the land map the BeamMP server plugin uses for the land meter (which share of Earth's land each base and
its corp hold). The world is cut into 1° squares, from 60°S (Antarctica is left out) to 90°N, and a square counts
as land when its centre is on land. The squares are written into server/WorldwideTrucking/main.lua, between the
LAND BEGIN and LAND END lines, one line of runs per row of latitude. Built offline, never on the server.

    python tools/make_land.py            # rebuild the land map in main.lua
    python tools/make_land.py --check    # fail if it is out of date

Input: tools/data/ne_110m_land.geojson, Natural Earth's 1:110m land polygons (public domain, naturalearthdata.com).
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAND = ROOT / 'tools' / 'data' / 'ne_110m_land.geojson'
MAIN = ROOT / 'server' / 'WorldwideTrucking' / 'main.lua'
SOUTH, NORTH = -60, 90
BEGIN, END = '-- LAND BEGIN', '-- LAND END'


def rings():
    data = json.loads(LAND.read_text(encoding='utf-8'))
    for feature in data['features']:
        geometry = feature['geometry']
        polygons = [geometry['coordinates']] if geometry['type'] == 'Polygon' else geometry['coordinates']
        for polygon in polygons:
            for ring in polygon:
                yield ring


def row_cells(edges, lat):
    """The land squares (0 is 180°W to 179°W) along one line of latitude: where it crosses the coastlines, inside
    and outside by turns (even-odd)."""
    xs = []
    for (x1, y1), (x2, y2) in edges:
        if (y1 > lat) != (y2 > lat):
            xs.append(x1 + (lat - y1) * (x2 - x1) / (y2 - y1))
    xs.sort()
    cells = []
    for a, b in zip(xs[0::2], xs[1::2]):
        for i in range(360):
            lon = -180 + i + 0.5
            if a <= lon < b:
                cells.append(i)
    return sorted(set(cells))


def runs(cells):
    out = []
    for i in cells:
        if out and out[-1][1] == i - 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return ','.join(f'{a}' if a == b else f'{a}-{b}' for a, b in out)


def build():
    edges = []
    for ring in rings():
        for p, q in zip(ring, ring[1:] + ring[:1]):
            if p != q:
                edges.append(((p[0], p[1]), (q[0], q[1])))
    lines = [BEGIN,
             f'-- Made by tools/make_land.py from Natural Earth (public domain): row 1 is {SOUTH}°..{SOUTH + 1}°, each a list',
             '-- of 1° squares (0 is 180°W..179°W) whose centre is on land. Antarctica is left out.',
             f'W.LAND_SOUTH = {SOUTH}',
             'W.LAND_ROWS = {']
    for lat in range(SOUTH, NORTH):
        lines.append(f"  '{runs(row_cells(edges, lat + 0.5))}',")
    lines += ['}', END]
    return '\n'.join(lines)


def replace(text, block):
    start, end = text.index(BEGIN), text.index(END) + len(END)
    return text[:start] + block + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--check', action='store_true', help='fail if main.lua is out of date')
    args = parser.parse_args()
    text = MAIN.read_text(encoding='utf-8')
    new = replace(text, build())
    if args.check:
        if new != text:
            print('main.lua: the land map is out of date. Run python tools/make_land.py', file=sys.stderr)
            return 1
        return 0
    MAIN.write_text(new, encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
