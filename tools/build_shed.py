#!/usr/bin/env python3
"""Build the shed at the end of the Shed in the Desert (desertRun.lua's shed): a rusty corrugated iron shed, open at
the south end so a truck can drive in, with a few crates and drums of precursors inside. Writes
mod/earth_freight/art/shapes/earth_freight_shed/shed.dae and its main.materials.json. Pure Python, no Blender: the
whole shed is boxes. Run it again after changing a size here.

The shed's origin is the middle of its floor at ground level. x is east, y north and z up, metres. Its walls go
SKIRT metres into the ground, so it sits on a dune's slope without a gap under it.
"""
import json
import math
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'mod' / 'earth_freight' / 'art' / 'shapes' / 'earth_freight_shed'
SHAPE_DIR = '/art/shapes/earth_freight_shed/'

# Sizes, in metres.
WIDTH, DEPTH, WALL, RIDGE, SKIRT = 12.0, 18.0, 5.0, 7.0, 1.5
SHEET = 0.08  # wall and roof sheets
RIB_GAP, RIB = 0.75, 0.05  # the corrugation: a rib this deep every RIB_GAP
POST = 0.25
OVERHANG = 0.6

MATERIALS = {
    'earth_freight_shed_iron': {'baseColorFactor': [0.42, 0.27, 0.17, 1], 'metallicFactor': 0.55, 'roughnessFactor': 0.8},
    'earth_freight_shed_roof': {'baseColorFactor': [0.5, 0.49, 0.46, 1], 'metallicFactor': 0.7, 'roughnessFactor': 0.6},
    'earth_freight_shed_frame': {'baseColorFactor': [0.16, 0.15, 0.14, 1], 'metallicFactor': 0.6, 'roughnessFactor': 0.55},
    'earth_freight_shed_crate': {'baseColorFactor': [0.55, 0.42, 0.26, 1], 'metallicFactor': 0.0, 'roughnessFactor': 0.9},
    'earth_freight_shed_drum': {'baseColorFactor': [0.62, 0.12, 0.08, 1], 'metallicFactor': 0.4, 'roughnessFactor': 0.6},
}

# Triangles by material: lists of (positions, normal) per triangle.
tris = {m: [] for m in MATERIALS}


def rotate_y(p, angle):
    c, s = math.cos(angle), math.sin(angle)
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


def box(mat, centre, size, tilt=0.0):
    """A box of size (x, y, z) at centre, tilted by tilt radians about the y axis."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    faces = [  # normal, four corners counter-clockwise seen from outside
        ((1, 0, 0), [(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)]),
        ((-1, 0, 0), [(-hx, hy, -hz), (-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz)]),
        ((0, 1, 0), [(hx, hy, -hz), (-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz)]),
        ((0, -1, 0), [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]),
        ((0, 0, 1), [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, 0, -1), [(-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz), (-hx, -hy, -hz)]),
    ]
    for normal, corners in faces:
        n = rotate_y(normal, tilt)
        pts = [tuple(a + b for a, b in zip(rotate_y(c, tilt), centre)) for c in corners]
        tris[mat].append(((pts[0], pts[1], pts[2]), n))
        tris[mat].append(((pts[0], pts[2], pts[3]), n))


def drum(centre, radius=0.3, height=0.9, segs=12):
    x0, y0, z0 = centre
    ring = [(x0 + radius * math.cos(2 * math.pi * k / segs), y0 + radius * math.sin(2 * math.pi * k / segs))
            for k in range(segs)]
    for k in range(segs):
        (ax, ay), (bx, by) = ring[k], ring[(k + 1) % segs]
        mid = 2 * math.pi * (k + 0.5) / segs
        n = (math.cos(mid), math.sin(mid), 0)
        tris['earth_freight_shed_drum'].append((((ax, ay, z0), (bx, by, z0), (bx, by, z0 + height)), n))
        tris['earth_freight_shed_drum'].append((((ax, ay, z0), (bx, by, z0 + height), (ax, ay, z0 + height)), n))
        tris['earth_freight_shed_drum'].append((((x0, y0, z0 + height), (ax, ay, z0 + height), (bx, by, z0 + height)), (0, 0, 1)))


def roof_height(x):
    return WALL + (RIDGE - WALL) * (1 - abs(x) / (WIDTH / 2))


def build():
    hw, hd = WIDTH / 2, DEPTH / 2
    low = -SKIRT
    # The side walls (east and west) and the back wall (north), each with its ribs outside.
    for side in (-1, 1):
        box('earth_freight_shed_iron', (side * hw, 0, (low + WALL) / 2), (SHEET, DEPTH, WALL - low))
        y = -hd + RIB_GAP / 2
        while y < hd:
            box('earth_freight_shed_iron', (side * (hw + SHEET / 2 + RIB / 2), y, (low + WALL) / 2),
                (RIB, 0.12, WALL - low))
            y += RIB_GAP
    box('earth_freight_shed_iron', (0, hd, (low + WALL) / 2), (WIDTH, SHEET, WALL - low))
    x = -hw + RIB_GAP / 2
    while x < hw:
        box('earth_freight_shed_iron', (x, hd + SHEET / 2 + RIB / 2, (low + WALL) / 2), (0.12, RIB, WALL - low))
        x += RIB_GAP
    # The gables at both ends, as steps of sheet under the roof's slope.
    steps = 12
    for k in range(steps):
        x0 = -hw + WIDTH * k / steps
        x1 = -hw + WIDTH * (k + 1) / steps
        top = min(roof_height(x0), roof_height(x1))
        box('earth_freight_shed_iron', ((x0 + x1) / 2, hd, (WALL + top) / 2), (x1 - x0, SHEET, top - WALL + 0.02))
        box('earth_freight_shed_iron', ((x0 + x1) / 2, -hd, (WALL + top) / 2), (x1 - x0, SHEET, top - WALL + 0.02))
    # The roof: two sloping sheets, with ribs running down them, and the ridge cap.
    half = hw + OVERHANG
    slope = math.atan2(RIDGE - WALL, hw)
    length = half / math.cos(slope)
    for side in (-1, 1):
        tilt = side * slope
        nx, nz = math.sin(tilt), math.cos(tilt)  # the sheet's outward normal
        cx = side * half / 2 + nx * SHEET / 2
        cz = RIDGE - (RIDGE - WALL) * (half / 2) / hw + nz * SHEET / 2
        box('earth_freight_shed_roof', (cx, 0, cz), (length, DEPTH + 2 * OVERHANG, SHEET), tilt)
        lift = SHEET / 2 + RIB / 2
        y = -hd - OVERHANG + RIB_GAP / 2
        while y < hd + OVERHANG:
            box('earth_freight_shed_roof', (cx + nx * lift, y, cz + nz * lift), (length, 0.12, RIB), tilt)
            y += RIB_GAP
    box('earth_freight_shed_roof', (0, 0, RIDGE + SHEET + 0.05), (0.5, DEPTH + 2 * OVERHANG, 0.1))
    # The frame: posts at the corners and along the open front, and a lintel over the opening.
    for x in (-hw, hw):
        for y in (-hd, 0, hd):
            box('earth_freight_shed_frame', (x, y, (low + WALL) / 2), (POST, POST, WALL - low))
    box('earth_freight_shed_frame', (0, -hd, WALL - 0.2), (WIDTH, POST, 0.4))
    box('earth_freight_shed_frame', (0, hd, WALL - 0.2), (WIDTH, POST, 0.4))
    # Inside, against the back wall: crates of precursors and red drums.
    for x, y, s in ((-4.2, hd - 1.2, 1.4), (-2.6, hd - 1.1, 1.2), (-3.4, hd - 1.2, 1.0), (4.0, hd - 1.3, 1.3)):
        z = 0 if (x, y) != (-3.4, hd - 1.2) else 1.4
        box('earth_freight_shed_crate', (x, y, z + s / 2), (s, s, s))
    for x, y in ((1.4, hd - 0.8), (2.1, hd - 0.8), (1.75, hd - 1.45), (5.0, hd - 3.0)):
        drum((x, y, 0))


def fmt(values):
    return ' '.join('%.5g' % v for v in values)


def write_dae(path):
    geoms, nodes = [], []
    for mat, faces in tris.items():
        if not faces:
            continue
        name = mat.replace('earth_freight_shed_', 'shed_')
        pos, normals, idx = [], [], []
        for k, (pts, n) in enumerate(faces):
            normals += list(n)
            for p in pts:
                idx += [len(pos) // 3, k]
                pos += list(p)

        def source(sid, data):
            return (f'<source id="{name}-{sid}"><float_array id="{name}-{sid}-array" count="{len(data)}">'
                    f'{fmt(data)}</float_array><technique_common><accessor source="#{name}-{sid}-array" '
                    f'count="{len(data) // 3}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/>'
                    '<param name="Z" type="float"/></accessor></technique_common></source>')
        geoms.append(
            f'<geometry id="{name}-mesh" name="{name}"><mesh>' + source('positions', pos) + source('normals', normals)
            + f'<vertices id="{name}-verts"><input semantic="POSITION" source="#{name}-positions"/></vertices>'
            + f'<triangles material="{mat}" count="{len(faces)}">'
            + f'<input semantic="VERTEX" source="#{name}-verts" offset="0"/>'
            + f'<input semantic="NORMAL" source="#{name}-normals" offset="1"/>'
            + f'<p>{" ".join(map(str, idx))}</p></triangles></mesh></geometry>')
        nodes.append(f'<node id="{name}" name="{name}" type="NODE"><instance_geometry url="#{name}-mesh" name="{name}">'
                     f'<bind_material><technique_common><instance_material symbol="{mat}" target="#{mat}"/>'
                     '</technique_common></bind_material></instance_geometry></node>')
    used = [m for m in MATERIALS if tris[m]]
    effects = ''.join(f'<effect id="{m}-effect"><profile_COMMON><technique sid="common"><lambert><diffuse>'
                      f'<color sid="diffuse">0.8 0.8 0.8 1</color></diffuse></lambert></technique></profile_COMMON></effect>'
                      for m in used)
    materials = ''.join(f'<material id="{m}" name="{m}"><instance_effect url="#{m}-effect"/></material>' for m in used)
    path.write_text('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">'
                    '<asset><contributor><authoring_tool>build_shed.py</authoring_tool></contributor>'
                    '<unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>'
                    f'<library_effects>{effects}</library_effects><library_materials>{materials}</library_materials>'
                    f'<library_geometries>{"".join(geoms)}</library_geometries>'
                    '<library_visual_scenes><visual_scene id="Scene" name="Scene">'
                    f'{"".join(nodes)}</visual_scene></library_visual_scenes>'
                    '<scene><instance_visual_scene url="#Scene"/></scene></COLLADA>\n')


def write_materials(path):
    out = {name: {'name': name, 'mapTo': name, 'class': 'Material', 'version': 1.5,
                  'Stages': [stage, {}, {}, {}], 'activeLayers': 1} for name, stage in MATERIALS.items()}
    path.write_text(json.dumps(out, indent=2) + '\n')


def main():
    build()
    OUT.mkdir(parents=True, exist_ok=True)
    write_dae(OUT / 'shed.dae')
    write_materials(OUT / 'main.materials.json')
    print(OUT / 'shed.dae', sum(len(f) for f in tris.values()), 'triangles')


if __name__ == '__main__':
    main()
