-- Offline inventory checks against real production modules and weapon asset Tools.
-- Run from the repository root: lune run tools/test-gear-inventory.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in value do result[key] = copy(item) end
    return result
end
local clock = 100
local queued = {}
local function signal()
    local listeners = {}
    return {
        Connect = function(_, callback) table.insert(listeners, callback); return { Disconnect = function() end } end,
        Fire = function(_, ...) for _, callback in listeners do callback(...) end end,
    }
end
local toolSignals = {}
local propertySignals = {}
r.implementMethod("Instance", "GetPropertyChangedSignal", function(instance, name)
    propertySignals[instance] = propertySignals[instance] or {}
    propertySignals[instance][name] = propertySignals[instance][name] or signal()
    return propertySignals[instance][name]
end)
r.implementProperty("Tool", "Activated", function(tool)
    if not toolSignals[tool] then toolSignals[tool] = signal() end
    return toolSignals[tool]
end)
r.implementMethod("Instance", "WaitForChild", function(instance, name) return assert(instance:FindFirstChild(name), name) end)
r.implementMethod("Humanoid", "EquipTool", function(humanoid, tool)
    local character = humanoid.Parent
    local owner = character:GetAttribute("TestPlayerId")
    local backpack = assert(character.Parent:FindFirstChild("Player" .. owner)):FindFirstChildOfClass("Backpack")
    for _, current in character:GetChildren() do if current:IsA("Tool") then current.Parent = backpack end end
    tool.Parent = character
end)
local rootFolder = r.Instance.new("Folder")
local replicatedStorage = r.Instance.new("ReplicatedStorage")
local weaponSource = fs.readFile("assets/WeaponModels.rbxmx"):gsub("^<%?xml.-%?>%s*", "")
local weapons = r.deserializeModel(weaponSource)[1]
weapons.Name = "WeaponModels"
weapons.Parent = replicatedStorage
local function makeCharacter(player)
    local character = r.Instance.new("Model")
    character.Name = "Character" .. player.UserId
    character:SetAttribute("TestPlayerId", player.UserId)
    character.Parent = rootFolder
    local humanoid = r.Instance.new("Humanoid")
    humanoid.Health = 100
    humanoid.MaxHealth = 100
    humanoid.Parent = character
    for _, name in { "HumanoidRootPart", "Left Leg", "Right Leg" } do
        local part = r.Instance.new("Part")
        part.Name = name
        part.Size = r.Vector3.new(2, 2, 1)
        part.Parent = character
    end
    player.Character = character
    return character, humanoid
end
local function makePlayer(id)
    local player = r.Instance.new("Player")
    player.UserId = id
    player.Name = "Player" .. id
    player.Parent = rootFolder
    r.Instance.new("Backpack").Parent = player
    r.Instance.new("StarterGear").Parent = player
    makeCharacter(player)
    return player
end
local player = makePlayer(1)
local saved = {}
local store = {
    GetAsync = function(_, key) return copy(saved[key]) end,
    UpdateAsync = function(_, key, callback) saved[key] = copy(callback(copy(saved[key]))); return copy(saved[key]) end,
}
local serverEvents = {}
local lastState
for _, name in { "StateUpdate", "Notify", "BuyEgg", "FeedMonster", "ToggleFollower", "MiniGameStart", "MiniGameCatch", "MiniGameFinish", "BuyAccessory", "BuySpeedAccessory", "EquipSpeedAccessory", "EquipAccessory", "SellMonster", "BuyUpgrade", "BuyPass", "BuyWeapon", "EquipWeapon", "BuyProduct", "HitFeedback", "PlayerHurt" } do
    serverEvents[name] = {
        OnServerEvent = signal(),
        FireClient = function(_, _, state) if name == "StateUpdate" then lastState = state end end,
    }
end
local ownsLegacyPass = false
local studio = false
local market = {
    PromptGamePassPurchaseFinished = signal(),
    UserOwnsGamePassAsync = function(_, _, id) return ownsLegacyPass and id == 999 end,
}
local players = { GetPlayers = function() return {} end, GetPlayerByUserId = function(_, id) return if id == 1 then player else nil end }
local services = {
    HttpService = { GenerateGUID = function() return tostring({}) end },
    DataStoreService = { GetDataStore = function() return store end },
    ReplicatedStorage = replicatedStorage,
    StarterPlayer = r.Instance.new("StarterPlayer"),
    Players = players,
    MarketplaceService = market,
    RunService = { IsStudio = function() return studio end },
    Debris = {},
}
local shared = r.Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = replicatedStorage
for _, name in { "Config", "MonsterMath", "Remotes" } do local item = r.Instance.new("ModuleScript"); item.Name = name; item.Parent = shared end
local modules = {
    Remotes = { Get = function() return serverEvents end },
    PlotService = { GetPlot = function() return { LockedUntil = 0, LockCooldownUntil = 0 } end, SendHome = function() end, SetUpgradeLabel = function() end },
    FollowerService = { Init = function() end, GetIds = function() return {} end, GetMinLevel = function() return 25 end, GetDamageBonus = function() return 0 end },
}
local moduleNames = { Config = "Config", MonsterMath = "MonsterMath", Remotes = "Remotes", DataService = "DataService", PlotService = "PlotService", CharacterService = "CharacterService", MonsterService = "MonsterService", FollowerService = "FollowerService", CombatService = "CombatService", MonetizationService = "MonetizationService" }
local function environment(extra)
    local env = {
        game = { GetService = function(_, name) return assert(services[name], name) end },
        script = { Parent = moduleNames },
        require = function(name) return assert(modules[if type(name) == "string" then name else name.Name], tostring(name)) end,
        task = { spawn = function(callback, ...) table.insert(queued, { callback, table.pack(...) }) end, wait = function() end },
        os = { clock = function() return clock end, time = os.time },
    }
    for key, value in r do env[key] = value end
    for key, value in extra or {} do env[key] = value end
    return env
end
local function loadModule(name, path)
    modules[name] = luau.load(fs.readFile(path), { environment = environment(), injectGlobals = true })()
    return modules[name]
end
local config = loadModule("Config", "src/shared/Config.luau")
loadModule("MonsterMath", "src/shared/MonsterMath.luau")
local data = loadModule("DataService", "src/server/DataService.luau")
local characterService = loadModule("CharacterService", "src/server/CharacterService.luau")
local monsters = loadModule("MonsterService", "src/server/MonsterService.luau")
local combat = loadModule("CombatService", "src/server/CombatService.luau")
local monetization = loadModule("MonetizationService", "src/server/MonetizationService.luau")
monsters.HasPass = monetization.HasPass
monsters.Init(serverEvents)
monetization.Init(serverEvents)
local function flushSaves()
    for index = #queued, 1, -1 do
        local pending = queued[index]
        if pending[1] == data.Save or pending.GearSelection then table.remove(queued, index); pending[1](table.unpack(pending[2], 1, pending[2].n)) end
    end
end
local function fire(name, argument, who, sameTime)
    if not sameTime then clock += 1 end
    local before = #queued
    serverEvents[name].OnServerEvent:Fire(who or player, argument)
    if name == "EquipWeapon" or name == "EquipSpeedAccessory" then
        for index = before + 1, #queued do queued[index].GearSelection = true end
    end
    flushSaves()
end
local profile = data.Load(player)
check(profile.Data.Weapons.Bat and profile.Data.EquippedWeapon == "Bat" and profile.Data.EquippedSpeedAccessory == nil, "New profile starts with Bat and no player accessory")
saved.Player_2 = { Version = 1, Coins = 99999, Weapons = { IronSword = true, IceSword = true }, SpeedAccessories = { SwiftSneakers = true, GoldenWings = true } }
local legacyPlayer = makePlayer(2)
local legacy = data.Load(legacyPlayer)
check(legacy.Data.Weapons.IronSword and legacy.Data.Weapons.IceSword and legacy.Data.Weapons.Bat, "Migration preserves old weapon purchases")
check(legacy.Data.SpeedAccessories.SwiftSneakers and legacy.Data.SpeedAccessories.GoldenWings, "Migration preserves old accessory purchases")
check(legacy.Data.EquippedSpeedAccessory == "GoldenWings", "Legacy automatic accessory choice becomes an explicit selection")
saved.Player_3 = { Version = 2, Weapons = "bad", SpeedAccessories = { SwiftSneakers = 1, ShadowCloak = true, Invalid = true }, EquippedWeapon = {}, EquippedSpeedAccessory = "SwiftSneakers" }
local malformed = data.Load(makePlayer(3))
check(malformed.Data.EquippedWeapon == "Bat" and malformed.Data.Weapons.Bat, "Malformed saved weapon fields recover safely")
check(malformed.Data.EquippedSpeedAccessory == nil and malformed.Data.SpeedAccessories.ShadowCloak and not malformed.Data.SpeedAccessories.Invalid, "Malformed accessory fields cannot equip or grant unknown gear")

local function gameTools(who)
    local result = {}
    for _, container in { who:FindFirstChildOfClass("Backpack"), who.Character, who:FindFirstChild("StarterGear") } do
        for _, item in container:GetChildren() do
            if item:IsA("Tool") and item:GetAttribute("GameWeaponOwner") == who.UserId then table.insert(result, item) end
        end
    end
    return result
end
local foreign = r.Instance.new("Tool")
foreign.Name = "Iron Sword"
foreign.Parent = player:FindFirstChildOfClass("Backpack")
combat.GiveWeapons(player, {}, profile.Data.Weapons, profile.Data.EquippedWeapon)
check(#gameTools(player) == 1 and gameTools(player)[1]:GetAttribute("GameWeaponKey") == "Bat", "Only the selected Bat is instantiated")
profile.Data.Coins = 1000000
local beforeCoins = profile.Data.Coins
fire("BuyWeapon", "IronSword")
check(profile.Data.Coins == beforeCoins - config.WeaponCoinPrices.IronSword and profile.Data.Weapons.IronSword, "Weapon purchase charges once and persists ownership")
check(profile.Data.EquippedWeapon == "IronSword" and #gameTools(player) == 1 and gameTools(player)[1].Parent == player.Character, "Purchase equips one selected weapon")
beforeCoins = profile.Data.Coins
fire("BuyWeapon", "IronSword")
check(profile.Data.Coins == beforeCoins, "Buying an owned weapon never charges again")
local stale = gameTools(player)[1]
local staleCopy = stale:Clone()
staleCopy.Parent = player:FindFirstChild("StarterGear")
fire("EquipWeapon", "Bat")
check(stale.Parent == nil and staleCopy.Parent == nil and #gameTools(player) == 1, "Switching removes old weapon copies from Character and StarterGear")
check(profile.Data.Weapons.IronSword == true and foreign.Parent ~= nil, "Switching keeps ownership and foreign Tools")
fire("EquipWeapon", "IronSword", nil, true)
check(profile.Data.EquippedWeapon == "Bat", "Weapon equip cooldown rejects immediate repeat")
fire("EquipWeapon", "LavaSword")
check(profile.Data.EquippedWeapon == "Bat", "Forged unowned sword equip is rejected")
for _, bad in { 4, {}, "", "NoSuchWeapon", string.rep("a", 128) } do fire("EquipWeapon", bad) end
check(profile.Data.EquippedWeapon == "Bat", "Wrong-type and unknown weapon requests are rejected")
fire("EquipWeapon", "IronSword")
check(profile.Data.EquippedWeapon == "IronSword" and #gameTools(player) == 1 and gameTools(player)[1]:GetAttribute("GameWeaponKey") == "IronSword", "Owned weapon can be selected again")
check(saved.Player_1.EquippedWeapon == "IronSword" and saved.Player_1.Weapons.IronSword, "Weapon selection and ownership are saved together")

-- Restore using the actual startup function, including the appearance refresh.
local startup = fs.readFile("src/server/init.server.luau")
local onCharacterSource = assert(startup:match("local function onCharacter%(player: Player, character: Model%).-\nend"))
local onCharacter = luau.load(onCharacterSource .. "\nreturn onCharacter", { environment = environment({
    PlotService = modules.PlotService, CharacterService = characterService, DataService = data, CombatService = combat, MonetizationService = monetization,
}), injectGlobals = true })()
local oldCharacter = player.Character
oldCharacter:Destroy()
local newCharacter = makeCharacter(player)
onCharacter(player, newCharacter)
local appearance = queued[#queued]
appearance[1](table.unpack(appearance[2], 1, appearance[2].n))
check(#gameTools(player) == 1 and gameTools(player)[1]:GetAttribute("GameWeaponKey") == "IronSword", "Respawn and appearance refresh restore the selected sword")
data.Release(player)
profile = data.Load(player)
onCharacter(player, newCharacter)
check(profile.Data.Weapons.IronSword and profile.Data.EquippedWeapon == "IronSword" and #gameTools(player) == 1, "Rejoin restores persisted weapon ownership and selection")

local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
humanoid.Health = 65
beforeCoins = profile.Data.Coins
fire("BuySpeedAccessory", "GoldenWings")
check(profile.Data.SpeedAccessories.GoldenWings and profile.Data.EquippedSpeedAccessory == "GoldenWings", "Accessory purchase saves ownership and auto-equips")
check(profile.Data.Coins == beforeCoins - config.SpeedAccessories.GoldenWings.Price, "Accessory purchase uses the configured coin price")
check(humanoid.Health == 65 and humanoid.MaxHealth == config.PlayerBaseHealth + config.SpeedAccessories.GoldenWings.HealthBonus, "Equipping stronger gear preserves current HP")
beforeCoins = profile.Data.Coins
fire("BuySpeedAccessory", "GoldenWings")
check(profile.Data.Coins == beforeCoins, "Owned accessory cannot be charged again")
fire("BuySpeedAccessory", "SwiftSneakers")
check(profile.Data.EquippedSpeedAccessory == "SwiftSneakers" and profile.Data.SpeedAccessories.GoldenWings, "New weaker gear can be selected without losing stronger ownership")
check(humanoid.WalkSpeed == config.WalkSpeed * config.SpeedAccessories.SwiftSneakers.Multiplier, "Only selected weaker gear affects speed")
check(humanoid.MaxHealth == config.PlayerBaseHealth + config.SpeedAccessories.SwiftSneakers.HealthBonus and humanoid.Health == 65, "Only selected gear affects MaxHealth without healing")
check(player.Character:GetAttribute("EquippedGear") == "SwiftSneakers", "VFX follows the selected accessory")
fire("EquipSpeedAccessory", "GoldenWings")
fire("EquipSpeedAccessory", "SwiftSneakers", nil, true)
check(profile.Data.EquippedSpeedAccessory == "GoldenWings", "Accessory equip cooldown rejects immediate repeat")
fire("EquipSpeedAccessory", "ShadowCloak")
check(profile.Data.EquippedSpeedAccessory == "GoldenWings", "Unowned accessory equip is rejected")
for _, bad in { 4, {}, "", "NoSuchAccessory", string.rep("a", 128) } do fire("EquipSpeedAccessory", bad) end
check(profile.Data.EquippedSpeedAccessory == "GoldenWings", "Wrong-type and unknown accessory requests are rejected")
for _ = 1, 3 do fire("EquipSpeedAccessory", "SwiftSneakers"); fire("EquipSpeedAccessory", "GoldenWings") end
check(humanoid.Health == 65, "Cycling accessories cannot heal")
fire("EquipSpeedAccessory", nil)
check(profile.Data.EquippedSpeedAccessory == nil and humanoid.WalkSpeed == config.WalkSpeed and humanoid.MaxHealth == config.PlayerBaseHealth, "Unequip removes selected speed and HP bonuses")
check(player.Character:GetAttribute("EquippedGear") == nil and profile.Data.SpeedAccessories.GoldenWings and profile.Data.SpeedAccessories.SwiftSneakers, "Unequip removes VFX and preserves purchases")
check(saved.Player_1.EquippedSpeedAccessory == nil and saved.Player_1.SpeedAccessories.GoldenWings, "Explicit unequip is persisted without discarding ownership")
check(characterService.GetSpeedAccessoryMultiplier(profile.Data.SpeedAccessories, "ShadowCloak") == 1, "An unowned selected accessory never affects stats")
humanoid.Health = 0
fire("EquipSpeedAccessory", "GoldenWings")
check(humanoid.Health == 0, "Gear cannot revive a dead player")
data.Release(player)
profile = data.Load(player)
oldCharacter = player.Character
oldCharacter:Destroy()
newCharacter, humanoid = makeCharacter(player)
onCharacter(player, newCharacter)
check(profile.Data.EquippedSpeedAccessory == "GoldenWings" and profile.Data.SpeedAccessories.SwiftSneakers, "Accessory selection and all purchases survive rejoin")
check(humanoid.Health == humanoid.MaxHealth and humanoid.MaxHealth == config.PlayerBaseHealth + config.SpeedAccessories.GoldenWings.HealthBonus, "Fresh respawn applies selected gear with full HP")
check(lastState.EquippedWeapon == "IronSword" and lastState.EquippedSpeedAccessory == "GoldenWings", "Server snapshots expose selected gear")

-- A legacy gamepass is eligible only after the server has verified ownership.
config.Gamepasses.VIPSword.Id = 999
fire("EquipWeapon", "VIPSword")
check(profile.Data.EquippedWeapon == "IronSword", "Uncached legacy pass cannot grant a sword")
ownsLegacyPass = true
monetization.SetupPlayer(player)
local passLoad = queued[#queued]
passLoad[1](table.unpack(passLoad[2], 1, passLoad[2].n))
fire("EquipWeapon", "VIPSword")
check(profile.Data.EquippedWeapon == "VIPSword" and #gameTools(player) == 1, "Verified cached legacy pass qualifies for selection")
beforeCoins = profile.Data.Coins
fire("BuyWeapon", "VIPSword")
check(profile.Data.Coins == beforeCoins, "Legacy pass owner is never charged coin ownership again")
data.Release(player)
monetization.CleanupPlayer(player)
profile = data.Load(player)
combat.GiveWeapons(player, monetization.GetOwnedPasses(player), profile.Data.Weapons, profile.Data.EquippedWeapon)
check(gameTools(player)[1]:GetAttribute("GameWeaponKey") == "Bat", "Saved pass selection waits for verified ownership after rejoin")
monetization.SetupPlayer(player)
passLoad = queued[#queued]
passLoad[1](table.unpack(passLoad[2], 1, passLoad[2].n))
check(profile.Data.EquippedWeapon == "VIPSword" and gameTools(player)[1]:GetAttribute("GameWeaponKey") == "VIPSword", "Pass lookup restores the persisted legacy weapon selection")

-- Exercise the real shop callbacks and refresh code with only widget creation
-- and network transport replaced. Export local bindings solely in this harness.
local buttonSignals = {}
r.implementProperty("TextButton", "Activated", function(button)
    if not buttonSignals[button] then buttonSignals[button] = signal() end
    return buttonSignals[button]
end)
local function widget(class, parent, text, size, position)
    local item = r.Instance.new(class)
    item.Parent = parent
    item.Text = text
    item.Size = size
    item.Position = position
    return item
end
local colors = {}
for _, key in { "Panel", "PanelLight", "Text", "SubText", "Yellow", "Green", "Red", "Blue", "Gray", "Pink", "Orange" } do colors[key] = r.Color3.new(0.5, 0.5, 0.5) end
modules.UI = {
    Colors = colors, Corner = function() end, Stroke = function() end, Icon = function() end,
    WeaponPreview = function(parent, template) parent:SetAttribute("PreviewTemplate", template) end,
    GearPreview = function(parent, name) parent:SetAttribute("GearPreviewName", name) end,
    Label = function(parent, text, size, position, textSize) local item = widget("TextLabel", parent, text, size, position); item.TextSize = textSize or 20; return item end,
    Button = function(parent, text, color, size, position) local item = widget("TextButton", parent, text, size, position); item.TextSize = 20; return item end,
}
moduleNames.UI = "UI"
services.TweenService = {}
players.LocalPlayer = player
local uiRemotes, calls = {}, {}
for name in serverEvents do
    uiRemotes[name] = { FireServer = function(_, ...) table.insert(calls, { Name = name, Args = table.pack(...) }) end }
end
local clientState = {
    Weapons = { Bat = true, IronSword = true }, EquippedWeapon = "IronSword",
    SpeedAccessories = { SwiftSneakers = true, GoldenWings = true }, EquippedSpeedAccessory = "GoldenWings",
}
local featureSource = fs.readFile("src/client/Features.luau"):gsub("return Features%s*$", [[
return {
    Build = buildShopExtras, Refresh = Features.Refresh, Weapons = weaponButtons, Accessories = speedAccessoryButtons, Passes = passButtons, Products = productButtons,
    Context = function(newUi, newRemotes, stateGetter)
        ui = newUi; remotes = newRemotes; getState = stateGetter
        statusLabel = Instance.new("TextLabel"); dailyInfo = Instance.new("TextLabel")
        dailyClaim = Instance.new("TextButton"); spinGo = Instance.new("TextButton"); rewardsButton = Instance.new("TextButton")
        accessoriesFrame = Instance.new("Frame"); accessoriesFrame.Visible = false
    end,
}
]])
local shop = luau.load(featureSource, { environment = environment(), injectGlobals = true })()
local gearPanel = r.Instance.new("Frame")
local gearScroll = r.Instance.new("ScrollingFrame")
shop.Context({ GearFrame = gearPanel, EggButtons = {}, GearScroll = gearScroll, ShopScroll = r.Instance.new("ScrollingFrame"), ShopContentBottom = 0 }, uiRemotes, function() return clientState end)
shop.Build()
shop.Refresh()
check(shop.Weapons.IronSword.Text == "Equipped ✓" and shop.Weapons.Bat.Text == "Equip", "Shop displays selected and owned starter weapons")
check(shop.Weapons.Bat.Parent:GetAttribute("PreviewTemplate") == "WoodenBat" and shop.Weapons.IronSword.Parent:GetAttribute("PreviewTemplate") == config.WeaponStats.IronSword.Template, "Shop previews use the real configured weapon Tools")
check(shop.Accessories.SwiftSneakers.Text == "Equip" and shop.Accessories.GoldenWings.Text == "Equipped · Unequip", "Shop displays owned accessories and an unequip action")
shop.Weapons.Bat.Activated:Fire()
check(calls[#calls].Name == "EquipWeapon" and calls[#calls].Args[1] == "Bat", "Starter weapon button equips the free Bat")
shop.Weapons.IronSword.Activated:Fire()
check(calls[#calls].Name == "EquipWeapon", "Owned weapon button selects without buying again")
shop.Weapons.LavaSword.Activated:Fire()
check(calls[#calls].Name == "BuyWeapon", "Unowned weapon button requests a purchase")
shop.Accessories.SwiftSneakers.Activated:Fire()
check(calls[#calls].Name == "EquipSpeedAccessory" and calls[#calls].Args[1] == "SwiftSneakers", "Owned weaker accessory button selects it")
shop.Accessories.GoldenWings.Activated:Fire()
check(calls[#calls].Name == "EquipSpeedAccessory" and calls[#calls].Args.n == 1 and calls[#calls].Args[1] == nil, "Selected accessory button requests unequip")
shop.Accessories.ShadowCloak.Activated:Fire()
check(calls[#calls].Name == "BuySpeedAccessory", "Unowned accessory button requests a purchase")
local function clickTab(name)
    for _, child in gearPanel:GetDescendants() do
        if child:IsA("TextButton") and child.Name == name .. "Tab" then child.Activated:Fire(); return end
    end
    error("Missing tab " .. name)
end
local function visibleCards()
    local result = {}
    for _, child in gearScroll:GetChildren() do
        if child:IsA("Frame") and child.Visible then table.insert(result, child) end
    end
    return result
end
clickTab("Owned")
check(#visibleCards() == 4, "Owned tab includes starter, owned weapons and owned accessories only")
clientState.SpeedAccessories.ShadowCloak = true
shop.Refresh()
check(#visibleCards() == 5, "Owned tab refreshes when new gear is purchased")
clickTab("Weapons")
check(#visibleCards() == 1 + (function() local n = 0; for _ in config.WeaponStats do n += 1 end; return n end)(), "Weapons tab retains every configured weapon")
check(shop.Weapons.LavaSword.Text == "Buy", "Unowned gear has an explicit Buy action")
clickTab("Coin Packs")
check(#visibleCards() == 3, "Coin packs category retains all repeatable coin offers")
clickTab("Perks")
local feederCard = gearScroll:FindFirstChild("Auto-FeederCard")
check(feederCard ~= nil and feederCard.Visible, "Perks keeps the Auto-Feeder in the scrollable catalog")
local feederBuy = shop.Passes.AutoFeeder
local autoFeederPassId = config.Gamepasses.AutoFeeder.Id
config.Gamepasses.AutoFeeder.Id = 0 -- Temporary fixture for inactive production and free Studio behavior.
shop.Refresh()
local beforeCalls = #calls
feederBuy.Activated:Fire()
check(feederBuy.Text == "Coming soon" and not feederBuy.Active and not feederBuy.Selectable and #calls == beforeCalls, "Unconfigured Auto-Feeder is inactive in production")
local feederPrice
for _, child in feederCard:GetChildren() do if child:IsA("TextLabel") and child.Text == "R$ 99" then feederPrice = child end end
check(feederPrice ~= nil, "Unavailable Auto-Feeder still discloses its configured 99 Robux price")
studio = true
shop.Refresh()
feederBuy.Activated:Fire()
check(feederBuy.Text == "Test free (Studio)" and feederBuy.Active and calls[#calls].Name == "BuyPass" and calls[#calls].Args[1] == "AutoFeeder", "Auto-Feeder keeps its explicit free Studio test callback")
clientState.Passes = { AutoFeeder = true }
shop.Refresh()
beforeCalls = #calls
feederBuy.Activated:Fire()
check(feederBuy.Text == "Owned ✓" and not feederBuy.Active and #calls == beforeCalls, "Owned Auto-Feeder cannot be requested again")
clientState.Passes = {}
studio = false
config.Gamepasses.AutoFeeder.Id = autoFeederPassId
shop.Refresh()
feederBuy.Activated:Fire()
check(feederBuy.Text == "Buy" and feederBuy.Active and calls[#calls].Name == "BuyPass" and calls[#calls].Args[1] == "AutoFeeder", "Configured production Auto-Feeder retains the purchase callback")
shop.Refresh()
beforeCalls = #calls
shop.Products.InstantHatch.Activated:Fire()
check(shop.Products.InstantHatch.Text == "Coming soon" and #calls == beforeCalls, "Unconfigured products also disclose their production availability")
shop.Products.Coins1000.Activated:Fire()
check(shop.Products.Coins1000.Text == "Buy" and calls[#calls].Name == "BuyProduct" and calls[#calls].Args[1] == "Coins1000", "Configured repeatable coin product keeps the purchase callback")
for _, child in gearPanel:GetDescendants() do
    check(not (child:IsA("TextButton") and child.Text:find("Premium")), "Shop has no Premium navigation")
end

-- Build the real UI and exercise its viewport callbacks. Roblox-only visual
-- effects are replaced; widget sizes, layout and production callbacks are real.
modules.GuiTheme = { Colors = colors, Gloss = function() end, ButtonFeedback = function() end, Icon = function() end, DecorateButton = function() end, DecoratePill = function() end }
moduleNames.GuiTheme = "GuiTheme"
local viewport = r.Vector2.new(568, 320)
local camera = { ViewportSize = viewport }
function camera:GetPropertyChangedSignal(name)
    propertySignals[self] = propertySignals[self] or {}
    propertySignals[self][name] = propertySignals[self][name] or signal()
    return propertySignals[self][name]
end
local workspaceSignals = {}
local uiWorkspace = {
    CurrentCamera = camera,
    DescendantAdded = signal(), DescendantRemoving = signal(),
    GetDescendants = function() return {} end,
    GetPropertyChangedSignal = function(_, name) workspaceSignals[name] = workspaceSignals[name] or signal(); return workspaceSignals[name] end,
}
local guiSignals = {}
services.GuiService = {
    TopbarInset = r.Rect.new(0, 0, 0, 36),
    GetGuiInset = function() return r.Vector2.new(0, 36), r.Vector2.zero end,
    GetPropertyChangedSignal = function(_, name) guiSignals[name] = guiSignals[name] or signal(); return guiSignals[name] end,
}
services.SoundService = r.Instance.new("SoundService")
services.UserInputService = { InputBegan = signal(), GamepadEnabled = false }
local clientGame = { GetService = function(_, name) return assert(services[name], name) end, DescendantAdded = signal(), GetDescendants = function() return {} end }
local uiEnvironment = environment({ workspace = uiWorkspace, game = clientGame })
local actualUI = luau.load(fs.readFile("src/client/UI.luau"), { environment = uiEnvironment, injectGlobals = true })()
local playerGui = r.Instance.new("PlayerGui")
playerGui.Parent = player
local builtUI = actualUI.Create(playerGui)
check(builtUI.ShopFrame == builtUI.GearFrame and builtUI.EggShopFrame ~= builtUI.ShopFrame, "Primary ShopFrame alias and independent egg panel are preserved")
local rootScale = builtUI.Gui:FindFirstChildOfClass("UIScale")
local shopScale = builtUI.GearFrame:FindFirstChild("NativeShopScale")
check(math.abs(rootScale.Scale * shopScale.Scale - 1) < 0.0001, "Phone catalog cancels the inherited HUD shrink scale")
local hudScale = builtUI.Hud:FindFirstChild("NativeHudScale")
check(math.abs(rootScale.Scale * hudScale.Scale - 1) < 0.0001, "Phone HUD also preserves native pixel touch targets")
check(builtUI.InventoryButton == builtUI.NavigationButtons.Inventory and builtUI.InventoryButton.NextSelectionUp == builtUI.NavigationButtons.Arena, "Monster inventory has a dedicated reachable gamepad navigation button")
for _, item in builtUI.NavigationButtons do check(item.Size.Y.Offset >= 44 and item.Size.X.Offset >= 44, "Navigation pills retain readable native touch targets") end
local navigation = builtUI.Hud:FindFirstChild("Navigation")
check(navigation.CanvasSize.Y.Offset > navigation.Size.Y.Offset, "Landscape phone navigation scrolls instead of shrinking buttons")
check(builtUI.GearFrame.Size.X.Offset == 552 and builtUI.GearFrame.Size.Y.Offset == 268, "568x320 phone shop fits the usable viewport with native pixels")
shop.Context(builtUI, uiRemotes, function() return clientState end)
shop.Build()
shop.Refresh()
gearPanel = builtUI.GearFrame
gearScroll = builtUI.GearScroll
local categories = builtUI.GearFrame:FindFirstChild("Categories")
check(categories.ScrollingDirection == r.Enum.ScrollingDirection.X and categories.Size.Y.Offset == 48, "Phone categories use a horizontal scroll row")
local phoneClose = builtUI.GearFrame:FindFirstChild("CloseButton")
check(phoneClose.Position.Y.Offset >= 0 and categories.Position.Y.Offset >= phoneClose.Position.Y.Offset + phoneClose.Size.Y.Offset, "Phone close control stays fully inside the safe panel and clear of category tabs")
local phoneCards = {}
for _, child in builtUI.GearScroll:GetChildren() do if child:IsA("Frame") and child.Visible then table.insert(phoneCards, child) end end
check(#phoneCards > 2 and phoneCards[1].Size.X.Offset >= 184 and phoneCards[1].Position.Y.Offset == phoneCards[2].Position.Y.Offset, "Phone catalog reflows to two readable columns")
local phoneFeeder = builtUI.GearScroll:FindFirstChild("Auto-FeederCard")
clickTab("Perks")
check(phoneFeeder ~= nil and phoneFeeder.Visible and builtUI.GearScroll.CanvasSize.Y.Offset > builtUI.GearFrame.Size.Y.Offset, "Phone Auto-Feeder remains reachable in the Perks catalog")
clickTab("Weapons")
for _, item in builtUI.GearFrame:GetDescendants() do
    if item:IsA("TextButton") then check(item.Size.Y.Offset >= 44 and item.TextSize >= 16, "Phone shop controls retain native touch size and text") end
end
viewport = r.Vector2.new(320, 568)
camera.ViewportSize = viewport
propertySignals[camera].ViewportSize:Fire()
propertySignals[builtUI.GearFrame].Size:Fire()
check(builtUI.GearFrame.Size.X.Offset == 304 and shop.Weapons.Bat.Parent.Size.X.Offset >= 250 and shop.Weapons.IronSword.Parent.Position.X.Offset == 0, "Portrait phone reflows to one readable column")
viewport = r.Vector2.new(1280, 720)
camera.ViewportSize = viewport
propertySignals[camera].ViewportSize:Fire()
propertySignals[builtUI.GearFrame].Size:Fire()
check(builtUI.GearFrame.Size.X.Offset == 860 and builtUI.GearFrame.Size.Y.Offset == 530 and phoneFeeder.Parent == builtUI.GearScroll, "Desktop viewport restores the wide catalog and retains the Perks card")
check(shop.Weapons.IronSword.Parent.Position.Y.Offset == 4 and shop.Weapons.IronSword.Parent.Position.X.Offset > shop.Weapons.IronBat.Parent.Position.X.Offset and shop.Weapons.ForestSword.Parent.Position.Y.Offset > 4, "Desktop catalog restores three price-sorted columns")
check(math.abs(rootScale.Scale * shopScale.Scale - 1) < 0.0001, "Desktop catalog also keeps native pixels")

viewport = r.Vector2.new(568, 320)
camera.ViewportSize = viewport
local settings = luau.load(fs.readFile("src/client/Settings.luau"), { environment = uiEnvironment, injectGlobals = true })()
local cleanupSettings = settings.Init(builtUI)
local settingsGui = playerGui:FindFirstChild("RaiseAMonsterSettings")
local settingsPanel = settingsGui:FindFirstChild("SettingsPanel")
local settingsContent = settingsPanel:FindFirstChild("SettingsContent")
check(settingsPanel:FindFirstChildOfClass("UIScale") == nil and settingsPanel.Size.Y.Offset == 250, "Landscape phone settings uses available height without shrinking controls")
check(settingsContent.CanvasSize.Y.Offset > settingsPanel.Size.Y.Offset - 64, "Compact settings provides scroll access to all controls")
for _, item in settingsGui:GetDescendants() do if item:IsA("TextButton") then check(item.Size.Y.Offset >= 44 and item.TextSize >= 15, "Compact settings keeps readable text and 44 pixel controls") end end
settingsGui:FindFirstChild("SettingsToggle").Activated:Fire()
check(settingsPanel.Visible, "Compact settings can still be opened")
local muteButton, hideButton
for _, item in settingsContent:GetChildren() do
    if item:IsA("TextButton") and item.Text == "Mute" then muteButton = item elseif item:IsA("TextButton") and item.Text == "Hide UI" then hideButton = item end
end
muteButton.Activated:Fire()
check(muteButton.Text == "Unmute", "Settings mute callback survives the scroll layout")
hideButton.Activated:Fire()
check(not builtUI.Gui.Enabled and hideButton.Text == "Show UI", "Settings remains usable when the main UI is hidden")
cleanupSettings()
local destroySignals = {}
r.implementProperty("Frame", "Destroying", function(frame)
    if not destroySignals[frame] then destroySignals[frame] = signal() end
    return destroySignals[frame]
end)
-- Exercise the unmodified module: icon rendering must not depend on engine
-- image-loader flags that Lune does not implement and Studio can report late.
local themeJobs = {}
local themeEnvironment = table.clone(uiEnvironment)
themeEnvironment.task = { spawn = function(callback) table.insert(themeJobs, callback) end }
local actualTheme = luau.load(fs.readFile("src/client/GuiTheme.luau"), { environment = themeEnvironment, injectGlobals = true })()
local pill = r.Instance.new("TextButton")
pill.Text = "Upgrades"
pill.Size = r.UDim2.fromOffset(150, 44)
local pillCorner = r.Instance.new("UICorner")
pillCorner.Parent = pill
actualTheme.DecoratePill(pill, "Strength")
local pillCaption = pill:FindFirstChild("Caption")
check(pillCaption.Text == "UPGRADES" and pillCaption.TextSize >= 16 and pillCaption.Size.X.Offset > -80, "Approved pill style keeps an uppercase readable caption at the smallest native size")
check(pillCorner.CornerRadius.Scale == 1 and pill:FindFirstChild("StrengthIcon") ~= nil, "Approved pill style uses a rounded silhouette and the requested atlas icon")
pill.Text = "Inventory"
propertySignals[pill].Text:Fire()
check(pillCaption.Text == "INVENTORY", "Pill captions follow real button text updates")
check(actualTheme.IconRects.Shop == r.Vector2.new(0, 0) and actualTheme.IconRects.Gift == r.Vector2.new(1, 0) and actualTheme.IconRects.Settings == r.Vector2.new(2, 1) and actualTheme.IconRects.Trophy == r.Vector2.new(1, 3), "Original icon sheet maps shop, gift, settings and arena to the correct cells")
check(actualTheme.Atlas.Image == "rbxassetid://116704436062887" and actualTheme.Atlas.Size == r.Vector2.new(1080, 1187) and actualTheme.Atlas.CellSize == r.Vector2.new(360, 296.75), "Atlas uses the verified uploaded original image and preserves its rectangular cell dimensions")
for _, nativeSize in { 640, 76, 44 } do
    for name, cell in actualTheme.IconRects do
        local icon = actualTheme.Icon(pill, name, r.UDim2.fromOffset(nativeSize, nativeSize), r.UDim2.fromOffset(0, 0))
        local atlasViewport = icon:FindFirstChild("AtlasViewport")
        local atlasImage = atlasViewport:FindFirstChild("AtlasImage")
        local atlasAspect = atlasViewport:FindFirstChildOfClass("UIAspectRatioConstraint")
        local fallback = icon:FindFirstChild("Fallback")
        check(icon:IsA("Frame") and icon.Size.X.Offset == nativeSize and icon.Size.Y.Offset == nativeSize and atlasViewport.ClipsDescendants, "Atlas root keeps its caller size and clips the requested cell")
        check(atlasViewport.Size == r.UDim2.fromScale(1, 1) and atlasViewport.AnchorPoint == r.Vector2.new(0.5, 0.5) and math.abs(atlasAspect.AspectRatio - 360 / 296.75) < 0.00001, "Atlas clipping preserves the original cell aspect within each native or mobile icon")
        check(atlasImage.Size == r.UDim2.fromScale(3, 4) and atlasImage.Position == r.UDim2.fromScale(-cell.X, -cell.Y) and atlasImage.ScaleType == r.Enum.ScaleType.Stretch, "Every atlas cell uses resolution independent normalized sheet geometry")
        check(atlasImage.Image == actualTheme.Atlas.Image and not fallback.Visible and atlasViewport.Visible, "Configured original artwork stays visible without a fallback covering valid atlas pixels")
        atlasImage.Image = ""
        propertySignals[atlasImage].Image:Fire()
        check(fallback.Visible and atlasViewport.Visible, "An unconfigured atlas still has a readable fallback")
        atlasImage.Image = actualTheme.Atlas.Image
        propertySignals[atlasImage].Image:Fire()
        check(not fallback.Visible, "Configuring the verified atlas removes its fallback immediately")
        icon.ZIndex = 8
        propertySignals[icon].ZIndex:Fire()
        check(atlasImage.ZIndex == 8 and atlasViewport.ZIndex == 8 and fallback.ZIndex == 9, "Fallback stays above the atlas after icon layer updates")
        destroySignals[icon]:Fire()
        icon:Destroy()
    end
end
check(#themeJobs == 0, "Rendering configured atlas icons starts no preload workers, retry loops or polling")
for _, file in { "Features", "UI", "GuiTheme", "Settings" } do
    luau.compile(fs.readFile("src/client/" .. file .. ".luau"))
end
print(string.format("PASS: %d inventory checks (migration, purchases, forged requests, saved selection, respawn/rejoin, real asset Tools, accessory stats/VFX and HP)", checks))
