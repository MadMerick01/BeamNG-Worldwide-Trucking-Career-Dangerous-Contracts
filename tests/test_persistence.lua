local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local P = require('earthFreight/persistence')
local F = require('fixtures')
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'
T.check(P.validate(F.save()) ~= nil,'valid save accepted')
do
  local named = F.save(); named.playerName = "Zoë O'Neil"
  T.eq(P.validate(named).playerName, "Zoë O'Neil", 'the player name is kept')
  T.eq(P.validate(F.save()).playerName, nil, 'a save without a name still loads')
end
local edits = {
  function(s) s.schemaVersion=2 end, function(s) s.profileId='../bad' end,
  function(s) s.generation=0 end, function(s) s.generation=1.5 end,
  function(s) s.resume.latitude=0/0 end, function(s) s.resume.longitude=math.huge end,
  function(s) s.base.latitude=91 end, function(s) s.resume.longitude=-181 end,
  function(s) s.progression.balance=-1 end, function(s) s.progression.balance=0.5 end,
  function(s) s.progression.totalDistanceKm=math.huge end, function(s) s.progression.totalDistanceKm=-1 end,
  function(s) s.vehicle.model={} end, function(s) s.vehicle.configuration='bad\npath' end,
  function(s) s.resume.altitude=math.huge end, function(s) s.resume.heading=360 end,
  function(s) s.base=nil end, function(s) s.vehicle=nil end,
  function(s) s.vehicle.config='pickup.pc' end, function(s) s.vehicle.config={ parts = {} } end,
  function(s) s.vehicle.config={ model = 'pickup', vars = { x = 0/0 } } end,
  function(s) s.vehicle.config={ model = 'pickup', [true] = 1 } end,
  function(s) s.atStart=false end, function(s) s.vehicle.fuelLitres=-1 end, function(s) s.vehicle.fuelLitres=0/0 end,
  function(s) s.progression.lastPunctureKm=-1 end,
  function(s) s.playerName='' end, function(s) s.playerName=' Sam' end, function(s) s.playerName=('x'):rep(81) end,
  function(s) s.playerName='Sam"' end, function(s) s.playerName='Sam\n' end, function(s) s.playerName=7 end,
  function(s) s.load='food' end, function(s) s.load={ slots=1, paid=1, from='gn1', condition=1 } end,
  function(s) s.load={ good='food', slots=1.5, paid=1, from='gn1', condition=1 } end,
  function(s) s.load={ good='food', slots=1, paid=-1, from='gn1', condition=1 } end,
  function(s) s.load={ good='food', slots=1, paid=1, condition=1 } end,
  function(s) s.load={ good='food', slots=1, paid=1, from='gn1', to={}, condition=1 } end,
  function(s) s.load={ good='food', slots=1, kg=-5, paid=1, from='gn1', condition=1 } end,
}
for _, edit in ipairs(edits) do local s=F.save(); edit(s); T.eq(P.validate(s),nil,'invalid save rejected') end
-- A load on board is kept with its places and distance driven.
do
  local s=F.save(); s.load={ good='food', slots=2, kg=50, paid=120, from='gn1', to='gn2', drivenKm=3.5, condition=0.75 }
  local v=P.validate(s)
  T.eq(v.load.good,'food','good kept'); T.eq(v.load.to,'gn2','drop-off kept'); T.eq(v.load.condition,nil,'an old cargo condition is dropped')
  T.eq(v.load.drivenKm,3.5,'distance kept'); T.check(v.load~=s.load,'load copied')
  T.eq(P.validate(F.save()).load,nil,'no load is fine')
  s=F.save(); s.vehicle.fuelLitres=31.5; T.eq(P.validate(s).vehicle.fuelLitres,31.5,'fuel kept')
end
-- A saved car config is kept as plain data.
do
  local s=F.save(); s.vehicle.config={ model='pickup', partsTree={ chosenPartName='pickup', children={ a={ chosenPartName='' } } },
    vars={ ['$fuel']=80 }, paints={ { baseColor={ 1, 0, 0, 1 } } } }
  local v=P.validate(s)
  T.eq(v.vehicle.config.partsTree.children.a.chosenPartName,'','nested parts kept'); T.eq(v.vehicle.config.paints[1].baseColor[1],1,'paints kept')
  T.check(v.vehicle.config~=s.vehicle.config,'config copied')
  T.eq(P.validate(F.save()).vehicle.config,nil,'older save without a config still valid')
  local deep={ model='pickup' }; local node=deep
  for _=1,100 do node.children={}; node=node.children end
  s=F.save(); s.vehicle.config=deep; T.eq(P.validate(s),nil,'absurdly deep config rejected')
end
local io=F.io(); local store=P.new(io)
local save,why=store:load(); T.eq(save,nil,'missing no save'); T.eq(why,'missing','first launch recognized')
T.eq(io.writes,0,'loading never writes'); T.eq(io.directories,0,'loading never makes directory')
local original=F.save(7,1,2)
save=store:save(original)
T.eq(save.generation,1,'store controls generation'); T.eq(original.generation,7,'candidate never mutated')
T.eq(io.files[A].resume.latitude,1,'first save uses a'); T.eq(io.files[B],nil,'first save leaves other slot absent')
save=store:save(F.save(1,3,4)); T.eq(save.generation,2,'next generation')
T.eq(io.files[A].resume.latitude,1,'previous generation retained'); T.eq(io.files[B].resume.latitude,3,'other slot written')
store=P.new(io); save,why=store:load()
T.eq(save.generation,2,'highest generation loaded'); T.eq(why,'loaded','healthy status')
io.files[A]='truncated JSON'; save,why=store:load()
T.eq(save.generation,2,'one bad slot recovers valid slot'); T.eq(why,'loaded','recovery needs no player action')
T.eq(io.writes,2,'recovery does not write')
io.writeFails=true
local before=F.copy(io.files[B]); save,why=store:save(F.save(1,5,6))
T.eq(save,nil,'partial write rejected'); T.eq(why,'write_failed','write failure diagnosed')
T.check(P.equal(io.files[B],before),'active valid slot survives failed write')
io.writeFails=false; store=P.new(io); save,why=store:load()
T.eq(save.generation,2,'restart after interrupted write recovers previous generation')
io.writeMismatch=true; save,why=store:save(F.save(1,7,8))
T.eq(save,nil,'readback mismatch rejected'); T.eq(why,'verification_failed','readback error')
T.check(P.equal(io.files[B],before),'readback mismatch preserves active generation')
io.writeMismatch=false; save=store:save(F.save(1,7,8))
T.eq(save.generation,3,'save works again straight after a failure, no reload needed')
T.eq(io.files[A].resume.latitude,7,'retry rewrites the same spare slot')
io.writeRounds=true; save=store:save(F.save(1,9,9))
T.check(save~=nil,'JSON rounding of decimals does not fail the save')
io=F.io({[A]='broken',[B]={schemaVersion=1}}); store=P.new(io)
save,why=store:load(); T.eq(save,nil,'no readable save'); T.eq(why,'unreadable','unreadable saves start fresh')
T.check(store:save(F.save())~=nil,'saving replaces unreadable files'); T.eq(io.writes,1,'one write')
local future=F.save(4); future.schemaVersion=2
io=F.io({[A]=F.save(1),[B]=future}); store=P.new(io)
save,why=store:load(); T.eq(why,'newer_version','future schema blocks rollback')
T.eq(store:save(F.save()),nil,'future schema cannot be overwritten')
io=F.io({[A]=F.save(3,1,2),[B]=F.save(3,3,4)}); store=P.new(io)
save,why=store:load(); T.eq(why,'loaded','equal generations still load')
T.eq(save.resume.latitude,1,'equal generations pick slot a')
io=F.io({[A]=F.save(3),[B]=F.save(3)}); store=P.new(io)
T.check(store:load()~=nil,'identical duplicate generations accepted')
io=F.io(); io.existsFails=true; store=P.new(io)
save,why=store:load(); T.eq(why,'storage_unavailable','permission failure is not first run')
io=F.io(); store=P.new(io); store:load(); io.mkdirFails=true
save,why=store:save(F.save()); T.eq(why,'directory_failed','directory error visible'); T.eq(io.writes,0,'no write if directory fails')
io=F.io({[A]=F.save()}); store=P.new(io); store:load(); io.readbackFails=true
save,why=store:save(F.save(1,3,4)); T.eq(why,'verification_failed','unreadable write not reported as success')
T.eq(io.files[A].generation,1,'unreadable readback keeps previous generation')
local s=F.save(); s.resume.altitude=123; s.resume.heading=120
local normalized=P.validate(s); T.eq(normalized.resume.altitude,123,'optional altitude retained')
normalized.base.latitude=7; T.eq(s.base.latitude,-33.75,'validation returns detached copy')
io=F.io(); io.writeReturnsNil=true; store=P.new(io); store:load()
T.check(store:save(F.save())~=nil,'nil native write result accepted only after successful readback')
do
  local good = F.save(1); good.vehicle.damage = 250.5
  T.eq(P.validate(good).vehicle.damage, 250.5, 'saved damage kept')
  T.eq(P.validate(F.save(1)).vehicle.damage, nil, 'older saves have no damage')
  for _, bad in ipairs({ -1, 0/0, math.huge, 'lots' }) do
    local s = F.save(1); s.vehicle.damage = bad
    T.eq(P.validate(s), nil, 'invalid damage rejected')
  end
end
T.done('persistence')
