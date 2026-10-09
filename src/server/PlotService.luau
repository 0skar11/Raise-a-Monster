--!strict
-- بيبني الخريطة بالكود (أرض + متجر بيض + قواعد اللاعبين) وبيرسم الوحوش والبيض.
-- كده الماب تشتغل في أي Baseplate فاضي من غير ما تبني حاجة بإيدك.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)

local PLOT_SIZE = 60
local HALF = PLOT_SIZE / 2
local WALL_HEIGHT = 12
local ENTRANCE_WIDTH = 16
local FLOOR_TOP = 0.5

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
	Barrier: BasePart,
	CollectorLabel: TextLabel,
	LockLabel: TextLabel,
	SignLabel: TextLabel,
	LockPrompt: ProximityPrompt,
	SpawnCFrame: CFrame,
}

type Callbacks = {
	Collect: (player: Player) -> (),
	Lock: (player: Player) -> (),
	OpenShop: (player: Player) -> (),
	Care: (player: Player, owner: Player, monsterId: string) -> (),
	Steal: (player: Player, owner: Player, monsterId: string) -> (),
}

local PlotService = {}

PlotService.Callbacks = {
	Collect = function() end,
	Lock = function() end,
	OpenShop = function() end,
	Care = function() end,
	Steal = function() end,
} :: Callbacks

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local mapFolder: Folder

-- أدوات مساعدة ------------------------------------------------------------------

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

local function makeBillboard(
	adornee: BasePart,
	size: UDim2,
	offset: Vector3,
	maxDistance: number?
): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 120
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.RichText = true
	label.Parent = gui
	return gui, label
end

local function makePrompt(parent: Instance, name: string, action: string, key: Enum.KeyCode, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function colorToHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

-- الخريطة ----------------------------------------------------------------------

local function buildGround()
	if workspace:FindFirstChild("Baseplate") then
		return
	end
	makePart({
		Name = "Ground",
		Size = Vector3.new(420, 2, 320),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(95, 160, 80),
		Material = Enum.Material.Grass,
		Parent = mapFolder,
	})
end

local function buildShop()
	local shopModel = Instance.new("Model")
	shopModel.Name = "EggShop"
	shopModel.Parent = mapFolder

	local counter = makePart({
		Name = "Counter",
		Size = Vector3.new(16, 4, 6),
		Position = Vector3.new(0, 2, 12),
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.Wood,
		Parent = shopModel,
	})
	makePart({
		Name = "Roof",
		Size = Vector3.new(20, 1, 10),
		Position = Vector3.new(0, 11, 12),
		Color = Color3.fromRGB(230, 80, 80),
		Parent = shopModel,
	})
	for _, x in { -9, 9 } do
		makePart({
			Name = "Pole",
			Size = Vector3.new(1, 7, 1),
			Position = Vector3.new(x, 7.5, 12),
			Color = Color3.fromRGB(240, 240, 240),
			Parent = shopModel,
		})
	end

	local sortedEggs = {}
	for _, egg in Config.Eggs do
		table.insert(sortedEggs, egg)
	end
	table.sort(sortedEggs, function(a, b)
		return a.Order < b.Order
	end)
	for i, egg in sortedEggs do
		local eggPart = makePart({
			Name = "DisplayEgg",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.4, 2.4),
			Position = Vector3.new((i - 2) * 5, 5.4, 12),
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
	title.Text = "🥚 EGG SHOP 🥚"
	title.TextColor3 = Color3.fromRGB(255, 230, 120)

	local prompt = makePrompt(counter, "ShopPrompt", "Open Shop", Enum.KeyCode.E, 0)
	prompt.ObjectText = "Egg Shop"
	prompt.MaxActivationDistance = 14
	prompt.Triggered:Connect(function(player)
		PlotService.Callbacks.OpenShop(player)
	end)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CenterSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, -4)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = mapFolder
end

local function plotCFrames(): { CFrame }
	local result = {}
	local columns = Config.MaxPlots // 2
	local spacing = PLOT_SIZE + 12
	local rowOffset = HALF + 40
	for row = 0, 1 do
		local z = if row == 0 then -rowOffset else rowOffset
		local facing = if row == 0 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
		for column = 1, columns do
			local x = (column - (columns + 1) / 2) * spacing
			local position = Vector3.new(x, 0, z)
			table.insert(result, CFrame.lookAt(position, position + facing))
		end
	end
	return result
end

-- محلياً: -Z هو اتجاه المدخل (ناحية الشارع)، +Z ورا القاعدة.
local function slotLocalPosition(slot: number): Vector3
	local row = if slot <= 5 then 0 else 1
	local column = ((slot - 1) % 5) - 2
	return Vector3.new(column * 10, FLOOR_TOP + 0.5, 4 + row * 14)
end

local function buildPlot(index: number, cframe: CFrame): Plot
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model.Parent = mapFolder

	local function at(localPosition: Vector3): CFrame
		return cframe * CFrame.new(localPosition)
	end

	makePart({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		CFrame = at(Vector3.new(0, 0, 0)),
		Color = Color3.fromRGB(200, 190, 170),
		Material = Enum.Material.Slate,
		Parent = model,
	})

	local wallColor = Color3.fromRGB(110, 120, 140)
	local function wall(name: string, size: Vector3, position: Vector3)
		makePart({
			Name = name,
			Size = size,
			CFrame = at(position),
			Color = wallColor,
			Material = Enum.Material.Brick,
			Parent = model,
		})
	end
	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	wall("BackWall", Vector3.new(PLOT_SIZE, WALL_HEIGHT, 1), Vector3.new(0, wallY, HALF - 0.5))
	wall("LeftWall", Vector3.new(1, WALL_HEIGHT, PLOT_SIZE), Vector3.new(-HALF + 0.5, wallY, 0))
	wall("RightWall", Vector3.new(1, WALL_HEIGHT, PLOT_SIZE), Vector3.new(HALF - 0.5, wallY, 0))
	local sideWidth = (PLOT_SIZE - ENTRANCE_WIDTH) / 2
	wall(
		"FrontWallLeft",
		Vector3.new(sideWidth, WALL_HEIGHT, 1),
		Vector3.new(-(ENTRANCE_WIDTH / 2 + sideWidth / 2), wallY, -HALF + 0.5)
	)
	wall(
		"FrontWallRight",
		Vector3.new(sideWidth, WALL_HEIGHT, 1),
		Vector3.new(ENTRANCE_WIDTH / 2 + sideWidth / 2, wallY, -HALF + 0.5)
	)

	local signPart = makePart({
		Name = "Sign",
		Size = Vector3.new(ENTRANCE_WIDTH, 1, 1),
		CFrame = at(Vector3.new(0, FLOOR_TOP + WALL_HEIGHT - 0.5, -HALF + 0.5)),
		Color = wallColor,
		Material = Enum.Material.Brick,
		Parent = model,
	})
	local _, signLabel = makeBillboard(signPart, UDim2.fromOffset(300, 50), Vector3.new(0, 3, 0), 200)
	signLabel.Text = "Empty Base"

	local barrier = makePart({
		Name = "LockBarrier",
		Size = Vector3.new(ENTRANCE_WIDTH, WALL_HEIGHT - 1, 1),
		CFrame = at(Vector3.new(0, FLOOR_TOP + (WALL_HEIGHT - 1) / 2, -HALF + 0.5)),
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	local pedestals: { BasePart } = {}
	for slot = 1, Config.MaxSlots do
		local pedestal = makePart({
			Name = "Pedestal_" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 7, 7),
			CFrame = at(slotLocalPosition(slot)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(90, 90, 100),
			Material = Enum.Material.Marble,
			Parent = model,
		})
		pedestals[slot] = pedestal
	end

	local collector = makePart({
		Name = "Collector",
		Size = Vector3.new(8, 0.4, 8),
		CFrame = at(Vector3.new(-18, FLOOR_TOP + 0.2, -18)),
		Color = Color3.fromRGB(60, 230, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local _, collectorLabel = makeBillboard(collector, UDim2.fromOffset(200, 50), Vector3.new(0, 4, 0))
	collectorLabel.Text = "💰 0"

	local lockButton = makePart({
		Name = "LockButton",
		Size = Vector3.new(5, 1, 5),
		CFrame = at(Vector3.new(18, FLOOR_TOP + 0.5, -18)),
		Color = Color3.fromRGB(230, 50, 50),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local _, lockLabel = makeBillboard(lockButton, UDim2.fromOffset(200, 50), Vector3.new(0, 4, 0))
	lockLabel.Text = "🔓 Lock Base"
	local lockPrompt = makePrompt(lockButton, "LockPrompt", "Lock Base", Enum.KeyCode.E, 0.5)

	local monstersFolder = Instance.new("Folder")
	monstersFolder.Name = "Monsters"
	monstersFolder.Parent = model

	local eggsFolder = Instance.new("Folder")
	eggsFolder.Name = "Eggs"
	eggsFolder.Parent = model

	local plot: Plot = {
		Index = index,
		Model = model,
		CFrame = cframe,
		Owner = nil,
		LockedUntil = 0,
		LockCooldownUntil = 0,
		Pedestals = pedestals,
		MonstersFolder = monstersFolder,
		EggsFolder = eggsFolder,
		Barrier = barrier,
		CollectorLabel = collectorLabel,
		LockLabel = lockLabel,
		SignLabel = signLabel,
		LockPrompt = lockPrompt,
		SpawnCFrame = at(Vector3.new(0, FLOOR_TOP + 3, -12)) * CFrame.Angles(0, math.pi, 0),
	}

	collector.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and player == plot.Owner then
			PlotService.Callbacks.Collect(player)
		end
	end)

	lockPrompt.Triggered:Connect(function(player)
		if player == plot.Owner then
			PlotService.Callbacks.Lock(player)
		end
	end)

	-- لو القاعدة مقفولة، أي حد غير صاحبها بيترمي برّه.
	barrier.Touched:Connect(function(hit)
		if os.clock() >= plot.LockedUntil then
			return
		end
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if not player or player == plot.Owner or not character then
			return
		end
		local root = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.CFrame = cframe * CFrame.new(0, FLOOR_TOP + 3, -HALF - 8)
		end
	end)

	return plot
end

-- رسم الوحوش ----------------------------------------------------------------

function PlotService.BuildMonsterModel(monster: MonsterMath.MonsterData): Model
	local species = Config.Species[monster.Species]
	local stage = MonsterMath.GetStage(monster.Level)
	local mutation = MonsterMath.GetMutation(monster.Mutation)
	local scale = stage.Scale
	local color = if mutation and mutation.Color then mutation.Color else species.Color

	local model = Instance.new("Model")
	model.Name = monster.Id

	local material = Enum.Material.SmoothPlastic
	if monster.Mutation == "Golden" then
		material = Enum.Material.Foil
	elseif monster.Mutation == "Toxic" or monster.Mutation == "Rainbow" then
		material = Enum.Material.Neon
	end

	local bodySize = 3 * scale
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
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

	-- العيون (الوش ناحية -Z)
	for _, side in { -1, 1 } do
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
	for _, side in { -1, 1 } do
		local foot = makePart({
			Name = "Foot",
			Size = Vector3.new(0.9, 0.6, 1.2) * scale,
			Color = color,
			Material = material,
		})
		attach(foot, CFrame.new(side * 0.8 * scale, -1.4 * scale, -0.2 * scale))
	end

	if species.Horns then
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
	if stage.Name == "Legendary" then
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
	return plot.CFrame * CFrame.new(slotLocalPosition(slot) + Vector3.new(0, 0.5, 0))
end

function PlotService.RenderMonster(player: Player, monster: MonsterMath.MonsterData)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	PlotService.RemoveMonster(player, monster.Id)

	local model = PlotService.BuildMonsterModel(monster)
	local body = model.PrimaryPart :: BasePart
	local slotCFrame = PlotService.GetSlotCFrame(plot, monster.Slot)
	model:PivotTo(slotCFrame * CFrame.new(0, body.Size.Y / 2 + 0.3 + body.Size.Y * 0.1, 0))
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MonsterId", monster.Id)

	local name = MonsterMath.GetDisplayName(monster)
	local care = makePrompt(body, "CarePrompt", "Care", Enum.KeyCode.E, 0)
	care.ObjectText = name
	care.MaxActivationDistance = 8 + body.Size.Y
	local steal = makePrompt(body, "StealPrompt", "Steal", Enum.KeyCode.F, Config.Steal.HoldDuration)
	steal.ObjectText = name
	steal.MaxActivationDistance = 8 + body.Size.Y

	local monsterId = monster.Id
	care.Triggered:Connect(function(who)
		PlotService.Callbacks.Care(who, player, monsterId)
	end)
	steal.Triggered:Connect(function(who)
		PlotService.Callbacks.Steal(who, player, monsterId)
	end)

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
		local unlocked = slot <= count
		pedestal.Transparency = if unlocked then 0 else 0.75
		pedestal.Color = if unlocked then Color3.fromRGB(90, 90, 100) else Color3.fromRGB(60, 60, 60)
	end
end

function PlotService.SetPending(player: Player, amount: number)
	local plot = plotByPlayer[player]
	if plot then
		plot.CollectorLabel.Text = "💰 " .. MonsterMath.FormatNumber(amount) .. "\nStep here to collect"
	end
end

function PlotService.SetLockVisual(plot: Plot, locked: boolean, text: string)
	plot.Barrier.Transparency = if locked then 0.35 else 1
	plot.LockLabel.Text = text
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
			plot.Owner = player
			plot.LockedUntil = 0
			plot.LockCooldownUntil = 0
			plot.SignLabel.Text = player.DisplayName .. "'s Base"
			plot.LockPrompt:SetAttribute("OwnerUserId", player.UserId)
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
	plot.LockedUntil = 0
	plot.SignLabel.Text = "Empty Base"
	plot.CollectorLabel.Text = "💰 0"
	plot.LockPrompt:SetAttribute("OwnerUserId", nil)
	PlotService.SetLockVisual(plot, false, "🔓 Lock Base")
	for _, pedestal in plot.Pedestals do
		pedestal.Transparency = 0
		pedestal.Color = Color3.fromRGB(90, 90, 100)
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
