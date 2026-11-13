-- The Radio window's web page, served by streetView.lua at http://127.0.0.1:47170/radio.
-- Live radio stations near the truck, from Radio Browser (www.radio-browser.info), a free and open list
-- of internet radio stations with where each one is. It runs in the player's own web browser because the
-- game's built-in browser refuses to fetch from the web. It asks the game for /position every few seconds,
-- passing the station playing so the HUD can show it, and looks for new stations after a long drive.
-- Favourites sit above the nearby list and play wherever the truck is: the mod's featured stations,
-- found on Radio Browser by name, and the player's own, added by stream address and kept in the browser.
-- Station names come from the web, so they are only ever put on the page as text, never as HTML.
local M = {}

M.html = [==[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Worldwide Trucking Radio</title>
<style>
  :root { --bg: #0c1318; --panel: #13201f; --line: #568d7a; --text: #f2f6f5; --dim: #c9d6d2; --faint: #7d8b88; --mint: #a7e5c9; --green: #6fcf97; --gold: #f2c94c; --red: #eb5757; }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 640px; margin: 0 auto; padding: 16px; }
  header { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 12px; padding-bottom: 10px; border-bottom: 1px solid var(--line); }
  .where { flex: 1 1 240px; min-width: 0; }
  .brand { font-size: 11px; font-weight: bold; letter-spacing: 3px; color: var(--faint); }
  .title { font-size: 20px; font-weight: bold; overflow-wrap: anywhere; }
  .sub { color: var(--dim); font-size: 13px; overflow-wrap: anywhere; }
  .live { display: flex; align-items: center; gap: 6px; color: var(--dim); font-size: 13px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--faint); flex: none; }
  .dot.live { background: var(--green); } .dot.down { background: var(--red); }
  .card { margin-top: 14px; padding: 14px; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; }
  .row { display: flex; align-items: baseline; gap: 8px; }
  .label { flex: 1; font-weight: bold; color: var(--mint); }
  .air { font-size: 13px; font-weight: bold; color: var(--faint); }
  .air.on { color: var(--green); } .air.tuning { color: var(--gold); }
  .now { margin-top: 6px; font-size: 22px; font-weight: bold; overflow-wrap: anywhere; }
  .nowsub { color: var(--dim); font-size: 13px; }
  .buttons { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
  button { font: inherit; font-size: 14px; color: var(--text); background: transparent; border: 1px solid var(--line); border-radius: 5px; padding: 7px 14px; cursor: pointer; }
  button.main { background: var(--mint); color: var(--bg); border-color: var(--mint); font-weight: bold; }
  button:disabled { opacity: .5; cursor: default; }
  label.line { display: flex; align-items: center; gap: 10px; margin-top: 10px; font-size: 14px; }
  input[type=range] { flex: 1; min-width: 0; accent-color: var(--mint); }
  input[type=checkbox] { accent-color: var(--mint); width: 16px; height: 16px; }
  .note { margin-top: 10px; font-size: 14px; color: var(--gold); }
  .note.bad { color: var(--red); }
  .note:empty { display: none; }
  h2 { margin: 18px 0 4px; font-size: 15px; color: var(--mint); display: flex; gap: 8px; align-items: baseline; }
  h2 span { flex: 1; } h2 small { color: var(--dim); font-weight: normal; font-size: 13px; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { display: flex; align-items: center; gap: 10px; padding: 6px 0; border-bottom: 1px solid rgba(86,141,122,.3); }
  li .name { flex: 1; min-width: 0; overflow-wrap: anywhere; }
  li .place { color: var(--faint); font-size: 12px; }
  li.playing .name b { color: var(--green); }
  li .km { flex: none; color: var(--dim); font-size: 13px; }
  li button { flex: none; padding: 3px 10px; font-size: 13px; }
  footer { margin-top: 16px; font-size: 12px; color: var(--faint); }
  footer a { color: var(--mint); }
  details { margin-top: 10px; font-size: 14px; }
  summary { cursor: pointer; color: var(--mint); }
  .add { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
  .add input { flex: 1 1 200px; min-width: 0; font: inherit; font-size: 14px; color: var(--text); background: var(--bg); border: 1px solid var(--line); border-radius: 5px; padding: 6px 8px; }
  .hint { margin-top: 6px; color: var(--faint); font-size: 12px; }
  .hint.bad { color: var(--red); }
</style>
</head>
<body>
<main>
<header>
  <div class="where">
    <div class="brand">WORLDWIDE TRUCKING RADIO</div>
    <div class="title" id="place">Waiting for the game&hellip;</div>
    <div class="sub" id="area"></div>
  </div>
  <div class="live"><span class="dot" id="dot"></span><span id="status">Connecting</span></div>
</header>
<section class="card" aria-live="polite">
  <div class="row"><div class="label">Radio</div><div class="air" id="air">Off</div></div>
  <div class="now" id="now">Nothing playing</div>
  <div class="nowsub" id="nowsub">Stations near your truck appear below as soon as the game says where you are.</div>
  <div class="buttons">
    <button type="button" class="main" id="play" disabled>Play nearest</button>
    <button type="button" id="stop" hidden>Stop</button>
    <button type="button" id="next" disabled>Next station</button>
  </div>
  <label class="line">Volume <input type="range" id="volume" min="0" max="1" step="0.05" aria-label="Radio volume"></label>
  <label class="line"><input type="checkbox" id="follow"> Follow my truck: switch to a nearby station when this one is far behind</label>
  <div class="note" id="note" role="status"></div>
</section>
<h2><span>Favourites</span><small>play wherever you drive</small></h2>
<ul id="favs"></ul>
<details id="addbox">
  <summary>Add your own station</summary>
  <div class="add">
    <input id="ownName" type="text" maxlength="60" placeholder="Name, such as Chill FM" aria-label="Station name">
    <input id="ownUrl" type="url" maxlength="500" placeholder="Stream address, starting http:// or https://" aria-label="Stream address">
    <button type="button" id="ownAdd">Add</button>
  </div>
  <div class="hint" id="ownHint">The address of the stream itself, not the station's web page: it often ends in .mp3, .aac, /stream or /listen. Your stations are kept in this browser.</div>
</details>
<h2><span>Stations near you</span><small id="count"></small></h2>
<ul id="list"></ul>
<div class="buttons"><button type="button" id="again">Look again</button></div>
<footer>Stations from <a href="https://www.radio-browser.info" target="_blank" rel="noopener">Radio Browser</a>, a free list of internet radio. Each station streams its own broadcast, so some may be off air or only play in their own country. About 60 MB of internet an hour. Keep this tab open: the music plays in the background while you drive.</footer>
</main>
<audio id="audio" preload="none"></audio>
<script>
(function () {
  'use strict'
  var EVERY = 5000                       // ms between asking the game where the truck is
  var HOSTS = ['de1', 'de2', 'fi1', 'at1', 'nl1', 'all'].map(function (h) { return h + '.api.radio-browser.info' })
  var SERVERS = HOSTS.map(function (h) { return 'https://' + h }).concat(HOSTS.map(function (h) { return 'http://' + h }))
  var RINGS = [50000, 150000, 400000, 1500000], ENOUGH = 5, LIST = 20
  var REFRESH_METRES = 25000, FAR_METRES = 150000, MIN_ASK_MS = 60000, WAIT_MS = 8000
  var STORE = 'earthFreight.radioPage'
  // Stations the mod always offers, looked up on Radio Browser by name; prefer picks among the matches.
  var FEATURED = [{ name: 'Psyndora Chill', find: 'psyndora', prefer: /chill/i }]
  var OWN_MAX = 20
  var $ = function (id) { return document.getElementById(id) }
  var audio = $('audio')
  var saved = {}
  try { saved = JSON.parse(localStorage.getItem(STORE) || '{}') || {} } catch (e) {}
  var st = {
    here: null, stations: [], at: null, asked: 0, looking: false, playing: null, server: null, failed: 0,
    volume: typeof saved.volume === 'number' && saved.volume >= 0 && saved.volume <= 1 ? saved.volume : 0.6,
    follow: saved.follow !== false, featured: [],
    own: (Array.isArray(saved.own) ? saved.own : []).filter(function (o) { return o && typeof o.name === 'string' && goodUrl(o.url) })
      .slice(0, OWN_MAX).map(function (o) { return { name: o.name.slice(0, 60), url: o.url, place: 'Your station', pinned: true, own: true } })
  }
  function goodUrl (u) { return typeof u === 'string' && u.length <= 500 && /^https?:\/\/[^\s"'<>]+$/i.test(u) }
  function save () {
    try {
      localStorage.setItem(STORE, JSON.stringify({ volume: st.volume, follow: st.follow,
        own: st.own.map(function (o) { return { name: o.name, url: o.url } }) }))
    } catch (e) {}
  }

  function metres (a, b) {
    var r = Math.PI / 180, dLat = (b.latitude - a.latitude) * r, dLon = (b.longitude - a.longitude) * r
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a.latitude * r) * Math.cos(b.latitude * r) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)))
  }
  function km (m) { return m < 1000 ? 'here' : Math.round(m / 1000) + ' km' }

  // Radio Browser's answer, as the stations listed: ones with a place and a stream a browser can play
  // (no HLS playlists), one of each name, nearest first.
  function readStations (list, here, within) {
    var seen = {}, out = []
    ;(Array.isArray(list) ? list : []).forEach(function (s) {
      if (!s || typeof s.name !== 'string' || !s.name.trim()) return
      var url = String(s.url_resolved || s.url || '')
      if (!/^https?:\/\//i.test(url) || s.hls === 1 || /\.m3u8(\?|$)/i.test(url)) return
      var lat = parseFloat(s.geo_lat), lon = parseFloat(s.geo_long)
      if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return
      var name = s.name.trim().replace(/\s+/g, ' ').slice(0, 60), key = name.toLowerCase()
      if (seen[key]) return
      var away = metres(here, { latitude: lat, longitude: lon })
      if (within && away > within) return
      seen[key] = true
      out.push({ id: String(s.stationuuid || ''), name: name, url: url,
        place: [s.state, s.country].filter(function (p) { return p && String(p).trim() }).join(', ').slice(0, 60),
        latitude: lat, longitude: lon, distance: away })
    })
    out.sort(function (a, b) { return a.distance - b.distance })
    return out.slice(0, LIST)
  }

  // Any one of Radio Browser's servers answers; the one that did is asked first next time.
  function ask (path) {
    var order = st.server ? [st.server].concat(SERVERS.filter(function (s) { return s !== st.server })) : SERVERS
    var problems = []
    function attempt (i) {
      if (i >= order.length) { var e = new Error('no server answered'); e.problems = problems; return Promise.reject(e) }
      var base = order[i], LATE = {}
      var late = new Promise(function (resolve) { setTimeout(function () { resolve(LATE) }, WAIT_MS) })
      var answer = fetch(base + path).then(function (r) { if (!r.ok) throw new Error('answered ' + r.status); return r.json() })
      return Promise.race([answer, late]).then(function (json) {
        if (json === LATE) throw new Error('no answer in ' + WAIT_MS / 1000 + ' s')
        st.server = base
        return json
      }).catch(function (e) {
        problems.push(base.replace('.api.radio-browser.info', '') + ': ' + String((e && e.message) || e).slice(0, 80))
        return attempt(i + 1)
      })
    }
    return attempt(0)
  }

  // The stations round the truck: a small circle first, wider ones until a few turn up.
  function find () {
    if (!st.here || st.looking) return
    var at = { latitude: st.here.latitude, longitude: st.here.longitude }
    st.looking = true; st.asked = Date.now()
    $('again').disabled = true; $('again').textContent = 'Looking...'
    function ring (i) {
      return ask('/json/stations/search?has_geo_info=true&hidebroken=true&order=clickcount&reverse=true&limit=100' +
        '&geo_lat=' + at.latitude.toFixed(3) + '&geo_long=' + at.longitude.toFixed(3) + '&geo_distance=' + RINGS[i])
        .then(function (list) {
          var found = readStations(list, at, RINGS[i])
          if (found.length >= ENOUGH || i + 1 >= RINGS.length) return found
          return ring(i + 1).then(function (wider) { return wider.length > found.length ? wider : found })
        })
    }
    ring(0).then(function (found) {
      st.stations = found; st.at = at
      if (!found.length) note('No stations found near here. Try again further along.')
      else if ($('note').className === 'note bad') note('')
      followTruck()
    }, function (e) {
      note('Couldn’t reach the radio list. Check your internet connection. ' + ((e && e.problems) || []).join('; '), true)
    }).then(function () {
      st.looking = false
      $('again').disabled = false; $('again').textContent = 'Look again'
      draw()
    })
  }

  function note (text, bad) { $('note').textContent = text || ''; $('note').className = bad ? 'note bad' : 'note' }

  function play (s) {
    if (!s) return
    st.playing = s; st.failed = st.failed || 0
    audio.src = s.url
    audio.volume = st.volume
    setAir('tuning')
    var started = audio.play()
    if (started && started.catch) started.catch(function (e) {
      if (e && e.name === 'NotAllowedError') { note('Press Play to start the radio: the browser waits for a click.'); setAir('off'); st.playing = null; draw() }
    })
    if (s.id && /^[0-9a-f-]{36}$/i.test(s.id)) ask('/json/url/' + s.id).catch(function () {})   // counts the listen, as Radio Browser asks
    try {
      if ('mediaSession' in navigator && typeof MediaMetadata === 'function') {
        navigator.mediaSession.metadata = new MediaMetadata({ title: s.name, artist: s.place || 'Worldwide Trucking Radio' })
      }
    } catch (e) {}
    draw()
  }
  function stop () {
    audio.pause(); audio.removeAttribute('src'); audio.load()
    st.playing = null; st.failed = 0
    setAir('off'); draw()
  }
  function next () {
    var list = st.stations
    if (!list.length) return
    var i = -1
    for (var k = 0; k < list.length; k++) if (st.playing && !st.playing.pinned && list[k].url === st.playing.url) i = k
    play(list[(i + 1) % list.length])
  }
  function setAir (how) {
    $('air').textContent = how === 'on' ? 'On air' : (how === 'tuning' ? 'Tuning in...' : 'Off')
    $('air').className = 'air ' + how
  }
  audio.addEventListener('playing', function () { st.failed = 0; setAir('on') })
  audio.addEventListener('waiting', function () { if (st.playing) setAir('tuning') })
  // A station that won't play: the next one is tried, once round the list at most.
  audio.addEventListener('error', function () {
    if (!st.playing) return
    var bad = st.playing
    if (bad.pinned) { note(bad.name + ' won’t play right now. If it is your own station, check its stream address.', true); stop(); return }
    st.failed++
    if (st.failed < st.stations.length) { note(bad.name + ' won’t play right now, so trying the next station.'); next() }
    else { note('None of the stations near here would play. Try Look again later.', true); stop() }
  })

  // Driven far from the station playing: the nearest one takes over.
  function followTruck () {
    if (!st.follow || !st.playing || st.playing.pinned || !st.here || !st.stations.length) return
    if (metres(st.here, st.playing) <= FAR_METRES) return
    var nearest = st.stations[0]
    if (nearest.url === st.playing.url) return
    play(nearest)
    note('Out of range of the last station. Tuned in to ' + nearest.name + (nearest.place ? ', ' + nearest.place : '') + '.')
  }

  function draw () {
    var p = st.playing
    $('now').textContent = p ? p.name : 'Nothing playing'
    $('nowsub').textContent = p ? [p.place, st.here && !p.pinned ? km(metres(st.here, p)) + ' from your truck' : ''].filter(Boolean).join(' · ')
      : (st.stations.length ? 'Press Play nearest, or pick a station below.' : (st.looking ? 'Looking for stations near your truck...' : 'Stations near your truck appear below as soon as the game says where you are.'))
    document.title = p ? '♪ ' + p.name + ' · Worldwide Trucking Radio' : 'Worldwide Trucking Radio'
    $('play').hidden = !!p; $('play').disabled = !st.stations.length
    $('stop').hidden = !p
    $('next').disabled = st.stations.length < 2
    $('count').textContent = st.stations.length ? st.stations.length + ' stations' : ''
    fill($('favs'), st.featured.concat(st.own))
    fill($('list'), st.stations)
  }
  function fill (list, stations) {
    var p = st.playing
    while (list.firstChild) list.removeChild(list.firstChild)
    stations.forEach(function (s) {
      var on = !!(p && p.url === s.url)
      var li = document.createElement('li'); if (on) li.className = 'playing'
      var name = document.createElement('div'); name.className = 'name'
      var b = document.createElement('b'); b.textContent = s.name; name.appendChild(b)
      if (s.place) { var pl = document.createElement('div'); pl.className = 'place'; pl.textContent = s.place; name.appendChild(pl) }
      li.appendChild(name)
      if (!s.pinned) { var d = document.createElement('div'); d.className = 'km'; d.textContent = st.here ? km(metres(st.here, s)) : km(s.distance); li.appendChild(d) }
      var btn = document.createElement('button'); btn.type = 'button'; btn.textContent = on ? 'Stop' : 'Play'
      btn.addEventListener('click', function () { if (on) stop(); else { st.failed = 0; note(''); play(s) } })
      li.appendChild(btn)
      if (s.own) {
        var rm = document.createElement('button'); rm.type = 'button'; rm.textContent = 'Remove'; rm.title = 'Remove ' + s.name
        rm.addEventListener('click', function () {
          if (on) stop()
          st.own = st.own.filter(function (o) { return o !== s }); save(); draw()
        })
        li.appendChild(rm)
      }
      list.appendChild(li)
    })
  }

  // The featured stations, found on Radio Browser by name once the page opens. One that isn't there is left out.
  function loadFeatured () {
    FEATURED.forEach(function (f) {
      ask('/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=20&name=' + encodeURIComponent(f.find)).then(function (list) {
        var good = (Array.isArray(list) ? list : []).filter(function (s) {
          var url = s && String(s.url_resolved || s.url || '')
          return s && typeof s.name === 'string' && goodUrl(url) && s.hls !== 1 && !/\.m3u8(\?|$)/i.test(url)
        })
        var pick = good.filter(function (s) { return f.prefer && f.prefer.test(s.name) })[0] || good[0]
        if (!pick) return
        st.featured.push({ id: String(pick.stationuuid || ''), name: f.name, url: String(pick.url_resolved || pick.url), place: 'Featured station', pinned: true })
        draw()
      }).catch(function () {})
    })
  }
  function addOwn () {
    var name = $('ownName').value.trim().replace(/\s+/g, ' ').slice(0, 60), url = $('ownUrl').value.trim()
    var hint = $('ownHint')
    if (!goodUrl(url)) { hint.textContent = 'That address needs to start with http:// or https://, with no spaces.'; hint.className = 'hint bad'; return }
    if (st.own.length >= OWN_MAX) { hint.textContent = 'You can keep up to ' + OWN_MAX + ' stations. Remove one first.'; hint.className = 'hint bad'; return }
    if (st.own.some(function (o) { return o.url === url })) { hint.textContent = 'That station is already in your favourites.'; hint.className = 'hint bad'; return }
    var s = { name: name || 'My station', url: url, place: 'Your station', pinned: true, own: true }
    st.own.push(s); save()
    $('ownName').value = ''; $('ownUrl').value = ''
    hint.textContent = 'Added. It is playing now; if nothing plays, check it is the stream address, not the web page.'; hint.className = 'hint'
    st.failed = 0; note(''); play(s)
  }

  function status (cls, text) { $('dot').className = 'dot ' + cls; $('status').textContent = text }
  var reasons = { earth_starting: 'BeamNG.Earth is still loading', no_vehicle: 'No truck yet' }
  var busy = false
  function update () {
    if (busy) return
    busy = true
    // Tells the game what is playing, so the HUD's Radio tab can show it.
    fetch('/position?radio=' + encodeURIComponent(st.playing ? st.playing.name : ''), { cache: 'no-store' })
      .then(function (r) { return r.json() }).then(function (p) {
        busy = false
        status('live', 'Live')
        if (!p || !p.ok) { $('place').textContent = reasons[p && p.reason] || 'Waiting for your truck'; return }
        st.here = { latitude: p.latitude, longitude: p.longitude }
        $('place').textContent = p.place || 'On the road'
        $('area').textContent = [p.street, p.region, p.country].filter(Boolean).join(' · ')
        var moved = !st.at || metres(st.here, st.at) > REFRESH_METRES
        if (!st.looking && (!st.stations.length || moved) && Date.now() - st.asked > (st.stations.length ? MIN_ASK_MS : 15000)) find()
        else draw()
      }).catch(function () {
        busy = false
        status('down', 'Can’t reach the game. Is BeamNG running?')
      })
  }

  $('volume').value = st.volume
  $('volume').addEventListener('input', function () { st.volume = Math.max(0, Math.min(1, Number(this.value) || 0)); audio.volume = st.volume; save() })
  $('follow').checked = st.follow
  $('follow').addEventListener('change', function () { st.follow = this.checked; save(); followTruck() })
  $('play').addEventListener('click', function () { st.failed = 0; note(''); play(st.stations[0]) })
  $('stop').addEventListener('click', stop)
  $('next').addEventListener('click', function () { st.failed = 0; note(''); next() })
  $('again').addEventListener('click', function () { st.asked = 0; find() })
  $('ownAdd').addEventListener('click', addOwn)
  $('ownUrl').addEventListener('keydown', function (e) { if (e.key === 'Enter') addOwn() })
  draw()
  loadFeatured()
  update()
  setInterval(update, EVERY)
})()
</script>
</body>
</html>
]==]

return M
