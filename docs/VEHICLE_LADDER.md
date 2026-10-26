# Vehicle ladder and prices

**Status: planned, not built.** Rowan asked on 26 Oct 2026 to keep this as documentation for now and build it later. Nothing here is in the game yet; the numbers are a starting point to tune in game.

## The short version

The garage already charges a car's own BeamNG **Value** (the price in its config info file), trades the old car in for half (`pricing.CAR_TRADE_IN_SHARE`), and scales repairs by Value. Vanilla Values work with today's pay: each step up takes roughly 5 to 8 runs.

What does not work yet is weight. A $33,000 H-Series van fits two XL boxes, and at our 2,500 kg per XL box it would carry about 5 t and out-earn the trucks. So the proposal is to keep vanilla prices and add a **payload limit per vehicle class**.

## The ladder

Pay is a typical 12 km run of bricks at the base rate (`jobs.lua`: $2,000 for 780 kg over 5 km; 12 km pays about 3.1 times a 5 km job). Payload is the proposed cap, not what the boxes alone would allow.

| Tier | Vanilla vehicles | BeamNG Value | Boxes it fits | Proposed payload | Pay, 12 km run |
|---|---|---|---|---|---|
| 1. Starter | Earth Freight Burnside (our config) | $3,500 (ours) | 5 M boxes, 20 slots | 650 kg (as today) | about $5,200 |
| 1b. Big car (optional) | Bruckell LeGran wagon; Bruckell Bastion; stock Burnside Special | $29,800 to $51,000; from $34,500; $41,000 to $47,000 | about 40 to 52 slots (L and M boxes) | 1,000 kg | about $7,300 |
| 2. Ute / van | Gavril D-Series D15; Gavril H-Series H15 / H25 van; Gavril Roamer | $33,000 to $44,000; $33,000 to $51,500; $40,000 to $54,900 | one XL in a pickup bed (128+ slots), about 260 slots in the H-Series van | 1,500 kg (D25 / H25: 2,000 kg) | about $9,400 |
| 3. Light truck | D-Series D35 dually; H-Series H45 Cabster Cargo Box; Gavril MD-Series MD60 / MD70 | $63,000; $79,000; $70,000 to $86,000 | H45 box 768 slots (6 XL), MD box or flatbed 1,536 slots (12 XL) | 3,500 kg (D35, H45); 8,000 kg (MD) | about $16,000; about $27,000 |
| 4. Big truck | Gavril T-Series (TC82, T82, TC83, T83, Long Haul); MD70 Fifth Wheel | $160,000 to $258,000 (Long Haul about $320,000 to $350,000, unofficial); $72,500 | a trailer's boxes (see below) | 20,000 kg with a trailer | about $48,000 |

Runs to move up, counting the 50% trade-in and ignoring fuel and repairs: starter to ute about 7 runs, ute to light truck about 6, MD to semi about 5. That is roughly 20 runs, or 5 to 6 hours, from rust bucket to rig.

This keeps Q9 in [DESIGN.md](DESIGN.md) as decided: there is no forced ladder, and the player can buy any vehicle they can afford. The tiers are the usual path, and the payload limit is what makes each step worth it.

## Why a payload limit

Boxes alone set capacity today (`cargo.lua`), and the XL box limit (2,500 kg) was sized for trucks. With it, an H-Series van (2 XL) takes about 5 t and an MD box truck (12 XL) about 30 t, so the van would skip the light-truck tier and the MD would match a semi.

A payload per class keeps the ladder: the boxes still decide how many slots there are, and the class decides how heavy a load can be. It could be a small table by model name (burnside, pickup, van, md_series, us_semi and so on), with a fallback based on the car's own weight for modded cars.

## To decide or build

- **Prices:** keep BeamNG's own Values (recommended: nothing to maintain, and every vanilla and modded car is priced), or keep our own price list per tier.
- **Payload limit per class:** the numbers above are a starting point to tune in game.
- **Trailers:** the garage reads cargo boxes on the player's vehicle only, so a semi has no cargo space until trailer boxes are counted. The semi tier needs that before it works.
- **MD70 Fifth Wheel at $72,500** is a cheap semi tractor. With a trailer it would jump the T-Series unless its payload is capped lower (for example 12,000 kg).
- **A full price list:** a small in-game console command that prints every config's Value, so the list is exact for the player's game version.

## Where the prices come from

Values are from BeamNG's official vehicle pages (game version 0.40.2), read through search results, plus a few from the BeamNG fan wiki (MD60 Cargo Box, LeGran) and Quarryside Auto (T-Series Long Haul). The full tables could not be opened at the time, so some trims are missing, including the Ibishu Pigeon, the Gavril Bluebuck and the Grand Marshal. Slot counts are from community career-mode guides and may have changed since. The game itself is the reliable source; see the console command above.
