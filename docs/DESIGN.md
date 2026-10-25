# Earth Freight: Rust to Rig — Design

Status: **layer 1 built** (fixed prices, parcels, around Sydney; see [Layer 1 as built](#layer-1-as-built)). This doc collects the decisions made so far and marks what is still open. Open questions are tagged **❓ OPEN** inline and gathered in [Open questions](#open-questions) at the end.

## The pitch

A single-player freight economy across the whole real world, played on [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth). You start with a rust-bucket sedan and a few dollars, run small parcels between nearby towns, and work your way up through a ute and a small truck to a semi hauling trailers through the world's most treacherous regions.

It sits alongside Earth Enduro (rally stages, CarKov) as a separate mod. It reuses Enduro's plumbing by copying it, and changes the game on top: Enduro is about reaching a finish line, Earth Freight is about choosing what to carry where for profit.

## Core loop

1. **Look.** The HUD shows the nearest 5–6 places, each with its goods as coloured dots and the road distance to it.
2. **Choose.** Pick a good that is cheap here (green) and short somewhere close (red) that your vehicle can carry.
3. **Load.** Buy it at the place you are at, up to your vehicle's capacity.
4. **Drive.** Usually 10–15 km by road. Rough driving damages the cargo and your car.
5. **Deliver.** Sell at the destination. Payout is the destination's price, reduced by any cargo damage.
6. **Spend.** Repairs, parts, and saving towards a bigger vehicle or a ticket to a better-paying region.

A run takes roughly 10–20 minutes of driving, which is the engagement target Rowan set.

## World: places

### Towns

Towns come from an **offline GeoNames list** (every place over 1,000 people, about 150,000 worldwide) bundled with the mod, built by a generator script in `tools/`. It is not read from BeamNG.Earth at runtime. Reasons, from the town-detection research:

- Earth's own town name (its status bar, via `require('beamngEarth/statusbar').location()`) comes from an online Photon lookup. It is online only, blank when "Place names" is off, lags up to ~1.5 km, and names the nearest village or county even out in the bush.
- Earth bundles only ~6,770 big towns (Katoomba is in, Penrith is not).
- A bundled list works offline, fires in the same place every time, and can be tested. Estimated size: 2–4 MB.

Earth's status bar name can still be shown on the HUD as flavour when it is available.

**Thinning.** Raw GeoNames is mostly suburbs (899 places within 150 km of Sydney). The generator keeps the best-known places and spaces them about **4 km apart**, which gives road runs from about 5 km. Around Penrith that is 223 places in a 150 km circle.

Known data problems to handle in the generator:

- Some well-known towns drop out because their GeoNames entries are thin (Penrith, Bowral, Kiama). Rank by importance instead of raw population, using Wikipedia or OpenStreetMap `place=town/city` tags, and keep a small **hand-edited override list** for towns that must be in or out.
- Some populations are wrong (Campbelltown shows ~13k against a real ~170k). Pay and demand should lean on the importance rank, not population.

GeoNames is CC BY 4.0, so the mod needs a credit line (README and the HUD's Tips/about screen).

### Rural pickup points

Out in the country towns alone are too far apart (Goulburn's nearest town is 27 km away). The gaps are filled with **rural pickup points**: farms, mines, quarries, brickworks, dams, grain silos and roadhouses, taken from GeoNames feature classes and OpenStreetMap. A rural point sells or buys only one or two goods and has no full board. It means there is a 10–15 km job from almost anywhere, and it feels right for the genre: grain from a farm to the town silo, gravel from a quarry to a building site.

### What each place makes and needs

There is no worldwide database of what towns produce, so the generator **guesses from real geography**, once, and stores the result as a small type tag per place (a place can have two, like `farm+port`). Nothing heavy runs in game.

| Signal | Source | Tag |
|---|---|---|
| Land cover around it: cropland, grassland, desert | ESA WorldCover | farm (cropland, grassland); dry (desert: needs water) |
| A mine, quarry or oil field within a few km | GeoNames / OSM | mining, quarry, fuel |
| A harbour, or on the coast | GeoNames / OSM, coastline | port |
| Big city | importance rank | city: makes parts and fuel, needs food and raw goods |
| Nothing stands out | seeded random pick fitting the region | fallback |

Each tag maps to goods it **supplies** and goods it **demands**. That gives trade both ways: raw goods flow into cities, fuel and parts flow back out to farms, mines and remote towns.

**❓ OPEN — Q1:** Is ESA WorldCover (10 m rasters, very large) practical to sample for 150k places in the generator, or is a coarser land-cover set (e.g. Copernicus 100 m, or MODIS) good enough? The CarKov land mask used Natural Earth at 0.1°; that is likely too coarse for "farm vs forest".

### Region

There is no hand-built region. Your region is simply the places around you, so it moves with you: drive far enough and you are among new towns. The HUD covers the nearest 5–6, and the planning map covers about 50 km.

**Decided (Q2): a new game starts in Penrith, NSW.** It sits on the edge of Sydney, so the first runs mix city and country driving, and the Blue Mountains next door give better-paying, more interesting hill deliveries early on. Penrith is one of the towns GeoNames thins out, so it goes on the generator's hand-edited "always include" list. A choice of start towns can come later.

## Goods and cargo sizes

Seven goods, few enough that the dots stay readable. Each maps onto one of BeamNG's built-in cargo types (see below), so the vanilla Cargo Load parts carry them. Livestock and timber were dropped because BeamNG has no cargo type for them; water and bricks replace them (decided, Q3).

| Good | BeamNG type | Feel | Typical flow |
|---|---|---|---|
| **Parts / machinery** | parcel | light, valuable | cities → farms and mines |
| **Food** | parcel | everyday, always wanted | farms → towns and cities |
| **Bricks** | parcel | very heavy per slot, so weight runs out before space | brickworks and quarries → towns and building sites |
| **Grain** | dry bulk | bulky | farms and silos → towns, cities and ports |
| **Gravel / ore** | dry bulk | very heavy | quarries and mines → cities |
| **Water** | fluid | heavy, sloshes | towns and dams → remote places, mines, dry farms |
| **Fuel** | fluid | dangerous, pays well | cities → remote places |

| Size | Carried by | Notes |
|---|---|---|
| **Parcels** | any car with a box; Cargo Load Box S/M holds 1–4 slots | low pay, always available (parts, food, a few bricks) |
| **Pallets** | ute or pickup with an L box (16 slots) or a small tank | where fuel and water start |
| **Bulk** | tray truck or bigger with an XL box (128 slots), aggregate box or fluid tank | grain, gravel, bricks by the pallet; where the money is |
| **Trailers** | semi | containers and tankers on the long, high-paying runs into dangerous regions |

A green bulk dot you can't carry yet is meant to be visible early on; it is what keeps you saving.

**❓ OPEN — Q4:** Vehicle capacity. BeamNG's own career mode puts cargo slots on vehicles for its delivery jobs. If we can read those outside career mode (Earth Freeroam does not load career modules, which is why Enduro's garage uses base-game calls only), each vehicle's capacity comes free and stays right when the car is modded. Otherwise we set capacity per vehicle class ourselves. Needs a check against the API dump (`docs/beamng-api/` in the Enduro repo) and in game.

**Decided (Q5): cargo is a number, but space comes from the cargo boxes on the vehicle, and weight matters.**

- A vehicle's cargo space is the number and size of the cargo boxes (or trays, racks, tanks) fitted to it. Fit more or bigger boxes in the garage and you can carry more. A bare car with no boxes still takes a couple of parcels in the boot.
- Every load also has a **weight**, and weight is a big part of the game: each vehicle has a payload limit, and a heavy load should make the vehicle slower, brake later and handle worse, so overloading a rust bucket is a real risk. Gravel and ore fill a vehicle's weight limit long before its space; parcels and parts fill space first.
- The load itself is still a number in the save, not objects in the tray, so it never falls through Earth's ground.

**What BeamNG has built in.** Since 0.31, vanilla vehicles can carry `cargoStorage` parts for career deliveries, sold in the parts menu as "Cargo Load …" (internal names contain `cargo_load_`). The `cargoStorage` jbeam section also says how stored cargo adds weight to the vehicle's nodes. Cargo types are `parcel`, `fluid`, `dryBulk` and `passenger`. Parcel capacity is counted in slots: Cargo Load Box S holds 1, M holds 4, L holds 16, XL holds 128, and 20 ft and 40 ft containers hold far more. Fluid and dry bulk are counted in litres (e.g. Fluid Tank XL and Aggregate Box XL, 800). From BeamNG's [Cargo Storage docs](https://documentation.beamng.com/modding/vehicle/sections/cargostorage/), via search; not yet checked against the 0.39 game files.

**❓ OPEN — Q5a:** How the load's weight reaches the physics. Options: change the vehicle's mass through a weight-adjusting part or jbeam variable, the way BeamNG's own career cargo does, or apply it as a game-side mass change. Needs a look at how career cargo adds mass, alongside Q4.

**❓ OPEN — Q5b:** Which parts count as cargo boxes and how much each holds. If BeamNG's career cargo slots (Q4) can be read, they answer this. Otherwise we keep our own table of box parts with their space and weight limit.

## Economy

### Prices are always visible

Hidden prices were considered and rejected: the distances are too large to make scouting fun. Every place's buy and sell prices show on the HUD and the map.

### Base prices, computed on the fly

A place's base price for each good comes from its type tags, its importance and a fixed seed. Nothing is stored for places you have never traded at. Big cities need a lot and pay less per load; small villages pay more but want small amounts.

### Supply and demand: a decaying offset

When you buy or sell at a place, the save records one small offset for that good there (for example "grain −30%"). The offset fades back towards zero as in-game time passes. A price you see is:

```
price = basePrice(place, good) × (1 + offset × decay(elapsed))
```

Nothing ticks in the background, and the save only holds places you have actually traded at. This stops one route being farmed forever without simulating the world.

The HUD's green and red dots come from the current price relative to the good's world baseline: green means stocked and cheap to buy, red means short and pays well to deliver.

**Decided (Q6):** the offset decays exponentially and **halves every 2 in-game hours**. Its size scales with the load: one delivery's offset is the load's size relative to how much the place wants, so a semi load can flood a village in one drop while a parcel barely moves a city's price.

### Fuel (decided, Q15)

Fuel costs money. BeamNG already simulates fuel use, so the mod reads the tank level and the player refuels at towns, paying per litre. Weight matters here too: a heavy load burns more fuel, so it is part of the cost of every run.

**Decided (Q15a):** a **Refuel** button on the HUD when stopped inside a town's arrival circle or at a roadhouse, paid per litre, filling the tank through the vehicle's fuel storage. (The exact vehicle-side fuel call still needs checking in game.)

### Pay modifiers

The generator scores every place once for how hard it is to get to:

- **Ruggedness:** how steep and broken the terrain is, from elevation data.
- **Remoteness:** distance to the nearest big city (long hauls with nowhere to repair).
- **Climate:** snow, desert or monsoon zones.
- **Danger:** not for now (Q16). CarKov-style hostiles could be added later.

Pay is a multiplier on that score. Norway's fjords, the Andes, the Australian outback and Himalayan passes pay several times more than flat European highways. Katoomba → Lithgow is a good local example of a climb that should pay more.

**Decided (Q7): the multiplier is capped at 3×.** Flat highways pay 1×, the Blue Mountains around 1.5×, the Andes or Himalayas near 3×. Any higher and nobody would deliver anywhere else.

**Decided (Q7a):** the free Mapzen terrain tiles on AWS (SRTM, with other sources where SRTM has none), at about 600 m a pixel. See [Region pay boost as built](#region-pay-boost-as-built).

### Cargo damage

Rough driving damages the cargo and cuts the payout. Damage costs more the more the load is worth, so careful driving pays. Fuel and parts are the most sensitive. A cheap pickup on a dirt road is a real trade-off.

### Living world (later)

Random events (a mine strike, a harvest boom, a flood closing a road) push prices around a region and appear as news on the board. Layer 3, see [Build plan](#build-plan).

## Progression: rust to rig

The same arc as Rust to Race Car, ending in a truck.

1. **Rust-bucket sedan.** Parcels only. It breaks down, punctures, and rough roads can cost you the load. Early game is earning enough to keep it going.
2. **Ute / pickup.** Pallets.
3. **Small (tray) truck.** Bulk.
4. **Semi.** Trailers and the best-paying long runs.

Vehicles are bought through the garage as in Enduro: a car's game Value sets its price, the old car is traded in, and repair prices scale with the car's Value.

**Decided (Q8): the semi tier stays.** BeamNG.Earth builds solid road out to at least 150 m around the car, which is plenty for a trailer. Which vanilla vehicles suit each tier is left to the player (Q9); the HUD tips can suggest some, such as a D-Series or Roamer for the ute stage and a Gavril T-Series for trucks.

**Decided (Q9): there is no forced ladder.** The player can buy any vanilla BeamNG vehicle they can afford. The sedan → ute → truck → semi tiers above describe the usual path, not a rule; money does the gating.

## Teleporting: book shipping (decided, Q10 and Q11)

The point of the game is to take your vehicle all over the world, so moving it should be **cheap**. What you cannot do is teleport with goods.

1. **Book shipping.** A small, minimal screen: pick a destination (a place from the list, or coordinates), see the price, pay. The price is low, scaling a little with distance and vehicle size. You can only book with an **empty** vehicle; sell or drop your load first.
2. **Teleport.** Once paid, the HUD gives the destination coordinates with a Copy button, to paste into the BeamNG.Earth map, as Enduro does. The mod never teleports the player itself.
3. **Arrive.** A jump that lands near the booked destination is accepted and the booking is used up.

**A teleport without a booking.** The mod detects the jump (Enduro treats movement faster than 150 m/s between two readings as a teleport). Any cargo on board is cancelled and the money paid for it is lost. A message tells the player where they left from, with the coordinates to return to, and no driving pay or deliveries count until they are back there (or book shipping from where they are).

**Short hops** under about 2 km, to get past a cliff or river, are free, need no booking and keep the cargo.

Every delivery still has to be driven: teleport-sized jumps never count as driving.

## HUD

A UI app in the same shell as Enduro's (one state payload at ≤4 Hz, tabs, an always-visible header).

**While driving (always in view):** money, the current load and its destination, distance to it, and cargo condition.

**Nearby list:** the nearest 5–6 places with:

- the place name and type icon,
- a coloured dot per good (green stocked, red short, grey not traded there),
- road distance.

One helper line suggests the best run for a new player, e.g. *"Best run: grain, Richmond → Katoomba, $$$"*.

**At a place (stopped):** what it sells and buys, at what price, how much your vehicle can take, and Buy / Sell.

**Planning map:** opened when stopped, showing the same dots for everything within about 50 km, so players can string together two- or three-leg routes without cluttering the HUD while driving.

**Arrival:** a place's "you've arrived" circle is sized from its importance (a city depot is bigger than a village store). Trading only works inside it and when stopped.

**Decided (Q12):** the nearby list shows **straight-line distance × 1.3, marked "≈"**, because Earth's road graph only covers the roads close to the car. The current delivery shows the true road distance from Earth's GPS route once it is set (see the planning map section).

### Planning map: our own screen, not Earth's (decided)

The planning map is **separate from BeamNG.Earth's map**: a panel in our own HUD app. Checked against BeamNG.Earth `main` (c6032e2, 2026-10-24):

- **BeamNG's big map is not available.** In Earth's level, Earth replaces it: the M key and the pause menu's Map open Earth's own world map instead (`settings.lua` `redirectBigMap` swaps out `freeroam_bigMapMode.toggleBigMap` / `enterBigMap`). The stock big map is a 3D overhead view of a stock level and would show nothing useful on Earth anyway.
- **Earth's map has no way for another mod to add markers.** `EarthMap.vue` draws only its own lists: the player's saved places (from `/settings/beamngEarth_places.json`), other BeamMP players, the GPS destination and the player. There is no marker or layer API. The only way in would be writing our towns into the player's saved places file, which would clutter their bookmarks and break the rule that we never write Earth's state. Patching Earth's Vue file is ruled out for the same reason and would break on every Earth update.
- **Earth's GPS is reachable, though.** `require('beamngEarth/gps').setDestination(lat, lon, name)` is a plain Lua function. It plans a road route on Earth's companion server (OSRM on OpenStreetMap), draws it on Earth's map, and puts the game's own route arrows on the road. So the player plans on our map, and once a load is bought we could set the delivery place as Earth's GPS destination, giving turn-by-turn arrows and a route on Earth's map for free.

**Decided (Q13, Rowan 2026-10-25): yes.** When a load is bought, the mod sets Earth's GPS destination to the delivery place, so the route and road arrows appear without the player doing anything. It is the one place we write to Earth, so the call is guarded like the adapter's reads: if `beamngEarth/gps` or `setDestination` is missing or changed, it is skipped quietly and the delivery still works from our HUD. It only fires on buying a load, never while driving, so a GPS destination the player sets afterwards is left alone. A setting can turn it off.

## Anti-cheat

Money rides on distance and destination, so this matters more than in Enduro:

- **Teleport detection** (copied from Enduro): jumps never count as driving, and they cancel cargo.
- **Delivery must be driven:** a load is only sellable at a place if the counted driving distance since loading is at least, say, 70% of the straight-line distance between the two places.
- **No buy-sell loops:** buying and selling the same good at the same place is blocked or priced at a loss, and the decaying offset kills repeated short loops.
- **Saves:** two alternating save slots and validation as in Enduro, so a corrupt or edited save is refused rather than silently fixed.

## Reuse from Enduro

Copy from [`earth-enduro---rust-to-race-car`](https://github.com/MadMerick01/earth-enduro---rust-to-race-car) under `mod/beamng_earth_enduro/`, renamed to a new namespace (proposed `earthFreight`). **Copy, don't depend:** BeamNG does not handle one mod depending on another well, and the two games will drift.

| Enduro module | Lines | Reuse | Changes |
|---|---|---|---|
| `earthAdapter.lua` | ~100 | as is | rename only; keep the rule that it is the only module that touches BeamNG.Earth |
| `location.lua` | ~55 | as is | distance, bearing, destination maths |
| `config.lua` | ~30 | as is | new settings path |
| `diagnostics.lua`, `hud.lua` | ~50 | as is | |
| `persistence.lua` | ~260 | adapt | two-slot JSON saves and the vehicle config copy carry over; the schema (stages, CarKov, perks) is replaced by money, vehicle, current load, and the price offsets |
| `garage.lua` | ~300 | as is | repair quotes, parts, buying and spawning vehicles; base-game calls only |
| repair and car pricing in `core.lua` | — | extract | `repairCost` scaled by car Value, parts bills, trade-ins |
| mileage and teleport checks in `core.lua` | — | extract | `addMileage` and the 150 m/s teleport rule |
| arrival logic in `core.lua` | — | extract | "within radius of a point" from resume / finish |
| `punctures.lua` | ~95 | as is | |
| `roadEvents.lua` | ~60 | adapt | **friendly village free-part offer only** (decided, Q16); bandits left out |
| `hostile.lua` | ~330 | not now | no hostiles for now (Q16) |
| `landmask.lua` + `tools/make_land_mask.py` | | pattern | the town-list generator follows the same "build data offline, ship a Lua table" approach |
| `tools/package.py`, `tools/check_earth_versions.py`, `tests/` harness | | as is | LuaJIT/Lupa test runner and mocked game APIs |

`core.lua` is ~2,000 lines and mixes all of these with stage, clock, perk and CarKov logic. The mileage, teleport, arrival and pricing pieces should be lifted into their own small modules (`odometer.lua`, `pricing.lua`, …) as part of the copy, rather than copying `core.lua` whole.

## New modules

| Module | Job |
|---|---|
| `tools/make_places.py` | generator: GeoNames + OSM + land cover + elevation → thinned places with type tags and difficulty score → `places.lua` (or a compact data file) |
| `places.lua` | generated data plus lookup: nearest N places to a point (needs a spatial index, e.g. a lat/lon grid of cells, to stay fast over ~150k+ entries) |
| `goods.lua` | the goods, sizes, base prices and type → supply/demand tables |
| `market.lua` | base price, decaying offsets, buy/sell, green/red classification |
| `cargo.lua` | current load, capacity per vehicle, damage while driving, payout |
| `shipping.lua` | teleport quotes, charging, cargo cancel |
| `core.lua` | the controller tying it together, much smaller than Enduro's |

**❓ OPEN — Q14:** Data format and size for the place list. A Lua table of 150k+ towns plus rural points could be well over the 2–4 MB estimate once rural points are added. A packed per-cell file loaded on demand may be needed.

## Build plan

Layered, so each layer is playable before the next starts. Estimates are from the design discussion and assume the Enduro copy goes cleanly.

1. **Fixed prices (≈2–3 days, plus ≈1 day for type tagging).** Copy Enduro's modules, the place generator (towns first), nearest-places HUD, buy, drive, sell, get paid. Starter sedan with parcels only. This alone is a playable loop.
2. **Supply and demand (≈1 day).** Decaying offsets, green/red dots that react to your trades.
3. **Progression and teleporting.** Vehicle tiers and capacity, rural pickup points, shipping cost and cargo cancel, difficulty pay multiplier.
4. **Living world (≈1–2 days).** Regional events and news.

The real work is **balance**, not code: pay per km against repairs and fuel, how fast offsets recover, what a teleport costs. That needs playtesting on BeamNG.Earth.

## Layer 1 as built

The first playable loop, in `mod/earth_freight/`:

- **Copied from Enduro** under the `earthFreight` namespace: `earthAdapter.lua` (plus a guarded `setDestination` for Earth's GPS), `location.lua`, `config.lua`, `diagnostics.lua`, `hud.lua`, `garage.lua`, `punctures.lua`, and `persistence.lua` with the new schema (money, distance, car with its damage and fuel, the load). From `core.lua`: repair and parts pricing into `pricing.lua`, the 150 m/s teleport rule into `odometer.lua`, and the garage bills (repair, parts, buying cars, the car on arrival) into `workshop.lua`.
- **Places:** `tools/make_places.py` thins a GeoNames extract (`tools/data/geonames_sydney.tsv`, cut from `cities1000`) to places 4 km apart within 150 km of Penrith, with a hand-edited override list (`tools/data/place_overrides.json`) that keeps Penrith, Katoomba, Lithgow and other well-known towns in. That gave 223 places in `placesData.lua`, now part of the worldwide tiles (see below) (it was 8 km and 104 places; Rowan asked for runs as short as 5 km). GeoNames has no importance rank, so suburbs (`PPLX`) are weighted down instead; Wikipedia/OSM ranking can come with the worldwide list.
- **Goods and prices:** all seven goods are defined, but only parcels (parts, food, bricks) can be carried. Prices are fixed: base price × a seeded factor (0.7–1.3) per place and good × a size factor (city 0.9, village 1.1).
- **Cargo space:** our own table of box parts (Q5b), matched on the part name or its parts-menu name: Cargo Load Box S/M/L/XL give 1/4/16/128 slots and 50/200/600/2,500 kg. No box means 2 parcels and 60 kg in the boot.
- **Weight (Q5a):** a game-side mass change. The load's kg are spread over the nodes of the box parts (each jbeam node's `partOrigin`), or over the whole car with no box, through the car's `obj:setNodeMass`. It is put back after every respawn.
- **Fuel (Q15a):** the car's fuel tanks are read and set through its `energyStorage` (litres from each tank's `remainingVolume` and `capacity`), every 2 s and on Refuel. A repair or part change respawns the car full, so the tank is put back to what it had; the save keeps it too.
- **Buying a load** fills the space as far as the money goes and sets the drop-off. Earth's GPS is set to it (Q13), with `autoGps: false` in config.json to turn that off.
- **Anti-cheat:** a load sells only after 70% of the straight-line distance has been driven with it, never where it was bought; a teleport over 2 km cancels it, a shorter hop keeps it.
- **Cargo damage:** the load loses condition as the car's damage reading rises, by each good's `damageForLoss` (parts 3,000, food 6,000, bricks 20,000).

Needs checking in game: whether the vanilla Cargo Load part names match (and which fit the starter Burnside), `obj:setNodeMass` and `partOrigin` on vehicle nodes, the fuel tanks' `remainingVolume`/`setRemainingRatio`, and Earth's `gps.setDestination`.

Not in layer 1: supply and demand, shipping, rural pickup points, the planning map, roadside events.

## Worldwide places as built

- **The list:** `tools/make_places.py` merges GeoNames' `cities1000` (`tools/data/geonames_world.tsv.gz`, 135,000 places) with the Sydney extract, which replaces it within 150 km of Penrith. The overrides apply only there, so Liverpool and Richmond in England are not forced in. Places are thinned to 4 km apart worldwide (suburbs weighted down as before), which keeps **100,125 places**. All but one of the 223 Sydney places are unchanged (St. Georges Basin, on the edge, gives way to a place just outside the old circle).
- **Tiles:** the places are split into 5° tiles (841 of them, 4.5 MB in all, 2.3 MB in the mod zip), one compact text line per place in `tiles/<tile>.lua`, with `placesIndex.lua` listing which tiles have places. `places.lua` loads the tile the player is in and the eight around it as they drive, plus the tiles around the start and around the last save. Lookups go through a 0.25° grid, so only the places close by are looked at.
- **Ids** stay GeoNames ids (`gn…`), so saves keep working.

## Region pay boost as built

Each place gets a boost from 1× to 3× when the list is built; nothing is worked out in game.

- **Steepness** (the biggest part, up to +1.6): `tools/sample_terrain.py` reads the terrain tiles around each place and takes the relief within 10 km (the 95th percentile of the ground height less the 5th; the sea counts as 0 m). From 200 m of relief (nothing) to 2,000 m (full).
- **Remoteness** (up to +0.4): the people living within 50 km, from the whole GeoNames list, on a log scale from a million (nothing) to 5,000 (full).
- **Altitude** (up to +0.3): from 2,000 m to 4,500 m.
- **Famous roads** (hand-made, `tools/data/regions.json`): Death Road +0.6, the Stelvio Pass +0.6, the Karakoram Highway +0.5, for places within 12–15 km of the road. The same file names a few areas (Blue Mountains, Yungas) without a bonus; every other place is named after its country.

The total is capped at 3×. With these settings: Sydney, Parramatta and Penrith 1.0×, Springwood 1.2×, Katoomba 1.5×, Lithgow 1.4×, La Paz 1.9×, Zermatt 2.5×, Leh 2.7×, and Coroico (Death Road), Bormio (Stelvio) and Gilgit (Karakoram) 3.0×. Worldwide the median is 1.13×, and 138 places are at the cap. `python tools/make_places.py --report` prints the breakdown.

**In game:** the boost multiplies every price at a place (what you pay to buy and what a delivery pays) and a run's freight pay at the average of its two ends. A run within a steep region pays that much more, a run up into one pays more again, and a run back down to the flat loses money. The HUD shows the region and its boost next to the town name, like "Death Road ×3.0", and each drop-off's boost on the Town tab.

## Open questions

| # | Question | Working assumption |
|---|---|---|
| Q1 | Land-cover source the generator can actually sample | try a coarser set than ESA WorldCover first |
| Q2 | Where a new game starts | **Decided:** Penrith, NSW |
| Q3 | Which goods, at which sizes | **Decided:** parts, food, bricks (parcel); grain, gravel/ore (dry bulk); water, fuel (fluid) |
| Q4 | Can we read career-mode cargo slots in Earth Freeroam? | capacity per vehicle class, set by us |
| Q5 | Physical or abstract cargo | **Decided:** a number; space from the cargo boxes fitted, weight matters |
| Q5a | How the load's weight reaches the physics | use the `cargoStorage` weight from the Cargo Load parts, if it works outside career |
| Q5b | Which parts are cargo boxes and what each holds | the vanilla Cargo Load parts (Box S/M/L/XL, tanks, aggregate boxes) |
| Q6 | Offset size and decay rate | **Decided:** halves every 2 in-game hours; offset scales with load size |
| Q7 | Pay multiplier cap | **Decided:** 3× |
| Q7a | Elevation source for ruggedness | **Decided:** Mapzen terrain tiles (SRTM and others), sampled offline per place |
| Q8 | Is a semi usable on Earth's streaming? | **Decided:** yes, Earth's road reaches at least 150 m, plenty for a trailer |
| Q9 | Strict tier ladder or buy anything affordable | **Decided:** any vanilla vehicle you can afford |
| Q10 | How a teleport gets paid for | **Decided:** cheap "Book shipping" with an empty vehicle, then coordinates to paste |
| Q11 | Free short hops | **Decided:** yes, under ~2 km and cargo-safe |
| Q12 | Road distance on the HUD | **Decided:** straight-line × 1.3 marked ≈; true road distance for the current delivery from Earth's GPS |
| Q13 | ~~Set Earth's GPS destination when a load is bought?~~ | **Decided: yes**, guarded, with a setting to turn it off |
| Q14 | Place-data format and size | per-cell files if a single table is too big |
| Q15 | Fuel as a running cost | **Decided:** yes, refuel at towns; heavy loads burn more |
| Q15a | How refuelling works | **Decided:** Refuel button in towns and at roadhouses, paid per litre |
| Q16 | What carries over from Enduro's extras | **Decided:** punctures and the friendly village part offer; no bandits, hostiles or CarKov for now |

## Credits

Place data © [GeoNames](https://www.geonames.org/), CC BY 4.0. Elevation: Mapzen terrain tiles (SRTM, GMTED and others; see the [AWS terrain tiles attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)). Further sources (OpenStreetMap ODbL, ESA WorldCover CC BY 4.0) to be credited as they are added.
