"""The multiplayer server's overview page (site/), published to GitHub Pages."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / 'site'


class SiteTest(unittest.TestCase):
    def setUp(self):
        self.html = (SITE / 'index.html').read_text(encoding='utf-8')
        self.stats = json.loads((SITE / 'status.json').read_text(encoding='utf-8'))

    def test_sample_stats_are_marked_and_complete(self):
        s = self.stats
        self.assertEqual(s['version'], 1)
        self.assertIs(s['sample'], True, 'the bundled stats must say they are sample data')
        for key in ('updated', 'server', 'season', 'today', 'ship', 'players', 'feed', 'leaderboard'):
            self.assertIn(key, s)
        for p in s['players']:
            self.assertIn('town', p, 'players are shown by town')
        for key in ('port', 'latitude', 'longitude', 'containers', 'left', 'sailsAt'):
            self.assertIn(key, s['ship'])

    def test_page_reads_every_field_it_needs(self):
        for field in ('players', 'feed', 'leaderboard', 'sailsAt', 'containers', 'deliveries', 'earned', 'truckers'):
            self.assertIn(field, self.html)
        self.assertIn('trucking-server-stats/main/status.json', self.html, 'live stats come from the stats repo')
        self.assertIn("'status.json'", self.html, 'with the sample as the fallback')

    def test_player_text_is_never_put_in_as_html(self):
        script = self.html[self.html.rindex('<script>'):]
        self.assertNotIn('innerHTML', script)
        self.assertNotIn('insertAdjacentHTML', script)

    def test_outside_scripts_are_pinned(self):
        for src in re.findall(r'<script src="([^"]+)"', self.html):
            self.assertRegex(src, r'^https://unpkg\.com/[a-z-]+@\d+\.\d+\.\d+/')

    def test_pages_workflow_publishes_the_site(self):
        workflow = (ROOT / '.github' / 'workflows' / 'pages.yml').read_text(encoding='utf-8')
        self.assertIn('path: site', workflow)
        self.assertIn('actions/deploy-pages', workflow)


if __name__ == '__main__':
    unittest.main()
