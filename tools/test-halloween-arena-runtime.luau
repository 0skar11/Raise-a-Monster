local fs=require("@lune/fs")
local roblox=require("@lune/roblox")
local luau=require("@lune/luau")
local env=table.clone(getfenv())
for key,value in roblox do env[key]=value end
local function load(path,custom)
	return luau.load(fs.readFile(path),{environment=custom or env,debugName=path})()
end
local gameConfig=load("src/shared/Config.luau")
env.script={Parent={Config="GameConfig"}}
env.require=function(key)assert(key=="GameConfig");return gameConfig end
local config=load("src/shared/HalloweenArenaConfig.luau")
assert(config.Capacity==gameConfig.MaxPlots and config.Capacity==10,"Encounter capacity does not match tycoons")
assert(config.CombatRadius==90 and #config.ArrivalPoints==config.Capacity)
local used={}
for _,point in config.ArrivalPoints do
	local world=config.Origin*point
	assert(not config.IsCombatPosition(world.Position),"Arrival is targetable")
	assert(point.Position.Y>2 and point.Position.Z>=108 and point.Position.Z<=138 and math.abs(point.Position.X)<20,"Arrival outside floor")
	for _,previous in used do assert((previous-point.Position).Magnitude>=7.9,"Arrivals overlap")end
	table.insert(used,point.Position)
end
assert(config.IsCombatPosition(config.Origin.Position))
assert(config.IsCombatPosition(config.Origin:PointToWorldSpace(roblox.Vector3.new(89,4,0))))
assert(not config.IsCombatPosition(config.Origin:PointToWorldSpace(roblox.Vector3.new(91,4,0))))
local attributes={}
local model={SetAttribute=function(_,k,v)attributes[k]=v end}
local serviceEnv=table.clone(env)
serviceEnv.game={GetService=function()return {Shared={HalloweenArenaConfig="config",HalloweenArenaBuilder="builder"}}end}
serviceEnv.workspace={FindFirstChild=function()return model end}
serviceEnv.require=function(key)if key=="config"then return config else return {}end end
local service=load("src/server/HalloweenArenaService.luau",serviceEnv)
assert(service.Init()==model and attributes.PlayerCapacity==config.Capacity)
for index=1,config.Capacity*2 do
	local destination=service.NextArrival()
	assert(destination==config.Origin*config.ArrivalPoints[(index-1)%config.Capacity+1],"Arrival distribution did not wrap")
end
-- Execute the production target predicate against a mixed combat/arrival group.
local players={}
for _,position in {config.Origin.Position,config.Origin:PointToWorldSpace(roblox.Vector3.new(89,3,0)),config.Origin:PointToWorldSpace(roblox.Vector3.new(0,3,110)),config.Origin:PointToWorldSpace(roblox.Vector3.new(0,3,123))} do
	local root={Position=position,IsA=function()return true end}
	local humanoid={Health=100}
	table.insert(players,{Character={FindFirstChild=function()return root end,FindFirstChildOfClass=function()return humanoid end}})
end
local attacksEnv=table.clone(env)
local shared={Config="gameConfig",HalloweenArenaConfig="config",Remotes="remotes"}
attacksEnv.game={GetService=function(_,name)if name=="Players"then return {GetPlayers=function()return players end}elseif name=="ReplicatedStorage"then return {Shared=shared}else return {}end end}
attacksEnv.script={Parent={CharacterService="character",HalloweenService="halloween",MonsterService="monster"}}
attacksEnv.require=function(key)if key=="gameConfig"then return gameConfig elseif key=="config"then return config elseif key=="remotes"then return {Get=function()return {}end}else return {}end end
local source=fs.readFile("src/server/BossAttacks.luau"):gsub("return BossAttacks%s*$","return {Targets=aliveTargets,StrikeCenter=strikeCenter}")
local attacks=luau.load(source,{environment=attacksEnv})()
local context={Part={Position=config.Origin.Position},Ground=.2}
local result=attacks.Targets(context)
assert(#result==2,"Arrival players were targeted, or combat players were excluded")
for _,radius in {9,5.5}do
	local point=attacks.StrikeCenter(context,config.Origin:PointToWorldSpace(roblox.Vector3.new(0,0,150)),radius)
	assert((point-config.Origin.Position).Magnitude+radius<=config.CombatRadius,"Predicted hazard leaked onto arrival")
end
print("PASS: ten tycoon arrivals, safe staging, floor/boundary checks, distribution wrap, production target eligibility and predicted hazard clamping")
