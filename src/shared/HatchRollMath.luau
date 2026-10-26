--!strict
-- Odds and reel contents for the egg-hatch roll. Pure maths on Config (no Roblox services), so the strip builder
-- can be checked offline. The server already chose the monster; nothing here can change what hatched.
local Config = require(script.Parent.Config)

local HatchRollMath = {}

export type Entry = { Key: string, Pct: number, Mystery: boolean? }

HatchRollMath.WinIndex = 46 -- the reel's landing card
HatchRollMath.TotalCards = 62

local function rarityOrder(rarity: string): number
	local info = Config.Rarities[rarity]
	return if info then info.Order else 1
end

function HatchRollMath.PctText(pct: number): string
	return string.format("%g%%", math.floor(pct * 100 + 0.5) / 100)
end

-- Chance (in %) of the separate Secret roll that can replace the egg's own monster.
function HatchRollMath.SecretPct(eggType: string): number
	return Config.SecretChance * (if eggType == "Lucky" then Config.LuckyEggSecretMultiplier else 1) * 100
end

-- Every monster an egg can give with its drop %, rarest first, plus one "mystery" entry for the Secret roll.
function HatchRollMath.PoolFor(eggType: string): { Entry }
	local egg = Config.Eggs[eggType]
	local pool: { Entry } = {}
	if not egg then return pool end
	local total, onlySecret = 0, true
	for key, weight in egg.Weights do
		total += weight
		if Config.Species[key] and Config.Species[key].Rarity ~= "Secret" then onlySecret = false end
	end
	for key, weight in egg.Weights do
		table.insert(pool, { Key = key, Pct = weight / math.max(total, 1) * 100 })
	end
	table.sort(pool, function(a, b)
		local ra, rb = rarityOrder(Config.Species[a.Key].Rarity), rarityOrder(Config.Species[b.Key].Rarity)
		if ra ~= rb then return ra > rb end
		if a.Pct ~= b.Pct then return a.Pct > b.Pct end
		return a.Key < b.Key
	end)
	if not onlySecret and egg.AllowSecret ~= false then
		table.insert(pool, { Key = Config.SecretSpecies[1], Pct = HatchRollMath.SecretPct(eggType), Mystery = true })
	end
	return pool
end

-- The strip the reel scrolls: every monster at least twice, the rest sampled by the real odds (no rigged near-misses),
-- and the server's species at WinIndex.
function HatchRollMath.BuildStrip(eggType: string, species: string, random: Random): { Entry }
	local pool = HatchRollMath.PoolFor(eggType)
	local cards: { Entry } = {}
	local total = 0
	for _, entry in pool do
		table.insert(cards, entry)
		if not entry.Mystery then table.insert(cards, entry) end
		total += entry.Pct
	end
	while #cards < HatchRollMath.TotalCards do
		local roll, picked = random:NextNumber() * total, pool[1]
		for _, entry in pool do
			roll -= entry.Pct
			if roll <= 0 then picked = entry; break end
		end
		table.insert(cards, picked)
	end
	for i = #cards, 2, -1 do
		local j = random:NextInteger(1, i)
		cards[i], cards[j] = cards[j], cards[i]
	end
	for _ = 1, 30 do
		for i = 2, #cards do
			if cards[i].Key == cards[i - 1].Key then
				local j = random:NextInteger(1, #cards)
				cards[i], cards[j] = cards[j], cards[i]
			end
		end
	end
	local winner: Entry? = nil
	for _, entry in pool do
		if entry.Key == species and not entry.Mystery then winner = entry end
	end
	if not winner then
		-- a Secret from the separate roll: the card shows that monster with its share of the Secret chance
		local mystery = pool[#pool]
		local secretCount = math.max(#Config.SecretSpecies, 1)
		winner = { Key = species, Pct = if mystery and mystery.Mystery then mystery.Pct / secretCount else 0 }
	end
	cards[HatchRollMath.WinIndex] = winner :: Entry
	return cards
end

-- Chance of each mutation on any monster (Config.Mutations are tried in order, so later ones are conditional).
function HatchRollMath.MutationOdds(): { { Name: string, Pct: number, Mult: number } }
	local out = {}
	local survive = 1
	for _, mutation in Config.Mutations do
		table.insert(out, { Name = mutation.Name, Pct = mutation.Chance * survive * 100, Mult = mutation.Multiplier })
		survive *= 1 - mutation.Chance
	end
	return out
end

return HatchRollMath
