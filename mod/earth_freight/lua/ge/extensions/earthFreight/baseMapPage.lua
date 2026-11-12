-- The Base map window's web page, served by streetView.lua at http://127.0.0.1:47170/bases.
-- An overhead map (OpenStreetMap, through Leaflet) of every base's circle of influence, shaded by whose
-- turf each spot is (the same rule as magnate.lua), with the truck and the current job's two ends.
-- It asks the game for /basemap every few seconds. Names come from other players, so they are only
-- ever put on the page as text, never as HTML.
local M = {}

M.html = [==[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Worldwide Trucking Base map</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="">
<style>
  :root { --bg: #0c1318; --panel: #13201f; --line: #568d7a; --text: #f2f6f5; --dim: #c9d6d2; --mint: #a7e5c9; --gold: #f2c94c; --red: #eb5757; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text); font: 14px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif; }
  body { display: flex; flex-direction: column; }
  header { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 14px; padding: 8px 14px; background: var(--panel); border-bottom: 1px solid var(--line); }
  .where { flex: 1 1 260px; min-width: 0; }
  .title { font-size: 18px; font-weight: bold; overflow-wrap: anywhere; }
  .sub { color: var(--dim); font-size: 13px; overflow-wrap: anywhere; }
  .live { display: flex; align-items: center; gap: 6px; color: var(--dim); font-size: 13px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: #7d8b88; flex: none; }
  .dot.live { background: #6fcf97; } .dot.down { background: var(--red); }
  button { font: inherit; font-size: 13px; color: var(--text); background: transparent; border: 1px solid var(--line); border-radius: 4px; padding: 4px 10px; cursor: pointer; }
  button.on { background: var(--mint); color: var(--bg); border-color: var(--mint); font-weight: bold; }
  #map { flex: 1; min-height: 200px; }
  footer { padding: 8px 14px; background: var(--panel); border-top: 1px solid var(--line); font-size: 13px; color: var(--dim); }
  footer div + div { margin-top: 2px; }
  footer b { color: var(--text); }
  .leaflet-container { font: inherit; background: #1b2226; }
  .leaflet-tile-pane { filter: invert(1) hue-rotate(180deg) brightness(0.9) contrast(0.85); }
  .leaflet-tooltip.tag { background: var(--panel); color: var(--text); border: 1.5px solid var(--line); border-radius: 6px; padding: 2px 8px; font-weight: bold; box-shadow: 0 2px 8px rgba(0,0,0,.4); }
  .leaflet-tooltip.tag::before { display: none; }
</style>
</head>
<body>
<header>
  <div class="where">
    <div class="title" id="turf">Base map</div>
    <div class="sub" id="sub">Waiting for the game&hellip;</div>
  </div>
  <div class="live"><span class="dot" id="dot"></span><span id="status">Connecting</span></div>
  <button type="button" id="follow" class="on" aria-pressed="true" title="Keep your truck in the middle of the map">Follow truck</button>
  <button type="button" id="popout" title="Open the map in its own small window, handy on a second screen">Pop out</button>
</header>
<div id="map" role="region" aria-label="Map of bases and their turf"></div>
<footer>
  <div id="job"></div>
  <div id="land"></div>
  <div>Each circle is a trucker's base. Where circles overlap, the bigger one pushes the border towards the smaller one, and every base keeps the 100 km around its town. Jobs in your own turf pay you up to +20%, or up to +10% in your corp's turf. Deliver in anyone else's turf and 20% of the pay goes to them as a turf toll, unless you are in their corp.</div>
</footer>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
<script>
(function () {
  'use strict'
  var EVERY = 3000           // ms between asking the game
  var MINE = '#a7e5c9'
  var COLOURS = ['#56ccf2', '#f2994a', '#bb6bd9', '#eb5757', '#9b8cff', '#27ae60', '#f78fb3', '#2d9cdb']
  var $ = function (id) { return document.getElementById(id) }
  var state = { follow: true, fitted: false, circlesKey: null, circles: [], coreKm: 100, lastOk: 0, layers: [], truck: null, pins: [] }

  var reasons = {
    earth_missing: 'Waiting for BeamNG.Earth to load',
    earth_starting: 'BeamNG.Earth is still loading',
    vehicle_required: 'Waiting for your truck',
    earth_interface_error: 'BeamNG.Earth is not giving a position yet'
  }

  function km (a, b) {
    var r = 6371, rad = Math.PI / 180
    var dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)))
  }
  // The same rule as the game: a base's own 5 km core first, else the circle with the smallest distance / radius.
  function turf (point) {
    var best = null, bestScore = null
    for (var i = 0; i < state.circles.length; i++) {
      var c = state.circles[i], d = km(c, point)
      if (d <= state.coreKm) return c
      if (d <= c.radiusKm) {
        var score = d / c.radiusKm
        if (bestScore === null || score < bestScore) { best = c; bestScore = score }
      }
    }
    return best
  }
  function colour (c) {
    if (c.mine) return MINE
    var name = String(c.owner || c.town || ''), h = 0
    for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
    return COLOURS[h % COLOURS.length]
  }
  function whose (t) {
    if (!t) return 'nobody’s turf'
    var where = t.town ? ' around ' + t.town : ''
    if (t.mine) return 'your turf' + where + ', up to +' + t.percent + '%'
    if (t.corp) return 'your corp’s turf' + where + ', up to +' + t.percent + '%'
    return (t.owner || 'another trucker') + '’s turf' + where + ', ' + t.toll + '% toll'
  }
  function label (text) { var s = document.createElement('span'); s.textContent = text; return s }
  function status (kind, message) { $('dot').className = 'dot ' + kind; $('status').textContent = message }

  var map = L.map('map', { worldCopyJump: true, zoomControl: true }).setView([-33.75, 150.7], 9)
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  }).addTo(map)
  map.on('dragstart', function () { setFollow(false) })

  // Turf shading: every 4 px square of the map is coloured by whose turf its middle is, so the borders
  // between overlapping circles show where they really are.
  var Shade = L.GridLayer.extend({
    createTile: function (coords) {
      var tile = document.createElement('canvas'), size = this.getTileSize(), step = 4
      tile.width = size.x; tile.height = size.y
      if (!state.circles.length) return tile
      var g = tile.getContext('2d'), origin = coords.scaleBy(size)
      g.globalAlpha = 0.22
      for (var y = 0; y < size.y; y += step) {
        for (var x = 0; x < size.x; x += step) {
          var ll = map.unproject(origin.add([x + step / 2, y + step / 2]), coords.z)
          var c = turf({ latitude: ll.lat, longitude: ll.lng })
          if (c) { g.fillStyle = colour(c); g.fillRect(x, y, step, step) }
        }
      }
      return tile
    }
  })
  var shade = new Shade({ opacity: 1, zIndex: 2 }).addTo(map)

  function drawCircles (list) {
    state.layers.forEach(function (l) { map.removeLayer(l) })
    state.layers = []
    list.forEach(function (c) {
      var col = colour(c), at = [c.latitude, c.longitude]
      // A full-size circle has a thick edge: its corp can open another base outside it.
      state.layers.push(L.circle(at, { radius: c.radiusKm * 1000, color: col, weight: c.full ? 4 : 2, fill: false, dashArray: c.mine ? null : '6 6', interactive: false }).addTo(map))
      state.layers.push(L.circle(at, { radius: state.coreKm * 1000, color: col, weight: 1, fill: false, opacity: 0.6, interactive: false }).addTo(map))
      var m = L.circleMarker(at, { radius: 5, color: col, weight: 2, fillColor: col, fillOpacity: 1 }).addTo(map)
      m.bindTooltip(label((c.mine ? 'Your base' : c.corp ? 'Your corp' : (c.owner || 'A trucker')) + ' · ' + (c.town || '') + ' · ' + c.radiusKm + ' km' + (c.full ? ', full size' : '')),
        { permanent: true, direction: 'top', offset: [0, -6], className: 'tag' })
      state.layers.push(m)
    })
    shade.redraw()
  }

  function drawPins (job) {
    state.pins.forEach(function (l) { map.removeLayer(l) })
    state.pins = []
    var lines = []
    if (job) {
      [['Pickup', job.pickup], ['Drop-off', job.dropoff]].forEach(function (pair) {
        var p = pair[1]
        if (!p) return
        var m = L.circleMarker([p.latitude, p.longitude], { radius: 7, color: '#0c1318', weight: 2, fillColor: '#f2c94c', fillOpacity: 1 }).addTo(map)
        m.bindTooltip(label(pair[0] + (p.name ? ': ' + p.name : '')), { direction: 'top', offset: [0, -8], className: 'tag' })
        state.pins.push(m)
        var t = p.turf
        lines.push(pair[0] + (p.name ? ' (' + p.name + ')' : '') + ': ' +
          (!t ? 'nobody’s turf' : whose(t) + (t.counts ? '' : ', which doesn’t count here')))
      })
    }
    var el = $('job'); el.textContent = ''
    if (lines.length) {
      var b = document.createElement('b'); b.textContent = 'Your job. '; el.appendChild(b)
      el.appendChild(document.createTextNode(lines.join('. ') + '.'))
    }
  }

  // Follow truck pans only once the truck is within 30 px of the map's edge, so a view fitted to a far-off circle stays.
  function nearEdge (at) {
    var p = map.latLngToContainerPoint(at), size = map.getSize()
    return p.x < 30 || p.y < 30 || p.x > size.x - 30 || p.y > size.y - 30
  }

  function setFollow (on) {
    state.follow = on
    $('follow').className = on ? 'on' : ''
    $('follow').setAttribute('aria-pressed', on ? 'true' : 'false')
    if (on && state.truck) map.panTo(state.truck.getLatLng())
  }
  $('follow').onclick = function () { setFollow(!state.follow) }
  $('popout').onclick = function () {
    var w = window.open(location.href, 'wwtBaseMap', 'popup,width=560,height=560')
    if (w) w.focus()
  }

  function show (d) {
    state.coreKm = d.coreKm || 100
    var circles = Array.isArray(d.circles) ? d.circles : []
    var key = JSON.stringify(circles)
    if (key !== state.circlesKey) { state.circlesKey = key; state.circles = circles; drawCircles(circles) }
    drawPins(d.job)
    if (d.truck) {
      var at = [d.truck.latitude, d.truck.longitude]
      if (!state.truck) {
        state.truck = L.circleMarker(at, { radius: 8, color: '#0c1318', weight: 3, fillColor: '#ffffff', fillOpacity: 1, zIndexOffset: 1000 }).addTo(map)
        state.truck.bindTooltip(label('Your truck'), { direction: 'bottom', offset: [0, 8], className: 'tag' })
      } else state.truck.setLatLng(at)
      // The first view: your own circle, else the nearest base's whole circle, with the truck in view. Done again
      // once when the bases first arrive, so a page opened before the server sent them doesn't stay zoomed in.
      if (!state.fitted || (!state.fittedCircles && circles.length)) {
        state.fitted = true
        state.fittedCircles = circles.length > 0
        var own = circles.filter(function (c) { return c.mine || c.corp })[0]
        var near = null, nearKm = Infinity
        circles.forEach(function (c) {
          var edge = map.distance(at, [c.latitude, c.longitude]) / 1000 - c.radiusKm
          if (edge < nearKm) { near = c; nearKm = edge }
        })
        if (own) map.fitBounds(L.latLng(at).toBounds(Math.max(own.radiusKm, 5) * 2000).extend([own.latitude, own.longitude]))
        else if (near) map.fitBounds(L.latLng(at).toBounds(20000).extend(L.latLng(near.latitude, near.longitude).toBounds(near.radiusKm * 2000)), { padding: [60, 60] })
        else map.setView(at, 10)
      } else if (state.follow && nearEdge(at)) map.panTo(at, { animate: true })
      var t = d.turf
      $('turf').textContent = t ? (t.mine ? 'In your turf' : t.corp ? 'In your corp’s turf' : 'In ' + (t.owner || 'another trucker') + '’s turf') : 'Outside every turf'
      $('sub').textContent = !t ? (circles.length ? 'No base bonus and no toll here.' : 'No bases yet. Buy one on the Base tab in the game.')
        : t.mine ? 'Around ' + (t.town || 'your base') + '. Jobs that start and end here pay you up to +' + t.percent + '%.'
        : t.corp ? 'Around ' + (t.town || 'their base') + ', ' + (t.owner || 'the owner') + '’s base. Jobs that start and end here pay you up to +' + t.percent + '%, and you pay no toll.'
        : 'Around ' + (t.town || 'their base') + '. Deliveries here pay ' + t.toll + '% of their pay to ' + (t.owner || 'them') + '.'
    } else {
      $('turf').textContent = 'Base map'
    }
    var l = d.land
    $('land').textContent = !l ? '' : 'Land race: ' + (l.percent != null ? l.who + ' ' + l.percent.toFixed(1) + '% of Earth’s land. ' : '')
      + (l.leader ? l.leader + ' leads with ' + (l.leaderLand || 0).toFixed(1) + '%. ' : '') + 'The first to ' + l.win + '% wins the season'
      + (l.daysLeft ? ', or whoever holds the most in ' + l.daysLeft + (l.daysLeft === 1 ? ' day.' : ' days.') : '.')
    if (!d.truck) {
      $('sub').textContent = reasons[d.waiting] || 'Waiting for your truck'
    }
  }

  var busy = false
  function update () {
    if (busy) return
    busy = true
    fetch('/basemap', { cache: 'no-store' }).then(function (r) { return r.json() }).then(function (d) {
      busy = false
      if (!d || d.ok === false) { status('down', 'The game could not answer'); return }
      state.lastOk = Date.now()
      status('live', 'Live')
      show(d)
    }).catch(function () {
      busy = false
      status('down', 'Can’t reach the game. Is BeamNG running?')
    })
  }
  update()
  setInterval(update, EVERY)
})()
</script>
</body>
</html>
]==]

return M
