local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local goods = require('earthFreight/goods')

-- The car returns before the saved trailer. None of its cargo may migrate into the car during that gap,
-- including a failed trailer spawn. The same allocation must apply when the trailer appears unhitched.
for _, case in ipairs({
  { good = 'bricks', units = 65, trailer = 65 }, -- the reported MD70 job: 8,287.5 kg, all in the trailer
  { good = 'parts', units = 12, trailer = 10 },
  { good = 'water', units = 100, trailer = 80 },
  { good = 'fuel', units = 100, trailer = 80 },
  { good = 'parts', units = 2, trailer = 0 },
}) do
  local c, _, _, g, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  local good = goods.get(case.good)
  local total, trailerKg = case.units * good.kg, case.trailer * good.kg
  local carKg = total - trailerKg
  c.load = { good = case.good, units = case.units, trailerUnits = case.trailer > 0 and case.trailer or nil, kg = total }
  c.trailer = { model = 'flatbed', config = 'vehicles/flatbed/earth_freight_28ft_boxes.pc', maxKg = 8400 }
  c.respawned, c.partsCheckDue = true, false
  c:afterRespawn()
  T.near(cargo.weights[#cargo.weights].kg, carKg, 1e-9, case.good .. ': restoring the car keeps only its cargo')
  T.eq(#cargo.trailerWeights, 0, 'no weight command for an absent trailer')

  g.trailerFails = true
  T.check(not c:spawnTrailer(), 'a failed spawn leaves the trailer absent')
  c:applyWeight(true)
  T.near(cargo.weights[#cargo.weights].kg, carKg, 1e-9, 'a failed spawn does not put the trailer cargo in the car')

  g.trailerFails = false
  c:watchTrailer()
  T.check(c.trailerOut ~= nil, 'the saved trailer can appear later through the normal restore poll')
  T.check(not c.trailerOut.hitched, 'the restored trailer is still unhitched')
  T.near(cargo.weights[#cargo.weights].kg, carKg, 1e-9, 'restoring the trailer leaves the car share unchanged')
  local sent = cargo.trailerWeights[#cargo.trailerWeights]
  T.check(sent ~= nil, 'the normal restore poll applies the trailer load without a manual reset')
  if sent then
    T.near(sent.kg, trailerKg, 1e-9, 'the reserved cargo goes to the restored trailer')
    T.near(sent.kg + cargo.weights[#cargo.weights].kg, total, 1e-9, 'the whole load is applied exactly once')
    T.eq(sent.hitchShare, 0.2, 'the existing fifth-wheel load distribution is preserved')
  end
  if sent and good.kind == 'fluid' then
    T.near(sent.fluid.litres, case.trailer * good.litres, 1e-9, 'the trailer receives its fluid volume')
    T.near(cargo.weights[#cargo.weights].fluid.litres, (case.units - case.trailer) * good.litres, 1e-9,
      'the car receives only its fluid volume')
  end

  local setWeightOn = cargo.setWeightOn
  cargo.setWeightOn = nil
  c:applyWeight(true)
  T.near(cargo.weights[#cargo.weights].kg, carKg, 1e-9, 'a missing trailer weight adapter cannot overload the car')
  cargo.setWeightOn = setWeightOn
end

do
  local c, _, _, _, cargo = F.controller()
  c:tick(0.1); c:tick(0.6); c:tick(0.6)
  c:applyWeight(true)
  T.eq(cargo.weights[#cargo.weights].kg, 0, 'an empty car still receives no cargo weight')
  T.eq(#cargo.trailerWeights, 0, 'an empty car without a trailer sends no trailer command')
end

T.done('Trailer cargo during vehicle restoration')
