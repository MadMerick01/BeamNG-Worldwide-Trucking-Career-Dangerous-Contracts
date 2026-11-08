#!/usr/bin/env python3
"""Build a deterministic, standalone mod archive with no user settings or saves."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def build(output: Path) -> Path:
    root = Path(__file__).resolve().parents[1]
    source = root / 'mod' / 'earth_freight'
    entries = {}
    for path in sorted(source.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink not permitted in mod package: {path}')
        if path.is_file():
            entries[path.relative_to(source).as_posix()] = path.read_bytes()
    entries['docs/DESIGN.md'] = (root / 'docs' / 'DESIGN.md').read_bytes()
    entries['README.md'] = (root / 'README.md').read_bytes()
    entries['CHANGELOG.md'] = (root / 'CHANGELOG.md').read_bytes()
    entries['LICENSE'] = (root / 'LICENSE').read_bytes()
    output = output.resolve()
    if output.is_relative_to(source):
        raise ValueError('Write the archive outside the mod source folder.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, 'w', compression=ZIP_DEFLATED) as archive:
        for name, content in sorted(entries.items()):
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    return output


def build_server(output: Path, mod_zip: Path) -> Path:
    """The BeamMP server download: unzipped into a BeamMP server's folder, it adds the trucking server plugin and
    the mod that BeamMP sends to every player who joins."""
    root = Path(__file__).resolve().parents[1]
    entries = {
        'Resources/Server/WorldwideTrucking/main.lua': (root / 'server' / 'WorldwideTrucking' / 'main.lua').read_bytes(),
        'Resources/Client/worldwide-trucking-dangerous-contracts.zip': mod_zip.read_bytes(),
        'MULTIPLAYER-SETUP.md': (root / 'docs' / 'MULTIPLAYER-SETUP.md').read_bytes(),
    }
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, 'w', compression=ZIP_DEFLATED) as archive:
        for name, content in sorted(entries.items()):
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'dist' / 'worldwide-trucking-dangerous-contracts.zip')
    parser.add_argument('--server-output', type=Path,
                        help='also build the BeamMP server download here, holding the mod built to --output')
    args = parser.parse_args()
    mod = build(args.output)
    print(mod)
    if args.server_output:
        print(build_server(args.server_output, mod))
