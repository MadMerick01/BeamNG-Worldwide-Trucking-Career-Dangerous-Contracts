#!/usr/bin/env python3
"""Build the mod's worldwide place list from GeoNames: thin it to well-known towns about 4 km
apart, score each one's region pay boost, and write it as region tiles the mod loads near the
player. Built offline, never in game.

    python tools/make_places.py                  # rebuild the tiles from the bundled extracts
    python tools/make_places.py --check          # fail if the tiles are out of date
    python tools/make_places.py --report         # print the boost of some well-known places
    python tools/make_places.py --world cities1000.txt

The inputs are in GeoNames' tab-separated dump format, plain or gzipped:
- tools/data/geonames_world.tsv.gz: every place over 1,000 people, cut from cities1000.
- tools/data/geonames_sydney.tsv: the Sydney region cut from a newer cities1000; inside
  REGION_RADIUS_KM of Penrith it replaces the world rows, and place_overrides.json applies there.
- tools/data/terrain.tsv.gz: each place's elevation and relief, sampled by tools/sample_terrain.py.
- tools/data/regions.json: hand-named areas and famous roads; tools/data/countries.tsv: names.
Place data (c) GeoNames, CC BY 4.0. Elevation: Mapzen terrain tiles (SRTM and others).
"""
import argparse
import gzip
import json
import math
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'tools' / 'data'
WORLD = DATA / 'geonames_world.tsv.gz'
SYDNEY = DATA / 'geonames_sydney.tsv'
OVERRIDES = DATA / 'place_overrides.json'
TERRAIN = DATA / 'terrain.tsv.gz'
REGIONS = DATA / 'regions.json'
COUNTRIES = DATA / 'countries.tsv'
EXTENSIONS = ROOT / 'mod' / 'earth_freight' / 'lua' / 'ge' / 'extensions' / 'earthFreight'
INDEX = EXTENSIONS / 'placesIndex.lua'
TILES = EXTENSIONS / 'tiles'
PENRITH = (-33.75, 150.7)
REGION_RADIUS_KM = 150
SPACING_KM = 4
# Tiles are TILE_DEGREES square; the mod loads the one you are in and the eight around it.
TILE_DEGREES = 5
EARTH_RADIUS = 6371008.8
# Suburbs (GeoNames PPLX, a section of a populated place) rank below real towns of the same size,
# so the thinned list keeps Penrith and Katoomba ahead of the suburbs between them.
SUBURB_WEIGHT = 0.2
# Size classes by population; a place's size sets its arrival circle and its prices.
CITY_POPULATION, TOWN_POPULATION = 50000, 5000

# The region pay boost, from 1x to MAX_BOOST. Tune with --report: flat Sydney about 1x, the Blue
# Mountains about 1.5x, Death Road near 3x.
MAX_BOOST = 3.0
# Steepness, the biggest part: the rise and fall of the ground within RELIEF_RADIUS_KM (see
# sample_terrain.py), from nothing at RELIEF_FLAT_M up to STEEP_BOOST at RELIEF_STEEP_M.
RELIEF_FLAT_M, RELIEF_STEEP_M, STEEP_BOOST = 200, 2000, 1.6
# Remoteness: the people living within REMOTE_RADIUS_KM, from nothing at a big city's
# REMOTE_BUSY people down to the full REMOTE_BOOST at REMOTE_EMPTY people.
REMOTE_RADIUS_KM, REMOTE_BUSY, REMOTE_EMPTY, REMOTE_BOOST = 50, 1000000, 5000, 0.4
# Altitude: thin air and snow above ALTITUDE_LOW_M, up to ALTITUDE_BOOST at ALTITUDE_HIGH_M.
ALTITUDE_LOW_M, ALTITUDE_HIGH_M, ALTITUDE_BOOST = 2000, 4500, 0.3


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(min(1, math.sqrt(h)))


def text_of(path):
    raw = path.read_bytes()
    return (gzip.decompress(raw) if path.suffix == '.gz' else raw).decode('utf-8')


def read(path):
    places = []
    for line in text_of(path).splitlines():
        cols = line.split('\t')
        if len(cols) < 15 or cols[6] != 'P':
            continue
        places.append({
            'geonameid': int(cols[0]), 'name': cols[1], 'lat': float(cols[4]), 'lon': float(cols[5]),
            'code': cols[7], 'country': cols[8], 'population': int(cols[14] or 0),
        })
    return places


class Grid:
    """Points bucketed in cubes of the given size on the unit sphere's 3D coordinates, so
    neighbours within that distance are in the 27 cubes around a point, at any latitude."""

    def __init__(self, metres):
        self.cell, self.cells = metres / EARTH_RADIUS, {}

    def key(self, lat, lon):
        la, lo = math.radians(lat), math.radians(lon)
        x, y, z = math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)
        return int(math.floor(x / self.cell)), int(math.floor(y / self.cell)), int(math.floor(z / self.cell))

    def add(self, p):
        self.cells.setdefault(self.key(p['lat'], p['lon']), []).append(p)

    def near(self, lat, lon):
        kx, ky, kz = self.key(lat, lon)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    yield from self.cells.get((kx + dx, ky + dy, kz + dz), ())


def merge(world, sydney):
    """The world rows, with the Sydney extract in place of them inside the Sydney region."""
    inside = lambda p: distance(PENRITH, (p['lat'], p['lon'])) <= REGION_RADIUS_KM * 1000
    return [p for p in world if not inside(p)] + [dict(p, regional=True) for p in sydney if inside(p)]


def thin(places, overrides, spacing_km):
    """Keeps the best-known places at least spacing_km apart. The override names only apply to
    places from the Sydney extract, so Liverpool in England is not forced in."""
    include = set(overrides.get('include', []))
    exclude = set(overrides.get('exclude', []))
    named = lambda p, names: p.get('regional') and (p['name'] in names or str(p['geonameid']) in names)
    candidates = [p for p in places if not named(p, exclude)]

    def score(p):
        return (bool(named(p, include)), p['population'] * (SUBURB_WEIGHT if p['code'] == 'PPLX' else 1), -p['geonameid'])

    grid, kept = Grid(spacing_km * 1000), []
    for p in sorted(candidates, key=score, reverse=True):
        if all(distance((p['lat'], p['lon']), (k['lat'], k['lon'])) >= spacing_km * 1000 for k in grid.near(p['lat'], p['lon'])):
            grid.add(p)
            kept.append(p)
    missing = [n for n in include if not any(named(k, {n}) for k in kept)]
    if missing:
        raise SystemExit(f'Always-include places not kept (missing from the input or too close together): {missing}')
    return kept


def size(p):
    if p['population'] >= CITY_POPULATION:
        return 'city'
    return 'town' if p['population'] >= TOWN_POPULATION else 'village'


def ramp(value, low, high):
    return max(0.0, min(1.0, (value - low) / (high - low)))


def segment_distance(p, a, b):
    """Metres from p to the segment a-b, on a local flat projection (fine for roads a few km apart)."""
    k = math.cos(math.radians(p[0]))
    ax, ay, bx, by = (a[1] - p[1]) * k, a[0] - p[0], (b[1] - p[1]) * k, b[0] - p[0]
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
    return math.hypot(ax + t * dx, ay + t * dy) * math.pi / 180 * EARTH_RADIUS


def area_distance(p, area):
    pts = area['points']
    if len(pts) > 1:
        return min(segment_distance(p, pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    return min(distance(p, q) for q in pts)


def regions_of(p, areas):
    """The named areas a place is in: roads first, then the rest, nearest first."""
    found = []
    for area in areas:
        d = area_distance((p['lat'], p['lon']), area)
        if d <= area['radiusKm'] * 1000:
            found.append((area.get('kind') != 'road', d, area))
    return [a for _, _, a in sorted(found, key=lambda f: (f[0], f[1]))]


def score_boost(p, terrain, people, areas):
    """The place's pay boost and the parts it is made of."""
    elevation, relief = terrain.get(p['geonameid'], (0, 0))
    parts = {
        'steep': STEEP_BOOST * ramp(relief, RELIEF_FLAT_M, RELIEF_STEEP_M),
        'remote': REMOTE_BOOST * ramp(-math.log10(max(1, people)), -math.log10(REMOTE_BUSY), -math.log10(REMOTE_EMPTY)),
        'altitude': ALTITUDE_BOOST * ramp(elevation, ALTITUDE_LOW_M, ALTITUDE_HIGH_M),
        'road': max([a.get('bonus', 0) for a in regions_of(p, areas)] or [0]),
    }
    return min(MAX_BOOST, 1 + sum(parts.values())), parts, elevation, relief


def people_around(kept, everyone):
    """The people living within REMOTE_RADIUS_KM of each kept place, from the whole input."""
    grid = Grid(REMOTE_RADIUS_KM * 1000)
    for p in everyone:
        grid.add(p)
    out = {}
    for k in kept:
        out[k['geonameid']] = sum(q['population'] for q in grid.near(k['lat'], k['lon'])
                                  if distance((k['lat'], k['lon']), (q['lat'], q['lon'])) <= REMOTE_RADIUS_KM * 1000)
    return out


def read_terrain(path):
    terrain = {}
    if path.exists():
        for line in text_of(path).splitlines():
            cols = line.split('\t')
            if len(cols) >= 3 and cols[0].isdigit():
                terrain[int(cols[0])] = (float(cols[1]), float(cols[2]))
    return terrain


def tile_key(lat, lon):
    """The tile a point is in, named after its south-west corner, like s35e150."""
    south = math.floor(lat / TILE_DEGREES) * TILE_DEGREES
    west = math.floor(lon / TILE_DEGREES) * TILE_DEGREES
    south, west = max(-90, min(90 - TILE_DEGREES, south)), max(-180, min(180 - TILE_DEGREES, west))
    return f"{'s' if south < 0 else 'n'}{abs(south)}{'w' if west < 0 else 'e'}{abs(west)}"


def search_key(name):
    """A name as the shipping search matches it: lower case, accents and punctuation dropped,
    so typing zurich finds Zürich."""
    plain = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode('ascii').lower()
    return ' '.join(''.join(ch if ch.isalnum() else ' ' for ch in plain).split())


def lua_text(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def render(kept, terrain, people, areas, countries, source):
    """The tile files and the index, as {filename: text}."""
    tiles = {}
    for p in kept:
        boost, _, _, _ = score_boost(p, terrain, people[p['geonameid']], areas)
        named = regions_of(p, areas)
        region = named[0]['name'] if named else countries.get(p['country'], p['country'])
        tiles.setdefault(tile_key(p['lat'], p['lon']), []).append((p, int(round(boost * 10)), region))
    header = ('-- Generated by tools/make_places.py; do not edit by hand. Rebuild with: python tools/make_places.py\n'
              '-- Place data (c) GeoNames (https://www.geonames.org/), CC BY 4.0.\n')
    files = {}
    for key, rows in sorted(tiles.items()):
        regions = sorted({r for _, _, r in rows})
        index = {r: i + 1 for i, r in enumerate(regions)}
        lines = []
        for p, boost, region in sorted(rows, key=lambda r: (r[0]['name'], r[0]['geonameid'])):
            if '\t' in p['name'] or '\n' in p['name'] or ']==]' in p['name']:
                raise SystemExit(f'Place name cannot be written: {p["name"]!r}')
            lines.append(f"{p['geonameid']}\t{p['name']}\t{p['lat']:.4f}\t{p['lon']:.4f}\t{size(p)[0]}\t{boost}\t{index[region]}")
        files[f'tiles/{key}.lua'] = (header + '-- One place a line: GeoNames id, name, latitude, longitude, size (city, town or village), pay boost in tenths, region.\n'
                                     + 'return {\n  regions = { ' + ', '.join(lua_text(r) for r in regions) + ' },\n'
                                     + '  places = [==[\n' + '\n'.join(lines) + '\n]==],\n}\n')
    counts = ', '.join(f'{k} = {len(v)}' for k, v in sorted(tiles.items()))
    # The search list for shipping: every place's folded name (see search_key), id and tile, sorted
    # by name and then size, so a name's matches sit together with the biggest place first.
    keys = sorted(tiles)
    rank = {'city': 0, 'town': 1, 'village': 2}
    entries = sorted((search_key(p['name']), rank[size(p)], p['geonameid'], i + 1)
                     for i, key in enumerate(keys) for p, _, _ in tiles[key])
    files['placesNames.lua'] = (header
        + '-- One place a line, sorted: folded name, GeoNames id, tile (a number into tiles).\n'
        + 'return {\n  tiles = { ' + ', '.join(lua_text(k) for k in keys) + ' },\n'
        + '  names = [==[\n' + '\n'.join(f'{k}\t{gid}\t{t}' for k, _, gid, t in entries if k) + '\n]==],\n}\n')
    files['placesIndex.lua'] = (header
        + 'return {\n'
        + f'  source = {lua_text(source)}, spacingKm = {SPACING_KM}, tileDegrees = {TILE_DEGREES}, maxBoost = {MAX_BOOST},\n'
        + f'  -- The places in each tile; a tile not listed has none.\n'
        + f'  tiles = {{ {counts} }},\n'
        + '}\n')
    return files


def build_all(args):
    overrides = json.loads(args.overrides.read_text(encoding='utf-8')) if args.overrides.exists() else {}
    everyone = merge(read(args.world), read(args.sydney))
    kept = thin(everyone, overrides, SPACING_KM)
    terrain = read_terrain(args.terrain)
    people = people_around(kept, everyone)
    areas = json.loads(args.regions.read_text(encoding='utf-8'))['areas']
    countries = dict(line.split('\t', 1) for line in args.countries.read_text(encoding='utf-8').splitlines() if '\t' in line)
    source = f'{args.world.name} + {args.sydney.name}'
    return kept, terrain, people, areas, render(kept, terrain, people, areas, countries, source)


REPORT = ['Sydney', 'Parramatta', 'Penrith', 'Springwood', 'Katoomba', 'Blackheath', 'Lithgow', 'Oberon',
          'La Paz', 'Coroico', 'Yolosa', 'Caranavi', 'Bormio', 'Prato allo Stelvio', 'Gilgit', 'Karimabad',
          'Sost', 'Chilas', 'Alice Springs', 'Amsterdam', 'Leh', 'Zermatt']


def report(kept, terrain, people, areas):
    print(f'{"place":24} {"boost":>5}  steep remote alt  road   relief  elev   people')
    for name in REPORT:
        for p in [k for k in kept if k['name'] == name][:3]:
            boost, parts, elevation, relief = score_boost(p, terrain, people[p['geonameid']], areas)
            print(f'{name + " " + p["country"]:24} {boost:5.2f}  {parts["steep"]:.2f}  {parts["remote"]:.2f}   {parts["altitude"]:.2f}  '
                  f'{parts["road"]:.2f}  {relief:6.0f} {elevation:6.0f} {people[p["geonameid"]]:8d}')
    boosts = sorted(score_boost(p, terrain, people[p['geonameid']], areas)[0] for p in kept)
    print(f'{len(kept)} places; {len(terrain)} with terrain. Boost median {boosts[len(boosts) // 2]:.2f}, '
          f'90th {boosts[len(boosts) * 9 // 10]:.2f}, 99th {boosts[len(boosts) * 99 // 100]:.2f}, at the cap {sum(b >= MAX_BOOST for b in boosts)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--world', type=Path, default=WORLD)
    parser.add_argument('--sydney', type=Path, default=SYDNEY)
    parser.add_argument('--overrides', type=Path, default=OVERRIDES)
    parser.add_argument('--terrain', type=Path, default=TERRAIN)
    parser.add_argument('--regions', type=Path, default=REGIONS)
    parser.add_argument('--countries', type=Path, default=COUNTRIES)
    parser.add_argument('--output', type=Path, default=EXTENSIONS, help='the folder placesIndex.lua and tiles/ go in')
    parser.add_argument('--places', type=Path, help='also write the kept places (id, lat, lon) here, for sample_terrain.py')
    parser.add_argument('--check', action='store_true', help='fail if the output is out of date')
    parser.add_argument('--report', action='store_true', help='print the boost of some well-known places')
    args = parser.parse_args()
    kept, terrain, people, areas, files = build_all(args)
    if args.places:
        args.places.write_text(''.join(f"{p['geonameid']}\t{p['lat']:.5f}\t{p['lon']:.5f}\n" for p in kept), encoding='utf-8')
    if args.report:
        report(kept, terrain, people, areas)
        return 0
    old_tiles = {f'tiles/{p.name}' for p in (args.output / 'tiles').glob('*.lua')}
    if args.check:
        stale = [name for name, text in files.items()
                 if not (args.output / name).exists() or (args.output / name).read_text(encoding='utf-8') != text]
        stale += sorted(old_tiles - set(files))
        if stale:
            print(f'{len(stale)} place files are out of date, such as {stale[0]}. Run: python tools/make_places.py', file=sys.stderr)
            return 1
        print(f'Place tiles are up to date ({len(kept)} places in {len(files) - 2} tiles).')
        return 0
    (args.output / 'tiles').mkdir(parents=True, exist_ok=True)
    for name in old_tiles - set(files):
        (args.output / name).unlink()
    for name, text in files.items():
        (args.output / name).write_text(text, encoding='utf-8', newline='\n')
    total = sum(len(t.encode('utf-8')) for t in files.values())
    print(f'Wrote {len(kept)} places in {len(files) - 2} tiles ({total / 1e6:.1f} MB) to {args.output}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
