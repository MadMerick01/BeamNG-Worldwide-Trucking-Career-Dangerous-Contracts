#!/usr/bin/env python3
"""Sample each place's elevation and relief for the region pay boost, and write
tools/data/terrain.tsv.gz for make_places.py. Run it again after the place list changes.

    python tools/make_places.py --places /tmp/places.tsv
    python tools/sample_terrain.py --places /tmp/places.tsv --cache /tmp/terrain-tiles

Elevation comes from the free Mapzen terrain tiles on AWS (Terrarium PNGs: SRTM, and other
sources where SRTM has none), at zoom ZOOM, about 600 m a pixel at the equator. A place's relief
is how far the ground rises and falls within RELIEF_RADIUS_KM of it: the 95th percentile of the
elevation there less the 5th, so a single bad pixel does not count. The sea counts as 0 m, so a
coastal town is not scored on the depth of the sea beside it. Needs numpy and Pillow.
"""
import argparse
import gzip
import io
import math
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tools' / 'data' / 'terrain.tsv.gz'
URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
ZOOM = 8
RELIEF_RADIUS_KM = 10
EARTH_RADIUS = 6371008.8
SIZE = 256


def pixel(lat, lon):
    """Global Web Mercator pixel coordinates at ZOOM."""
    n = SIZE * 2 ** ZOOM
    s = math.sin(math.radians(max(-85.05, min(85.05, lat))))
    return (lon + 180) / 360 * n, (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n


def radius_pixels(lat):
    metres_per_pixel = 2 * math.pi * EARTH_RADIUS * math.cos(math.radians(lat)) / (SIZE * 2 ** ZOOM)
    return RELIEF_RADIUS_KM * 1000 / metres_per_pixel


def tiles_for(lat, lon):
    x, y = pixel(lat, lon)
    r = radius_pixels(lat)
    n = 2 ** ZOOM
    ys = range(max(0, int((y - r) // SIZE)), min(n - 1, int((y + r) // SIZE)) + 1)
    xs = [(tx % n) for tx in range(int((x - r) // SIZE), int((x + r) // SIZE) + 1)]
    return [(tx, ty) for ty in ys for tx in xs]


def fetch(tile, cache):
    path = cache / f'{ZOOM}-{tile[0]}-{tile[1]}.png'
    if not path.exists():
        with urllib.request.urlopen(URL.format(z=ZOOM, x=tile[0], y=tile[1]), timeout=60) as response:
            data = response.read()
        path.write_bytes(data)
    return path


def decode(path):
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)
    return rgb[:, :, 0] * 256 + rgb[:, :, 1] + rgb[:, :, 2] / 256 - 32768


def sample(lat, lon, tile_array):
    x, y = pixel(lat, lon)
    r = radius_pixels(lat)
    n = SIZE * 2 ** ZOOM
    x0, x1 = int(math.floor(x - r)), int(math.ceil(x + r))
    y0, y1 = max(0, int(math.floor(y - r))), min(n - 1, int(math.ceil(y + r)))
    values, centre = [], None
    for ty in range(y0 // SIZE, y1 // SIZE + 1):
        for tx in range(x0 // SIZE, x1 // SIZE + 1):
            grid = tile_array((tx % (2 ** ZOOM), ty))
            gx0, gy0 = tx * SIZE, ty * SIZE
            ys = np.arange(max(y0, gy0), min(y1, gy0 + SIZE - 1) + 1)
            xs = np.arange(max(x0, gx0), min(x1, gx0 + SIZE - 1) + 1)
            if len(xs) == 0 or len(ys) == 0:
                continue
            yy, xx = np.meshgrid(ys, xs, indexing='ij')
            inside = (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2 <= r * r
            block = grid[yy - gy0, xx - gx0]
            values.append(block[inside])
            if gx0 <= x < gx0 + SIZE and gy0 <= y < gy0 + SIZE:
                centre = grid[int(y) - gy0, int(x) - gx0]
    heights = np.maximum(0, np.concatenate(values)) if values else np.zeros(1)
    elevation = max(0.0, float(centre)) if centre is not None else float(np.median(heights))
    return elevation, float(np.percentile(heights, 95) - np.percentile(heights, 5))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--places', type=Path, required=True, help='id, latitude, longitude per line (make_places.py --places)')
    parser.add_argument('--cache', type=Path, required=True, help='a folder to keep the downloaded tiles in')
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--workers', type=int, default=16)
    args = parser.parse_args()
    places = []
    for line in args.places.read_text(encoding='utf-8').splitlines():
        cols = line.split('\t')
        places.append((int(cols[0]), float(cols[1]), float(cols[2])))
    args.cache.mkdir(parents=True, exist_ok=True)
    needed = sorted({t for _, lat, lon in places for t in tiles_for(lat, lon)})
    print(f'{len(places)} places need {len(needed)} terrain tiles', flush=True)
    with ThreadPoolExecutor(args.workers) as pool:
        for i, _ in enumerate(pool.map(lambda t: fetch(t, args.cache), needed)):
            if i % 500 == 0:
                print(f'  {i}/{len(needed)} tiles', flush=True)
    loaded = {}

    def tile_array(tile):
        if tile not in loaded:
            if len(loaded) > 400:
                loaded.clear()
            loaded[tile] = decode(fetch(tile, args.cache))
        return loaded[tile]

    # Nearby places share tiles, so go through them tile by tile.
    rows = []
    for gid, lat, lon in sorted(places, key=lambda p: tuple(int(v // SIZE) for v in pixel(p[1], p[2]))):
        elevation, relief = sample(lat, lon, tile_array)
        rows.append((gid, elevation, relief))
    rows.sort()
    text = ''.join(f'{gid}\t{elevation:.0f}\t{relief:.0f}\n' for gid, elevation, relief in rows)
    args.output.write_bytes(gzip.compress(text.encode('utf-8'), mtime=0))
    print(f'Wrote {len(rows)} places to {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
