--!strict
-- مناطق الوحوش: طريق طالع من الساحة بيعدّي على مناطق ورا بعض، وكل ما تبعد الأم بتبقى أقوى.
-- في كل منطقة أعشاش، كل عش فيه وحش أم وحواليه صغارها.
-- لازم تقتل الأم الأول عشان تقدر تاخد الصغار، وكل 10 دقايق الأعشاش بتتجدد بوحوش تانية.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CarryService = require(script.Parent.CarryService)
local MonsterModels = require(script.Parent.MonsterModels)
local MonsterAttack = require(script.Parent.MonsterAttack)

local makePart = Build.MakePart
local makeBillboard = Build.MakeBillboard
local makePrompt = Build.MakePrompt

local ZONE_LENGTH = Config.Map.ZoneLength
local ZONE_HALF_Z = Config.Map.ZoneHalfZ
local ROAD_WIDTH = Config.Map.RoadWidth
local NEST_RADIUS = Config.Map.NestRadius
local NEST_Z = Config.Map.NestZ
local NEST_TOP = Config.Map.NestTop

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
	Aggro: Player?, -- آخر واحد ضربها، وهي بتجري وراه
	Moving: boolean,
	Style: Config.MotherStyle?, -- الـ M1 بتاعها (حسب شكل جسمها)
	NextAttackAt: number,
	Engaged: boolean, -- فيه حد قريب منها دلوقتي
	WindingUntil: number, -- واقفة بتجهّز الضربة لحد الوقت ده
}

local ZoneService = {}

-- حدود المناطق (الجبال بتلف حواليها)
ZoneService.ZoneHalfZ = ZONE_HALF_Z
ZoneService.ZonesEndX = PlotService.ZonesStartX + #Config.Zones * ZONE_LENGTH

local zonesFolder: Folder
local nests: { Nest } = {}
local gateLabels: { { Label: TextLabel, Title: string } } = {}
local boardResetLabels: { TextLabel } = {}
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

-- A Studio-authored gate (Workspace.ZoneGates.ZoneGate_1, tag "ZoneGateBoard", attribute ZoneIndex) replaces the
-- stone gate: it is never rebuilt or moved by code, the other zones get clones of it at the same offset from their
-- zone start, and the walls are rebuilt in its style so the fence runs straight into its posts (one opening only).
local WALL_COLOR = Color3.fromRGB(34, 22, 48)
local WALL_TRIM = Color3.fromRGB(255, 130, 30)

local function authoredGateTemplate(): Model?
	for _, model in CollectionService:GetTagged("ZoneGateBoard") do
		if model:IsA("Model") and not model:GetAttribute("GateClone") then
			return model
		end
	end
	return nil
end

-- outer z edges of the two posts and their x, so the walls can start exactly at the gate
local function gatePostBounds(board: Model): (number?, number?, number?)
	local left, right, x = nil, nil, nil
	for _, child in board:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Post" then
			local half = child.Size.Z / 2
			x = child.Position.X
			if not left or child.Position.Z - half < left then
				left = child.Position.Z - half
			end
			if not right or child.Position.Z + half > right then
				right = child.Position.Z + half
			end
		end
	end
	return left, right, x
end

local function buildGateWall(folder: Folder, x: number, fromZ: number, toZ: number)
	local length = math.abs(toZ - fromZ)
	local centerZ = (fromZ + toZ) / 2
	makePart({ Name = "ZoneWall", Size = Vector3.new(2, 4, length), Position = Vector3.new(x, 2, centerZ), Color = WALL_COLOR, Material = Enum.Material.Slate, Parent = folder })
	makePart({ Name = "ZoneWallTrim", Size = Vector3.new(2.3, 0.35, length), Position = Vector3.new(x, 4.17, centerZ), Color = WALL_TRIM, Material = Enum.Material.Neon, Parent = folder })
	local posts = math.max(1, math.floor(length / 24))
	for i = 0, posts do
		local z = math.min(fromZ, toZ) + (length / posts) * i
		makePart({ Name = "ZoneWallPost", Size = Vector3.new(3, 6.4, 3), Position = Vector3.new(x, 3.2, z), Color = WALL_COLOR, Material = Enum.Material.Slate, Parent = folder })
		makePart({ Name = "ZoneWallPostCap", Size = Vector3.new(3.3, 0.4, 3.3), Position = Vector3.new(x, 6.6, z), Color = WALL_TRIM, Material = Enum.Material.Neon, Parent = folder })
	end
end

local function adoptAuthoredGate(index: number, zone: Config.Zone, folder: Folder): boolean
	local template = authoredGateTemplate()
	if not template then
		if workspace:FindFirstChild("ZoneGates") then
			-- The authored gate folder exists but the gate was deleted on purpose: no gate comes back, only the
			-- walls with the normal road-wide opening.
			local x = zoneStartX(index)
			local opening = ROAD_WIDTH / 2 + 2
			buildGateWall(folder, x, -ZONE_HALF_Z, -opening)
			buildGateWall(folder, x, opening, ZONE_HALF_Z)
			return true
		end
		return false
	end
	local templateIndex = template:GetAttribute("ZoneIndex")
	if type(templateIndex) ~= "number" then
		templateIndex = 1
	end
	local board = template
	if index ~= templateIndex then
		board = template:Clone()
		board:SetAttribute("GateClone", true)
		board:SetAttribute("ZoneIndex", index)
		CollectionService:RemoveTag(board, "ZoneGateBoard")
		board.Name = "ZoneGate_" .. index
		board:PivotTo(template:GetPivot() + Vector3.new((index - templateIndex) * ZONE_LENGTH, 0, 0))
		board.Parent = folder
	end
	local title = string.format("ZONE %d · %s  %s %s", index, string.upper(zone.Name), stars(zone.Stars), string.upper(zone.Difficulty))
	for _, gui in board:GetDescendants() do
		if gui:IsA("TextLabel") then
			if gui.Name == "ZoneTitle" then
				gui.Text = title
				gui.TextColor3 = zone.AccentColor
			elseif gui.Name == "ResetValue" then
				table.insert(boardResetLabels, gui)
			end
		end
	end
	local leftEdge, rightEdge, x = gatePostBounds(board)
	if leftEdge and rightEdge and x then
		buildGateWall(folder, x, -ZONE_HALF_Z, leftEdge)
		buildGateWall(folder, x, rightEdge, ZONE_HALF_Z)
	end
	return true
end

local function buildGate(index: number, zone: Config.Zone, folder: Folder)
	if adoptAuthoredGate(index, zone, folder) then
		return
	end
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
			Aggro = nil,
			Moving = false,
			Style = nil,
			NextAttackAt = 0,
			Engaged = false,
			WindingUntil = 0,
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

-- ضربة الأم: حسب المنطقة وندرة الوحش
local function motherDamage(nest: Nest): number
	local species = nest.Species and Config.Species[nest.Species]
	local multiplier = species and Config.MotherDamageByRarity[species.Rarity] or 1
	local styleMultiplier = if nest.Style then nest.Style.DamageMultiplier else 1
	return math.floor(nest.Zone.MotherDamage * multiplier * styleMultiplier + 0.5)
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
	nest.Aggro = player -- لو اتنين ضربوها بتروح لآخر واحد

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
	nest.Aggro = nil
	nest.Moving = false
	nest.Engaged = false
	nest.WindingUntil = 0
	nest.NextAttackAt = 0
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
	-- الدم حسب المنطقة وندرة الوحش
	nest.MaxHealth = math.floor(nest.Zone.MotherHealth * (Config.MotherHealthByRarity[Config.Species[species].Rarity] or 1))
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
	local styles = Config.MotherAttacks.Styles
	local rigType = motherModel:GetAttribute("RigType") :: string
	local comboStyles = Config.MotherAttacks.ComboStyles
	if Config.MotherAttacks.ComboDifficulties[nest.Zone.Difficulty] and comboStyles[rigType] then
		nest.Style = comboStyles[rigType]
	else
		nest.Style = styles[rigType] or styles.Quad
	end
	local picked = nest.Style :: Config.MotherStyle
	motherModel:SetAttribute("AttackWindup", picked.Windup)
	motherModel:SetAttribute("ComboHits", picked.Hits) -- بيخلّي الأنيميشن يعمل كومبو
	motherModel:SetAttribute("ComboInterval", picked.HitInterval)
	local extents = motherModel:GetExtentsSize()
	local height = extents.Y - (motherModel:GetAttribute("PivotHeight") :: number)

	-- مقاسات الـ Billboards بالـ studs عشان تصغر مع البعد وماتركبش على بعض
	local gui, label = makeBillboard(mother, UDim2.fromScale(16, 5.5), Vector3.new(0, height + 4, 0), 120)
	gui.Name = "Info"
	gui.AlwaysOnTop = false
	label.Size = UDim2.fromScale(1, 0.6)
	label.Text = string.format(
		'<font color="%s">%s</font> · MOTHER\n<font color="%s">%s</font> · ⚔️ %d dmg',
		rarityHex(species),
		name,
		rarityHex(species),
		Config.Species[species].Rarity,
		motherDamage(nest)
	)

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

-- أقرب لاعب في مدى الضربة (واللي ضربها ليه الأولوية)
local function pickVictim(nest: Nest, mother: BasePart, reach: number): BasePart?
	local best: BasePart? = nil
	local bestScore = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = Vector3.new(root.Position.X - mother.Position.X, 0, root.Position.Z - mother.Position.Z).Magnitude
			local score = if player == nest.Aggro then distance - 1000 else distance
			if distance <= reach and score < bestScore then
				best = root
				bestScore = score
			end
		end
	end
	return best
end

-- الـ HP بيرجع كامل لو محدش ضربها شوية، والأم بتعمل M1 على اللي قريب منها.
local function motherTick(now: number)
	for _, nest in nests do
		local mother = nest.Mother
		local model = nest.MotherModel
		local style = nest.Style
		if not nest.Alive or not mother or not model or not style then
			continue
		end
		if nest.Health < nest.MaxHealth and now - nest.LastHit > Config.Combat.MotherRegenDelay then
			nest.Health = nest.MaxHealth
			nest.Damagers = {}
			nest.Aggro = nil
			updateHealthBar(nest)
		end
		if now < nest.WindingUntil then
			continue
		end
		local bodyRadius = if nest.Target then nest.Target.Radius else 3
		local reach = if style.Shape == "Slam" then style.Radius else math.min(style.Range, Config.MotherAttacks.AggroRange)
		local victim = pickVictim(nest, mother, bodyRadius + reach)
		if not victim then
			nest.Engaged = false
			continue
		end
		if not nest.Engaged then
			-- أول ما حد يقرب: مهلة صغيرة قبل أول ضربة
			nest.Engaged = true
			nest.NextAttackAt = math.max(nest.NextAttackAt, now + Config.MotherAttacks.FirstAttackDelay)
		end
		if now < nest.NextAttackAt then
			continue
		end

		-- تبص على اللاعب وتقف تجهّز الضربة
		local pivot = model:GetPivot()
		local look = Vector3.new(victim.Position.X, pivot.Position.Y, victim.Position.Z)
		if (look - pivot.Position).Magnitude > 0.1 then
			model:PivotTo(CFrame.lookAt(pivot.Position, look))
		end
		model:SetAttribute("AnimState", "Attack")
		nest.Moving = false
		local current = model
		local windup = MonsterAttack.Start({
			Model = model,
			Root = mother,
			BodyRadius = bodyRadius,
			Target = victim,
			Style = style,
			Element = nest.Zone.Name,
			Damage = motherDamage(nest),
			IsValid = function()
				return nest.Alive and nest.MotherModel == current
			end,
			OnDrain = function(amount: number)
				if nest.Alive and nest.MotherModel == current then
					nest.Health = math.min(nest.MaxHealth, nest.Health + math.floor(amount))
					updateHealthBar(nest)
				end
			end,
		})
		nest.WindingUntil = now + windup + 0.25
		nest.NextAttackAt = now + windup + style.Cooldown
		task.delay(windup + 0.25, function()
			if nest.MotherModel == current and not nest.Moving then
				current:SetAttribute("AnimState", "Idle")
			end
		end)
	end
end

local function updateGateTimers()
	local left = math.max(0, math.ceil(nextResetAt - os.clock()))
	local timer = string.format("🔄 New monsters in %d:%02d", left // 60, left % 60)
	for _, gate in gateLabels do
		gate.Label.Text = gate.Title .. "\n" .. timer
	end
	local clock = string.format("%d:%02d", left // 60, left % 60)
	for _, label in boardResetLabels do
		label.Text = clock
	end
end

-- Where each zone Mother stands (used by the Halloween event so its Mothers appear in the same places).
function ZoneService.GetNestCenters(): { Vector3 }
	local centers: { Vector3 } = {}
	for _, nest in nests do
		table.insert(centers, nest.Center)
	end
	return centers
end

function ZoneService.CleanupPlayer(player: Player)
	for _, nest in nests do
		nest.Damagers[player] = nil
	end
end

-- الأم بتجري ورا آخر واحد ضربها، وبترجع عشها لو بعدت أوي أو هو مات أو خرج
local function chaseStep(dt: number)
	for _, nest in nests do
		local model = nest.MotherModel
		local mother = nest.Mother
		if not nest.Alive or not model or not mother or os.clock() < nest.WindingUntil then
			continue
		end
		local pivot = model:GetPivot()
		local home = Vector3.new(nest.Center.X, pivot.Position.Y, nest.Center.Z)

		-- الهدف لسه صالح؟
		local goal: Vector3? = nil
		local stopDistance = 0.5
		local aggro = nest.Aggro
		if not aggro then
			-- Nobody hit her yet: she still notices a player who walks close to her nest.
			local bestDistance = Config.Combat.MotherNoticeRange
			for _, candidate in Players:GetPlayers() do
				local candidateRoot = candidate.Character and candidate.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local candidateHumanoid = candidate.Character and candidate.Character:FindFirstChildOfClass("Humanoid")
				if candidateRoot and candidateHumanoid and candidateHumanoid.Health > 0 then
					local fromMother = Vector3.new(candidateRoot.Position.X - pivot.Position.X, 0, candidateRoot.Position.Z - pivot.Position.Z).Magnitude
					local fromHome = Vector3.new(candidateRoot.Position.X - home.X, 0, candidateRoot.Position.Z - home.Z).Magnitude
					if fromMother < bestDistance and fromHome <= Config.Combat.MotherLeashRange then
						bestDistance = fromMother
						aggro = candidate
						nest.Aggro = candidate
					end
				end
			end
		end
		if aggro then
			local character = aggro.Parent and aggro.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local flatFromHome = root and Vector3.new(root.Position.X - home.X, 0, root.Position.Z - home.Z).Magnitude
			if root and humanoid and humanoid.Health > 0 and flatFromHome and flatFromHome <= Config.Combat.MotherLeashRange then
				goal = Vector3.new(root.Position.X, pivot.Position.Y, root.Position.Z)
				local target = nest.Target
				stopDistance = (if target then target.Radius else 3) + 2
			else
				nest.Aggro = nil
			end
		end
		if not goal then
			goal = home
		end

		local offset = Vector3.new(goal.X - pivot.Position.X, 0, goal.Z - pivot.Position.Z)
		local distance = offset.Magnitude
		local moving = distance > stopDistance
		if moving then
			local step = math.min(Config.Combat.MotherChaseSpeed * dt, distance - stopDistance)
			local position = pivot.Position + offset.Unit * step
			model:PivotTo(CFrame.lookAt(position, position + offset.Unit))
		end
		if moving ~= nest.Moving then
			nest.Moving = moving
			model:SetAttribute("AnimState", if moving then "Walk" else "Idle")
		end
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
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			chaseStep(now - last)
			motherTick(now)
			last = now
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
