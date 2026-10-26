-- Real DataService with two independent servers sharing a deterministic DataStore.
-- No live data, Roblox account or currency is touched.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks, now, serial = 0, 1700000000, 0
local function check(value, message) assert(value, message); checks += 1 end
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
local function environment(extra)
	local env = table.clone(getfenv())
	for key, value in r do env[key] = value end
	for key, value in extra or {} do env[key] = value end
	return env
end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = environment() })()
local stored, failures, writes, reads = {}, 0, 0, 0
local store = {
	GetAsync = function() error("Non-atomic profile reads must not be used") end,
	UpdateAsync = function(_, key, callback)
		reads += 1
		if failures > 0 then failures -= 1; error("simulated datastore outage") end
		local result = callback(copy(stored[key]))
		if result ~= nil then stored[key] = copy(result); writes += 1 end
		return copy(result)
	end,
}
local function player(id)
	return { UserId = id, Name = "Player" .. id, Kick = function(self, reason) self.Kicked = reason end }
end
local function server(unavailable, studio)
	local closeCallback, jobs = nil, {}
	local services = {
		DataStoreService = { GetDataStore = function() if unavailable then error("offline") end; return store end },
		ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
		HttpService = { GenerateGUID = function() serial += 1; return "session-" .. serial end },
		RunService = { IsStudio = function() return studio == true end },
	}
	local modules = { Config = config, MonsterMath = {} }
	local fakeTask = {
		wait = function(delay) now += delay or 0; return coroutine.yield(delay or 0) end,
		spawn = function(callback, ...) table.insert(jobs, { Callback = callback, Args = table.pack(...) }) end,
	}
	local gameMock = {
		GetService = function(_, name) return assert(services[name], name) end,
		BindToClose = function(_, callback) closeCallback = callback end,
	}
	local module = luau.load(fs.readFile("src/server/DataService.luau"), { environment = environment({
		game = gameMock, require = function(name) return assert(modules[name], name) end,
		task = fakeTask, os = { time = function() return now end, clock = function() return now end },
	}) })()
	return module, jobs, function() return closeCallback end
end
local function run(callback)
	local thread = coroutine.create(callback)
	while coroutine.status(thread) ~= "dead" do
		local ok, err = coroutine.resume(thread)
		assert(ok, tostring(err))
	end
end
local first, second = server(), server()
local p, rival = player(1), player(1)
local profile = first.Load(p)
check(not profile.LoadFailed and profile.CanSave and profile.Data.Coins == config.StartingCoins, "New profile atomically claims a savable session")
check(stored.Player_1._SessionLock.Id == profile.SessionId and profile.Data._SessionLock == nil, "Lock metadata stays outside gameplay state")
local before = writes
local blocked = second.Load(rival)
check(blocked.LoadFailed and writes == before, "Second live server cannot open or overwrite an active profile")
check(not second.Save(rival), "Failed load cannot write starter defaults")
second.Release(rival)
check(stored.Player_1._SessionLock.Id == profile.SessionId, "Rejected session cannot release another server's lock")
profile.Data.Coins = 7654
profile.Data.ProcessedReceipts["summon-pending"] = true
profile.Data.PendingBossSummons["summon-pending"] = 50
profile.Data.PendingCoins = 125.5
profile.Data.TotalEarned = 9000
profile.Data.Monsters = { ["7"] = { Id = "7", Species = "Grassland_1", Slot = 1, Level = 12, Xp = 25, Hunger = 65, Happiness = 77, Hat = "saved-hat" } }
profile.Data.Eggs = { ["8"] = { Id = "8", EggType = "Rare", Slot = 2, HatchAt = now + 500 } }
profile.Data.Weapons.IronSword = true
profile.Data.EquippedWeapon = "IronSword"
profile.Data.SpeedAccessories.SwiftSneakers = true
profile.Data.EquippedSpeedAccessory = "SwiftSneakers"
profile.Data.SlotUpgrades = 2
profile.Data.LastSpin = now
profile.Data.ProcessedReceipts["purchase-1"] = true
profile.Data.SpeedBoostUntil = now + 600
profile.Data.NextId = 9
local oldExpiry = stored.Player_1._SessionLock.ExpiresAt
now += config.AutosaveInterval
check(first.Save(p), "Owned profile saves successfully")
check(stored.Player_1._SessionLock.ExpiresAt > oldExpiry, "Autosave renews session expiry")
check(stored.Player_1.Coins == 7654 and stored.Player_1.PendingCoins == 125.5, "Wallet and uncollected income are durable")
check(stored.Player_1.ProcessedReceipts["purchase-1"], "Receipt marker is written alongside its reward")
profile.Data.Monsters["7"].Level = 13
check(stored.Player_1.Monsters["7"].Level == 12, "Saved snapshot is independent from later mutations")
first.Release(p)
check(first.Get(p) == nil and stored.Player_1._SessionLock == nil, "Exit atomically flushes latest state and releases the session")
check(stored.Player_1.Monsters["7"].Level == 13, "Exit saves progress after the last autosave")
profile = second.Load(rival)
check(not profile.LoadFailed and profile.Data.Coins == 7654, "Rejoin reads the saved balance")
check(profile.Data.PendingBossSummons["summon-pending"] == 50 and profile.Data.ProcessedReceipts["summon-pending"], "Paid summon credit and receipt survive real DataService save/rejoin together")
local reset = second.WipeProgress(profile.Data)
check(reset.PendingBossSummons["summon-pending"] == 50 and reset.ProcessedReceipts["summon-pending"], "Progress reset preserves unfulfilled paid summons and their receipt markers")
check(profile.Data.Monsters["7"].Hat == "saved-hat" and profile.Data.Monsters["7"].Level == 13 and profile.Data.Eggs["8"].EggType == "Rare", "Monsters, accessories, XP and eggs survive rejoin")
check(profile.Data.Weapons.IronSword and profile.Data.EquippedWeapon == "IronSword" and profile.Data.SpeedAccessories.SwiftSneakers and profile.Data.EquippedSpeedAccessory == "SwiftSneakers", "Gear ownership and both selections survive rejoin")
check(profile.Data.LastSpin == now - config.AutosaveInterval and profile.Data.ProcessedReceipts["purchase-1"] and profile.Data.NextId == 9, "Rewards, receipt deduplication and ID sequence survive rejoin")
before = reads
profile.Data.Coins += 1
failures = 2
run(function() check(second.Save(rival), "Transient save failure recovers") end)
check(reads == before + config.DataSave.MaxRetries and stored.Player_1.Coins == 7655, "Retries are bounded and persist the original snapshot")
before = reads
failures = 100
run(function() check(not second.Save(rival), "Persistent save failure reports failure") end)
check(reads == before + config.DataSave.MaxRetries and stored.Player_1.Coins == 7655, "Exhausted retries never replace durable progress")
failures = 0
now += config.DataSave.SessionTimeout + 1
local third = server()
local newcomer = player(1)
local fresh = third.Load(newcomer)
check(not fresh.LoadFailed and fresh.Data.Coins == 7655, "Crashed server lease expires and preserves all saved progress")
fresh.Data.Coins = 8888
check(third.Save(newcomer), "New owner saves after expired lease takeover")
profile.Data.Coins = 1
check(not second.Save(rival) and profile.LoadFailed and rival.Kicked, "Stale server detects lost ownership and disconnects safely")
check(stored.Player_1.Coins == 8888 and stored.Player_1._SessionLock.Id == fresh.SessionId, "Stale server cannot overwrite or unlock the new owner's profile")
second.Release(rival)
check(stored.Player_1.Coins == 8888 and stored.Player_1._SessionLock.Id == fresh.SessionId, "Stale release cannot overwrite the new session")
failures = config.DataSave.MaxRetries
run(function() third.Release(newcomer) end)
check(stored.Player_1.Coins == 8888 and stored.Player_1._SessionLock ~= nil, "Failed final write retains the durable profile and lock until expiry")
failures = config.DataSave.MaxRetries
local failedPlayer = player(2)
local failed
run(function() failed = first.Load(failedPlayer) end)
check(failed.LoadFailed and stored.Player_2 == nil and not first.Save(failedPlayer), "Read outage cannot save temporary starter data")
failures = 0
stored.Player_3 = "damaged-record"
local damaged = player(3)
check(first.Load(damaged).LoadFailed and not first.Save(damaged) and stored.Player_3 == "damaged-record", "Invalid stored root fails closed without replacement")
stored.Player_4 = { Coins = 99, Monsters = "invalid-collection" }
check(first.Load(player(4)).LoadFailed and stored.Player_4.Monsters == "invalid-collection", "Invalid collections fail closed before locking or reconciling")
stored.Player_5 = { WipeVersion = config.ProgressWipeVersion, Coins = 555, SpeedAccessories = { SwiftSneakers = true, GoldenWings = true } }
local legacyPlayer = player(5)
local legacy = first.Load(legacyPlayer)
check(not legacy.LoadFailed and legacy.Data.Coins == 555 and legacy.Data.Weapons.Bat and legacy.Data.Stats.Hatched == 0, "Legacy fields reconcile without discarding existing progress")
check(legacy.Data.EquippedSpeedAccessory == "GoldenWings" and legacy.Data.Version == 2, "Missing legacy version still migrates its best owned accessory")
-- ريسيت البروجريس: سجل قديم من غير WipeVersion بيبدأ من الأول مرة واحدة، وبيحتفظ بسجل الإيصالات
stored.Player_11 = {
	Coins = 987654, TotalEarned = 5e9, Monsters = { ["1"] = { Id = "1", Species = "Void_10", Slot = 1, Level = 60, Xp = 0, Hunger = 100, Happiness = 100 } },
	Eggs = { ["2"] = { Id = "2", EggType = "Mythic", Slot = 2, HatchAt = now + 100 } }, SlotUpgrades = 5, NextId = 40,
	Weapons = { Bat = true, LavaSword = true }, EquippedWeapon = "LavaSword", LastSpin = now,
	ProcessedReceipts = { ["old-purchase"] = true }, Halloween = { Candy = 500, TotalCandy = 900, BoostUntil = 0, Converted = 0, Owned = {}, Equipped = {} },
}
local wipedPlayer = player(11)
local wipedProfile = first.Load(wipedPlayer)
check(not wipedProfile.LoadFailed and wipedProfile.Data.Coins == config.StartingCoins and next(wipedProfile.Data.Monsters) == nil and next(wipedProfile.Data.Eggs) == nil, "Progress wipe resets coins, monsters and eggs for a pre-wipe save")
check(wipedProfile.Data.SlotUpgrades == 0 and wipedProfile.Data.NextId == 1 and wipedProfile.Data.LastSpin == 0 and wipedProfile.Data.Halloween.Candy == 0 and wipedProfile.Data.TotalEarned == 0, "Progress wipe resets upgrades, ids, spin timer, candy and earnings")
check(wipedProfile.Data.EquippedWeapon == "Bat" and wipedProfile.Data.Weapons.LavaSword == nil and wipedProfile.Data.Weapons.Bat, "Progress wipe resets purchased weapons")
check(wipedProfile.Data.ProcessedReceipts["old-purchase"] and wipedProfile.Data.WipeVersion == config.ProgressWipeVersion, "Progress wipe keeps receipt deduplication and stamps the wipe version")
wipedProfile.Data.Coins = 4242
check(first.Save(wipedPlayer) and stored.Player_11.Coins == 4242 and stored.Player_11.WipeVersion == config.ProgressWipeVersion, "Wiped profile persists its fresh state and version")
first.Release(wipedPlayer)
local wipedAgain = second.Load(player(11))
check(not wipedAgain.LoadFailed and wipedAgain.Data.Coins == 4242, "A wiped player is not wiped again on the next join")
second.Release(player(11))
local unavailable = server(true)
local offlineProduction = unavailable.Load(player(6))
check(offlineProduction.LoadFailed and not offlineProduction.Temporary, "Unavailable DataStore in production fails closed")
local offlineStudio = server(true, true)
local studioPlayer = player(6)
local studioProfile = offlineStudio.Load(studioPlayer)
before = writes
studioProfile.Data.Coins = 123456
check(studioProfile.LoadFailed and not studioProfile.CanSave and studioProfile.Temporary, "Studio with disabled API access can play a clearly temporary profile")
check(not offlineStudio.Save(studioPlayer), "Temporary Studio profile never saves")
offlineStudio.Release(studioPlayer)
check(writes == before and stored.Player_6 == nil, "Temporary Studio progress cannot overwrite any durable profile")
local failedApiStudio = server(false, true)
failures = config.DataSave.MaxRetries
run(function() studioProfile = failedApiStudio.Load(player(8)) end)
check(studioProfile.LoadFailed and studioProfile.Temporary and stored.Player_8 == nil, "Studio API read errors allow only temporary progress")
local lockedStudio = server(false, true)
stored.Player_9 = { Coins = 500, _SessionLock = { Id = "live-owner", ExpiresAt = now + config.DataSave.SessionTimeout } }
local lockedProfile = lockedStudio.Load(player(9))
check(lockedProfile.LoadFailed and not lockedProfile.Temporary and stored.Player_9.Coins == 500, "Studio cannot bypass another active session's lock")
local simultaneous = server()
local repeatedPlayer = player(10)
local originalUpdate, pause = store.UpdateAsync, true
store.UpdateAsync = function(...)
	if pause then pause = false; coroutine.yield("pending-load") end
	return originalUpdate(...)
end
local firstProfile, duplicateProfile
local loadingFirst = coroutine.create(function() firstProfile = simultaneous.Load(repeatedPlayer) end)
local loadingDuplicate = coroutine.create(function() duplicateProfile = simultaneous.Load(repeatedPlayer) end)
check(coroutine.resume(loadingFirst), "First load waits inside DataStore")
check(coroutine.resume(loadingDuplicate), "Duplicate load waits behind the first profile acquisition")
before = writes
check(coroutine.resume(loadingFirst) and coroutine.resume(loadingDuplicate), "Both pending load calls complete")
check(firstProfile == duplicateProfile and not duplicateProfile.LoadFailed and writes == before + 1, "Concurrent loads share one accepted profile and atomic acquisition")
store.UpdateAsync = originalUpdate
local shutdown, jobs, getClose = server()
local exiting = player(7)
local exitingProfile = shutdown.Load(exiting)
exitingProfile.Data.Coins = 4321
shutdown.StartAutosave()
local autosave = coroutine.create(jobs[1].Callback)
check(coroutine.resume(autosave), "Autosave loop starts")
exitingProfile.Data.Coins = 777
local expiry = stored.Player_7._SessionLock.ExpiresAt
check(coroutine.resume(autosave), "Autosave interval schedules a real profile write")
local autosaveJob = table.remove(jobs, 2)
run(function() autosaveJob.Callback(table.unpack(autosaveJob.Args, 1, autosaveJob.Args.n)) end)
check(stored.Player_7.Coins == 777 and stored.Player_7._SessionLock.ExpiresAt > expiry, "Real autosave loop writes latest progress and renews ownership")
exitingProfile.Data.Coins = 4321
run(function()
	local closeThread = coroutine.create(getClose())
	check(coroutine.resume(closeThread), "Shutdown schedules profile flushes")
	for _, job in jobs do if job.Args.n > 0 or job.Callback ~= jobs[1].Callback then run(function() job.Callback(table.unpack(job.Args, 1, job.Args.n)) end) end end
	while coroutine.status(closeThread) ~= "dead" do check(coroutine.resume(closeThread), "Shutdown waits for final writes") end
end)
check(stored.Player_7.Coins == 4321 and stored.Player_7._SessionLock == nil and shutdown.Get(exiting) == nil, "Shutdown flushes progress and releases sessions")
print(string.format("PASS: %d persistence checks (atomic session ownership, full progress roundtrip, autosave lease, retries, takeover, stale writes, failed loads, migration, shutdown)", checks))
