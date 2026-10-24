-- Editable, deterministic Part geometry; used by Studio and the offline asset exporter.
local PumpkinVisual = require(script.Parent.PumpkinVisual)
local Builder = {}
local stone = Color3.fromRGB(60, 45, 70)
local purple = Color3.fromRGB(108, 28, 192)
local orange = Color3.fromRGB(255, 70, 8)

function Builder.Build(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "HalloweenPortal"
	model:SetAttribute("PortalVersion", 1)
	local function part(name, size, cf, color, material, solid, shape)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, origin * cf
		p.Color, p.Material = color, material or Enum.Material.Slate
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, solid == true, false, solid == true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if shape then p.Shape = shape end
		p.Parent = model
		return p
	end
	local function rod(name, a, b, width, color)
		local delta = b - a
		-- A local XY-plane line: the long Y axis follows the two endpoints.
		return part(name, Vector3.new(width, delta.Magnitude, width), CFrame.new((a+b)/2) * CFrame.Angles(0, 0, -math.atan2(delta.X, delta.Y)), color, Enum.Material.Neon)
	end
	local function rune(x, y, scale)
		local points = {Vector3.new(x,y+scale,-2.23), Vector3.new(x+scale*.55,y,-2.23), Vector3.new(x,y-scale,-2.23), Vector3.new(x-scale*.55,y,-2.23)}
		for i=1,4 do rod("EmberRune",points[i],points[i%4+1],.25,orange) end
	end
	for _, side in {-1,1} do
		part("Foundation",Vector3.new(7,1.5,6),CFrame.new(side*11,.75,0),stone,Enum.Material.Slate,true)
		part("FoundationCap",Vector3.new(5.8,1.4,5),CFrame.new(side*11,2,0),Color3.fromRGB(53,43,63),nil,true)
		for row=0,3 do
			part("PillarStone",Vector3.new(4.2,3.15,4.3),CFrame.new(side*11,3.95+row*3.25,0)*CFrame.Angles(0,math.rad(side*(row%2==0 and 3 or -3)),math.rad(side*(row%2==0 and 1 or -1))),stone:Lerp(Color3.fromRGB(73,54,81),row*.07),nil,true)
		end
		rune(side*11,10.5,1.3)
		rune(side*11,6.4,.7)
	end
	for i=0,10 do
		local theta = math.pi*i/10
		local x,y=11*math.cos(theta),16+11*math.sin(theta)
		part("ArchStone",Vector3.new(4,4.8,5),CFrame.new(x,y,0)*CFrame.Angles(0,0,theta-math.pi/2),stone:Lerp(Color3.fromRGB(79,57,91),(i%3)*.13),nil,true)
	end
	part("Keystone",Vector3.new(5,5.5,5),CFrame.new(0,27,0),Color3.fromRGB(49,38,59),nil,true)
	-- Keystone rune sits in front of its deeper stone.
	for i, a in {Vector3.new(0,28.5,-2.6),Vector3.new(.85,27,-2.6),Vector3.new(0,25.5,-2.6),Vector3.new(-.85,27,-2.6)} do
		local b=({Vector3.new(.85,27,-2.6),Vector3.new(0,25.5,-2.6),Vector3.new(-.85,27,-2.6),Vector3.new(0,28.5,-2.6)})[i]
		rod("KeystoneRune",a,b,.28,orange)
	end
	local surface=part("PortalSurface",Vector3.new(18,15,.25),CFrame.new(0,8.5,.2),Color3.fromRGB(75,15,130),Enum.Material.Glass)
	surface.Transparency=.2
	local crown=part("PortalCrown",Vector3.new(.24,18,18),CFrame.new(0,16,.2)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(75,15,130),Enum.Material.Glass,false,Enum.PartType.Cylinder)
	crown.Transparency=.2
	local trigger=part("TeleportTrigger",Vector3.new(17,22,4),CFrame.new(0,12,0),purple,Enum.Material.SmoothPlastic)
	trigger.Transparency=1
	trigger.CanTouch=true
	model.PrimaryPart=trigger
	local glow=Instance.new("PointLight")
	glow.Color,glow.Brightness,glow.Range=purple,1.2,26
	glow.Parent=surface
	local cloudOrigin=Instance.new("Attachment");cloudOrigin.Position=Vector3.new(0,4.5,-1);cloudOrigin.Parent=surface
	local clouds=Instance.new("ParticleEmitter")
	clouds.Name="VortexMist";clouds.Texture="rbxasset://textures/particles/smoke_main.dds"
	clouds.Color=ColorSequence.new(Color3.fromRGB(116,40,205),Color3.fromRGB(171,88,231))
	clouds.LightEmission=.8;clouds.Rate=11;clouds.Lifetime=NumberRange.new(2,3)
	clouds.Speed=NumberRange.new(.2,.7);clouds.Rotation=NumberRange.new(0,360);clouds.RotSpeed=NumberRange.new(15,30)
	clouds.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,8),NumberSequenceKeypoint.new(1,13)})
	clouds.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,.5),NumberSequenceKeypoint.new(1,1)})
	clouds.Parent=cloudOrigin
	-- Three continuous spiral arms, rather than concentric target rings.
	for arm=0,2 do
		for segment=0,27 do
			local t=segment/28
			local nextT=(segment+1)/28
			local a=t*math.pi*1.8+arm*math.pi*2/3
			local b=nextT*math.pi*1.8+arm*math.pi*2/3
			local radius=.5+t*7
			local nextRadius=.5+nextT*7
			local p=rod("VortexBand",Vector3.new(math.cos(a)*radius,13+math.sin(a)*radius,-.5),Vector3.new(math.cos(b)*nextRadius,13+math.sin(b)*nextRadius,-.5),.16+t*.24,Color3.fromRGB(147,77,221))
			p.Transparency=.22+t*.58
			p:SetAttribute("Vortex",true)
		end
	end
	local core=part("VortexCore",Vector3.new(.8,.8,.25),CFrame.new(0,13,-.6),Color3.fromRGB(192,137,255),Enum.Material.Neon,false,Enum.PartType.Ball)
	core.Transparency=.2
	for _,side in {-1,1} do
		local x,z=side*12,-4
		local height=PumpkinVisual.MeshSize.Y*4.9/PumpkinVisual.MeshSize.X
		local body=PumpkinVisual.Create("JackOLantern",4.9,origin*CFrame.new(x,height*.5,z))
		body.Parent=model
		local light=Instance.new("PointLight");light.Color=orange;light.Range=10;light.Brightness=1.1;light.Parent=body
		for level=0,1 do
			local flame=part("Wisp",Vector3.new(.2,.2,.2),CFrame.new(side*(14-level*1.7),5+level*15,.25),purple,Enum.Material.Neon)
			flame.Transparency=1
			local fx=Instance.new("ParticleEmitter")
			fx.Texture="rbxasset://textures/particles/fire_main.dds"
			fx.Color=ColorSequence.new(Color3.fromRGB(169,55,255),Color3.fromRGB(221,146,255))
			fx.LightEmission=1;fx.Rate=9;fx.Lifetime=NumberRange.new(.8,1.3);fx.Speed=NumberRange.new(2,4)
			fx.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.3),NumberSequenceKeypoint.new(.5,2),NumberSequenceKeypoint.new(1,0)})
			fx.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,.25),NumberSequenceKeypoint.new(1,1)})
			fx.SpreadAngle=Vector2.new(15,15);fx.Parent=flame
		end
	end
	return model
end

return Builder
