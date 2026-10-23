-- Actual theme decorators: geometry, input transparency, unique native glyphs,
-- category accents, native hit targets and hover/press cleanup.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function signal()
	local callbacks = {}
	return { Connect = function(_, callback)
		local item = { Callback = callback, Connected = true }; table.insert(callbacks, item)
		return { Disconnect = function() item.Connected = false end }
	end, Fire = function(_, ...) for _, item in callbacks do if item.Connected then item.Callback(...) end end end }
end
local changed, events = {}, {}
local function event(object, name)
	events[object] = events[object] or {}; events[object][name] = events[object][name] or signal()
	return events[object][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", function(object, name)
	changed[object] = changed[object] or {}; changed[object][name] = changed[object][name] or signal(); return changed[object][name]
end)
r.implementProperty("Instance", "Destroying", function(object) return event(object, "Destroying") end)
for _, name in { "MouseEnter", "MouseLeave", "SelectionGained", "SelectionLost", "InputBegan" } do
	r.implementProperty("GuiObject", name, function(object) return event(object, name) end)
end
local ended, tweens = signal(), 0
local services = { UserInputService = { InputEnded = ended }, TweenService = { Create = function(_, target, _, properties)
	return { Play = function() for name, value in properties do target[name] = value end; tweens += 1 end, Cancel = function() end }
end } }
local environment = { game = { GetService = function(_, name) return assert(services[name], name) end } }
for key, value in r do environment[key] = value end
environment.TweenInfo = { new = function() return {} end }
local theme = luau.load(fs.readFile("src/client/GuiTheme.luau"), { environment = environment, injectGlobals = true })()
local signatures = {}
for _, name in { "Shop", "Gift", "Friends", "Trophy", "Pets", "Settings", "Play", "Rebirth", "Coins", "Cash", "Strength", "Potion" } do
	local button = r.Instance.new("TextButton"); button.Size = r.UDim2.fromOffset(48, 48); button.Text = name
	local corner = r.Instance.new("UICorner"); corner.CornerRadius = r.UDim.new(1, 0); corner.Parent = button
	local border = r.Instance.new("UIStroke"); border.Parent = button
	theme.Gloss(button); theme.ButtonFeedback(button, border); theme.DecoratePill(button, name)
	check(button.Active and button.Selectable and button.Size.X.Offset == 48 and button.Size.Y.Offset == 48, name .. " retains native input bounds")
	check(button:GetAttribute("AccessibleName") == name and button.TextTransparency == 1, name .. " keeps its semantic action")
	check(corner.CornerRadius.Scale == 0 and corner.CornerRadius.Offset <= 4, name .. " is a square pixel tile")
	check(button.BackgroundColor3 == theme.IconColors[name], name .. " has its category accent")
	local burst = assert(button:FindFirstChild("PixelBurst")); check(burst.ClipsDescendants and #burst:GetChildren() == 12, name .. " has bounded clipped rays")
	local icon = assert(button:FindFirstChild(name .. "Icon"))
	local pieces, signature = 0, {}
	for _, item in button:GetDescendants() do
		if item:IsA("GuiObject") then check(not item.Active and not item.Selectable, "Decorations cannot intercept input") end
		check(not item:IsA("ImageLabel") and not item:IsA("TextLabel"), "Pixel tiles do not depend on atlas backgrounds or emoji")
	end
	for _, item in icon:GetChildren() do
		if item:IsA("Frame") then
			pieces += 1; table.insert(signature, tostring(item.Position) .. tostring(item.Size))
			check(item.Position.X.Scale >= 0 and item.Position.Y.Scale >= 0 and item.Position.X.Scale + item.Size.X.Scale <= 1.00001 and item.Position.Y.Scale + item.Size.Y.Scale <= 1.00001, "Glyph pixels remain inside their logical canvas")
		end
	end
	check(pieces > 8 and pieces <= 100, name .. " uses a bounded native glyph")
	local combined = table.concat(signature, "|"); check(not signatures[combined], name .. " has distinguishable artwork"); signatures[combined] = true
	button.ZIndex = 8; changed[button].ZIndex:Fire(); changed[icon].ZIndex:Fire()
	check(icon.ZIndex == 9 and burst.ZIndex == 8, "Glyph remains above its burst")
	event(button, "MouseEnter"):Fire(); check(border.Color == r.Color3.fromRGB(12, 16, 31), "Hover keeps the black frame")
	event(button, "SelectionGained"):Fire(); check(border.Thickness == 3, "Gamepad selection remains visible")
	event(button, "Destroying"):Fire()
end
local panel = r.Instance.new("Frame"); panel.BackgroundColor3 = theme.Colors.Panel; panel:SetAttribute("PixelAccent", theme.IconColors.Shop)
local border = r.Instance.new("UIStroke"); border.Parent = panel
theme.Gloss(panel)
check(panel:FindFirstChild("PixelInset"):FindFirstChildOfClass("UIStroke").Color == theme.IconColors.Shop, "Panel accents match their action family")
check(tweens > 0, "Feedback still animates without altering actions")
print("Pixel GUI theme: " .. checks .. " checks PASS")
