--!strict
-- حفظ وتحميل بيانات اللاعبين باستخدام DataStoreService.
-- كل جلسة ليها قفل؛ السيرفر القديم ما يكتبش فوق تقدم جلسة أحدث.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

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
	IncomeMultiplier: number,
	IncomeUnlockedSlots: number,
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
	EquippedWeapon: string,
	Followers: { string }, -- adult monsters chosen to follow the player; restored on respawn and rejoin
	EquippedSpeedAccessory: string?,
	Daily: { LastClaim: number, Streak: number },
	LastSpin: number,
	ProcessedReceipts: { [string]: boolean },
	PendingAdultPurchase: {
		Token: string, ProductName: string, ProductId: number, Status: string,
		Targets: { { Id: string, Identity: string } }, ReceiptId: string?,
	}?,
	SpeedBoostUntil: number,
	Halloween: HalloweenData, -- event currency + purchases; safe to keep forever (see Config.Halloween)
}

export type HalloweenData = {
	Candy: number,
	TotalCandy: number,
	BoostUntil: number, -- os.time epoch
	Converted: number, -- coins already paid out for leftover Candy
	Owned: { [string]: boolean },
	Equipped: { [string]: string }, -- slot (Hat/Trail/Aura/Title) -> item id
}

export type Profile = {
	Data: PlayerData,
	LoadFailed: boolean,
	CanSave: boolean,
	SessionId: string,
	Closing: boolean?,
	Temporary: boolean?,
}

local DEFAULT_DATA: PlayerData = {
	Version = 2,
	Coins = Config.StartingCoins,
	PendingCoins = 0,
	IncomeMultiplier = 1,
	IncomeUnlockedSlots = Config.BaseSlots,
	TotalEarned = 0,
	Monsters = {},
	Eggs = {},
	SlotUpgrades = 0,
	LockUpgrades = 0,
	NextId = 1,
	Stats = { Hatched = 0, Steals = 0, TimesRobbed = 0, ArenaWins = 0 },
	Accessories = {},
	SpeedAccessories = {},
	Weapons = { Bat = true },
	EquippedWeapon = "Bat",
	Followers = {},
	Daily = { LastClaim = 0, Streak = 0 },
	LastSpin = 0,
	ProcessedReceipts = {},
	SpeedBoostUntil = 0,
	Halloween = { Candy = 0, TotalCandy = 0, BoostUntil = 0, Converted = 0, Owned = {}, Equipped = {} },
}

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
local loading: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
type QueuedSave = { Profile: Profile, Revision: number, Closing: boolean }
local queuedSaves: { [Player]: QueuedSave } = {}

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
	for attempt = 1, Config.DataSave.MaxRetries do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < Config.DataSave.MaxRetries then task.wait(attempt * Config.DataSave.RetryDelay) end
	end
	return false, tostring(lastError)
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function validRecord(record: any): boolean
	if record == nil then return true end
	if type(record) ~= "table" then return false end
	for key, template in DEFAULT_DATA do
		local value = record[key]
		if value ~= nil and key ~= "Version" and key ~= "Weapons" and key ~= "SpeedAccessories" and key ~= "EquippedWeapon" and key ~= "Halloween" then
			if type(value) ~= type(template) then return false end
			if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then return false end
		end
	end
	for _, records in { record.Monsters or {}, record.Eggs or {} } do
		for id, value in records do
			if type(id) ~= "string" or type(value) ~= "table" then return false end
		end
	end
	return true
end

local DataService = {}

-- Slot 0 is the persistent bench. Legacy collisions/invalid slots never delete ownership.
function DataService.NormalizeMonsterSlots(data: PlayerData, unlocked: number)
	local used: { [number]: boolean } = {}
	local function normalize(records: { [string]: any })
		local ids = {}
		for id in records do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ids do
			local record = records[id]
			local slot = record.Slot
			record.Id = id
			if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > unlocked or used[slot] then
				record.Slot = 0
			else
				used[slot] = true
			end
		end
	end
	-- Eggs already occupying a slot keep it; displaced monsters move to the bench.
	normalize(data.Eggs)
	normalize(data.Monsters)
end

-- الملكية منفصلة عن الاختيار؛ البيانات القديمة بتحتفظ بكل مشترياتها.
local function reconcileGear(data: PlayerData)
	local legacy = type(data.Version) ~= "number" or data.Version < 2
	local function ownedKeys(value: any, definitions: { [string]: any }, includeBat: boolean): { [string]: boolean }
		local result = {}
		if type(value) == "table" then
			for key, owned in value do
				if type(key) == "string" and owned == true and (definitions[key] or (includeBat and key == "Bat")) then result[key] = true end
			end
		end
		if includeBat then result.Bat = true end
		return result
	end
	data.Weapons = ownedKeys(data.Weapons, Config.WeaponStats, true)
	data.SpeedAccessories = ownedKeys(data.SpeedAccessories, Config.SpeedAccessories, false)
	if type(data.EquippedWeapon) ~= "string" or (data.EquippedWeapon ~= "Bat" and not Config.WeaponStats[data.EquippedWeapon]) then
		data.EquippedWeapon = "Bat"
	end
	if legacy and data.EquippedSpeedAccessory == nil then
		local bestPrice = -1
		for name, accessory in Config.SpeedAccessories do
			if data.SpeedAccessories[name] and accessory.Price > bestPrice then data.EquippedSpeedAccessory = name; bestPrice = accessory.Price end
		end
	end
	if type(data.EquippedSpeedAccessory) ~= "string" or not data.SpeedAccessories[data.EquippedSpeedAccessory] then data.EquippedSpeedAccessory = nil end
	data.Version = math.max(if type(data.Version) == "number" then data.Version else 0, 2)
end

-- Halloween data is rebuilt field by field: old saves without it get the defaults, and anything
-- invalid (wrong type, NaN, negative, unknown item) is dropped instead of crashing or being trusted.
local function sanitizeHalloween(data: PlayerData)
	local source: any = data.Halloween
	if type(source) ~= "table" then source = {} end
	local items = Config.Halloween.Items
	local cap = Config.Halloween.CandyCap
	local function number(value: any, maximum: number): number
		if type(value) ~= "number" or value ~= value or value < 0 then return 0 end
		return math.min(math.floor(value), maximum)
	end
	local owned: { [string]: boolean } = {}
	if type(source.Owned) == "table" then
		for id, flag in source.Owned do
			if type(id) == "string" and flag == true and items[id] then owned[id] = true end
		end
	end
	local equipped: { [string]: string } = {}
	if type(source.Equipped) == "table" then
		for slot, id in source.Equipped do
			if type(slot) == "string" and type(id) == "string" and owned[id] and items[id].Kind == slot then equipped[slot] = id end
		end
	end
	data.Halloween = {
		Candy = number(source.Candy, cap),
		TotalCandy = number(source.TotalCandy, cap * 1000),
		BoostUntil = number(source.BoostUntil, 4e9),
		Converted = number(source.Converted, 1e18),
		Owned = owned,
		Equipped = equipped,
	}
end
DataService.SanitizeHalloween = sanitizeHalloween

function DataService.Load(player: Player): Profile
	while loading[player] do task.wait() end
	if profiles[player] then return profiles[player] end
	loading[player] = true
	local data: PlayerData = deepCopy(DEFAULT_DATA)
	local loadFailed = false
	local sessionId = HttpService:GenerateGUID(false)
	local rejectedRecord = false

	if store then
		local dataStore = store :: DataStore
		local ok, result = withRetries(function()
			return dataStore:UpdateAsync(keyFor(player), function(current)
				rejectedRecord = false
				if not validRecord(current) then rejectedRecord = true; return nil end
				local lock = current and current._SessionLock
				if type(lock) == "table" and lock.Id ~= sessionId and type(lock.ExpiresAt) == "number" and lock.ExpiresAt > os.time() then
					rejectedRecord = true
					return nil
				end
				local record = deepCopy(current or DEFAULT_DATA)
				record._SessionLock = { Id = sessionId, ExpiresAt = os.time() + Config.DataSave.SessionTimeout }
				return record
			end)
		end)
		if ok and type(result) == "table" and type(result._SessionLock) == "table" and result._SessionLock.Id == sessionId then
			data = deepCopy(result) :: any
			(data :: any)._SessionLock = nil
			-- Keep the old version until the gear migration has inspected it.
			local version = (data :: any).Version
			reconcile(data :: any, DEFAULT_DATA :: any)
			if version == nil then data.Version = 1 end
		else
			loadFailed = true
			warn("[DataService] Failed to load or acquire session for", player.Name, if ok then "profile locked or invalid" else result)
		end
	else
		loadFailed = true
	end

	reconcileGear(data)
	sanitizeHalloween(data)
	do
		local cleaned: { string } = {}
		if type((data :: any).Followers) == "table" then
			for _, id in (data :: any).Followers do
				if type(id) == "string" and #cleaned < Config.Followers.MaxCount and not table.find(cleaned, id) then
					table.insert(cleaned, id)
				end
			end
		end
		data.Followers = cleaned
	end
	DataService.NormalizeMonsterSlots(data, Config.MaxSlots)
	local profile: Profile = {
		Data = data, LoadFailed = loadFailed, CanSave = not loadFailed, SessionId = sessionId,
		Temporary = loadFailed and not rejectedRecord and RunService:IsStudio(),
	}
	profiles[player] = profile
	loading[player] = nil
	return profile
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

-- Purchase snapshots use a persisted identity rather than a client-supplied ID alone.
function DataService.NewPurchaseToken(): string
	return HttpService:GenerateGUID(false)
end

local function saveProfile(player: Player, releaseLock: boolean): boolean
	local profile = profiles[player]
	while saving[player] do
		task.wait()
	end
	if not profile or profiles[player] ~= profile or profile.LoadFailed or (profile.Closing and not releaseLock) or not store then
		return false
	end
	saving[player] = true
	local dataStore = store :: DataStore
	local snapshot = deepCopy(profile.Data)
	local ok, result = withRetries(function()
		return dataStore:UpdateAsync(keyFor(player), function(current)
			local lock = type(current) == "table" and current._SessionLock
			if type(lock) ~= "table" or lock.Id ~= profile.SessionId then return nil end
			local record = deepCopy(snapshot)
			record._SessionLock = if releaseLock then nil else { Id = profile.SessionId, ExpiresAt = os.time() + Config.DataSave.SessionTimeout }
			return record
		end)
	end)
	saving[player] = nil
	local saved = ok and type(result) == "table"
	if not saved then
		warn("[DataService] Failed to save data for", player.Name, if ok then "session ownership lost" else result)
		if ok then
			profile.LoadFailed = true
			profile.CanSave = false
			player:Kick("Your data session changed. Please rejoin to load your saved progress safely.")
		end
	end
	return saved
end

function DataService.Save(player: Player): boolean
	return saveProfile(player, false)
end

-- Selection remotes share one worker per profile. Save remains synchronous for
-- receipts; each worker waits for the current write before taking a fresh snapshot.
function DataService.QueueSave(player: Player)
	local profile = profiles[player]
	if not profile or profile.LoadFailed or not store then return end
	local pending = queuedSaves[player]
	if pending and pending.Profile == profile then
		if not pending.Closing then pending.Revision += 1 end
		return
	end
	local state: QueuedSave = { Profile = profile, Revision = 1, Closing = false }
	queuedSaves[player] = state
	task.spawn(function()
		local function active(): boolean
			return not state.Closing and profiles[player] == profile and queuedSaves[player] == state
		end
		while active() do
			task.wait(Config.Security.GearSaveInterval)
			while active() and saving[player] do task.wait(0.1) end
			if not active() then break end
			local revision = state.Revision
			DataService.Save(player) -- Uses the existing bounded three-attempt retry.
			-- Mutations during the write need another snapshot, including after a
			-- failed write. Otherwise autosave/exit retain the normal retry policy.
			if state.Revision == revision then break end
		end
		if queuedSaves[player] == state then queuedSaves[player] = nil end
	end)
end

function DataService.Release(player: Player)
	local profile = profiles[player]
	if not profile then return end
	profile.Closing = true
	local pending = queuedSaves[player]
	if pending then pending.Closing = true end
	-- Release ownership in the same durable write as the final progress snapshot.
	saveProfile(player, true)
	if profiles[player] == profile then profiles[player] = nil end
	if queuedSaves[player] == pending then queuedSaves[player] = nil end
end

function DataService.NewId(player: Player): string
	local profile = profiles[player]
	assert(profile, "No profile")
	local id: string
	repeat
		id = tostring(profile.Data.NextId)
		profile.Data.NextId += 1
	until not profile.Data.Monsters[id] and not profile.Data.Eggs[id]
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
				DataService.Release(player)
				remaining -= 1
			end)
		end
		local started = os.clock()
		while remaining > 0 and os.clock() - started < Config.DataSave.ShutdownTimeout do
			task.wait(0.1)
		end
	end)
end

return DataService
