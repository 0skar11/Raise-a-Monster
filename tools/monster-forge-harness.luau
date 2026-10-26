-- Shared production UI/Features/MonsterForge harness. Engine renderers and network are stubbed.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local function signal()
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn); return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local signals, buttons = {}, {}
local function changed(item, name)
	signals[item] = signals[item] or {}; signals[item][name] = signals[item][name] or signal()
	return signals[item][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", changed)
r.implementProperty("TextButton", "Activated", function(item)
	buttons[item] = buttons[item] or signal(); return buttons[item]
end)
return function(options)
options = options or {}
local env = {}
for key, value in r do env[key] = value end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env, injectGlobals = true })()
local colors = {}
for _, name in { "Panel", "PanelLight", "Text", "SubText", "Yellow", "Green", "Red", "Blue", "Gray", "Pink", "Orange" } do colors[name] = r.Color3.new(0.5, 0.5, 0.5) end
local theme = { ModalShrink = function() return 1 end, Backdrop = function() end, Colors = colors, Gloss = function() end, ButtonFeedback = function() end, DecoratePill = function() end, DecorateButton = function() end }
function theme.Icon(parent, _, size, position)
	local icon = r.Instance.new("Frame"); icon.Size = size; icon.Position = position; icon.Parent = parent; return icon
end
local modules = { Config = config, MonsterMath = { FormatNumber = tostring }, GuiTheme = theme, TravelControls = {}, RewardsArcade = {} }
local camera = { ViewportSize = r.Vector2.new(1096, 676), GetPropertyChangedSignal = changed }
local workspace = { CurrentCamera = camera, GetPropertyChangedSignal = changed }
local services = {
	Players = { LocalPlayer = {} }, ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
	TweenService = {}, RunService = { IsStudio = function() return false end },
	GuiService = { GetGuiInset = function() return r.Vector2.new(0, 36), r.Vector2.zero end },
}
local delayed, spawned = {}, {}
env.task = { delay = function(_, callback) table.insert(delayed, callback) end, spawn = function(callback) table.insert(spawned, callback) end }
if options.Market then services.MarketplaceService = { GetProductInfo = function(_, ...) return options.Market(...) end } end
services.RunService.IsStudio = function() return options.Studio == true end
env.game = { GetService = function(_, name) return assert(services[name], name) end }
env.workspace = workspace
env.script = { Parent = { UI = "UI", GuiTheme = "GuiTheme", TravelControls = "TravelControls", RewardsArcade = "RewardsArcade", MonsterForge = "MonsterForge", CartoonUI = "CartoonUI" } }
env.require = function(name) return assert(modules[name], name) end
-- Decorative images are real GuiObjects; network loading is an engine concern.
modules.CartoonUI = { Icon = function(parent, _, size)
	local icon = r.Instance.new("ImageLabel"); icon.BackgroundTransparency = 1; icon.Size = r.UDim2.fromOffset(size, size); icon.Parent = parent; return icon
end, DecorateShell = function(parent)
	local image = r.Instance.new("ImageLabel"); image.Name = "CartoonBackdrop"; image.Size = r.UDim2.fromScale(1, 1); image.Parent = parent; return image
end }
local uiModule = luau.load(fs.readFile("src/client/UI.luau"), { environment = env, injectGlobals = true })()
modules.UI = uiModule
-- Preview rendering is unrelated to layout; preserve each viewport's real class.
for _, method in { "WeaponPreview", "GearPreview" } do
	uiModule[method] = function(parent)
		local preview = r.Instance.new("ViewportFrame"); preview.Name = method; preview.Parent = parent
	end
end
modules.MonsterForge = luau.load(fs.readFile("src/client/MonsterForge.luau"), { environment = env, injectGlobals = true })()
local source = fs.readFile("src/client/Features.luau"):gsub("return Features%s*$", [[
return { Build = buildShopExtras, Refresh = function() refreshShopCatalog(); refreshAdultChooser() end, Context = function(newUi, stateGetter, allRemotes)
	ui = newUi; getState = stateGetter; remotes = allRemotes
end }
]])
local features = luau.load(source, { environment = env, injectGlobals = true })()
local ui = uiModule.Create(r.Instance.new("PlayerGui"))
local state = { Weapons = { IronSword = true }, SpeedAccessories = { SwiftSneakers = true }, Passes = {}, Monsters = {}, EquippedWeapon = "IronSword" }
local calls, remotes = {}, {}
for _, name in { "EquipWeapon", "BuyWeapon", "EquipSpeedAccessory", "BuySpeedAccessory", "BuyPass", "BuyProduct" } do
	remotes[name] = { FireServer = function(_, ...) table.insert(calls, { Name = name, Args = table.pack(...) }) end }
end
features.Context(ui, function() return state end, remotes)
features.Build()
local h = { UI = ui, Config = config, Roblox = r, State = state, Calls = calls, Module = modules.MonsterForge }
function h.Refresh() features.Refresh() end
function h.Resize(x,y) camera.ViewportSize = r.Vector2.new(x,y); changed(camera,"ViewportSize"):Fire(); changed(ui.GearFrame,"Size"):Fire() end
function h.Tab(name) ui.GearFrame.Categories:FindFirstChild(name .. "Tab").Activated:Fire() end
function h.Card(key) return assert(ui.GearScroll:FindFirstChild(key .. "Card"), key) end
function h.Select(key) h.Card(key).BuyButton.Activated:Fire() end
function h.Detail() return ui.GearFrame:FindFirstChild("SelectedItem", true) end
function h.Action() h.Detail().BuyButton.Activated:Fire() end
function h.Last() return calls[#calls] end
function h.Flush() local jobs = delayed; delayed = {}; for _, job in jobs do job() end end
function h.Fetch() local jobs = spawned; spawned = {}; for _, job in jobs do job() end end
h.Refresh()
return h
end
