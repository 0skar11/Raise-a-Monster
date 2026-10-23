--!strict
-- الاقتصاد والتربية: شراء البيض، الفقس، الأكل واللعب، الـ XP والتطور، الإنتاج، البيع والترقيات.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local CharacterService = require(script.Parent.CharacterService)
local FollowerService = require(script.Parent.FollowerService)

type Remotes = { [string]: RemoteEvent }

local MonsterService = {}

-- الوحوش اللي حد شايلها دلوقتي (بيتملى من StealService): carried[owner][monsterId] = true
MonsterService.Carried = {} :: { [Player]: { [string]: boolean } }
-- العروض المفتوحة محجوزة لحد تأكيد أو إلغاء التبادل.
MonsterService.Trading = {} :: { [Player]: { [string]: boolean } }

-- Hooks بتتربط في init.server (عشان مايبقاش فيه require دايري بين الخدمات)
MonsterService.HasPass = function(_player: Player, _name: string): boolean
	return false
end
MonsterService.ExtraState = function(_player: Player): { [string]: any }
	return {}
end

local remotes: Remotes
local lastPlay: { [Player]: { [string]: number } } = {}
local lastAction: { [Player]: number } = {}
local lastCollect: { [Player]: number } = {}
local lastFeed: { [Player]: { [string]: number } } = {}
local lastAutoFeed: { [Player]: number } = {}
type OfflineEarnings = { Id: string, SecondsAway: number, CoinsEarned: number, CollectiblePending: number, MonstersGrown: number }
local offlineEarnings: { [Player]: OfflineEarnings } = {}

-- Temporary event multiplier on live income only (Halloween Candy Boost). It is deliberately NOT
-- folded into GetCoinMultiplier, so it is never saved as the offline-income multiplier.
MonsterService.GetEventMultiplier = function(_player: Player): number
	return 1
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.15 then
		return true
	end
	lastAction[player] = now
	return false
end

function MonsterService.Notify(player: Player, text: string, kind: string?)
	remotes.Notify:FireClient(player, text, kind or "info")
end

function MonsterService.IsCarried(owner: Player, monsterId: string): boolean
	local set = MonsterService.Carried[owner]
	return set ~= nil and set[monsterId] == true
end

function MonsterService.IsUnavailable(owner: Player, monsterId: string): boolean
	local trading = MonsterService.Trading[owner]
	return MonsterService.IsCarried(owner, monsterId) or (trading ~= nil and trading[monsterId] == true)
end

function MonsterService.IsPlaced(player: Player, monster: MonsterMath.MonsterData): boolean
	return monster.Slot >= 1 and monster.Slot % 1 == 0 and monster.Slot <= MonsterService.GetUnlockedSlots(player)
end

function MonsterService.GetUnlockedSlots(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local extra = if MonsterService.HasPass(player, "ExtraSlots") then Config.ExtraSlotsAmount else 0
	return math.min(Config.MaxSlots, Config.BaseSlots + (profile.Data.SlotUpgrades or 0) + extra)
end

function MonsterService.GetFreeSlot(player: Player): number?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, monster in profile.Data.Monsters do
		if MonsterService.IsPlaced(player, monster) then used[monster.Slot] = true end
	end
	for _, egg in profile.Data.Eggs do
		used[egg.Slot] = true
	end
	for slot = 1, MonsterService.GetUnlockedSlots(player) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

function MonsterService.CountMonsters(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local count = 0
	for _ in profile.Data.Monsters do
		count += 1
	end
	return count
end

-- بيبعت للاعب نسخة من بياناته + أرقام محسوبة عشان الواجهة.
function MonsterService.PushState(player: Player)
	local profile = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not profile or not plot then
		return
	end
	local data = profile.Data
	local now = os.clock()

	local followingIds = FollowerService.GetIds(player)
	local monsters = {}
	local placedCount = 0
	for id, monster in data.Monsters do
		local species = Config.Species[monster.Species]
		local played = lastPlay[player] and lastPlay[player][id] or 0
		local placed = MonsterService.IsPlaced(player, monster)
		if placed then placedCount += 1 end
		table.insert(monsters, {
			Id = id,
			Species = monster.Species,
			DisplayName = MonsterMath.GetDisplayName(monster),
			Rarity = species.Rarity,
			Mutation = monster.Mutation,
			Level = monster.Level,
			Xp = monster.Xp,
			XpNeeded = Config.XpForLevel(monster.Level),
			MaxLevel = monster.Level >= Config.MaxLevel,
			Stage = MonsterMath.GetStage(monster.Level).Name,
			Hunger = monster.Hunger,
			Happiness = monster.Happiness,
			Production = MonsterMath.GetProduction(monster),
			SellValue = MonsterMath.GetSellValue(monster),
			FoodCost = MonsterMath.GetFoodCost(monster),
			PlayReadyIn = math.max(0, Config.MiniGames.Cooldown - (now - played)),
			Slot = monster.Slot,
			Placed = placed,
			Benched = not placed,
			Available = not MonsterService.IsUnavailable(player, id),
			InTrade = MonsterService.Trading[player] ~= nil and MonsterService.Trading[player][id] == true,
			ActualIncome = MonsterMath.GetProduction(monster) * MonsterService.GetCoinMultiplier(player),
			Hat = monster.Hat,
			Glasses = monster.Glasses,
			Carried = MonsterService.IsCarried(player, id),
			Following = table.find(followingIds, id) ~= nil,
			CanFollow = FollowerService.IsEligible(player, monster),
		})
	end

	local eggs = {}
	local nowTime = os.time()
	for _, egg in data.Eggs do
		table.insert(eggs, {
			Id = egg.Id,
			Slot = egg.Slot,
			EggType = egg.EggType,
			SecondsLeft = math.max(0, egg.HatchAt - nowTime),
		})
	end

	local nextSlotCost = Config.SlotUpgradeCosts[data.SlotUpgrades + 1]
	local nextLockCost = Config.LockUpgradeCosts[data.LockUpgrades + 1]

	PlotService.SetUpgradeLabel(
		player,
		if nextSlotCost then string.format("⬆️ New slot · 💰 %s\n%d / %d slots", MonsterMath.FormatNumber(nextSlotCost), MonsterService.GetUnlockedSlots(player), Config.MaxSlots)
			else "⬆️ Slots MAX"
	)

	local state: { [string]: any } = {
		Coins = data.Coins,
		PendingCoins = data.PendingCoins,
		OfflineEarnings = offlineEarnings[player],
		UnlockedSlots = MonsterService.GetUnlockedSlots(player),
		MaxSlots = Config.MaxSlots,
		NextSlotCost = nextSlotCost,
		LockDuration = Config.LockDuration + data.LockUpgrades * Config.LockDurationPerUpgrade,
		NextLockCost = nextLockCost,
		LockedFor = math.max(0, plot.LockedUntil - now),
		LockCooldown = math.max(0, plot.LockCooldownUntil - now),
		Monsters = monsters,
		PlacedCount = placedCount,
		BenchCount = #monsters - placedCount,
		FollowingIds = followingIds,
		FollowerLimit = Config.Followers.MaxCount,
		FollowerMinLevel = FollowerService.GetMinLevel(),
		FollowerDamageBonus = FollowerService.GetDamageBonus(player),
		Eggs = eggs,
		Stats = data.Stats,
		SaveDisabled = profile.LoadFailed,
		Accessories = data.Accessories,
		SpeedAccessories = data.SpeedAccessories,
		Weapons = data.Weapons,
		EquippedWeapon = data.EquippedWeapon,
		EquippedSpeedAccessory = data.EquippedSpeedAccessory,
		SpeedAccessoryMultiplier = CharacterService.GetSpeedAccessoryMultiplier(data.SpeedAccessories, data.EquippedSpeedAccessory),
		CoinMultiplier = MonsterService.GetCoinMultiplier(player),
	}
	for key, value in MonsterService.ExtraState(player) do
		state[key] = value
	end

	remotes.StateUpdate:FireClient(player, state)
end

-- VIP بيضاعف الفلوس
function MonsterService.GetCoinMultiplier(player: Player): number
	local multiplier = if MonsterService.HasPass(player, "VIP") then Config.VIPCoinMultiplier else 1
	return multiplier * (if MonsterService.HasPass(player, "CoinBoost") then Config.CoinBoostMultiplier else 1)
end

local function saveInventory(player: Player)
	MonsterService.PushState(player)
	DataService.QueueSave(player)
end

-- النقل والتبديل بيتحققوا بالكامل على السيرفر، وبدون حذف أي ملكية.
function MonsterService.PlaceMonster(player: Player, id: unknown, slot: unknown): (boolean, string)
	if type(id) ~= "string" or #id == 0 or #id > 128 or type(slot) ~= "number"
		or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > MonsterService.GetUnlockedSlots(player) then
		return false, "Choose an unlocked slot."
	end
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[id]
	if not profile or not monster or MonsterService.IsUnavailable(player, id) then return false, "This monster is unavailable." end
	for _, egg in profile.Data.Eggs do
		if egg.Slot == slot then return false, "That slot has an egg." end
	end
	local displaced: MonsterMath.MonsterData? = nil
	for otherId, other in profile.Data.Monsters do
		if otherId ~= id and other.Slot == slot then
			if MonsterService.IsUnavailable(player, otherId) then return false, "That slot is reserved." end
			displaced = other
			break
		end
	end
	if monster.Slot == slot then return true, "Already placed here." end
	local oldSlot = if MonsterService.IsPlaced(player, monster) then monster.Slot else 0
	monster.Slot = slot
	if displaced then displaced.Slot = oldSlot end
	PlotService.RemoveMonster(player, id)
	if displaced then PlotService.RemoveMonster(player, displaced.Id) end
	PlotService.RenderMonster(player, monster)
	if displaced and displaced.Slot > 0 then PlotService.RenderMonster(player, displaced) end
	saveInventory(player)
	return true, if displaced then "Monsters swapped. Your collection is safe." else "Monster placed."
end

function MonsterService.BenchMonster(player: Player, id: unknown): (boolean, string)
	if type(id) ~= "string" or #id == 0 or #id > 128 then return false, "Invalid monster." end
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[id]
	if not monster or MonsterService.IsUnavailable(player, id) then return false, "This monster is unavailable." end
	monster.Slot = 0
	PlotService.RemoveMonster(player, id)
	saveInventory(player)
	return true, "Monster moved to your bench."
end

function MonsterService.AutoPlace(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then return false, "Your collection is loading." end
	local unlocked = MonsterService.GetUnlockedSlots(player)
	local reserved: { [number]: boolean } = {}
	for _, egg in profile.Data.Eggs do
		if egg.Slot >= 1 and egg.Slot <= unlocked then reserved[egg.Slot] = true end
	end
	local candidates: { MonsterMath.MonsterData } = {}
	for id, monster in profile.Data.Monsters do
		if MonsterService.IsUnavailable(player, id) then
			if MonsterService.IsPlaced(player, monster) then reserved[monster.Slot] = true end
		else
			table.insert(candidates, monster)
		end
	end
	-- GetProduction includes level, stage, mutation, accessories and current needs.
	table.sort(candidates, function(a, b)
		local incomeA, incomeB = MonsterMath.GetProduction(a), MonsterMath.GetProduction(b)
		if incomeA ~= incomeB then return incomeA > incomeB end
		local placedA, placedB = MonsterService.IsPlaced(player, a), MonsterService.IsPlaced(player, b)
		if placedA ~= placedB then return placedA end
		return a.Id < b.Id
	end)
	local slots = {}
	for slot = 1, unlocked do if not reserved[slot] then table.insert(slots, slot) end end
	local changed = {}
	for index, monster in candidates do
		local target = slots[index] or 0
		if monster.Slot ~= target then monster.Slot = target; table.insert(changed, monster) end
	end
	-- Commit every assignment before updating models, so slots cannot overlap.
	for _, monster in changed do PlotService.RemoveMonster(player, monster.Id) end
	for _, monster in changed do if monster.Slot > 0 then PlotService.RenderMonster(player, monster) end end
	saveInventory(player)
	return true, "Highest income monsters placed. Others are safe on your bench."
end

-- البيض والفقس --------------------------------------------------------------------

local function rollWeighted(weights: { [string]: number }): string
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = math.random() * total
	local last = ""
	for name, weight in weights do
		last = name
		roll -= weight
		if roll <= 0 then
			return name
		end
	end
	return last
end

-- multiplier بيكبّر فرصة الطفرة (الـ Monster Rain مثلاً)
function MonsterService.RollMutation(multiplier: number?): string?
	for _, mutation in Config.Mutations do
		if math.random() < mutation.Chance * (multiplier or 1) then
			return mutation.Name
		end
	end
	return nil
end
local rollMutation = MonsterService.RollMutation

-- إعلان كبير لكل اللي في السيرفر
function MonsterService.Announce(text: string, color: Color3?)
	remotes.Announce:FireAllClients(text, color or Color3.fromRGB(255, 220, 90))
end

local function buyEgg(player: Player, eggType: unknown)
	if rateLimited(player) or type(eggType) ~= "string" then
		return
	end
	local egg = Config.Eggs[eggType]
	local profile = DataService.Get(player)
	if not egg or not profile or not table.find(Config.ShopEggs, eggType) then
		return
	end
	if not MonsterService.GetFreeSlot(player) then
		MonsterService.Notify(player, "Your base is full! Sell a monster or buy a new slot.", "error")
		return
	end
	if not DataService.TrySpend(player, egg.Cost) then
		MonsterService.Notify(player, "Not enough coins!", "error")
		return
	end
	MonsterService.AddEgg(player, eggType)
end

-- بيحط البيضة في مكان فاضي، أو يحفظ بيضة المكافأة على البنش لحد الفقس.
function MonsterService.AddEgg(player: Player, eggType: string): boolean
	local egg = Config.Eggs[eggType]
	local profile = DataService.Get(player)
	local slot = MonsterService.GetFreeSlot(player) or 0
	if not egg or not profile then
		return false
	end
	local id = DataService.NewId(player)
	profile.Data.Eggs[id] = {
		Id = id,
		EggType = eggType,
		Slot = slot,
		HatchAt = os.time() + egg.HatchTime,
	}
	if slot > 0 then PlotService.RenderEgg(player, id, eggType, slot) end
	MonsterService.Notify(player, "🥚 " .. egg.DisplayName .. (if slot > 0 then " placed in your base!" else " saved to your bench!") .. " Wait for it to hatch.", "success")
	saveInventory(player)
	return true
end

-- بيفقس كل البيض دلوقتي (Developer Product)
function MonsterService.HatchAllNow(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile or next(profile.Data.Eggs) == nil then
		return false
	end
	for _, egg in profile.Data.Eggs do
		egg.HatchAt = 0
	end
	return true
end

local function hatch(player: Player, eggData: DataService.EggData)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local egg = Config.Eggs[eggData.EggType]
	local species = if egg then rollWeighted(egg.Weights) else "Blobby"
	-- بيضة الحظ محصورة في جدولها؛ الأنواع التانية ممكن تطلع Secret.
	local secretChance = Config.SecretChance * (if eggData.EggType == "Lucky" then Config.LuckyEggSecretMultiplier else 1)
	if (not egg or egg.AllowSecret ~= false) and math.random() < secretChance then
		species = Config.SecretSpecies[math.random(1, #Config.SecretSpecies)]
	end
	local monster: MonsterMath.MonsterData = {
		Id = eggData.Id,
		Species = species,
		Mutation = rollMutation(),
		Level = 1,
		Xp = 0,
		Hunger = 100,
		Happiness = 100,
		Slot = eggData.Slot,
		LastProgressAt = os.time(),
	}
	profile.Data.Eggs[eggData.Id] = nil
	profile.Data.Monsters[monster.Id] = monster
	profile.Data.Stats.Hatched += 1

	PlotService.RemoveEgg(player, eggData.Id)
	if MonsterService.IsPlaced(player, monster) then PlotService.RenderMonster(player, monster) end

	local rarity = Config.Species[species].Rarity
	MonsterService.Notify(player, "🐣 Hatched! You got " .. MonsterMath.GetDisplayName(monster) .. " (" .. rarity .. ")", "success")
	if rarity == "Secret" then
		MonsterService.Announce("🌌 " .. player.DisplayName .. " hatched a SECRET monster: " .. MonsterMath.GetDisplayName(monster) .. "!", Color3.fromRGB(200, 120, 255))
	end
end

-- الوحش الجديد يروح أول مكان فاضي، والزيادة محفوظة على البنش.
function MonsterService.AddMonster(player: Player, species: string, mutation: string?): boolean
	local profile = DataService.Get(player)
	local slot = MonsterService.GetFreeSlot(player) or 0
	if not profile or not Config.Species[species] then
		return false
	end
	local monster: MonsterMath.MonsterData = {
		Id = DataService.NewId(player),
		Species = species,
		Mutation = mutation,
		Level = 1,
		Xp = 0,
		Hunger = 100,
		Happiness = 100,
		Slot = slot,
		LastProgressAt = os.time(),
	}
	profile.Data.Monsters[monster.Id] = monster
	if slot > 0 then PlotService.RenderMonster(player, monster) end
	local rarity = Config.Species[species].Rarity
	MonsterService.Notify(player, "🐾 You got " .. MonsterMath.GetDisplayName(monster) .. " (" .. rarity .. ")! " .. (if slot > 0 then "It's in your base." else "Saved to your bench."), "success")
	if rarity == "Secret" then
		MonsterService.Announce("🌌 " .. player.DisplayName .. " got a SECRET monster: " .. MonsterMath.GetDisplayName(monster) .. "!", Color3.fromRGB(200, 120, 255))
	end
	saveInventory(player)
	return true
end

-- بيشيل وحش من بيانات اللاعب ويرجّعه (للـ Trading والـ Arena)
function MonsterService.TakeMonsterData(player: Player, monsterId: string, allowTrade: boolean?): MonsterMath.MonsterData?
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[monsterId]
	if not profile or not monster or MonsterService.IsCarried(player, monsterId)
		or (not allowTrade and MonsterService.IsUnavailable(player, monsterId)) then
		return nil
	end
	profile.Data.Monsters[monsterId] = nil
	FollowerService.Remove(player, monsterId)
	PlotService.RemoveMonster(player, monsterId)
	return monster
end

-- بيحفظ الوحش الجاي من لاعب تاني بنفس مستواه وتجهيزه حتى لو القاعدة مليانة.
function MonsterService.InsertMonsterData(player: Player, monster: MonsterMath.MonsterData): boolean
	local profile = DataService.Get(player)
	local slot = MonsterService.GetFreeSlot(player) or 0
	if not profile or not Config.Species[monster.Species] then
		return false
	end
	local copy: MonsterMath.MonsterData = table.clone(monster)
	copy.Id = DataService.NewId(player)
	copy.Slot = slot
	profile.Data.Monsters[copy.Id] = copy
	if slot > 0 then PlotService.RenderMonster(player, copy) end
	return true
end

-- عدد الأماكن الفاضية (عشان نتأكد قبل الـ Trading)
function MonsterService.CountFreeSlots(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local used: { [number]: boolean } = {}
	local unlocked = MonsterService.GetUnlockedSlots(player)
	for _, monster in profile.Data.Monsters do
		if MonsterService.IsPlaced(player, monster) then used[monster.Slot] = true end
	end
	for _, egg in profile.Data.Eggs do
		if egg.Slot >= 1 and egg.Slot <= unlocked then used[egg.Slot] = true end
	end
	local count = 0
	for slot = 1, unlocked do if not used[slot] then count += 1 end end
	return count
end

-- قوة الضربة من المرافقين المختارين فقط؛ دخل الوحوش ملوش علاقة بالضرر.
function MonsterService.GetAttackDamage(player: Player): number
	return Config.Combat.BaseDamage + FollowerService.GetDamageBonus(player)
end

function MonsterService.GetFollowerDamageBonus(player: Player): number
	return FollowerService.GetDamageBonus(player)
end

local function toggleFollower(player: Player, id: unknown)
	if rateLimited(player) then return end
	local success, message = FollowerService.Toggle(player, id)
	MonsterService.Notify(player, message, if success then "success" else "error")
	MonsterService.PushState(player)
end

-- التربية ---------------------------------------------------------------------------

local function addXp(player: Player, monster: MonsterMath.MonsterData, amount: number)
	local oldLevel = monster.Level
	local oldStage = MonsterMath.GetStageIndex(monster.Level)
	MonsterMath.AddXp(monster, amount)
	if monster.Level == oldLevel then
		return
	end
	local newStage = MonsterMath.GetStageIndex(monster.Level)
	if newStage ~= oldStage then
		if not MonsterService.IsCarried(player, monster.Id) then
			PlotService.UpdateMonster(player, monster, true)
		end
		MonsterService.Notify(
			player,
			"✨ " .. MonsterMath.GetDisplayName(monster) .. " evolved into " .. Config.Stages[newStage].Name .. "!",
			"success"
		)
	else
		PlotService.UpdateMonster(player, monster, false)
	end
end

local function getOwnMonster(player: Player, monsterId: unknown): MonsterMath.MonsterData?
	if type(monsterId) ~= "string" then
		return nil
	end
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local monster = profile.Data.Monsters[monsterId]
	if not monster then
		return nil
	end
	if MonsterService.IsUnavailable(player, monsterId) then
		MonsterService.Notify(player, "This monster is unavailable while carried or offered in a trade.", "error")
		return nil
	end
	return monster
end

-- كل أكلة بتراجع الملكية وتخصم تمنها على السيرفر قبل أي XP أو تحديث للمجسم.
-- الجزء اللي بيخصم ويحدّث الجوع والمهلة مفيهوش أي دالة بتعمل yield.
local function feedOwnedMonster(player: Player, monsterId: string, now: number): (boolean, string?)
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[monsterId]
	if not monster or MonsterService.IsUnavailable(player, monsterId) then
		return false, nil
	end
	local previous = lastFeed[player] and lastFeed[player][monsterId]
	if previous and now - previous < Config.AutoFeeder.FeedCooldown then
		return false, nil
	end
	if monster.Hunger >= 99 then
		return false, "Your monster is already full!"
	end
	if not DataService.TrySpend(player, MonsterMath.GetFoodCost(monster)) then
		return false, "Not enough coins for food!"
	end
	lastFeed[player] = lastFeed[player] or {}
	lastFeed[player][monsterId] = now
	monster.Hunger = math.min(100, monster.Hunger + Config.Food.Hunger)
	addXp(player, monster, Config.Food.Xp)
	PlotService.UpdateMonster(player, monster, false)
	return true, nil
end

local function feed(player: Player, monsterId: unknown)
	if rateLimited(player) then return end
	local monster = getOwnMonster(player, monsterId)
	if not monster then return end
	local fed, message = feedOwnedMonster(player, monster.Id, os.clock())
	if message then MonsterService.Notify(player, message, if monster.Hunger >= 99 then "info" else "error") end
	if fed then MonsterService.PushState(player) end
end

local function autoFeedPlayer(player: Player, now: number)
	local previous = lastAutoFeed[player]
	if previous and now - previous < Config.AutoFeeder.Interval then return end
	-- نعمل محاولة واحدة بعد أي توقف؛ مفيش تعويض أكلات أو XP عن وقت قديم.
	lastAutoFeed[player] = now
	if not MonsterService.HasPass(player, "AutoFeeder") then return end
	local profile = DataService.Get(player)
	if not profile then return end
	for id, monster in profile.Data.Monsters do
		if MonsterService.IsPlaced(player, monster) and monster.Hunger <= Config.AutoFeeder.Threshold then
			feedOwnedMonster(player, id, now)
		end
	end
end

-- ألعاب صغيرة مع الوحش (بدل زرار Play) ----------------------------------------------------
-- Catch: السيرفر يعدّ المحاولات المقبولة ويحدد النقاط؛ نتيجة الكلاينت لا تمنح XP.
-- Run: بتجري مع وحشك، والسيرفر بيقيس المسافة اللي مشيتها بنفسه.

type ActiveGame = { MonsterId: string, Game: string, StartedAt: number, Distance: number, Catches: number, LastCatchAt: number }
local activeGames: { [Player]: ActiveGame } = {}

local function finishGame(player: Player, game: ActiveGame, xp: number)
	if activeGames[player] ~= game then
		return
	end
	activeGames[player] = nil
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[game.MonsterId]
	if monster then
		monster.Happiness = math.min(100, monster.Happiness + Config.MiniGames.Happiness)
		addXp(player, monster, xp)
		PlotService.UpdateMonster(player, monster, false)
	end
	remotes.MiniGameState:FireClient(player, { Game = game.Game, Done = true, Xp = xp })
	MonsterService.Notify(player, string.format("🎮 Great game! +%d XP", xp), "success")
	MonsterService.PushState(player)
end

local function startMiniGame(player: Player, monsterId: unknown, gameName: unknown)
	if rateLimited(player) or (gameName ~= "Catch" and gameName ~= "Run") then
		return
	end
	local monster = getOwnMonster(player, monsterId)
	if not monster or activeGames[player] then
		return
	end
	lastPlay[player] = lastPlay[player] or {}
	local now = os.clock()
	if now - (lastPlay[player][monster.Id] or 0) < Config.MiniGames.Cooldown then
		MonsterService.Notify(player, "Your monster needs a little rest first!", "info")
		return
	end
	lastPlay[player][monster.Id] = now

	local catchSettings = Config.MiniGames.Catch
	local game: ActiveGame = {
		MonsterId = monster.Id,
		Game = gameName :: string,
		StartedAt = now,
		Distance = 0,
		Catches = 0,
		LastCatchAt = now - catchSettings.MinCatchInterval,
	}
	activeGames[player] = game
	if gameName == "Catch" then
		local duration = catchSettings.Duration
		remotes.MiniGameState:FireClient(player, { Game = "Catch", TimeLeft = duration })
		-- لو الكلاينت مابعتش النتيجة، اللعبة بتخلص لوحدها
		task.delay(duration + 6, function()
			finishGame(player, game, game.Catches * catchSettings.XpPerCatch)
		end)
		return
	end

	-- Run: نقيس المسافة كل ربع ثانية
	local settings = Config.MiniGames.Run
	remotes.MiniGameState:FireClient(player, { Game = "Run", TimeLeft = settings.Duration, Progress = 0, Target = settings.Target })
	task.spawn(function()
		local lastPosition: Vector3? = nil
		while activeGames[player] == game and os.clock() - game.StartedAt < settings.Duration do
			task.wait(0.25)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local position = Vector3.new(root.Position.X, 0, root.Position.Z)
				if lastPosition then
					-- حد أقصى للخطوة عشان التليبورت مايتحسبش
					game.Distance += math.min((position - lastPosition).Magnitude, 10)
				end
				lastPosition = position
			end
			remotes.MiniGameState:FireClient(player, {
				Game = "Run",
				TimeLeft = math.max(0, settings.Duration - (os.clock() - game.StartedAt)),
				Progress = math.floor(game.Distance),
				Target = settings.Target,
			})
		end
		local xp = math.floor(math.clamp(game.Distance / settings.Target, 0, 1) * settings.MaxXp)
		finishGame(player, game, xp)
	end)
end

local function recordCatch(player: Player)
	local game = activeGames[player]
	if not game or game.Game ~= "Catch" then
		return
	end
	local settings = Config.MiniGames.Catch
	local now = os.clock()
	if now - game.StartedAt > settings.Duration or game.Catches >= settings.MaxCatches then
		return
	end
	if now - game.LastCatchAt < settings.MinCatchInterval then
		return
	end
	game.LastCatchAt = now
	game.Catches += 1
	remotes.MiniGameState:FireClient(player, { Game = "Catch", Score = game.Catches })
end

local function finishCatch(player: Player)
	local game = activeGames[player]
	if not game or game.Game ~= "Catch" then
		return
	end
	local settings = Config.MiniGames.Catch
	if os.clock() - game.StartedAt < settings.Duration - 1.5 then
		return -- السيرفر لا يقبل الإنهاء قبل انتهاء الجولة
	end
	finishGame(player, game, game.Catches * settings.XpPerCatch)
end

-- الإكسسوارات ------------------------------------------------------------------------------

local function buySpeedAccessory(player: Player, name: unknown)
	if rateLimited(player) or type(name) ~= "string" then
		return
	end
	local accessory = Config.SpeedAccessories[name]
	local profile = DataService.Get(player)
	if not accessory or not profile then
		return
	end
	if type(profile.Data.SpeedAccessories) ~= "table" then return end
	if profile.Data.SpeedAccessories[name] == true then
		MonsterService.Notify(player, "You already own " .. accessory.Name .. "!", "info")
		return
	end
	if not DataService.TrySpend(player, accessory.Price) then
		MonsterService.Notify(player, "Not enough coins!", "error")
		return
	end
	profile.Data.SpeedAccessories[name] = true
	profile.Data.EquippedSpeedAccessory = name
	CharacterService.ApplySpeedAccessory(player, profile.Data.SpeedAccessories, name)
	MonsterService.Notify(player, "🏃 You bought " .. accessory.Name .. "!", "success")
	MonsterService.PushState(player)
	task.spawn(DataService.Save, player)
end

local lastGearEquip: { [Player]: number } = {}
local function equipSpeedAccessory(player: Player, name: unknown)
	if name ~= nil and (type(name) ~= "string" or #name > 64 or not Config.SpeedAccessories[name]) then return end
	local profile = DataService.Get(player)
	if not profile or type(profile.Data.SpeedAccessories) ~= "table" then return end
	if name ~= nil and profile.Data.SpeedAccessories[name] ~= true then return end
	local now = os.clock()
	if lastGearEquip[player] and now - lastGearEquip[player] < Config.Security.GearEquipCooldown then return end
	lastGearEquip[player] = now
	if profile.Data.EquippedSpeedAccessory == name then return end
	profile.Data.EquippedSpeedAccessory = name :: string?
	CharacterService.ApplySpeedAccessory(player, profile.Data.SpeedAccessories, name :: string?)
	MonsterService.PushState(player)
	DataService.QueueSave(player)
end

local function buyAccessory(player: Player, name: unknown, monsterId: unknown)
	if rateLimited(player) or type(name) ~= "string" then
		return
	end

	local accessory = Config.Accessories[name]
	local profile = DataService.Get(player)
	if not accessory or not profile then
		return
	end
	if profile.Data.Accessories[name] then
		MonsterService.Notify(player, "You already own " .. accessory.Name .. "!", "info")
		return
	end
	if not DataService.TrySpend(player, accessory.Cost) then
		MonsterService.Notify(player, "Not enough coins!", "error")
		return
	end
	profile.Data.Accessories[name] = true
	MonsterService.Notify(player, "👒 You bought " .. accessory.Name .. "!", "success")
	-- بيلبسها على طول للوحش اللي اشتراها عشانه
	local monster = getOwnMonster(player, monsterId)
	if monster and monster.Species == accessory.Species then
		if accessory.Slot == "Hat" then
			monster.Hat = name
		else
			monster.Glasses = name
		end
		PlotService.UpdateMonster(player, monster, true)
	end
	MonsterService.PushState(player)
end

local function equipAccessory(player: Player, monsterId: unknown, slot: unknown, name: unknown)
	if rateLimited(player) or (slot ~= "Hat" and slot ~= "Glasses") then
		return
	end
	local monster = getOwnMonster(player, monsterId)
	local profile = DataService.Get(player)
	if not monster or not profile then
		return
	end
	local chosen: string? = nil
	if name ~= nil then
		if type(name) ~= "string" then
			return
		end
		local accessory = Config.Accessories[name]
		if not accessory or accessory.Slot ~= slot or accessory.Species ~= monster.Species or not profile.Data.Accessories[name] then
			return
		end
		chosen = name
	end
	if slot == "Hat" then
		monster.Hat = chosen
	else
		monster.Glasses = chosen
	end
	PlotService.UpdateMonster(player, monster, true)
	MonsterService.PushState(player)
end

local function sell(player: Player, monsterId: unknown)
	if rateLimited(player) then
		return
	end
	local monster = getOwnMonster(player, monsterId)
	local profile = DataService.Get(player)
	if not monster or not profile then
		return
	end
	local value = MonsterMath.GetSellValue(monster)
	profile.Data.Monsters[monster.Id] = nil
	FollowerService.Remove(player, monster.Id)
	DataService.AddCoins(player, value)
	PlotService.RemoveMonster(player, monster.Id)
	MonsterService.Notify(player, "Sold " .. MonsterMath.GetDisplayName(monster) .. " for " .. MonsterMath.FormatNumber(value) .. " 💰", "success")
	MonsterService.PushState(player)
end

-- Called from the base's upgrade pad (PlotService.Callbacks.Upgrade); there is no remote for this anymore.
function MonsterService.BuyUpgrade(player: Player, upgrade: unknown)
	if rateLimited(player) then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	if upgrade == "Slots" then
		local cost = Config.SlotUpgradeCosts[data.SlotUpgrades + 1]
		if not cost or MonsterService.GetUnlockedSlots(player) >= Config.MaxSlots then
			MonsterService.Notify(player, "You already have the max number of slots!", "info")
			return
		end
		if not DataService.TrySpend(player, cost) then
			MonsterService.Notify(player, "Not enough coins!", "error")
			return
		end
		data.SlotUpgrades += 1
		PlotService.SetUnlockedSlots(player, MonsterService.GetUnlockedSlots(player))
		MonsterService.Notify(player, "🏠 New slot unlocked!", "success")
	elseif upgrade == "Lock" then
		local cost = Config.LockUpgradeCosts[data.LockUpgrades + 1]
		if not cost then
			MonsterService.Notify(player, "Your lock is already max level!", "info")
			return
		end
		if not DataService.TrySpend(player, cost) then
			MonsterService.Notify(player, "Not enough coins!", "error")
			return
		end
		data.LockUpgrades += 1
		MonsterService.Notify(player, "🔒 Your base lock now lasts longer!", "success")
	else
		return
	end
	MonsterService.PushState(player)
end

-- القاعدة -------------------------------------------------------------------------------

function MonsterService.Collect(player: Player)
	local now = os.clock()
	if lastCollect[player] and now - lastCollect[player] < 0.5 then
		return
	end
	lastCollect[player] = now
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local amount = math.floor(profile.Data.PendingCoins)
	if amount <= 0 then
		return
	end
	profile.Data.PendingCoins -= amount
	DataService.AddCoins(player, amount)
	PlotService.SetPending(player, profile.Data.PendingCoins)
	MonsterService.Notify(player, "+" .. MonsterMath.FormatNumber(amount) .. " 💰", "coins")
	MonsterService.PushState(player)
end

function MonsterService.Lock(player: Player)
	local plot = PlotService.GetPlot(player)
	local profile = DataService.Get(player)
	if not plot or not profile then
		return
	end
	local now = os.clock()
	if now < plot.LockedUntil then
		MonsterService.Notify(player, "Your base is already locked.", "info")
		return
	end
	if now < plot.LockCooldownUntil then
		MonsterService.Notify(player, string.format("Wait %ds before locking again.", math.ceil(plot.LockCooldownUntil - now)), "error")
		return
	end
	local duration = Config.LockDuration + profile.Data.LockUpgrades * Config.LockDurationPerUpgrade
	plot.LockedUntil = now + duration
	plot.LockCooldownUntil = plot.LockedUntil + Config.LockCooldown
	MonsterService.Notify(player, "🔒 Base locked for " .. duration .. " seconds!", "success")
	MonsterService.PushState(player)
end

local function updateLockVisual(player: Player)
	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local now = os.clock()
	if now < plot.LockedUntil then
		PlotService.SetLockVisual(plot, true, string.format("🔒 Locked %ds", math.ceil(plot.LockedUntil - now)))
	elseif now < plot.LockCooldownUntil then
		PlotService.SetLockVisual(plot, false, string.format("⏳ Ready in %ds", math.ceil(plot.LockCooldownUntil - now)))
	else
		PlotService.SetLockVisual(plot, false, "🔓 Lock Base")
	end
end

-- اللوب الأساسي ------------------------------------------------------------------------

local function prepareProgress(player: Player)
	if offlineEarnings[player] then return end
	local profile = DataService.Get(player)
	if not profile then return end
	local data = profile.Data
	local slots = data.IncomeUnlockedSlots or (Config.BaseSlots + (data.SlotUpgrades or 0))
	local multiplier = data.IncomeMultiplier or 1
	if slots ~= slots or math.abs(slots) == math.huge then slots = Config.BaseSlots end
	if multiplier ~= multiplier or math.abs(multiplier) == math.huge then multiplier = 1 end
	slots = math.clamp(math.floor(slots), 0, Config.MaxSlots)
	multiplier = math.clamp(multiplier, 1, Config.VIPCoinMultiplier * Config.CoinBoostMultiplier)
	local now, coins, secondsAway, grown = os.time(), 0, 0, 0
	for _, monster in data.Monsters do
		local previous = monster.LastProgressAt
		if type(previous) == "number" and previous == previous and previous >= 0 and previous <= now then
			secondsAway = math.max(secondsAway, now - previous)
		end
		local stage = MonsterMath.GetStageIndex(monster.Level)
		coins += MonsterMath.AdvanceProgress(monster, now, monster.Slot >= 1 and monster.Slot <= slots, multiplier)
		if MonsterMath.GetStageIndex(monster.Level) > stage then grown += 1 end
	end
	data.PendingCoins += coins
	-- Stored in the same atomic profile snapshot as the consumed timestamps.
	data.IncomeMultiplier = MonsterService.GetCoinMultiplier(player)
	data.IncomeUnlockedSlots = MonsterService.GetUnlockedSlots(player)
	offlineEarnings[player] = {
		Id = profile.SessionId or tostring(now), SecondsAway = secondsAway,
		CoinsEarned = coins, CollectiblePending = math.floor(data.PendingCoins), MonstersGrown = grown,
	}
end

local function tickPlayer(player: Player, dt: number)
	local profile = DataService.Get(player)
	if not profile or not PlotService.GetPlot(player) then
		return
	end
	-- Pass lookup can yield before SetupPlayer. Settle the saved interval first.
	prepareProgress(player)
	local data = profile.Data
	local multiplier = MonsterService.GetCoinMultiplier(player)
	local progressAt = os.time()
	data.IncomeMultiplier = multiplier
	data.IncomeUnlockedSlots = MonsterService.GetUnlockedSlots(player)
	local okEvent, eventValue = pcall(MonsterService.GetEventMultiplier, player)
	local eventMultiplier = if okEvent and type(eventValue) == "number" and eventValue >= 1 and eventValue < 100 then eventValue else 1

	for id, monster in data.Monsters do
		local oldStage = MonsterMath.GetStageIndex(monster.Level)
		local producing = MonsterService.IsPlaced(player, monster) and not MonsterService.IsCarried(player, id)
		data.PendingCoins += MonsterMath.AdvanceProgress(monster, progressAt, producing, multiplier * eventMultiplier)
		if producing then
			local evolved = MonsterMath.GetStageIndex(monster.Level) ~= oldStage
			PlotService.UpdateMonster(player, monster, evolved)
			if evolved then MonsterService.Notify(player, "✨ " .. MonsterMath.GetDisplayName(monster) .. " evolved into " .. MonsterMath.GetStage(monster.Level).Name .. "!", "success") end
		end
	end

	autoFeedPlayer(player, os.clock())

	local now = os.time()
	for _, egg in data.Eggs do
		if now >= egg.HatchAt then
			hatch(player, egg)
		elseif egg.Slot > 0 then
			PlotService.UpdateEggTimer(player, egg.Id, egg.EggType, egg.HatchAt - now)
		end
	end

	-- Players start with a bat and collect monsters from the zones; no automatic eggs.

	-- Auto-Collect: الفلوس بتروح المحفظة لوحدها
	if MonsterService.HasPass(player, "AutoCollect") and data.PendingCoins >= 1 then
		local amount = math.floor(data.PendingCoins)
		data.PendingCoins -= amount
		DataService.AddCoins(player, amount)
	end

	PlotService.SetPending(player, data.PendingCoins)
	updateLockVisual(player)
	MonsterService.PushState(player)
end

-- بيرسم كل حاجة اللاعب يملكها لما يدخل.
function MonsterService.SetupPlayer(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local data = profile.Data

	local unlocked = MonsterService.GetUnlockedSlots(player)
	-- Marketplace can still be checking ExtraSlots. Keep saved assignments until
	-- ownership is known; locked slots remain inactive and cannot earn income.
	DataService.NormalizeMonsterSlots(data, Config.MaxSlots)
	prepareProgress(player)
	PlotService.SetUnlockedSlots(player, unlocked)
	for _, monster in data.Monsters do
		if MonsterService.IsPlaced(player, monster) then PlotService.RenderMonster(player, monster) end
	end
	for _, egg in data.Eggs do
		if egg.Slot > 0 and egg.Slot <= unlocked then PlotService.RenderEgg(player, egg.Id, egg.EggType, egg.Slot) end
	end
	PlotService.SetPending(player, data.PendingCoins)
	MonsterService.PushState(player)
end

function MonsterService.CleanupPlayer(player: Player)
	offlineEarnings[player] = nil
	FollowerService.CleanupPlayer(player)
	lastPlay[player] = nil
	activeGames[player] = nil
	lastAction[player] = nil
	lastCollect[player] = nil
	lastGearEquip[player] = nil
	lastFeed[player] = nil
	lastAutoFeed[player] = nil
	MonsterService.Carried[player] = nil
	MonsterService.Trading[player] = nil
end

function MonsterService.OpenMonster(who: Player, owner: Player, monsterId: string)
	if who ~= owner then
		return
	end
	remotes.OpenMonster:FireClient(who, monsterId)
end

function MonsterService.Init(allRemotes: Remotes)
	remotes = allRemotes
	FollowerService.Init(MonsterService.IsUnavailable, MonsterService.PushState)
	local function inventoryAction(action: (Player, any, any) -> (boolean, string), player: Player, id: any?, slot: any?)
		if rateLimited(player) then return end
		local success, message = action(player, id, slot)
		MonsterService.Notify(player, message, if success then "success" else "error")
	end
	if remotes.PlaceMonster then remotes.PlaceMonster.OnServerEvent:Connect(function(player, id, slot) inventoryAction(MonsterService.PlaceMonster, player, id, slot) end) end
	if remotes.BenchMonster then remotes.BenchMonster.OnServerEvent:Connect(function(player, id) inventoryAction(MonsterService.BenchMonster :: any, player, id) end) end
	if remotes.AutoPlaceMonsters then remotes.AutoPlaceMonsters.OnServerEvent:Connect(function(player) inventoryAction(MonsterService.AutoPlace :: any, player) end) end
	remotes.ToggleFollower.OnServerEvent:Connect(toggleFollower)
	remotes.BuyEgg.OnServerEvent:Connect(buyEgg)
	remotes.FeedMonster.OnServerEvent:Connect(feed)
	remotes.MiniGameStart.OnServerEvent:Connect(startMiniGame)
	remotes.MiniGameCatch.OnServerEvent:Connect(recordCatch)
	remotes.MiniGameFinish.OnServerEvent:Connect(finishCatch)
	remotes.BuyAccessory.OnServerEvent:Connect(buyAccessory)
	remotes.BuySpeedAccessory.OnServerEvent:Connect(buySpeedAccessory)
	remotes.EquipSpeedAccessory.OnServerEvent:Connect(equipSpeedAccessory)
	remotes.EquipAccessory.OnServerEvent:Connect(equipAccessory)
	remotes.SellMonster.OnServerEvent:Connect(sell)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.NeedsTickInterval)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				task.spawn(tickPlayer, player, dt)
			end
		end
	end)
end

return MonsterService
