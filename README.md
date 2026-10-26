# Earth Freight Sim

A world freight economy career for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), the real-world map for BeamNG.drive. Start in a rust-bucket sedan, end in a semi truck

<img width="1800" height="1200" alt="image" src="https://github.com/user-attachments/assets/366238e0-c6bb-4482-8b03-6375b77c402b" />

The design is in [`docs/DESIGN.md`](docs/DESIGN.md). What is built so far: a job board in each of 130,000 towns worldwide, parcels, a pay bonus for rough roads, insurance, and shipping to anywhere on Earth.

## Install

Copy `earth-freight-sim.zip` into the `mods` folder of your BeamNG user folder. Do not extract it. If you have the older `earth_freight.zip` there, delete it first; your saves carry over. Every push to `main` builds a new ZIP on the [Releases](../../releases/latest) page. What changed in each build is listed in plain English in [`CHANGELOG.md`](CHANGELOG.md) and on its release page. Turn on the **Earth Freight Sim** UI app in the game's UI apps menu.

## Play

1. Load the BeamNG.Earth Freeroam level. A new game opens the start page: type your name and read the short how-to (the **Profile** button at the top of the HUD opens it again, and that is where you start a new game). The HUD shows Penrith's coordinates: copy them, paste them into the BeamNG.Earth map and teleport there. You get the starter car, a rusty Burnside, and $2,500. The car needs a radiator straight away, so fit one first in the parts menu.
2. Stop inside a town. The **Town** tab lists 3 to 5 jobs, each with one total pay for your car. Nothing to buy and no timers. The **Best job** line on the Route tab names the best one nearby.
3. Press **Take job**. It fills every cargo slot you have with that good, so a bigger box or vehicle earns more. BeamNG.Earth's GPS is set to the drop-off, so the route and road arrows appear on their own.
4. Drive there. The load's weight is added to the car, so it is slower and burns more fuel. Rough driving damages the car, which costs money to repair, and tyres can puncture (more often off road). The job itself always pays in full.
5. Stop inside the drop-off town and press **Deliver** to get paid. **Refuel** is on the Town tab too, at $2.10 a litre.
6. **Save** keeps your money, car, job and fuel. Anything since your last Save is lost when you exit.

**Goods.** Parts take 1 slot and weigh 15 kg each, food 2 slots and 50 kg, bricks 3 slots and 150 kg. On the starter Burnside (20 slots, 1,000 kg) a full load over 5 km pays about $1,700 of parts, $2,000 of food or $2,400 of bricks.

**Pay.** Longer jobs pay more per km: 10 km pays about 2.4 times a 5 km job, and 20 km six times (about $12,000 of food on the starter car). Jobs go at most 20 km. Each job pays up to 30% more or less than that, depending on how much the drop-off town wants the good: green on the board pays above the usual, red below. Every delivery makes that town want the good a little less for an hour or so, so the same run three times pays clearly less. Every board has at least one decent job.

**Sweet jobs.** Now and then a town runs short of a good and pays double for it until the end of the hour: a gold dot on the Nearby list and an alert on the Route tab. About one job in 20 is a jackpot paying two to three times. Rough roads pay up to twice as much (see below). The bonuses stack.

**Abandoning a job** costs $1,000 (or all your money, if you have less).

**Insurance.** After a serious crash the Garage tab offers **Claim insurance** for $1,000: the car is put back on the nearest road and fixed, but the job and its cargo are lost. Paying for the normal repair keeps the job.

**Cargo space.** A car with no cargo box carries 2 slots in the boot. Fit a "Cargo Load" box in the game's parts menu for more: the Garage tab bills it like any part (Box S 1 slot, M 4, L 16, XL 128). Repairs, parts and buying cars work as in Earth Enduro.

**Jobs must be driven.** A job only delivers at its drop-off, once you have driven 70% of the straight-line distance.

## The world

**Towns everywhere.** Every place in the world with over 1,000 people is in the game, thinned to about 4 km apart: 100,125 towns. They load as you drive, so the Nearby list and the Town tab work wherever you are.

**Region pay boost.** Steep, remote and high places pay more, from ×1 up to ×3. The boost comes from how much the ground rises and falls around a town, how few people live nearby, its altitude, and a bonus for famous roads (Death Road, the Stelvio Pass, the Karakoram Highway). Flat Sydney pays ×1.0, Katoomba in the Blue Mountains ×1.5, La Paz ×1.9 and Coroico on Death Road ×3.0. The HUD shows it next to the region name, like "Death Road ×3.0", and on each drop-off. Jobs get a rough-road bonus of half the boost above ×1, at the average of the two towns, so a job on Death Road pays ×2 and one in the Blue Mountains about ×1.25.

## Shipping

To go far, book shipping on the **Garage** tab with an empty car (no job on board):

- pick one of the listed regions (Penrith, Katoomba, La Paz, Coroico, Bormio, Zermatt, Gilgit, Leh),
- or **Find** any town by the start of its name (case and accents don't matter: "zurich" finds Zürich),
- or paste any **coordinates**, like `-16.19, -67.73`.

It costs $100 plus 2 cents a km (Sydney to Bolivia is about $360). You get the coordinates with a Copy button: paste them into the BeamNG.Earth map and teleport there. Landing within 5 km uses the booking up. **Cancel** refunds it. Save waits until you have used or cancelled it.

**Paid shipping offer.** A card at the top of the Garage tab names a town in one of the world's hardest regions (×2.3 to ×3.0, with another town to deliver to within 7 km) that will pay your shipping if you come and deliver there. A new town is offered every 5 minutes. You pay when you book, and your first delivery within 50 km of that town pays it back. The refund waits in your save, even after the card has moved on.

**Teleporting without a booking.** A teleport longer than 2 km cancels any job on board, for the $1,000 abandon fee. Deliveries, jobs and driving distance then stop until you go back to where you left from (the Route tab shows the coordinates), or book shipping and land there. A short hop under 2 km, past a cliff or river, is fine and keeps the job.

## Settings

`/settings/earthFreight/config.json` in your BeamNG user folder, optional (see `mod/earth_freight/config.example.json`):

- `base`: where a new game starts, instead of Penrith.
- `autoGps`: `false` stops the mod setting BeamNG.Earth's GPS when you take a job.

## Development

```
python -m pip install -r tests/requirements.txt
python tests/run.py                    # every Lua, HUD and packaging test
python tools/package.py                # builds dist/earth-freight-sim.zip
python tools/make_places.py            # rebuilds the worldwide place tiles from tools/data/
python tools/make_places.py --report   # prints the pay boost of some well-known places
python tools/sample_terrain.py --places PLACES --cache DIR   # re-samples elevation (see its --help)
python tools/check_earth_versions.py C:\path\to\BeamNG.Earth   # checks the adapter against Earth releases
```

Every pull request adds a line for players under **Coming next** in [`CHANGELOG.md`](CHANGELOG.md). The release workflow uses those lines as the release notes and moves them under the new build's number. See [`CLAUDE.md`](CLAUDE.md) for how to write them.

The mod's Lua is in `mod/earth_freight/lua/ge/extensions/earthFreight/`. `core.lua` ties it together; `workshop.lua` (garage bills), `earthAdapter.lua`, `persistence.lua`, `garage.lua`, `punctures.lua` and `pricing.lua` come from Earth Enduro. `docs/beamng-api/` is the BeamNG 0.39 API dump, searchable with `tools/api_lookup.py`.

## Credits

Place data © [GeoNames](https://www.geonames.org/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `tools/data/geonames_world.tsv.gz` is GeoNames' `cities1000` (every place over 1,000 people, from the June 2022 copy in the `all-the-cities` npm package); the Sydney extract in `tools/data/geonames_sydney.tsv` is cut from a newer `cities1000`. Elevation for the region pay boost: [Mapzen terrain tiles](https://registry.opendata.aws/terrain-tiles/) on AWS (SRTM, GMTED and other sources), sampled into `tools/data/terrain.tsv.gz` by `tools/sample_terrain.py`.
