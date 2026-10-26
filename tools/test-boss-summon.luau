-- Real receipt router + summon service with deterministic Marketplace/world/save fakes.
-- No account, live purchases, or Roblox currency is used.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local globals = getfenv()
local function env(extra)
	for key, value in globals do if extra[key] == nil then extra[key] = value end end
	for key, value in r do if extra[key] == nil then extra[key] = value end end
	return extra
end
local function signal()
	local handlers = {}
	return { Connect = function(_, fn) table.insert(handlers, fn) end,
		Fire = function(_, ...) for _, fn in handlers do fn(...) end end }
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for k, v in value do result[k] = copy(v) end; return result
end
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function harness()
	local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env({}) })()
	local player = { UserId = 123, Name = "VerifiedBuyer", DisplayName = "Pumpkin Hero" }
	local profile = { CanSave = true, Data = { ProcessedReceipts = {}, PendingBossSummons = {} } }
	local stored, saveOk, saveHook = copy(profile.Data), true, nil
	local alive, spawns, announcements, prompts, notes = false, 0, {}, {}, {}
	local fakeTask = { spawn = function() end, wait = function() end }
	local data = { Get = function(p) return if p == player then profile else nil end,
		Save = function()
			if saveHook then return saveHook() end
			if saveOk then stored = copy(profile.Data) end
			return saveOk
		end }
	local event = { IsBossAlive = function() return alive end,
		SpawnBoss = function(summoned)
			check(summoned == true, "Paid spawn must suppress competing generic announcement")
			if alive then return false end
			alive = true; spawns += 1; return true
		end }
	local monster = { Notify = function(_, text) table.insert(notes, text) end }
	local market = { PromptGamePassPurchaseFinished = signal(), PromptProductPurchaseFinished = signal(),
		PromptProductPurchase = function(_, p, id) check(p == player, "Prompt uses authenticated player"); table.insert(prompts, id) end }
	local players = { GetPlayerByUserId = function(_, id) return if id == player.UserId then player else nil end }
	local modules = { Config = config, DataService = data, EventService = event, MonsterService = monster,
		MonsterMath = {}, PlotService = {}, CharacterService = {}, CombatService = {} }
	local services = { Players = players, ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
		MarketplaceService = market, RunService = { IsStudio = function() return false end } }
	local parent = {}; for name in modules do parent[name] = name end
	local function load(path)
		return luau.load(fs.readFile(path), { environment = env({
			game = { GetService = function(_, name) return assert(services[name], name) end },
			script = { Parent = parent }, require = function(name) return assert(modules[name], name) end,
			task = fakeTask, Enum = { ProductPurchaseDecision = { PurchaseGranted = "granted", NotProcessedYet = "retry" } },
		}) })()
	end
	local service = load("src/server/BossSummonService.luau")
	local monetization = load("src/server/MonetizationService.luau")
	monetization.CanPromptBossSummon, monetization.ProcessBossSummonReceipt = service.CanPrompt, service.ProcessReceipt
	local remotes = { BossSummoned = { FireAllClients = function(_, notice) table.insert(announcements, notice) end } }
	for _, key in { "BuyPass", "BuyWeapon", "EquipWeapon", "BuyProduct" } do remotes[key] = { OnServerEvent = signal() } end
	service.Init(remotes); monetization.Init(remotes)
	local h = { Config = config, Player = player, Service = service, Market = market, Prompts = prompts, Announcements = announcements, Notes = notes }
	h.Profile = function() return profile end
	h.Stored = function() return stored end
	h.Reload = function() profile = { CanSave = true, Data = copy(stored) } end
	h.SetSave = function(ok) saveOk = ok end
	h.SetSaveHook = function(fn) saveHook = fn end
	h.SetAlive = function(on) alive = on end
	h.Spawns = function() return spawns end
	h.Buy = function(name) remotes.BuyProduct.OnServerEvent:Fire(player, name or "SummonBoss") end
	h.Receipt = function(id, extra)
		local receipt = { PlayerId = player.UserId, ProductId = config.Products.SummonBoss.Id, PurchaseId = id, CurrencySpent = 50 }
		for key, value in extra or {} do receipt[key] = value end
		return market.ProcessReceipt(receipt)
	end
	return h
end

local h = harness()
check(h.Config.Products.SummonBoss.Id == 3722488952 and h.Config.Products.SummonBoss.Price == 50, "Live product matches fixed 50 Robux dashboard product")
h.Buy()
check(#h.Prompts == 1 and h.Prompts[1] == h.Config.Products.SummonBoss.Id, "Valid request opens correct prompt")
check(h.Spawns() == 0 and next(h.Profile().Data.PendingBossSummons) == nil, "Prompt grants no summon")
h.Market.PromptProductPurchaseFinished:Fire(h.Player.UserId, h.Config.Products.SummonBoss.Id, true)
check(h.Spawns() == 0 and next(h.Profile().Data.PendingBossSummons) == nil, "Purchase finished cannot grant a summon")
check(h.Receipt("first") == "granted", "Receipt is granted after durable credit saved")
check(h.Stored().ProcessedReceipts.first and h.Stored().PendingBossSummons.first == 50, "Credit and receipt marker saved atomically")
h.Service.Deliver(h.Player)
check(h.Spawns() == 1 and #h.Announcements == 1, "Saved purchase spawns one boss with one premium announcement")
local notice = h.Announcements[1]
check(notice.Name == "VerifiedBuyer" and notice.DisplayName == "Pumpkin Hero" and notice.UserId == 123 and notice.Robux == 50, "Server announcement names authenticated payer and real paid amount")
check(next(h.Stored().PendingBossSummons) == nil and h.Stored().ProcessedReceipts.first, "Debit saved while receipt idempotency retained")
check(h.Receipt("first") == "granted" and h.Spawns() == 1, "Duplicate receipt cannot spawn twice")
check(h.Receipt("bad-player", { PlayerId = 999 }) == "retry", "Missing player not acknowledged")
check(h.Receipt("bad-product", { ProductId = -1 }) == "retry", "Unknown product not acknowledged")
check(h.Receipt("") == "retry", "Empty purchase ID rejected")
check(h.Receipt("bad-product-zero", { ProductId = 0 }) == "retry", "Unconfigured product not acknowledged")

h = harness(); h.SetAlive(true); h.Buy()
check(#h.Prompts == 0, "Active boss blocks unnecessary paid prompt")
check(h.Receipt("concurrent") == "granted", "Concurrent purchase arriving after another spawn receives durable credit")
h.Service.Deliver(h.Player)
check(h.Spawns() == 0 and h.Stored().PendingBossSummons.concurrent == 50, "Busy arena retains paid credit")
local waitingSaves = 0
h.SetSaveHook(function() waitingSaves += 1; return true end)
for _ = 1, 10 do h.Service.Deliver(h.Player) end
check(waitingSaves == 0, "Queued buyers make no DataStore writes while a boss is alive")
h.SetSaveHook(nil)
h.SetAlive(false); h.Service.Deliver(h.Player)
check(h.Spawns() == 1 and next(h.Stored().PendingBossSummons) == nil, "Queued summon delivers when arena is free without requiring a Roblox receipt retry")

h = harness(); h.SetSave(false)
check(h.Receipt("save-failed") == "retry", "Failed initial save does not acknowledge receipt")
h.Service.Deliver(h.Player)
check(h.Spawns() == 0, "Unsaved credit never creates world benefit")
check(h.Receipt("save-failed") == "retry", "Repeated failed save does not add a duplicate credit")
h.SetSave(true); h.Service.Deliver(h.Player)
check(h.Spawns() == 1, "Background save recovery delivers pending purchase")
check(h.Receipt("save-failed") == "granted" and h.Spawns() == 1, "Delayed Roblox retry acknowledges once without duplicate spawn")

h = harness(); check(h.Receipt("debit-failed") == "granted", "Setup paid credit")
local saves = 0
h.SetSaveHook(function()
	saves += 1
	return saves == 1 -- persisted credit already exists; the post-spawn debit write fails
end)
h.Service.Deliver(h.Player)
check(h.Spawns() == 1 and h.Stored().PendingBossSummons["debit-failed"] == 50, "Failed debit leaves recoverable credit on disk")
h.Reload(); h.SetSaveHook(nil); h.SetAlive(false); h.Service.Deliver(h.Player)
check(h.Spawns() == 1 and next(h.Stored().PendingBossSummons) == nil, "Same-server rejoin recognizes delivered receipt and retries debit without a second boss")

h = harness(); h.Receipt("debit-first")
local debitSaves = 0
h.SetSaveHook(function() debitSaves += 1; return debitSaves == 1 end)
h.Service.Deliver(h.Player)
h.SetSaveHook(nil)
check(h.Receipt("waiting-second") == "granted", "A concurrent second paid summon is saved while the first debit is pending")
h.Service.Deliver(h.Player)
check(h.Spawns() == 1 and h.Stored().PendingBossSummons["debit-first"] == nil
	and h.Stored().PendingBossSummons["waiting-second"] == 50, "Delivered debit is processed first while living boss holds undelivered credit")
h.SetAlive(false); h.Service.Deliver(h.Player)
check(h.Spawns() == 2 and next(h.Stored().PendingBossSummons) == nil, "Next paid credit spawns once after first fight, without any lost credit")

h = harness(); h.Receipt("recovery"); h.Reload(); h.Service.Deliver(h.Player)
check(h.Spawns() == 1, "Durable pending credit is recovered after reconnect")
h = harness(); h.Profile().CanSave = false
check(h.Receipt("unsafe") == "retry", "Unsafe profile cannot consume a purchase")
h.Buy(); check(#h.Prompts == 0, "Unsafe profile cannot open paid prompt")
h = harness(); h.Profile().Closing = true
check(h.Receipt("closing") == "retry", "Departing profile cannot consume a purchase")
h.Buy(); check(#h.Prompts == 0, "Departing profile cannot open paid prompt")
print(string.format("PASS: %d paid summon checks (real receipt routing, prompt/cancel safety, saves, duplicate receipts, queue, authenticated announcement, reconnect)", checks))
