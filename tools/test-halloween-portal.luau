local fs = require("@lune/fs")
local r = require("@lune/roblox")
local luau = require("@lune/luau")
local env = setmetatable({}, { __index = getfenv() })
for k,v in r do env[k]=v end
local function load(path, environment)
	return luau.load(fs.readFile(path), { environment=environment or env, debugName=path })()
end
local config = load("src/shared/HalloweenPortalConfig.luau")
local pumpkin = load("src/shared/PumpkinVisual.luau")
env.script = { Parent = { PumpkinVisual = "PumpkinVisual" } }
env.require = function(key) assert(key == "PumpkinVisual"); return pumpkin end
local builder = load("src/shared/HalloweenPortalBuilder.luau")
local model = builder.Build(config.Origin)
assert(model.Name == "HalloweenPortal" and model.Parent == nil)
assert(model.PrimaryPart.Name == "TeleportTrigger")
assert((model.PrimaryPart.CFrame.Position - (config.Origin*r.CFrame.new(0,12,0)).Position).Magnitude < .001)
assert(config.DestinationPlaceId == 0, "Destination must stay unset until supplied")
local pumpkins, vortex, emitters, parts = 0,0,0,0
for _,item in model:GetDescendants() do
	if item:IsA("BasePart") then
		parts += 1
		assert(item.Anchored, item.Name .. " is unanchored")
		if item.Name ~= "TeleportTrigger" then assert(not item.CanTouch) end
		if item:GetAttribute("Vortex") then vortex += 1; assert(not item.CanCollide) end
		if item.Name == "JackOLantern" then
			pumpkins += 1
			local mesh = item:FindFirstChildOfClass("SpecialMesh")
			assert(mesh and mesh.MeshId == pumpkin.MeshId and mesh.TextureId == pumpkin.TextureId, "Portal pumpkin is not canonical")
		end
	elseif item:IsA("ParticleEmitter") then emitters += 1 end
end
assert(pumpkins==2 and vortex==84 and emitters==5)
assert(parts<250, "Portal exceeded geometry budget")
local function signal()
	local callbacks={}
	return {Connect=function(_,fn) table.insert(callbacks,fn) end, Fire=function(_,...) for _,fn in callbacks do fn(...) end end}
end
local touched, returning, failed, removing = signal(),signal(),signal(),signal()
local trigger={CFrame=r.CFrame.new(),Size=r.Vector3.new(17,22,4),Touched=touched,IsA=function(_,name) return name=="BasePart" end}
local livePortal={FindFirstChild=function(_,name) return name=="TeleportTrigger" and trigger end,SetAttribute=function() end}
local returnTrigger={CFrame=r.CFrame.new(50,0,0),Size=r.Vector3.new(17,22,4),Touched=returning,IsA=function(_,name) return name=="BasePart" end}
local returnPortal={FindFirstChild=function(_,name)return name=="TeleportTrigger" and returnTrigger end,SetAttribute=function()end,IsA=function(_,name)return name=="Model"end}
local liveArena={FindFirstChild=function(_,name)return name=="ReturnPortal" and returnPortal end}
local root={Position=r.Vector3.new(),IsA=function(_,name) return name=="BasePart" end}
local humanoid={Health=100}
local pivotCalls,lastPivot=0,nil
local cargo={Kind="Egg",EggType="Secret"}
local character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end,PivotTo=function(_,cf)pivotCalls+=1;lastPivot=cf;root.Position=cf.Position end}
local player={Character=character}
local hit={FindFirstAncestorOfClass=function() return character end}
local carrying, synchronousFailure, calls=false,false,0
local players={PlayerRemoving=removing,GetPlayerFromCharacter=function(_,c) return c==character and player end}
local teleport={TeleportInitFailed=failed,TeleportAsync=function(_,id,list)
	assert(id==123 and list[1]==player)
	calls+=1
	if synchronousFailure then error("test failure") end
end}
local serviceConfig={DestinationPlaceId=0,Cooldown=5,Origin=config.Origin}
local shared={HalloweenPortalConfig="config",HalloweenPortalBuilder="builder"}
local services={Players=players,TeleportService=teleport,ReplicatedStorage={Shared=shared}}
local serviceEnv=setmetatable({
	game={GetService=function(_,name) return assert(services[name]) end},
	workspace={FindFirstChild=function() return livePortal end},
	script={Parent={CarryService="carry",HalloweenArenaService="arena"}},
	require=function(key) if key=="config" then return serviceConfig elseif key=="builder" then return {} elseif key=="arena" then return {Init=function()return liveArena end,NextArrival=function()return r.CFrame.new(1600,3.7,115)end} else return {IsCarrying=function() return carrying end} end end,
	warn=function() end,
}, {__index=env})
for key,value in env do if rawget(serviceEnv,key)==nil then serviceEnv[key]=value end end
local service=load("src/server/HalloweenPortalService.luau",serviceEnv)
service.Init();service.Init()
touched:Fire(hit);assert(calls==0,"Unset destination teleported")
serviceConfig.DestinationPlaceId=123
root.Position=r.Vector3.new(100,0,0);touched:Fire(hit);assert(calls==0,"Far touch accepted")
root.Position=r.Vector3.new();humanoid.Health=0;touched:Fire(hit);assert(calls==0,"Dead character accepted")
humanoid.Health=100;carrying=true;touched:Fire(hit);assert(calls==0,"Carrying character accepted")
carrying=false;touched:Fire(hit);touched:Fire(hit);assert(calls==1,"Duplicate teleport attempt")
failed:Fire(player,nil,nil,999);touched:Fire(hit);assert(calls==1,"Unrelated failure cleared pending")
failed:Fire(player,nil,nil,123);touched:Fire(hit);assert(calls==1,"Cooldown was bypassed")
serviceConfig.Cooldown=0;touched:Fire(hit);assert(calls==2,"Async failure did not allow retry")
failed:Fire(player,nil,nil,123);synchronousFailure=true;touched:Fire(hit);touched:Fire(hit)
assert(calls==4,"Synchronous failure did not clear pending")
synchronousFailure=false;removing:Fire(player);touched:Fire(hit);assert(calls==5)
failed:Fire(player,nil,nil,123)
serviceConfig.DestinationMode="Arena";serviceConfig.Cooldown=5
removing:Fire(player);root.Position=r.Vector3.zero;carrying=true
touched:Fire(hit);assert(pivotCalls==0,"Carried cargo entered the arena")
carrying=false;touched:Fire(hit);assert(pivotCalls==1 and lastPivot.Position==r.Vector3.new(1600,3.7,115),"Arena arrival failed")
root.Position=returnTrigger.CFrame.Position;returning:Fire(hit);assert(pivotCalls==1,"Arrival/return cooldown was bypassed")
serviceConfig.Cooldown=0;carrying=true;returning:Fire(hit)
assert(pivotCalls==2 and (lastPivot.Position-(config.Origin*r.CFrame.new(0,3.5,-12)).Position).Magnitude<.001,"Return with boss reward failed")
assert(cargo.Kind=="Egg" and cargo.EggType=="Secret" and carrying,"Returning changed the cargo payload")
assert(root.AssemblyLinearVelocity==r.Vector3.zero and root.AssemblyAngularVelocity==r.Vector3.zero,"Teleport momentum was retained")
print(string.format("PASS: %d anchored parts, canonical geometry, external guards/failure retries and local entry/return with intact carried reward",parts))
