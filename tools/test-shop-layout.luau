-- Execute actual UI.Create and catalog construction. Lune verifies geometry and
-- callbacks; font rasterization, 3D appearance and input occlusion need Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
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
local env = {}
for key, value in r do env[key] = value end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env, injectGlobals = true })()
local colors = {}
for _, name in { "Panel", "PanelLight", "Text", "SubText", "Yellow", "Green", "Red", "Blue", "Gray", "Pink", "Orange" } do colors[name] = r.Color3.new(0.5, 0.5, 0.5) end
local theme = { Colors = colors, Gloss = function() end, ButtonFeedback = function() end, DecoratePill = function() end, DecorateButton = function() end }
function theme.Icon(parent, _, size, position)
	local icon = r.Instance.new("Frame"); icon.Size = size; icon.Position = position; icon.Parent = parent; return icon
end
local modules = { Config = config, MonsterMath = { FormatNumber = tostring }, GuiTheme = theme, TravelControls = {} }
local camera = { ViewportSize = r.Vector2.new(1096, 676), GetPropertyChangedSignal = changed }
local workspace = { CurrentCamera = camera, GetPropertyChangedSignal = changed }
local services = {
	Players = { LocalPlayer = {} }, ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
	TweenService = {}, RunService = { IsStudio = function() return false end },
	GuiService = { GetGuiInset = function() return r.Vector2.new(0, 36), r.Vector2.zero end },
}
env.game = { GetService = function(_, name) return assert(services[name], name) end }
env.workspace = workspace
env.script = { Parent = { UI = "UI", GuiTheme = "GuiTheme", TravelControls = "TravelControls" } }
env.require = function(name) return assert(modules[name], name) end
local uiModule = luau.load(fs.readFile("src/client/UI.luau"), { environment = env, injectGlobals = true })()
modules.UI = uiModule
-- Preview rendering is unrelated to layout; preserve each viewport's real class.
for _, method in { "WeaponPreview", "GearPreview" } do
	uiModule[method] = function(parent)
		local preview = r.Instance.new("ViewportFrame"); preview.Name = method; preview.Parent = parent
	end
end
local source = fs.readFile("src/client/Features.luau"):gsub("return Features%s*$", [[
return { Build = buildShopExtras, Context = function(newUi, stateGetter, allRemotes)
	ui = newUi; getState = stateGetter; remotes = allRemotes
end }
]])
local features = luau.load(source, { environment = env, injectGlobals = true })()
local ui = uiModule.Create(r.Instance.new("PlayerGui"))
local state = { Weapons = { IronSword = true }, SpeedAccessories = { SwiftSneakers = true }, Passes = {} }
local calls, remotes = {}, {}
for _, name in { "EquipWeapon", "BuyWeapon", "EquipSpeedAccessory", "BuySpeedAccessory", "BuyPass", "BuyProduct" } do
	remotes[name] = { FireServer = function(_, ...) table.insert(calls, { Name = name, Args = table.pack(...) }) end }
end
features.Context(ui, function() return state end, remotes)
features.Build()
local function rect(item, width, height)
	local w = item.Size.X.Scale * width + item.Size.X.Offset
	local h = item.Size.Y.Scale * height + item.Size.Y.Offset
	return { x = item.Position.X.Scale * width + item.Position.X.Offset - item.AnchorPoint.X * w,
		y = item.Position.Y.Scale * height + item.Position.Y.Offset - item.AnchorPoint.Y * h, w = w, h = h }
end
local function overlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local categories = ui.GearFrame:FindFirstChild("Categories")
local function tab(name)
	categories:FindFirstChild(name .. "Tab").Activated:Fire()
end
for _, viewport in { r.Vector2.new(1096, 676), r.Vector2.new(1920, 1080), r.Vector2.new(320, 568), r.Vector2.new(568, 320), r.Vector2.new(480, 320) } do
	camera.ViewportSize = viewport; changed(camera, "ViewportSize"):Fire(); changed(ui.GearFrame, "Size"):Fire()
	local w, h = ui.GearFrame.Size.X.Offset, ui.GearFrame.Size.Y.Offset
	check(w <= 740 and h <= 470 and w <= viewport.X - 24 and h <= viewport.Y - 60, "Compact panel fits usable viewport")
	check(ui.GearFrame.Position == r.UDim2.fromScale(0.5, 0.5), "Shop remains centered")
	local rootScale = ui.Gui:FindFirstChildOfClass("UIScale")
	check(math.abs(rootScale.Scale * ui.GearFrame.NativeShopScale.Scale - 1) < 0.0001, "Shop targets retain native size")
	local categoryRect, closeRect = rect(categories, w, h), rect(ui.GearFrame.CloseButton, w, h)
	local content = rect(ui.GearScroll, w, h)
	check(closeRect.y >= 0 and closeRect.y + closeRect.h <= categoryRect.y and categoryRect.y + categoryRect.h <= content.y, "Header, tabs and catalog stay separate")
	check(content.h >= 96 and content.y + content.h <= h, "Scrolling body remains usable on short landscape")
	local expected = { Weapons = 1, Accessories = 0, ["Coin Packs"] = 0, Perks = 0, Owned = 3 }
	for _ in config.WeaponStats do expected.Weapons += 1 end
	for _ in config.SpeedAccessories do expected.Accessories += 1 end
	for _, product in config.Products do if product.Coins then expected["Coin Packs"] += 1 else expected.Perks += 1 end end
	for name, pass in config.Gamepasses do if not config.WeaponStats[name] and not pass.Hidden then expected.Perks += 1 end end
	for _, name in { "Weapons", "Accessories", "Coin Packs", "Owned", "Perks" } do
		tab(name)
		local count, visible = 0, {}
		for _, card in ui.GearScroll:GetChildren() do
			if card:IsA("Frame") and card.Visible then
				count += 1
				local bounds = rect(card, content.w, content.h)
				check(bounds.x >= 0 and bounds.x + bounds.w <= content.w - 8 and bounds.y + bounds.h <= ui.GearScroll.CanvasSize.Y.Offset, "Card fits scroll canvas and scrollbar gutter")
				for _, other in visible do check(not overlap(bounds, other), "Catalog cards do not overlap") end
				table.insert(visible, bounds)
				local regions = {}
				for _, childName in { "Preview", "Title", "Description", "Price", "BuyButton" } do
					local child = card:FindFirstChild(childName)
					local region = rect(child, bounds.w, bounds.h)
					check(region.x >= 0 and region.y >= 0 and region.x + region.w <= bounds.w and region.y + region.h <= bounds.h, "Content stays inside compact card")
					for _, other in regions do check(not overlap(region, other), "Preview, copy, price and action never overlap") end
					table.insert(regions, region)
					if childName == "BuyButton" then check(region.h >= 44 and region.w >= 44 and child.TextSize >= 18, "Purchase retains a legible native touch target") end
					if childName == "Description" then check(child.TextSize >= 14 and child.TextTruncate == r.Enum.TextTruncate.None and region.h >= 42, "Full description retains wrapping space") end
				end
			end
		end
		check(count == expected[name], "Category retains its configured offers: " .. name)
		local button = categories:FindFirstChild(name .. "Tab")
		check(button.Size.Y.Offset >= 44 and button.Size.X.Offset >= 116, "Categories remain readable touch targets")
	end
end
ui.GearScroll:FindFirstChild("Wooden BatCard").BuyButton.Activated:Fire()
check(calls[#calls].Name == "EquipWeapon" and calls[#calls].Args[1] == "Bat", "Starter weapon still equips")
ui.GearScroll:FindFirstChild("Iron SwordCard").BuyButton.Activated:Fire()
check(calls[#calls].Name == "EquipWeapon" and calls[#calls].Args[1] == "IronSword", "Owned weapon still equips")
ui.GearScroll:FindFirstChild("Lava SwordCard").BuyButton.Activated:Fire()
check(calls[#calls].Name == "BuyWeapon" and calls[#calls].Args[1] == "LavaSword", "Unowned weapon retains purchase route")
ui.GearScroll:FindFirstChild("Auto-FeederCard").BuyButton.Activated:Fire()
check(calls[#calls].Name == "BuyPass" and calls[#calls].Args[1] == "AutoFeeder", "Perk retains gamepass purchase route")
ui.GearScroll:FindFirstChild("1,000 CoinsCard").BuyButton.Activated:Fire()
check(calls[#calls].Name == "BuyProduct" and calls[#calls].Args[1] == "Coins1000", "Repeatable coin product keeps its purchase route")
print(string.format("PASS: %d actual shop layout and callback checks", checks))
