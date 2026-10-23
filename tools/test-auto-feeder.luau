-- Offline behavioral tests: real feeding/entitlement modules, fake clock and Marketplace.
-- No Roblox account, purchase, live currency, or persisted ownership is touched.
local fs = require('@lune/fs')
local r = require('@lune/roblox')
local luau = require('@lune/luau')
local globals = getfenv()

local function environment(extra)
	local result = extra or {}
	for key, value in globals do if result[key] == nil then result[key] = value end end
	for key, value in r do if result[key] == nil then result[key] = value end end
	return result
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback) table.insert(listeners, callback) end,
		Fire = function(_, ...) for _, callback in listeners do callback(...) end end,
	}
end

local function newMonster(id, hunger, level)
	return {Id = id, Species = 'Grassland_1', Hunger = hunger or 20, Happiness = 0,
		Level = level or 1, Xp = 0, Slot = 1, Mutation = nil}
end

local function harness(studio, passId, ownsPass)
	local clock, jobs = 0, {}
	local clockOs = table.clone(os)
	clockOs.clock = function() return clock end
	clockOs.time = function() return 1700000000 + math.floor(clock) end
	local function resume(job, ...)
		local ok, delay = coroutine.resume(job.Thread, ...)
		assert(ok, tostring(delay))
		job.Wake = clock + (delay or 0)
	end
	local fakeTask = {
		wait = function(delay) return coroutine.yield(delay or 0) end,
		spawn = function(callback, ...)
			local job = {Thread = coroutine.create(callback), Wake = clock}
			resume(job, ...)
			if coroutine.status(job.Thread) ~= 'dead' then table.insert(jobs, job) end
		end,
		delay = function() end,
	}
	local config = luau.load(fs.readFile('src/shared/Config.luau'), {environment = environment()})()
	-- Isolate feeding rewards; elapsed natural growth has its own regression suite.
	config.AdultGrowthSeconds = math.huge
	config.Gamepasses.AutoFeeder.Id = passId or 0
	local mathModule = luau.load(fs.readFile('src/shared/MonsterMath.luau'), {environment = environment({
		script = {Parent = {Config = 'Config'}}, require = function() return config end,
	})})()
	local player = {UserId = 1}
	local stranger = {UserId = 2}
	local profile = {Data = {Coins = 1000, PendingCoins = 0, Monsters = {}, Eggs = {}, SpeedBoostUntil = 0}}
	local foreignProfile = {Data = {Coins = 1000, PendingCoins = 0, Monsters = {}, Eggs = {}, SpeedBoostUntil = 0}}
	local spendCount, evolutions, notifications = 0, 0, {}
	local data = {
		Get = function(p) return if p == player then profile elseif p == stranger then foreignProfile else nil end,
		TrySpend = function(p, amount)
			local target = if p == player then profile else foreignProfile
			if target.Data.Coins < amount then return false end
			target.Data.Coins -= amount
			spendCount += 1
			return true
		end,
		AddCoins = function(p, amount) if p == player then profile.Data.Coins += amount end end,
		Save = function() return true end,
	}
	local plot = {LockedUntil = 0, LockCooldownUntil = 0}
	local plotService = {
		GetPlot = function() return plot end,
		SetPending = function() end,
		SetLockVisual = function() end,
		SetUpgradeLabel = function() end,
		UpdateMonster = function(_, _, evolved) if evolved then evolutions += 1 end end,
		SetUnlockedSlots = function() end,
		SetCollectorEnabled = function(_, enabled) plot.CollectorEnabled = enabled end,
	}
	local follower = {Init = function() end, CleanupPlayer = function() end}
	local modules = {Config = config, MonsterMath = mathModule, DataService = data,
		PlotService = plotService, CharacterService = {}, FollowerService = follower, CombatService = {}}
	local market = {PromptGamePassPurchaseFinished = signal(), Prompts = {}}
	market.UserOwnsGamePassAsync = function(_, _, id)
		assert(id ~= 0, 'An invalid pass ID reached Marketplace ownership verification')
		return ownsPass == true and id == config.Gamepasses.AutoFeeder.Id
	end
	market.PromptGamePassPurchase = function(_, _, id) table.insert(market.Prompts, id) end
	local services = {
		Players = {GetPlayers = function() return {player} end},
		ReplicatedStorage = {Shared = {Config = 'Config', MonsterMath = 'MonsterMath'}},
		MarketplaceService = market, RunService = {IsStudio = function() return studio == true end},
	}
	local parent = {}
	for name in modules do parent[name] = name end
	parent.MonsterService = 'MonsterService'
	local function load(path)
		return luau.load(fs.readFile(path), {environment = environment({
			game = {GetService = function(_, name) return assert(services[name], name) end},
			script = {Parent = parent}, require = function(name) return assert(modules[name], name) end,
			task = fakeTask, os = clockOs,
		})})()
	end
	local monsterService = load('src/server/MonsterService.luau')
	modules.MonsterService = monsterService
	monsterService.PushState = function() end
	monsterService.Notify = function(_, text) table.insert(notifications, text) end
	local monetization = load('src/server/MonetizationService.luau')
	monsterService.HasPass = monetization.HasPass
	local remotes = {}
	for _, name in {'ToggleFollower', 'BuyEgg', 'FeedMonster', 'MiniGameStart', 'MiniGameCatch',
		'MiniGameFinish', 'BuyAccessory', 'BuySpeedAccessory', 'EquipAccessory', 'EquipSpeedAccessory',
		'SellMonster', 'BuyUpgrade', 'BuyPass', 'BuyWeapon', 'EquipWeapon', 'BuyProduct'} do
		remotes[name] = {OnServerEvent = signal()}
	end
	monsterService.Init(remotes)
	monetization.Init(remotes)
	monetization.SetupPlayer(player)
	local result = {Config = config, Math = mathModule, MonsterService = monsterService, Monetization = monetization,
		Player = player, Stranger = stranger, Profile = profile, ForeignProfile = foreignProfile, Market = market, Plot = plot}
	result.Advance = function(time)
		assert(time >= clock, 'Clock cannot run backwards')
		clock = time
		-- Resume each overdue loop once, so a stall never replays a backlog of ticks.
		for _, job in table.clone(jobs) do
			if coroutine.status(job.Thread) ~= 'dead' and job.Wake <= clock then resume(job) end
		end
	end
	result.Buy = function() remotes.BuyPass.OnServerEvent:Fire(player, 'AutoFeeder') end
	result.ManualFeed = function(id, claimedXp) remotes.FeedMonster.OnServerEvent:Fire(player, id, claimedXp) end
	result.Spends = function() return spendCount end
	result.Evolutions = function() return evolutions end
	return result
end

local function earnedXp(config, monster)
	local total = monster.Xp
	for level = 1, monster.Level - 1 do total += config.XpForLevel(level) end
	return total
end

local assertions = 0
local function check(condition, message) assertions += 1; assert(condition, message) end

-- Id=0 remains a temporary fixture for production-inactive and free-Studio paths.
local h = harness(false, 0, false)
local monster = newMonster('owned')
h.Profile.Data.Monsters.owned = monster
h.Profile.Data.Gamepasses = {AutoFeeder = true}
h.Buy()
h.Advance(1)
check(not h.Monetization.HasPass(h.Player, 'AutoFeeder'), 'Production granted an unconfigured pass')
check(h.Spends() == 0 and monster.Xp == 0, 'Unowned pass auto-fed a monster')
check(#h.Market.Prompts == 0, 'Invalid pass ID opened a purchase prompt')
check(h.Config.Gamepasses.AutoFeeder.Price == 99, 'Pass is not priced at 99 Robux')
h.ManualFeed('owned', 1000000000)
check(h.Spends() == 1 and monster.Xp == h.Config.Food.Xp, 'Manual feed trusts claimed XP or requires a pass')

-- The existing explicit Studio purchase grants session entitlement only.
h = harness(true, 0, false)
monster = newMonster('owned')
h.Profile.Data.Monsters.owned = monster
h.Buy()
check(h.Monetization.HasPass(h.Player, 'AutoFeeder'), 'Explicit Studio test purchase did not grant the pass')
h.Advance(1)
check(h.Spends() == 1 and monster.Xp == h.Config.Food.Xp, 'Owned pass did not feed normally')
h.Monetization.CleanupPlayer(h.Player)
check(not h.Monetization.HasPass(h.Player, 'AutoFeeder'), 'Studio entitlement survived session cleanup')

-- The production pass uses the configured real ID and still waits for Marketplace confirmation.
h = harness(false, 2036452299, false)
check(h.Config.Gamepasses.AutoFeeder.Id == 2036452299, 'Auto-Feeder is configured with its real pass ID')
monster = newMonster('owned')
h.Profile.Data.Monsters.owned = monster
h.Buy()
check(h.Market.Prompts[1] == 2036452299 and not h.Monetization.HasPass(h.Player, 'AutoFeeder'), 'Prompt alone grants ownership')
h.Advance(1)
check(h.Spends() == 0, 'Unconfirmed purchase auto-fed')
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 2036452299, true)
h.Advance(31)
check(h.Spends() == 1 and monster.Xp == h.Config.Food.Xp, 'Confirmed production pass did not auto-feed')

-- Shared manual/auto cooldown, elapsed-time interval, and no catch-up XP after a stall.
h = harness(false, 2036452299, true)
monster = newMonster('owned')
h.Profile.Data.Monsters.owned = monster
h.Advance(1)
h.ManualFeed('owned')
h.ManualFeed('owned')
check(h.Spends() == 1 and monster.Xp == 15, 'Same-frame manual/auto feeds granted duplicate XP')
monster.Hunger = 20
h.Advance(30)
check(h.Spends() == 1 and monster.Xp == 15, 'Auto-feeder ignored its 30-second interval')
h.Advance(31)
check(h.Spends() == 2 and monster.Xp == 30, 'Auto-feeder did not run at the next interval')
monster.Hunger = 20
local beforeXp = earnedXp(h.Config, monster)
h.Advance(10000)
check(h.Spends() == 3 and earnedXp(h.Config, monster) - beforeXp == h.Config.Food.Xp, 'Stall replayed food/XP catch-up')

-- Full/above-threshold, carried, sold, foreign, and unaffordable monsters get no feeding XP.
for _, scenario in {'full', 'above-threshold', 'carried', 'sold', 'foreign', 'poor'} do
 h = harness(false, 2036452299, true)
	monster = newMonster('owned', if scenario == 'full' then 100 elseif scenario == 'above-threshold' then 71 else 20)
	h.Profile.Data.Monsters.owned = monster
	if scenario == 'carried' then h.MonsterService.Carried[h.Player] = {owned = true} end
	if scenario == 'sold' then h.Profile.Data.Monsters.owned = nil end
	if scenario == 'foreign' then h.Profile.Data.Monsters.owned = nil; h.ForeignProfile.Data.Monsters.owned = monster end
	if scenario == 'poor' then h.Profile.Data.Coins = h.Config.Food.Cost - 1 end
	h.Advance(1)
	check(h.Spends() == 0 and monster.Xp == 0, scenario..' monster received a paid feed or XP')
	if scenario ~= 'above-threshold' then
		h.ManualFeed('owned')
		check(h.Spends() == 0 and monster.Xp == 0, scenario..' monster accepted a stale/manual request')
	end
end

h = harness(false, 2036452299, true)
monster = newMonster('threshold', h.Config.AutoFeeder.Threshold)
h.Profile.Data.Monsters.threshold = monster
h.Advance(1)
check(h.Spends() == 1 and monster.Xp == h.Config.Food.Xp, 'Threshold hunger was not eligible')

-- Separate monsters each consume exactly one normal food cost; no cross-monster XP.
h = harness(false, 2036452299, true)
local first, second, full = newMonster('first'), newMonster('second', 30), newMonster('full', 100)
h.Profile.Data.Monsters = {first = first, second = second, full = full}
h.Profile.Data.Coins = h.Config.Food.Cost * 2
h.Advance(1)
check(h.Spends() == 2 and h.Profile.Data.Coins == 0, 'Individual feeds did not debit their normal food costs')
check(first.Xp == 15 and second.Xp == 15 and full.Xp == 0, 'XP leaked between individual monsters')

-- Evolution uses the same normal feeding XP path, once, and charges the pre-feed stage.
h = harness(false, 2036452299, true)
monster = newMonster('growing', 20, 9)
monster.Xp = h.Config.XpForLevel(9) - 10
h.Profile.Data.Monsters.growing = monster
local coins = h.Profile.Data.Coins
h.Advance(1)
check(monster.Level == 10 and monster.Xp == 5 and h.Evolutions() == 1, 'Feeding evolution/XP was skipped or doubled')
check(coins - h.Profile.Data.Coins == h.Config.Food.Cost, 'Evolution charged the wrong food stage')
h.ManualFeed('growing')
check(h.Evolutions() == 1 and monster.Xp == 5, 'Repeated request evolved or rewarded twice')

-- Session timestamps are cleared; a new verified session does not inherit the old timer.
h = harness(false, 2036452299, true)
monster = newMonster('owned')
h.Profile.Data.Monsters.owned = monster
h.Advance(1)
h.MonsterService.CleanupPlayer(h.Player)
h.Monetization.CleanupPlayer(h.Player)
h.Monetization.SetupPlayer(h.Player)
monster.Hunger = 20
h.Advance(2)
check(h.Spends() == 2 and monster.Xp == 30, 'Session cleanup retained feeder/cooldown timestamps')

print('PASS Auto-Feeder assertions:', assertions,
	'production/Studio entitlements, coins/ownership/fullness, intervals/stalls, individual XP/evolution, shared cooldown and cleanup')
