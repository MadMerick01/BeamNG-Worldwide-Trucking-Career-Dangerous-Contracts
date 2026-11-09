# Updating the trucking server

When BeamNG.Earth or the trucking mod has a new release, one script updates your server: **`update-server.bat`**, in
your server folder (for example `D:\WWTruckingCareerOnline`). Double-click it, or let Windows run it every night.

Single player needs none of this: the BeamNG.Earth app and the mod update themselves there.

## What it does

1. **Checks GitHub** for a newer BeamNG.Earth host zip and a newer `worldwide-trucking-server.zip`. If there's nothing
   new, it says "Up to date" and stops. Nothing else happens.
2. **Gets everything ready while the server keeps running.** It downloads and unzips the new files into a staging
   folder, puts your BeamNG.Earth settings (`G.MEET_M = 100000000` and `G.SHARE_OUT_KBPS = 256`) back into
   BeamNG.Earth's new `main.lua`, and puts your trucking settings (the season, the welcome lines, Ship Day and the
   server page settings) back into the new trucking `main.lua`. If anything looks wrong, such as BeamNG.Earth
   renaming a setting, it stops here and the server is never touched.
3. **Warns everyone.** Players get a message in chat ("The server restarts for an update in 10 minutes"), again at 5,
   2 and 1 minutes, and on Discord if you've set that up. A minute and a half before the restart, every player's game
   saves itself, so they lose next to nothing. At the time, everyone is sent off with "The server is updating. Your
   career is kept. Join again in a few minutes." With nobody on, it skips the wait.
4. **Stops the server and backs it up.** The whole server folder, careers included, is copied to a dated folder in
   `D:\WWTruckingCareerOnline-backups`. The newest 5 backups are kept and older ones deleted.
5. **Copies in the new files and starts the server.** It never replaces `ServerConfig.toml` (your AuthKey and server
   name), `update-settings.json`, the careers or BeamNG.Earth's road store.
6. **Checks it worked.** It waits for both `[BeamNG.Earth] plugin loaded` and `[Trucking] plugin loaded` in the
   server's log. If either doesn't show within 2 minutes, it **puts the backup back and starts the old version**, and
   says so on Discord. The worst case is that the server stays on the old version.
7. **Tells everyone it's back**, on Discord: "The server is back up with BeamNG.Earth 1.9.1-beta. Update your
   BeamNG.Earth app to 1.9.1-beta before joining." The trucking mod needs nothing from players, because the server
   hands it out when they join.

Careers are safe throughout. They live on the server, an update never changes them, and they're in every backup.

## Setting it up (once)

1. Download the newest `worldwide-trucking-server.zip` and unzip it over your server folder, as for any trucking
   update. This puts `update-server.bat`, `update-server.ps1`, `update-settings.example.json` and this guide in the
   server folder. After this once, the script keeps itself up to date.
2. Double-click `update-server.bat`. The first time, it makes **`update-settings.json`** from the example, and since
   it doesn't yet know which versions your server has, it updates both to the newest. That's a good first test: do it
   when nobody's on.
3. Optional, **Discord**: in your Discord server, open the channel's settings, then Integrations > Webhooks > New
   Webhook, and press Copy Webhook URL. Paste it between the quotes of `"DiscordWebhook": ""` in
   `update-settings.json` (open it in Notepad). **Keep this file private.** Anyone with the webhook can post in that
   channel. It isn't in any download and updates never overwrite it.

If Windows says scripts are blocked, run the `.bat`, not the `.ps1`: the `.bat` starts it with permission to run.

## Running it

- **Double-click `update-server.bat`.** The window shows each step and waits for a key at the end.
- **From your phone:** install Chrome Remote Desktop on the PC (remotedesktop.google.com, free) and its app on your
  phone. Connect, open the server folder, and double-click `update-server.bat`.
- **Every night, by itself:** open PowerShell in the server folder (Shift + right-click in the folder, Open PowerShell
  window here) and run:

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\update-server.ps1 -Schedule 05:00
  ```

  Windows then checks every day at 5 am and updates only when there's something new, with the usual countdown. The PC
  must be on and you must be signed in to Windows at that time. To stop it: the same line with `-Unschedule`.

Other options, typed after `update-server.bat` in a Command Prompt or after the `.ps1` in PowerShell:

| Option | What it does |
| --- | --- |
| `-CheckOnly` | Only says what's new. Changes nothing. |
| `-Now` | No countdown. Players get about 15 seconds' warning. |
| `-Minutes 30` | A 30 minute countdown this time. |
| `-Force` | Updates even when nothing is new, for example to repair the server. |

To call off an update during the countdown, press **Ctrl+C** in its window. Players are told in chat that it's off.

## Settings (`update-settings.json`)

| Setting | What it does |
| --- | --- |
| `DiscordWebhook` | Your Discord webhook address, or `""` for no Discord posts. |
| `WarningMinutes` | How long the countdown is (10). |
| `KeepBackups` | How many dated backups to keep (5). |
| `ServerFolder` | Your server folder. `""` means the folder the script is in. |
| `BackupFolder` | Where backups go. `""` means next to the server folder, ending `-backups`. |
| `UpdateEarth`, `UpdateTrucking` | `false` leaves that one alone. |
| `EarthDevBuilds` | `true` also takes BeamNG.Earth's development builds. Leave it `false`: most players don't run them. |
| `EarthMinAgeHours` | Waits until a BeamNG.Earth release is this many hours old, in case a quick fix follows it. `0` updates straight away. |
| `EarthSettings` | Lines put back into BeamNG.Earth's `main.lua` after every update. Add any other `G.` setting you change, such as `"G.TIME": "'20:30'"` (text values keep their single quotes inside). |
| `StartSeconds` | How long to wait for the server to start before rolling back (120). |
| `MustSeeInLog` | The lines that show a good start. |

Settings you change at the top of the trucking plugin's `main.lua` (`W.SEASON`, `W.WELCOME`, the Ship Day settings and
`W.STATS_REPO`) are kept by every update without any setting here. The GitHub token for the server page is in its own
file, `github-token.txt`, which updates never touch.

## Good to know

- **Players need the same BeamNG.Earth version as the server.** After a BeamNG.Earth update, anyone still on the old
  app can't join until they update it. The Discord post says which version to get. A nightly update means the server
  follows a new BeamNG.Earth release within a day. If you'd rather give players time, set `EarthMinAgeHours` to `24`.
- **BeamMP updates come with BeamNG.Earth.** The host zip includes the BeamMP server, so updating BeamNG.Earth updates
  it too. Players' BeamMP launcher updates itself.
- **The log of every update** is in `update-log.txt` in the backups folder. A failed start's server log is saved there
  as `failed-<date>.log`.
- **To go back to a backup by hand:** stop the server, copy the dated backup folder's contents over the server
  folder, and start it again.
- **Restarts:** the server starts with Windows if there's a shortcut to `BeamMP-Server.exe` in your Startup folder
  (press Win+R and type `shell:startup`). Without it, a Windows Update restart leaves the server off until you start
  it.
- **Big updates:** to try a new version first, unzip it into a second folder with its own `ServerConfig.toml` on
  another port (such as 30815), join it yourself, then update the real server.
