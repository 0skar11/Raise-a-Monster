-- Pumpkin Titan attack kit: config sanity and wiring/source contracts (the live fight needs a Studio playtest).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function environment()
	local env = table.clone(getfenv())
	for key, value in r do env[key] = value end
	return env
end
local Config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = environment() })()
local A = Config.Boss.Attacks
local server = fs.readFile("src/server/BossAttacks.luau")
local client = fs.readFile("src/client/BossFx.luau")
local events = fs.readFile("src/server/EventService.luau")

check(#A.PhaseAt == 3 and A.PhaseAt[1] > A.PhaseAt[2] and A.PhaseAt[2] > A.PhaseAt[3], "Three phase thresholds, falling")
for index = 2, 4 do
	check(A.DamageScale[index] > A.DamageScale[index - 1], "Damage rises every phase")
	check(A.WindupScale[index] < A.WindupScale[index - 1], "Telegraphs shorten every phase")
	check(A.Cooldown[index] < A.Cooldown[index - 1], "Cooldowns shorten every phase")
	check(A.ChainChance[index] >= A.ChainChance[index - 1], "Chaining gets likelier every phase")
end
for _, move in { "Sweep", "Slam", "Bombs", "Vine", "Pulse", "Rain" } do
	check(server:find('"' .. move .. '"', 1, true), move .. " is part of the kit")
end
check(server:find("MinPhase = 4", 1, true) and server:find("MinPhase = 3", 1, true) and server:find("MinPhase = 2", 1, true), "Harder moves unlock in later phases")
check(server:find("airborne(candidate, ctx.Ground)", 1, true), "Jumping dodges the ground waves")
check(server:find("ctx.State.VulnerableUntil", 1, true) and events:find("PulseExposedBonus", 1, true), "The chest is exposed during Heart Pulse")
check(server:find("pcall(runMoveUnsafe", 1, true), "A failing move cannot stop the fight")
check(events:find("BossAttacks.Run", 1, true) and events:find('"Death"', 1, true), "EventService runs the kit and fires the death effect")
for _, kind in { "Sweep", "Slam", "Bomb", "BombFire", "Vine", "VineGrabbed", "HeartPulse", "RainStart", "Rain", "Rage", "Phase", "Death" } do
	check(client:find("handlers." .. kind .. " = function", 1, true), "The client draws " .. kind)
end
check(fs.readFile("src/shared/Remotes.luau"):find('"BossFx"', 1, true), "The BossFx remote exists")
check(fs.readFile("src/client/init.client.luau"):find("BossFx.Start", 1, true), "The client starts BossFx")
-- balance: 5M health, and every main hit kills an unarmored (100 HP) player in two
check(Config.Boss.MinHealth == 5000000 and Config.Boss.HealthPerPlayer == 0, "The boss has a fixed 5 million health")
for _, move in { "SweepDamage", "SlamDamage", "BombDamage", "VineDamage", "PulseDamage", "RainDamage" } do
	check(Config.Boss.Damage * A[move] * A.DamageScale[1] >= Config.PlayerBaseHealth / 2, move .. " takes an unarmored player down in two hits")
end
-- presentation: its own animation, a cinematic entrance, safe zones shaped like the map's carved pumpkin
check(events:find('SetAttribute("Procedural", false)', 1, true) and client:find("ANIMS.Slam", 1, true) and client:find("ANIMS.Throw", 1, true), "The client animates the boss, timed to each attack")
check(client:find("handlers.Entrance = function", 1, true) and events:find('"Entrance"', 1, true) and events:find("IntroUntil", 1, true), "The boss has a cinematic entrance and cannot be hurt during it")
check(client:find('require(ReplicatedStorage.Shared.PumpkinVisual)', 1, true) and client:find("local lantern = carvedPumpkin(", 1, true), "Safe zones use the shared carved pumpkin")
-- entrance beats (from the "why boss fights feel epic" reel): path crumbles, build-up, slow reveal, name card, boss bar, roar
check(Config.Boss.IntroBuildUp > 0 and Config.Boss.IntroRise > Config.Boss.IntroBuildUp and Config.Boss.IntroRoar > 0, "The entrance has a build-up, a slow rise and a roar")
check(client:find("THE PATH BEHIND YOU CRUMBLES", 1, true) and client:find("showBossBar(part", 1, true) and client:find("setBossMusic(true)", 1, true), "Entrance: crumbling path, boss bar and heavy music")
check(client:find('"MaxHealth"', 1, true) and events:find('SetAttribute("MaxHealth"', 1, true), "The boss health is shared with clients for the big bar")
print(("PASS: boss attack kit (%d checks)"):format(checks))
