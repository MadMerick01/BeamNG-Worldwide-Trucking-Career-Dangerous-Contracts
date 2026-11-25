import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'

const APP = '../mod/earth_freight/ui/modules/apps/TruckingCareerDC/'
const source = readFileSync(new URL(APP + 'app.js', import.meta.url), 'utf8')
const html = readFileSync(new URL(APP + 'app.html', import.meta.url), 'utf8')
const help = readFileSync(new URL(APP + 'help.txt', import.meta.url), 'utf8')
const fixed = body => 'if earthFreight_core then earthFreight_core.' + body + ' end'
// Just enough of a page for the parts bill box: elements with text, style, children and a click.
function page() {
  const make = tag => ({
    tag, children: [], style: {}, attributes: {}, textContent: '', parentNode: null,
    setAttribute(k, v) { this.attributes[k] = v },
    appendChild(child) { child.parentNode = this; this.children.push(child); return child },
    removeChild(child) { this.children = this.children.filter(c => c !== child); child.parentNode = null; return child }
  })
  return { body: make('body'), createElement: make }
}
function app(storage, element, extra) {
  const commands = [], handlers = {}, root = {}, timers = new Map(), timeouts = [], document = page()
  let definition, clock = 0
  const scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
  vm.runInNewContext(source, {
    angular: { module(name) {
      assert.equal(name, 'beamng.apps')
      return { directive(id, factory) { assert.equal(id, 'earthFreightHud'); definition = factory.at(-1)({ $on: (name, fn) => { root[name] = fn } }) } }
    } },
    bngApi: { engineLua: command => commands.push(command) },
    setInterval: fn => { timers.set(1, fn); return 1 },
    clearInterval: id => timers.delete(id), Date: { now: () => clock },
    setTimeout: (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length },
    window: storage ? { localStorage: storage } : {}, document, ...(extra || {})
  })
  definition.link(scope, element)
  const state = data => handlers.EarthFreightState({}, data)
  const a = { scope, commands, handlers, root, document, timers, timeouts, state, advance: ms => { clock += ms; for (const tick of timers.values()) tick() } }
  // BeamNG rebuilds the app when a menu closes: the old one is destroyed and a new one linked.
  a.remount = () => {
    handlers.$destroy()
    a.scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
    definition.link(a.scope, element)
    return a
  }
  return a
}

test('app mounts and resynchronizes', () => {
  const a = app()
  assert.match(a.commands[0], /uiMounted\(true\)/)
  a.advance(3000)
  assert.match(a.commands[1], /uiMounted\(true\)/)
  assert.equal(a.scope.data.saveAllowed, false)
})
test('buttons only send fixed commands when Lua enabled them', () => {
  const a = app()
  const buttons = {
    save: ['saveAllowed', 'save()'],
    requestRepairQuote: ['repairQuoteAllowed', 'requestRepairQuote()'], repairVehicle: ['repairAllowed', 'repairVehicle()'],
    buyParts: ['buyPartsAllowed', 'buyParts()'], revertParts: ['revertPartsAllowed', 'revertParts()'],
    buyCar: ['buyCarAllowed', 'buyCar(false)'], keepCar: ['keepCarAllowed', 'buyCar(true)'], revertCar: ['revertCarAllowed', 'revertCar()'],
    newGame: ['newGameAllowed', 'newGame()'], abandonJob: ['abandonAllowed', 'abandonJob()'],
    teleportToResume: ['teleportAllowed', 'teleportToResume()'], startHere: ['startHereAllowed', 'startHere()']
  }
  for (const [name, [flag, body]] of Object.entries(buttons)) {
    const count = a.commands.length
    a.state({ state: 'READY' }); a.scope[name]()
    assert.equal(a.commands.length, count, name + ' refused when not allowed')
    a.state({ state: 'READY', [flag]: true }); a.scope[name]()
    assert.equal(a.commands.at(-1), fixed(body), name)
  }
})
test('Buy second hand opens the list, and a car is only bought by its slot when Lua allows it', () => {
  const a = app()
  a.scope.openUsedCars(true); assert.equal(a.commands.at(-1), fixed('openUsedCars(true)'))
  a.scope.openUsedCars(false); assert.equal(a.commands.at(-1), fixed('openUsedCars(false)'))
  const count = a.commands.length
  a.scope.buyUsedCar({ slot: 1, allowed: false }); a.scope.buyUsedCar({ slot: '1); x(', allowed: true })
  a.scope.buyUsedCar({ slot: 1.5, allowed: true }); a.scope.buyUsedCar(null)
  assert.equal(a.commands.length, count, 'refused unless allowed, with a whole slot')
  a.scope.buyUsedCar({ slot: 2, allowed: true }); assert.equal(a.commands.at(-1), fixed('buyUsedCar(2)'))
})

test('Trailer buttons only call Lua when it allows them, and a trailer is bought by its place in the list', () => {
  const a = app()
  a.scope.openTrailers(true); assert.equal(a.commands.at(-1), fixed('openTrailers(true)'))
  let count = a.commands.length
  a.scope.buyTrailer({ index: 1, allowed: false }); a.scope.buyTrailer({ index: '1); x(', allowed: true })
  a.scope.buyTrailer({ index: 1.5, allowed: true }); a.scope.buyTrailer(null)
  assert.equal(a.commands.length, count, 'refused unless allowed, with a whole index')
  a.scope.buyTrailer({ index: 3, allowed: true }); assert.equal(a.commands.at(-1), fixed('buyTrailer(3)'))
  const buttons = {
    cancelStoreTrailer: ['storeArmed', 'cancelStoreTrailer()'],
    bringOutTrailer: ['bringOutAllowed', 'bringOutTrailer()'], sellTrailer: ['sellAllowed', 'sellTrailer()'],
    repairTrailer: ['repairAllowed', 'repairTrailer()']
  }
  for (const [name, [flag, body]] of Object.entries(buttons)) {
    count = a.commands.length
    a.state({ state: 'READY', trailer: {} }); a.scope[name]()
    assert.equal(a.commands.length, count, name + ' refused when not allowed')
    a.state({ state: 'READY', trailer: { [flag]: true } }); a.scope[name]()
    assert.equal(a.commands.at(-1), fixed(body), name)
  }
  // Storing goes to a place: the base (Park at base or Send to base) or the depot, each when allowed.
  count = a.commands.length
  a.state({ state: 'READY', trailer: {} }); a.scope.storeTrailer('base'); a.scope.storeTrailer('depot')
  a.state({ state: 'READY', trailer: { parkAllowed: true, depotAllowed: true } }); a.scope.storeTrailer('garage')
  assert.equal(a.commands.length, count, 'refused unless allowed, and only to the base or the depot')
  a.scope.storeTrailer('base'); assert.equal(a.commands.at(-1), fixed("storeTrailer('base')"))
  a.state({ state: 'READY', trailer: { sendAllowed: true } }); a.scope.storeTrailer('base'); assert.equal(a.commands.at(-1), fixed("storeTrailer('base')"), 'Send to base')
  a.state({ state: 'READY', trailer: { depotAllowed: true } }); a.scope.storeTrailer('depot'); assert.equal(a.commands.at(-1), fixed("storeTrailer('depot')"))
  a.state({ state: 'READY', trailer: { storeArmed: 'depot' } }); a.scope.storeTrailer('depot'); assert.equal(a.commands.at(-1), fixed("storeTrailer('depot')"), 'confirm after the warning')
  // Your trailers: Hitch, Swap and Sell on each parked trailer, by its place on the list.
  count = a.commands.length
  a.scope.hitchSpareTrailer({ index: 1, hitchAllowed: false }); a.scope.swapTrailers({ index: 1 })
  a.scope.hitchSpareTrailer({ index: '1); x(', hitchAllowed: true }); a.scope.sellSpareTrailer({ index: 0 }); a.scope.sellSpareTrailer(null)
  assert.equal(a.commands.length, count, 'refused unless allowed, with a whole place on the list')
  a.scope.hitchSpareTrailer({ index: 2, hitchAllowed: true }); assert.equal(a.commands.at(-1), fixed('hitchSpareTrailer(2)'))
  a.scope.swapTrailers({ index: 1, swapAllowed: true }); assert.equal(a.commands.at(-1), fixed('swapTrailers(1)'))
  a.scope.swapTrailers({ index: 3, swapArmed: true }); assert.equal(a.commands.at(-1), fixed('swapTrailers(3)'), 'confirm a swap')
  a.scope.sellSpareTrailer({ index: 2 }); assert.equal(a.commands.at(-1), fixed('sellSpareTrailer(2)'))
})

test('trailer parts cannot be bought: no button for them', () => {
  const a = app()
  for (const name of ['buyTrailerParts', 'payTrailerParts', 'undoTrailerParts']) assert.equal(a.scope[name], undefined, name)
  assert.ok(!html.includes('Buy trailer parts'), 'no Buy trailer parts button')
})

test('paying a bill asks to confirm that total, and a new total asks again', () => {
  const a = app()
  a.state({ state: 'READY', partsChange: { cost: 500 }, buyPartsAllowed: true })
  assert.equal(a.scope.isConfirming('parts', 500), false)
  a.scope.askToPay('parts', 500)
  assert.equal(a.scope.isConfirming('parts', 500), true, 'asks to confirm')
  assert.equal(a.scope.isConfirming('parts', 650), false, 'a changed bill asks again')
  assert.equal(a.scope.isConfirming('car', 500), false)
  a.scope.cancelPay(); assert.equal(a.scope.isConfirming('parts', 500), false, 'cancelled')
  assert.ok(html.includes('ng-click="cancelPay(); buyParts()"') && html.includes('ng-click="cancelPay(); buyCar()"'), 'only the confirm pays')
  assert.ok(html.includes('ng-click="cancelPay(); keepCar()"') && html.includes('ng-click="cancelPay(); claimHome()"'), 'keeping a car and buying a home confirm too')
})
test('Base: Buy this spot only calls Lua when it allows it, and Base is a tab', () => {
  const a = app()
  assert.ok(a.scope.tabs.some(t => t.id === 'home' && t.label === 'Base'))
  let count = a.commands.length
  a.state({ state: 'READY' }); a.scope.claimHome()
  a.state({ state: 'READY', home: { claimAllowed: false } }); a.scope.claimHome()
  assert.equal(a.commands.length, count, 'refused unless allowed')
  a.state({ state: 'READY', home: { claimAllowed: true } }); a.scope.claimHome()
  assert.equal(a.commands.at(-1), fixed('claimHome()'))
  assert.ok(html.includes("ng-if=\"tab === 'home'\""), 'the Home tab has a panel')
  assert.ok(html.includes("bookShipping('home')"), 'Relocate lists home')
})
test('Your cars: Drive and Sell only send a plain slot number, when Lua allows them', () => {
  const a = app()
  const count = a.commands.length
  a.scope.swapCars({ index: 1, driveAllowed: false }); a.scope.sellParkedCar({ index: 1, sellAllowed: false })
  a.scope.swapCars({ index: '1); evil(', driveAllowed: true }); a.scope.sellParkedCar({ index: 0, sellAllowed: true })
  a.scope.swapCars(null)
  assert.equal(a.commands.length, count, 'refused')
  a.scope.swapCars({ index: 2, driveAllowed: true })
  assert.equal(a.commands.at(-1), fixed('swapCars(2)'))
  a.scope.sellParkedCar({ index: 3, sellAllowed: true })
  assert.equal(a.commands.at(-1), fixed('sellParkedCar(3)'))
  assert.equal(JSON.stringify(a.scope.fleetEmpty({ used: 2, slots: 5 })), '[3,4,5]', 'the empty slots are numbered')
  assert.ok(html.includes('ng-click="cancelPay(); sellParkedCar(car)"'), 'Sell confirms first')
  const before = a.commands.length
  a.state({ state: 'READY', fleet: { buySlot: { price: 200000 } } }); a.scope.buyCarSlot()
  assert.equal(a.commands.length, before, 'Buy a 4th slot refused unless allowed')
  a.state({ state: 'READY', fleet: { buySlot: { price: 200000, allowed: true } } }); a.scope.buyCarSlot()
  assert.equal(a.commands.at(-1), fixed('buyCarSlot()'))
  assert.ok(html.includes('ng-click="cancelPay(); buyCarSlot()"'), 'buying a slot confirms first')
})
test('town buttons only send fixed commands, with plain ids, when Lua enabled them', () => {
  const a = app()
  const job = { id: 'food_gn1', allowed: false }
  a.state({ state: 'READY', town: { jobs: [job], delivery: { allowed: false } } })
  a.scope.takeJob(job); a.scope.deliverJob(); a.scope.refuel()
  assert.equal(a.commands.length, 1)
  a.state({ state: 'READY', town: { refuelAllowed: true, delivery: { allowed: true } } })
  a.scope.takeJob({ id: "food_gn1') os.exit() --", allowed: true }); a.scope.takeJob(null)
  assert.equal(a.commands.length, 1, 'odd ids never sent')
  a.state({ state: 'READY', town: {}, load: { to: 'X' } })
  a.scope.takeJob({ id: 'food_gn1', allowed: true })
  assert.equal(a.commands.length, 1, 'not with a job on board')
  a.state({ state: 'READY', town: { delivery: { allowed: true } }, refuel: { allowed: true } })
  a.scope.takeJob({ id: 'food_gn2153471', allowed: true })
  assert.equal(a.commands.at(-1), fixed("takeJob('food_gn2153471', 100)"), 'a full load unless the slider moved')
  a.scope.shares.food_gn2153471 = '50'
  a.scope.takeJob({ id: 'food_gn2153471', allowed: true })
  assert.equal(a.commands.at(-1), fixed("takeJob('food_gn2153471', 50)"), 'the slider share')
  for (const odd of ['55', '0', '120', 'x); os.exit(', -10]) {
    a.scope.shares.food_gn2153471 = odd
    a.scope.takeJob({ id: 'food_gn2153471', allowed: true })
    assert.equal(a.commands.at(-1), fixed("takeJob('food_gn2153471', 100)"), 'odd shares take it all: ' + odd)
  }
  a.scope.deliverJob(); assert.equal(a.commands.at(-1), fixed('deliverJob()'))
  a.scope.refuel(); assert.equal(a.commands.at(-1), fixed('refuel()'))
})
test('the load slider shows a straight share of weight and pay as Lua works it out', () => {
  const a = app()
  const job = { id: 'bricks_gn1', units: 6, unitKg: 150, pay: 2400, allowed: true }
  a.state({ state: 'READY', town: { jobs: [job] } })
  assert.deepEqual({ ...a.scope.taken(job) }, { units: 6, kg: 900, pay: 2400 }, 'a full load to start')
  a.scope.shares.bricks_gn1 = '50'
  assert.equal(a.scope.shareOf(job), 50)
  assert.deepEqual({ ...a.scope.taken(job) }, { units: 3, kg: 450, pay: 1200 }, 'Bricks, 50%: 450 kg, $1,200')
  a.scope.shares.bricks_gn1 = '10'
  assert.deepEqual({ ...a.scope.taken(job) }, { units: 1, kg: 150, pay: 400 }, 'at least one unit')
  const three = { id: 'food_gn1', units: 3, unitKg: 50, pay: 1000 }
  a.scope.shares.food_gn1 = 50
  assert.deepEqual({ ...a.scope.taken(three) }, { units: 2, kg: 100, pay: 670 }, 'whole units, tens of dollars')
  assert.ok(html.includes('type="range" min="10" max="100" step="10" ng-model="shares[j.id]"'), 'a slider on each job')
})
test('the off-road drop delivers from the Route tab only when Lua allows it, with its arrow turned', () => {
  const a = app()
  const drop = { distanceMetres: 1500, arrow: 90, inZone: false, radiusMetres: 100, delivery: { allowed: false, problem: 'Drive to the drop spot' } }
  a.state({ state: 'READY', load: { to: 'off-road drop', pay: 1700, drop } })
  a.scope.deliverJob(); assert.equal(a.commands.length, 1, 'not out of the zone')
  assert.equal(a.scope.tabAlert('route'), false)
  drop.inZone = true; drop.delivery = { allowed: true }
  a.scope.deliverJob(); assert.equal(a.commands.at(-1), fixed('deliverJob()'), 'delivered in the zone')
  assert.equal(a.scope.tabAlert('route'), true, 'the Route tab asks for attention')
  assert.equal(a.scope.arrowStyle(drop).transform, 'rotate(90deg)', 'the arrow turns right for a spot to the right')
  assert.equal(a.scope.arrowStyle({}).transform, 'rotate(0deg)', 'and points ahead without a heading')
  assert.ok(html.includes('ng-if="data.load.drop && (!data.load.contract || data.load.contract.started)"') && html.includes('ng-style="arrowStyle(data.load.drop)"'), 'the Route tab shows the arrow')
  assert.ok(html.includes('off-road drop'), 'the board names the drop')
})
test('a fluid job shows litres, or that it needs a tank', () => {
  const a = app()
  const water = { id: 'water_gn1', fluid: true, units: 40, unitLitres: 10, unitKg: 10, pay: 1320, allowed: true }
  a.state({ state: 'READY', town: { jobs: [water] } })
  a.scope.shares.water_gn1 = '50'
  assert.deepEqual({ ...a.scope.taken(water) }, { units: 20, kg: 200, pay: 660 }, 'half a tank: 200 L, 200 kg')
  assert.ok(html.includes('taken(j).units * j.unitLitres'), 'the board shows litres')
  assert.ok(html.includes('Needs a tank'), 'and says when a tank is needed')
  assert.ok(html.includes('L of {{data.load.good | lowercase}}'), 'the job banner shows litres')
})
test('insurance is only claimed when Lua offers it', () => {
  const a = app()
  a.state({ state: 'READY', insurance: { allowed: false } }); a.scope.claimInsurance()
  assert.equal(a.commands.length, 1)
  a.state({ state: 'READY', insurance: { allowed: true } }); a.scope.claimInsurance()
  assert.equal(a.commands.at(-1), fixed('claimInsurance()'))
})
test('an insurance debt is only paid off when Lua allows it', () => {
  const a = app()
  a.state({ state: 'READY', insuranceDebt: { owed: 5000, payAllowed: false } }); a.scope.payInsurance()
  assert.equal(a.commands.length, 1)
  a.state({ state: 'READY', insuranceDebt: { owed: 5000, payAllowed: true } }); a.scope.payInsurance()
  assert.equal(a.commands.at(-1), fixed('payInsurance()'))
  assert.ok(html.includes('ng-click="payInsurance()"'), 'a Pay off button')
})
test('towing is only asked for when Lua allows it, from the Repair card, with the steps shown', () => {
  const a = app()
  a.state({ state: 'READY', tow: { allowed: false, fee: 500 } }); a.scope.towHere(); a.scope.payTow(); a.scope.getOut()
  assert.equal(a.commands.length, 1)
  a.state({ state: 'READY', tow: { allowed: true, payAllowed: true, getOutAllowed: true, fee: 500 } })
  a.scope.towHere(); assert.equal(a.commands.at(-1), fixed('towHere()'))
  a.scope.payTow(); assert.equal(a.commands.at(-1), fixed('payTow()'))
  a.scope.getOut(); assert.equal(a.commands.at(-1), fixed('getOut()'))
  const repair = html.slice(html.indexOf('>Repair</div>'), html.indexOf('>Fuel</div>'))
  for (const part of ['ng-click="towHere()"', 'ng-click="payTow()"', 'ng-click="getOut()"', 'get out of your car', 'within {{data.tow.range}} m']) {
    assert.ok(repair.includes(part), part)
  }
  assert.ok(!html.includes('towToRoad'), 'no Tow to road button')
  assert.ok(repair.includes('<span ng-if="!(data.tow.fee > 0)">, free</span>'), 'a free tow says so')
})
test('a tow fee owed, or being on foot, turns off Buy parts and Buy new car', () => {
  const a = app()
  a.state({ state: 'READY', garageLocked: 'Pay the $500 tow fee on the Repair card first.' })
  const before = a.commands.length
  a.scope.openPartsMenu(); a.scope.openCarMenu()
  assert.equal(a.commands.length, before, 'the game menus stay shut')
  assert.ok(html.includes('ng-click="openPartsMenu()" ng-disabled="data.garageLocked"'), 'Buy parts off')
  assert.ok(html.includes('ng-click="openCarMenu()" ng-disabled="data.garageLocked"'), 'Buy new car off')
  assert.ok(html.includes('ng-click="openUsedCars(true)" ng-disabled="data.garageLocked"'), 'Buy second hand off')
})
test('colours: green above the usual pay, red below, gold for a shortage or jackpot', () => {
  const a = app()
  assert.equal(a.scope.dotColor('high'), '#6fcf97'); assert.equal(a.scope.dotColor('low'), '#eb5757')
  assert.equal(a.scope.dotColor('sweet'), '#f2c94c'); assert.equal(a.scope.dotColor('normal'), '#7d8b88')
})
test('a serious crash opens the Garage tab, and a shortage marks the Route tab without opening it', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true }); a.scope.setTab('relocate')
  a.state({ state: 'READY', arrived: true, shortages: [{ town: 'Katoomba' }] })
  assert.equal(a.scope.tab, 'relocate'); assert.equal(a.scope.tabAlert('route'), true)
  a.state({ state: 'READY', arrived: true, insurance: { allowed: true } })
  assert.equal(a.scope.tab, 'garage'); assert.equal(a.scope.tabAlert('garage'), true)
  assert.equal(a.scope.tabAlert('town'), false)
  a.state({ state: 'READY', arrived: true, town: { jobs: [{ id: 'x', allowed: true }] } })
  assert.equal(a.scope.tabAlert('town'), true, 'a job to take marks the Town tab')
})
test('arriving in a town opens the Town tab once, and leaving goes back to Route', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.tab, 'route')
  a.state({ state: 'READY', arrived: true, town: { jobs: [] } })
  assert.equal(a.scope.tab, 'town')
  a.scope.setTab('garage'); a.state({ state: 'READY', arrived: true, town: { jobs: [] } })
  assert.equal(a.scope.tab, 'garage', 'the player can switch away')
  a.scope.setTab('town'); a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.tab, 'route')
  a.state({ state: 'READY', arrived: true, partsChange: { cost: 1 } })
  assert.equal(a.scope.tab, 'garage', 'a bill opens the Garage')
  assert.equal(a.scope.tabAlert('garage'), true)
})
test('one message: what just happened, then what to do, reused for Angular', () => {
  const a = app()
  assert.equal(a.scope.notice({ state: 'READY', arrived: true }), null, 'nothing to say while driving')
  const lost = a.scope.notice({ state: 'READY', arrived: true, flash: { kind: 'cancelled', title: 'LOAD LOST', text: 'x' } })
  assert.equal(lost.title, 'LOAD LOST'); assert.equal(lost.alert, true)
  const go = a.scope.notice({ state: 'READY', stateLabel: 'GO TO PENRITH', sessionStatus: 'Copy these' })
  assert.equal(go.title, 'GO TO PENRITH'); assert.equal(go, lost, 'the same object every time')
})
test('stale backend removes Save authorization, and destruction releases the timer', () => {
  const a = app()
  a.state({ state: 'READY', saveAllowed: true })
  a.advance(6001)
  assert.equal(a.scope.data.saveAllowed, false)
  a.handlers.$destroy()
  assert.equal(a.timers.size, 0)
  assert.match(a.commands.at(-1), /uiMounted\(false\)/)
})
test('coordinates copy as one latitude, longitude pair through the game clipboard', () => {
  const a = app()
  a.scope.copyCoordinates({ latitude: -33.75, longitude: 150.7 })
  assert.equal(a.commands.at(-1), 'setClipboard("-33.75000000, 150.70000000")')
  const count = a.commands.length
  for (const invalid of [null, {}, { latitude: 91, longitude: 0 }, { latitude: '0); x()', longitude: 0 }]) a.scope.copyCoordinates(invalid)
  assert.equal(a.commands.length, count)
})
test('the Ko-fi link sits only at the bottom of the start page, opens the browser and copies the link', () => {
  const a = app()
  a.scope.openKofi()
  assert.equal(a.commands.at(-1), 'if openWebBrowser then openWebBrowser("https://ko-fi.com/madmerick") end setClipboard("https://ko-fi.com/madmerick")')
  assert.equal(a.scope.intro.kofiOpened, true)
  const start = html.indexOf('class="ef-start"'), rest = html.indexOf('<div ng-if="!hud.minimised && !intro.open">', start)
  const at = html.indexOf('ng-click="openKofi()"')
  assert.ok(at > start && at < rest && at > html.indexOf('ng-click="newGame()"'), 'below Start over, on the start page')
  assert.equal(html.split('openKofi()').length, 2, 'nowhere else in the HUD')
})
test('the HUD keeps money, Save, the message and the load outside the tabs', () => {
  const panels = html.indexOf('role="tabpanel"')
  for (const always of ['ng-click="save()"', 'data.balance', 'notice(data)', 'trip(data).to', 'data.fuel.litres', 'copyCoordinates(data.resume)']) {
    assert.ok(html.indexOf(always) > -1 && html.indexOf(always) < panels, always)
  }
  for (const id of ['route', 'town', 'garage', 'relocate', 'heli']) assert.ok(html.includes(`ng-if="tab === '${id}'"`), id)
  for (const action of ['cancelPay(); buyParts()', 'revertParts()', 'cancelPay(); buyCar()', 'revertCar()', 'requestRepairQuote()', 'repairVehicle()',
    'newGame()', 'cancelNewGame()', 'deliverJob()', 'refuel()', 'abandonJob()', 'takeJob(j)', 'claimInsurance()', 'teleportToResume()', 'startHere()']) {
    assert.ok(html.includes(`ng-click="${action}"`), action)
  }
  assert.ok(html.includes('GeoNames'), 'GeoNames credit')
})
test('the Tips tab is gone and shipping has its own Relocate tab', () => {
  const a = app()
  assert.deepEqual([...a.scope.tabs.map(t => t.id)], ['route', 'town', 'garage', 'relocate', 'heli', 'home', 'streetview', 'radio', 'mayday', 'race'])
  assert.ok(!html.includes(`tab === 'tips'`), 'no Tips tab')
  const garage = html.slice(html.indexOf(`ng-if="tab === 'garage'"`), html.indexOf(`ng-if="tab === 'relocate'"`))
  const shipping = html.slice(html.indexOf(`ng-if="tab === 'relocate'"`))
  for (const card of ['Relocation paid:', 'Book relocation', 'bookOffer()', 'openBigMap()', 'cancelShipping()']) {
    assert.ok(shipping.includes(card), card); assert.ok(!garage.includes(card), card + ' not on the Garage tab')
  }
  a.state({ state: 'READY', arrived: true, shipping: { booking: { name: 'La Paz' } } })
  assert.equal(a.scope.tabAlert('relocate'), true, 'a booking marks the Relocate tab')
  assert.equal(a.scope.tabAlert('garage'), false, 'and not the Garage tab')
  const start = html.slice(0, html.indexOf('role="tabpanel"'))
  assert.ok(start.includes('GeoNames'), 'credit on the start page')
  for (const gone of ['addTestMoney', 'test money', 'testContracts', 'testTeleport']) assert.ok(!html.includes(gone), gone + ' is gone')
})
test('the start page opens once on a new game, and again after the next new game', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  assert.equal(a.scope.intro.open, true, 'opens on a new game')
  assert.equal(a.scope.intro.name, 'Sam', 'with the saved name filled in')
  a.scope.closeIntro()
  assert.equal(a.scope.intro.open, false)
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  assert.equal(a.scope.intro.open, false, 'stays closed')
  a.state({ state: 'READY', mode: 'resume' }); a.state({ state: 'READY', mode: 'start' })
  assert.equal(a.scope.intro.open, true, 'opens after another new game')
  const b = app()
  b.state({ state: 'READY', mode: 'resume' })
  assert.equal(b.scope.intro.open, true, 'opens on loading a save, to show the way back')
  assert.equal(b.scope.returning({ mode: 'resume', arrived: false, resume: {} }), true)
  b.scope.closeIntro(); b.state({ state: 'READY', mode: 'resume' })
  assert.equal(b.scope.intro.open, false, 'Continue closes it')
  b.state({ state: 'READY', mode: 'resume', arrived: true })
  assert.equal(b.scope.intro.open, false, 'not shown again once back at the save')
  assert.equal(b.scope.returning(b.scope.data), false)
  b.scope.openIntro()
  assert.equal(b.scope.intro.open, true, 'opens from the Profile button')
  b.scope.closeIntro(); b.state({ state: 'READY', mode: 'resume', arrived: false })
  assert.equal(b.scope.intro.open, true, 'opens again on the next load')
  assert.ok(html.includes("firstLaunch(data) ? 'Choose my start on the map' : 'Back to the road'"), 'Back to the road, except on a brand new game')
  assert.ok(html.includes('ng-click="openIntro()"'), 'Profile button')
})
test('starting over lives on the start page behind a confirm, and closing the page cancels it', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'start', arrived: false, newGameAllowed: true })
  assert.equal(a.scope.firstLaunch(a.scope.data), true, 'nothing to start over before reaching the start town')
  a.state({ state: 'READY', mode: 'resume', arrived: true, newGameAllowed: true })
  assert.equal(a.scope.firstLaunch(a.scope.data), false)
  let count = a.commands.length
  a.scope.cancelNewGame()
  assert.equal(a.commands.length, count, 'nothing to cancel until it asks to confirm')
  a.scope.openIntro(); a.scope.closeIntro()
  assert.equal(a.commands.length, count, 'closing the page sends nothing when not asking')
  a.state({ state: 'READY', mode: 'resume', arrived: true, newGameAllowed: true, newGameArmed: true })
  a.scope.cancelNewGame()
  assert.equal(a.commands.at(-1), fixed('cancelNewGame()'), 'Keep my game')
  a.scope.openIntro(); count = a.commands.length; a.scope.closeIntro()
  assert.equal(a.commands.at(-1), fixed('cancelNewGame()'), 'closing the page keeps the game')
  assert.ok(a.commands.length > count)
  assert.ok(html.indexOf('ng-click="newGame()"') < html.indexOf('role="tabpanel"'), 'it is on the start page')
})
test('closing the parts menu or the map keeps the tab and does not reopen the start page', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  a.scope.closeIntro(); a.scope.setTab('garage')
  a.remount(); a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  assert.equal(a.scope.intro.open, false, 'start page stays closed')
  assert.equal(a.scope.tab, 'garage', 'same tab as before')
  a.state({ state: 'READY', mode: 'start', town: {} }); a.scope.setTab('relocate')
  a.remount(); a.state({ state: 'READY', mode: 'start', town: {} })
  assert.equal(a.scope.tab, 'relocate', 'a town already there does not open the Town tab again')
  a.scope.openIntro(); a.scope.intro.name = 'Al'
  a.remount(); a.state({ state: 'READY', mode: 'start', town: {} })
  assert.equal(a.scope.intro.open, true, 'a start page left open stays open')
  assert.equal(a.scope.intro.name, 'Al', 'with what was typed')
  a.scope.closeIntro(); a.state({ state: 'READY', mode: 'resume' }); a.remount(); a.state({ state: 'READY', mode: 'start' })
  assert.equal(a.scope.intro.open, true, 'a new game still opens it')
})
test('the name is cleaned, kept short and only sent when it changed', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  a.scope.intro.name = 'Sam'
  let count = a.commands.length
  a.scope.closeIntro()
  assert.equal(a.commands.filter(c => c.includes('setPlayerName')).length, 0, 'unchanged name not sent')
  a.scope.openIntro(); a.scope.intro.name = '  Zoë   O\'Neil "); x() '
  a.scope.closeIntro()
  assert.equal(a.commands.at(-1), fixed('setPlayerName("Zoë O\'Neil x")'), 'quotes and brackets taken out')
  assert.equal(a.scope.cleanName('A'.repeat(30)).length, 20, 'at most 20 letters')
  assert.equal(a.scope.cleanName('\\"\n\t'), '', 'no quotes, backslashes or control characters')
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' }); a.scope.openIntro(); a.scope.intro.name = ''
  count = a.commands.length; a.scope.closeIntro()
  assert.equal(a.commands[count], fixed('setPlayerName("")'), 'an empty box clears the name')
})
test('typing in a text box turns the game keys off, so it does not drive the car', () => {
  const a = app()
  a.scope.typing(true)
  assert.equal(a.commands.at(-1), 'if setCEFTyping then setCEFTyping(true) end')
  const count = a.commands.length
  a.scope.typing(true)
  assert.equal(a.commands.length, count, 'sent once')
  a.handlers.$destroy()
  assert.ok(a.commands.includes('if setCEFTyping then setCEFTyping(false) end'), 'keys back on when the HUD closes')
  for (const box of ['intro.name', 'ship.coords']) {
    assert.match(html, new RegExp(`ng-model="${box.replace('.', '\\.')}" [^>]*ng-focus="typing\\(true\\)" ng-blur="typing\\(false\\)"`), box)
  }
})
test('a changed name lights up Save', () => {
  const a = app()
  assert.equal(a.scope.unsaved({ nameUnsaved: true }), true)
  assert.equal(a.scope.unsaved({ nameUnsaved: false }), false)
})
test('With only the boot, the Town tab and the start steps say to fit cargo boxes', () => {
  const a = app()
  const town = html.slice(html.indexOf("tab === 'town'"), html.indexOf("tab === 'garage'"))
  const hint = town.slice(town.indexOf('ng-if="data.space.boot"'), town.indexOf('aria-label="Distance"'))
  assert.ok(hint.includes('rear seat slot') && hint.includes('ng-click="openPartsMenu()"'), 'a boot-only hint with Buy parts')
  const radiator = a.scope.introSteps.findIndex(s => s.includes('radiator'))
  assert.match(a.scope.introSteps[radiator + 1], /cargo boxes.*rear seat slot/, 'cargo boxes come right after the radiator')
})
test('Refuel sits on the Garage tab, and the Town tab has no cargo slots card', () => {
  const a = app()
  const town = html.slice(html.indexOf("tab === 'town'"), html.indexOf("tab === 'garage'"))
  const garage = html.slice(html.indexOf("tab === 'garage'"), html.indexOf("tab === 'relocate'"))
  assert.ok(!town.includes('ng-click="refuel()"') && garage.includes('ng-click="refuel()"'), 'Refuel moved to the Garage tab')
  assert.ok(garage.includes('{{data.fuelFeedback}}'), 'refuel messages show by the button')
  assert.ok(!html.includes('Cargo slots') && !html.includes('Buy more cargo space'), 'the cargo slots card is gone')
  assert.equal(a.scope.cargoRoom, undefined)
  assert.ok(garage.includes('ng-click="openPartsMenu()"'), 'Buy parts still opens the parts menu')
  a.scope.openPartsMenu()
  assert.match(a.commands.at(-1), /core_vehicles\.openPartsSelectorUI\(\)/)
  assert.match(a.commands.at(-1), /menu\.vehicleconfig\.parts/)
  assert.match(a.commands.at(-2), /earthFreight_core\.partsMenuOpening\(\)/, 'Lua notes the camera before the menu opens')
})
test('the HUD minimises to a Worldwide Trucking button, and stays that way after a rebuild or a restart', () => {
  const saved = {}
  const storage = { getItem: k => (k in saved ? saved[k] : null), setItem: (k, v) => { saved[k] = String(v) } }
  const a = app(storage)
  assert.equal(a.scope.hud.minimised, false)
  a.state({ state: 'READY', mode: 'free' })
  a.scope.setMinimised(true)
  assert.equal(a.scope.hud.minimised, true)
  assert.equal(a.remount().scope.hud.minimised, true, 'kept when BeamNG rebuilds the app')
  assert.equal(app(storage).scope.hud.minimised, true, 'kept after the game restarts')
  a.scope.setMinimised(false)
  assert.equal(app(storage).scope.hud.minimised, false)
  assert.equal(app().scope.hud.minimised, false, 'starts open without storage')
  assert.ok(html.includes('ng-if="hud.minimised && !intro.open" ng-click="setMinimised(false)"') && html.includes('>Worldwide Trucking<'))
  assert.ok(html.includes('ng-click="setMinimised(true)"'), 'the header has a minimise button')
  assert.ok(/ng-style="hud\.minimised \|\| intro\.open \? \{[^}]*\} : \{height:'100%'[^}]*background:'rgba/.test(html), 'the full HUD gets its look back when reopened')
  assert.ok(html.indexOf('ng-click="setMinimised(true)"') > html.indexOf('<div ng-if="!hud.minimised && !intro.open">'), 'hidden while the start page is open')
})
test('a minimised HUD shrinks its box to the button, so no empty outline is left behind', () => {
  const box = { style: { width: '380px', height: '620px' } }
  const a = app(undefined, [{ parentElement: box }])
  a.scope.setMinimised(true)
  assert.deepEqual(box.style, { width: 'auto', height: 'auto' }, 'shrinks to the button')
  a.remount()
  assert.deepEqual(box.style, { width: 'auto', height: 'auto' }, 'still small after BeamNG rebuilds the app')
  a.scope.setMinimised(false)
  assert.deepEqual(box.style, { width: '380px', height: '620px' }, 'the full size comes back on open')
  a.scope.setMinimised(true); a.handlers.$destroy()
  assert.deepEqual(box.style, { width: '380px', height: '620px' }, 'a removed app hands its box back full size')
  app().scope.setMinimised(true)
})
test('a minimised HUD lights its dot for anything waiting and opens only for what needs the player', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'free' })
  a.scope.setMinimised(true)
  assert.equal(a.scope.hudAlert(), '')
  a.state({ state: 'READY', mode: 'free', shortages: [{ id: 'x' }] })
  assert.equal(a.scope.hudAlert(), 'waiting'); assert.equal(a.scope.hud.minimised, true, 'a shortage only lights the dot')
  a.state({ state: 'READY', mode: 'free', town: { jobs: [{ allowed: true }] } })
  assert.equal(a.scope.hudAlert(), 'waiting'); assert.equal(a.scope.hud.minimised, true, 'arriving in a town only lights the dot')
  a.state({ state: 'READY', mode: 'free', flash: { kind: 'cancelled', title: 'x', text: 'y' } })
  assert.equal(a.scope.hudAlert(), 'bad'); assert.equal(a.scope.hud.minimised, true)
  a.state({ state: 'READY', mode: 'free', insurance: { allowed: true } })
  assert.equal(a.scope.hud.minimised, false, 'an insurance offer opens it'); assert.equal(a.scope.tab, 'garage')
  for (const extra of [{ partsChange: {} }, { carChange: {} }, { stranded: {} }]) {
    a.state({ state: 'READY', mode: 'free' }); a.scope.setMinimised(true)
    a.state({ state: 'READY', mode: 'free', ...extra })
    assert.equal(a.scope.hud.minimised, false, Object.keys(extra)[0] + ' opens it')
  }
  a.state({ state: 'READY', mode: 'free' }); a.scope.setMinimised(true)
  a.state({ state: 'READY', mode: 'start' })
  assert.equal(a.scope.intro.open, true, 'the start page opens')
  assert.equal(a.scope.hud.minimised, true, 'over a HUD that stays minimised for after')
})
test('the Garage tab card has Buy parts and Buy new car buttons, and no shortcut keys are shown', () => {
  const a = app()
  const garage = html.slice(html.indexOf("tab === 'garage'"), html.indexOf("tab === 'relocate'"))
  const card = garage.indexOf('ng-if="!data.carChange && !data.partsChange && !data.usedCars"')
  const inside = garage.slice(card, garage.indexOf('Cargo space'))
  assert.ok(card > 0, 'the buttons are on the Garage tab')
  assert.ok(inside.includes('ng-click="openPartsMenu()"') && inside.includes('>Buy parts</button>'), 'Buy parts is in the card')
  assert.ok(inside.includes('ng-click="openCarMenu()"') && inside.includes('>Buy new car</button>'), 'Buy new car is in the card')
  assert.doesNotMatch(html, /Ctrl\+[WE]/)
  a.scope.openCarMenu()
  assert.match(a.commands.at(-1), /core_input_actions\.triggerDownUp\('vehicle_selector'\)/, 'the same action as Ctrl+E')
  assert.doesNotMatch(a.commands.at(-1), /menu\.vehicles/, 'not the old route, which hides the UI')
})
test('a dangerous contract shows on the board and teleports to its start only when Lua allows it', () => {
  assert.match(html, /Dangerous contract/)
  assert.match(html, /ng-click="teleportToContract\(\)"/)
  const a = app()
  const contract = { name: 'Death Road', started: false, start: { latitude: -16.287, longitude: -67.815 }, insurance: 4000 }
  a.state({ state: 'READY', load: { contract, drop: { delivery: { allowed: false } } } })
  let count = a.commands.length
  a.scope.teleportToContract()
  assert.equal(a.commands.length, count, 'refused when not allowed')
  a.state({ state: 'READY', load: { contract: { ...contract, teleportAllowed: true }, drop: { delivery: { allowed: false } } } })
  a.scope.teleportToContract()
  assert.equal(a.commands.at(-1), fixed('teleportToContract()'))
  assert.equal(a.scope.coordinates(contract.start), '-16.28700000, -67.81500000')
})
test('a relocation booking has a Teleport button next to Copy, sent only when Lua allows it', () => {
  const card = html.slice(html.indexOf('ng-click="copyCoordinates(data.shipping.booking)"'))
  assert.ok(card.indexOf('ng-click="teleportToBooking()"') > 0 && card.indexOf('ng-click="teleportToBooking()"') < card.indexOf('</div>'), 'beside Copy')
  const a = app()
  const booking = { name: 'Coroico', region: 'Death Road', fee: 300, latitude: -16.19, longitude: -67.73 }
  a.state({ state: 'READY', arrived: true, shipping: { booking } })
  const count = a.commands.length
  a.scope.teleportToBooking()
  assert.equal(a.commands.length, count, 'refused when not allowed')
  a.state({ state: 'READY', arrived: true, shipping: { booking: { ...booking, teleportAllowed: true } } })
  a.scope.teleportToBooking()
  assert.equal(a.commands.at(-1), fixed('teleportToBooking()'))
})
test('the HUD has no select box: BeamNG does not open its list', () => {
  assert.doesNotMatch(html, /<select/)
})
test('the parts bill box shows over the parts menu until closed, paid or the menu closes', () => {
  const a = app()
  const bill = { open: true, serial: 3, total: 'Parts bill so far: $600', detail: 'Parts $600, repair $0.', hint: 'Pay or undo on the Garage tab.' }
  const box = () => a.document.body.children[0]
  const words = el => [el.textContent, ...el.children.map(words)].join(' ')
  const text = () => words(box())
  a.handlers.$destroy() // the parts menu hides the HUD; the box does not need it
  a.root.EarthFreightPartsBill({}, bill)
  assert.equal(a.document.body.children.length, 1, 'box shown')
  assert.match(text(), /Parts bill so far: \$600/); assert.match(text(), /Parts \$600, repair \$0\./)
  assert.equal(a.commands.at(-1), fixed('partsBillShown(3)'), 'tells Lua it showed')
  a.root.EarthFreightPartsBill({}, { ...bill, serial: 4, total: 'Parts bill so far: $1,500', money: 'You have $100.', short: 'You are $1,400 short.' })
  assert.equal(a.document.body.children.length, 1, 'a new bill replaces the box')
  assert.match(text(), /\$1,400 short/); assert.match(text(), /You have \$100\./, 'shows the money the player has')
  box().children[0].onclick()
  assert.equal(a.document.body.children.length, 0, 'Close closes it')
  a.root.EarthFreightPartsBill({}, { ...bill, serial: 5, cost: 1500, payAllowed: true,
    lines: [{ label: '+ Cargo Load Box L', amount: '$1,500' }, { label: '- Cargo Load Box M (sold back)', amount: '-$180' }] })
  assert.match(text(), /\+ Cargo Load Box L \$1,500/, 'lists each part with its price'); assert.match(text(), /sold back\) -\$180/)
  assert.doesNotMatch(text(), /Parts \$600, repair/, 'the list replaces the split')
  const pay = box().children.find(c => c.tag === 'button' && /^Pay/.test(c.textContent))
  assert.equal(pay.textContent, 'Pay $1,500')
  const sent = a.commands.length
  pay.onclick()
  assert.equal(pay.textContent, 'Yes, pay $1,500', 'asks once more'); assert.equal(a.commands.length, sent, 'nothing paid yet')
  pay.onclick()
  assert.equal(a.commands.at(-1), fixed('payPartsBill(5)'), 'pays this bill')
  a.root.EarthFreightPartsBill({}, { ...bill, serial: 6, cost: 1500, payAllowed: false })
  assert.ok(!box().children.some(c => c.tag === 'button' && /^Pay/.test(c.textContent)), 'no Pay button when Lua does not allow it')
  a.root.EarthFreightPartsBill({}, { open: false })
  assert.equal(a.document.body.children.length, 0, 'paid or undone closes it')
  a.root.EarthFreightPartsBill({}, bill)
  a.remount()
  assert.equal(a.document.body.children.length, 0, 'the menu closing, which builds the HUD again, closes it')
  a.root.EarthFreightPartsBill({}, { ...bill, serial: 'x); os.exit(' })
  assert.notEqual(a.commands.at(-1), fixed('partsBillShown(NaN)'), 'only a plain number goes back to Lua')
  assert.doesNotMatch(a.commands.at(-1), /os\.exit/)
})

test('the Heli tab hires, goes back to the car, and opens when a hire starts', () => {
  const a = app()
  const heli = html.slice(html.indexOf(`ng-if="tab === 'heli'"`))
  for (const part of ['ng-click="hireHeli()"', 'ng-click="backToCar()"', 'ng-click="openHeliMod()"', 'Needs the {{data.heli.modName}} mod']) {
    assert.ok(heli.includes(part), part)
  }
  a.state({ state: 'READY', arrived: true, heli: { installed: true, hireAllowed: false } })
  a.scope.hireHeli()
  assert.ok(!a.commands.some(c => c.includes('hireHeli')), 'nothing sent while hiring is not allowed')
  a.state({ state: 'READY', arrived: true, heli: { installed: true, hireAllowed: true } })
  a.scope.hireHeli()
  assert.ok(a.commands.includes(fixed('hireHeli()')), 'hire sent')
  a.scope.setTab('route')
  a.state({ state: 'READY', arrived: true, heli: { hired: { stage: 'flying', backAllowed: true, car: {} } } })
  assert.equal(a.scope.tab, 'heli', 'a hire opens the Heli tab')
  a.scope.backToCar()
  assert.ok(a.commands.includes(fixed('backToCar()')), 'back to the car sent')
  assert.equal(a.scope.tabAlert('heli'), false)
  a.state({ state: 'READY', arrived: true, heli: { hired: { stage: 'flying', car: {} } }, beacon: { pickup: {} } })
  assert.equal(a.scope.tabAlert('heli'), true, 'a beacon found in flight marks the tab')
  assert.ok(heli.includes('Towns around you') && heli.includes('Jobs from {{data.heli.hired.here.name}}'), 'scouting: towns and a board')
  assert.ok(!heli.includes('data.heli.hired.load'), 'no loads any more')
  a.state({ state: 'READY', arrived: true, heli: { modPage: 'https://www.beamng.com/threads/x.1/' } })
  a.scope.openHeliMod()
  assert.ok(a.commands.some(c => c.includes('openWebBrowser("https://www.beamng.com/threads/x.1/")')), 'the mod page opens')
  const route = html.slice(html.indexOf(`ng-if="tab === 'route'"`), html.indexOf(`ng-if="tab === 'town'"`))
  assert.ok(route.includes('Heli hired.'), 'the Route tab says a heli is hired')
})

test('a signal beacon shows in the middle of the screen, closes by itself, and is picked up or ignored', () => {
  const a = app()
  a.root.EarthFreightBeacon({}, { title: 'SIGNAL BEACON PICKED UP', text: 'Coordinates for a job.' })
  const box = a.document.body.children[0]
  assert.ok(box, 'box shown'); assert.equal(box.children[0].textContent, 'SIGNAL BEACON PICKED UP')
  assert.equal(a.timeouts.at(-1).ms, 10000, 'closes after 10 seconds')
  a.timeouts.at(-1).fn()
  assert.equal(a.document.body.children.length, 0, 'closed by itself')
  a.root.EarthFreightBeacon({}, { title: 'X', text: 'Y' })
  a.document.body.children[0].onclick()
  assert.equal(a.document.body.children.length, 0, 'a click closes it')
  const count = a.commands.length
  a.state({ state: 'READY', beacon: { pickUpAllowed: false } }); a.scope.pickUpBeacon()
  assert.equal(a.commands.length, count, 'no pickup until Lua allows it')
  a.state({ state: 'READY', beacon: { pickUpAllowed: true } }); a.scope.pickUpBeacon()
  assert.equal(a.commands.at(-1), fixed('pickUpBeacon()'))
  assert.equal(a.scope.tabAlert('route'), true, 'the Route tab is marked at the beacon')
  a.scope.ignoreBeacon(); assert.equal(a.commands.at(-1), fixed('ignoreBeacon()'))
  const route = html.slice(html.indexOf(`ng-if="tab === 'route'"`), html.indexOf(`ng-if="tab === 'town'"`))
  for (const part of ['ng-click="pickUpBeacon()"', 'ng-click="ignoreBeacon()"', 'copyCoordinates(data.beacon.pickup)', "Don't ask questions"]) {
    assert.ok(route.includes(part), part)
  }
})
test('the Distance filter sends its band to Lua, and is kept after a rebuild or a restart', () => {
  const saved = {}
  const storage = { getItem: k => (k in saved ? saved[k] : null), setItem: (k, v) => { saved[k] = String(v) } }
  const a = app(storage)
  assert.equal(a.scope.jobDistance(), 'any', 'starts at Any')
  a.scope.setJobDistance('long')
  assert.equal(a.commands.at(-1), fixed("setJobDistance('long')"))
  assert.equal(a.scope.jobDistance(), 'long')
  const sent = a.commands.length
  a.scope.setJobDistance("x'); os.exit() --")
  assert.equal(a.commands.length, sent, 'only the four choices are sent')
  a.state({ state: 'READY', town: { distance: 'long', jobs: [] } })
  assert.equal(a.commands.length, sent, 'nothing sent while Lua agrees')
  assert.equal(a.remount().scope.jobDistance(), 'long', 'kept when BeamNG rebuilds the app')
  const b = app(storage)
  assert.equal(b.scope.jobDistance(), 'long', 'kept after the game restarts')
  b.state({ state: 'READY', town: { distance: 'any', jobs: [] } })
  assert.equal(b.commands.at(-1), fixed("setJobDistance('long')"), 'sent again when Lua has forgotten it')
  assert.equal(app().scope.jobDistance(), 'any', 'Any without storage')
  assert.equal(b.scope.hasOutside([{ outside: true }]), true)
  assert.equal(b.scope.hasOutside([{}]), false)
  assert.ok(html.includes('ng-click="setJobDistance(o.id)"') && html.includes('j.outside'), 'the Town tab shows the filter and marks jobs outside it')
})
test('conflicting HUD distance filters settle and follow the next explicit selection', () => {
  const saved = { 'earthFreight.jobDistance': 'any' }
  const storage = { getItem: k => saved[k] ?? null, setItem: (k, v) => { saved[k] = String(v) } }
  const a = app(storage)
  saved['earthFreight.jobDistance'] = 'long'
  const b = app(storage)
  const apps = [a, b]
  const commands = () => apps.flatMap(a => a.commands.splice(0)).filter(c => c.includes('setJobDistance('))
  commands()
  let distance = 'any'
  const sent = []
  for (let i = 0; i < 8; i++) {
    for (const a of apps) a.state({ state: 'READY', town: { distance, jobs: [] } })
    const updates = commands()
    sent.push(...updates)
    for (const command of updates) distance = command.match(/setJobDistance\('([a-z]+)'\)/)[1]
  }
  assert.deepEqual(sent, [fixed("setJobDistance('long')")], 'restore once, without Any/Long feedback')
  assert.equal(a.scope.jobDistance(), 'long', 'the highlighted filter follows the board')
  assert.equal(b.scope.jobDistance(), 'long')
  a.scope.setJobDistance('any')
  assert.deepEqual(commands(), [fixed("setJobDistance('any')")])
  for (const a of apps) a.state({ state: 'READY', town: { distance: 'any', jobs: [] } })
  assert.deepEqual(commands(), [], 'the other HUD does not undo the click')
  assert.equal(a.scope.jobDistance(), 'any')
  assert.equal(b.scope.jobDistance(), 'any')
  assert.equal(saved['earthFreight.jobDistance'], 'any', 'the explicit choice is saved')
})

test('distance restoration waits for a valid board and does not retry stale updates', () => {
  const a = app({ getItem: k => k === 'earthFreight.jobDistance' ? 'long' : null, setItem() {} })
  const commands = () => a.commands.filter(c => c.includes('setJobDistance('))
  a.state({ state: 'READY' })
  a.state({ state: 'READY', town: { distance: "x'); os.exit() --" } })
  assert.deepEqual(commands(), [], 'missing and invalid filters do not consume restoration')
  a.state({ state: 'READY', town: { distance: 'any' } })
  a.state({ state: 'READY', town: { distance: 'any' } })
  a.state({ state: 'READY', town: { distance: 'any' } })
  assert.deepEqual(commands(), [fixed("setJobDistance('long')")], 'only one restore is sent')
  assert.equal(a.scope.jobDistance(), 'any', 'later snapshots remain authoritative')
  a.remount().state({ state: 'READY', town: { distance: 'long' } })
  assert.equal(a.scope.jobDistance(), 'long')
})

test('a rebuilt HUD reads the latest saved filter, with a fallback when storage is unavailable', () => {
  const saved = { 'earthFreight.jobDistance': 'long' }
  const a = app({ getItem: k => saved[k] ?? null, setItem: (k, v) => { saved[k] = String(v) } })
  assert.equal(a.scope.jobDistance(), 'long')
  saved['earthFreight.jobDistance'] = 'medium'
  assert.equal(a.remount().scope.jobDistance(), 'medium', 'another menu may have changed the preference')
  a.state({ state: 'READY', town: { distance: 'any' } })
  assert.equal(a.commands.at(-1), fixed("setJobDistance('medium')"))
  const b = app({ getItem() { throw new Error('unavailable') }, setItem() { throw new Error('unavailable') } })
  b.scope.setJobDistance('short')
  b.state({ state: 'READY', town: { distance: 'short' } })
  assert.equal(b.remount().scope.jobDistance(), 'short', 'the in-memory choice still survives a rebuild')
})

test('arriving at the drop-off chimes once, and a minimised HUD button flashes until delivered', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'free', arrived: true })
  a.scope.setMinimised(true)
  assert.equal(a.scope.chimes(), 0)
  a.state({ state: 'READY', mode: 'free', arrived: true, town: { jobs: [], delivery: { allowed: false, problem: 'Stop the car to deliver.' } } })
  assert.equal(a.scope.chimes(), 0, 'not while still moving')
  const there = { state: 'READY', mode: 'free', arrived: true, town: { jobs: [], delivery: { allowed: true } } }
  a.state(there)
  assert.equal(a.scope.chimes(), 1, 'stopped at the drop-off: one chime')
  assert.equal(a.scope.atDestination(), true, 'the button flashes')
  assert.equal(a.scope.hud.minimised, true, 'and the HUD stays minimised')
  a.state(there); a.remount().state(there)
  assert.equal(a.scope.chimes(), 1, 'only once, even after the HUD is rebuilt')
  a.state({ state: 'READY', mode: 'free', arrived: true, town: { jobs: [] } })
  assert.equal(a.scope.atDestination(), false, 'delivered: no more flashing')
  a.state({ state: 'READY', mode: 'free', arrived: true, load: { drop: { delivery: { allowed: true } } } })
  assert.equal(a.scope.chimes(), 2, 'an off-road drop chimes too')
  a.state({ state: 'READY', mode: 'free', arrived: true })
  a.state({ state: 'READY', mode: 'free', arrived: true, beacon: { pickUpAllowed: true } })
  assert.equal(a.scope.chimes(), 3, 'and a beacon ready to pick up')
  assert.ok(html.includes(`ng-class="{'ef-arrive': atDestination(data)}"`) && html.includes('@keyframes efArrive'), 'the minimised button flashes')
})
test('the Nearby list shows each town\'s direction and sets the GPS only when Lua allows it', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true, gpsAllowed: false })
  a.scope.gpsToTown('gn123')
  assert.equal(a.commands.filter(c => c.includes('gpsToTown')).length, 0, 'not when Lua says no')
  a.state({ state: 'READY', arrived: true, gpsAllowed: true })
  a.scope.gpsToTown("gn1'); os.exit() --")
  assert.equal(a.commands.filter(c => c.includes('gpsToTown')).length, 0, 'only plain ids')
  a.scope.gpsToTown('gn123')
  assert.ok(a.commands.includes(fixed("gpsToTown('gn123')")), 'sends the town')
  assert.ok(html.includes('ng-click="gpsToTown(p.id)"') && html.includes('{{p.letters}}'), 'each row has its letters and a GPS button')
})
test('each town job and dangerous contract has a GPS button to see where it goes before taking it', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true, gpsAllowed: true, town: { jobs: [{ id: 'food_gn1', toId: 'gn1' }] } })
  a.scope.gpsToTown('gn1')
  assert.ok(a.commands.includes(fixed("gpsToTown('gn1')")), 'sends the drop-off town')
  assert.equal(a.commands.filter(c => c.includes('takeJob')).length, 0, 'without taking the job')
  a.scope.gpsToContract('death_road')
  assert.ok(a.commands.includes(fixed("gpsToContract('death_road')")), 'a dangerous contract sends its road')
  assert.ok(html.includes('ng-click="j.contract ? gpsToContract(j.contract.id) : gpsToTown(j.toId)"') && html.includes('ng-if="!j.drop" aria-label="Set the GPS'), 'no button on off-road drops')
})

test('folding sections remember how the player left them, and open by themselves when they need the player', () => {
  const saved = {}
  const storage = { getItem: k => (k in saved ? saved[k] : null), setItem: (k, v) => { saved[k] = String(v) } }
  const a = app(storage)
  assert.equal(a.scope.isOpen('nearby'), true, 'Nearby starts open')
  assert.equal(a.scope.isOpen('repair'), false, 'the rest start closed')
  a.scope.toggle('nearby'); a.scope.toggle('repair')
  assert.equal(a.scope.isOpen('nearby'), false); assert.equal(a.scope.isOpen('repair'), true)
  assert.equal(a.remount().scope.isOpen('repair'), true, 'kept when BeamNG rebuilds the app')
  const b = app(storage)
  assert.equal(b.scope.isOpen('nearby'), false, 'kept after the game restarts'); assert.equal(b.scope.isOpen('repair'), true)
  b.scope.toggle('repair')
  assert.equal(b.scope.isOpen('repair', true), true, 'money owed keeps it open')
  saved['earthFreight.hudFolds'] = 'not json'
  assert.equal(app(storage).scope.isOpen('nearby'), true, 'bad storage falls back to the defaults')
  assert.equal(app().scope.isOpen('fuel'), false, 'and so does no storage')
  for (const id of ['nearby', 'dropoff', 'abandon', 'cargo', 'repair', 'tow', 'fuel', 'helitowns', 'heliboard']) {
    assert.ok(html.includes(`ng-click="toggle('${id}')"`), id + ' folds')
  }
  assert.ok(html.includes("isOpen('repair', data.repairOwed > 0 || data.puncture)"), 'a repair owed or a puncture opens Repair')
})
test('one town job at a time opens to show its load slider and GPS', () => {
  const a = app()
  assert.equal(a.scope.jobOpen('bricks_gn1'), false)
  a.scope.toggleJob('bricks_gn1'); assert.equal(a.scope.jobOpen('bricks_gn1'), true)
  a.scope.toggleJob('parts_gn1'); assert.equal(a.scope.jobOpen('bricks_gn1'), false, 'opening another closes it')
  a.scope.toggleJob('parts_gn1'); assert.equal(a.scope.jobOpen('parts_gn1'), false, 'a second press closes it')
  const town = html.slice(html.indexOf("tab === 'town'"), html.indexOf("tab === 'garage'"))
  assert.ok(town.indexOf('ng-click="takeJob(j)"') < town.indexOf('ng-if="jobOpen(j.id)"'), 'Take job is on the row, not hidden')
})
test('the minimised strip shows money, the job and where you are', () => {
  const a = app()
  assert.equal(a.scope.trip({}), null, 'no job')
  const t = a.scope.trip({ load: { to: 'Servoz', distanceMetres: 4900, direction: 'west', pay: 4490 } })
  assert.deepEqual({ ...t }, { to: 'Servoz', metres: 4900, letters: 'W', pay: 4490, danger: false })
  const contract = { name: 'Grimsel Pass', started: false }
  assert.equal(a.scope.trip({ load: { contract, drop: { distanceMetres: 800 }, pay: 1 } }).to, 'Grimsel Pass start', 'a contract not started yet')
  assert.equal(a.scope.trip({ load: { contract, drop: { distanceMetres: 800 }, pay: 1 } }).metres, null, 'with no distance')
  const road = a.scope.trip({ load: { contract: { name: 'Grimsel Pass', started: true }, drop: { distanceMetres: 800 }, pay: 1 } })
  assert.equal(road.metres, 800, 'then the distance to the finish'); assert.equal(road.danger, true, 'in red')
  assert.equal(a.scope.distance(800), '800 m'); assert.equal(a.scope.distance(4900), '4.9 km'); assert.equal(a.scope.distance(null), '')
  assert.equal(a.scope.fuelStyle({ litres: 30, capacity: 60 }).width, '50%')
  assert.equal(a.scope.fuelStyle({ litres: 5, capacity: 60 }).background, '#eb5757', 'red when nearly empty')
  assert.equal(a.scope.flashBad({ flash: { kind: 'puncture' } }), true); assert.equal(a.scope.flashBad({ flash: { kind: 'delivered' } }), false)
  const strip = html.slice(html.indexOf('ng-if="hud.minimised && !intro.open"'), html.indexOf('class="ef-start"'))
  for (const part of ['data.balance', 'trip(data).to', 'data.where.title', 'data.where.area', 'data.where.street', 'DELIVER HERE']) assert.ok(strip.includes(part), part)
})

test('while on a job, the distance left shows big in the job card, almost as large as the money', () => {
  const panels = html.indexOf('role="tabpanel"')
  const card = html.slice(html.indexOf('<div ng-if="data.load && !data.sightseeing.on" style="margin:8px 0 0'), panels)
  const big = card.indexOf('distance(trip(data).metres)')
  assert.ok(big > 0, 'in the job card, above the tabs')
  assert.ok(card.lastIndexOf('font-size:28px', big) > card.lastIndexOf('<div', big), 'in 28 px type, next to the 32 px money')
  assert.ok(card.includes('ng-if="trip(data).metres != null"'), 'hidden until there is a distance, such as before a dangerous contract starts')
})

test('the start page opens in a big window in the middle of the screen, with the HUD hidden until Back to the road', () => {
  const box = { style: { width: '380px', height: '620px' } }
  const startPage = { tag: 'div', parentNode: null }
  const element = [{ parentElement: box, querySelector: q => (q === '.ef-start' ? startPage : null) }]
  const a = app(undefined, element)
  assert.equal(startPage.parentNode, a.document.body, 'moved onto the page, out of the small app box')
  a.state({ state: 'READY', mode: 'resume', arrived: false, resume: {} })
  assert.equal(a.scope.intro.open, true)
  assert.deepEqual(box.style, { width: 'auto', height: 'auto' }, 'the app box shrinks while it is open')
  a.scope.closeIntro()
  assert.deepEqual(box.style, { width: '380px', height: '620px' }, 'and the HUD comes back')
  a.scope.openIntro(); a.remount()
  assert.equal(a.document.body.children.filter(c => c === startPage).length, 1, 'a rebuilt app puts back the one page')
  a.handlers.$destroy()
  assert.equal(startPage.parentNode, null, 'a removed app takes its page away')
  const page = html.slice(html.indexOf('class="ef-start"'), html.indexOf('<div ng-if="!hud.minimised && !intro.open">'))
  assert.ok(page.includes('position:fixed') && page.includes('z-index:2147483646'), 'over the game, under the parts bill and beacon boxes')
  assert.ok(source.includes('z-index:2147483647'), 'which sit one higher')
  for (const part of ['YOUR TRUCK', 'data.car.preview', 'data.car.name', 'data.car.value', 'data.car.repair', 'data.space.slots', 'data.trailer.owned.name',
    'YOUR CAREER', 'data.career.jobsDone', 'data.career.contractsDone', 'climbAt(data.car.climb)', 'RUST BUCKET', 'Welcome back', 'ng-model="intro.name"',
    'ng-click="newGame()"', 'openMap() : closeIntro()', 'earth_freight_starter.jpg']) assert.ok(page.includes(part), part)
})
test('on a new game the page sends the player to the map and opens the HUD for Start here', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'free' }); a.scope.setMinimised(true)
  a.state({ state: 'READY', mode: 'start', arrived: false, startHereAllowed: true })
  assert.equal(a.scope.intro.open, true)
  a.scope.openMap()
  assert.equal(a.scope.intro.open, false, 'Choose my start on the map closes the page')
  assert.equal(a.scope.hud.minimised, false, 'and opens the HUD, where Start here is')
  assert.match(a.commands.at(-1), /freeroam_bigMapMode\.enterBigMap/, 'and opens the map, which on Earth is Earth\'s own')
  assert.ok(html.includes('ng-click="firstLaunch(data) ? openMap() : closeIntro()"'), 'from the big button on a new game')
  const b = app()
  b.state({ state: 'READY', mode: 'free' }); b.scope.setMinimised(true); b.scope.openIntro(); b.scope.closeIntro()
  assert.equal(b.scope.hud.minimised, true, 'Back to the road leaves a minimised HUD minimised')
})
test('teleporting from the start page closes it, and a bill, insurance or being stranded closes it too', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'resume', arrived: false, resume: {} })
  a.scope.teleportToResume()
  assert.equal(a.scope.intro.open, true, 'nothing happens while Lua does not allow it')
  a.state({ state: 'READY', mode: 'resume', arrived: false, resume: {}, teleportAllowed: true })
  a.scope.teleportToResume()
  assert.equal(a.commands.at(-1), fixed('teleportToResume()')); assert.equal(a.scope.intro.open, false, 'closed so the world can be seen loading')
  for (const extra of [{ partsChange: {} }, { carChange: {} }, { insurance: {} }, { stranded: {} }]) {
    a.state({ state: 'READY', mode: 'free', arrived: true }); a.scope.openIntro()
    a.state({ state: 'READY', mode: 'free', arrived: true, ...extra })
    assert.equal(a.scope.intro.open, false, Object.keys(extra)[0] + ' closes the page')
  }
  a.scope.openIntro(); a.state({ state: 'READY', mode: 'free', arrived: true, stranded: {} })
  assert.equal(a.scope.intro.open, true, 'opened again by the player, it stays open')
})
test('the Rust Bucket to Rig marker sits by the car value', () => {
  const a = app()
  assert.equal(a.scope.climbAt(0), '0%'); assert.equal(a.scope.climbAt(0.5), '50%'); assert.equal(a.scope.climbAt(3), '100%'); assert.equal(a.scope.climbAt('x'), '0%')
  assert.equal(a.scope.climbLabel(0), 'Still a rust bucket.'); assert.equal(a.scope.climbLabel(0.42), '42% of the way to a rig'); assert.equal(a.scope.climbLabel(1), 'You drive a rig.')
})

test('sightseeing: Go sightseeing sits under Street View, and sightseeing swaps the job card and tabs for Return to your job', () => {
  const street = html.indexOf('ng-click="openStreetView()"')
  const go = html.indexOf('ng-click="goSightseeing()"')
  assert.ok(street > 0 && go > street, 'Go sightseeing comes after the Street View button')
  const panel = html.slice(html.indexOf('<div ng-if="data.sightseeing.on && !data.admin.drive"'), html.indexOf('role="tablist"'))
  assert.ok(panel.includes('ng-click="returnToJob()"'), 'Return to your job in the sightseeing panel')
  assert.ok(html.includes('role="tablist" ng-if="!data.sightseeing.on"'), 'tabs hidden while sightseeing')
  assert.ok(html.includes('role="tabpanel" ng-if="!data.sightseeing.on"'), 'tab panels hidden while sightseeing')
  assert.ok(source.includes("core('goSightseeing()')") && source.includes("core('returnToJob()')"), 'both buttons call the game')
})

test('Street View: the address sits in a box with a Copy button, which only copies the local address', () => {
  assert.ok(html.includes('ng-click="copyStreetView()"'), 'Copy button for the address')
  const a = app()
  const before = a.commands.length
  a.scope.copyStreetView(); assert.equal(a.commands.length, before, 'nothing to copy before a state arrives')
  a.state({ state: 'READY', streetView: { on: true, url: 'http://evil.example/");os.exit()--' } }); a.scope.copyStreetView()
  assert.equal(a.commands.length, before, 'only a local address is ever copied')
  a.state({ state: 'READY', streetView: { on: true, url: 'http://127.0.0.1:47170/' } }); a.scope.copyStreetView()
  assert.equal(a.commands.at(-1), 'setClipboard("http://127.0.0.1:47170/")')
})

test('real businesses: the HUD picks one that suits the load, moves it to the road and tells the game', async () => {
  const asked = []
  const shops = [
    { type: 'node', id: 5, lat: -33.80, lon: 150.80, tags: { name: 'Corner Cafe', amenity: 'cafe' } },
    { type: 'node', id: 9, lat: -33.80, lon: 150.80, tags: { name: "O'Brien \"Tools\"", shop: 'hardware' } },
    { type: 'way', id: 3, center: { lat: -33.801, lon: 150.801 }, tags: { name: 'Brick & Co', shop: 'trade' } }
  ]
  const road = [{ geometry: [{ lat: -33.8003, lon: 150.800 }, { lat: -33.8003, lon: 150.802 }] }]
  const fetch = (url, opts) => {
    asked.push(decodeURIComponent(opts.body.slice(5)))
    const roads = asked.at(-1).includes('highway')
    return Promise.resolve({ ok: true, json: () => Promise.resolve({ elements: roads ? road : shops }) })
  }
  const a = app(null, null, { fetch, Promise })
  const lookup = { key: 'gn42:bricks', town: 'St Clair', latitude: -33.8, longitude: 150.8, good: 'bricks', metres: 1500, widerMetres: 3000 }
  // Bricks go to a builders' merchant before a hardware store; a cafe never.
  const list = a.scope.businessCandidates(shops, lookup.key, 'bricks')
  assert.deepEqual([...list.map(b => b.kind)], ['builders', 'hardware'])
  assert.equal(a.scope.businessCandidates(shops, 'gn42:fuel', 'fuel').length, 0, 'nothing for fuel here')
  a.state({ state: 'READY', load: { to: 'St Clair', lookup } })
  a.state({ state: 'READY', load: { to: 'St Clair', lookup } })
  await new Promise(r => setImmediate(r)); await new Promise(r => setImmediate(r))
  await new Promise(r => setTimeout(r, 10))
  assert.equal(asked.length, 2, 'one search and one road lookup, asked once even with two updates')
  assert.ok(asked[0].includes('around:1500,-33.800000,150.800000'), 'around the town')
  const sent = a.commands.at(-1)
  assert.match(sent, /^if earthFreight_core then earthFreight_core\.setBusiness\("gn42:bricks","Brick%20%26%20Co","builders",-33\.8003\d*,150\.801\d*\) end$/)
  // A name with quotes cannot break out of the command.
  const b = app(null, null, { fetch: (u, o) => Promise.resolve({ ok: true, json: () => Promise.resolve({ elements: o.body.includes('highway') ? road : [shops[1]] }) }), Promise })
  b.scope.lookUpBusiness({ ...lookup, key: 'gn43:bricks' })
  await new Promise(r => setTimeout(r, 10))
  assert.ok(b.commands.at(-1).includes('"O\'Brien%20%22Tools%22"'), 'quotes encoded')
  // Nothing anywhere: the game is told, after one wider search.
  const none = []
  const c = app(null, null, { fetch: (u, o) => { none.push(o.body); return Promise.resolve({ ok: true, json: () => Promise.resolve({ elements: [] }) }) }, Promise })
  c.scope.lookUpBusiness({ ...lookup, key: 'gn44:water' })
  await new Promise(r => setTimeout(r, 10))
  assert.equal(none.length, 2, 'searched wider once'); assert.ok(decodeURIComponent(none[1]).includes('around:3000'))
  assert.equal(c.commands.at(-1), fixed('noBusiness("gn44:water")'))
  // No web: nothing is sent, and the usual drop-off stays.
  const d = app(null, null, { fetch: () => Promise.reject(new Error('offline')), Promise })
  const before = d.commands.length
  d.scope.lookUpBusiness({ ...lookup, key: 'gn45:parts' })
  await new Promise(r => setTimeout(r, 10))
  assert.equal(d.commands.length, before, 'nothing sent when offline')
  assert.equal(d.scope.lookUpBusiness({ ...lookup, key: 'bad key"' }), null, 'odd keys ignored')
})

test('real businesses: the job card names the business, counts down the last metres and delivers there', () => {
  assert.ok(html.includes('{{data.load.business.distanceMetres | number:0}} m to {{data.load.business.name}}'), 'countdown')
  const a = app()
  a.state({ state: 'READY', load: { to: 'St Clair', pay: 900, distanceMetres: 5000, business: { name: 'Bunnings', near: true, distanceMetres: 120, inZone: false, delivery: { allowed: false } } } })
  assert.equal(a.scope.trip(a.scope.data).to, 'Bunnings, St Clair')
  assert.equal(a.scope.trip(a.scope.data).metres, 120, 'exact metres when close'); assert.equal(a.scope.atShop(a.scope.data), true)
  const before = a.commands.length
  a.scope.deliverJob(); assert.equal(a.commands.length, before, 'not delivered outside the circle')
  a.state({ state: 'READY', load: { to: 'St Clair', pay: 900, business: { name: 'Bunnings', near: true, distanceMetres: 12, inZone: true, delivery: { allowed: true } } } })
  a.scope.deliverJob(); assert.equal(a.commands.at(-1), fixed('deliverJob()'))
})

test('Street View has its own tab with sightseeing, and the header only shows a marker while it is on', () => {
  const a = app()
  assert.equal(a.scope.tabs.at(-4).label, 'Street View')
  const panel = html.slice(html.indexOf(`ng-if="tab === 'streetview'"`), html.indexOf(`ng-if="tab === 'radio'"`))
  for (const part of ['openStreetView()', 'stopStreetView()', 'copyStreetView()', 'goSightseeing()', 'Turn on', 'Turn off', 'Open again'])
    assert.ok(panel.includes(part), part + ' on the Street View tab')
  const header = html.slice(0, html.indexOf('<div ng-if="data.sightseeing.on && !data.admin.drive"'))
  for (const part of ['openStreetView()', 'copyStreetView()', 'goSightseeing()']) assert.ok(!header.includes(part), part + ' not in the header')
  assert.ok(header.includes(`ng-if="data.streetView.on && !data.sightseeing.on"`) && header.includes(`setTab('streetview')`), 'marker opens the tab')
  // The tabs are hidden while sightseeing, so its panel keeps Street View to hand.
  const seeing = html.slice(html.indexOf('<div ng-if="data.sightseeing.on && !data.admin.drive"'), html.indexOf('role="tablist"'))
  assert.ok(seeing.includes('openStreetView()') && seeing.includes('copyStreetView()'), 'Street View while sightseeing')
  a.scope.setTab('streetview'); assert.equal(a.scope.tab, 'streetview')
})

test('tabs sit in three rows: the job on top, the extras below, and the server events last', () => {
  const a = app()
  assert.deepEqual(JSON.parse(JSON.stringify(a.scope.tabRows.map(r => r.map(t => t.id)))), [['route', 'town', 'garage', 'relocate'], ['heli', 'home', 'streetview', 'radio'], ['mayday', 'race']])
  assert.equal(a.scope.tabs.at(-1).label, 'Land Race and Leaderboard')
  assert.ok(html.includes('ng-repeat="row in tabRows"') && html.includes('ng-repeat="t in row"'))
})
test('Mayday Rescue: its tab shows only while a call is out, and the edge buttons send fixed commands', () => {
  const a = app()
  assert.ok(html.includes('ng-if="tabShown(t.id)"'), 'tabs can hide')
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.tabShown('mayday'), false, 'no call: no tab')
  assert.equal(a.scope.tabShown('route'), true, 'the others always show')
  const edges = [{ id: 'n', name: 'North', allowed: true }, { id: 'e', name: 'East', allowed: false },
    { id: 'x"); evil("', name: 'Bad', allowed: true }]
  const call = { round: 4, open: true, name: 'Gobi Desert', reward: 80000, edges, secondsLeft: 3600 }
  a.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(a.scope.tabShown('mayday'), true, 'a call: the tab shows')
  assert.equal(a.scope.tabAlert('mayday'), true, 'and is marked until the player looks')
  a.scope.setTab('mayday')
  assert.equal(a.scope.tabAlert('mayday'), false, 'looked at')
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 5 } })
  assert.equal(a.scope.tabAlert('mayday'), false, 'a new call while on the tab is seen')
  a.scope.setTab('route')
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 6 } })
  assert.equal(a.scope.tabAlert('mayday'), true, 'a new call elsewhere is marked')
  a.commands.length = 0
  for (const e of edges) a.scope.maydayEdge(e)
  a.scope.maydayEdge(null)
  assert.deepEqual(a.commands, [fixed('maydayEdge("n")')], 'only an allowed edge, by its letter')
  const panel = html.slice(html.indexOf(`ng-if="tab === 'mayday' && data.mayday"`), html.indexOf(`ng-if="tab === 'race'"`))
  for (const part of ['MAYDAY RESCUE', 'maydayEdge(e)', 'data.mayday.running', 'data.mayday.winner', 'copyCoordinates(data.mayday.scene)',
    'nobody can relocate inside the circle'])
    assert.ok(panel.includes(part), part)
  // Landing on an edge opens the tab, and the tab goes when the call does.
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 6, running: { edge: 'North', seconds: 5 } } })
  assert.equal(a.scope.tab, 'mayday', 'a run opens the tab')
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.tab, 'route', 'no call: back to Route')
  for (const gone of ['shipDay', 'goToPort', 'takeContainer']) assert.ok(!html.includes(gone) && !source.includes(gone), gone + ' is gone')
  // The off-road drop's arrow points to the scene, on this tab and on the Route tab while on a run.
  assert.ok(panel.includes('arrowStyle(data.mayday)'), 'an arrow on the tab')
  const route = html.slice(html.indexOf(`ng-if="tab === 'route'"`), html.indexOf(`ng-if="tab === 'town'"`))
  assert.ok(route.includes('ng-if="data.mayday.running"') && route.includes('arrowStyle(data.mayday)'), 'and on the Route tab')
  assert.equal(a.scope.arrowStyle({ arrow: 90 }).transform, 'rotate(90deg)')
})
test('Mayday Rescue card: shows for a new call even when minimised, plays the alert once, and stays closed after a restart', () => {
  const saved = { 'earthFreight.hudMinimised': '1' }
  const storage = { getItem: k => saved[k] ?? null, setItem: (k, v) => { saved[k] = String(v) } }
  const played = []
  class Audio { constructor(src) { this.src = src } play() { played.push(this); return { catch() {} } } }
  let a = app(storage, undefined, { Audio })
  const call = { round: 7, open: true, name: 'Coober Pedy', region: 'South Australia', story: 'A road train lost a wheel.',
    reward: 80000, edges: [], secondsLeft: 7000, distanceMetres: 1284000, racers: 2 }
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.maydayCard(), false, 'no call: no card')
  a.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(a.scope.hud.minimised, true, 'the HUD stays minimised')
  assert.equal(a.scope.maydayCard(), true, 'a new call: the card shows')
  assert.equal(a.scope.hudAlert(), 'mayday', 'and the strip gets a red dot')
  assert.equal(played.length, 1, 'the alert plays')
  assert.equal(played[0].src, '/ui/modules/apps/TruckingCareerDC/mayday_alert.wav')
  a.state({ state: 'READY', arrived: true, mayday: { ...call, secondsLeft: 6990 } })
  assert.equal(played.length, 1, 'only once for a call')
  // Closed with Not now: gone, with its dot, and not back after the game restarts.
  a.scope.closeMaydayCard()
  assert.equal(a.scope.maydayCard(), false, 'closed')
  assert.equal(a.scope.tabAlert('mayday'), false, 'counts as seen')
  assert.equal(saved['earthFreight.maydaySeen'], '7')
  a = app(storage, undefined, { Audio })
  a.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(a.scope.maydayCard(), false, 'not back after a restart')
  assert.equal(played.length, 1, 'and no sound')
  // The next call gets a new card. Open Mayday Rescue opens the HUD on the tab.
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 8 } })
  assert.equal(a.scope.maydayCard(), true, 'the next call: a new card')
  assert.equal(played.length, 2)
  a.scope.openMaydayCard()
  assert.equal(a.scope.hud.minimised, false, 'Open Mayday Rescue opens the HUD')
  assert.equal(a.scope.tab, 'mayday', 'on the Mayday Rescue tab')
  assert.equal(a.scope.maydayCard(), false, 'and the card goes')
})
test('EMP sound: plays once for each EMP the game counts, never for the count a fresh HUD first sees', () => {
  const played = [], made = []
  class Audio { constructor(src) { this.src = src; this.loaded = 0; made.push(this) } load() { this.loaded++ } play() { played.push(this); return { catch() {} } } }
  const a = app(undefined, undefined, { Audio })
  assert.equal(made.filter(x => x.src.endsWith('/emp.wav')).length, 1, 'the EMP sound is loaded as the HUD starts')
  a.state({ state: 'READY', arrived: true, empSound: 3 })
  assert.equal(played.length, 0, 'the first count is old news')
  a.state({ state: 'READY', arrived: true, empSound: 3 })
  assert.equal(played.length, 0, 'no change: no sound')
  a.state({ state: 'READY', arrived: true, empSound: 4 })
  assert.equal(played.length, 1, 'one more EMP: the sound plays')
  assert.equal(played[0].src, '/ui/modules/apps/TruckingCareerDC/emp.wav')
  assert.equal(made.filter(x => x.src.endsWith('emp.wav')).length, 1, 'loaded once, as the HUD starts')
  assert.ok(made.every(x => x.loaded === 1), 'every sound fetched ahead, so the first one plays')
  a.state({ state: 'DRIVING', arrived: false, empSound: 5 })
  assert.equal(played.length, 2, 'and again while driving')
  assert.equal(a.scope.empBangs(), 2)
  const quiet = app()
  quiet.state({ state: 'READY', arrived: true, empSound: 0 })
  quiet.state({ state: 'READY', arrived: true, empSound: 1 })
  assert.equal(quiet.scope.empBangs(), 1, 'without Audio it still counts, silently')
})
test('Cha-ching: plays once for each time the game counts money in, never for the count a fresh HUD first sees', () => {
  const played = [], made = []
  class Audio { constructor(src) { this.src = src; this.loaded = 0; made.push(this) } load() { this.loaded++ } play() { played.push(this); return { catch() {} } } }
  const a = app(undefined, undefined, { Audio })
  assert.equal(made.filter(x => x.src.endsWith('/cha_ching.wav')).length, 1, 'loaded as the HUD starts')
  a.state({ state: 'READY', arrived: true, cashSound: 2 })
  assert.equal(played.length, 0, 'the first count is old news')
  a.state({ state: 'READY', arrived: true, cashSound: 2 })
  assert.equal(played.length, 0, 'no change: no sound')
  a.state({ state: 'READY', arrived: true, cashSound: 3 })
  assert.equal(played.length, 1, 'money in: cha-ching')
  assert.equal(played[0].src, '/ui/modules/apps/TruckingCareerDC/cha_ching.wav')
  assert.equal(a.scope.cashIns(), 1)
  assert.equal(made.filter(x => x.src.endsWith('/cha_ching.wav')).length, 1, 'the same sound reused')
})
test('EMP charged: plays when the EMP button goes from charging to ready, for the player and the admin robber', () => {
  const played = []
  class Audio { constructor(src) { this.src = src } load() {} play() { played.push(this.src); return { catch() {} } } }
  const a = app(undefined, undefined, { Audio })
  const chase = emp => ({ state: 'DRIVING', arrived: false, thief: { phase: 'chasing', emp } })
  a.state(chase({ ready: true }))
  assert.equal(played.length, 0, 'a chase that starts ready: nothing to announce')
  a.state(chase({ ready: false, chargeLeft: 20 }))
  a.state(chase({ ready: false, chargeLeft: 1 }))
  assert.equal(played.length, 0, 'still charging: quiet')
  a.state(chase({ ready: true }))
  assert.deepEqual(played, ['/ui/modules/apps/TruckingCareerDC/emp_charged.wav'], 'full charge: the sound plays once')
  a.state(chase({ ready: true }))
  assert.equal(played.length, 1, 'stays ready: no repeat')
  a.state({ state: 'DRIVING', arrived: false, admin: { drive: { emp: { ready: false, chargeLeft: 3 } } } })
  a.state({ state: 'DRIVING', arrived: false, admin: { drive: { emp: { ready: true } } } })
  assert.equal(played.length, 2, 'the admin robber hears it too')
  assert.equal(a.scope.empCharges(), 2)
  const fresh = app(undefined, undefined, { Audio })
  fresh.state(chase({ ready: true }))
  assert.equal(played.length, 2, 'a rebuilt HUD that first sees a ready EMP stays quiet')
})
test('A new Mayday call, base theft or robber hit scrolls the HUD to the top once, then leaves the player to scroll', () => {
  const page = { scrollTop: 400, scrolls: [], scrollTo(o) { this.scrolls.push(o); this.scrollTop = o.top }, parentElement: null }
  const a = app(undefined, [page])
  const call = { round: 3, open: true, name: 'Gobi Desert', reward: 80000, edges: [], secondsLeft: 3600 }
  a.state({ state: 'READY', arrived: true })
  a.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(page.scrollTop, 0, 'a new Mayday call: back to the top')
  assert.equal(page.scrolls[0].behavior, 'smooth', 'smoothly')
  page.scrollTop = 400
  a.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(page.scrollTop, 400, 'the same call: the player can scroll down again')
  a.state({ state: 'READY', arrived: true, mayday: call, thief: { phase: 'stolen', amount: 1000 } })
  assert.equal(page.scrollTop, 0, 'a thief at the base: to the top')
  page.scrollTop = 300
  a.state({ state: 'READY', arrived: true, mayday: call, thief: { phase: 'stolen', amount: 1000 } })
  assert.equal(page.scrollTop, 300, 'and only once')
  a.state({ state: 'DRIVING', arrived: false, mayday: call })
  a.state({ state: 'DRIVING', arrived: false, mayday: call, thief: { road: true, phase: 'chasing', amount: 1000 } })
  assert.equal(page.scrollTop, 0, 'a road robber\'s hit: to the top')
  assert.equal(a.scope.toTops(), 3)
  const old = { scrollTop: 250 }
  const b = app(undefined, [old])
  b.state({ state: 'READY', arrived: true, mayday: call })
  assert.equal(old.scrollTop, 0, 'without smooth scrolling it still jumps')
  b.scope.setMinimised(true)
  old.scrollTop = 250
  b.state({ state: 'READY', arrived: true, mayday: { ...call, round: 4 } })
  assert.equal(old.scrollTop, 250, 'minimised: the card shows by itself, nothing scrolls')
})
test('Mayday Rescue card: not for a won call, a run, or over the start page, and a minimised Mayday tab does not hide it', () => {
  const a = app()
  const call = { round: 3, open: true, name: 'Gobi Desert', reward: 80000, edges: [], secondsLeft: 3600 }
  a.state({ state: 'READY', arrived: true, mayday: { ...call, open: false, winner: 'Sam' } })
  assert.equal(a.scope.maydayCard(), false, 'a won call: no card')
  a.state({ state: 'READY', arrived: true, mayday: { ...call, running: { edge: 'North', seconds: 4 } } })
  assert.equal(a.scope.maydayCard(), false, 'on a run: no card')
  assert.equal(a.scope.tab, 'mayday', 'the run opened the tab')
  a.scope.setTab('route')
  a.scope.intro.open = true
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 4 } })
  assert.equal(a.scope.maydayCard(), false, 'waits for the start page')
  assert.equal(a.scope.maydayAlerts(), 0, 'and so does the sound')
  a.scope.intro.open = false
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 4 } })
  assert.equal(a.scope.maydayCard(), true, 'then shows')
  assert.equal(a.scope.maydayAlerts(), 1, 'without Audio the chime stands in')
  assert.equal(a.scope.chimes(), 1)
  // Left on the Mayday tab and minimised, a new call still gets its card.
  a.scope.setTab('mayday'); a.scope.setMinimised(true)
  a.state({ state: 'READY', arrived: true, mayday: { ...call, round: 5 } })
  assert.equal(a.scope.maydayCard(), true, 'minimised on the Mayday tab: still a card')
  // Both places show it, and the away card's Mayday line makes way for it.
  const strip = html.slice(html.indexOf('class="ef-strip"'), html.indexOf('class="ef-start"'))
  assert.ok(strip.includes('ng-if="hud.minimised && !intro.open && maydayCard(data)"'), 'under the strip')
  assert.ok(html.includes('ng-if="maydayCard(data)"'), 'in the open HUD')
  for (const part of ['Open Mayday Rescue', 'Not now', 'closeMaydayCard()', 'openMaydayCard()', 'data.mayday.problem', 'until(data.mayday.secondsLeft)'])
    assert.ok(strip.includes(part), part)
  assert.ok(html.includes('data.mayday.open && !maydayCard(data)'), 'no double mention on the away card')
})
test('Relocate to a player: a Join button for each player, sent by number only, and the opt-out', () => {
  const a = app()
  const relocate = html.slice(html.indexOf(`ng-if="tab === 'relocate'"`), html.indexOf(`ng-if="tab === 'home'"`))
  for (const part of ['Relocate to a player', 'findPlayer(p)', 'Let other players relocate to me']) assert.ok(relocate.includes(part), part)
  const sam = { id: 0, name: 'Sam', allowed: true }
  a.state({ state: 'READY', arrived: true, shipping: { players: { list: [sam], findable: true } } })
  a.commands.length = 0
  a.scope.findPlayer(sam)
  a.scope.findPlayer({ id: 2, allowed: false })
  a.scope.findPlayer({ id: '1); evil(', allowed: true })
  a.scope.setFindable(false)
  assert.deepEqual(a.commands.map(c => c.replace(/^if earthFreight_core then earthFreight_core\.| end$/g, '')),
    ['findPlayer(0)', 'setFindable(false)'])
})
test('Admin robber: the Route tab list sends Rob by number only, and his EMP and Stop only while they are allowed', () => {
  const a = app()
  const route = html.slice(html.indexOf('Road robbers'), html.indexOf(`ng-if="tab === 'town'"`))
  for (const part of ['Admin robber', 'adminRob(p)', 'ng-if="data.admin && !data.admin.drive"']) assert.ok(route.includes(part), part)
  assert.ok(html.includes('<div ng-if="data.admin.drive"') && html.includes('YOU ARE THE ROBBER'), 'his own panel while robbing')
  const sam = { id: 3, name: 'Sam', allowed: true }
  a.state({ state: 'READY', arrived: true, admin: { targets: [sam] } })
  a.commands.length = 0
  a.scope.adminRob(sam)
  a.scope.adminRob({ id: 4, allowed: false })
  a.scope.adminRob({ id: '1); evil(', allowed: true })
  a.scope.adminStop()
  a.scope.adminEmp()
  a.state({ state: 'READY', arrived: true, admin: { targets: [], drive: { stage: 'ready', name: 'Sam', stopAllowed: true, emp: { ready: false, chargeLeft: 12, charged: 40 } } } })
  a.scope.adminEmp()
  a.scope.adminStop()
  a.state({ state: 'READY', arrived: true, admin: { targets: [], drive: { stage: 'ready', name: 'Sam', stopAllowed: true, emp: { ready: true, charged: 100 } } } })
  a.scope.adminEmp()
  assert.ok(html.includes('ng-click="adminEmp()"'), 'his own EMP button while robbing')
  assert.deepEqual(a.commands.map(c => c.replace(/^if earthFreight_core then earthFreight_core\.| end$/g, '')),
    ['adminRob(3)', 'adminStop()', 'adminEmp()'])
})
test('Play online shows whether the server is up and how many are on it, from its stats', async () => {
  const asked = []
  let answer = { ok: true, json: async () => ({ updated: '2026-11-10T18:44:23Z', server: { name: 'WW Trucking Career | MadMerick', online: true, maxPlayers: 20 },
    players: [{ name: 'A' }, { name: 'B' }], season: { number: 1, day: 2, truckers: 10 } }) }
  const now = Date.parse('2026-11-10T18:50:00Z')
  const a = app(null, null, { fetch: url => { asked.push(url); return Promise.resolve(answer) }, Date: { now: () => now, parse: Date.parse } })
  assert.equal(a.scope.server.status, 'checking')
  a.scope.openIntro()
  await new Promise(r => setImmediate(r))
  assert.deepEqual(asked.filter(u => !u.endsWith('/help.txt')), ['https://raw.githubusercontent.com/MadMerick01/trucking-server-stats/main/status.json'])
  assert.equal(a.scope.server.status, 'online')
  assert.equal(a.scope.server.players, 2); assert.equal(a.scope.server.max, 20); assert.equal(a.scope.server.season, 1)
  assert.equal(a.scope.server.name, 'WW Trucking Career | MadMerick')
  a.scope.toggleOnline()
  assert.equal(asked.filter(u => !u.endsWith('/help.txt')).length, 1, 'asked at most once a minute')
  const read = a.scope.readServer
  assert.equal(read({ updated: '2026-11-10T18:20:00Z', server: { online: true } }, now).status, 'offline', 'stats older than 15 minutes')
  assert.equal(read({ updated: '2026-11-10T18:49:00Z', server: { online: true }, sample: true }, now).status, 'offline', 'the sample is not the server')
  assert.equal(read(null, now).status, 'offline')
  assert.equal(read({ server: { name: 'x'.repeat(200), maxPlayers: -3 } }, now).name.length, 60)
  assert.equal(read({ server: { name: '^l^fA WW Trucking Career | MadMerick' } }, now).name, 'A WW Trucking Career | MadMerick', 'no BeamMP colour codes')
})
test('Play online says when the status cannot be reached, and opens its two links', async () => {
  const a = app(null, null, { fetch: () => Promise.reject(new Error('offline')) })
  a.scope.openIntro()
  await new Promise(r => setImmediate(r))
  assert.equal(a.scope.server.status, 'unknown')
  a.scope.openLink('server')
  assert.equal(a.commands.at(-1), 'if openWebBrowser then openWebBrowser("https://madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts/") end setClipboard("https://madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts/")')
  a.scope.openLink('discord')
  assert.match(a.commands.at(-1), /openWebBrowser\("https:\/\/discord\.gg\/eYJCfXNGbP"\)/)
  const count = a.commands.length
  a.scope.openLink('");x("')
  assert.equal(a.commands.length, count, 'only the two fixed links')
  const page = html.slice(html.indexOf('class="ef-start"'), html.indexOf('<div ng-if="!hud.minimised && !intro.open">'))
  for (const part of ['PLAY ONLINE', 'OFFLINE CAREER', 'ng-click="toggleOnline()"', "openLink('server')", "openLink('discord')", 'ng-if="!data.online"']) assert.ok(page.includes(part), part)
})
test('the While you were away card: places read as 1st, 2nd, 3rd, and Got it closes it in the game', () => {
  const a = app()
  assert.deepEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 112].map(a.scope.ordinal),
    ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '101st', '112th'])
  assert.equal(a.scope.ordinal(0), '')
  a.scope.dismissAway()
  assert.equal(a.commands.at(-1), fixed('dismissAway()'))
  assert.ok(html.includes('WHILE YOU WERE AWAY') && html.includes('ng-click="dismissAway()"'), 'the card and its button')
})
test('the coffee line sits under the title and its Buy MadMerick a coffee button copies the Ko-fi link without opening anything', () => {
  const a = app()
  const count = a.commands.length
  a.scope.copySupport()
  assert.equal(a.commands.length, count + 1, 'one command')
  assert.equal(a.commands.at(-1), 'setClipboard("https://ko-fi.com/madmerick")')
  assert.equal(a.scope.hud.supportCopied, true)
  const main = html.indexOf('<div ng-if="!hud.minimised && !intro.open">'), title = html.indexOf('WORLDWIDE TRUCKING', main)
  const at = html.indexOf('ng-click="copySupport()"'), where = html.indexOf('data.where.title', main)
  assert.ok(title < at && at < where, 'under the title, above where you are')
  assert.equal(html.split('copySupport()').length, 2, 'once')
  for (const part of ['This mod will always be free to play', 'Buy MadMerick a coffee', 'Ko-fi link copied', 'Paste it into your web browser. Thank you!']) assert.ok(html.includes(part), part)
})
test('Radio tab: opens the radio page in the browser, shows what it plays, and copies only its address', () => {
  const a = app()
  a.scope.data = { state: 'TRUCK_IDLE' }
  a.scope.openRadio()
  assert.ok(!a.commands.includes(fixed('openRadio()')), 'nothing without the radio')
  a.scope.data = { state: 'TRUCK_IDLE', radio: { on: true, url: 'http://127.0.0.1:47170/radio', playing: 'Lithgow FM', open: true } }
  a.scope.openRadio()
  assert.equal(a.commands.at(-1), fixed('openRadio()'))
  a.scope.copyRadio()
  assert.equal(a.commands.at(-1), 'setClipboard("http://127.0.0.1:47170/radio")')
  const count = a.commands.length
  a.scope.data.radio.url = 'http://evil.example/radio")x("'
  a.scope.copyRadio()
  assert.equal(a.commands.length, count, 'only the radio address')
  const panel = html.slice(html.indexOf(`ng-if="tab === 'radio'"`), html.indexOf(`ng-if="tab === 'heli'"`))
  for (const part of ['openRadio()', 'copyRadio()', 'data.radio.playing', 'Open radio', "help('extras')"]) assert.ok(panel.includes(part), part)
  assert.ok(help.includes('Radio Browser'), 'the help page says where the stations come from')
})

// The HUD gets a fresh copy of the state up to four times a second. A list of rows without track by
// throws its rows away and draws new ones each time, so a click that straddles an update lands on
// a row that is gone and does nothing (the Book buttons on the Relocate tab missed about half the time).
test('every list of rows with a button keeps its rows between updates', () => {
  const open = /<(\w+)\b[^>]*\sng-repeat="([^"]+)"[^>]*>/g
  const missing = []
  let m
  while ((m = open.exec(html))) {
    if (!/\bin data\./.test(m[2])) continue
    // The row's own markup: up to the tag that closes it.
    let depth = 0, end = html.length
    const tags = new RegExp('<(/?)' + m[1] + '\\b[^>]*?(/?)>', 'g')
    tags.lastIndex = m.index
    for (let t; (t = tags.exec(html));) {
      if (t[1]) depth--
      else if (!t[2]) depth++
      if (depth === 0) { end = tags.lastIndex; break }
    }
    const row = html.slice(m.index, end)
    if (/ng-click|ng-model/.test(row) && !/\btrack by\b/.test(m[2])) missing.push(m[2])
  }
  assert.deepEqual(missing, [])
})

test('Land Race and Leaderboard tab: copies the live page address, shows the race online, and only join steps in single player', () => {
  const a = app()
  const count = a.commands.length
  a.scope.copyLiveAddress()
  assert.equal(a.commands.length, count + 1, 'one command')
  assert.equal(a.commands.at(-1), 'setClipboard("https://madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts/")', 'copies only, opens nothing')
  assert.equal(a.scope.intro.liveCopied, true)
  const panel = html.slice(html.indexOf(`ng-if="tab === 'race'"`), html.indexOf(`ng-if="tab === 'heli'"`))
  const address = panel.indexOf('copyLiveAddress()'), online = panel.indexOf('ng-if="data.standings"'), single = panel.indexOf('ng-if="!data.online"')
  assert.ok(address >= 0 && address < online && online < single, 'the address on top, then the race, then single player')
  for (const part of ['Copy address', 'Land race', 'Season leaderboard', 'How to play online', 'The land race is online only'])
    assert.ok(panel.includes(part), part)
  for (const gone of ['Ship Day', 'Driving now', 'Live feed']) assert.ok(!panel.includes(gone), gone + ' is not on this tab')
  assert.ok(!panel.includes('fetch') && !panel.includes('checkServer'), 'nothing is fetched from the web')
  const st = { race: { win: 50, leader: 'Sam', leaderLand: 1.6 }, board: [{ rank: 1, name: 'Sam', wealth: 550950 }, { rank: 2, name: 'Me', wealth: 530800, mine: true }] }
  assert.equal(a.scope.raceSummary(st), 'Sam leads with 1.6% of 50%')
  assert.equal(a.scope.boardSummary(st), "you're 2nd, $20,150 behind Sam")
  assert.equal(a.scope.boardSummary({ board: [{ rank: 1, name: 'Sam', wealth: 1000 }], me: { rank: 14, wealth: 400, mine: true } }), "you're 14th, $600 behind Sam")
  assert.equal(a.scope.boardSummary({ board: [{ rank: 1, name: 'Sam', wealth: 1000 }] }), 'Sam leads, $1,000')
  assert.equal(a.scope.boardSummary({ waiting: true }), 'waiting for the server')
  assert.equal(a.scope.raceSummary({ race: {} }), 'nobody holds land yet')
  assert.equal(a.scope.landWidth(25, 50), '50%'); assert.equal(a.scope.landWidth(0, 50), '1%')
})
test('Fuel runs: the Town tab card loads a run and sets the GPS to the depot only when Lua allows it', () => {
  assert.match(html, /ng-click="takeFuelRun\(r\)"/)
  assert.match(html, /ng-click="gpsToDepot\(\)"/)
  assert.match(html, /ng-repeat="r in data\.fuelRuns\.runs track by r\.id"/)
  const a = app()
  const run = { id: 'fuelrun_gn123', to: 'Oberon', pay: 260000, units: 1200, allowed: false }
  const fuelRuns = { hub: { id: 'gn9', name: 'Richmond' }, runs: [run] }
  a.state({ state: 'READY', fuelRuns })
  let count = a.commands.length
  a.scope.takeFuelRun(run); a.scope.gpsToDepot()
  assert.equal(a.commands.length, count, 'refused when not allowed')
  a.state({ state: 'READY', gpsAllowed: true, fuelRuns: { ...fuelRuns, runs: [{ ...run, allowed: true }] } })
  a.scope.takeFuelRun({ ...run, allowed: true })
  assert.equal(a.commands.at(-1), fixed("takeFuelRun('fuelrun_gn123', 100)"), 'a full load unless the slider moved')
  a.scope.shares[run.id] = '40'
  a.scope.takeFuelRun({ ...run, allowed: true })
  assert.equal(a.commands.at(-1), fixed("takeFuelRun('fuelrun_gn123', 40)"), 'the share on the Load slider')
  assert.match(html, /ng-model="shares\[r\.id\]"/)
  a.scope.gpsToDepot()
  assert.equal(a.commands.at(-1), fixed('gpsToDepot()'))
  a.scope.gpsToRun(run)
  assert.equal(a.commands.at(-1), fixed("gpsToRun('fuelrun_gn123')"))
  count = a.commands.length
  a.scope.teleportToDepot()
  assert.equal(a.commands.length, count, 'no teleport unless Lua allows it')
  a.state({ state: 'READY', gpsAllowed: true, fuelRuns: { ...fuelRuns, teleportAllowed: true } })
  a.scope.teleportToDepot()
  assert.equal(a.commands.at(-1), fixed('teleportToDepot()'))
  assert.match(html, /ng-click="teleportToDepot\(\)"/)
  assert.match(html, /ng-click="gpsToRun\(r\)"/)
  count = a.commands.length
  a.scope.takeFuelRun({ ...run, id: "x'); evil(", allowed: true })
  assert.equal(a.commands.length, count, 'only plain ids')
})
test('Fuel runs: the HUD looks for a depot that suits loading fuel', () => {
  const a = app()
  const elements = [
    { type: 'node', id: 1, lat: 1, lon: 1, tags: { amenity: 'fuel', name: 'Truck Stop' } },
    { type: 'way', id: 2, center: { lat: 1, lon: 1 }, tags: { industrial: 'fuel_depot', name: 'Ampol Terminal' } },
    { type: 'node', id: 3, lat: 1, lon: 1, tags: { shop: 'supermarket', name: 'Coles' } }
  ]
  const list = a.scope.businessCandidates(elements, 'gn9:fuelhub', 'fuelhub')
  assert.equal(list.map(b => b.name).join('|'), 'Ampol Terminal|Truck Stop', 'a fuel terminal first, then a truck stop, never a shop')
  assert.equal(list[0].kind, 'terminal')
})
test('Base thief and road robber: a theft or a hit rings the Mayday alert once, but not for one a rebuilt HUD first sees', () => {
  const played = []
  class Audio { constructor(src) { this.src = src } play() { played.push(this); return { catch() {} } } }
  const theft = { phase: 'stolen', amount: 1000, bounty: 5000, secondsLeft: 600, chaseAllowed: true }
  let a = app(undefined, undefined, { Audio })
  a.state({ state: 'READY', arrived: true })
  a.state({ state: 'READY', arrived: true, thief: theft })
  assert.equal(played.length, 1, 'the alert plays as the theft starts')
  assert.equal(played[0].src, '/ui/modules/apps/TruckingCareerDC/mayday_alert.wav')
  a.state({ state: 'READY', arrived: true, thief: { ...theft, secondsLeft: 590 } })
  a.state({ state: 'READY', arrived: true, thief: { ...theft, phase: 'travelling' } })
  assert.equal(played.length, 1, 'only once for a theft')
  a.state({ state: 'READY', arrived: true })
  a.state({ state: 'READY', arrived: true, thief: { phase: 'chasing', road: true, amount: 1000 } })
  assert.equal(played.length, 2, 'a road robber\'s hit rings it too')
  a.state({ state: 'READY', arrived: true, thief: { phase: 'chasing', road: true, amount: 1000, distanceMetres: 50 } })
  assert.equal(played.length, 2, 'once')
  a = app(undefined, undefined, { Audio })
  a.state({ state: 'READY', arrived: true, thief: theft })
  assert.equal(played.length, 2, 'a rebuilt HUD stays quiet')
  assert.equal(a.scope.thiefCard(), true, 'but shows the card')
})
test('Robbery cards: the money in big letters, how it ended, and the admin robber card when minimised', () => {
  const a = app()
  const big = () => { const m = a.scope.robberyMoney(a.scope.data.thief); return m && { good: m.good, text: m.text } }
  a.state({ state: 'READY', arrived: true, thief: { phase: 'stolen', amount: 1000, bounty: 5000 } })
  assert.deepEqual(big(), { good: false, text: '-$1,000 TAKEN' }, 'taken')
  assert.equal(a.scope.thiefTitle(a.scope.data.thief), 'THIEF AT YOUR BASE')
  a.state({ state: 'READY', arrived: true, thief: { road: true, phase: 'chasing', amount: 1000, bounty: 20000 } })
  assert.equal(a.scope.thiefTitle(a.scope.data.thief), 'CATCH THE ROBBER')
  a.state({ state: 'READY', arrived: true, thief: { road: true, phase: 'caught', amount: 1000, bounty: 20000, paid: 21000 } })
  assert.equal(a.scope.thiefCard(), true, 'the card stays up once caught')
  assert.deepEqual(big(), { good: true, text: '+$21,000 WON BACK' }, 'won back')
  assert.equal(a.scope.thiefTitle(a.scope.data.thief), 'ROBBER CAUGHT')
  assert.equal(a.scope.robberyGood(a.scope.data.thief), true, 'a green card'); assert.equal(a.scope.hudAlert(), '', 'and no red dot')
  a.state({ state: 'READY', arrived: true, thief: { road: true, phase: 'over', outcome: 'escaped', amount: 1000 } })
  assert.equal(a.scope.thiefTitle(a.scope.data.thief), 'THE ROBBER GOT AWAY')
  assert.deepEqual(big(), { good: false, text: '-$1,000 GONE' }, 'gone')
  a.state({ state: 'READY', arrived: true, thief: { phase: 'over', outcome: 'dropped', amount: 1000, paid: 1000 } })
  assert.equal(a.scope.thiefTitle(a.scope.data.thief), 'THE THIEF DROPPED IT'); assert.deepEqual(big(), { good: true, text: '+$1,000 BACK' })
  a.state({ state: 'READY', arrived: true, thief: { phase: 'return', outcome: 'caught', amount: 1000, paid: 6000, returnAllowed: true } })
  assert.deepEqual(big(), { good: true, text: '+$6,000 WON BACK' }, 'and on the way back')
  a.state({ state: 'READY', arrived: true, thief: { phase: 'return', returnAllowed: true } })
  assert.equal(big(), null, 'nothing to say: no line')
  for (const part of ['class="ef-money"', '&#9888; YOU ARE THE ROBBER', 'hud.minimised && !intro.open && data.admin.drive']) assert.ok(html.includes(part), part)
  a.state({ state: 'READY', arrived: true, admin: { drive: { stage: 'ready', name: 'Sam' } } })
  assert.equal(a.scope.hudAlert(), 'bad', 'the admin robber: a red dot on the strip')
})
test('Base thief: the card shows while a theft is on, and Chase and EMP send fixed commands', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.thiefCard(), false, 'no theft: no card')
  a.state({ state: 'READY', arrived: true, thief: { phase: 'stolen', amount: 1000, bounty: 5000, secondsLeft: 600, chaseAllowed: false } })
  assert.equal(a.scope.thiefCard(), true, 'a theft: the card')
  assert.equal(a.scope.hudAlert(), 'bad', 'and the minimised HUD is marked')
  a.commands.length = 0
  a.scope.thiefChase(); a.scope.empThief()
  assert.deepEqual(a.commands, [], 'nothing while Chase is not allowed and before the chase')
  a.scope.thiefLetGo()
  assert.deepEqual(a.commands, [fixed('thiefLetGo()')], 'Let them go, even when Chase is not allowed')
  a.commands.length = 0
  a.state({ state: 'READY', arrived: true, thief: { phase: 'stolen', amount: 1000, bounty: 5000, secondsLeft: 500, chaseAllowed: true } })
  a.scope.thiefChase()
  a.state({ state: 'READY', arrived: true, thief: { phase: 'chasing', amount: 1000, bounty: 5000, distanceMetres: 40, empMetres: 5, escapeMetres: 450 } })
  a.scope.empThief(); a.scope.thiefLetGo()
  assert.deepEqual(a.commands, [fixed('thiefChase()'), fixed('empThief()')], 'no Let them go once the chase is on')
  a.commands.length = 0
  // Chase in a parked car: by its slot, only when both Chase and that car are allowed.
  const cars = [{ index: 1, name: 'Pickup D15', allowed: true }, { index: 2, name: 'Moonhawk', allowed: false }]
  a.state({ state: 'READY', arrived: true, thief: { phase: 'stolen', amount: 1000, chaseAllowed: false, cars } })
  a.scope.thiefChaseIn(cars[0])
  a.state({ state: 'READY', arrived: true, thief: { phase: 'stolen', amount: 1000, chaseAllowed: true, cars } })
  a.scope.thiefChaseIn(cars[1]); a.scope.thiefChaseIn({ index: 1.5, allowed: true }); a.scope.thiefChaseIn(null)
  a.scope.thiefChaseIn(cars[0])
  assert.deepEqual(a.commands, [fixed('thiefChase(1)')], 'Chase in the allowed car only')
  assert.ok(html.includes('ng-click="thiefChaseIn(car)"'), 'a button for each parked car')
  a.commands.length = 0
  // No Get robbed or ROB ME button (MadMerick, 23 Nov): players farmed money with them.
  assert.equal(a.scope.getRobbed, undefined, 'no Get robbed command')
  assert.equal(a.scope.robMe, undefined, 'no ROB ME command')
  for (const part of ['getRobbed()', 'robMe()', '>Get robbed<', '>ROB ME<']) assert.ok(!html.includes(part), 'no ' + part)
  a.state({ state: 'READY', arrived: true, thief: { phase: 'return', job: true, returnAllowed: false, problem: 'Get back in your car first.' } })
  a.scope.thiefGoBack()
  a.state({ state: 'READY', arrived: true, thief: { phase: 'return', job: true, returnAllowed: true } })
  assert.equal(a.scope.thiefCard(), true, 'the way back shows on the card')
  a.scope.thiefGoBack()
  assert.deepEqual(a.commands, [fixed('thiefGoBack()')], 'Back to your job only when allowed')
  assert.ok(html.includes('ng-click="thiefGoBack()"'))
  for (const part of ['Base thief (trial)', 'Robbers and thieves (single player only)']) assert.ok(html.includes(part), part)
  for (const part of ['arrowStyle(data.thief)', 'thiefTitle(data.thief)', 'ng-click="thiefChase()"', 'ng-click="empThief()"', 'escape with the money'])
    assert.ok(html.includes(part), part)
})

// The help page: one big window with every part of the game, its text in help.txt.
const helpApp = (storage) => app(storage || null, null, { fetch: url => Promise.resolve({ ok: true, text: () => Promise.resolve(help) }), Promise })
const settle = async () => { for (let i = 0; i < 3; i++) await new Promise(r => setImmediate(r)) }
test('Help page: help.txt is read into sections, and every small ? opens a section that exists', async () => {
  const a = helpApp()
  const sections = a.scope.readHelp(help)
  const ids = sections.map(s => s.id)
  for (const id of ['start', 'jobs', 'fuel', 'robbers', 'mayday', 'base']) assert.ok(ids.includes(id), id + ' section')
  assert.equal(new Set(ids).size, ids.length, 'no two sections share an id')
  assert.ok(sections.every(s => s.title && s.lines.length), 'every section has a title and points')
  assert.ok(sections.every(s => s.lines.every(l => !l.startsWith('//'))), 'notes are not shown')
  assert.deepEqual([...sections.filter(s => s.online).map(s => s.id)], ['mayday', 'online'], 'online-only sections are marked')
  const used = [...html.matchAll(/help\('(\w+)'\)/g)].map(m => m[1])
  assert.ok(used.length >= 10, 'small ? buttons across the HUD')
  for (const id of used) assert.ok(ids.includes(id), "help('" + id + "') has a section")
  assert.deepEqual(JSON.parse(JSON.stringify(a.scope.readHelp('# a | A\none\n// note\n\n# bad\ntwo\n# b | B | online\nthree'))),
    [{ id: 'a', title: 'A', online: false, lines: ['one', 'two'] }, { id: 'b', title: 'B', online: true, lines: ['three'] }])
})
test('Help page: the start page steps are its Getting started points, with the built-in copy matching help.txt', async () => {
  const a = helpApp()
  const fallback = a.scope.introSteps.slice()
  a.scope.help('start')
  await settle()
  const start = a.scope.readHelp(help).find(s => s.id === 'start')
  assert.deepEqual([...a.scope.introSteps], [...start.lines], 'the start page reads help.txt')
  assert.deepEqual([...fallback], [...start.lines], 'the copy used when help.txt cannot be read is the same')
  assert.ok(html.includes(`ng-click="help('start')"`) && html.includes('Read the full guide'), 'the start page links to the full guide')
})
test('Help page: {names} are filled in with the game\'s own numbers', () => {
  const a = helpApp()
  a.state({ state: 'READY', rules: { robberTake: '$1,000', empRange: 15 } })
  assert.equal(a.scope.helpLine('Take {robberTake} within {empRange} m'), 'Take $1,000 within 15 m')
  assert.equal(a.scope.helpLine('Unknown {nope}'), 'Unknown ...')
  const names = new Set([...help.split('\n').filter(l => !l.startsWith('//')).join('\n').matchAll(/\{(\w+)\}/g)].map(m => m[1]))
  const core = readFileSync(new URL('../mod/earth_freight/lua/ge/extensions/earthFreight/core.lua', import.meta.url), 'utf8')
  const rules = core.slice(core.indexOf('function c:rulesView()'), core.indexOf('function c:serverSaveWarning()'))
  for (const name of names) assert.match(rules, new RegExp('\\b' + name + ' = '), name + ' is sent by the game')
})
test('Help page: opens from ?, its ? glows until the first time, and closes with X or a click outside, not Esc', async () => {
  const store = {}
  const storage = { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = String(v) } }
  const a = helpApp(storage)
  assert.equal(a.scope.helpState.seen, false, 'glows on a new game')
  assert.ok(html.includes(`ng-class="{'ef-help-new': !helpState.seen}"`), 'the glow is on the ? at the top of the HUD')
  a.scope.help()
  await settle()
  assert.equal(a.scope.helpOpen(), true)
  assert.equal(a.scope.helpState.at, 'start', 'the ? at the top opens Getting started')
  assert.equal(store['earthFreight.helpSeen'], '1', 'remembered')
  a.scope.help('robbers'); assert.equal(a.scope.helpState.at, 'robbers')
  a.scope.helpNext(); assert.equal(a.scope.helpState.at, 'mayday')
  a.scope.help('not-a-section'); assert.equal(a.scope.helpState.at, 'start', 'an unknown section opens the first one')
  const inside = {}, outside = {}
  a.scope.helpBackdrop({ target: inside, currentTarget: outside }); assert.equal(a.scope.helpOpen(), true, 'a click in the window keeps it')
  a.scope.helpBackdrop({ target: outside, currentTarget: outside }); assert.equal(a.scope.helpOpen(), false, 'a click outside closes it')
  a.scope.help('jobs'); a.scope.closeHelp(); assert.equal(a.scope.helpOpen(), false, 'X closes it')
  assert.ok(!/keydown|Escape|keyCode/.test(source), 'Esc is left to the game')
  const b = helpApp(storage)
  assert.equal(b.scope.helpState.seen, true, 'no glow after the first time, after a restart too')
})
test('Help page: the live page and the Discord are copied or opened, and only those two addresses', () => {
  const a = helpApp()
  a.scope.copyHelpLink('server')
  assert.equal(a.commands.at(-1), 'setClipboard("https://madmerick01.github.io/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts/")')
  assert.equal(a.scope.helpState.copied, 'server')
  a.scope.copyHelpLink('discord')
  assert.equal(a.commands.at(-1), 'setClipboard("https://discord.gg/eYJCfXNGbP")')
  a.scope.openHelpLink('discord')
  assert.match(a.commands.at(-1), /openWebBrowser\("https:\/\/discord\.gg\/eYJCfXNGbP"\)/)
  const count = a.commands.length
  a.scope.copyHelpLink('elsewhere'); assert.equal(a.commands.length, count, 'nothing else')
  const page = html.slice(html.indexOf('class="ef-help"'), html.indexOf('<div ng-if="!hud.minimised && !intro.open">'))
  for (const part of ["copyHelpLink('server')", "openHelpLink('server')", "copyHelpLink('discord')", "openHelpLink('discord')", 'closeHelp()', 'helpBackdrop($event)', 'Online only'])
    assert.ok(page.includes(part), part)
})
test('Help page: cannot be read, says so and tries again next time', async () => {
  let ok = false
  const a = app(null, null, { fetch: () => Promise.resolve(ok ? { ok: true, text: () => Promise.resolve(help) } : { ok: false }), Promise })
  a.scope.help('fuel'); await settle()
  assert.equal(a.scope.helpState.status, 'failed')
  assert.ok(a.scope.introSteps.length === 6, 'the start page keeps its steps')
  ok = true; a.scope.help('fuel'); await settle()
  assert.equal(a.scope.helpState.status, 'ready'); assert.equal(a.scope.helpState.at, 'fuel')
})
test('Fuel runs sit on the Town tab, not the Route tab', () => {
  const route = html.slice(html.indexOf("tab === 'route'"), html.indexOf("tab === 'town'"))
  const town = html.slice(html.indexOf("tab === 'town'"), html.indexOf("tab === 'garage'"))
  assert.ok(!route.includes('data.fuelRuns'), 'not on Route')
  for (const part of ['ng-click="teleportToDepot()"', 'ng-click="gpsToDepot()"', 'ng-click="takeFuelRun(r)"', 'ng-click="gpsToRun(r)"']) assert.ok(town.includes(part), part + ' on Town')
})

test('Pickup point: the Town tab points to it with a needle and a GPS button, and the minimised strip shows how far', () => {
  assert.match(html, /ng-style="arrowStyle\(data\.town\.pickup\)"/)
  assert.match(html, /ng-click="gpsToPickup\(\)"/)
  assert.match(html, /pickupStrip\(data\)/)
  assert.ok(!html.includes('useComputer'), 'no depot computer')
  const a = app()
  const pickup = { name: 'Penrith', distanceMetres: 180, direction: 'north-east', letters: 'NE', arrow: 45, radiusMetres: 50, gpsAllowed: false }
  a.state({ state: 'READY', town: { id: 'gn1', jobs: [], pickup } })
  assert.equal(a.scope.pickupStrip(a.scope.data).letters, 'NE', 'the strip shows the pickup point')
  assert.equal(a.scope.arrowStyle(pickup).transform, 'rotate(45deg)', 'the needle turns')
  let count = a.commands.length
  a.scope.gpsToPickup()
  assert.equal(a.commands.length, count, 'no GPS unless Lua allows it')
  a.state({ state: 'READY', town: { id: 'gn1', jobs: [], pickup: { ...pickup, gpsAllowed: true } } })
  a.scope.gpsToPickup()
  assert.equal(a.commands.at(-1), fixed('gpsToPickup()'))
  a.state({ state: 'READY', town: { id: 'gn1', jobs: [], pickup: { ...pickup, inZone: true } } })
  assert.equal(a.scope.pickupStrip(a.scope.data), null, 'not once you are there')
  a.state({ state: 'READY', town: { id: 'gn1', jobs: [], pickup }, load: { to: 'Blaxland' } })
  assert.equal(a.scope.pickupStrip(a.scope.data), null, 'not while on a job')
})

test('Drop-off point: close to it, the job card and the strip count the exact metres down, with a needle', () => {
  assert.match(html, /ng-style="arrowStyle\(data\.load\.point\)"/)
  const a = app()
  a.state({ state: 'READY', load: { to: 'St Clair', pay: 900, distanceMetres: 4000, direction: 'north', point: { near: false, distanceMetres: 3000 } } })
  assert.equal(a.scope.trip(a.scope.data).metres, 4000, 'far off: the road estimate')
  a.state({ state: 'READY', load: { to: 'St Clair', pay: 900, distanceMetres: 400, direction: 'north', point: { near: true, distanceMetres: 310, arrow: 10 } } })
  assert.equal(a.scope.trip(a.scope.data).metres, 310, 'close: straight to the point')
})

test('Relocate: the big map opens only when allowed, and the pop-up pays or goes back only when Lua allows it', () => {
  const a = app()
  let count = a.commands.length
  a.state({ state: 'READY', shipping: { mapAllowed: false } }); a.scope.openBigMap()
  assert.equal(a.commands.length, count, 'no map while relocating is barred')
  a.state({ state: 'READY', shipping: { mapAllowed: true } }); a.scope.openBigMap()
  assert.match(a.commands.at(-1), /freeroam_bigMapMode/, 'the big map opens')
  count = a.commands.length
  a.state({ state: 'READY', relocateHere: { payAllowed: false, backAllowed: false } }); a.scope.payRelocation(); a.scope.goBackUnpaid()
  assert.equal(a.commands.length, count, 'refused while landing or going back')
  a.state({ state: 'READY', relocateHere: { payAllowed: true, backAllowed: true } })
  a.scope.payRelocation(); assert.equal(a.commands.at(-1), fixed('payRelocation()'))
  a.scope.goBackUnpaid(); assert.equal(a.commands.at(-1), fixed('goBackUnpaid()'))
  const relocate = html.slice(html.indexOf(`ng-if="tab === 'relocate'"`), html.indexOf(`ng-if="tab === 'home'"`))
  assert.ok(!relocate.includes('data.shipping.destinations') && !relocate.includes('searchShipping'), 'no list of places, no search')
  assert.ok(html.includes('ng-if="data.relocateHere"') && html.includes('ng-click="payRelocation()"') && html.includes('ng-click="goBackUnpaid()"'), 'the pop-up')
})
test('Relocate backup: pasted coordinates teleport or copy, and the on-foot pop-up only calls Lua when allowed', () => {
  const a = app()
  a.state({ state: 'READY', shipping: { mapAllowed: true } })
  a.scope.ship.coords = 'nonsense'; let count = a.commands.length
  a.scope.relocateTo(); a.scope.copyPasted()
  assert.equal(a.commands.length, count, 'nothing sent for text that is not coordinates'); assert.ok(a.scope.ship.error)
  a.scope.ship.coords = '-16.19, -67.73'
  a.scope.relocateTo(); assert.equal(a.commands.at(-1), fixed('relocateTo(-16.19, -67.73)'))
  a.scope.copyPasted(); assert.match(a.commands.at(-1), /setClipboard\("-16\.19000000, -67\.73000000"\)/)
  a.state({ state: 'READY', shipping: { mapAllowed: false } }); count = a.commands.length
  a.scope.relocateTo(); assert.equal(a.commands.length, count, 'not while relocating is barred')
  a.state({ state: 'READY', footAway: { backAllowed: false } }); a.scope.goBackToCar()
  assert.equal(a.commands.length, count, 'not while already going back')
  a.state({ state: 'READY', footAway: { backAllowed: true } }); a.scope.goBackToCar()
  assert.equal(a.commands.at(-1), fixed('goBackToCar()'))
  assert.ok(html.includes('ng-if="data.footAway && !data.relocateHere"') && html.includes('copyCoordinates(data.footAway)'), 'the on-foot pop-up with Copy')
  assert.ok(html.includes('copyCoordinates(data.relocateHere)'), 'the pay pop-up shows where you left, with Copy')
})
