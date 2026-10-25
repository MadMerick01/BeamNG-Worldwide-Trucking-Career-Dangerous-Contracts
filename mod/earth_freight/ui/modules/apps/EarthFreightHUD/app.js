/* global angular, bngApi */
angular.module('beamng.apps').directive('earthFreightHud', [function () {
  return {
    templateUrl: '/ui/modules/apps/EarthFreightHUD/app.html',
    replace: true,
    link: function (scope) {
      'use strict'
      var disposed = false
      var lastMessage = Date.now()
      scope.data = { state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR EARTH FREIGHT', saveAllowed: false }
      var call = function (command) {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) bngApi.engineLua(command)
      }
      var core = function (body) { call('if earthFreight_core then earthFreight_core.' + body + ' end') }
      var mount = function (on) { core('uiMounted(' + (on ? 'true' : 'false') + ')') }
      // Each part of the HUD sits on its own tab so the app stays short.
      scope.tabs = [{ id: 'route', label: 'Route' }, { id: 'town', label: 'Town' }, { id: 'garage', label: 'Garage' },
        { id: 'tips', label: 'Tips' }]
      scope.tab = 'route'
      scope.setTab = function (id) { scope.tab = id }
      // Marks a tab that has something waiting for the player.
      var alerts = {
        route: function (d) { return !!d.resume || !!d.stranded },
        town: function (d) { return !!d.town && (!!d.town.sellAllowed || (!!d.town.buyAllowed && !d.load)) },
        garage: function (d) { return !!d.partsChange || !!d.carChange || d.repairOwed > 0 || !!d.puncture || !!(d.shipping && d.shipping.booking) }
      }
      scope.tabAlert = function (id) { return !!alerts[id] && alerts[id](scope.data || {}) }
      // Opens a tab when its bill, town or coordinates first appear; the player can switch away after.
      var autoOpen = [
        ['garage', function (d) { return !!d.carChange }], ['garage', function (d) { return !!d.partsChange }],
        ['town', function (d) { return !!d.town }], ['route', alerts.route]
      ]
      var follow = function (previous, next) {
        for (var i = 0; i < autoOpen.length; i++) {
          if (autoOpen[i][1](next) && !autoOpen[i][1](previous)) { scope.tab = autoOpen[i][0]; return }
        }
        if (scope.tab === 'town' && !next.town) scope.tab = 'route'
      }
      // The good picked on the Town tab; its drop-offs are listed under it.
      // count is how many slots to buy; null means as many as fit and are affordable.
      scope.picked = { good: null, count: null }
      scope.pickGood = function (id) { scope.picked.good = id; scope.picked.count = null }
      scope.buyCount = function (g) {
        if (!g || !(g.slots >= 1)) return 0
        if (scope.picked.count === null) return g.slots
        return Math.max(1, Math.min(g.slots, scope.picked.count))
      }
      scope.stepCount = function (g, delta) {
        if (!g || !(g.slots >= 1)) return
        scope.picked.count = Math.max(1, Math.min(g.slots, scope.buyCount(g) + delta))
      }
      scope.setCount = function (count) { scope.picked.count = count }
      // The drop-off's price plus its freight pay, less what you pay here, for the chosen count.
      // The delivery distance slider; it starts at Lua's value and sends each change back.
      scope.range = { km: null }
      scope.setRange = function () {
        var km = scope.range.km
        if (scope.data.town && Number.isInteger(km) && km >= 5 && km <= 50) core('setDeliveryRange(' + km + ')')
      }
      scope.profit = function (g, p) { return (p.price + (p.freight || 0) - g.price) * scope.buyCount(g) }
      scope.pickedGood = function (d) {
        var list = (d && d.town && d.town.goods) || []
        for (var i = 0; i < list.length; i++) if (list[i].id === scope.picked.good) return list[i]
        var best = d && d.bestRun && d.bestRun.goodId
        for (var j = 0; j < list.length; j++) if (list[j].id === best) return list[j]
        return list[0] || null
      }
      scope.destinationName = function (d, id) {
        var list = (d && d.town && d.town.destinations) || []
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
      }
      // Dot colours: green stocked and cheap here, red short and pays well, grey otherwise.
      scope.dotColor = function (level) { return level === 'cheap' ? '#6fcf97' : (level === 'short' ? '#eb5757' : '#7d8b88') }
      scope.km = function (metres) { return typeof metres === 'number' && isFinite(metres) ? (metres / 1000).toFixed(1) : '' }
      scope.percent = function (share) { return typeof share === 'number' ? Math.round(share * 100) : '' }
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
        return !!d && (d.unsavedBalance > 0 || d.unsavedSpending > 0 || d.unsavedDistanceKm >= 0.005)
      }
      var plainId = function (id) { return /^[a-z0-9_]+$/.test(String(id)) }
      scope.buyLoad = function (good, destination, count) {
        if (!scope.data.town || !scope.data.town.buyAllowed || !plainId(good) || !plainId(destination)) return
        if (!(Number.isInteger(count) && count >= 1 && count <= 999)) return
        core("buyLoad('" + good + "', '" + destination + "', " + count + ')')
      }
      scope.sellLoad = function () { if (scope.data.town && scope.data.town.sellAllowed) core('sellLoad()') }
      scope.refuel = function () { if (scope.data.town && scope.data.town.refuelAllowed) core('refuel()') }
      scope.dumpLoad = function () { if (scope.data.dumpAllowed) core('dumpLoad()') }
      scope.bookShipping = function (destination) {
        if (scope.data.shipping && !scope.data.shipping.booking && plainId(destination)) core("bookShipping('" + destination + "')")
      }
      scope.cancelShipping = function () { if (scope.data.shipping && scope.data.shipping.booking) core('cancelShipping()') }
      scope.save = function () { if (scope.data.saveAllowed) core('save()') }
      scope.addTestMoney = function () { if (scope.data.testMoneyAllowed) core('addTestMoney()') }
      scope.requestRepairQuote = function () { if (scope.data.repairQuoteAllowed) core('requestRepairQuote()') }
      scope.repairVehicle = function () { if (scope.data.repairAllowed) core('repairVehicle()') }
      scope.buyParts = function () { if (scope.data.buyPartsAllowed) core('buyParts()') }
      scope.revertParts = function () { if (scope.data.revertPartsAllowed) core('revertParts()') }
      scope.buyCar = function () { if (scope.data.buyCarAllowed) core('buyCar()') }
      scope.revertCar = function () { if (scope.data.revertCarAllowed) core('revertCar()') }
      // The first press asks Lua to confirm; the second wipes the save.
      scope.newGame = function () { if (scope.data.newGameAllowed) core('newGame()') }
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
          follow(scope.data || {}, data)
          if (scope.range.km === null && data.town && data.town.range) scope.range.km = data.town.range.km
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
              state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR EARTH FREIGHT', saveAllowed: false,
              sessionStatus: 'Earth Freight is not responding. Check that the mod is enabled, then reload it.'
            }
          })
        }
      }, 3000)
      scope.$on('$destroy', function () {
        disposed = true
        clearInterval(heartbeat)
        mount(false)
      })
    }
  }
}])
