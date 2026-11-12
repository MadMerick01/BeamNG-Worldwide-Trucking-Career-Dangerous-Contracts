# Multiplayer career — design

Status: **step 1 ("keeper") built**, 8 Nov 2026: careers kept on the server, career keys, seasons and the `trucking` command (`server/WorldwideTrucking/main.lua`, `multiplayer.lua`; setup in [MULTIPLAYER-SETUP.md](MULTIPLAYER-SETUP.md)). Written from a design discussion with MadMerick. Decisions are marked
**Decided**; open questions are tagged **❓ OPEN**.

## The pitch

The Worldwide Trucking career on a BeamMP server running BeamNG.Earth: friends drive the same real-world map, each with
their own truck and money, working the same towns. Later: seasons, a public leaderboard webpage, player tows and
convoys.

## What BeamNG.Earth already gives us

BeamNG.Earth runs on BeamMP today (its `beammp/` folder: a server plugin and a client zip).

- Every player's own Earth app builds the world around them, in a local frame around an **anchor** that moves as they
  drive (a rebase about every 15 km) and on a teleport. BeamMP sends car positions in each driver's own frame, so
  Earth's server plugin tells every client where everyone's anchor is (`bngeAnchors`, every 2 s and when an anchor
  changes) and each client converts the others' cars into its own frame (`mpanchor.lua`).
- Each client reports its pose to the server (`bngePose { v, aLat, aLon, lat, lon, joined, h }`, every 2 s). So the
  server already knows every player's latitude and longitude.
- Players far apart each build their own world and don't see each other until they meet.
- The server needs no world data and little CPU. It can share road levelling plans (`G.SHARE_OUT_KBPS`, 1 MB/s
  default) and has an optional, heavy "share helper" we don't need.
- **A joining player farther than `G.MEET_M` (3 km) from the others is teleported to the longest-joined player.** That
  suits free roam but breaks a career: a teleport while on a job without a shipping booking strands the player. Our
  servers set `G.MEET_M` very high (or our plugin replaces this behaviour).

Client hooks are BeamMP's own: `TriggerServerEvent(name, data)` and `AddEventHandler(name, fn)` in GE Lua; the
server answers with `MP.TriggerClientEvent(pid, name, json)` (pid -1 for everyone). We add our own plugin next to
Earth's (`Resources/Server/WorldwideTrucking/main.lua`) and never change Earth's.

## Decided

- **Hosting starts on MadMerick's own PC, free.** The PC must not sleep, port 30814 TCP+UDP forwarded. Move to a
  $5–10/month VPS if it gets popular (home upload limits it to roughly 5–10 players; past 20–30, run servers by region).
  Charging, if ever, only once popular, and as supporter perks rather than an entry fee.
- **Multiplayer careers are kept on the server** (MadMerick, 8 Nov). The server is the only thing that changes a player's
  money. This gives seasons (resets), a fair leaderboard and no editing money in a save file.
- **Multiplayer careers are separate from single-player careers.** Playing on a server never reads or writes the
  player's own `/settings/earthFreight/` saves.
- **Positions are private.** Real places can be a player's home street. Other players and the webpage only ever see a
  town name, never exact coordinates.

## Server-kept careers

### Where it plugs in

The career already has the seams this needs:

- **Saves** go through one store (`persistence.new(io)`, injected into `core`). In multiplayer the store is swapped for
  one that sends the save document to the server and loads it from the server's answer, instead of the two JSON slots.
  The document and its validation (`persistence.validate`) stay the same.
- **Money** changes in a handful of places: `addMoney` (deliveries), `spend` (every purchase, with a label), the police
  fine and the abandon/insurance charges. In multiplayer each becomes an event to the server, and the balance shown is
  the server's.
- **Job pay** is pure Lua (`jobs`, `places`, `contracts`, `goods`, `location`, `pricing`): no game globals. The server
  can load the same files and recompute what a delivery pays. They must stay runnable on the BeamMP server's Lua 5.3 as
  well as the game's LuaJIT (no `unpack`, `bit`, `ffi` or `setfenv`; tests should run on both).

### The server's records

In `Resources/Server/WorldwideTrucking/`:

- `careers/season-N/<career key>.json`: the same save document the game writes in single player, kept as the JSON
  text the game sent;
- `careers/season-N/ledger.tsv`: one line per change of money (time, key, name, before, after, save generation);
- `accounts.json`: BeamMP account id (`MP.GetPlayerIdentifiers(pid).beammp`) to career key, so a signed-in player
  keeps their career on any PC and after renaming;
- `server.json`: this server's own id, which the game files career keys under.

**Decided (MadMerick, 8 Nov): guest accounts are allowed, and keep money and trucks too.** A BeamMP guest has no account id
and a new random name each time, so the server gives every career a secret **career key** on first join. The game
keeps it in a small file on the player's PC (one per server) and sends it on every join; the server finds the career by
it. A guest's career therefore stays on the PC it was started on: a reinstall that deletes the file, or another PC,
starts over. Account players are found by their account id, with the key as well. The key is never shown to other
players. (Not built yet: a HUD note telling a guest that signing in to BeamMP keeps their career safer.)

### How much the server checks

Built in two steps, so a first version ships quickly:

1. **Keeper.** The server stores each career and hands it back on join. Money changes are reported as events and
   logged, with simple limits (a delivery can't pay more than the board's maximum for that distance, a balance can't
   jump without an event). Enough for a friends' server.
2. **Referee.** For a delivery the game reports the job (from town, board seed, good, drop-off, units); the server
   recomputes the pay from the shared pure modules and checks with Earth's poses that the player was at the pickup,
   drove there in a plausible time, and is at the drop-off now. Purchases only take money away, so they need no check
   beyond "can afford it".

### Seasons

The server holds a season number in its settings. A player whose career is from an older season starts a new one on
join: the normal start (rusty Burnside, $6,000), not $0, since the first radiator must be affordable. The old season's
final leaderboard is kept for a hall of fame. Each season can carry a twist (a start region, a pay multiplier).

### Updates

Replacing the mod zip in `Resources/Client` and restarting the server is all it takes; BeamMP sends the new file to
players as they join. A build that changes the save document must also be read by the server, so the server plugin and
the mod ship together and carry the same save schema.

## Ship Day (built)

**Decided (MadMerick, 8 Nov):** buying ports worldwide is too big for a server of about 10 players. Instead, every 3
days a ship docks at one interesting port and everyone heads there: on BeamNG.Earth players only see each other when
they are close, so this is what brings them together.

- The server holds the schedule, the port list and who has which container (`ships.json` in the season folder). It
  sends the ship to each player (`wwtcShip`), answers claims (`wwtcClaim`/`wwtcClaimed`, first come first served, one
  at a time), frees abandoned containers (`wwtcRelease`) and announces deliveries in chat (`wwtcShipDone`).
- Each container's destination and pay are worked out in the game (`shipday.lua`), the same on every PC: towns 15–70 km
  by road from the port town, picked by a hash of the ship and container number. Pay is the usual pay by weight and
  distance for "Container cargo", which pays twice the usual rate.
- **No landing in the water:** Go to port goes to the centre of the town nearest the port's coordinates, never to the
  coordinates themselves.
- Not yet: the server doesn't check the pay of a container delivery against what it should be (the referee step).

## Relocate to a player (built)

MadMerick, 9 Nov: "there need to be a way to relocate to a player, so you can do jobs together."

- The **Relocate** tab lists everyone else on the server by name and town (`wwtcPlayers`, from the towns the games
  already report, sent every 15 s and on every join and leave). Never a position.
- **Join** sends `wwtcFind` to the server, which asks that player's game (`wwtcLocate`); their game answers (`wwtcHere`)
  with its exact spot and heading, or no. The server passes the spot to the asker only (`wwtcFound`) and keeps nothing.
- The asker's game books a normal relocation to a spot 20 m behind the other car and teleports there in one press.
- **Fairness (chosen):** the usual relocation fee and rules, not free: an empty car, no job on board, no garage bill
  owed. A free jump would make a friend parked in a far-off region a free worldwide taxi, and the fee is small anyway
  ($100 plus $0.02 a km). Taking the trip doesn't affect the other player's job in any way.
- **Privacy:** the other player gets a pop-up when someone relocates to them, and can untick "Let other players relocate
  to me" (kept on their PC in `mp/prefs.json`, for every server). A player on foot, in a helicopter or the sightseeing
  car, or not yet back at their save answers no, so nobody lands under a helicopter.

## While you were away (built)

MadMerick, 12 Nov: a card on joining that says what happened while you were off the server.

- The server keeps `careers/season-N/away.json` by career key: when the player left and their leaderboard place then,
  turf tolls paid to them while they were off (total, deliveries, and how much each payer paid), and up to 10 lines of
  corp news (a request to join, a member leaving, being let in, turned down or removed).
- On a full join (not a quiet rejoin after a lost connection) it sends `wwtcAway { since, place, was, of, tolls, news }`
  and clears the record. A player away under 15 minutes with no tolls or news gets nothing.
- The game shows it on the HUD under the money once the player is back at their save, with Ship Day from what the game
  already knows, until **Got it**. The tolls themselves still arrive as the usual commission batch.

## Later steps (agreed in principle, not scheduled)

- **Shared job boards and town need.** Boards are now seeded by the player's own delivery count (`jobsDone`), so two
  players in one town see different jobs. Seed them from a per-town counter on the server instead, and keep town need on
  the server, so a delivery lowers the pay for everyone. Shortages already match for everyone (they come from the clock
  hour and the town). **Decided (MadMerick, 8 Nov): not yet.** A job one player takes stays on everyone's board for now.
- **Multiplayer HUD section.** "Sync my truck" only if testing shows BeamMP desyncs after our respawns.
- **Server page (first version built, 8 Nov):** a GitHub Pages site in `site/` (MadMerick: the server runs on their PC, GitHub Pages shows the info). It reads `status.json`, which the server plugin builds (who's on by town, Ship Day, feed, today's totals, leaderboard; the game reports its town and deliveries with `wwtcWhere`/`wwtcDelivered`) and sends every 3 minutes to its own `trucking-server-stats` repo with a fine-grained token kept in `github-token.txt`. A marked sample shows until it does.
- **Webpage and Discord.** The server writes a stats file; a Discord webhook posts the live delivery feed and a daily
  leaderboard first, then a page on a free static host (online now by town, leaderboards, server totals, Dangerous
  Contract best times). Nothing is served from MadMerick's PC.
- **Admin commands** in the server window (`players`, money fixes, kick).
- **Co-op play:** player tows and roadside fuel first, then leaderboards, convoys, relay runs, player-to-player trading,
  companies.

## To find out in the first test

Run with the mod as it is today (careers still on each PC) and one friend, and watch:

- Repairs, part changes and sightseeing respawn the car (`core_vehicles.replaceVehicle`): do other players see it
  correctly?
- Hitching a trailer spawns a second vehicle: needs `MaxCars` of at least 2 (3 recommended).
- Teleport, Relocate and Teleport to last save put the player in their own world: does Earth bring them back into
  sight when they meet again?
- The Insert key and BeamMP's own reset: does the mod still catch a free repair?
