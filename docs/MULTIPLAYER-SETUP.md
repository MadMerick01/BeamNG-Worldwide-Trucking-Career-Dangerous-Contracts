# Hosting a Worldwide Trucking server

This sets up a BeamMP server running BeamNG.Earth with the trucking career, where **each player's career is kept on the
server**. Everyone keeps their own truck and money, separate from their single-player career. The server needs
little power: every player's own BeamNG.Earth app builds the world around them.

## What you need

- A PC that stays on and doesn't sleep while the server runs. Your own gaming PC is fine, and you can play on it at the
  same time.
- A free BeamMP AuthKey from [keymaster.beammp.com](https://keymaster.beammp.com).
- Two downloads:
  - **BeamNG.Earth's host zip**, `BeamNG.Earth-Host-<version>-Windows.zip` (or `-Linux-x86_64.zip`), from
    [BeamNG.Earth's releases](https://github.com/TecnaGamer/BeamNG.Earth/releases). It includes the BeamMP server
    program. Use the same version as the BeamNG.Earth app you play with.
  - **`worldwide-trucking-server.zip`** from this mod's [latest release](../../releases/latest).

## Setting it up

1. **Unzip BeamNG.Earth's host zip** into a folder of its own, for example `C:\TruckingServer`.
2. **Unzip `worldwide-trucking-server.zip` into the same folder.** Its `Resources` folder merges with the one already
   there. It adds:
   - the trucking server plugin, `Resources\Server\WorldwideTrucking\main.lua`;
   - the mod itself, `Resources\Client\worldwide-trucking-dangerous-contracts.zip`, which BeamMP sends to every
     player who joins.
3. **Edit `ServerConfig.toml`** in Notepad:

   ```toml
   Map = "/levels/beamng_earth/info.json"
   Name = "Worldwide Trucking Career"
   Port = 30814
   MaxPlayers = 8
   MaxCars = 3        # your truck, its trailer and one spare
   Private = true     # Direct Connect only; false lists it in the BeamNG.Earth tab of the server browser
   AuthKey = "your key"
   ```

4. **Change two lines in `Resources\Server\BeamNGEarth\main.lua`** (BeamNG.Earth's plugin):
   - `G.MEET_M = 3000` to `G.MEET_M = 100000000`. As it comes, BeamNG.Earth teleports a joining player to whoever is
     already on. In the career, that would pull a trucker off their job.
   - `G.SHARE_OUT_KBPS = 1024` to `G.SHARE_OUT_KBPS = 256`, to keep your upload free for your own online games.
5. **Stop the PC sleeping.** On Windows: Settings, System, Power (or Power & sleep), and set sleep to **Never**. The
   screen can still turn off.
6. **Open the port** for players over the internet: forward port 30814, **TCP and UDP**, in your router to this PC, and
   allow `BeamMP-Server.exe` through the firewall when Windows asks. Players on your own network need nothing.
7. **Start `BeamMP-Server.exe`.** The window should show both `[BeamNG.Earth] plugin loaded` and
   `[Trucking] plugin loaded`.

To start the server by itself after Windows restarts for an update, put a shortcut to `BeamMP-Server.exe` in your
Startup folder (press Win+R and type `shell:startup`).

## Joining

- Every player needs the **BeamNG.Earth app** running, the same version as the server. The trucking mod comes from the
  server by itself.
- In BeamMP's server browser, use **Direct Connect**: `127.0.0.1` from the server's own PC, or the host's public
  address (search "what is my IP" on the host PC) and port 30814 from anywhere else.
- On joining, the HUD says **Getting your trucking career from the server** for a few seconds, then loads your career
  on this server, or starts a new one.
- **First time only: turn on the trucking HUD.** The mod comes from the server, but its HUD is a UI app each player
  adds to their screen once: press Esc, go to System > HUD Apps > .Earth (edit layout), press + Add app, pick
  **BeamNG Worldwide Trucking Career: Dangerous Contracts** near the bottom of the list, press + Add to layout and
  Save. The server also posts these steps in chat to each player as they join (anyone can type `!hud` to see
  them again), and a player without the HUD gets a pop-up with them after about 20 seconds. To change the chat
  message, edit the `W.WELCOME` lines near the top of `Resources\Server\WorldwideTrucking\main.lua` and restart.
- **Everyone plays the server's build of the mod.** A player whose game runs an older copy (their own download, or
  one from BeamNG.Earth's Add-ons page, loaded instead of the server's) is sent off as they join, with a message
  saying which builds and how to fix it: turn off their own copy in the Mod Manager and on the Add-ons page, close
  BeamNG completely and join again. Their career isn't touched. The server window says who was sent off. To let older
  copies play, set `W.REQUIRE_LATEST = false` near the top of `main.lua`. The check needs a server download from build
  161 or later (it holds `build.txt` next to `main.lua`).

## Careers, guests and seasons

- **Signed-in BeamMP players** get their career back on any PC.
- **Guests** get their career back on the same PC. The game keeps a career key for each server in
  `settings/earthFreight/mp/keys.json` in the BeamNG user folder; deleting it, or joining from another PC, starts over.
- **Single-player careers are never touched.** A multiplayer career lives in its own folder.
- **Every Save goes to the server.** If the server refuses one, the HUD says why; press Save to try again.
- **New season:** open `Resources\Server\WorldwideTrucking\main.lua`, raise `W.SEASON = 1` by one and restart the server.
  Everyone starts over in the rusty starter car with the starting money on their next join. The old season's careers
  stay in `careers\season-1`.
- **Who's on:** type `trucking` in the server window to list players and their money at their last save.

## Ship Day

Every day a ship docks at the next port on the server's list with 5 containers of high-value cargo. Everyone
hears about it in chat, and the **Town** tab shows a **Ship Day** card: the ship, its port, how long until it sails and
every container with its destination and pay.

- **Go to port (free)** takes an empty car to the town by the docks. It always lands on the town centre, never on the
  port's own coordinates, so nobody lands in the water.
- At the port, press **Take** on a container. First come, first served: the server decides who gets it, and everyone
  sees it as taken. One container at a time. The **Load** slider above the containers picks how much of a
  full load to take, 10% to 100%, like the town job board, and the pay shown changes with it.
- Drive it to its town, 15 to 70 km inland, and press **Deliver** as usual. Everyone sees the delivery in chat.
- Abandoning a container gives it back for someone else.

To change it, edit the settings at the top of `Resources\Server\WorldwideTrucking\main.lua` and restart:

- `W.SHIP_START`: when the first ship docks (this PC's time). `W.SHIP_EVERY_HOURS`: hours between ships (24).
- `W.SHIP_CONTAINERS`: containers per ship (5). Set it to 0 to turn Ship Day off.
- `W.PORTS`: the ports, in order. Each has a name, region and coordinates; keep the coordinates on the land side of
  the port. `W.SHIP_NAMES`: the ships' names.

## The server page

A public page shows what's happening on the server: who's driving and in which town, Ship Day with its countdown and
containers left, a live feed, the season leaderboard and how to join. It is in this repo's `site` folder and GitHub
Pages hosts it for free, so nothing is served from your PC.

**Turn it on once:** on GitHub, open the repo's **Settings > Pages**, and under **Build and deployment** set **Source**
to **GitHub Actions**. The next change to `site` on main publishes it (or run the **Server page** workflow by hand from
the **Actions** tab). The page is then at `https://madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts/`.

Until the server sends its own stats, the page shows **sample data**, marked as such.

**Send the live stats (once):** the server sends `status.json` every few minutes to a small repo of its own, so the
token on your PC can't touch the mod's repo.

1. On GitHub, create a new **public** repository called **`trucking-server-stats`**, with **Add a README** ticked so it
   has a `main` branch.
2. Make a token: open [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
   (fine-grained token). Give it a name, an expiry (a year is fine), **Repository access: Only select repositories**,
   pick `trucking-server-stats`, and under **Permissions > Repository permissions** set **Contents** to **Read and
   write**. Generate it and copy it.
3. Paste the token, alone, into a new file `Resources\Server\WorldwideTrucking\github-token.txt` and save it. Never
   share it or put it in `main.lua`.
4. Restart the server. Within a few minutes `status.json` appears in the stats repo and the page shows the live
   server: who's on and in which town, Ship Day, the feed and the leaderboard. If GitHub refuses the stats, the server
   window says why.

Players are only ever shown by town. The stats are also written to `Resources\Server\WorldwideTrucking\status.json`.
If you name the stats repo differently, change `W.STATS_REPO` at the top of `main.lua` and the first address in
`site/index.html`; set `W.STATS_REPO = ''` to send nothing.

## Updating

**The easy way:** double-click `update-server.bat` in the server folder. It updates BeamNG.Earth and the trucking mod,
warns players, saves everyone, backs up, keeps your settings and rolls back if the new version doesn't start. It can
also run every night by itself. [SERVER-UPDATES.md](SERVER-UPDATES.md) explains it.

By hand:

- **The mod:** unzip the new `worldwide-trucking-server.zip` over the old one and restart the server. Players get the
  new mod when they next join.
- **BeamNG.Earth:** unzip its new host zip over the old one, redo step 4 (the update replaces its `main.lua`), and
  restart. Everyone must update their BeamNG.Earth app to match.

## Back up the careers

All careers are in `Resources\Server\WorldwideTrucking\` (the `careers` folder, `accounts.json` and `server.json`).
Copy that folder somewhere safe now and then. If `server.json` is lost, the server gets a new identity, and guests'
games no longer find their careers on it.
