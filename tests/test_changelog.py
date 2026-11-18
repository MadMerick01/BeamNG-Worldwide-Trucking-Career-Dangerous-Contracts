"""Check CHANGELOG.md's shape and the release step that numbers its builds."""
import datetime
import unittest
from pathlib import Path

from tools import changelog

ROOT = Path(__file__).resolve().parents[1]
DATE = datetime.date(2026, 10, 25)

BASE = """# What's changed

Intro.

## Coming next

Waiting for a build.

{entries}
## Build 10 · 25 Oct 2026

- Old change.
"""


def make(*items):
    return BASE.format(entries=''.join(item + '\n' for item in items) + ('\n' if items else ''))


class ChangelogTest(unittest.TestCase):
    def test_real_changelog_has_coming_next_and_numbered_builds(self):
        text = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
        changelog.split(text)
        self.assertIn('## Build 1 · ', text)

    def test_release_moves_entries_into_a_numbered_build(self):
        text = make('- **Bigger trucks.**', '- Nested:\n  - detail')
        notes, updated = changelog.release(text, text, 11, DATE)
        latest, history = notes.split('\n<details>\n', 1)
        self.assertEqual(latest, '- **Bigger trucks.**\n- Nested:\n  - detail\n')
        self.assertEqual(history, '<summary>Earlier builds</summary>\n\n### Build 10 · 25 Oct 2026\n\n'
                                  '- Old change.\n\n</details>\n')
        self.assertEqual(changelog.entries(updated), [])
        self.assertIn('## Coming next\n\nWaiting for a build.\n\n## Build 11 · 25 Oct 2026\n\n'
                      '- **Bigger trucks.**\n- Nested:\n  - detail\n\n## Build 10', updated)

    def test_entries_merged_after_the_released_commit_wait_for_the_next_build(self):
        released = make('- A')
        current = make('- A', '- B')
        notes, updated = changelog.release(released, current, 11, DATE)
        self.assertTrue(notes.startswith('- A\n\n<details>'))
        self.assertEqual(changelog.entries(updated), ['- B'])
        self.assertIn('## Build 11 · 25 Oct 2026\n\n- A\n', updated)

    def test_entries_already_numbered_are_not_listed_again(self):
        released = make('- A', '- B')
        current = make('- B')
        notes, updated = changelog.release(released, current, 12, DATE)
        self.assertTrue(notes.startswith('- B\n\n<details>'))
        self.assertNotIn('\n- A\n', updated.split('## Build 10')[0])

    def test_nothing_listed_leaves_the_changelog_alone(self):
        text = make()
        notes, updated = changelog.release(text, text, 11, DATE)
        self.assertEqual(notes, changelog.NO_CHANGES + '\n')
        self.assertEqual(updated, text)

    def test_long_history_is_cut_to_fit_githubs_limit(self):
        tail = ''.join(f'## Build {n} · 1 Oct 2026\n\n- ' + 'x' * 500 + '\n\n' for n in range(400, 0, -1))
        history = changelog.earlier(tail, limit=5000)
        self.assertIn('### Build 400 ·', history)
        self.assertNotIn('### Build 1 ·', history)
        self.assertIn(changelog.MORE_IN_CHANGELOG, history)
        self.assertLess(len(history), 6000)

    def test_real_changelog_notes_fit_on_github(self):
        text = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
        notes = changelog.earlier(changelog.split(text)[3])
        self.assertLess(len(notes), 100_000)


if __name__ == '__main__':
    unittest.main()
