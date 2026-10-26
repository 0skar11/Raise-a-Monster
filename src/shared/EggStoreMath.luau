--!strict
-- Pure Egg Keeper store rules (no Roblox services), shared by the server that charges and the client that
-- displays, and loadable by the lune tests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local EggStoreMath = {}

-- Only these bundle sizes are ever accepted; anything else (0, 2, -1, 1e9, NaN, strings) is rejected.
function EggStoreMath.FindBundle(count: unknown): Config.EggBundle?
	if type(count) ~= "number" then return nil end
	for _, bundle in Config.EggStore.Bundles do
		if bundle.Count == count then return bundle end
	end
	return nil
end

-- Robux price of a bundle (the -10% / -20% badges are this price against Count x the single-egg price).
function EggStoreMath.BundlePrice(bundle: Config.EggBundle): number
	return math.floor(Config.EggStore.EggPrice * bundle.Count * (1 - bundle.Discount) + 0.5)
end

-- Developer Product id of a bundle (0 = not created yet).
function EggStoreMath.BundleProductId(bundle: Config.EggBundle): number
	local id = Config.EggStore.Products["Egg" .. bundle.Count]
	return if type(id) == "number" then id else 0
end

function EggStoreMath.LuckProductId(): number
	local id = Config.EggStore.Products.Luck
	return if type(id) == "number" then id else 0
end

-- Which store item a receipt's product id is: ("Bundle", bundle), ("Luck", nil) or nil. Unset ids (0) never match.
function EggStoreMath.ProductFor(productId: unknown): (string?, Config.EggBundle?)
	if type(productId) ~= "number" or productId <= 0 then return nil, nil end
	if productId == EggStoreMath.LuckProductId() then return "Luck", nil end
	for _, bundle in Config.EggStore.Bundles do
		if EggStoreMath.BundleProductId(bundle) == productId then return "Bundle", bundle end
	end
	return nil, nil
end

-- Hatch weights with Luck applied (a copy; the Config table is never touched).
function EggStoreMath.LuckWeights(weights: { [string]: number }, luckActive: boolean): { [string]: number }
	local result: { [string]: number } = {}
	local luck = Config.EggStore.Luck
	for species, weight in weights do
		local definition = Config.Species[species]
		local boosted = luckActive and definition ~= nil and luck.Rarities[definition.Rarity] == true
		result[species] = if boosted then weight * luck.Multiplier else weight
	end
	return result
end

-- Percent chance of each species (sums to 100) with or without Luck.
function EggStoreMath.Odds(weights: { [string]: number }, luckActive: boolean): { [string]: number }
	local adjusted = EggStoreMath.LuckWeights(weights, luckActive)
	local total = 0
	for _, weight in adjusted do total += weight end
	local odds: { [string]: number } = {}
	for species, weight in adjusted do
		odds[species] = if total > 0 then weight / total * 100 else 0
	end
	return odds
end

function EggStoreMath.AppliesLuck(eggType: string): boolean
	return Config.EggStore.Luck.Eggs[eggType] == true
end

-- Seconds of Luck left at `now`.
function EggStoreMath.LuckLeft(luckUntil: number, now: number): number
	return math.max(0, luckUntil - now)
end

-- New expiry after buying one Luck, or nil when the timer is already at its cap (nothing is charged then).
function EggStoreMath.ExtendLuck(luckUntil: number, now: number): number?
	local luck = Config.EggStore.Luck
	local base = math.max(luckUntil, now)
	if base - now + luck.Duration > luck.MaxSeconds then return nil end
	return base + luck.Duration
end

return EggStoreMath
