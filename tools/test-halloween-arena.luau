local fs, r, luau = require("@lune/fs"), require("@lune/roblox"), require("@lune/luau")
local env=setmetatable({}, {__index=getfenv()})
for k,v in r do env[k]=v end
local function load(path) return luau.load(fs.readFile(path),{environment=env,debugName=path})() end
local dependencies={}
env.script={Parent={PumpkinVisual="PumpkinVisual",HalloweenPortalBuilder="HalloweenPortalBuilder",Config="Config"}}
env.require=function(name) return assert(dependencies[name],"Missing dependency "..tostring(name)) end
dependencies.PumpkinVisual=load("src/shared/PumpkinVisual.luau")
dependencies.Config=load("src/shared/Config.luau")
dependencies.HalloweenPortalBuilder=load("src/shared/HalloweenPortalBuilder.luau")
local config=load("src/shared/HalloweenArenaConfig.luau")
local builder=load("src/shared/HalloweenArenaBuilder.luau")
local model=builder.Build(config)
local checks,parts,pumpkins=0,0,0
local function check(condition,label) checks+=1; assert(condition,label) end
check(model.Name=="HalloweenArena" and model.Parent==nil,"Builder must return a detached arena")
check(config.Capacity==dependencies.Config.MaxPlots and config.Capacity==6,"Capacity does not follow actual tycoon slots")
check(config.CombatRadius==90,"Approved combat diameter changed")
check((config.Origin.Position-dependencies.Config.Map.SpawnPosition).Magnitude>10000,"Arena must remain isolated from the tycoon spawn")
local combat=model:FindFirstChild("CombatFloor")
check(combat and combat.CanCollide and combat.Shape==r.Enum.PartType.Cylinder,"Solid circular combat floor missing")
check(combat.Size==r.Vector3.new(2,180,180),"Combat floor is not 180 studs across")
check((config.Origin:PointToObjectSpace(combat.CFrame.Position)-r.Vector3.new(0,-1,0)).Magnitude<.001,"Combat floor is not flush with local zero")
local arrival=model:FindFirstChild("ArrivalFloor")
check(arrival.Size.X==40 and arrival.Size.Z==30 and arrival.CanCollide,"Approved reception footprint changed")
local arrivalCenter=config.Origin:PointToObjectSpace(arrival.CFrame.Position)
check(math.abs(arrivalCenter.Y+arrival.Size.Y/2)<.001,"Arrival floor has a raised step")
local fillPositions={r.Vector3.new(-38,30,-38),r.Vector3.new(38,30,-38),r.Vector3.new(-38,30,38),r.Vector3.new(38,30,38),r.Vector3.new(config.ArrivalCenter.X,22,config.ArrivalCenter.Z-1)}
for index,position in fillPositions do
	local fill=model.Scenery:FindFirstChild("MoonlightFill_"..index)
	check(fill~=nil and fill.Transparency==1 and fill.Size==r.Vector3.new(1,1,1),"Invisible moonlight fill missing")
	check(fill.Anchored and not fill.CanCollide and not fill.CanTouch and not fill.CanQuery,"Moonlight fill participates in gameplay geometry")
	check((config.Origin:PointToObjectSpace(fill.CFrame.Position)-position).Magnitude<.001,"Moonlight fill drifted from the arena origin")
	local light=fill:FindFirstChildOfClass("PointLight")
	check(light~=nil and light.Color==r.Color3.fromRGB(183,165,222) and light.Brightness==2 and light.Range==60 and not light.Shadows,"Moonlight fill settings changed")
end
check(model.Scenery:FindFirstChild("MoonlightFill_6")==nil,"Unexpected extra moonlight fill")
local connector=model:FindFirstChild("EntryConnector")
local connectorCenter=config.Origin:PointToObjectSpace(connector.CFrame.Position)
check(connector.Size.X==24 and connector.CanCollide,"Entry is not the approved unobstructed width")
check(connectorCenter.Z+connector.Size.Z/2>=arrivalCenter.Z-arrival.Size.Z/2,"Gap between entry and arrival")
check(math.sqrt((connector.Size.X/2)^2+(connectorCenter.Z-connector.Size.Z/2)^2)<config.CombatRadius,"Entry does not overlap circular combat floor")
local points={}
for i=1,config.Capacity do
	local marker=model:FindFirstChild("ArrivalPoint_"..i)
	check(marker~=nil and marker.Transparency==1 and not marker.CanCollide,"Arrival marker blocks players")
	local pos=config.Origin:PointToObjectSpace(marker.CFrame.Position)
	check(math.abs(pos.X)<=arrival.Size.X/2-3 and math.abs(pos.Z-arrivalCenter.Z)<=arrival.Size.Z/2-3,"Arrival point is off its floor")
	check(not config.IsCombatPosition(marker.CFrame.Position),"A player arrives inside live combat")
	for _,other in points do check((marker.CFrame.Position-other).Magnitude>=6,"Arrival positions overlap") end
	table.insert(points,marker.CFrame.Position)
end
check(model:FindFirstChild("ArrivalPoint_7")==nil,"Arena still uses an incorrect server capacity")
local portal=model:FindFirstChild("ReturnPortal")
check(portal and portal:FindFirstChild("TeleportTrigger"),"Return portal trigger missing")
local portalPos=config.Origin:PointToObjectSpace(portal.TeleportTrigger.CFrame.Position)
check(portalPos.Z>arrivalCenter.Z and portal.TeleportTrigger.CFrame.LookVector:Dot(config.Origin.LookVector)>.99,"Return portal does not face boss across the reception")
local plinth=model:FindFirstChild("PortalPlinth")
local plinthCenter=config.Origin:PointToObjectSpace(plinth.CFrame.Position)
check(plinthCenter.Z-plinth.Size.Z/2<=137-3 and plinthCenter.Z+plinth.Size.Z/2>=137+3,"Portal rear foundations float off the reception")
check(plinth.Size.X>=29 and plinth.CanCollide,"Return portal footing is unsupported")
local function localBounds(part)
	local cf=config.Origin:ToObjectSpace(part.CFrame)
	local half=part.Size/2
	local minX,minZ,maxX,maxZ=math.huge,math.huge,-math.huge,-math.huge
	for _,x in {-half.X,half.X} do for _,z in {-half.Z,half.Z} do
		local p=cf:PointToWorldSpace(r.Vector3.new(x,0,z))
		minX,minZ,maxX,maxZ=math.min(minX,p.X),math.min(minZ,p.Z),math.max(maxX,p.X),math.max(maxZ,p.Z)
	end end
	return minX,minZ,maxX,maxZ
end
for _,item in model:GetDescendants() do
	if item:IsA("BasePart") then
		parts+=1
		check(item.Anchored,"Unanchored arena geometry: "..item.Name)
		local pos=config.Origin:PointToObjectSpace(item.CFrame.Position)
		if item.Name=="RimWall" or item.Name=="RimCoping" or item.Name=="LanternPier" then
			local minX,minZ,maxX,maxZ=localBounds(item)
			check(not (maxZ>87 and minZ<108 and minX<12 and maxX> -12),"Perimeter blocks the 24-stud entrance")
		end
		if item.Name=="FloorTile" then
			local minX,minZ,maxX,maxZ=localBounds(item)
			check(math.max(math.abs(minX),math.abs(maxX))^2+math.max(math.abs(minZ),math.abs(maxZ))^2<=90^2,"Tile extends beyond supported circular floor")
		end
		if item:IsDescendantOf(model.Scenery) and item.CanCollide and item.Name~="IslandFoundation" then
			check(r.Vector2.new(pos.X,pos.Z).Magnitude>config.CombatRadius,"Decorative obstacle intrudes into combat floor")
		end
		if item.Name=="ArenaPumpkin" or item.Name=="JackOLantern" then
			pumpkins+=1
			local mesh=item:FindFirstChildOfClass("SpecialMesh")
			check(mesh and mesh.MeshId==dependencies.PumpkinVisual.MeshId and mesh.TextureId==dependencies.PumpkinVisual.TextureId,"Non-canonical arena pumpkin")
		end
	elseif item:IsA("BaseScript") or item:IsA("SpawnLocation") then
		error("Geometry asset contains an unintended script or default respawn")
	end
end
check(parts<1000 and pumpkins>10,"Geometry budget or Halloween identity violated")
local second=builder.Build(config)
check(#model:GetDescendants()==#second:GetDescendants(),"Builder is not deterministic")
local a,b=model:GetDescendants(),second:GetDescendants()
for i,item in a do
	if item:IsA("BasePart") then check(item.CFrame==b[i].CFrame and item.Color==b[i].Color,"Studio/export geometry differs between builds") end
end
print(string.format("PASS: %d arena geometry checks; %d anchored parts, %d canonical pumpkins, 6 separated arrivals, open 180-stud floor and 24-stud entrance",checks,parts,pumpkins))
