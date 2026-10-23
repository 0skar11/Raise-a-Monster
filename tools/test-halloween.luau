-- Halloween 2026 event: config sanity, pure rules (HalloweenLogic), real DataService migration/persistence,
-- and wiring/source contracts. HalloweenService itself needs a Studio playtest (see docs/Halloween-2026.md).
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

local Config = load("src/shared/Config.luau")
local Logic = load("src/shared/HalloweenLogic.luau")
local H = Config.Halloween
local items = H.Items

-- Config -----------------------------------------------------------------------------------------------
check(H.Enabled == true and H.Name == "Halloween 2026" and H.EndsAt == 0, "Event is on by default and has no scheduled end")
check(H.CandyToCoinRate > 0, "Leftover Candy converts to cash at a positive configurable rate")
check(H.Invasion.Interval == 3600 and H.Invasion.AnnounceBefore == 60 and H.Invasion.MinCount == 3, "Invasion: hourly, 1 minute warning, min 3")
check(H.Pumpkins.Interval == 1800 and H.Pumpkins.Count == 5 and H.Pumpkins.Lifetime == 120, "Pumpkin hunt: 30 min, 5 pumpkins, 2 minute life")
check(H.Pumpkins.CandyMin == 3 and H.Pumpkins.CandyMax == 10 and H.Pumpkins.GoldenCandy == 50, "Pumpkin rewards 3-10, golden 50")
check(H.Invasion.ParticipationFraction == 0.05 and H.Invasion.CandyPerLevel == 5, "5% HP threshold and level x 5 Candy")
check(H.Pumpkins.Offset % H.Invasion.Interval ~= 0, "Hunt and invasion never start on the same second")
for id, item in items do
	check(item.Cost > 0 and item.Order > 0 and item.Name ~= "" and item.Kind ~= "", id .. " is fully described")
end
for _, id in { "CandyBoost", "PumpkinHat", "GhostTrail", "CandyAura", "HalloweenTitle", "HauntedEgg", "GhostSlime", "SkeletonImp", "PumpkinKing" } do
	check(items[id] ~= nil, "Shop sells " .. id)
end
local mostExpensive = 0
for _, item in items do mostExpensive = math.max(mostExpensive, item.Cost) end
check(items.PumpkinKing.Cost == mostExpensive and items.PumpkinKing.Unique == true, "Pumpkin King is the most expensive and one per player")
check(items.CandyBoost.Multiplier == 2 and items.CandyBoost.Duration == 600, "Candy Boost is 2x for 10 minutes")
for id, item in items do
	if item.Kind == "Monster" then
		local species = Config.Species[item.Species]
		check(species ~= nil and Config.Rarities[species.Rarity] ~= nil and Config.Followers.DamagePerRarity[species.Rarity] ~= nil, id .. " species is a valid game monster")
		for eggName, egg in Config.Eggs do check(egg.Weights[item.Species] == nil, id .. " is exclusive, not in egg " .. eggName) end
	end
end
local total, rare, mythic = 0, Config.Eggs.Rare.Order, Config.Eggs.Mythic.Order
for eggType, weight in items.HauntedEgg.EggWeights do
	local egg = Config.Eggs[eggType]
	check(egg ~= nil and egg.Order >= rare and egg.Order <= mythic and egg.Cost > 0, "Haunted Egg only rolls real purchasable eggs from Rare up to Mythic: " .. eggType)
	total += weight
end
check(total > 0 and items.HauntedEgg.EggWeights.Rare > items.HauntedEgg.EggWeights.Mythic, "Mythic Haunted Eggs are rarer than Rare ones")

-- Invasion count: min 3, 3-6 common, bigger waves rare ----------------------------------------------------
local counts, samples = {}, 100000
for i = 0, samples - 1 do
	local n = Logic.RollInvasionCount(H.Invasion, i / samples)
	counts[n] = (counts[n] or 0) + 1
end
local common, minimum = 0, math.huge
for n, c in counts do
	minimum = math.min(minimum, n)
	if n >= 3 and n <= 6 then common += c end
end
check(minimum == 3, "A wave never has fewer than 3 Mothers")
check(common / samples > 0.85, "3-6 Mothers make up the large majority of waves")
for n = 7, 10 do check((counts[n] or 0) < (counts[6] or 0), "Waves of " .. n .. " are rarer than waves of 6") end
check(Logic.RollInvasionCount({ MinCount = 3, CountWeights = { [1] = 5, [2] = 5 } }, 0.5) == 3, "Weights below the minimum are ignored")
check(Logic.RollInvasionCount(H.Invasion, 5) >= 3 and Logic.RollInvasionCount(H.Invasion, -1) >= 3, "Out of range rolls stay valid")

-- Level scaling -----------------------------------------------------------------------------------------
local inv = H.Invasion
check(Logic.HealthForLevel(inv, inv.MinLevel) == inv.HealthAtMinLevel and Logic.HealthForLevel(inv, inv.MaxLevel) == inv.HealthAtMaxLevel, "Mother HP spans the configured range")
local previous = 0
for level = inv.MinLevel, inv.MaxLevel do
	local hp = Logic.HealthForLevel(inv, level)
	check(hp >= previous, "Mother HP never drops with level")
	previous = hp
end
check(Logic.DamageForLevel(inv, 1) == inv.DamageAtMinLevel and Logic.DamageForLevel(inv, inv.MaxLevel) == inv.DamageAtMaxLevel, "Mother damage spans the configured range")
check(Logic.CandyForMother(inv, 12) == 60 and Logic.CandyForMother(inv, 60) == 300, "Candy = Mother level x 5")

-- Damage tracking / who gets rewarded ---------------------------------------------------------------------
local tracker = Logic.NewTracker(1000)
check(tracker:Record(1, 50) == 50 and tracker:Record(2, 49.9) == 49.9, "Damage is recorded per UserId")
check(tracker:Record(3, -5) == 0 and tracker:Record(3, 0) == 0 and tracker:Record(3, 0 / 0) == 0, "Negative, zero and NaN damage are ignored")
check(tracker:Record("x" :: any, 10) == 0, "A non-numeric id is ignored")
local participants = tracker:Participants(0.05)
check(#participants == 1 and participants[1] == 1, "Exactly 5% qualifies, 4.99% does not")
tracker:Record(2, 0.1)
check(#tracker:Participants(0.05) == 2, "A second player crossing the line is rewarded too (no stealing)")
local overkill = Logic.NewTracker(100)
check(overkill:Record(1, 1e9) == 100 and overkill.Health == 0 and overkill:Record(2, 50) == 0, "Overkill is clipped and a dead Mother takes no more damage")
local settled = Logic.Settle(overkill, inv, 20)
check(#settled == 1 and settled[1].UserId == 1 and settled[1].Candy == 100, "Settling pays level x 5 Candy to the participant")
local team = Logic.NewTracker(10000)
team:Record(10, 5000); team:Record(11, 3999); team:Record(12, 600); team:Record(13, 400)
local paid = Logic.Settle(team, inv, 30)
local byId = {}
for _, entry in paid do byId[entry.UserId] = entry.Candy end
check(byId[10] == 150 and byId[11] == 150 and byId[12] == 150 and byId[13] == nil, "Every player at or above 5% is paid in full, the killer gets no bonus or steal")
check(Logic.QualifiesForReward(5, 100, 0.05) and not Logic.QualifiesForReward(4.9, 100, 0.05) and not Logic.QualifiesForReward(1, 0, 0.05), "Qualification edge cases")

-- Pumpkins ------------------------------------------------------------------------------------------------
local seen = {}
for i = 0, 999 do
	local candy = Logic.PumpkinCandy(H.Pumpkins, false, i / 1000)
	check(candy >= 3 and candy <= 10, "Normal pumpkin gives 3-10 Candy")
	seen[candy] = true
end
for candy = 3, 10 do check(seen[candy], "Every value 3-10 can be rolled") end
check(Logic.PumpkinCandy(H.Pumpkins, true, 0.5) == 50 and Logic.PumpkinCandy(H.Pumpkins, false, 5) == 10, "Golden pumpkin is 50 and rolls are clamped")

-- Hints never reveal the spot --------------------------------------------------------------------------------
check(Logic.HintSector(0, 0, 10, 0) == 0 and Logic.HintSector(0, 0, 0, 10) == 2 and Logic.HintSector(0, 0, -10, 0) == 4 and Logic.HintSector(0, 0, 0, -10) == 6, "Compass sectors")
local s1, b1 = Logic.Hint(0, 0, { { X = 50, Z = 3 } }, H.Pumpkins.HintBands)
local s2, b2 = Logic.Hint(0, 0, { { X = 61, Z = -9 } }, H.Pumpkins.HintBands)
check(s1 == s2 and b1 == b2 and s1 == 0 and b1 == 2, "Different spots in the same sector/band give the identical hint")
local sector, band = Logic.Hint(0, 0, { { X = 500, Z = 500 }, { X = 20, Z = 0 } }, H.Pumpkins.HintBands)
check(sector == 0 and band == 1, "Hint points at the nearest pumpkin")
check(Logic.Hint(0, 0, {}, H.Pumpkins.HintBands) == nil, "No pumpkins, no hint")
check(select("#", Logic.Hint(0, 0, { { X = 1, Z = 1 } }, H.Pumpkins.HintBands)) == 2, "Only a sector and a band come back")
local dx, dz = Logic.SectorDirection(2)
check(math.abs(dx) < 1e-9 and math.abs(dz - 1) < 1e-9, "Sector direction")

-- Scheduling ----------------------------------------------------------------------------------------------
check(Logic.NextOccurrence(7200, 3600, 0) == 10800 and Logic.NextOccurrence(7199, 3600, 0) == 7200, "Next hourly slot is strictly in the future")
check(Logic.NextOccurrence(1000, 1800, 900) == 2700 and Logic.NextOccurrence(900, 1800, 900) == 2700, "Offset slots")

-- Purchases ----------------------------------------------------------------------------------------------
local function fresh(candy) return { Candy = candy, TotalCandy = candy, BoostUntil = 0, Converted = 0, Owned = {}, Equipped = {} } end
local now = 1000000
local data = fresh(100)
local ok, reason = Logic.ApplyPurchase(data, "CandyBoost", items, now, 0.5)
check(not ok and reason == "NoCandy" and data.Candy == 100, "Cannot buy without enough Candy, nothing is charged")
check(select(2, Logic.ApplyPurchase(data, "Nope", items, now, 0.5)) == "Unknown" and select(2, Logic.ApplyPurchase(data, 42, items, now, 0.5)) == "Unknown", "Unknown and non-string ids are rejected")
data = fresh(10000)
ok, reason = Logic.ApplyPurchase(data, "CandyBoost", items, now, 0.5)
check(ok and data.Candy == 10000 - items.CandyBoost.Cost and data.BoostUntil == now + 600, "Candy Boost charges and starts a 10 minute timer")
check(Logic.CashMultiplier(data, now + 599, items) == 2 and Logic.CashMultiplier(data, now + 600, items) == 1 and Logic.CashMultiplier(fresh(0), now, items) == 1, "2x cash only while the boost lasts")
Logic.ApplyPurchase(data, "CandyBoost", items, now + 300, 0.5)
check(data.BoostUntil == now + 1200, "Buying again adds time instead of stacking the multiplier")
for _ = 1, 10 do Logic.ApplyPurchase(data, "CandyBoost", items, now, 0.5) end
check(data.BoostUntil - now <= items.CandyBoost.MaxBoostSeconds, "Stored boost time is capped")
check(select(2, Logic.ApplyPurchase(data, "CandyBoost", items, now, 0.5)) == "BoostCap", "Reports the cap")
data = fresh(100000)
for _, id in { "PumpkinHat", "GhostTrail", "CandyAura", "HalloweenTitle" } do
	ok = Logic.ApplyPurchase(data, id, items, now, 0.5)
	check(ok and data.Owned[id] and data.Equipped[items[id].Kind] == id, id .. " is owned and equipped")
	check(select(2, Logic.ApplyPurchase(data, id, items, now, 0.5)) == "Owned", id .. " cannot be bought twice")
end
check(Logic.SetEquipped(data, "PumpkinHat", items, false) and data.Equipped.Hat == nil, "Unequip works")
check(Logic.SetEquipped(data, "PumpkinHat", items, true) and data.Equipped.Hat == "PumpkinHat", "Re-equip works")
check(not Logic.SetEquipped(data, "CandyBoost", items, true) and not Logic.SetEquipped(data, "GhostSlime", items, true) and not Logic.SetEquipped(fresh(0), "PumpkinHat", items, true), "Cannot equip boosts, monsters or unowned items")
check(not Logic.SetEquipped(data, { }, items, true), "Garbage ids are rejected")
-- Haunted Egg: a real egg type from the configured weights
data = fresh(100000)
local eggs = {}
for i = 0, 99 do
	local good, _, purchase = Logic.ApplyPurchase(data, "HauntedEgg", items, now, i / 100)
	check(good and purchase.Kind == "Egg" and Config.Eggs[purchase.EggType] ~= nil, "Haunted Egg resolves to a real Config.Eggs entry")
	eggs[purchase.EggType] = (eggs[purchase.EggType] or 0) + 1
end
check(eggs.Rare and eggs.Mythic and eggs.Rare > eggs.Mythic and (eggs.Lucky or 0) == 0 and (eggs.Basic or 0) == 0 and (eggs.Secret or 0) == 0, "Eggs roll between Rare and Mythic with Rare more common")
-- monsters, undo, and Pumpkin King uniqueness
data = fresh(100000)
local before = data.Candy
local _, _, king = Logic.ApplyPurchase(data, "PumpkinKing", items, now, 0.5)
check(king.Species == "HalloweenPumpkinKing" and data.Owned.PumpkinKing and data.Candy == before - items.PumpkinKing.Cost, "Pumpkin King is charged and recorded")
check(select(2, Logic.ApplyPurchase(data, "PumpkinKing", items, now, 0.5)) == "Owned", "Pumpkin King is one per player")
king.Undo()
check(data.Candy == before and data.Owned.PumpkinKing == nil, "A failed delivery fully refunds and un-owns")
local _, _, slime = Logic.ApplyPurchase(data, "GhostSlime", items, now, 0.5)
local _, _, again = Logic.ApplyPurchase(data, "GhostSlime", items, now, 0.5)
check(slime.Species == "HalloweenGhostSlime" and again ~= nil and data.Owned.GhostSlime == nil, "Non-unique monsters can be bought repeatedly")
local _, _, imp = Logic.ApplyPurchase(data, "SkeletonImp", items, now, 0.5)
check(imp.Species == "HalloweenSkeletonImp", "Skeleton Imp sells the exclusive imp")
-- Candy ledger and conversion
data = fresh(5)
check(Logic.AwardCandy(data, 10, 100) == 10 and data.Candy == 15 and data.TotalCandy == 15, "Awarding Candy adds to balance and lifetime total")
check(Logic.AwardCandy(data, 1000, 100) == 85 and data.Candy == 100, "Candy is capped")
check(Logic.AwardCandy(data, -5, 100) == 0 and Logic.AwardCandy(data, 0 / 0, 100) == 0 and Logic.AwardCandy(data, math.huge, 10) == 0, "Bad amounts are ignored")
data.Candy = 37
local coins, candy = Logic.ConvertAll(data, 20)
check(coins == 740 and candy == 37 and data.Candy == 0 and data.Converted == 740, "Leftover Candy is converted to coins, not zeroed")
coins = Logic.ConvertAll(data, 20)
check(coins == 0 and data.Converted == 740, "Converting twice cannot pay twice")
check(Logic.ConvertCandy(-3, 20) == 0 and Logic.ConvertCandy(0 / 0, 20) == 0 and Logic.ConvertCandy(2.9, 10) == 20, "Conversion edge cases")

-- DataService: migration-safe default, sanitising, persistence round trip --------------------------------
local stored, serial = {}, 0
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
local store = {
	UpdateAsync = function(_, key, callback)
		local result = callback(copy(stored[key]))
		if result ~= nil then stored[key] = copy(result) end
		return copy(result)
	end,
}
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
-- a pre-event save has no Halloween key at all
stored.Player_1 = { Version = 2, Coins = 4321, Monsters = {}, Eggs = {}, Weapons = { Bat = true } }
local profile = ds.Load(player(1))
check(not profile.LoadFailed and profile.Data.Coins == 4321, "Legacy save still loads")
local h = profile.Data.Halloween
check(h and h.Candy == 0 and h.TotalCandy == 0 and h.BoostUntil == 0 and h.Converted == 0 and next(h.Owned) == nil and next(h.Equipped) == nil, "Legacy save gets the Halloween defaults")
-- garbage in the Halloween block is cleaned, not trusted
stored.Player_2 = { Version = 2, Coins = 1, Halloween = { Candy = -50, TotalCandy = "lots", BoostUntil = 0 / 0, Owned = { PumpkinHat = true, Fake = true, GhostTrail = "yes" }, Equipped = { Hat = "PumpkinHat", Trail = "GhostTrail", Aura = "Nope" } } }
local cleaned = ds.Load(player(2)).Data.Halloween
check(cleaned.Candy == 0 and cleaned.TotalCandy == 0 and cleaned.BoostUntil == 0, "Negative, NaN and wrong-type numbers reset to zero")
check(cleaned.Owned.PumpkinHat and not cleaned.Owned.Fake and not cleaned.Owned.GhostTrail, "Unknown and non-true ownership entries are dropped")
check(cleaned.Equipped.Hat == "PumpkinHat" and cleaned.Equipped.Trail == nil and cleaned.Equipped.Aura == nil, "Only owned items in the right slot stay equipped")
stored.Player_3 = { Version = 2, Coins = 1, Halloween = "broken" }
check(not ds.Load(player(3)).LoadFailed, "A non-table Halloween value cannot block a load")
-- candy persists across a save/load
local p4 = player(4)
local profile4 = ds.Load(p4)
profile4.Data.Halloween.Candy = 777
profile4.Data.Halloween.TotalCandy = 900
profile4.Data.Halloween.Owned.PumpkinKing = true
profile4.Data.Halloween.BoostUntil = 1700000600
check(ds.Save(p4), "Save with Candy succeeds")
ds.Release(p4)
local reload = dataService().Load(player(4)).Data.Halloween
check(reload.Candy == 777 and reload.TotalCandy == 900 and reload.Owned.PumpkinKing == true and reload.BoostUntil == 1700000600, "Candy, purchases and boost time persist")

-- wiring and source contracts ------------------------------------------------------------------------------
local function read(path) return fs.readFile(path) end
local remotes = read("src/shared/Remotes.luau")
for _, name in { "HalloweenState", "HalloweenOpenShop", "HalloweenHint", "HalloweenBuy", "HalloweenEquip", "HalloweenSync" } do
	check(remotes:find('"' .. name .. '"', 1, true), "Remote declared: " .. name)
end
local service, ui = read("src/server/HalloweenService.luau"), read("src/client/HalloweenUI.luau")
for text in (service .. ui):gmatch("remotes%.(Halloween%w+)") do
	check(remotes:find('"' .. text .. '"', 1, true), "Used remote exists: " .. text)
end
local server = read("src/server/init.server.luau")
check(server:find("HalloweenService.Init(remotes)", 1, true) and server:find("MonsterService.GetEventMultiplier = HalloweenService.GetCashMultiplier", 1, true), "Server initialises the event and links the cash multiplier")
check(server:find("HalloweenService.SetupPlayer(player)", 1, true) and server:find("HalloweenService.CleanupPlayer(player)", 1, true) and server:find("HalloweenService.OnCharacter(player)", 1, true), "Join, leave and respawn are handled")
check(read("src/client/init.client.luau"):find("HalloweenUI.Init(ui, remotes)", 1, true), "Client starts the Halloween UI")
local monsterService = read("src/server/MonsterService.luau")
check(monsterService:find("multiplier * eventMultiplier", 1, true) and monsterService:find("data.IncomeMultiplier = multiplier\r?\n"), "Candy Boost affects live income but is not saved as the offline multiplier")
check(service:find("settings.Enabled ~= true", 1, true) and service:find("EndsAt", 1, true) and service:find("restoreAtmosphere()", 1, true), "Event is gated by the config flag and restores the lighting when it ends")
check(service:find("nearMerchant(player)", 1, true) and service:find("PickupDistance", 1, true) and service:find("PickupDebounce", 1, true), "Server re-checks shop and pumpkin distance and debounces pickups")
check(not service:find("OnServerEvent:Connect%(function%(player, ?[%w_]+, ?[%w_]+, ?[%w_]+%)"), "No remote handler trusts extra client arguments")
-- the client never sends an amount, price or position
check(not ui:find("FireServer%([^)]*[Cc]ost") and not ui:find("FireServer%([^)]*Candy"), "Client sends only item ids")

-- event-only night: held by reasons (Invasion / Hunt), union semantics, smooth fade, hard restore on Stop
local startBody = service:match("function HalloweenService%.Start%(%).-\nend\n") or ""
check(startBody ~= "" and not startBody:find("applyAtmosphere", 1, true) and not startBody:find("fadeToNight", 1, true), "Starting the event does not turn the night on by itself")
check(service:find('setNight("Invasion", true) -- night falls with the 60 s warning', 1, true), "Night falls with the Mother Invasion warning")
check(service:find('setNight("Invasion", spawned > 0)', 1, true) and service:find('setNight("Invasion", false)', 1, true), "Invasion night is released when the Mothers are gone (repelled, retreated, or none spawned)")
check(service:find('setNight("Hunt", true)', 1, true) and service:find('setNight("Hunt", false)', 1, true), "Pumpkin Hunt night lasts exactly as long as the hunt")
check(service:find("for _, held in nightHolds do", 1, true) and service:find("if wanted == nightTarget then", 1, true), "Overlapping events share one night (any hold keeps it; no restore mid-event)")
check(service:find("nightToken ~= token or snapshot ~= saved", 1, true), "A fade back to day that is overtaken by a new event never destroys the lighting snapshot")
check(service:find("TweenService:Create(instance, TweenInfo.new(seconds", 1, true) and Config.Halloween.Atmosphere.FadeSeconds > 0, "Night fades in and out with a configurable tween")
local stopBody = service:match("function HalloweenService%.Stop%(%).-\nend\n") or ""
check(stopBody:find("table.clear(nightHolds)", 1, true) and stopBody:find("restoreAtmosphere()", 1, true), "Stop clears the holds and restores the day lighting immediately")
do
	local a = Config.Halloween.Atmosphere
	check(a.Brightness >= 1.5 and a.Ambient.R + a.Ambient.G + a.Ambient.B >= 1.1 and a.FogEnd >= 1500 and a.AtmosphereDensity <= 0.35, "Event night is brighter than the first version (configurable)")
	check(a.ClockTime < 4 and a.Brightness <= 3 and a.Ambient.B > a.Ambient.G, "...but is still clearly a purple night")
end
-- one Candy display: the authored CandyCounter GUI driven by CandyCounter.luau
local candyClient = read("src/client/CandyCounter.luau")
check(candyClient:find('WaitForChild("CandyCounter"', 1, true) and not candyClient:find('Instance.new("ScreenGui")', 1, true), "CandyCounter finds the authored GUI and never creates it")
check(candyClient:find("HalloweenState.OnClientEvent", 1, true) and candyClient:find("CompactMoney.Format", 1, true) and candyClient:find("state.Enabled == true", 1, true), "CandyCounter shows state.Candy compactly and hides when the event is off")
check(read("src/client/init.client.luau"):find("task.spawn(CandyCounter.Init,", 1, true), "Client starts the Candy counter on its own thread")
check(not ui:find("candyLabel", 1, true), "The old Candy pill number is gone from HalloweenUI")
-- Studio-authored persistent world: the server ADOPTS Workspace.HalloweenWorld, never rebuilds/moves/destroys it
check(service:find('CollectionService:GetTagged(TAG_MERCHANT)', 1, true) and service:find('"HalloweenMerchant"', 1, true), "Merchant is found by the HalloweenMerchant tag")
check(service:find('authored:FindFirstChild("Props")', 1, true) or service:find('world:FindFirstChild("Props")', 1, true), "Props are adopted from Workspace.HalloweenWorld.Props")
check(service:find("local function merchantPart()", 1, true) and service:find("local merchant = merchantPart()", 1, true), "Shop distance is measured from the merchant's CURRENT position")
check(not service:find("settings.Merchant.Position", 1, true) or service:find("buildDefaultMerchant", 1, true), "Config position is only used by the fallback merchant")
check(service:find("merchantRoot", 1, true) == nil, "No cached merchant position/root is used for the shop check any more")
do
	local adopt = service:match("local function adoptMerchant%(%).-\nend\n") or ""
	check(adopt ~= "" and adopt:find("findMerchantModel()", 1, true) and adopt:find("buildDefaultMerchant()", 1, true), "adoptMerchant builds the default only when no authored merchant exists")
	check(not adopt:find("PivotTo", 1, true) and not adopt:find(":Destroy()", 1, true) and not adopt:find(".CFrame", 1, true) and not adopt:find(".Position =", 1, true), "Adopting the merchant never moves or destroys him")
	local build = service:match("local function buildProps%(%).-\n\tlocal a = settings.Atmosphere") or ""
	check(build:find("propFolder = authored", 1, true) and build:find("#authored:GetChildren() > 0", 1, true) and not build:find(":Destroy()", 1, true), "Existing props are adopted untouched; defaults are built only when none exist")
	local stop = service:match("function HalloweenService%.Stop%(%).-\nend\n") or ""
	check(stop:find("hideWorld()", 1, true) and not stop:find('HalloweenWorld"):Destroy', 1, true), "Stopping the event stashes the authored world instead of destroying it")
	local hide = service:match("local function hideWorld%(%).-\nend\n") or ""
	check(hide:find('GetAttribute("AutoBuilt")', 1, true) and hide:find("world.Parent = nil", 1, true), "Only auto-built fallback worlds are destroyed; authored ones are stashed")
	local start = service:match("function HalloweenService%.Start%(%).-\nend\n") or ""
	check(start:find('workspace:FindFirstChild("HalloweenEvent")', 1, true) and not start:find('FindFirstChild("HalloweenWorld")', 1, true) and start:find("showWorld()", 1, true), "Start rebuilds only the runtime HalloweenEvent folder and restores the authored world")
end
check(ui:find('GetTagged("HalloweenMerchant")', 1, true) and not ui:find('"PumpkinMerchant"', 1, true), "The shop panel closes by distance to the tagged (possibly moved) merchant")
do
	local decor = read("src/client/HalloweenDecor.luau")
	check(decor:find("HalloweenSpider", 1, true) and decor:find("HalloweenFloat", 1, true) and decor:find("HalloweenEyes", 1, true) and decor:find("HalloweenMerchant", 1, true), "Client decor animation covers spiders, floating props, eyes and the merchant")
	check(decor:find("state.Base = current", 1, true) and not decor:find("FireServer", 1, true), "Decor idle motion re-bases on external moves and never talks to the server")
	check(read("src/client/init.client.luau"):find("task.spawn(HalloweenDecor.Init)", 1, true), "Client starts the decor animations on their own thread")
end
-- The shop monsters have real rigged models (MonsterModels region 6 "Halloween") and never spawn in the wild.
for index, species in { "HalloweenGhostSlime", "HalloweenSkeletonImp", "HalloweenPumpkinKing" } do
	local definition = Config.Species[species]
	check(definition and definition.Model and definition.Model.Region == 6 and definition.Model.Index == index and definition.EventOnly == true, species .. " has a rigged model and is event-only")
end
check(service:find("species.Model and not species.EventOnly", 1, true), "Event-only monsters are never picked for Mother Invasions")
check(Config.Halloween.Invasion.Mothers == nil and not service:find("custom.Health", 1, true), "Invasions use the game's regular Mothers (no extra Halloween Mother types)")
check(service:find("HauntedGlow", 1, true) and service:find("SpookyWisps", 1, true) and service:find("PumpkinEmbers", 1, true), "Invasion Mothers get Halloween effects")
check(service:find("Color3.fromRGB(205, 62, 14)", 1, true), "Hunt pumpkins use the approved squat red-orange look")
check(service:find('if regionInfo then regionInfo.Region else "Void"', 1, true) and Config.MotherAttacks.Elements.Void, "Event Mothers fall back to the Void element (Halloween region is not a zone region)")
check(Config.Camera.MinZoom > 0 and Config.Camera.MaxZoom > Config.Camera.MinZoom, "Camera zoom limits are configured")
check(read("src/client/init.client.luau"):find("CameraMaxZoomDistance", 1, true), "Client applies the camera zoom limit")
local rigs = read("src/server/MonsterModels.luau")
check(rigs:find('name = "Halloween"', 1, true) and rigs:find('rarity = "Mythic"', 1, true) and rigs:find("def.rarity or RARITY_ORDER", 1, true), "MonsterModels defines the Halloween region with explicit rarities")
check(rigs:find("build it from code, once, on demand", 1, true), "Regions missing from the saved Studio rigs are built on demand")

print(string.format("PASS: %d Halloween checks (config, rules, rewards, shop, persistence/migration, wiring)", checks))
