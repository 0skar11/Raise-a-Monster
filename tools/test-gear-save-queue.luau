local fs = require("@lune/fs")
local luau = require("@lune/luau")
-- Reuse the real-module/asset fixture, replacing only its deterministic task
-- scheduler. All handler and DataService code is loaded unchanged from disk.
local fixture = fs.readFile("tools/test-gear-inventory.luau")
fixture = fixture:sub(1, assert(fixture:find("local profile = data.Load(player)", 1, true)) - 1)
fixture = fixture:gsub("task = { spawn = function%(callback, %.%.%.%).-wait = function%(%) end },", "task = scheduler,")
local schedulerSource = [[
local jobs, now = {}, 100
local scheduler = {}
local function resumeJob(job, ...)
    local ok, delay = coroutine.resume(job.Thread, ...)
    assert(ok, tostring(delay))
    job.Wake = now + (delay or 0.01)
end
function scheduler.spawn(callback, ...)
    local job = { Thread = coroutine.create(callback), Wake = now }
    table.insert(jobs, job)
    resumeJob(job, ...)
    return job.Thread
end
function scheduler.wait(delay) return coroutine.yield(delay or 0.01) end
local function activeJobs()
    local count = 0
    for _, job in jobs do if coroutine.status(job.Thread) ~= "dead" then count += 1 end end
    return count
end
local function advance(seconds)
    local target = now + seconds
    while true do
        local nextJob
        for _, job in jobs do
            if coroutine.status(job.Thread) ~= "dead" and job.Wake <= target and (not nextJob or job.Wake < nextJob.Wake) then nextJob = job end
        end
        if not nextJob then break end
        now = nextJob.Wake
        resumeJob(nextJob)
    end
    now = target
end
]]
local regression = [[
local profile = data.Load(player)
profile.Data.Weapons.IronSword = true
profile.Data.SpeedAccessories.SwiftSneakers = true
local baseline = activeJobs()
local frozen, writes, failures = true, 0, 0
store.UpdateAsync = function(_, key, callback)
    writes += 1
    while frozen do scheduler.wait(0.1) end
    if failures > 0 then failures -= 1; error("simulated outage") end
    saved[key] = copy(callback(copy(saved[key])))
    return copy(saved[key])
end
local function equip(weapon, accessory)
    clock += 0.51
    serverEvents.EquipWeapon.OnServerEvent:Fire(player, weapon)
    serverEvents.EquipSpeedAccessory.OnServerEvent:Fire(player, accessory)
end
for index = 1, 60 do
    equip(if index % 2 == 0 then "Bat" else "IronSword", if index % 2 == 0 then nil else "SwiftSneakers")
    advance(0.51)
    check(activeJobs() <= baseline + 1, "Both remotes must share at most one selection worker")
end
check(writes == 1, "Frozen datastore receives only one active selection write during 30s burst")
equip("IronSword", "SwiftSneakers")
frozen = false
advance(6)
check(saved.Player_1.EquippedWeapon == "IronSword" and saved.Player_1.EquippedSpeedAccessory == "SwiftSneakers", "Mutation during pending write receives a fresh latest snapshot")
check(writes == 2 and activeJobs() == baseline, "Only one follow-up write and worker finishes")
local before = writes
failures = 2
equip("Bat", nil)
advance(10)
check(writes == before + 3 and saved.Player_1.EquippedWeapon == "Bat", "Transient errors use bounded three-attempt retry")
before = writes
failures = 100
equip("IronSword", "SwiftSneakers")
advance(20)
check(writes == before + 3 and activeJobs() == baseline, "Persistent failure stops after three attempts without spin")
failures = 0
data.Release(player)
check(saved.Player_1.EquippedWeapon == "IronSword", "Exit retries failed queued selection")
profile = data.Load(player)
equip("Bat", nil)
check(activeJobs() == baseline + 1, "New profile queues selection")
data.Release(player)
check(saved.Player_1.EquippedWeapon == "Bat" and saved.Player_1.EquippedSpeedAccessory == nil, "Release flushes latest selection before debounce expires")
profile = data.Load(player)
profile.Data.EquippedWeapon = "IronSword"
before = writes
advance(10)
check(writes == before and saved.Player_1.EquippedWeapon == "Bat", "Old worker cannot write rejoined profile")
check(activeJobs() == baseline, "Released worker exits")
-- A synchronous receipt-style save waiting behind a selection write must still
-- return only after its own snapshot including the new receipt is durable.
frozen = true
equip("Bat", "SwiftSneakers")
advance(5)
local receiptDone, receiptResult = false, nil
profile.Data.ProcessedReceipts["queue-receipt"] = true
scheduler.spawn(function() receiptResult = data.Save(player); receiptDone = true end)
advance(1)
check(not receiptDone, "Synchronous save cannot acknowledge a blocked receipt")
frozen = false
advance(2)
check(receiptDone and receiptResult and saved.Player_1.ProcessedReceipts["queue-receipt"], "Receipt save returns success only after durable snapshot")
failures = 3
local failedResult
scheduler.spawn(function() failedResult = data.Save(player) end)
advance(7)
check(failedResult == false, "Synchronous save still returns false on exhausted retries")
failures = 0
frozen = true
equip("IronSword", nil)
advance(5)
equip("Bat", "SwiftSneakers")
local released = false
scheduler.spawn(function() data.Release(player); released = true end)
advance(1)
check(not released, "Release waits for the in-flight write")
frozen = false
advance(2)
check(released and data.Get(player) == nil, "Release completes after final flush")
check(saved.Player_1.EquippedWeapon == "Bat" and saved.Player_1.EquippedSpeedAccessory == "SwiftSneakers", "Release saves changes made during in-flight selection snapshot")
before = writes
advance(10)
check(writes == before and activeJobs() == baseline, "Closing worker cannot issue an extra write after release")
print(string.format("PASS: %d gear queue checks (actual equip handlers, frozen datastore, bounded workers, latest selection, retries, release/rejoin, synchronous receipt durability)", checks))
]]
luau.load(schedulerSource .. fixture .. regression, { injectGlobals = true })()
