-- Real DataService, MonsterService and MonetizationService; ownership deliberately yields.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local fixture = fs.readFile("tools/test-monster-inventory.luau")
fixture = fixture:sub(1, assert(fixture:find("local p, q = players[1], players[2]", 1, true)) - 1)
local regression = [[
local p = players[1]
local profile = data.Load(p)
local monsterSlot, eggSlot = config.BaseSlots + 1, config.BaseSlots + 2
profile.Data.Monsters.saved = { Id = "saved", Species = "Grassland_1", Slot = monsterSlot, Level = 1, Xp = 0, Hunger = 100, Happiness = 100 }
profile.Data.Eggs.savedEgg = { Id = "savedEgg", EggType = "Common", Slot = eggSlot, HatchAt = 1700002000 }
check(data.Save(p), "Save extra-slot monster and egg before rejoin")
data.Release(p)
profile = data.Load(p)
local eggRenders = {}
plotService.RenderEgg = function(_, id, _, slot) eggRenders[id] = slot end
plotService.UpdateMonster = function(owner, monster) plotService.RenderMonster(owner, monster) end
services.RunService = { IsStudio = function() return false end }
services.MarketplaceService = { PromptGamePassPurchaseFinished = signal() }
modules.CombatService = { GiveWeapons = function() end }
parent.CombatService = "CombatService"
for _, pass in config.Gamepasses do pass.Id = 0 end
config.Gamepasses.ExtraSlots.Id = 9001 -- synthetic fixture only
local monetization = load("MonetizationService", "src/server/MonetizationService.luau")
monsters.HasPass = monetization.HasPass
local function beginOwnership(result, failure)
    services.MarketplaceService.UserOwnsGamePassAsync = function()
        coroutine.yield("Marketplace pending")
        if failure then error("Marketplace unavailable") end
        return result
    end
    monetization.SetupPlayer(p)
    local job = table.remove(jobs)
    local thread = coroutine.create(function() job.Callback(table.unpack(job.Args, 1, job.Args.n)) end)
    check(coroutine.resume(thread), "Ownership query yields before it resolves")
    return thread
end
local pending = beginOwnership(true)
monsters.SetupPlayer(p)
check(profile.Data.Monsters.saved.Slot == monsterSlot and profile.Data.Eggs.savedEgg.Slot == eggSlot, "Rejoin preserves exact saved assignments before delayed verification")
check(not monsters.IsPlaced(p, profile.Data.Monsters.saved) and not (renders[p] or {}).saved and not eggRenders.savedEgg, "Unverified extra slots do not render or activate")
local income = profile.Data.PendingCoins
tick(1)
check(profile.Data.PendingCoins == income, "Pending extra-slot monster produces no income")
check(coroutine.resume(pending) and coroutine.status(pending) == "dead", "Delayed ownership resolves successfully")
check(monsters.IsPlaced(p, profile.Data.Monsters.saved) and renders[p].saved == monsterSlot and eggRenders.savedEgg == eggSlot, "Verified ownership restores saved monster and egg models in their exact slots")
tick(1)
check(profile.Data.PendingCoins > income, "Verified saved extra-slot monster resumes income")
monetization.CleanupPlayer(p)
renders[p], eggRenders = {}, {}
pending = beginOwnership(false, true)
monsters.SetupPlayer(p)
while coroutine.status(pending) ~= "dead" do check(coroutine.resume(pending), "Ownership outage uses bounded retries") end
check(profile.Data.Monsters.saved.Slot == monsterSlot and profile.Data.Eggs.savedEgg.Slot == eggSlot, "Failed verification cannot bench or erase saved assignments")
check(not monsters.IsPlaced(p, profile.Data.Monsters.saved) and not renders[p].saved and not eggRenders.savedEgg, "Failed verification cannot activate or render locked slots")
check(data.Save(p) and saved.Player_1.Monsters.saved.Slot == monsterSlot and saved.Player_1.Eggs.savedEgg.Slot == eggSlot, "Autosave during Marketplace outage preserves saved slot ownership")
income = profile.Data.PendingCoins
tick(1)
check(profile.Data.PendingCoins == income, "Failed verification cannot earn income from locked slots")
monetization.CleanupPlayer(p)
pending = beginOwnership(false)
monsters.SetupPlayer(p)
check(coroutine.resume(pending), "Unowned check completes")
check(not monetization.HasPass(p, "ExtraSlots") and not monsters.IsPlaced(p, profile.Data.Monsters.saved), "Confirmed nonowner cannot use saved locked slots")
print(string.format("PASS: %d extra-slot rejoin checks (real data roundtrip, yielding ownership, saved monster and egg assignments, delayed render, failed checks, income gating)", checks))
]]
luau.load(fixture .. regression, { injectGlobals = true })()
