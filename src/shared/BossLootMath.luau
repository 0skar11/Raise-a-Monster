--!strict
-- Pumpkin Titan loot odds. Pure maths (no Roblox services) so the roll tables can be tested offline.
-- Config.BossLoot holds every number; this file only turns "share of the boss's HP you dealt" into rolls.

local BossLootMath = {}

export type Rng = () -> number

type LootConfig = {
	MinShare: number,
	RareBoost: number,
	RollTable: { { any } },
	Fixed: { any },
	Entries: { any },
}

-- 0 rolls below MinShare, otherwise 1 to 3 rolls from the row that covers the share.
function BossLootMath.RollCount(share: number, loot: LootConfig, rng: Rng): number
	if share < loot.MinShare then
		return 0
	end
	local row = loot.RollTable[#loot.RollTable]
	for _, candidate in loot.RollTable do
		if share < candidate[1] then
			row = candidate
			break
		end
	end
	local chances = row[2] :: { number }
	local total = 0
	for _, chance in chances do
		total += chance
	end
	local roll = rng() * total
	for count, chance in chances do
		roll -= chance
		if roll < 0 then
			return count
		end
	end
	for count = #chances, 1, -1 do
		if chances[count] > 0 then
			return count
		end
	end
	return 1
end

-- The weight an entry has for a player who dealt `share` of the boss's HP: rare entries grow with the share.
function BossLootMath.Weight(entry: any, share: number, loot: LootConfig): number
	local weight = entry.Weight or 0
	if entry.Rare then
		weight *= 1 + math.clamp(share, 0, 1) * loot.RareBoost
	end
	return weight
end

-- One roll: the fixed-odds entries first (their chance never changes), otherwise a weighted pick.
function BossLootMath.Pick(share: number, loot: LootConfig, rng: Rng): any
	local roll = rng()
	for _, entry in loot.Fixed do
		if roll < entry.Chance then
			return entry
		end
		roll -= entry.Chance
	end
	local total = 0
	for _, entry in loot.Entries do
		total += BossLootMath.Weight(entry, share, loot)
	end
	local pick = rng() * total
	for _, entry in loot.Entries do
		pick -= BossLootMath.Weight(entry, share, loot)
		if pick < 0 then
			return entry
		end
	end
	return loot.Entries[#loot.Entries]
end

-- Picks one key from { [key] = weight }.
function BossLootMath.WeightedKey(weights: { [string]: number }, rng: Rng): string?
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	table.sort(keys)
	local pick = rng() * total
	for _, key in keys do
		pick -= weights[key]
		if pick < 0 then
			return key
		end
	end
	return keys[#keys]
end

return BossLootMath
