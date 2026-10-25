--!strict
-- Pumpkin Titan loot: when the boss dies every player who dealt enough damage gets 1 to 3 rolls
-- (Config.BossLoot). Server-authoritative; items go straight into the player's data, nothing lands on the ground.
-- The result is sent to the player as structured data (the BossLoot remote) for the loot panel on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local BossLootMath = require(ReplicatedStorage.Shared.BossLootMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local HalloweenService = require(script.Parent.HalloweenService)

local BossLoot = {}

export type Contributor = { Player: Player, Name: string, Damage: number }
export type Item = { Icon: string, Name: string, Detail: string, Rarity: string }

local PURPLE = Color3.fromRGB(200, 120, 255)
local remotes = Remotes.Get()

local EGG_RARITY = { Rare = "Rare", Lucky = "Epic", HalloweenMonster = "Legendary", Secret = "Secret" }
local EGG_DETAIL = {
	Rare = "Hatches a real monster",
	Lucky = "Better odds than a Rare Egg",
	HalloweenMonster = "Hatches one of the 8 Halloween monsters",
	Secret = "Hatches a Secret monster",
}
local ACCESSORY_RARITY = { WitchBoots = "Legendary", PhantomCloak = "Mythic", PumpkinKingWings = "Mythic" }

local function item(icon: string, name: string, detail: string, rarity: string): Item
	return { Icon = icon, Name = name, Detail = detail, Rarity = rarity }
end

local function coins(player: Player, amount: number, detail: string): Item
	DataService.AddCoins(player, amount)
	return item("💰", MonsterMath.FormatNumber(amount) .. " Coins", detail, "Common")
end

-- Candy only exists during the event; outside it the same reward is paid as coins.
local function candy(player: Player, amount: number): Item
	local granted = HalloweenService.AddCandy(player, amount)
	if granted > 0 then
		return item("🍬", MonsterMath.FormatNumber(granted) .. " Candy", "Spend it at the Pumpkin Merchant", "Common")
	end
	return coins(player, amount * Config.Halloween.CandyToCoinRate, "Candy paid as coins (no event right now)")
end

local function egg(player: Player, eggType: string): Item
	local config = Config.Eggs[eggType]
	local name = if config then config.DisplayName else eggType
	if config and MonsterService.AddEgg(player, eggType) then
		return item("🥚", name, EGG_DETAIL[eggType] or "Place it in your base to hatch", EGG_RARITY[eggType] or "Common")
	end
	local income = MonsterService.GetIncomePerSecond(player) * Config.Spin.EggFallbackMinutes * 60
	return coins(player, math.max(1000, math.floor(income)), name .. " paid as coins")
end

-- Returns the accessory key that was granted ("" for a duplicate that paid Candy instead) and its item.
local function accessory(player: Player, rng: BossLootMath.Rng): (string, Item)
	local key = BossLootMath.WeightedKey(Config.BossLoot.AccessoryWeights, rng)
	local info = key and Config.SpeedAccessories[key]
	local profile = DataService.Get(player)
	if not key or not info or not profile or type(profile.Data.SpeedAccessories) ~= "table" then
		return "", candy(player, Config.BossLoot.AccessoryCandy)
	end
	if profile.Data.SpeedAccessories[key] == true then
		local paid = candy(player, Config.BossLoot.AccessoryCandy)
		return "", item("👟", info.Name .. " (duplicate)", "Already owned: " .. paid.Name .. " instead", ACCESSORY_RARITY[key] or "Mythic")
	end
	profile.Data.SpeedAccessories[key] = true
	return key, item("👟", info.Name, string.format("x%.2f run speed - find it under Owned in the shop", info.Multiplier), ACCESSORY_RARITY[key] or "Mythic")
end

-- Rolls and grants the loot for one player. Returns every drop.
function BossLoot.GrantTo(player: Player, share: number, rng: BossLootMath.Rng?): { Item }
	local random = rng or math.random
	local loot = Config.BossLoot
	local drops: { Item } = {}
	local count = BossLootMath.RollCount(share, loot, random)
	for _ = 1, count do
		local entry = BossLootMath.Pick(share, loot, random)
		local drop: Item
		if entry.Kind == "Candy" then
			drop = candy(player, entry.Candy)
		elseif entry.Kind == "Coins" then
			local income = MonsterService.GetIncomePerSecond(player) * (entry.Minutes or 0) * 60
			drop = coins(player, math.max(entry.Floor or 0, math.floor(income)), "From the Pumpkin Titan's hoard")
		elseif entry.Kind == "Egg" then
			drop = egg(player, entry.Egg)
			if entry.Egg == "HalloweenMonster" or entry.Egg == "Secret" then
				MonsterService.Announce("🎁 " .. player.DisplayName .. " won a " .. Config.Eggs[entry.Egg].DisplayName .. " from the Pumpkin Titan!", PURPLE)
			end
		else
			local key, dropped = accessory(player, random)
			drop = dropped
			if key ~= "" then
				MonsterService.Announce("🎁 " .. player.DisplayName .. " won " .. Config.SpeedAccessories[key].Name .. " from the Pumpkin Titan!", PURPLE)
			end
		end
		table.insert(drops, drop)
	end
	return drops
end

-- Every contributor with at least Config.BossLoot.MinShare of the boss's max HP gets loot.
function BossLoot.Distribute(contributors: { Contributor }, maxHealth: number)
	local ranked = table.clone(contributors)
	table.sort(ranked, function(a, b)
		return a.Damage > b.Damage
	end)
	for rank, contributor in ranked do
		local player = contributor.Player
		if player.Parent and DataService.Get(player) then
			local share = math.clamp(contributor.Damage / math.max(1, maxHealth), 0, 1)
			local drops = BossLoot.GrantTo(player, share)
			remotes.BossLoot:FireClient(player, {
				Share = share,
				Damage = contributor.Damage,
				Rank = rank,
				Fighters = #ranked,
				Needed = Config.BossLoot.MinShare,
				Items = drops,
			})
			MonsterService.PushState(player)
			task.spawn(DataService.Save, player)
		end
	end
end

return BossLoot
