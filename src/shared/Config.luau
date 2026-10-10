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
	Rare = { Name = "Rare", Color = Color3.fromRGB(70, 150, 255), Order = 2 },
	Epic = { Name = "Epic", Color = Color3.fromRGB(180, 80, 255), Order = 3 },
	Legendary = { Name = "Legendary", Color = Color3.fromRGB(255, 170, 40), Order = 4 },
	Mythic = { Name = "Mythic", Color = Color3.fromRGB(255, 70, 90), Order = 5 },
	Secret = { Name = "Secret", Color = Color3.fromRGB(255, 255, 255), Order = 6 },
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
	-- بيضة الحظ (Developer Product وعجلة الحظ): أندر من العادي، وفرصة الـ Secret فيها ×5
	Lucky = {
		DisplayName = "Lucky Egg",
		Cost = 0,
		HatchTime = 30,
		Color = Color3.fromRGB(90, 230, 120),
		Order = 4,
		Weights = { Fangy = 25, Frosty = 25, Shadowy = 25, Flamey = 15, Draco = 10 },
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

Config.WalkSpeed = 20 -- سرعة المشي (الافتراضي في Roblox 16)

-- الوحش اللي شايله على ضهرك لحد ما توصل قاعدتك
Config.Carry = {
	WalkSpeedMultiplier = 0.8, -- بتمشي أبطأ وانت شايل وحش
	SecretEggSpeedMultiplier = 0.7, -- بيضة الـ Big Boss تقيلة شوية
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
Config.SpeedBoost = { Duration = 600, Multiplier = 1.4 }

-- أحداث الماب ---------------------------------------------------------------------------
-- Monster Rain: كل ساعة وحش نادر بيقع في نص الماب، وأول واحد يمسكه ويوصله قاعدته ياخده.
Config.MonsterRain = {
	Interval = 3600,
	Lifetime = 300, -- لو محدش مسكه بيختفي
	Species = { "Shadowy", "Flamey", "Draco", "Monster9", "Monster10", "Monster11", "Monster12", "Monster13", "Monster14" },
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

-- إكسسوارات الوحوش -------------------------------------------------------------------------
export type Accessory = { Name: string, Slot: string, Cost: number, Bonus: number, Color: Color3, Order: number }
Config.Accessories = {
	PartyHat = { Name = "Party Hat", Slot = "Hat", Cost = 300, Bonus = 0, Color = Color3.fromRGB(255, 90, 180), Order = 1 },
	TopHat = { Name = "Top Hat", Slot = "Hat", Cost = 1500, Bonus = 0.03, Color = Color3.fromRGB(30, 30, 35), Order = 2 },
	WizardHat = { Name = "Wizard Hat", Slot = "Hat", Cost = 8000, Bonus = 0.08, Color = Color3.fromRGB(90, 60, 200), Order = 3 },
	Crown = { Name = "Crown", Slot = "Hat", Cost = 30000, Bonus = 0.15, Color = Color3.fromRGB(255, 205, 50), Order = 4 },
	StarGlasses = { Name = "Star Glasses", Slot = "Glasses", Cost = 400, Bonus = 0, Color = Color3.fromRGB(255, 220, 60), Order = 5 },
	CoolShades = { Name = "Cool Shades", Slot = "Glasses", Cost = 2500, Bonus = 0.05, Color = Color3.fromRGB(20, 20, 25), Order = 6 },
	Monocle = { Name = "Monocle", Slot = "Glasses", Cost = 12000, Bonus = 0.1, Color = Color3.fromRGB(230, 190, 80), Order = 7 },
} :: { [string]: Accessory }

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
