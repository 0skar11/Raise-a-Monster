-- Egg Keeper monster store: odds, bundle pricing, the real EggStoreService purchase rules (with deterministic
-- DataService/MonsterService fakes), the real DataService Luck persistence, and wiring/source contracts.
-- No account, live purchase or Roblox currency is used. The NPC's look and the store GUI need a Studio playtest.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function environment(extra)
	local env = table.clone(getfenv())
	for key, value in r do env[key] = value end
	for key, value in extra or {} do env[key] = value end
	return env
end
local function load(path, extra) return luau.load(fs.readFile(path), { environment = environment(extra) })() end
local function read(path) return fs.readFile(path) end
local function signal()
	local handlers = {}
	return { Connect = function(_, fn) table.insert(handlers, fn) end,
		Fire = function(_, ...) for _, fn in handlers do fn(...) end end }
end

local Config = load("src/shared/Config.luau")
local S = Config.EggStore
local function mathModule()
	local services = { ReplicatedStorage = { Shared = { Config = "Config" } } }
	return load("src/shared/EggStoreMath.luau", {
		game = { GetService = function(_, name) return assert(services[name], name) end },
		require = function(name) return assert(({ Config = Config })[name], name) end,
	})
end
local M = mathModule()

-- Config and odds ------------------------------------------------------------------------------------------
local MONSTERS = { "CountFang", "CryptMummy", "GhostSlime", "GraveGolem", "HexCat", "PumpkinKing", "SkeletonImp", "WraithReaper" }
local egg = Config.Eggs[S.Egg]
check(egg ~= nil and S.Egg == "HalloweenMonster", "The store sells the existing Halloween Monster Egg")
do
	local count = 0
	for name in egg.Weights do count += 1 end
	check(count == 8, "The egg hatches exactly the eight Halloween monsters")
	for _, monster in MONSTERS do
		check(egg.Weights["Halloween" .. monster] ~= nil and Config.Species["Halloween" .. monster].EventOnly == true, monster .. " is in the egg")
	end
end
local function sum(odds) local total = 0; for _, value in odds do total += value end; return total end
check(math.abs(sum(M.Odds(egg.Weights, false)) - 100) < 1e-9, "Base odds sum to 100%")
check(math.abs(sum(M.Odds(egg.Weights, true)) - 100) < 1e-9, "Luck odds sum to 100%")
do
	local base, lucky = M.Odds(egg.Weights, false), M.Odds(egg.Weights, true)
	check(base.HalloweenPumpkinKing == 3 and base.HalloweenGhostSlime == 20, "Base odds are the egg weights (they already total 100)")
	check(lucky.HalloweenPumpkinKing > base.HalloweenPumpkinKing and lucky.HalloweenWraithReaper > base.HalloweenWraithReaper, "Luck raises Mythic odds")
	check(lucky.HalloweenHexCat > base.HalloweenHexCat and lucky.HalloweenGhostSlime < base.HalloweenGhostSlime, "Luck raises Legendary and lowers Epic")
	local before = egg.Weights.HalloweenPumpkinKing
	M.LuckWeights(egg.Weights, true)
	check(egg.Weights.HalloweenPumpkinKing == before, "Luck never mutates the Config weights")
	check(M.LuckWeights(egg.Weights, false).HalloweenPumpkinKing == before, "No Luck leaves weights untouched")
end
check(S.Luck.Multiplier == 2 and S.Luck.Duration > 0 and S.Luck.MaxSeconds >= S.Luck.Duration and S.Luck.Price > 0, "Luck is x2, timed, capped and priced")
check(M.AppliesLuck("HalloweenMonster") and not M.AppliesLuck("Lucky") and not M.AppliesLuck("Secret"), "Luck only affects the Halloween egg")

-- Bundles ----------------------------------------------------------------------------------------------------
check(#S.Bundles == 3 and S.Bundles[1].Count == 1 and S.Bundles[2].Count == 3 and S.Bundles[3].Count == 8, "Bundles are exactly 1, 3 and 8")
check(M.BundlePrice(S.Bundles[1]) == S.EggPrice, "Buy 1 costs the egg price")
do
	local previous = math.huge
	for _, bundle in S.Bundles do
		local price = M.BundlePrice(bundle)
		check(price > 0 and price == math.floor(price), "Whole-Robux price for Buy " .. bundle.Count)
		check(price <= S.EggPrice * bundle.Count and bundle.Discount >= 0 and bundle.Discount < 1, "Never dearer than buying singly: Buy " .. bundle.Count)
		check(price / bundle.Count < previous or bundle.Count == 1, "Bigger bundles are cheaper per egg")
		previous = price / bundle.Count
	end
end
check(M.BundlePrice(S.Bundles[2]) == math.floor(S.EggPrice * 3 * 0.9 + 0.5) and M.BundlePrice(S.Bundles[3]) == math.floor(S.EggPrice * 8 * 0.8 + 0.5), "Buy 3 is 10% off and Buy 8 is 20% off")
for _, bad in { 0, 2, 4, 7, 9, -1, -3, 1e9, 0 / 0, math.huge, 3.5, 1.0000001, "3", "1", true, false, {}, nil } do
	check(M.FindBundle(bad) == nil, "Rejects bundle size " .. tostring(bad))
end
for _, count in { 1, 3, 8 } do check(M.FindBundle(count) ~= nil and M.FindBundle(count).Count == count, "Accepts " .. count) end

-- Luck timer math --------------------------------------------------------------------------------------------
check(M.LuckLeft(1000, 400) == 600 and M.LuckLeft(100, 400) == 0, "LuckLeft never goes negative")
check(M.ExtendLuck(0, 1000) == 1000 + S.Luck.Duration, "A fresh Luck lasts one Duration")
check(M.ExtendLuck(1000 + 100, 1000) == 1100 + S.Luck.Duration, "Buying while active stacks on the remaining time")
check(M.ExtendLuck(1000 + S.Luck.MaxSeconds, 1000) == nil and M.ExtendLuck(1000 + S.Luck.MaxSeconds - S.Luck.Duration + 1, 1000) == nil, "Luck cannot be stacked past the cap")
check(M.ExtendLuck(1000 + S.Luck.MaxSeconds - S.Luck.Duration, 1000) == 1000 + S.Luck.MaxSeconds, "...but may reach the cap exactly")

-- lune's Instance DOM has no Position/Triggered, so the NPC is built from a tiny fake instance tree.
local function newInstance(className)
	local raw = { ClassName = className, Name = className, Children = {} }
	local obj
	local methods = {}
	function methods.FindFirstChild(_, name)
		for _, child in raw.Children do if child.Name == name then return child end end
		return nil
	end
	function methods.FindFirstChildOfClass(_, class)
		for _, child in raw.Children do if child.ClassName == class then return child end end
		return nil
	end
	function methods.IsA(_, class) return class == className or (class == "BasePart" and className == "Part") end
	function methods.IsDescendantOf(_, ancestor)
		local parent = raw.Parent
		while parent do
			if parent == ancestor then return true end
			parent = parent.Parent
		end
		return false
	end
	obj = setmetatable({}, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			if key == "Position" and raw.CFrame then return raw.CFrame.Position end
			if key == "Triggered" then raw.Triggered = raw.Triggered or signal() end
			return raw[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				if raw.Parent then table.remove(raw.Parent.Children, table.find(raw.Parent.Children, obj)) end
				raw.Parent = value
				if value then table.insert(value.Children, obj) end
			else
				raw[key] = value
			end
		end,
	})
	return obj
end
local fakeBuild = {
	MakePart = function(props)
		local part = newInstance("Part")
		for key, value in props do if key ~= "Parent" then part[key] = value end end
		part.Parent = props.Parent
		return part
	end,
	MakeBillboard = function(adornee)
		local gui, label = newInstance("BillboardGui"), newInstance("TextLabel")
		gui.Parent, label.Parent = adornee, gui
		return gui, label
	end,
	MakePrompt = function(parent, name, action, key, hold)
		local prompt = newInstance("ProximityPrompt")
		prompt.Name, prompt.ActionText, prompt.KeyboardKeyCode, prompt.HoldDuration, prompt.MaxActivationDistance = name, action, key, hold, 10
		prompt.Parent = parent
		return prompt
	end,
}

-- The real EggStoreService with fakes ------------------------------------------------------------------------
local IDS = { Egg1 = 1001, Egg3 = 1003, Egg8 = 1008, Luck = 1100 }
local function harness(configure)
	local config = load("src/shared/Config.luau")
	config.EggStore.Cooldown = 0
	for name, id in IDS do config.EggStore.Products[name] = id end
	if configure then configure(config) end
	local world = newInstance("Workspace")
	local tags = {}
	local npcPosition = config.EggStore.Npc.Position
	local profile = { Data = { Coins = 100000000, EggLuckUntil = 0, ProcessedReceipts = {} }, CanSave = true }
	local player = { UserId = 7, Name = "Buyer" }
	local root = { Position = npcPosition + r.Vector3.new(0, 0, -5), IsA = function(_, name) return name == "BasePart" end }
	local humanoid = { Health = 100 }
	player.Character = {
		FindFirstChild = function(_, name) return if name == "HumanoidRootPart" then root else nil end,
		FindFirstChildOfClass = function(_, name) return if name == "Humanoid" then humanoid else nil end,
	}
	local now = 1700000000
	local eggs, notes, saves, pushes, prompts = {}, {}, { 0 }, { 0 }, {}
	local state = { SaveOk = true }
	local data = {
		Get = function(p) return if p == player then profile else nil end,
		TrySpend = function() error("the Egg Keeper store must never spend coins") end,
		QueueSave = function() saves[1] += 1 end,
		Save = function() saves[1] += 1; return state.SaveOk end,
	}
	local monster = {
		Notify = function(_, text, kind) table.insert(notes, { text, kind }) end,
		PushState = function() pushes[1] += 1 end,
		AddEgg = function(_, eggType, quiet) table.insert(eggs, { eggType, quiet }); return true end,
	}
	local finished = signal()
	local services = {
		CollectionService = {
			AddTag = function(_, instance, tag) tags[tag] = instance end,
			GetTagged = function(_, tag)
				if tags[tag] then return { tags[tag] } end
				return {}
			end,
		},
		MarketplaceService = {
			PromptProductPurchase = function(_, p, id) table.insert(prompts, { p, id }) end,
			PromptProductPurchaseFinished = finished,
		},
		Players = { PlayerRemoving = signal(), GetPlayerByUserId = function(_, id) return if id == player.UserId then player else nil end },
		ReplicatedStorage = { Shared = { Config = "Config", EggStoreMath = "EggStoreMath" } },
	}
	local build = fakeBuild
	local mathLoaded = load("src/shared/EggStoreMath.luau", {
		game = { GetService = function(_, name) return assert(services[name], name) end },
		require = function(name) return assert(({ Config = config })[name], name) end,
	})
	local modules = { Config = config, EggStoreMath = mathLoaded, DataService = data, MonsterService = monster, Build = build }
	local parent = {}; for name in modules do parent[name] = name end
	local service = load("src/server/EggStoreService.luau", {
		game = { GetService = function(_, name) return assert(services[name], name) end },
		script = { Parent = parent }, workspace = world, Instance = { new = newInstance },
		require = function(name) return assert(modules[name], name) end,
		os = { time = function() return now end, clock = os.clock },
	})
	local remotes = {
		BuyEggBundle = { OnServerEvent = signal() }, BuyEggLuck = { OnServerEvent = signal() },
		OpenEggStore = {}, EggStoreState = {},
	}
	function remotes.OpenEggStore.FireClient(_, p, st) remotes.Opened = { p, st } end
	function remotes.EggStoreState.FireClient(_, p, st) remotes.State = { p, st } end
	service.Init(remotes)
	local h = { Service = service, Config = config, Player = player, Profile = profile, Root = root, Eggs = eggs, Notes = notes, Remotes = remotes,
		Saves = saves, Pushes = pushes, World = world, Tags = tags, Humanoid = humanoid, Prompts = prompts, State = state, Finished = finished }
	h.Buy = function(count) remotes.BuyEggBundle.OnServerEvent:Fire(player, count) end
	h.BuyLuck = function() remotes.BuyEggLuck.OnServerEvent:Fire(player) end
	h.Advance = function(seconds) now += seconds end
	h.Now = function() return now end
	local serial = 0
	h.Receipt = function(productId, purchaseId)
		serial += 1
		return { ProductId = productId, PurchaseId = purchaseId or ("receipt-" .. serial), PlayerId = player.UserId, CurrencySpent = 99 }
	end
	return h
end

do
	local h = harness()
	local keeper = h.Tags.EggKeeper
	check(keeper and keeper.Name == "EggKeeper" and keeper.Parent == h.World, "The Egg Keeper man is built into the world and tagged")
	check(keeper:FindFirstChild("Torso") and keeper:FindFirstChild("Head") and keeper:FindFirstChildOfClass("Humanoid"), "He is a man (Torso, Head, Humanoid)")
	local heldEgg = keeper:FindFirstChild("HalloweenEgg")
	check(heldEgg ~= nil, "He holds a Halloween egg")
	local prompt = keeper:FindFirstChild("Torso"):FindFirstChildOfClass("ProximityPrompt")
	check(prompt and prompt.ActionText == "Talk" and prompt.MaxActivationDistance == h.Config.EggStore.Npc.PromptDistance, "His ProximityPrompt says Talk")
	check((keeper:FindFirstChild("Torso").Position - h.Config.EggStore.Npc.Position).Magnitude < 5, "He stands at the configured spot beside the zone gate")
end

do -- placement: right of the Zone 1 gate for a player walking in from the plaza, on the plaza side, off the lane
	local npc, map = Config.EggStore.Npc, Config.Map
	local gateX = map.ZonesStartX
	check(npc.Position.Z > map.RoadWidth / 2 + 4, "He stands to the right (+Z) of the gate lane, off the walking road")
	check(npc.Position.X < gateX - 4 and npc.Position.X > gateX - 20, "He stands on the plaza side, a few studs before the gate/zone wall")
	check(npc.FaceTowards.X < npc.Position.X and math.abs(npc.FaceTowards.Z) < npc.Position.Z, "He faces the plaza and the lane")
	check(npc.StoreDistance >= npc.PromptDistance, "The store distance covers the prompt distance")
end

-- Robux config -------------------------------------------------------------------------------------------------
do
	check(S.EggPrice == 99 and M.BundlePrice(S.Bundles[2]) == 267 and M.BundlePrice(S.Bundles[3]) == 634 and S.Luck.Price == 149, "Robux prices: 99 / 267 / 634 / Luck 149")
	for _, key in { "Egg1", "Egg3", "Egg8", "Luck" } do
		check(type(S.Products[key]) == "number" and S.Products[key] == 0, "Product id " .. key .. " is the unset placeholder 0")
	end
	for _, bundle in S.Bundles do
		local truth = 1 - M.BundlePrice(bundle) / (S.EggPrice * bundle.Count)
		check(math.abs(truth - bundle.Discount) < 0.005, "The -" .. bundle.Discount * 100 .. "% badge is true against the single-egg Robux price")
	end
	check(M.ProductFor(0) == nil and M.ProductFor(nil) == nil and M.ProductFor("1001") == nil and M.ProductFor(-5) == nil, "Unset or junk product ids match nothing")
end

do -- valid purchases only OPEN a prompt: nothing is granted or charged until the receipt
	for _, count in { 1, 3, 8 } do
		local h = harness()
		h.Buy(count)
		check(#h.Prompts == 1 and h.Prompts[1][1] == h.Player and h.Prompts[1][2] == IDS["Egg" .. count], "Buy " .. count .. " prompts its own developer product")
		check(#h.Eggs == 0 and h.Profile.Data.Coins == 100000000 and next(h.Profile.Data.ProcessedReceipts) == nil, "Buy " .. count .. " grants nothing before the receipt")
	end
end

do -- receipts grant exactly once
	for _, count in { 1, 3, 8 } do
		local h = harness()
		local receipt = h.Receipt(IDS["Egg" .. count])
		check(h.Service.ProcessReceipt(h.Player, receipt) == true, "Receipt for Buy " .. count .. " is granted")
		check(#h.Eggs == count, "Buy " .. count .. " grants " .. count .. " eggs")
		for _, granted in h.Eggs do check(granted[1] == "HalloweenMonster" and granted[2] == true, "Granted egg is the Halloween egg (quiet)") end
		check(h.Profile.Data.ProcessedReceipts[receipt.PurchaseId] == true and h.Saves[1] >= 1, "The receipt id is recorded and saved")
		check(h.Service.ProcessReceipt(h.Player, receipt) == true and #h.Eggs == count, "A replayed receipt is acknowledged without granting again")
		check(h.Profile.Data.Coins == 100000000, "Coins are never touched")
	end
	local h = harness()
	h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Egg1, "a")); h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Egg1, "b"))
	check(#h.Eggs == 2, "Two different purchases grant two eggs")
end

do -- receipts that must NOT be granted
	local h = harness()
	check(h.Service.ProcessReceipt(h.Player, h.Receipt(999)) == false and #h.Eggs == 0, "A foreign product id is not this store's")
	check(h.Service.ProcessReceipt(h.Player, { ProductId = IDS.Egg1, PurchaseId = "" }) == false, "An empty PurchaseId is not granted")
	check(h.Service.ProcessReceipt(h.Player, { ProductId = IDS.Egg1 }) == false and #h.Eggs == 0, "A missing PurchaseId is not granted")
	check(h.Service.ProcessReceipt({ UserId = 99 }, h.Receipt(IDS.Egg1)) == false and #h.Eggs == 0, "No profile: NotProcessedYet")
	h.Profile.CanSave = false
	check(h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Egg1)) == false and #h.Eggs == 0, "Saving offline: NotProcessedYet")
	h.Profile.CanSave = true
	h.State.SaveOk = false
	local receipt = h.Receipt(IDS.Egg3, "unsaved")
	check(h.Service.ProcessReceipt(h.Player, receipt) == false, "A failed save is NotProcessedYet")
	h.State.SaveOk = true
	local before = #h.Eggs
	check(h.Service.ProcessReceipt(h.Player, receipt) == true and #h.Eggs == before, "The retry after a failed save does not duplicate the eggs")
	local unset = harness(function(config) config.EggStore.Products.Egg1 = 0 end)
	check(unset.Service.ProcessReceipt(unset.Player, unset.Receipt(0)) == false and #unset.Eggs == 0, "Product id 0 never matches a receipt")
end

do -- unset product ids: the prompt is refused with a clear message and nothing is charged
	local h = harness(function(config) for name in IDS do config.EggStore.Products[name] = 0 end end)
	h.Buy(1); h.Buy(3); h.Buy(8); h.BuyLuck()
	check(#h.Prompts == 0 and #h.Eggs == 0 and h.Profile.Data.EggLuckUntil == 0, "Unset ids: no prompt, no grant")
	check(#h.Notes == 4 and h.Notes[1][1]:find("not available yet", 1, true) and h.Notes[1][2] == "info", "Unset ids: a clear 'not available yet' message")
	check(h.Notes[1][1]:find("not charged", 1, true), "...that says nothing was charged")
end

do -- invalid sizes never prompt
	local h = harness()
	for _, bad in { 0, 2, 5, 9, -1, 100, 1e9, 0 / 0, math.huge, 2.5, "8", true, {} } do h.Buy(bad) end
	h.Remotes.BuyEggBundle.OnServerEvent:Fire(h.Player)
	check(#h.Prompts == 0 and #h.Eggs == 0 and #h.Notes == 0, "Invalid counts are ignored without a prompt")
	h.Remotes.BuyEggBundle.OnServerEvent:Fire(h.Player, 3, 1)
	check(#h.Prompts == 1 and h.Prompts[1][2] == IDS.Egg3, "An extra client argument (a fake price or product id) is ignored")
end

do -- one purchase window at a time (so two Luck prompts cannot both pass the cap check)
	local h = harness()
	h.Buy(1); h.Buy(3); h.BuyLuck()
	check(#h.Prompts == 1, "A second prompt cannot open while one is pending")
	h.Finished:Fire(h.Player.UserId, IDS.Egg1, false)
	h.Buy(3)
	check(#h.Prompts == 2 and h.Prompts[2][2] == IDS.Egg3, "After the prompt finishes the next one may open")
end

do -- distance, life, closed store, no profile
	local h = harness()
	h.Root.Position = h.Config.EggStore.Npc.Position + r.Vector3.new(0, 0, -(h.Config.EggStore.Npc.StoreDistance + 5))
	h.Buy(1); h.BuyLuck()
	check(#h.Prompts == 0 and #h.Eggs == 0 and h.Profile.Data.EggLuckUntil == 0, "Buying from far away does nothing")
	h.Root.Position = h.Config.EggStore.Npc.Position
	h.Humanoid.Health = 0
	h.Buy(1)
	check(#h.Prompts == 0, "A dead player cannot buy")
	local closed = harness(function(config) config.Halloween.Enabled = false end)
	check(closed.Tags.EggKeeper == nil, "No Egg Keeper while the Halloween event is off")
	closed.Buy(1)
	check(#closed.Prompts == 0, "The closed store never prompts")
	local ended = harness(function(config) config.Halloween.EndsAt = 1 end)
	ended.Buy(1)
	check(#ended.Prompts == 0, "The store closes when the event has ended")
	local stranger = harness()
	stranger.Remotes.BuyEggBundle.OnServerEvent:Fire({ UserId = 99 }, 1)
	check(#stranger.Prompts == 0, "A player without a profile is ignored")
	local offline = harness()
	offline.Profile.CanSave = false
	offline.Buy(1)
	check(#offline.Prompts == 0, "No prompt while saving is offline")
end

do -- the Talk prompt opens the store, only when close
	local h = harness()
	local prompt = h.Tags.EggKeeper:FindFirstChild("Torso"):FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Fire(h.Player)
	check(h.Remotes.Opened and h.Remotes.Opened[1] == h.Player and h.Remotes.Opened[2].LuckLeft == 0, "Talk opens the store with the Luck state")
	local far = harness()
	far.Root.Position = far.Config.EggStore.Npc.Position + r.Vector3.new(0, 0, -200)
	far.Tags.EggKeeper:FindFirstChild("Torso"):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(far.Player)
	check(far.Remotes.Opened == nil, "A far player cannot open the store")
end

do -- rate limiting
	local h = harness(function(config) config.EggStore.Cooldown = 1e6 end)
	h.Buy(1); h.Buy(1); h.Buy(3); h.BuyLuck()
	check(#h.Prompts == 1, "Rapid requests are rate limited to one prompt per cooldown")
end

do -- the hatch hook applies Luck on the server, to the right egg only
	local h = harness()
	local weights = h.Config.Eggs.HalloweenMonster.Weights
	local hook = h.Service.AdjustHatchWeights
	check(hook(h.Player, "HalloweenMonster", weights) == weights, "Without Luck the original weights are used")
	h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Luck))
	local lucky = hook(h.Player, "HalloweenMonster", weights)
	check(lucky ~= weights and lucky.HalloweenPumpkinKing == weights.HalloweenPumpkinKing * 2 and lucky.HalloweenGhostSlime == weights.HalloweenGhostSlime, "With Luck the rare species are doubled")
	check(hook(h.Player, "Lucky", h.Config.Eggs.Lucky.Weights) == h.Config.Eggs.Lucky.Weights, "Other eggs are never affected")
	h.Advance(S.Luck.Duration + 1)
	check(hook(h.Player, "HalloweenMonster", weights) == weights, "Luck stops when the timer runs out")
	check(hook({ UserId = 99 }, "HalloweenMonster", weights) == weights, "No profile, no Luck")
end

do -- Luck
	local h = harness()
	h.BuyLuck()
	check(#h.Prompts == 1 and h.Prompts[1][2] == IDS.Luck and h.Profile.Data.EggLuckUntil == 0, "Luck prompts its product and grants nothing yet")
	local receipt = h.Receipt(IDS.Luck)
	check(h.Service.ProcessReceipt(h.Player, receipt) == true, "The Luck receipt is granted")
	check(h.Profile.Data.EggLuckUntil == h.Now() + S.Luck.Duration and h.Profile.Data.Coins == 100000000, "Luck lasts one Duration and costs no coins")
	check(h.Saves[1] >= 1 and h.Remotes.State and h.Remotes.State[2].LuckLeft == S.Luck.Duration, "Luck is saved and the client is told the time left")
	check(h.Service.ProcessReceipt(h.Player, receipt) == true and h.Profile.Data.EggLuckUntil == h.Now() + S.Luck.Duration, "A replayed Luck receipt adds no time")
	-- fill the timer to the cap through receipts, then the PROMPT must be refused (Robux never taken for nothing)
	for _ = 1, 10 do h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Luck)) end
	check(h.Profile.Data.EggLuckUntil - h.Now() <= S.Luck.MaxSeconds, "Luck never exceeds the cap")
	check(h.Profile.Data.EggLuckUntil - h.Now() == S.Luck.MaxSeconds, "...and reaches it")
	h.Finished:Fire(h.Player.UserId, IDS.Luck, true)
	local promptCount = #h.Prompts
	h.BuyLuck()
	check(#h.Prompts == promptCount and h.Notes[#h.Notes][2] == "error" and h.Notes[#h.Notes][1]:find("maximum", 1, true), "At the cap the prompt is refused BEFORE any Robux prompt")
	h.Advance(S.Luck.Duration * 2)
	h.BuyLuck()
	check(#h.Prompts == promptCount + 1, "Once time has passed Luck can be bought again")
	h.Service.ProcessReceipt(h.Player, h.Receipt(IDS.Luck))
	check(h.Profile.Data.EggLuckUntil - h.Now() == S.Luck.MaxSeconds - S.Luck.Duration * 2 + S.Luck.Duration, "Luck counts down with time and can be topped up again")
end

-- Real DataService: Luck persists and bad values are cleaned --------------------------------------------------
do
	local stored, serial = {}, 0
	local function copy(value)
		if type(value) ~= "table" then return value end
		local result = {}
		for key, item in value do result[key] = copy(item) end
		return result
	end
	local store = { UpdateAsync = function(_, key, callback)
		local result = callback(copy(stored[key]))
		if result ~= nil then stored[key] = copy(result) end
		return copy(result)
	end }
	local function dataService()
		local services = {
			DataStoreService = { GetDataStore = function() return store end },
			ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
			HttpService = { GenerateGUID = function() serial += 1; return "session-" .. serial end },
			RunService = { IsStudio = function() return false end },
		}
		local modules = { Config = Config, MonsterMath = {} }
		return luau.load(fs.readFile("src/server/DataService.luau"), { environment = environment({
			game = { GetService = function(_, name) return assert(services[name], name) end, BindToClose = function() end },
			require = function(name) return assert(modules[name], name) end,
			task = { wait = function() end, spawn = function(callback, ...) callback(...) end },
			os = { time = function() return 1700000000 end, clock = function() return 0 end },
		}) })()
	end
	local function player(id) return { UserId = id, Name = "P" .. id, Kick = function() end } end
	local ds = dataService()
	stored.Player_1 = { WipeVersion = Config.ProgressWipeVersion, Version = 2, Coins = 50, Monsters = {}, Eggs = {}, Weapons = { Bat = true } }
	check(ds.Load(player(1)).Data.EggLuckUntil == 0, "A save from before the store loads with no Luck")
	stored.Player_2 = { WipeVersion = Config.ProgressWipeVersion, Version = 2, Coins = 50, EggLuckUntil = -5 }
	check(ds.Load(player(2)).Data.EggLuckUntil == 0, "Negative Luck is reset")
	stored.Player_3 = { WipeVersion = Config.ProgressWipeVersion, Version = 2, Coins = 50, EggLuckUntil = 9e99 }
	check(ds.Load(player(3)).Data.EggLuckUntil <= 4e9, "Absurd Luck values are capped")
	local p4 = player(4)
	local profile = ds.Load(p4)
	profile.Data.EggLuckUntil = 1700000900
	check(ds.Save(p4), "Save with Luck succeeds")
	ds.Release(p4)
	check(dataService().Load(player(4)).Data.EggLuckUntil == 1700000900, "Luck time survives a save and reload")
end

-- Wiring and source contracts ---------------------------------------------------------------------------------
local remotes = read("src/shared/Remotes.luau")
for _, name in { "OpenEggStore", "EggStoreState", "BuyEggBundle", "BuyEggLuck" } do
	check(remotes:find('"' .. name .. '"', 1, true), "Remote declared: " .. name)
end
local service, client, server, monster = read("src/server/EggStoreService.luau"), read("src/client/EggStore.luau"), read("src/server/init.server.luau"), read("src/server/MonsterService.luau")
for name in (service .. client):gmatch("remotes%.(%u%w+)") do
	if name:find("Egg") then check(remotes:find('"' .. name .. '"', 1, true), "Used remote exists: " .. name) end
end
check(server:find("EggStoreService.Init(remotes)", 1, true), "Server initialises the Egg Keeper store")
check(read("src/client/init.client.luau"):find("EggStore.Init(ui, remotes", 1, true), "Client starts the store UI")
check(monster:find("MonsterService.AdjustHatchWeights(player, eggData.EggType, egg.Weights)", 1, true) and server:find("MonsterService.AdjustHatchWeights = EggStoreService.AdjustHatchWeights", 1, true), "The server hatch roll goes through the Luck hook")
check(not monster:find("EggStoreMath", 1, true), "MonsterService takes no new require (its test harnesses stay valid)")
check(monster:find("quiet: boolean?", 1, true), "Bundle grants reuse AddEgg (quiet) instead of a second grant path")
check(not service:find("TrySpend", 1, true) and not service:find("Coins", 1, true), "The store never spends or refunds coins")
check(service:find("PromptProductPurchase", 1, true) and service:find("EggStoreMath.FindBundle(count)", 1, true) and service:find("rateLimited(player)", 1, true), "Server validates the bundle, rate limits and prompts a developer product")
check(not service:find("ProcessReceipt =", 1, true), "EggStoreService installs no second MarketplaceService.ProcessReceipt")
local monetization = read("src/server/MonetizationService.luau")
check(server:find("MonetizationService.ProcessEggStoreReceipt = EggStoreService.ProcessReceipt", 1, true) and monetization:find("IsEggStoreProduct(receipt.ProductId)", 1, true), "The existing ProcessReceipt routes egg-store products to EggStoreService")
check(select(2, monetization:gsub("MarketplaceService.ProcessReceipt =", "")) == 1, "Exactly one ProcessReceipt callback exists")
check(not client:find("Coins", 1, true) and client:find('"R$ "', 1, true), "The client shows Robux prices, not coins")
check(not client:find("FireServer%([^)]*[Pp]rice") and not client:find("FireServer%([^)]*[Cc]oins"), "Client sends only a bundle size or nothing")
check(client:find("FireServer(bundle.Count)", 1, true) and client:find("BuyEggLuck:FireServer()", 1, true), "Client sends the bundle size and a bare luck request")
check(not service:find("OnServerEvent:Connect%(function%(player, ?[%w_]+, ?[%w_]+, ?[%w_]+%)"), "No remote handler trusts extra client arguments")

print(string.format("PASS: %d Egg Keeper store checks (odds, bundle pricing, server validation, Luck, persistence, wiring)", checks))
