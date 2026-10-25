import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'

const APP = '../mod/earth_freight/ui/modules/apps/EarthFreightHUD/'
const source = readFileSync(new URL(APP + 'app.js', import.meta.url), 'utf8')
const html = readFileSync(new URL(APP + 'app.html', import.meta.url), 'utf8')
const fixed = body => 'if earthFreight_core then earthFreight_core.' + body + ' end'
function app() {
  const commands = [], handlers = {}, timers = new Map()
  let definition, clock = 0
  const scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
  vm.runInNewContext(source, {
    angular: { module(name) {
      assert.equal(name, 'beamng.apps')
      return { directive(id, factory) { assert.equal(id, 'earthFreightHud'); definition = factory.at(-1)() } }
    } },
    bngApi: { engineLua: command => commands.push(command) },
    setInterval: fn => { timers.set(1, fn); return 1 },
    clearInterval: id => timers.delete(id), Date: { now: () => clock }
  })
  definition.link(scope)
  const state = data => handlers.EarthFreightState({}, data)
  return { scope, commands, handlers, timers, state, advance: ms => { clock += ms; for (const tick of timers.values()) tick() } }
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
    save: ['saveAllowed', 'save()'], addTestMoney: ['testMoneyAllowed', 'addTestMoney()'],
    requestRepairQuote: ['repairQuoteAllowed', 'requestRepairQuote()'], repairVehicle: ['repairAllowed', 'repairVehicle()'],
    buyParts: ['buyPartsAllowed', 'buyParts()'], revertParts: ['revertPartsAllowed', 'revertParts()'],
    buyCar: ['buyCarAllowed', 'buyCar()'], revertCar: ['revertCarAllowed', 'revertCar()'],
    newGame: ['newGameAllowed', 'newGame()'], dumpLoad: ['dumpAllowed', 'dumpLoad()']
  }
  for (const [name, [flag, body]] of Object.entries(buttons)) {
    const count = a.commands.length
    a.state({ state: 'READY' }); a.scope[name]()
    assert.equal(a.commands.length, count, name + ' refused when not allowed')
    a.state({ state: 'READY', [flag]: true }); a.scope[name]()
    assert.equal(a.commands.at(-1), fixed(body), name)
  }
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
})
test('town buttons only send fixed commands, with plain ids, when Lua enabled them', () => {
  const a = app()
  a.state({ state: 'READY', town: {} })
  a.scope.buyLoad('food', 'gn1'); a.scope.sellLoad(); a.scope.refuel()
  assert.equal(a.commands.length, 1)
  a.state({ state: 'READY', town: { buyAllowed: true, sellAllowed: true, refuelAllowed: true } })
  a.scope.buyLoad('food', "gn1') os.exit() --", 1); a.scope.buyLoad("x'", 'gn1', 1)
  a.scope.buyLoad('food', 'gn1', 0); a.scope.buyLoad('food', 'gn1', 1.5); a.scope.buyLoad('food', 'gn1', '1) os.exit(')
  assert.equal(a.commands.length, 1, 'odd ids and counts never sent')
  a.scope.buyLoad('food', 'gn2153471', 3)
  assert.equal(a.commands.at(-1), fixed("buyLoad('food', 'gn2153471', 3)"))
  a.scope.sellLoad(); assert.equal(a.commands.at(-1), fixed('sellLoad()'))
  a.scope.refuel(); assert.equal(a.commands.at(-1), fixed('refuel()'))
})
test('the buy count starts at the most you can take and stays within 1 and that', () => {
  const a = app()
  const g = { id: 'parts', slots: 4, price: 100 }
  assert.equal(a.scope.buyCount(g), 4, 'max by default')
  a.scope.stepCount(g, -1); assert.equal(a.scope.buyCount(g), 3)
  a.scope.setCount(1); a.scope.stepCount(g, -1); assert.equal(a.scope.buyCount(g), 1, 'never below 1')
  a.scope.setCount(9); assert.equal(a.scope.buyCount(g), 4, 'never above what you can take')
  assert.equal(a.scope.profit(g, { price: 130 }), 120, 'profit on that many')
  assert.equal(a.scope.profit(g, { price: 130, freight: 20 }), 200, 'freight pay counts in the profit')
  assert.equal(a.scope.profit(g, { price: 130, bonus: 30, freight: 20 }), 320, 'the town pay bonus counts in the profit')
  a.scope.setCount(2); assert.equal(a.scope.buyCount({ slots: 1 }), 1, 'shrinks when you can take fewer')
  assert.equal(a.scope.buyCount({ slots: 0 }), 0, 'nothing when nothing fits')
  a.scope.pickGood('food'); assert.equal(a.scope.buyCount(g), 4, 'a new good starts at max again')
})
test('the delivery distance starts at the game\'s value and only sends whole km in range', () => {
  const a = app()
  a.scope.range.km = 25; a.scope.setRange()
  assert.equal(a.commands.length, 1, 'nothing sent outside a town')
  a.scope.range.km = null
  a.state({ state: 'READY', town: { range: { km: 10, min: 5, max: 50, step: 5 } } })
  assert.equal(a.scope.range.km, 10, 'starts at the game value')
  a.scope.range.km = 25; a.scope.setRange()
  assert.equal(a.commands.at(-1), fixed('setDeliveryRange(25)'))
  const sent = a.commands.length
  for (const odd of [0, 55, 12.5, '20) os.exit(', null]) { a.scope.range.km = odd; a.scope.setRange() }
  assert.equal(a.commands.length, sent, 'odd values never sent')
  a.scope.range.km = '35'; a.scope.setRange()
  assert.equal(a.commands.at(-1), fixed('setDeliveryRange(35)'), 'a string value from older AngularJS is parsed')
  a.state({ state: 'READY', town: { range: { km: 35, min: 5, max: 50, step: 5 } } })
  a.scope.stepRange(5); assert.equal(a.commands.at(-1), fixed('setDeliveryRange(40)'), '+ steps up')
  a.scope.range.km = 50; a.scope.stepRange(5); assert.equal(a.commands.at(-1), fixed('setDeliveryRange(50)'), 'never past 50')
})
test('the picked good defaults to the best run, then the first good', () => {
  const a = app()
  const goods = [{ id: 'parts' }, { id: 'food' }]
  assert.equal(a.scope.pickedGood({ town: { goods }, bestRun: { goodId: 'food' } }).id, 'food')
  assert.equal(a.scope.pickedGood({ town: { goods } }).id, 'parts')
  a.scope.pickGood('food'); assert.equal(a.scope.pickedGood({ town: { goods } }).id, 'food')
  assert.equal(a.scope.pickedGood({}), null)
})
test('arriving in a town opens the Town tab once, and leaving goes back to Route', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true })
  assert.equal(a.scope.tab, 'route')
  a.state({ state: 'READY', arrived: true, town: { buyAllowed: true } })
  assert.equal(a.scope.tab, 'town')
  a.scope.setTab('garage'); a.state({ state: 'READY', arrived: true, town: { buyAllowed: true } })
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
test('the HUD keeps money, Save, the message and the load outside the tabs', () => {
  const panels = html.indexOf('role="tabpanel"')
  for (const always of ['ng-click="save()"', 'data.balance', 'notice(data)', 'data.load.to', 'data.fuel.litres', 'copyCoordinates(data.resume)']) {
    assert.ok(html.indexOf(always) > -1 && html.indexOf(always) < panels, always)
  }
  for (const id of ['route', 'town', 'garage', 'tips']) assert.ok(html.includes(`ng-if="tab === '${id}'"`), id)
  for (const action of ['cancelPay(); buyParts()', 'revertParts()', 'cancelPay(); buyCar()', 'revertCar()', 'requestRepairQuote()', 'repairVehicle()',
    'newGame()', 'addTestMoney()', 'sellLoad()', 'refuel()', 'dumpLoad()', 'buyLoad(pickedGood(data).id, p.id, buyCount(pickedGood(data)))']) {
    assert.ok(html.includes(`ng-click="${action}"`), action)
  }
  assert.ok(html.includes('GeoNames'), 'GeoNames credit')
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
  assert.equal(b.scope.intro.open, false, 'not shown when carrying on from a save')
  b.scope.openIntro()
  assert.equal(b.scope.intro.open, true, 'opens from the Profile button')
  assert.ok(html.includes('ng-click="openIntro()"'), 'Profile button and Tips link')
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
