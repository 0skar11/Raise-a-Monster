-- Execute production collection priority/entitlement logic against real gamepass ownership.
local fs, luau = require("@lune/fs"), require("@lune/luau")
local setup = fs.readFile("tools/test-auto-feeder.luau")
setup = setup:sub(1, assert(setup:find("local assertions = 0", 1, true)) - 1)
local h = luau.load(setup .. "\nreturn harness", { injectGlobals = true })()(false, 9001, false)
local source = fs.readFile("src/server/ZoneService.luau")
local first = assert(source:find("local function autoCollectBabies(", 1, true))
local last = assert(source:find("\nlocal function killMother(", first, true))
local grants, accepted = {}, true
local collector = luau.load(source:sub(first, last - 1) .. "\nreturn autoCollectBabies", { environment = {
	MonsterService = { HasPass = h.Monetization.HasPass, RollMutation = function() return nil end,
		AddMonster = function(owner, species)
			if not accepted then return false end
			table.insert(grants, { Owner = owner, Species = species }); return true
		end },
}, injectGlobals = true })()
local checks = 0
local function check(ok, msg) assert(ok, msg); checks += 1 end
local buyer = h.Player; buyer.Parent = true
local baby = { Destroyed = false, Destroy = function(self) self.Destroyed = true end }
local nest = { Species = "Grassland_1", Damagers = { [buyer] = 50 }, Babies = { baby } }
local id = h.Config.Gamepasses.AutoCollectBabies.Id
check(id == 2052666547 and h.Config.Gamepasses.AutoCollectBabies.Price == 149, "Monster Collector uses configured live pass and149 price")
check(next(collector(nest, buyer)) == nil and #nest.Babies == 1 and #grants == 0, "Nonowner must collect manually")
h.Market.PromptGamePassPurchaseFinished:Fire(buyer, id, false)
check(next(collector(nest, buyer)) == nil and not baby.Destroyed, "Canceled pass cannot collect babies")
h.Market.PromptGamePassPurchaseFinished:Fire(buyer, id, true)
accepted = false
check(next(collector(nest, buyer)) == nil and #nest.Babies == 1 and not baby.Destroyed, "Failed inventory grant preserves original pickup")
accepted = true
check(collector(nest, buyer)[buyer] and #nest.Babies == 0 and baby.Destroyed and #grants == 1, "Confirmed owner gets one baby and removes only its granted pickup")
check(grants[1].Owner == buyer and grants[1].Species == nest.Species, "Reward belongs to server-selected fighter with original species")
nest.Babies = { { Destroy = function() end }, { Destroy = function() end } }
collector(nest, buyer)
check(#nest.Babies == 1 and #grants == 2, "One baby per eligible fighter per defeated mother")
nest.Damagers = {}
check(next(collector(nest, buyer)) == nil and #nest.Babies == 1, "Ownership alone cannot claim rewards without fighting")
h.Monetization.CleanupPlayer(buyer)
nest.Damagers[buyer] = 50
check(next(collector(nest, buyer)) == nil, "Departed session loses collector authority")
h.Market.UserOwnsGamePassAsync = function(_, _, passId) return passId == id end
h.Monetization.SetupPlayer(buyer)
check(collector(nest, buyer)[buyer] and #nest.Babies == 0, "Rejoin restores collector via Marketplace ownership")
print(string.format("PASS: %d Monster Collector checks (live ID, canceled/confirmed ownership, participation, failed reward safety, rejoin)", checks))
