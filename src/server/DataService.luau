--!strict
-- حفظ وتحميل بيانات اللاعبين باستخدام DataStoreService.
-- لو التحميل فشل، اللاعب بيلعب ببيانات مؤقتة ومش بنحفظ فوق بياناته القديمة.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)

export type EggData = {
	Id: string,
	EggType: string,
	Slot: number,
	HatchAt: number,
}

export type PlayerData = {
	Version: number,
	Coins: number,
	PendingCoins: number,
	TotalEarned: number,
	Monsters: { [string]: MonsterMath.MonsterData },
	Eggs: { [string]: EggData },
	SlotUpgrades: number,
	LockUpgrades: number,
	NextId: number,
	Stats: { Hatched: number, Steals: number, TimesRobbed: number, ArenaWins: number },
	Accessories: { [string]: boolean }, -- الإكسسوارات اللي اللاعب اشتراها
	SpeedAccessories: { [string]: boolean },
	Weapons: { [string]: boolean },
	Daily: { LastClaim: number, Streak: number },
	LastSpin: number,
}

export type Profile = {
	Data: PlayerData,
	LoadFailed: boolean,
}

local DEFAULT_DATA: PlayerData = {
	Version = 1,
	Coins = Config.StartingCoins,
	PendingCoins = 0,
	TotalEarned = 0,
	Monsters = {},
	Eggs = {},
	SlotUpgrades = 0,
	LockUpgrades = 0,
	NextId = 1,
	Stats = { Hatched = 0, Steals = 0, TimesRobbed = 0, ArenaWins = 0 },
	Accessories = {},
	SpeedAccessories = {},
	Weapons = {},
	Daily = { LastClaim = 0, Streak = 0 },
	LastSpin = 0,
}

local MAX_RETRIES = 3

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (enable Studio Access to API Services):", result)
	end
end

local profiles: { [Player]: Profile } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- يضيف أي مفاتيح جديدة اتضافت للـ DEFAULT_DATA من غير ما يمسح القديم.
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			reconcile(target[key], value)
		end
	end
end

local function withRetries<T>(callback: () -> T): (boolean, T | string)
	local lastError: any
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(attempt)
	end
	return false, tostring(lastError)
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local DataService = {}

function DataService.Load(player: Player): Profile
	local data: PlayerData = deepCopy(DEFAULT_DATA)
	local loadFailed = false

	if store then
		local dataStore = store :: DataStore
		local ok, result = withRetries(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			if type(result) == "table" then
				data = result :: any
				reconcile(data :: any, DEFAULT_DATA :: any)
			end
		else
			loadFailed = true
			warn("[DataService] Failed to load data for", player.Name, result)
		end
	else
		loadFailed = true
	end

	local profile: Profile = { Data = data, LoadFailed = loadFailed }
	profiles[player] = profile
	return profile
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.Save(player: Player): boolean
	local profile = profiles[player]
	if not profile or profile.LoadFailed or not store then
		return false
	end
	local dataStore = store :: DataStore
	local snapshot = deepCopy(profile.Data)
	local ok, err = withRetries(function()
		dataStore:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
		return true
	end)
	if not ok then
		warn("[DataService] Failed to save data for", player.Name, err)
	end
	return ok
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player] = nil
end

function DataService.NewId(player: Player): string
	local profile = profiles[player]
	assert(profile, "No profile")
	local id = tostring(profile.Data.NextId)
	profile.Data.NextId += 1
	return id
end

function DataService.AddCoins(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data.Coins += amount
	if amount > 0 then
		profile.Data.TotalEarned += amount
	end
end

function DataService.TrySpend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Data.Coins < amount then
		return false
	end
	profile.Data.Coins -= amount
	return true
end

function DataService.StartAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				DataService.Save(player)
				remaining -= 1
			end)
		end
		local started = os.clock()
		while remaining > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
