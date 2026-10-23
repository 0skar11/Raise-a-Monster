-- Runs actual data, monster and trade modules with deterministic offline services.
-- Run: lune run tools/test-monster-inventory.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
check(pcall(luau.compile, fs.readFile("src/client/MonsterInventory.luau")), "Client inventory compiles")
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
local function signal()
	local listeners = {}
	return { Connect = function(_, callback) table.insert(listeners, callback) end,
		Fire = function(_, ...) for _, callback in listeners do callback(...) end end }
end
local clock = 100
local jobs = {}
local players = { {UserId = 1, Name = "One", DisplayName = "One", Parent = true}, {UserId = 2, Name = "Two", DisplayName = "Two", Parent = true} }
local saved, lastState, renders, removed = {}, {}, {}, {}
local store = {
	GetAsync = function(_, key) return copy(saved[key]) end,
	UpdateAsync = function(_, key, callback) saved[key] = copy(callback(copy(saved[key]))); return copy(saved[key]) end,
}
local plot = {LockedUntil = 0, LockCooldownUntil = 0}
local plotService = {
	GetPlot = function() return plot end,
	RenderMonster = function(player, monster) check(monster.Slot > 0, "Bench monster rendered"); renders[player] = renders[player] or {}; renders[player][monster.Id] = monster.Slot end,
	RemoveMonster = function(player, id) removed[id] = true; if renders[player] then renders[player][id] = nil end end,
	UpdateMonster = function() end,
	RenderEgg = function(_, _, _, slot) check(slot > 0, "Bench egg rendered") end,
	RemoveEgg = function() end,
	UpdateEggTimer = function() end,
	SetUnlockedSlots = function() end,
	SetPending = function() end,
	SetLockVisual = function() end,
	SetUpgradeLabel = function() end,
}
local services = {
	HttpService = { GenerateGUID = function() return tostring({}) end },
	RunService = { IsStudio = function() return false end },
	DataStoreService = { GetDataStore = function() return store end },
	ReplicatedStorage = {Shared = {Config = "Config", MonsterMath = "MonsterMath"}},
	Players = {GetPlayers = function() return players end, GetPlayerByUserId = function(_, id) return players[id] end},
}
local modules = {
	PlotService = plotService,
	CharacterService = {GetSpeedAccessoryMultiplier = function() return 1 end},
	FollowerService = { Init = function() end, CleanupPlayer = function() end, Remove = function() end,
		GetIds = function() return {} end, IsEligible = function() return false end,
		GetMinLevel = function() return 25 end, GetDamageBonus = function() return 0 end },
}
local parent = {Config = "Config", MonsterMath = "MonsterMath", DataService = "DataService", MonsterService = "MonsterService", PlotService = "PlotService", CharacterService = "CharacterService", FollowerService = "FollowerService"}
local env = {
	game = {GetService = function(_, name) return assert(services[name], name) end},
	script = {Parent = parent},
	require = function(name) return assert(modules[name], tostring(name)) end,
	task = {spawn = function(callback, ...) table.insert(jobs, {Callback = callback, Args = table.pack(...)}) end,
		wait = function(delay) return coroutine.yield(delay or 0) end, delay = function() end},
	os = {clock = function() return clock end, time = function() return 1700000000 + math.floor(clock) end},
}
for key, value in r do env[key] = value end
local function load(name, path)
	modules[name] = luau.load(fs.readFile(path), {environment = env, injectGlobals = true})()
	return modules[name]
end
local config = load("Config", "src/shared/Config.luau")
local mathModule = load("MonsterMath", "src/shared/MonsterMath.luau")
local data = load("DataService", "src/server/DataService.luau")
local monsters = load("MonsterService", "src/server/MonsterService.luau")
local trade = load("TradeService", "src/server/TradeService.luau")
local remotes = {}
for name in fs.readFile("src/shared/Remotes.luau"):gmatch('"([%w]+)",') do
	remotes[name] = {OnServerEvent = signal(), FireClient = function(_, player, state) if name == "StateUpdate" then lastState[player] = state end end, FireAllClients = function() end}
end
monsters.Init(remotes)
trade.Init(remotes)
local tickLoop = table.remove(jobs, 1)
local function tick(dt)
	local thread = coroutine.create(tickLoop.Callback)
	check(coroutine.resume(thread), "Tick loop starts")
	clock += dt
	check(coroutine.resume(thread), "Tick loop updates")
	local tickJobs = {}
	for index = #jobs, 1, -1 do if jobs[index].Args.n == 2 then table.insert(tickJobs, table.remove(jobs, index)) end end
	for _, job in tickJobs do job.Callback(table.unpack(job.Args, 1, job.Args.n)) end
end
local p, q = players[1], players[2]
local profile, other = data.Load(p), data.Load(q)
check(config.BaseSlots == 3 and next(profile.Data.Eggs) == nil, "Starter has 3 slots and no free eggs")
for _ = 1, 5 do check(monsters.AddMonster(p, "Grassland_1"), "Collect at full base") end
check(monsters.CountMonsters(p) == 5, "Collection never lost overflow")
check(profile.Data.Monsters["4"].Slot == 0 and profile.Data.Monsters["5"].Slot == 0, "Overflow lives on bench")
check(monsters.CountFreeSlots(p) == 0 and monsters.GetFreeSlot(p) == nil, "Bench does not consume extra slots")
local first, bench = profile.Data.Monsters["1"], profile.Data.Monsters["4"]
first.Hat, bench.Glasses = "keep-hat", "keep-glasses"
local count = monsters.CountMonsters(p)
check(monsters.PlaceMonster(p, "4", 1), "Bench can replace placed monster")
check(first.Slot == 0 and bench.Slot == 1 and monsters.CountMonsters(p) == count, "Swap retained both IDs")
check(first.Hat == "keep-hat" and bench.Glasses == "keep-glasses", "Swap retained accessories")
check(monsters.PlaceMonster(p, "4", 2), "Placed monsters can swap slots")
check(profile.Data.Monsters["2"].Slot == 1 and bench.Slot == 2, "Placed swap has no collision")
for _, slot in {0, -1, 4, 1.5, math.huge, 0/0, "1"} do check(not monsters.PlaceMonster(p, "4", slot), "Reject invalid/locked slot") end
check(not monsters.PlaceMonster(q, "4", 1), "Reject foreign ownership")
check(not monsters.PlaceMonster(p, {}, 1), "Reject malformed ID")
monsters.Carried[p] = {["4"] = true}
check(not monsters.BenchMonster(p, "4") and not monsters.PlaceMonster(p, "1", 2), "Carried source and target protected")
monsters.Trading[p] = {["2"] = true}
check(not monsters.PlaceMonster(p, "2", 3), "Trade offered source protected")
check(not monsters.PlaceMonster(p, "1", 1), "Trade offered target protected")
check(not monsters.TakeMonsterData(p, "2"), "Arena cannot remove trade offer")
check(monsters.AutoPlace(p), "Auto Place runs with unavailable monsters")
check(bench.Slot == 2 and profile.Data.Monsters["2"].Slot == 1, "Auto Place preserves reserved carried/trade slots")
monsters.Carried[p], monsters.Trading[p] = nil, nil
local eggType = "Basic"
check(monsters.AddEgg(p, eggType), "Full base accepts collected egg")
local benchEgg
for _, egg in profile.Data.Eggs do benchEgg = egg end
check(benchEgg and benchEgg.Slot == 0, "Collected egg overflows safely")
benchEgg.HatchAt = 0
local eggId = benchEgg.Id
tick(1)
check(profile.Data.Eggs[eggId] == nil and profile.Data.Monsters[eggId].Slot == 0, "Bench egg hatches without taking a plot slot")
check(profile.Data.Stats.Hatched == 1, "Bench hatch retains normal hatch statistics")
profile.Data.Monsters[eggId] = nil
profile.Data.Eggs = {}
-- Actual production beats rarity ordering and includes current needs, stage and mutation.
local speciesByIncome = {}
for name, species in config.Species do table.insert(speciesByIncome, {Name = name, Income = species.BaseProduction}) end
table.sort(speciesByIncome, function(a,b) return a.Income < b.Income end)
local strongest = profile.Data.Monsters["5"]
strongest.Species, strongest.Level, strongest.Hunger, strongest.Happiness = speciesByIncome[#speciesByIncome].Name, config.MaxLevel, 100, 100
profile.Data.Monsters["3"].Hunger = 0
check(monsters.AutoPlace(p), "Auto Place succeeds")
check(strongest.Slot > 0, "Highest actual income placed")
local chosenIncome, benchIncome = {}, {}
local used = {}
for _, monster in profile.Data.Monsters do
	check(monster.Slot >= 0 and monster.Slot <= 3, "Auto Place never unlocks a slot")
	if monster.Slot > 0 then check(not used[monster.Slot], "Unique placement"); used[monster.Slot] = true; table.insert(chosenIncome, mathModule.GetProduction(monster))
	else table.insert(benchIncome, mathModule.GetProduction(monster)) end
end
for _, placedIncome in chosenIncome do for _, storedIncome in benchIncome do check(placedIncome >= storedIncome, "Sorted by actual income") end end
check(monsters.CountMonsters(p) == count, "Auto Place never deletes weaker monsters")
local reservedMonster = profile.Data.Monsters["2"]
reservedMonster.Slot = 0
profile.Data.Eggs.reserved = {Id = "reserved", EggType = eggType, Slot = 3, HatchAt = math.huge}
for _, monster in profile.Data.Monsters do if monster.Slot == 3 then monster.Slot = 0 end end
monsters.AutoPlace(p)
for _, monster in profile.Data.Monsters do check(monster.Slot ~= 3, "Auto Place respects hatching egg reservation") end
profile.Data.Eggs = {}
monsters.AutoPlace(p)
local assignments = {}
for id, monster in profile.Data.Monsters do assignments[id] = monster.Slot end
monsters.AutoPlace(p)
for id, monster in profile.Data.Monsters do check(assignments[id] == monster.Slot, "Auto Place deterministic ties") end
-- Bench monsters age naturally, but never generate income or consume needs.
for id in profile.Data.Monsters do monsters.BenchMonster(p, id) end
local xp, hunger = first.Xp, first.Hunger
local pending = profile.Data.PendingCoins
tick(1)
check(profile.Data.PendingCoins == pending and first.Xp > xp and first.Hunger == hunger, "Bench ages without income or needs decay")
monsters.PlaceMonster(p, "1", 1)
first.Hunger, first.Happiness, first.Xp = 0, 0, 0
pending = profile.Data.PendingCoins
local expected = mathModule.GetProduction(first)
tick(1)
check(math.abs(profile.Data.PendingCoins - pending - expected) < 0.001, "Placed income matches shared production math")
check(lastState[p].BenchCount == 4 and lastState[p].PlacedCount == 1, "State distinguishes bench and placed")
check(lastState[p].Monsters[1].ActualIncome ~= nil, "State includes actual income")
-- Persistence and legacy slot migration preserve every monster and its loadout.
check(data.Save(p), "Inventory saves")
profile = data.Load(p)
check(profile.Data.Monsters["5"].Slot == 0 and profile.Data.Monsters["5"].Level == config.MaxLevel, "Bench persists across reload")
check(profile.Data.Monsters["1"].Hat == "keep-hat", "Monster gear persists")
profile.Data.SlotUpgrades = 1
monsters.AutoPlace(p)
check(monsters.CountFreeSlots(p) == 0, "Unlocked upgrade slot filled")
local upgradedCount = 0
for _, monster in profile.Data.Monsters do if monster.Slot > 0 then upgradedCount += 1 end end
check(upgradedCount == 4, "Auto Place uses purchased unlocked slots")
profile.Data.SlotUpgrades = 0
monsters.SetupPlayer(p)
for _, monster in profile.Data.Monsters do check(monster.Slot <= config.MaxSlots and (monster.Slot <= 3 or not monsters.IsPlaced(p, monster)), "Pending or lost entitlement preserves saved assignments without activating locked slots") end
local legacy = copy(profile.Data)
legacy.Eggs = {egg = {Id = "old", EggType = eggType, Slot = 1, HatchAt = 0}}
legacy.Monsters["1"].Slot, legacy.Monsters["2"].Slot, legacy.Monsters["3"].Slot = 1, 2, 2
legacy.Monsters["4"].Slot, legacy.Monsters["5"].Slot = -2, 8
data.NormalizeMonsterSlots(legacy, 3)
check(legacy.Monsters["1"].Slot == 0 and legacy.Monsters["3"].Slot == 0, "Legacy collisions move to bench")
check(legacy.Monsters["4"].Slot == 0 and legacy.Monsters["5"].Slot == 0, "Legacy invalid/locked slots move to bench")
check(legacy.Eggs.egg.Id == "egg" and legacy.Monsters["1"].Hat == "keep-hat", "Migration keeps identities and gear")
profile.Data.NextId = 1
check(data.NewId(p) ~= "1", "Stale NextId cannot overwrite ownership")
-- Trade over full bases, offer locks, cancellation and transfer retain all data.
for _ = 1, 4 do monsters.AddMonster(q, "Grassland_1") end
profile.Data.Coins = 1000000
clock += 1
remotes.TradeRequest.OnServerEvent:Fire(p, q.UserId)
remotes.TradeRespond.OnServerEvent:Fire(q, p.UserId, true)
remotes.TradeSetOffer.OnServerEvent:Fire(p, {"1"})
check(monsters.IsUnavailable(p, "1"), "Trade offer reserves monster")
local coins = profile.Data.Coins
clock += 1
remotes.SellMonster.OnServerEvent:Fire(p, "1")
check(profile.Data.Monsters["1"] ~= nil and profile.Data.Coins == coins, "Cannot sell offered monster")
remotes.TradeSetOffer.OnServerEvent:Fire(q, {"1", "2", "3", "4"})
remotes.TradeReady.OnServerEvent:Fire(p, true)
remotes.TradeReady.OnServerEvent:Fire(q, true)
check(monsters.CountMonsters(p) == 8 and monsters.CountMonsters(q) == 1, "Asymmetric full-base trade retains all monsters")
check(not monsters.IsUnavailable(p, "1"), "Completed trade clears reservations")
local foundHat = false
for _, monster in other.Data.Monsters do if monster.Hat == "keep-hat" then foundHat = true end end
check(foundHat, "Trade retains monster accessories")
clock += config.Trade.RequestCooldown + 1
remotes.TradeRequest.OnServerEvent:Fire(p, q.UserId)
remotes.TradeRespond.OnServerEvent:Fire(q, p.UserId, true)
local offerId = next(profile.Data.Monsters)
remotes.TradeSetOffer.OnServerEvent:Fire(p, {offerId})
remotes.TradeCancel.OnServerEvent:Fire(q)
check(not monsters.IsUnavailable(p, offerId) and profile.Data.Monsters[offerId] ~= nil, "Cancel releases reservation without deleting")

-- Save -> leave -> advance wall clock -> rejoin -> collect, using real services.
profile.Data.Monsters = { offline = { Id = "offline", Species = "Grassland_1", Level = 1, Xp = 0,
	Slot = 1, Hunger = 0, Happiness = 0, LastProgressAt = env.os.time() } }
profile.Data.Eggs = {}
profile.Data.IncomeMultiplier, profile.Data.IncomeUnlockedSlots = 1, config.BaseSlots
profile.Data.PendingCoins = 0.25
local expectedMonster = copy(profile.Data.Monsters.offline)
local expectedOffline = mathModule.AdvanceProgress(expectedMonster, env.os.time() + 9000, true, 1)
monsters.CleanupPlayer(p)
data.Release(p)
clock += 9000
profile = data.Load(p)
monsters.SetupPlayer(p)
check(profile.Data.Monsters.offline.Level == 25, "Offline rejoin reaches Adult after 2h 30m")
check(math.abs(profile.Data.PendingCoins - expectedOffline - 0.25) < 0.001, "Offline income joins existing uncollected balance")
local summary = lastState[p].OfflineEarnings
check(summary.SecondsAway == 9000 and math.abs(summary.CoinsEarned - expectedOffline) < 0.001 and summary.MonstersGrown == 1, "Join summary reports real offline earnings and elapsed seconds")
pending = profile.Data.PendingCoins
monsters.SetupPlayer(p)
check(profile.Data.PendingCoins == pending and lastState[p].OfflineEarnings.Id == summary.Id, "Repeated setup cannot replay income or create another summary")
local wallet = profile.Data.Coins
monsters.Collect(p)
check(profile.Data.Coins == wallet + math.floor(pending) and math.abs(profile.Data.PendingCoins - (pending % 1)) < 0.001, "Offline income is claimable through the normal collect path")
monsters.Collect(p)
check(profile.Data.Coins == wallet + math.floor(pending), "Repeated collection cannot replay offline income")
check(data.Save(p), "Claimed income and consumed timestamps save together")
monsters.CleanupPlayer(p)
data.Release(p)
profile = data.Load(p)
monsters.SetupPlayer(p)
check(profile.Data.Coins == wallet + math.floor(pending) and lastState[p].OfflineEarnings.CoinsEarned == 0, "Immediate saved rejoin does not award the same absence twice")
print(string.format("PASS: monster inventory (%d checks)", checks))
