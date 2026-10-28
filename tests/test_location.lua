local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local L = require('earthFreight/location')
local F = require('fixtures')
local C = require('earthFreight/config')
for _, p in ipairs({ F.position(), F.position(90,180), F.position(-90,-180), F.position(-33.86,151.21) }) do
  T.check(L.valid(p), 'valid coordinate')
end
for _, p in ipairs({ {}, { latitude = '0', longitude = 0 }, F.position(91,0), F.position(0,181),
    F.position(0/0,0), F.position(0,math.huge), F.position(-math.huge,0), F.position(0,false) }) do
  T.check(not L.valid(p), 'invalid coordinate rejected')
end
T.eq(L.distance(F.position(),F.position()),0,'zero distance')
T.near(L.distance(F.position(),F.position(1,0)),111195.0802,0.01,'one degree north')
T.near(L.distance(F.position(0,179.9999),F.position(0,-179.9999)),22.239,0.01,'antimeridian')
T.near(L.distance(F.position(90,0),F.position(90,180)),0,1e-6,'pole longitudes coincide')
T.near(L.distance(F.position(),F.position(0,180)),20015114.44,0.1,'antipodal numeric stability')
T.eq(L.distance({},F.position()),nil,'invalid distance not zero')
T.near(L.bearing(F.position(),F.position(1,0)),0,1e-9,'bearing north')
T.near(L.bearing(F.position(),F.position(0,1)),90,1e-9,'bearing east')
T.near(L.bearing(F.position(),F.position(-1,0)),180,1e-9,'bearing south')
T.eq(L.bearing({},F.position()),nil,'invalid bearing')
T.eq(L.compassPoint(0),'north','compass north'); T.eq(L.compassPoint(350),'north','compass wraps')
T.eq(L.compassPoint(80),'east','compass east'); T.eq(L.compassPoint(225),'south-west','compass south-west')
T.eq(L.compassPoint(0/0),nil,'invalid compass point')
T.check(C.validate(F.config()) ~= nil,'valid config')
local cfg = F.config(); cfg.base.latitude=nil; T.eq(C.validate(cfg),nil,'unset base rejected')
for _, patch in ipairs({ { 'resumeRadiusMetres',0 }, {'resumeRadiusMetres',math.huge},
    {'resumeRadiusMetres','50'}, {'resumeRadiusMetres',1001} }) do
  cfg=F.config(); cfg[patch[1]]=patch[2]; T.eq(C.validate(cfg),nil,'unsafe config value rejected')
end
cfg=F.config(); cfg.resumeRadiusMetres=nil; cfg.stabilitySeconds=3
local clean=C.validate(cfg); T.eq(clean.resumeRadiusMetres,50,'default radius'); T.eq(clean.stabilitySeconds,nil,'legacy stability setting ignored')
local io=F.io()
local defaults=C.load(io)
T.eq(defaults.base,nil,'missing config has no fixed start: the player chooses one')
T.eq(defaults.resumeRadiusMetres,50,'built-in radius')
T.eq(io.writes,0,'loading defaults does not create configuration')
defaults.resumeRadiusMetres=1
T.eq(C.load(io).resumeRadiusMetres,50,'defaults are detached per load')
cfg=F.config(); cfg.base=nil; T.eq(C.validate(cfg).base,nil,'a config without a base is valid')
io=F.io({[C.FILE]=F.config(F.position(0,0))})
T.eq(C.load(io).base.latitude,0,'existing override wins over defaults')
T.eq(io.writes,0,'existing override never overwritten')
T.eq(C.load(io).autoGps,true,'GPS on by default')
local off=F.config(); off.autoGps=false; T.eq(C.validate(off).autoGps,false,'GPS can be turned off')
off.autoGps='no'; T.eq(C.validate(off),nil,'a bad GPS setting is refused')
io.files[C.FILE]={base={}}
T.eq(C.load(io),nil,'present invalid override is not silently ignored')
io.files[C.FILE]=F.config(); io.readFails=C.FILE
T.eq(C.load(io),nil,'unreadable override does not fall back to defaults')
io=F.io(); io.existsFails=true
T.eq(C.load(io),nil,'failed existence check is not treated as absent configuration')
T.done('location/config')
