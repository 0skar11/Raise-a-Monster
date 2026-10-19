-- Reuse real MonsterService/MonetizationService with offline Marketplace only.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local source = fs.readFile("tools/test-auto-feeder.luau")
source = source:sub(1, assert(source:find("local assertions = 0", 1, true)) - 1)
local harness = luau.load(source .. "\nreturn harness", { injectGlobals = true })()
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local h = harness(false, 2036452299, false)
-- Synthetic IDs below are fixtures, never written to production Config.
local fixtureIds = { VIP = 9001, AutoCollect = 9002, ExtraSlots = 9003 }
for name, id in fixtureIds do h.Config.Gamepasses[name].Id = id end
check(h.MonsterService.GetCoinMultiplier(h.Player) == 1, "Unowned VIP does not boost income")
check(h.MonsterService.GetUnlockedSlots(h.Player) == h.Config.BaseSlots, "Unowned slot pass does not expand base")
h.Profile.Data.PendingCoins = 12.75
h.Advance(1)
check(h.Profile.Data.PendingCoins == 12.75 and h.Profile.Data.Coins == 1000, "Unowned auto collect leaves income pending")
for name, id in fixtureIds do
	h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, id, false)
	check(not h.Monetization.HasPass(h.Player, name), "Canceled purchase does not grant " .. name)
	h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, id, true)
	check(h.Monetization.HasPass(h.Player, name), "Confirmed purchase grants " .. name)
end
check(h.MonsterService.GetCoinMultiplier(h.Player) == h.Config.VIPCoinMultiplier, "Verified VIP applies the configured income multiplier")
check(h.MonsterService.GetUnlockedSlots(h.Player) == h.Config.BaseSlots + h.Config.ExtraSlotsAmount, "Verified ExtraSlots expands base immediately")
h.Advance(2)
check(h.Profile.Data.PendingCoins == 0.75 and h.Profile.Data.Coins == 1012, "Verified AutoCollect moves whole pending coins into wallet")
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, fixtureIds.VIP, true)
check(h.MonsterService.GetCoinMultiplier(h.Player) == h.Config.VIPCoinMultiplier, "Duplicate confirmation cannot stack VIP")
h.Monetization.CleanupPlayer(h.Player)
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, fixtureIds.VIP, true)
check(not h.Monetization.HasPass(h.Player, "VIP"), "Late purchase event cannot recreate a departed session")
for _, pass in h.Config.Gamepasses do pass.Id = 0 end
h.Config.Gamepasses.AutoFeeder.Id = 2036452299
local attempts = 0
h.Market.UserOwnsGamePassAsync = function()
	attempts += 1
	if attempts < 3 then error("temporary marketplace outage") end
	return true
end
h.Monetization.SetupPlayer(h.Player)
h.Advance(3)
h.Advance(5)
check(attempts == 3 and h.Monetization.HasPass(h.Player, "AutoFeeder"), "Transient ownership errors retry and recover a paid entitlement")
h.Monetization.CleanupPlayer(h.Player)
h.Market.UserOwnsGamePassAsync = function() coroutine.yield(1); return true end
h.Monetization.SetupPlayer(h.Player)
h.Monetization.CleanupPlayer(h.Player)
h.Advance(6)
check(not h.Monetization.HasPass(h.Player, "AutoFeeder"), "Ownership response after departure cannot resurrect a session")
h.Market.UserOwnsGamePassAsync = function() return false end
h.Monetization.SetupPlayer(h.Player)
h.Buy()
h.Buy()
check(#h.Market.Prompts == 1, "Repeated same-frame pass request opens one prompt")
check(not h.Monetization.HasPass(h.Player, "AutoFeeder"), "Prompt alone never grants entitlement")
h.Advance(7)
h.Market.PromptGamePassPurchase = function() error("prompt unavailable") end
check(pcall(h.Buy), "Marketplace prompt failure is handled without crashing the remote")
h.Market.PromptGamePassPurchaseFinished:Fire(h.Player, 0, true)
check(not h.Monetization.HasPass(h.Player, "VIP"), "Invalid pass zero cannot grant Studio-only perks through a confirmation")
print(string.format("PASS: %d gamepass checks (VIP income, auto collect, extra slots, confirmed/canceled purchase, no stacking, retry, prompt throttle, departed session race)", checks))
