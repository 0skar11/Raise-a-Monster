--!strict
-- كل أرقام اللعبة في مكان واحد عشان تعدّل التوازن بسهولة.

local Config = {}

Config.StartingCoins = 150
Config.DataStoreName = "RaiseAMonster_v1"
Config.AutosaveInterval = 60 -- ثواني
Config.DataSave = {
	MaxRetries = 3,
	RetryDelay = 1,
	SessionTimeout = 180,
	ShutdownTimeout = 25,
}
Config.Monetization = {
	OwnershipRetries = 3,
	OwnershipRetryDelay = 1,
	PromptCooldown = 1,
}

-- أبعاد الأرض والممرات؛ القواعد الستة تفضل في مكانها الحالي.
Config.Map = {
	IslandMinX = -100,
	PlazaMinX = -10,
	PlazaHalfZ = 280,
	PlazaPadding = 10,
	ZonesStartX = 100,
	ZoneLength = 180,
	ZoneHalfZ = 140,
	RoadWidth = 28,
	NestRadius = 17,
	NestZ = 75,
	NestTop = 1,
	SpawnPosition = Vector3.new(20, 0.5, 40),
	WaterMargin = 300,
}

-- القاعدة ------------------------------------------------------------------
Config.MaxPlots = 6
-- لون كل قاعدة بالترتيب (القواعد جنب بعض على الشمال)
Config.PlotColors = {
	Color3.fromRGB(60, 140, 255), -- أزرق
	Color3.fromRGB(235, 60, 60), -- أحمر
	Color3.fromRGB(60, 210, 90), -- أخضر
	Color3.fromRGB(245, 200, 40), -- أصفر
	Color3.fromRGB(170, 70, 240), -- بنفسجي
	Color3.fromRGB(40, 210, 230), -- سماوي
}
-- شكل القاعدة: منصة مفتوحة على الأرض فيها 10 أماكن للوحوش حوالين الأطراف، و4 أعمدة في الأركان،
-- ونقطة في النص (شجرة أو كريستالة أو كورة)، وجناين صغيرة وفوانيس. كل النسخ نفس التصميم،
-- الاختلاف في الألوان والخامات والديكور بس.
export type BaseTheme = {
	FloorColor: Color3, -- البلاط
	FloorMaterial: Enum.Material,
	RimColor: Color3, -- الحافة حوالين المنصة
	RimMaterial: Enum.Material,
	StoneColor: Color3, -- الأعمدة وقواعد الـ Pads والحجر
	StoneMaterial: Enum.Material,
	PadColor: Color3, -- النيون حوالين أماكن الوحوش
	PillarTop: string, -- "Crystal" / "Flame" / "Lantern"
	PillarTopColor: Color3,
	LanternColor: Color3, -- الفوانيس الصغيرة
	Center: string, -- "Tree" / "Crystal" / "Orb" / "Flame" / "GoldenTree"
	CenterColor: Color3, -- المية أو الكريستالة أو الكورة
	Foliage: string, -- "Oak" / "Pine" / "Palm" / "Spikes" / "Dead"
	FoliageColor: Color3,
	GardenColor: Color3, -- الجناين الصغيرة
	GardenMaterial: Enum.Material,
	BannerColor: Color3,
}

Config.BaseTheme = "Normal"
Config.BaseThemes = {
	Normal = {
		FloorColor = Color3.fromRGB(196, 190, 182),
		FloorMaterial = Enum.Material.Pavement,
		RimColor = Color3.fromRGB(95, 165, 70),
		RimMaterial = Enum.Material.Grass,
		StoneColor = Color3.fromRGB(150, 150, 158),
		StoneMaterial = Enum.Material.Cobblestone,
		PadColor = Color3.fromRGB(70, 160, 255),
		PillarTop = "Crystal",
		PillarTopColor = Color3.fromRGB(80, 150, 255),
		LanternColor = Color3.fromRGB(255, 180, 80),
		Center = "Tree",
		CenterColor = Color3.fromRGB(70, 170, 255),
		Foliage = "Oak",
		FoliageColor = Color3.fromRGB(70, 150, 60),
		GardenColor = Color3.fromRGB(90, 160, 70),
		GardenMaterial = Enum.Material.Grass,
		BannerColor = Color3.fromRGB(40, 70, 160),
	},
	-- النسخ دي متسجلة وشغالة، بس مش مستخدمة لسه (غيّر Config.BaseTheme عشان تجربها)
	Ice = {
		FloorColor = Color3.fromRGB(215, 235, 250),
		FloorMaterial = Enum.Material.Pavement,
		RimColor = Color3.fromRGB(150, 200, 245),
		RimMaterial = Enum.Material.Ice,
		StoneColor = Color3.fromRGB(175, 205, 235),
		StoneMaterial = Enum.Material.Ice,
		PadColor = Color3.fromRGB(80, 210, 255),
		PillarTop = "Crystal",
		PillarTopColor = Color3.fromRGB(90, 200, 255),
		LanternColor = Color3.fromRGB(150, 220, 255),
		Center = "Crystal",
		CenterColor = Color3.fromRGB(90, 200, 255),
		Foliage = "Pine",
		FoliageColor = Color3.fromRGB(240, 248, 255),
		GardenColor = Color3.fromRGB(235, 245, 255),
		GardenMaterial = Enum.Material.Snow,
		BannerColor = Color3.fromRGB(60, 120, 200),
	},
	Desert = {
		FloorColor = Color3.fromRGB(225, 195, 140),
		FloorMaterial = Enum.Material.Sandstone,
		RimColor = Color3.fromRGB(205, 165, 105),
		RimMaterial = Enum.Material.Sand,
		StoneColor = Color3.fromRGB(200, 160, 105),
		StoneMaterial = Enum.Material.Sandstone,
		PadColor = Color3.fromRGB(255, 170, 40),
		PillarTop = "Lantern",
		PillarTopColor = Color3.fromRGB(255, 150, 40),
		LanternColor = Color3.fromRGB(255, 170, 60),
		Center = "Orb",
		CenterColor = Color3.fromRGB(255, 190, 40),
		Foliage = "Palm",
		FoliageColor = Color3.fromRGB(70, 140, 50),
		GardenColor = Color3.fromRGB(210, 175, 115),
		GardenMaterial = Enum.Material.Sand,
		BannerColor = Color3.fromRGB(190, 120, 40),
	},
	Fire = {
		FloorColor = Color3.fromRGB(90, 70, 75),
		FloorMaterial = Enum.Material.Pavement,
		RimColor = Color3.fromRGB(60, 40, 40),
		RimMaterial = Enum.Material.Basalt,
		StoneColor = Color3.fromRGB(80, 60, 62),
		StoneMaterial = Enum.Material.Basalt,
		PadColor = Color3.fromRGB(255, 70, 40),
		PillarTop = "Flame",
		PillarTopColor = Color3.fromRGB(255, 80, 30),
		LanternColor = Color3.fromRGB(255, 90, 40),
		Center = "Flame",
		CenterColor = Color3.fromRGB(255, 70, 40),
		Foliage = "Spikes",
		FoliageColor = Color3.fromRGB(230, 60, 40),
		GardenColor = Color3.fromRGB(70, 45, 40),
		GardenMaterial = Enum.Material.CrackedLava,
		BannerColor = Color3.fromRGB(160, 30, 30),
	},
	Gold = {
		FloorColor = Color3.fromRGB(225, 210, 175),
		FloorMaterial = Enum.Material.Pavement,
		RimColor = Color3.fromRGB(95, 165, 70),
		RimMaterial = Enum.Material.Grass,
		StoneColor = Color3.fromRGB(205, 175, 110),
		StoneMaterial = Enum.Material.Sandstone,
		PadColor = Color3.fromRGB(255, 205, 60),
		PillarTop = "Lantern",
		PillarTopColor = Color3.fromRGB(255, 210, 90),
		LanternColor = Color3.fromRGB(255, 200, 90),
		Center = "GoldenTree",
		CenterColor = Color3.fromRGB(240, 190, 60),
		Foliage = "Oak",
		FoliageColor = Color3.fromRGB(70, 150, 60),
		GardenColor = Color3.fromRGB(90, 160, 70),
		GardenMaterial = Enum.Material.Grass,
		BannerColor = Color3.fromRGB(200, 40, 40),
	},
	Void = {
		FloorColor = Color3.fromRGB(70, 50, 105),
		FloorMaterial = Enum.Material.Pavement,
		RimColor = Color3.fromRGB(55, 35, 85),
		RimMaterial = Enum.Material.Slate,
		StoneColor = Color3.fromRGB(80, 55, 120),
		StoneMaterial = Enum.Material.Slate,
		PadColor = Color3.fromRGB(190, 90, 255),
		PillarTop = "Flame",
		PillarTopColor = Color3.fromRGB(190, 90, 255),
		LanternColor = Color3.fromRGB(200, 110, 255),
		Center = "Orb",
		CenterColor = Color3.fromRGB(110, 50, 170),
		Foliage = "Dead",
		FoliageColor = Color3.fromRGB(60, 40, 80),
		GardenColor = Color3.fromRGB(60, 40, 90),
		GardenMaterial = Enum.Material.Slate,
		BannerColor = Color3.fromRGB(120, 50, 180),
	},
} :: { [string]: BaseTheme }

Config.BaseSlots = 3 -- عدد أماكن الوحوش في البداية
Config.MaxSlots = 10
Config.SlotUpgradeCosts = { 650, 1950, 5200, 13000, 32500, 78000, 195000 } -- تكلفة كل slot زيادة

Config.LockDuration = 45 -- مدة قفل القاعدة (ثواني)
Config.LockCooldown = 90 -- لازم تستنى قد إيه بعد ما القفل يخلص
Config.LockDurationPerUpgrade = 10
Config.LockUpgradeCosts = { 1040, 3900, 11700, 32500 }

-- الاحتياجات ----------------------------------------------------------------
Config.NeedsTickInterval = 1 -- كل قد إيه السيرفر يحدّث الوحوش
Config.HungerDecayPerSecond = 0.25 -- 100 → 0 في حوالي 6.5 دقيقة
Config.HappinessDecayPerSecond = 0.18
Config.PassiveXpPerSecond = 1 -- لو الوحش شبعان ومبسوط
Config.LowNeedsThreshold = 25 -- تحت الرقم ده الإنتاج يقل
Config.LowNeedsProductionMultiplier = 0.4

Config.Food = {
	Cost = 13, -- ثابت حسب المرحلة، عشان أكل الوحوش يفضل في متناول البداية
	Hunger = 35,
	Xp = 15,
}

Config.AutoFeeder = {
	Interval = 30,
	Threshold = 70,
	FeedCooldown = 0.15, -- نفس مهلة الأكل اليدوي، ومشتركة مع الأكل التلقائي
}

Config.Play = {
	Cooldown = 8,
	Happiness = 30,
	Xp = 10,
}

-- المستويات والتطور -------------------------------------------------------------
Config.MaxLevel = 60
Config.ProductionLevelBonusPerLevel = 0.05
Config.SellLevelBonusPerLevel = 0.1

function Config.XpForLevel(level: number): number
	return math.floor(40 * level ^ 1.35)
end

export type Stage = {
	Name: string,
	MinLevel: number,
	Scale: number,
	ProductionMultiplier: number,
}

Config.Stages = {
	{ Name = "Baby", MinLevel = 1, Scale = 1, ProductionMultiplier = 1 },
	{ Name = "Teen", MinLevel = 10, Scale = 1.4, ProductionMultiplier = 2.5 },
	{ Name = "Adult", MinLevel = 25, Scale = 1.9, ProductionMultiplier = 6 },
	{ Name = "Legendary", MinLevel = 45, Scale = 2.6, ProductionMultiplier = 15 },
} :: { Stage }

-- الندرة والوحوش ----------------------------------------------------------------
export type Rarity = {
	Name: string,
	Color: Color3,
	Order: number,
}

Config.Rarities = {
	Common = { Name = "Common", Color = Color3.fromRGB(200, 200, 200), Order = 1 },
	Uncommon = { Name = "Uncommon", Color = Color3.fromRGB(70, 210, 90), Order = 2 },
	Rare = { Name = "Rare", Color = Color3.fromRGB(70, 150, 255), Order = 3 },
	Epic = { Name = "Epic", Color = Color3.fromRGB(180, 80, 255), Order = 4 },
	Legendary = { Name = "Legendary", Color = Color3.fromRGB(255, 170, 40), Order = 5 },
	Mythic = { Name = "Mythic", Color = Color3.fromRGB(255, 70, 90), Order = 6 },
	Secret = { Name = "Secret", Color = Color3.fromRGB(255, 255, 255), Order = 7 },
} :: { [string]: Rarity }

export type Species = {
	DisplayName: string,
	Rarity: string,
	BaseProduction: number, -- Coins في الثانية في مرحلة Baby
	SellValue: number,
	Color: Color3,
	Horns: boolean,
	Placeholder: boolean?, -- شكل مؤقت (مكعب واسمه فوقه) لحد ما الـ Skin يجهز
	Model: { Region: number, Index: number }?, -- الـ Rig المتحرك من MonsterModels (المنطقة ورقم الوحش)
}

Config.Species = {
	Blobby = { DisplayName = "Blobby", Rarity = "Common", BaseProduction = 1, SellValue = 40, Color = Color3.fromRGB(120, 220, 120), Horns = false },
	Pebble = { DisplayName = "Pebble", Rarity = "Common", BaseProduction = 1.2, SellValue = 50, Color = Color3.fromRGB(150, 140, 130), Horns = false },
	Fangy = { DisplayName = "Fangy", Rarity = "Rare", BaseProduction = 4, SellValue = 400, Color = Color3.fromRGB(240, 150, 60), Horns = true },
	Frosty = { DisplayName = "Frosty", Rarity = "Rare", BaseProduction = 5, SellValue = 500, Color = Color3.fromRGB(140, 220, 255), Horns = false },
	Shadowy = { DisplayName = "Shadowy", Rarity = "Epic", BaseProduction = 18, SellValue = 4000, Color = Color3.fromRGB(70, 40, 110), Horns = true },
	Flamey = { DisplayName = "Flamey", Rarity = "Epic", BaseProduction = 22, SellValue = 5000, Color = Color3.fromRGB(255, 80, 30), Horns = true },
	Draco = { DisplayName = "Draco", Rarity = "Mythic", BaseProduction = 80, SellValue = 25000, Color = Color3.fromRGB(200, 20, 60), Horns = true },
} :: { [string]: Species }

-- وحوش المناطق (من GrowAMonster_RiggedGenerator): 5 مناطق × 10 وحوش، وشكلهم Rig متحرك.
-- المفتاح بتاع كل وحش "<Region>_<رقمه>"، مثلاً "Grassland_1" = Leaf Slime.
Config.RegionMonsters = {
	{ Region = "Grassland", Names = { "Leaf Slime", "Bunnycorn", "Wood Turtle", "Flower Golem", "Beehive Beast", "Moss Deer", "Treant", "Verdant Griffin", "Solar Stag", "Gaia Titan" } },
	{ Region = "Desert", Names = { "Sand Slime", "Cactus Pup", "Sand Fox", "Armadillo", "Scorpion", "Mummy", "Anubis Hound", "Sand Dragon", "Pharaoh Golem", "Sun Wyrm" } },
	{ Region = "Ice", Names = { "Ice Slime", "Penguin", "Ice Wolf", "Frost Turtle", "Crystal Bear", "Snow Golem", "Ice Dragon", "Blizzard Phoenix", "Glacial Titan", "Frost Leviathan" } },
	{ Region = "Volcano", Names = { "Magma Slime", "Lava Lizard", "Fire Boar", "Rock Rhino", "Flame Ape", "Lava Golem", "Inferno Wolf", "Magma Dragon", "Molten Titan", "Fire Overlord" } },
	{ Region = "Void", Names = { "Shadow Slime", "Void Cat", "Dark Deer", "Void Spider", "Chaos Hound", "Eclipse Raven", "Abyss Golem", "Void Dragon", "Celestial Serpent", "Reality Titan" } },
}
-- الندرة بالترتيب جوه كل منطقة (زي الملف بالظبط)
Config.RegionRarities = { "Common", "Common", "Uncommon", "Uncommon", "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" }
-- الإنتاج بيعلى مع الندرة، ومن Ice (Hard) بيبدأ بالملايين في الثانية.
local REGION_PRODUCTION = { 1, 1.3, 2.5, 3, 6, 7.5, 18, 22, 60, 150 }
Config.RegionProductionMultipliers = { 1, 3, 1000000, 3000000, 10000000 }
local REGION_COLORS = {
	Color3.fromRGB(90, 205, 95),
	Color3.fromRGB(238, 205, 145),
	Color3.fromRGB(150, 212, 255),
	Color3.fromRGB(255, 110, 30),
	Color3.fromRGB(172, 92, 255),
}
for regionIndex, region in Config.RegionMonsters do
	for index, name in region.Names do
		local production = REGION_PRODUCTION[index] * Config.RegionProductionMultipliers[regionIndex]
		Config.Species[region.Region .. "_" .. index] = {
			DisplayName = name,
			Rarity = Config.RegionRarities[index],
			BaseProduction = production,
			SellValue = math.floor(production * 40),
			Color = REGION_COLORS[regionIndex],
			Horns = false,
			Model = { Region = regionIndex, Index = index },
		}
	end
end

-- وحوش Secret: نادرة جداً من البيض العادي أو مضمونة من بيضة الـ Big Boss، ومش موجودة في Lucky.
-- السيرفر كله بيجيله إعلان لما حد يفقس واحد.
Config.SecretChance = 0.001
Config.SecretSpecies = { "Secret1", "Secret2" }
local strongestRegionalProduction = Config.Species.Void_10.BaseProduction
Config.Species.Secret1 = { DisplayName = "Secret ???", Rarity = "Secret", BaseProduction = strongestRegionalProduction * 1.25, SellValue = strongestRegionalProduction * 50, Color = Color3.fromRGB(20, 20, 25), Horns = true }
Config.Species.Secret2 = { DisplayName = "Secret Void", Rarity = "Secret", BaseProduction = strongestRegionalProduction * 1.5, SellValue = strongestRegionalProduction * 60, Color = Color3.fromRGB(240, 240, 255), Horns = true }

-- البيض ----------------------------------------------------------------------
export type Egg = {
	DisplayName: string,
	Cost: number,
	HatchTime: number,
	Color: Color3,
	Order: number,
	Weights: { [string]: number },
	AllowSecret: boolean?,
}

Config.Eggs = {
	Basic = {
		DisplayName = "Basic Egg",
		Cost = 130,
		HatchTime = 20,
		Color = Color3.fromRGB(235, 225, 200),
		Order = 1,
		Weights = { Grassland_1 = 30, Grassland_2 = 25, Grassland_3 = 18, Grassland_4 = 12, Desert_1 = 8, Desert_2 = 5, Grassland_5 = 2 },
	},
	Rare = {
		DisplayName = "Rare Egg",
		Cost = 1560,
		HatchTime = 45,
		Color = Color3.fromRGB(80, 160, 255),
		Order = 2,
		Weights = { Grassland_5 = 20, Grassland_6 = 18, Desert_5 = 18, Desert_6 = 14, Ice_5 = 10, Grassland_7 = 8, Desert_7 = 6, Ice_7 = 4, Grassland_9 = 2 },
	},
	Mythic = {
		DisplayName = "Mythic Egg",
		Cost = 19500,
		HatchTime = 90,
		Color = Color3.fromRGB(255, 60, 120),
		Order = 3,
		Weights = { Ice_7 = 25, Ice_8 = 20, Volcano_7 = 18, Volcano_8 = 15, Ice_9 = 10, Volcano_9 = 7, Void_9 = 3, Ice_10 = 2 },
	},
	-- Original Lucky Egg pool; the separate Secret roll keeps its 5x odds.
	Lucky = {
		DisplayName = "Lucky Egg",
		Cost = 0,
		HatchTime = 30,
		Color = Color3.fromRGB(90, 230, 120),
		Order = 4,
		Weights = { Desert_5 = 20, Ice_5 = 20, Volcano_5 = 18, Ice_7 = 15, Volcano_7 = 12, Desert_9 = 8, Ice_9 = 5, Volcano_10 = 2 },
	},
	-- بيضة الـ Big Boss: بتفقس وحش Secret مضمون
	Secret = {
		DisplayName = "Secret Egg",
		Cost = 0,
		HatchTime = 60,
		Color = Color3.fromRGB(20, 20, 30),
		Order = 5,
		Weights = { Secret1 = 50, Secret2 = 50 },
	},
} :: { [string]: Egg }

Config.LuckyEggSecretMultiplier = 5

-- البيض اللي بيتباع في المتجر، بالترتيب. فاضي دلوقتي (البيضة المجانية في الأول شغالة عادي).
-- عشان ترجّع البيض: { "Basic", "Rare", "Mythic" }
Config.ShopEggs = {} :: { string }

-- الطفرات (Mutations) ------------------------------------------------------------
export type Mutation = {
	Name: string,
	Chance: number, -- من 0 لـ 1
	Multiplier: number,
	Color: Color3?,
}

-- مترتبة من الأندر للأشهر؛ أول واحدة تنجح هي اللي بتتطبق.
Config.Mutations = {
	{ Name = "Rainbow", Chance = 0.01, Multiplier = 5, Color = nil },
	{ Name = "Toxic", Chance = 0.03, Multiplier = 3, Color = Color3.fromRGB(110, 255, 40) },
	{ Name = "Golden", Chance = 0.06, Multiplier = 2, Color = Color3.fromRGB(255, 205, 50) },
} :: { Mutation }

-- السرقة -------------------------------------------------------------------
Config.Steal = {
	Enabled = false, -- السرقة بين اللاعبين مقفولة دلوقتي (خليها true عشان ترجع)
	HoldDuration = 2.5, -- مدة الضغط على زرار السرقة
	CarryWalkSpeed = 11, -- سرعة الحرامي وهو شايل الوحش
	CatchRadius = 7, -- لو صاحب الوحش قرّب كده من الحرامي الوحش يرجع
	MaxCarryTime = 60,
	ProtectLastMonster = true, -- ماينفعش تسرق آخر وحش مع لاعب
}

-- مناطق الوحوش ---------------------------------------------------------------------
-- كل ما المنطقة تبعد عن القواعد، الأم بتبقى أقوى والصغار أندر.
-- عشان تاخد الصغار لازم تقتل الأم الأول.
export type Zone = {
	Name: string,
	Difficulty: string,
	Stars: number,
	GroundColor: Color3,
	GroundMaterial: Enum.Material,
	AccentColor: Color3,
	Decoration: string, -- "Flowers" / "Desert" / "Ice" / "Lava" / "Crystals"
	Species: { string },
	MotherHealth: number,
	MotherDamage: number, -- الضرر اللي الأم بتعمله في اللاعبين اللي جنبها كل ضربة
}

Config.Zones = {
	{
		Name = "Grassland",
		Difficulty = "Easy",
		Stars = 1,
		GroundColor = Color3.fromRGB(120, 200, 90),
		GroundMaterial = Enum.Material.Grass,
		AccentColor = Color3.fromRGB(90, 220, 110),
		Decoration = "Flowers",
		Species = { "Grassland_1", "Grassland_2", "Grassland_3", "Grassland_4", "Grassland_5", "Grassland_6", "Grassland_7", "Grassland_8", "Grassland_9", "Grassland_10" },
		MotherHealth = 300,
		MotherDamage = 5,
	},
	{
		Name = "Desert",
		Difficulty = "Medium",
		Stars = 2,
		GroundColor = Color3.fromRGB(225, 190, 130),
		GroundMaterial = Enum.Material.Sand,
		AccentColor = Color3.fromRGB(255, 190, 80),
		Decoration = "Desert",
		Species = { "Desert_1", "Desert_2", "Desert_3", "Desert_4", "Desert_5", "Desert_6", "Desert_7", "Desert_8", "Desert_9", "Desert_10" },
		MotherHealth = 2500,
		MotherDamage = 10,
	},
	{
		Name = "Ice",
		Difficulty = "Hard",
		Stars = 3,
		GroundColor = Color3.fromRGB(220, 240, 255),
		GroundMaterial = Enum.Material.Snow,
		AccentColor = Color3.fromRGB(120, 200, 255),
		Decoration = "Ice",
		Species = { "Ice_1", "Ice_2", "Ice_3", "Ice_4", "Ice_5", "Ice_6", "Ice_7", "Ice_8", "Ice_9", "Ice_10" },
		MotherHealth = 20000,
		MotherDamage = 18,
	},
	{
		Name = "Volcano",
		Difficulty = "Very Hard",
		Stars = 4,
		GroundColor = Color3.fromRGB(60, 45, 45),
		GroundMaterial = Enum.Material.Basalt,
		AccentColor = Color3.fromRGB(255, 120, 30),
		Decoration = "Lava",
		Species = { "Volcano_1", "Volcano_2", "Volcano_3", "Volcano_4", "Volcano_5", "Volcano_6", "Volcano_7", "Volcano_8", "Volcano_9", "Volcano_10" },
		MotherHealth = 150000,
		MotherDamage = 30,
	},
	{
		Name = "Void",
		Difficulty = "Extreme",
		Stars = 5,
		GroundColor = Color3.fromRGB(45, 30, 70),
		GroundMaterial = Enum.Material.Slate,
		AccentColor = Color3.fromRGB(170, 70, 255),
		Decoration = "Crystals",
		Species = { "Void_1", "Void_2", "Void_3", "Void_4", "Void_5", "Void_6", "Void_7", "Void_8", "Void_9", "Void_10" },
		MotherHealth = 1000000,
		MotherDamage = 45,
	},
} :: { Zone }

Config.ZoneResetInterval = 600 -- كل 10 دقايق الأعشاش بتتجدد بوحوش تانية
Config.NestsPerZone = 3
-- الوحش اللي بيطلع في كل عش بيتختار بالندرة دي (Common أكتر بكتير من Mythic)
Config.NestRarityWeights = { Common = 35, Uncommon = 25, Rare = 18, Epic = 12, Legendary = 7, Mythic = 3 }
Config.MotherScale = 1.6 -- الأم = نسخة الـ Adult مكبّرة
-- ضربة الأم = MotherDamage بتاع المنطقة × الرقم ده حسب ندرة الوحش
Config.MotherDamageByRarity = { Common = 1.15, Uncommon = 1.5, Rare = 1.95, Epic = 2.55, Legendary = 3.45, Mythic = 4.6 } -- +15%
-- دم الأم = MotherHealth بتاع المنطقة × الرقم ده حسب ندرة الوحش
Config.MotherHealthByRarity = { Common = 1, Uncommon = 1.3, Rare = 1.7, Epic = 2.2, Legendary = 3, Mythic = 4 }
Config.BabiesPerNest = 3

Config.PlayerBaseHealth = 100
Config.Shop = { Position = Vector3.new(Config.Map.ZonesStartX - 8, 0, -55), Yaw = -90, TeleportOffset = Vector3.new(0, 4, 12) }
Config.WalkSpeed = 25 -- سرعة المشي ثابتة (الافتراضي في Roblox 16)

Config.SpeedAccessories = {
	SwiftSneakers = { Name = "Neon Dash Sneakers", Description = "Neon sneakers that leave a streak and pulse as you run", Price = 650, Multiplier = 1.05, HealthBonus = 15, Order = 1, Color = Color3.fromRGB(70, 180, 255) },
	FlameBoots = { Name = "Ember Stompers", Description = "Boots that ignite while you run", Price = 1950, Multiplier = 1.08, HealthBonus = 30, Order = 2, Color = Color3.fromRGB(255, 100, 35) },
	IceSkates = { Name = "Frost Glide Skates", Description = "Frozen skates that shed snow sparkles as you glide", Price = 4550, Multiplier = 1.10, HealthBonus = 50, Order = 3, Color = Color3.fromRGB(130, 230, 255) },
	WindScarf = { Name = "Zephyr Scarf", Description = "A scarf that ripples in the wind", Price = 9100, Multiplier = 1.12, HealthBonus = 75, Order = 4, Color = Color3.fromRGB(220, 245, 255) },
	LightningBoots = { Name = "Storm Strike Boots", Description = "Boots that crackle with lightning when you move", Price = 18200, Multiplier = 1.15, HealthBonus = 100, Order = 5, Color = Color3.fromRGB(255, 225, 70) },
	ShadowCloak = { Name = "Umbral Cloak", Description = "A cloak wrapped in orbiting shadow shards", Price = 227500, Multiplier = 1.40, HealthBonus = 350, Order = 9, Color = Color3.fromRGB(125, 75, 210) },
	VoidHoverboard = { Name = "Void Hoverboard", Description = "A board that floats above the ground", Price = 71500, Multiplier = 1.22, HealthBonus = 190, Order = 7, Color = Color3.fromRGB(255, 95, 225) },
	GoldenWings = { Name = "Sunfeather Wings", Description = "Radiant wings that flap faster the quicker you go", Price = 130000, Multiplier = 1.30, HealthBonus = 250, Order = 8, Color = Color3.fromRGB(255, 205, 60) },
} :: { [string]: { Name: string, Description: string, Price: number, Multiplier: number, HealthBonus: number, Order: number, Color: Color3 } }

-- الوحش اللي شايله على ضهرك لحد ما توصل قاعدتك
Config.Carry = {
	WalkSpeedMultiplier = 1, -- السرعة مابتقلّش وانت شايل وحش
	SecretEggSpeedMultiplier = 1, -- ولا وانت شايل بيضة الـ Big Boss
	KillCreditTime = 10, -- لو حد ضربك في آخر 10 ثواني وموتّ، هو اللي بياخد اللي شايله
	DropLifetime = 60, -- الوحش اللي بيقع على الأرض بيختفي بعد المدة دي
}

-- ضرب اللاعبين بالمضرب (برّه القواعد بس)
Config.PvP = {
	BatDamage = 19,
	SwordDamage = 38,
	Reach = 7,
}

-- الوحوش الكبيرة اللي اللاعب يجهزها بتتبعه؛ ضربها مرتبط بالندرة مش الدخل.
Config.Followers = {
	MaxCount = 5,
	MinLevel = 25,
	DamagePerRarity = { Common = 5, Uncommon = 8, Rare = 12, Epic = 18, Legendary = 28, Mythic = 40, Secret = 60 },
	LevelBonusPerLevel = 0.02,
	MaxLevelBonus = 2,
	ModelScale = 0.6,
	Spacing = 6,
	RowDistance = 8,
	PvpDamageScale = 0.25,
	VisualPadding = 1.2,
}

Config.Combat = {
	BaseDamage = 10, -- ضرر اللاعب من غير وحوش
	DamagePerProduction = 2, -- كل 1 Coin/s من وحوشك بيزوّد ضربتك 2
	AttackCooldown = 0.35,
	BatReach = 7, -- قد إيه تبعد عن حرف الأم وتقدر تضربها بالمضرب
	MotherRegenDelay = 20, -- لو محدش ضربها المدة دي الـ HP بيرجع كامل
	MotherChaseSpeed = 16, -- سرعتها وهي بتجري ورا اللي ضربها (أبطأ من اللاعب 25 عشان يقدر يهرب)
	MotherNoticeRange = 32, -- أي لاعب يقرب من الأم لحد المسافة دي بتجري وراه حتى لو ماضربهاش
	MotherLeashRange = 70, -- لو اللاعب بعد عن عشها أكتر من كده بترجع
	TakeHoldDuration = 1,
	CritChance = 0.12, -- فرصة الضربة القاضية
	CritMultiplier = 2,
	Sounds = {
		Swing = "rbxassetid://12222208",
		Hit = "rbxassetid://12222216",
	},
}

-- M1 بتاع الوحوش الأم: كل نوع جسم ليه ضربة، وكل منطقة ليها عنصر (لون + تأثير).
-- الضربة بتتعلّم على الأرض الأول (Windup) عشان اللاعب يلحق يهرب منها.
export type MotherStyle = {
	Name: string,
	Shape: "Slam" | "Cone" | "Lob", -- Slam دايرة حواليها، Cone قدامها، Lob بترمي على مكان اللاعب
	Radius: number, -- Slam/Lob: نص قطر الدايرة (Slam بيتحسب من حرف الأم)
	Range: number, -- Cone: الطول من حرف الأم، Lob: أبعد مسافة ترمي لها
	Angle: number?, -- Cone: الزاوية كلها بالدرجات
	Windup: number,
	Cooldown: number,
	DamageMultiplier: number,
	Hits: number?, -- ضربات متتالية (يمين شمال يمين شمال)، DamageMultiplier لكل ضربة
	HitInterval: number?, -- الفاصل بين الضربات بالثواني
}
Config.MotherAttacks = {
	AggroRange = 34, -- لو لاعب قرّب أكتر من كده الأم بتبدأ تضرب
	FirstAttackDelay = 0.8, -- مهلة صغيرة أول ما حد يقرب
	FxDistance = 260, -- الكلاينت مش بيرسم ضربات أبعد من كده
	Sounds = {
		Windup = "rbxasset://sounds/swordlunge.wav",
		Impact = "rbxassetid://12222216",
	},
	-- المناطق الصعبة: البايبد بيضرب كومبو إيدين بدل الكنسة (ComboStyles بتحل محل Styles)
	ComboDifficulties = { Hard = true, ["Very Hard"] = true, Extreme = true } :: { [string]: boolean },
	ComboStyles = {
		Biped = { Name = "Fist Barrage", Shape = "Cone", Radius = 0, Range = 11, Angle = 110, Windup = 0.5, Cooldown = 2.2, DamageMultiplier = 0.45, Hits = 4, HitInterval = 0.4 },
	} :: { [string]: MotherStyle },
	Styles = {
		Slime = { Name = "Bounce Slam", Shape = "Slam", Radius = 11, Range = 0, Windup = 0.75, Cooldown = 1.9, DamageMultiplier = 1 },
		Quad = { Name = "Pounce Bite", Shape = "Cone", Radius = 0, Range = 15, Angle = 75, Windup = 0.55, Cooldown = 1.6, DamageMultiplier = 1 },
		Biped = { Name = "Arm Sweep", Shape = "Cone", Radius = 0, Range = 12, Angle = 160, Windup = 0.6, Cooldown = 1.6, DamageMultiplier = 1.1 }, -- M1: الإيد بتكنس من اليمين للشمال
		Bird = { Name = "Dive Bomb", Shape = "Lob", Radius = 8, Range = 40, Windup = 0.9, Cooldown = 2, DamageMultiplier = 1 },
		Dragon = { Name = "Elemental Breath", Shape = "Cone", Radius = 0, Range = 22, Angle = 55, Windup = 0.8, Cooldown = 2.2, DamageMultiplier = 1.2 },
		Serpent = { Name = "Venom Spit", Shape = "Lob", Radius = 7, Range = 36, Windup = 0.8, Cooldown = 1.8, DamageMultiplier = 1 },
		Spider = { Name = "Web Shot", Shape = "Lob", Radius = 8, Range = 34, Windup = 0.8, Cooldown = 2, DamageMultiplier = 0.9 },
		Scorpion = { Name = "Tail Sting", Shape = "Cone", Radius = 0, Range = 14, Angle = 50, Windup = 0.5, Cooldown = 1.5, DamageMultiplier = 1.1 },
		Turtle = { Name = "Shell Quake", Shape = "Slam", Radius = 13, Range = 0, Windup = 0.9, Cooldown = 2.2, DamageMultiplier = 1.15 },
		Boss = { Name = "Void Quake", Shape = "Slam", Radius = 18, Range = 0, Windup = 1.1, Cooldown = 2.6, DamageMultiplier = 1 },
	} :: { [string]: MotherStyle },
	-- العنصر حسب المنطقة. Slow = بطء مؤقت، Burn = ضرر زيادة على مرات، Drain = الأم بتاخد دم.
	Elements = {
		Grassland = { Name = "Nature", Color = Color3.fromRGB(110, 230, 90), Secondary = Color3.fromRGB(255, 240, 120) },
		Desert = { Name = "Sand", Color = Color3.fromRGB(240, 200, 110), Secondary = Color3.fromRGB(190, 140, 70), Slow = 0.8, SlowTime = 1.2 },
		Ice = { Name = "Frost", Color = Color3.fromRGB(140, 220, 255), Secondary = Color3.fromRGB(255, 255, 255), Slow = 0.6, SlowTime = 2 },
		Volcano = { Name = "Fire", Color = Color3.fromRGB(255, 110, 30), Secondary = Color3.fromRGB(255, 220, 80), BurnTicks = 3, BurnFraction = 0.15 },
		Void = { Name = "Void", Color = Color3.fromRGB(180, 80, 255), Secondary = Color3.fromRGB(60, 20, 90), Drain = 0.5 },
	},
}

-- الموسيقى في الخلفية (من مكتبة Roblox المرخّصة APM). زرار 🔊 على الشمال بيقفلها.
Config.Music = {
	SoundId = "rbxassetid://120231070741138", -- Curious Creatures
	Volume = 0.3,
	CombatVolume = 0.18, -- بتوطى شوية وقت القتال عشان أصوات الضرب تبان
}

Config.Security = {
	GearEquipCooldown = 0.5,
	GearSaveInterval = 5,
	TradeCooldown = 5,
	ArenaCooldown = 5,
	FreeEggCooldown = 300,
	MaxSpeedTolerance = 1.6,
}

-- Gamepasses و Developer Products -----------------------------------------------------
-- حط الـ Id بتاع كل واحد بعد ما تعمله من Creator Dashboard (بعد الـ Publish).
-- لو الـ Id = 0: في Studio الزرار بيدّيهولك مجاناً عشان التجربة، وفي اللعبة الحقيقية بيقول "Coming soon".
-- Auto Minigame requires a configured pass in Studio too.
export type Gamepass = { Id: number, Name: string, Description: string, Price: number, Order: number, Hidden: boolean? }
Config.Gamepasses = {
	CoinBoost = { Id = 0, Name = "Coin Booster", Description = "Legacy income boost", Price = 99, Order = 0, Hidden = true },
	VIP = { Id = 2036579024, Name = "VIP", Description = "x2 coins from all your monsters and the VIP Sword", Price = 299, Order = 1 },
	VIPSword = { Id = 0, Name = "VIP Sword", Description = "Included with VIP", Price = 199, Order = 2, Hidden = true },
	AutoCollect = { Id = 2038162860, Name = "Auto-Collect", Description = "Coins go to your wallet by themselves", Price = 149, Order = 3 },
	ExtraSlots = { Id = 2036429020, Name = "+2 Slots", Description = "Two more monster slots in your base", Price = 99, Order = 4 },
	AutoFeeder = { Id = 2037406772, Name = "Auto-Feeder", Description = "Feeds hungry monsters using your coins and grants normal feeding XP", Price = 99, Order = 5 },
	AutoMinigame = { Id = 2044616622, Name = "Auto Minigame", Description = "Automatically plays with your placed monsters and earns normal game XP", Price = 99, Order = 6 },
	IronBat = { Id = 0, Name = "Iron Bat", Description = "A heavy bat for stronger hits", Price = 79, Order = 9 },
	IronSword = { Id = 0, Name = "Iron Sword", Description = "A reliable sword for monster zones", Price = 99, Order = 10 },
	ForestSword = { Id = 0, Name = "Forest Sword", Description = "A nature-forged sword", Price = 149, Order = 11 },
	DesertSword = { Id = 0, Name = "Desert Sword", Description = "A sword tempered by desert heat", Price = 199, Order = 12 },
	IceSword = { Id = 0, Name = "Ice Sword", Description = "A frozen sword with extra reach", Price = 249, Order = 13 },
	LavaSword = { Id = 0, Name = "Lava Sword", Description = "A blazing sword with maximum power", Price = 299, Order = 14 },
} :: { [string]: Gamepass }

export type Product = { Id: number, Name: string, Description: string, Price: number, Order: number, Coins: number? }
Config.Products = {
	Coins1000 = { Id = 3717867513, Name = "1,000 Coins", Description = "1,000 coins added to your wallet · repeatable", Price = 50, Order = 4, Coins = 1000 },
	Coins5000 = { Id = 3717867716, Name = "5,000 Coins", Description = "5,000 coins added to your wallet · repeatable", Price = 100, Order = 5, Coins = 5000 },
	Coins15000 = { Id = 3717867936, Name = "15,000 Coins", Description = "15,000 coins added to your wallet · repeatable", Price = 250, Order = 6, Coins = 15000 },
	InstantHatch = { Id = 0, Name = "Instant Hatch", Description = "All your eggs hatch right now", Price = 25, Order = 1 },
	LuckyEgg = { Id = 0, Name = "Lucky Egg", Description = "A rare egg with better odds", Price = 49, Order = 2 },
	SpeedBoost = { Id = 0, Name = "Speed Boost", Description = "Run faster for 10 minutes", Price = 29, Order = 3 },
	SkipToAdultOne = { Id = 3721310526, Name = "Grow Monster - One", Description = "Grow one selected current monster to Adult once", Price = 29, Order = 7 },
	SkipToAdultAll = { Id = 3721310988, Name = "Grow Monsters - All", Description = "Grow your current eligible inventory to Adult once; future monsters are excluded", Price = 100, Order = 8 },
} :: { [string]: Product }

Config.VIPCoinMultiplier = 2
Config.CoinBoostMultiplier = 1.5
Config.ExtraSlotsAmount = 2
Config.VIPSword = { DamageMultiplier = 4.3, ExtraReach = 3 }
Config.WeaponStats = {
	IronBat = { Template = "IronBat", DamageMultiplier = 1.7, ExtraReach = 0.5 },
	VIPSword = { Template = "VoidBat", DamageMultiplier = 4.3, ExtraReach = 3 },
	IronSword = { Template = "IronSword", DamageMultiplier = 2.2, ExtraReach = 1 },
	ForestSword = { Template = "ForestSword", DamageMultiplier = 2.6, ExtraReach = 1.5 },
	DesertSword = { Template = "DesertSword", DamageMultiplier = 3.05, ExtraReach = 2 },
	IceSword = { Template = "IceSword", DamageMultiplier = 3.6, ExtraReach = 2.5 },
	LavaSword = { Template = "LavaSword", DamageMultiplier = 5.05, ExtraReach = 4 },
} :: { [string]: { Template: string, DamageMultiplier: number, ExtraReach: number } }
-- معدات القتال تُشترى بعملات اللعبة من المتجر، مش بـ Robux.
-- Early upgrades are affordable; later tiers follow the five-zone economy.
Config.WeaponCoinPrices = {
	IronBat = 390,
	IronSword = 1040,
	ForestSword = 3250,
	DesertSword = 9750,
	IceSword = 26000,
	VIPSword = 52000,
	LavaSword = 104000,
} :: { [string]: number }
Config.SpeedBoost = { Duration = 600, Multiplier = 1.4 }

-- أحداث الماب ---------------------------------------------------------------------------
-- Monster Rain: كل ساعة وحش نادر بيقع في نص الماب، وأول واحد يمسكه ويوصله قاعدته ياخده.
Config.MonsterRain = {
	Interval = 3600,
	Lifetime = 300, -- لو محدش مسكه بيختفي
	Species = { "Grassland_7", "Grassland_8", "Desert_7", "Desert_8", "Ice_7", "Ice_8", "Grassland_9", "Desert_9", "Volcano_7" },
	MutationChanceMultiplier = 3,
}

-- Big Boss: أوقات بينزل في الماب ومعاه بيضة Secret. لازم الكل يتجمع يقتله.
Config.Boss = {
	MinInterval = 2400, -- بين 40 و 80 دقيقة
	MaxInterval = 4800,
	HealthPerPlayer = 60000,
	MinHealth = 120000,
	Damage = 30, -- كل ضربة، لكل اللي جنبه (شكلها في Config.MotherAttacks.Styles.Boss)
	AttackRange = 30, -- لو حد قرّب أكتر من كده بيبدأ يضرب
	Size = 18,
	Lifetime = 600, -- لو محدش قتله بيمشي
	Position = Vector3.new(Config.Map.ZonesStartX + Config.Map.ZoneLength / 2, 0, 0), -- في الطريق جوه Zone 1
}

-- اللوحات اللي في الساحة (Leaderboards)
Config.Leaderboards = {
	UpdateInterval = 60,
	TopCount = 10,
}

-- الهدية اليومية وعجلة الحظ ---------------------------------------------------------------
Config.Daily = {
	Cooldown = 20 * 3600, -- تقدر تاخدها كل 20 ساعة
	StreakReset = 48 * 3600, -- لو غبت أكتر من كده الـ Streak يبدأ من الأول
	CoinsPerDay = 150, -- بتتضرب في يوم الـ Streak (لحد 7)
	MaxStreak = 7,
	Day7Egg = "Rare", -- اليوم السابع بيدّيك بيضة كمان
}

export type SpinPrize = { Name: string, Weight: number, Coins: number?, Egg: string?, Color: Color3 }
Config.Spin = {
	Cooldown = 24 * 3600, -- لفة مجانية كل يوم
	Prizes = {
		{ Name = "100 Coins", Weight = 30, Coins = 100, Color = Color3.fromRGB(255, 210, 70) },
		{ Name = "Rare Egg", Weight = 16, Egg = "Rare", Color = Color3.fromRGB(80, 160, 255) },
		{ Name = "400 Coins", Weight = 24, Coins = 400, Color = Color3.fromRGB(255, 160, 50) },
		{ Name = "Lucky Egg", Weight = 6, Egg = "Lucky", Color = Color3.fromRGB(90, 230, 120) },
		{ Name = "1500 Coins", Weight = 14, Coins = 1500, Color = Color3.fromRGB(255, 110, 60) },
		{ Name = "Mythic Egg", Weight = 10, Egg = "Mythic", Color = Color3.fromRGB(255, 60, 120) },
	} :: { SpinPrize },
}

-- ألعاب صغيرة مع الوحش (بدل زرار Play) ------------------------------------------------------
Config.MiniGames = {
	Cooldown = 20, -- لكل وحش
	Happiness = 40,
	Catch = { Duration = 12, XpPerCatch = 4, MaxCatches = 30, MinCatchInterval = 0.5 },
	Run = { Duration = 15, Target = 160, MaxXp = 60 }, -- XP على حسب المسافة اللي جريتها
}

-- إكسسوارات الوحوش: كل وحش ليه قبعة ونضارة بتوعه هو بس، ولازم تشتريهم -------------------
-- المفتاح "<نوع الوحش>_Hat" أو "<نوع الوحش>_Glasses"، وShape بيحدد شكلها في PlotService
export type Accessory = {
	Name: string,
	Slot: string,
	Shape: string,
	Species: string,
	Cost: number,
	Bonus: number,
	Color: Color3,
	Order: number,
}
-- الشكل حسب ندرة الوحش: كل ما يندر الإكسسوار يبقى أشيك
local ACCESSORY_SHAPES = {
	Common = { Hat = "PartyHat", Glasses = "StarGlasses" },
	Uncommon = { Hat = "TopHat", Glasses = "StarGlasses" },
	Rare = { Hat = "TopHat", Glasses = "CoolShades" },
	Epic = { Hat = "WizardHat", Glasses = "CoolShades" },
	Legendary = { Hat = "Crown", Glasses = "Monocle" },
	Mythic = { Hat = "Crown", Glasses = "Monocle" },
	Secret = { Hat = "Crown", Glasses = "Monocle" },
}
local SHAPE_NAMES = {
	PartyHat = "Party Hat",
	TopHat = "Top Hat",
	WizardHat = "Wizard Hat",
	Crown = "Crown",
	StarGlasses = "Star Glasses",
	CoolShades = "Cool Shades",
	Monocle = "Monocle",
}
Config.AccessoryHatCostSeconds = 390 -- تمن القبعة = 6.5 دقيقة إنتاج Baby، من غير تصاعد أسرع من الدخل
Config.AccessoryGlassesCostSeconds = 260
Config.AccessoryMinCost = 195
Config.AccessoryHatBonus = 0.1 -- +10% فلوس
Config.AccessoryGlassesBonus = 0.05
Config.Accessories = {} :: { [string]: Accessory }
do
	local keys = {}
	for key in Config.Species do
		table.insert(keys, key)
	end
	table.sort(keys)
	for order, key in keys do
		local species = Config.Species[key]
		local shapes = ACCESSORY_SHAPES[species.Rarity] or ACCESSORY_SHAPES.Common
		local function cost(seconds: number): number
			return math.max(Config.AccessoryMinCost, math.floor(species.BaseProduction * seconds / 10 + 0.5) * 10)
		end
		local hatColor = species.Color:Lerp(Color3.fromRGB(255, 70, 160), 0.35)
		if shapes.Hat == "Crown" then
			hatColor = Color3.fromRGB(255, 205, 50)
		end
		Config.Accessories[key .. "_Hat"] = {
			Name = species.DisplayName .. " " .. SHAPE_NAMES[shapes.Hat],
			Slot = "Hat",
			Shape = shapes.Hat,
			Species = key,
			Cost = cost(Config.AccessoryHatCostSeconds),
			Bonus = Config.AccessoryHatBonus,
			Color = hatColor,
			Order = order * 2 - 1,
		}
		Config.Accessories[key .. "_Glasses"] = {
			Name = species.DisplayName .. " " .. SHAPE_NAMES[shapes.Glasses],
			Slot = "Glasses",
			Shape = shapes.Glasses,
			Species = key,
			Cost = cost(Config.AccessoryGlassesCostSeconds),
			Bonus = Config.AccessoryGlassesBonus,
			Color = if shapes.Glasses == "CoolShades" then Color3.fromRGB(20, 20, 25) else species.Color:Lerp(Color3.fromRGB(255, 220, 60), 0.6),
			Order = order * 2,
		}
	end
end

-- Monster Arena: معارك 1 ضد 1. الكسبان بياخد فلوس والوحش اللي خسر --------------------------
Config.Arena = {
	-- Two arenas on the grass at both ends of the base row (left and right of the bases).
	Positions = { Vector3.new(-40, 0, 238), Vector3.new(-40, 0, -238) },
	Radius = 22,
	RequestTimeout = 60,
	RequestCooldown = 3,
	TurnTime = 0.8,
	MaxTurns = 40,
	PrizeCoins = 500, -- + 10% من قيمة الوحش اللي خسر
	PrizeValueShare = 0.1,
}

-- Trading -------------------------------------------------------------------------------------
Config.Trade = {
	MaxOffer = 4,
	RequestTimeout = 60,
	RequestCooldown = 3,
}

Config.MapBorder = { Spacing = 28, LowHeight = 13, MiddleHeight = 28, HighHeight = 44, LanternEvery = 3, LightRange = 16, LightBrightness = 1 }
-- الصوت ومؤثرات الواجهة -----------------------------------------------------------------------
-- حط الـ Asset ID بتاع كل صوت من Toolbox ← Audio (الأحسن تختار من أصوات Roblox نفسها، مرخّصة ومناسبة لكل الأعمار).
-- لو الـ ID بـ 0 الصوت ده مش هيشتغل، والمؤثرات الشكلية شغالة عادي من غير أصوات.
Config.Audio = {
	MusicIds = { 0 } :: { number }, -- الأغاني بتتلف ورا بعض (حط أكتر من واحدة لو عايز)
	MusicVolume = 0.25,
	SfxVolume = 0.5,
	Sfx = {
		Click = 0, -- أي زرار
		Open = 0, -- شباك بيتفتح
		Coins = 0, -- الفلوس زادت
		Success = 0, -- فقس، شرا، جايزة
		Error = 0, -- مش معاك فلوس وكده
	} :: { [string]: number },
}

-- مؤثرات الواجهة (من غير صوت)
Config.UIEffects = {
	HoverScale = 1.06, -- الزرار بيكبر لما الماوس يعدّي عليه
	PressScale = 0.92, -- وبيصغر لما تدوس
	PanelPopFrom = 0.85, -- الشباك بيتفتح من الحجم ده لحد 1
	CoinsBump = 1.15,
	ReadyPulse = 1.08, -- الزرار اللي فيه Ready! بينبض
}

-- Halloween 2026 event --------------------------------------------------------------------------
-- Runs until it is switched off. To END the event: set Enabled = false (or EndsAt to a unix time)
-- and publish. Leftover Candy is then converted to coins on the next join / at the end of the event.
-- In Studio you can also run  game.ServerStorage.RaiseAMonsterDebug.HalloweenToggle:Fire()  to flip it live.
export type HalloweenItem = {
	Name: string,
	Kind: string, -- "Boost" | "Hat" | "Trail" | "Aura" | "Title" | "Egg" | "Monster"
	Cost: number, -- in Candy
	Order: number,
	Description: string,
	Color: Color3,
	Unique: boolean?, -- one purchase per player (Pumpkin King)
	Duration: number?, -- Boost: seconds added per purchase
	Multiplier: number?, -- Boost: cash multiplier while active
	MaxBoostSeconds: number?, -- Boost: cap on stored time so stacking can't run away
	TitleText: string?,
	EggWeights: { [string]: number }?, -- Egg: weights over Config.Eggs keys
	Species: string?, -- Monster
}
Config.Halloween = {
	Enabled = true,
	Name = "Halloween 2026",
	EndsAt = 0, -- unix seconds; 0 = no scheduled end (runs until Enabled = false)
	CandyToCoinRate = 20, -- each leftover Candy becomes this many coins when the event is over
	CandyCap = 1000000000, -- sanity cap on stored Candy
	Invasion = {
		Interval = 3600, -- Mother Invasion every hour on the hour (server clock, same time in every server)
		Offset = 0,
		AnnounceBefore = 60, -- warn everyone this many seconds ahead
		Lifetime = 900, -- invaders that survive this long run off
		-- How many Mothers invade: minimum 3, 3-6 are common and larger waves are increasingly rare.
		MinCount = 3,
		CountWeights = { [3] = 28, [4] = 26, [5] = 20, [6] = 14, [7] = 6, [8] = 3.5, [9] = 1.7, [10] = 0.8 } :: { [number]: number },
		MinLevel = 1,
		MaxLevel = Config.MaxLevel,
		ParticipationFraction = 0.05, -- must deal >= 5% of the Mother's max HP to be rewarded
		CandyPerLevel = 5, -- reward = Mother level * 5 Candy
		HealthAtMinLevel = 2500, -- Mother HP grows exponentially from level 1 to the max level
		HealthAtMaxLevel = 3000000,
		DamageAtMinLevel = 5,
		DamageAtMaxLevel = 45,
		-- Where invaders spawn / may walk (the open plaza in front of the bases, never inside a base).
		Area = { MinX = 10, MaxX = 88, HalfZ = 150 },
		SpawnSpacing = 22, -- minimum distance between two invaders at spawn
		ChaseSpeed = 14, -- slower than a player (25) so they can run away
		NoticeRange = 34,
		LeashRange = 90,
	},
	Pumpkins = {
		Interval = 1800, -- Pumpkin Hunt every 30 minutes
		Offset = 900, -- :15 and :45 so it never lands on the Mother Invasion
		Count = 5,
		Lifetime = 120, -- pumpkins vanish after 2 minutes
		CandyMin = 3,
		CandyMax = 10,
		GoldenChance = 0.08, -- per pumpkin
		GoldenCandy = 50,
		PickupDistance = 14, -- server re-checks the player's real distance
		PickupDebounce = 0.4,
		HintInterval = 6,
		-- The hint only says roughly which way (8 sectors) and how far (bands), never the spot.
		HintBands = { 40, 100 } :: { number },
		MinSpacing = 28,
		Area = { MinX = 8, MaxX = 90, HalfZ = 235 },
		-- keep clear of the egg shop, the merchant and the zone gate road
		KeepClear = { { X = 92, Z = -55, Radius = 24 }, { X = 76, Z = -34, Radius = 14 }, { X = 100, Z = 0, Radius = 24 } },
	},
	Merchant = {
		Name = "Pumpkin Merchant",
		Position = Vector3.new(76, 0, -34),
		FaceTowards = Vector3.new(40, 0, -34),
		PromptDistance = 12,
		ShopDistance = 18, -- the server only opens/accepts shop actions this close to the merchant
		PurchaseCooldown = 0.35,
	},
	Atmosphere = {
		ClockTime = 0,
		FadeSeconds = 3, -- smooth fade in/out when an event starts/ends
		Brightness = 1.8, -- event-only night; brighter than the first version (was 0.6)
		Ambient = Color3.fromRGB(125, 95, 165),
		OutdoorAmbient = Color3.fromRGB(115, 90, 160),
		FogColor = Color3.fromRGB(70, 48, 100),
		FogStart = 260,
		FogEnd = 2000,
		AtmosphereDensity = 0.28,
		AtmosphereOffset = 0.15,
		AtmosphereColor = Color3.fromRGB(135, 100, 175),
		AtmosphereDecay = Color3.fromRGB(70, 35, 95),
		Haze = 1.4,
		TintColor = Color3.fromRGB(255, 205, 235),
		Saturation = 0.12,
		Contrast = 0.08,
		BloomIntensity = 0.45,
		BloomThreshold = 1.6,
		StarCount = 3000,
		PumpkinPropCount = 46, -- jack-o-lanterns / pumpkin piles around the plaza
		LanternRange = 14,
		Seed = 20261031,
	},
	Items = {
		CandyBoost = { Name = "Candy Boost", Kind = "Boost", Cost = 150, Order = 1, Description = "2x cash from your monsters for 10 minutes. Buying again adds time.", Color = Color3.fromRGB(255, 190, 60), Duration = 600, Multiplier = 2, MaxBoostSeconds = 3600 },
		PumpkinHat = { Name = "Pumpkin Hat", Kind = "Hat", Cost = 300, Order = 2, Description = "A glowing jack-o-lantern on your head.", Color = Color3.fromRGB(255, 130, 30) },
		GhostTrail = { Name = "Ghost Trail", Kind = "Trail", Cost = 500, Order = 3, Description = "A pale ghostly trail follows you.", Color = Color3.fromRGB(190, 230, 255) },
		CandyAura = { Name = "Candy Aura", Kind = "Aura", Cost = 800, Order = 4, Description = "Sweet sparkles swirl around you.", Color = Color3.fromRGB(255, 120, 200) },
		HalloweenTitle = { Name = "Halloween 2026 Title", Kind = "Title", Cost = 1000, Order = 5, Description = "Show 'Halloween 2026' above your head.", Color = Color3.fromRGB(190, 110, 255), TitleText = "Halloween 2026" },
		HauntedEgg = { Name = "Haunted Egg", Kind = "Egg", Cost = 400, Order = 6, Description = "A real egg: Rare Egg (common) or Mythic Egg (rarer). Hatches into a real monster.", Color = Color3.fromRGB(150, 255, 160), EggWeights = { Rare = 70, Mythic = 30 } :: { [string]: number } },
		GhostSlime = { Name = "Ghost Slime", Kind = "Monster", Cost = 1500, Order = 7, Description = "Exclusive spooky slime monster.", Color = Color3.fromRGB(200, 240, 255), Species = "HalloweenGhostSlime" },
		SkeletonImp = { Name = "Skeleton Imp", Kind = "Monster", Cost = 3000, Order = 8, Description = "Exclusive rattling imp monster.", Color = Color3.fromRGB(235, 232, 215), Species = "HalloweenSkeletonImp" },
		PumpkinKing = { Name = "Pumpkin King", Kind = "Monster", Cost = 12000, Order = 9, Description = "The ultimate Halloween monster. One per player.", Color = Color3.fromRGB(255, 120, 20), Species = "HalloweenPumpkinKing", Unique = true },
	} :: { [string]: HalloweenItem },
}

-- Event-exclusive monsters. They are not in any egg pool and use the generated body (no rig yet).
-- Defined after the accessory table above on purpose: they have no per-species accessories.
Config.Species.HalloweenGhostSlime = { DisplayName = "Ghost Slime", Rarity = "Epic", BaseProduction = 45, SellValue = 1800, Color = Color3.fromRGB(205, 235, 255), Horns = false }
Config.Species.HalloweenSkeletonImp = { DisplayName = "Skeleton Imp", Rarity = "Legendary", BaseProduction = 140, SellValue = 5600, Color = Color3.fromRGB(238, 234, 214), Horns = true }
Config.Species.HalloweenPumpkinKing = { DisplayName = "Pumpkin King", Rarity = "Mythic", BaseProduction = 520, SellValue = 20800, Color = Color3.fromRGB(255, 125, 20), Horns = true }

return Config
