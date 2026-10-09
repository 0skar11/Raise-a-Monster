--!strict
-- الاقتصاد والتربية: شراء البيض، الفقس، الأكل واللعب، الـ XP والتطور، الإنتاج، البيع والترقيات.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Remotes = { [string]: RemoteEvent }

local MonsterService = {}

-- الوحوش اللي حد شايلها دلوقتي (بيتملى من StealService): carried[owner][monsterId] = true
MonsterService.Carried = {} :: { [Player]: { [string]: boolean } }

local remotes: Remotes
local lastPlay: { [Player]: { [string]: number } } = {}
local lastAction: { [Player]: number } = {}
local lastCollect: { [Player]: number } = {}

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

function MonsterService.GetUnlockedSlots(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return math.min(Config.MaxSlots, Config.BaseSlots + profile.Data.SlotUpgrades)
end

function MonsterService.GetFreeSlot(player: Player): number?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, monster in profile.Data.Monsters do
		used[monster.Slot] = true
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

	local monsters = {}
	for id, monster in data.Monsters do
		local species = Config.Species[monster.Species]
		local played = lastPlay[player] and lastPlay[player][id] or 0
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
			PlayReadyIn = math.max(0, Config.Play.Cooldown - (now - played)),
			Slot = monster.Slot,
			Carried = MonsterService.IsCarried(player, id),
		})
	end

	local eggs = {}
	local nowTime = os.time()
	for _, egg in data.Eggs do
		table.insert(eggs, {
			Id = egg.Id,
			EggType = egg.EggType,
			SecondsLeft = math.max(0, egg.HatchAt - nowTime),
		})
	end

	local nextSlotCost = Config.SlotUpgradeCosts[data.SlotUpgrades + 1]
	local nextLockCost = Config.LockUpgradeCosts[data.LockUpgrades + 1]

	remotes.StateUpdate:FireClient(player, {
		Coins = data.Coins,
		PendingCoins = data.PendingCoins,
		UnlockedSlots = MonsterService.GetUnlockedSlots(player),
		MaxSlots = Config.MaxSlots,
		NextSlotCost = nextSlotCost,
		LockDuration = Config.LockDuration + data.LockUpgrades * Config.LockDurationPerUpgrade,
		NextLockCost = nextLockCost,
		LockedFor = math.max(0, plot.LockedUntil - now),
		LockCooldown = math.max(0, plot.LockCooldownUntil - now),
		Monsters = monsters,
		Eggs = eggs,
		Stats = data.Stats,
		SaveDisabled = profile.LoadFailed,
	})
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

local function rollMutation(): string?
	for _, mutation in Config.Mutations do
		if math.random() < mutation.Chance then
			return mutation.Name
		end
	end
	return nil
end

local function buyEgg(player: Player, eggType: unknown)
	if rateLimited(player) or type(eggType) ~= "string" then
		return
	end
	local egg = Config.Eggs[eggType]
	local profile = DataService.Get(player)
	if not egg or not profile then
		return
	end
	local slot = MonsterService.GetFreeSlot(player)
	if not slot then
		MonsterService.Notify(player, "Your base is full! Sell a monster or buy a new slot.", "error")
		return
	end
	if not DataService.TrySpend(player, egg.Cost) then
		MonsterService.Notify(player, "Not enough coins!", "error")
		return
	end
	local id = DataService.NewId(player)
	profile.Data.Eggs[id] = {
		Id = id,
		EggType = eggType,
		Slot = slot,
		HatchAt = os.time() + egg.HatchTime,
	}
	PlotService.RenderEgg(player, id, eggType, slot)
	MonsterService.Notify(player, egg.DisplayName .. " placed in your base! Wait for it to hatch.", "success")
	MonsterService.PushState(player)
end

local function hatch(player: Player, eggData: DataService.EggData)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local egg = Config.Eggs[eggData.EggType]
	local species = if egg then rollWeighted(egg.Weights) else "Blobby"
	local monster: MonsterMath.MonsterData = {
		Id = eggData.Id,
		Species = species,
		Mutation = rollMutation(),
		Level = 1,
		Xp = 0,
		Hunger = 100,
		Happiness = 100,
		Slot = eggData.Slot,
	}
	profile.Data.Eggs[eggData.Id] = nil
	profile.Data.Monsters[monster.Id] = monster
	profile.Data.Stats.Hatched += 1

	PlotService.RemoveEgg(player, eggData.Id)
	PlotService.RenderMonster(player, monster)

	local rarity = Config.Species[species].Rarity
	MonsterService.Notify(player, "🐣 Hatched! You got " .. MonsterMath.GetDisplayName(monster) .. " (" .. rarity .. ")", "success")
end

-- التربية ---------------------------------------------------------------------------

local function addXp(player: Player, monster: MonsterMath.MonsterData, amount: number)
	if monster.Level >= Config.MaxLevel then
		monster.Xp = 0
		return
	end
	local oldStage = MonsterMath.GetStageIndex(monster.Level)
	monster.Xp += amount
	local leveled = false
	while monster.Level < Config.MaxLevel and monster.Xp >= Config.XpForLevel(monster.Level) do
		monster.Xp -= Config.XpForLevel(monster.Level)
		monster.Level += 1
		leveled = true
	end
	if not leveled then
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
	if MonsterService.IsCarried(player, monsterId) then
		MonsterService.Notify(player, "This monster is being stolen! Catch the thief!", "error")
		return nil
	end
	return monster
end

local function feed(player: Player, monsterId: unknown)
	if rateLimited(player) then
		return
	end
	local monster = getOwnMonster(player, monsterId)
	if not monster then
		return
	end
	if monster.Hunger >= 99 then
		MonsterService.Notify(player, "Your monster is already full!", "info")
		return
	end
	if not DataService.TrySpend(player, MonsterMath.GetFoodCost(monster)) then
		MonsterService.Notify(player, "Not enough coins for food!", "error")
		return
	end
	monster.Hunger = math.min(100, monster.Hunger + Config.Food.Hunger)
	addXp(player, monster, Config.Food.Xp)
	PlotService.UpdateMonster(player, monster, false)
	MonsterService.PushState(player)
end

local function play(player: Player, monsterId: unknown)
	if rateLimited(player) then
		return
	end
	local monster = getOwnMonster(player, monsterId)
	if not monster then
		return
	end
	lastPlay[player] = lastPlay[player] or {}
	local now = os.clock()
	local last = lastPlay[player][monster.Id] or 0
	if now - last < Config.Play.Cooldown then
		return
	end
	lastPlay[player][monster.Id] = now
	monster.Happiness = math.min(100, monster.Happiness + Config.Play.Happiness)
	addXp(player, monster, Config.Play.Xp)
	PlotService.UpdateMonster(player, monster, false)
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
	DataService.AddCoins(player, value)
	PlotService.RemoveMonster(player, monster.Id)
	MonsterService.Notify(player, "Sold " .. MonsterMath.GetDisplayName(monster) .. " for " .. MonsterMath.FormatNumber(value) .. " 💰", "success")
	MonsterService.PushState(player)
end

local function buyUpgrade(player: Player, upgrade: unknown)
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

local function tickPlayer(player: Player, dt: number)
	local profile = DataService.Get(player)
	if not profile or not PlotService.GetPlot(player) then
		return
	end
	local data = profile.Data

	for id, monster in data.Monsters do
		monster.Hunger = math.max(0, monster.Hunger - Config.HungerDecayPerSecond * dt)
		monster.Happiness = math.max(0, monster.Happiness - Config.HappinessDecayPerSecond * dt)
		if not MonsterService.IsCarried(player, id) then
			data.PendingCoins += MonsterMath.GetProduction(monster) * dt
			if monster.Hunger >= 50 and monster.Happiness >= 50 then
				addXp(player, monster, Config.PassiveXpPerSecond * dt)
			end
			PlotService.UpdateMonster(player, monster, false)
		end
	end

	local now = os.time()
	for _, egg in data.Eggs do
		if now >= egg.HatchAt then
			hatch(player, egg)
		else
			PlotService.UpdateEggTimer(player, egg.Id, egg.EggType, egg.HatchAt - now)
		end
	end

	-- ضمان إن مفيش لاعب يعلق من غير وحوش ولا فلوس.
	if next(data.Monsters) == nil and next(data.Eggs) == nil and data.Coins + data.PendingCoins < Config.Eggs.Basic.Cost then
		local id = DataService.NewId(player)
		data.Eggs[id] = { Id = id, EggType = "Basic", Slot = 1, HatchAt = os.time() + 5 }
		PlotService.RenderEgg(player, id, "Basic", 1)
		MonsterService.Notify(player, "🎁 Here is a free egg to get you back on your feet!", "success")
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

	-- أول مرة يلعب: بيضة مجانية عشان يبدأ على طول.
	if next(data.Monsters) == nil and next(data.Eggs) == nil and data.Stats.Hatched == 0 then
		local id = DataService.NewId(player)
		data.Eggs[id] = { Id = id, EggType = "Basic", Slot = 1, HatchAt = os.time() + 5 }
	end

	PlotService.SetUnlockedSlots(player, MonsterService.GetUnlockedSlots(player))
	for _, monster in data.Monsters do
		PlotService.RenderMonster(player, monster)
	end
	for _, egg in data.Eggs do
		PlotService.RenderEgg(player, egg.Id, egg.EggType, egg.Slot)
	end
	PlotService.SetPending(player, data.PendingCoins)
	MonsterService.PushState(player)
end

function MonsterService.CleanupPlayer(player: Player)
	lastPlay[player] = nil
	lastAction[player] = nil
	lastCollect[player] = nil
	MonsterService.Carried[player] = nil
end

function MonsterService.OpenMonster(who: Player, owner: Player, monsterId: string)
	if who ~= owner then
		return
	end
	remotes.OpenMonster:FireClient(who, monsterId)
end

function MonsterService.Init(allRemotes: Remotes)
	remotes = allRemotes
	remotes.BuyEgg.OnServerEvent:Connect(buyEgg)
	remotes.FeedMonster.OnServerEvent:Connect(feed)
	remotes.PlayMonster.OnServerEvent:Connect(play)
	remotes.SellMonster.OnServerEvent:Connect(sell)
	remotes.BuyUpgrade.OnServerEvent:Connect(buyUpgrade)

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
