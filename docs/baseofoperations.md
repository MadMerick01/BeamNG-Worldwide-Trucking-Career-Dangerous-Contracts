# The Magnate update: bases of operations

Status: **step 1 built** (single player: the base replaces the home, its circle and the owner's bonus on town jobs and
off-road drops), 9 Nov 2026. Dangerous contracts, heli jobs and beacon packages get the bonus with step 2. All open questions answered by MadMerick on 9 Nov. Written from MadMerick's idea. Decisions are marked **Decided**.

## The pitch

You buy a base of operations in a town. Around it is a circle of influence, and the circle grows as you get richer.
Anyone who delivers inside your circle earns a little more, you earn more still, and you take a small commission on
other players' jobs that start or end there. On a server, the map fills up with rival bases and turf, and getting rich
shows: your circle is the biggest one on the map.

## How it works for the player

1. **Buy a base.** On the Home card, park in a town and press **Buy a base here** ($250,000, the price of a home today).
   The base takes the name of the town, for example "MadMerick's base, Katoomba".
2. **Your circle.** A circle of influence is drawn around the base. It reaches about 20 km out at the start (half of Sydney) and
   grows with your wealth (see [Circle size](#circle-size)).
3. **Pay inside a circle.** Any delivery with an end inside a base's circle pays more:
   - **Anyone:** the region multiplier gets **+0.2 × the region multiplier** at that end (Sydney's ×1.0 counts as
     ×1.2, Death Road's ×3.0 as ×3.6).
   - **The owner, in their own turf:** **+0.4 × the region multiplier** instead.
   - Steep regions are rewarded twice: a bigger bonus and a bigger circle (see
     [Steep regions](#steep-regions-pay-more-and-reach-further)).
4. **Commission.** When another player picks up or drops off a job inside your circle, you are paid a small commission
   on top of what they earn. Nothing is taken from them.
5. **Everything a home does today stays.** The base keeps your stored car, Swap cars, half-price repairs and the
   Relocate destination (shown as "Base" instead of "Home").

## Base replaces home

**Decided (MadMerick, 9 Nov):** the base of operations replaces the home rather than sitting beside it. One building, one price, and
the existing home perks become the base's perks.

- **Saves keep working.** An existing home becomes a base at the nearest town automatically, at no cost.
- **Single player** gets the base too: you get the owner's +0.4 in your own circle. There are no other players, so no
  visitors and no commission.
- **One base per player.** Moving it is **Move base here**, for 20% of the price ($50,000). The circle keeps its size,
  since that comes from your wealth, not from the base.

## Circle size

The circle grows with **wealth**, the same number the leaderboard ranks by: cash plus truck value plus the base's price
(see [Wealth and the leaderboard](#wealth-and-the-leaderboard)).

**Decided (MadMerick, 9 Nov):** a new base is big from the start, about half of Sydney's metro area, and the circle's
*area* grows in line with wealth (double your wealth, double your turf):

> radius = 20 km × √(wealth ÷ $350,000) × √(region multiplier at the base's town), at most 100 km

The table below is for a flat region (×1.0). Steep regions start bigger: see
[Steep regions](#steep-regions-pay-more-and-reach-further).

| Wealth | Radius | From Sydney's CBD, that reaches |
|---|---|---|
| $250,000 (the base and nothing else) | 17 km | the inner suburbs |
| **$350,000** (base $250k, truck $80k, cash $20k) | **20 km** | **Hornsby, Sutherland, nearly Parramatta: about half the metro** |
| $700,000 | 28 km | Parramatta, Campbelltown side |
| $1,400,000 | 40 km | the whole metro area |
| $2,800,000 | 57 km | the lower Blue Mountains, the Central Coast edge |
| $5,600,000 | 80 km | Wollongong |
| about $8,750,000 or more | 100 km (the most) | Katoomba |

Because the base's price counts as wealth, a fresh base never starts below 17 km.

- The size updates each time the owner saves, from their wealth at that save, the same way the leaderboard does today.
- **Decided (MadMerick, 9 Nov): a circle never shrinks.** It is sized by the most wealth the owner has had this season,
  so spending money or a bad crash never costs turf. It only grows. (Neighbours can still push its border back: see
  [Circles pushing circles](#circles-pushing-circles).)

## The pay bonus

### How big it is

The region multiplier is the number shown next to a town name, like "Katoomba ×1.5". Today it pays like this:

- **Town jobs** get half of it above ×1.0: the road bonus is 1 + (multiplier − 1) ÷ 2, at most ×2, taken from the
  average of the job's two ends.
- **Off-road drops** get all of it above ×1.0, at most ×2.

**Decided (MadMerick, 9 Nov):** the bonus goes on the region multiplier, and it **scales with the region**: at each
end inside a circle, visitors add **0.2 × that end's multiplier** and the owner adds **0.4 × that end's multiplier**. The
usual caps (×3 multiplier, ×2 road bonus) apply to the normal part only, and the base bonus goes on top of them. For a
town job that is: road bonus = (the usual road bonus) + half the average base bonus of its two ends.

On a job that pays $1,000 on flat ground, with both ends inside the circle:

| | Flat Sydney (×1.0) | Katoomba (×1.5) | Death Road (×3.0) |
|---|---|---|---|
| Job pays without a base | $1,000 | $1,250 | $2,000 |
| Visitor | $1,100 (+10%) | $1,400 (+12%) | $2,300 (+15%) |
| Owner, in their own turf | $1,200 (+20%) | $1,550 (+24%) | $2,600 (+30%) |
| Owner's commission on a visitor's job (5%) | $55 | $70 | $115 |

With only one end inside, the gain is half. Off-road drops get the whole multiplier, so their gain is twice that of a
town job: on flat ground +20% for visitors and +40% for the owner.

### Steep regions pay more and reach further

**Decided (MadMerick, 9 Nov):** a base in a steep region is rewarded twice.

1. **A bigger bonus**, as above: the bonus is a share of the region multiplier, so Death Road's visitors get +0.6 and
   its owner +1.2, against +0.2 and +0.4 in Sydney. Commission grows with it, since it is a share of the pay.
2. **A bigger circle.** Steep regions are remote and their towns are far apart, so the radius is multiplied by
   √(the region multiplier at the base's town):

| Base's town | Multiplier | Circle at $350,000 | Circle at $1,400,000 |
|---|---|---|---|
| Sydney | ×1.0 | 20 km | 40 km |
| Katoomba | ×1.5 | 24 km | 49 km |
| La Paz | ×1.9 | 28 km | 55 km |
| Zermatt | ×2.5 | 32 km | 63 km |
| Coroico (Death Road) | ×3.0 | 35 km | 69 km |

The 100 km limit stays the same everywhere, so a steep base reaches it sooner (at about $2.9M on Death Road, against
$8.75M in Sydney). Pushing uses these bigger radii, so a steep base also holds its borders better against a flat
neighbour.

### Where several circles overlap

- **No stacking.** An end inside several circles gets the best single bonus: the owner's bonus if it is in your own turf, else the visitors' bonus.
- **Turf** decides who gets the commission and where the owner's +0.4 applies. See
  [Circles pushing circles](#circles-pushing-circles).

## Circles pushing circles

**Decided (MadMerick, 9 Nov):** bases never move, but where circles overlap, the bigger circle pushes the shared border
toward the smaller one.

- **The border sits in proportion to the circles' sizes.** Between two bases, it falls at the bigger base's share of
  the distance. For example, a 40 km circle and a 20 km circle whose bases are 30 km apart meet 20 km from the big base
  and 10 km from the small one.
- **The rule for any spot:** it belongs to the base it is "closest" to relative to size, that is, the one with the
  smallest distance ÷ radius, among the circles it is inside. That gives exactly the border above, and with three or
  more bases each pair's border works the same way. The borders come out as gentle curves bending around the smaller
  base.
- **A protected 5 km core.** Everything within 5 km of a base belongs to it, however big its neighbours get, so nobody
  can be wiped off the map.
- **Bases at least 10 km apart.** Buying a base closer than that to someone else's is refused ("Too close to Sam's base
  in Parramatta. Bases must be 10 km apart."), so the cores never overlap and nobody can set up right next door to
  steal a town.
- **What turf decides:** commission and the owner's +0.4 count only inside your own turf. The visitors' +0.2 applies
  anywhere inside any circle, your neighbour's included.
- **It moves as you grow.** Circles never shrink, but each time you get richer your circle grows and your borders move
  out. A neighbour who gets richer than you pushes back. That is the only way to win ground from a rival, and the map
  shows it happening.
- **On the map,** each base is drawn as its circle cut off where a stronger neighbour's border runs, in the owner's
  colour, with the 5 km core shaded.
- **Single player:** there is nobody to push, so your turf is your whole circle.

### What counts as "inside"

- A town job's ends are the pickup town and the drop-off town, measured from the town centre to the base's centre.
- An off-road drop's spot counts as its own end.
- Ship Day containers, dangerous contracts, heli jobs and beacon packages: the same rule applies (the pickup town and
  the drop-off town). **Decided (MadMerick, 9 Nov):** Ship Day gets the bonus and commission like any job, so a base
  near a port is worth having.

The board shows the bonus before you take a job: the drop-off line reads, for example, "Lithgow ×1.4 +0.2 (Sam's
base)", and the Route tab says "Inside Sam's base: +0.2" while you drive.

## Commission

- **Rate (Decided, MadMerick, 9 Nov):** 5% of what the job pays, split between its two ends: 2.5% to the base whose turf holds the
  pickup and 2.5% to the base whose turf holds the drop-off. A job that starts and ends in your turf pays you the full
  5%.
- **Who pays (Decided):** the server, as new money. The driver keeps everything they earned, bonus included, so nobody feels
  taxed for working in someone's circle.
- **Not on your own jobs:** the owner's own deliveries pay no commission to themselves. They get the +0.4 instead.
- **A daily limit (Decided, MadMerick, 9 Nov):** at most $20,000 commission a day for each base, so a few friends can't farm each
  other's circles with tiny jobs. To be tuned once we see real numbers in the server's ledger.
- **While you're offline:** commission builds up on the server and is paid the next time you join, with one toast
  ("While you were away, 14 jobs in your turf paid you $3,240").
- **While you're online:** a small toast per job ("Sam delivered in your turf: +$85 commission"), and an entry in the
  server's live feed.

## Multiplayer

### What the server keeps

In `careers/season-N/bases.json`: for each base, the owner's career key and name, the town's name and centre, the price
paid and the current radius.

- **One base per town, and 10 km apart.** The first player to buy in a town gets it. A second player gets "Sam
  already has a base in Katoomba. Try the next town." A base closer than 10 km to another is refused too.
- **Privacy:** a base sits at its **town centre** for everyone else and on the web page, never at the exact spot
  where the owner parked. That spot (where the stored car and Swap cars are) stays private, like the home today.
- **Players who stop playing (Decided, MadMerick, 9 Nov):** their base keeps its circle and keeps earning commission
  until the season ends.
- **Seasons:** bases go with the season. A new season starts with no bases, and the old season's map is kept for the
  hall of fame.

### Messages

- `wwtcBases` (server to everyone): every base's owner name, town, centre and radius. Sent on join and whenever a base
  is bought, moved or changes size.
- `wwtcBuyBase` / `wwtcBaseBought` (game to server and back): asks the server for the town, so two players can't buy
  the same town at once. Like a Ship Day container claim: first come, first served.
- `wwtcDelivered` already reports each delivery's pay and towns. It gains the pickup and drop-off centres (town
  centres only, which are public), so the server can work out the commission and whose turf it is.
- `wwtcCommission` (server to owner): commission owed. The game adds it to the balance, saves and confirms, and the
  server marks it paid. Until it's confirmed, it stays owed, so nothing is lost if the game crashes.

The pay bonus is worked out in each player's game from the `wwtcBases` list, the same way Ship Day pay is. The server
checks it later, in the referee step.

### The web page

- The map shows each base as a circle with the owner's name, like the town markers today.
- The leaderboard gains a **Base** column (the town, or a dash) next to Wealth.

## Wealth and the leaderboard

**Decided (MadMerick, 9 Nov):** wealth becomes cash + truck value + the base's price. Without that, buying a base would drop you
$250,000 down the leaderboard, which is the same problem we just fixed for trucks.

## Building it in steps

1. **Single player:** the base replaces the home, the circle and its size, and the owner's +0.4. Shown on the Home
   card and the job board.
2. **Server, bonus only:** bases kept on the server, one per town, the `wwtcBases` list, visitors' +0.2, circles on
   the web page, base price in wealth.
3. **Commission:** the owed ledger, `wwtcCommission`, toasts, the daily limit and the live feed.
4. **Later:** base upgrades (more car spaces, a fuel pump, a repair bay), and town
   rivalries.

## Decisions

| # | Question | Answer |
|---|---|---|
| B1 | Does the base replace the home? | **Decided:** yes, with homes converted for free |
| B2 | Bonus: on the region multiplier (+10% / +20% on a town job), or on the road bonus (+20% / +40%)? | **Decided:** region multiplier (+0.2 / +0.4) |
| B3 | Commission rate and who pays | **Decided:** 5% split across both ends, paid by the server |
| B4 | Daily commission limit | **Decided:** $20,000 a base a day, a server setting tuned later |
| B5 | Does the base's price count as wealth on the leaderboard? | **Decided:** yes |
| B6 | Circle shrinks straight away or slowly? | **Decided:** never shrinks; sized by the season's best wealth |
| B7 | Does Ship Day get the bonus? | **Decided:** yes, bonus and commission like any job |
| B8 | What happens to the base of a player who stops playing? | **Decided:** it keeps its circle and earns commission until the season ends |
| B9 | How does the circle grow with wealth? | **Decided:** 20 km at $350k, area in line with wealth, at most 100 km |
| B10 | Do circles push each other? | **Decided:** border by size, 5 km protected core, bases 10 km apart |
| B11 | How is a base in a steep region rewarded? | **Decided:** bonus × the region multiplier (past the caps), and radius × √(region multiplier) |
