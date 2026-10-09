--!strict
-- كل أرقام اللعبة في مكان واحد عشان تعدّل التوازن بسهولة.

local Config = {}

Config.StartingCoins = 150
Config.DataStoreName = "RaiseAMonster_v1"
Config.AutosaveInterval = 60 -- ثواني

-- القاعدة ------------------------------------------------------------------
Config.MaxPlots = 8
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
	HoldDuration = 2.5, -- مدة الضغط على زرار السرقة
	CarryWalkSpeed = 11, -- سرعة الحرامي وهو شايل الوحش
	CatchRadius = 7, -- لو صاحب الوحش قرّب كده من الحرامي الوحش يرجع
	MaxCarryTime = 60,
	ProtectLastMonster = true, -- ماينفعش تسرق آخر وحش مع لاعب
}

return Config
