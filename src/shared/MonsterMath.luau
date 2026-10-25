--!strict
-- حسابات مشتركة بين السيرفر والواجهة (مستوى، مرحلة، إنتاج، أسعار).

local Config = require(script.Parent.Config)

export type MonsterData = {
	Id: string,
	Species: string,
	Mutation: string?,
	Level: number,
	Xp: number,
	Hunger: number,
	Happiness: number,
	Slot: number,
	LastProgressAt: number?, -- Server epoch; saved with XP and uncollected income.
	Hat: string?, -- إكسسوارات الوحش (Config.Accessories، بتاعة نوعه بس)
	Glasses: string?,
}

local MonsterMath = {}

function MonsterMath.GetStageIndex(level: number): number
	local index = 1
	for i, stage in Config.Stages do
		if level >= stage.MinLevel then
			index = i
		end
	end
	return index
end

function MonsterMath.GetStage(level: number): Config.Stage
	return Config.Stages[MonsterMath.GetStageIndex(level)]
end

function MonsterMath.GetMutation(name: string?): Config.Mutation?
	if not name then
		return nil
	end
	for _, mutation in Config.Mutations do
		if mutation.Name == name then
			return mutation
		end
	end
	return nil
end

function MonsterMath.GetMutationMultiplier(name: string?): number
	local mutation = MonsterMath.GetMutation(name)
	return if mutation then mutation.Multiplier else 1
end

-- الزيادة في الإنتاج من القبعة والنضارة (0.15 = +15%)
function MonsterMath.GetAccessoryBonus(monster: MonsterData): number
	local bonus = 0
	for _, name in { monster.Hat, monster.Glasses } do
		local accessory = name and Config.Accessories[name]
		if accessory and accessory.Species == monster.Species then
			bonus += accessory.Bonus
		end
	end
	return bonus
end

-- Coins في الثانية
function MonsterMath.GetProduction(monster: MonsterData): number
	local species = Config.Species[monster.Species]
	if not species then
		return 0
	end
	local stage = MonsterMath.GetStage(monster.Level)
	local levelBonus = 1 + (monster.Level - 1) * Config.ProductionLevelBonusPerLevel
	local production = species.BaseProduction
		* stage.ProductionMultiplier
		* levelBonus
		* MonsterMath.GetMutationMultiplier(monster.Mutation)
		* (1 + MonsterMath.GetAccessoryBonus(monster))
	if monster.Hunger < Config.LowNeedsThreshold or monster.Happiness < Config.LowNeedsThreshold then
		production *= Config.LowNeedsProductionMultiplier
	end
	return production
end

local adultLevel = Config.MaxLevel
for _, stage in Config.Stages do
	if stage.Name == "Adult" then adultLevel = stage.MinLevel; break end
end
local adultXp = 0
for level = 1, adultLevel - 1 do adultXp += Config.XpForLevel(level) end
local growthXpPerSecond = adultXp / Config.AdultGrowthSeconds

-- Care rewards still accelerate growth. Natural growth never depends on needs.
function MonsterMath.AddXp(monster: MonsterData, amount: number)
	monster.Xp += amount
	while monster.Level < Config.MaxLevel do
		local needed = Config.XpForLevel(monster.Level)
		if monster.Xp + 1e-7 < needed then break end
		monster.Xp = math.max(0, monster.Xp - needed)
		monster.Level += 1
	end
	if monster.Level >= Config.MaxLevel then monster.Xp = 0 end
end

-- One clock for online and offline progress. Integration splits only at level and
-- need thresholds, so years away cost at most MaxLevel + a few iterations.
-- Unplaced/carried monsters age, but do not produce coins or consume needs.
-- Legacy records have no reliable last-seen time: their first call starts now.
function MonsterMath.AdvanceProgress(monster: MonsterData, now: number, producing: boolean, multiplier: number): number
	local previous = monster.LastProgressAt
	if type(previous) ~= "number" or previous ~= previous or previous < 0 or previous > now then
		monster.LastProgressAt = now
		return 0
	end
	local remaining = now - previous
	monster.LastProgressAt = now
	local earned = 0
	MonsterMath.AddXp(monster, 0)
	while remaining > 1e-7 do
		local rate = 0
		if monster.Level < adultLevel then
			rate = growthXpPerSecond
		elseif producing and monster.Hunger > 50 and monster.Happiness > 50 and monster.Level < Config.MaxLevel then
			rate = Config.PassiveXpPerSecond
		end
		local duration = remaining
		if rate > 0 then duration = math.min(duration, (Config.XpForLevel(monster.Level) - monster.Xp) / rate) end
		if producing then
			for _, need in { { monster.Hunger, Config.HungerDecayPerSecond }, { monster.Happiness, Config.HappinessDecayPerSecond } } do
				if need[2] > 0 then
					for _, threshold in { 50, Config.LowNeedsThreshold, 0 } do
						if need[1] > threshold then duration = math.min(duration, (need[1] - threshold) / need[2]) end
					end
				end
			end
			-- Sampling within a segment handles exact threshold crossings correctly.
			local sample = table.clone(monster)
			sample.Hunger = math.max(0, monster.Hunger - Config.HungerDecayPerSecond * duration / 2)
			sample.Happiness = math.max(0, monster.Happiness - Config.HappinessDecayPerSecond * duration / 2)
			earned += MonsterMath.GetProduction(sample) * multiplier * duration
			monster.Hunger = math.max(0, monster.Hunger - Config.HungerDecayPerSecond * duration)
			monster.Happiness = math.max(0, monster.Happiness - Config.HappinessDecayPerSecond * duration)
		end
		MonsterMath.AddXp(monster, rate * duration)
		remaining -= duration
	end
	return earned
end

function MonsterMath.GetSellValue(monster: MonsterData): number
	local species = Config.Species[monster.Species]
	if not species then
		return 0
	end
	local stage = MonsterMath.GetStage(monster.Level)
	return math.floor(
		species.SellValue
			* (1 + (monster.Level - 1) * Config.SellLevelBonusPerLevel)
			* stage.ProductionMultiplier
			* MonsterMath.GetMutationMultiplier(monster.Mutation)
	)
end

-- تمن الأكل بيمشي مع دخل النوع: Grassland يفضل رخيص، وVoid يبقى بالآلاف
function MonsterMath.GetFoodCost(monster: MonsterData): number
	local species = Config.Species[monster.Species]
	local scaled = if species then Config.Food.CostPerBaseProduction * species.BaseProduction else 0
	return math.floor(math.max(Config.Food.Cost, scaled)) * MonsterMath.GetStageIndex(monster.Level)
end

function MonsterMath.GetDisplayName(monster: MonsterData): string
	local species = Config.Species[monster.Species]
	local name = if species then species.DisplayName else monster.Species
	if monster.Mutation then
		name = monster.Mutation .. " " .. name
	end
	return name
end

function MonsterMath.FormatNumber(value: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
	local index = 1
	while math.abs(value) >= 1000 and index < #suffixes do
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	return string.format("%.1f%s", value, suffixes[index])
end

return MonsterMath
