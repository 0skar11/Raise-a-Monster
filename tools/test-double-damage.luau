-- Execute the production swing with real server ownership and offline Marketplace.
-- Run: lune run tools/test-double-damage.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local setup = fs.readFile("tools/test-auto-feeder.luau")
setup = setup:sub(1, assert(setup:find("local assertions = 0", 1, true)) - 1)
local harness = luau.load(setup .. "\nreturn harness", { injectGlobals = true })()
local h = harness(false, 9001, false)
-- Fixture only: never configure a made-up production pass ID.
local passId = 9009
h.Config.Gamepasses.DoubleDamage.Id = passId
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local source = fs.readFile("src/server/CombatService.luau")
local first = assert(source:find("local function swing(", 1, true))
local last = assert(source:find("\n-- Templates extend", first, true))
local swingSource = source:sub(first, last - 1)
local now, critical, safe, damage = 100, false, false, nil
local player = h.Player
player.Character = {}
local victim = { Character = {} }
local tool = { Parent = player.Character }
function tool:GetAttribute() return player.UserId end
function tool:FindFirstChild() return nil end
local root = { Position = r.Vector3.zero }
local victimRoot = { Position = r.Vector3.new(1, 0, 0) }
local humanoid = { Health = 100 }
local victimHumanoid = { Health = 100, TakeDamage = function(_, amount) damage = amount end }
local target = { Part = { Parent = true, Position = r.Vector3.zero }, Radius = 1, OnHit = function(_, amount) damage = amount end }
local targets = { [target] = true }
local quiet = { FireClient = function() end }
local monsterService = {
	HasPass = h.Monetization.HasPass,
	GetAttackDamage = function() return 40 end,
	GetFollowerDamageBonus = function() return 0 end,
}
local swing = luau.load("local lastSwing, tags = {}, {}\n" .. swingSource .. "\nreturn swing", {
	environment = {
		Config = h.Config, MonsterService = monsterService, targets = targets,
		os = { clock = function() return now end },
		math = { huge = math.huge, floor = math.floor, random = function() return if critical then 0 else 1 end },
		Vector3 = r.Vector3, Color3 = r.Color3,
		getRoot = function(p) return if p == player then root else victimRoot end,
		getHumanoid = function(p) return if p == player then humanoid else victimHumanoid end,
		flatDistance = function(a, b) return (a - b).Magnitude end,
		playSound = function() end, animateSwing = function() end, spawnHitVfx = function() end,
		CombatService = { IsInSafeZone = function() return safe end },
		Players = { GetPlayers = function() return { player, victim } end },
		remotes = { HitFeedback = quiet, PlayerHurt = quiet },
	},
})()
local function hit(multiplier, pvp)
	now += 1
	damage = nil
	targets[target] = if pvp then nil else true
	swing(player, tool, multiplier, 0, 20)
	return damage
end
local weapons = { Bat = { DamageMultiplier = 1 } }
for name, stats in h.Config.WeaponStats do weapons[name] = stats end
for name, stats in weapons do
	check(hit(stats.DamageMultiplier, false) == 40 * stats.DamageMultiplier, name .. " unowned PvE damage unchanged")
	check(hit(stats.DamageMultiplier, true) == 20 * stats.DamageMultiplier, name .. " unowned PvP damage unchanged")
end
h.Market:PromptGamePassPurchase(player, passId)
check(not h.Monetization.HasPass(player, "DoubleDamage") and hit(1, false) == 40, "Opening a prompt cannot grant damage")
h.Market.PromptGamePassPurchaseFinished:Fire(player, passId, false)
check(hit(1, false) == 40, "Canceled purchase cannot grant damage")
h.Market.PromptGamePassPurchaseFinished:Fire(player, passId, true)
for name, stats in weapons do
	check(hit(stats.DamageMultiplier, false) == 80 * stats.DamageMultiplier, name .. " purchase immediately doubles PvE damage")
	check(hit(stats.DamageMultiplier, true) == 40 * stats.DamageMultiplier, name .. " purchase immediately doubles PvP damage")
end
h.Market.PromptGamePassPurchaseFinished:Fire(player, passId, true)
check(hit(1, false) == 80, "Duplicate confirmation cannot stack damage")
critical = true
check(hit(4, false) == math.floor(40 * 4 * 2 * h.Config.Combat.CritMultiplier), "Critical and weapon multipliers stack once")
critical = false
safe = true
check(hit(1, true) == nil, "Damage pass retains PvP safe zones")
safe = false
hit(1, false)
damage = nil
swing(player, tool, 1, 0, 20)
check(damage == nil, "Damage pass retains swing cooldown")
tool.Parent = {}
check(hit(1, false) == nil, "Damage pass cannot activate an unequipped weapon")
tool.Parent = player.Character
h.Monetization.CleanupPlayer(player)
check(hit(1, false) == 40, "Session cleanup removes damage entitlement")
h.Market.UserOwnsGamePassAsync = function(_, _, id) return id == passId end
h.Monetization.SetupPlayer(player)
check(hit(1, false) == 80, "Rejoin ownership verification restores damage entitlement")
h.Monetization.CleanupPlayer(player)
h.Market.UserOwnsGamePassAsync = function() error("Marketplace unavailable") end
h.Monetization.SetupPlayer(player)
check(hit(1, false) == 40, "Unavailable ownership verification fails closed")
print(string.format("PASS: %d x2 damage checks (all weapons, PvE/PvP, purchase, rejoin, crits, safeguards)", checks))
