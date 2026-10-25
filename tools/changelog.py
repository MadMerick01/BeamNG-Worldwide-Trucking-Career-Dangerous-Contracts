#!/usr/bin/env python3
"""Turn CHANGELOG.md's "Coming next" entries into a numbered build.

The release workflow runs this after a push to main. It takes the entries that
were in "Coming next" in the released commit and are still there on main,
writes them as the release notes, and moves them under "## Build N · date".
Entries merged after the released commit stay in "Coming next" for the next
build.
"""
import argparse
import datetime
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / 'CHANGELOG.md'
NEXT_HEADING = '## Coming next'
NO_CHANGES = 'No changes were listed for this build.'


def split(text):
    """Return (head, intro, entries, tail) around the Coming next section.

    head ends with the Coming next heading line, intro is any text before the
    first bullet, entries are the top-level bullets (each with its indented
    continuation lines) and tail starts at the next "## " heading.
    """
    lines = text.splitlines(keepends=True)
    try:
        start = next(i for i, line in enumerate(lines) if line.rstrip() == NEXT_HEADING)
    except StopIteration:
        raise SystemExit(f'CHANGELOG.md has no "{NEXT_HEADING}" section')
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    intro, entries = [], []
    for line in lines[start + 1:end]:
        if line.startswith('- '):
            entries.append(line)
        elif entries and (line.startswith((' ', '\t')) and line.strip()):
            entries[-1] += line
        elif not entries:
            intro.append(line)
    return ''.join(lines[:start + 1]), ''.join(intro).strip(), [e.rstrip('\n') for e in entries], ''.join(lines[end:])


def entries(text):
    return split(text)[2]


def release(released, current, build, date):
    """Return (notes, new changelog). The changelog is unchanged when nothing is released."""
    waiting = entries(current)
    shipped = [e for e in entries(released) if e in waiting]
    if not shipped:
        return NO_CHANGES + '\n', current
    head, intro, _, tail = split(current)
    left = [e for e in waiting if e not in shipped]
    section = head + '\n'
    if intro:
        section += intro + '\n\n'
    if left:
        section += '\n'.join(left) + '\n\n'
    label = f'{date.day} {date:%b %Y}'
    section += f'## Build {build} · {label}\n\n' + '\n'.join(shipped) + '\n\n'
    return '\n'.join(shipped) + '\n', section + tail


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--build', type=int, required=True, help='build number, as in the release name')
    parser.add_argument('--date', type=datetime.date.fromisoformat, default=datetime.date.today(),
                        help='YYYY-MM-DD, default today')
    parser.add_argument('--released', type=Path, required=True,
                        help='CHANGELOG.md as it was in the released commit')
    parser.add_argument('--changelog', type=Path, default=CHANGELOG, help='CHANGELOG.md to update in place')
    parser.add_argument('--notes', type=Path, required=True, help='where to write the release notes')
    args = parser.parse_args(argv)
    notes, updated = release(args.released.read_text(encoding='utf-8'),
                             args.changelog.read_text(encoding='utf-8'), args.build, args.date)
    args.notes.write_text(notes, encoding='utf-8')
    args.changelog.write_text(updated, encoding='utf-8')
    print(notes, end='')
    return 0


if __name__ == '__main__':
    sys.exit(main())
