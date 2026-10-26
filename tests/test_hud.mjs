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
  const a = { scope, commands, handlers, timers, state, advance: ms => { clock += ms; for (const tick of timers.values()) tick() } }
  // BeamNG rebuilds the app when a menu closes: the old one is destroyed and a new one linked.
  a.remount = () => {
    handlers.$destroy()
    a.scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
    definition.link(a.scope)
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
    save: ['saveAllowed', 'save()'], addTestMoney: ['testMoneyAllowed', 'addTestMoney()'],
    requestRepairQuote: ['repairQuoteAllowed', 'requestRepairQuote()'], repairVehicle: ['repairAllowed', 'repairVehicle()'],
    buyParts: ['buyPartsAllowed', 'buyParts()'], revertParts: ['revertPartsAllowed', 'revertParts()'],
    buyCar: ['buyCarAllowed', 'buyCar()'], revertCar: ['revertCarAllowed', 'revertCar()'],
    newGame: ['newGameAllowed', 'newGame()'], abandonJob: ['abandonAllowed', 'abandonJob()']
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
  assert.ok(html.includes('ng-if="data.load.drop"') && html.includes('ng-style="arrowStyle(data.load.drop)"'), 'the Route tab shows the arrow')
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
test('colours: green above the usual pay, red below, gold for a shortage or jackpot', () => {
  const a = app()
  assert.equal(a.scope.dotColor('high'), '#6fcf97'); assert.equal(a.scope.dotColor('low'), '#eb5757')
  assert.equal(a.scope.dotColor('sweet'), '#f2c94c'); assert.equal(a.scope.dotColor('normal'), '#7d8b88')
})
test('a serious crash opens the Garage tab, and a shortage marks the Route tab without opening it', () => {
  const a = app()
  a.state({ state: 'READY', arrived: true }); a.scope.setTab('tips')
  a.state({ state: 'READY', arrived: true, shortages: [{ town: 'Katoomba' }] })
  assert.equal(a.scope.tab, 'tips'); assert.equal(a.scope.tabAlert('route'), true)
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
test('the HUD keeps money, Save, the message and the load outside the tabs', () => {
  const panels = html.indexOf('role="tabpanel"')
  for (const always of ['ng-click="save()"', 'data.balance', 'notice(data)', 'data.load.to', 'data.fuel.litres', 'copyCoordinates(data.resume)']) {
    assert.ok(html.indexOf(always) > -1 && html.indexOf(always) < panels, always)
  }
  for (const id of ['route', 'town', 'garage', 'tips']) assert.ok(html.includes(`ng-if="tab === '${id}'"`), id)
  for (const action of ['cancelPay(); buyParts()', 'revertParts()', 'cancelPay(); buyCar()', 'revertCar()', 'requestRepairQuote()', 'repairVehicle()',
    'newGame()', 'cancelNewGame()', 'addTestMoney()', 'deliverJob()', 'refuel()', 'abandonJob()', 'takeJob(j)', 'claimInsurance()']) {
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
  assert.ok(html.includes("firstLaunch(data) ? 'Let’s go' : 'Continue'"), 'Continue, except on a brand new game')
  assert.ok(html.includes('ng-click="openIntro()"'), 'Profile button and Tips link')
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
  const tips = html.slice(html.indexOf(`ng-if="tab === 'tips'"`))
  assert.ok(!tips.includes('newGame()'), 'no new game button on the Tips tab')
  assert.ok(html.indexOf('ng-click="newGame()"') < html.indexOf('role="tabpanel"'), 'it is on the start page')
})
test('closing the parts menu or the map keeps the tab and does not reopen the start page', () => {
  const a = app()
  a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  a.scope.closeIntro(); a.scope.setTab('garage')
  a.remount(); a.state({ state: 'READY', mode: 'start', playerName: 'Sam' })
  assert.equal(a.scope.intro.open, false, 'start page stays closed')
  assert.equal(a.scope.tab, 'garage', 'same tab as before')
  a.state({ state: 'READY', mode: 'start', town: {} }); a.scope.setTab('tips')
  a.remount(); a.state({ state: 'READY', mode: 'start', town: {} })
  assert.equal(a.scope.tab, 'tips', 'a town already there does not open the Town tab again')
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
