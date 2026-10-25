# Notes for working on Earth Freight Sim

## Every PR adds a changelog entry

`CHANGELOG.md` is the one complete list of changes, written for players. Every pull request must add at least one entry to it, in the same PR.

- Add your entries as `- ` bullets under `## Coming next`, below the short intro line. Don't add a build number or date: when the PR merges, the release workflow (`.github/workflows/release.yml`, using `tools/changelog.py`) publishes the build, uses the waiting entries as its release notes and moves them under `## Build N · date`.
- Write for someone who plays the game and has never seen the code. Say what they will notice: what's new, what works differently, what got fixed. Use the names they see in game (tab names, button labels, prices in dollars), not file, function or setting names.
- Plain English, full sentences, no jargon. Bold the opening words of the most important change.
- If a PR changes nothing in the game (docs, tests, tools), say so in one line, for example "No changes in the game. The README now explains shipping."
- Mention anything the player must do, such as deleting an old ZIP, and say whether their saves still work.
- Never edit the numbered build sections by hand, except to fix a mistake.
- If two PRs both add to `## Coming next`, a merge conflict there is expected. Keep both sets of entries.
