# Earth Freight: Rust to Rig

A world freight economy mod for BeamNG.drive on [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth). Start in a rust-bucket sedan, end in a semi.

The design is in [`docs/DESIGN.md`](docs/DESIGN.md). This is the first playable layer: fixed prices, parcels only, around Sydney.

## Install

Copy `earth_freight.zip` into the `mods` folder of your BeamNG user folder. Do not extract it. Every push to `main` builds a new ZIP on the [Releases](../../releases/latest) page. Turn on the **Earth Freight** UI app in the game's UI apps menu.

## Play

1. Load the BeamNG.Earth Freeroam level. The HUD shows Penrith's coordinates: copy them, paste them into the BeamNG.Earth map and teleport there. You get the starter car, a rusty Burnside, and $2,500. The car needs a radiator straight away, so fit one first in the parts menu.
2. Stop inside Penrith. The **Town** tab lists the goods you can buy (parts, food, bricks) and the nearby drop-offs with what each pays. Green dots are cheap to buy, red ones pay well.
3. **Buy** fills your cargo space as far as your money goes and sets BeamNG.Earth's GPS to the drop-off, so the route and road arrows appear on their own.
4. Drive there. The load's weight is added to the car, so it is slower and burns more fuel. Rough driving damages the cargo and cuts the pay.
5. Stop inside the drop-off town and press **Deliver** to get paid. **Refuel** is on the Town tab too, at $2.10 a litre.
6. **Save** keeps your money, car, load and fuel.

A car with no cargo box carries 2 parcels in the boot. Fit a "Cargo Load" box in the game's parts menu for more: the Garage tab bills it like any part (Box S 1 slot, M 4, L 16, XL 128). Repairs, parts and buying cars work as in Earth Enduro.

Deliveries must be driven: a load only sells once you have driven 70% of the straight-line distance. A teleport longer than 2 km loses the load and its money; a short hop past a cliff or river keeps it.

## Settings

`/settings/earthFreight/config.json` in your BeamNG user folder, optional (see `mod/earth_freight/config.example.json`):

- `base`: where a new game starts, instead of Penrith.
- `autoGps`: `false` stops the mod setting BeamNG.Earth's GPS when you buy a load.

## Development

```
python -m pip install -r tests/requirements.txt
python tests/run.py                    # every Lua, HUD and packaging test
python tools/package.py                # builds dist/earth_freight.zip
python tools/make_places.py            # rebuilds the place list from tools/data/
python tools/check_earth_versions.py C:\path\to\BeamNG.Earth   # checks the adapter against Earth releases
```

The mod's Lua is in `mod/earth_freight/lua/ge/extensions/earthFreight/`. `core.lua` ties it together; `workshop.lua` (garage bills), `earthAdapter.lua`, `persistence.lua`, `garage.lua`, `punctures.lua` and `pricing.lua` come from Earth Enduro. `docs/beamng-api/` is the BeamNG 0.39 API dump, searchable with `tools/api_lookup.py`.

## Credits

Place data © [GeoNames](https://www.geonames.org/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The Sydney extract in `tools/data/geonames_sydney.tsv` is cut from GeoNames' `cities1000`.
