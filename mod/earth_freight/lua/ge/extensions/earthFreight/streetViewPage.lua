-- The Street View window's web page, served by streetView.lua at http://127.0.0.1:47170/.
-- It asks the game where the car is every 10 seconds and points Google Street View there.
-- With no Google key it uses Google's plain embed, which needs no key. With a free Maps JavaScript
-- API key (kept in this browser only) it finds the nearest photo when the car is off the road.
local M = {}

M.html = [==[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Worldwide Trucking Street View</title>
<style>
  :root { --bg: #0c1318; --panel: #13201f; --line: #568d7a; --text: #f2f6f5; --dim: #c9d6d2; --mint: #a7e5c9; --gold: #f2c94c; --red: #eb5757; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text); font: 14px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif; }
  body { display: flex; flex-direction: column; }
  header { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 14px; padding: 8px 14px; background: var(--panel); border-bottom: 1px solid var(--line); }
  .where { flex: 1 1 260px; min-width: 0; }
  .title { font-size: 18px; font-weight: bold; overflow-wrap: anywhere; }
  .sub { color: var(--dim); font-size: 13px; overflow-wrap: anywhere; }
  .street { color: var(--mint); }
  .status { font-size: 13px; color: var(--dim); white-space: nowrap; }
  .dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; background: var(--dim); margin-right: 5px; vertical-align: 1px; }
  .dot.live { background: #6fcf97; } .dot.wait { background: var(--gold); } .dot.down { background: var(--red); }
  .buttons { display: flex; flex-wrap: wrap; gap: 6px; }
  button, .button { font: inherit; font-size: 13px; color: var(--text); background: transparent; border: 1px solid var(--line); border-radius: 4px; padding: 4px 10px; cursor: pointer; text-decoration: none; }
  button:hover, .button:hover { background: rgba(86,141,122,.25); }
  button.on { background: var(--line); color: var(--bg); font-weight: bold; }
  main { position: relative; flex: 1; min-height: 0; }
  #view, #frame, #map { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
  #inset { position: absolute; right: 12px; bottom: 12px; width: 240px; height: 170px; border: 2px solid var(--line); border-radius: 6px; overflow: hidden; display: none; }
  #notice { position: absolute; left: 50%; top: 12px; transform: translateX(-50%); max-width: calc(100% - 24px); padding: 6px 12px; border-radius: 6px; background: rgba(12,19,24,.88); border: 1px solid var(--gold); color: var(--gold); font-weight: bold; display: none; text-align: center; z-index: 5; }
  #cover { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; padding: 24px; text-align: center; color: var(--dim); font-size: 16px; }
  #settings { position: absolute; right: 12px; top: 12px; width: min(420px, calc(100% - 24px)); padding: 14px; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; display: none; z-index: 10; }
  #settings h2 { margin: 0 0 6px; font-size: 16px; color: var(--mint); }
  #settings p { margin: 6px 0; color: var(--dim); font-size: 13px; }
  #settings input { width: 100%; padding: 6px 8px; margin: 4px 0 8px; font: inherit; color: var(--text); background: var(--bg); border: 1px solid var(--line); border-radius: 4px; }
  #settings a { color: var(--mint); }
  #caption { display: none; padding: 3px 8px; font-size: 12px; color: var(--dim); background: var(--panel); border-bottom: 1px solid var(--line); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  #caption b { color: var(--text); }
  #away { flex: 1; display: flex; flex-direction: column; gap: 10px; align-items: center; justify-content: center; padding: 24px; text-align: center; color: var(--dim); font-size: 16px; }
  .zoom { display: inline-flex; align-items: center; gap: 4px; font-size: 13px; color: var(--dim); white-space: nowrap; }
  .zoom button { padding: 4px 9px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<header>
  <div class="where">
    <div class="title" id="title">Worldwide Trucking Street View</div>
    <div class="sub"><span class="street" id="street"></span><span id="area"></span></div>
  </div>
  <div class="status"><span class="dot wait" id="dot"></span><span id="status">Connecting to the game&hellip;</span></div>
  <div class="buttons">
    <span class="zoom" title="Zoom the picture in or out to match your view in the game"><button type="button" id="zoomOut" aria-label="Zoom out">&minus;</button><span id="zoomLabel">Zoom 1</span><button type="button" id="zoomIn" aria-label="Zoom in">+</button></span>
    <button type="button" id="mode" title="Switch between Street View and an overhead map">Map</button>
    <button type="button" id="popout" hidden title="Open Street View in a small window that stays on top of the game">Pop out</button>
    <button type="button" id="pause" title="Stop following the car, so you can look around">Pause</button>
    <a class="button" id="google" href="https://www.google.com/maps" target="_blank" rel="noopener" title="Open this spot in Google Maps in a new tab">Google Maps</a>
    <button type="button" id="gear" title="Google key and how this works">Settings</button>
  </div>
</header>
<div id="away" hidden>Street View is in its own window on top of the game.<button type="button" id="bringBack">Bring it back here</button></div>
<main>
  <div id="caption"></div>
  <div id="cover">Waiting for the game&hellip;</div>
  <iframe id="frame" title="Street View" hidden referrerpolicy="no-referrer-when-downgrade" allowfullscreen></iframe>
  <div id="view" hidden></div>
  <div id="map" hidden></div>
  <div id="inset"></div>
  <div id="notice"></div>
  <div id="settings">
    <h2>Street View settings</h2>
    <p>This page asks the game where your truck is every 10 seconds and shows Google Street View of that spot. Keep BeamNG running with Worldwide Trucking and this tab open.</p>
    <p><b>Optional Google key.</b> Without one the page uses Google's free embed, which shows nothing where there are no photos right on the spot. With a free Google Maps JavaScript API key the page finds the nearest photo within 5 km, faces it the way you are driving and adds a small map. Your key stays in this browser only.</p>
    <p>Get one at <a href="https://console.cloud.google.com/google/maps-apis/credentials" target="_blank" rel="noopener">Google Cloud: Maps credentials</a> and turn on the Maps JavaScript API.</p>
    <label for="key">Google Maps JavaScript API key</label>
    <input id="key" type="text" autocomplete="off" spellcheck="false" placeholder="AIza...">
    <div class="buttons">
      <button type="button" id="saveKey" class="on">Save key</button>
      <button type="button" id="clearKey">Remove key</button>
      <button type="button" id="closeSettings">Close</button>
    </div>
    <p id="keyStatus"></p>
  </div>
</main>
<script>
(function () {
  'use strict'
  var EVERY = 10000          // ms between updates
  var MOVED = 20             // metres the truck must move before the picture changes
  var RADII = [50, 500, 5000] // metres searched for the nearest photo, with a key
  var KEY_STORE = 'wwtStreetViewKey'
  var ZOOM_STORE = 'wwtStreetViewZoom'
  var MAX_ZOOM = 3          // Street View zoom steps: 0 is the widest, each step about twice as close
  // Elements are looked up in the pop-out window too, once Street View has moved there.
  var pip = null
  var $ = function (id) { return document.getElementById(id) || (pip && pip.document.getElementById(id)) }
  var store = {
    get: function (k) { try { return window.localStorage.getItem(k) } catch (e) { return null } },
    set: function (k, v) { try { if (v) window.localStorage.setItem(k, v); else window.localStorage.removeItem(k) } catch (e) {} }
  }
  var state = { paused: false, showMap: false, last: null, shown: null, lastOk: 0, google: null, pano: null, map: null, inset: null, marker: null, insetMarker: null, keyFailed: false }

  var reasons = {
    earth_missing: 'Waiting for BeamNG.Earth to load',
    earth_starting: 'BeamNG.Earth is still loading',
    vehicle_required: 'Waiting for your truck',
    earth_interface_error: 'BeamNG.Earth is not giving a position yet'
  }

  function metres (a, b) {
    var r = 6371000, rad = Math.PI / 180
    var dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)))
  }
  function fixed (n) { return Number(n).toFixed(5) }
  function text (id, value) { $(id).textContent = value || '' }
  function status (kind, message) { $('dot').className = 'dot ' + kind; text('status', message) }
  function notice (message) { var n = $('notice'); n.textContent = message || ''; n.style.display = message ? 'block' : 'none' }
  function cover (message) { var c = $('cover'); c.textContent = message || ''; c.hidden = !message }

  function caption (p) {
    var c = $('caption')
    c.textContent = ''
    var b = document.createElement('b'); b.textContent = p.place || (fixed(p.latitude) + ', ' + fixed(p.longitude))
    c.appendChild(b)
    if (p.street) c.appendChild(document.createTextNode(' \u00b7 ' + p.street))
  }
  function showHeader (p) {
    caption(p)
    text('title', p.place || (fixed(p.latitude) + ', ' + fixed(p.longitude)))
    text('street', p.street ? p.street : '')
    var area = [p.region, p.country].filter(Boolean).join(', ')
    var coords = fixed(p.latitude) + ', ' + fixed(p.longitude)
    text('area', (p.street ? ' · ' : '') + (area ? area + ' · ' : '') + coords)
    $('google').href = 'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=' + p.latitude + ',' + p.longitude +
      (p.heading != null ? '&heading=' + Math.round(p.heading) : '')
  }

  // ---- Without a key: Google's plain embeds ----
  function frameUrl (p) {
    if (state.showMap) return 'https://maps.google.com/maps?q=' + p.latitude + ',' + p.longitude + '&t=k&z=17&output=embed'
    return 'https://maps.google.com/maps?layer=c&cbll=' + p.latitude + ',' + p.longitude +
      '&cbp=12,' + Math.round(p.heading || 0) + ',,' + state.zoom + ',0&source=embed&output=svembed'
  }
  function showFrame (p) {
    $('view').hidden = true; $('map').hidden = true; $('inset').style.display = 'none'
    var f = $('frame'); f.hidden = false
    f.src = frameUrl(p)
    notice('')
  }

  // ---- With a key: the Maps JavaScript API ----
  function loadGoogle (key) {
    return new Promise(function (resolve, reject) {
      window.gm_authFailure = function () { state.keyFailed = true; reject(new Error('key')) }
      window.wwtMapsReady = function () { resolve(window.google) }
      var s = document.createElement('script')
      s.src = 'https://maps.googleapis.com/maps/api/js?key=' + encodeURIComponent(key) + '&v=weekly&callback=wwtMapsReady'
      s.async = true
      s.onerror = function () { reject(new Error('load')) }
      document.head.appendChild(s)
    })
  }
  function nearestPano (g, p) {
    var service = new g.maps.StreetViewService()
    var at = { lat: p.latitude, lng: p.longitude }
    var tryRadius = function (i) {
      if (i >= RADII.length) return Promise.resolve(null)
      return service.getPanorama({ location: at, radius: RADII[i], preference: g.maps.StreetViewPreference.NEAREST, source: g.maps.StreetViewSource.OUTDOOR })
        .then(function (r) { return r && r.data && r.data.location ? r.data.location : tryRadius(i + 1) })
        .catch(function () { return tryRadius(i + 1) })
    }
    return tryRadius(0)
  }
  function ensureGoogleViews (g) {
    if (state.pano) return
    state.pano = new g.maps.StreetViewPanorama($('view'), { addressControl: false, motionTracking: false, fullscreenControl: true, showRoadLabels: true })
    state.map = new g.maps.Map($('map'), { zoom: 16, mapTypeId: 'hybrid', streetViewControl: false })
    state.inset = new g.maps.Map($('inset'), { zoom: 14, disableDefaultUI: true, gestureHandling: 'none', mapTypeId: 'roadmap' })
    state.marker = new g.maps.Marker({ map: state.map, title: 'Your truck' })
    state.insetMarker = new g.maps.Marker({ map: state.inset, title: 'Your truck' })
  }
  function showGoogle (g, p) {
    ensureGoogleViews(g)
    $('frame').hidden = true
    var at = { lat: p.latitude, lng: p.longitude }
    state.map.setCenter(at); state.marker.setPosition(at)
    state.inset.setCenter(at); state.insetMarker.setPosition(at)
    if (state.showMap) {
      $('view').hidden = true; $('map').hidden = false; $('inset').style.display = 'none'; notice('')
      return Promise.resolve()
    }
    return nearestPano(g, p).then(function (found) {
      if (!found) {
        $('view').hidden = true; $('map').hidden = false; $('inset').style.display = 'none'
        notice('No Street View within 5 km of your truck. Showing the map instead.')
        return
      }
      $('map').hidden = true; $('view').hidden = false; $('inset').style.display = 'block'
      state.pano.setPano(found.pano)
      state.pano.setPov({ heading: p.heading != null ? p.heading : 0, pitch: 0 })
      state.pano.setZoom(state.zoom)
      state.pano.setVisible(true)
      var away = found.latLng ? metres(p, { latitude: found.latLng.lat(), longitude: found.latLng.lng() }) : 0
      notice(away > 60 ? 'Nearest Street View is ' + (away >= 1000 ? (away / 1000).toFixed(1) + ' km' : Math.round(away) + ' m') + ' from your truck.' : '')
    })
  }

  function show (p) {
    cover('')
    showHeader(p)
    state.shown = p
    if (state.google) return showGoogle(state.google, p).catch(function () { showFrame(p) })
    showFrame(p)
    return Promise.resolve()
  }

  function update () {
    if (state.paused) return
    fetch('/position', { cache: 'no-store' }).then(function (r) { return r.json() }).then(function (p) {
      state.lastOk = Date.now()
      if (!p || !p.ok) {
        status('wait', reasons[p && p.reason] || 'Waiting for the game')
        if (!state.shown) cover((reasons[p && p.reason] || 'Waiting for the game') + '…')
        return
      }
      status('live', 'Live, every 10 s')
      state.last = p
      if (!state.shown || metres(state.shown, p) >= MOVED) show(p)
    }).catch(function () {
      status('down', 'Can’t reach the game. Is BeamNG running?')
      if (!state.shown) cover('Can’t reach the game. Start BeamNG with Worldwide Trucking, then press Street View on its HUD.')
    })
  }

  function refresh () { if (state.last) show(state.last) }

  // Zoom: one step in by default, which matches the game's view better in a small window. Kept
  // in this browser, and used for every picture after.
  function showZoom () { text('zoomLabel', 'Zoom ' + state.zoom) }
  function setZoom (z) {
    state.zoom = Math.max(0, Math.min(MAX_ZOOM, z))
    store.set(ZOOM_STORE, String(state.zoom))
    showZoom()
    if (state.pano && !$('view').hidden) state.pano.setZoom(state.zoom)
    else refresh()
  }
  $('zoomIn').onclick = function () { setZoom(state.zoom + 1) }
  $('zoomOut').onclick = function () { setZoom(state.zoom - 1) }

  $('pause').onclick = function () {
    state.paused = !state.paused
    $('pause').textContent = state.paused ? 'Follow truck' : 'Pause'
    $('pause').className = state.paused ? 'on' : ''
    if (state.paused) status('wait', 'Paused. Look around as you like.')
    else update()
  }
  $('mode').onclick = function () {
    state.showMap = !state.showMap
    $('mode').textContent = state.showMap ? 'Street View' : 'Map'
    refresh()
  }
  // Pop out: Chrome and Edge can open a small window that stays on top of other windows (the
  // Document Picture-in-Picture API). Street View moves into it and comes back when it closes.
  var main = document.querySelector('main')
  // Street View back in this tab: moved first, so it is found here again.
  function dock () {
    document.body.appendChild(main)
    pip = null
    $('caption').style.display = ''
    $('away').hidden = true
    $('popout').className = ''
    refresh()
  }
  function bringBack () {
    if (!pip) return
    var w = pip
    dock()
    try { w.close() } catch (e) {}
  }
  if ('documentPictureInPicture' in window) {
    $('popout').hidden = false
    $('popout').onclick = function () {
      if (pip) { bringBack(); return }
      window.documentPictureInPicture.requestWindow({ width: 520, height: 340 }).then(function (w) {
        pip = w
        document.querySelectorAll('style').forEach(function (st) { w.document.head.appendChild(st.cloneNode(true)) })
        w.document.title = 'Street View'
        w.document.body.appendChild(main)
        $('caption').style.display = 'block'
        $('away').hidden = false
        $('popout').className = 'on'
        w.addEventListener('pagehide', function () {
          if (pip === w) dock()
        })
        refresh()
      }).catch(function () {
        notice('Your browser would not open a pop-out window. Try Chrome or Edge.')
      })
    }
  }
  $('bringBack').onclick = bringBack
  $('gear').onclick = function () { var s = $('settings'); s.style.display = s.style.display === 'block' ? 'none' : 'block' }
  $('closeSettings').onclick = function () { $('settings').style.display = 'none' }
  $('saveKey').onclick = function () {
    var k = $('key').value.trim()
    store.set(KEY_STORE, k)
    location.reload()
  }
  $('clearKey').onclick = function () { store.set(KEY_STORE, ''); location.reload() }

  var savedZoom = parseInt(store.get(ZOOM_STORE), 10)
  state.zoom = isFinite(savedZoom) ? Math.max(0, Math.min(MAX_ZOOM, savedZoom)) : 1
  showZoom()

  var key = store.get(KEY_STORE)
  $('key').value = key || ''
  if (key) {
    text('keyStatus', 'Loading Google Maps with your key…')
    loadGoogle(key).then(function (g) {
      state.google = g
      text('keyStatus', 'Your key works: nearest-photo search is on.')
      refresh()
    }).catch(function () {
      state.google = null
      text('keyStatus', 'Google did not accept that key, so the page is using the plain embed. Check the key has the Maps JavaScript API turned on.')
      notice('Your Google key did not work. Using the plain Street View embed.')
      refresh()
    })
  } else {
    text('keyStatus', 'No key saved: using the plain Street View embed.')
  }

  update()
  setInterval(update, EVERY)
  // A fresh header line while waiting.
  setInterval(function () {
    if (!state.paused && state.lastOk && Date.now() - state.lastOk > EVERY * 3) status('down', 'Can’t reach the game. Is BeamNG running?')
  }, 2000)
})()
</script>
</body>
</html>
]==]

return M
