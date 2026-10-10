--!strict
-- كل أرقام اللعبة في مكان واحد عشان تعدّل التوازن بسهولة.

local Config = {}

Config.StartingCoins = 150
Config.DataStoreName = "RaiseAMonster_v1"
Config.AutosaveInterval = 60 -- ثواني

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
Config.SlotUpgradeCosts = { 500, 1500, 4000, 10000, 25000, 60000, 150000 } -- تكلفة كل slot زيادة

Config.LockDuration = 45 -- مدة قفل القاعدة (ثواني)
Config.LockCooldown = 90 -- لازم تستنى قد إيه بعد ما القفل يخلص
Config.LockDurationPerUpgrade = 10
Config.LockUpgradeCosts = { 800, 3000, 9000, 25000 }

-- الاحتياجات ----------------------------------------------------------------
Config.NeedsTickInterval = 1 -- كل قد إيه السيرفر يحدّث الوحوش
Config.HungerDecayPerSecond = 0.25 -- 100 → 0 في حوالي 6.5 دقيقة
Config.HappinessDecayPerSecond = 0.18
Config.PassiveXpPerSecond = 1 -- لو الوحش شبعان ومبسوط
Config.LowNeedsThreshold = 25 -- تحت الرقم ده الإنتاج يقل
Config.LowNeedsProductionMultiplier = 0.4

Config.Food = {
	Cost = 10, -- بيتضرب في مرحلة الوحش (Stage)
	Hunger = 35,
	Xp = 15,
}

Config.Play = {
	Cooldown = 8,
	Happiness = 30,
	Xp = 10,
}

-- المستويات والتطور -------------------------------------------------------------
Config.MaxLevel = 60

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
-- الإنتاج الأساسي حسب ترتيب الوحش، وكل منطقة أبعد ×3
local REGION_PRODUCTION = { 1, 1.3, 2.5, 3, 6, 7.5, 18, 22, 60, 150 }
local REGION_COLORS = {
	Color3.fromRGB(90, 205, 95),
	Color3.fromRGB(238, 205, 145),
	Color3.fromRGB(150, 212, 255),
	Color3.fromRGB(255, 110, 30),
	Color3.fromRGB(172, 92, 255),
}
for regionIndex, region in Config.RegionMonsters do
	for index, name in region.Names do
		local production = REGION_PRODUCTION[index] * 3 ^ (regionIndex - 1)
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

-- وحوش Secret: نادرة جداً (0.1% من أي بيضة، أو من بيضة الـ Big Boss)، وليها شكل خاص منوّر.
-- السيرفر كله بيجيله إعلان لما حد يفقس واحد.
Config.SecretChance = 0.001
Config.SecretSpecies = { "Secret1", "Secret2" }
Config.Species.Secret1 = { DisplayName = "Secret ???", Rarity = "Secret", BaseProduction = 500, SellValue = 250000, Color = Color3.fromRGB(20, 20, 25), Horns = true }
Config.Species.Secret2 = { DisplayName = "Secret Void", Rarity = "Secret", BaseProduction = 650, SellValue = 320000, Color = Color3.fromRGB(240, 240, 255), Horns = true }

-- البيض ----------------------------------------------------------------------
export type Egg = {
	DisplayName: string,
	Cost: number,
	HatchTime: number,
	Color: Color3,
	Order: number,
	Weights: { [string]: number },
}

Config.Eggs = {
	Basic = {
		DisplayName = "Basic Egg",
		Cost = 100,
		HatchTime = 20,
		Color = Color3.fromRGB(235, 225, 200),
		Order = 1,
		Weights = { Grassland_1 = 30, Grassland_2 = 25, Grassland_3 = 18, Grassland_4 = 12, Desert_1 = 8, Desert_2 = 5, Grassland_5 = 2 },
	},
	Rare = {
		DisplayName = "Rare Egg",
		Cost = 1200,
		HatchTime = 45,
		Color = Color3.fromRGB(80, 160, 255),
		Order = 2,
		Weights = { Grassland_5 = 20, Grassland_6 = 18, Desert_5 = 18, Desert_6 = 14, Ice_5 = 10, Grassland_7 = 8, Desert_7 = 6, Ice_7 = 4, Grassland_9 = 2 },
	},
	Mythic = {
		DisplayName = "Mythic Egg",
		Cost = 15000,
		HatchTime = 90,
		Color = Color3.fromRGB(255, 60, 120),
		Order = 3,
		Weights = { Ice_7 = 25, Ice_8 = 20, Volcano_7 = 18, Volcano_8 = 15, Ice_9 = 10, Volcano_9 = 7, Void_9 = 3, Ice_10 = 2 },
	},
	-- بيضة الحظ (Developer Product وعجلة الحظ): أندر من العادي، وفرصة الـ Secret فيها ×5
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
Config.MotherDamageByRarity = { Common = 1, Uncommon = 1.3, Rare = 1.7, Epic = 2.2, Legendary = 3, Mythic = 4 }
-- دم الأم = MotherHealth بتاع المنطقة × الرقم ده حسب ندرة الوحش
Config.MotherHealthByRarity = { Common = 1, Uncommon = 1.3, Rare = 1.7, Epic = 2.2, Legendary = 3, Mythic = 4 }
Config.BabiesPerNest = 3

Config.WalkSpeed = 25 -- سرعة المشي ثابتة (الافتراضي في Roblox 16)

Config.SpeedAccessories = {
	SwiftSneakers = { Name = "Swift Sneakers", Description = "Blue neon sneakers", Price = 1500, Multiplier = 1.05, Order = 1, Color = Color3.fromRGB(70, 180, 255) },
	FlameBoots = { Name = "Flame Boots", Description = "Boots with a fiery trail", Price = 3000, Multiplier = 1.08, Order = 2, Color = Color3.fromRGB(255, 100, 35) },
	IceSkates = { Name = "Ice Skates", Description = "Frozen skates that glide", Price = 6000, Multiplier = 1.10, Order = 3, Color = Color3.fromRGB(130, 230, 255) },
	WindScarf = { Name = "Wind Scarf", Description = "A scarf carried by the wind", Price = 10000, Multiplier = 1.12, Order = 4, Color = Color3.fromRGB(220, 245, 255) },
	LightningBoots = { Name = "Lightning Boots", Description = "Boots charged with lightning", Price = 15000, Multiplier = 1.15, Order = 5, Color = Color3.fromRGB(255, 225, 70) },
	ShadowCloak = { Name = "Shadow Cloak", Description = "A cloak that moves like smoke", Price = 22000, Multiplier = 1.18, Order = 6, Color = Color3.fromRGB(125, 75, 210) },
	VoidHoverboard = { Name = "Void Hoverboard", Description = "A board that floats above the ground", Price = 32000, Multiplier = 1.22, Order = 7, Color = Color3.fromRGB(195, 80, 255) },
	GoldenWings = { Name = "Golden Wings", Description = "Radiant wings for maximum speed", Price = 50000, Multiplier = 1.30, Order = 8, Color = Color3.fromRGB(255, 205, 60) },
} :: { [string]: { Name: string, Description: string, Price: number, Multiplier: number, Order: number, Color: Color3 } }

-- الوحش اللي شايله على ضهرك لحد ما توصل قاعدتك
Config.Carry = {
	WalkSpeedMultiplier = 1, -- السرعة مابتقلّش وانت شايل وحش
	SecretEggSpeedMultiplier = 1, -- ولا وانت شايل بيضة الـ Big Boss
	KillCreditTime = 10, -- لو حد ضربك في آخر 10 ثواني وموتّ، هو اللي بياخد اللي شايله
	DropLifetime = 60, -- الوحش اللي بيقع على الأرض بيختفي بعد المدة دي
}

-- ضرب اللاعبين بالمضرب (برّه القواعد بس)
Config.PvP = {
	BatDamage = 15,
	SwordDamage = 30,
	Reach = 7,
}

Config.Combat = {
	BaseDamage = 10, -- ضرر اللاعب من غير وحوش
	DamagePerProduction = 2, -- كل 1 Coin/s من وحوشك بيزوّد ضربتك 2
	AttackCooldown = 0.35,
	BatReach = 7, -- قد إيه تبعد عن حرف الأم وتقدر تضربها بالمضرب
	MotherAttackInterval = 1.5,
	MotherAttackRange = 24,
	MotherRegenDelay = 20, -- لو محدش ضربها المدة دي الـ HP بيرجع كامل
	MotherChaseSpeed = 16, -- سرعتها وهي بتجري ورا اللي ضربها (أبطأ من اللاعب 25 عشان يقدر يهرب)
	MotherLeashRange = 70, -- لو اللاعب بعد عن عشها أكتر من كده بترجع
	TakeHoldDuration = 1,
}

-- Gamepasses و Developer Products -----------------------------------------------------
-- حط الـ Id بتاع كل واحد بعد ما تعمله من Creator Dashboard (بعد الـ Publish).
-- لو الـ Id = 0: في Studio الزرار بيدّيهولك مجاناً عشان التجربة، وفي اللعبة الحقيقية بيقول "Coming soon".
export type Gamepass = { Id: number, Name: string, Description: string, Price: number, Order: number }
Config.Gamepasses = {
	VIP = { Id = 0, Name = "VIP", Description = "x2 coins from all your monsters", Price = 299, Order = 1 },
	VIPSword = { Id = 0, Name = "VIP Sword", Description = "A strong sword for the monster zones", Price = 199, Order = 2 },
	AutoCollect = { Id = 0, Name = "Auto-Collect", Description = "Coins go to your wallet by themselves", Price = 149, Order = 3 },
	ExtraSlots = { Id = 0, Name = "+2 Slots", Description = "Two more monster slots in your base", Price = 99, Order = 4 },
	IronBat = { Id = 0, Name = "Iron Bat", Description = "A heavy bat for stronger hits", Price = 79, Order = 9 },
	IronSword = { Id = 0, Name = "Iron Sword", Description = "A reliable sword for monster zones", Price = 99, Order = 10 },
	ForestSword = { Id = 0, Name = "Forest Sword", Description = "A nature-forged sword", Price = 149, Order = 11 },
	DesertSword = { Id = 0, Name = "Desert Sword", Description = "A sword tempered by desert heat", Price = 199, Order = 12 },
	IceSword = { Id = 0, Name = "Ice Sword", Description = "A frozen sword with extra reach", Price = 249, Order = 13 },
	LavaSword = { Id = 0, Name = "Lava Sword", Description = "A blazing sword with maximum power", Price = 299, Order = 14 },
} :: { [string]: Gamepass }

export type Product = { Id: number, Name: string, Description: string, Price: number, Order: number }
Config.Products = {
	InstantHatch = { Id = 0, Name = "Instant Hatch", Description = "All your eggs hatch right now", Price = 25, Order = 1 },
	LuckyEgg = { Id = 0, Name = "Lucky Egg", Description = "A rare egg with better odds", Price = 49, Order = 2 },
	SpeedBoost = { Id = 0, Name = "Speed Boost", Description = "Run faster for 10 minutes", Price = 29, Order = 3 },
} :: { [string]: Product }

Config.VIPCoinMultiplier = 2
Config.ExtraSlotsAmount = 2
Config.VIPSword = { DamageMultiplier = 3, ExtraReach = 3 }
Config.WeaponStats = {
	IronBat = { Template = "IronBat", DamageMultiplier = 1.2, ExtraReach = 0.5 },
	VIPSword = { Template = "IceSword", DamageMultiplier = 3, ExtraReach = 3 },
	IronSword = { Template = "IronSword", DamageMultiplier = 1.5, ExtraReach = 1 },
	ForestSword = { Template = "ForestSword", DamageMultiplier = 1.8, ExtraReach = 1.5 },
	DesertSword = { Template = "DesertSword", DamageMultiplier = 2.1, ExtraReach = 2 },
	IceSword = { Template = "IceSword", DamageMultiplier = 2.5, ExtraReach = 2.5 },
	LavaSword = { Template = "LavaSword", DamageMultiplier = 3.5, ExtraReach = 4 },
} :: { [string]: { Template: string, DamageMultiplier: number, ExtraReach: number } }
-- معدات القتال تُشترى بعملات اللعبة من المتجر، مش بـ Robux.
Config.WeaponCoinPrices = {
	IronBat = 1500,
	IronSword = 2500,
	ForestSword = 6000,
	DesertSword = 12000,
	IceSword = 30000,
	VIPSword = 45000,
	LavaSword = 65000,
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
	Damage = 30, -- كل ضربة، لكل اللي جنبه
	AttackInterval = 1.5,
	AttackRange = 30,
	Size = 18,
	Lifetime = 600, -- لو محدش قتله بيمشي
	Position = Vector3.new(120, 0, 0), -- في الطريق جوه Zone 1
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
	Catch = { Duration = 12, XpPerCatch = 4, MaxCatches = 30 },
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
Config.AccessoryHatCostSeconds = 300 -- القبعة بتمن 5 دقايق إنتاج الوحش وهو Baby
Config.AccessoryGlassesCostSeconds = 200
Config.AccessoryMinCost = 150
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
	Position = Vector3.new(20, 0, 150), -- في الساحة
	RequestTimeout = 60,
	TurnTime = 0.8,
	MaxTurns = 40,
	PrizeCoins = 500, -- + 10% من قيمة الوحش اللي خسر
	PrizeValueShare = 0.1,
}

-- Trading -------------------------------------------------------------------------------------
Config.Trade = {
	MaxOffer = 4,
	RequestTimeout = 60,
}

return Config
