--!strict
-- بيبني الخريطة بالكود (أرض + متجر بيض + قواعد اللاعبين) وبيرسم الوحوش والبيض.
-- كده الماب تشتغل في أي Baseplate فاضي من غير ما تبني حاجة بإيدك.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local MonsterModels = require(script.Parent.MonsterModels)

local PLOT_SIZE = 60
local HALF = PLOT_SIZE / 2
local FLOOR_TOP = 0.6 -- المنصة قاعدة على الأرض، مش طايرة

-- شكل الماب: القواعد جنب بعض في عمود على الشمال (X سالب) وبتبص ناحية +X،
-- قدامها ساحة فيها متجر البيض، وبعدها الطريق اللي داخل على مناطق الوحوش.
local BASE_X = -40
local PLOT_SPACING = PLOT_SIZE + 8
local ISLAND_MIN_X = Config.Map.IslandMinX
local PLAZA_MIN_X = Config.Map.PlazaMinX
local PLAZA_HALF_Z = Config.Map.PlazaHalfZ


export type Plot = {
	Index: number,
	Model: Model,
	CFrame: CFrame,
	Owner: Player?,
	LockedUntil: number,
	LockCooldownUntil: number,
	Pedestals: { BasePart },
	MonstersFolder: Folder,
	EggsFolder: Folder,
	Barrier: BasePart?,
	CollectorLabel: TextLabel,
	CollectorParts: { BasePart },
	CollectorEnabled: boolean,
	LockLabel: TextLabel?, -- مش موجودين لما السرقة تبقى مقفولة
	SignLabel: TextLabel,
	LockPrompt: ProximityPrompt?,
	UpgradeLabel: TextLabel,
	SpawnCFrame: CFrame,
}

type Callbacks = {
	Upgrade: (player: Player) -> (),
	Collect: (player: Player) -> (),
	Lock: (player: Player) -> (),
	OpenShop: (player: Player) -> (),
	Care: (player: Player, owner: Player, monsterId: string) -> (),
	Steal: (player: Player, owner: Player, monsterId: string) -> (),
}

local PlotService = {}

-- أول المناطق (آخر الساحة) بالـ X
PlotService.ZonesStartX = Config.Map.ZonesStartX
-- حدود منطقة القواعد والساحة (الجبال بتلف حواليها)
PlotService.IslandMinX = ISLAND_MIN_X
PlotService.PlazaHalfZ = PLAZA_HALF_Z

PlotService.Callbacks = {
	Upgrade = function() end,
	Collect = function() end,
	Lock = function() end,
	OpenShop = function() end,
	Care = function() end,
	Steal = function() end,
} :: Callbacks

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local mapFolder: Folder

local makePart = Build.MakePart
local makeBillboard = Build.MakeBillboard
local makePrompt = Build.MakePrompt
local colorToHex = Build.ColorToHex

-- الخريطة ----------------------------------------------------------------------

local function buildGround()
	-- الجزيرة اللي عليها القواعد والساحة (المناطق بتبني أرضها في ZoneService)
	makePart({
		Name = "Ground",
		Size = Vector3.new(PlotService.ZonesStartX - ISLAND_MIN_X, 2, PLAZA_HALF_Z * 2),
		Position = Vector3.new((ISLAND_MIN_X + PlotService.ZonesStartX) / 2, -1, 0),
		Color = Color3.fromRGB(95, 160, 80),
		Material = Enum.Material.Grass,
		Parent = mapFolder,
	})
	makePart({
		Name = "Plaza",
		Size = Vector3.new(PlotService.ZonesStartX - PLAZA_MIN_X, 0.2, (PLAZA_HALF_Z - Config.Map.PlazaPadding) * 2),
		Position = Vector3.new((PLAZA_MIN_X + PlotService.ZonesStartX) / 2, 0.1, 0),
		Color = Color3.fromRGB(150, 150, 155),
		Material = Enum.Material.Cobblestone,
		Parent = mapFolder,
	})
	-- المية بتكبر مع الأرض، فتفضل محاوطة آخر منطقة كمان.
	local zonesEndX = PlotService.ZonesStartX + #Config.Zones * Config.Map.ZoneLength
	makePart({
		Name = "Water",
		Size = Vector3.new(zonesEndX - ISLAND_MIN_X + Config.Map.WaterMargin * 2, 1, PLAZA_HALF_Z * 2 + Config.Map.WaterMargin * 2),
		Position = Vector3.new((ISLAND_MIN_X + zonesEndX) / 2, -4, 0),
		Color = Color3.fromRGB(40, 110, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = mapFolder,
	})
end

-- Against the zone-entrance wall, south of the gate road; the leaderboards line up on the north side.
local SHOP_ORIGIN = Config.Shop.Position
PlotService.ShopPosition = SHOP_ORIGIN
local SHOP_FRAME = CFrame.new(SHOP_ORIGIN) * CFrame.Angles(0, math.rad(Config.Shop.Yaw), 0)
PlotService.ShopTeleportCFrame = CFrame.lookAt(SHOP_FRAME:PointToWorldSpace(Config.Shop.TeleportOffset), SHOP_ORIGIN + Vector3.new(0, Config.Shop.TeleportOffset.Y, 0))

-- The authored Blacksmith's "Open Shop" prompt (tag GearShopPrompt) opens the same shop as the old counter.
local boundGearPrompts: { [Instance]: boolean } = {}
local gearPromptSignal: RBXScriptConnection? = nil
local function bindGearShopPrompt(prompt: Instance)
	if boundGearPrompts[prompt] or not prompt:IsA("ProximityPrompt") then
		return
	end
	boundGearPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		PlotService.Callbacks.OpenShop(player)
	end)
end

local function buildShop()
	local shopModel = Instance.new("Model")
	shopModel.Name = "EggShop"
	shopModel.Parent = mapFolder

	local counter = makePart({
		Name = "Counter",
		Size = Vector3.new(16, 4, 6),
		Position = SHOP_ORIGIN + Vector3.new(0, 2, 0),
		Color = Color3.fromRGB(100, 65, 40),
		Material = Enum.Material.Wood,
		Parent = shopModel,
	})
	shopModel.PrimaryPart = counter
	makePart({
		Name = "Roof",
		Size = Vector3.new(20, 1, 10),
		Position = SHOP_ORIGIN + Vector3.new(0, 11, 0),
		Color = Color3.fromRGB(30, 65, 75),
		Parent = shopModel,
	})
	makePart({
		Name = "ShopTrim",
		Size = Vector3.new(20.2, 0.35, 0.35),
		Position = SHOP_ORIGIN + Vector3.new(0, 10.7, 5),
		Color = Color3.fromRGB(255, 205, 95),
		Material = Enum.Material.Metal,
		Parent = shopModel,
	})
	for _, x in { -9, 9 } do
		makePart({
			Name = "Pole",
			Size = Vector3.new(1, 7, 1),
			Position = SHOP_ORIGIN + Vector3.new(x, 7.5, 0),
			Color = Color3.fromRGB(240, 240, 240),
			Parent = shopModel,
		})
	end

	-- Anchored display models cannot be picked up as Tools.
	local templates = ReplicatedStorage:FindFirstChild("WeaponModels")
	for i, name in { "WoodenBat", "IronSword" } do
		local template = templates and templates:FindFirstChild(name)
		if template then
			local copy = template:Clone()
			local display = Instance.new("Model")
			display.Name = "Display" .. name
			for _, child in copy:GetChildren() do child.Parent = display end
			copy:Destroy()
			local handle = display:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				display.PrimaryPart = handle
				for _, part in display:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanTouch = false
					end
				end
				display:PivotTo(CFrame.new(SHOP_ORIGIN + Vector3.new(if i == 1 then -4 else 4, 4.8, 1)) * CFrame.Angles(0, 0, math.rad(65)))
				display.Parent = shopModel
			else
				display:Destroy()
			end
		end
	end

	-- البيض المعروض على الكاونتر = اللي بيتباع في المتجر بس
	local sortedEggs = {}
	for _, eggType in Config.ShopEggs do
		local egg = Config.Eggs[eggType]
		if egg then
			table.insert(sortedEggs, egg)
		end
	end
	for i, egg in sortedEggs do
		local eggPart = makePart({
			Name = "DisplayEgg",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.4, 2.4),
			Position = SHOP_ORIGIN + Vector3.new((i - 2) * 5, 5.4, 0),
			Color = egg.Color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = shopModel,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = eggPart
	end

	local _, title = makeBillboard(counter, UDim2.fromOffset(260, 60), Vector3.new(0, 10, 0))
	title.Text = "⚔️ GEAR SHOP ⚔️"
	title.TextColor3 = Color3.fromRGB(255, 230, 120)

	local prompt = makePrompt(counter, "ShopPrompt", "Open Shop", Enum.KeyCode.E, 0)
	prompt.ObjectText = "Gear Shop"
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		PlotService.Callbacks.OpenShop(player)
	end)
	for _, part in shopModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	shopModel:PivotTo(SHOP_FRAME * CFrame.new(SHOP_ORIGIN):Inverse() * shopModel:GetPivot())

	-- A Studio-authored Gear Shop (Workspace.GearShopWorld: stall + Blacksmith NPC, tagged GearShopStand)
	-- replaces this code-made stall. It is never rebuilt or moved by code, so the user's edits stick.
	if CollectionService:GetTagged("GearShopStand")[1] then
		shopModel:Destroy()
	end
	for _, prompt in CollectionService:GetTagged("GearShopPrompt") do
		bindGearShopPrompt(prompt)
	end
	if not gearPromptSignal then
		gearPromptSignal = CollectionService:GetInstanceAddedSignal("GearShopPrompt"):Connect(bindGearShopPrompt)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CenterSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(Config.Map.SpawnPosition)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = mapFolder
end

-- القواعد جنب بعض في عمود واحد، ومداخلها بتبص على الساحة (+X).
local function plotCFrames(): { CFrame }
	local result = {}
	local facing = Vector3.new(1, 0, 0)
	for index = 1, Config.MaxPlots do
		local z = (index - (Config.MaxPlots + 1) / 2) * PLOT_SPACING
		local position = Vector3.new(BASE_X, 0, z)
		table.insert(result, CFrame.lookAt(position, position + facing))
	end
	return result
end

-- The three starting habitats face the entrance; seven real expansions fit the
-- existing ten-slot capacity. Local -Z is the plaza side of every plot.
local SLOT_POSITIONS = {
	Vector3.new(-19, 0, -5), Vector3.new(0, 0, -5), Vector3.new(19, 0, -5),
	Vector3.new(-22, 0, 10), Vector3.new(-10, 0, 10), Vector3.new(2, 0, 10),
	Vector3.new(-22, 0, 23), Vector3.new(-10, 0, 23), Vector3.new(2, 0, 23), Vector3.new(14, 0, 23),
}

local function slotLocalCFrame(slot: number): CFrame
	local position = SLOT_POSITIONS[slot] + Vector3.new(0, FLOOR_TOP + 0.25, 0)
	return CFrame.lookAt(position, Vector3.new(position.X, position.Y, -HALF))
end

local function setPadState(pad: BasePart, unlocked: boolean)
	pad:SetAttribute("Unlocked", unlocked)
	pad.Color = if unlocked then Color3.fromRGB(94, 156, 62) else Color3.fromRGB(110, 107, 79)
	pad.Material = if unlocked then Enum.Material.Grass else Enum.Material.Slate
	pad.Transparency = 0
	local habitat = pad.Parent
	if not habitat then return end
	for _, name in { "UnlockedGeometry", "LockedGeometry" } do
		local group = habitat:FindFirstChild(name)
		local visible = if name == "UnlockedGeometry" then unlocked else not unlocked
		if group then
			for _, item in group:GetDescendants() do
				if item:IsA("BasePart") then
					item.Transparency = if visible then (item:GetAttribute("VisibleTransparency") or 0) else 1
					item.CanCollide = visible and item:GetAttribute("VisibleCanCollide") == true
					item.CanTouch = visible and item:GetAttribute("VisibleCanTouch") == true
					item.CanQuery = visible and item:GetAttribute("VisibleCanQuery") == true
				elseif item:IsA("SurfaceGui") then
					item.Enabled = visible
				elseif item:IsA("PointLight") then
					item.Enabled = visible
				end
			end
		end
	end
end

local function buildPlot(index: number, cframe: CFrame): Plot
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("Design", "FlowMonsterSanctuary")
	model.Parent = mapFolder
	local wood = Color3.fromRGB(143, 98, 48)
	local lightWood = Color3.fromRGB(189, 139, 67)
	local stone = Color3.fromRGB(164, 161, 144)
	local gold = Color3.fromRGB(255, 218, 101)
	local function at(position: Vector3): CFrame return cframe * CFrame.new(position) end
	local function block(name: string, size: Vector3, position: Vector3, props: { [string]: any }?): Part
		local all: { [string]: any } = { Name = name, Size = size, CFrame = at(position), Color = stone, Material = Enum.Material.Slate, Parent = model }
		for key, value in props or {} do all[key] = value end
		return makePart(all)
	end
	local function beam(name: string, a: Vector3, b: Vector3, width: number, height: number, parent: Instance?, color: Color3?, material: Enum.Material?): Part
		return Build.MakeBeam(name, cframe:PointToWorldSpace(a), cframe:PointToWorldSpace(b), width, height,
			{ Color = color or wood, Material = material or Enum.Material.Wood, Parent = parent or model, CanCollide = false })
	end
	local function lamp(position: Vector3)
		block("LanternPost", Vector3.new(0.45, 3.8, 0.45), position + Vector3.new(0, FLOOR_TOP + 1.9, 0), { Color = wood, Material = Enum.Material.Wood })
		local core = block("WarmLantern", Vector3.new(0.85, 1.05, 0.85), position + Vector3.new(0, FLOOR_TOP + 3.5, 0), { Color = gold, Material = Enum.Material.Neon, CanCollide = false })
		for _, y in { 2.92, 4.08 } do block("LanternFrame", Vector3.new(1.12, 0.16, 1.12), position + Vector3.new(0, FLOOR_TOP + y, 0), { Color = Color3.fromRGB(69, 50, 31), Material = Enum.Material.Metal }) end
		local light = Instance.new("PointLight"); light.Color = gold; light.Range = 11; light.Brightness = 1.1; light.Parent = core
	end
	local function fence(a: Vector3, b: Vector3, pieces: number)
		for i = 0, pieces do
			local p = a:Lerp(b, i / pieces)
			block("PerimeterFencePost", Vector3.new(0.65, 2.8, 0.65), p + Vector3.new(0, FLOOR_TOP + 1.4, 0), { Color = wood, Material = Enum.Material.Wood })
		end
		for i = 1, pieces do
			for _, y in { 0.9, 2.05 } do beam("PerimeterFenceRail", a:Lerp(b, (i - 1) / pieces) + Vector3.new(0, FLOOR_TOP + y, 0), a:Lerp(b, i / pieces) + Vector3.new(0, FLOOR_TOP + y, 0), 0.27, 0.38) end
		end
	end

	block("Rim", Vector3.new(PLOT_SIZE, FLOOR_TOP, PLOT_SIZE), Vector3.new(0, FLOOR_TOP / 2, 0), { Color = Color3.fromRGB(106, 80, 44), Material = Enum.Material.Ground })
	block("Floor", Vector3.new(PLOT_SIZE, 0.16, PLOT_SIZE), Vector3.new(0, FLOOR_TOP, 0), { Color = Color3.fromRGB(91, 158, 62), Material = Enum.Material.Grass })
	fence(Vector3.new(-28.6, 0, -28.6), Vector3.new(-28.6, 0, 28.6), 8)
	fence(Vector3.new(28.6, 0, -28.6), Vector3.new(28.6, 0, 28.6), 8)
	fence(Vector3.new(-28.6, 0, 28.6), Vector3.new(28.6, 0, 28.6), 8)
	fence(Vector3.new(-28.6, 0, -28.6), Vector3.new(-6, 0, -28.6), 3)
	fence(Vector3.new(6, 0, -28.6), Vector3.new(28.6, 0, -28.6), 3)

	-- Broad stone arch with an open walk-through centre. Each voussoir is editable.
	for _, x in { -5.4, 5.4 } do
		block("ArchFoot", Vector3.new(2.7, 0.6, 3.2), Vector3.new(x, FLOOR_TOP + 0.3, -27.7))
		for tier = 1, 3 do block("ArchPillarStone", Vector3.new(2.05, 1.75, 2.55), Vector3.new(x, FLOOR_TOP + 0.6 + (tier - 0.5) * 1.75, -27.7), { Color = stone:Lerp(Color3.new(1, 1, 1), tier % 2 * 0.06) }) end
	end
	for i = 0, 6 do
		local angle = i * math.pi / 6
		block("ArchCurveStone", Vector3.new(2.6, 2, 2.6), Vector3.new(math.cos(angle) * 5.4, FLOOR_TOP + 5.55 + math.sin(angle) * 3.8, -27.7),
			{ CFrame = at(Vector3.new(math.cos(angle) * 5.4, FLOOR_TOP + 5.55 + math.sin(angle) * 3.8, -27.7)) * CFrame.Angles(0, 0, angle - math.pi / 2) })
	end

	-- Pale stepping-stone paths fork from the arch towards the three starting pens.
	local function path(a: Vector3, b: Vector3, rows: number)
		local direction = (b - a).Unit
		local side = Vector3.new(-direction.Z, 0, direction.X)
		for i = 0, rows do
			local point = a:Lerp(b, i / rows) + Vector3.new(0, FLOOR_TOP + 0.15, 0)
			for _, offset in { -0.88, 0.88 } do
				block("PathStone", Vector3.new(1.45, 0.18, 1.8), point + side * offset,
					{ Color = if i % 2 == 0 then Color3.fromRGB(195, 194, 165) else Color3.fromRGB(174, 179, 151), CFrame = CFrame.lookAt(cframe:PointToWorldSpace(point + side * offset), cframe:PointToWorldSpace(point + side * offset + direction)), CanCollide = false })
			end
		end
	end
	path(Vector3.new(0, 0, -29), Vector3.new(0, 0, -19), 5)
	path(Vector3.new(0, 0, -21), Vector3.new(-19, 0, -15), 8)
	path(Vector3.new(0, 0, -21), Vector3.new(19, 0, -15), 8)
	path(Vector3.new(11, 0, 2), Vector3.new(20, 0, 5), 5)

	-- A small timber caretaker cottage and low-poly oak, with no waterside area.
	local cottage = Vector3.new(21, FLOOR_TOP, 11)
	block("CottageFoundation", Vector3.new(11, 0.45, 10), cottage + Vector3.new(0, 0.22, 0))
	for i = 0, 8 do
		local x = cottage.X - 4.8 + i * 1.2
		block("CottageWallPlank", Vector3.new(1.13, 5.6, 8.7), Vector3.new(x, cottage.Y + 3.15, cottage.Z), { Color = if i % 2 == 0 then lightWood else wood, Material = Enum.Material.Wood })
	end
	for _, x in { -5.15, 5.15 } do block("CottageCornerBeam", Vector3.new(0.5, 6.5, 0.6), cottage + Vector3.new(x, 3.25, -4.55), { Color = Color3.fromRGB(89, 57, 29), Material = Enum.Material.Wood }) end
	block("CottageDoor", Vector3.new(2.25, 4.2, 0.24), cottage + Vector3.new(0, 2.35, -4.55), { Color = Color3.fromRGB(101, 64, 31), Material = Enum.Material.Wood })
	block("DoorHandle", Vector3.new(0.18, 0.25, 0.18), cottage + Vector3.new(0.65, 2.35, -4.73), { Color = gold, Material = Enum.Material.Metal, CanCollide = false })
	block("CottageWindow", Vector3.new(2, 1.9, 0.2), cottage + Vector3.new(-3.1, 3.7, -4.55), { Color = Color3.fromRGB(255, 208, 94), Material = Enum.Material.Neon })
	for _, x in { -4.15, -3.1, -2.05 } do block("WindowMullion", Vector3.new(0.14, 2.2, 0.3), cottage + Vector3.new(x, 3.7, -4.7), { Color = wood, Material = Enum.Material.Wood }) end
	block("WindowMullion", Vector3.new(2.2, 0.14, 0.3), cottage + Vector3.new(-3.1, 3.7, -4.7), { Color = wood, Material = Enum.Material.Wood })
	for _, side in { -1, 1 } do
		for strip = 0, 6 do
			local roof = block("CottageRoofBoard", Vector3.new(6.9, 0.3, 1.62), cottage + Vector3.new(side * 2.9, 7.5, -4.8 + strip * 1.6), { Color = if strip % 2 == 0 then Color3.fromRGB(213, 163, 65) else Color3.fromRGB(194, 135, 48), Material = Enum.Material.WoodPlanks })
			roof.CFrame *= CFrame.Angles(0, 0, side * math.rad(-27))
		end
	end
	block("RoofRidge", Vector3.new(0.45, 0.45, 12), cottage + Vector3.new(0, 9, 0), { Color = Color3.fromRGB(116, 76, 32), Material = Enum.Material.Wood })
	local treeAt = Vector3.new(23.5, FLOOR_TOP, 24)
	block("OakTrunk", Vector3.new(1.65, 7.2, 1.65), treeAt + Vector3.new(0, 3.6, 0), { Color = Color3.fromRGB(108, 69, 34), Material = Enum.Material.Wood })
	for i, offset in { Vector3.new(0, 8.2, 0), Vector3.new(-2.3, 7.8, 0.5), Vector3.new(1.5, 9.4, -0.8), Vector3.new(0.8, 7.4, 2) } do
		local leaves = block("FacetedOakCanopy", Vector3.new(5, 4.8, 5), treeAt + offset, { Color = Color3.fromRGB(73 + i * 6, 130 + i * 5, 45), Material = Enum.Material.Grass, CanCollide = false })
		leaves.CFrame *= CFrame.Angles(math.rad(i * 13), math.rad(i * 29), math.rad(14))
	end
	for _, p in { Vector3.new(-26, 0, -15), Vector3.new(26, 0, -15), Vector3.new(10, 0, 5), Vector3.new(27, 0, 4) } do lamp(p) end

	local pedestals: { BasePart } = {}
	for slot = 1, Config.MaxSlots do
		local position = SLOT_POSITIONS[slot]
		local radius = if slot <= Config.BaseSlots then 6.4 else 4.4
		local habitat = Instance.new("Model"); habitat.Name = "Habitat_" .. slot; habitat:SetAttribute("Slot", slot); habitat.Parent = model
		local unlocked = Instance.new("Model"); unlocked.Name = "UnlockedGeometry"; unlocked.Parent = habitat
		local locked = Instance.new("Model"); locked.Name = "LockedGeometry"; locked.Parent = habitat
		local pad = block("Pedestal_" .. slot, Vector3.new(0.28, radius * 2, radius * 2), position + Vector3.new(0, FLOOR_TOP + 0.22, 0), { Shape = Enum.PartType.Cylinder, CFrame = at(position + Vector3.new(0, FLOOR_TOP + 0.22, 0)) * CFrame.Angles(0, 0, math.pi / 2), Parent = habitat })
		habitat.PrimaryPart = pad
		for i = 0, 11 do
			local angle = i * math.pi / 6
			local nextAngle = (i + 1) * math.pi / 6
			local a = position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local b = position + Vector3.new(math.cos(nextAngle) * radius, 0, math.sin(nextAngle) * radius)
			block("HabitatFencePost", Vector3.new(0.55, 2.5, 0.55), a + Vector3.new(0, FLOOR_TOP + 1.25, 0), { Color = wood, Material = Enum.Material.Wood, Parent = unlocked, CanCollide = false })
			-- Leave the front centre open for access to eggs and care prompts.
			if i ~= 8 and i ~= 9 then
				for _, y in { 0.72, 1.72 } do beam("HabitatRoundRail", a + Vector3.new(0, FLOOR_TOP + y, 0), b + Vector3.new(0, FLOOR_TOP + y, 0), 0.27, 0.36, unlocked, lightWood) end
			end
		end
		local expansion = block("FutureExpansion", Vector3.new(radius * 2 + 0.6, 0.22, radius * 2 + 0.6), position + Vector3.new(0, FLOOR_TOP + 0.42, 0), { Color = Color3.fromRGB(124, 119, 81), Material = Enum.Material.Slate, CanCollide = false, Parent = locked })
		local gui = Instance.new("SurfaceGui"); gui.Face = Enum.NormalId.Top; gui.CanvasSize = Vector2.new(384, 384); gui.LightInfluence = 0; gui.Parent = expansion
		local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1); label.Font = Enum.Font.FredokaOne; label.TextScaled = true; label.TextColor3 = gold; label.Text = "🔒\nFUTURE\nEXPANSION"; label.Parent = gui
		for _, side in { -1, 1 } do
			for dash = 0, 2 do
				local v = (dash - 1) * radius * 0.68
				block("ExpansionBoundaryDash", Vector3.new(1.8, 0.08, 0.16), position + Vector3.new(v, FLOOR_TOP + 0.56, side * (radius + 0.55)), { Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = locked })
				block("ExpansionBoundaryDash", Vector3.new(0.16, 0.08, 1.8), position + Vector3.new(side * (radius + 0.55), FLOOR_TOP + 0.56, v), { Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = locked })
			end
		end
		for _, item in habitat:GetDescendants() do if item:IsA("BasePart") then item:SetAttribute("VisibleTransparency", item.Transparency); item:SetAttribute("VisibleCanCollide", item.CanCollide); item:SetAttribute("VisibleCanQuery", item.CanQuery) end end
		pedestals[slot] = pad
		setPadState(pad, slot <= Config.BaseSlots)
	end

	local collector = block("Collector", Vector3.new(4.3, 0.2, 3.2), Vector3.new(-23, FLOOR_TOP + 0.18, -24.2), { Color = gold, Material = Enum.Material.Neon, CanCollide = false })
	block("Chest", Vector3.new(2.6, 1.3, 1.55), Vector3.new(-23, FLOOR_TOP + 0.85, -22.7), { Color = wood, Material = Enum.Material.Wood })
	block("ChestLid", Vector3.new(2.7, 0.4, 1.65), Vector3.new(-23, FLOOR_TOP + 1.7, -22.7), { Color = lightWood, Material = Enum.Material.Wood })
	for _, x in { -23.85, -22.15 } do block("ChestBand", Vector3.new(0.19, 1.55, 1.72), Vector3.new(x, FLOOR_TOP + 1, -22.7), { Color = gold, Material = Enum.Material.Metal, CanCollide = false }) end
	local collectorGui, collectorLabel = makeBillboard(collector, UDim2.fromOffset(200, 50), Vector3.new(0, 4.4, 0), 80)
	local collectorParts: { BasePart } = {}
	for _, item in model:GetChildren() do
		if item:IsA("BasePart") and (item == collector or item.Name == "Chest" or item.Name == "ChestLid" or item.Name == "ChestBand") then
			table.insert(collectorParts, item)
		end
	end
	collectorGui.AlwaysOnTop = false
	collectorLabel.Text = "💰 0"
	local signAnchor = block("NameAnchor", Vector3.new(1, 1, 1), Vector3.new(0, FLOOR_TOP + 12, -27), { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local signGui, signLabel = makeBillboard(signAnchor, UDim2.fromScale(22, 3.5), Vector3.zero, 200)
	signGui.AlwaysOnTop = false
	signLabel.Text = "Empty Base"
	signLabel.TextColor3 = (Config.PlotColors[index] or gold):Lerp(Color3.new(1, 1, 1), 0.4)
	local barrier: BasePart? = nil
	local lockLabel: TextLabel? = nil
	local lockPrompt: ProximityPrompt? = nil
	if Config.Steal.Enabled then
		barrier = block("LockBarrier", Vector3.new(PLOT_SIZE, 10, 1), Vector3.new(0, FLOOR_TOP + 5, -HALF), { Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.ForceField, Transparency = 1, CanCollide = false })
		local button = block("LockButton", Vector3.new(3, 0.5, 3), Vector3.new(-9, FLOOR_TOP + 0.4, -23), { Color = Color3.fromRGB(210, 70, 60) })
		local _, label = makeBillboard(button, UDim2.fromOffset(200, 50), Vector3.new(0, 4, 0)); label.Text = "🔓 Lock Base"; lockLabel = label
		lockPrompt = makePrompt(button, "LockPrompt", "Lock Base", Enum.KeyCode.E, 0.5)
	end
	-- Upgrades are bought in the base: step up to the pad and press the prompt.
	local upgradePad = block("UpgradePad", Vector3.new(3, 0.5, 3), Vector3.new(23, FLOOR_TOP + 0.4, -24.2), { Color = Color3.fromRGB(70, 150, 230), Material = Enum.Material.Neon })
	local _, upgradeLabel = makeBillboard(upgradePad, UDim2.fromOffset(220, 60), Vector3.new(0, 4, 0), 80)
	upgradeLabel.Text = "⬆️ Upgrade Base"
	local upgradePrompt = makePrompt(upgradePad, "UpgradePrompt", "Buy Upgrade", Enum.KeyCode.E, 0.3)
	local monstersFolder = Instance.new("Folder"); monstersFolder.Name = "Monsters"; monstersFolder.Parent = model
	local eggsFolder = Instance.new("Folder"); eggsFolder.Name = "Eggs"; eggsFolder.Parent = model
	local plot: Plot = { Index = index, Model = model, CFrame = cframe, Owner = nil, LockedUntil = 0, LockCooldownUntil = 0, Pedestals = pedestals, MonstersFolder = monstersFolder, EggsFolder = eggsFolder, Barrier = barrier, CollectorLabel = collectorLabel, CollectorParts = collectorParts, CollectorEnabled = true, LockLabel = lockLabel, SignLabel = signLabel, LockPrompt = lockPrompt, UpgradeLabel = upgradeLabel, SpawnCFrame = at(Vector3.new(0, FLOOR_TOP + 3, -23)) * CFrame.Angles(0, math.pi, 0) }
	local function collect(hit: BasePart)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if plot.CollectorEnabled and player and player == plot.Owner then PlotService.Callbacks.Collect(player) end
	end
	collector.Touched:Connect(collect)
	upgradePrompt.Triggered:Connect(function(player) if player == plot.Owner then PlotService.Callbacks.Upgrade(player) end end)
	if lockPrompt then lockPrompt.Triggered:Connect(function(player) if player == plot.Owner then PlotService.Callbacks.Lock(player) end end) end
	if barrier then
		barrier.Touched:Connect(function(hit)
			if os.clock() >= plot.LockedUntil then return end
			local character = hit.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if not player or player == plot.Owner or not character then return end
			local root = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then root.CFrame = cframe * CFrame.new(0, 3, -HALF - 10) end
		end)
	end
	return plot
end

-- رسم الوحوش ----------------------------------------------------------------

-- الوحوش الـ Rig (من MonsterModels) ----------------------------------------------------

-- المرحلة → نسخة الـ Template (الـ Legendary = الـ Adult مكبّر)
local RIG_STAGES = { "Baby", "Teen", "Adult", "Adult" }
local LEGENDARY_RIG_SCALE = 1.25

-- المسافة من رجلين الوحش لحد الـ Pivot بتاعه (عشان نحطه على الأرض بالظبط)
function PlotService.PivotHeight(model: Model): number
	local height = model:GetAttribute("PivotHeight")
	if type(height) == "number" then
		return height
	end
	local body = model.PrimaryPart :: BasePart
	return body.Size.Y / 2 + 0.3 + body.Size.Y * 0.1
end

-- لمعة سريعة على الوحش (لما يتضرب مثلاً)
function PlotService.Flash(model: Model, color: Color3)
	local flash = Instance.new("Highlight")
	flash.Name = "HitFlash"
	flash.FillColor = color
	flash.FillTransparency = 0.3
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = model
	task.delay(0.15, function()
		flash:Destroy()
	end)
end

local function weldTo(part: BasePart, target: BasePart, model: Model)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
end

-- القبعة فوق الراس والنضارة قدام العينين، ملزوقين في الراس فبيتحركوا معاه
local function addRigAccessories(model: Model, head: BasePart, monster: MonsterMath.MonsterData)
	local k = math.max(head.Size.X, head.Size.Z) / 2.2
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)
	local hat = monster.Hat and Config.Accessories[monster.Hat]
	if hat then
		local function hatPart(props: { [string]: any }, offset: CFrame)
			local part = makePart(props)
			part.CFrame = top * offset
			weldTo(part, head, model)
		end
		local turn = CFrame.Angles(0, 0, math.rad(90))
		if hat.Shape == "TopHat" then
			hatPart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.4, 2.4) * k, Color = hat.Color }, CFrame.new(0, 0.1 * k, 0) * turn)
			hatPart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.5, 1.5) * k, Color = hat.Color }, CFrame.new(0, 0.9 * k, 0) * turn)
		elseif hat.Shape == "WizardHat" then
			for i, width in { 2.2, 1.5, 0.9, 0.4 } do
				hatPart({ Name = "Hat", Size = Vector3.new(width, 0.6, width) * k, Color = hat.Color }, CFrame.new(0, (0.3 + (i - 1) * 0.55) * k, 0) * CFrame.Angles(0, i * 0.3, 0))
			end
		elseif hat.Shape == "Crown" then
			hatPart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.6, 1.6) * k, Color = hat.Color, Material = Enum.Material.Foil }, CFrame.new(0, 0.3 * k, 0) * turn)
			for i = 0, 3 do
				hatPart({ Name = "Hat", Size = Vector3.new(0.25, 0.6, 0.25) * k, Color = hat.Color, Material = Enum.Material.Foil }, CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0.8 * k, -0.65 * k))
			end
		else -- PartyHat
			hatPart({ Name = "Hat", Size = Vector3.new(1, 1.6, 1) * k, Color = hat.Color }, CFrame.new(0, 0.8 * k, 0) * CFrame.Angles(0, math.rad(45), 0))
			hatPart({ Name = "Hat", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5) * k, Color = Color3.new(1, 1, 1) }, CFrame.new(0, 1.75 * k, 0))
		end
	end
	local glasses = monster.Glasses and Config.Accessories[monster.Glasses]
	if glasses then
		local front = head.CFrame * CFrame.new(0, head.Size.Y * 0.15, -head.Size.Z / 2 - 0.06 * k)
		local eyeX = head.Size.X * 0.24
		local function lens(props: { [string]: any }, offset: CFrame)
			local part = makePart(props)
			part.CFrame = front * offset
			weldTo(part, head, model)
		end
		if glasses.Shape == "Monocle" then
			lens({ Name = "Glasses", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.9, 0.9) * k, Color = glasses.Color, Material = Enum.Material.Foil }, CFrame.new(eyeX, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
		else
			local star = glasses.Shape == "StarGlasses"
			for _, side in { -1, 1 } do
				lens(
					{ Name = "Glasses", Size = Vector3.new(0.85, 0.6, 0.1) * k, Color = glasses.Color, Material = if star then Enum.Material.Neon else Enum.Material.Glass },
					CFrame.new(side * eyeX, 0, 0) * (if star then CFrame.Angles(0, 0, math.rad(45)) else CFrame.new())
				)
			end
			lens({ Name = "Glasses", Size = Vector3.new(0.4, 0.12, 0.1) * k, Color = glasses.Color }, CFrame.new())
		end
	end
end

local function buildRiggedMonster(monster: MonsterMath.MonsterData, species: Config.Species): Model?
	local info = species.Model
	if not info then
		return nil
	end
	local stageIndex = MonsterMath.GetStageIndex(monster.Level)
	local model = MonsterModels.Get(info.Region, info.Index, RIG_STAGES[stageIndex] or "Adult")
	if not model then
		return nil
	end
	local extra = if stageIndex >= 4 then LEGENDARY_RIG_SCALE else 1
	if extra ~= 1 then
		model:ScaleTo(extra)
	end
	model.Name = monster.Id
	model:SetAttribute("PivotHeight", (model:GetAttribute("Scale") or 1) * extra)
	model:SetAttribute("AnimState", "Idle")
	local root = model.PrimaryPart :: BasePart

	-- الطفرة: لمعة باللون بتاعها (والـ Rainbow الكلاينت بيلوّنه)
	local mutation = MonsterMath.GetMutation(monster.Mutation)
	if mutation then
		local glow = Instance.new("Highlight")
		glow.Name = "MutationGlow"
		glow.FillColor = mutation.Color or Color3.new(1, 1, 1)
		glow.OutlineColor = mutation.Color or Color3.new(1, 1, 1)
		glow.FillTransparency = 0.55
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
		if monster.Mutation == "Rainbow" then
			CollectionService:AddTag(glow, "RainbowHighlight")
		end
	end

	local head = (model:FindFirstChild("Head") or model:FindFirstChild("Body") or root) :: BasePart
	addRigAccessories(model, head, monster)

	local height = model:GetExtentsSize().Y
	local gui, label = makeBillboard(root, UDim2.fromOffset(220, 70), Vector3.new(0, height - PlotService.PivotHeight(model) + 2, 0), 70)
	gui.Name = "Info"
	label.Name = "Label"
	PlotService.UpdateMonsterLabelOn(label, monster)
	return model
end

function PlotService.BuildMonsterModel(monster: MonsterMath.MonsterData): Model
	local species = Config.Species[monster.Species]
	local rigged = buildRiggedMonster(monster, species)
	if rigged then
		return rigged
	end
	local stage = MonsterMath.GetStage(monster.Level)
	local mutation = MonsterMath.GetMutation(monster.Mutation)
	local scale = stage.Scale
	local color = if mutation and mutation.Color then mutation.Color else species.Color

	local model = Instance.new("Model")
	model.Name = monster.Id

	local material = Enum.Material.SmoothPlastic
	local isSecret = species.Rarity == "Secret"
	if isSecret then
		material = Enum.Material.Neon
		scale *= 1.2
	end
	if monster.Mutation == "Golden" then
		material = Enum.Material.Foil
	elseif monster.Mutation == "Toxic" or monster.Mutation == "Rainbow" then
		material = Enum.Material.Neon
	end

	local bodySize = 3 * scale
	local body = makePart({
		Name = "Body",
		Shape = if species.Placeholder then Enum.PartType.Block else Enum.PartType.Ball,
		Size = Vector3.new(bodySize, bodySize, bodySize),
		Color = color,
		Material = material,
		CanCollide = false,
		CanQuery = true,
		Massless = true,
		Parent = model,
	})
	model.PrimaryPart = body

	local parts: { BasePart } = { body }
	local function attach(part: BasePart, offset: CFrame)
		part.CFrame = body.CFrame * offset
		part.CanCollide = false
		part.Massless = true
		part.Parent = model
		table.insert(parts, part)
	end

	-- الوحوش اللي لسه ملهاش Skin بتفضل مكعب واسمها فوقه بس
	local hasFace = not species.Placeholder

	-- العيون (الوش ناحية -Z)
	for _, side in if hasFace then { -1, 1 } else {} do
		local eye = makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9) * scale,
			Color = Color3.new(1, 1, 1),
		})
		attach(eye, CFrame.new(side * 0.6 * scale, 0.4 * scale, -1.25 * scale))
		local pupil = makePart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.45, 0.45, 0.45) * scale,
			Color = Color3.new(0, 0, 0),
		})
		attach(pupil, CFrame.new(side * 0.6 * scale, 0.4 * scale, -1.6 * scale))
	end

	-- رجلين
	for _, side in if hasFace then { -1, 1 } else {} do
		local foot = makePart({
			Name = "Foot",
			Size = Vector3.new(0.9, 0.6, 1.2) * scale,
			Color = color,
			Material = material,
		})
		attach(foot, CFrame.new(side * 0.8 * scale, -1.4 * scale, -0.2 * scale))
	end

	if species.Horns and hasFace then
		for _, side in { -1, 1 } do
			local horn = makePart({
				Name = "Horn",
				Size = Vector3.new(0.4, 1.2, 0.4) * scale,
				Color = Color3.fromRGB(250, 245, 230),
			})
			attach(horn, CFrame.new(side * 0.8 * scale, 1.6 * scale, 0) * CFrame.Angles(0, 0, side * -0.4))
		end
	end

	-- المراحل الأعلى بتاخد شكل مميز
	if stage.Name == "Adult" or stage.Name == "Legendary" then
		for _, side in { -1, 1 } do
			local wing = makePart({
				Name = "Wing",
				Size = Vector3.new(0.2, 1.6, 2.2) * scale,
				Color = color:Lerp(Color3.new(1, 1, 1), 0.3),
				Material = material,
				Transparency = 0.1,
			})
			attach(wing, CFrame.new(side * 1.6 * scale, 0.3 * scale, 0.6 * scale) * CFrame.Angles(0, 0, side * 0.5))
		end
	end
	if stage.Name == "Legendary" and not (monster.Hat and Config.Accessories[monster.Hat]) then
		local crown = makePart({
			Name = "Crown",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 1.4, 1.4) * scale,
			Color = Color3.fromRGB(255, 210, 40),
			Material = Enum.Material.Neon,
		})
		attach(crown, CFrame.new(0, 1.65 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(255, 230, 120)
		sparkle.Parent = body
	end

	-- إكسسوارات: القبعة فوق الراس، والنضارة على العينين
	local top = 1.5 * scale
	local hat = monster.Hat and Config.Accessories[monster.Hat]
	if hat then
		local hatProps = { Color = hat.Color, Material = Enum.Material.SmoothPlastic }
		if hat.Shape == "TopHat" then
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.4, 2.4) * scale, Color = hat.Color }), CFrame.new(0, top + 0.1 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.5, 1.5) * scale, Color = hat.Color }), CFrame.new(0, top + 0.9 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
		elseif hat.Shape == "WizardHat" then
			for i, width in { 2.2, 1.5, 0.9, 0.4 } do
				attach(makePart({ Name = "Hat", Size = Vector3.new(width, 0.6, width) * scale, Color = hat.Color, Material = hatProps.Material }), CFrame.new(0, top + (0.2 + (i - 1) * 0.55) * scale, 0) * CFrame.Angles(0, i * 0.3, 0))
			end
		elseif hat.Shape == "Crown" then
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.6, 1.6) * scale, Color = hat.Color, Material = Enum.Material.Foil }), CFrame.new(0, top + 0.3 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
			for i = 0, 3 do
				attach(makePart({ Name = "Hat", Size = Vector3.new(0.25, 0.6, 0.25) * scale, Color = hat.Color, Material = Enum.Material.Foil }), CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, top + 0.8 * scale, -0.65 * scale))
			end
		else -- PartyHat
			attach(makePart({ Name = "Hat", Size = Vector3.new(1, 1.6, 1) * scale, Color = hat.Color }), CFrame.new(0, top + 0.8 * scale, 0) * CFrame.Angles(0, math.rad(45), 0))
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5) * scale, Color = Color3.new(1, 1, 1) }), CFrame.new(0, top + 1.75 * scale, 0))
		end
	end
	local glasses = monster.Glasses and Config.Accessories[monster.Glasses]
	if glasses then
		local front = -1.7 * scale
		local eyeY = 0.4 * scale
		if glasses.Shape == "Monocle" then
			attach(makePart({ Name = "Glasses", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.9, 0.9) * scale, Color = glasses.Color, Material = Enum.Material.Foil }), CFrame.new(0.6 * scale, eyeY, front) * CFrame.Angles(0, math.rad(90), 0))
		else
			for _, side in { -1, 1 } do
				local lens = makePart({ Name = "Glasses", Size = Vector3.new(0.85, 0.6, 0.1) * scale, Color = glasses.Color, Material = if glasses.Shape == "StarGlasses" then Enum.Material.Neon else Enum.Material.Glass })
				attach(lens, CFrame.new(side * 0.6 * scale, eyeY, front) * (if glasses.Shape == "StarGlasses" then CFrame.Angles(0, 0, math.rad(45)) else CFrame.new()))
			end
			attach(makePart({ Name = "Glasses", Size = Vector3.new(0.4, 0.12, 0.1) * scale, Color = glasses.Color }), CFrame.new(0, eyeY, front))
		end
	end

	if isSecret then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(200, 120, 255)
		sparkle.Parent = body
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(200, 120, 255)
		light.Range = 12
		light.Parent = body
	end

	if monster.Mutation == "Rainbow" then
		for _, part in parts do
			if part.Name == "Body" or part.Name == "Foot" or part.Name == "Wing" then
				CollectionService:AddTag(part, "RainbowPart")
			end
		end
	end

	-- كل الأجزاء ملزوقة في الجسم عشان نقدر نشيله على راس الحرامي
	for _, part in parts do
		if part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local gui, label = makeBillboard(body, UDim2.fromOffset(220, 70), Vector3.new(0, bodySize / 2 + 2.5, 0), 70)
	gui.Name = "Info"
	label.Name = "Label"
	PlotService.UpdateMonsterLabelOn(label, monster)

	return model
end

function PlotService.UpdateMonsterLabelOn(label: TextLabel, monster: MonsterMath.MonsterData)
	local species = Config.Species[monster.Species]
	local rarity = Config.Rarities[species.Rarity]
	local stage = MonsterMath.GetStage(monster.Level)
	local warning = ""
	if monster.Hunger < Config.LowNeedsThreshold then
		warning = " 🍖"
	elseif monster.Happiness < Config.LowNeedsThreshold then
		warning = " 😢"
	end
	label.Text = string.format(
		'<font color="%s">%s</font>%s\nLv %d · %s · +%s/s',
		colorToHex(rarity.Color),
		MonsterMath.GetDisplayName(monster),
		warning,
		monster.Level,
		stage.Name,
		MonsterMath.FormatNumber(MonsterMath.GetProduction(monster))
	)
end

function PlotService.GetSlotCFrame(plot: Plot, slot: number): CFrame
	return plot.CFrame * slotLocalCFrame(slot) * CFrame.new(0, 0.5, 0)
end

function PlotService.RenderMonster(player: Player, monster: MonsterMath.MonsterData)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	PlotService.RemoveMonster(player, monster.Id)
	if monster.Slot < 1 or monster.Slot > Config.MaxSlots then return end

	local model = PlotService.BuildMonsterModel(monster)
	local body = model.PrimaryPart :: BasePart
	local slotCFrame = PlotService.GetSlotCFrame(plot, monster.Slot)
	model:PivotTo(slotCFrame * CFrame.new(0, PlotService.PivotHeight(model) + 0.2, 0))
	local reach = 8 + model:GetExtentsSize().Y
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MonsterId", monster.Id)

	local name = MonsterMath.GetDisplayName(monster)
	local care = makePrompt(body, "CarePrompt", "Care", Enum.KeyCode.E, 0)
	care.ObjectText = name
	care.MaxActivationDistance = reach
	local monsterId = monster.Id
	care.Triggered:Connect(function(who)
		PlotService.Callbacks.Care(who, player, monsterId)
	end)

	if Config.Steal.Enabled then
		local steal = makePrompt(body, "StealPrompt", "Steal", Enum.KeyCode.F, Config.Steal.HoldDuration)
		steal.ObjectText = name
		steal.MaxActivationDistance = reach
		steal.Triggered:Connect(function(who)
			PlotService.Callbacks.Steal(who, player, monsterId)
		end)
	end

	model.Parent = plot.MonstersFolder
end

function PlotService.RemoveMonster(player: Player, monsterId: string)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local existing = plot.MonstersFolder:FindFirstChild(monsterId)
	if existing then
		existing:Destroy()
	end
end

function PlotService.UpdateMonster(player: Player, monster: MonsterMath.MonsterData, rebuild: boolean)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	if monster.Slot < 1 or monster.Slot > Config.MaxSlots then
		PlotService.RemoveMonster(player, monster.Id)
		return
	end
	local model = plot.MonstersFolder:FindFirstChild(monster.Id) :: Model?
	if not model or rebuild then
		PlotService.RenderMonster(player, monster)
		return
	end
	local body = model.PrimaryPart
	local info = body and body:FindFirstChild("Info")
	local label = info and info:FindFirstChild("Label")
	if label then
		PlotService.UpdateMonsterLabelOn(label :: TextLabel, monster)
	end
end

-- البيض --------------------------------------------------------------------------

function PlotService.RenderEgg(player: Player, eggId: string, eggType: string, slot: number)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	PlotService.RemoveEgg(player, eggId)
	if slot < 1 or slot > Config.MaxSlots then return end
	local egg = Config.Eggs[eggType]
	local part = makePart({
		Name = eggId,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.6, 2.6, 2.6),
		CFrame = PlotService.GetSlotCFrame(plot, slot) * CFrame.new(0, 2, 0),
		Color = egg.Color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	local gui, label = makeBillboard(part, UDim2.fromOffset(160, 40), Vector3.new(0, 3, 0), 70)
	gui.Name = "Info"
	label.Text = egg.DisplayName
	part.Parent = plot.EggsFolder
end

function PlotService.UpdateEggTimer(player: Player, eggId: string, eggType: string, secondsLeft: number)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local part = plot.EggsFolder:FindFirstChild(eggId)
	local info = part and part:FindFirstChild("Info")
	local label = info and info:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = string.format("%s\n⏳ %ds", Config.Eggs[eggType].DisplayName, math.max(0, math.ceil(secondsLeft)))
	end
end

function PlotService.RemoveEgg(player: Player, eggId: string)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local existing = plot.EggsFolder:FindFirstChild(eggId)
	if existing then
		existing:Destroy()
	end
end

-- حالة القاعدة -------------------------------------------------------------------

function PlotService.SetUnlockedSlots(player: Player, count: number)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	for slot, pedestal in plot.Pedestals do
		setPadState(pedestal, slot <= count)
	end
end

local function setCollectorEnabled(plot: Plot, enabled: boolean)
	plot.CollectorEnabled = enabled
	-- Keep references so a freed plot can restore the same collector for its next owner.
	-- Removing the parts from Workspace also removes the label, collision and touch target.
	for _, part in plot.CollectorParts do
		part.Parent = if enabled then plot.Model else nil
	end
end

function PlotService.SetCollectorEnabled(player: Player, enabled: boolean)
	local plot = plotByPlayer[player]
	if plot then setCollectorEnabled(plot, enabled) end
end

function PlotService.SetPending(player: Player, amount: number)
	local plot = plotByPlayer[player]
	if plot then
		plot.CollectorLabel.Text = "💰 " .. MonsterMath.FormatNumber(amount) .. "\nStep here to collect"
	end
end

function PlotService.SetUpgradeLabel(player: Player, text: string)
	local plot = plotByPlayer[player]
	if plot then
		plot.UpgradeLabel.Text = text
	end
end

function PlotService.SetLockVisual(plot: Plot, locked: boolean, text: string)
	if plot.Barrier then
		plot.Barrier.Transparency = if locked then 0.35 else 1
	end
	if plot.LockLabel then
		plot.LockLabel.Text = text
	end
end

function PlotService.IsInsidePlot(plot: Plot, position: Vector3): boolean
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= HALF and math.abs(localPos.Z) <= HALF and localPos.Y > -5 and localPos.Y < 40
end

function PlotService.GetPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.GetPlots(): { Plot }
	return plots
end

function PlotService.SendHome(player: Player)
	local plot = plotByPlayer[player]
	local character = player.Character
	if plot and character then
		character:PivotTo(plot.SpawnCFrame)
	end
end

function PlotService.Assign(player: Player): Plot?
	for _, plot in plots do
		if not plot.Owner then
			setCollectorEnabled(plot, true)
			plot.Owner = player
			plot.LockedUntil = 0
			plot.LockCooldownUntil = 0
			plot.SignLabel.Text = player.DisplayName .. "'s Base"
			if plot.LockPrompt then
				plot.LockPrompt:SetAttribute("OwnerUserId", player.UserId)
			end
			plotByPlayer[player] = plot
			return plot
		end
	end
	return nil
end

function PlotService.Release(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	plot.MonstersFolder:ClearAllChildren()
	plot.EggsFolder:ClearAllChildren()
	plot.Owner = nil
	setCollectorEnabled(plot, true)
	plot.LockedUntil = 0
	plot.SignLabel.Text = "Empty Base"
	plot.CollectorLabel.Text = "💰 0"
	if plot.LockPrompt then
		plot.LockPrompt:SetAttribute("OwnerUserId", nil)
	end
	PlotService.SetLockVisual(plot, false, "🔓 Lock Base")
	for slot, pedestal in plot.Pedestals do
		setPadState(pedestal, slot <= Config.BaseSlots)
	end
	plotByPlayer[player] = nil
end

function PlotService.Init()
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	buildGround()
	buildShop()
	for index, cframe in plotCFrames() do
		table.insert(plots, buildPlot(index, cframe))
	end
end

return PlotService
