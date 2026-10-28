/* global angular, bngApi */
angular.module('beamng.apps').directive('earthFreightHud', ['$rootScope', function ($rootScope) {
  // What the player was looking at. BeamNG rebuilds the app each time the parts menu or the map
  // closes, so this is kept out here and the new app carries on where the old one was.
  var kept = {
    tab: 'route', introShown: false, intro: { open: false, name: '', steps: false }, shares: {},
    ship: { query: '', coords: '', error: null }, last: null, hud: null
  }
  // Minimised to one button, kept in the browser's storage so it lasts across game restarts.
  var STORE = 'earthFreight.hudMinimised'
  var stored = function () { try { return window.localStorage.getItem(STORE) === '1' } catch (e) { return false } }
  var store = function (on) { try { window.localStorage.setItem(STORE, on ? '1' : '0') } catch (e) {} }
  // The parts bill box. The HUD is hidden while the game's parts menu is open, so Lua sends each new
  // bill here and the box goes on the page itself, over the menu. It stays until the player closes
  // it, Lua says the bill was paid or undone, or the menu closes and the HUD is built again.
  var bill = null
  var closeBill = function () {
    if (bill && bill.parentNode) bill.parentNode.removeChild(bill)
    bill = null
  }
  var line = function (box, text, css) {
    var div = document.createElement('div')
    div.textContent = text
    div.style.cssText = css
    box.appendChild(div)
  }
  var showBill = function (data) {
    closeBill()
    if (typeof document === 'undefined' || !document.body) return
    var gold = data.short ? '#eb5757' : '#f2c94c'
    var box = document.createElement('div')
    box.setAttribute('role', 'alert')
    box.style.cssText = 'position:fixed;top:12%;left:50%;transform:translateX(-50%);z-index:2147483647;' +
      'width:440px;max-width:80vw;padding:14px 18px;background:rgba(12,19,24,.96);color:#f2f6f5;' +
      'border:3px solid ' + gold + ';border-radius:10px;box-shadow:0 0 24px rgba(0,0,0,.7);' +
      'font:15px/1.4 sans-serif;pointer-events:auto;'
    var close = document.createElement('button')
    close.type = 'button'
    close.textContent = 'Close'
    close.style.cssText = 'float:right;margin-left:10px;padding:5px 12px;background:' + gold + ';color:#0c1318;' +
      'font-weight:bold;border:none;border-radius:4px;cursor:pointer;'
    close.onclick = closeBill
    box.appendChild(close)
    line(box, 'PARTS BILL', 'font-weight:bold;letter-spacing:1px;font-size:13px;color:' + gold + ';')
    line(box, String(data.total || ''), 'font-weight:bold;font-size:22px;color:' + gold + ';margin-top:2px;')
    // Each part, as on the Garage tab's bill; just the split when there is no list.
    var lines = Array.isArray(data.lines) ? data.lines : []
    if (!lines.length) line(box, String(data.detail || ''), 'margin-top:4px;')
    lines.forEach(function (l) {
      var row = document.createElement('div')
      row.style.cssText = 'display:flex;gap:8px;margin-top:2px;'
      line(row, String(l.label || ''), 'flex:1;min-width:0;')
      line(row, String(l.amount || ''), '')
      box.appendChild(row)
    })
    if (data.money) line(box, String(data.money), 'font-weight:bold;margin-top:6px;')
    if (data.short) line(box, String(data.short), 'font-weight:bold;color:#eb5757;margin-top:4px;')
    if (data.payWhy) line(box, String(data.payWhy), 'color:#eb5757;margin-top:4px;')
    var serial = parseInt(data.serial, 10)
    var lua = function (body) {
      if (typeof bngApi !== 'undefined' && bngApi.engineLua) bngApi.engineLua('if earthFreight_core then earthFreight_core.' + body + ' end')
    }
    // Pay asks once more, as on the Garage tab, then pays this bill.
    var cost = typeof data.cost === 'number' && isFinite(data.cost) ? data.cost : null
    if (data.payAllowed && serial > 0 && cost !== null) {
      var amount = '$' + Math.round(cost).toLocaleString('en-US')
      var pay = document.createElement('button')
      pay.type = 'button'
      pay.textContent = 'Pay ' + amount
      pay.style.cssText = 'margin-top:10px;padding:7px 14px;background:#f2c94c;color:#0c1318;font-weight:bold;' +
        'border:none;border-radius:4px;cursor:pointer;'
      var asked = false
      pay.onclick = function () {
        if (!asked) { asked = true; pay.textContent = 'Yes, pay ' + amount; return }
        pay.disabled = true
        pay.textContent = 'Paying...'
        lua('payPartsBill(' + serial + ')')
      }
      box.appendChild(pay)
    }
    line(box, String(data.hint || ''), 'margin-top:6px;color:#c9d6d2;font-size:13px;')
    document.body.appendChild(box)
    bill = box
    if (serial > 0) lua('partsBillShown(' + serial + ')')
  }
  $rootScope.$on('EarthFreightPartsBill', function (event, data) {
    if (data && data.open) showBill(data); else closeBill()
  })
  return {
    templateUrl: '/ui/modules/apps/TruckingCareerDC/app.html',
    replace: true,
    link: function (scope, element) {
      'use strict'
      // Built again once the game's menus close: the HUD shows the bill from here.
      closeBill()
      var disposed = false
      var lastMessage = Date.now()
      scope.data = { state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR EARTH FREIGHT SIM', saveAllowed: false }
      var call = function (command) {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) bngApi.engineLua(command)
      }
      var core = function (body) { call('if earthFreight_core then earthFreight_core.' + body + ' end') }
      var mount = function (on) { core('uiMounted(' + (on ? 'true' : 'false') + ')') }
      // Each part of the HUD sits on its own tab so the app stays short.
      scope.tabs = [{ id: 'route', label: 'Route' }, { id: 'town', label: 'Town' }, { id: 'garage', label: 'Garage' },
        { id: 'relocate', label: 'Relocate' }]
      scope.tab = kept.tab
      scope.setTab = function (id) { scope.tab = kept.tab = id }
      // Marks a tab that has something waiting for the player.
      var alerts = {
        route: function (d) {
          return !!d.resume || !!d.stranded || !!(d.shortages && d.shortages.length) ||
            !!(d.load && d.load.drop && d.load.drop.delivery && d.load.drop.delivery.allowed)
        },
        town: function (d) {
          var t = d.town
          if (!t) return false
          if (t.delivery && t.delivery.allowed) return true
          return !d.load && (t.jobs || []).some(function (j) { return j.allowed })
        },
        garage: function (d) {
          return !!d.partsChange || !!d.carChange || d.repairOwed > 0 || !!d.puncture || !!d.insurance
        },
        relocate: function (d) { return !!(d.shipping && d.shipping.booking) }
      }
      scope.tabAlert = function (id) { return !!alerts[id] && alerts[id](scope.data || {}) }
      // The HUD shrinks to a Worldwide Trucking button. Its dot is red for bad news, gold for anything a
      // tab marks, so the player can tell from the button alone that the HUD has something for them.
      if (!kept.hud) kept.hud = { minimised: stored() }
      scope.hud = kept.hud
      // BeamNG keeps the app's box at its full layout size and outlines it, so a minimised HUD
      // would leave an empty frame. The box shrinks to the button, and gets its size back on open.
      var box = element && element[0] && element[0].parentElement
      var boxSize = null
      var fitBox = function (small) {
        if (!box || !box.style) return
        if (small && !boxSize) {
          boxSize = { width: box.style.width, height: box.style.height }
          box.style.width = 'auto'; box.style.height = 'auto'
        } else if (!small && boxSize) {
          box.style.width = boxSize.width; box.style.height = boxSize.height
          boxSize = null
        }
      }
      scope.setMinimised = function (on) { scope.hud.minimised = !!on; store(!!on); fitBox(!!on) }
      fitBox(scope.hud.minimised)
      scope.hudAlert = function (d) {
        d = d || scope.data || {}
        if (d.flash && (d.flash.kind === 'cancelled' || d.flash.kind === 'puncture')) return 'bad'
        for (var id in alerts) if (alerts[id](d)) return 'waiting'
        return ''
      }
      // Opens a tab when its bill, town or coordinates first appear; the player can switch away after.
      var autoOpen = [
        ['garage', function (d) { return !!d.carChange }], ['garage', function (d) { return !!d.partsChange }],
        ['garage', function (d) { return !!d.insurance }],
        ['town', function (d) { return !!d.town }], ['route', function (d) { return !!d.resume || !!d.startHereAllowed || !!d.stranded }]
      ]
      var follow = function (previous, next) {
        // The start page opens once on a new game or on loading a save, until the player is there.
        if (next.arrived || (previous.mode && previous.mode !== next.mode)) kept.introShown = false
        if ((next.mode === 'start' || next.mode === 'resume') && !next.arrived && !kept.introShown) {
          kept.introShown = true; scope.openIntro(next); scope.setMinimised(false)
        }
        for (var i = 0; i < autoOpen.length; i++) {
          if (autoOpen[i][1](next) && !autoOpen[i][1](previous)) {
            scope.setTab(autoOpen[i][0])
            // A bill, an insurance offer or being stranded needs the player, so a minimised HUD
            // opens for it. Arriving in a town only lights the button's dot.
            if (autoOpen[i][0] !== 'town') scope.setMinimised(false)
            return
          }
        }
        if (scope.tab === 'town' && !next.town) scope.setTab('route')
      }
      // The start page: the player's name and how to play. It covers the rest of the HUD while open.
      scope.intro = kept.intro
      scope.openIntro = function (d) {
        scope.intro.name = ((d || scope.data || {}).playerName) || ''
        scope.intro.open = true
      }
      // Letters in any alphabet, digits, spaces, dots, apostrophes and hyphens; at most 20 of them.
      var notInName
      try { notInName = new RegExp("[^\\p{L}\\p{M}\\p{N} .'-]", 'gu') } catch (e) { notInName = /[^A-Za-z0-9\u00C0-\u024F .'-]/g }
      scope.cleanName = function (text) {
        var name = String(text == null ? '' : text).replace(notInName, '').replace(/\s+/g, ' ').trim()
        return Array.from(name).slice(0, 20).join('').trim()
      }
      scope.closeIntro = function () {
        var name = scope.cleanName(scope.intro.name)
        if (name !== ((scope.data && scope.data.playerName) || '')) core('setPlayerName("' + name + '")')
        scope.typing(false)
        scope.intro.open = false
        scope.cancelNewGame()
      }
      // Loaded from a save and not back at it yet: the start page shows where to go.
      scope.returning = function (d) { return !!d && d.mode === 'resume' && !d.arrived && !!d.resume }
      // A new game that has not reached the start town yet: nothing to show or start over.
      scope.firstLaunch = function (d) { return !!d && d.mode === 'start' && !d.arrived }
      scope.introSteps = [
        'open the BeamNG.Earth map, find anywhere on Earth, such as your home town, and teleport there. Then press Start here: your starter car is waiting.',
        'Fit a radiator first: the starter car needs one. Press Buy parts on the Garage tab, fit one and pay there.',
        'Stop in a town. The Town tab lists its jobs with what each pays. Press Take job: it fills your car.',
        'Follow the GPS to the drop-off, stop in the town and press Deliver to get paid in full.',
        'Press Save often. Anything since your last Save is lost when you exit.'
      ]
      // While a text box has focus the game's keys are off, so typing does not drive the car.
      var typingNow = false
      scope.typing = function (on) {
        if (typingNow === !!on) return
        typingNow = !!on
        call('if setCEFTyping then setCEFTyping(' + typingNow + ') end')
      }
      // Dot and pay colours: green pays above the usual, red below, gold for a shortage or a jackpot.
      var colors = { high: '#6fcf97', low: '#eb5757', sweet: '#f2c94c' }
      scope.dotColor = function (level) { return colors[level] || '#7d8b88' }
      scope.km = function (metres) { return typeof metres === 'number' && isFinite(metres) ? (metres / 1000).toFixed(1) : '' }
      // The one message under the header: what just happened, then what to do. One object is
      // reused, as Angular watches it by reference.
      var notice = { title: '', text: '', color: '#a7e5c9', alert: false }
      scope.notice = function (d) {
        if (!d) return null
        if (d.flash) {
          var bad = d.flash.kind === 'cancelled' || d.flash.kind === 'puncture'
          notice.title = d.flash.title; notice.text = d.flash.text
          notice.color = bad ? '#eb5757' : '#6fcf97'; notice.alert = bad
          return notice
        }
        if (!d.stateLabel && !d.sessionStatus) return null
        if (d.state === 'READY' && d.arrived && !d.sessionStatus) return null
        notice.title = d.stateLabel || ''; notice.text = d.sessionStatus; notice.color = '#a7e5c9'; notice.alert = false
        return notice
      }
      // True when there is money, spending or mileage that a Save would keep.
      scope.unsaved = function (d) {
        return !!d && (!!d.nameUnsaved || d.unsavedBalance > 0 || d.unsavedSpending > 0 || d.unsavedDistanceKm >= 0.005)
      }
      var plainId = function (id) { return /^[a-z0-9_]+$/.test(String(id)) }
      // The load slider: how much of each job to take, 10% to 100% in steps of 10, by job id. Older
      // AngularJS (as in BeamNG's UI) gives a range input's value as a string, so it is parsed here.
      scope.shares = kept.shares
      scope.shareOf = function (job) {
        var share = job ? parseInt(scope.shares[job.id], 10) : NaN
        return share >= 10 && share <= 100 && share % 10 === 0 ? share : 100
      }
      // What that share comes to, as Lua works it out: whole units (at least one), their kg, and a
      // straight share of the pay in tens of dollars.
      var taken = { units: 0, kg: 0, pay: 0 }
      scope.taken = function (job) {
        if (!job || !(job.units > 0)) { taken.units = 0; taken.kg = 0; taken.pay = 0; return taken }
        var units = Math.max(1, Math.min(job.units, Math.floor(job.units * scope.shareOf(job) / 100 + 0.5)))
        taken.units = units
        taken.kg = units * job.unitKg
        taken.pay = units === job.units ? job.pay : Math.max(10, Math.floor(job.pay * units / job.units / 10 + 0.5) * 10)
        return taken
      }
      scope.takeJob = function (job) {
        if (!scope.data.town || scope.data.load || !job || !job.allowed || !plainId(job.id)) return
        core("takeJob('" + job.id + "', " + scope.shareOf(job) + ')')
      }
      scope.deliverJob = function () {
        var d = scope.data
        var town = d.town && d.town.delivery && d.town.delivery.allowed
        var drop = d.load && d.load.drop && d.load.drop.delivery && d.load.drop.delivery.allowed
        if (town || drop) core('deliverJob()')
      }
      // The off-road drop's arrow, turned by how far the spot is off the way the car points.
      var arrow = {}
      scope.arrowStyle = function (drop) {
        var turn = drop && typeof drop.arrow === 'number' && isFinite(drop.arrow) ? Math.round(drop.arrow) : 0
        arrow.transform = 'rotate(' + turn + 'deg)'
        return arrow
      }
      scope.refuel = function () { if (scope.data.town && scope.data.town.refuelAllowed) core('refuel()') }
      scope.abandonJob = function () { if (scope.data.abandonAllowed) core('abandonJob()') }
      scope.claimInsurance = function () { if (scope.data.insurance && scope.data.insurance.allowed) core('claimInsurance()') }
      scope.bookShipping = function (destination) {
        if (scope.data.shipping && !scope.data.shipping.booking && plainId(destination)) core("bookShipping('" + destination + "')")
      }
      // Shipping anywhere: a town by name, or coordinates pasted from a map.
      scope.ship = kept.ship
      scope.searchShipping = function () {
        var q = String(scope.ship.query || '').replace(/[^A-Za-z0-9 .-]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60)
        if (scope.data.shipping && q.length >= 2) core("searchShipping('" + q + "')")
      }
      scope.parseCoordinates = function (text) {
        var m = /^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ''))
        if (!m) return null
        var lat = parseFloat(m[1]), lon = parseFloat(m[2])
        if (!(lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)) return null
        return { latitude: lat, longitude: lon }
      }
      scope.bookCoordinates = function () {
        var p = scope.parseCoordinates(scope.ship.coords)
        scope.ship.error = p ? null : 'Paste latitude, longitude, like -16.19, -67.73.'
        if (p && scope.data.shipping && !scope.data.shipping.booking) core('bookShippingTo(' + p.latitude + ', ' + p.longitude + ')')
      }
      scope.bookOffer = function () { if (scope.data.shipping && scope.data.shipping.offer && scope.data.shipping.offer.allowed) core('bookOffer()') }
      scope.clock = function (seconds) {
        if (typeof seconds !== 'number' || !isFinite(seconds)) return ''
        var s = Math.max(0, Math.ceil(seconds))
        return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2)
      }
      scope.cancelShipping = function () { if (scope.data.shipping && scope.data.shipping.booking) core('cancelShipping()') }
      scope.save = function () { if (scope.data.saveAllowed) core('save()') }
      scope.requestRepairQuote = function () { if (scope.data.repairQuoteAllowed) core('requestRepairQuote()') }
      scope.repairVehicle = function () { if (scope.data.repairAllowed) core('repairVehicle()') }
      scope.takeLoan = function () { if (scope.data.loan && scope.data.loan.takeAllowed) core('takeLoan()') }
      scope.repayLoan = function () { if (scope.data.loan && scope.data.loan.repayAllowed) core('repayLoan()') }
      scope.towToRoad = function () { if (scope.data.tow && scope.data.tow.allowed) core('towToRoad()') }
      // Paying for a bill takes two presses: the first asks to confirm that total, and a changed
      // total asks again.
      scope.confirming = { kind: null, cost: null }
      scope.askToPay = function (kind, cost) { scope.confirming.kind = kind; scope.confirming.cost = cost }
      scope.isConfirming = function (kind, cost) { return scope.confirming.kind === kind && scope.confirming.cost === cost }
      scope.cancelPay = function () { scope.confirming.kind = null; scope.confirming.cost = null }
      scope.buyParts = function () { if (scope.data.buyPartsAllowed) core('buyParts()') }
      scope.revertParts = function () { if (scope.data.revertPartsAllowed) core('revertParts()') }
      scope.buyCar = function () { if (scope.data.buyCarAllowed) core('buyCar()') }
      scope.revertCar = function () { if (scope.data.revertCarAllowed) core('revertCar()') }
      // Buy second hand: opens or closes the town's list; a car is picked by its place in it.
      scope.openUsedCars = function (open) { core('openUsedCars(' + (open ? 'true' : 'false') + ')') }
      scope.buyUsedCar = function (offer) {
        if (offer && offer.allowed && [1, 2, 3, 4, 5, 6, 7, 8, 9].indexOf(offer.slot) >= 0) core('buyUsedCar(' + offer.slot + ')')
      }
      // Open the game's own parts menu (Ctrl+W) and car selector (Ctrl+E); the bill then shows up on the Garage tab.
      scope.openPartsMenu = function () {
        call("if core_vehicles and core_vehicles.openPartsSelectorUI then core_vehicles.openPartsSelectorUI() " +
          "elseif guihooks then guihooks.trigger('ChangeState', {state = 'menu.vehicleconfig.parts'}) end")
      }
      // Runs the game's own Ctrl+E action: changing the UI state to the old menu.vehicles route hides
      // the whole UI in this game version instead of opening the car selector.
      scope.openCarMenu = function () {
        call("if core_input_actions and core_input_actions.triggerDownUp then core_input_actions.triggerDownUp('vehicle_selector') end")
      }
      // The first press asks Lua to confirm; the second wipes the save.
      scope.newGame = function () { if (scope.data.newGameAllowed) core('newGame()') }
      scope.cancelNewGame = function () { if (scope.data && scope.data.newGameArmed) core('cancelNewGame()') }
      scope.coordinates = function (position) {
        if (!position || typeof position.latitude !== 'number' || typeof position.longitude !== 'number' ||
            !isFinite(position.latitude) || !isFinite(position.longitude) ||
            Math.abs(position.latitude) > 90 || Math.abs(position.longitude) > 180) return ''
        return position.latitude.toFixed(8) + ', ' + position.longitude.toFixed(8)
      }
      // The mod asks BeamNG.Earth to teleport the player to the last save (or the start town).
      // Start here: a new game starts wherever the player is. The start page closes, keeping the name.
      scope.startHere = function () {
        if (!scope.data || !scope.data.startHereAllowed) return
        if (scope.intro.open) scope.closeIntro()
        core('startHere()')
      }
      scope.teleportToResume = function () { if (scope.data && scope.data.teleportAllowed) core('teleportToResume()') }
      // ...and to the start of a dangerous contract just taken.
      scope.teleportToContract = function () {
        var load = scope.data && scope.data.load
        if (load && load.contract && load.contract.teleportAllowed) core('teleportToContract()')
      }
      scope.teleportToBooking = function () {
        var booking = scope.data && scope.data.shipping && scope.data.shipping.booking
        if (booking && booking.teleportAllowed) core('teleportToBooking()')
      }
      scope.copyCoordinates = function (position) {
        var text = scope.coordinates(position)
        if (text) call('setClipboard("' + text + '")')
      }
      scope.$on('EarthFreightState', function (event, data) {
        if (disposed || !data || typeof data.state !== 'string') return
        lastMessage = Date.now()
        scope.$evalAsync(function () {
          if (disposed) return
          // Compared with the last state any app saw, so a rebuilt app does not reopen a tab.
          follow(kept.last || {}, data)
          kept.last = data
          scope.data = data
        })
      })
      mount(true)
      var heartbeat = setInterval(function () {
        if (disposed) return
        mount(true)
        if (Date.now() - lastMessage > 6000) {
          scope.$evalAsync(function () {
            if (disposed) return
            scope.data = {
              state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR EARTH FREIGHT SIM', saveAllowed: false,
              sessionStatus: 'Worldwide Trucking Career is not responding. Check that the mod is enabled, then reload it.'
            }
          })
        }
      }, 3000)
      scope.$on('$destroy', function () {
        disposed = true
        fitBox(false)
        scope.typing(false)
        clearInterval(heartbeat)
        mount(false)
      })
    }
  }
}])
