-- Real server/Marketplace modules, deterministic clock, no live account or purchase.
local fs, r, luau = require("@lune/fs"), require("@lune/roblox"), require("@lune/luau")
local globals = getfenv()
local function environment(extra)
	local result = extra or {}
	for key, value in globals do if result[key] == nil then result[key] = value end end
	for key, value in r do if result[key] == nil then result[key] = value end end
	return result
end
local function signal()
	local listeners = {}
	return { Connect = function(_, fn) table.insert(listeners, fn) end,
		Fire = function(_, ...) for _, fn in listeners do fn(...) end end }
end
local function monster(id, slot)
	return { Id = id, Slot = slot or 1, Species = "Grassland_1", Hunger = 0, Happiness = 0, Level = 1, Xp = 0 }
end
local function harness(id, owner, studio)
	local h = { ProfileAvailable = true, PlotAvailable = true, Online = true, Owner = owner, Messages = {}, Prompts = {} }
	local now, jobs = 0, {}
	local clock = table.clone(os)
	clock.clock = function() return now end
	clock.time = function() return 1700000000 + math.floor(now) end
	local function resume(job, ...)
		local ok, wait = coroutine.resume(job.Thread, ...)
		assert(ok, tostring(wait)); job.Wake = now + (wait or 0)
	end
	local function spawn(fn, ...)
		local job = { Thread = coroutine.create(fn), Wake = now }
		resume(job, ...)
		if coroutine.status(job.Thread) ~= "dead" then table.insert(jobs, job) end
	end
	local fakeTask = { spawn = spawn, wait = function(seconds) return coroutine.yield(seconds or 0) end,
		delay = function(seconds, fn) spawn(function() coroutine.yield(seconds); fn() end) end }
	local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = environment() })()
	config.Gamepasses.AutoMinigame.Id = id
	local mathModule = luau.load(fs.readFile("src/shared/MonsterMath.luau"), { environment = environment({
		script = { Parent = { Config = "Config" } }, require = function() return config end }) })()
	local humanoid = { Health = 100 }
	local character = { FindFirstChildOfClass = function(_, class) return if class == "Humanoid" then humanoid else nil end,
		FindFirstChild = function() return nil end }
	local player = { UserId = 1, Character = character }
	local profile = { Data = { Monsters = {}, Coins = 1000, PendingCoins = 0, Eggs = {}, SlotUpgrades = 0, SpeedBoostUntil = 0 } }
	local plot = { LockedUntil = 0, LockCooldownUntil = 0 }
	local data = { Get = function(p) return if p == player and h.ProfileAvailable then profile else nil end,
		TrySpend = function() return false end, AddCoins = function(_, amount) profile.Data.Coins += amount end, Save = function() return true end }
	local plots = { GetPlot = function() return if h.PlotAvailable then plot else nil end,
		SetPending = function() end, SetLockVisual = function() end, SetUpgradeLabel = function() end,
		UpdateMonster = function() end, SetUnlockedSlots = function() end }
	local market = { PromptGamePassPurchaseFinished = signal(),
		UserOwnsGamePassAsync = function(_, _, passId) return h.Owner == true and passId == id and id > 0 end,
		PromptGamePassPurchase = function(_, _, passId) table.insert(h.Prompts, passId) end }
	local services = { Players = { GetPlayers = function() return if h.Online then { player } else {} end },
		ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } }, MarketplaceService = market,
		RunService = { IsStudio = function() return studio == true end } }
	local modules = { Config = config, MonsterMath = mathModule, DataService = data, PlotService = plots,
		CharacterService = {}, FollowerService = { Init = function() end, CleanupPlayer = function() end }, CombatService = {} }
	local parent = { MonsterService = "MonsterService" }
	for name in modules do parent[name] = name end
	local function load(path)
		return luau.load(fs.readFile(path), { environment = environment({ game = { GetService = function(_, name) return assert(services[name], name) end },
			script = { Parent = parent }, require = function(name) return assert(modules[name], name) end, task = fakeTask, os = clock }) })()
	end
	local service = load("src/server/MonsterService.luau")
	modules.MonsterService = service
	service.PushState = function() end
	service.Notify = function() end
	local monetization = load("src/server/MonetizationService.luau")
	service.HasPass = monetization.HasPass
	local remotes = {}
	for _, name in { "ToggleFollower", "BuyEgg", "FeedMonster", "MiniGameStart", "MiniGameCatch", "MiniGameFinish", "MiniGameState",
		"BuyAccessory", "BuySpeedAccessory", "EquipAccessory", "EquipSpeedAccessory", "SellMonster", "BuyUpgrade", "BuyPass", "BuyWeapon", "EquipWeapon", "BuyProduct" } do
		remotes[name] = { OnServerEvent = signal(), FireClient = function(_, _, info) table.insert(h.Messages, info) end }
	end
	service.Init(remotes); monetization.Init(remotes); monetization.SetupPlayer(player)
	h.Config, h.Profile, h.Player, h.Service, h.Monetization, h.Humanoid = config, profile, player, service, monetization, humanoid
	h.Character, h.Market = character, market
	h.Advance = function(time)
		assert(time >= now); now = time
		for _, job in table.clone(jobs) do if coroutine.status(job.Thread) ~= "dead" and job.Wake <= now then resume(job) end end
	end
	h.Buy = function() remotes.BuyPass.OnServerEvent:Fire(player, "AutoMinigame") end
	h.Start = function(mid, gameName) remotes.MiniGameStart.OnServerEvent:Fire(player, mid, gameName or "Catch") end
	h.Catch = function() remotes.MiniGameCatch.OnServerEvent:Fire(player, 1000000) end
	h.Finish = function() remotes.MiniGameFinish.OnServerEvent:Fire(player, 1000000) end
	h.Xp = function(m)
		local total = m.Xp
		for level = 1, m.Level - 1 do total += config.XpForLevel(level) end
		return total
	end
	return h
end
local checks = 0
local function check(ok, message) checks += 1; assert(ok, message) end
local function add(h, id, slot) local m = monster(id or "first", slot); h.Profile.Data.Monsters[m.Id] = m; return m end
local function catchXp(h) local s = h.Config.MiniGames.Catch; return math.min(s.MaxCatches, math.floor(s.Duration / s.MinCatchInterval)) * s.XpPerCatch end
local declared = luau.load(fs.readFile("src/shared/Config.luau"), { environment = environment() })()
check(declared.Gamepasses.AutoMinigame.Id == 2044616622 and declared.Gamepasses.AutoMinigame.Price == 99, "Actual pass ID/price differs from the approved offer")

for _, studio in { false, true } do
	local h = harness(0, false, studio); local m = add(h)
	h.Profile.Data.Gamepasses = { AutoMinigame = true }; h.Buy(); h.Advance(1); h.Advance(100)
	check(not h.Monetization.HasPass(h.Player, "AutoMinigame") and h.Xp(m) == 0, "Unconfigured/stored entitlement granted auto XP")
	check(#h.Prompts == 0, "Invalid pass ID reached Marketplace")
end
local h = harness(123456789, false, false); local m = add(h)
check(h.Config.Gamepasses.AutoMinigame.Price == 99, "Auto Minigame price must be 99 Robux")
h.Buy(); h.Advance(1); h.Advance(13)
check(h.Prompts[1] == 123456789 and h.Xp(m) == 0, "Prompt granted ownership without confirmed purchase")
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 123456789, false); h.Advance(14)
check(h.Xp(m) == 0, "Canceled purchase granted XP")
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 123456789, true); h.Advance(15); h.Advance(26)
check(h.Xp(m) == 0, "Auto Catch finished before the normal duration")
h.Catch(); h.Finish(); h.Advance(27)
check(h.Xp(m) == catchXp(h), "Auto round trusts client score or does not use normal capped Catch XP")
check(m.Happiness == h.Config.MiniGames.Happiness, "Auto reward differs from normal happiness")
check(#h.Messages == 0, "Automatic session opened/replaced the manual minigame HUD")
h.Advance(28); h.Advance(34)
check(h.Xp(m) == catchXp(h), "Auto round ignored shared per-monster cooldown")
h.Advance(35); h.Advance(49)
check(h.Xp(m) == catchXp(h), "Auto Run finished early")
h.Advance(50)
check(h.Xp(m) == catchXp(h) + h.Config.MiniGames.Run.MaxXp, "Automatic play does not alternate normal Run rewards")
local before = h.Xp(m); h.Advance(51); h.Advance(10000)
check(h.Xp(m) == before, "Cooldown/stall replayed an unstarted historical round")
h.Advance(10001); h.Advance(20000)
check(h.Xp(m) - before == catchXp(h), "Stall awarded multiple historical games")

-- One active session and a stable rotation keep large inventories fair.
h = harness(123456789, true, false)
local first, second = add(h, "a", 1), add(h, "b", 2)
h.Advance(1); h.Start(second.Id); h.Catch(); h.Finish(); h.Advance(13)
check(h.Xp(first) == catchXp(h) and h.Xp(second) == 0, "Auto session affected multiple monsters at once")
h.Advance(14); h.Advance(29)
check(h.Xp(second) == catchXp(h), "Automatic play starved the next placed monster")
h.Advance(30); h.Advance(45); h.Advance(46); h.Advance(61)
check(h.Xp(first) == catchXp(h) + h.Config.MiniGames.Run.MaxXp and h.Xp(second) == h.Xp(first), "Even-sized inventories did not alternate games fairly per monster")

for _, reason in { "dead", "respawn", "benched", "moved", "carried", "trading", "removed", "replaced", "profile", "plot", "entitlement" } do
	h = harness(123456789, true, false); m = add(h); h.Advance(1)
	if reason == "dead" then h.Humanoid.Health = 0
	elseif reason == "respawn" then h.Player.Character = { FindFirstChildOfClass = function() return { Health = 100 } end }
	elseif reason == "benched" then m.Slot = 0
	elseif reason == "moved" then m.Slot = 2
	elseif reason == "carried" then h.Service.Carried[h.Player] = { first = true }
	elseif reason == "trading" then h.Service.Trading[h.Player] = { first = true }
	elseif reason == "removed" then h.Profile.Data.Monsters.first = nil
	elseif reason == "replaced" then h.Profile.Data.Monsters.first = monster("first")
	elseif reason == "profile" then h.ProfileAvailable = false
	elseif reason == "plot" then h.PlotAvailable = false
	elseif reason == "entitlement" then h.Monetization.CleanupPlayer(h.Player) end
	h.Advance(13)
	check(h.Xp(m) == 0, reason .. " monster received automatic XP")
end
h = harness(123456789, true, false); m = add(h); h.Advance(1)
h.Service.CleanupPlayer(h.Player); h.Monetization.CleanupPlayer(h.Player); h.Online = false; h.Advance(10000)
check(h.Xp(m) == 0, "Disconnected player received offline XP")
h = harness(123456789, true, false); m = add(h); h.Advance(1)
h.PlotAvailable = false; h.Advance(2); h.PlotAvailable = true; h.Advance(1000)
check(h.Xp(m) == 0, "Restoring a plot paid a stale canceled game")

-- Manual Catch remains usable without buying the pass and shares its cooldown.
h = harness(123456789, false, false); m = add(h); h.Advance(25); h.Start(m.Id); h.Catch()
h.Advance(26); h.Catch(); h.Finish()
check(h.Xp(m) == 0, "Manual game accepted an early finish")
h.Advance(37); h.Finish()
check(h.Xp(m) == h.Config.MiniGames.Catch.XpPerCatch * 2, "Manual Catch behavior changed")
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 123456789, true)
h.Advance(38); h.Advance(44)
check(h.Xp(m) == h.Config.MiniGames.Catch.XpPerCatch * 2, "Automation bypassed the manual cooldown")
h.Advance(45); h.Advance(57)
check(h.Xp(m) == h.Config.MiniGames.Catch.XpPerCatch * 2 + catchXp(h), "Automatic play did not resume after manual cooldown")

h = harness(123456789, false, false); m = add(h); h.Advance(25); h.Start(m.Id); h.Catch()
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 123456789, true); h.Advance(26); h.Catch()
h.Advance(37); h.Finish()
check(h.Xp(m) == h.Config.MiniGames.Catch.XpPerCatch * 2, "Purchasing auto play replaced an in-progress manual game")
h = harness(123456789, true, false); m = add(h); m.Level = h.Config.MaxLevel; h.Advance(1); h.Advance(13)
check(m.Xp == 0 and m.Level == h.Config.MaxLevel, "Automatic rewards exceeded the maximum level")
print(string.format("PASS: %d automatic minigame checks", checks))
