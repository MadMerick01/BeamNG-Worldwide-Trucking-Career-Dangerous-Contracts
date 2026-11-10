import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'

const APP = '../mod/earth_freight/ui/modules/apps/TruckingCareerDC/'
const source = readFileSync(new URL(APP + 'app.js', import.meta.url), 'utf8')
const html = readFileSync(new URL(APP + 'app.html', import.meta.url), 'utf8')
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
    storeTrailer: ['storeAllowed', 'storeTrailer()'], cancelStoreTrailer: ['storeArmed', 'cancelStoreTrailer()'],
    bringOutTrailer: ['bringOutAllowed', 'bringOutTrailer()'], sellTrailer: ['sellAllowed', 'sellTrailer()'],
    repairTrailer: ['repairAllowed', 'repairTrailer()'], buyTrailerParts: ['partsAllowed', 'buyTrailerParts()']
  }
  for (const [name, [flag, body]] of Object.entries(buttons)) {
    count = a.commands.length
    a.state({ state: 'READY', trailer: {} }); a.scope[name]()
    assert.equal(a.commands.length, count, name + ' refused when not allowed')
    a.state({ state: 'READY', trailer: { [flag]: true } }); a.scope[name]()
    assert.equal(a.commands.at(-1), fixed(body), name)
  }
})

test('trailer parts: Pay and Undo only while in the trailer, and Pay only when Lua allows it', () => {
  const a = app()
  let count = a.commands.length
  a.state({ state: 'READY', trailer: {} }); a.scope.payTrailerParts(); a.scope.undoTrailerParts()
  assert.equal(a.commands.length, count, 'nothing to pay or undo outside the trailer')
  a.state({ state: 'READY', trailer: { shop: { payAllowed: false } } }); a.scope.payTrailerParts()
  assert.equal(a.commands.length, count, 'Pay refused when short')
  a.scope.undoTrailerParts(); assert.equal(a.commands.at(-1), fixed('undoTrailerParts()'))
  a.state({ state: 'READY', trailer: { shop: { payAllowed: true } } }); a.scope.payTrailerParts()
  assert.equal(a.commands.at(-1), fixed('payTrailerParts()'))
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
test('Base: Buy this spot and Swap cars only call Lua when it allows them, and Base is a tab', () => {
  const a = app()
  assert.ok(a.scope.tabs.some(t => t.id === 'home' && t.label === 'Base'))
  let count = a.commands.length
  a.state({ state: 'READY' }); a.scope.claimHome(); a.scope.swapCars()
  a.state({ state: 'READY', home: { claimAllowed: false, swapAllowed: false } }); a.scope.claimHome(); a.scope.swapCars()
  assert.equal(a.commands.length, count, 'refused unless allowed')
  a.state({ state: 'READY', home: { claimAllowed: true } }); a.scope.claimHome()
  assert.equal(a.commands.at(-1), fixed('claimHome()'))
  a.state({ state: 'READY', home: { swapAllowed: true } }); a.scope.swapCars()
  assert.equal(a.commands.at(-1), fixed('swapCars()'))
  assert.ok(html.includes("ng-if=\"tab === 'home'\""), 'the Home tab has a panel')
  assert.ok(html.includes("bookShipping('home')"), 'Relocate lists home')
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
  a.state({ state: 'READY', town: { refuelAllowed: true, delivery: { allowed: true } } })
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
  assert.deepEqual([...a.scope.tabs.map(t => t.id)], ['route', 'town', 'garage', 'relocate', 'heli', 'home', 'streetview'])
  assert.ok(!html.includes(`tab === 'tips'`), 'no Tips tab')
  const garage = html.slice(html.indexOf(`ng-if="tab === 'garage'"`), html.indexOf(`ng-if="tab === 'relocate'"`))
  const shipping = html.slice(html.indexOf(`ng-if="tab === 'relocate'"`))
  for (const card of ['Relocation paid:', 'Book relocation', 'bookOffer()', 'bookShipping(d.id)', 'cancelShipping()']) {
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
  for (const box of ['intro.name', 'ship.query', 'ship.coords']) {
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
  const panel = html.slice(html.indexOf('<div ng-if="data.sightseeing.on"'), html.indexOf('role="tablist"'))
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
  assert.equal(a.scope.tabs.at(-1).label, 'Street View')
  const panel = html.slice(html.indexOf(`ng-if="tab === 'streetview'"`), html.indexOf(`ng-if="tab === 'heli'"`))
  for (const part of ['openStreetView()', 'stopStreetView()', 'copyStreetView()', 'goSightseeing()', 'Turn on', 'Turn off', 'Open again'])
    assert.ok(panel.includes(part), part + ' on the Street View tab')
  const header = html.slice(0, html.indexOf('<div ng-if="data.sightseeing.on"'))
  for (const part of ['openStreetView()', 'copyStreetView()', 'goSightseeing()']) assert.ok(!header.includes(part), part + ' not in the header')
  assert.ok(header.includes(`ng-if="data.streetView.on && !data.sightseeing.on"`) && header.includes(`setTab('streetview')`), 'marker opens the tab')
  // The tabs are hidden while sightseeing, so its panel keeps Street View to hand.
  const seeing = html.slice(html.indexOf('<div ng-if="data.sightseeing.on"'), html.indexOf('role="tablist"'))
  assert.ok(seeing.includes('openStreetView()') && seeing.includes('copyStreetView()'), 'Street View while sightseeing')
  a.scope.setTab('streetview'); assert.equal(a.scope.tab, 'streetview')
})

test('tabs sit in two rows: the job on top, the extras below', () => {
  const a = app()
  assert.deepEqual(JSON.parse(JSON.stringify(a.scope.tabRows.map(r => r.map(t => t.id)))), [['route', 'town', 'garage', 'relocate'], ['heli', 'home', 'streetview']])
  assert.ok(html.includes('ng-repeat="row in tabRows"') && html.includes('ng-repeat="t in row"'))
})
test('Ship Day: the Town tab shows the ship, Go to port and the containers to take', () => {
  const a = app()
  const town = html.slice(html.indexOf(`ng-if="tab === 'town'"`), html.indexOf(`ng-if="tab === 'garage'"`))
  for (const part of ['Ship Day:', 'goToPort()', 'takeContainer(b)', 'Go to port (free)']) assert.ok(town.includes(part), part)
  const relocate = html.slice(html.indexOf(`ng-if="tab === 'relocate'"`), html.indexOf(`ng-if="tab === 'home'"`))
  for (const part of ['Ship Day:', 'goToPort()', 'Go to port (free)']) assert.ok(relocate.includes(part), part + ' on the Relocate tab too')
  const box = { n: 3, allowed: true }
  a.state({ state: 'READY', arrived: true, shipDay: { goAllowed: true, containers: [box] } })
  a.commands.length = 0
  a.scope.goToPort()
  a.scope.takeContainer(box)
  a.scope.takeContainer({ n: 4, allowed: false })
  a.scope.takeContainer({ n: 'x); evil(', allowed: true })
  assert.deepEqual(a.commands.map(c => c.replace(/^if earthFreight_core then earthFreight_core\.| end$/g, '')),
    ['goToPort()', 'takeContainer(3, 100)'])
  // The load slider: one share for every container, sent with the one taken, and the pay shown for it.
  assert.ok(town.includes('ng-model="shares.container"'), 'a load slider for the containers')
  a.state({ state: 'READY', arrived: true, shipDay: { goAllowed: true, units: 10, unitKg: 25, containers: [box] } })
  a.scope.shares.container = '40'
  assert.equal(a.scope.containerTaken({ pay: 1000 }).units, 4)
  assert.equal(a.scope.containerTaken({ pay: 1000 }).kg, 100)
  assert.equal(a.scope.containerTaken({ pay: 1000 }).pay, 400)
  a.commands.length = 0
  a.scope.takeContainer(box)
  assert.equal(a.commands[0].replace(/^if earthFreight_core then earthFreight_core\.| end$/g, ''), 'takeContainer(3, 40)')
  a.scope.shares.container = '100'
  a.state({ state: 'READY', arrived: true, shipDay: { goAllowed: false, containers: [] } })
  a.commands.length = 0
  a.scope.goToPort()
  assert.equal(a.commands.length, 0, 'Go to port only when allowed')
  assert.equal(a.scope.until(2 * 86400 + 14 * 3600 + 59), '2d 14h')
  assert.equal(a.scope.until(5 * 3600 + 12 * 60), '5h 12m')
})
test('Ship Day: the Town tab card folds to a summary and Go to port, and remembers it', () => {
  const town = html.slice(html.indexOf(`ng-if="tab === 'town'"`), html.indexOf(`ng-if="tab === 'garage'"`))
  assert.ok(town.includes(`ng-click="toggle('shipday')"`), 'the card has a fold')
  const list = town.indexOf('<div ng-if="shipDayOpen()"'), repeat = town.indexOf('ng-repeat="b in data.shipDay.containers"')
  assert.ok(list >= 0 && list < repeat, 'the containers only show when it is open')
  assert.ok(town.indexOf('Go to port (free)') < list, 'Go to port shows when it is folded')
  const saved = {}
  const storage = { getItem: k => (k in saved ? saved[k] : null), setItem: (k, v) => { saved[k] = String(v) } }
  const a = app(storage)
  a.state({ state: 'READY', arrived: true, shipDay: { goAllowed: true, atPort: false, containers: [] } })
  assert.equal(a.scope.shipDayOpen(), false, 'it starts folded')
  a.scope.toggle('shipday')
  assert.equal(a.scope.shipDayOpen(), true)
  const b = app(storage)
  b.state({ state: 'READY', arrived: true, shipDay: { goAllowed: true, atPort: false, containers: [] } })
  assert.equal(b.scope.shipDayOpen(), true, 'kept after the game restarts')
  b.scope.toggle('shipday')
  b.state({ state: 'READY', arrived: true, shipDay: { atPort: true, containers: [] } })
  assert.equal(b.scope.shipDayOpen(), true, 'at the port with no container, the list opens to pick one')
  b.state({ state: 'READY', arrived: true, shipDay: { atPort: true, carrying: 3, containers: [] } })
  assert.equal(b.scope.shipDayOpen(), false, 'once one is on board it folds again')
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
test('Play online shows whether the server is up and how many are on it, from its stats', async () => {
  const asked = []
  let answer = { ok: true, json: async () => ({ updated: '2026-11-10T18:44:23Z', server: { name: 'WW Trucking Career | MadMerick', online: true, maxPlayers: 20 },
    players: [{ name: 'A' }, { name: 'B' }], season: { number: 1, day: 2, truckers: 10 } }) }
  const now = Date.parse('2026-11-10T18:50:00Z')
  const a = app(null, null, { fetch: url => { asked.push(url); return Promise.resolve(answer) }, Date: { now: () => now, parse: Date.parse } })
  assert.equal(a.scope.server.status, 'checking')
  a.scope.openIntro()
  await new Promise(r => setImmediate(r))
  assert.deepEqual(asked, ['https://raw.githubusercontent.com/MadMerick01/trucking-server-stats/main/status.json'])
  assert.equal(a.scope.server.status, 'online')
  assert.equal(a.scope.server.players, 2); assert.equal(a.scope.server.max, 20); assert.equal(a.scope.server.season, 1)
  assert.equal(a.scope.server.name, 'WW Trucking Career | MadMerick')
  a.scope.toggleOnline()
  assert.equal(asked.length, 1, 'asked at most once a minute')
  const read = a.scope.readServer
  assert.equal(read({ updated: '2026-11-10T18:20:00Z', server: { online: true } }, now).status, 'offline', 'stats older than 15 minutes')
  assert.equal(read({ updated: '2026-11-10T18:49:00Z', server: { online: true }, sample: true }, now).status, 'offline', 'the sample is not the server')
  assert.equal(read(null, now).status, 'offline')
  assert.equal(read({ server: { name: 'x'.repeat(200), maxPlayers: -3 } }, now).name.length, 60)
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
