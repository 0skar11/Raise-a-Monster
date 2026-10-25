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
local walls={}
local wallNames={VoidBarrier_RimWall=true,VoidBarrier_ConnectorWall=true,VoidBarrier_ArrivalShoulder=true,VoidBarrier_ArrivalRail=true,VoidBarrier_ArrivalBackWall=true}
check(model:FindFirstChild("VoidBarriers")~=nil,"Invisible void barrier folder missing")
for _,item in model.VoidBarriers:GetChildren() do
	if wallNames[item.Name] then
		table.insert(walls,item)
		local pos=config.Origin:PointToObjectSpace(item.CFrame.Position)
		check(item.Anchored and item.CanCollide and item.CanQuery and not item.CanTouch and item.Transparency==1,"Void boundary must be invisible and physically solid")
		check(item.Size.Y>=32 and math.abs(pos.Y-item.Size.Y/2)<.001,"Void boundary is jumpable or has a ground gap")
		if item.Name=="VoidBarrier_RimWall" then
			local cf=config.Origin:ToObjectSpace(item.CFrame)
			local center=cf:PointToObjectSpace(r.Vector3.zero)
			local dx=math.max(math.abs(center.X)-item.Size.X/2,0)
			local dz=math.max(math.abs(center.Z)-item.Size.Z/2,0)
			check(math.sqrt(dx*dx+dz*dz)>=config.CombatRadius-.002,"Invisible barrier consumes combat floor")
		end
	end
end
local decorativeHeights={RimWall=4,RimCoping=.65,LanternPier=6.4,ArrivalRail=3.5,ArrivalPillar=5.5}
for _,item in model.Perimeter:GetChildren() do
	local height=decorativeHeights[item.Name]
	check(height~=nil and math.abs(item.Size.Y-height)<.001,"Visible perimeter gained a tall wall")
	local pos=config.Origin:PointToObjectSpace(item.CFrame.Position)
	check(pos.Y+item.Size.Y/2<=6.401,"Decorative perimeter floats above its approved low height")
end
check(#walls==55,"Continuous circle, entry, shoulders, reception or rear wall is missing")
local function inWall(position)
	local world=config.Origin:PointToWorldSpace(position)
	for _,wall in walls do
		local p=wall.CFrame:PointToObjectSpace(world)
		local half=wall.Size/2
		if math.abs(p.X)<=half.X+.002 and math.abs(p.Y)<=half.Y+.002 and math.abs(p.Z)<=half.Z+.002 then return true end
	end
	return false
end
local function covered(a,b,outward)
	local distance=(b-a).Magnitude
	for step=0,math.ceil(distance*4) do
		local pos=a:Lerp(b,step/math.ceil(distance*4))+outward*.1
		for _,height in {.25,7.5,24,31.75} do
			check(inWall(pos+r.Vector3.new(0,height,0)),"Hole or jumpable section in perimeter at "..tostring(pos))
		end
	end
end
-- Sample every authored tangent face, including both shoulders of the circular entry.
local gap=math.asin(12/config.CombatRadius)
local angularStep=(2*math.pi-2*gap)/47
for index=0,47 do
	local angle=gap+index*angularStep
	local normal=r.Vector3.new(math.sin(angle),0,math.cos(angle))
	local tangent=r.Vector3.new(math.cos(angle),0,-math.sin(angle))
	local halfLength=config.CombatRadius*math.tan(angularStep/2)
	covered(normal*90-tangent*(index==0 and 0 or halfLength),normal*90+tangent*(index==47 and 0 or halfLength),normal)
	if index<47 then
		-- Test the shared corner itself, rather than only separated panel interiors.
		local corner=normal*90+tangent*halfLength
		check(inWall(corner+r.Vector3.new(0,31.75,0)),"Gap between circular wall panels")
	end
end
for _,side in {-1,1} do
	covered(r.Vector3.new(side*12,0,math.sqrt(90^2-12^2)),r.Vector3.new(side*12,0,108),r.Vector3.new(side,0,0))
	covered(r.Vector3.new(side*12,0,108),r.Vector3.new(side*20,0,108),r.Vector3.new(0,0,-1))
	covered(r.Vector3.new(side*20,0,108),r.Vector3.new(side*20,0,143),r.Vector3.new(side,0,0))
end
covered(r.Vector3.new(-20,0,143),r.Vector3.new(20,0,143),r.Vector3.new(0,0,1))
for z=87,109 do
	for _,x in {-11.99,-6,0,6,11.99} do
		check(not inWall(r.Vector3.new(x,3,z)),"Wall narrows the 24-stud entry")
	end
end
for _,position in points do
	local pos=config.Origin:PointToObjectSpace(position)
	for _,offset in {r.Vector3.zero,r.Vector3.new(-2.5,0,0),r.Vector3.new(2.5,0,0),r.Vector3.new(0,0,-2.5),r.Vector3.new(0,0,2.5)} do
		check(not inWall(pos+offset),"Wall blocks an arrival landing")
	end
end
for z=portalPos.Z-3,portalPos.Z+3 do
	for _,x in {-8,0,8} do check(not inWall(r.Vector3.new(x,3,z)),"Rear wall blocks the return portal trigger") end
end
for _,item in model:GetDescendants() do
	if item:IsA("BasePart") then
		parts+=1
		check(item.Anchored,"Unanchored arena geometry: "..item.Name)
		local pos=config.Origin:PointToObjectSpace(item.CFrame.Position)
		if item.Name=="RimWall" or item.Name=="RimCoping" or item.Name=="LanternPier" then
			local minX,minZ,maxX,maxZ=localBounds(item)
			check(not (maxZ>87 and minZ<108 and minX<11.998 and maxX> -11.998),"Perimeter blocks the 24-stud entrance")
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
print(string.format("PASS: %d arena geometry checks; %d anchored parts, %d canonical pumpkins, 6 separated arrivals, open 180-stud floor, 24-stud entrance, original low decor and continuous invisible 32-stud barriers",checks,parts,pumpkins))
