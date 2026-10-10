--!strict
-- بيبني الخريطة بالكود (أرض + متجر بيض + قواعد اللاعبين) وبيرسم الوحوش والبيض.
-- كده الماب تشتغل في أي Baseplate فاضي من غير ما تبني حاجة بإيدك.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)

local PLOT_SIZE = 60
local HALF = PLOT_SIZE / 2
local FLOOR_TOP = 0.6 -- المنصة قاعدة على الأرض، مش طايرة
local PAD_SIZE = 7

-- شكل الماب: القواعد جنب بعض في عمود على الشمال (X سالب) وبتبص ناحية +X،
-- قدامها ساحة فيها متجر البيض، وبعدها الطريق اللي داخل على مناطق الوحوش.
local BASE_X = -40
local PLOT_SPACING = PLOT_SIZE + 8
local ISLAND_MIN_X = -80
local PLAZA_MIN_X = -10
local PLAZA_HALF_Z = 220

local theme = Config.BaseThemes[Config.BaseTheme] or Config.BaseThemes.Normal

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
	LockLabel: TextLabel?, -- مش موجودين لما السرقة تبقى مقفولة
	SignLabel: TextLabel,
	LockPrompt: ProximityPrompt?,
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

-- أول المناطق (آخر الساحة) بالـ X
PlotService.ZonesStartX = 50
-- حدود منطقة القواعد والساحة (الجبال بتلف حواليها)
PlotService.IslandMinX = ISLAND_MIN_X
PlotService.PlazaHalfZ = PLAZA_HALF_Z

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
		Size = Vector3.new(PlotService.ZonesStartX - PLAZA_MIN_X, 0.2, PLAZA_HALF_Z * 2 - 20),
		Position = Vector3.new((PLAZA_MIN_X + PlotService.ZonesStartX) / 2, 0.1, 0),
		Color = Color3.fromRGB(150, 150, 155),
		Material = Enum.Material.Cobblestone,
		Parent = mapFolder,
	})
	-- مية حوالين الماب كلها
	makePart({
		Name = "Water",
		Size = Vector3.new(2000, 1, 1000),
		Position = Vector3.new(300, -4, 0),
		Color = Color3.fromRGB(40, 110, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = mapFolder,
	})
end

local SHOP_ORIGIN = Vector3.new(20, 0, -100)
PlotService.ShopPosition = SHOP_ORIGIN

local function buildShop()
	local shopModel = Instance.new("Model")
	shopModel.Name = "EggShop"
	shopModel.Parent = mapFolder

	local counter = makePart({
		Name = "Counter",
		Size = Vector3.new(16, 4, 6),
		Position = SHOP_ORIGIN + Vector3.new(0, 2, 0),
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.Wood,
		Parent = shopModel,
	})
	makePart({
		Name = "Roof",
		Size = Vector3.new(20, 1, 10),
		Position = SHOP_ORIGIN + Vector3.new(0, 11, 0),
		Color = Color3.fromRGB(230, 80, 80),
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
	spawn.Position = Vector3.new(20, 0.5, 40)
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

-- القاعدة: منصة مفتوحة على الأرض (مش طايرة).
-- محلياً: -Z هو قدام القاعدة (ناحية الساحة)، +Z ورا.
-- 10 أماكن للوحوش حوالين الأطراف: 4 ورا، و2 على كل جنب، و2 قدام. كلها بتبص على النص.
local SLOT_POSITIONS = {
	Vector3.new(-6.5, 0, 20.5),
	Vector3.new(6.5, 0, 20.5),
	Vector3.new(-19.5, 0, 20.5),
	Vector3.new(19.5, 0, 20.5),
	Vector3.new(-22, 0, 6),
	Vector3.new(22, 0, 6),
	Vector3.new(-22, 0, -8),
	Vector3.new(22, 0, -8),
	Vector3.new(-14, 0, -21),
	Vector3.new(14, 0, -21),
}

local function slotLocalCFrame(slot: number): CFrame
	local position = SLOT_POSITIONS[slot] + Vector3.new(0, FLOOR_TOP + 0.75, 0)
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

local LOCKED_PAD_COLOR = Color3.fromRGB(60, 60, 66)

local function setPadState(pad: BasePart, unlocked: boolean)
	pad.Color = if unlocked then theme.PadColor else LOCKED_PAD_COLOR
	pad.Material = if unlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic
	pad.Transparency = if unlocked then 0 else 0.4
end

local function buildPlot(index: number, cframe: CFrame): Plot
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model.Parent = mapFolder

	local function at(localPosition: Vector3): CFrame
		return cframe * CFrame.new(localPosition)
	end
	local function block(name: string, size: Vector3, localPosition: Vector3, props: { [string]: any }?): Part
		local all: { [string]: any } = {
			Name = name,
			Size = size,
			CFrame = at(localPosition),
			Color = theme.StoneColor,
			Material = theme.StoneMaterial,
			Parent = model,
		}
		if props then
			for key, value in props do
				all[key] = value
			end
		end
		return makePart(all)
	end
	local function glow(part: BasePart, color: Color3, range: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = 1.5
		light.Parent = part
	end
	local function neon(color: Color3): { [string]: any }
		return { Color = color, Material = Enum.Material.Neon, CanCollide = false }
	end

	-- فانوس صغير على عمود
	local function lantern(position: Vector3)
		block("LanternPost", Vector3.new(0.6, 3, 0.6), position + Vector3.new(0, FLOOR_TOP + 1.5, 0), {
			Color = Color3.fromRGB(70, 50, 35),
			Material = Enum.Material.Wood,
		})
		block("LanternCap", Vector3.new(1.6, 0.4, 1.6), position + Vector3.new(0, FLOOR_TOP + 4.6, 0), {
			Color = Color3.fromRGB(45, 40, 40),
			Material = Enum.Material.Metal,
		})
		local light = block("Lantern", Vector3.new(1.2, 1.4, 1.2), position + Vector3.new(0, FLOOR_TOP + 3.7, 0), neon(theme.LanternColor))
		glow(light, theme.LanternColor, 12)
	end

	-- شجرة على حسب النسخة (بلوكات زي التصميم)
	local function tree(position: Vector3, scale: number)
		local base = position + Vector3.new(0, FLOOR_TOP, 0)
		local trunkColor = Color3.fromRGB(105, 70, 40)
		if theme.Foliage == "Oak" then
			block("Trunk", Vector3.new(1.4, 5, 1.4) * scale, base + Vector3.new(0, 2.5 * scale, 0), { Color = trunkColor, Material = Enum.Material.Wood })
			block("Leaves", Vector3.new(5, 4, 5) * scale, base + Vector3.new(0, 6 * scale, 0), { Color = theme.FoliageColor, Material = Enum.Material.Grass, CanCollide = false })
			block("Leaves", Vector3.new(3.4, 2.4, 3.4) * scale, base + Vector3.new(0.6 * scale, 8.6 * scale, -0.4 * scale), { Color = theme.FoliageColor:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.Grass, CanCollide = false })
		elseif theme.Foliage == "Pine" then
			block("Trunk", Vector3.new(1, 2, 1) * scale, base + Vector3.new(0, 1 * scale, 0), { Color = trunkColor, Material = Enum.Material.Wood })
			for i, width in { 5, 3.8, 2.6, 1.4 } do
				block("Pine", Vector3.new(width, 1.6, width) * scale, base + Vector3.new(0, (1.6 + i * 1.5) * scale, 0), { Color = if i % 2 == 0 then Color3.fromRGB(60, 120, 80) else theme.FoliageColor, Material = Enum.Material.Snow, CanCollide = false })
			end
		elseif theme.Foliage == "Palm" then
			block("Trunk", Vector3.new(0.9, 8, 0.9) * scale, base + Vector3.new(0, 4 * scale, 0), { Color = Color3.fromRGB(150, 110, 60), Material = Enum.Material.Wood })
			for i = 0, 3 do
				local leafCFrame = at(base + Vector3.new(0, 8 * scale, 0)) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -1.8 * scale) * CFrame.Angles(math.rad(-20), 0, 0)
				makePart({ Name = "PalmLeaf", Size = Vector3.new(1.4, 0.3, 4) * scale, CFrame = leafCFrame, Color = theme.FoliageColor, Material = Enum.Material.Grass, CanCollide = false, Parent = model })
			end
		elseif theme.Foliage == "Spikes" then
			for i, height in { 4, 2.6, 2.2 } do
				local offset = Vector3.new((i - 2) * 1.2, height / 2, (i % 2) * 0.8)
				makePart({ Name = "Spike", Size = Vector3.new(1, height, 1) * scale, CFrame = at(base + offset * scale) * CFrame.Angles(0, math.rad(45), math.rad((i - 2) * 12)), Color = theme.FoliageColor, Material = Enum.Material.Neon, Parent = model })
			end
		elseif theme.Foliage == "Dead" then
			block("Trunk", Vector3.new(1, 5, 1) * scale, base + Vector3.new(0, 2.5 * scale, 0), { Color = theme.FoliageColor, Material = Enum.Material.Wood })
			for _, side in { -1, 1 } do
				makePart({ Name = "Branch", Size = Vector3.new(0.5, 2.6, 0.5) * scale, CFrame = at(base + Vector3.new(side * 0.9, 5 * scale, 0)) * CFrame.Angles(0, 0, side * -0.7), Color = theme.FoliageColor, Material = Enum.Material.Wood, Parent = model })
			end
		end
	end

	local baseColor = Config.PlotColors[index] or Color3.fromRGB(110, 120, 140)

	-- المنصة: حافة (عشب) وجواها البلاط، قاعدة على الأرض على طول
	block("Rim", Vector3.new(PLOT_SIZE, FLOOR_TOP, PLOT_SIZE), Vector3.new(0, FLOOR_TOP / 2, 0), {
		Color = theme.RimColor,
		Material = theme.RimMaterial,
	})
	block("Floor", Vector3.new(PLOT_SIZE - 4, 0.1, PLOT_SIZE - 4), Vector3.new(0, FLOOR_TOP + 0.05, 0), {
		Color = theme.FloorColor,
		Material = theme.FloorMaterial,
	})

	-- 4 أعمدة في الأركان وفوقها كريستالة أو شعلة أو فانوس، وعليها راية
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = Vector3.new(sx * 26.5, 0, sz * 26.5)
			block("Pillar", Vector3.new(5, 8, 5), corner + Vector3.new(0, FLOOR_TOP + 4, 0))
			block("PillarCap", Vector3.new(6, 1, 6), corner + Vector3.new(0, FLOOR_TOP + 8.5, 0))
			block("Banner", Vector3.new(0.2, 4, 2.6), corner + Vector3.new(-sx * 2.6, FLOOR_TOP + 4.5, 0), {
				Color = theme.BannerColor,
				Material = Enum.Material.Fabric,
			})
			block("BannerEmblem", Vector3.new(0.25, 1.4, 1.2), corner + Vector3.new(-sx * 2.65, FLOOR_TOP + 5, 0), {
				Color = Color3.fromRGB(240, 190, 60),
				Material = Enum.Material.Foil,
			})
			local topY = FLOOR_TOP + 9
			local top: BasePart
			if theme.PillarTop == "Crystal" then
				top = makePart({
					Name = "Crystal",
					Size = Vector3.new(1.8, 4, 1.8),
					CFrame = at(corner + Vector3.new(0, topY + 2, 0)) * CFrame.Angles(0, math.rad(45), 0),
					Color = theme.PillarTopColor,
					Material = Enum.Material.Neon,
					Parent = model,
				})
				for i = 0, 3 do
					makePart({
						Name = "Crystal",
						Size = Vector3.new(0.9, 2.2, 0.9),
						CFrame = at(corner + Vector3.new(0, topY + 1, 0)) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -1.4) * CFrame.Angles(math.rad(-25), 0, 0),
						Color = theme.PillarTopColor,
						Material = Enum.Material.Neon,
						Parent = model,
					})
				end
			elseif theme.PillarTop == "Flame" then
				block("Brazier", Vector3.new(3, 1, 3), corner + Vector3.new(0, topY + 0.5, 0), { Color = Color3.fromRGB(40, 35, 35), Material = Enum.Material.Metal })
				top = block("FlameCore", Vector3.new(1.6, 1.6, 1.6), corner + Vector3.new(0, topY + 1.8, 0), neon(theme.PillarTopColor))
				local fire = Instance.new("Fire")
				fire.Color = theme.PillarTopColor
				fire.SecondaryColor = theme.PillarTopColor:Lerp(Color3.new(1, 1, 1), 0.4)
				fire.Size = 4
				fire.Heat = 6
				fire.Parent = top
			else
				block("LanternFrame", Vector3.new(2.6, 0.5, 2.6), corner + Vector3.new(0, topY + 3.4, 0), { Color = Color3.fromRGB(45, 40, 40), Material = Enum.Material.Metal })
				top = block("Lantern", Vector3.new(2, 2.6, 2), corner + Vector3.new(0, topY + 1.8, 0), neon(theme.PillarTopColor))
			end
			glow(top, theme.PillarTopColor, 18)
		end
	end

	-- النص: قاعدة حجر بدرجتين وعليها شجرة كبيرة أو كريستالة أو كورة، وفوانيس على الأركان
	block("CenterBase", Vector3.new(14, 1.2, 14), Vector3.new(0, FLOOR_TOP + 0.6, 0))
	block("CenterTop", Vector3.new(10, 1.2, 10), Vector3.new(0, FLOOR_TOP + 1.8, 0))
	local centerY = FLOOR_TOP + 2.4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local post = block("CenterLantern", Vector3.new(0.9, 1.2, 0.9), Vector3.new(sx * 6, FLOOR_TOP + 1.8, sz * 6), neon(theme.LanternColor))
			glow(post, theme.LanternColor, 8)
		end
	end
	if theme.Center == "Tree" or theme.Center == "GoldenTree" then
		local golden = theme.Center == "GoldenTree"
		if not golden then
			block("Water", Vector3.new(9, 0.2, 9), Vector3.new(0, centerY + 0.1, 0), {
				Color = theme.CenterColor,
				Material = Enum.Material.Glass,
				Transparency = 0.2,
				CanCollide = false,
			})
		end
		block("CenterTrunk", Vector3.new(2, 7, 2), Vector3.new(0, centerY + 3.5, 0), {
			Color = if golden then theme.CenterColor else Color3.fromRGB(105, 70, 40),
			Material = if golden then Enum.Material.Foil else Enum.Material.Wood,
		})
		local leafColor = if golden then theme.CenterColor:Lerp(Color3.new(1, 1, 0.6), 0.2) else theme.FoliageColor
		local leafMaterial = if golden then Enum.Material.Foil else Enum.Material.Grass
		for _, leaf in {
			{ Vector3.new(8, 4, 8), Vector3.new(0, 8.5, 0) },
			{ Vector3.new(5, 3, 5), Vector3.new(1, 11.5, -0.5) },
			{ Vector3.new(4, 3, 4), Vector3.new(-2.5, 9.5, 2) },
		} do
			block("CenterLeaves", leaf[1], Vector3.new(0, centerY, 0) + leaf[2], { Color = leafColor, Material = leafMaterial, CanCollide = false })
		end
	elseif theme.Center == "Crystal" or theme.Center == "Flame" then
		local crystal = makePart({
			Name = "CenterCrystal",
			Size = Vector3.new(3, 8, 3),
			CFrame = at(Vector3.new(0, centerY + 4, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Color = theme.CenterColor,
			Material = Enum.Material.Neon,
			Parent = model,
		})
		for i = 0, 3 do
			makePart({
				Name = "CenterCrystal",
				Size = Vector3.new(1.4, 4, 1.4),
				CFrame = at(Vector3.new(0, centerY + 2, 0)) * CFrame.Angles(0, i * math.pi / 2 + 0.4, 0) * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(-22), 0, 0),
				Color = theme.CenterColor,
				Material = Enum.Material.Neon,
				Parent = model,
			})
		end
		glow(crystal, theme.CenterColor, 22)
		if theme.Center == "Flame" then
			local fire = Instance.new("Fire")
			fire.Color = theme.CenterColor
			fire.Size = 8
			fire.Parent = crystal
		end
	else -- Orb
		block("OrbStand", Vector3.new(3, 2, 3), Vector3.new(0, centerY + 1, 0))
		local orb = block("Orb", Vector3.new(4.5, 4.5, 4.5), Vector3.new(0, centerY + 4.4, 0), {
			Shape = Enum.PartType.Ball,
			Color = theme.CenterColor,
			Material = Enum.Material.Neon,
		})
		glow(orb, theme.CenterColor, 22)
	end

	-- 4 جناين صغيرة بين النص والأطراف
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local patch = Vector3.new(sx * 13, 0, sz * 11)
			block("Garden", Vector3.new(8, 0.4, 8), patch + Vector3.new(0, FLOOR_TOP + 0.2, 0), {
				Color = theme.GardenColor,
				Material = theme.GardenMaterial,
			})
			block("Bush", Vector3.new(2.6, 2, 2.6), patch + Vector3.new(sx * 1.5, FLOOR_TOP + 1.2, sz * 1.5), {
				Color = theme.FoliageColor:Lerp(Color3.new(0, 0, 0), 0.15),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
			block("Bush", Vector3.new(1.6, 1.4, 1.6), patch + Vector3.new(-sx * 1.6, FLOOR_TOP + 0.9, -sz * 1.2), {
				Color = theme.FoliageColor,
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
		end
	end

	-- ديكور الأطراف: شجر ورا وفوانيس وسور حجر واطي متكسّر
	tree(Vector3.new(-14, 0, 27.5), 1)
	tree(Vector3.new(14, 0, 27.5), 1)
	tree(Vector3.new(-27.5, 0, 14), 0.8)
	tree(Vector3.new(27.5, 0, -1), 0.8)
	for _, position in {
		Vector3.new(0, 0, 27.5),
		Vector3.new(-27.5, 0, -1),
		Vector3.new(27.5, 0, 14),
		Vector3.new(-27.5, 0, -15),
		Vector3.new(27.5, 0, -15),
		Vector3.new(-9.5, 0, -27.5),
		Vector3.new(9.5, 0, -27.5),
	} do
		lantern(position)
	end
	for _, piece in {
		{ Vector3.new(7, 1.6, 1.4), Vector3.new(-20.5, 0, 28.4) },
		{ Vector3.new(7, 1.6, 1.4), Vector3.new(20.5, 0, 28.4) },
		{ Vector3.new(1.4, 1.6, 6), Vector3.new(-28.4, 0, 21) },
		{ Vector3.new(1.4, 1.6, 6), Vector3.new(28.4, 0, 21) },
	} do
		block("LowWall", piece[1], piece[2] + Vector3.new(0, FLOOR_TOP + 0.8, 0))
	end

	-- أماكن الوحوش: قاعدة حجر وعليها إطار نيون وجواه بلاطة غامقة
	local pedestals: { BasePart } = {}
	for slot = 1, Config.MaxSlots do
		local slotCFrame = cframe * slotLocalCFrame(slot)
		makePart({
			Name = "PadBase",
			Size = Vector3.new(PAD_SIZE + 1.2, 0.6, PAD_SIZE + 1.2),
			CFrame = slotCFrame * CFrame.new(0, -0.45, 0),
			Color = theme.StoneColor,
			Material = theme.StoneMaterial,
			Parent = model,
		})
		local pad = makePart({
			Name = "Pedestal_" .. slot,
			Size = Vector3.new(PAD_SIZE, 0.3, PAD_SIZE),
			CFrame = slotCFrame,
			Parent = model,
		})
		setPadState(pad, true)
		makePart({
			Name = "PadInner",
			Size = Vector3.new(PAD_SIZE - 1, 0.34, PAD_SIZE - 1),
			CFrame = slotCFrame,
			Color = Color3.fromRGB(25, 30, 40),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		pedestals[slot] = pad
	end

	-- قدام: صندوق تجميع الفلوس، ويافطة بلون القاعدة عليها اسم صاحبها
	local collector = block("Collector", Vector3.new(6, 0.4, 6), Vector3.new(0, FLOOR_TOP + 0.2, -22), {
		Color = Color3.fromRGB(60, 230, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	block("Chest", Vector3.new(3, 1.8, 2), Vector3.new(0, FLOOR_TOP + 0.9, -19.4), {
		Color = Color3.fromRGB(120, 75, 40),
		Material = Enum.Material.Wood,
	})
	block("ChestLid", Vector3.new(3.2, 0.6, 2.2), Vector3.new(0, FLOOR_TOP + 2.1, -19.4), {
		Color = Color3.fromRGB(240, 190, 60),
		Material = Enum.Material.Foil,
	})
	local collectorGui, collectorLabel = makeBillboard(collector, UDim2.fromOffset(200, 50), Vector3.new(0, 5, 0), 80)
	collectorGui.AlwaysOnTop = false -- مايبانش من ورا القواعد التانية
	collectorLabel.Text = "💰 0"

	for _, side in { -1, 1 } do
		block("SignPost", Vector3.new(0.6, 6, 0.6), Vector3.new(side * 5, FLOOR_TOP + 3, -29), {
			Color = Color3.fromRGB(70, 50, 35),
			Material = Enum.Material.Wood,
		})
	end
	local signBoard = block("SignBoard", Vector3.new(10.6, 2.2, 0.4), Vector3.new(0, FLOOR_TOP + 5, -29), {
		Color = baseColor,
		Material = Enum.Material.SmoothPlastic,
	})
	local signGui, signLabel = makeBillboard(signBoard, UDim2.fromScale(22, 3.5), Vector3.new(0, 3.2, 0), 200)
	signGui.AlwaysOnTop = false -- عشان لافتات القواعد مايركبوش على بعض
	signLabel.Text = "Empty Base"
	signLabel.TextColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.4)

	-- حاجز القفل على حافة القاعدة القدامية (بيشتغل بس لو السرقة مفتوحة)
	local barrier = block("LockBarrier", Vector3.new(PLOT_SIZE, 10, 1), Vector3.new(0, FLOOR_TOP + 5, -HALF), {
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
	})

	-- زرار القفل بيتعمل بس لو السرقة شغالة
	local lockLabel: TextLabel? = nil
	local lockPrompt: ProximityPrompt? = nil
	if Config.Steal.Enabled then
		local lockButton = block("LockButton", Vector3.new(4, 1, 4), Vector3.new(-7, FLOOR_TOP + 0.5, -21), {
			Color = Color3.fromRGB(230, 50, 50),
			Material = Enum.Material.SmoothPlastic,
		})
		local _, label = makeBillboard(lockButton, UDim2.fromOffset(200, 50), Vector3.new(0, 4, 0))
		label.Text = "🔓 Lock Base"
		lockLabel = label
		lockPrompt = makePrompt(lockButton, "LockPrompt", "Lock Base", Enum.KeyCode.E, 0.5)
	end

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
		SpawnCFrame = at(Vector3.new(0, FLOOR_TOP + 3, -14)) * CFrame.Angles(0, math.pi, 0),
	}

	collector.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and player == plot.Owner then
			PlotService.Callbacks.Collect(player)
		end
	end)

	if lockPrompt then
		lockPrompt.Triggered:Connect(function(player)
			if player == plot.Owner then
				PlotService.Callbacks.Lock(player)
			end
		end)
	end

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
			root.CFrame = cframe * CFrame.new(0, 3, -HALF - 10)
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
	if stage.Name == "Legendary" and not monster.Hat then
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
		if monster.Hat == "TopHat" then
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.4, 2.4) * scale, Color = hat.Color }), CFrame.new(0, top + 0.1 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
			attach(makePart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.5, 1.5) * scale, Color = hat.Color }), CFrame.new(0, top + 0.9 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
		elseif monster.Hat == "WizardHat" then
			for i, width in { 2.2, 1.5, 0.9, 0.4 } do
				attach(makePart({ Name = "Hat", Size = Vector3.new(width, 0.6, width) * scale, Color = hat.Color, Material = hatProps.Material }), CFrame.new(0, top + (0.2 + (i - 1) * 0.55) * scale, 0) * CFrame.Angles(0, i * 0.3, 0))
			end
		elseif monster.Hat == "Crown" then
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
		if monster.Glasses == "Monocle" then
			attach(makePart({ Name = "Glasses", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.9, 0.9) * scale, Color = glasses.Color, Material = Enum.Material.Foil }), CFrame.new(0.6 * scale, eyeY, front) * CFrame.Angles(0, math.rad(90), 0))
		else
			for _, side in { -1, 1 } do
				local lens = makePart({ Name = "Glasses", Size = Vector3.new(0.85, 0.6, 0.1) * scale, Color = glasses.Color, Material = if monster.Glasses == "StarGlasses" then Enum.Material.Neon else Enum.Material.Glass })
				attach(lens, CFrame.new(side * 0.6 * scale, eyeY, front) * (if monster.Glasses == "StarGlasses" then CFrame.Angles(0, 0, math.rad(45)) else CFrame.new()))
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
	local monsterId = monster.Id
	care.Triggered:Connect(function(who)
		PlotService.Callbacks.Care(who, player, monsterId)
	end)

	if Config.Steal.Enabled then
		local steal = makePrompt(body, "StealPrompt", "Steal", Enum.KeyCode.F, Config.Steal.HoldDuration)
		steal.ObjectText = name
		steal.MaxActivationDistance = 8 + body.Size.Y
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
		setPadState(pedestal, slot <= count)
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
	plot.LockedUntil = 0
	plot.SignLabel.Text = "Empty Base"
	plot.CollectorLabel.Text = "💰 0"
	if plot.LockPrompt then
		plot.LockPrompt:SetAttribute("OwnerUserId", nil)
	end
	PlotService.SetLockVisual(plot, false, "🔓 Lock Base")
	for _, pedestal in plot.Pedestals do
		setPadState(pedestal, true)
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
