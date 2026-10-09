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
	Rare = { Name = "Rare", Color = Color3.fromRGB(70, 150, 255), Order = 2 },
	Epic = { Name = "Epic", Color = Color3.fromRGB(180, 80, 255), Order = 3 },
	Mythic = { Name = "Mythic", Color = Color3.fromRGB(255, 70, 90), Order = 4 },
} :: { [string]: Rarity }

export type Species = {
	DisplayName: string,
	Rarity: string,
	BaseProduction: number, -- Coins في الثانية في مرحلة Baby
	SellValue: number,
	Color: Color3,
	Horns: boolean,
	Placeholder: boolean?, -- شكل مؤقت (مكعب واسمه فوقه) لحد ما الـ Skin يجهز
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

-- وحوش المناطق: بالأرقام وشكلها مؤقت لحد ما الـ Skins تيجي.
-- كل منطقة ليها 4 وحوش، وكل ما المنطقة تبعد الوحش بيبقى أندر وبينتج أكتر.
local ZONE_SPECIES_STATS = {
	{ Rarity = "Common", Production = { 1.5, 1.8, 2.1, 2.5 }, Sell = { 60, 70, 85, 100 } },
	{ Rarity = "Rare", Production = { 6, 7, 8, 9 }, Sell = { 600, 700, 800, 900 } },
	{ Rarity = "Epic", Production = { 28, 32, 36, 40 }, Sell = { 6000, 7000, 8000, 9000 } },
	{ Rarity = "Mythic", Production = { 120, 140, 160, 180 }, Sell = { 40000, 46000, 52000, 60000 } },
}
for zoneIndex, stats in ZONE_SPECIES_STATS do
	for i = 1, 4 do
		local number = (zoneIndex - 1) * 4 + i
		Config.Species["Monster" .. number] = {
			DisplayName = "Monster " .. number,
			Rarity = stats.Rarity,
			BaseProduction = stats.Production[i],
			SellValue = stats.Sell[i],
			Color = Color3.fromRGB(163, 162, 165),
			Horns = false,
			Placeholder = true,
		}
	end
end

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
		Weights = { Blobby = 55, Pebble = 35, Fangy = 8, Frosty = 2 },
	},
	Rare = {
		DisplayName = "Rare Egg",
		Cost = 1200,
		HatchTime = 45,
		Color = Color3.fromRGB(80, 160, 255),
		Order = 2,
		Weights = { Pebble = 20, Fangy = 40, Frosty = 30, Shadowy = 8, Flamey = 2 },
	},
	Mythic = {
		DisplayName = "Mythic Egg",
		Cost = 15000,
		HatchTime = 90,
		Color = Color3.fromRGB(255, 60, 120),
		Order = 3,
		Weights = { Frosty = 25, Shadowy = 35, Flamey = 30, Draco = 10 },
	},
} :: { [string]: Egg }

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
	Decoration: string, -- "Flowers" / "Trees" / "Lava" / "Crystals"
	Species: { string },
	MotherHealth: number,
	MotherDamage: number, -- الضرر اللي الأم بتعمله في اللاعبين اللي جنبها كل ضربة
	MotherSize: number,
}

Config.Zones = {
	{
		Name = "Meadow",
		Difficulty = "Easy",
		Stars = 1,
		GroundColor = Color3.fromRGB(120, 200, 90),
		GroundMaterial = Enum.Material.Grass,
		AccentColor = Color3.fromRGB(90, 220, 110),
		Decoration = "Flowers",
		Species = { "Monster1", "Monster2", "Monster3", "Monster4" },
		MotherHealth = 300,
		MotherDamage = 5,
		MotherSize = 6,
	},
	{
		Name = "Forest",
		Difficulty = "Medium",
		Stars = 2,
		GroundColor = Color3.fromRGB(60, 130, 60),
		GroundMaterial = Enum.Material.Grass,
		AccentColor = Color3.fromRGB(60, 150, 255),
		Decoration = "Trees",
		Species = { "Monster5", "Monster6", "Monster7", "Monster8" },
		MotherHealth = 4000,
		MotherDamage = 12,
		MotherSize = 7.5,
	},
	{
		Name = "Lava Canyon",
		Difficulty = "Hard",
		Stars = 3,
		GroundColor = Color3.fromRGB(60, 45, 45),
		GroundMaterial = Enum.Material.Basalt,
		AccentColor = Color3.fromRGB(255, 120, 30),
		Decoration = "Lava",
		Species = { "Monster9", "Monster10", "Monster11", "Monster12" },
		MotherHealth = 40000,
		MotherDamage = 25,
		MotherSize = 9,
	},
	{
		Name = "Shadow Realm",
		Difficulty = "Extreme",
		Stars = 4,
		GroundColor = Color3.fromRGB(45, 30, 70),
		GroundMaterial = Enum.Material.Slate,
		AccentColor = Color3.fromRGB(170, 70, 255),
		Decoration = "Crystals",
		Species = { "Monster13", "Monster14", "Monster15", "Monster16" },
		MotherHealth = 400000,
		MotherDamage = 45,
		MotherSize = 11,
	},
} :: { Zone }

Config.ZoneResetInterval = 600 -- كل 10 دقايق الأعشاش بتتجدد بوحوش تانية
Config.NestsPerZone = 3
Config.BabiesPerNest = 3

Config.Combat = {
	BaseDamage = 10, -- ضرر اللاعب من غير وحوش
	DamagePerProduction = 2, -- كل 1 Coin/s من وحوشك بيزوّد ضربتك 2
	AttackCooldown = 0.35,
	MotherAttackInterval = 1.5,
	MotherAttackRange = 24,
	MotherRegenDelay = 20, -- لو محدش ضربها المدة دي الـ HP بيرجع كامل
	TakeHoldDuration = 1,
}

return Config
