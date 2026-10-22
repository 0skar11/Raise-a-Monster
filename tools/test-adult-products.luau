-- Real profile, monster and receipt services; offline deterministic Marketplace/DataStore.
local fs, r, luau = require("@lune/fs"), require("@lune/roblox"), require("@lune/luau")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for key, item in value do result[key] = copy(item) end; return result
end
local function env(extra)
	local e = table.clone(getfenv()); for key, value in r do e[key] = value end
	for key, value in extra or {} do e[key] = value end; return e
end
local function signal()
	local callbacks = {}
	return { Connect = function(_, callback) table.insert(callbacks, callback) end,
		Fire = function(_, ...) for _, callback in callbacks do callback(...) end end }
end
local function run(callback)
	local thread = coroutine.create(callback)
	for _ = 1, 100 do
		local ok, value = coroutine.resume(thread); assert(ok, tostring(value))
		if coroutine.status(thread) == "dead" then return value end
	end
	error("Test failed to complete")
end
local function harness(studio, existing)
	local h = { Stored = copy(existing), Failures = 0, Prompts = {}, Renders = {}, Notifications = {}, Clock = 0, Saves = 0 }
	local serial = 0
	local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env() })()
	config.Products.SkipToAdultOne.Id, config.Products.SkipToAdultAll.Id = 91001, 91002
	local player = { UserId = 1, Name = "Tester", Kick = function(self) self.Kicked = true end }
	local market = { PromptProductPurchaseFinished = signal(), PromptGamePassPurchaseFinished = signal() }
	market.PromptProductPurchase = function(_, _, id)
		check(h.Stored.PendingAdultPurchase and h.Stored.PendingAdultPurchase.Status == "Prompting", "Marketplace opened before the intent was durable")
		table.insert(h.Prompts, id)
		if h.PromptError then error("uncertain prompt failure") end
	end
	local services = {
		DataStoreService = { GetDataStore = function() return { UpdateAsync = function(_, _, callback)
			h.Saves += 1
			if h.OnSave then h.OnSave() end
			if h.Failures > 0 then h.Failures -= 1; error("simulated save failure") end
			local result = callback(copy(h.Stored)); if result then h.Stored = copy(result) end; return copy(result)
		end } end },
		Players = { GetPlayerByUserId = function(_, id) return if id == 1 and not h.Offline then player else nil end, GetPlayers = function() return { player } end },
		ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
		HttpService = { GenerateGUID = function() serial += 1; return "token-" .. serial end },
		RunService = { IsStudio = function() return studio == true end }, MarketplaceService = market,
	}
	local jobs = {}
	local fakeTask = { wait = function() return coroutine.yield() end,
		spawn = function(callback, ...)
			local thread = coroutine.create(callback); local ok, value = coroutine.resume(thread, ...); assert(ok, tostring(value))
			if coroutine.status(thread) ~= "dead" then table.insert(jobs, thread) end
		end }
	local clock = table.clone(os); clock.clock = function() return h.Clock end; clock.time = function() return 1700000000 end
	local modules = { Config = config, CharacterService = {}, CombatService = {},
		FollowerService = { Init = function() end, Remove = function() end },
		PlotService = { UpdateMonster = function(_, monster, rebuild) table.insert(h.Renders, { Id = monster.Id, Rebuild = rebuild }) end,
			RemoveMonster = function() end } }
	local parent = {}; for _, key in { "DataService", "MonsterService", "Config", "MonsterMath", "CharacterService", "CombatService", "FollowerService", "PlotService" } do parent[key] = key end
	local function load(path)
		return luau.load(fs.readFile(path), { environment = env({ game = { GetService = function(_, key) return assert(services[key], key) end },
			script = { Parent = parent }, require = function(key) return assert(modules[key], key) end, task = fakeTask, os = clock,
			Enum = { ProductPurchaseDecision = { PurchaseGranted = "granted", NotProcessedYet = "retry" } } }) })()
	end
	modules.MonsterMath = load("src/shared/MonsterMath.luau")
	modules.DataService = load("src/server/DataService.luau")
	if h.Stored then h.Stored._SessionLock = nil end
	local profile = modules.DataService.Load(player)
	modules.MonsterService = load("src/server/MonsterService.luau")
	modules.MonsterService.PushState = function() end
	modules.MonsterService.Notify = function(_, text) table.insert(h.Notifications, text) end
	local monetization = load("src/server/MonetizationService.luau")
	local remotes = {}; for _, key in { "BuyPass", "BuyWeapon", "EquipWeapon", "BuyProduct" } do remotes[key] = { OnServerEvent = signal() } end
	monetization.Init(remotes)
	h.Config, h.Player, h.Profile, h.Data, h.Monsters, h.Market, h.Monetization = config, player, profile, modules.DataService, modules.MonsterService, market, monetization
	h.Drain = function()
		for _ = 1, 10 do for _, thread in table.clone(jobs) do
			if coroutine.status(thread) ~= "dead" then local ok, value = coroutine.resume(thread); assert(ok, tostring(value)) end
		end end
	end
	h.Buy = function(name, id) h.Clock += 10; return run(function() remotes.BuyProduct.OnServerEvent:Fire(player, name, id) end) end
	h.Receipt = function(name, id)
		return run(function() return market.ProcessReceipt({ PlayerId = 1, ProductId = config.Products[name].Id, PurchaseId = id }) end)
	end
	h.Add = function(id, level, slot)
		local monster = { Id = id, Species = "Grassland_1", Level = level or 1, Xp = 44, Hunger = 81, Happiness = 77, Slot = slot or 0 }
		profile.Data.Monsters[id] = monster; return monster
	end
	return h
end

local h = harness(false)
local declared = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env() })()
check(declared.Products.SkipToAdultOne.Id == 3721310526 and declared.Products.SkipToAdultAll.Id == 3721310988, "Configured IDs do not match the actual created developer products")
check(h.Config.Products.SkipToAdultOne.Price == 29 and h.Config.Products.SkipToAdultAll.Price == 100, "Approved prices changed")
check(h.Monsters.GetAdultLevel() == 25, "Adult threshold differs from the stage definition")
for _, selected in { false, 123, {}, "foreign", string.rep("x", 200) } do h.Buy("SkipToAdultOne", selected) end
check(#h.Prompts == 0 and not h.Profile.Data.PendingAdultPurchase, "Invalid or foreign target reached Marketplace")
local adult, carried, trading = h.Add("adult", 25), h.Add("carried"), h.Add("trading")
h.Monsters.Carried[h.Player] = { carried = true }; h.Monsters.Trading[h.Player] = { trading = true }
for _, id in { "adult", "carried", "trading" } do h.Buy("SkipToAdultOne", id) end
check(#h.Prompts == 0, "Adult/carried/trading target reached Marketplace")
local first, bench = h.Add("first", 3, 1), h.Add("bench", 17)
h.Buy("SkipToAdultAll")
check(#h.Prompts == 1 and #h.Stored.PendingAdultPurchase.Targets == 2, "All did not freeze eligible placed and benched inventory")
check(first.Level == 3 and bench.Level == 17, "Prompt alone granted growth")
local future = h.Add("future")
h.Buy("SkipToAdultOne", "future"); h.Buy("SkipToAdultAll")
check(#h.Prompts == 1 and #h.Profile.Data.PendingAdultPurchase.Targets == 2, "A second request overwrote a pending purchase")
h.Market.PromptProductPurchaseFinished:Fire(1, 91002, true)
check(first.Level == 3, "Purchase finished event granted without a receipt")
check(h.Receipt("SkipToAdultAll", "all-1") == "granted", "Valid all receipt was not granted")
check(first.Level == 25 and bench.Level == 25 and first.Xp == 0 and bench.Xp == 0, "Growth did not reach Adult with reset XP")
check(future.Level == 1 and carried.Level == 1 and trading.Level == 1 and adult.Level == 25, "All purchase granted to future or excluded monsters")
check(first.Hunger == 81 and first.Happiness == 77 and h.Profile.Data.Coins == h.Config.StartingCoins, "Growth modified needs/cash")
check(#h.Renders == 1 and h.Renders[1].Id == "first" and h.Renders[1].Rebuild, "Placed monster did not rebuild or bench was rendered")
check(h.Stored.Monsters.first.Level == 25 and h.Stored.ProcessedReceipts["all-1"] and not h.Stored.PendingAdultPurchase, "Grant, receipt and consumed intent were not durable together")
first.Xp = 9; first.Level = 26
check(h.Receipt("SkipToAdultAll", "all-1") == "granted" and first.Level == 26 and first.Xp == 9, "Repeated receipt downgraded or repeated growth")
check(h.Receipt("SkipToAdultAll", "without-intent") == "retry" and future.Level == 1, "Orphan receipt granted to future inventory")
h.Buy("SkipToAdultOne", "future")
check(h.Receipt("SkipToAdultAll", "all-1") == "granted" and h.Profile.Data.PendingAdultPurchase.Targets[1].Id == "future", "Old receipt consumed a newer pending intent")
h.Market.PromptProductPurchaseFinished:Fire(1, 91001, false)
check(not h.Profile.Data.PendingAdultPurchase, "Old duplicate receipt detached the newer cancellation handler")

-- Receipt-first ordering must wait for the original prompt's Finished event.
h = harness(false); first = h.Add("first"); future = h.Add("future")
h.Buy("SkipToAdultOne", "first")
check(h.Receipt("SkipToAdultOne", "receipt-first") == "granted", "Receipt-first purchase did not settle")
h.Buy("SkipToAdultOne", "future")
check(#h.Prompts == 1 and not h.Profile.Data.PendingAdultPurchase, "A new prompt began before the old Finished event")
h.Market.PromptProductPurchaseFinished:Fire(1, 91001, true)
h.Buy("SkipToAdultOne", "future")
check(#h.Prompts == 2 and h.Profile.Data.PendingAdultPurchase.Targets[1].Id == "future", "Finished old prompt did not permit a fresh selection")
h.Market.PromptProductPurchaseFinished:Fire(1, 91001, false)
check(not h.Profile.Data.PendingAdultPurchase and future.Level == 1, "New cancellation after receipt-first ordering was misrouted")

-- Reconnect preserves the exact original targets, never whoever is owned later.
h = harness(false); first = h.Add("first", 2); h.Buy("SkipToAdultOne", "first")
local saved = copy(h.Stored)
local rejoined = harness(false, saved); future = rejoined.Add("future")
rejoined.Buy("SkipToAdultOne", "future")
check(#rejoined.Prompts == 0 and rejoined.Profile.Data.PendingAdultPurchase.Targets[1].Id == "first", "Reconnect replaced an uncertain old selection")
check(rejoined.Receipt("SkipToAdultOne", "late") == "granted" and rejoined.Profile.Data.Monsters.first.Level == 25 and future.Level == 1, "Delayed receipt did not use persisted selection")

-- Removed/transferred records and same-ID replacements cannot receive redirected value.
for _, change in { "removed", "replaced", "naturally-adult" } do
	h = harness(false); first = h.Add("first", 3); h.Buy("SkipToAdultOne", "first")
	if change == "removed" then h.Profile.Data.Monsters.first = nil
	elseif change == "replaced" then first = h.Add("first", 2)
	else first.Level, first.Xp = 31, 93 end
	future = h.Add("new")
	check(h.Receipt("SkipToAdultOne", "moved-" .. change) == "granted", "Snapshot could not settle after " .. change)
	check(future.Level == 1 and (change == "removed" or first.Level == (if change == "naturally-adult" then 31 elseif change == "replaced" then 2 else 3)), "Receipt affected unavailable/replaced/future inventory")
end

-- Temporary carry/trade locks defer the entire frozen purchase without consuming it.
for _, product in { "SkipToAdultOne", "SkipToAdultAll" } do
	for _, lock in { "Carried", "Trading" } do
		h = harness(false); first = h.Add("z-locked", 3); bench = h.Add("a-ready", 17)
		h.Buy(product, "z-locked")
		local intent = h.Profile.Data.PendingAdultPurchase
		local originalTargets = copy(intent.Targets)
		future = h.Add("future")
		h.Monsters[lock][h.Player] = { ["z-locked"] = true }
		local receiptId = product .. "-" .. lock
		local savesBefore = h.Saves
		for _ = 1, 2 do
			check(h.Receipt(product, receiptId) == "retry", "Temporarily locked paid target was acknowledged: " .. receiptId)
			check(first.Level == 3 and first.Xp == 44 and bench.Level == 17 and bench.Xp == 44, "Blocked snapshot partially applied growth")
			check(h.Profile.Data.PendingAdultPurchase == intent and intent.Status == "Prompting" and not intent.ReceiptId
				and not h.Profile.Data.ProcessedReceipts[receiptId], "Blocked receipt mutated its intent or marker")
			check(#intent.Targets == #originalTargets and intent.Targets[1].Identity == originalTargets[1].Identity
				and h.Saves == savesBefore and #h.Renders == 0, "Blocked receipt changed snapshot or saved/rendered a partial reward")
		end
		h.Monsters[lock][h.Player] = nil
		check(h.Receipt(product, receiptId) == "granted", "Unlocked snapshot could not retry")
		check(first.Level == 25 and first.Xp == 0 and bench.Level == (if product == "SkipToAdultAll" then 25 else 17)
			and future.Level == 1, "Unlocked receipt did not apply only its frozen targets")
		check(h.Stored.ProcessedReceipts[receiptId] and not h.Stored.PendingAdultPurchase
			and h.Stored.Monsters["z-locked"].Level == 25, "Unlocked reward was not durably settled")
		first.Level, first.Xp = 26, 9
		check(h.Receipt(product, receiptId) == "granted" and first.Level == 26 and first.Xp == 9, "Retried lock receipt applied twice")
	end
end

-- Cancellation is matched to the active prompt and durable before another choice.
h = harness(false); first = h.Add("first"); future = h.Add("other")
h.Buy("SkipToAdultOne", "first")
h.Market.PromptProductPurchaseFinished:Fire(2, 91001, false)
h.Market.PromptProductPurchaseFinished:Fire(1, 91002, false)
check(h.Profile.Data.PendingAdultPurchase ~= nil, "Wrong player/product canceled the selection")
h.Market.PromptProductPurchaseFinished:Fire(1, 91001, false)
check(not h.Profile.Data.PendingAdultPurchase and not h.Stored.PendingAdultPurchase and first.Level == 1, "Cancellation was not durably cleared without a grant")
h.Buy("SkipToAdultOne", "other")
check(#h.Prompts == 2 and h.Receipt("SkipToAdultOne", "new-selection") == "granted" and future.Level == 25 and first.Level == 1, "Confirmed cancellation prevented the next valid selection")

h = harness(false); first = h.Add("first"); future = h.Add("future")
h.Buy("SkipToAdultOne", "first"); h.Failures = 100
run(function() h.Market.PromptProductPurchaseFinished:Fire(1, 91001, false) end)
h.Drain()
check(h.Profile.Data.PendingAdultPurchase.Targets[1].Id == "first" and h.Profile.Data.PendingAdultPurchase.Status == "Prepared", "Failed cancellation save lost the original snapshot")
h.Failures = 0; h.Buy("SkipToAdultOne", "future")
check(#h.Prompts == 1 and h.Profile.Data.PendingAdultPurchase.Targets[1].Id == "first", "Failed cancellation save allowed a different future target")
h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 2 and h.Receipt("SkipToAdultOne", "cancel-save-retry") == "granted" and first.Level == 25 and future.Level == 1, "Confirmed canceled original could not safely retry after save recovery")

-- Save failures never open an unpaid/unsaved intent, acknowledge, or repeat a grant.
h = harness(false); first = h.Add("first"); h.Failures = 100; h.Buy("SkipToAdultOne", "first")
h.Failures = 0; h.Profile.Data.Monsters.first = nil; future = h.Add("future")
h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 0 and not h.Profile.Data.PendingAdultPurchase and future.Level == 1, "Prepared retry charged after its original target left inventory")
h = harness(false); first = h.Add("first")
local writesBefore = h.Saves
h.OnSave = function() if h.Saves == writesBefore + 2 then first.Level = 25 end end
h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 0 and not h.Profile.Data.PendingAdultPurchase, "Target growing during intent save still opened a paid prompt")

h = harness(false); first = h.Add("first")
h.Failures = 100; h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 0 and first.Level == 1 and h.Profile.Data.PendingAdultPurchase.Status == "Prepared", "Failed intent save opened a prompt/granted")
h.Failures = 0; h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 1, "Saved original prepared selection could not retry")
h.Failures = 100
check(h.Receipt("SkipToAdultOne", "failed-save") == "retry" and first.Level == 25, "Failed receipt save acknowledged or did not apply the frozen target")
first.Xp = 7; first.Level = 26
check(h.Receipt("SkipToAdultOne", "failed-save") == "retry" and first.Xp == 7 and first.Level == 26, "Retry reapplied a non-durable reward")
h.Failures = 0
check(h.Receipt("SkipToAdultOne", "failed-save") == "granted" and h.Stored.ProcessedReceipts["failed-save"] and not h.Stored.PendingAdultPurchase, "Save recovery did not atomically settle the receipt")
check(first.Level == 26 and first.Xp == 7, "Receipt recovery downgraded normal subsequent growth")

-- An autosave can persist Applied+marker after receipt Save failed; rejoin still settles once.
h = harness(false); first = h.Add("first"); h.Buy("SkipToAdultOne", "first"); h.Failures = 100
check(h.Receipt("SkipToAdultOne", "applied-reconnect") == "retry", "Failing receipt save was acknowledged")
h.Failures = 0; check(h.Data.Save(h.Player), "Follow-up autosave did not persist applied state")
rejoined = harness(false, h.Stored); future = rejoined.Add("future")
check(rejoined.Receipt("SkipToAdultOne", "applied-reconnect") == "granted"
	and rejoined.Profile.Data.Monsters.first.Level == 25 and future.Level == 1
	and not rejoined.Stored.PendingAdultPurchase, "Applied receipt did not recover idempotently across a server restart")

for _, studio in { false, true } do
	h = harness(studio); first = h.Add("first"); h.Config.Products.SkipToAdultOne.Id = 0; h.Buy("SkipToAdultOne", "first")
	check(#h.Prompts == 0 and first.Level == 1 and not h.Profile.Data.PendingAdultPurchase, "Unconfigured product granted a Studio/free entitlement")
end
h = harness(false); first = h.Add("first"); h.Profile.LoadFailed = true; h.Buy("SkipToAdultOne", "first")
check(#h.Prompts == 0 and first.Level == 1, "Unsafe profile reached paid prompt")
h.Profile.LoadFailed = false; h.Buy("SkipToAdultOne", "first"); h.Profile.Closing = true
check(h.Receipt("SkipToAdultOne", "closing") == "retry" and first.Level == 1, "Closing profile consumed a receipt")

-- Historical contents and the separate Secret roll are restored exactly.
local weights = { Desert_5 = 20, Ice_5 = 20, Volcano_5 = 18, Ice_7 = 15, Volcano_7 = 12, Desert_9 = 8, Ice_9 = 5, Volcano_10 = 2 }
local total, count = 0, 0
for key, value in h.Config.Eggs.Lucky.Weights do check(weights[key] == value, "Lucky pool differs from the historical weights"); total += value; count += 1 end
check(total == 100 and count == 8 and h.Config.Eggs.Lucky.AllowSecret ~= false, "Lucky includes an extra/missing/restricted outcome")
check(h.Config.LuckyEggSecretMultiplier == 5 and h.Config.SecretChance * h.Config.LuckyEggSecretMultiplier == 0.005, "Lucky Secret odds are not the original 0.5%")
print(string.format("PASS: %d adult product and historical Lucky checks (real profile durability, selection, current-only snapshots, delayed/repeated receipts, cancellation, failed saves)", checks))
