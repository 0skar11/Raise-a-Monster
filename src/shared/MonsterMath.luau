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

-- Coins في الثانية
function MonsterMath.GetProduction(monster: MonsterData): number
	local species = Config.Species[monster.Species]
	if not species then
		return 0
	end
	local stage = MonsterMath.GetStage(monster.Level)
	local levelBonus = 1 + (monster.Level - 1) * 0.05
	local production = species.BaseProduction
		* stage.ProductionMultiplier
		* levelBonus
		* MonsterMath.GetMutationMultiplier(monster.Mutation)
	if monster.Hunger < Config.LowNeedsThreshold or monster.Happiness < Config.LowNeedsThreshold then
		production *= Config.LowNeedsProductionMultiplier
	end
	return production
end

function MonsterMath.GetSellValue(monster: MonsterData): number
	local species = Config.Species[monster.Species]
	if not species then
		return 0
	end
	local stage = MonsterMath.GetStage(monster.Level)
	return math.floor(
		species.SellValue
			* (1 + (monster.Level - 1) * 0.1)
			* stage.ProductionMultiplier
			* MonsterMath.GetMutationMultiplier(monster.Mutation)
	)
end

function MonsterMath.GetFoodCost(monster: MonsterData): number
	return Config.Food.Cost * MonsterMath.GetStageIndex(monster.Level)
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
	local suffixes = { "", "K", "M", "B", "T" }
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
