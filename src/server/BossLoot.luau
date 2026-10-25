--!strict
-- Pumpkin Titan loot: when the boss dies every player who dealt enough damage gets 1 to 3 rolls
-- (Config.BossLoot). Server-authoritative; items go straight into the player's data, nothing lands on the ground.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local BossLootMath = require(ReplicatedStorage.Shared.BossLootMath)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local HalloweenService = require(script.Parent.HalloweenService)

local BossLoot = {}

export type Contributor = { Player: Player, Name: string, Damage: number }

local PURPLE = Color3.fromRGB(200, 120, 255)

local function coins(player: Player, amount: number, label: string): string
	DataService.AddCoins(player, amount)
	return label .. " 💰 " .. MonsterMath.FormatNumber(amount)
end

-- Candy only exists during the event; outside it the same reward is paid as coins.
local function candy(player: Player, amount: number): string
	local granted = HalloweenService.AddCandy(player, amount)
	if granted > 0 then
		return "🍬 " .. MonsterMath.FormatNumber(granted) .. " Candy"
	end
	return coins(player, amount * Config.Halloween.CandyToCoinRate, "Candy turned into")
end

local function egg(player: Player, eggType: string): string
	local config = Config.Eggs[eggType]
	local name = if config then config.DisplayName else eggType
	if config and MonsterService.AddEgg(player, eggType) then
		return "🥚 " .. name
	end
	local income = MonsterService.GetIncomePerSecond(player) * Config.Spin.EggFallbackMinutes * 60
	return coins(player, math.max(1000, math.floor(income)), name .. " turned into")
end

-- Returns the accessory key that was granted (or "" for a duplicate that paid Candy instead) and its text.
local function accessory(player: Player, rng: BossLootMath.Rng): (string, string)
	local key = BossLootMath.WeightedKey(Config.BossLoot.AccessoryWeights, rng)
	local info = key and Config.SpeedAccessories[key]
	local profile = DataService.Get(player)
	if not key or not info or not profile or type(profile.Data.SpeedAccessories) ~= "table" then
		return "", candy(player, Config.BossLoot.AccessoryCandy)
	end
	if profile.Data.SpeedAccessories[key] == true then
		return "", "duplicate " .. info.Name .. " → " .. candy(player, Config.BossLoot.AccessoryCandy)
	end
	profile.Data.SpeedAccessories[key] = true
	return key, "👟 " .. info.Name .. " (x" .. string.format("%.2f", info.Multiplier) .. " speed)"
end

-- Rolls and grants the loot for one player. Returns the text of every drop.
function BossLoot.GrantTo(player: Player, share: number, rng: BossLootMath.Rng?): { string }
	local random = rng or math.random
	local loot = Config.BossLoot
	local lines: { string } = {}
	local count = BossLootMath.RollCount(share, loot, random)
	for _ = 1, count do
		local entry = BossLootMath.Pick(share, loot, random)
		local text: string
		if entry.Kind == "Candy" then
			text = candy(player, entry.Candy)
		elseif entry.Kind == "Coins" then
			local income = MonsterService.GetIncomePerSecond(player) * (entry.Minutes or 0) * 60
			text = coins(player, math.max(entry.Floor or 0, math.floor(income)), "Coins")
		elseif entry.Kind == "Egg" then
			text = egg(player, entry.Egg)
			if entry.Egg == "HalloweenMonster" or entry.Egg == "Secret" then
				MonsterService.Announce("🎁 " .. player.DisplayName .. " won a " .. Config.Eggs[entry.Egg].DisplayName .. " from the Pumpkin Titan!", PURPLE)
			end
		else
			local key, description = accessory(player, random)
			text = description
			if key ~= "" then
				MonsterService.Announce("🎁 " .. player.DisplayName .. " won " .. Config.SpeedAccessories[key].Name .. " from the Pumpkin Titan!", PURPLE)
			end
		end
		table.insert(lines, text)
	end
	return lines
end

-- Every contributor with at least Config.BossLoot.MinShare of the boss's max HP gets loot.
function BossLoot.Distribute(contributors: { Contributor }, maxHealth: number)
	for _, contributor in contributors do
		local player = contributor.Player
		if player.Parent and DataService.Get(player) then
			local share = math.clamp(contributor.Damage / math.max(1, maxHealth), 0, 1)
			local percent = string.format("%.1f%%", share * 100)
			local lines = BossLoot.GrantTo(player, share)
			if #lines == 0 then
				MonsterService.Notify(player, "You dealt " .. percent .. " of the boss's HP. Deal at least " .. string.format("%d%%", Config.BossLoot.MinShare * 100) .. " to earn loot!", "info")
			else
				MonsterService.Notify(player, "🎁 BOSS LOOT (" .. percent .. " damage): " .. table.concat(lines, "  •  "), "success")
			end
			MonsterService.PushState(player)
			task.spawn(DataService.Save, player)
		end
	end
end

return BossLoot
