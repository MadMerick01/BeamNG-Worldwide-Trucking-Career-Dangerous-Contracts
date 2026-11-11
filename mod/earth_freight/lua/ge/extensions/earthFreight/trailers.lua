-- Trailers: the player can own one trailer at a time, bought new with Buy new trailer on the Garage
-- tab from the trailers in FOR_SALE. It is either out (spawned behind the car, hitched or
-- not) or stored in the garage, which goes everywhere with the player: Bring out puts it behind the
-- car in any town, any time, for free. While it is hitched its cargo space adds to the car's, and a
-- job loads the trailer first, then the car. Storing it with part of a job in it loses the whole job
-- and costs the abandon fee. A stored trailer keeps the damage it had, which Repair trailer mends
-- and a sale takes off its price. Sell (stored only) pays SELL_SHARE of what was paid.
-- The maths at the top needs no game; attach(c) adds the controller's side, which reaches the game
-- only through the garage (spawn, remove, read containers) and the cargo weight.
local pricing = require('earthFreight/pricing')
local cargo = require('earthFreight/cargo')
local jobs = require('earthFreight/jobs')
local persistence -- required when first needed: persistence requires this file
local M = {}

-- One-line settings. Tune these after testing in game.
-- Selling a trailer pays this share of what was paid for it, less the repair it needs.
M.SELL_SHARE = 0.75
-- A trailer's parcel space: BeamNG's parcel slots, each taking this many kg, as Cargo box XL does.
M.PARCEL_KG_PER_SLOT = 20
-- How often, in seconds, the controller checks the trailer is still in the world and reads its damage.
M.CHECK_SECONDS = 1
-- How long a trailer has to spawn after Buy or Bring out before it counts as failed.
M.SPAWN_SECONDS = 5

local dollars = pricing.dollars

-- The trailers for sale, cheapest first on the card. Each is a model/config key (our own empty
-- setups in the mod's vehicles folder, with a .pc, info json whose Value is the price, and picture,
-- or a vanilla tanker whose tank is already empty), the name the card shows, the cargo fitted
-- (fit: Boxes or Tanks, or nil when the tank is part of the trailer), the hitch it needs, what it
-- holds (room) and maxKg: the most a job puts on it, BeamNG's own payload for that trailer (its
-- heaviest loaded setup less the empty one), so 32 XL boxes don't take 80 t. The trailer fills
-- first, up to maxKg, and the rest goes in the car. Prices are the game's own for the empty trailer.
M.FOR_SALE = {
  { id = 'boxutility/earth_freight_trailer_boxes', name = 'Box utility trailer', fit = 'Boxes', hitch = 'ball', room = '2 XL boxes', maxKg = 600 },
  { id = 'boxutility/earth_freight_trailer_fluid', name = 'Box utility trailer', fit = 'Tanks', hitch = 'ball', room = '2 XL tanks', maxKg = 600 },
  { id = 'boxutility_large/earth_freight_large_boxes', name = 'Large box utility trailer', fit = 'Boxes', hitch = 'ball', room = '3 XL boxes', maxKg = 800 },
  { id = 'boxutility_large/earth_freight_large_tanks', name = 'Large box utility trailer', fit = 'Tanks', hitch = 'ball', room = '3 XL tanks', maxKg = 800 },
  { id = 'tiltdeck/earth_freight_22ft_boxes', name = 'Tilt deck 22 ft', fit = 'Boxes', hitch = 'ball', room = '4 XL boxes', maxKg = 2900 },
  { id = 'tiltdeck/earth_freight_22ft_tanks', name = 'Tilt deck 22 ft', fit = 'Tanks', hitch = 'ball', room = '4 XL tanks', maxKg = 2900 },
  { id = 'tiltdeck/earth_freight_30ft_boxes', name = 'Tilt deck 30 ft', fit = 'Boxes', hitch = 'ball', room = '7 XL boxes', maxKg = 3800 },
  { id = 'cargotrailer/earth_freight_enclosed_boxes', name = 'Enclosed cargo trailer', fit = 'Boxes', hitch = 'ball', room = '4 XL boxes', maxKg = 2100 },
  { id = 'tiltdeck/earth_freight_40ft_boxes', name = 'Tilt deck 40 ft', fit = 'Boxes', hitch = 'ball', room = '9 XL boxes', maxKg = 7000 },
  { id = 'tiltdeck/earth_freight_30ft_gooseneck_boxes', name = 'Tilt deck 30 ft gooseneck', fit = 'Boxes', hitch = 'gooseneck', room = '7 XL boxes', maxKg = 5600 },
  { id = 'tiltdeck/earth_freight_40ft_gooseneck_boxes', name = 'Tilt deck 40 ft gooseneck', fit = 'Boxes', hitch = 'gooseneck', room = '9 XL boxes', maxKg = 9600 },
  { id = 'tanker/empty_short', name = 'Short tanker', hitch = 'fifthwheel', room = '17,700 L tank', maxKg = 17700 },
  { id = 'tanker/empty', name = 'Long tanker', hitch = 'fifthwheel', room = '34,000 L tank', maxKg = 34000 },
  { id = 'flatbed/earth_freight_28ft_boxes', name = 'Flatbed 28 ft', fit = 'Boxes', hitch = 'fifthwheel', room = '10 XL boxes', maxKg = 8400 },
  { id = 'dryvan/earth_freight_28ft_boxes', name = 'Dry van 28 ft', fit = 'Boxes', hitch = 'fifthwheel', room = '8 XL boxes', maxKg = 9600 },
  { id = 'flatbed/earth_freight_53ft_boxes', name = 'Flatbed 53 ft', fit = 'Boxes', hitch = 'fifthwheel', room = '32 XL boxes', maxKg = 19700 },
  { id = 'dryvan/earth_freight_53ft_boxes', name = 'Dry van 53 ft', fit = 'Boxes', hitch = 'fifthwheel', room = '32 XL boxes', maxKg = 22400 },
  { id = 'eu_trailers/tanker3a', name = 'EU tanker, 3 axle', hitch = 'fifthwheel', room = '22,500 L tank', maxKg = 22500 },
}
local forSale = {}
for _, entry in ipairs(M.FOR_SALE) do forSale[entry.id] = entry end

-- What each hitch is called on a card.
M.HITCHES = { ball = 'ball hitch', gooseneck = 'gooseneck hitch', fifthwheel = 'fifth wheel' }

-- The hitches a car has, from its fitted parts (a parts snapshot): a set of ball, gooseneck,
-- fifthwheel. Read from the part names, so a car with an oddly named hitch may show none.
function M.hitches(snapshot)
  local found = {}
  for _, part in pairs(type(snapshot) == 'table' and type(snapshot.parts) == 'table' and snapshot.parts or {}) do
    local text = type(part) == 'string' and part:lower() or ''
    if text:find('fifthwheel', 1, true) or text:find('fifth_wheel', 1, true) then found.fifthwheel = true
    elseif text:find('gooseneck', 1, true) then found.gooseneck = true
    elseif text:find('hitch', 1, true) and not text:find('pintle', 1, true) then found.ball = true end
  end
  return found
end

-- The most a job puts on a trailer, from the list, by its model and .pc path; nil when not listed.
function M.limitOf(model, config)
  -- A trailer with parts fitted keeps its whole config, which still names the .pc it came from.
  if type(config) == 'table' then config = config.partConfigFilename end
  if type(model) ~= 'string' or type(config) ~= 'string' then return nil end
  local key = config:match('([^/\\]+)%.pc$')
  local entry = key and forSale[model .. '/' .. key]
  return entry and entry.maxKg or nil
end

-- Whether a config from the game's list is one of the trailers for sale, with a price.
function M.sellable(info)
  if type(info) ~= 'table' or type(info.model) ~= 'string' or type(info.key) ~= 'string' then return false end
  if not forSale[info.model .. '/' .. info.key] then return false end
  local value = tonumber(info.value)
  return value ~= nil and value == value and value > 0 and value ~= math.huge
end

-- Every trailer for sale, cheapest first, then in list order:
-- { model, key, config, name, fit, hitch, room, maxKg, preview, price }.
function M.catalogue(list)
  local out, order = {}, {}
  for i, entry in ipairs(M.FOR_SALE) do order[entry.id] = i end
  for _, info in ipairs(list or {}) do
    if M.sellable(info) then
      local entry = forSale[info.model .. '/' .. info.key]
      out[#out + 1] = { model = info.model, key = info.key, config = info.config, name = entry.name, fit = entry.fit,
        hitch = entry.hitch, room = entry.room, maxKg = entry.maxKg, preview = info.preview,
        price = math.floor(tonumber(info.value) + 0.5), order = order[entry.id] }
    end
  end
  table.sort(out, function(a, b)
    if a.price ~= b.price then return a.price < b.price end
    return a.order < b.order
  end)
  return out
end

-- The name a bought trailer goes by: its card's name, with what is fitted.
function M.offerName(offer)
  return offer.fit and (offer.name .. ' with ' .. offer.fit:lower()) or offer.name
end

-- What a trailer sells for: SELL_SHARE of what was paid, less the repair it needs, never below $0.
function M.salePrice(paid, repair)
  return math.max(0, math.floor((paid or 0) * M.SELL_SHARE + 0.5) - (repair or 0))
end

-- A trailer's cargo space from its containers (garage:cargoStorage): { slots, kg, litres, tankKg }.
function M.space(storage)
  local slots, litres = 0, 0
  for _, c in ipairs(type(storage) == 'table' and storage or {}) do
    if c.kind == 'parcel' then slots = slots + math.floor(c.capacity)
    elseif c.kind == 'fluid' then litres = litres + math.floor(c.capacity) end
  end
  return { slots = slots, kg = slots * M.PARCEL_KG_PER_SLOT, litres = litres, tankKg = litres }
end

-- A trailer's space from its containers, or, when they give none, from the cargo boxes and fluid
-- tanks fitted to it, as for a car (a parts snapshot; a trailer has no boot). With maxKg, no job
-- puts more than that many kg on it, however much room its boxes or tank have.
function M.spaceWith(storage, snapshot, maxKg)
  local space = M.space(storage)
  if snapshot then
    local fitted = cargo.capacity(snapshot)
    if space.slots == 0 and not fitted.boot then space.slots, space.kg = fitted.slots, fitted.kg end
    if space.litres == 0 and fitted.litres > 0 then space.litres, space.tankKg = fitted.litres, fitted.tankKg end
  end
  if type(maxKg) == 'number' and maxKg > 0 then
    space.kg, space.tankKg, space.maxKg = math.min(space.kg, maxKg), math.min(space.tankKg, maxKg), maxKg
  end
  return space
end

-- How a good loads into a hitched trailer and the car: the trailer is filled first, then the car.
-- Returns units, slots, kg in all, and how many of the units are in the trailer.
function M.fits(carSpace, trailerSpace, good)
  local inTrailer = trailerSpace and cargo.fits(trailerSpace, good) or 0
  local inCar = cargo.fits(carSpace, good)
  local units = inTrailer + inCar
  return units, units * good.slots, units * good.kg, inTrailer
end

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

function M.attach(c)
  -- The controller keeps:
  --   self.trailer: the trailer owned, as saved: { model, config, name, paid, damage, stored }
  --   self.trailerOut: { id, at, spawned, hitched, damage, space } while it is in the world
  --   self.foreignTrailer: the id of a trailer the player towed that is not theirs

  -- The trailers for sale, read once.
  function c:trailerCatalogue()
    if not self.trailerList and self.garage and self.garage.configs then
      local list = M.catalogue(self.garage:configs())
      if #list > 0 then self.trailerList = list end
      return list
    end
    return self.trailerList or {}
  end

  -- The most a job puts on the trailer owned, or nil for no limit (a trailer no longer for sale).
  function c:trailerLimit()
    local t = self.trailer
    if not t then return nil end
    return t.maxKg or M.limitOf(t.model, t.config)
  end

  -- What the trailer owned is worth for wealth: what was paid for it and its parts.
  function c:trailerWorth()
    return self.trailer and self.trailer.paid or 0
  end

  -- The trailer's space while it is out and hitched, or nil.
  function c:trailerSpace()
    local out = self.trailerOut
    if not out or not out.hitched then return nil end
    return out.space
  end

  -- The repair the trailer needs: what it had when stored or saved, plus what it has now.
  function c:trailerDamage()
    local t = self.trailer
    if not t then return 0 end
    local now = self.trailerOut and self.trailerOut.damage or 0
    return (t.damage or 0) + now
  end

  function c:trailerRepairCost()
    local t = self.trailer
    return t and pricing.repairCost(self:trailerDamage(), t.paid) or 0
  end

  -- Why Buy new trailer, Bring out or a trailer purchase cannot happen now, or nil.
  function c:trailerProblem()
    if not self.profile or self.error or self.state ~= 'READY' or not self.arrived or not self.garage then
      return 'Trailers are unavailable right now.'
    end
    if self.hire then return self:awayText() end
    if self.onFoot then return 'Get back in your car first.' end
    if self.stranded then return 'You teleported without booking a relocation. Go back to where you left from first.' end
    if self.booking then return 'Teleport to your relocation booking, or cancel it, first.' end
    if self.pendingCar or self.pendingParts then return 'Pay for or undo the bill above first.' end
    local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
    if not self.ownedParts or not vehicle or vehicle.id ~= self.ownedParts.id then return 'Get in your own car first.' end
    if self.trailerOut and not self.trailerOut.spawned then return 'Bringing the trailer out...' end
    if not self.odometer:stopped() then return 'Stop the car first.' end
    return nil
  end

  function c:openTrailers(open)
    self.trailersOpen = open == true
    self.trailerFeedback, self.sellArmed, self.storeArmed = nil, false, false
  end

  -- Puts the owned trailer behind the car. Returns true once the game spawned it.
  function c:spawnTrailer()
    local t = self.trailer
    if not t or not self.garage.spawnTrailer then return false end
    self.trailerSpawning = true
    local id, why, detail = self.garage:spawnTrailer(t.model, t.config)
    self.trailerSpawning = nil
    if not id then
      self.diag:event('trailer_spawn_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.trailerOut = { id = id, at = self.clock, spawned = true, hitched = false, damage = 0 }
    self:readTrailerSpace()
    t.stored = false
    self.appliedWeight = nil
    self.diag:event('trailer_out', t.model .. ' #' .. tostring(id))
    return true
  end

  -- Reads the trailer's cargo space from its containers and fitted parts.
  function c:readTrailerSpace(snapshot)
    local out = self.trailerOut
    if not out then return end
    if not snapshot and self.garage.parts then snapshot = self.garage:parts(out.id) end
    out.space = M.spaceWith(self.garage.cargoStorage and self.garage:cargoStorage(out.id) or {}, snapshot, self:trailerLimit())
    self.appliedWeight = nil
  end

  -- Trailer parts. Buy trailer parts puts the player in their trailer and opens the game's parts
  -- menu on it, as Buy parts does for the car, so they can fit cargo boxes or tanks. Each change
  -- respawns the trailer; the bill (parts added less the trade-in of parts taken off, as for the car) is
  -- worked out in watchTrailerShop. Pay keeps the parts, Undo puts the paid ones back, and both put
  -- the player back in their car. While in the trailer, nothing counts as changing car.
  -- self.trailerShop = { carId, paid (parts snapshot paid for), fitted, bill, due }

  -- Why Buy trailer parts cannot be pressed now, or nil.
  function c:trailerShopProblem()
    if not self.trailer or not self.trailerOut then return 'Bring your trailer out first.' end
    local problem = self:trailerProblem()
    if problem then return problem end
    if self.load then return 'Deliver or abandon your job before changing trailer parts.' end
    return nil
  end

  function c:buyTrailerParts()
    local problem = self:trailerShopProblem()
    if problem then
      self.trailerFeedback = problem
      return false
    end
    local out = self.trailerOut
    local paid = self.garage.parts and self.garage:parts(out.id)
    if not paid then
      self.trailerFeedback = 'Could not read your trailer\'s parts. Try again in a moment.'
      return false
    end
    local carId = self.ownedParts.id
    local ok = self.garage:enter(out.id)
    if not ok then
      self.trailerFeedback = 'Could not get into your trailer. Try again in a moment.'
      return false
    end
    self.trailerShop = { carId = carId, paid = paid, fitted = paid }
    self.trailerFeedback = 'Fit cargo boxes or tanks to your trailer in the parts menu. The bill shows up here.'
    if self.garage.openPartsMenu then self.garage:openPartsMenu() end
    self.diag:event('trailer_parts_open', tostring(out.id))
    return true
  end

  -- Called every tick while in the trailer: after a part change, prices it.
  function c:watchTrailerShop()
    local shop, out = self.trailerShop, self.trailerOut
    if not shop or not shop.due or not out then return end
    local snapshot = self.garage:parts(out.id)
    if not snapshot then return end
    shop.due, shop.fitted = false, snapshot
    shop.bill = pricing.partsDiff(shop.paid, snapshot)
    self:readTrailerSpace(snapshot)
    self.diag:event('trailer_parts_quote', shop.bill and tostring(shop.bill.cost) or 'none')
  end

  -- Back in the car, which is asked to hitch the trailer again.
  local function backToCar(self)
    local shop = self.trailerShop
    self.trailerShop = nil
    if not shop then return end
    if not self.garage:enter(shop.carId) then self.diag:event('trailer_parts_back_failed', tostring(shop.carId), 'W') end
    if self.trailerOut and self.garage.hitch then self.garage:hitch(self.trailerOut.id) end
  end

  -- Pays the trailer parts bill (or takes the refund) and keeps the parts.
  function c:payTrailerParts()
    local shop, t = self.trailerShop, self.trailer
    if not shop or not t then return false end
    if shop.due then
      self.trailerFeedback = 'Working out the bill...'
      return false
    end
    local bill = shop.bill
    if not bill then
      backToCar(self)
      self.trailerFeedback = 'No changes to your trailer. Nothing to pay.'
      return true
    end
    if bill.cost > 0 and not self:spend(bill.cost, 'trailer_parts') then
      self.trailerFeedback = 'Not enough money. You need ' .. dollars(bill.cost - self.profile.progression.balance)
        .. ' more. Undo some changes, or press Undo.'
      return false
    end
    local config = shop.fitted.config
    persistence = persistence or require('earthFreight/persistence')
    local kept = persistence.plainConfig({ model = config.model or t.model, parts = config.parts, partsTree = config.partsTree,
      partConfigFilename = config.partConfigFilename, vars = config.vars, paints = config.paints })
    if kept then t.config = kept else self.diag:event('trailer_config_unsaved', t.model, 'W') end
    -- The parts are part of what the trailer is worth: its sale, repairs and the player's wealth.
    t.paid = math.max(0, t.paid + bill.cost)
    backToCar(self)
    self.trailerFeedback = 'Trailer parts paid: ' .. dollars(bill.cost) .. '. Back up to your trailer to hitch it again.'
    self:autoSaveSoon('your trailer parts')
    return true
  end

  -- Undo: puts the paid-for parts back on the trailer, then the player back in their car.
  function c:undoTrailerParts()
    local shop = self.trailerShop
    if not shop then return false end
    if shop.bill and self.garage.repair then
      local ok, why = self.garage:repair(shop.paid.config)
      if not ok then
        self.trailerFeedback = 'Could not undo the changes. Try again in a moment.'
        self.diag:event('trailer_parts_undo_failed', tostring(why), 'W')
        return false
      end
    end
    self:readTrailerSpace(shop.paid)
    backToCar(self)
    self.trailerFeedback = 'Trailer part changes undone. Nothing to pay.'
    return true
  end

  -- Buys trailer number index of the list (cheapest first) and puts it behind the car.
  function c:buyTrailer(index)
    local list = self:trailerCatalogue()
    local offer = list[index]
    if not offer then
      self.trailerFeedback = 'That trailer is not for sale.'
      return false
    end
    local problem = self:trailerProblem()
    if not problem and self.trailer then problem = 'You already own a trailer. Store it and sell it first.' end
    if not problem and not self:canAfford(offer.price) then
      problem = 'Not enough money. You need ' .. dollars(offer.price - self.profile.progression.balance) .. ' more.'
    end
    if problem then
      self.trailerFeedback = problem
      return false
    end
    self.trailer = { model = offer.model, config = offer.config, name = M.offerName(offer), paid = offer.price,
      maxKg = offer.maxKg, stored = false }
    if not self:spawnTrailer() then
      self.trailer = nil
      self.trailerFeedback = 'Could not bring that trailer out. Try again in a moment. You have not been charged.'
      return false
    end
    self:spend(offer.price, 'trailer')
    self.trailersOpen = false
    local need = offer.hitch and not M.hitches(self.ownedParts)[offer.hitch]
    self.trailerFeedback = 'Bought the ' .. self.trailer.name .. ' for ' .. dollars(offer.price)
      .. '. It is behind your car: back up to it slowly and it hitches itself.'
      .. (need and (' It needs a ' .. M.HITCHES[offer.hitch] .. ': fit one with Buy parts if your car has none.') or '')
    self:autoSaveSoon('buying your trailer')
    self.diag:event('trailer_bought', offer.model .. '/' .. offer.key .. ' ' .. offer.price)
    return true
  end

  -- Takes the trailer out of the world into the garage, keeping its damage. why says what for.
  local function stow(self, why)
    local out, t = self.trailerOut, self.trailer
    if not t or not out then return end
    t.damage = self:trailerDamage()
    if t.damage <= 0 then t.damage = nil end
    if self.garage.removeVehicle then self.garage:removeVehicle(out.id) end
    self.trailerOut, t.stored, self.storeArmed = nil, true, false
    self.appliedWeight = nil
    self.diag:event('trailer_stored', tostring(why))
  end

  -- How much of the job is in the trailer: 0 when none.
  local function inTrailer(self)
    return self.load and self.load.trailerUnits or 0
  end

  -- Store trailer: anywhere, any time. With part of the job in the trailer it asks once first,
  -- then the whole job is lost and the abandon fee charged.
  function c:storeTrailer()
    if not self.trailer or not self.trailerOut or not self.profile or self.error then return false end
    if self.hire then self.trailerFeedback = self:awayText(); return false end
    if self.trailerShop then self.trailerFeedback = 'Pay for or undo your trailer parts first.'; return false end
    if inTrailer(self) > 0 and not self.storeArmed then
      self.storeArmed = true
      self.trailerFeedback = 'Warning: your trailer has part of your job in it. Storing it loses the whole load and costs '
        .. dollars(jobs.ABANDON_FEE) .. '. Press Confirm store to go ahead.'
      return false
    end
    local lost = ''
    if inTrailer(self) > 0 then
      local fee = self:dropJob('trailer_stored')
      lost = ' Your load is lost' .. (fee > 0 and (' and that cost ' .. dollars(fee)) or '') .. '.'
    end
    stow(self, 'stored')
    self.trailerFeedback = 'Your ' .. self.trailer.name .. ' is in the garage. Bring it out any time.' .. lost
    self:autoSaveSoon('storing your trailer')
    return true
  end

  function c:cancelStoreTrailer()
    self.storeArmed = false
    self.trailerFeedback = nil
    return true
  end

  -- Bring out: puts the stored trailer behind the car, anywhere.
  function c:bringOutTrailer()
    if not self.trailer or not self.trailer.stored then return false end
    local problem = self:trailerProblem()
    if problem then
      self.trailerFeedback = problem
      return false
    end
    if not self:spawnTrailer() then
      self.trailerFeedback = 'Could not bring your trailer out. Try again in a moment.'
      return false
    end
    self.trailerFeedback = 'Your ' .. self.trailer.name .. ' is behind your car: back up to it slowly and it hitches itself.'
    return true
  end

  -- Sell: a stored trailer only, for SELL_SHARE of what was paid less its repair. Asks once first.
  function c:sellTrailer()
    local t = self.trailer
    if not t or not t.stored or not self.profile or self.error then return false end
    local price = M.salePrice(t.paid, self:trailerRepairCost())
    if not self.sellArmed then
      self.sellArmed = true
      self.trailerFeedback = 'Press Confirm sale to sell your ' .. t.name .. ' for ' .. dollars(price) .. '.'
      return false
    end
    self:addMoney(price)
    self.trailer, self.sellArmed = nil, false
    self.trailerFeedback = 'Sold your ' .. t.name .. ' for ' .. dollars(price) .. '.'
    self:autoSaveSoon('selling your trailer')
    self.diag:event('trailer_sold', t.model .. ' ' .. price)
    return true
  end

  -- Repair trailer: pays for the damage it had when stored or saved. Damage it picks up while out
  -- shows on it, and is added once it is stored.
  function c:repairTrailer()
    local t = self.trailer
    if not t or not self.profile or self.error then return false end
    local cost = pricing.repairCost(t.damage or 0, t.paid)
    if cost <= 0 then
      self.trailerFeedback = self.trailerOut and 'Store your trailer to have its damage repaired.' or 'Your trailer needs no repair.'
      return false
    end
    if not self:spend(cost, 'trailer_repair') then
      self.trailerFeedback = 'Not enough money. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    t.damage = nil
    self.trailerFeedback = 'Trailer repaired for ' .. dollars(cost) .. '.'
    self:autoSaveSoon('repairing your trailer')
    return true
  end

  -- Called by the game's coupler hooks: a and b are the two vehicles' ids.
  function c:couplerChanged(a, b, attached)
    local carId = self.ownedParts and self.ownedParts.id
    if carId == nil or a == b or (a ~= carId and b ~= carId) then return end
    local other = a == carId and b or a
    local out = self.trailerOut
    if out and other == out.id then
      if out.hitched ~= attached then
        out.hitched = attached
        self.appliedWeight = nil
        if attached then self.trailerFeedback = nil end
        self.diag:event(attached and 'trailer_hitched' or 'trailer_unhitched', tostring(other))
      end
      return
    end
    self.foreignTrailer = attached and other or (self.foreignTrailer ~= other and self.foreignTrailer or nil)
  end

  -- Called every tick: brings a saved trailer back out once the car is back, checks the trailer
  -- is still in the world and reads its damage.
  function c:watchTrailer()
    local t = self.trailer
    if not t or not self.garage then return end
    self:watchTrailerShop()
    local out = self.trailerOut
    if not out then
      if t.stored or self.trailerRestored or self.state ~= 'READY' or not self.arrived or not self.ownedParts
        or self.respawned or self.partsCheckDue or self.hire or self.onFoot then return end
      local vehicle = self.lastSample and self.lastSample.valid and self.lastSample.vehicle
      if not vehicle or vehicle.id ~= self.ownedParts.id then return end
      -- A trailer saved out comes back behind the car, once; if it cannot, it waits in the garage.
      self.trailerRestored = true
      if not self:spawnTrailer() then t.stored = true end
      return
    end
    if self.clock - (out.checkedAt or -math.huge) < M.CHECK_SECONDS then return end
    out.checkedAt = self.clock
    if self.garage.exists and not self.garage:exists(out.id) then
      -- Gone from the world (destroyed, or the map let go of it): it goes back to the garage, and a
      -- load in it is lost as if it had been stored.
      local lost = ''
      if inTrailer(self) > 0 then
        local fee = self:dropJob('trailer_lost')
        lost = ' The load in it is lost' .. (fee > 0 and (', which cost ' .. dollars(fee)) or '') .. '.'
      end
      stow(self, 'lost')
      self:showFlash('cancelled', 'TRAILER LOST', 'Your trailer is back in the garage. Bring it out on the Garage tab.' .. lost)
      return
    end
    local inspected = self.garage:inspect(out.id)
    if inspected and finite(inspected.damage) then out.damage = inspected.damage end
  end

  -- A teleport leaves the trailer behind, so it goes into the garage. Relocating drops the job
  -- anyway, and a dangerous contract only ever loads the car.
  function c:trailerTeleported()
    if not self.trailerOut then return '' end
    stow(self, 'teleport')
    return ' Your trailer is in the garage: bring it out on the Garage tab.'
  end

  -- Puts the job's share of the weight on the trailer. Returns the kg left for the car.
  function c:applyTrailerWeight(kg, good)
    local out, load = self.trailerOut, self.load
    local units = load and load.trailerUnits or 0
    if not out or not self.cargo or not self.cargo.setWeightOn then return kg end
    local trailerKg = (good and units > 0) and math.min(kg, units * good.kg) or 0
    local fluid = { litres = 0, density = 1, tanks = {} }
    if good and good.kind == 'fluid' and units > 0 then
      fluid.litres, fluid.density = units * good.litres, good.kg / good.litres
    end
    local ok, why = self.cargo:setWeightOn(out.id, trailerKg, {}, fluid)
    if not ok then self.diag:event('trailer_weight_failed', tostring(why), 'W') end
    return kg - trailerKg
  end

  -- Why the job cannot be delivered for the trailer, or nil.
  function c:trailerDeliveryProblem()
    if inTrailer(self) > 0 and not (self.trailerOut and self.trailerOut.hitched) then
      return 'Hitch your trailer first: part of the load is in it.'
    end
    return nil
  end

  -- Why Save cannot keep the trailer as it is, or nil.
  function c:trailerSaveProblem()
    if self.trailerShop then return 'Pay for or undo your trailer parts on the Garage tab before saving.' end
    if self.trailerOut and not self.trailerOut.hitched then
      return 'Hitch your trailer, or store it on the Garage tab, before saving.'
    end
    return nil
  end

  -- The trailer as Save keeps it, or nil.
  function c:savedTrailer()
    local t = self.trailer
    if not t then return nil end
    local damage = self:trailerDamage()
    return { model = t.model, config = t.config, name = t.name, paid = t.paid, maxKg = t.maxKg,
      damage = damage > 0 and math.min(9007199254740991, damage) or nil, stored = t.stored == true }
  end

  -- The Trailer card on the Garage tab.
  function c:trailerView()
    local t, out = self.trailer, self.trailerOut
    local problem = self:trailerProblem()
    local balance = self.profile and self.profile.progression.balance or 0
    local view = { feedback = self.trailerFeedback, problem = problem, open = self.trailersOpen == true,
      foreign = self.foreignTrailer ~= nil and not (out and out.id == self.foreignTrailer) }
    if t then
      local repair = self:trailerRepairCost()
      view.owned = {
        name = t.name, paid = t.paid, stored = t.stored == true, out = out ~= nil, hitched = out and out.hitched or false,
        repair = repair > 0 and repair or nil, owed = pricing.repairCost(t.damage or 0, t.paid),
        sale = M.salePrice(t.paid, repair), space = out and out.space or nil,
        loaded = inTrailer(self) > 0,
      }
      view.storeAllowed = out ~= nil and not self.hire and not self.trailerShop
      view.partsAllowed = self:trailerShopProblem() == nil
      local shop = self.trailerShop
      if shop then
        view.shop = { due = shop.due == true, bill = shop.bill and { added = shop.bill.added, removed = shop.bill.removed,
          cost = shop.bill.cost } or nil }
        view.shop.payAllowed = not shop.due and (not shop.bill or shop.bill.cost <= balance)
      end
      view.storeArmed = self.storeArmed == true
      view.bringOutAllowed = t.stored == true and problem == nil
      view.sellAllowed = t.stored == true
      view.sellArmed = self.sellArmed == true
      view.repairAllowed = view.owned.owed > 0 and view.owned.owed <= balance
    elseif self.trailersOpen then
      -- One card per trailer, cheapest first; a trailer sold with boxes or tanks has a button for each.
      view.offers = {}
      local cards, have = {}, M.hitches(self.ownedParts)
      for i, offer in ipairs(self:trailerCatalogue()) do
        local card = cards[offer.name]
        if not card then
          card = { name = offer.name, preview = offer.preview, hitch = offer.hitch, hitchName = M.HITCHES[offer.hitch],
            hitchFound = offer.hitch == nil or have[offer.hitch] == true, maxKg = offer.maxKg, room = offer.room, buys = {} }
          cards[offer.name] = card
          view.offers[#view.offers + 1] = card
        end
        card.buys[#card.buys + 1] = { index = i, fit = offer.fit, room = offer.room, price = offer.price,
          short = offer.price > balance and offer.price - balance or nil,
          allowed = problem == nil and offer.price <= balance }
      end
    end
    return view
  end
end

-- The saved trailer, cleaned: { model, config, name, paid, damage, stored }, or nil when unusable.
function M.clean(t)
  if type(t) ~= 'table' or type(t.model) ~= 'string' or t.model == '' or #t.model > 128 or t.model:find('%c')
      or not ((type(t.config) == 'string' and t.config ~= '' and #t.config <= 512 and not t.config:find('%c'))
        or (type(t.config) == 'table' and type(t.config.model) == 'string'))
      or type(t.name) ~= 'string' or t.name == '' or #t.name > 256 or t.name:find('%c')
      or not finite(t.paid) or t.paid < 0 or t.paid ~= math.floor(t.paid) or t.paid > 9007199254740991
      or (t.damage ~= nil and (not finite(t.damage) or t.damage < 0))
      or (t.stored ~= nil and type(t.stored) ~= 'boolean')
      or (t.maxKg ~= nil and (not finite(t.maxKg) or t.maxKg <= 0)) then return nil end
  return { model = t.model, config = t.config, name = t.name, paid = t.paid, maxKg = t.maxKg, damage = t.damage,
    stored = t.stored == true }
end

return M
