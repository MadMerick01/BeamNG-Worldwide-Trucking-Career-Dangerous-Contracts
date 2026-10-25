# Earth Freight Sim

A world freight economy for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), the real-world map for BeamNG.drive. Start in a rust-bucket sedan, end in a semi.

The design is in [`docs/DESIGN.md`](docs/DESIGN.md). What is built so far: parcels between 100,000 towns worldwide, fixed prices, a region pay boost for hard places, and shipping to anywhere on Earth.

## Install

Copy `earth-freight-sim.zip` into the `mods` folder of your BeamNG user folder. Do not extract it. If you have the older `earth_freight.zip` there, delete it first; your saves carry over. Every push to `main` builds a new ZIP on the [Releases](../../releases/latest) page. Turn on the **Earth Freight Sim** UI app in the game's UI apps menu.

## Play

1. Load the BeamNG.Earth Freeroam level. The HUD shows Penrith's coordinates: copy them, paste them into the BeamNG.Earth map and teleport there. You get the starter car, a rusty Burnside, and $2,500. The car needs a radiator straight away, so fit one first in the parts menu.
2. Stop inside a town. The **Town** tab lists the goods you can buy (parts, food, bricks). Green dots are cheap to buy, red ones pay well. The **Best run** line on the Route tab suggests a good first load.
3. Pick a good, then set **how far** you want to drive with the slider (5 to 50 km). The drop-offs closest to that distance are listed with what each pays and your profit.
4. Pick **how many** to buy with − / + (or 1, or Max to fill your space as far as your money goes), then press **Buy** next to a drop-off. BeamNG.Earth's GPS is set to it, so the route and road arrows appear on their own.
5. Drive there. The load's weight is added to the car, so it is slower and burns more fuel. Rough driving damages the cargo and cuts the pay, and tyres can puncture (more often off road).
6. Stop inside the drop-off town and press **Deliver** to get paid. **Refuel** is on the Town tab too, at $2.10 a litre.
7. **Save** keeps your money, car, load and fuel. Anything since your last Save is lost when you exit.

**Pay.** A delivery pays the drop-off's price for the goods plus freight pay: $20 a tonne for each road km, and the rate rises the longer the run, to twice that on a 50 km run.

**Cargo space.** A car with no cargo box carries 2 parcels in the boot. Fit a "Cargo Load" box in the game's parts menu for more: the Garage tab bills it like any part (Box S 1 slot, M 4, L 16, XL 128). Repairs, parts and buying cars work as in Earth Enduro.

**Deliveries must be driven.** A load only sells once you have driven 70% of the straight-line distance, and never where you bought it.

## The world

**Towns everywhere.** Every place in the world with over 1,000 people is in the game, thinned to about 4 km apart: 100,125 towns. They load as you drive, so the Nearby list and the Town tab work wherever you are.

**Region pay boost.** Steep, remote and high places pay more, from ×1 up to ×3. The boost comes from how much the ground rises and falls around a town, how few people live nearby, its altitude, and a bonus for famous roads (Death Road, the Stelvio Pass, the Karakoram Highway). Flat Sydney pays ×1.0, Katoomba in the Blue Mountains ×1.5, La Paz ×1.9 and Coroico on Death Road ×3.0. The HUD shows it next to the region name, like "Death Road ×3.0", and on each drop-off. It multiplies everything a town pays and charges, so runs in a hard region pay more, and a run up into one pays more again.

## Shipping

To go far, book shipping on the **Garage** tab with an empty car (no load on board):

- pick one of the listed regions (Penrith, Katoomba, La Paz, Coroico, Bormio, Zermatt, Gilgit, Leh),
- or **Find** any town by the start of its name (case and accents don't matter: "zurich" finds Zürich),
- or paste any **coordinates**, like `-16.19, -67.73`.

It costs $100 plus 2 cents a km (Sydney to Bolivia is about $360). You get the coordinates with a Copy button: paste them into the BeamNG.Earth map and teleport there. Landing within 5 km uses the booking up. **Cancel** refunds it. Save waits until you have used or cancelled it.

**Paid shipping offer.** A card at the top of the Garage tab names a town in one of the world's hardest regions (×2.7 to ×3.0) that will pay your shipping if you come and deliver there. A new town is offered every 5 minutes. You pay when you book, and your first delivery within 50 km of that town pays it back. The refund waits in your save, even after the card has moved on.

**Teleporting without a booking.** A teleport longer than 2 km loses any load on board and the money paid for it. Deliveries, trading and driving distance then stop until you go back to where you left from (the Route tab shows the coordinates), or book shipping and land there. A short hop under 2 km, past a cliff or river, is fine and keeps the load.

## Settings

`/settings/earthFreight/config.json` in your BeamNG user folder, optional (see `mod/earth_freight/config.example.json`):

- `base`: where a new game starts, instead of Penrith.
- `autoGps`: `false` stops the mod setting BeamNG.Earth's GPS when you buy a load.

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

The mod's Lua is in `mod/earth_freight/lua/ge/extensions/earthFreight/`. `core.lua` ties it together; `workshop.lua` (garage bills), `earthAdapter.lua`, `persistence.lua`, `garage.lua`, `punctures.lua` and `pricing.lua` come from Earth Enduro. `docs/beamng-api/` is the BeamNG 0.39 API dump, searchable with `tools/api_lookup.py`.

## Credits

Place data © [GeoNames](https://www.geonames.org/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `tools/data/geonames_world.tsv.gz` is GeoNames' `cities1000` (every place over 1,000 people, from the June 2022 copy in the `all-the-cities` npm package); the Sydney extract in `tools/data/geonames_sydney.tsv` is cut from a newer `cities1000`. Elevation for the region pay boost: [Mapzen terrain tiles](https://registry.opendata.aws/terrain-tiles/) on AWS (SRTM, GMTED and other sources), sampled into `tools/data/terrain.tsv.gz` by `tools/sample_terrain.py`.
