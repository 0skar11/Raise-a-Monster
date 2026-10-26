-- Offline receipt tests: no Roblox account or live currency is touched.
local fs = require('@lune/fs')
local r = require('@lune/roblox')
local luau = require('@lune/luau')
local globals = getfenv()
local function environment(extra)
	local e = extra or {}
	for k, v in globals do if e[k] == nil then e[k] = v end end
	for k, v in r do if e[k] == nil then e[k] = v end end
	return e
end
local config = luau.load(fs.readFile('src/shared/Config.luau'), {environment = environment()})()
local player = {UserId = 1}
local profile = {Data = {Coins = 150, ProcessedReceipts = {}}}
local saveOk = true
local data = {
	Get = function(p) return if p == player then profile else nil end,
	Save = function() return saveOk end,
	AddCoins = function(_, amount) profile.Data.Coins += amount end,
}
local signal = {Connect = function() end}
local market = {PromptGamePassPurchaseFinished = signal, PromptProductPurchaseFinished = signal}
local modules = {Config = config, DataService = data, PlotService = {}, MonsterService = {Notify = function() end, PushState = function() end, GetIncomePerSecond = function() return 0 end}, MonsterMath = {FormatNumber = tostring}, CharacterService = {}, CombatService = {}}
local services = {MarketplaceService = market, Players = {GetPlayerByUserId = function(_, id) return if id == 1 then player else nil end}, ReplicatedStorage = {Shared = {Config = 'Config', MonsterMath = 'MonsterMath'}}, RunService = {}}
local parent = {}
for k in modules do parent[k] = k end
local enums = {ProductPurchaseDecision = {PurchaseGranted = 'granted', NotProcessedYet = 'retry'}}
local module = luau.load(fs.readFile('src/server/MonetizationService.luau'), {environment = environment({
	game = {GetService = function(_, name) return assert(services[name], name) end},
	script = {Parent = parent},
	require = function(key) return assert(modules[key], key) end,
	Enum = enums,
	task = {spawn = function() end},
})})()
module.Init({BuyPass = {OnServerEvent = signal}, BuyWeapon = {OnServerEvent = signal}, EquipWeapon = {OnServerEvent = signal}, BuyProduct = {OnServerEvent = signal}})
local total = 150
for _, key in {'Coins1000', 'Coins5000', 'Coins15000'} do
	local product = config.Products[key]
	local receipt = {PlayerId = 1, ProductId = product.Id, PurchaseId = key}
	assert(market.ProcessReceipt(receipt) == 'granted')
	total += product.Coins
	assert(profile.Data.Coins == total)
	assert(market.ProcessReceipt(receipt) == 'granted')
	assert(profile.Data.Coins == total, 'duplicate receipt added currency')
end
saveOk = false
local receipt = {PlayerId = 1, ProductId = config.Products.Coins1000.Id, PurchaseId = 'save-retry'}
assert(market.ProcessReceipt(receipt) == 'retry')
total += 1000
assert(profile.Data.Coins == total)
assert(market.ProcessReceipt(receipt) == 'retry')
assert(profile.Data.Coins == total)
saveOk = true
assert(market.ProcessReceipt(receipt) == 'granted')
assert(profile.Data.Coins == total)
assert(market.ProcessReceipt({PlayerId = 2, ProductId = receipt.ProductId, PurchaseId = 'missing-player'}) == 'retry')
assert(market.ProcessReceipt({PlayerId = 1, ProductId = -1, PurchaseId = 'unknown-product'}) == 'retry')
assert(market.ProcessReceipt({PlayerId = 1, ProductId = 0, PurchaseId = 'unconfigured-product'}) == 'retry')
profile.LoadFailed = true
assert(market.ProcessReceipt({PlayerId = 1, ProductId = receipt.ProductId, PurchaseId = 'unsafe-profile'}) == 'retry')
assert(profile.Data.Coins == total and not profile.Data.ProcessedReceipts['unsafe-profile'], 'failed profile consumed a purchase')
print('PASS: all 3 packs, duplicate receipts, save failure/retry, missing player, unknown/unconfigured product and failed profile')
