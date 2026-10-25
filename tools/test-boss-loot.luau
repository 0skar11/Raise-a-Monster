-- Pumpkin Titan loot: roll counts by damage share, fixed Halloween-egg / Secret-egg odds, rare boost,
-- no guaranteed Secret Egg any more, the damage board, and the three loot-only speed accessories.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function load(path)
	local env = table.clone(getfenv())
	for key, value in r do env[key] = value end
	return luau.load(fs.readFile(path), { environment = env })()
end
local function read(path) return fs.readFile(path) end

local Config = load("src/shared/Config.luau")
local Math = load("src/shared/BossLootMath.luau")
local loot = Config.BossLoot

-- deterministic generator so the statistics never flake
local seed = 12345
local function rng()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

-- roll count -----------------------------------------------------------------------------------------------
check(Math.RollCount(0, loot, rng) == 0 and Math.RollCount(loot.MinShare - 0.001, loot, rng) == 0, "Below 1% of the boss's HP there is no loot")
for _, case in {
	{ share = 0.03, chances = { 85, 15, 0 } },
	{ share = 0.10, chances = { 55, 35, 10 } },
	{ share = 0.20, chances = { 30, 45, 25 } },
	{ share = 0.60, chances = { 15, 40, 45 } },
} do
	local counts, samples = { 0, 0, 0 }, 100000
	for _ = 1, samples do
		local count = Math.RollCount(case.share, loot, rng)
		check(count >= 1 and count <= 3, "A fighter always gets between 1 and 3 rolls")
		counts[count] += 1
	end
	for index = 1, 3 do
		check(math.abs(counts[index] / samples * 100 - case.chances[index]) < 1, string.format("share %.2f: %d roll(s) happen about %d%% of the time", case.share, index, case.chances[index]))
	end
end
local function meanRolls(share)
	local total, samples = 0, 50000
	for _ = 1, samples do total += Math.RollCount(share, loot, rng) end
	return total / samples
end
check(meanRolls(0.03) < meanRolls(0.10) and meanRolls(0.10) < meanRolls(0.20) and meanRolls(0.20) < meanRolls(0.60), "More damage means more rolls on average")

-- pick odds ------------------------------------------------------------------------------------------------
local function tally(share, samples)
	local result = { total = samples, byKey = {} }
	for _ = 1, samples do
		local entry = Math.Pick(share, loot, rng)
		local key = entry.Kind .. ":" .. tostring(entry.Egg or "")
		result.byKey[key] = (result.byKey[key] or 0) + 1
	end
	return result
end
for _, share in { 0.02, 0.5 } do
	local result = tally(share, 200000)
	local halloween = (result.byKey["Egg:HalloweenMonster"] or 0) / result.total
	local secret = (result.byKey["Egg:Secret"] or 0) / result.total
	check(math.abs(halloween - 0.05) < 0.004, string.format("Halloween Monster Egg is 5%% per roll at share %.2f (got %.4f)", share, halloween))
	check(math.abs(secret - 0.03) < 0.004, string.format("Secret Egg is 3%% per roll at share %.2f (got %.4f)", share, secret))
end
local small, big = tally(0.02, 200000), tally(0.6, 200000)
check((big.byKey["Accessory:"] or 0) > (small.byKey["Accessory:"] or 0) * 1.3, "Bigger damage shares get noticeably more accessory drops")
check(Math.Weight({ Weight = 10, Rare = true }, 0.5, loot) == 10 * (1 + 0.5 * loot.RareBoost) and Math.Weight({ Weight = 10 }, 0.5, loot) == 10, "Only rare entries grow with the damage share")
for _, entry in loot.Entries do check((entry.Weight or 0) > 0, "Every weighted loot entry has a positive weight") end
local fixedTotal = 0
for _, entry in loot.Fixed do fixedTotal += entry.Chance end
check(fixedTotal < 0.2 and loot.Fixed[1].Egg == "HalloweenMonster" and loot.Fixed[1].Chance == 0.05, "Fixed odds are small and the first one is the 5% Halloween Monster Egg")
for _, entry in loot.Entries do
	if entry.Kind == "Egg" then check(Config.Eggs[entry.Egg] ~= nil, entry.Egg .. " is a real egg") end
end
for _, entry in loot.Fixed do check(Config.Eggs[entry.Egg] ~= nil, entry.Egg .. " is a real egg") end
local keys = {}
for _ = 1, 2000 do keys[Math.WeightedKey(loot.AccessoryWeights, rng)] = true end
check(keys.WitchBoots and keys.PhantomCloak and keys.PumpkinKingWings, "Every boss accessory can drop")

-- accessories ----------------------------------------------------------------------------------------------
local gear = Config.SpeedAccessories
local order = { "WitchBoots", "PhantomCloak", "PumpkinKingWings" }
for _, key in order do
	check(gear[key] ~= nil and gear[key].LootOnly == true and gear[key].Price == 0, key .. " is boss-loot-only and never sold")
	check(loot.AccessoryWeights[key] ~= nil, key .. " has a drop weight")
end
check(gear.WitchBoots.Multiplier == 1.18 and gear.PhantomCloak.Multiplier == 1.32 and gear.PumpkinKingWings.Multiplier == 1.45, "Boss accessories give x1.18, x1.32 and x1.45 speed")
check(gear.WitchBoots.Multiplier < gear.PhantomCloak.Multiplier and gear.PhantomCloak.Multiplier < gear.PumpkinKingWings.Multiplier, "Each boss accessory is faster than the one before")
for key, info in gear do
	if not info.LootOnly then check(info.Price > 0, key .. " stays a normal shop item") end
end
local service = read("src/server/MonsterService.luau")
check(service:find("or accessory.LootOnly then", 1, true), "Buying a loot-only accessory is refused on the server")
check(read("src/client/MonsterForge.luau"):find("OwnedOnly = info.LootOnly == true", 1, true), "Loot-only accessories only show under Owned")
local character = read("src/server/CharacterService.luau")
for _, key in order do check(character:find('selected == "' .. key .. '"', 1, true), key .. " has an in-game model") end
check(read("src/client/GearAnimate.luau"):find('"PhantomCloak"', 1, true) and read("src/client/GearAnimate.luau"):find("KingWingL", 1, true) and read("src/client/GearAnimate.luau"):find('gear == "WitchBoots"', 1, true), "The client animates all three")
for _, key in order do check(read("src/client/UI.luau"):find('gearName == "' .. key .. '"', 1, true), key .. " has a shop/inventory preview") end

-- the boss -------------------------------------------------------------------------------------------------
local event = read("src/server/EventService.luau")
check(not event:find('EggType = "Secret"', 1, true), "The boss no longer drops a guaranteed Secret Egg")
check(event:find("BossLoot.Distribute(fighters, current.MaxHealth)", 1, true), "Loot is shared out when the boss dies")
check(event:find("contributor.Damage += dealt", 1, true) and event:find("math.min(current.Health, damage", 1, true), "Damage is recorded per player and capped at the boss's remaining HP")
local fx = read("src/client/BossFx.luau")
check(event:find('part:SetAttribute("DamageBoard"', 1, true) and fx:find('part:GetAttribute("DamageBoard")', 1, true), "The damage list travels as a boss attribute and is read by the boss bar HUD")
check(fx:find("damageList.BackgroundTransparency = 1", 1, true) and fx:find("damageList.TextStrokeTransparency", 1, true) and fx:find("damageList.Position = UDim2.fromOffset(0, 60)", 1, true) and fx:find("damageList.Parent = frame", 1, true), "A background-free damage list sits directly under the health bar")
check(event:find("%.1f%%", 1, true), "The board shows each fighter's damage percentage")
local bossLoot = read("src/server/BossLoot.luau")
local panel = read("src/client/BossLootPanel.luau")
check(bossLoot:find("remotes.BossLoot:FireClient", 1, true) and panel:find("remotes.BossLoot.OnClientEvent", 1, true) and read("src/shared/Remotes.luau"):find('"BossLoot"', 1, true), "The loot result reaches the client through the BossLoot remote")
check(panel:find("COLLECT", 1, true) and panel:find("Config.Rarities", 1, true) and read("src/client/init.client.luau"):find("BossLootPanel.Start", 1, true), "The loot panel shows rarity cards with a Collect button and is started by the client")
check(bossLoot:find("BossLootMath.RollCount", 1, true) and bossLoot:find("BossLootMath.Pick", 1, true), "The server uses the tested loot maths")
check(not Config.Halloween.Items.GhostSlime and not Config.Halloween.Items.SkeletonImp and not Config.Halloween.Items.PumpkinKing, "The old Candy-shop monsters are gone")

-- Secret monsters use real rigs (region 7) instead of the plain blob
local models = read("src/server/MonsterModels.luau")
check(models:find('name = "Secret"', 1, true) and models:find('"Void Phantom"', 1, true) and models:find('"Celestial Void"', 1, true) and models:find("Secret    = {", 1, true), "MonsterModels has a Secret region with both Secret rigs and a Secret rarity look")
for index, key in { "Secret1", "Secret2" } do
	local model = Config.Species[key].Model
	check(model and model.Region == 7 and model.Index == index, key .. " points at its rigged model")
end

print(string.format("PASS: %d boss loot checks", checks))
