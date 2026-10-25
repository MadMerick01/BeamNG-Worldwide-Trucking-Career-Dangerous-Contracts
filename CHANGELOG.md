# What's changed

Every change to Earth Freight Sim, in plain English, newest first. Each build is a new download on the [Releases](../../releases/latest) page.

## Coming next

Changes that are finished but not in a download yet. They move into a numbered build as soon as it's published.

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
