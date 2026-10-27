# Earth Freight Sim

**Haul cargo anywhere on the real planet. Start in a rust bucket. Finish in a semi.**

A freight career for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), the real-world map for BeamNG.drive.

<img width="1350" height="900" alt="earthFSim1" src="https://github.com/user-attachments/assets/cba471f1-b4f9-4097-b502-20e35c1105d6" />

## What you get

- **100,000+ real towns, each with a job board.** Parts, bricks, water and fuel, wherever you are on Earth.
- **Off-road drops.** No GPS, no road. Just an arrow, a spot out in the hills and whatever it takes to get there.
- **Dangerous contracts.** Death Road, Carhuaz, Zoji La, Sani Pass and Grimsel Pass, for up to **8x the pay**. Each one can be beaten once per game.
- **A living economy.** Towns want different goods, repeat runs pay less, shortages pay double and the odd jackpot pays up to triple.
- **The world bites back.** Steep, remote and famous roads pay up to 3x. Cargo weighs the car down, fluids slosh in the tank, tyres puncture and crashes cost money.
- **Build your rig.** Buy parts, bolt on bigger cargo boxes and tanks, or buy a whole new vehicle. Every upgrade means bigger loads and bigger pay.
- **Relocate.** Pay to move to any town or coordinates on Earth. Some of the world's hardest regions will pay your way if you come and deliver.

## Install

1. Download `earth-freight-sim.zip` from the [latest release](../../releases/latest).
2. Drop it, **still zipped**, into the `mods` folder of your BeamNG user folder. If an older `earth_freight.zip` is there, delete it. Your saves carry over.
3. In game, turn on the **Earth Freight Sim** UI app.

## Get going

1. Load the BeamNG.Earth Freeroam level, type your name and press **Teleport to Penrith**. You start with a rusty Burnside and $2,500.
2. Fit a radiator first: **Buy parts** on the Garage tab. The starter car needs one.
3. Stop in any town, open the **Town** tab, pick a job and press **Take job**. The GPS is set for you.
4. Drive it there in one piece and press **Deliver**.
5. Press **Save** often. Next time, **Teleport to last save** puts you right back.

**Good to know:** insurance after a big crash costs $1,000 (the load is lost), abandoning a job costs $1,000, and the Insert key won't fix your car for free. Press the **–** at the top of the HUD to tuck it away while you drive.

## What's new

Every change, in plain English: [CHANGELOG.md](CHANGELOG.md). Each build is also on the [Releases](../../releases/latest) page.

---

<details>
<summary>Settings, development and credits</summary>

### Settings

Optional: `/settings/earthFreight/config.json` in your BeamNG user folder (see `mod/earth_freight/config.example.json`).

- `base`: where a new game starts, instead of Penrith.
- `autoGps`: `false` stops the mod setting BeamNG.Earth's GPS when you take a job.

### Development

```
python -m pip install -r tests/requirements.txt
python tests/run.py                    # every Lua, HUD and packaging test
python tools/package.py                # builds dist/earth-freight-sim.zip
python tools/make_places.py            # rebuilds the worldwide place tiles from tools/data/
python tools/make_places.py --report   # prints the pay boost of some well-known places
python tools/sample_terrain.py --places PLACES --cache DIR   # re-samples elevation (see its --help)
python tools/check_earth_versions.py C:\path\to\BeamNG.Earth   # checks the adapter against Earth releases
```

Every pull request adds a line for players under **Coming next** in [`CHANGELOG.md`](CHANGELOG.md); see [`CLAUDE.md`](CLAUDE.md). The design is in [`docs/DESIGN.md`](docs/DESIGN.md). The mod's Lua is in `mod/earth_freight/lua/ge/extensions/earthFreight/`, with `core.lua` tying it together. `docs/beamng-api/` is the BeamNG 0.39 API dump, searchable with `tools/api_lookup.py`.

### Credits

Place data © [GeoNames](https://www.geonames.org/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (`cities1000`, every place over 1,000 people). Elevation for the region pay boost: [Mapzen terrain tiles](https://registry.opendata.aws/terrain-tiles/) on AWS (SRTM, GMTED and other sources).

</details>
