--!strict
-- مناطق الوحوش: طريق طالع من الساحة بيعدّي على مناطق ورا بعض، وكل ما تبعد الأم بتبقى أقوى.
-- في كل منطقة أعشاش، كل عش فيه وحش أم وحواليه صغارها.
-- لازم تقتل الأم الأول عشان تقدر تاخد الصغار، وكل 10 دقايق الأعشاش بتتجدد بوحوش تانية.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CarryService = require(script.Parent.CarryService)
local MonsterModels = require(script.Parent.MonsterModels)

local makePart = Build.MakePart
local makeBillboard = Build.MakeBillboard
local makePrompt = Build.MakePrompt

local ZONE_LENGTH = 140
local ZONE_HALF_Z = 100
local ROAD_WIDTH = 20
local NEST_RADIUS = 17
local NEST_Z = 55
local NEST_TOP = 1

type Nest = {
	Zone: Config.Zone,
	Center: Vector3,
	Folder: Folder,
	Species: string?,
	Alive: boolean,
	Health: number,
	MaxHealth: number,
	LastHit: number,
	Mother: BasePart?, -- الـ HumanoidRootPart بتاع الأم
	MotherModel: Model?,
	HealthFill: Frame?,
	HealthText: TextLabel?,
	Babies: { BasePart },
	Damagers: { [Player]: number },
	Target: CombatService.Target?,
}

local ZoneService = {}

-- حدود المناطق (الجبال بتلف حواليها)
ZoneService.ZoneHalfZ = ZONE_HALF_Z
ZoneService.ZonesEndX = PlotService.ZonesStartX + #Config.Zones * ZONE_LENGTH

local zonesFolder: Folder
local nests: { Nest } = {}
local gateLabels: { { Label: TextLabel, Title: string } } = {}
local nextResetAt = 0

local function zoneStartX(index: number): number
	return PlotService.ZonesStartX + (index - 1) * ZONE_LENGTH
end

local function stars(count: number): string
	return string.rep("⭐", count)
end

local function rarityHex(species: string): string
	return Build.ColorToHex(Config.Rarities[Config.Species[species].Rarity].Color)
end

-- شكل المنطقة ---------------------------------------------------------------------

local function decorate(index: number, zone: Config.Zone, folder: Folder, nestCenters: { Vector3 })
	local random = Random.new(index * 1000)
	local x0 = zoneStartX(index)
	local placed = 0
	local attempts = 0
	while placed < 22 and attempts < 200 do
		attempts += 1
		local position = Vector3.new(
			random:NextNumber(x0 + 8, x0 + ZONE_LENGTH - 8),
			0,
			random:NextNumber(-ZONE_HALF_Z + 6, ZONE_HALF_Z - 6)
		)
		local blocked = math.abs(position.Z) < ROAD_WIDTH / 2 + 6
		for _, center in nestCenters do
			if (Vector3.new(center.X, 0, center.Z) - position).Magnitude < NEST_RADIUS + 8 then
				blocked = true
			end
		end
		if blocked then
			continue
		end
		placed += 1
		local spin = CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)

		if zone.Decoration == "Flowers" then
			local bush = random:NextNumber() < 0.4
			if bush then
				makePart({
					Name = "Bush",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * random:NextNumber(3, 5),
					Position = position + Vector3.new(0, 1.5, 0),
					Color = Color3.fromRGB(70, 160, 70),
					Material = Enum.Material.Grass,
					CanCollide = false,
					Parent = folder,
				})
			else
				local colors = { Color3.fromRGB(255, 120, 180), Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 255, 255) }
				for i = 1, 4 do
					makePart({
						Name = "Flower",
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * 1.2,
						Position = position + Vector3.new(random:NextNumber(-2, 2), 0.6, random:NextNumber(-2, 2)),
						Color = colors[(i % #colors) + 1],
						Material = Enum.Material.SmoothPlastic,
						CanCollide = false,
						Parent = folder,
					})
				end
			end
		elseif zone.Decoration == "Trees" then
			local height = random:NextNumber(8, 13)
			makePart({
				Name = "Trunk",
				Size = Vector3.new(1.6, height, 1.6),
				Position = position + Vector3.new(0, height / 2, 0),
				Color = Color3.fromRGB(110, 75, 45),
				Material = Enum.Material.Wood,
				Parent = folder,
			})
			makePart({
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * random:NextNumber(8, 11),
				Position = position + Vector3.new(0, height + 2, 0),
				Color = Color3.fromRGB(40, 110 + random:NextInteger(0, 40), 45),
				Material = Enum.Material.Grass,
				CanCollide = false,
				Parent = folder,
			})
		elseif zone.Decoration == "Lava" then
			if random:NextNumber() < 0.55 then
				makePart({
					Name = "Lava",
					Size = Vector3.new(random:NextNumber(10, 24), 0.3, random:NextNumber(3, 7)),
					CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * spin,
					Color = Color3.fromRGB(255, 110, 20),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Parent = folder,
				})
			else
				local size = random:NextNumber(3, 7)
				makePart({
					Name = "Rock",
					Size = Vector3.new(size, size * 0.8, size),
					CFrame = CFrame.new(position + Vector3.new(0, size * 0.4, 0)) * spin,
					Color = Color3.fromRGB(45, 35, 35),
					Material = Enum.Material.Basalt,
					Parent = folder,
				})
			end
		elseif zone.Decoration == "Crystals" then
			local height = random:NextNumber(5, 12)
			makePart({
				Name = "Crystal",
				Size = Vector3.new(2, height, 2),
				CFrame = CFrame.new(position + Vector3.new(0, height / 2 - 0.5, 0))
					* spin
					* CFrame.Angles(random:NextNumber(-0.25, 0.25), 0, random:NextNumber(-0.25, 0.25)),
				Color = Color3.fromRGB(170, 70, 255),
				Material = Enum.Material.Neon,
				Parent = folder,
			})
		elseif zone.Decoration == "Desert" then
			if random:NextNumber() < 0.6 then
				-- صبّار
				local height = random:NextNumber(4, 8)
				local green = Color3.fromRGB(80, 150, 70)
				makePart({ Name = "Cactus", Size = Vector3.new(1.4, height, 1.4), Position = position + Vector3.new(0, height / 2, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
				for _, side in { -1, 1 } do
					if random:NextNumber() < 0.7 then
						local armY = random:NextNumber(height * 0.35, height * 0.7)
						makePart({ Name = "CactusArm", Size = Vector3.new(1.6, 0.9, 0.9), Position = position + Vector3.new(side * 1.1, armY, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
						makePart({ Name = "CactusArm", Size = Vector3.new(0.9, 1.8, 0.9), Position = position + Vector3.new(side * 1.6, armY + 1.1, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
					end
				end
			else
				local size = random:NextNumber(2.5, 5)
				makePart({ Name = "Rock", Size = Vector3.new(size, size * 0.7, size), CFrame = CFrame.new(position + Vector3.new(0, size * 0.35, 0)) * spin, Color = Color3.fromRGB(200, 160, 105), Material = Enum.Material.Sandstone, Parent = folder })
			end
		elseif zone.Decoration == "Ice" then
			if random:NextNumber() < 0.5 then
				local height = random:NextNumber(4, 9)
				makePart({
					Name = "IceCrystal",
					Size = Vector3.new(1.8, height, 1.8),
					CFrame = CFrame.new(position + Vector3.new(0, height / 2 - 0.5, 0)) * spin * CFrame.Angles(random:NextNumber(-0.3, 0.3), 0, random:NextNumber(-0.3, 0.3)),
					Color = Color3.fromRGB(150, 215, 255),
					Material = Enum.Material.Ice,
					Transparency = 0.15,
					Parent = folder,
				})
			else
				-- شجرة صنوبر عليها تلج
				makePart({ Name = "Trunk", Size = Vector3.new(1, 2, 1), Position = position + Vector3.new(0, 1, 0), Color = Color3.fromRGB(100, 70, 45), Material = Enum.Material.Wood, Parent = folder })
				for i, width in { 5, 3.6, 2.2 } do
					makePart({ Name = "Pine", Size = Vector3.new(width, 1.6, width), Position = position + Vector3.new(0, 1.4 + i * 1.5, 0), Color = if i % 2 == 0 then Color3.fromRGB(60, 110, 80) else Color3.fromRGB(240, 248, 255), Material = Enum.Material.Snow, CanCollide = false, Parent = folder })
				end
			end
		end
	end
end

local function buildGate(index: number, zone: Config.Zone, folder: Folder)
	local x = zoneStartX(index)
	local stoneColor = Color3.fromRGB(105, 105, 110)
	local pillarZ = ROAD_WIDTH / 2 + 2
	for _, side in { -1, 1 } do
		makePart({
			Name = "GatePillar",
			Size = Vector3.new(4, 16, 4),
			Position = Vector3.new(x, 8, side * pillarZ),
			Color = stoneColor,
			Material = Enum.Material.Cobblestone,
			Parent = folder,
		})
		-- سور واطي على حدود المنطقة عشان الطريق يعدّي من البوابة
		local wallLength = ZONE_HALF_Z - pillarZ - 2
		makePart({
			Name = "ZoneWall",
			Size = Vector3.new(2, 4, wallLength),
			Position = Vector3.new(x, 2, side * (pillarZ + 2 + wallLength / 2)),
			Color = stoneColor,
			Material = Enum.Material.Cobblestone,
			Parent = folder,
		})
	end
	local beam = makePart({
		Name = "GateBeam",
		Size = Vector3.new(4, 3, pillarZ * 2 + 4),
		Position = Vector3.new(x, 17.5, 0),
		Color = zone.AccentColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local gui, label = makeBillboard(beam, UDim2.fromScale(34, 11), Vector3.new(0, 7, 0), 160)
	gui.AlwaysOnTop = false
	local title = string.format(
		'<font color="%s">ZONE %d · %s</font>\n%s %s',
		Build.ColorToHex(zone.AccentColor),
		index,
		string.upper(zone.Name),
		stars(zone.Stars),
		string.upper(zone.Difficulty)
	)
	label.Text = title
	table.insert(gateLabels, { Label = label, Title = title })
end

local function buildZone(index: number, zone: Config.Zone)
	local folder = Instance.new("Folder")
	folder.Name = "Zone" .. index .. "_" .. zone.Name
	folder.Parent = zonesFolder

	local x0 = zoneStartX(index)
	makePart({
		Name = "Ground",
		Size = Vector3.new(ZONE_LENGTH, 2, ZONE_HALF_Z * 2),
		Position = Vector3.new(x0 + ZONE_LENGTH / 2, -1, 0),
		Color = zone.GroundColor,
		Material = zone.GroundMaterial,
		Parent = folder,
	})
	makePart({
		Name = "Road",
		Size = Vector3.new(ZONE_LENGTH, 0.2, ROAD_WIDTH),
		Position = Vector3.new(x0 + ZONE_LENGTH / 2, 0.1, 0),
		Color = Color3.fromRGB(150, 120, 90),
		Material = Enum.Material.Cobblestone,
		Parent = folder,
	})
	buildGate(index, zone, folder)

	local centers: { Vector3 } = {}
	for n = 1, Config.NestsPerZone do
		local x = x0 + ZONE_LENGTH * n / (Config.NestsPerZone + 1)
		local z = if n % 2 == 1 then -NEST_Z else NEST_Z
		local center = Vector3.new(x, NEST_TOP, z)
		table.insert(centers, center)

		makePart({
			Name = "Nest",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(NEST_TOP, NEST_RADIUS * 2, NEST_RADIUS * 2),
			CFrame = CFrame.new(x, NEST_TOP / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = zone.AccentColor:Lerp(Color3.fromRGB(70, 70, 75), 0.6),
			Material = Enum.Material.Slate,
			Parent = folder,
		})

		local nestFolder = Instance.new("Folder")
		nestFolder.Name = "Nest" .. n
		nestFolder.Parent = folder
		table.insert(nests, {
			Zone = zone,
			Center = center,
			Folder = nestFolder,
			Species = nil,
			Alive = false,
			Health = 0,
			MaxHealth = zone.MotherHealth,
			LastHit = 0,
			Mother = nil,
			MotherModel = nil,
			HealthFill = nil,
			HealthText = nil,
			Babies = {},
			Damagers = {},
			Target = nil,
		})
	end

	decorate(index, zone, folder, centers)
end

-- الأم والصغار ----------------------------------------------------------------------

local function updateHealthBar(nest: Nest)
	local fill = nest.HealthFill
	local text = nest.HealthText
	if not fill or not text then
		return
	end
	local ratio = math.clamp(nest.Health / nest.MaxHealth, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	text.Text = MonsterMath.FormatNumber(math.max(0, nest.Health)) .. " / " .. MonsterMath.FormatNumber(nest.MaxHealth)
end

local function babyText(nest: Nest): string
	local species = nest.Species :: string
	local name = Config.Species[species].DisplayName
	if nest.Alive then
		return string.format('<font color="%s">%s</font>\n🔒 Defeat the mother', rarityHex(species), name)
	end
	return string.format('<font color="%s">%s</font>\n✋ Hold E to take', rarityHex(species), name)
end

local function killMother(nest: Nest, killer: Player)
	nest.Alive = false
	nest.Health = 0
	CombatService.Unregister(nest.Target)
	nest.Target = nil
	if nest.MotherModel then
		nest.MotherModel:Destroy()
	end
	nest.MotherModel = nil
	nest.Mother = nil
	nest.HealthFill = nil
	nest.HealthText = nil
	for _, baby in nest.Babies do
		local prompt = baby:FindFirstChild("TakePrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = true
		end
		local info = baby:FindFirstChild("Info")
		local label = info and info:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = babyText(nest)
		end
	end
	local name = Config.Species[nest.Species :: string].DisplayName
	for player in nest.Damagers do
		if player.Parent then
			MonsterService.Notify(
				player,
				"🏆 " .. killer.DisplayName .. " finished off the " .. name .. " mother! Grab her babies!",
				"success"
			)
		end
	end
end

local function attack(player: Player, nest: Nest, damage: number)
	if not nest.Alive then
		return
	end
	nest.Health -= damage
	nest.Damagers[player] = (nest.Damagers[player] or 0) + damage
	nest.LastHit = os.clock()

	if nest.MotherModel then
		PlotService.Flash(nest.MotherModel, Color3.fromRGB(255, 80, 80))
	end

	if nest.Health <= 0 then
		killMother(nest, player)
	else
		updateHealthBar(nest)
	end
end

-- الصغير بيتشال على ضهرك، ولازم توصله قاعدتك عشان يبقى بتاعك
local function take(player: Player, nest: Nest, baby: BasePart)
	if nest.Alive or not baby.Parent or not nest.Species then
		return
	end
	if not nest.Damagers[player] then
		MonsterService.Notify(player, "Help defeat the mother first to take her babies!", "error")
		return
	end
	local cargo: CarryService.Cargo = { Kind = "Monster", Species = nest.Species, Mutation = MonsterService.RollMutation(1) }
	if CarryService.StartCarry(player, cargo) then
		local babyModel = baby.Parent
		if babyModel and babyModel:IsA("Model") then
			babyModel:Destroy()
		else
			baby:Destroy()
		end
		local index = table.find(nest.Babies, baby)
		if index then
			table.remove(nest.Babies, index)
		end
	end
end

local function clearNest(nest: Nest)
	CombatService.Unregister(nest.Target)
	nest.Target = nil
	nest.Folder:ClearAllChildren()
	nest.Mother = nil
	nest.MotherModel = nil
	nest.HealthFill = nil
	nest.HealthText = nil
	nest.Babies = {}
	nest.Damagers = {}
	nest.Alive = false
end

-- الوحش اللي بيطلع في العش: بالندرة (Config.NestRarityWeights)، ومختلف عن اللي قبله لو ينفع
local function pickSpecies(nest: Nest): string
	local pool = nest.Zone.Species
	local total = 0
	local weights: { [string]: number } = {}
	for _, species in pool do
		local rarity = Config.Species[species].Rarity
		local weight = Config.NestRarityWeights[rarity] or 1
		if species == nest.Species and #pool > 1 then
			weight = 0
		end
		weights[species] = weight
		total += weight
	end
	local roll = math.random() * total
	for _, species in pool do
		roll -= weights[species]
		if roll <= 0 then
			return species
		end
	end
	return pool[1]
end

-- نسخة من الـ Rig بتاع الوحش على الأرض (رجليه على الأرض بالظبط)
local function placeRig(species: string, stage: string, position: Vector3, facing: Vector3, scale: number): Model?
	local info = Config.Species[species].Model
	local model = info and MonsterModels.Get(info.Region, info.Index, stage)
	if not model then
		return nil
	end
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	local pivotHeight = (model:GetAttribute("Scale") or 1) * scale
	model:SetAttribute("PivotHeight", pivotHeight)
	model:PivotTo(CFrame.lookAt(position + Vector3.new(0, pivotHeight, 0), Vector3.new(facing.X, position.Y + pivotHeight, facing.Z)))
	return model
end

local function spawnNest(nest: Nest)
	clearNest(nest)

	local species = pickSpecies(nest)
	nest.Species = species
	nest.Alive = true
	nest.MaxHealth = nest.Zone.MotherHealth
	nest.Health = nest.MaxHealth
	nest.LastHit = 0

	local name = Config.Species[species].DisplayName
	-- الأم: الـ Adult مكبّرة، بتبص على الطريق
	local roadSide = Vector3.new(nest.Center.X, nest.Center.Y, 0)
	local motherModel = placeRig(species, "Adult", nest.Center, roadSide, Config.MotherScale)
	if not motherModel then
		warn("[ZoneService] Missing monster model for", species)
		return
	end
	motherModel.Name = "Mother"
	motherModel:SetAttribute("AnimState", "Idle")
	motherModel.Parent = nest.Folder
	local mother = motherModel.PrimaryPart :: BasePart
	nest.Mother = mother
	nest.MotherModel = motherModel
	local extents = motherModel:GetExtentsSize()
	local height = extents.Y - (motherModel:GetAttribute("PivotHeight") :: number)

	-- مقاسات الـ Billboards بالـ studs عشان تصغر مع البعد وماتركبش على بعض
	local gui, label = makeBillboard(mother, UDim2.fromScale(16, 5.5), Vector3.new(0, height + 4, 0), 120)
	gui.Name = "Info"
	gui.AlwaysOnTop = false
	label.Size = UDim2.fromScale(1, 0.6)
	label.Text = string.format('<font color="%s">%s</font> · MOTHER\n🏏 Hit her with your bat', rarityHex(species), name)

	local bar = Instance.new("Frame")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromScale(1, 0.32)
	bar.Position = UDim2.fromScale(0, 0.66)
	bar.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 50, 50)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HealthText"
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.FredokaOne
	hpText.TextScaled = true
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.TextStrokeTransparency = 0.3
	hpText.ZIndex = 2
	hpText.Parent = bar
	nest.HealthFill = fill
	nest.HealthText = hpText
	updateHealthBar(nest)

	-- المضرب بيضربها لما تبقى قريب منها
	nest.Target = CombatService.Register({
		Part = mother,
		Radius = math.max(extents.X, extents.Z) / 2,
		OnHit = function(player: Player, damage: number)
			attack(player, nest, damage)
		end,
	})

	-- الصغار: نسخ Baby حوالين الأم
	local ring = math.max(extents.X, extents.Z) / 2 + 5
	for i = 1, Config.BabiesPerNest do
		local angle = (i / Config.BabiesPerNest) * math.pi * 2
		local position = nest.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * ring
		local babyModel = placeRig(species, "Baby", position, roadSide, 1)
		if not babyModel then
			continue
		end
		babyModel.Name = "Baby"
		babyModel.Parent = nest.Folder
		local baby = babyModel.PrimaryPart :: BasePart
		local babyHeight = babyModel:GetExtentsSize().Y - (babyModel:GetAttribute("PivotHeight") :: number)
		local babyGui, babyLabel = makeBillboard(baby, UDim2.fromScale(7, 2.2), Vector3.new(0, babyHeight + 2, 0), 60)
		babyGui.Name = "Info"
		babyGui.AlwaysOnTop = false
		babyLabel.Text = babyText(nest)
		local takePrompt = makePrompt(baby, "TakePrompt", "Take", Enum.KeyCode.E, Config.Combat.TakeHoldDuration)
		takePrompt.ObjectText = name
		takePrompt.Enabled = false
		takePrompt.MaxActivationDistance = 10
		takePrompt.Triggered:Connect(function(player)
			take(player, nest, baby)
		end)
		table.insert(nest.Babies, baby)
	end
end

local function resetAll()
	for _, nest in nests do
		spawnNest(nest)
	end
	nextResetAt = os.clock() + Config.ZoneResetInterval
end

-- اللوب -----------------------------------------------------------------------------

-- الأم بتضرب أي لاعب قريب منها، والـ HP بيرجع كامل لو محدش ضربها شوية.
local function motherTick()
	local now = os.clock()
	for _, nest in nests do
		local mother = nest.Mother
		if not nest.Alive or not mother then
			continue
		end
		if nest.Health < nest.MaxHealth and now - nest.LastHit > Config.Combat.MotherRegenDelay then
			nest.Health = nest.MaxHealth
			nest.Damagers = {}
			updateHealthBar(nest)
		end
		local attacking = false
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local flat = Vector3.new(root.Position.X - mother.Position.X, 0, root.Position.Z - mother.Position.Z)
				if flat.Magnitude <= Config.Combat.MotherAttackRange then
					humanoid:TakeDamage(nest.Zone.MotherDamage)
					attacking = true
				end
			end
		end
		-- الأنيميشن: بتهاجم لما حد قريب منها
		if nest.MotherModel then
			nest.MotherModel:SetAttribute("AnimState", if attacking then "Attack" else "Idle")
		end
	end
end

local function updateGateTimers()
	local left = math.max(0, math.ceil(nextResetAt - os.clock()))
	local timer = string.format("🔄 New monsters in %d:%02d", left // 60, left % 60)
	for _, gate in gateLabels do
		gate.Label.Text = gate.Title .. "\n" .. timer
	end
end

function ZoneService.CleanupPlayer(player: Player)
	for _, nest in nests do
		nest.Damagers[player] = nil
	end
end

function ZoneService.Init()
	zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = workspace

	for index, zone in Config.Zones do
		buildZone(index, zone)
	end
	resetAll()

	task.spawn(function()
		while true do
			task.wait(Config.Combat.MotherAttackInterval)
			motherTick()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if os.clock() >= nextResetAt then
				resetAll()
				for _, player in Players:GetPlayers() do
					MonsterService.Notify(player, "🔄 The monster zones have new monsters!", "info")
				end
			end
			updateGateTimers()
		end
	end)
	updateGateTimers()
end

return ZoneService
