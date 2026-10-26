/* global angular, bngApi */
angular.module('beamng.apps').directive('earthFreightHud', [function () {
  // What the player was looking at. BeamNG rebuilds the app each time the parts menu or the map
  // closes, so this is kept out here and the new app carries on where the old one was.
  var kept = {
    tab: 'route', introShown: false, intro: { open: false, name: '', steps: false }, shares: {},
    ship: { query: '', coords: '', error: null }, last: null
  }
  return {
    templateUrl: '/ui/modules/apps/EarthFreightHUD/app.html',
    replace: true,
    link: function (scope) {
      'use strict'
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
      // Opens a tab when its bill, town or coordinates first appear; the player can switch away after.
      var autoOpen = [
        ['garage', function (d) { return !!d.carChange }], ['garage', function (d) { return !!d.partsChange }],
        ['garage', function (d) { return !!d.insurance }],
        ['town', function (d) { return !!d.town }], ['route', function (d) { return !!d.resume || !!d.stranded }]
      ]
      var follow = function (previous, next) {
        // The start page opens once on a new game or on loading a save, until the player is there.
        if (next.arrived || (previous.mode && previous.mode !== next.mode)) kept.introShown = false
        if ((next.mode === 'start' || next.mode === 'resume') && !next.arrived && !kept.introShown) {
          kept.introShown = true; scope.openIntro(next)
        }
        for (var i = 0; i < autoOpen.length; i++) {
          if (autoOpen[i][1](next) && !autoOpen[i][1](previous)) { scope.setTab(autoOpen[i][0]); return }
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
        'copy the coordinates, paste them into the BeamNG.Earth map and teleport there. Your starter car is waiting.',
        'Fit a radiator first: the starter car needs one. Use the parts menu (Ctrl+W) and pay on the Garage tab.',
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
      // The Town tab's cargo card: slots in the boxes, how many the load on board takes and how many
      // are free. A fluid load sits in the tank, so it takes no slots.
      var room = { total: 0, used: 0, free: 0, percent: 0 }
      scope.cargoRoom = function (d) {
        var total = d && d.space && d.space.slots > 0 ? d.space.slots : 0
        var load = d && d.load
        var used = load && !(load.litres > 0) && load.slots > 0 ? Math.min(load.slots, total) : 0
        room.total = total
        room.used = used
        room.free = total - used
        room.percent = total > 0 ? Math.round(used / total * 100) : 0
        return room
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
      scope.addTestMoney = function () { if (scope.data.testMoneyAllowed) core('addTestMoney()') }
      scope.requestRepairQuote = function () { if (scope.data.repairQuoteAllowed) core('requestRepairQuote()') }
      scope.repairVehicle = function () { if (scope.data.repairAllowed) core('repairVehicle()') }
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
      // The first press asks Lua to confirm; the second wipes the save.
      scope.newGame = function () { if (scope.data.newGameAllowed) core('newGame()') }
      scope.cancelNewGame = function () { if (scope.data && scope.data.newGameArmed) core('cancelNewGame()') }
      scope.coordinates = function (position) {
        if (!position || typeof position.latitude !== 'number' || typeof position.longitude !== 'number' ||
            !isFinite(position.latitude) || !isFinite(position.longitude) ||
            Math.abs(position.latitude) > 90 || Math.abs(position.longitude) > 180) return ''
        return position.latitude.toFixed(8) + ', ' + position.longitude.toFixed(8)
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
              sessionStatus: 'Earth Freight Sim is not responding. Check that the mod is enabled, then reload it.'
            }
          })
        }
      }, 3000)
      scope.$on('$destroy', function () {
        disposed = true
        scope.typing(false)
        clearInterval(heartbeat)
        mount(false)
      })
    }
  }
}])
