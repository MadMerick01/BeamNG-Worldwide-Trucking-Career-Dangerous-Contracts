-- The Earth Freight controller: ties the Earth position, the save, the garage, the places and the
-- job boards together, and builds the HUD's state. The garage side lives in workshop.lua.
local location = require('earthFreight/location')
local config = require('earthFreight/config')
local persistence = require('earthFreight/persistence')
local diagnostics = require('earthFreight/diagnostics')
local hud = require('earthFreight/hud')
local earthAdapter = require('earthFreight/earthAdapter')
local garage = require('earthFreight/garage')
local punctures = require('earthFreight/punctures')
local pricing = require('earthFreight/pricing')
local odometer = require('earthFreight/odometer')
local places = require('earthFreight/places')
local goods = require('earthFreight/goods')
local jobs = require('earthFreight/jobs')
local cargo = require('earthFreight/cargo')
local fuel = require('earthFreight/fuel')
local workshop = require('earthFreight/workshop')
local shipping = require('earthFreight/shipping')
local contracts = require('earthFreight/contracts')
local beacons = require('earthFreight/beacons')
local flights = require('earthFreight/flights')
local aircraft = require('earthFreight/aircraft')
local trailers = require('earthFreight/trailers')
local home = require('earthFreight/home')
local streetView = require('earthFreight/streetView')
local business = require('earthFreight/business')
local multiplayer = require('earthFreight/multiplayer')
local shipday = require('earthFreight/shipday')
local magnate = require('earthFreight/magnate')
local M = {}
-- Money a new game starts with.
local STARTING_MONEY = 6000 -- the radiator the starter car needs, fuel, and room for a few cargo boxes
local MAX_BALANCE = 9007199254740991
M.STARTING_MONEY = STARTING_MONEY
-- What the game's traffic police take when they catch the player, for a ticket or an arrest.
local POLICE_FINE = 200
M.POLICE_FINE = POLICE_FINE
M.STARTER_MODEL, M.STARTER_CONFIG = workshop.STARTER_MODEL, workshop.STARTER_CONFIG
-- How many places the nearby list shows.
local NEARBY_COUNT = 6
-- How long the HUD shows a delivery, a cancelled job or a puncture.
local FLASH_SECONDS = 8
-- After Teleport there, the button waits this long for Earth to load the terrain and place the car.
local TELEPORT_WAIT_SECONDS = 30
-- After a delivery, a purchase, a repair or a relocation, the game saves itself once the car has
-- been stopped this long and nothing else is going on.
local AUTOSAVE_SECONDS = 3
-- Every this many seconds of play with something new to keep (distance driven, money earned or spent, a new
-- name), the game also saves itself, in the same way: at the next stop, never while driving.
local TIMED_SAVE_SECONDS = 5 * 60
-- Whether the Street View window was on, so it starts again with the game.
local STREET_VIEW_FILE = '/settings/earthFreight/streetview.json'
-- The real businesses found for towns, so each town is only looked up once (see business.lua).
local BUSINESS_FILE = '/settings/earthFreight/businesses.json'
M.AUTOSAVE_SECONDS, M.TIMED_SAVE_SECONDS = AUTOSAVE_SECONDS, TIMED_SAVE_SECONDS
-- A puncture's tyre repair, as damage points, so every repair quote and bill includes it. Like
-- other damage it is priced by the car's Value: TYRE_REPAIR_COST on a REFERENCE_CAR_VALUE car.
local PUNCTURE_DAMAGE = punctures.TYRE_REPAIR_COST / pricing.REPAIR_COST_PER_DAMAGE
local dollars = pricing.dollars

local labels = {
  CONFIG_REQUIRED = 'BASE CONFIGURATION REQUIRED', EARTH_UNAVAILABLE = 'EARTH UNAVAILABLE',
  READY = 'READY', ERROR = 'FREIGHT PAUSED',
}
-- What the HUD asks of the player until they reach the resume point. A new game with no start yet
-- asks them to choose one: anywhere on Earth they teleport to, then Start here.
local goMessages = {
  resume = 'Press Teleport there to carry on, or copy these coordinates into the BeamNG.Earth map.',
  start = 'Press Teleport there to go back to your start, or teleport anywhere in the BeamNG.Earth map and press Start here.'
    .. ' You get your starter car when you start.',
  choose = 'Open the BeamNG.Earth map, find anywhere on Earth, such as your home town, and teleport there.'
    .. ' Then press Start here. You get your starter car there.',
}
local messages = {
  earth_missing = 'Enable BeamNG.Earth to continue.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_interface_error = 'Earth information is unavailable. Load the level again when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
}
-- What the player sees for each problem that pauses Earth Freight.
local errorMessages = {
  newer_version = 'Your save was made by a newer version of Worldwide Trucking Career. Update the mod to keep playing.',
  storage_unavailable = 'Worldwide Trucking Career could not open its save folder. Load the level again to try again.',
  mp_waiting = 'Getting your trucking career from the server. This takes a few seconds.',
  internal_error = 'Worldwide Trucking Career hit a problem and paused. Load the level again to carry on from your last save.'
    .. ' What went wrong is in beamng.log: search it for internal_error.',
}
local loadMessages = {
  loaded = 'Loaded your last save.',
  missing = 'No save yet. Press Save to keep your progress.',
  unreadable = 'Your save file could not be read, so this is a fresh start. Saving will replace it.',
}

-- How much of a good, as the player reads it: '20 parts', or '400 L of water' for a fluid.
local function amount(good, units)
  if good.kind == 'fluid' then return math.floor(units * good.litres + 0.5) .. ' L of ' .. good.name:lower() end
  return units .. ' ' .. good.name:lower()
end

-- A start this far from every town is called "your start", not after a town far away.
local START_TOWN_METRES = 20000
-- Farther than this from every town, the HUD says you are far from any town.
local WHERE_NEAR_METRES = 50000

-- The name of the town at a point, or of the nearest one close enough; nil when there is none.
local function townName(point)
  if not location.valid(point) then return nil end
  places.ensure(point)
  local here = places.at(point)
  if not here then
    local nearest = places.nearest(point, 1)[1]
    here = nearest and nearest.metres <= START_TOWN_METRES and nearest.place or nil
  end
  return here and here.name or nil
end

local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- Controller dependencies permit deterministic headless tests. No game globals below this factory.
function M.new(deps)
  local c = {
    state = 'CONFIG_REQUIRED', clock = 0, sessionVerified = false,
    diag = diagnostics.new(deps.log), adapter = deps.adapter,
    store = persistence.new(deps.io), ui = hud.new(deps.trigger),
    feedback = 'Not saved this session.', garage = deps.garage,
    paused = deps.paused or function() return false end,
    random = deps.random or math.random,
    -- Wall-clock seconds, which the paid-shipping offers rotate by.
    now = deps.now or os.time,
    -- Bursts tyres and tells whether the car is off road; without it there are no punctures.
    punctures = deps.punctures,
    -- Adds the load's weight to the car, and reads and sets its fuel; without them the load has no
    -- weight and there is no Refuel.
    cargo = deps.cargo, fuelTank = deps.fuel,
    -- Reads where the hired helicopter is and how high; without it there are no heli flights.
    aircraft = deps.aircraft,
    odometer = odometer.new(),
    -- Sends game UI events, such as the pop-ups that show over the game's own menus.
    trigger = deps.trigger,
    -- The Street View window's little web server, and how a web page is opened in the player's
    -- browser; without them there is no Street View button.
    streetView = deps.streetView, openUrl = deps.openUrl,
    punctureDamage = 0, owedDamage = 0, refuelSerial = 0,
  }
  workshop.attach(c)
  flights.attach(c)
  trailers.attach(c)
  home.attach(c)

  function c:transition(nextState, reason)
    if self.state == nextState and self.reason == reason then return end
    self.state, self.reason = nextState, reason
    self.diag:event('state', nextState .. ':' .. tostring(reason or ''))
  end

  -- A saved job is kept only when its good and both its towns are known to this version, and an
  -- off-road drop's spot is a real position, and a dangerous contract's section is known. A
  -- contract's finish is taken from its section, so a road moved since the save finishes in its new place.
  local function knownLoad(l)
    if type(l) ~= 'table' or not l.pay or not goods.get(l.good) or not places.get(l.from) or not places.get(l.to) then return nil end
    if l.drop ~= nil and not location.valid(l.drop) then return nil end
    if l.contract ~= nil and not contracts.get(l.contract) then return nil end
    if l.pickup ~= nil and not location.valid(l.pickup) then return nil end
    local out = copy(l)
    out.paid = nil
    if l.contract ~= nil then out.drop = location.copy(contracts.get(l.contract).finish) end
    -- A business that no longer checks out leaves the town's usual drop-off.
    if l.business ~= nil then out.business = not l.drop and business.clean(l.business, places.get(l.to)) or nil end
    return out
  end

  -- The recent deliveries from a save, as jobs.lua keeps them: { ['place:good'] = { drop, at } }.
  local function needsFrom(list)
    local out = {}
    for _, n in ipairs(list or {}) do out[n.place .. ':' .. n.good] = { drop = n.drop, at = n.at } end
    return out
  end

  function c:reload()
    self.adapter:invalidate()
    self.odometer:reset()
    self.sessionVerified, self.lastSample, self.error = false, nil, nil
    self.quote, self.repairFeedback = nil, nil
    self.partsFeedback, self.carFeedback, self.tradeFeedback, self.fuelFeedback = nil, nil, nil, nil
    self.vehicleProvided, self.arrivingModel, self.arrivingValue, self.arrived = false, nil, nil, false
    self.arrivingName, self.arrivingConfigFile = nil, nil
    self.newGameArmed, self.flash, self.refunded = false, nil, nil
    self.teleportAskedAt, self.teleportFeedback, self.contractTeleportAt, self.bookingTeleportAt = nil, nil, nil, nil
    -- Shipping booked and not yet used, and where an unbooked teleport left from. Neither is saved:
    -- Save waits until both are settled.
    self.booking, self.stranded, self.shippingFeedback, self.lastDriven = nil, nil, nil, nil
    self.shippingSearch = nil
    -- A puncture not yet repaired; a reload respawns the car, so its tyre repair is owed instead.
    self.punctureDamage, self.offRoad, self.offRoadCheckedAt = 0, nil, nil
    self.fuel, self.fuelReadAt, self.refuelPending, self.appliedWeight, self.tankReading = nil, nil, nil, nil, nil
    self.ourRespawn, self.rawDamage = nil, nil
    self.autoSave, self.gpsTown, self.gpsContract, self.gpsFeedback = nil, nil, nil, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    -- A trailer still in the world from before is taken away: the save says where it is.
    if self.trailerOut and self.garage and self.garage.removeVehicle then self.garage:removeVehicle(self.trailerOut.id) end
    -- On a BeamMP server the career is the server's, kept apart from the single-player one (multiplayer.lua).
    -- The session lasts until the level ends, so a reload in it (such as New game) keeps talking to the same server.
    local mp = deps.multiplayer
    if not (mp and mp.inSession()) then
      self.mp = nil
    elseif not self.mp then
      mp.listen(function(event, data) self:multiplayerEvent(event, data) end)
      self.mp = multiplayer.new({ send = mp.send, encode = mp.encode, decode = mp.decode, io = deps.io })
      self.mp:start(self.clock)
      self.diag:event('multiplayer', 'asking the server for the career')
    end
    self.store = self.mp and multiplayer.store(self.mp, deps.io) or persistence.new(deps.io)
    self.profile, self.loadStatus = self.store:load()
    -- The trailers owned: one saved out comes back behind the car once it is back (watchTrailer). A
    -- second one is kept stored, with a base.
    self.trailer = self.profile and trailers.clean(self.profile.trailer) or nil
    self.spareTrailer = self.profile and trailers.clean(self.profile.spareTrailer) or nil
    self.trailerOut, self.trailerRestored, self.foreignTrailer, self.trailersOpen = nil, nil, nil, false
    self.trailerFeedback, self.storeArmed, self.sellArmed = nil, false, false
    -- The home owned and the car stored there; like money, a home bought since the last Save is not kept.
    self.property = self.profile and copy(self.profile.property) or nil
    self.storedCars = self.profile and copy(self.profile.storedCars) or nil
    self.homeFeedback, self.homeCard = nil, nil
    -- A trailer stored before trailers had a place (the garage that went everywhere) is at the base,
    -- or the depot without one.
    self:placeStoredTrailers()
    -- A paid-shipping offer the player shipped in on, paid back by their first delivery near it.
    self.offer = self.profile and copy(self.profile.offer) or nil
    -- The saved load's places are near where the player left off.
    if self.profile then places.ensure(self.profile.resume) end
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = loadMessages[self.loadStatus] or ''
    if self.mp and self.mp.state == 'server' then
      self.feedback = self.loadStatus == 'loaded' and 'Loaded your career from this server.'
        or self.loadStatus == 'missing' and 'A new career on this server. Every Save is kept on the server.' or self.feedback
      -- Saves made on this PC that never reached the server were kept, and are being sent to it.
      local recovered = self.mp.recovered
      if recovered and self.loadStatus == 'loaded' then
        self.feedback = 'Your last saves never reached the server, so they were kept on this PC and sent to it now: '
          .. pricing.dollars(recovered.balance) .. '.'
        self.diag:event('multiplayer_unsent_kept', tostring(recovered.balance), 'W')
      end
      self.mp.recovered = nil
    elseif self.mp and self.mp.state == 'local' then
      self.feedback = 'This server does not keep trucking careers, so your career here is saved on your PC,'
        .. ' apart from your single-player one. ' .. self.feedback
    end
    if not self.profile and not loadMessages[self.loadStatus] then self.error = self.loadStatus end
    self.load = self.profile and knownLoad(self.profile.load) or nil
    self.needs = needsFrom(self.profile and self.profile.needs)
    self.abandonArmed, self.insuranceArmed, self.insurancePending, self.insuredUntil = false, false, nil, nil
    self.towArmed, self.towedAt = false, nil
    -- A heli hire is not saved: the saved car comes back on arrival. A beacon found and not yet
    -- picked up is, by Save, like money.
    self.hire, self.heliArmed, self.backArmed, self.heliFeedback = nil, false, false, nil
    self.beacon, self.beaconArmed = copy(self.profile and self.profile.beacon), false
    local oldLoad = self.profile and self.profile.load
    if oldLoad and not self.load then
      self.diag:event('load_dropped', tostring(oldLoad.good), 'W')
      -- Cargo bought before the job board: it is taken off and its money given back.
      if not oldLoad.pay and oldLoad.paid then
        self.profile.progression.balance = math.min(MAX_BALANCE, self.profile.progression.balance + oldLoad.paid)
        self.refunded = oldLoad.paid
      end
    end
    self.savedDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0
    -- Before the first save the starting money counts as saved, since it was not earned.
    self.savedBalance = self.profile and self.profile.progression.balance or STARTING_MONEY
    if self.refunded then self.savedBalance = self.savedBalance - self.refunded end
    -- A restored car looks new, but the repair it needed when saved is still owed.
    self.owedDamage = self.profile and self.profile.vehicle and self.profile.vehicle.damage or 0
    -- The name typed on the start page; like money, a changed name is kept by Save.
    self.playerName = self.profile and self.profile.playerName or nil
    self.savedName = self.playerName
    -- The five minutes before the next timed save start again with each load and each save.
    self.savedAt = self.clock
    self.mode = (self.profile and not self.profile.atStart) and 'resume' or 'start'
    self.creationBase = location.copy(self.profile and self.profile.base or self.unsavedBase
      or (self.configuration and self.configuration.base))
    self.startupTarget = location.copy(self.profile and not self.profile.atStart and self.profile.resume or self.creationBase)
    if self.startupTarget then
      self.diag:event('target', self.mode .. ':' .. string.format('%.8f,%.8f', self.startupTarget.latitude, self.startupTarget.longitude))
    end
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration')
    elseif self.error then self:transition('ERROR', self.error)
    else self:transition('EARTH_UNAVAILABLE', 'position_invalid') end
  end

  -- The town the player's start is in: where a new game starts. Remembered for the last base asked.
  function c:startTown()
    local base = self.profile and self.profile.base or self.creationBase
    if not base then return nil end
    local key = string.format('%.6f,%.6f', base.latitude, base.longitude)
    if self.startTownKey ~= key then self.startTownKey, self.startTownName = key, townName(base) end
    return self.startTownName
  end

  -- Teleport there: asks Earth to take the player to the resume point (the last save, or the start
  -- of a new game), as pasting its coordinates into Earth's map does. Arriving is seen in observe.
  function c:teleportToResume()
    if self.state ~= 'READY' or self.arrived or self.error or not self.startupTarget then return false end
    if not self.adapter.teleport then
      self.teleportFeedback = 'Teleporting is not available. Copy the coordinates into the BeamNG.Earth map instead.'
      return false
    end
    local name = self.mode == 'start' and ('Worldwide Trucking: ' .. (self:startTown() or 'start')) or 'Worldwide Trucking: last save'
    local ok, why, detail = self.adapter:teleport(self.startupTarget, name)
    self.diag:event('teleport_to_resume', ok and 'requested' or (tostring(why) .. ':' .. tostring(detail or '')), ok and 'I' or 'W')
    if not ok then
      self.teleportAskedAt = nil
      self.teleportFeedback = 'BeamNG.Earth did not take the teleport. Copy the coordinates into its map instead.'
      return false
    end
    self.teleportAskedAt = self.clock
    self.teleportFeedback = 'Teleporting. The terrain takes a few seconds to load.'
    return true
  end

  function c:interrupt(reason)
    self.odometer:reset()
    if self.configuration and not self.error then self:transition('EARTH_UNAVAILABLE', reason) end
  end

  -- The server's answers (multiplayer.lua). Its career arriving loads it.
  function c:multiplayerEvent(event, data)
    if not self.mp then return end
    local waiting, before = not self.mp:ready(), self.mp.state
    self.mp:receive(event, data)
    if waiting and self.mp:ready() and self.loadStatus == 'mp_waiting' then self:reload()
    elseif before == 'local' and self.mp.state == 'server' then
      -- The server answered late, after the career was kept on this PC: its own career replaces that one.
      self.diag:event('multiplayer', 'the server answered late: its career is loaded', 'W')
      self:reload()
    end
    if event == 'wwtcShip' then
      self.ship, self.shipAt = shipday.clean(self.mp.ship), self.clock
    elseif event == 'wwtcClaimed' then
      self:claimAnswered(self.mp.claimed)
    elseif event == 'wwtcLocate' then
      self:answerLocate(self.mp.locate)
    elseif event == 'wwtcFound' then
      self:playerFound(self.mp.found)
    elseif event == 'wwtcBaseClaimed' then
      self:baseClaimAnswered(self.mp.baseClaimed)
    end
    if event == 'wwtcSaveNow' then self:saveForRestart() end
    if event == 'wwtcSaved' and self.mp.saveError then
      self.feedback = 'The server did not keep your last save (' .. self.mp.saveError .. '). Press Save to try again.'
      self.diag:event('multiplayer_save_refused', self.mp.saveError, 'W')
    end
  end

  -- BeamMP drops a joining player into the world as a free camera, with no car, and the career can't start without
  -- one. After a few seconds without a car, once the career is in, the starter car is put down where the camera is,
  -- as the game's vehicle menu would: from there the usual start (Start here, or Teleport to last save, where the
  -- player's own car is handed over) carries on. Once per level, so a player who leaves their car on purpose isn't
  -- given another.
  M.FIRST_CAR_SECONDS = 3
  function c:spawnFirstCar(sample, dt)
    if not self.mp or not self.mp:ready() or self.firstCarSpawned or not self.garage or not self.garage.spawnFirst
        or self.loadStatus == 'mp_waiting' or type(sample) ~= 'table' or sample.reason ~= 'vehicle_required' then
      self.noCarFor = 0
      return
    end
    self.noCarFor = (self.noCarFor or 0) + dt
    if self.noCarFor < M.FIRST_CAR_SECONDS then return end
    self.firstCarSpawned = true
    local ok, why = self.garage:spawnFirst(M.STARTER_MODEL, M.STARTER_CONFIG)
    self.diag:event('first_car', ok and 'spawned' or tostring(why), ok and 'I' or 'W')
  end

  -- The HUD is a UI app the player adds to their screen layout once. A player who has never added it (often someone
  -- joining a server, who got the mod from it) sees nothing at all, so a pop-up says how, while BeamNG.Earth is
  -- loaded and the HUD hasn't been on screen this level: after HUD_HINT_SECONDS, then every HUD_HINT_REPEAT_SECONDS,
  -- at most HUD_HINT_TIMES. Once the HUD has shown, never again that level (it also closes while the game's menus are
  -- open, which is no reason to nag).
  M.HUD_HINT_SECONDS, M.HUD_HINT_REPEAT_SECONDS, M.HUD_HINT_TIMES = 20, 180, 3
  M.HUD_HINT_TITLE = 'Turn on the trucking HUD'
  M.HUD_HINT_TEXT = 'Worldwide Trucking needs its HUD on screen. Press Esc, go to System > HUD Apps > .Earth (edit layout), '
    .. 'press + Add app, pick "BeamNG Worldwide Trucking Career: Dangerous Contracts" near the bottom of the list, press '
    .. '+ Add to layout, move it where you like and press Save.'
  function c:hintHud(sample, dt)
    local earth = type(sample) == 'table' and (sample.valid or sample.reason == 'vehicle_required')
    if self.hudSeen or not earth or (self.hudHints or 0) >= M.HUD_HINT_TIMES then return end
    self.hudMissingFor = (self.hudMissingFor or 0) + dt
    local due = M.HUD_HINT_SECONDS + (self.hudHints or 0) * M.HUD_HINT_REPEAT_SECONDS
    if self.hudMissingFor < due then return end
    self.hudHints = (self.hudHints or 0) + 1
    self:toast('info', M.HUD_HINT_TITLE, M.HUD_HINT_TEXT, 30)
    self.diag:event('hud_hint', tostring(self.hudHints))
  end

  -- For the server page: the town the player is in or nearest (its centre, never the player's own position), and what
  -- they're doing, told to the server every WHERE_SECONDS and whenever either changes.
  M.WHERE_SECONDS = 60
  function c:doingText()
    local load = self.load
    if not load then
      if self.ship and self:atPort(shipday.portTown(self.ship)) then return 'At the docks for Ship Day' end
      return 'Looking for work'
    end
    local good = goods.get(load.good)
    local to = load.to and places.get(load.to)
    if load.ship then return 'Carrying container ' .. load.ship.n .. (to and (' to ' .. to.name) or '') end
    if load.contract then
      local section = contracts.get(load.contract)
      return 'Dangerous contract' .. (section and (': ' .. section.name) or '')
    end
    if load.beacon then return 'Asking no questions' end
    if load.drop then return 'Off-road drop: ' .. amount(good, load.units) end
    return 'Carrying ' .. amount(good, load.units) .. (to and (' to ' .. to.name) or '')
  end

  function c:reportWhere(sample)
    if not self.mp or self.mp.state ~= 'server' or not self.arrived or type(sample) ~= 'table' or not sample.valid then return end
    local near = places.nearest(sample, 1)[1]
    if not near then return end
    local place, doing = near.place, self:doingText()
    local key = place.id .. '|' .. doing
    if key == self.whereSent and self.clock - (self.whereAt or -math.huge) < M.WHERE_SECONDS then return end
    self.whereSent, self.whereAt = key, self.clock
    self.mp:where({ town = place.name, region = place.region, latitude = place.latitude, longitude = place.longitude,
      doing = doing })
  end

  -- The two ends of a delivery for the server's commission (magnate.lua): the town centres only, never a spot.
  local function townEnds(a, b)
    if not a or not b then return nil end
    return { { latitude = a.latitude, longitude = a.longitude }, { latitude = b.latitude, longitude = b.longitude } }
  end
  M.townEnds = townEnds

  -- Commission from the server for the player's base: added to the money once (by batch id), told in a toast, and
  -- saved, which is what tells the server it's paid. Waits until the career is in and the player is on the road.
  function c:watchCommission()
    local d = self.mp and self.mp.commission
    if not d or not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return end
    self.mp.commission = nil
    if d.id <= (self.profile.commissionId or 0) then return end
    self.profile.commissionId = d.id
    if d.amount > 0 then
      self:addMoney(d.amount)
      self:toast('info', 'Commission', d.jobs == 1 and d.by
        and string.format('%s delivered in your turf and paid you a %s turf toll.', d.by, dollars(d.amount))
        or string.format('%d deliveries in your turf paid you %s in turf tolls.', d.jobs, dollars(d.amount)))
      self.diag:event('commission', string.format('#%d %d from %d jobs', d.id, d.amount, d.jobs))
    end
    self:autoSaveSoon('your commission')
  end

  -- Tells the server a delivery happened, for its live feed, today's totals and base owners' commission.
  function c:reportDelivery(kind, good, units, from, to, pay, ends, toll)
    if not self.mp or self.mp.state ~= 'server' then return end
    self.mp:delivered({ kind = kind, what = good and amount(good, units) or nil, from = from, to = to, pay = pay, ends = ends,
      toll = toll and toll.amount or nil })
  end

  -- The turf toll (magnate.lua): a delivery whose drop-off town is in someone else's turf pays them part of its pay.
  -- Returns the pay left and the toll { owner, amount }, or the pay and nil.
  function c:applyToll(pay, point)
    local owner = pay > 0 and point and self:baseTollAt(point)
    if not owner then return pay, nil end
    local left, toll = magnate.afterToll(pay)
    return left, { owner = owner, amount = toll }
  end

  -- The line the delivery message adds for a toll.
  local function tollLine(load)
    return load.toll and (' ' .. load.toll.owner .. ' took a ' .. dollars(load.toll.amount) .. ' turf toll.') or ''
  end

  function c:endMission()
    self.whereSent, self.whereAt = nil, nil
    self.hudSeen, self.hudHints, self.hudMissingFor = nil, nil, nil
    self.ship, self.shipAt, self.shipClaim, self.shipFeedback = nil, nil, nil, nil
    self.finding = nil
    self.turf, self.turfKey, self.turfPending, self.turfCheckedAt = nil, nil, nil, nil
    self.mp, self.firstCarSpawned, self.noCarFor = nil, nil, nil
    self.sessionVerified, self.lastSample = false, nil
    self:interrupt('earth_level_required')
    self.adapter:invalidate()
  end

  function c:addMoney(amount)
    local progression = self.profile.progression
    progression.balance = math.min(MAX_BALANCE, progression.balance + math.floor(amount))
  end

  function c:canAfford(amount)
    return self.profile ~= nil and not self.error and type(amount) == 'number' and amount >= 0
      and amount == math.floor(amount) and amount <= self.profile.progression.balance
  end

  -- Every purchase pays through here: refuses when the balance is short, never goes below zero.
  -- Like earnings, the new balance is only kept on disk by Save.
  function c:spend(amount, label)
    if not self:canAfford(amount) then
      self.diag:event('spend_rejected', tostring(label) .. ':' .. tostring(amount), 'W')
      return false
    end
    self.profile.progression.balance = self.profile.progression.balance - amount
    self.diag:event('spend', tostring(label) .. ':' .. tostring(amount))
    return true
  end

  -- The game's traffic police caught the player's car: 'arrest' ends every pursuit they win, and a
  -- pursuit at its first level (mode 1) is a ticket. Takes POLICE_FINE, or all the money when the
  -- player has less. The game shows its own arrest message, which says nothing of money, so the fine
  -- goes on a line of its own under it, and on the HUD. Nothing before the player has arrived.
  function c:policeAction(action, data)
    if action ~= 'arrest' or not self.profile or self.error or not self.arrived then return false end
    local ticket = type(data) ~= 'table' or tonumber(data.mode) == nil or tonumber(data.mode) <= 1
    local progression = self.profile.progression
    local taken = math.min(POLICE_FINE, progression.balance)
    progression.balance = progression.balance - taken
    self.diag:event('police_fine', (ticket and 'ticket:' or 'arrest:') .. tostring(taken))
    local text = 'Police fine: ' .. dollars(taken) .. ' taken'
      .. (taken < POLICE_FINE and (' (all you had, of ' .. dollars(POLICE_FINE) .. ')') or '')
      .. '. You have ' .. dollars(progression.balance) .. ' left.'
    self:showFlash('cancelled', ticket and 'POLICE TICKET' or 'ARRESTED BY THE POLICE', text)
    if self.trigger then
      pcall(self.trigger, 'Message', { msg = text, ttl = 8, category = 'earthFreightPoliceFine', icon = 'warning' })
    end
    self:autoSaveSoon('your police fine')
    return true
  end

  function c:showFlash(kind, title, text)
    self.flash = { kind = kind, title = title, text = text, at = self.clock }
  end

  -- A pop-up in the corner of the screen. Unlike the HUD it shows over the game's own menus.
  function c:toast(kind, title, text, seconds)
    if self.trigger then
      pcall(self.trigger, 'toastrMsg', { type = kind, title = title, msg = text, config = { timeOut = (seconds or 12) * 1000 } })
    end
  end

  -- Adds the player's name to a greeting: "Welcome back" becomes "Welcome back, Sam".
  function c:named(greeting)
    return self.playerName and (greeting .. ', ' .. self.playerName) or greeting
  end

  -- Sets the player's name. Spaces are tidied, and an empty name clears it. Returns false when the
  -- name is too long or has characters a save cannot hold.
  function c:setPlayerName(name)
    if type(name) ~= 'string' then return false end
    name = name:gsub('%s+', ' '):match('^ ?(.-) ?$')
    if name == '' then self.playerName = nil; return true end
    if not persistence.validName(name) then
      self.diag:event('name_rejected', tostring(#name), 'W')
      return false
    end
    self.playerName = name
    return true
  end

  -- The cargo space of the car the player owns, from its paid-for parts. Once the car has said how
  -- many litres its fluid containers really hold, that replaces the size guessed from the part names.
  -- A vanilla tanker's tank is part of its body, with no Cargo Load tank part to match on, so its
  -- space comes only from the car's answer.
  function c:space()
    local space = cargo.capacity(self.ownedParts)
    local reading = self.tankReading
    if reading and reading.litres and self.ownedParts and reading.vehicleId == self.ownedParts.id then
      space.litres, space.tankKg = reading.litres, reading.litres
      if #space.tanks == 0 then space.tanks = { cargo.BUILT_IN_TANK } end
    end
    return space
  end

  -- Puts the load's weight on the car, when it changed or the car respawned. A fluid load pours
  -- into the tank, so it sloshes.
  function c:applyWeight(force)
    -- The load waits in the car while the player flies a helicopter or is on foot.
    if not self.cargo or self.hire or self.onFoot then return end
    local kg = self.load and self.load.kg or 0
    local good = self.load and goods.get(self.load.good)
    local key = tostring(kg) .. ':' .. tostring(good and good.id) .. ':' .. tostring(self.trailerOut and self.trailerOut.id)
    if not force and self.appliedWeight == key then return end
    local space = self:space()
    -- The trailer's share goes on the trailer; the rest is in the car.
    kg = self:applyTrailerWeight(kg, good)
    local carUnits = self.load and (self.load.units - (self.load.trailerUnits or 0)) or 0
    local fluid = { litres = 0, density = 1, tanks = space.tankParts }
    if good and good.kind == 'fluid' then
      fluid.litres = carUnits * good.litres
      fluid.density = good.kg / good.litres
    end
    local ok, why, detail = self.cargo:setWeight(kg, cargo.partsFor(space, good), fluid)
    if ok then self.appliedWeight = key
    else self.diag:event('weight_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'W') end
  end

  -- The car's answer: how many litres its fluid containers hold. None (0) keeps the guess.
  function c:tanksRead(vehicleId, litres)
    if not location.finite(litres) or litres < 0 then return end
    local current = self.lastSample and self.lastSample.vehicle and self.lastSample.vehicle.id
    if current ~= nil and vehicleId ~= current then return end
    self.tankReading = { vehicleId = vehicleId, litres = litres > 0 and math.floor(litres + 0.5) or nil }
  end

  -- A respawn (repair, part change or reverted car) fills the tank and drops the load's weight;
  -- the fuel the car had is put back once it has spawned, and so is the weight.
  function c:beforeRespawn()
    if self.fuel and self.ownedParts and self.fuel.vehicleId == self.ownedParts.id then self.fuel.restore = true end
    self.appliedWeight, self.tankReading = nil, nil
    -- Its damage drops as it respawns, which is not the game resetting it.
    self.ourRespawn = true
  end

  -- The respawn did not happen, so the car keeps its fuel and weight.
  function c:respawnFailed()
    self.ourRespawn = nil
    if self.fuel then self.fuel.restore = nil end
    self:applyWeight()
  end

  -- After a spawn of the player's own car: puts its fuel back and the load's weight on.
  function c:afterRespawn()
    if not self.respawned or self.partsCheckDue or not self.ownedParts then return end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if vehicleId ~= nil and vehicleId ~= self.ownedParts.id then return end
    self.respawned = false
    if self.fuel and self.fuel.restore and self.fuelTank then
      self.fuel.restore = nil
      local ok, why = self.fuelTank:set(self.fuel.litres, 0)
      if not ok then self.diag:event('fuel_restore_failed', tostring(why), 'W') end
    end
    self:applyWeight(true)
  end

  -- Driving. Distance counts only once the player has arrived. A teleport-sized jump never counts;
  -- one longer than a short hop goes through teleported. While stranded nothing counts.
  function c:drive(sample, dt)
    -- Earth can pause while it teleports, which resets the odometer, so the last place driven to
    -- is kept as well.
    local fresh = self.odometer.last == nil
    local before = location.copy(self.odometer.last or self.lastDriven)
    local metres, jump = self.odometer:step(sample, dt)
    self.lastDriven = location.copy(sample)
    -- Which way the car is going, for the drop arrow when Earth does not say which way it points.
    if before and not jump and (location.distance(before, sample) or 0) > 0.5 then self.heading = location.bearing(before, sample) end
    -- Flying a hired helicopter, or on foot, nothing counts: not the distance, nor the teleport back to the car.
    if self.hire or self.onFoot then return end
    if fresh and before then
      local gap = location.distance(before, sample)
      if gap and gap > odometer.SHORT_HOP_METRES then jump = gap end
    end
    if jump then
      -- The insurance claim's or tow's move back to the road is not a teleport.
      local insured = self.insuredUntil and self.clock <= self.insuredUntil
      if jump > odometer.SHORT_HOP_METRES and not insured then self:teleported(before, sample) end
      return
    end
    -- Landing at a booking is seen from where the car is, not only from a jump: while Earth loads the
    -- terrain the car can turn up first somewhere near the destination (which strands it, booking still
    -- held), then reach the booking in a long loading frame that does not read as a jump.
    if self.booking and shipping.arrived(sample, self.booking) then
      self:landAtBooking('')
      return
    end
    if self.stranded then
      if shipping.returned(sample, self.stranded) then self:unstrand() end
      return
    end
    if metres <= 0 then return end
    local progression = self.profile.progression
    progression.totalDistanceKm = progression.totalDistanceKm + metres / 1000
    if self.load then self.load.drivenKm = self.load.drivenKm + metres / 1000 end
    self:roadPuncture(sample, metres, dt)
  end

  local function coordinates(p) return string.format('%.5f, %.5f', p.latitude, p.longitude) end

  function c:unstrand()
    self.stranded = nil
    self:showFlash('delivered', 'BACK ON THE ROAD', 'You are back where you teleported from. Deliveries and driving count again.')
    self.diag:event('unstranded', '')
  end

  -- A long teleport. Any load on board is lost, with the money paid for it. A booked one that lands
  -- at the destination is shipping; a jump back to where an unbooked one left from undoes it;
  -- anything else strands the player until they go back or book shipping. A dangerous contract not
  -- yet started is relocated to its start by a teleport that lands there, and starts.
  function c:teleported(from, to)
    -- The trailer is left behind, so it goes into the garage.
    local trailerNote = self:trailerTeleported()
    if trailerNote ~= '' then self.trailerFeedback = trailerNote:gsub('^ ', '') end
    local section = self.load and self.load.contract and not self.load.started and contracts.get(self.load.contract)
    if section and contracts.atStart(to, section) then
      self.load.started, self.load.drivenKm, self.stranded = true, 0, nil
      self.contractTeleportAt = nil
      local gps = self:gpsToFinish(section)
      self:showFlash('delivered', 'DANGEROUS CONTRACT: ' .. section.name:upper(), section.summary
        .. (gps and ' The GPS is set to the finish.' or ' Follow the arrow on the Route tab to the finish.')
        .. ' Stop there to deliver. A crash ends the contract.')
      self.diag:event('contract_started', section.id)
      return
    end
    local lost = ''
    if self.load then
      local fee = self:dropJob('teleport')
      lost = ' Your job is cancelled' .. (fee > 0 and (', which cost ' .. dollars(fee)) or '') .. '.'
    end
    if self.booking and shipping.arrived(to, self.booking) then
      self:landAtBooking(lost)
    elseif self.stranded and shipping.returned(to, self.stranded) then
      self:unstrand()
      if lost ~= '' then self:showFlash('cancelled', 'LOAD LOST', 'You are back where you teleported from.' .. lost) end
    else
      self.stranded = self.stranded or from
      self:showFlash('cancelled', 'RELOCATION NOT BOOKED', 'Deliveries and driving do not count until you go back to '
        .. coordinates(self.stranded) .. ' (copy them on the Route tab), or book a relocation on the Relocate tab.' .. lost)
      self.diag:event('stranded', coordinates(self.stranded), 'W')
    end
  end

  -- The car is at its booked relocation: the booking is used up, and anything the teleport on the way
  -- there looked like (stranded somewhere in between while Earth loaded) is forgiven.
  function c:landAtBooking(lost)
    local b = self.booking
    self.booking, self.stranded, self.bookingTeleportAt = nil, nil, nil
    local paid = ''
    if b.offer then
      self.offer = { latitude = b.latitude, longitude = b.longitude, name = b.name, fee = b.fee }
      paid = ' ' .. b.name .. ' pays back your ' .. dollars(b.fee) .. ' relocation when you deliver within '
        .. math.floor(shipping.OFFER_RADIUS_METRES / 1000) .. ' km of it.'
    end
    self:showFlash(lost ~= '' and 'cancelled' or 'delivered', 'RELOCATED TO ' .. b.name:upper(),
      'Welcome to ' .. b.region .. '. Find a load in town.' .. paid .. lost)
    self:autoSaveSoon('your relocation')
    self.diag:event('shipped', b.id)
  end

  -- What the player is told while on foot. (Away in a helicopter or the sightseeing car: c:awayText.)
  local ON_FOOT = 'You are on foot. Get back in your car first.'

  -- Why booking shipping is not possible now, or nil when it is.
  function c:shippingProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Relocation is unavailable right now.' end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    if self.load then return 'Deliver or abandon your job first: cargo cannot be relocated.' end
    if self.trailerShop then return 'Finish with your trailer parts on the Garage tab first.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.booking then return 'You already have a relocation booked to ' .. self.booking.name .. '.' end
    return nil
  end

  -- A place as a shipping destination.
  local function placeDestination(place)
    return place and { id = place.id, name = place.name, region = place.region,
      latitude = place.latitude, longitude = place.longitude } or nil
  end

  -- Books shipping to one of the listed regions or any place by its id.
  function c:bookShipping(destinationId)
    if destinationId == 'home' then return self:book(self:homeDestination()) end
    return self:book(shipping.get(destinationId) or placeDestination(places.get(destinationId)))
  end

  -- Books shipping to any coordinates; the region is the nearest place's.
  function c:bookShippingTo(latitude, longitude)
    local point = { latitude = latitude, longitude = longitude }
    if not location.valid(point) then
      self.shippingFeedback = 'Those are not coordinates. Use latitude, longitude, like -16.19, -67.73.'
      return false
    end
    places.ensure(point)
    local near = places.nearest(point, 1)[1]
    return self:book({ id = 'coordinates', name = string.format('%.5f, %.5f', latitude, longitude),
      region = near and (near.metres < 50000 and ('near ' .. near.place.name .. ', ' .. near.place.region) or near.place.region) or 'somewhere remote',
      latitude = latitude, longitude = longitude })
  end

  -- The paid-shipping offer showing now, and the seconds until the next one.
  function c:currentOffer()
    return shipping.offer(self.now(), places.hardest())
  end

  -- Books the offer showing now. The fee is paid as usual and paid back by a delivery there.
  function c:bookOffer()
    local offer = self:currentOffer()
    if not offer then
      self.shippingFeedback = 'No offer right now.'
      return false
    end
    if not self:book({ id = offer.id, name = offer.name, region = offer.region,
      latitude = offer.latitude, longitude = offer.longitude }) then return false end
    self.booking.offer = true
    self.shippingFeedback = self.shippingFeedback .. ' ' .. offer.name .. ' pays it back when you deliver there.'
    return true
  end

  -- Finds places by name to ship to.
  function c:searchShipping(query)
    local found = places.search(query, shipping.SEARCH_RESULTS)
    self.shippingSearch = { query = query, results = {} }
    for _, place in ipairs(found) do self.shippingSearch.results[#self.shippingSearch.results + 1] = placeDestination(place) end
    self.shippingFeedback = #found == 0 and ('No town called ' .. tostring(query) .. '. Try the start of its name, or paste coordinates.') or nil
    return #found > 0
  end

  -- Books shipping to a destination: pay the fee, then teleport there with the coordinates.
  function c:book(destination, free)
    local here = self.lastSample
    local problem = self:shippingProblem()
    if not problem and not destination then problem = 'Pick a destination.' end
    if not problem and shipping.arrived(here, destination) then problem = destination.id == 'home' and 'You are already at your base.' or ('You are already in ' .. destination.name .. '.') end
    local fee = not problem and (free and 0 or shipping.fee(here, destination)) or nil
    if not problem and not self:spend(fee, 'shipping') then problem = 'Not enough money. Relocating to ' .. destination.name .. ' costs ' .. dollars(fee) .. '.' end
    if problem then
      self.shippingFeedback = problem
      return false
    end
    self.booking = { id = destination.id, name = destination.name, region = destination.region, fee = fee,
      latitude = destination.latitude, longitude = destination.longitude }
    self.bookingTeleportAt = nil
    self.shippingFeedback = 'Booked to ' .. destination.name .. ' for ' .. dollars(fee) .. '. Press Teleport there, or copy the coordinates into the BeamNG.Earth map.'
    self.diag:event('shipping_booked', destination.id .. ':' .. fee)
    return true
  end


  -- ===== Ship Day (multiplayer): see shipday.lua ==================================================================
  -- The ship in port, while this game's career is the server's.
  function c:shipDay()
    return self.mp and self.mp.state == 'server' and self.ship or nil
  end

  function c:atPort(town)
    local sample = self.lastSample
    if not town or not sample or not sample.valid then return false end
    local d = location.distance(sample, town)
    return d ~= nil and d <= shipday.AT_PORT_METRES
  end

  -- Why Go to port can't be pressed now, or nil when it can.
  function c:portTripProblem(ship, town)
    if not ship or not town then return 'No ship is in port right now.' end
    if self:atPort(town) then return 'You are at the port.' end
    if self.booking and self.booking.id == 'port' then return nil end
    return self:shippingProblem()
  end

  -- Go to port: a free relocation to the port's town (its centre, on land), and the teleport there, in one press.
  function c:goToPort()
    local ship = self:shipDay()
    local town = shipday.portTown(ship)
    local problem = self:portTripProblem(ship, town)
    if not problem and not self.booking then
      if not self:book({ id = 'port', name = town.name, region = town.region,
        latitude = town.latitude, longitude = town.longitude }, true) then problem = self.shippingFeedback end
    end
    if problem then
      self.shipFeedback = problem
      return false
    end
    local ok = self:teleportToBooking()
    self.shipFeedback = ok and ('Off to ' .. ship.port.name .. '. The terrain takes a few seconds to load.')
      or (self.shippingFeedback or 'BeamNG.Earth did not take the teleport.')
    return ok
  end

  -- ===== Relocate to a player (multiplayer) ======================================================================
  -- The Relocate tab lists the other players on the server by name and town. Picking one asks the server, which asks
  -- that player's game where it is; the answer comes back to this game only, and books the usual relocation (the same
  -- fee, an empty car, never on a job) to a spot LAND_BEHIND_METRES behind their car, and teleports there.
  M.FIND_WAIT_SECONDS = 10
  M.LAND_BEHIND_METRES = 20

  function c:otherPlayers()
    return self.mp and self.mp.state == 'server' and self.mp.players or nil
  end

  -- Asks where another player is, to relocate to them.
  function c:findPlayer(id)
    local who
    for _, p in ipairs(self:otherPlayers() or {}) do if p.id == id then who = p end end
    local problem = self:shippingProblem()
    if not problem and not who then problem = 'That player is not on the server any more.' end
    if not problem and self.finding then problem = 'Waiting for ' .. self.finding.name .. ' to answer.' end
    if problem then
      self.shippingFeedback = problem
      return false
    end
    self.finding = { id = id, name = who.name, at = self.clock }
    self.mp:find(id)
    self.shippingFeedback = 'Asking ' .. who.name .. ' where they are...'
    self.diag:event('find_player', tostring(id))
    return true
  end

  -- Their answer: book the relocation to them and teleport, or say why not.
  function c:playerFound(d)
    local f = self.finding
    if not f or type(d) ~= 'table' or tonumber(d.to) ~= f.id then return false end
    self.finding = nil
    local spot = d.ok == true and location.valid(d) and location.copy(d) or nil
    if not spot then
      self.shippingFeedback = d.why == 'off' and (f.name .. ' does not let other players relocate to them.')
        or d.why == 'gone' and (f.name .. ' is not on the server any more.')
        or (f.name .. ' is not driving their car right now. Try again in a moment.')
      return false
    end
    -- Never on top of their car: behind it, or to one side when its heading isn't known.
    local behind = location.finite(d.heading) and (d.heading + 180) % 360 or 180
    local land = location.destination(spot, behind, M.LAND_BEHIND_METRES) or spot
    if shipping.arrived(self.lastSample, land) then
      self.shippingFeedback = f.name .. ' is less than ' .. math.floor(shipping.ARRIVE_METRES / 1000) .. ' km away. Drive to them.'
      return false
    end
    places.ensure(land)
    local near = places.nearest(land, 1)[1]
    local booked = self:book({ id = 'player', name = f.name,
      region = near and (near.place.name .. ', ' .. near.place.region) or 'somewhere remote',
      latitude = land.latitude, longitude = land.longitude })
    if not booked then return false end
    local fee = self.booking.fee
    local ok = self:teleportToBooking()
    if ok then self.shippingFeedback = 'Off to ' .. f.name .. ' for ' .. dollars(fee) .. '. The terrain takes a few seconds to load.' end
    return ok
  end

  function c:watchFind()
    if self.finding and self.clock - self.finding.at > M.FIND_WAIT_SECONDS then
      self.shippingFeedback = self.finding.name .. '\'s game did not answer. Try again.'
      self.finding = nil
    end
  end

  -- Someone wants to relocate to this player: where the car is, unless it's turned off or the player is away from it.
  function c:answerLocate(ask)
    if not ask or not self.mp then return end
    local sample = self.lastSample
    if not self.mp:findable() then
      self.mp:here({ ask = ask.ask, ok = false, why = 'off' })
      return
    end
    if self.state ~= 'READY' or not self.arrived or self.hire or self.onFoot or type(sample) ~= 'table' or not sample.valid then
      self.mp:here({ ask = ask.ask, ok = false, why = 'away' })
      return
    end
    local heading = location.finite(sample.heading) and sample.heading or self.heading
    self.mp:here({ ask = ask.ask, ok = true, latitude = sample.latitude, longitude = sample.longitude, heading = heading })
    self:toast('info', 'A trucker is on the way', ask.name .. ' is relocating to you. Turn this off on the Relocate tab.', 8)
    self.diag:event('located', ask.name)
  end

  function c:setFindable(on)
    if not self.mp or self.mp.state ~= 'server' then return false end
    self.mp:setFindable(on == true)
    self.shippingFeedback = on and 'Other players can relocate to you.' or 'Other players can no longer relocate to you.'
    return true
  end

  -- The players on the Relocate tab, with roughly what it costs to reach each (from their town; the real fee is
  -- worked out from where they are when you press Join).
  function c:playersView(current, problem)
    local list = self:otherPlayers()
    if not list then return nil end
    local rows = {}
    for _, p in ipairs(list) do
      local fee = p.near and shipping.fee(current, p.near) or nil
      rows[#rows + 1] = { id = p.id, name = p.name, town = p.town, region = p.region, doing = p.doing, fee = fee,
        distanceMetres = p.near and location.distance(current, p.near) or nil,
        allowed = problem == nil and not self.finding and (fee == nil or self:canAfford(fee)) }
    end
    return { list = rows, findable = self.mp:findable(), finding = self.finding and self.finding.name or nil }
  end

  -- How many units of container cargo the car (and a hitched trailer) takes, and what one container pays.
  function c:containerQuote(box)
    local good = goods.get(shipday.GOOD)
    local units, slots, kg, inTrailer = trailers.fits(self:space(), self:trailerSpace(), good)
    local pay, toll = self:applyToll(shipday.pay(box, units, self:baseShareFunction()), places.get(box.to))
    return { units = units, slots = slots, kg = kg, trailerUnits = inTrailer, pay = pay, toll = toll }
  end

  -- Why a container can't be taken now, or nil when it can.
  function c:containerProblem(ship, town)
    if not ship or not town then return 'No ship is in port right now.' end
    if not self:atPort(town) then return 'Go to the port at ' .. town.name .. ' to load a container.' end
    local problem = self:tradeProblem(town)
    if problem then return problem end
    if self.load then return 'Deliver or abandon your job first.' end
    if self.shipClaim then return 'Waiting for the dock to answer.' end
    return nil
  end

  -- Asks the server for a container. It's loaded when the server says it's this player's (claimAnswered), with the
  -- share of a full load picked on the slider (a percentage, 100 when not given), like a job from the board.
  function c:takeContainer(n, share)
    local ship = self:shipDay()
    local town = shipday.portTown(ship)
    local problem = self:containerProblem(ship, town)
    local box = not problem and shipday.container(ship, n) or nil
    if not problem and not box then problem = 'There is no container ' .. tostring(n) .. ' on this ship.' end
    if not problem and ship.states[n] then problem = 'Container ' .. n .. ' is already taken.' end
    if not problem and self:containerQuote(box).units == 0 then
      local good = goods.get(shipday.GOOD)
      problem = 'Not enough cargo space: container cargo takes ' .. good.slots .. ' slots and '
        .. string.format('%g', good.kg) .. ' kg a unit. Fit a cargo box in the parts menu.'
    end
    if problem then
      self.shipFeedback = problem
      return false
    end
    self.shipClaim = { ship = ship.ship, n = n, at = self.clock, share = share or 100 }
    self.mp:claim(ship.ship, n)
    self.shipFeedback = 'Asking the dock for container ' .. n .. '...'
    return true
  end

  -- The server's answer to a claim: the container is loaded, or someone else got it first.
  function c:claimAnswered(d)
    local claim = self.shipClaim
    if type(d) ~= 'table' or not claim or d.ship ~= claim.ship or d.n ~= claim.n then return end
    self.shipClaim = nil
    local ship = self:shipDay()
    if d.ok ~= true then
      self.shipFeedback = 'Someone else got container ' .. claim.n .. ' first. Pick another.'
      return
    end
    local town = ship and ship.ship == claim.ship and shipday.portTown(ship) or nil
    local box = town and shipday.container(ship, claim.n)
    local problem = not box and 'That ship has sailed.' or self:containerProblem(ship, town)
    local quote = not problem and self:containerQuote(box) or nil
    if not problem and quote.units == 0 then problem = 'Not enough cargo space.' end
    if problem then
      -- Given back, so someone else can take it.
      self.mp:release(claim.ship, claim.n)
      self.shipFeedback = problem
      return
    end
    local good = goods.get(shipday.GOOD)
    quote.units, quote.pay = jobs.share(quote.units, quote.pay, claim.share or 100)
    self.load = { good = good.id, units = quote.units, slots = quote.units * good.slots, kg = quote.units * good.kg,
      pay = quote.pay, from = box.from, to = box.to, drivenKm = 0, ship = { ship = claim.ship, n = claim.n }, toll = quote.toll }
    if (quote.trailerUnits or 0) > 0 then self.load.trailerUnits = math.min(quote.trailerUnits, quote.units) end
    self.abandonArmed = false
    self:applyWeight()
    self:gpsToJob()
    local to = places.get(box.to)
    self.shipFeedback = 'Container ' .. claim.n .. ' is yours: take it to ' .. to.name .. ' for ' .. dollars(quote.pay) .. '.'
    self.diag:event('container_taken', string.format('ship %d #%d -> %s for %d', claim.ship, claim.n, box.to, quote.pay))
    self:autoSaveSoon('your container')
  end

  -- The server never answered: the claim is dropped, and the player can try again.
  function c:watchClaim()
    if self.shipClaim and self.clock - self.shipClaim.at > shipday.CLAIM_WAIT_SECONDS then
      self.shipClaim = nil
      self.shipFeedback = 'The dock did not answer. Try again.'
    end
  end

  -- Ship Day on the Town tab: the ship, its port, the time left and every container.
  function c:shipView(current)
    local ship = self:shipDay()
    if not ship then return nil end
    local town = shipday.portTown(ship)
    if not town then return nil end
    local atPort = self:atPort(town)
    local takeProblem = self:containerProblem(ship, town)
    local tripProblem = self:portTripProblem(ship, town)
    local units
    local list, free = {}, 0
    for _, box in ipairs(shipday.containers(ship)) do
      local st = ship.states[box.n]
      units = units or self:containerQuote(box).units
      local pay, toll = self:applyToll(shipday.pay(box, units, self:baseShareFunction()), places.get(box.to))
      local state = st and (st.mine and st.state ~= 'delivered' and 'mine' or st.state) or 'free'
      if state == 'free' then free = free + 1 end
      local to = places.get(box.to)
      list[#list + 1] = { n = box.n, to = to and to.name or box.to, region = to and to.region or nil,
        distanceMetres = box.km * 1000, pay = pay, tollTo = toll and toll.owner, state = state, by = st and st.by or nil,
        allowed = state == 'free' and takeProblem == nil and units > 0 }
    end
    local held = self.load and self.load.ship
    return {
      name = ship.name, port = ship.port.name, region = ship.port.region, town = town.name,
      secondsLeft = math.max(0, ship.left - (self.clock - (self.shipAt or self.clock))),
      total = ship.containers, free = free, atPort = atPort, containers = list,
      goAllowed = tripProblem == nil, goProblem = not atPort and tripProblem or nil,
      problem = atPort and takeProblem or nil, units = units or 0, unitKg = goods.get(shipday.GOOD).kg,
      carrying = held and held.ship == ship.ship and held.n or nil,
      feedback = self.shipFeedback,
    }
  end

  -- Asks Earth to take the car to the booked destination, as pasting its coordinates into Earth's
  -- map does. Landing there uses up the booking, seen in teleported.
  function c:teleportToBooking()
    local b = self.booking
    if not b or self.error or self.state ~= 'READY' or not self.adapter.teleport then return false end
    if self.onFoot then
      self.shippingFeedback = ON_FOOT
      return false
    end
    local ok, why, detail = self.adapter:teleport(b, 'Worldwide Trucking: ' .. b.name)
    self.diag:event('teleport_to_booking', ok and b.id or (tostring(why) .. ':' .. tostring(detail or '')), ok and 'I' or 'W')
    self.bookingTeleportAt = ok and self.clock or nil
    -- On the way, the HUD says so under the button for as long as the button rests.
    self.shippingFeedback = not ok and 'BeamNG.Earth did not take the teleport. Copy the coordinates into its map instead.' or nil
    return ok == true
  end

  -- Cancels a booking not yet used and refunds its fee.
  function c:cancelShipping()
    if not self.booking or not self.profile or self.error then return false end
    self:addMoney(self.booking.fee)
    self.shippingFeedback = 'Booking cancelled. ' .. dollars(self.booking.fee) .. ' refunded.'
    self.diag:event('shipping_cancelled', self.booking.id)
    self.booking, self.bookingTeleportAt = nil, nil
    return true
  end

  -- Road punctures. Each stretch driven has a small chance of bursting a tyre (see punctures.lua):
  -- more at speed, double off road, never within GAP_KM of the last one or SAFE_FINISH_METRES of
  -- the drop-off. The tyre repair is added to the repair, which mends it.
  function c:roadPuncture(sample, metres, dt)
    if not self.punctures or self.paused() or self.pendingParts or self.pendingCar then return end
    local progression = self.profile.progression
    if progression.lastPunctureKm and progression.totalDistanceKm - progression.lastPunctureKm < punctures.GAP_KM then return end
    local goal = self.load and (self.load.business or self.load.to and places.get(self.load.to))
    local left = goal and location.distance(sample, goal)
    if left and left <= punctures.SAFE_FINISH_METRES then return end
    if not self.offRoadCheckedAt or self.clock - self.offRoadCheckedAt >= punctures.OFF_ROAD_CHECK_SECONDS then
      local ok, offRoad = pcall(self.punctures.offRoad, self.punctures)
      self.offRoad, self.offRoadCheckedAt = ok and offRoad == true, self.clock
    end
    if self.random() >= punctures.chance(metres, metres / dt * 3.6, self.offRoad) then return end
    local ok, why, detail = self.punctures:burst()
    if not ok then
      self.diag:event('puncture_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return
    end
    progression.lastPunctureKm = progression.totalDistanceKm
    self.punctureDamage = self.punctureDamage + PUNCTURE_DAMAGE
    self.quote = nil
    self:showFlash('puncture', 'PUNCTURE!', 'A tyre burst on the road. Repair it on the Garage tab.')
    self.diag:event('puncture', string.format('%.1f km%s', progression.totalDistanceKm, self.offRoad and ' off road' or ''))
  end

  function c:observe(sample, dt)
    self.lastSample = sample
    self.diag:event('earth', tostring(sample.reason or 'available') .. ':' .. tostring(sample.detail or sample.source or ''))
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration'); return end
    if self.error then self:transition('ERROR', self.error); return end
    if not sample.valid or not location.valid(sample) then
      self:interrupt(sample.reason or 'position_invalid'); return
    end
    -- The places around the player, wherever in the world they are.
    places.ensure(sample)
    -- Any valid vehicle position starts the session: saving and driving work wherever the vehicle is.
    if not self.profile then
      self.profile = persistence.newProfile(self.creationBase, sample, sample.vehicle, STARTING_MONEY)
      self.profile.atStart = true
      self.unsavedBase = location.copy(self.profile.base)
      self.diag:event('profile_initialised', 'default (in memory, not yet saved)')
    end
    self.sessionVerified = true
    -- Arriving within the radius of the resume point, usually by teleporting there from the map,
    -- confirms the player is back where they left off.
    self:checkArrival(sample)
    if self.arrived then self:drive(sample, dt) end
    self:transition('READY', 'verified')
  end

  function c:checkArrival(sample)
    if not self.arrived and self.startupTarget then
      local away = location.distance(sample, self.startupTarget)
      if away and away <= self.configuration.resumeRadiusMetres then
        self.arrived = true
        self.odometer:reset()
        if self.mode == 'start' then
          local town = self:startTown()
          self:showFlash('delivered', self:named('Welcome to ' .. (town or 'your start')):upper(),
            'Your starter car needs a radiator: press Buy parts on the Garage tab, fit one, then pay there.')
        else
          self:showFlash('delivered', self:named('Welcome back'):upper(), 'You are where you last saved.'
            .. (self.refunded and (' Buying cargo has been replaced by job boards, so the cargo you bought was taken off and its '
              .. dollars(self.refunded) .. ' refunded. Find a job on the Town tab.') or ''))
        end
        self.diag:event('arrived', string.format('%.1f m', away))
      end
    end
  end

  -- Start here: on a new game, makes wherever the player stands their start, and starts there. A
  -- new game later starts there again. Like everything else, it is kept by Save.
  function c:startHereAllowed()
    return self.state == 'READY' and self.mode == 'start' and not self.arrived and not self.error and self.profile ~= nil
  end

  function c:startHere()
    if not self:startHereAllowed() then return false end
    local fresh = self.adapter:sample()
    if not fresh.valid or not location.valid(fresh) then
      self.lastSample = fresh
      self:interrupt(fresh.reason or 'position_invalid')
      self.diag:event('start_here_rejected', fresh.reason or 'position_invalid', 'W')
      return false
    end
    places.ensure(fresh)
    local spot = location.copy(fresh)
    self.profile.base, self.profile.resume = location.copy(spot), location.copy(spot)
    self.creationBase, self.startupTarget, self.unsavedBase = location.copy(spot), location.copy(spot), location.copy(spot)
    self.teleportAskedAt, self.teleportFeedback = nil, nil
    self.lastSample = fresh
    self.diag:event('start_here', string.format('%.8f,%.8f', spot.latitude, spot.longitude))
    self:checkArrival(fresh)
    return self.arrived
  end

  -- Where the player is: the place whose arrival circle they are in, once arrived.
  function c:here()
    local sample = self.lastSample
    if self.state ~= 'READY' or not self.arrived or not sample or not sample.valid then return nil end
    return places.at(sample)
  end

  -- Why taking or delivering a job at this place is not possible now, or nil when it is.
  function c:tradeProblem(place)
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived then return 'Jobs are unavailable right now.' end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    if not place then return 'Drive into a town to find a job.' end
    if not self.odometer:stopped() then return 'Stop the car to take or deliver a job.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.trailerShop then return 'Finish with your trailer parts on the Garage tab first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from, or book a relocation on the Relocate tab.' end
    return nil
  end

  -- The job board of a place: its jobs, seeded by how many jobs the player has done, in the band
  -- picked on the Distance filter.
  function c:board(place)
    local progression = self.profile and self.profile.progression
    return jobs.board(place, progression and progression.jobsDone or 0, self.needs, self.now(), self.jobDistance)
  end

  -- The Distance filter: 'short', 'medium' or 'long' sends every town job that far; anything else
  -- shows the usual mix. The HUD keeps the choice and sends it again when it opens.
  function c:setJobDistance(distance)
    self.jobDistance = jobs.DISTANCES[distance] and distance or nil
    return true
  end

  -- What a job on the board pays the player's car now: how many units of its good fit, and the pay.
  function c:jobQuote(job)
    local good = goods.get(job.good)
    -- A hitched trailer is loaded first, then the car. A dangerous contract only loads the car: its
    -- teleport to the start leaves the trailer behind.
    local units, slots, kg, inTrailer = trailers.fits(self:space(), not job.contract and self:trailerSpace() or nil, good)
    -- Ends inside the player's base circle pay more (magnate.lua).
    local quote = jobs.quote(job, units, self.needs, self.now(), self:baseShareFunction())
    quote.units, quote.slots, quote.kg, quote.trailerUnits = units, slots, kg, inTrailer
    -- Delivering in someone else's turf pays them the toll: at the drop-off town, or for an off-road drop the town it
    -- was taken in (what the server checks). Dangerous contracts pay none.
    if not job.contract then
      quote.pay, quote.toll = self:applyToll(quote.pay, places.get(job.drop and job.from or job.to))
    end
    return quote
  end

  -- Takes a job from the board here: the car is filled with its good, or the share of a full load
  -- picked on the slider (a percentage, 100 when not given), and its pay is locked in.
  function c:takeJob(jobId, share)
    share = share or 100
    local place = self:here()
    local problem = self:tradeProblem(place)
    if not problem and self.load then problem = 'You already have a job. Deliver it or abandon it first.' end
    local job
    if not problem then
      for _, j in ipairs(self:board(place)) do if not job and j.id == jobId then job = j end end
      if not job then problem = 'That job is no longer on the board.' end
    end
    local quote = job and not problem and self:jobQuote(job) or nil
    local good = job and goods.get(job.good)
    if quote and quote.units == 0 and good.kind == 'fluid' then
      problem = good.name .. ' needs a fluid tank. Drive a tanker, or press Buy parts on the Garage tab, fit a Cargo Load fluid tank and pay for it there.'
    elseif quote and quote.units == 0 then
      problem = 'Not enough cargo space or payload for ' .. good.name:lower() .. ': one unit takes ' .. good.slots
        .. (good.slots == 1 and ' slot' or ' slots') .. ' and ' .. string.format('%g', good.kg) .. ' kg. Fit a cargo box in the parts menu.'
    end
    if not problem and job.contract and not self:canAfford(contracts.FEE) then
      problem = 'Not enough money. The relocation to the start of a dangerous contract costs ' .. dollars(contracts.FEE) .. '.'
    end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local destination = places.get(job.to)
    local units, pay = jobs.share(quote.units, quote.pay, share)
    quote.units, quote.slots, quote.kg, quote.pay = units, units * good.slots, units * good.kg, pay
    self.load = { good = good.id, units = quote.units, slots = quote.slots, kg = quote.kg, pay = quote.pay,
      from = place.id, to = destination.id, drivenKm = 0, drop = location.copy(job.drop), toll = quote.toll }
    -- The trailer is filled first; a part load leaves the car empty before the trailer.
    local inTrailer = math.min(quote.trailerUnits or 0, units)
    if inTrailer > 0 then self.load.trailerUnits = inTrailer end
    self.abandonArmed = false
    if job.contract then return self:takeContract(job, good, quote) end
    self:applyWeight()
    if job.drop then
      -- No GPS: an off-road drop is found by the arrow on the Route tab, whose card says so. The job
      -- card above the tabs already shows the load, where it goes and the pay, so no message repeats it.
      self.tradeFeedback = nil
      self.diag:event('job_taken', string.format('%s x%d %s -> drop %.5f,%.5f for %d', good.id, quote.units, place.id,
        job.drop.latitude, job.drop.longitude, quote.pay))
      return true
    end
    -- The job card shows the load and the pay; a message is only needed when the GPS could not be set.
    self.tradeFeedback = nil
    -- A real business in that town, when one was found before; otherwise the HUD looks for one.
    local known = self:businesses()[business.key(destination.id, good.id)]
    if known and not known.none then self.load.business = business.clean(known, destination) end
    self:gpsToJob()
    self.diag:event('job_taken', string.format('%s x%d %s -> %s for %d', good.id, quote.units, place.id, destination.id, quote.pay))
    return true
  end

  -- Sets the GPS to the job's drop-off: its business when it has one, else the middle of its town.
  function c:gpsToJob()
    local load = self.load
    if not load or load.drop or not self.configuration.autoGps or not self.adapter.setDestination then return false end
    local town = places.get(load.to)
    local spot = load.business or town
    local name = load.business and (load.business.name .. ', ' .. town.name) or town.name
    local ok, why = self.adapter:setDestination(spot, name)
    self.gpsTown, self.gpsContract, self.gpsFeedback = ok and not load.business and town.id or nil, nil, nil
    if not ok then self.tradeFeedback = 'Set the GPS yourself: copy the drop-off coordinates on the Route tab.' end
    self.diag:event('gps', ok and (load.business and ('business:' .. town.id) or town.id) or tostring(why), ok and 'I' or 'W')
    return ok == true
  end

  -- The businesses found so far, read from their file the first time.
  function c:businesses()
    if not self.businessList then
      local saved
      if deps.io then
        local ok, value = pcall(function() return deps.io.exists(BUSINESS_FILE) and deps.io.read(BUSINESS_FILE) end)
        saved = ok and value or nil
      end
      self.businessList = business.remembered(saved)
    end
    return self.businessList
  end

  function c:rememberBusiness(key, entry)
    business.remember(self:businesses(), key, entry, self.now())
    if not deps.io then return end
    pcall(function()
      deps.io.mkdir('/settings/earthFreight')
      deps.io.write(BUSINESS_FILE, { towns = self.businessList })
    end)
  end

  -- What the HUD should look up: the town job's town and good, while no business is known for it.
  function c:businessWanted()
    local load = self.load
    if not load or load.drop or load.business then return nil end
    local town, good = places.get(load.to), goods.get(load.good)
    local key = business.key(town.id, good.id)
    if self:businesses()[key] then return nil end
    return { key = key, town = town.name, latitude = town.latitude, longitude = town.longitude, good = good.id,
      metres = business.SEARCH_METRES, widerMetres = business.WIDER_METRES }
  end

  -- The HUD found a business for the job's town: it becomes the drop-off. name and kind come
  -- percent-encoded. Only taken for the town job on board, and only while it has none.
  function c:setBusiness(key, name, kind, latitude, longitude)
    local wanted = self:businessWanted()
    if not wanted or key ~= wanted.key then return false end
    local town = places.get(self.load.to)
    local found = business.clean({ name = business.decode(name), kind = kind, latitude = latitude, longitude = longitude }, town)
    if not found then
      self.diag:event('business', 'refused:' .. wanted.key, 'W')
      return false
    end
    self:rememberBusiness(wanted.key, business.clean(found))
    self.load.business = found
    self:gpsToJob()
    self.diag:event('business', wanted.key .. ':' .. found.kind)
    return true
  end

  -- The HUD looked and found nothing that fits: the town's usual drop-off stays, and is remembered.
  function c:noBusiness(key)
    local wanted = self:businessWanted()
    if not wanted or key ~= wanted.key then return false end
    self:rememberBusiness(wanted.key, { none = true })
    self.diag:event('business', 'none:' .. wanted.key)
    return true
  end

  -- Why the job cannot be delivered at its business now (nil when it can).
  function c:businessProblem()
    local sample, load = self.lastSample, self.load
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not sample or not sample.valid then
      return 'Deliveries are unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    local away = location.distance(sample, load.business)
    if not away or away > business.RADIUS then
      return 'Drive to ' .. load.business.name .. ' and stop within ' .. business.RADIUS .. ' m of it.'
    end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from, or book a relocation on the Relocate tab.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if self.trailerShop then return 'Finish with your trailer parts on the Garage tab first.' end
    local trailerProblem = self:trailerDeliveryProblem()
    if trailerProblem then return trailerProblem end
    local needed = jobs.drivenNeeded(places.get(load.from), places.get(load.to))
    if load.drivenKm * 1000 < needed then
      return 'Drive it here: you have driven ' .. string.format('%.1f', load.drivenKm) .. ' km of the '
        .. string.format('%.1f', needed / 1000) .. ' km this job needs.'
    end
    if not self.odometer:stopped() then return 'Stop the truck to deliver.' end
    return nil
  end

  -- Takes a dangerous contract: pays the relocation and asks Earth to teleport the car to the start.
  function c:takeContract(job, good, quote)
    local section = contracts.get(job.contract)
    self:spend(contracts.FEE, 'contract')
    self.load.contract, self.load.started, self.load.fee = section.id, false, contracts.FEE
    self:applyWeight()
    self.diag:event('job_taken', string.format('%s x%d %s -> contract %s for %d', good.id, quote.units, job.from, section.id, quote.pay))
    -- The job card and the contract card on the Route tab show the rest; a message is only needed
    -- when Earth is not taking the car there now (teleportToContract may already have said why).
    self.tradeFeedback = nil
    if not self:teleportToContract() and not self.tradeFeedback then
      self.tradeFeedback = 'Press Teleport to the start on the Route tab, or copy its coordinates into the BeamNG.Earth map.'
    end
    return true
  end

  -- GPS on the Route tab's Nearby list: sets BeamNG.Earth's GPS to the middle of a town, where
  -- it counts as being in town. A job's own GPS is set again with the button on its own row.
  function c:gpsToTown(placeId)
    local place = placeId and places.get(placeId)
    if not place or not self.adapter.setDestination or self.state ~= 'READY' or not self.arrived or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local ok, why = self.adapter:setDestination(place, place.name)
    self.diag:event('gps', ok and ('town:' .. place.id) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract = ok and place.id or nil, nil
    self.gpsFeedback = ok and ('The GPS is set to ' .. place.name .. '.')
      or ('Could not set the GPS. Paste ' .. coordinates(place) .. ' into the BeamNG.Earth map instead.')
    return ok == true
  end

  -- GPS on a dangerous contract on the job board: sets the GPS to the start of its road, so the
  -- player can see where it is before paying for the relocation.
  function c:gpsToContract(contractId)
    local section = contractId and contracts.get(contractId)
    if not section or not self.adapter.setDestination or self.state ~= 'READY' or not self.arrived or self.hire then
      self.gpsFeedback = 'The GPS cannot be set right now.'
      return false
    end
    local ok, why = self.adapter:setDestination(section.start, section.name .. ' start')
    self.diag:event('gps', ok and ('contract_start:' .. section.id) or tostring(why), ok and 'I' or 'W')
    self.gpsTown, self.gpsContract = nil, ok and section.id or nil
    self.gpsFeedback = ok and ('The GPS is set to the start of ' .. section.name .. ', ' .. section.region .. '.')
      or ('Could not set the GPS. Paste ' .. coordinates(section.start) .. ' into the BeamNG.Earth map instead.')
    return ok == true
  end

  -- Sets the GPS to a dangerous contract's finish. Returns whether it was set.
  function c:gpsToFinish(section)
    if not self.adapter.setDestination then return false end
    local ok, why = self.adapter:setDestination(section.finish, section.name .. ' finish')
    if ok then self.gpsTown, self.gpsContract, self.gpsFeedback = nil, nil, nil end
    self.diag:event('gps', ok and ('contract:' .. section.id) or tostring(why), ok and 'I' or 'W')
    return ok == true
  end

  -- Asks Earth to take the car to the start of the dangerous contract on board.
  function c:teleportToContract()
    local section = self.load and self.load.contract and not self.load.started and contracts.get(self.load.contract)
    if not section or self.error or self.state ~= 'READY' or not self.adapter.teleport then return false end
    if self.hire or self.onFoot then
      self.tradeFeedback = self.hire and self:awayText() or ON_FOOT
      return false
    end
    local ok, why, detail = self.adapter:teleport(section.start, 'Worldwide Trucking: ' .. section.name)
    self.diag:event('teleport_to_contract', ok and section.id or (tostring(why) .. ':' .. tostring(detail or '')), ok and 'I' or 'W')
    self.contractTeleportAt = ok and self.clock or nil
    if not ok then
      self.tradeFeedback = 'BeamNG.Earth did not take the teleport. Copy the start coordinates on the Route tab into its map instead.'
    end
    return ok == true
  end

  -- Why the job cannot be delivered here (nil when it can).
  function c:deliveryProblem(place)
    if not self.load or not place then return 'You have no job to deliver.' end
    if place.id ~= self.load.to then return nil end
    if self.load.business then return self:businessProblem() end
    local trailerProblem = self:trailerDeliveryProblem()
    if trailerProblem then return trailerProblem end
    local needed = jobs.drivenNeeded(places.get(self.load.from), place)
    if self.load.drivenKm * 1000 < needed then
      return 'Drive it here: you have driven ' .. string.format('%.1f', self.load.drivenKm) .. ' km of the '
        .. string.format('%.1f', needed / 1000) .. ' km this job needs.'
    end
    return nil
  end

  -- Why an off-road drop cannot be delivered where the car is now (nil when it can).
  function c:dropProblem()
    local sample, load = self.lastSample, self.load
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not sample or not sample.valid then
      return 'Deliveries are unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    local section = load.contract and contracts.get(load.contract)
    if section and not load.started then return 'Teleport to the start of ' .. section.name .. ' first.' end
    local away = location.distance(sample, load.drop)
    if section and (not away or away > contracts.FINISH_RADIUS) then
      return 'Drive to the finish and stop within ' .. contracts.FINISH_RADIUS .. ' m of it.'
    end
    local radius = load.beacon and beacons.RADIUS or jobs.DROP_RADIUS
    if not away or away > radius then
      return 'Drive to the drop spot and stop within ' .. radius .. ' m of it.'
    end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from, or book a relocation on the Relocate tab.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    local trailerProblem = self:trailerDeliveryProblem()
    if trailerProblem then return trailerProblem end
    local needed = jobs.drivenNeeded(section and section.start or load.pickup or places.get(load.from), load.drop)
    if section and section.driveKm then needed = math.max(needed, section.driveKm * 1000) end
    if load.drivenKm * 1000 < needed then
      return 'Drive it here: you have driven ' .. string.format('%.1f', load.drivenKm) .. ' km of the '
        .. string.format('%.1f', needed / 1000) .. ' km this job needs.'
    end
    if not self.odometer:stopped() then return 'Stop the car to deliver.' end
    return nil
  end

  -- Delivers an off-road drop at its spot, paid in full. No town's need changes.
  function c:deliverDrop()
    local problem = self:dropProblem()
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local load, good = self.load, goods.get(self.load.good)
    self:addMoney(load.pay)
    -- A delivered dangerous contract's road is counted for the career page (it stays on the boards).
    if load.contract then
      local progression = self.profile.progression
      progression.contractsDone = progression.contractsDone or {}
      local listed = false
      for _, id in ipairs(progression.contractsDone) do listed = listed or id == load.contract end
      if not listed then table.insert(progression.contractsDone, load.contract) end
    end
    self:finishJob()
    local refund = ''
    if self.offer and shipping.offerPays(load.drop, self.offer) then
      self:addMoney(self.offer.fee)
      refund = ' ' .. self.offer.name .. ' paid back your ' .. dollars(self.offer.fee) .. ' relocation.'
      self.diag:event('offer_paid', self.offer.name .. ':' .. self.offer.fee)
      self.offer = nil
    end
    local section = load.contract and contracts.get(load.contract)
    -- An off-road drop counts for the turf of the town it was taken in, at both ends.
    local town = not load.beacon and not section and places.get(load.from) or nil
    self:reportDelivery(load.beacon and 'beacon' or (section and 'contract' or 'drop'), not load.beacon and good or nil,
      load.units, nil, section and section.name or nil, load.pay, townEnds(town, town), load.toll)
    if load.beacon then
      self:showFlash('delivered', 'DELIVERED: +' .. dollars(load.pay), 'Dropped off. Nobody saw a thing, and nobody asked.'
        .. refund)
      self.tradeFeedback = nil
      self:autoSaveSoon('your delivery')
      self.diag:event('job_delivered', 'beacon for ' .. load.pay)
      return true
    end
    self:showFlash('delivered', 'DELIVERED: +' .. dollars(load.pay), amount(good, load.units)
      .. (section and (' over ' .. section.name .. '. ' .. self:named('You made it') .. '.') or (' dropped off road. ' .. self:named('Nice driving') .. '.'))
      .. tollLine(load) .. refund)
    self.tradeFeedback = nil
    self:autoSaveSoon('your delivery')
    self.diag:event('job_delivered', string.format('%s x%d -> drop for %d', good.id, load.units, load.pay))
    return true
  end

  -- Delivers the job at its drop-off: paid in full, and the town needs that good a little less.
  function c:deliver()
    if self.load and self.load.drop then return self:deliverDrop() end
    local place, problem
    if self.load and self.load.business then
      -- At a business the truck may be past the edge of town: the spot is what counts.
      place = places.get(self.load.to)
      problem = self:businessProblem()
    else
      place = self:here()
      problem = self:tradeProblem(place)
      if not problem and not self.load then problem = 'You have no job to deliver.' end
      if not problem and place.id ~= self.load.to then problem = 'This job goes to ' .. places.get(self.load.to).name .. '.' end
      if not problem then problem = self:deliveryProblem(place) end
    end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local load, good = self.load, goods.get(self.load.good)
    self:addMoney(load.pay)
    jobs.delivered(self.needs, place, good, self.now())
    self:finishJob()
    local from = places.get(load.from)
    if load.ship and self.mp then
      self.mp:shipDelivered(load.ship.ship, load.ship.n, place.name, load.pay, townEnds(from, place), load.toll and load.toll.amount or nil)
    else
      self:reportDelivery('job', good, load.units, from and from.name or nil, place.name, load.pay, townEnds(from, place), load.toll)
    end
    local refund = ''
    if self.offer and shipping.offerPays(place, self.offer) then
      self:addMoney(self.offer.fee)
      refund = ' ' .. self.offer.name .. ' paid back your ' .. dollars(self.offer.fee) .. ' relocation.'
      self.diag:event('offer_paid', self.offer.name .. ':' .. self.offer.fee)
      self.offer = nil
    end
    self:showFlash('delivered', 'DELIVERED: +' .. dollars(load.pay), amount(good, load.units) .. ' to '
      .. (load.business and (load.business.name .. ', ') or '') .. place.name
      .. '. ' .. self:named('Nice driving') .. '.' .. tollLine(load) .. refund)
    self.tradeFeedback = nil
    self:autoSaveSoon('your delivery')
    self.diag:event('job_delivered', string.format('%s x%d -> %s for %d', good.id, load.units, place.id, load.pay))
    return true
  end

  -- Clears the job and its weight; the boards reshuffle.
  function c:finishJob()
    local progression = self.profile.progression
    progression.jobsDone = (progression.jobsDone or 0) + 1
    self.load, self.abandonArmed = nil, false
    self:applyWeight()
  end

  -- Cancels the job: the abandon fee is charged, or all the money if there is less. Returns the fee.
  -- A dangerous contract abandoned before its start gives back the relocation fee first.
  function c:dropJob(why)
    local load = self.load
    if why == 'abandoned' and load.contract and not load.started and (load.fee or 0) > 0 then self:addMoney(load.fee) end
    local fee = math.min(jobs.ABANDON_FEE, self.profile.progression.balance)
    if fee > 0 then self:spend(fee, 'abandon') end
    self.diag:event('job_abandoned', tostring(why) .. ':' .. self.load.good .. ':' .. fee)
    if load.ship and self.mp then self.mp:release(load.ship.ship, load.ship.n) end
    self:finishJob()
    return fee
  end

  -- Abandons the job anywhere, for the abandon fee. Asks once first.
  function c:abandonJob()
    if not self.load or not self.profile or self.error then return false end
    if not self.abandonArmed then
      self.abandonArmed = true
      local refund = self.load.contract and not self.load.started and (self.load.fee or 0) > 0
      self.tradeFeedback = 'Press Confirm abandon to give up this job. It costs ' .. dollars(jobs.ABANDON_FEE)
        .. (refund and (', and your ' .. dollars(self.load.fee) .. ' relocation is paid back.') or '.')
      return false
    end
    local fee = self:dropJob('abandoned')
    self.tradeFeedback = 'Job abandoned' .. (fee > 0 and (' for ' .. dollars(fee)) or '') .. '.'
    return true
  end

  -- Why the beacon's package cannot be picked up now, or nil when it can.
  function c:beaconProblem()
    local sample, b = self.lastSample, self.beacon
    if not b then return 'There is no beacon.' end
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not sample or not sample.valid then
      return 'Pickups are unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return ON_FOOT end
    if self.load then return 'Deliver or abandon your job first. The package will wait until the beacon goes quiet.' end
    local away = location.distance(sample, b.pickup)
    if not away or away > beacons.RADIUS then return 'Drive to the beacon and stop within ' .. beacons.RADIUS .. ' m of it.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from, or book a relocation on the Relocate tab.' end
    if self.pendingParts or self.pendingCar then return 'Settle your garage bill first.' end
    if not self.odometer:stopped() then return 'Stop the car to pick it up.' end
    return nil
  end

  -- Picks up the beacon's package: a job with no weight, delivered off road at the beacon's drop
  -- like an off-road drop, for beacons.PAY. Its towns are the nearest one, as for a saved job.
  function c:pickUpBeacon()
    local problem = self:beaconProblem()
    local b = self.beacon
    local nearest = not problem and places.nearest(b.pickup, 1)[1]
    if not problem and not nearest then problem = 'Pickups are unavailable right now.' end
    if problem then
      self.tradeFeedback = problem
      return false
    end
    local away = location.distance(b.pickup, b.drop)
    self.load = { good = 'package', units = 1, slots = 1, kg = 0, pay = beacons.PAY, from = nearest.place.id,
      to = nearest.place.id, drivenKm = 0, drop = location.copy(b.drop), pickup = location.copy(b.pickup), beacon = true }
    self.beacon, self.beaconArmed, self.abandonArmed = nil, false, false
    self:applyWeight()
    self.tradeFeedback = 'Picked up: ' .. beacons.line(b.line):lower():gsub('%.$', '') .. '. Take it '
      .. string.format('%.1f', away / 1000) .. ' km to the ' .. location.compassPoint(location.bearing(b.pickup, b.drop))
      .. ', off road: follow the arrow and stop within ' .. beacons.RADIUS .. ' m of the drop. It pays ' .. dollars(beacons.PAY)
      .. '. A crash costs ' .. dollars(beacons.INSURANCE_FEE) .. ' insurance and loses it.'
    self.diag:event('beacon_picked_up', string.format('%.5f,%.5f', b.drop.latitude, b.drop.longitude))
    return true
  end

  -- Ignores the beacon: it goes, for nothing. Asks once first.
  function c:ignoreBeacon()
    if not self.beacon then return false end
    if not self.beaconArmed then
      self.beaconArmed = true
      self.tradeFeedback = 'Press Confirm to ignore the beacon. It costs nothing, and it is gone for good.'
      return false
    end
    self.beacon, self.beaconArmed = nil, false
    self.tradeFeedback = 'Beacon ignored.'
    self.diag:event('beacon_ignored', '')
    return true
  end

  -- Counts down a waiting beacon while the game runs; it goes quiet when its time is up.
  function c:watchBeacon(dt)
    local b = self.beacon
    if not b or self.state ~= 'READY' or not self.arrived or self.paused() then return end
    b.left = math.max(0, b.left - dt)
    if b.left > 0 then return end
    self.beacon, self.beaconArmed = nil, false
    self:showFlash('cancelled', 'BEACON WENT QUIET', 'Nobody picked up the package in time. Keep flying to find another.')
    self.diag:event('beacon_expired', '')
  end

  -- The beacon waiting, as the HUD shows it from where the player is.
  function c:beaconView(current)
    local b = self.beacon
    if not b or self.state ~= 'READY' or not self.arrived then return nil end
    local away = current and location.distance(current, b.pickup)
    local bearing = away and away > 0 and location.bearing(current, b.pickup) or nil
    local heading = self.lastSample and location.finite(self.lastSample.heading) and self.lastSample.heading or self.heading
    local problem = self:beaconProblem()
    return {
      line = beacons.line(b.line), pay = beacons.PAY, insurance = beacons.INSURANCE_FEE, secondsLeft = math.ceil(b.left),
      pickup = location.copy(b.pickup), distanceMetres = away, direction = bearing and location.compassPoint(bearing) or nil,
      arrow = bearing and heading and (bearing - heading) % 360 or nil,
      dropMetres = location.distance(b.pickup, b.drop), radiusMetres = beacons.RADIUS,
      inZone = away ~= nil and away <= beacons.RADIUS, problem = problem, pickUpAllowed = problem == nil,
      ignoreArmed = self.beaconArmed,
    }
  end

  -- Fuel. The car is asked for its tank every READ_EVERY_SECONDS once arrived; the answer comes back
  -- through fuelReading. Refuel fills the tank as far as the money goes, inside a place's arrival
  -- circle, stopped, and is charged when the car reports how much went in.
  function c:watchFuel()
    if not self.fuelTank or self.state ~= 'READY' or not self.arrived or self.partsCheckDue or self.hire or self.onFoot
      or self.trailerShop then return end
    if self.fuelReadAt and self.clock - self.fuelReadAt < fuel.READ_EVERY_SECONDS then return end
    self.fuelReadAt = self.clock
    local ok, why = self.fuelTank:read()
    if not ok then self.diag:event('fuel_read_failed', tostring(why), 'W') end
    -- The fluid containers' real size, once per car: a fitted tank's, or a tanker's own.
    local space = cargo.capacity(self.ownedParts)
    if self.cargo and self.cargo.readTanks and not self.tankReading then self.cargo:readTanks(space.tankParts) end
  end

  function c:fuelReading(vehicleId, litres, capacity)
    if not location.finite(litres) or not location.finite(capacity) or capacity <= 0 or litres < 0 then return end
    local current = self.lastSample and self.lastSample.vehicle and self.lastSample.vehicle.id
    if current ~= nil and vehicleId ~= current then return end
    -- A reading taken before a respawn's restore has gone in would undo it.
    if self.fuel and self.fuel.restore then return end
    self.fuel = { vehicleId = vehicleId, litres = math.min(litres, capacity), capacity = capacity, at = self.clock }
  end

  -- Nil until the car has reported its tank: fuel from a save is only litres to put back, with no
  -- capacity or reading time.
  function c:refuelQuote()
    local f = self.fuel
    if not f or not f.at or not f.capacity or self.clock - f.at > fuel.STALE_SECONDS then return nil end
    local wanted = math.max(0, f.capacity - f.litres)
    local balance = self.profile and self.profile.progression.balance or 0
    local litres = math.min(wanted, math.floor(balance / fuel.PRICE_PER_LITRE))
    return { wanted = wanted, litres = litres, cost = fuel.cost(litres), full = wanted <= fuel.FULL_MARGIN_LITRES }
  end

  function c:refuel()
    local place = self:here()
    local problem = self:tradeProblem(place)
    local quote = self:refuelQuote()
    if not problem and not quote then problem = 'Could not read your fuel gauge. Try again in a moment.' end
    if not problem and quote.full then problem = 'Your tank is already full.' end
    if not problem and quote.litres <= 0 then problem = 'Not enough money for fuel: ' .. string.format('$%.2f', fuel.PRICE_PER_LITRE) .. ' a litre.' end
    if not problem and self.refuelPending then problem = 'Refuelling...' end
    if problem then
      self.fuelFeedback = problem
      return false
    end
    self.refuelSerial = self.refuelSerial + 1
    self.refuelPending = { serial = self.refuelSerial, at = self.clock }
    local ok, why = self.fuelTank:set(self.fuel.litres + quote.litres, self.refuelSerial)
    if not ok then
      self.refuelPending = nil
      self.fuelFeedback = 'Could not refuel. You have not been charged.'
      self.diag:event('refuel_failed', tostring(why), 'E')
      return false
    end
    self.fuelFeedback = 'Refuelling...'
    return true
  end

  -- The car's answer to a fuel change: a refuel is charged for what went in; a restore is free.
  function c:fuelSet(vehicleId, serial, before, after, capacity)
    if not location.finite(before) or not location.finite(after) or not location.finite(capacity) then return end
    local pending = self.refuelPending
    if pending and serial == pending.serial then
      self.refuelPending = nil
      local litres = math.max(0, after - before)
      local cost = math.min(fuel.cost(litres), self.profile and self.profile.progression.balance or 0)
      if cost > 0 then self:spend(cost, 'fuel') end
      self.fuelFeedback = 'Refuelled ' .. string.format('%.1f', litres) .. ' L for ' .. dollars(cost) .. '.'
      self.diag:event('refuelled', string.format('%.1f L, %d', litres, cost))
    end
    if capacity > 0 then self.fuel = { vehicleId = vehicleId, litres = math.min(after, capacity), capacity = capacity, at = self.clock } end
  end

  function c:tick(dtReal)
    local dt = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + dt
    -- On foot, in the game's walking mode, the car waits where it was left.
    self.onFoot = self.garage ~= nil and self.garage.onFoot ~= nil and self.garage:onFoot() or false
    if self.garage and self.garage.keepParked then
      if not self.onFoot then self.garage:releaseParked()
      elseif self.ownedParts then self.garage:keepParked(self.ownedParts.id) end
    end
    -- A server that never answers keeps the multiplayer career on this PC instead.
    if self.mp then
      local waiting = not self.mp:ready()
      self.mp:tick(self.clock)
      if waiting and self.mp:ready() and self.loadStatus == 'mp_waiting' then self:reload() end
    end
    local sample = self.adapter:sample()
    self:observe(sample, dt)
    self:spawnFirstCar(sample, dt)
    self:hintHud(sample, dt)
    self:watchClaim()
    self:watchFind()
    self:watchCommission()
    self:watchTurf()
    self:reportWhere(sample)
    self:provideVehicle()
    self:watchHire()
    self:watchBeacon(dt)
    self:watchParts()
    self:watchPartsBill()
    self:watchTrailer()
    self:afterRespawn()
    self:watchFuel()
    self:watchInsurance()
    self:watchTow()
    self:watchTimedSave()
    self:watchAutoSave()
    if self.streetView then
      self.streetView:poll(self.clock, function() return self:streetViewPosition() end, function() return self:baseMapData() end)
    end
    -- A refuel the car never answered is given up, uncharged.
    if self.refuelPending and self.clock - self.refuelPending.at > fuel.STALE_SECONDS then
      self.refuelPending, self.fuelFeedback = nil, 'Refuelling did not go through. You have not been charged.'
    end
    self.ui:publish(self:view(), self.clock)
  end

  -- What a town is known for, as the Town tab says it.
  local characterText = { city = 'City: wants parts', building = 'Building town: wants bricks', farming = 'Farming town: wants water' }

  -- A place's dots, one per good: how much it pays to deliver that good there now.
  function c:dots(place, now)
    local out = {}
    for _, good in ipairs(goods.carried()) do
      local short = jobs.shortage(place, good, now)
      out[#out + 1] = { id = good.id, name = good.name,
        level = short and 'sweet' or jobs.level(jobs.need(place, good, self.needs, now)) }
    end
    return out
  end

  -- The shortages within a job's reach of a place, nearest first: at most three.
  function c:shortagesNear(anchor, now)
    local out = {}
    local list = { { place = anchor, km = 0 } }
    for _, d in ipairs(jobs.destinations(anchor)) do list[#list + 1] = d end
    for _, d in ipairs(list) do
      for _, good in ipairs(goods.carried()) do
        local short, left = jobs.shortage(d.place, good, now)
        if short and #out < 3 then
          out[#out + 1] = { town = d.place.name, good = good.name, distanceMetres = d.km * 1000, secondsLeft = left, pays = jobs.SHORTAGE_PAY }
        end
      end
    end
    return out
  end

  -- A board's jobs as the HUD shows them, with what each pays the player's car.
  function c:boardView(place, allowed)
    local out = {}
    for _, job in ipairs(self:board(place)) do
      local q, good, to = self:jobQuote(job), goods.get(job.good), places.get(job.to)
      local section = job.contract and contracts.get(job.contract)
      out[#out + 1] = { id = job.id, good = good.name, goodId = good.id,
        to = section and section.name or job.drop and 'Off-road drop' or to.name, toId = to.id,
        -- A job's GPS button, before it is taken: a town job's goes to the drop-off town, a dangerous
        -- contract's to the start of its road. Off-road drops have no road to route along.
        gps = (section and self.gpsContract == section.id or not job.drop and not section and self.gpsTown == to.id) or nil,
        size = not job.drop and to.size or nil, drop = job.drop ~= nil and not section or nil,
        contract = section and { id = section.id, name = section.name, region = section.region, summary = section.summary,
          fee = contracts.FEE, insurance = contracts.INSURANCE_FEE, pays = section.pay } or nil,
        direction = job.drop and not section and location.compassPoint(location.bearing(place, job.drop)) or nil,
        distanceMetres = job.km * 1000, pay = q.pay, base = jobs.quote(job, q.units, nil, 0).base, level = q.level,
        units = q.units, kg = q.kg, unitSlots = good.slots, unitKg = good.kg,
        fluid = good.kind == 'fluid' or nil, unitLitres = good.litres, litres = good.litres and q.units * good.litres or nil,
        shortage = q.shortage or nil, jackpot = q.jackpot, road = q.road - (q.baseBonus or 0) > 1.005 and q.road - (q.baseBonus or 0) or nil,
        -- What the player's base adds, as a percentage of the pay without it.
        basePercent = q.baseBonus and math.floor(q.baseBonus / (q.road - q.baseBonus) * 100 + 0.5) or nil, outside = job.outside,
        tollTo = q.toll and q.toll.owner or nil, tollPercent = q.toll and math.floor(magnate.TOLL * 100 + 0.5) or nil,
        allowed = allowed and q.units > 0 and (not section or self:canAfford(contracts.FEE)) }
    end
    return out
  end

  -- The best-paying job on a board for the player's car, for the Route tab.
  function c:bestJob(place)
    local best
    for _, j in ipairs(self:boardView(place, true)) do
      if j.units > 0 and not j.contract and (not best or j.pay > best.pay) then best = j end
    end
    return best and { good = best.good, from = place.name, to = best.to, pay = best.pay, distanceMetres = best.distanceMetres } or nil
  end

  -- Where the car is, by name, for the top of the HUD and the minimised strip. Earth's names come
  -- first (its status bar's street, town, state and country); the mod's own towns fill in whatever
  -- Earth has not got. In a town, it is the town the Town tab trades in.
  function c:whereView(current, place, anchor)
    if not current then return nil end
    local earth = self.adapter.placeNames and self.adapter:placeNames() or nil
    local title = place and place.name or (earth and earth.place)
    if not title then
      local near = places.nearest(current, 1)[1]
      if near and near.metres <= WHERE_NEAR_METRES then
        local km = near.metres / 1000
        title = string.format(km < 10 and '%.1f km %s of %s' or '%.0f km %s of %s', km,
          location.compassPoint(location.bearing(near.place, current)) or 'away', near.place.name)
      else
        title = 'Far from any town'
      end
    end
    local area = {}
    for _, part in ipairs({ earth and earth.region, earth and earth.country }) do
      if part and part ~= title and part ~= area[#area] then area[#area + 1] = part end
    end
    if #area == 0 and anchor and anchor.region then area[1] = anchor.region end
    return { title = title, area = table.concat(area, ', '), street = earth and earth.street or nil, fromEarth = earth ~= nil }
  end

  -- Where the car is, for the Street View page: the live position, which way it points, and its
  -- street and town as the HUD shows them. Built only when the page asks, every 6, 10 or 20 seconds.
  function c:streetViewPosition()
    local sample = self.lastSample
    if not sample or not sample.valid or not location.valid(sample) then
      return { ok = false, reason = sample and sample.reason or 'earth_starting' }
    end
    local place = self:here()
    local anchor = place or (places.nearest(sample, 1)[1] or {}).place
    local where = self:whereView(sample, place, anchor) or {}
    local earth = self.adapter.placeNames and self.adapter:placeNames() or {}
    return {
      ok = true, latitude = sample.latitude, longitude = sample.longitude,
      heading = location.finite(sample.heading) and math.floor(sample.heading * 10 + 0.5) / 10 or nil,
      cameraHeading = location.finite(sample.cameraHeading) and math.floor(sample.cameraHeading * 10 + 0.5) / 10 or nil,
      place = where.title, street = where.street, region = earth.region, country = earth.country,
    }
  end

  -- Street View: starts the web server if it is not running yet and opens its page in the
  -- player's browser. Once used, it starts by itself next time, so an open tab carries on.
  function c:openStreetView()
    if not self.streetView then return false end
    local ok, why = self.streetView:start()
    if not ok then
      self.streetViewFeedback = why == 'port_busy'
        and 'Street View could not start: something else on your computer is using port ' .. self.streetView.port .. '.'
        or 'Street View could not start in this version of BeamNG.'
      self.diag:event('street_view', tostring(why), 'W')
      return false
    end
    self:rememberStreetView(true)
    local url = self.streetView:url()
    local okOpen, opened = false, false
    if self.openUrl then okOpen, opened = pcall(self.openUrl, url) end
    -- The HUD shows the address with a Copy button, in case the browser does not come up.
    self.streetViewFeedback = (okOpen and opened ~= false)
      and 'Street View is opening in your web browser. If it does not, copy the address below into your browser.'
      or 'To see Street View, copy the address below into your web browser.'
    self.diag:event('street_view', 'started')
    return true
  end

  -- The Base map: the same little web server as Street View, at its /bases page, opened in the browser.
  function c:openBaseMap()
    if not self.streetView then return false end
    local ok, why = self.streetView:start()
    if not ok then
      self.baseMapFeedback = why == 'port_busy'
        and 'The base map could not start: something else on your computer is using port ' .. self.streetView.port .. '.'
        or 'The base map could not start in this version of BeamNG.'
      self.diag:event('base_map', tostring(why), 'W')
      return false
    end
    self:rememberStreetView(true)
    local url = self.streetView:url() .. 'bases'
    local okOpen, opened = false, false
    if self.openUrl then okOpen, opened = pcall(self.openUrl, url) end
    self.baseMapFeedback = (okOpen and opened ~= false)
      and 'The base map is opening in your web browser. If it does not, copy the address below into your browser.'
      or 'To see the base map, copy the address below into your web browser.'
    self.diag:event('base_map', 'started')
    return true
  end

  function c:baseMapView()
    if not self.streetView then return nil end
    return { on = self.streetView.on, url = self.streetView:url() .. 'bases', feedback = self.streetView.on and self.baseMapFeedback or nil }
  end

  function c:stopStreetView()
    if not self.streetView then return false end
    self.streetView:stop()
    self:rememberStreetView(false)
    self.streetViewFeedback = 'Street View is off.'
    return true
  end

  function c:rememberStreetView(on)
    if not deps.io then return end
    pcall(function()
      deps.io.mkdir('/settings/earthFreight')
      deps.io.write(STREET_VIEW_FILE, { on = on == true })
    end)
  end

  function c:streetViewView()
    if not self.streetView then return nil end
    return { on = self.streetView.on, url = self.streetView:url(), feedback = self.streetViewFeedback }
  end

  function c:tradeView(current)
    local now = self.now()
    local place = current and self:here()
    local anchor = place or (current and (places.nearest(current, 1)[1] or {}).place)
    local nearby = {}
    if current then
      for _, n in ipairs(places.nearest(current, NEARBY_COUNT, place and place.id)) do
        local bearing = location.bearing(current, n.place)
        nearby[#nearby + 1] = { id = n.place.id, name = n.place.name, size = n.place.size,
          distanceMetres = n.metres * places.ROAD_FACTOR, dots = self:dots(n.place, now),
          direction = location.compassPoint(bearing), letters = location.compassLetters(bearing),
          gps = self.gpsTown == n.place.id or nil,
          destination = self.load ~= nil and not self.load.drop and self.load.to == n.place.id }
      end
    end
    local town
    if place then
      local problem = self:tradeProblem(place)
      local kind = jobs.character(place)
      local delivery
      if self.load and not self.load.drop and self.load.to == place.id then
        local why = self:deliveryProblem(place)
        delivery = { pay = self.load.pay, problem = why, allowed = problem == nil and why == nil }
      end
      local refuel = self:refuelQuote()
      town = {
        id = place.id, name = place.name, size = place.size, stopped = self.odometer:stopped(), problem = problem,
        region = place.region, boost = jobs.roadBonusFor(places.boost(place)), character = characterText[kind],
        jobs = self:boardView(place, problem == nil and not self.load), distance = self.jobDistance or 'any',
        delivery = delivery,
        refuel = refuel and { litres = refuel.litres, cost = refuel.cost, full = refuel.full } or nil,
        refuelAllowed = problem == nil and self.fuelTank ~= nil and refuel ~= nil and not refuel.full and refuel.litres > 0
          and not self.refuelPending and not self.hire and not self.onFoot,
      }
    end
    local loadView
    if self.load and self.load.drop then
      local good, from, drop = goods.get(self.load.good), places.get(self.load.from), self.load.drop
      local bearing = current and location.bearing(current, drop)
      local heading = self.lastSample and location.finite(self.lastSample.heading) and self.lastSample.heading or self.heading
      local away = current and location.distance(current, drop)
      local problem = self:dropProblem()
      local section = self.load.contract and contracts.get(self.load.contract)
      local radius = section and contracts.FINISH_RADIUS or self.load.beacon and beacons.RADIUS or jobs.DROP_RADIUS
      local teleporting = self.contractTeleportAt ~= nil and self.clock - self.contractTeleportAt < TELEPORT_WAIT_SECONDS
      loadView = {
        good = good.name, goodId = good.id, units = self.load.units or self.load.slots, slots = self.load.slots,
        kg = self.load.kg, pay = self.load.pay, drivenKm = self.load.drivenKm, from = from.name,
        to = section and section.name or 'off-road drop', beacon = self.load.beacon or nil,
        insurance = self.load.beacon and beacons.INSURANCE_FEE or nil,
        contract = section and { name = section.name, region = section.region, summary = section.summary,
          started = self.load.started == true, start = location.copy(section.start),
          startMetres = current and location.distance(current, section.start) or nil,
          teleportAllowed = not self.load.started and self.adapter.teleport ~= nil and not teleporting,
          teleporting = not self.load.started and teleporting or nil, insurance = contracts.INSURANCE_FEE } or nil,
        distanceMetres = away, direction = bearing and location.compassPoint(bearing) or nil,
        drop = {
          distanceMetres = away, bearing = bearing,
          -- Which way to turn: the spot's bearing from the way the car points (or last went), 0 is straight ahead.
          arrow = bearing and heading and (bearing - heading) % 360 or nil,
          inZone = away ~= nil and away <= radius, radiusMetres = radius,
          delivery = { allowed = problem == nil, problem = problem },
        },
      }
    elseif self.load then
      local good, to, from = goods.get(self.load.good), places.get(self.load.to), places.get(self.load.from)
      loadView = {
        good = good.name, goodId = good.id, units = self.load.units or self.load.slots, slots = self.load.slots,
        kg = self.load.kg, pay = self.load.pay, drivenKm = self.load.drivenKm,
        -- A fluid load's slots are its litres.
        litres = good.kind == 'fluid' and self.load.slots or nil,
        from = from.name, to = to.name, destination = location.copy(self.load.business or to),
        distanceMetres = current and places.roadEstimate(current, self.load.business or to) or nil,
        direction = current and location.compassPoint(location.bearing(current, self.load.business or to)) or nil,
        lookup = self:businessWanted(),
      }
      local b = self.load.business
      if b then
        local away = current and location.distance(current, b)
        local problem = self:businessProblem()
        loadView.business = { name = b.name, kind = business.label(b), distanceMetres = away,
          near = away ~= nil and away <= business.COUNTDOWN_METRES, inZone = away ~= nil and away <= business.RADIUS,
          radiusMetres = business.RADIUS, delivery = { allowed = problem == nil, problem = problem } }
      end
    end
    return {
      here = place and { id = place.id, name = place.name, size = place.size } or nil,
      -- The region you are in, from the nearest place, and what its roads add to a job's pay.
      region = anchor and { name = anchor.region, boost = jobs.roadBonusFor(places.boost(anchor)) } or nil,
      where = self:whereView(current, place, anchor),
      nearby = nearby, town = town, load = loadView,
      bestJob = not self.load and anchor and self:bestJob(anchor) or nil,
      shortages = anchor and self:shortagesNear(anchor, now) or {},
      abandonAllowed = self.load ~= nil, abandonArmed = self.abandonArmed, abandonFee = jobs.ABANDON_FEE,
    }
  end

  function c:shippingView(current)
    if not current or self.state ~= 'READY' or not self.arrived then return nil end
    local problem = self:shippingProblem()
    local list = {}
    for _, d in ipairs(shipping.DESTINATIONS) do
      local here, fee = shipping.arrived(current, d), shipping.fee(current, d)
      list[#list + 1] = { id = d.id, name = d.name, region = d.region, fee = fee, here = here,
        allowed = problem == nil and not here and self:canAfford(fee) }
    end
    -- Home, at the usual fee.
    local homeSpot, homeView = self:homeDestination(), nil
    if homeSpot then
      local here, fee = shipping.arrived(current, homeSpot), shipping.fee(current, homeSpot)
      homeView = { id = 'home', name = homeSpot.name, region = homeSpot.region, fee = fee, here = here,
        allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local found = {}
    for _, d in ipairs(self.shippingSearch and self.shippingSearch.results or {}) do
      local here, fee = shipping.arrived(current, d), shipping.fee(current, d)
      found[#found + 1] = { id = d.id, name = d.name, region = d.region, fee = fee, here = here,
        allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local offer, left = self:currentOffer()
    local offerView
    if offer then
      local here, fee = shipping.arrived(current, offer), shipping.fee(current, offer)
      offerView = { id = offer.id, name = offer.name, region = offer.region, boost = jobs.roadBonusFor(offer.boost), fee = fee,
        secondsLeft = left, here = here, allowed = problem == nil and not here and self:canAfford(fee) }
    end
    local playersView = self:playersView(current, problem)
    local b = self.booking
    -- Teleport there rests while Earth carries out the last press.
    local teleporting = self.bookingTeleportAt ~= nil and self.clock - self.bookingTeleportAt < TELEPORT_WAIT_SECONDS
    return {
      offer = offerView, home = homeView, destinations = list, players = playersView, found = found, query = self.shippingSearch and self.shippingSearch.query or nil,
      problem = problem, feedback = self.shippingFeedback,
      pending = self.offer and { name = self.offer.name, fee = self.offer.fee, radiusKm = shipping.OFFER_RADIUS_METRES / 1000,
        distanceMetres = location.distance(current, self.offer) } or nil,
      booking = b and { id = b.id, name = b.name, region = b.region, fee = b.fee, offer = b.offer == true, latitude = b.latitude, longitude = b.longitude,
        distanceMetres = location.distance(current, b),
        teleportAllowed = self.adapter.teleport ~= nil and not teleporting, teleporting = teleporting or nil } or nil,
    }
  end

  function c:view()
    local current = self.lastSample and self.lastSample.valid and location.copy(self.lastSample) or nil
    -- Where the player goes to carry on: the last save, or the start before the first save.
    local resume = not self.arrived and not self.error and location.copy(self.startupTarget) or nil
    local base = location.copy(self.profile and self.profile.base or self.creationBase)
    local status = messages[self.reason]
    -- A quote only stands for the vehicle it was made for.
    local quote = self.quote
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if quote and (self.error or vehicleId ~= quote.vehicleId) then quote = nil end
    if self.state == 'CONFIG_REQUIRED' then
      status = 'Set valid base coordinates in the Worldwide Trucking Career configuration, then load the level again.'
    elseif self.state == 'ERROR' then
      status = errorMessages[self.error] or errorMessages.internal_error
    elseif self.state == 'READY' and not self.arrived then
      status = goMessages[(self.mode == 'start' and not resume) and 'choose' or self.mode]
    elseif self.state == 'READY' then
      status = nil
    elseif not status then status = messages.position_invalid end
    local teleporting = self.teleportAskedAt ~= nil and self.clock - self.teleportAskedAt < TELEPORT_WAIT_SECONDS
    local label = labels[self.state]
    local startTown = self:startTown()
    if self.state == 'READY' and not self.arrived then
      if self.mode == 'resume' then label = 'GO TO YOUR LAST SAVE'
      elseif resume then label = 'GO TO ' .. (startTown or 'YOUR START'):upper()
      else label = 'CHOOSE WHERE YOU START' end
    end
    local active = self.profile ~= nil and not self.error
    local flashShown = self.flash ~= nil and self.clock - self.flash.at < FLASH_SECONDS
    -- Before the player is back at their save, the card and the cargo space are the saved car's.
    local car, savedSpace = self:carCard()
    local space = savedSpace or self:space()
    local trade = (self.state == 'READY' and self.arrived) and self:tradeView(current) or {}
    return {
      state = self.state, stateLabel = label, mode = self.mode,
      sessionStatus = status, arrived = self.arrived,
      -- The base is not shown; it stays in the state for tools and tests.
      base = base,
      resume = resume,
      resumeDistanceMetres = current and resume and location.distance(current, resume) or nil,
      resumeRadiusMetres = self.configuration and self.configuration.resumeRadiusMetres or nil,
      -- Teleport there is offered until arrival, and rests while Earth carries out the last press.
      teleportAllowed = resume ~= nil and self.state == 'READY' and self.adapter.teleport ~= nil and not teleporting,
      teleportFeedback = resume and (self.teleportAskedAt and not teleporting
        and 'Not there yet? Press Teleport there again, or copy the coordinates into the BeamNG.Earth map.'
        or self.teleportFeedback) or nil,
      startTown = startTown,
      startHereAllowed = self:startHereAllowed(),
      startingMoney = STARTING_MONEY,
      -- On a BeamMP server: the start page then calls the career the server's, not the offline one on this PC.
      online = self.mp ~= nil or nil,
      playerName = self.playerName,
      nameUnsaved = self.playerName ~= self.savedName,
      newGameAllowed = self:newGameAllowed(),
      newGameArmed = self.newGameArmed,
      vehicle = current and self.lastSample.vehicle and {
        model = self.lastSample.vehicle.model, id = self.lastSample.vehicle.id,
      } or nil,
      -- The start page's Your truck card and the career so far.
      car = car,
      career = self.profile and {
        jobsDone = self.profile.progression.jobsDone or 0,
        contractsDone = #(self.profile.progression.contractsDone or {}), contractsTotal = #contracts.LIST,
      } or nil,
      balance = self.profile and self.profile.progression.balance or STARTING_MONEY,
      totalDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0,
      unsavedDistanceKm = self.profile and math.max(0, self.profile.progression.totalDistanceKm - self.savedDistanceKm) or 0,
      unsavedBalance = self.profile and math.max(0, self.profile.progression.balance - self.savedBalance) or 0,
      unsavedSpending = self.profile and math.max(0, self.savedBalance - self.profile.progression.balance) or 0,
      -- Cargo space from the boxes on the car, the fuel in the tank, and trading.
      space = { slots = space.slots, kg = space.kg, boxes = space.boxes, boot = space.boot, litres = space.litres, tanks = space.tanks },
      fuel = self.fuel and { litres = self.fuel.litres, capacity = self.fuel.capacity, pricePerLitre = fuel.PRICE_PER_LITRE } or nil,
      here = trade.here, region = trade.region, where = trade.where, nearby = trade.nearby, town = trade.town, load = trade.load, bestJob = trade.bestJob,
      -- Whose turf the truck is in, for the line under the town name (the same check as the turf messages).
      turf = self.turf or nil,
      shortages = trade.shortages,
      streetView = self:streetViewView(),
      baseMap = self:baseMapView(),
      sightseeing = self:sightseeingView(current),
      gpsAllowed = self.adapter.setDestination ~= nil and self.state == 'READY' and self.arrived and not self.hire,
      gpsFeedback = self.gpsFeedback,
      abandonAllowed = trade.abandonAllowed, abandonArmed = trade.abandonArmed, abandonFee = trade.abandonFee,
      tradeFeedback = self.tradeFeedback,
      fuelFeedback = self.fuelFeedback,
      flash = flashShown and { kind = self.flash.kind, title = self.flash.title, text = self.flash.text } or nil,
      repairQuoteAllowed = active and self.garage ~= nil and not self.hire and not self.onFoot,
      repairQuote = quote and quote.cost or nil,
      repairOwed = self.owedDamage > 0 and pricing.repairCost(self.owedDamage, self:carValueOf(self.ownedParts and self.ownedParts.id)) or nil,
      repairAllowed = quote ~= nil and not self.pendingParts and not self.pendingCar and not self.onFoot,
      repairFeedback = self.repairFeedback,
      insurance = self:insuranceView(),
      tow = self:towView(),
      onFoot = self.onFoot == true,
      -- Why Buy parts, Buy new car and Buy second hand are off, or nil when they are on.
      garageLocked = self.onFoot and 'Get back in your car to change parts or cars.'
        or (self.trailerShop and 'Finish with your trailer parts first.') or self:towDebtProblem(),
      partsChange = self.pendingParts and {
        added = self.pendingParts.added, removed = self.pendingParts.removed,
        partsCost = self.pendingParts.partsCost, repair = self.pendingParts.repair, cost = self.pendingParts.cost,
      } or nil,
      buyPartsAllowed = self:buyPartsAllowed(),
      revertPartsAllowed = self.pendingParts ~= nil,
      partsFeedback = self.partsFeedback,
      carChange = self.pendingCar and {
        name = self.pendingCar.name, price = self.pendingCar.price, extras = self.pendingCar.extras,
        tradeIn = self.pendingCar.tradeIn, repair = self.pendingCar.repair, cost = self.pendingCar.cost,
        -- With a home: what keeping the old car costs, or that home is full.
        keepCost = self:homeSpaceFree() and self.pendingCar.keepCost or nil,
        homeFull = self.property ~= nil and not self:homeSpaceFree() or nil,
        oldName = self.ownedParts and self.ownedParts.name or nil,
        used = self.pendingCar.used and { km = self.pendingCar.used.km, newPrice = self.pendingCar.used.newPrice } or nil,
      } or nil,
      usedCars = self:usedCarsView(),
      trailer = self:trailerView(),
      buyCarAllowed = self:buyCarAllowed(),
      keepCarAllowed = self:keepCarAllowed(),
      revertCarAllowed = self.pendingCar ~= nil,
      carFeedback = self.carFeedback,
      saveAllowed = self.state == 'READY' and self.arrived and not self.stranded and not self.booking and not self.hire and not self.onFoot,
      heli = self:heliView(current), beacon = self:beaconView(current),
      shipping = self:shippingView(current),
      shipDay = self:shipView(current),
      home = self:homeView(current),
      repairAtHome = self.property ~= nil and self:atHome() or nil,
      stranded = self.stranded and current and {
        latitude = self.stranded.latitude, longitude = self.stranded.longitude,
        distanceMetres = location.distance(current, self.stranded),
      } or nil,
      saveFeedback = self:serverSaveWarning() or self.feedback,
      puncture = self.punctureDamage > 0 and {
        tyreCost = math.floor(self.punctureDamage / PUNCTURE_DAMAGE + 0.5)
          * math.floor(PUNCTURE_DAMAGE * pricing.repairRate(self:carValueOf(self.ownedParts and self.ownedParts.id)) + 0.5),
      } or nil,
    }
  end

  -- On a server, while it hasn't confirmed the last save: what to tell the player, in place of the save line.
  function c:serverSaveWarning()
    local late = self.mp and self.mp.state == 'server' and self.mp:unconfirmed(self.clock)
    if not late then return nil end
    return 'The server hasn\'t got your saves since ' .. (late.balance and pricing.dollars(late.balance) or 'you joined')
      .. '. They\'re kept on this PC: join the server again from this PC to send them.'
  end

  -- The recent deliveries Save keeps, as a list; nil when there are none.
  function c:savedNeeds()
    local list = {}
    for key, entry in pairs(self.needs or {}) do
      local place, good = key:match('^(.+):([^:]+)$')
      if place then list[#list + 1] = { place = place, good = good, drop = entry.drop, at = entry.at } end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    for i = #list, persistence.MAX_NEEDS + 1, -1 do list[i] = nil end
    return #list > 0 and list or nil
  end

  -- Writes a save of this profile and makes it the loaded one. Returns it, or nil and why.
  function c:record(candidate)
    candidate.schemaVersion, candidate.profileId = persistence.SCHEMA, 'default'
    local saved, why = self.store:save(candidate)
    if not saved then return nil, why end
    self.profile, self.unsavedBase = saved, nil
    self.savedName = saved.playerName
    self.savedDistanceKm = saved.progression.totalDistanceKm
    self.savedBalance = saved.progression.balance
    self.savedAt = self.clock
    return saved
  end

  function c:manualSave()
    if self.state ~= 'READY' or not self.profile or self.error then
      self.feedback = 'Save is unavailable right now. Check the status above.'
      self.diag:event('manual_save_rejected', tostring(self.state), 'W')
      return false
    end
    -- Until the player reaches the resume point they are not in their own car, so a Save would
    -- replace the saved car and location with the stand-in vehicle and wherever it is.
    if self.stranded or self.booking then
      self.feedback = self.stranded and 'Go back to where you teleported from, or book a relocation, before saving.'
        or 'Teleport to your relocation booking, or cancel it, before saving.'
      self.diag:event('manual_save_rejected', self.stranded and 'stranded' or 'booking', 'W')
      return false
    end
    if self.hire then
      self.feedback = self.hire.sightseeing and 'Press Return to your job before saving: Save keeps your car, not the sightseeing car.'
        or 'Press Back to my car on the Heli tab before saving: Save keeps your car, not the helicopter.'
      self.diag:event('manual_save_rejected', 'heli', 'W')
      return false
    end
    if self.onFoot then
      self.feedback = 'Get back in your car before saving.'
      self.diag:event('manual_save_rejected', 'on_foot', 'W')
      return false
    end
    if not self.arrived then
      self.feedback = 'Go to the coordinates above before saving.'
      self.diag:event('manual_save_rejected', 'not_arrived', 'W')
      return false
    end
    local trailerProblem = self:trailerSaveProblem()
    if trailerProblem then
      self.feedback = trailerProblem
      self.diag:event('manual_save_rejected', 'trailer_unhitched', 'W')
      return false
    end
    -- Read the vehicle position at click time so the saved location is current.
    local fresh = self.adapter:sample()
    if not fresh.valid or not location.valid(fresh) then
      self.lastSample = fresh
      self:interrupt(fresh.reason or 'position_invalid')
      self.feedback = 'Save paused. Waiting for a valid vehicle position.'
      self.diag:event('manual_save_rejected', fresh.reason or 'position_invalid', 'W')
      return false
    end
    local fuelLitres = self.fuel and self.ownedParts and self.fuel.vehicleId == self.ownedParts.id and self.fuel.litres or nil
    local progression = self.profile.progression
    local saved, why = self:record({
      base = self.profile.base, resume = location.copy(fresh),
      progression = { balance = progression.balance, totalDistanceKm = progression.totalDistanceKm, lastPunctureKm = progression.lastPunctureKm,
        jobsDone = progression.jobsDone, contractsDone = copy(progression.contractsDone),
        towOwed = progression.towOwed },
      vehicle = { model = fresh.vehicle and fresh.vehicle.model, config = self:savedVehicleConfig(),
        -- The car's name, for the start page before the car is back and for the car once it is.
        name = self:savedVehicleName(),
        damage = self:savedVehicleDamage(), fuelLitres = fuelLitres,
        value = self:savedVehicleUsed() and self.ownedParts.value or nil, km = self:savedVehicleUsed() and self.ownedParts.km or nil,
        -- What the car is worth now with its parts (the Your truck card's value), for a server's
        -- leaderboard and the card before the car is back. Worked out again once it is.
        worth = self:carWorth() },
      load = copy(self.load), offer = copy(self.offer), playerName = self.playerName, needs = self:savedNeeds(),
      commissionId = self.profile.commissionId,
      trailer = self:savedTrailer(), spareTrailer = self:savedSpareTrailer(),
      property = copy(self.property),
      storedCars = self.storedCars and #self.storedCars > 0 and copy(self.storedCars) or nil,
      beacon = self.beacon and { pickup = location.copy(self.beacon.pickup), drop = location.copy(self.beacon.drop),
        line = self.beacon.line, left = math.ceil(self.beacon.left) } or nil,
    })
    if not saved then
      -- Nothing is lost: the last save is untouched and the session carries on, so Save can be tried again.
      self.feedback = 'Could not save just now. Your last save is still safe. Press Save to try again.'
      self.diag:clear('manual_save_failed'); self.diag:event('manual_save_failed', why, 'E')
      return false
    end
    self.lastSample = fresh
    self.mode = 'resume'
    self.feedback = self:named('Saved') .. '.'
    self.diag:clear('manual_save_succeeded'); self.diag:event('manual_save_succeeded', 'generation ' .. saved.generation)
    return true
  end

  -- The server restarts for an update in about a minute: save now, as Save would, so nothing is lost. A save that
  -- can't happen right now says why, so the player can sort it and press Save themselves.
  function c:saveForRestart()
    self.diag:event('server_restart', 'saving', 'I')
    if self:manualSave() then
      self.feedback = 'Saved for the server update. The server restarts in about a minute.'
    else
      self.feedback = 'The server restarts for an update in about a minute. ' .. tostring(self.feedback or '')
    end
  end

  -- Asks for a save once things have settled: see watchAutoSave. A later ask replaces it.
  function c:autoSaveSoon(what)
    if self.profile then self.autoSave = { what = what, since = nil } end
  end

  -- Whether anything Save keeps has changed since the last save: distance driven, money or the name. A player
  -- parked and away from the keyboard is not saved over and over.
  function c:unsavedProgress()
    local p = self.profile and self.profile.progression
    if not p then return false end
    return p.totalDistanceKm ~= self.savedDistanceKm or p.balance ~= self.savedBalance or self.playerName ~= self.savedName
  end

  -- Every TIMED_SAVE_SECONDS since the last save, asks for one, which watchAutoSave makes at the next stop. A save
  -- already asked for (after a delivery, say) is left as it is: it saves the same progress.
  function c:watchTimedSave()
    if self.autoSave or not self.profile or self.error then return end
    if self.clock - (self.savedAt or self.clock) < TIMED_SAVE_SECONDS then return end
    if not self:unsavedProgress() then return end
    self.autoSave = { timed = true, since = nil }
  end

  -- Called every tick: saves the game the player asked for with autoSaveSoon once the car has been
  -- stopped for AUTOSAVE_SECONDS in its own car, with no bill, booking, respawn or claim waiting.
  -- Until then it keeps waiting, so a player who drives straight off is saved at their next stop.
  function c:watchAutoSave()
    local due = self.autoSave
    if not due then return end
    local sample = self.lastSample
    local settled = self.state == 'READY' and self.profile and not self.error and self.arrived
      and not self.stranded and not self.booking and not self.hire and not self.onFoot
      and not self.pendingParts and not self.pendingCar and not self.insurancePending
      and not self.refuelPending and not self.respawned and not self.partsCheckDue
      and not self:trailerSaveProblem()
      -- Not while BeamNG.Earth is still taking the car to a dangerous contract's start and loading its terrain.
      and not (self.contractTeleportAt and self.clock - self.contractTeleportAt < TELEPORT_WAIT_SECONDS)
      and sample and sample.valid and self.odometer:stopped()
    if not settled then due.since = nil; return end
    due.since = due.since or self.clock
    if self.clock - due.since < AUTOSAVE_SECONDS then return end
    self.autoSave = nil
    -- A save that fails says so, as Save does; the last save is untouched.
    if self:manualSave() then
      self.feedback = due.timed and 'Saved automatically.' or ('Saved automatically after ' .. due.what .. '.')
      self.diag:event('auto_save', due.timed and 'timed' or due.what)
    elseif due.timed then
      -- A timed save that could not happen tries again in another five minutes, not every tick.
      self.savedAt = self.clock
    end
  end

  function c:newGameAllowed()
    return self.configuration ~= nil and not self.store.blocked
  end

  function c:newGame()
    if not self:newGameAllowed() then
      self.feedback = 'New game is unavailable right now. Check the status above.'
      return false
    end
    -- A new game starts where the last one did; Start here moves it anywhere else.
    local start = location.copy(self.profile and self.profile.base or self.creationBase)
    if not start then
      self.feedback = 'You have not started yet. Teleport anywhere in the BeamNG.Earth map and press Start here.'
      return false
    end
    local town = self:startTown() or 'your start'
    if not self.newGameArmed then
      self.newGameArmed = true
      self.feedback = 'Press Yes, start over to start over in ' .. town .. ' in the starter car with '
        .. dollars(STARTING_MONEY) .. '. Your car, job and every dollar you have now are lost.'
      return false
    end
    local saved, why = self:record({ base = start, resume = start,
      progression = { balance = STARTING_MONEY, totalDistanceKm = 0 }, vehicle = {}, atStart = true,
      playerName = self.playerName })
    if not saved then
      self.newGameArmed = false
      self.feedback = 'Could not start a new game just now. Your save is unchanged. Press New game to try again.'
      self.diag:event('new_game_failed', tostring(why), 'E')
      return false
    end
    self.diag:event('new_game', town)
    -- The new game starts in a stock starter, so an old photo of an upgraded one would be wrong.
    if self.garage and self.garage.removePhoto then
      self.garage:removePhoto(workshop.STARTER_MODEL)
      -- And the old game's car, so its photo can't turn up on a car of that model bought later.
      local old = self.ownedParts and self.ownedParts.model
      if old and old ~= workshop.STARTER_MODEL then self.garage:removePhoto(old) end
    end
    self.photoAt, self.photoStamp, self.photoModel = nil, nil, nil
    -- The old game's bills and damage readings go with it: nothing it owed carries over.
    self.pendingParts, self.pendingCar, self.secondHand, self.lastDamage = nil, nil, nil, nil
    if self.partsBill and self.trigger then pcall(self.trigger, 'EarthFreightPartsBill', { open = false }) end
    self.partsBill = nil
    self:reload()
    self.feedback = string.format('New game started. Teleport to %s at %.8f, %.8f (Copy is just below) to get your starter car,'
      .. ' or teleport anywhere in the BeamNG.Earth map and press Start here.', town, start.latitude, start.longitude)
    return true
  end

  -- Keep my game: drops the request to start over, so the next press asks again.
  function c:cancelNewGame()
    if not self.newGameArmed then return false end
    self.newGameArmed, self.feedback = false, nil
    return true
  end

  function c:mount(on)
    if on then self.hudSeen = true end
    if self.ui:mount(on, self.clock) then
      self.diag:clear('ui_initialised'); self.diag:event('ui_initialised', 'Earth Freight HUD')
    end
  end

  c:reload()
  -- Street View carries on from last time, so a tab left open picks the truck up again.
  if c.streetView and deps.io then
    local ok, saved = pcall(function() return deps.io.exists(STREET_VIEW_FILE) and deps.io.read(STREET_VIEW_FILE) end)
    if ok and type(saved) == 'table' and saved.on == true then c.streetView:start() end
  end
  return c
end

local active
local function gameIO()
  return {
    read = function(path) return jsonReadFile(path) end,
    exists = function(path) return FS:fileExists(path) end,
    mkdir = function(path)
      if not FS:directoryExists(path) then FS:directoryCreate(path, true) end
      return FS:directoryExists(path)
    end,
    -- Compact JSON: the pretty writer may round coordinates.
    write = function(path, data) return jsonWriteFile(path, data, false) end,
    remove = function(path) if FS:fileExists(path) then FS:removeFile(path) end end,
  }
end
-- BeamMP's sending and events, set up below once safely is (multiplayer.lua).
local gameMultiplayer
-- Whether the game is paused; punctures wait while it is.
local function gamePaused()
  for _, name in ipairs({ 'bullettime', 'simTimeAuthority' }) do
    local timing = rawget(_G, name)
    if type(timing) == 'table' and type(timing.getPause) == 'function' then return timing.getPause() == true end
  end
  return false
end
-- Opens a page of this computer's own web server in the player's browser. The game's
-- openWebBrowser does not open http://127.0.0.1 addresses, so a one-line page that forwards to
-- the address is saved in the user folder and opened as a file, which Windows hands to the default
-- browser. openWebBrowser is the fallback. False when neither way is there.
local function gameOpenUrl(url)
  local platform = rawget(_G, 'Engine') and Engine.Platform
  local fs = rawget(_G, 'FS')
  local write = rawget(_G, 'writeFile')
  if type(platform) == 'table' or type(platform) == 'userdata' then
    local ok, opened = pcall(function()
      if type(write) ~= 'function' or not fs or type(platform.openFile) ~= 'function' then return false end
      local path = '/settings/earthFreight/streetview.html'
      if not fs:directoryExists('/settings/earthFreight') then fs:directoryCreate('/settings/earthFreight', true) end
      local page = '<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=' .. url .. '">' ..
        '<title>Street View</title><a href="' .. url .. '">Open Street View</a>'
      if not write(path, page) then return false end
      local real = fs:getFileRealPath(path)
      if type(real) ~= 'string' or real == '' then return false end
      platform.openFile(real)
      return true
    end)
    if ok and opened then return true end
  end
  local browser = rawget(_G, 'openWebBrowser')
  if type(browser) == 'function' then browser(url); return true end
  return false
end

local function ensure()
  if not active then
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), garage = garage.new(),
      punctures = punctures.new(), cargo = cargo.new(), fuel = fuel.new(), aircraft = aircraft.new(),
      log = rawget(_G, 'log'),
      streetView = streetView.new(), openUrl = gameOpenUrl, multiplayer = gameMultiplayer(),
      paused = gamePaused, trigger = function(event, payload) if guihooks then guihooks.trigger(event, payload) end end })
  end
  return active
end
-- The error with the calls that led to it, so the log names the line that failed and how it got there.
local function traced(e)
  return type(debug) == 'table' and type(debug.traceback) == 'function' and debug.traceback(tostring(e), 2) or tostring(e)
end
local function safely(f)
  local ok, result = xpcall(f, traced)
  if not ok then
    if active then
      active.error, active.feedback = 'internal_error', 'Anything since your last save is lost when you reload.'
      active:transition('ERROR', 'internal_error')
      active.diag:event('internal_error', tostring(result), 'E')
    elseif log then log('E', 'earthFreight', tostring(result)) end
    return false
  end
  return result
end
gameMultiplayer = function()
  local g = multiplayer.game()
  return {
    inSession = g.inSession, send = g.send,
    listen = function(handler) return g.listen(function(event, data) safely(function() handler(event, data) end) end) end,
    encode = function(t) return jsonEncode(t) end, decode = function(text) return jsonDecode(text) end,
  }
end
-- Ids the HUD may send: place and good ids are short lowercase words and digits.
local function id(value)
  return type(value) == 'string' and value:match('^[a-z0-9_]+$') and #value <= 64 and value or nil
end

function M.onExtensionLoaded()
  return safely(function() local c = ensure(); c.diag:event('extension_loaded', 'Earth Freight') end)
end
function M.onPreRender(dtReal)
  return safely(function() ensure():tick(dtReal) end)
end
function M.save() return safely(function() return ensure():manualSave() end) end
function M.requestRepairQuote() return safely(function() return ensure():requestRepairQuote() end) end
function M.repairVehicle() return safely(function() return ensure():repairVehicle() end) end
function M.buyParts() return safely(function() return ensure():buyParts() end) end
function M.revertParts() return safely(function() return ensure():revertParts(false) end) end
function M.buyCar(keep) return safely(function() return ensure():buyCar(keep == true) end) end
function M.revertCar() return safely(function() return ensure():revertCar(false) end) end
function M.openUsedCars(open) return safely(function() return ensure():openUsedCars(open == true) end) end
-- slot is the car's place in the Buy second hand list, from 1.
function M.buyUsedCar(slot)
  if type(slot) ~= 'number' or slot ~= math.floor(slot) or slot < 1 or slot > 9 then return false end
  return safely(function() return ensure():buyUsedCar(slot) end)
end
function M.openTrailers(open) return safely(function() return ensure():openTrailers(open == true) end) end
-- index is the trailer's place in the Buy new trailer list, from 1.
function M.buyTrailer(index)
  if type(index) ~= 'number' or index ~= math.floor(index) or index < 1 or index > 999 then return false end
  return safely(function() return ensure():buyTrailer(index) end)
end
-- place is where the trailer goes: 'base' or 'depot'.
function M.storeTrailer(place)
  if place ~= 'base' and place ~= 'depot' then return false end
  return safely(function() return ensure():storeTrailer(place) end)
end
function M.cancelStoreTrailer() return safely(function() return ensure():cancelStoreTrailer() end) end
function M.bringOutTrailer() return safely(function() return ensure():bringOutTrailer() end) end
function M.swapTrailers() return safely(function() return ensure():swapTrailers() end) end
function M.switchTrailer() return safely(function() return ensure():switchTrailer() end) end
function M.sellTrailer() return safely(function() return ensure():sellTrailer() end) end
function M.buyTrailerParts() return safely(function() return ensure():buyTrailerParts() end) end
function M.payTrailerParts() return safely(function() return ensure():payTrailerParts() end) end
function M.undoTrailerParts() return safely(function() return ensure():undoTrailerParts() end) end
function M.claimHome() return safely(function() return ensure():claimHome() end) end
function M.swapCars() return safely(function() return ensure():swapCars() end) end
function M.repairTrailer() return safely(function() return ensure():repairTrailer() end) end
-- The game calls these when two vehicles couple or uncouple, such as a car and its trailer.
function M.onCouplerAttached(a, b) return safely(function() if active then active:couplerChanged(a, b, true) end end) end
function M.onCouplerDetached(a, b) return safely(function() if active then active:couplerChanged(a, b, false) end end) end
function M.newGame() return safely(function() return ensure():newGame() end) end
function M.cancelNewGame() return safely(function() return ensure():cancelNewGame() end) end
function M.startHere() return safely(function() return ensure():startHere() end) end
function M.teleportToResume() return safely(function() return ensure():teleportToResume() end) end
function M.teleportToContract() return safely(function() return ensure():teleportToContract() end) end
function M.teleportToBooking() return safely(function() return ensure():teleportToBooking() end) end
-- count is how many slots to buy; anything but a whole number from 1 to 999 buys as many as fit and are affordable.
-- share is the slider's percentage of a full load: 10 to 100 in steps of 10; anything else takes it all.
function M.takeJob(job, share)
  local s = type(share) == 'number' and share >= jobs.SHARE_STEP and share <= 100 and share % jobs.SHARE_STEP == 0 and share or 100
  return safely(function() return ensure():takeJob(id(job), s) end)
end
function M.setJobDistance(distance) return safely(function() return ensure():setJobDistance(distance) end) end
function M.deliverJob() return safely(function() return ensure():deliver() end) end
-- The HUD's answer about a real business for the job's town (see business.lua). The key, kind and
-- coordinates are checked here; the name comes percent-encoded and is decoded and checked by the controller.
local function businessKey(key) return type(key) == 'string' and #key <= 200 and not key:find('[^%w_:%-]') end
function M.setBusiness(key, name, kind, latitude, longitude)
  if not businessKey(key) or type(name) ~= 'string' or type(kind) ~= 'string' or not business.KINDS[kind]
      or not location.finite(latitude) or not location.finite(longitude) then return false end
  return safely(function() return ensure():setBusiness(key, name, kind, latitude, longitude) end)
end
function M.noBusiness(key)
  if not businessKey(key) then return false end
  return safely(function() return ensure():noBusiness(key) end)
end
function M.abandonJob() return safely(function() return ensure():abandonJob() end) end
function M.claimInsurance() return safely(function() return ensure():claimInsurance() end) end
function M.towHere() return safely(function() return ensure():towHere() end) end
function M.payTow() return safely(function() return ensure():payTow() end) end
function M.getOut() return safely(function() return ensure():getOut() end) end
function M.refuel() return safely(function() return ensure():refuel() end) end
function M.hireHeli() return safely(function() return ensure():hireHeli() end) end
function M.backToCar() return safely(function() return ensure():backToCar(false) end) end
function M.goSightseeing() return safely(function() return ensure():goSightseeing() end) end
function M.returnToJob() return safely(function() return ensure():returnToJob() end) end
-- A heli load's answer: what it weighs once its mass is set.
function M.pickUpBeacon() return safely(function() return ensure():pickUpBeacon() end) end
function M.ignoreBeacon() return safely(function() return ensure():ignoreBeacon() end) end
function M.gpsToContract(contract) return safely(function() return ensure():gpsToContract(id(contract)) end) end
function M.gpsToTown(place) return safely(function() return ensure():gpsToTown(id(place)) end) end
function M.bookShipping(destination) return safely(function() return ensure():bookShipping(id(destination)) end) end
-- latitude and longitude are numbers; the query is letters, digits, spaces, dots and hyphens.
function M.bookShippingTo(latitude, longitude)
  if type(latitude) ~= 'number' or type(longitude) ~= 'number' then return false end
  return safely(function() return ensure():bookShippingTo(latitude, longitude) end)
end
function M.searchShipping(query)
  if type(query) ~= 'string' or #query > 60 or query:find('[^%w %.%-]') then return false end
  return safely(function() return ensure():searchShipping(query) end)
end
function M.bookOffer() return safely(function() return ensure():bookOffer() end) end
function M.goToPort() return safely(function() return ensure():goToPort() end) end
-- share is the load slider's percentage of a full load, as for takeJob.
function M.takeContainer(n, share)
  local s = type(share) == 'number' and share >= jobs.SHARE_STEP and share <= 100 and share % jobs.SHARE_STEP == 0 and share or 100
  return safely(function() return ensure():takeContainer(tonumber(n), s) end)
end
function M.findPlayer(player)
  if type(player) ~= 'number' then return false end
  return safely(function() return ensure():findPlayer(player) end)
end
function M.setFindable(on) return safely(function() return ensure():setFindable(on == true) end) end
function M.cancelShipping() return safely(function() return ensure():cancelShipping() end) end
function M.setPlayerName(name) return safely(function() return ensure():setPlayerName(name) end) end
-- The player car's answers to fuel.lua's commands.
function M.fuelReading(vehicleId, litres, capacity)
  return safely(function() if active then active:fuelReading(vehicleId, litres, capacity) end end)
end
function M.fuelSet(vehicleId, serial, before, after, capacity)
  return safely(function() if active then active:fuelSet(vehicleId, serial, before, after, capacity) end end)
end
function M.tanksRead(vehicleId, litres)
  return safely(function() if active then active:tanksRead(vehicleId, litres) end end)
end
function M.onVehicleSpawned(vehicleId) return safely(function() if active then active:vehicleSpawned(vehicleId) end end) end
function M.onVehicleResetted(vehicleId) return safely(function() if active then active:vehicleReset(vehicleId) end end) end
function M.reload() return safely(function() ensure():reload() end) end
-- The game's traffic police (gameplay_police) hook this when a pursuit starts, ends or catches someone.
function M.onPursuitAction(vehicleId, action, data)
  return safely(function()
    if not active then return end
    local player = getPlayerVehicle and getPlayerVehicle(0)
    if not player or player:getID() ~= vehicleId then return end
    active:policeAction(action, data)
  end)
end
function M.payPartsBill(serial) return safely(function() return ensure():payPartsBill(serial) end) end
function M.partsBillShown(serial) return safely(function() if active then active:partsBillShown(serial) end end) end
function M.uiMounted(on) return safely(function() ensure():mount(on == true) end) end
function M.getState() return safely(function() return ensure():view() end) end
function M.onClientStartMission() return M.reload() end
function M.onClientEndMission()
  return safely(function() if active then active:endMission() end end)
end
function M.onFilesChanged(files)
  return safely(function()
    if not active then return end
    for _, f in pairs(type(files) == 'table' and files or {}) do
      if type(f) == 'table' and type(f.filename) == 'string' and f.filename:lower() == config.FILE:lower() then
        active:reload(); return
      end
    end
  end)
end
function M.openStreetView() return safely(function() return ensure():openStreetView() end) end
function M.stopStreetView() return safely(function() return ensure():stopStreetView() end) end
function M.openBaseMap() return safely(function() return ensure():openBaseMap() end) end
function M.onExtensionUnloaded()
  -- The web server lets go of its port, so the next load can open it again.
  if active and active.streetView then pcall(function() active.streetView:stop() end) end
  active = nil
end -- no implicit save on shutdown

return M
