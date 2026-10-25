-- Inject the actual MonsterService factory with loadService(environment).
-- No DataStore, live player, wallet, Marketplace call, or Lune dependency.
return function(Config, MonsterMath, loadService)
	local checks = 0
	local function check(value, message) checks += 1; assert(value, message) end
	local function copy(value)
		if type(value) ~= "table" then return value end
		local result = {}
		for key, item in value do result[key] = copy(item) end
		return result
	end
	local now, player, state = 1700009000, { UserId = 90 }, nil
	local species = next(Config.Species)
	local placed = { Id = "placed", Species = species, Level = 1, Xp = 0, Hunger = 0, Happiness = 0, Slot = 1, LastProgressAt = now - 9000 }
	local bench = copy(placed)
	bench.Id, bench.Slot = "bench", 0
	local locked = copy(placed)
	locked.Id, locked.Slot = "locked", Config.BaseSlots + 1
	local profile = { SessionId = "first-session", Data = {
		Coins = 50, PendingCoins = 0.25, TotalEarned = 0, SlotUpgrades = 0, LockUpgrades = 0,
		IncomeMultiplier = 2, IncomeUnlockedSlots = Config.BaseSlots,
		Monsters = { placed = placed, bench = bench, locked = locked }, Eggs = {}, Stats = {},
		Accessories = {}, SpeedAccessories = {}, Weapons = { Bat = true }, EquippedWeapon = "Bat",
	} }
	local jobs = {}
	local noop = function() end
	local data = {
		Get = function() return profile end, NormalizeMonsterSlots = noop, QueueSave = noop,
		AddCoins = function(_, amount) profile.Data.Coins += amount; profile.Data.TotalEarned += amount end,
	}
	local plot = { GetPlot = function() return { LockedUntil = 0, LockCooldownUntil = 0 } end,
		SetUnlockedSlots = noop, RenderMonster = noop, RenderEgg = noop,
		SetPending = noop, SetUpgradeLabel = noop, UpdateMonster = noop, SetLockVisual = noop }
	local followers = { Init = noop, CleanupPlayer = noop, GetIds = function() return {} end,
		GetMinLevel = function() return 25 end, GetDamageBonus = function() return 0 end, IsEligible = function() return false end }
	local modules = { Config = Config, MonsterMath = MonsterMath, DataService = data, PlotService = plot,
		FollowerService = followers, CharacterService = { GetSpeedAccessoryMultiplier = function() return 1 end } }
	local parent, shared = {}, { Config = "Config", MonsterMath = "MonsterMath" }
	for name in modules do parent[name] = name end
	local services = { ReplicatedStorage = { Shared = shared }, Players = { GetPlayers = function() return { player } end } }
	local service = loadService({
		game = { GetService = function(_, name) return assert(services[name], name) end }, script = { Parent = parent },
		require = function(name) return assert(modules[name], tostring(name)) end,
		os = { time = function() return now end, clock = function() return now end },
		task = { spawn = function(callback, ...) table.insert(jobs, { Callback = callback, Args = table.pack(...) }) end,
			wait = function() coroutine.yield() end },
	})
	local remotes = setmetatable({}, { __index = function(self, name)
		local remote = { OnServerEvent = { Connect = noop }, FireClient = function(_, _, value) if name == "StateUpdate" then state = value end end }
		rawset(self, name, remote)
		return remote
	end })
	service.Init(remotes)
	-- الأوفلاين بياخد Config.OfflineIncomeShare (20%) بس من الدخل العادي
	local full = MonsterMath.AdvanceProgress(copy(placed), now, true, 2)
	local expected = MonsterMath.AdvanceProgress(copy(placed), now, true, 2 * Config.OfflineIncomeShare)
	check(Config.OfflineIncomeShare == 0.2 and math.abs(expected - full * 0.2) < 0.001, "Offline income is exactly 20% of the normal income")
	service.SetupPlayer(player)
	check(math.abs(profile.Data.PendingCoins - expected - 0.25) < 0.001, "Only saved active slots earn offline income with the saved multiplier")
	check(profile.Data.Coins == 50, "Viewing offline earnings never claims the wallet")
	check(placed.Level == 25 and bench.Level == 25 and locked.Level == 25, "Offline growth also applies to bench and locked slots")
	check(state.OfflineEarnings.SecondsAway == 9000 and math.abs(state.OfflineEarnings.CoinsEarned - expected) < 0.001, "Summary reports exact settled absence and income")
	check(state.OfflineEarnings.MonstersGrown == 3 and state.OfflineEarnings.CollectiblePending == math.floor(profile.Data.PendingCoins), "Summary exposes stage growth and the total claimable balance")
	local summary, pending = state.OfflineEarnings, profile.Data.PendingCoins
	service.SetupPlayer(player)
	service.PushState(player)
	check(profile.Data.PendingCoins == pending and state.OfflineEarnings.Id == summary.Id, "Repeated setup and state updates preserve one summary without credit replay")
	service.Collect(player)
	check(profile.Data.Coins == 50 + math.floor(pending) and math.abs(profile.Data.PendingCoins - pending % 1) < 0.001, "Normal collection claims offline coins and preserves fractional income")
	service.Collect(player)
	check(profile.Data.Coins == 50 + math.floor(pending), "Duplicate collect cannot spend the same earnings twice")
	-- An atomic profile snapshot includes both remaining coins and all consumed clocks.
	local saved = copy(profile.Data)
	service.CleanupPlayer(player)
	profile = { SessionId = "second-session", Data = copy(saved) }
	service.SetupPlayer(player)
	check(profile.Data.Coins == saved.Coins and profile.Data.PendingCoins == saved.PendingCoins and state.OfflineEarnings.CoinsEarned == 0, "Saved same-time rejoin cannot replay credited or claimed earnings")
	check(state.OfflineEarnings.Id ~= summary.Id, "The summary id changes only for a new session")
	-- Existing AutoCollect owners keep their normal next-tick collection behavior.
	service.HasPass = function(_, name) return name == "AutoCollect" end
	profile.Data.PendingCoins = 12.5
	local before = profile.Data.Coins
	local loop = coroutine.create(jobs[1].Callback)
	assert(coroutine.resume(loop))
	now += 1
	assert(coroutine.resume(loop))
	local tick = jobs[#jobs]
	tick.Callback(table.unpack(tick.Args, 1, tick.Args.n))
	check(profile.Data.Coins >= before + 12 and profile.Data.PendingCoins < 1, "Owned AutoCollect still collects settled offline coins through its existing tick")
	return string.format("PASS: %d offline service/claim checks", checks)
end
