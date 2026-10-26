-- Two alternating JSON save slots; the newest readable one is loaded. Loading never writes files.
-- Copied from Enduro: the slots, validation and vehicle config copy are the same, and the schema
-- holds Earth Freight's money, vehicle and current load.
local location = require('earthFreight/location')
local M = { DIRECTORY = '/settings/earthFreight/', SCHEMA = 1 }
local MAX_INTEGER = 9007199254740991

local function integer(n, minimum)
  return location.finite(n) and n >= minimum and n <= MAX_INTEGER and n == math.floor(n)
end
local function optionalString(s)
  return s == nil or (type(s) == 'string' and #s > 0 and #s <= 512 and not s:find('%c'))
end
local function amount(n)
  return n == nil or (location.finite(n) and n >= 0 and n <= MAX_INTEGER)
end
-- The player's name, as typed on the start page: up to 80 bytes (20 letters in any alphabet),
-- with no control characters, quotes or backslashes, and no spaces at either end.
M.NAME_BYTES = 80
function M.validName(s)
  return type(s) == 'string' and #s > 0 and #s <= M.NAME_BYTES and not s:find('[%c"\\]')
    and not s:find('^%s') and not s:find('%s$')
end

-- Copies a saved vehicle config (the game's own config table: model, partsTree, vars, paints),
-- keeping only plain JSON data and refusing anything oversized. Returns nil when unusable.
local MAX_CONFIG_DEPTH, MAX_CONFIG_VALUES = 64, 50000
local function plainConfig(config)
  local count = 0
  local function copy(value, depth)
    count = count + 1
    if count > MAX_CONFIG_VALUES or depth > MAX_CONFIG_DEPTH then return nil, false end
    local kind = type(value)
    if kind == 'string' then return value, #value <= 4096 end
    if kind == 'boolean' then return value, true end
    if kind == 'number' then return value, location.finite(value) end
    if kind ~= 'table' then return nil, false end
    local out = {}
    for k, v in pairs(value) do
      if type(k) ~= 'string' and not (type(k) == 'number' and integer(k, 1)) then return nil, false end
      local item, ok = copy(v, depth + 1)
      if not ok then return nil, false end
      out[k] = item
    end
    return out, true
  end
  if type(config) ~= 'table' or type(config.model) ~= 'string' or config.model == '' then return nil end
  local out, ok = copy(config, 1)
  return ok and out or nil
end
M.plainConfig = plainConfig

-- The money and distance driven, where the last puncture was and how many jobs are done (the job
-- boards are seeded from it). Returns a clean copy, or nil.
local function progression(p)
  if type(p) ~= 'table' or not integer(p.balance, 0) or not location.finite(p.totalDistanceKm)
      or p.totalDistanceKm < 0 or p.totalDistanceKm > MAX_INTEGER then return nil end
  if not amount(p.lastPunctureKm) then return nil end
  if p.jobsDone ~= nil and not integer(p.jobsDone, 0) then return nil end
  return { balance = p.balance, totalDistanceKm = p.totalDistanceKm, lastPunctureKm = p.lastPunctureKm, jobsDone = p.jobsDone }
end

-- A saved position, with the altitude and heading when present. Returns a clean copy, or nil and why.
local function pose(r)
  if not location.valid(r) then return nil, 'invalid_coordinates' end
  local out = location.copy(r)
  if r.altitude ~= nil then
    if not location.finite(r.altitude) or r.altitude < -20000 or r.altitude > 1000000 then return nil, 'invalid_altitude' end
    out.altitude = r.altitude
  end
  if r.heading ~= nil then
    if not location.finite(r.heading) or r.heading < 0 or r.heading >= 360 then return nil, 'invalid_heading' end
    out.heading = r.heading
  end
  return out
end

-- The job on board: which good, how many units, slots and kilograms, what it pays, the place it
-- was taken at and the place it goes to (place ids) and the distance driven with it. Saves from
-- before the job board carry bought cargo instead: no pay, but what was paid for it, which the
-- controller refunds. Saves from before cargo damage was removed carry a condition, which is
-- ignored. An off-road drop carries its spot: { latitude, longitude }. A dangerous contract also
-- carries its section's id, whether it has started and the relocation fee paid. The
-- controller drops a job whose good, places or section it does not know.
local function drop(d)
  if type(d) ~= 'table' or not location.valid(d) then return nil end
  return { latitude = d.latitude, longitude = d.longitude }
end

local function load(l)
  if type(l) ~= 'table' or type(l.good) ~= 'string' or not optionalString(l.good) or not integer(l.slots, 1)
      or not amount(l.kg) or type(l.from) ~= 'string' or not optionalString(l.from)
      or not optionalString(l.to) or not amount(l.drivenKm) then return nil end
  if (l.pay ~= nil and not integer(l.pay, 0)) or (l.paid ~= nil and not integer(l.paid, 0))
      or (l.pay == nil and l.paid == nil) or (l.units ~= nil and not integer(l.units, 1)) then return nil end
  if l.drop ~= nil and not drop(l.drop) then return nil end
  if l.contract ~= nil and (type(l.contract) ~= 'string' or not optionalString(l.contract) or l.drop == nil
      or (l.started ~= nil and type(l.started) ~= 'boolean') or (l.fee ~= nil and not integer(l.fee, 0))) then return nil end
  return { good = l.good, units = l.units, slots = l.slots, kg = l.kg or 0, pay = l.pay, paid = l.paid,
    from = l.from, to = l.to, drivenKm = l.drivenKm or 0, drop = drop(l.drop),
    contract = l.contract, started = l.contract and l.started == true or nil, fee = l.contract and l.fee or nil }
end

-- Recent deliveries, which lower what a town pays for that good for a while: a list of
-- { place, good, drop, at } (at in wall-clock seconds). Returns a clean copy, or nil.
M.MAX_NEEDS = 500
local function needs(list)
  if type(list) ~= 'table' or #list > M.MAX_NEEDS then return nil end
  local out = {}
  for i = 1, #list do
    local n = list[i]
    if type(n) ~= 'table' or type(n.place) ~= 'string' or not optionalString(n.place) or type(n.good) ~= 'string'
        or not optionalString(n.good) or not location.finite(n.drop) or n.drop < 0 or n.drop > 10
        or not location.finite(n.at) then return nil end
    out[i] = { place = n.place, good = n.good, drop = n.drop, at = n.at }
  end
  return out
end

function M.validate(s)
  if type(s) ~= 'table' then return nil, 'invalid_document' end
  if s.schemaVersion ~= M.SCHEMA then return nil, 'unsupported_schema' end
  if s.profileId ~= 'default' or not integer(s.generation, 1) then return nil, 'invalid_identity' end
  if not location.valid(s.base) then return nil, 'invalid_coordinates' end
  local p = progression(s.progression)
  if not p then return nil, 'invalid_progression' end
  if type(s.vehicle) ~= 'table' or not optionalString(s.vehicle.model)
      or not optionalString(s.vehicle.configuration) then return nil, 'invalid_vehicle' end
  local vehicleConfig = nil
  if s.vehicle.config ~= nil then
    vehicleConfig = plainConfig(s.vehicle.config)
    if not vehicleConfig then return nil, 'invalid_vehicle' end
  end
  -- Damage the saved car had and nobody has paid to repair, and the fuel in its tank.
  if not amount(s.vehicle.damage) or not amount(s.vehicle.fuelLitres) then return nil, 'invalid_vehicle' end
  local resume, poseWhy = pose(s.resume)
  if not resume then return nil, poseWhy end
  -- atStart marks a new game the player has not reached the start of yet.
  if s.atStart ~= nil and s.atStart ~= true then return nil, 'invalid_identity' end
  -- A paid-shipping offer not yet paid back: where to deliver, the town's name and the fee.
  local offer = nil
  if s.offer ~= nil then
    local o = s.offer
    if type(o) ~= 'table' or not location.valid(o) or type(o.name) ~= 'string' or not optionalString(o.name)
        or not integer(o.fee, 0) then return nil, 'invalid_offer' end
    offer = { latitude = o.latitude, longitude = o.longitude, name = o.name, fee = o.fee }
  end
  if s.playerName ~= nil and not M.validName(s.playerName) then return nil, 'invalid_identity' end
  local cargo = nil
  if s.load ~= nil then
    cargo = load(s.load)
    if not cargo then return nil, 'invalid_load' end
  end
  local recent = nil
  if s.needs ~= nil then
    recent = needs(s.needs)
    if not recent then return nil, 'invalid_needs' end
  end
  return {
    schemaVersion = M.SCHEMA, profileId = 'default', generation = s.generation,
    base = location.copy(s.base), resume = resume, progression = p,
    vehicle = { model = s.vehicle.model, configuration = s.vehicle.configuration, config = vehicleConfig,
      damage = s.vehicle.damage, fuelLitres = s.vehicle.fuelLitres },
    atStart = s.atStart, load = cargo, offer = offer, playerName = s.playerName, needs = recent,
  }
end

function M.equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not M.equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function M.newProfile(base, pose, vehicle, balance)
  return {
    schemaVersion = M.SCHEMA, profileId = 'default', generation = 0,
    base = location.copy(base), resume = location.copy(pose),
    progression = { balance = balance or 0, totalDistanceKm = 0 },
    vehicle = { model = vehicle and vehicle.model, configuration = vehicle and vehicle.configuration },
  }
end

function M.new(io)
  local store = { generation = 0, slot = nil, blocked = true }
  local paths = { a = M.DIRECTORY .. 'save-a.json', b = M.DIRECTORY .. 'save-b.json' }

  -- Returns the newest readable save, or nil and why: 'missing' (no save files), 'unreadable'
  -- (files exist but none can be read; saving replaces them), 'newer_version' or 'storage_unavailable'.
  function store:load()
    self.generation, self.slot, self.blocked = 0, nil, true
    local valid, unreadable = {}, false
    for _, slot in ipairs({ 'a', 'b' }) do
      local ok, present = pcall(io.exists, paths[slot])
      if not ok or type(present) ~= 'boolean' then return nil, 'storage_unavailable' end
      if present then
        local readOK, data = pcall(io.read, paths[slot])
        -- A save from a newer Earth Freight is never overwritten, even if the other slot is readable.
        if readOK and type(data) == 'table' and data.schemaVersion ~= nil and data.schemaVersion ~= M.SCHEMA then
          return nil, 'newer_version'
        end
        local save = readOK and M.validate(data) or nil
        if save then valid[#valid + 1] = { slot = slot, data = save } else unreadable = true end
      end
    end
    self.blocked = false
    if #valid == 0 then return nil, unreadable and 'unreadable' or 'missing' end
    table.sort(valid, function(a, b)
      if a.data.generation ~= b.data.generation then return a.data.generation > b.data.generation end
      return a.slot < b.slot
    end)
    local best = valid[1]
    self.generation, self.slot = best.data.generation, best.slot
    return best.data, 'loaded'
  end

  -- Writes the slot not holding the newest save, so a failed write never touches it. A failure
  -- changes nothing here, so Save can simply be tried again.
  function store:save(candidate)
    if self.blocked then return nil, 'storage_locked' end
    if self.generation >= MAX_INTEGER then return nil, 'generation_limit' end
    -- Build a new value: never change the caller's profile.
    local prepared = {
      schemaVersion = candidate.schemaVersion, profileId = candidate.profileId,
      generation = self.generation + 1, base = candidate.base, resume = candidate.resume,
      progression = candidate.progression, vehicle = candidate.vehicle,
      atStart = candidate.atStart, load = candidate.load, offer = candidate.offer,
      playerName = candidate.playerName, needs = candidate.needs,
    }
    local clean, why = M.validate(prepared)
    if not clean then return nil, why end
    local dirOK, made = pcall(io.mkdir, M.DIRECTORY)
    if not dirOK or made == false then return nil, 'directory_failed' end
    local slot = self.slot == 'a' and 'b' or 'a'
    local ok, result = pcall(io.write, paths[slot], clean)
    if not ok or result == false then return nil, 'write_failed' end
    -- The file must read back as a valid save of this generation. Decimals are not compared
    -- exactly, because the game's JSON writer may round them.
    local readOK, readback = pcall(io.read, paths[slot])
    local checked = readOK and M.validate(readback) or nil
    if not checked or checked.generation ~= clean.generation
        or checked.progression.balance ~= clean.progression.balance then
      return nil, 'verification_failed'
    end
    self.slot, self.generation = slot, clean.generation
    return clean, 'saved'
  end
  return store
end

return M
