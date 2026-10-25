# Earth Freight: Rust to Rig — Design

Status: **draft**, nothing built yet. This doc collects the decisions made so far and marks what is still open. Open questions are tagged **❓ OPEN** inline and gathered in [Open questions](#open-questions) at the end.

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

**Thinning.** Raw GeoNames is mostly suburbs (899 places within 150 km of Sydney). The generator keeps the best-known places and spaces them about **8 km apart**, which gives road runs of 10–15 km. Around Sydney that is ~36 stops in a 150 km circle, most with a neighbour in range.

Known data problems to handle in the generator:

- Some well-known towns drop out because their GeoNames entries are thin (Penrith, Bowral, Kiama). Rank by importance instead of raw population, using Wikipedia or OpenStreetMap `place=town/city` tags, and keep a small **hand-edited override list** for towns that must be in or out.
- Some populations are wrong (Campbelltown shows ~13k against a real ~170k). Pay and demand should lean on the importance rank, not population.

GeoNames is CC BY 4.0, so the mod needs a credit line (README and the HUD's Tips/about screen).

### Rural pickup points

Out in the country towns alone are too far apart (Goulburn's nearest town is 27 km away). The gaps are filled with **rural pickup points**: farms, mines, quarries, sawmills, grain silos and roadhouses, taken from GeoNames feature classes and OpenStreetMap. A rural point sells or buys only one or two goods and has no full board. It means there is a 10–15 km job from almost anywhere, and it feels right for the genre: grain from a farm to the town silo, gravel from a quarry to a building site.

### What each place makes and needs

There is no worldwide database of what towns produce, so the generator **guesses from real geography**, once, and stores the result as a small type tag per place (a place can have two, like `farm+port`). Nothing heavy runs in game.

| Signal | Source | Tag |
|---|---|---|
| Land cover around it: cropland, forest, grassland, desert | ESA WorldCover | farm, timber, livestock |
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

Only about six goods, so the dots stay readable. Each one is spread across the cargo sizes so the same good shows up at every stage of progress.

| Good | Feel | Typical flow |
|---|---|---|
| **Grain / food** | heavy, bulky | farms → towns and cities |
| **Livestock** | pays well, rough driving costs you | farms → cities |
| **Timber** | long load | forests and sawmills → towns |
| **Gravel / ore** | very heavy | quarries and mines → cities |
| **Fuel** | dangerous, pays well | cities → remote places |
| **Parts / machinery** | light, valuable | cities → farms and mines |

| Size | Carried by | Notes |
|---|---|---|
| **Parcels** | any car; a rust-bucket sedan takes 3–4 | low pay, always available (parts, mail, food boxes) |
| **Pallets** | ute or pickup takes 1–2 | where fuel drums and machinery start |
| **Bulk** | tray truck or bigger | grain, gravel, timber, livestock; where the money is |
| **Trailers** | semi | long, high-paying runs into dangerous regions |

A green bulk dot you can't carry yet is meant to be visible early on; it is what keeps you saving.

**❓ OPEN — Q3:** Exactly which goods exist at which sizes (e.g. is there a "livestock parcel"? probably not). A good × size table needs filling in.

**❓ OPEN — Q4:** Vehicle capacity. BeamNG's own career mode puts cargo slots on vehicles for its delivery jobs. If we can read those outside career mode (Earth Freeroam does not load career modules, which is why Enduro's garage uses base-game calls only), each vehicle's capacity comes free and stays right when the car is modded. Otherwise we set capacity per vehicle class ourselves. Needs a check against the API dump (`docs/beamng-api/` in the Enduro repo) and in game.

**Decided (Q5): cargo is a number, but space comes from the cargo boxes on the vehicle, and weight matters.**

- A vehicle's cargo space is the number and size of the cargo boxes (or trays, racks, tanks) fitted to it. Fit more or bigger boxes in the garage and you can carry more. A bare car with no boxes still takes a couple of parcels in the boot.
- Every load also has a **weight**, and weight is a big part of the game: each vehicle has a payload limit, and a heavy load should make the vehicle slower, brake later and handle worse, so overloading a rust bucket is a real risk. Gravel and ore fill a vehicle's weight limit long before its space; parcels and parts fill space first.
- The load itself is still a number in the save, not objects in the tray, so it never falls through Earth's ground.

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

**❓ OPEN — Q15a:** How refuelling works on Earth, which has no petrol stations: a Refuel button on the HUD when stopped inside a town's arrival circle (and maybe at roadhouses), filling the tank through the vehicle's fuel storage. Needs a check of the vehicle-side energy storage calls.

### Pay modifiers

The generator scores every place once for how hard it is to get to:

- **Ruggedness:** how steep and broken the terrain is, from elevation data.
- **Remoteness:** distance to the nearest big city (long hauls with nowhere to repair).
- **Climate:** snow, desert or monsoon zones.
- **Danger (optional):** CarKov-style hostiles in some regions.

Pay is a multiplier on that score. Norway's fjords, the Andes, the Australian outback and Himalayan passes pay several times more than flat European highways. Katoomba → Lithgow is a good local example of a climb that should pay more.

**Decided (Q7): the multiplier is capped at 3×.** Flat highways pay 1×, the Blue Mountains around 1.5×, the Andes or Himalayas near 3×. Any higher and nobody would deliver anywhere else.

**❓ OPEN — Q7a:** Which elevation source the generator samples for ruggedness (SRTM or Copernicus DEM per place).

### Cargo damage

Rough driving damages the cargo and cuts the payout. Damage costs more the more the load is worth, so careful driving pays. Livestock and fuel are the most sensitive. A cheap pickup on a dirt road is a real trade-off.

### Living world (later)

Random events (a mine strike, a harvest boom, a flood closing a road) push prices around a region and appear as news on the board. Layer 3, see [Build plan](#build-plan).

## Progression: rust to rig

The same arc as Rust to Race Car, ending in a truck.

1. **Rust-bucket sedan.** Parcels only. It breaks down, punctures, and rough roads can cost you the load. Early game is earning enough to keep it going.
2. **Ute / pickup.** Pallets.
3. **Small (tray) truck.** Bulk.
4. **Semi.** Trailers and the best-paying long runs.

Vehicles are bought through the garage as in Enduro: a car's game Value sets its price, the old car is traded in, and repair prices scale with the car's Value.

**❓ OPEN — Q8:** Which vanilla vehicles fit each tier best, for tips and balance (the Enduro starter is a Burnside; the ute/pickup could be a D-Series or Roamer config; trucks a Gavril T-Series). Is the semi tier usable on BeamNG.Earth's streamed roads at all, given tight terrain streaming around the car?

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
| `roadEvents.lua` | ~60 | maybe | bandits and friendly villages could fit freight too |
| `hostile.lua` | ~330 | later | for the danger modifier, if wanted |
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

## Open questions

| # | Question | Working assumption |
|---|---|---|
| Q1 | Land-cover source the generator can actually sample | try a coarser set than ESA WorldCover first |
| Q2 | Where a new game starts | **Decided:** Penrith, NSW |
| Q3 | Good × size table | to fill in |
| Q4 | Can we read career-mode cargo slots in Earth Freeroam? | capacity per vehicle class, set by us |
| Q5 | Physical or abstract cargo | **Decided:** a number; space from the cargo boxes fitted, weight matters |
| Q5a | How the load's weight reaches the physics | look at how career cargo adds mass |
| Q5b | Which parts are cargo boxes and what each holds | career cargo slots if readable, else our own table |
| Q6 | Offset size and decay rate | **Decided:** halves every 2 in-game hours; offset scales with load size |
| Q7 | Pay multiplier cap | **Decided:** 3× |
| Q7a | Elevation source for ruggedness | SRTM or Copernicus DEM |
| Q8 | Vehicles per tier; is a semi usable on Earth's streaming? | to test in game |
| Q9 | Strict tier ladder or buy anything affordable | **Decided:** any vanilla vehicle you can afford |
| Q10 | How a teleport gets paid for | **Decided:** cheap "Book shipping" with an empty vehicle, then coordinates to paste |
| Q11 | Free short hops | **Decided:** yes, under ~2 km and cargo-safe |
| Q12 | Road distance on the HUD | **Decided:** straight-line × 1.3 marked ≈; true road distance for the current delivery from Earth's GPS |
| Q13 | ~~Set Earth's GPS destination when a load is bought?~~ | **Decided: yes**, guarded, with a setting to turn it off |
| Q14 | Place-data format and size | per-cell files if a single table is too big |
| Q15 | Fuel as a running cost | **Decided:** yes, refuel at towns; heavy loads burn more |
| Q15a | How refuelling works with no petrol stations | Refuel button inside a town's arrival circle |
| Q16 | Does CarKov or any Enduro side mode carry over? | no, at least not in layers 1–3 |

## Credits

Place data © [GeoNames](https://www.geonames.org/), CC BY 4.0. Further sources (OpenStreetMap ODbL, ESA WorldCover CC BY 4.0, elevation data) to be credited as they are added.
