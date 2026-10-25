-- The approved compact arena. All scenery stays beyond the unobstructed combat floor.
local PumpkinVisual = require(script.Parent.PumpkinVisual)
local PortalBuilder = require(script.Parent.HalloweenPortalBuilder)
local Builder = {}

function Builder.Build(config): Model
	local origin = config.Origin
	local radius = config.CombatRadius or 90
	local arrival = config.ArrivalCenter or Vector3.new(0, 0, 120)
	local arrivalSize = config.ArrivalSize or Vector3.new(40, 1, 30)
	local entranceWidth = config.ConnectorWidth or 24
	-- A tiny deterministic generator keeps Studio and the offline Lune exporter identical.
	local seed = 103124
	local random = { NextNumber = function(_, low, high)
		seed = seed * 16807 % 2147483647
		return low + (high-low) * seed / 2147483647
	end }
	local model = Instance.new("Model")
	model.Name = "HalloweenArena"
	model:SetAttribute("ArenaVersion", 1)
	model:SetAttribute("CombatRadius", radius)
	model:SetAttribute("PlayerCapacity", config.Capacity or 6)
	local floor = Instance.new("Folder"); floor.Name = "FloorDetail"; floor.Parent = model
	local rim = Instance.new("Folder"); rim.Name = "Perimeter"; rim.Parent = model
	local scenery = Instance.new("Folder"); scenery.Name = "Scenery"; scenery.Parent = model
	local stone = Color3.fromRGB(68, 57, 79)
	local ember = Color3.fromRGB(255, 104, 22)
	local function part(name, size, cf, color, material, solid, parent, shape)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, origin * cf
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, solid == true, false, solid == true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Color, p.Material = color, material or Enum.Material.Slate
		if shape then p.Shape = shape end
		p.Parent = parent or model
		return p
	end
	local function line(name, a, b, width, color, material, parent, solid)
		return part(name, Vector3.new(width, width, (b-a).Magnitude), CFrame.lookAt((a+b)/2, b), color, material, solid, parent)
	end
	local function disc(name, r, thickness, top, color, parent, solid)
		return part(name, Vector3.new(thickness, r*2, r*2), CFrame.new(0, top-thickness/2, 0)*CFrame.Angles(0,0,math.pi/2), color, Enum.Material.Slate, solid, parent, Enum.PartType.Cylinder)
	end
	local function lamp(parent, color, brightness, range)
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range = color, brightness, range
		light.Shadows = false
		light.Parent = parent
	end
	-- Local fill preserves readable dodge space while the boss darkens the world.
	local moonlight = Color3.fromRGB(183, 165, 222)
	for index, position in {
		Vector3.new(-38, 30, -38), Vector3.new(38, 30, -38),
		Vector3.new(-38, 30, 38), Vector3.new(38, 30, 38),
		Vector3.new(arrival.X, 22, arrival.Z - 1),
	} do
		local fill = part("MoonlightFill_"..index, Vector3.new(1, 1, 1), CFrame.new(position), moonlight, Enum.Material.SmoothPlastic, false, scenery)
		fill.Transparency = 1
		lamp(fill, moonlight, 2, 60)
	end
	local function pumpkin(position, width, yaw, lit)
		local height = PumpkinVisual.MeshSize.Y * width / PumpkinVisual.MeshSize.X
		local p = PumpkinVisual.Create("ArenaPumpkin", width, origin*CFrame.new(position+Vector3.new(0,height/2,0))*CFrame.Angles(0,yaw,0))
		p.Parent = scenery
		if lit then lamp(p, ember, 1.1, 19) end
		return p
	end
	-- Raised island foundation is scenery beneath the single continuous combat floor.
	disc("IslandFoundation", radius+23, 8, -0.15, Color3.fromRGB(35,29,43), scenery, true)
	local combat = disc("CombatFloor", radius, 2, 0, stone, model, true)
	model.PrimaryPart = combat
	for x=-8,8 do
		for z=-8,8 do
			local pos = Vector3.new(x*10, 0.025, z*10)
			if Vector2.new(pos.X,pos.Z).Magnitude <= radius-7.2 then
				local shade = random:NextNumber(-4,5)
				part("FloorTile",Vector3.new(9.72,.05,9.72),CFrame.new(pos),Color3.fromRGB(76+shade,65+shade,87+shade),Enum.Material.Slate,false,floor)
			end
		end
	end
	-- Flush stone joints around the rim; only the central emergence seal glows faintly.
	for i=0,47 do
		local a,b=i*math.pi/24,(i+1)*math.pi/24
		for _,r in {radius-1.5, 19} do
			line("InlaidStoneRing",Vector3.new(math.sin(a)*r,.065,math.cos(a)*r),Vector3.new(math.sin(b)*r,.065,math.cos(b)*r),r<20 and .12 or .18,r<20 and Color3.fromRGB(113,58,31) or Color3.fromRGB(75,63,85),Enum.Material.SmoothPlastic,floor)
		end
	end
	for i=0,7 do
		local angle=i*math.pi/4
		local a=Vector3.new(math.sin(angle)*5,.072,math.cos(angle)*5)
		local b=Vector3.new(math.sin(angle+.16)*12,.072,math.cos(angle+.16)*12)
		local c=Vector3.new(math.sin(angle)*18,.072,math.cos(angle)*18)
		line("EmergenceCrack",a,b,.13,Color3.fromRGB(168,71,24),Enum.Material.Neon,floor)
		line("EmergenceCrack",b,c,.11,Color3.fromRGB(145,59,19),Enum.Material.SmoothPlastic,floor)
	end
	-- Low battlement ring has a 28-stud southern break aligned with the 24-stud connector.
	local wallRadius = radius+1.7
	for i=0,47 do
		local angle=(i+.5)*math.pi/24
		local x,z=math.sin(angle)*wallRadius,math.cos(angle)*wallRadius
		if not (z>0 and math.abs(x)<18.5) then
			local cf=CFrame.new(x,2,z)*CFrame.Angles(0,angle,0)
			part("RimWall",Vector3.new(12.3,4,3.5),cf,stone,Enum.Material.Slate,true,rim)
			part("RimCoping",Vector3.new(12.55,.65,4.2),cf*CFrame.new(0,2.3,0),Color3.fromRGB(64,54,74),Enum.Material.Slate,true,rim)
			if i%4==2 then
				part("LanternPier",Vector3.new(5,6.4,5),CFrame.new(x,3.2,z),Color3.fromRGB(54,43,63),Enum.Material.Slate,true,rim)
				pumpkin(Vector3.new(x,6.4,z),4.8,angle+math.pi,true)
			end
		end
	end
	-- Arrival remains flat and separate from combat, with a short broad connector.
	part("ArrivalFloor",Vector3.new(arrivalSize.X,arrivalSize.Y,arrivalSize.Z),CFrame.new(arrival.X,-arrivalSize.Y/2,arrival.Z),stone,Enum.Material.Slate,true)
	local connectorStart = radius-3
	local connectorEnd = arrival.Z-arrivalSize.Z/2+1
	part("EntryConnector",Vector3.new(entranceWidth,1,connectorEnd-connectorStart),CFrame.new(0,-.5,(connectorStart+connectorEnd)/2),stone,Enum.Material.Slate,true)
	part("PortalPlinth",Vector3.new(40,1,10),CFrame.new(0,-.5,138),stone,Enum.Material.Slate,true)
	for x=-3,3 do
		for z=0,5 do
			part("ArrivalTile",Vector3.new(5.5,.05,4.9),CFrame.new(x*5.6,.025,arrival.Z-12.5+z*5),Color3.fromRGB(56+(x+z)%3*3,47+(x+z)%3*2,64+(x+z)%3*3),Enum.Material.Slate,false,floor)
		end
	end
	for _,side in {-1,1} do
		part("ArrivalRail",Vector3.new(2.8,3.5,arrivalSize.Z+8),CFrame.new(side*21.4,1.75,arrival.Z+2),stone,Enum.Material.Slate,true,rim)
		for _,z in {106,124,139} do
			local x=side*21.4
			part("ArrivalPillar",Vector3.new(4.5,5.5,4.5),CFrame.new(x,2.75,z),Color3.fromRGB(57,45,66),Enum.Material.Slate,true,rim)
			local fire=part("LanternEmber",Vector3.new(1.4,1.9,1.4),CFrame.new(x,6.4,z),ember,Enum.Material.Neon,false,scenery)
			lamp(fire,ember,1.6,22)
		end
	end
	-- Individually spaced arrival points are metadata, never a second spawn system.
	local points = config.ArrivalPoints or { CFrame.new(-10,3.5,115),CFrame.new(0,3.5,115),CFrame.new(10,3.5,115),CFrame.new(-10,3.5,123),CFrame.new(0,3.5,123),CFrame.new(10,3.5,123) }
	for index, cf in points do
		local marker=part("ArrivalPoint_"..index,Vector3.new(1,1,1),cf,Color3.new(1,1,1),Enum.Material.SmoothPlastic,false)
		marker.Transparency=1
	end
	local portal=PortalBuilder.Build(config.ReturnPortalOrigin or origin*CFrame.new(0,0,137))
	portal.Name="ReturnPortal"
	portal:SetAttribute("PortalRole","ReturnToWorld")
	portal.Parent=model
	-- Scenic perimeter: short trees, rocks and thorn stems sit outside all dodge space.
	for i=0,31 do
		local angle=(i+.4)*math.pi/16
		local r=radius+15+random:NextNumber(-1.5,2)
		local x,z=math.sin(angle)*r,math.cos(angle)*r
		if not (z>85 and math.abs(x)<38) then
			local h=random:NextNumber(10,22)
			part("BorderRock",Vector3.new(random:NextNumber(7,12),h,random:NextNumber(7,11)),CFrame.new(x,h/2-2,z)*CFrame.Angles(random:NextNumber(-.16,.16),angle,random:NextNumber(-.25,.25)),Color3.fromRGB(54+i%3*5,43+i%3*3,68+i%3*5),Enum.Material.Slate,true,scenery)
			local shoulder=Vector3.new(x+math.cos(angle)*4,0,z-math.sin(angle)*4)
			part("CliffShard",Vector3.new(4,h*.75,5),CFrame.new(shoulder+Vector3.new(0,h*.32,0))*CFrame.Angles(.2,angle,-.28),Color3.fromRGB(43,34,57),Enum.Material.Slate,true,scenery)
			if i%3==0 then
				local treeAngle=angle+.105
				local base=Vector3.new(math.sin(treeAngle)*(radius+17),0,math.cos(treeAngle)*(radius+17))
				local lean=Vector3.new(math.cos(angle)*2,0,-math.sin(angle)*2)
				local p1=base+Vector3.new(0,8,0)+lean
				local p2=base+Vector3.new(0,17,0)-lean*.5
				local p3=base+Vector3.new(0,24,0)+lean*.8
				local bark=Color3.fromRGB(59,35,40)
				line("DeadTreeTrunk",base,p1,2.7,bark,Enum.Material.Wood,scenery,true)
				line("DeadTreeTrunk",p1,p2,1.9,bark,Enum.Material.Wood,scenery,true)
				line("DeadTreeTip",p2,p3,.9,bark,Enum.Material.Wood,scenery)
				for _,side in {-1,1} do
					local b=p1+Vector3.new(math.cos(angle)*side*8,5,math.sin(angle)*side*8)
					local c=b+Vector3.new(math.cos(angle+.7)*side*3,4,math.sin(angle+.7)*side*3)
					line("DeadTreeBranch",p1,b,1.15,bark,Enum.Material.Wood,scenery)
					line("DeadTreeTwig",b,c,.65,bark,Enum.Material.Wood,scenery)
					line("DeadTreeFork",b,b+Vector3.new(-side*2,5,side*1.5),.45,bark,Enum.Material.Wood,scenery)
				end
				local rootEnd=base+Vector3.new(-math.sin(angle)*6,.25,-math.cos(angle)*6)
				line("ThornRoot",base+Vector3.new(0,1.4,0),rootEnd,.75,bark,Enum.Material.Wood,scenery)
				for j=1,3 do
					local point=base:Lerp(rootEnd,j/4)+Vector3.new(0,.6,0)
					line("RootThorn",point,point+Vector3.new(.5,1.7,-.3),.25,Color3.fromRGB(72,39,47),Enum.Material.Wood,scenery)
				end
			else
				pumpkin(Vector3.new(x-3,0,z-2),random:NextNumber(3.1,4.1),angle+math.pi,false)
			end
		end
	end
	for _,side in {-1,1} do
		for _,z in {96,132} do
			local x=side*(z==96 and 27 or 28)
			part("TorchPedestal",Vector3.new(4,6,4),CFrame.new(x,3,z),Color3.fromRGB(61,46,70),Enum.Material.Slate,true,scenery)
			part("TorchBowl",Vector3.new(5,1,5),CFrame.new(x,6.5,z),Color3.fromRGB(30,25,35),Enum.Material.Metal,false,scenery)
			local fire=part("TorchFlame",Vector3.new(1.8,2.2,1.8),CFrame.new(x,7.5,z),ember,Enum.Material.Neon,false,scenery,Enum.PartType.Ball)
			lamp(fire,ember,1.6,24)
			local fx=Instance.new("ParticleEmitter")
			fx.Name="EmberFlame";fx.Texture="rbxasset://textures/particles/fire_main.dds"
			fx.Color=ColorSequence.new(Color3.fromRGB(255,118,24),Color3.fromRGB(255,210,93))
			fx.LightEmission=1;fx.Rate=7;fx.Lifetime=NumberRange.new(.5,.9);fx.Speed=NumberRange.new(2,4)
			fx.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.5),NumberSequenceKeypoint.new(1,0)})
			fx.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
			fx.Parent=fire
		end
	end
	-- Close the scene with broken standing stones beyond the wall, keeping the entry clear.
	for i=0,23 do
		local angle=i*math.pi/12
		local r=radius+11
		local x,z=math.sin(angle)*r,math.cos(angle)*r
		if not (z>85 and math.abs(x)<36) then
			local h=3.5+(i%4)*1.4
			part("BrokenStone",Vector3.new(6.5,h,5),CFrame.new(x,h/2-1,z)*CFrame.Angles(.08,angle,(i%2==0 and 1 or -1)*.14),Color3.fromRGB(40,33,49),Enum.Material.Slate,true,scenery)
		end
	end
	return model
end

return Builder
