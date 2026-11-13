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
  :root { --dash: #121212; --face: #0b0b0b; --text: #ece6d6; --dim: #b8b1a0; --faint: #7a7468; --cream: #efe7cf; --amber: #ffb347; --red: #e8473c; --green: #7bdc8f; --chrome1: #f4f4f4; --chrome2: #9a9a9a; --chrome3: #4a4a4a; }
  * { box-sizing: border-box; }
  html, body { margin: 0; color: var(--text); font: 15px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
  body { min-height: 100vh; background: radial-gradient(ellipse at 50% 0%, #2a2724 0%, #161514 55%, #0d0d0c 100%); }
  main { max-width: 760px; margin: 0 auto; padding: 18px 16px 24px; }
  header { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 12px; padding-bottom: 12px; }
  .where { flex: 1 1 240px; min-width: 0; }
  .brand { font-size: 11px; font-weight: bold; letter-spacing: 4px; color: var(--faint); }
  .title { font-size: 20px; font-weight: bold; overflow-wrap: anywhere; }
  .sub { color: var(--dim); font-size: 13px; overflow-wrap: anywhere; }
  .live { display: flex; align-items: center; gap: 6px; color: var(--dim); font-size: 13px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--faint); flex: none; }
  .dot.live { background: var(--green); box-shadow: 0 0 6px var(--green); } .dot.down { background: var(--red); }

  /* The radio itself: a chrome bezel round a black face, two knobs and a lit dial between them. */
  .unit { padding: 7px; border-radius: 14px; background: linear-gradient(180deg, var(--chrome1) 0%, #c9c9c9 30%, var(--chrome2) 52%, #dcdcdc 75%, var(--chrome3) 100%);
    box-shadow: 0 14px 30px rgba(0,0,0,.65), 0 2px 0 rgba(255,255,255,.15) inset; }
  .face { display: flex; align-items: center; gap: 14px; padding: 16px 18px; border-radius: 9px;
    background: linear-gradient(180deg, #1d1d1d 0%, var(--face) 45%, #050505 100%); box-shadow: 0 0 0 1px #000 inset, 0 2px 6px rgba(255,255,255,.06) inset; }
  .knobwrap { flex: none; display: flex; flex-direction: column; align-items: center; gap: 8px; width: 86px; }
  .knob { position: relative; width: 74px; height: 74px; border-radius: 50%; cursor: pointer; touch-action: none; outline: none;
    background: repeating-conic-gradient(from 0deg, #f8f8f8 0deg 4deg, #9c9c9c 4deg 8deg);
    box-shadow: 0 6px 10px rgba(0,0,0,.8), 0 0 0 2px #2a2a2a; }
  .knob::before { content: ''; position: absolute; inset: 12px; border-radius: 50%;
    background: radial-gradient(circle at 35% 30%, #4a4a4a 0%, #1a1a1a 45%, #000 100%); box-shadow: 0 0 0 3px #dcdcdc, 0 0 0 5px #6d6d6d; }
  .knob .mark { position: absolute; left: 50%; top: 15px; width: 3px; height: 14px; margin-left: -1.5px; border-radius: 2px; background: var(--cream); transform-origin: 50% 22px; }
  .knob:focus-visible { box-shadow: 0 6px 10px rgba(0,0,0,.8), 0 0 0 3px var(--amber); }
  .cap { font-size: 9px; letter-spacing: 1.5px; color: var(--dim); text-align: center; line-height: 1.3; }
  .centre { flex: 1; min-width: 0; }
  .dial { position: relative; height: 92px; border-radius: 6px; overflow: hidden; border: 2px solid #3a3a3a;
    background: linear-gradient(180deg, #151a1a 0%, #070909 100%); box-shadow: 0 0 18px rgba(255,179,71,.08) inset; }
  .dial.lit { box-shadow: 0 0 26px rgba(255,179,71,.22) inset; }
  .redline { position: absolute; left: 4%; top: 10px; width: 6px; height: 22px; background: var(--red); border-radius: 1px; }
  .scale { position: absolute; left: 7%; right: 4%; top: 6px; display: flex; justify-content: space-between; font: 600 19px/1 Georgia, "Times New Roman", serif; color: var(--cream); }
  .ticks { position: absolute; left: 4%; right: 4%; top: 32px; height: 8px;
    background: repeating-linear-gradient(90deg, rgba(239,231,207,.75) 0 1px, transparent 1px 12px); }
  .needle { position: absolute; top: 4px; width: 3px; height: 50px; margin-left: -1.5px; background: var(--red); box-shadow: 0 0 6px rgba(232,71,60,.8); border-radius: 1px; transition: left .7s cubic-bezier(.3,.7,.2,1); left: 6%; }
  .readout { position: absolute; left: 0; right: 0; bottom: 0; display: flex; align-items: center; gap: 8px; height: 34px; padding: 0 10px;
    background: linear-gradient(180deg, rgba(0,0,0,.2), rgba(0,0,0,.6)); border-top: 1px solid #222; }
  .lamp { flex: none; width: 9px; height: 9px; border-radius: 50%; background: #3a2a10; }
  .lamp.on { background: var(--green); box-shadow: 0 0 8px var(--green); }
  .lamp.tuning { background: var(--amber); box-shadow: 0 0 8px var(--amber); animation: blink .8s steps(2) infinite; }
  @keyframes blink { 50% { opacity: .25 } }
  .now { flex: 1; min-width: 0; font: 600 18px/1 "Courier New", ui-monospace, monospace; letter-spacing: 1px; color: var(--amber); text-shadow: 0 0 8px rgba(255,179,71,.55);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-transform: uppercase; }
  .now.off { color: #6b5532; text-shadow: none; }
  .air { flex: none; font: 600 11px/1 "Courier New", ui-monospace, monospace; letter-spacing: 1px; color: var(--faint); text-transform: uppercase; }
  .air.on { color: var(--green); } .air.tuning { color: var(--amber); }
  .plate { margin: 8px 0 6px; text-align: center; font-size: 10px; font-weight: bold; letter-spacing: 3px; color: #cfcfcf; }
  .presets { display: flex; gap: 6px; }
  .preset { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 0; border: none; background: none; cursor: pointer; color: var(--dim); }
  .preset .key { width: 100%; height: 30px; border-radius: 3px; background: linear-gradient(180deg, #3a3a3a 0%, #151515 60%, #0a0a0a 100%);
    box-shadow: 0 4px 0 #000, 0 5px 6px rgba(0,0,0,.6), 0 1px 0 rgba(255,255,255,.18) inset; transition: transform .08s, box-shadow .08s; font: bold 12px/30px sans-serif; color: #8d8d8d; }
  .preset.down .key { transform: translateY(3px); box-shadow: 0 1px 0 #000, 0 1px 2px rgba(0,0,0,.6), 0 1px 0 rgba(255,255,255,.1) inset; color: var(--amber); }
  .preset .lbl { width: 100%; font-size: 10px; line-height: 1.2; text-align: center; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .preset:disabled { cursor: default; opacity: .45; }
  .preset:focus-visible .key { outline: 2px solid var(--amber); }

  .below { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 16px; margin-top: 14px; padding: 0 4px; }
  .nowsub { flex: 1 1 260px; color: var(--dim); font-size: 13px; }
  .toggle { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--dim); cursor: pointer; }
  .toggle input { position: absolute; opacity: 0; width: 1px; height: 1px; }
  .switch { position: relative; width: 38px; height: 20px; border-radius: 10px; background: linear-gradient(180deg, #2a2a2a, #111); box-shadow: 0 0 0 1px #555 inset; flex: none; }
  .switch::after { content: ''; position: absolute; top: 2px; left: 2px; width: 16px; height: 16px; border-radius: 50%; background: linear-gradient(180deg, #f2f2f2, #8a8a8a); transition: left .15s; }
  .toggle input:checked + .switch { background: linear-gradient(180deg, #4b3a12, #2a1f08); box-shadow: 0 0 0 1px var(--amber) inset; }
  .toggle input:checked + .switch::after { left: 20px; }
  .toggle input:focus-visible + .switch { outline: 2px solid var(--amber); outline-offset: 2px; }
  .note { margin-top: 10px; padding: 0 4px; font-size: 14px; color: var(--amber); }
  .note.bad { color: var(--red); }
  .note:empty { display: none; }

  button { font: inherit; font-size: 13px; color: var(--text); background: linear-gradient(180deg, #2b2b2b, #161616); border: 1px solid #555; border-radius: 4px; padding: 5px 12px; cursor: pointer; }
  button:hover { border-color: var(--amber); }
  button:disabled { opacity: .5; cursor: default; }
  .buttons { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
  .log { margin-top: 18px; padding: 12px 14px; border-radius: 8px; background: rgba(0,0,0,.35); border: 1px solid #2c2a26; }
  h2 { margin: 0 0 4px; font-size: 12px; letter-spacing: 2px; text-transform: uppercase; color: var(--amber); display: flex; gap: 8px; align-items: baseline; }
  h2 span { flex: 1; } h2 small { color: var(--faint); font-weight: normal; font-size: 12px; letter-spacing: 0; text-transform: none; }
  .log + .log { margin-top: 12px; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { display: flex; align-items: center; gap: 10px; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,.06); }
  li:last-child { border-bottom: none; }
  li .name { flex: 1; min-width: 0; overflow-wrap: anywhere; }
  li .place { color: var(--faint); font-size: 12px; }
  li.playing .name b { color: var(--amber); }
  li .km { flex: none; color: var(--dim); font-size: 13px; font-family: "Courier New", ui-monospace, monospace; }
  li button { flex: none; padding: 3px 10px; font-size: 12px; }
  footer { margin-top: 16px; font-size: 12px; color: var(--faint); }
  footer a { color: var(--amber); }
  details { margin-top: 8px; font-size: 13px; }
  summary { cursor: pointer; color: var(--amber); }
  .add { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
  .add input { flex: 1 1 200px; min-width: 0; font: inherit; font-size: 14px; color: var(--text); background: #0b0b0b; border: 1px solid #555; border-radius: 4px; padding: 6px 8px; }
  .hint { margin-top: 6px; color: var(--faint); font-size: 12px; }
  .hint.bad { color: var(--red); }
  @media (max-width: 560px) {
    .face { flex-wrap: wrap; justify-content: space-between; padding: 12px; }
    .centre { order: -1; flex: 1 1 100%; }
    .knobwrap { width: 46%; }
  }
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
<section class="unit" aria-label="Car radio">
  <div class="face">
    <div class="knobwrap">
      <div class="knob" id="volume" role="slider" tabindex="0" aria-label="Volume. Press it to turn the radio on or off" aria-valuemin="0" aria-valuemax="100" aria-valuenow="60" title="Turn for volume (drag up or down, or scroll). Press for on and off."><span class="mark" id="volMark"></span></div>
      <div class="cap">VOLUME<br>PUSH ON&middot;OFF</div>
    </div>
    <div class="centre">
      <div class="dial" id="dial" aria-live="polite">
        <div class="redline"></div>
        <div class="scale" aria-hidden="true"><span>6</span><span>7</span><span>8</span><span>9</span><span>10</span><span>12</span><span>14</span><span>16</span></div>
        <div class="ticks" aria-hidden="true"></div>
        <div class="needle" id="needle" aria-hidden="true"></div>
        <div class="readout"><span class="lamp" id="lamp"></span><span class="now off" id="now">Off</span><span class="air" id="air">Off</span></div>
      </div>
      <div class="plate">WORLDWIDE TRUCKING</div>
      <div class="presets" id="presets" role="group" aria-label="Presets"></div>
    </div>
    <div class="knobwrap">
      <div class="knob" id="tune" role="button" tabindex="0" aria-label="Tune: next station" title="Press or scroll to tune to the next station"><span class="mark" id="tuneMark"></span></div>
      <div class="cap">TUNE<br>NEXT STATION</div>
    </div>
  </div>
</section>
<div class="below">
  <div class="nowsub" id="nowsub">Stations near your truck appear as soon as the game says where you are.</div>
  <label class="toggle"><input type="checkbox" id="follow"><span class="switch" aria-hidden="true"></span>Follow my truck</label>
</div>
<div class="note" id="note" role="status"></div>
<section class="log">
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
</section>
<section class="log">
  <h2><span>Stations near you</span><small id="count"></small></h2>
  <ul id="list"></ul>
  <div class="buttons"><button type="button" id="again">Look again</button></div>
</section>
<footer>Push the volume knob to turn the radio on, turn it for volume, and press Tune or a preset to change station. With Follow my truck on, the radio switches to a nearby station once you are far from the one playing. Stations from <a href="https://www.radio-browser.info" target="_blank" rel="noopener">Radio Browser</a>, a free list of internet radio; some may be off air or only play in their own country. About 60 MB of internet an hour. Keep this tab open: the music plays in the background while you drive.</footer>
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
      if (e && e.name === 'NotAllowedError') { note('Push the volume knob to start the radio: the browser waits for a click.'); setAir('off'); st.playing = null; draw() }
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
  // The next station along the dial; after a favourite that won't play, the nearby stations.
  function next (step) {
    var list = band()
    if (!list.length) return
    var i = -1
    for (var k = 0; k < list.length; k++) if (st.playing && list[k].url === st.playing.url) i = k
    play(list[((i < 0 ? (step < 0 ? 0 : -1) : i) + (step || 1) + list.length) % list.length])
  }
  function setAir (how) {
    $('air').textContent = how === 'on' ? 'On air' : (how === 'tuning' ? 'Tuning' : 'Off')
    $('air').className = 'air ' + how
    $('lamp').className = 'lamp ' + how
    $('dial').className = how === 'off' ? 'dial' : 'dial lit'
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
    $('now').textContent = p ? p.name : (st.stations.length || st.featured.length || st.own.length ? 'Off' : (st.looking ? 'Searching' : 'Off'))
    $('now').className = p ? 'now' : 'now off'
    $('nowsub').textContent = p ? [p.place, st.here && !p.pinned ? km(metres(st.here, p)) + ' from your truck' : ''].filter(Boolean).join(' · ')
      : (st.stations.length ? 'Push the volume knob to turn on, or press a preset.' : (st.looking ? 'Looking for stations near your truck...' : 'Stations near your truck appear as soon as the game says where you are.'))
    document.title = p ? '♪ ' + p.name + ' · Worldwide Trucking Radio' : 'Worldwide Trucking Radio'
    // The needle points along the dial at the station playing: favourites first, then the nearest ones.
    var all = band(), at = -1
    for (var i = 0; i < all.length; i++) if (p && all[i].url === p.url) at = i
    $('needle').style.left = (at < 0 ? 6 : 10 + 84 * (all.length > 1 ? at / (all.length - 1) : 0.5)) + '%'
    drawPresets(all.slice(0, 5))
    $('count').textContent = st.stations.length ? st.stations.length + ' stations' : ''
    fill($('favs'), st.featured.concat(st.own))
    fill($('list'), st.stations)
  }
  function band () { return st.featured.concat(st.own, st.stations) }
  function drawPresets (picks) {
    var box = $('presets'), p = st.playing
    while (box.firstChild) box.removeChild(box.firstChild)
    for (var i = 0; i < 5; i++) {
      (function (s, n) {
        var b = document.createElement('button'); b.type = 'button'; b.className = 'preset' + (s && p && p.url === s.url ? ' down' : '')
        var key = document.createElement('span'); key.className = 'key'; key.textContent = String(n)
        var lbl = document.createElement('span'); lbl.className = 'lbl'; lbl.textContent = s ? s.name : '-'
        b.appendChild(key); b.appendChild(lbl)
        b.disabled = !s
        b.title = s ? 'Preset ' + n + ': ' + s.name : 'Preset ' + n + ': empty'
        b.setAttribute('aria-label', b.title)
        if (s) b.addEventListener('click', function () { st.failed = 0; note(''); play(s) })
        box.appendChild(b)
      })(picks[i], i + 1)
    }
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

  // The knobs. Volume turns from -135 to +135 degrees: drag up or down, scroll, or the arrow keys; a press
  // without turning switches the radio on (the station last played, or the first on the dial) or off.
  function setVolume (v) {
    st.volume = Math.round(Math.max(0, Math.min(1, v)) * 100) / 100
    audio.volume = st.volume
    $('volMark').style.transform = 'rotate(' + (-135 + 270 * st.volume) + 'deg)'
    $('volume').setAttribute('aria-valuenow', String(Math.round(st.volume * 100)))
  }
  var last = null
  function power () {
    if (st.playing) { last = st.playing; stop(); return }
    var all = band()
    var pick = last && all.some(function (s) { return s.url === last.url }) ? last : all[0]
    if (pick) { st.failed = 0; note(''); play(pick) } else note('No stations yet. Wait a moment for the list, or press Look again.')
  }
  var turns = 0
  function tune (step) {
    turns += step || 1
    $('tuneMark').style.transform = 'rotate(' + (turns * 30) + 'deg)'
    st.failed = 0; note(''); next(step)
  }
  setVolume(st.volume)
  ;(function () {
    var knob = $('volume'), from = null, moved = false
    knob.addEventListener('pointerdown', function (e) { from = { y: e.clientY, v: st.volume }; moved = false; knob.setPointerCapture(e.pointerId) })
    knob.addEventListener('pointermove', function (e) {
      if (!from) return
      var dy = from.y - e.clientY
      if (Math.abs(dy) > 3) moved = true
      if (moved) setVolume(from.v + dy / 150)
    })
    knob.addEventListener('pointerup', function () { if (from && !moved) power(); if (moved) save(); from = null })
    knob.addEventListener('wheel', function (e) { e.preventDefault(); setVolume(st.volume + (e.deltaY < 0 ? 0.05 : -0.05)); save() }, { passive: false })
    knob.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowUp' || e.key === 'ArrowRight') { e.preventDefault(); setVolume(st.volume + 0.05); save() }
      else if (e.key === 'ArrowDown' || e.key === 'ArrowLeft') { e.preventDefault(); setVolume(st.volume - 0.05); save() }
      else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); power() }
    })
    var t = $('tune')
    t.addEventListener('click', function () { tune(1) })
    t.addEventListener('wheel', function (e) { e.preventDefault(); tune(e.deltaY < 0 ? 1 : -1) }, { passive: false })
    t.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowRight' || e.key === 'ArrowUp') { e.preventDefault(); tune(1) }
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { e.preventDefault(); tune(-1) }
    })
  })()
  $('follow').checked = st.follow
  $('follow').addEventListener('change', function () { st.follow = this.checked; save(); followTruck() })
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
