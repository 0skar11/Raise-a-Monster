--!strict
-- Halloween plaza decorations (jack-o-lanterns, dead trees, tombstones, lanterns, wisps). Kept free of gameplay
-- requires so Studio Edit mode can require it from the command bar and drop real, movable props into the map.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PumpkinVisual = require(ReplicatedStorage.Shared.PumpkinVisual)
local Build = require(script.Parent.Build)

local settings = Config.Halloween
local pumpkinSettings = settings.Pumpkins
local makePart = Build.MakePart

local HalloweenProps = {}

local TAG_MERCHANT = "HalloweenMerchant"
local ORANGE = Color3.fromRGB(240, 120, 25)

local function folder(name: string, parent: Instance): Folder
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function jackOLantern(parent: Instance, position: Vector3, size: number, yaw: number, lit: boolean, tint: Color3?)
	local width = size * 1.15
	local height = PumpkinVisual.MeshSize.Y * width / PumpkinVisual.MeshSize.X
	local base = CFrame.new(position + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
	local body = PumpkinVisual.Create("Pumpkin", width, base, tint)
	body.Parent = parent
	if lit then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = settings.Atmosphere.LanternRange
		light.Brightness = 1.3
		light.Shadows = false
		light.Parent = body
	end
end

local function deadTree(parent: Instance, position: Vector3, height: number, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local wood = Color3.fromRGB(46, 34, 40)
	local common = { CanCollide = false, CanQuery = false, CanTouch = false, Color = wood, Material = Enum.Material.Wood, Parent = parent }
	local function part(props: { [string]: any }): Part
		for key, value in common do props[key] = value end
		return makePart(props)
	end
	part({ Name = "DeadTrunk", Size = Vector3.new(1.4, height, 1.4), CFrame = base * CFrame.new(0, height / 2, 0) })
	for index, side in { -1, 1, -1 } do
		part({
			Name = "DeadBranch",
			Size = Vector3.new(0.7, height * 0.5, 0.7),
			CFrame = base * CFrame.new(side * height * 0.18, height * (0.55 + 0.12 * index), 0) * CFrame.Angles(0, index, side * math.rad(40)),
		})
	end
end

local function tombstone(parent: Instance, position: Vector3, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local stone = Color3.fromRGB(110, 110, 120)
	makePart({ Name = "Tombstone", Size = Vector3.new(3, 3.4, 0.9), CFrame = base * CFrame.new(0, 1.7, 0), CanCollide = false, CanQuery = false, CanTouch = false, Color = stone, Material = Enum.Material.Slate, Parent = parent })
	makePart({
		Name = "TombstoneTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 3, 3),
		CFrame = base * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, math.pi / 2, 0),
		CanCollide = false, CanQuery = false, CanTouch = false, Color = stone, Material = Enum.Material.Slate, Parent = parent,
	})
end

local function clearOf(x: number, z: number, margin: number): boolean
	for _, zone in pumpkinSettings.KeepClear do
		if math.sqrt((zone.X - x) ^ 2 + (zone.Z - z) ^ 2) < zone.Radius + margin then
			return false
		end
	end
	return true
end

local function populateProps(parent: Instance)
	local a = settings.Atmosphere
	local random = Random.new(a.Seed)
	local placed, attempts = 0, 0
	while placed < a.PumpkinPropCount and attempts < a.PumpkinPropCount * 12 do
		attempts += 1
		-- Keep the central lane and the two new end plots clear.
		local x = random:NextNumber(Config.Map.PlazaMaxX + 5, Config.Map.LobbyMaxX - 8)
		local z = random:NextNumber(-190, Config.Map.PlazaHalfZ - 14)
		-- keep the path in front of the zone gate and the shop area open
		if clearOf(x, z, 4) then
			placed += 1
			local pos = Vector3.new(x, 0.2, z)
			local yaw = random:NextNumber(0, math.pi * 2)
			local kind = placed % 6
			if kind == 0 then
				deadTree(parent, pos, random:NextNumber(8, 13), yaw)
			elseif kind == 1 then
				tombstone(parent, pos, yaw)
			elseif kind == 2 or kind == 3 then
				jackOLantern(parent, pos, random:NextNumber(2.4, 3.6), yaw, true)
			else
				-- a small pile: one lit jack and two plain pumpkins
				jackOLantern(parent, pos, 3, yaw, true)
				jackOLantern(parent, pos + Vector3.new(2.6, 0, 1.2), 2, yaw + 1, false)
				jackOLantern(parent, pos + Vector3.new(-2.2, 0, 1.8), 1.7, yaw + 2, false, Color3.fromRGB(225, 95, 20))
			end
		end
	end
	-- the plaza, scattered at random (no rows): trees, tombstones and pumpkin piles with a minimum gap between them
	local median = pumpkinSettings.Median
	local medianRandom = Random.new(a.Seed + 1)
	local taken: { Vector3 } = {}
	local scattered, tries = 0, 0
	while scattered < median.Count and tries < median.Count * 30 do
		tries += 1
		local x = medianRandom:NextNumber(median.MinX, median.MaxX)
		local zz = medianRandom:NextNumber(-median.HalfLength, median.HalfLength)
		local ok = true
		for _, zone in median.KeepClear do
			if math.sqrt((zone.X - x) ^ 2 + (zone.Z - zz) ^ 2) < zone.Radius then
				ok = false
				break
			end
		end
		if ok then
			for _, other in taken do
				if math.sqrt((other.X - x) ^ 2 + (other.Z - zz) ^ 2) < median.MinGap then
					ok = false
					break
				end
			end
		end
		if ok then
			scattered += 1
			table.insert(taken, Vector3.new(x, 0, zz))
			local pos = Vector3.new(x, 0.2, zz)
			local yaw = medianRandom:NextNumber(0, math.pi * 2)
			local roll = medianRandom:NextNumber()
			if roll < 0.22 then
				deadTree(parent, pos, medianRandom:NextNumber(8, 15), yaw)
			elseif roll < 0.4 then
				tombstone(parent, pos, yaw)
			elseif roll < 0.7 then
				jackOLantern(parent, pos, medianRandom:NextNumber(2.2, 3.8), yaw, true)
				if medianRandom:NextNumber() < 0.6 then
					jackOLantern(parent, pos + Vector3.new(medianRandom:NextNumber(-3, 3), 0, medianRandom:NextNumber(-3, 3)), medianRandom:NextNumber(1.5, 2.4), yaw + 1, false)
				end
			elseif roll < 0.85 then
				jackOLantern(parent, pos, 3, yaw, true)
				jackOLantern(parent, pos + Vector3.new(2.6, 0, 1.2), 2, yaw + 1, false)
				jackOLantern(parent, pos + Vector3.new(-2.2, 0, 1.8), 1.7, yaw + 2, false, Color3.fromRGB(225, 95, 20))
			else
				deadTree(parent, pos, medianRandom:NextNumber(9, 13), yaw)
				jackOLantern(parent, pos + Vector3.new(medianRandom:NextNumber(-4, 4), 0, medianRandom:NextNumber(-4, 4)), 2.2, yaw, true)
			end
		end
	end
	-- a lantern on each side of every zone gate road
	for index = 1, #Config.Zones do
		local gateX = Config.Map.ZonesStartX + (index - 1) * Config.Map.ZoneLength
		for _, side in { -1, 1 } do
			jackOLantern(parent, Vector3.new(gateX + 4, 0.2, side * (Config.Map.RoadWidth / 2 + 7)), 3.6, if side < 0 then math.pi / 2 else -math.pi / 2, true)
		end
	end
	-- drifting embers and wisps over the whole plaza
	local centers = {}
	for z = -200, 200, 100 do
		table.insert(centers, Vector3.new((Config.Map.PlazaMinX + Config.Map.ZonesStartX) / 2, 14, z))
	end
	for _, center in centers do
		local emitterPart = makePart({
			Name = "AmbientEmitter", Size = Vector3.new(100, 8, 90), Position = center, Transparency = 1,
			CanCollide = false, CanQuery = false, CanTouch = false, Parent = parent,
		})
		for _, spec in {
			{ Color = Color3.fromRGB(255, 140, 40), Rate = 6, Speed = 1.5 },
			{ Color = Color3.fromRGB(170, 120, 255), Rate = 4, Speed = 0.8 },
		} do
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Wisps"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(spec.Color)
			emitter.LightEmission = 0.8
			emitter.Rate = spec.Rate
			emitter.Lifetime = NumberRange.new(7, 12)
			emitter.Speed = NumberRange.new(spec.Speed * 0.5, spec.Speed)
			emitter.Acceleration = Vector3.new(0, 0.4, 0)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.7), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) })
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.Parent = emitterPart
		end
	end
end


local function buildMerchant(holder: Instance): Model
	local info = settings.Merchant
	local model = Instance.new("Model")
	model.Name = "PumpkinMerchant"
	local origin = CFrame.lookAt(info.Position + Vector3.new(0, 0.2, 0), Vector3.new(info.FaceTowards.X, info.Position.Y + 0.2, info.FaceTowards.Z))
	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		return makePart({
			Name = name, Size = size, CFrame = origin * CFrame.new(offset), Color = color,
			Material = material or Enum.Material.Fabric, Shape = shape or Enum.PartType.Block,
			CanCollide = false, CanQuery = true, CanTouch = false, Parent = model,
		})
	end
	local robe = Color3.fromRGB(58, 30, 84)
	limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), robe)
	limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), robe)
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), robe)
	limb("RobeHem", Vector3.new(2.6, 1.6, 1.5), Vector3.new(0, 1.4, 0), Color3.fromRGB(45, 22, 66))
	limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, -0.3), Color3.fromRGB(70, 38, 100))
	limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, -0.3), Color3.fromRGB(70, 38, 100))
	local head = limb("Head", Vector3.new(2.5, 2.2, 2.5), Vector3.new(0, 5.2, 0), ORANGE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	PumpkinVisual.Fit(head)
	local brim = limb("HatBrim", Vector3.new(0.25, 3.4, 3.4), Vector3.new(0, 6.15, 0), Color3.fromRGB(30, 20, 40), Enum.Material.Fabric, Enum.PartType.Cylinder)
	brim.CFrame = origin * CFrame.new(0, 6.15, 0) * CFrame.Angles(0, 0, math.pi / 2)
	limb("HatCone", Vector3.new(2, 1.9, 2), Vector3.new(0, 7.15, 0), Color3.fromRGB(30, 20, 40))
	local lantern = limb("Lantern", Vector3.new(0.9, 1.1, 0.9), Vector3.new(2.1, 2.2, -0.9), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 22
	glow.Brightness = 1.6
	glow.Parent = lantern
	-- a counter piled with pumpkins in front of him
	limb("Counter", Vector3.new(7, 3, 2.4), Vector3.new(0, 1.5, -3.2), Color3.fromRGB(80, 50, 32), Enum.Material.Wood)
	jackOLantern(model, (origin * CFrame.new(-2, 3, -3.2)).Position, 1.8, 0.3, true)
	jackOLantern(model, (origin * CFrame.new(2.2, 3, -3.2)).Position, 1.5, -0.4, false)

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = ""
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = torso
	CollectionService:AddTag(model, TAG_MERCHANT)
	model.Parent = holder

	local gui, label = Build.MakeBillboard(head, UDim2.fromOffset(240, 60), Vector3.new(0, 4.5, 0), 90)
	gui.AlwaysOnTop = false
	label.Text = '<font color="#FFA030">' .. info.Name .. '</font>\n🎃 Trade your Candy!'
	return model
end

HalloweenProps.BuildMerchant = buildMerchant
HalloweenProps.JackOLantern = jackOLantern
HalloweenProps.ClearOf = clearOf
HalloweenProps.Populate = populateProps

-- Studio Edit mode: Workspace.HalloweenWorld.Props as authored instances. The server adopts an authored world
-- untouched, so whatever you move and save stays. Returns false when a HalloweenWorld already exists.
function HalloweenProps.BuildEditorWorld(): boolean
	if workspace:FindFirstChild("HalloweenWorld") then
		return false
	end
	local world = folder("HalloweenWorld", workspace)
	populateProps(folder("Props", world))
	buildMerchant(folder("Merchant", world))
	return true
end

return HalloweenProps
