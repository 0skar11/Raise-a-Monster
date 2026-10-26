-- Executes the production rewards controller against Roblox instances; no renderer or live data.
local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function signal()
	local items = {}
	return {
		Connect = function(_, callback)
			local item = { Callback = callback, Connected = true }; table.insert(items, item)
			return { Disconnect = function() item.Connected = false end }
		end,
		Fire = function(_, ...) for _, item in items do if item.Connected then item.Callback(...) end end end,
	}
end
local signals = {}
local function event(object, name)
	signals[object] = signals[object] or {}
	signals[object][name] = signals[object][name] or signal()
	return signals[object][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", event)
r.implementProperty("Instance", "Destroying", function(object) return event(object, "Destroying") end)
r.implementProperty("TextButton", "Activated", function(object) return event(object, "Activated") end)
local scheduled, tweens = {}, {}
local camera = { ViewportSize = r.Vector2.new(1280, 800), GetPropertyChangedSignal = event }
local workspace = { CurrentCamera = camera, GetPropertyChangedSignal = event }
local modules = {}
local services = {
	ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
	GuiService = { GetGuiInset = function() return r.Vector2.new(0, 36), r.Vector2.zero end },
	TweenService = { Create = function(_, object, _, properties)
		local tween = { Object = object, Properties = properties, Cancelled = false }
		tween.Play = function() for name, value in properties do object[name] = value; event(object, name):Fire() end end
		tween.Cancel = function() tween.Cancelled = true end
		table.insert(tweens, tween)
		return tween
	end },
}
local env = {
	game = { GetService = function(_, name) return assert(services[name], name) end },
	workspace = workspace,
	script = { Parent = { Config = "Config", GuiTheme = "GuiTheme", CartoonUI = "CartoonUI" } },
	require = function(name) return assert(modules[name], name) end,
	task = { delay = function(seconds, callback) table.insert(scheduled, { Seconds = seconds, Callback = callback }) end },
	TweenInfo = { new = function() return {} end },
}
for key, value in r do env[key] = value end
modules.Config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env, injectGlobals = true })()
modules.MonsterMath = luau.load(fs.readFile("src/shared/MonsterMath.luau"), { environment = env, injectGlobals = true })()
modules.GuiTheme = {
	ButtonFeedback = function() end,
	ModalShrink = function() return 1 end, -- the real shrink is a presentation scale; geometry checks run at 1
	Backdrop = function() end,
	Atlas = { Image = "rbxassetid://116704436062887", CellSize = r.Vector2.new(360, 296.75) },
	IconRects = { Gift = r.Vector2.new(1, 0) },
}
-- Artwork is a renderer boundary; the real controller still builds all native
-- controls, labels and prize geometry, and exercises every reward interaction.
modules.CartoonUI = {
	Icon = function(parent, key, size)
		local icon = r.Instance.new("ImageLabel")
		icon.Name, icon.BackgroundTransparency = key, 1
		icon.Image, icon.Size, icon.Parent = "rbxassetid://123", r.UDim2.fromOffset(size, size), parent
		return icon
	end,
	ApplyBackdrop = function(parent)
		local art = r.Instance.new("ImageLabel")
		art.Name, art.Parent = "CartoonBackdrop", parent
		return art
	end,
}
local module = luau.load(fs.readFile("src/client/RewardsArcade.luau"), { environment = env, injectGlobals = true })()
local gui = r.Instance.new("ScreenGui")
local scale = r.Instance.new("UIScale"); scale.Scale, scale.Parent = 0.6, gui
local panel = r.Instance.new("Frame"); panel.Parent, panel.Visible = gui, true
local close = r.Instance.new("TextButton"); close.Name, close.Parent = "CloseButton", panel
local state = { SpinReadyIn = 0 }
local spins = 0
local controller = module.Mount(panel, {
	GetState = function() return state end,
	Spin = function() spins += 1 end,
})
local root = panel.RewardsArcade
local content = root.RewardContent
local arcade = content.SpinArcade
local spinButton = arcade.SpinInfo.FreeSpin
check(content:FindFirstChild("DailyRewards") == nil, "The daily streak panel is gone; only the spin wheel remains")
local disc = arcade.WheelMount.PrizeDisc
local function rect(item, width, height)
	local w, h = item.Size.X.Scale * width + item.Size.X.Offset, item.Size.Y.Scale * height + item.Size.Y.Offset
	return { x = item.Position.X.Scale * width + item.Position.X.Offset - item.AnchorPoint.X * w,
		y = item.Position.Y.Scale * height + item.Position.Y.Offset - item.AnchorPoint.Y * h, w = w, h = h }
end
for _, viewport in { r.Vector2.new(320, 568), r.Vector2.new(480, 320), r.Vector2.new(568, 320), r.Vector2.new(1280, 720), r.Vector2.new(1914, 824), r.Vector2.new(1606, 686), r.Vector2.new(1310, 720) } do
	camera.ViewportSize = viewport; event(camera, "ViewportSize"):Fire()
	local width, height = panel.Size.X.Offset, panel.Size.Y.Offset
	check(width <= viewport.X - 24 and height <= viewport.Y - 60, "Panel fits available inset viewport")
	check(math.abs(scale.Scale * panel.NativeRewardsScale.Scale - 1) < 0.00001, "Parent scale is cancelled for native touch targets")
	check(content.Position.Y.Offset >= 78 and content.Position.Y.Offset + content.Size.Y.Offset <= height, "Content fits below fixed header")
	local heading, gift = root.Header.Heading, root.Header.GiftArt
	check(not gift.Visible or gift.Position.X.Offset + gift.Size.X.Offset <= heading.Position.X.Offset,
		"Reward header illustration and heading never overlap")
	check(arcade.Position.Y.Offset + arcade.Size.Y.Offset <= content.CanvasSize.Y.Offset, "Spin region reachable through scroll canvas")
	if viewport.X >= 1100 and viewport.Y >= 600 then
		check(content.CanvasSize.Y.Offset <= content.Size.Y.Offset, "Desktop shows the full wheel without scrolling")
		local wheel = arcade.WheelMount
		check(arcade.Position.Y.Offset + wheel.Position.Y.Offset + wheel.Size.Y.Offset <= content.Size.Y.Offset, "Complete desktop wheel is visible on first open")
		check(arcade.Position.Y.Offset + arcade.SpinInfo.Position.Y.Offset + spinButton.Position.Y.Offset + spinButton.Size.Y.Offset <= content.Size.Y.Offset, "Desktop free spin action is visible on first open")
	end
	for _, item in { close, spinButton } do
		check(item.Size.X.Offset >= 44 and item.Size.Y.Offset >= 44, "Every action retains native 44px target")
	end
	for _, region in { arcade.SpinInfo, arcade } do
		for _, child in region:GetChildren() do
			if child:IsA("GuiObject") then
				local box = rect(child, region.Size.X.Offset, region.Size.Y.Offset)
				check(box.x >= 0 and box.y >= 0 and box.x + box.w <= region.Size.X.Offset + 0.01 and box.y + box.h <= region.Size.Y.Offset + 0.01, "Reward summary / action fits card: " .. child.Name)
			end
		end
	end
end
check(panel.ZIndex == 30, "Rewards modal appears above sibling HUD elements")
-- كل جايزة نوع واحد بس (Coins أو Candy أو Egg) والأوزان كلها موجبة
local totalWeight = 0
for _, prize in modules.Config.Spin.Prizes do
	local kinds = (if prize.Egg then 1 else 0) + (if prize.Candy then 1 else 0) + (if prize.Coins then 1 else 0)
	check(kinds == 1 and prize.Weight > 0, "Prize " .. prize.Name .. " is exactly one of egg, candy or coins")
	check(not prize.Egg or modules.Config.Eggs[prize.Egg] ~= nil, "Egg prize points at a real egg")
	totalWeight += prize.Weight
end
check(totalWeight > 0, "Spin odds have positive total weight")
state.SpinReadyIn = 59
controller:Refresh(state)
check(not spinButton.Active, "Cooldown disables the spin request")
check(not spinButton:FindFirstChildOfClass("UIGradient").Enabled, "Unavailable free spin has no active purchase sheen")
spinButton.Activated:Fire()
check(spins == 0, "Disabled spin cannot request a reward even if Activated fires")
state.SpinReadyIn = 0; controller:Refresh(state)
check(spinButton:FindFirstChildOfClass("UIGradient").Enabled, "Ready free spin restores its action sheen")
spinButton.Activated:Fire(); spinButton.Activated:Fire()
check(spins == 1, "Pending spin sends exactly one request")
for index, prize in modules.Config.Spin.Prizes do
	controller:ShowSpinResult(index)
	local tween = tweens[#tweens]
	local final = tween.Properties.Rotation % 360
	check(math.abs((final + (index - 1) * 360 / #modules.Config.Spin.Prizes) % 360) < 0.001, "Server prize " .. index .. " lands at pointer")
	check(disc["Prize" .. index].PrizeName.Text == prize.Name, "Wheel label uses exact configured prize")
	panel.Visible = false; event(panel, "Visible"):Fire()
	check(tween.Cancelled and arcade.SpinResult.Text == "Prize: " .. prize.Name, "Hiding cancels animation while preserving selected result")
	panel.Visible = true; event(panel, "Visible"):Fire()
end
local before = #tweens
controller:ShowSpinResult(0); controller:ShowSpinResult(1.5); controller:ShowSpinResult(999)
check(#tweens == before, "Invalid server indices cannot animate or access out-of-range prizes")
local world = disc.RadialPrizeWedges:FindFirstChildOfClass("WorldModel")
check(world ~= nil and #world:GetChildren() >= 120, "Actual radial wedges render each sector, rather than rectangular prize chips")
local colors = {}
for _, part in world:GetChildren() do
	check(part:IsA("WedgePart") and part.Anchored and not part.CanCollide and part.Size.Y > 0 and part.Size.Z > 0, "Wheel triangle is valid static visual geometry")
	colors[part.Color:ToHex()] = true
end
for _, prize in modules.Config.Spin.Prizes do check(colors[prize.Color:ToHex()], "Every configured prize has a colored sector") end
controller:Destroy()
for _, item in scheduled do item.Callback() end
check(gui:FindFirstChild("RewardsArcade", true) == nil and panel:FindFirstChild("NativeRewardsScale") == nil, "Destroy removes visuals and delayed callbacks remain safe")
print(string.format("PASS: %d Rewards Arcade geometry, state, request, and server-selected wheel checks", checks))
