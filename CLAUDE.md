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

## Every change to how the game works updates the help page

The HUD's help page (the **?** at the top of the HUD) reads all its text from
`mod/earth_freight/ui/modules/apps/TruckingCareerDC/help.txt`. A pull request that changes how something works,
adds a feature or changes what a player sees must update that file in the same PR, like the changelog.

- Keep each point short and in plain English, written for players, like the changelog.
- Don't type in prices or numbers the game sets: use a `{name}` from `rulesView` in `core.lua`, and add one there if
  it's missing.
- Keep the section ids: the small **?** buttons on the HUD open sections by id. Mark online-only sections `| online`.
- The **Getting started** points are also the start page's How to play steps, and `FALLBACK_STEPS` in `app.js` is a
  copy of them (a test checks they match).
- When a tab's long explanation would make the HUD taller, put it in `help.txt` and give the tab a small **?** instead.

## The author's name

The author is **MadMerick** everywhere in this repo and anything posted online: docs, changelog, code comments, commit messages and pull requests. Never use any other name for them.
