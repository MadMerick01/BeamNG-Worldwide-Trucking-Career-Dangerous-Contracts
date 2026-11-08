# What's changed

Every change to BeamNG Worldwide Trucking Career: Dangerous Contracts (formerly Earth Freight Sim), in plain English, newest first. Each build is a new download on the [Releases](../../releases/latest) page.

## Coming next

Changes that are finished but not in a download yet. They move into a numbered build as soon as it's published.

- **Ship Day on trucking servers.** Every 3 days a ship docks at a port somewhere in the world, such as Valparaíso, Reykjavík, Hobart or Cape Town, carrying 20 containers of high-value cargo. The server announces it in chat, and a new **Ship Day** card at the top of the **Town** tab shows the ship, when it sails and every container with where it goes and what it pays. Press **Go to port (free)** to take your empty car to the town by the docks (always on land), then **Take** a container. It's first come, first served, one at a time, and everyone sees which are gone. Drive it 15 to 70 km inland and deliver it as usual for well above normal pay, and the whole server hears about it in chat. Abandoning a container frees it for someone else. Server hosts get the new plugin by unzipping the new server download over their server folder; ports, timing and the number of containers are settings at the top of the plugin. Careers and saves carry on as before. Single player is unchanged.

## Build 153 · 8 Nov 2026

- **Trucking servers now greet each player in chat** with how to turn on the trucking HUD. Anyone can type **!hud** in chat to see the steps again; only they see the answer. Server hosts can change the welcome lines at the top of the server plugin. To get this, unzip the new server download over your server folder and restart it. Careers are unaffected.

## Build 152 · 8 Nov 2026

- **If the trucking HUD isn't on your screen, a pop-up now tells you how to add it.** This mostly helps players joining a server, who get the mod automatically but have never added its HUD. About 20 seconds into BeamNG.Earth without the HUD, a pop-up gives the steps: Esc, System, HUD Apps, .Earth (edit layout), + Add app, then pick BeamNG Worldwide Trucking Career: Dangerous Contracts and Save. It shows up to three times, a few minutes apart, and never once the HUD has been on screen. Saves are unaffected.

## Build 151 · 8 Nov 2026

- **Joining a trucking server now gives you a car.** BeamMP drops you in as a free camera with no vehicle, so the HUD sat waiting until you spawned one yourself. Now, a few seconds after your career arrives, the rusty starter Burnside is put down where you are and you're put in it. From there, Start here or Teleport to last save works as usual, and your own truck is handed over when you reach your save. Single player is unchanged.

## Build 150 · 8 Nov 2026

- Fixed: a new trucking server no longer shows two "string given to JsonDecode is not valid json" errors in its window when it starts. They were harmless: the server was looking for its own files before it had made them.

## Build 149 · 8 Nov 2026

- **Flat tyres happen about a quarter as often.** On the road at normal speed you now get a puncture roughly once every 160 km instead of every 40 km. Driving fast and going off road still raise the chance as before, and a burst tyre still costs the same to fix. Your saves still work.

## Build 148 · 8 Nov 2026

- **Multiplayer careers on BeamMP servers.** On a BeamNG.Earth server running the new Worldwide Trucking server plugin, your career is kept on the server: when you join, the HUD says "Getting your trucking career from the server" for a few seconds, then loads your truck and money there, or starts you a new career. Every Save goes to the server. Your single-player career is never touched, and you get it back as it was when you play alone again. Signed-in BeamMP players get their career on any PC; guests get theirs back on the same PC. On a server without the plugin, your multiplayer career is saved on your PC, still apart from your single-player one.
- Hosting a server? Each build now also comes with `worldwide-trucking-server.zip`: unzip it into your BeamMP server folder, next to BeamNG.Earth's host files. `MULTIPLAYER-SETUP.md` inside it explains the setup, starting a new season (everyone back to the rusty starter car) and the `trucking` command that lists who's on.

## Build 146 · 8 Nov 2026

- No changes in the game. A new design document plans a multiplayer version of the career on BeamMP servers.
- No changes in the game. The notes now name the author as MadMerick.

## Build 145 · 7 Nov 2026

- **BeamNG's own tanker trucks now count as fluid space.** Before, only a Cargo Load fluid tank fitted in the parts menu counted, so a tanker you bought showed no tank and couldn't take water or fuel jobs. Now the game asks your truck how much its tank holds a moment after you get in, and the Garage tab shows it as "Built-in tank" with its size in litres. Water and fuel are poured into the tanker's own tank, so they slosh. Your saves still work.

## Build 142 · 5 Nov 2026

- **Pressing Pay on the parts bill no longer closes the parts menu.** Closing it for you left you stuck in the free camera, so it's back to how it was: Pay just pays, and you leave the parts menu yourself to get back to your car on your usual camera. Your saves still work.

## Build 141 · 5 Nov 2026

- **Long jobs now go up to 300 km.** Pick **Long** on the Town tab's **Distance** filter and the three town jobs go to towns anywhere from 13 km to about 300 km away by road, instead of stopping at 20 km. The distances are spread out, so you will see a mix of 50 km, 150 km and 250 km runs rather than only the farthest ones. This helps most in places where towns are far apart, such as mountain regions, where you used to be stuck between the same two towns until you relocated. **Any**, **Short** and **Medium** work as before, and your saves still work.

## Build 140 · 5 Nov 2026

- **Street View has its own tab.** The new **Street View** tab on the HUD holds everything for it: **Turn on** and **Turn off**, **Open again** if you closed the browser page, and the address with its **Copy** button. **Go sightseeing** has moved there too, with a short note on how it works. The space above the tabs is clearer: while Street View is on it just shows a small green **Street View on** button that takes you to the tab. While you are sightseeing, the tabs are hidden as before, so the sightseeing panel has its own **Turn on Street View** button. The tabs now sit in two rows, with Route, Town, Garage and Relocate on top and Heli, Home and Street View below, so every name fits at full size. Your saves still work.

## Build 139 · 5 Nov 2026

- **Town jobs now end at a real business.** When you take a job to a town, the HUD looks up one real business there that suits your load on OpenStreetMap: a builders' merchant or hardware store for bricks, a car parts shop or garage for parts, a farm or garden centre for water, a fuel station for fuel. The job card shows its name, such as "Bunnings Warehouse, St Clair", and the GPS takes you to the road right outside it. In the last 500 m the card counts down the metres, and you deliver by stopping within **25 m** of the spot. Each town keeps the same business for that load, for every player, so you can get to know your regular stops. Pay is the same as before.
- If no suitable business is found, or the game can't reach the internet, the job ends in the middle of town as it always has. Off-road drops and dangerous contracts are unchanged. Your saves still work, and a town job you are already carrying gets its business the same way.

## Build 138 · 4 Nov 2026

- **Street View's update rate is now your choice.** Open **Settings** on the Street View page and pick **6 s**, **10 s** or **20 s** under **Update every**. 10 seconds is still the default, and your pick is remembered next time you open the page. A new picture is only fetched once the truck has moved or the view has turned, so a faster rate uses no extra data while you are parked; on the highway, 6 seconds uses roughly 600 MB an hour and 20 seconds about a third of that. Your saves still work.
- **The Street View address now has a Copy button.** When Street View is on, the HUD shows its address in a box with a **Copy** button, the same way the coordinates of your last save work, so you can paste it into any browser. The game no longer copies the address on its own when you press **Street View**.

## Build 137 · 4 Nov 2026

- **Street View now looks where your camera looks.** Turn the orbit camera 90 degrees to the left and, at the next 10-second update, Street View turns to face the same way, even when the truck is standing still. In the driver's camera it faces the way you are driving, as before. The **Camera** button next to the zoom buttons switches to **Truck**, which always faces the way the truck points; your choice is remembered.
- **Street View now starts one step zoomed in, with zoom buttons on the picture.** A small window over the game looks more like your view from the cab. The **−** and **+** buttons sit in the top-left corner of the picture, so they come with it into the **Pop out** window too. Your zoom is kept for every picture after, and next time you open the page. This was meant to arrive with sightseeing but missed that build. In the Pop out window, the town and street line no longer covers the top of the picture. Your saves still work.

## Build 136 · 4 Nov 2026

- **The locals no longer shoot at your truck.** The hits could make your car unstable enough that the game put you back at your last save, so the shooting, its gunshot sound and the **Start shots in 5 s** test button on the Garage tab are gone. Your saves still work.

## Build 135 · 4 Nov 2026

- **Go sightseeing.** A new **Go sightseeing** button sits under the **Street View** button. Press it while stopped in your own car and the game saves first, then swaps your truck for a free black Moonhawk right where you are. Use the BeamNG.Earth map to teleport anywhere you like and look around, with Street View following you. While you are sightseeing the HUD shows a sightseeing panel instead of the tabs: there are no jobs, fuel bills, punctures, locals or crash bills, and nothing costs money. Press **Return to your job** and you are teleported back to your truck, with your job, money, fuel and damage just as you left them. Your saves still work.

## Build 134 · 4 Nov 2026

- **Street View can now float on top of the game.** On the Street View page, press **Pop out** and Street View moves into a small window that stays above the game, so it no longer disappears when you click back into BeamNG. Drag it wherever you like and resize it; it still follows your truck every 10 seconds. Close it, or press **Bring it back here**, to put it back in the browser tab. This needs Chrome or Edge, and BeamNG set to **Borderless** or **Windowed** in its display options, because nothing can sit on top of true fullscreen. Your saves still work.

## Build 133 · 4 Nov 2026

- **The Street View button now opens your web browser.** Before, pressing it started Street View but no browser window came up. Now the page opens in your normal browser, and the address is also copied so you can paste it in if your browser still doesn't appear. The HUD shows the address under the button too. Your saves still work.

## Build 132 · 4 Nov 2026

- **Street View of where you are, in your web browser.** Press the new **Street View** button on the HUD, next to your distance driven, and a page opens in your normal web browser showing Google Street View of the spot your truck is on, facing the way you are driving. Every 10 seconds it catches up with the truck, so you can keep it on a second screen as you drive. It also shows the street, town and coordinates, and has **Map** (an overhead satellite view), **Pause** (stop following so you can look around) and **Google Maps** buttons. Press **×** next to the button to turn it off. Once used, it comes back by itself next time you play, so a tab you left open carries on.
- Street View only exists where Google has photographed the road, so off the road or somewhere remote the picture may be blank. For a better result there, open **Settings** on the page and paste in a free Google Maps key: the page then shows the nearest photo within 5 km, tells you how far away it is, and switches to the map when there is none. The key is kept in your browser only.
- The page lives on your own computer at http://127.0.0.1:47170 and nothing outside your computer can reach it. Your saves still work.

## Build 131 · 4 Nov 2026

- **You can now hear the locals shooting.** A distant gunshot rings out with each shot.
- The locals' shots hit half as hard again as before. They dent deeper and knock the truck harder. Your saves still work.

## Build 130 · 4 Nov 2026

- **Locals may shoot at your truck in rough country.** Where the HUD shows rough roads ×1.4 or more, now and then someone opens fire from a spot off to your left or right. The HUD says **HIT THE GAS, THE LOCALS ARE SHOOTING AT YOU** and a short burst of shots follows. Not every shot hits, and the ones that do dent the body and can flatten a tyre. The shooter stays put, so the way out is to keep driving. With a "Don't ask questions" job on board it happens twice as often. Damage and flat tyres go on the normal repair on the Garage tab, with no other cost. There's no gunshot sound yet.
- For testing, the Garage tab has a **Start shots in 5 s** button that starts the shooting five seconds after you press it, wherever you are. It will be removed once the hits feel right. Your saves still work.
- **Dangerous contracts stay in rotation after you deliver them.** Before, each road could only be driven once per game, and once you had done them all the town boards stopped offering any. Now every road keeps coming round on the boards, so there is always a dangerous contract to pick and you can drive your favourites again. The **Dangerous** count on the career page still shows how many different roads you have delivered. Your saves still work, and roads you had already finished come back onto the boards.

## Build 128 · 4 Nov 2026

- **You can buy a home, and own two cars.** The new **Home** tab lets you buy the spot where you're parked for $250,000. Your home keeps a second car for you. You only get one home, and it can't be moved or sold.
- When you buy a new or second-hand car and your home has room, the bill now has two buttons. **Trade in** works as before. **Keep and store at home** charges the full price with no trade-in and sends your old car home with its parts, fuel and damage. The second-hand list also shows both prices.
- Within 200 m of your home, **Swap cars** on the Home tab swaps the car you're driving with the one at home. Each car keeps its own parts, fuel, wear and the repairs it still needs. You can't swap with a job on board or a bill open.
- **Repairs are half price within 200 m of your home.** That covers the Repair button and the repair part of a parts bill.
- Relocate lists **Home** at the top, at the usual relocation fee.
- Your saves still work. A home is kept by Save like your money, and the game saves itself after you buy one or swap cars.

## Build 127 · 4 Nov 2026

- **Your truck is on the start page as soon as you load your game.** The Your truck card now shows the car from your last save straight away, with its name, picture, what it's worth, any repair it needs and its cargo space, before you've even driven back to it. It used to stay empty until you got there.
- Buying another car of the same model no longer shows the old car's photo on the start page. You see the new car's picture until its own photo is taken. A new game also clears the photo of the car you had before.
- Your car keeps its full name after you load a save. Saves from earlier builds still work. Their name comes back the next time you press Save.

## Build 126 · 3 Nov 2026

- **After you press Pay on the parts bill, you're back on your normal camera.** The parts menu closed itself but left you in the free camera, so you had to press Shift+C to get back. Now you return to the camera you were driving with. Your saves still work.

## Build 125 · 3 Nov 2026

- **Choose my start on the map now opens the BeamNG.Earth map for you.** On a new game, pressing it on the start page closes the page and opens Earth's world map, so you can teleport anywhere and press **Start here** on the HUD. If the map doesn't open, press M. Your saves still work.
- **The starter Burnside Rusty has a new picture again,** on the start page's **Your truck** card and in BeamNG's vehicle menu. Your saves still work.

## Build 124 · 3 Nov 2026

- **Buy new trailer now offers just two trailers built for freight**, instead of every trailer in the game (log carriers and the like). One is a small utility trailer with two XL cargo boxes for parcels, the other the same trailer with two XL fluid tanks. Both cost $6,000 and take a ball hitch. More will be added later.
- A trailer you already own stays yours, even if it's no longer in the list, and your saves still work.

## Build 123 · 3 Nov 2026

- **You can now fit cargo boxes and fluid tanks to your trailer.** With your trailer out, press **Buy trailer parts** in the Trailer section of the Garage tab. You're put in the trailer and the parts menu opens, so you can fit boxes or tanks to any trailer that has room for them, such as a flatbed. The bill shows up on the Trailer card and is priced like car parts. Press **Pay** to keep the parts, or **Undo** to put the old ones back, and either one puts you back in your car. Back up to the trailer to hitch it again. The new boxes add to the trailer's cargo space.
- Before, a bare flatbed carried nothing. Now its cargo space comes from the boxes and tanks you fit to it.
- You can't take a job, save or relocate until you've paid for or undone the trailer parts. You also need to deliver or abandon your job before you start. Save keeps your trailer's parts, and your saves still work.

## Build 121 · 3 Nov 2026

- **New players are now told to fit cargo boxes.** The starter car only has its boot, which holds 2 slots, so its jobs pay very little. The **How to play** steps on the start page now say to fit **Cargo Load** boxes in the rear seat slot with **Buy parts**, right after the radiator. While your car only has its boot, the **Town** tab also shows a gold line saying so, with its own **Buy parts** button. Your saves still work.
- **A new game now starts with $6,000 instead of $2,500**, enough for the radiator, fuel and a few cargo boxes. Games already under way keep the money they have; pressing **New game** gives you the new amount.
- **All cargo is 15% lighter.** Parts now weigh 12.75 kg a unit instead of 15, bricks 127.5 kg instead of 150, water 8.5 kg per 10 L and fuel about 6.4 kg per 10 L. Jobs still pay what they did for the same number of units, and because bricks are lighter a cargo box fits more of them, so brick jobs in a full box pay a little more. A single brick now fits in one **Cargo box M**. A job you have already taken keeps its old weight until you deliver it. Your saves still work.

## Build 120 · 3 Nov 2026

- **A new game no longer carries over your old repair bill.** Before, if your truck was damaged when you pressed **Yes, start over**, the teleport to your start counted that damage as still owed, so the fresh starter car arrived with the old game's repair on the **Garage** tab and a "Repair still owed" warning. Now the new game starts with nothing to pay, and any open parts or car bill from the old game is cleared too. Your saves still work. If a new game you already started is showing the old bill, press **New game** and **Yes, start over** again once you're on this build.

## Build 119 · 3 Nov 2026

- **Pressing Pay on the parts bill now closes the parts menu and puts you back in your car,** ready to drive. If the payment doesn't go through, the menu stays open so you can change your parts or undo them. Your saves still work.

## Build 118 · 3 Nov 2026

- **The Your truck card on the start page now shows a photo of your own truck.** A few seconds after you pay for parts or buy a car, once you're standing still with the HUD showing, the game takes a photo of your truck as it is, the same way the parts menu's Save does. Until your first upgrade, the card shows the car's normal picture.
- The photo is kept as one config called earth_freight_my_truck in your BeamNG vehicles folder, and each new photo writes over it. You'll see it in BeamNG's vehicle menu, but not in **Buy new car**. When you change to a different car model, the old photo is removed once the new one is taken, and a new game clears it too. Your saves still work.
- **The starter Burnside Rusty has a new picture,** on the start page's **Your truck** card and in BeamNG's vehicle menu. Your saves still work.

## Build 117 · 3 Nov 2026

- **The start page now opens in a big window in the middle of the screen,** like a real game's title screen. The HUD hides while it's open and comes back when you press **Back to the road**, which replaces Continue. If you had the HUD minimised, it stays minimised.
- **Your truck is on the start page,** like a character in a role-playing game: its picture, name, what it's worth, its condition with any repair it needs, the fuel in its tank, its cargo space and your trailer. A marker on the **Rust Bucket ▶ Rig** line shows how far your truck has come, from the starter Burnside to a rig worth $100,000 or more.
- **Your career is on the start page too:** your money, the km you've driven, the jobs you've done and how many of the dangerous roads you've driven.
- On a new game, **Choose my start on the map** closes the page so you can open the BeamNG.Earth map, teleport anywhere and press **Start here** on the HUD. **Teleport to last save** also closes the page, so you can watch the world load.
- A parts bill, an insurance offer or being stranded closes the start page, so you can deal with it straight away. Parts bills and beacons still show on top of the page. Your saves still work.

## Build 116 · 1 Nov 2026

- **Trailers are here.** On the Garage tab, open the new **Trailer** section and press **Buy new trailer** to see every trailer in the game at its full price. Pick one, press **Buy**, and it's paid for straight away and put down behind your car. Back up to it slowly and it hitches itself, or use the game's couple key. You can own one trailer at a time.
- You need the right hitch on your car to pull a trailer. Small trailers take a ball hitch and semi trailers a fifth wheel. Fit one with **Buy parts** like any other part.
- While your trailer is hitched, its cargo space adds to your car's, and jobs on the Town tab fill the trailer first, then your car. The trailer carries the weight, so a full trailer really pulls. A trailer that isn't hitched adds no space, and if part of your job is in it you can't deliver until you hitch it again. Dangerous contracts only load your car, because their teleport leaves the trailer behind.
- **Store trailer** puts it in your garage for free, so you can drive just your car or truck. The garage goes everywhere with you: press **Bring out** in any town, any time, and it's put down behind you again. If part of your job is in the trailer, Store trailer first warns you in red, and storing it then loses your whole load and costs the $1,000 abandon fee.
- A trailer keeps its damage. If you store it damaged it stays damaged: **Repair trailer** fixes it, and **Sell** (on a stored trailer) pays 75% of what you paid, less any repair it needs.
- Save keeps your trailer, hitched or in the garage, and **Teleport to last save** puts a hitched trailer back behind your car. Save asks you to hitch your trailer or store it first if it's standing on its own. Teleporting or relocating puts the trailer in your garage. Hire a helicopter only once your trailer is stored.
- A trailer spawned from the game's own vehicle menu can still be towed, but it isn't yours, so it adds no cargo space.
- Your saves still work. If you buy a trailer and then go back to an older download, the older one won't know about it, and you'll lose the trailer the next time you save.

## Build 115 · 30 Oct 2026

- **The distance left to your drop-off is now big and easy to read.** While you have a job, the job card under your money shows how far you still have to go, such as "2.5 km", in type nearly as large as your money. Under 1 km it counts down in metres. This works for town deliveries, off-road drops and dangerous contracts. Your saves still work.
- **No more repeated job message under Abandon job.** After you take a job, the HUD no longer adds a line like "Loaded 2 bricks (300 kg) for Servoz. It pays $4,490 on delivery." at the bottom of the Route and Town tabs, because the job card already shows all of that. You still get a message when something needs you, such as setting the GPS yourself when it couldn't be set, or pressing Teleport to the start of a dangerous contract.

## Build 114 · 30 Oct 2026

- **The short term loan is gone.** The Garage tab no longer has a Short term loan section, so the only money you can owe is for a repair or a tow. This keeps money simple.
- Your saves still work. If a save had a loan you hadn't repaid yet, that debt is cleared when you load it and you keep the money you borrowed.

## Build 113 · 30 Oct 2026

- **The HUD is cleaner, with your money in big type at the top.** Under it you see your fuel as a small gauge, your car and the km you've driven. Your job sits in one card with where it goes, how far and what it pays. Every tab and button is still there, but the details now fold away: Nearby, Drop-off coordinates and Abandon job on the Route tab, and Cargo space, Repair, Tow, Short term loan and Fuel on the Garage tab. Each folded section still shows its key number, such as "quote $730" or "19.0 L for $40". Click a heading to open or close it, and the HUD remembers how you left them. A section that needs you, such as a repair still owed, a puncture or a tow fee, opens by itself.
- **Town jobs are one line each.** Each line shows the cargo, where it goes, how far, the pay and Take job. Click a job to see its load slider, GPS button and the small print.
- **The HUD shows where you are.** At the top you see the town, or how far you are from the nearest one, such as "2.1 km west of Servoz", with the state and country under it and the road you're on. These names come from BeamNG.Earth, the same ones as in its bar at the top of the screen. If BeamNG.Earth has none (its place names are switched off, you're offline, or after a teleport), the HUD uses its own town list and shows the town and country. Road names only come from BeamNG.Earth.
- **Minimising the HUD now leaves a small strip that's easy to read on a stream.** It replaces the old "Worldwide Trucking" button and shows your money, your job with its distance and pay, and where you are. It still flashes gold at the drop-off, now with "DELIVER HERE", and shows bad news such as a puncture in red. Click it to open the full HUD. Your saves still work.

## Build 109 · 30 Oct 2026

- **Getting caught by the police now costs $200.** With police switched on in the game's traffic settings, being pulled over and ticketed, or arrested after a chase, takes $200 off your money. The game still shows its own police message, and a line under it tells you the fine and how much money you have left, such as "Police fine: $200 taken. You have $1,250 left." The HUD shows it too. If you have less than $200, the police take what you have and your money never goes below zero. The fine is saved the next time your car stops, so reloading won't undo it. Getting away from the police costs nothing. Your saves still work.

## Build 108 · 30 Oct 2026

- **The mod now has a licence.** You can still download it, play it and make videos of it for free. Copying its code into other mods, sharing a changed version or re-uploading it now needs the author's written permission. The download includes a LICENSE file with the full terms. Nothing changes in the game, and your saves still work.

## Build 107 · 30 Oct 2026

- **See a job's route before you take it.** Each job to a town on the Town tab's job board now has a **GPS** button next to **Take job**. Press it to set BeamNG.Earth's GPS to that town and see the route on the map, with nothing taken and nothing to pay. Dangerous contracts have one too: it sets the GPS to the start of the road, so you can see where it is before paying for the relocation. The button turns gold for the one the GPS is set to. Off-road drops don't have one, since there's no road to follow. Your saves still work.

## Build 106 · 30 Oct 2026

- **Your car now stays where you left it when you walk away from it.** With the game's traffic switched on, walking more than about 50 m from your parked car could make it vanish and turn up a few hundred metres away in a different colour, because the game's traffic treated it as an empty traffic car. While you are on foot your car is now kept out of traffic, and it goes back to normal once you get back in. Your saves still work.

## Build 105 · 30 Oct 2026

- **Two new dangerous contracts in Peru: Anta and Marcará.** Both are steep climbs of tight hairpins near Carhuaz, below the Cordillera Blanca, and both pay 6 times the base rate. Anta is about 1.6 km from start to finish, and Marcará about 2.4 km. Like the other dangerous contracts, each can be done once per game. Your saves still work.
- **The Carhuaz dangerous contract now starts and finishes on the right road.** Taking it sends you to a new start on the hairpin climb in Peru's Cordillera Blanca, and the finish is about 1.7 km away across the mountainside. It now pays 6 times the base rate instead of 8. It no longer asks you to drive an extra 1.5 km before the load delivers: drive the climb to the finish and stop there. Your saves still work. If you saved partway through a Carhuaz contract, it now uses the new start and finish when you load.

## Build 103 · 29 Oct 2026

- **Towing is free for now.** Tow car here no longer costs $500, so you can tow even with no money. If you owed a tow fee from the last build, it's cleared, and Buy parts, Buy new car and Buy second hand work again. Towing still doesn't fix any damage. Your saves still work.

## Build 101 · 29 Oct 2026

- **Towing now brings your car to you, instead of back to the road.** Tow to road is gone. To tow, stop and press **Get out** on the Repair card (or use the game's walking mode key), walk to a clear, flat spot within 50 m of your car, and press **Tow car here**, then **Confirm tow**. Your car is put down on its wheels in front of you and you're put straight back in it. Use it to get past a bad patch of map, or to get your car out of somewhere it's stuck. The Repair card lists the steps and shows how far away your car is.
- A tow costs $500. You keep your job, on a dangerous contract too, but towing doesn't fix anything: any damage is still owed on the Repair card. If you're short of $500 you can still tow, and the fee is owed instead. Pay it with **Pay** on the Repair card. Until you do, Buy parts, Buy new car and Buy second hand are switched off. Save keeps what you owe, and your saves still work.
- **The mod now copes with you getting out of your car.** While you're on foot, getting out is no longer treated as buying a new vehicle, walking doesn't count as distance driven, and your cargo stays in the car. Saving, jobs, deliveries, refuelling, repairs, insurance, relocation and changing parts or cars all wait until you're back in your car, and the HUD tells you so.

## Build 100 · 29 Oct 2026

- **The world is fuller: about 179,000 towns and villages to trade at, up from 100,000.** Villages down to 500 people are on the map now, and places can be as close as 3 km apart, so country areas that had nowhere to deliver nearby now have short runs too. The job boards, the Nearby list and the Relocate search all include the new places. The download grows from about 3.3 MB to 5.3 MB. Your saves still work, and every town you know is still there except about 40 worldwide whose position on the map was corrected; a job you saved on the way to one of those is cancelled when you load. A few remote places pay a little differently because the town populations are newer, for example Coroico on Death Road now pays 2.9 times instead of 3.
- **Pick how far you want to drive with the new Distance filter on the Town tab.** Choose Any, Short (up to 8 km), Medium (8 to 13 km) or Long (13 to 20 km), and all three town jobs on the board go that far, each to a different town where there are enough. Any keeps the usual mix of one short, one medium and one long run. If no town is that far away, the closest towns are used instead and those jobs are marked "nearest". The off-road drop and the dangerous contract don't change. Your choice is remembered after you restart the game, and your saves still work.

## Build 99 · 29 Oct 2026

- **The game now saves itself.** After a delivery, buying parts or a car, a repair or a relocation, it saves once you've been stopped for a few seconds, and the line under your money says "Saved automatically after your delivery" (or whatever you did). If you drive straight off, it saves at your next stop. A game crash or a forgotten Save no longer loses your run. The **Save** button still works for anything else, such as kilometres driven. Your saves still work.
- **The Nearby list on the Route tab shows which way each town is**, as N, SE and so on under its distance, and each town has a **GPS** button. Press it to set BeamNG.Earth's GPS to the middle of that town, which is where it counts as being in town. The town the GPS is set to has a gold button, including the drop-off of the job you took.
- **A chime plays when you can deliver.** Stopping at your drop-off town, an off-road drop or a dangerous contract's finish, or at a beacon you can pick up, plays two short notes. If the HUD is minimised, its Worldwide Trucking button flashes gold until you deliver.

## Build 98 · 28 Oct 2026

- **Relocating no longer fixes your car for free.** Teleporting to a relocation you booked on the Relocate tab, to the start of a dangerous contract, or anywhere with the BeamNG.Earth map puts the car down as new, just like pressing Insert. The repair it needed now always stays owed on the Garage tab, even when the car's damage could not be read while the new area was loading, which could let it slip through before. Your saves still work.

## Build 97 · 28 Oct 2026

- **New dangerous contract: Ravin de Piquet, France.** It runs from the Ravin de Piquet down the mountain valley to Cauterets in the French Pyrenees, about 5 km, paying 4 times the base rate. Like the other dangerous contracts, it can be done once per game. Your saves still work.

## Build 96 · 28 Oct 2026

- **Car names are tidy again.** The starter car shows as Burnside Rusty everywhere, including the trade-in line on the Buy second hand card, which used to show a jumble like "Special Earth_freight_starter Earth Freight _Starter". Other cars show their brand, model and version, such as "Gavril D-Series D15", with no underscores. Your saves still work.
- **Buy second hand no longer offers trailers or props**, such as traffic cones. Only cars and trucks are for sale now.

## Build 95 · 28 Oct 2026

- **The helicopter is now for sightseeing and scouting, and the loads under the hook are gone.** A hire still costs $1,000 and lasts as long as you like. The Heli tab now shows the town you're over, its region, your height, which way your car is, the five nearest towns, and the nearest town's job board, so you can plan your next run. **Back to my car** only happens when you press it, never by landing.
- **New "don't ask questions" jobs.** Every 5 minutes you fly more than 30 m up, there's a 50% chance of picking up a signal beacon within 15 km of your car. A box pops up in the middle of the screen and closes by itself. The beacon appears on the Route tab with an arrow and its coordinates, and on the Town tab's job board. Drive there in your car, stop within 100 m and press **Pick it up**. Then take the package, which weighs nothing, 2 to 5 km off road to the drop for $12,000. Only one beacon waits at a time, and it goes quiet after an hour of play. Ignoring it is free, but once it's picked up an insurance claim costs $4,000 and loses it, and abandoning costs $1,000.
- Your saves still work, and a beacon you've found is kept when you save.

## Build 92 · 28 Oct 2026

- **The download is now called `worldwide-trucking-dangerous-contracts.zip`** to match the new name. Delete the old `earth-freight-sim.zip` from your `mods` folder before you add the new one, otherwise the game loads both copies. Your saves still work.

## Build 91 · 28 Oct 2026

- No changes in the game. The README now lists what you need before installing (BeamNG.drive 0.40, BeamNG.Earth, and the Revamped Bell 407 for heli flights), how to update, where to report bugs, the features it was missing, and credits for BeamNG.Earth and the Bell 407.

## Build 90 · 28 Oct 2026

- **New Heli tab: hire a helicopter and fly loads over the world.** It needs the Revamped Bell 407 mod by stefan750, which you download from the BeamNG forum and put in your mods folder yourself. Without it, the Heli tab says what to install and has a button that opens the mod's page. Press **Hire helicopter · $1,000**, then **Confirm hire**, in your own car while it's stopped. The helicopter takes your car's place, and your car waits with its job, fuel and damage.
- A load turns up in front of the helicopter. Hook it on, fly it to the town named on the Heli tab (an arrow points the way), set it down inside the drop zone and let go. It pays $3 a kg, up to $3,000 for 1,000 kg, and the next load turns up. A load that hits the ground too hard pays nothing. You can fly as many loads as you like until you press **Back to my car**. Near your car, land and your car takes the helicopter's place. Farther away, you're teleported back first. Hiring again costs another $1,000.
- A helicopter crash costs $1,000 insurance, and you lose the load and the hire. You're taken back to your car. While you fly, Save, jobs, refuelling, repairs and relocation wait until you're back in your car. Nothing about a hire is saved, and your saves still work.

## Build 87 · 28 Oct 2026

- **The Ko-fi line at the bottom of the start page now reads "Keep me awake behind the wheel: ko-fi.com/madmerick".** Pressing the link works as before: it opens the page in your browser and copies the link. Your saves still work.

## Build 85 · 28 Oct 2026

- **You can now support the mod on Ko-fi.** At the very bottom of the start page (open it with your name button at the top of the HUD), **Support the mod on Ko-fi** opens ko-fi.com/madmerick in your browser and copies the link, so you can paste it yourself if the browser doesn't open. The mod stays free, and nothing about Ko-fi shows up while you drive, deliver or use the Garage. Your saves still work.

## Build 84 · 28 Oct 2026

- **You can now take a short term loan.** The Repair card on the Garage tab has a **Short term loan** button: press it and then **Yes, borrow** to get $1,000 straight away. You owe $1,350 for it, shown on the same card. Once you have $1,350, press **Repay $1,350** there to pay it off in one go. Nothing is taken from your delivery pay, and you can't take another loan until this one is repaid. The Repair card also shows up while a parts or car bill is waiting and you're short of money, so you can borrow to pay it.
- A loan is kept when you save, like your money. Your saves still work, and an old save starts with no loan.

## Build 83 · 28 Oct 2026

- **Stuck off the road? Press Tow to road.** The Repair card on the Garage tab has a new **Tow to road · $500** button that puts your car back on the road it was last on. Press it, then **Confirm tow**. The $500 is only taken once your car has actually moved, so if the game can't find a road you pay nothing. Towing keeps your job and doesn't count as a teleport, but it doesn't fix anything: any damage your car had is still owed on the Repair card, even if it looks new after the tow. Your saves still work.

## Build 79 · 28 Oct 2026

- **You can now buy second-hand cars.** Press **Buy second hand** on the Garage tab to see two used cars for sale in the town you're in, or the nearest town. They can be any BeamNG car in any version, except trailers and props, and cost between 70% and 105% of the new price. Each card shows the car's picture, its kilometres, its price, a "Good deal" tag when it's under 80% of new, and what you'd pay after your trade-in. Each town always sells the same two cars, so drive to another town to see different ones. **Buy this one** puts the car in place of yours and opens the usual car bill at the second-hand price: buy it or press **Get my car back**, as with a new car.
- Second-hand cars look worn, with faded paint and the kilometres on the clock, but they drive like new. A second-hand car is worth what you paid for it, so that's what its trade-in and repairs are based on, and it stays that way after part changes and after you save and load. Your saves still work.
- **The starter car is now called the Burnside Rusty**, in the HUD and in the game's car selector. It's the same car. Your saves still work, and an existing starter car shows the new name straight away.

## Build 78 · 28 Oct 2026

- **The HUD is now called TruckingCareerDC in the app list.** When you open Edit Layout (or the UI apps menu) to add or move the HUD, look for TruckingCareerDC instead of EarthFreightHUD. Because the HUD has a new name, the game may drop it from a layout you saved before this build. If the HUD is missing after you update, open Edit Layout, add TruckingCareerDC again and save your layout. Delete the old ZIP from your mods folder so you don't end up with two copies. Your saves still work.

## Build 77 · 28 Oct 2026

- **You can now pay for your parts straight from the parts bill box.** The box that pops up in the parts menu now lists each part you've added or sold back with its price, as the Garage tab does, and shows how much money you have. Press Pay, then Yes, pay, to buy the parts without leaving the menu. The Pay button only shows when you can afford the bill. You can still pay or undo on the Garage tab. Your saves still work.

## Build 74 · 28 Oct 2026

- **Teleport straight to your relocation.** Once you've booked a relocation on the Relocate tab, a new **Teleport** button sits next to **Copy** and takes you there in one press, so you no longer need to paste the coordinates into the BeamNG.Earth map. The fee and the rules are the same: book with an empty car, and the booking is used up when you land. Copying the coordinates still works. Your saves still work.

## Build 71 · 28 Oct 2026

- **Start anywhere on Earth, such as your home town.** A new game no longer sends you to Penrith. Open the BeamNG.Earth map, find any place, teleport there and press the new **Start here** button on the start page or the Route tab. Your starter car and $2,500 are waiting right where you are, and that spot becomes your start. It's named after the town you're in or the nearest one within 20 km. Anywhere more remote is simply called your start.
- **New game takes you back to your own start.** After pressing **New game…** and **Yes, start over**, the start page offers **Teleport to** your start town, or you can teleport somewhere else and press **Start here** to pick a new one. Your saves still work: a game that began in Penrith keeps Penrith as its start until you choose another.

## Build 70 · 28 Oct 2026

- **The mod has a new name: BeamNG Worldwide Trucking Career: Dangerous Contracts.** It used to be called Earth Freight Sim. The HUD now says Worldwide Trucking Career at the top, the start page shows the new name, the minimised HUD button says Worldwide Trucking, and the UI apps list shows the new name. Nothing else changes: the download is still `earth-freight-sim.zip`, you don't need to delete anything, and your saves still work.

## Build 64 · 27 Oct 2026

- No changes in the game. **The README has been rewritten for players**: a short list of what the game offers, how to install it and how to get started.

## Build 63 · 27 Oct 2026

- **The parts bill is now a bold box near the top of the screen while you're in the parts menu.** It has a gold border, or red when you can't afford the bill, and shows the total so far, how it splits into parts and repair, and how much you're short. It stays up as you change parts, updating each time, until you press Close, pay, undo the changes or leave the parts menu. If the box can't show, you get the corner pop-up as before. Your saves still work.

## Build 62 · 27 Oct 2026

- **The parts bill pop-up now shows in the middle of the screen and stays twice as long**, 12 seconds instead of 6, so it's easier to read while you're in the parts menu. Your saves still work.

## Build 61 · 27 Oct 2026

- **You can now see the parts bill while you're still in the parts menu.** Each time you change a part with Ctrl+W, a pop-up in the corner shows the bill so far, split into parts and repair, and says how much you're short if you can't afford it. Undoing every change in the parts menu pops up "Nothing to pay". You still pay or undo on the Garage tab as before. Your saves still work.

## Build 60 · 27 Oct 2026

- **New dangerous contract: Grimsel Pass, Switzerland.** It runs from the lakes by the Grimsel Hospiz over the top of the pass and down the tight Alpine switchbacks to Gletsch, paying 2.5 times the base rate. Your saves still work.

## Build 59 · 27 Oct 2026

- **The Buy new car button on the Garage tab now opens the car selector.** Before, it hid the whole game screen, including the map and compass. It now does exactly what Ctrl+E does. Your saves still work.

## Build 58 · 27 Oct 2026

- **New dangerous contract: Carhuaz, Peru.** A steep, tight climb of never-ending hairpins in the Cordillera Blanca, paying 8 times the base rate. The finish sits almost straight above the start, so the load only delivers once you have driven at least 1.5 km of the climb. Your saves still work.
- **The testing tools are gone from the start page.** The +$10,000 test money button and the dangerous contract road list with its Start and Finish teleport buttons have been removed, now that every road has been checked. Money you already added stays in your saves, and your saves still work.

## Build 57 · 27 Oct 2026

- **The Death Road dangerous contract now starts and finishes on the road.** Its start and finish have been checked in game and moved to the right spots, so the teleport puts you on the track and the GPS leads to the real finish. A Death Road contract you already started keeps going. Your saves still work.
- The Sani Pass and Zoji La dangerous contracts' starts and finishes have also been checked in game and moved onto the road.
- **Dangerous contracts now use only the three roads checked in game: Death Road, Sani Pass and Zoji La.** Fairy Meadows Road, Skippers Canyon, Atigun Pass and Transfăgărășan are gone for now. If you saved partway through one of their contracts, that job is gone when you load. Your saves otherwise still work.
- **Each dangerous road now pays its own rate.** Death Road pays 8 times a normal 5 km job for the same load, Zoji La 4 times and Sani Pass 3 times. The job board shows the rate on each contract. A contract you already took keeps the pay it showed.
- **Each dangerous road can only be done once per game.** When you deliver a dangerous contract, that road comes off every job board until you start a new game. Once you've done all three, the job boards have no dangerous contract. Your saves still work.
- For testing, the dangerous contract list on the start page now shows each road's start and finish coordinates under its name, and lists only the three checked roads.

## Build 56 · 26 Oct 2026

- **The dangerous contract test picker on the start page now works for every road.** The drop-down list wouldn't open in game, so it only ever offered Death Road. Each road now has its own row with Start and Finish buttons. Each row also shows the road's start and finish coordinates. Your saves still work.

## Build 55 · 26 Oct 2026

- **Minimising the HUD no longer leaves a red dotted outline where the full HUD was.** Only the small Earth Freight button stays on screen, and pressing it opens the HUD at its usual size. Your saves still work.

## Build 51 · 26 Oct 2026

- **The Town tab is shorter.** The Refuel button has moved to the Garage tab, next to Repair. It still only works when you are stopped in a town, and it shows the litres and the price as before.
- The Cargo slots card and its Buy more cargo space button are gone from the Town tab. To add cargo room, press Buy parts on the Garage tab and fit a Cargo Load box, as before. Your saves still work.

## Build 50 · 26 Oct 2026

- **When Earth Freight Sim hits a problem and shows FREIGHT PAUSED, the notice now tells you where to look:** search `beamng.log` for `internal_error`. That line now names exactly where the problem happened and how the game got there, so sending it along is all it takes to get it fixed. Nothing else changes, and your saves still work.

## Build 49 · 26 Oct 2026

- **Dangerous contracts are on every job board.** Each town now offers one, below the off-road drop: a load of parts or bricks over about 2 km of a famous treacherous road, such as the cliff edge of Death Road in Bolivia, the Sani Pass hairpins or the Atigun Pass in Alaska. It pays 8 times a normal 5 km job for the same load, and you choose how much to carry with the Load slider. The contract changes after every job, and the next town usually has a different road.
- Taking a dangerous contract costs $200 to be relocated to the start, and you are teleported there straight away (or press Teleport to the start on the Route tab). When you arrive, the GPS is set to the finish. Drive the road and stop within 100 m of the finish to get paid. A crash ends the contract: insurance on a dangerous contract costs $4,000 instead of $1,000. Abandoning one before you reach the start gives you the $200 back. The start and finish points have not been checked in game yet. Your saves still work.
- For testing, the start page (open it with your name button) has a dangerous contract road picker next to the test money button. Pick a road and press Teleport to start or Teleport to finish to go straight there. Teleport to start also sets the GPS to the finish. A test teleport doesn't cancel your job or strand you.

## Build 47 · 26 Oct 2026

- **Job pay is now scaled for a starter car with 52 cargo slots.** A full 52 slots of parts (780 kg) pays $2,000 over 5 km, and heavier loads pay more but less for each kilogram: about $2,600 for the 1,200 kg of bricks that fit in 52 slots, $8,700 for 8 tonnes and $11,200 for 12 tonnes. Smaller loads pay their share by weight, so the starter car's own 20 slots of parts now pays about $770 over 5 km instead of $2,000, and fitting more cargo boxes before your first run pays off.
- **Cargo boxes carry less weight.** Cargo box L now takes up to 400 kg instead of 600 kg, and Cargo box M 130 kg instead of 200 kg; their slots are unchanged. The starter car's own boxes now take 650 kg, which is 20 parts or 4 bricks, and a single box M is too small for a brick. A job you were already carrying pays what it showed when you took it. Your saves still work.

## Build 46 · 26 Oct 2026

- **Teleport to last save.** When you load the game, the Welcome back card now has a Teleport to last save button. Press it and BeamNG.Earth takes you straight to where you last saved, with no copying or pasting coordinates into its map. The same button is on the Route tab until you get there. A new game has a Teleport to Penrith button instead.
- The coordinates and Copy button are still there if you prefer the map, or if BeamNG.Earth can't teleport you right then (the HUD tells you). Your saves still work.

## Build 45 · 26 Oct 2026

- **The Buy parts and Buy new car buttons are now inside the Change parts or buy a car card on the Garage tab**, under the steps, so it's clear where to start. Buy parts opens the parts menu and Buy new car opens the car selector.
- Tips and messages no longer tell you to press Ctrl+W. They point you to the Buy parts button instead, for example when your starter car needs a radiator or a job needs a fluid tank. To get these buttons, put the new `earth-freight-sim.zip` in your mods folder in place of the old one. Your saves still work.

## Build 44 · 26 Oct 2026

- **The Garage tab has Buy parts and Buy new car buttons.** Buy parts opens the parts menu and Buy new car opens the car selector, so you no longer need Ctrl+W or Ctrl+E. The bill still shows up on the Garage tab to pay or undo as before. Your saves still work.

## Build 39 · 26 Oct 2026

- **You can minimise the HUD.** Press the – button at the top right of the HUD and it shrinks to a small Earth Freight button. Press that button to open the full HUD again, on the tab you were on. It stays minimised until you open it, even after you restart the game.
- While the HUD is minimised, a dot on the Earth Freight button tells you something is waiting: gold for a shortage, a job or a delivery you can make, red for bad news such as a cancelled load or a puncture. The HUD opens by itself for a garage bill, an insurance offer, being stranded or the start page. Your saves still work.

## Build 38 · 26 Oct 2026

- **The load slider on the Town tab no longer jumps when you drag it down from 100%.** The "full load" price that used to pop up beside it is gone, so the slider keeps the same size the whole time you drag. The pay for the share you pick still shows next to Take job. Your saves still work.

## Build 37 · 26 Oct 2026

- **Jobs now pay by the weight of the load.** A full 300 kg load pays $2,000 over 5 km, and heavier loads pay more but less for each kilogram: about $3,300 for the starter car's 6 bricks (900 kg), $5,800 for 3 tonnes and $10,900 for 12 tonnes. Distance, town need, shortages, jackpots and rough roads still raise the pay as before, and the load slider still pays its share of the job. Loads under 300 kg pay their share by weight, such as $200 for 2 parts in a car boot. The goods are the same: parts and bricks in cargo boxes, and water or fuel in a tank.
- A job you were already carrying pays what it showed when you took it. Your saves still work.

## Build 36 · 26 Oct 2026

- **The Town tab now shows your cargo slots in a card above the jobs.** It shows how many slots your cargo boxes give you, how many your load takes and how many are free, with your weight limit. It explains that a Cargo Load box S adds 1 slot, M adds 4, L adds 16 and XL adds 128, and its Buy more cargo space button opens the parts menu. Fit a box there, then pay for it on the Garage tab. Your saves still work.

## Build 34 · 26 Oct 2026

- **Shipping is now called Relocation and has its own Relocate tab.** The Relocation paid offer (was Shipping paid) and the Book relocation card (was Book shipping) have moved from the Garage tab to the new Relocate tab, next to Garage. A gold dot marks it while you have a booking waiting. Messages in the game say relocation too, such as "Relocated to Coroico". It works exactly as before, and a refund you are owed from an earlier paid offer still comes through.
- **The Tips tab is gone.** The +$10,000 test money button and the map data credits are now at the bottom of the start page (press your name or Profile at the top of the HUD). Your saves still work.

## Build 33 · 26 Oct 2026

- **Loading a saved game now opens the start page with a Welcome back box.** It shows the coordinates of your last save with a Copy button and how far away you are, in the same colours as the rest of the start page. Press Continue to close it; the coordinates stay on the HUD until you get there.
- The start page's button now says Continue instead of Done. On a brand new game it still says Let's go.

## Build 28 · 26 Oct 2026

- **Pressing Insert no longer fixes your car for free.** Resetting the car after a crash (Insert, or the game's own recovery) still puts it back on its wheels, but the repair it needed stays on the Garage tab as "Repair still owed", and a pop-up says so. After a serious crash you can still claim insurance instead. Reloading the car, or undoing part changes in the parts menu, no longer clears the damage either.
- A reset also leaves your fuel as it was, so it can't be used to fill up for free, and a load you're carrying keeps its weight. Your saves still work.

## Build 27 · 26 Oct 2026

- **The start page has a new look.** The title is much bigger, the How to play steps are numbered, and when you reopen the page with the Profile button it shows your money, car and kilometres driven. The steps fold away there behind a Show the steps button.
- **New game has moved from the Tips tab to the start page.** Press your name (or Profile) at the top of the HUD, then New game… at the bottom. It asks once more and says exactly what you will lose. Press Yes, start over to go ahead, or Keep my game to back out. Closing the page also backs out. Your saves still work.

## Build 23 · 25 Oct 2026

- **Water and fuel now slosh in the tank.** A fluid load is poured into the Cargo Load fluid tank itself, the same way BeamNG fills it, so it moves around when you brake, corner or climb instead of sitting still like a solid weight. Please try it and say how it feels.
- **The Garage tab shows your tank's real size.** Once you have driven to a town with a tank fitted, the game asks the car how many litres the tank holds, and job sizes use that instead of an estimate.
- If your tank turns out not to slosh, the load still weighs the same as before. Your saves still work.

## Build 22 · 25 Oct 2026

- **Water and fuel jobs.** Every town's job board is now four jobs: parts, bricks, one fluid (water or fuel, depending on the town) and the off-road drop, which carries parts or bricks. Fluids are carried in litres and pay about a quarter more than bricks for the same weight. The Load slider works in litres.
- **Fluids need a tank.** Without one, the fluid job says "Needs a tank". Fit a Cargo Load fluid tank in the parts menu (Ctrl+W) and pay for it on the Garage tab, the same way as a cargo box. The Garage tab shows how many litres your tank holds.
- Food is no longer posted, and farming towns now want water. A food job you saved before this build still delivers. Saves still work.

## Build 21 · 25 Oct 2026

- **Off-road drops.** Every town's job board now has one off-road drop: parts, food or bricks to a random spot 1.8 to 3.2 km out of town, away from the roads. There is no GPS route. The Route tab shows how far the spot is and an arrow pointing to it, and you deliver it from there by stopping within 100 m of the spot. It pays like a 5 km job, and more in steep country. The spot can land anywhere, up a hill or across a creek, so getting there is part of the challenge. The Load slider and insurance work as on any other job. Saves still work.
- The help text under the job board is gone: the jobs and sliders explain themselves.

## Build 20 · 25 Oct 2026

- **Take part of a job with the Load slider.** Each job on the Town tab now has a Load slider from 10% to 100%. Take half the bricks or 70% of the parts and the weight and pay drop by the same share, shown as you drag. The job is used up when you take it, whatever share you pick. Saves still work.

## Build 19 · 25 Oct 2026

- **Deliveries are now jobs, and they pay much more.** You no longer buy cargo. Stop in a town and the Town tab lists 3 to 5 jobs, each showing one total pay. Press Take job and it fills every cargo slot your car has, so bigger cargo boxes and vehicles earn more. Deliver it to the drop-off town and you get the pay shown, in full. On the starter car a 5 km job pays about $1,700 to $2,400, and a 20 km job about six times as much.
- Parts now take 1 slot and weigh 15 kg each, food 2 slots and 50 kg, and bricks 3 slots and 150 kg. Bricks need a cargo box: they don't fit in the boot.
- Each job pays up to 30% more or less depending on how much the drop-off town wants that good. Green on the board pays above the usual, red below. Delivering the same thing to the same town again pays less for an hour or so. Every town always has at least one decent job.
- Look out for gold: a town short of a good pays double until the end of the hour (shown on the Route tab with the time left), and about one job in 20 is a jackpot paying two to three times. Rough roads pay up to twice as much, and the bonuses add up.
- Abandoning a job costs $1,000. So does teleporting without booking shipping while you have a job.
- **Insurance after a serious crash.** The Garage tab now offers Claim insurance for $1,000: your car is fixed and put back on the nearest road, but the job and its cargo are lost. The normal repair is still there if you want to keep the job.
- The delivery distance slider and the "how many" buttons are gone. Fuel and repair prices are the same.
- Saves still work. If you saved while carrying cargo you bought, it is taken off when you load and the money you paid for it is given back.

## Build 18 · 25 Oct 2026

- **The towns offering to pay your shipping are less remote.** The offer card in the Garage tab now picks from towns paying ×2.3 to ×3.0 (was ×2.7 to ×3.0), and only towns with at least one delivery within 7 km, so you are never sent somewhere with nothing close to drive to. Saves still work, and a refund you are already owed still pays out.

## Build 17 · 25 Oct 2026

- **The HUD stays where you left it after the parts menu or the map.** Closing the parts menu (Ctrl+W) or the map no longer sends the HUD back to the start page, and it stays on the tab you were on instead of jumping to Town or Garage. The start page still opens by itself on a new game, and any time from the Profile button. Saves still work.

## Build 16 · 25 Oct 2026

- **Parts, food and bricks are much lighter.** Each slot of parts now weighs 2 kg (was 20 kg), food 8 kg (was 25 kg) and bricks 25 kg (was 120 kg). Your car feels the lighter load and uses less fuel carrying it.
- Bricks now fit in the boot, and a full set of cargo boxes can be filled with bricks instead of running out of weight after a few slots. Only the biggest Cargo box XL still runs out of weight before space with bricks.
- Because freight pay is paid per tonne for each road km, these goods now earn much less freight pay per slot: about a tenth as much for parts, a third for food and a fifth for bricks. What a town pays for the goods themselves is the same.
- Saves still work. A load you are carrying when you load a save keeps the weight it had when you bought it, but is paid freight at the new, lighter weight.

## Build 15 · 25 Oct 2026

- **New game now always gives you a fresh starter car.** Before, if you were still driving the starter Burnside when you pressed New game, it kept every part you had paid for, such as a radiator, cargo boxes or a turbo, and the next Save kept them too. Now the Burnside is swapped for a stock one when you reach Penrith, even if you are already standing there. Your saves still work.
- When you are close to Penrith or your last save, the Go to card now says you can simply drive there instead of teleporting, and how close you need to get.

## Build 14 · 25 Oct 2026

- **The Garage's "Change parts or buy a car" box is tidier.** It no longer lists keyboard keys, and the Cargo line now gives one short total, such as "Cargo: 5 boxes · 20 slots · 1,000 kg max", instead of naming every box. Saves still work.

## Build 13 · 25 Oct 2026

- **A new start page welcomes you to Earth Freight Sim.** It opens when you start a new game, with a box for your name and seven short steps on how to play: going to Penrith (with the coordinates and a Copy button), fitting a radiator, buying a load, the delivery distance slider, delivering, refuelling, the Garage and shipping. Press **Let's go** to close it.
- You can open the start page again at any time with the button at the top right of the HUD (it shows your name, or "Profile"), or with **Your name and how to play** on the Tips tab.
- The HUD uses your name: it welcomes you when you reach Penrith or get back to your last save, after a delivery, and when you save. Your name is kept when you press Save, and New game keeps it too.
- Typing in the HUD's text boxes (your name, and the town or coordinates boxes for shipping) no longer drives the car or triggers other game keys.
- Saves from earlier builds still load. They just have no name until you add one.

## Build 12 · 25 Oct 2026

- Each build's download page now lists every earlier build's changes too, under "Earlier builds", so you can see everything that has been added so far.

## Build 11 · 25 Oct 2026

- The download page for each build now lists what changed, in plain English, and this list of changes comes inside the mod's ZIP too.

## Build 10 · 25 Oct 2026

- **Deliveries always pay in full.** Your cargo no longer gets damaged when you drive roughly. Rough driving still costs you, but only through your car's repair bill.
- The cargo condition bar is gone from the load card.
- Saves from earlier builds still load, including one with a load on board.

## Build 9 · 25 Oct 2026

- **You can see where to go after starting a new game.** The "Go to Penrith" card, with the coordinates and a Copy button, now sits above the tabs, so it's in view on every tab until you arrive. The new-game message gives the coordinates too.
- **The delivery distance slider works in game now.** Before, moving it did nothing. It also has − and + buttons that change the distance by 5 km.
- **The Town tab stays open outside a town.** It used to jump straight back to Route. Now it tells you that you're not in a town, which place is nearest and how far away it is.

## Build 8 · 25 Oct 2026

- **The Garage bill is much clearer.**
  - The bill is at the top of the Garage tab, so you see it as soon as it opens.
  - Every line shows its price: parts you add, parts you take off (with what you get back for them) and the repair, with a total underneath.
  - Under the total you see how much money you have and what you'll have left, or how much you're short.
- The pay button says how much you'll pay ("Pay $1,020", "Buy for $17,300") and asks you to confirm.
- The undo buttons say what they do: "Undo changes" and "Get my car back". Driving off without paying also undoes the change, and the bill now tells you that.
- When you buy a car, the bill names the car you're trading in and shows how much its damage took off its trade-in value.
- With no bill open, the Garage tab shows three short steps: open the parts menu (Ctrl+W) or the vehicle selector (Ctrl+E), the bill appears here, then pay or undo.

## Build 7 · 25 Oct 2026

- **The mod is now called Earth Freight Sim.**
- The download is now `earth-freight-sim.zip`. If you still have the old `earth_freight.zip` in your `mods` folder, delete it so the two don't both load. Your saves carry over.

## Build 6 · 25 Oct 2026

- No changes in the game. The instructions in the README now cover the worldwide towns, the region pay boost and shipping.

## Build 5 · 25 Oct 2026

- **Towns all over the world.** There are now over 100,000 towns to trade between, not just the area around Sydney.
- **Hard places pay more.** Every town has a pay boost from 1x to 3x. Steep, remote and high places pay more, and so do famous roads like Bolivia's Death Road, the Stelvio Pass and the Karakoram Highway. Sydney is 1.0x, Katoomba 1.5x, La Paz 1.9x, and Coroico and Bormio 3.0x. The boost shows next to the region name.
- **Shipping.** From the Garage tab you can ship your car to one of the listed regions, to any town by typing its name, or to any coordinates. It costs $100 plus 2 cents a km and your car has to be empty. You get coordinates to paste into Earth's map, and Cancel gives your money back.
- **Paid shipping offer.** Every 5 minutes the Garage tab offers a town in one of the hardest regions. Ship there, make a delivery nearby, and the shipping fee is paid back.
- **Teleporting without booking costs you.** You lose any load and you're stranded: no deliveries or trading until you drive back to where you were, or book shipping.

## Build 4 · 25 Oct 2026

- **Short runs from about 5 km.** There are twice as many places around Sydney now, about 4 km apart.
- **Pick how far you want to drive.** A slider on the Town tab sets the delivery distance from 5 to 50 km, and the drop-off list shows places about that far away.
- **Long runs pay more per km.** A 5 km run pays $22 a tonne for each km and a 50 km run pays $40, so long runs are worth the risk.

## Build 3 · 25 Oct 2026

- **A new game starts with $2,500** instead of $1,500. The starter car needs a radiator straight away, and this covers it with enough left for a first load.
- The coloured dots on the Route tab have headings now (Parts, Food, Bricks), and a colour key explains them: green is cheap to buy there, grey is a normal price, red is short and pays well to deliver there.

## Build 2 · 25 Oct 2026

- **Choose how much to buy.** The Town tab has −, +, 1 and Max buttons and shows the cost and weight for that many.
- **Deliveries pay for the distance.** On top of the drop-off's price you get $20 per tonne for every km of road, so short runs are worth doing. Heavy goods earn more but burn more fuel.
- The drop-off list has column headings: Drop-off, Pays per slot and Your profit.

## Build 1 · 25 Oct 2026

The first playable version.

- Start in Penrith, near Sydney, in a rusty Burnside with $1,500 and five cargo boxes (20 slots).
- About 100 places around Sydney buy and sell parts, food and bricks at fixed prices.
- Buy a load on the Town tab, and Earth's GPS is set to the drop-off for you. Drive there and get paid.
- The weight of your load is felt in the car. More cargo boxes, fitted in the Garage like any part, give you more room.
- Refuel in towns at $2.10 a litre. You only pay for what goes in.
- You have to actually drive the load most of the way. Teleporting more than 2 km cancels it.
- The Garage repairs your car, changes parts and sells you other cars. Punctures can happen.
- Two save slots keep your money, car, fuel and load.

## Before build 1

- Planning only, no download. The design was written down and the first questions about towns, cargo, cars, shipping and maps were answered.
