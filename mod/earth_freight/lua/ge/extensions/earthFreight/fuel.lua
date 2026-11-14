-- Fuel. BeamNG already burns fuel as you drive (more with a heavy load); this reads the player
-- car's tank and sets it, for the Refuel button and to put the tank back as it was after a
-- respawn (a repair or a part change would otherwise fill it for free). The car answers through
-- earthFreight_core.fuelReading and earthFreight_core.fuelSet. Every game call is guarded: a
-- missing or changed one means no reading, and the Refuel button stays off.
-- It also finds the petrol station pump the car stands at: BeamNG.Earth builds real stations from
-- map data and lists them, as any level's, in the game's own gas station POIs (gameplay_rawPois), so
-- the game's own Refuel prompt works there. Fuel is priced per continent, from the country of the
-- nearest town, petrol and diesel apart (MadMerick, 14 Nov).
local M = {}

-- One-line settings. Tune these after testing in game.
-- Real pump prices in US dollars a litre, one per continent, refreshed about monthly by hand from
-- GlobalPetrolPrices.com (October 2026 averages; check them before each release).
M.PRICES_FROM = 'October 2026'
M.PRICES = {
  ['North America'] = { gasoline = 1.10, diesel = 1.25 },
  ['South America'] = { gasoline = 1.40, diesel = 1.30 },
  ['Europe'] = { gasoline = 2.05, diesel = 2.10 },
  ['Africa'] = { gasoline = 1.40, diesel = 1.40 },
  ['Asia'] = { gasoline = 1.35, diesel = 1.30 },
  ['Oceania'] = { gasoline = 1.45, diesel = 1.50 },
}
-- Anywhere not on the list (Antarctica, the open sea): the world average.
M.WORLD = { gasoline = 1.55, diesel = 1.55 }
-- Scales every price: 100 as is, 80 a fifth cheaper.
M.PRICE_PERCENT = 100
-- A town's Refuel button, away from any pump: this many times that continent's pump price, so
-- players use the pumps (MadMerick, 14 Nov: 5 times, with a warning).
M.TOWN_PRICE_TIMES = 5
-- How close the car's middle must be to a pump to fill up there (a truck is long).
M.PUMP_METRES = 10
-- The station list is gathered again at most this often (seconds).
M.STATIONS_EVERY_SECONDS = 5
-- The tank rising by more than this, with no Refuel pressed, is the game's own pump prompt.
M.PUMP_MARGIN_LITRES = 1
M.READ_EVERY_SECONDS = 2
-- A reading older than this is not trusted for a refuel.
M.STALE_SECONDS = 10
-- Tanks within this many litres of full count as full.
M.FULL_MARGIN_LITRES = 0.5

-- The countries (as the place list names them) of each continent. Mexico, Central America and the
-- Caribbean are North America; the Middle East and the Caucasus Asia; Russia and Turkey Europe.
local CONTINENTS = {
  ['North America'] = { 'United States', 'Canada', 'Mexico', 'Greenland', 'Bermuda', 'Saint Pierre and Miquelon',
    'Belize', 'Guatemala', 'Honduras', 'El Salvador', 'Nicaragua', 'Costa Rica', 'Panama', 'Bahamas', 'Cuba',
    'Jamaica', 'Haiti', 'Dominican Republic', 'Puerto Rico', 'U.S. Virgin Islands', 'British Virgin Islands',
    'Anguilla', 'Antigua and Barbuda', 'Saint Kitts and Nevis', 'Montserrat', 'Guadeloupe', 'Dominica',
    'Martinique', 'Saint Lucia', 'Saint Vincent and the Grenadines', 'Barbados', 'Grenada', 'Trinidad and Tobago',
    'Aruba', 'Curacao', 'Bonaire', 'Saint Eustatius and Saba', 'Sint Maarten', 'Saint Martin', 'Saint Barthelemy',
    'Cayman Islands', 'Turks and Caicos Islands' },
  ['South America'] = { 'Argentina', 'Bolivia', 'Brazil', 'Chile', 'Colombia', 'Ecuador', 'Guyana', 'Suriname',
    'French Guiana', 'Paraguay', 'Peru', 'Uruguay', 'Venezuela', 'Falkland Islands',
    'South Georgia and the South Sandwich Islands', 'Death Road', 'Yungas' },
  ['Europe'] = { 'Aland Islands', 'Albania', 'Andorra', 'Austria', 'Belarus', 'Belgium', 'Bosnia and Herzegovina',
    'Bulgaria', 'Croatia', 'Cyprus', 'Czechia', 'Denmark', 'Estonia', 'Faroe Islands', 'Finland', 'France',
    'Germany', 'Gibraltar', 'Greece', 'Guernsey', 'Hungary', 'Iceland', 'Ireland', 'Isle of Man', 'Italy', 'Jersey',
    'Kosovo', 'Latvia', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Malta', 'Moldova', 'Monaco', 'Montenegro',
    'North Macedonia', 'Norway', 'Poland', 'Portugal', 'Romania', 'Russia', 'San Marino', 'Serbia', 'Slovakia',
    'Slovenia', 'Spain', 'Svalbard and Jan Mayen', 'Sweden', 'Switzerland', 'The Netherlands', 'Turkey', 'Ukraine',
    'United Kingdom', 'Vatican', 'Stelvio Pass' },
  ['Africa'] = { 'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi', 'Cabo Verde', 'Cameroon',
    'Central African Republic', 'Chad', 'Comoros', 'Democratic Republic of the Congo', 'Djibouti', 'Egypt',
    'Equatorial Guinea', 'Eritrea', 'Eswatini', 'Ethiopia', 'Gabon', 'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau',
    'Ivory Coast', 'Kenya', 'Lesotho', 'Liberia', 'Libya', 'Madagascar', 'Malawi', 'Mali', 'Mauritania',
    'Mauritius', 'Mayotte', 'Morocco', 'Mozambique', 'Namibia', 'Niger', 'Nigeria', 'Republic of the Congo',
    'Reunion', 'Rwanda', 'Saint Helena', 'Sao Tome and Principe', 'Senegal', 'Seychelles', 'Sierra Leone',
    'Somalia', 'South Africa', 'South Sudan', 'Sudan', 'Tanzania', 'Togo', 'Tunisia', 'Uganda', 'Western Sahara',
    'Zambia', 'Zimbabwe', 'French Southern Territories' },
  ['Asia'] = { 'Afghanistan', 'Armenia', 'Azerbaijan', 'Bahrain', 'Bangladesh', 'Bhutan',
    'British Indian Ocean Territory', 'Brunei', 'Cambodia', 'China', 'Georgia', 'Hong Kong', 'India', 'Indonesia',
    'Iran', 'Iraq', 'Israel', 'Japan', 'Jordan', 'Kazakhstan', 'Kuwait', 'Kyrgyzstan', 'Laos', 'Lebanon', 'Macao',
    'Malaysia', 'Maldives', 'Mongolia', 'Myanmar', 'Nepal', 'North Korea', 'Oman', 'Pakistan',
    'Palestinian Territory', 'Philippines', 'Qatar', 'Saudi Arabia', 'Singapore', 'South Korea', 'Sri Lanka',
    'Syria', 'Taiwan', 'Tajikistan', 'Thailand', 'Timor Leste', 'Turkmenistan', 'United Arab Emirates',
    'Uzbekistan', 'Vietnam', 'Yemen', 'Christmas Island', 'Cocos Islands', 'Karakoram Highway' },
  ['Oceania'] = { 'Australia', 'New Zealand', 'Fiji', 'Papua New Guinea', 'Solomon Islands', 'Vanuatu',
    'New Caledonia', 'French Polynesia', 'Samoa', 'American Samoa', 'Tonga', 'Kiribati', 'Tuvalu', 'Nauru',
    'Marshall Islands', 'Micronesia', 'Palau', 'Guam', 'Northern Mariana Islands', 'Cook Islands', 'Niue',
    'Tokelau', 'Wallis and Futuna', 'Pitcairn', 'Norfolk Island', 'Blue Mountains' },
}
M.CONTINENT_OF = {}
for continent, countries in pairs(CONTINENTS) do
  for _, country in ipairs(countries) do M.CONTINENT_OF[country] = continent end
end

-- The continent of a country or region, as the place list names it, or nil.
function M.continent(region)
  return type(region) == 'string' and M.CONTINENT_OF[region] or nil
end

-- Dollars a litre, to the cent, for this fuel ('diesel', or anything else as petrol) on this
-- continent; town = true is a town's Refuel button, away from a station.
function M.price(continent, fuelType, town)
  local row = M.PRICES[continent] or M.WORLD
  local base = fuelType == 'diesel' and row.diesel or row.gasoline
  local price = base * M.PRICE_PERCENT / 100
  if town then price = price * M.TOWN_PRICE_TIMES end
  return math.floor(price * 100 + 0.5) / 100
end

-- The game's gas station POIs for this level, as the pumps' positions: { x, y, z, name, brand,
-- energy = { gasoline = true, ... } }. Earth's carry their pumps as { area name, POI name } pairs,
-- the area's object standing at the pump.
local function gatherPumps()
  if not gameplay_rawPois or not gameplay_rawPois.getRawPoiListByLevel then return nil end
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not level then return nil end
  local list = gameplay_rawPois.getRawPoiListByLevel(level)
  local pumps = {}
  for _, poi in ipairs(list or {}) do
    local facility = type(poi) == 'table' and type(poi.data) == 'table' and poi.data.type == 'gasStation' and poi.data.facility
    if type(facility) == 'table' then
      local energy = {}
      for _, e in ipairs(facility.energyTypes or {}) do energy[e] = true end
      if energy.gasoline or energy.diesel then
        for _, pump in ipairs(facility.pumps or {}) do
          local area = type(pump) == 'table' and pump[1]
          local object = type(area) == 'string' and scenetree.findObject(area)
          local pos = object and object:getPosition()
          if pos then
            pumps[#pumps + 1] = { x = pos.x, y = pos.y, z = pos.z, energy = energy,
              name = type(facility.name) == 'string' and facility.name or nil,
              brand = type(facility.description) == 'string' and facility.description ~= '' and facility.description or nil }
          end
        end
      end
    end
  end
  return pumps
end

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    pumps = gatherPumps,
    -- Which batch of POIs the game has: a new one means stations came or went.
    generation = function() return gameplay_rawPois and gameplay_rawPois.getRawPoiGeneration and gameplay_rawPois.getRawPoiGeneration() end,
    -- Shows the game's gas stations outside career; Earth only lists its stations with it on.
    stationsShown = function() return settings.getValue('enableGasStationsInFreeroam') end,
    showStations = function() settings.setValue('enableGasStationsInFreeroam', true) end,
  }
end

-- Runs inside the car: adds up its fuel tanks (energy storages with a volume and capacity in
-- litres, leaving out batteries, nitrous and air) into litres and capacity, and whether it runs on
-- diesel (any diesel tank) or petrol.
local TANKS = [[
local litres, capacity, tanks, kind = 0, 0, {}, 'gasoline'
if energyStorage and energyStorage.getStorages then
  for _, s in pairs(energyStorage.getStorages() or {}) do
    if type(s) == 'table' and type(s.capacity) == 'number' and s.capacity > 0 and type(s.remainingVolume) == 'number'
        and s.energyType ~= 'electricEnergy' and s.energyType ~= 'n2o' and s.energyType ~= 'air' then
      litres, capacity = litres + s.remainingVolume, capacity + s.capacity
      tanks[#tanks + 1] = s
      if s.energyType == 'diesel' then kind = 'diesel' end
    end
  end
end
]]
-- The outer string.format fills in the car's id; %% escapes the car's own format string.
local READ = TANKS .. [[
obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.fuelReading(%%d, %%.3f, %%.3f, %%q) end', %d, litres, capacity, kind))
]]
-- Sets every tank to the same share of full, so the total is the target, and reports before and
-- after. The outer string.format fills in the target, the car's id and the serial; %% escapes the
-- car's own format string.
local SET = TANKS .. [[
local before, target = litres, math.max(0, math.min(capacity, %.3f))
for _, s in ipairs(tanks) do
  local ratio = capacity > 0 and target / capacity or 0
  if s.setRemainingRatio then s:setRemainingRatio(ratio) elseif s.setRemainingVolume then s:setRemainingVolume(ratio * s.capacity) end
end
local after = 0
for _, s in ipairs(tanks) do after = after + (s.remainingVolume or 0) end
obj:queueGameEngineLua(string.format('if earthFreight_core then earthFreight_core.fuelSet(%%d, %%d, %%.3f, %%.3f, %%.3f) end', %d, %d, before, after, capacity))
]]

-- Whole dollars for this many litres at this price a litre.
function M.cost(litres, price)
  if type(litres) ~= 'number' or litres ~= litres or litres <= 0 then return 0 end
  if type(price) ~= 'number' or price ~= price or price <= 0 then return 0 end
  return math.floor(litres * price + 0.5)
end

function M.new(environment)
  local env = environment or defaults()
  local f = {}

  local function send(command)
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or type(id) ~= 'number' then return false, 'vehicle_required' end
    local ok, why = pcall(function() vehicle:queueLuaCommand(command(id)) end)
    if not ok then return false, 'fuel_failed', tostring(why) end
    return true
  end

  -- Asks the player car for its fuel. The answer comes back through fuelReading.
  function f:read()
    return send(function(id) return string.format(READ, id) end)
  end

  -- Sets the player car's fuel to this many litres in all. serial ties the answer, which comes
  -- back through fuelSet, to this request.
  function f:set(litres, serial)
    if type(litres) ~= 'number' or litres ~= litres or litres < 0 then return false, 'invalid_litres' end
    return send(function(id) return string.format(SET, litres, id, serial or 0) end)
  end

  -- The nearest pump within PUMP_METRES of the player car, as { name, brand, energy, metres }, or
  -- nil. The station list is gathered again only when the game's POIs change, or every
  -- STATIONS_EVERY_SECONDS; any failure is no pump.
  local pumps, generation, gatheredAt
  function f:pumpNear(clock)
    local okGen, gen = pcall(env.generation)
    gen = okGen and gen or nil
    if not pumps or gen ~= generation or not gatheredAt or not clock or clock - gatheredAt >= M.STATIONS_EVERY_SECONDS then
      local ok, list = pcall(env.pumps)
      pumps, generation, gatheredAt = ok and type(list) == 'table' and list or {}, gen, clock
    end
    if #pumps == 0 then return nil end
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return nil end
    local okPos, pos = pcall(function() return vehicle:getPosition() end)
    if not okPos or not pos then return nil end
    local best, bestMetres
    for _, p in ipairs(pumps) do
      local dx, dy, dz = p.x - pos.x, p.y - pos.y, p.z - pos.z
      local metres = math.sqrt(dx * dx + dy * dy + dz * dz)
      if metres <= M.PUMP_METRES and (not bestMetres or metres < bestMetres) then best, bestMetres = p, metres end
    end
    return best and { name = best.name, brand = best.brand, energy = best.energy, metres = bestMetres } or nil
  end

  -- Turns on the game's gas stations outside career, once, so Earth's pumps and their Refuel
  -- prompt show. True when it was off and is now turned on.
  function f:showStations()
    local okShown, shown = pcall(env.stationsShown)
    if not okShown or shown ~= false then return false end
    return pcall(env.showStations) == true
  end

  return f
end

return M
