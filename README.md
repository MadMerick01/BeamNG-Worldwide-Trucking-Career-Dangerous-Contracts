# BeamNG Worldwide Trucking Career: Dangerous Contracts

**Haul cargo anywhere on Earth. Start in a rust bucket with no radiator or front brakes**

A freight career for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), the real-world map for BeamNG.drive.

<img width="1650" height="1100" alt="wwtcDCtitle" src="https://github.com/user-attachments/assets/18fa1fa3-ff30-460b-a18f-791cb1303c4f" />

## What you need

- **BeamNG.drive 0.40.**
- **[BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth)**, installed and working. Follow its own install guide first. The mod's **Teleport** buttons use Earth's teleport, so keep Earth's companion app running too. Without it you can still paste coordinates into Earth's map yourself.
- Optional, for heli flights: the **[Revamped Bell 407](https://www.beamng.com/threads/revamped-bell-407-with-weapons.98195/)** mod by stefan750.

## Features

- **130,000+ real earth towns, each with a job board.** Move parts, bricks, water and fuel.
- **Garage - Build your Rig.** Upgrade parts, buy and sell **new** and **second hand** vehicles.
- **Off-road drops.** No GPS route: follow the arrow on the Route tab to a spot off the road.
- **Dangerous highly paid contracts.** Death Road, Carhuaz, Zoji La, Ravin de Piquet, Sani Pass and Grimsel, for up to **8x the pay**. Each one can be done once per game.
- **Dynamic economy.** Towns want different goods, repeat runs pay less, shortages pay double.
- **Steep, remote and notorious roads** pay up to 3x. Regions are graded for difficulty.
- **Relocate.** Pay to move to any town or coordinates on Earth. Some of the world's hardest regions will pay your way if you come and deliver their wares.
- **Fuel, punctures and breakdowns.** Refuel in towns, repair burst tyres, use **Tow to road** when you're stuck, or take a short term loan when money runs out.
- **Insurance** after a big crash costs $1,000 (the load is lost), abandoning a job costs $1,000, and the Insert key won't fix your car for free. Press the **–** at the top of the HUD to tuck it away while you drive.
- **Heli flights.** Hire a Bell 407 for $1,000 and search for **'dont ask questions'** jobs. Needs the [Revamped Bell 407](https://www.beamng.com/threads/revamped-bell-407-with-weapons.98195/) mod by stefan750.

## Install

1. Download `worldwide-trucking-dangerous-contracts.zip` from the [latest release](../../releases/latest).
2. Drop it, **still zipped**, into the `mods` folder of your BeamNG user folder. If an older `earth-freight-sim.zip` or `earth_freight.zip` is there, delete it so two copies don't load. Your saves carry over.
3. In game, turn on the **TruckingCareerDC** UI app.

## How to Start

1. Load the BeamNG.Earth Freeroam level and type your name. Open the BeamNG.Earth map, teleport anywhere on Earth, such as your home town, and press **Start here**. You start there with a rusty Burnside and $2,500.
2. Fit a radiator first: **Buy parts** on the Garage tab. The starter car needs one.
3. Stop in any town, open the **Town** tab, pick a job and press **Take job**. The GPS is set for you.
4. Drive it there in one piece and press **Deliver**.
5. Press **Save** often. Next time, **Teleport to last save** puts you right back.


## Updating

Download the new `worldwide-trucking-dangerous-contracts.zip`, delete the old one from your `mods` folder and drop the new one in. Your saves carry over unless the changelog says otherwise.

## Feedback and bugs

Found a bug or have an idea? Open an [issue on GitHub](../../issues). Say what you were doing, and if something broke, attach your `beamng.log` (in your BeamNG user folder).

## What's new

Every change, in plain English: [CHANGELOG.md](CHANGELOG.md). Each build is also on the [Releases](../../releases/latest) page.

Keep me awake behind the wheel! [buy me a coffee on Ko-fi](https://ko-fi.com/madmerick).
---

<details>
<summary>Settings, development and credits</summary>

### Settings

Optional: `/settings/earthFreight/config.json` in your BeamNG user folder (see `mod/earth_freight/config.example.json`).

- `base`: a fixed spot every new game starts at, instead of the one you choose with **Start here**.
- `autoGps`: `false` stops the mod setting BeamNG.Earth's GPS when you take a job.

### Development

```
python -m pip install -r tests/requirements.txt
python tests/run.py                    # every Lua, HUD and packaging test
python tools/package.py                # builds dist/worldwide-trucking-dangerous-contracts.zip
python tools/make_places.py            # rebuilds the worldwide place tiles from tools/data/
python tools/make_places.py --report   # prints the pay boost of some well-known places
python tools/sample_terrain.py --places PLACES --cache DIR   # re-samples elevation (see its --help)
python tools/check_earth_versions.py C:\path\to\BeamNG.Earth   # checks the adapter against Earth releases
```

Every pull request adds a line for players under **Coming next** in [`CHANGELOG.md`](CHANGELOG.md); see [`CLAUDE.md`](CLAUDE.md). The design is in [`docs/DESIGN.md`](docs/DESIGN.md). The mod's Lua is in `mod/earth_freight/lua/ge/extensions/earthFreight/`, with `core.lua` tying it together. `docs/beamng-api/` is the BeamNG 0.39 API dump, searchable with `tools/api_lookup.py`.

### Credits

[BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth) by TecnaGamer, the real-world map this career runs on. The [Revamped Bell 407](https://www.beamng.com/threads/revamped-bell-407-with-weapons.98195/) by stefan750 (based on DrowsySam's Bell 407), used for heli flights and not included in this mod.
Place data © [GeoNames](https://www.geonames.org/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (`cities500`, every place over 500 people). Elevation for the region pay boost: [Mapzen terrain tiles](https://registry.opendata.aws/terrain-tiles/) on AWS (SRTM, GMTED and other sources).

</details>
