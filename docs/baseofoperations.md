# The Magnate update: bases of operations

Status: **steps 1 to 3 built**, 10 Nov 2026; **Magnate 2 built**, 11 Nov 2026; **Magnate 3 (corps) built**, 11 Nov 2026 (see below). Built so far: the base replaces the home; its circle and the owner's bonus; on a
server, bases kept by the server (one a town, 10 km apart), everyone's circles, visitors' bonus, turf pushing, Ship Day
containers, circles and a Base column on the web page, and commission. Since 11 Nov 2026 the Base tab also opens a
Base map in the browser (served by the game like Street View, at `/bases`), and the game says when the truck crosses
into or out of a turf. BeamNG.Earth's own map has no way for a mod to draw on it, so the circles live there instead.
Dangerous contracts, heli jobs and beacon packages get no base bonus and no commission: they run on famous roads and
remote spots far from towns, where a town's circle means little. An off-road drop counts for the town it was taken in,
at both ends. Commission is marked paid when the owner's next save reaches the server (the save carries the batch's
id), so it is never lost or paid twice.

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
- Ship Day containers: the same rule applies (the port town and the drop-off town). Dangerous contracts, heli jobs and
  beacon packages get no base bonus (decided while building step 1: they happen far from towns). **Decided (MadMerick, 9 Nov):** Ship Day gets the bonus and commission like any job, so a base
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

## Magnate 2: world-size turf

Decided by MadMerick on 11 Nov 2026, for 20-player servers that cover the whole world, and built the same day; the proposals below were accepted as written. It replaces the
circle sizes, the visitors' bonus and the 2.5% commission above.

### Circle size

- **1,600 km at $250,000**, growing with the square root of wealth (4× the wealth, twice the reach), with **no cap**:
  radius = 1,600 km × √(wealth ÷ $250,000) × √(region multiplier).
- Wealth stays cash + truck + base, and the circle still uses the season's best wealth, so it never shrinks.
- Examples on flat ground: $350k → 1,890 km, $637,500 → 2,555 km, $1M → 3,200 km, $2M → 4,525 km, $4M → 6,400 km,
  $10M → 10,100 km, $25M → 16,000 km (most of the world).
- Ten bases worth about $13.5M together claim most of the world's land, with a big neighbour squeezing a small one but
  never wiping it out.

### Turf rules

- The border rule stays: inside a base's core it's that base's; elsewhere, the circle with the smallest distance ÷
  radius wins.
- **Core: 100 km** (was 5 km), so a rival can't build next door and take your city. *Proposed.*
- **Bases at least 300 km apart** (was 10 km), so bases spread out instead of crowding around Sydney. *Proposed.*

### Pay

- **Your own turf:** the owner's +0.4 on the region multiplier stays.
- **Visitors' +0.2 is dropped.** With circles this big almost everything is inside one, so it would just be a pay rise
  for everyone.
- **The turf toll (Decided, MadMerick, 11 Nov):** deliver in someone else's turf and **20% of the payout goes to that
  turf's owner**. This discourages teaming up in one another's turf. It replaces the 2.5% commission. The driver's pay
  really drops: the toll is a transfer, not new money from the server.
  - Which end counts: the **drop-off**, where the delivery is made. *Proposed;* the alternative is 10% at each end.
  - It applies to town jobs, off-road drops (at the drop spot) and Ship Day containers. Dangerous contracts, heli jobs
    and beacon packages stay out, as now. *Proposed.*
  - No toll in your own turf, outside every turf, or in single player.
  - The job board shows it before you take the job: "Drop-off in Belake's turf: 20% toll". The delivery pay line
    shows "Turf toll to Belake −$1,240".
  - The owner is paid like commission today: straight away when online, otherwise in one go when they next join,
    marked paid by their next save.
  - **Daily limit:** none, since it's money moving between players, not new money. *Proposed.*

### What changes in the game

- The turf messages and the Base map say "Deliveries here pay a 20% toll to Belake" instead of "+0.2".
- The Base tab and the web page show the new sizes, the 100 km core and the 300 km spacing.
- Existing bases keep their town, and their circle is re-sized by the new rule. Bases closer than 300 km stay where
  they are; the spacing only applies to new ones. *Proposed.*

## Magnate 3: corps

Built. On a server, other players can join a base and become a corp. Single player has no corps.

### Joining and leaving

- The player who built the base founds the corp and owns it. Nothing about the base or its toll changes hands.
- A player without a base presses **Ask to join** next to a base on the Base tab. The owner sees the request on
  their Base tab and presses **Accept** or **Turn down**. A player has one request out at a time.
- A corp holds at most 5 truckers: the owner and 4 members.
- A player is in one corp at a time, and a member can't buy a base while they're in one. A player who owns a base
  can't join a corp.
- A member can press **Leave corp**, and the owner can press **Remove** next to a member. Either way that player waits
  24 hours before they can ask to join any corp again, so nobody hops into whichever corp owns the drop-off town to
  skip its toll.

### What members get

- **A yard at the base.** A member parks one car and one trailer at the owner's base spot, as the owner does: Swap
  cars, Park at base, Swap trailers, half-price repairs there, and a second trailer. Relocate lists it as Corp yard.
  The server only sends the base's exact spot to its members.
- **No toll in their corp's turf.** Everyone else still pays the 20% toll, and all of it goes to the owner.
- **+0.2 on the region multiplier** for jobs that start or end in their corp's turf. The owner keeps +0.4.
- Members don't pay the owner anything.
- **Tolls are split equally** between the owner and every member (since 12 Nov 2026). A solo owner keeps every toll in
  a smaller turf; a corp shares the tolls of a bigger one. Each player's share is kept on the server (`tolls.json`,
  by career key) and paid as a batch when they're next on, as before. A member who leaves stops earning but keeps
  what they're owed. Whole dollars only: what doesn't split evenly goes to the owner.
- **The bonus is shown as a percentage.** +0.4 on the region multiplier is up to +20% on a job (both ends in the turf,
  flat ground; one end is +10%), +0.2 is up to +10%. Off-road drops are now halved like town jobs, so they also get
  +20% in your turf instead of +40%.

### Circle size

The circle is sized by the owner's best wealth plus half of each member's wealth now, by the Magnate 2 formula.
Four $250k truckers with one $250k owner reach 1,600 × √3 ≈ 2,770 km instead of 1,600 km. Only the owner's part keeps
the never-shrinks rule: a member's half goes when they leave.

### Leaving with things in the yard

A member who leaves or is removed has their car in the yard traded in at the usual trade-in price (half its worth,
less the repair it needs) and their trailers there sent to the depot for free. The Leave corp button says so before
it goes ahead.

### The server

`bases.json` gains each base's `id`, its owner's exact `spot` (sent to members only), `members` and `requests`
(by career key, each with a public number the owner's buttons use) and `corps.json` keeps when each player last left.
`wwtcCorp '{"v","do","base","who"}'` carries ask, cancel, leave, accept, turn down and remove. `wwtcBases` gains
each base's `id`, `members` (names) and the viewer's own `corp`, `asked`, `yard`, `requests` and `memberList`.

## Building it in steps

1. **Single player:** the base replaces the home, the circle and its size, and the owner's +0.4. Shown on the Home
   card and the job board.
2. **Server, bonus only:** bases kept on the server, one per town, the `wwtcBases` list, visitors' +0.2, circles on
   the web page, base price in wealth.
3. **Commission:** the owed ledger, `wwtcCommission`, toasts, the daily limit and the live feed.
4. **Magnate 2:** world-size circles, the 100 km core and 300 km spacing, no visitors' bonus, and the 20% turf toll
   in place of commission.
5. **Magnate 3:** corps.
6. **Later:** base upgrades (more car spaces, a fuel pump, a repair bay), and town
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
| B12 | Circle size for world servers (Magnate 2) | **Decided:** 1,600 km at $250k, square root of wealth, no cap |
| B13 | Delivering in someone else's turf (Magnate 2) | **Decided:** 20% of the payout goes to the turf's owner, replacing commission and the visitors' +0.2 |
| B14 | Core and spacing (Magnate 2) | *Proposed:* 100 km core, bases 300 km apart |
| B15 | Which end the toll counts at, and any daily limit | *Proposed:* the drop-off only, no daily limit |
| B16 | Corps: who owns the base, and who gets the toll? | **Decided:** the founder owns it and gets every toll from non-members; members pay no toll in their corp's turf |
| B17 | Corps: what do members get? | **Decided:** a car and trailer yard at the base, and +0.2 in the corp's turf; they pay the owner nothing |
| B18 | Corps: what sizes the circle? | **Decided:** the owner's best wealth plus half of each member's wealth now |
| B19 | Corps: limits | **Decided:** 5 truckers a corp, one corp at a time, 24 hours after leaving before joining another |
| B20 | Corps: who gets the tolls? | **Decided:** split equally between the owner and every member; a solo owner keeps them all |
| B21 | How is the bonus shown? | **Decided:** as a percentage, up to +20% for an owner and +10% for a member; drops get the same +20% |
