--!strict
-- بيبني كل الواجهة بالكود (مفيش حاجة محتاجة تتعمل بإيدك في StarterGui).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)

local GuiTheme = require(script.Parent.GuiTheme)
local COLORS = GuiTheme.Colors

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel }

export type UI = {
	Gui: ScreenGui,
	Hud: Frame,
	NavigationButtons: { [string]: TextButton },
	InventoryButton: TextButton,
	HomeButton: TextButton,
	TeleportShopButton: TextButton,
	TeleportArenaButton: TextButton,
	CoinsLabel: TextLabel,
	PendingLabel: TextLabel,
	ShopButton: TextButton,
	ShopFrame: Frame,
	GearFrame: Frame,
	EggShopFrame: Frame,
	GearScroll: ScrollingFrame,
	ShopScroll: ScrollingFrame,
	ShopContentBottom: number,
	EggButtons: { [string]: TextButton },
	MonsterFrame: Frame,
	MonsterName: TextLabel,
	MonsterInfo: TextLabel,
	XpBar: Bar,
	HungerBar: Bar,
	HappyBar: Bar,
	ProductionLabel: TextLabel,
	FeedButton: TextButton,
	PlayButton: TextButton,
	AccessoriesButton: TextButton,
	SellButton: TextButton,
	FollowButton: TextButton,
	Toasts: Frame,
	Panels: { Frame },
}

local UI = {}
UI.Colors = COLORS

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.TextColor3 = COLORS.Text
	l.TextSize = textSize or 20
	l.TextWrapped = true
	l.RichText = true
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.Text = text
	b.TextColor3 = COLORS.Text
	b.TextSize = 20
	b.TextWrapped = true
	b.AutoButtonColor = true
	b.RichText = true
	b.Parent = parent
	corner(b, 10)
	local border = stroke(b, COLORS.Yellow, 2)
	GuiTheme.Gloss(b)
	GuiTheme.ButtonFeedback(b, border)
	return b
end

local function panel(parent: Instance, name: string, size: UDim2, title: string, titleColor: Color3): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = size
	f.BackgroundColor3 = COLORS.Panel
	f.Active = true
	f.Visible = false
	f.Parent = parent
	-- Keep the Roblox hotbar from covering modal shop cards.
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		local modalOpen = false
		for _, child in parent:GetChildren() do
			if child:IsA("Frame") and child.AnchorPoint.Y == 0.5 and child.Visible then modalOpen = true; break end
		end
		pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not modalOpen) end)
	end)
	corner(f, 16)
	stroke(f, COLORS.Yellow, 3)
	GuiTheme.Gloss(f)

	local titleLabel = label(f, title, UDim2.new(1, -60, 0, 44), UDim2.fromOffset(16, 6), 30)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = titleColor

	local close = button(f, "X", COLORS.Panel, UDim2.fromOffset(44, 44), UDim2.new(1, -52, 0, 6))
	close.Name = "CloseButton"
	local closeCorner = close:FindFirstChildOfClass("UICorner")
	if closeCorner then closeCorner.CornerRadius = UDim.new(1, 0) end
	close.Activated:Connect(function()
		f.Visible = false
	end)
	return f, titleLabel
end

local function bar(parent: Instance, color: Color3, position: UDim2): Bar
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -32, 0, 26)
	frame.Position = position
	frame.BackgroundColor3 = COLORS.PanelLight
	frame.Parent = parent
	corner(frame, 8)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = color
	fill.Parent = frame
	corner(fill, 8)

	local text = label(frame, "", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 16)
	text.ZIndex = 2
	return { Frame = frame, Fill = fill, Label = text }
end

function UI.SetBar(b: Bar, fraction: number, text: string)
	b.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	b.Label.Text = text
end

function UI.Create(playerGui: PlayerGui): UI
	local gui = Instance.new("ScreenGui")
	gui.Name = "RaiseAMonsterUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local camera = workspace.CurrentCamera
	local resizeGear: (() -> ())? = nil
	local resizeHud: (() -> ())? = nil
	local function rescale()
		if not camera then return end
		local viewport = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 880, viewport.Y / 700), 0.32, 1.2)
		if resizeGear then resizeGear() end
		if resizeHud then resizeHud() end
	end
	local viewportConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		camera = workspace.CurrentCamera
		if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale) end
		rescale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	rescale()

	-- HUD controls cancel the legacy modal scale and retain native touch targets.
	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.BackgroundTransparency = 1
	hud.ZIndex = 0
	hud.Parent = gui
	local hudScale = Instance.new("UIScale")
	hudScale.Name = "NativeHudScale"
	hudScale.Parent = hud
	local navigation = Instance.new("ScrollingFrame")
	navigation.Name = "Navigation"
	navigation.BackgroundTransparency = 1
	navigation.BorderSizePixel = 0
	navigation.ScrollBarImageColor3 = COLORS.Yellow
	navigation.ScrollingDirection = Enum.ScrollingDirection.Y
	navigation.ZIndex = 0
	navigation.Parent = hud
	local navigationButtons: { [string]: TextButton } = {}
	local navigationOrder = { "Shop", "Rewards", "Trade", "Arena", "Inventory" }
	local navigationIcons = { "Shop", "Gift", "Friends", "Trophy", "Pets" }
	for index, name in navigationOrder do
		local item = button(navigation, name, COLORS.Panel, UDim2.fromOffset(280, 72), UDim2.fromOffset(4, (index - 1) * 84 + 6))
		item.Name = name .. "Button"
		item.ZIndex = 0
		GuiTheme.DecoratePill(item, navigationIcons[index])
		navigationButtons[name] = item
	end
	for index, name in navigationOrder do
		local item = navigationButtons[name]
		item.NextSelectionUp = navigationButtons[navigationOrder[if index > 1 then index - 1 else #navigationOrder]]
		item.NextSelectionDown = navigationButtons[navigationOrder[if index < #navigationOrder then index + 1 else 1]]
	end

	-- Keep quick travel compact at the top and place the wallet with the left HUD.
	local walletTravel = Instance.new("Frame")
	walletTravel.Name = "WalletTravel"
	walletTravel.AnchorPoint = Vector2.new(0.5, 0)
	walletTravel.Position = UDim2.new(0.5, 0, 0, 8)
	walletTravel.BackgroundTransparency = 1
	walletTravel.ZIndex = 0
	walletTravel.Parent = hud
	local coinsFrame = Instance.new("Frame")
	coinsFrame.Name = "Wallet"
	coinsFrame.Position = UDim2.fromOffset(0, 0)
	coinsFrame.Size = UDim2.fromOffset(200, 46)
	coinsFrame.BackgroundColor3 = COLORS.Panel
	coinsFrame.BackgroundTransparency = 0
	GuiTheme.Gloss(coinsFrame)
	coinsFrame.ZIndex = 0
	coinsFrame.AnchorPoint = Vector2.new(0, 1)
	coinsFrame.Parent = hud
	corner(coinsFrame, 14)
	stroke(coinsFrame, COLORS.Yellow, 2)
	GuiTheme.Icon(coinsFrame, "Coins", UDim2.fromOffset(38, 38), UDim2.fromOffset(4, 4))
	local coinsLabel = label(coinsFrame, "0", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(44, 1), 24)
	-- التحديث الأصلي بيضيف إيموجي العملة؛ الأيقونة المرسومة موجودة جنب الرقم.
	coinsLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local text = coinsLabel.Text:gsub("^💰%s*", "")
		if text ~= coinsLabel.Text then coinsLabel.Text = text end
	end)
	coinsLabel.TextColor3 = COLORS.Yellow
	local pendingLabel = label(coinsFrame, "", UDim2.new(1, -48, 0, 16), UDim2.fromOffset(44, 27), 13)
	pendingLabel.TextColor3 = COLORS.SubText

	local shopButton = navigationButtons.Shop
	local homeButton = button(walletTravel, "Home", COLORS.Panel, UDim2.fromOffset(90, 34), UDim2.fromOffset(208, 6))
	homeButton.Name = "HomeButton"
	homeButton.ZIndex = 0
	homeButton.TextSize = 16
	local teleportShopButton = button(walletTravel, "To Shop", COLORS.Panel, UDim2.fromOffset(90, 34), UDim2.fromOffset(306, 6))
	teleportShopButton.TextSize = 16
	local teleportArenaButton = button(walletTravel, "To Arena", COLORS.Panel, UDim2.fromOffset(90, 34), UDim2.fromOffset(404, 6))
	teleportArenaButton.Name = "TeleportArenaButton"
	teleportArenaButton.ZIndex = 0
	teleportArenaButton.TextSize = 16
	teleportShopButton.Name = "TeleportShopButton"
	teleportShopButton.ZIndex = 0
	resizeHud = function()
		if not camera then return end
		local topLeft, bottomRight = Vector2.zero, Vector2.zero
		pcall(function() topLeft, bottomRight = GuiService:GetGuiInset() end)
		local viewport = camera.ViewportSize - topLeft - bottomRight
		hudScale.Scale = 1 / uiScale.Scale
		hud.Size = UDim2.fromOffset(viewport.X, viewport.Y)
		local stacked = viewport.X < 520
		if stacked then
			local groupWidth = math.min(288, math.max(1, viewport.X - 24))
			local homeWidth = math.floor((groupWidth - 12) / 3)
			walletTravel.Size = UDim2.fromOffset(groupWidth, 40)
			homeButton.Size = UDim2.fromOffset(homeWidth, 34)
			homeButton.Position = UDim2.fromOffset(0, 3)
			teleportShopButton.Size = UDim2.fromOffset(homeWidth, 34)
			teleportShopButton.Position = UDim2.fromOffset(homeWidth + 6, 3)
			teleportArenaButton.Size = UDim2.fromOffset(groupWidth - homeWidth * 2 - 12, 34)
			teleportArenaButton.Position = UDim2.fromOffset(homeWidth * 2 + 12, 3)
		else
			walletTravel.Size = UDim2.fromOffset(288, 46)
			homeButton.Size = UDim2.fromOffset(90, 34)
			homeButton.Position = UDim2.fromOffset(0, 6)
			teleportShopButton.Size = UDim2.fromOffset(90, 34)
			teleportShopButton.Position = UDim2.fromOffset(98, 6)
			teleportArenaButton.Size = UDim2.fromOffset(90, 34)
			teleportArenaButton.Position = UDim2.fromOffset(196, 6)
		end
		coinsLabel.TextSize = 24
		local height = if viewport.X < 600 then 44 else 48
		local gap = if viewport.Y >= 560 then 8 else 6
		local width = height
		local contentHeight = #navigationOrder * (height + gap) + 12
		local walletHeight = 46
		local walletGap = 8
		local top = math.max(8, viewport.Y - contentHeight - walletHeight - walletGap - 12)
		local available = math.max(44, viewport.Y - top - walletHeight - walletGap - 12)
		navigation.Position = UDim2.fromOffset(8, top)
		navigation.Size = UDim2.fromOffset(width + 12, math.min(contentHeight, available))
		navigation.CanvasSize = UDim2.fromOffset(0, contentHeight)
		navigation.ScrollBarThickness = if contentHeight > available then 3 else 0
		for index, name in navigationOrder do
			local item = navigationButtons[name]
			item.Size = UDim2.fromOffset(width, height)
			item.Position = UDim2.fromOffset(4, (index - 1) * (height + gap) + 6)
		end
		coinsFrame.Size = UDim2.fromOffset(math.min(200, math.max(1, viewport.X - 24)), walletHeight)
		coinsFrame.Position = UDim2.fromOffset(8, viewport.Y - 12)
	end

	local panels: { Frame } = {}

	-- المتجر -------------------------------------------------------------------
	local shopFrame = panel(gui, "Shop", UDim2.fromOffset(700, 560), "Shop", COLORS.Pink)
	table.insert(panels, shopFrame)
	local shopScroll = Instance.new("ScrollingFrame")
	shopScroll.Name = "Content"
	shopScroll.Position = UDim2.fromOffset(0, 56)
	shopScroll.Size = UDim2.new(1, 0, 1, -64)
	shopScroll.BackgroundTransparency = 1
	shopScroll.BorderSizePixel = 0
	shopScroll.ScrollBarThickness = 8
	shopScroll.CanvasSize = UDim2.fromOffset(0, 0)
	shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shopScroll.Parent = shopFrame
	local gearFrame, gearTitle = panel(gui, "GearShop", UDim2.fromOffset(860, 530), "SHOP", COLORS.Text)
	gearTitle.Visible = false
	local gearCorner = gearFrame:FindFirstChildOfClass("UICorner")
	if gearCorner then gearCorner.CornerRadius = UDim.new(0, 28) end
	local gearClose = gearFrame:FindFirstChild("CloseButton") :: TextButton
	gearClose.Position = UDim2.new(1, -48, 0, -14)
	gearClose.ZIndex = 4
	-- The shop uses native pixels and reflows its catalog on small screens.
	-- Other modal panels keep their existing scale and positioning.
	local gearScale = Instance.new("UIScale")
	gearScale.Name = "NativeShopScale"
	gearScale.Parent = gearFrame
	resizeGear = function()
		if not camera then return end
		local topLeft, bottomRight = Vector2.zero, Vector2.zero
		pcall(function() topLeft, bottomRight = GuiService:GetGuiInset() end)
		local viewport = camera.ViewportSize - topLeft - bottomRight
		gearScale.Scale = 1 / uiScale.Scale
		gearFrame.Size = UDim2.fromOffset(math.min(860, math.max(1, viewport.X - 16)), math.min(530, math.max(1, viewport.Y - 16)))
		local compact = gearFrame.Size.X.Offset < 700 or gearFrame.Size.Y.Offset < 440
		gearTitle.Visible = compact
		gearTitle.TextSize = 24
		gearClose.Position = if compact then UDim2.new(1, -52, 0, 6) else UDim2.new(1, -48, 0, -14)
		if viewport.X >= 1100 then
			gearFrame.AnchorPoint = Vector2.new(1, 0.5)
			gearFrame.Position = UDim2.new(1, -16 / uiScale.Scale, 0.5, 0)
		else
			gearFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			gearFrame.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	rescale()
	table.insert(panels, gearFrame)
	local gearScroll = shopScroll:Clone()
	gearScroll.Position = UDim2.fromOffset(16, 122)
	gearScroll.Size = UDim2.new(1, -224, 1, -138)
	gearScroll.ScrollBarImageColor3 = COLORS.Yellow
	gearScroll.BackgroundColor3 = Color3.fromRGB(22, 25, 65)
	gearScroll.BackgroundTransparency = 0
	corner(gearScroll, 16)
	gearScroll.Parent = gearFrame
	local eggButtons: { [string]: TextButton } = {}
	local sortedEggs = {}
	for _, eggType in Config.ShopEggs do
		local egg = Config.Eggs[eggType]
		if egg then
			table.insert(sortedEggs, { Type = eggType, Egg = egg })
		end
	end
	if #sortedEggs == 0 then
		local empty = label(shopScroll, "Permanent perks and temporary boosts", UDim2.new(1, -40, 0, 60), UDim2.fromOffset(20, 10), 20)
		empty.TextColor3 = COLORS.SubText
	end
	for i, entry in sortedEggs do
		local egg = entry.Egg
		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(196, 300)
		card.Position = UDim2.fromOffset(16 + (i - 1) * 206, 4)
		card.BackgroundColor3 = COLORS.PanelLight
		card.Parent = shopScroll
		corner(card, 12)
		stroke(card, egg.Color, 2)

		local eggIcon = Instance.new("Frame")
		eggIcon.Size = UDim2.fromOffset(56, 72)
		eggIcon.Position = UDim2.new(0.5, -28, 0, 10)
		eggIcon.BackgroundColor3 = egg.Color
		eggIcon.Parent = card
		corner(eggIcon, 36)
		stroke(eggIcon, Color3.new(0, 0, 0), 2)

		label(card, egg.DisplayName, UDim2.new(1, -10, 0, 28), UDim2.fromOffset(5, 86), 22)

		-- نسب الوحوش في البيضة
		local total = 0
		for _, weight in egg.Weights do
			total += weight
		end
		local odds = {}
		for speciesName, weight in egg.Weights do
			table.insert(odds, { Name = speciesName, Chance = weight / total })
		end
		table.sort(odds, function(a, b)
			return a.Chance > b.Chance
		end)
		local lines = {}
		for _, odd in odds do
			local species = Config.Species[odd.Name]
			local rarity = Config.Rarities[species.Rarity]
			table.insert(
				lines,
				string.format(
					'<font color="#%s">%s</font> %d%%',
					rarity.Color:ToHex(),
					species.DisplayName,
					math.floor(odd.Chance * 100 + 0.5)
				)
			)
		end
		local oddsLabel = label(card, table.concat(lines, "\n"), UDim2.new(1, -10, 0, 110), UDim2.fromOffset(5, 116), 16)
		oddsLabel.TextYAlignment = Enum.TextYAlignment.Top
		label(card, "⏳ " .. egg.HatchTime .. "s to hatch", UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 226), 15).TextColor3 =
			COLORS.SubText

		local buy = button(card, "💰 " .. MonsterMath.FormatNumber(egg.Cost), COLORS.Green, UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 250))
		eggButtons[entry.Type] = buy
	end

	-- لوحة الوحش ------------------------------------------------------------------
	local monsterFrame, monsterName = panel(gui, "Monster", UDim2.fromOffset(440, 516), "", COLORS.Green)
	table.insert(panels, monsterFrame)
	local monsterInfo = label(monsterFrame, "", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 52), 18)
	monsterInfo.TextXAlignment = Enum.TextXAlignment.Left
	monsterInfo.TextColor3 = COLORS.SubText

	label(monsterFrame, "XP", UDim2.fromOffset(100, 20), UDim2.fromOffset(16, 84), 16).TextXAlignment = Enum.TextXAlignment.Left
	local xpBar = bar(monsterFrame, COLORS.Blue, UDim2.fromOffset(16, 104))
	label(monsterFrame, "🍖 Hunger", UDim2.fromOffset(140, 20), UDim2.fromOffset(16, 138), 16).TextXAlignment =
		Enum.TextXAlignment.Left
	local hungerBar = bar(monsterFrame, COLORS.Orange, UDim2.fromOffset(16, 158))
	label(monsterFrame, "😄 Happiness", UDim2.fromOffset(160, 20), UDim2.fromOffset(16, 192), 16).TextXAlignment =
		Enum.TextXAlignment.Left
	local happyBar = bar(monsterFrame, COLORS.Pink, UDim2.fromOffset(16, 212))

	local productionLabel = label(monsterFrame, "", UDim2.new(1, -32, 0, 50), UDim2.fromOffset(16, 246), 18)
	productionLabel.TextColor3 = COLORS.Yellow

	local feedButton = button(monsterFrame, "", COLORS.Orange, UDim2.fromOffset(196, 48), UDim2.fromOffset(16, 304))
	local playButton = button(monsterFrame, "", COLORS.Pink, UDim2.fromOffset(196, 48), UDim2.fromOffset(228, 304))
	GuiTheme.DecorateButton(playButton, "Play")
	local accessoriesButton = button(monsterFrame, "👒 Accessories", COLORS.Blue, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 362))
	GuiTheme.DecorateButton(accessoriesButton, "Pets")
	local sellButton = button(monsterFrame, "", COLORS.Red, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 412))

	local followButton = button(monsterFrame, "Follow", COLORS.Blue, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 464))

	-- الإشعارات --------------------------------------------------------------------
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.AnchorPoint = Vector2.new(0.5, 0)
	toasts.Position = UDim2.new(0.5, 0, 0, 64)
	toasts.Size = UDim2.fromOffset(560, 300)
	toasts.BackgroundTransparency = 1
	toasts.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toasts

	rescale()
	return {
		Gui = gui,
		Hud = hud,
		NavigationButtons = navigationButtons,
		InventoryButton = navigationButtons.Inventory,
		HomeButton = homeButton,
		TeleportShopButton = teleportShopButton,
		TeleportArenaButton = teleportArenaButton,
		CoinsLabel = coinsLabel,
		PendingLabel = pendingLabel,
		ShopButton = shopButton,
		ShopFrame = gearFrame,
		EggShopFrame = shopFrame,
		GearFrame = gearFrame,
		GearScroll = gearScroll,
		ShopScroll = shopScroll,
		ShopContentBottom = if #sortedEggs > 0 then 316 else 80,
		EggButtons = eggButtons,
		MonsterFrame = monsterFrame,
		MonsterName = monsterName,
		MonsterInfo = monsterInfo,
		XpBar = xpBar,
		HungerBar = hungerBar,
		HappyBar = happyBar,
		ProductionLabel = productionLabel,
		FeedButton = feedButton,
		PlayButton = playButton,
		AccessoriesButton = accessoriesButton,
		SellButton = sellButton,
		FollowButton = followButton,
		Toasts = toasts,
		Panels = panels,
	}
end

-- أدوات البناء متاحة لباقي ملفات الواجهة
UI.Corner = corner
UI.Stroke = stroke
UI.Label = label
UI.Button = button
UI.Panel = panel
UI.Bar = bar
UI.DecorateButton = GuiTheme.DecorateButton
UI.Icon = GuiTheme.Icon

-- Render the real weapon Tool locally; the shop does not depend on thumbnail uploads.
function UI.WeaponPreview(parent: GuiObject, templateName: string)
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if not template then return end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "WeaponPreview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -16, 0, 142)
	viewport.Position = UDim2.fromOffset(8, 6)
	viewport.Ambient = Color3.fromRGB(205, 211, 237)
	viewport.LightColor = Color3.fromRGB(255, 242, 216)
	viewport.LightDirection = Vector3.new(-1, -1, -2)
	viewport.Parent = parent
	local model = Instance.new("Model")
	model.Name = templateName
	local tool = template:Clone()
	for _, item in tool:GetDescendants() do
		if item:IsA("LuaSourceContainer") then item:Destroy() end
	end
	for _, item in tool:GetChildren() do item.Parent = model end
	tool:Destroy()
	model.Parent = viewport
	model:PivotTo(CFrame.Angles(0, 0, math.rad(-32)))
	local box, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local distance = math.max(size.X, size.Y, size.Z) * 2.05
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(0, 0, distance), box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Small 3D models of the speed gear for the shop cards (simplified versions of the in-game cosmetics).
function UI.GearPreview(parent: GuiObject, gearName: string)
	local gear = Config.SpeedAccessories[gearName]
	if not gear then return end
	local color = gear.Color
	local dark = Color3.fromRGB(29, 30, 45)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "GearPreview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -16, 0, 142)
	viewport.Position = UDim2.fromOffset(8, 6)
	viewport.Ambient = Color3.fromRGB(205, 211, 237)
	viewport.LightColor = Color3.fromRGB(255, 242, 216)
	viewport.LightDirection = Vector3.new(-1, -1, -2)
	viewport.Parent = parent
	local model = Instance.new("Model")
	model.Name = gearName
	model.Parent = viewport
	local function add(size: Vector3, cframe: CFrame, tint: Color3, material: Enum.Material?, shape: Enum.PartType?)
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = size
		part.CFrame = cframe
		part.Color = tint
		part.Material = material or Enum.Material.SmoothPlastic
		part.Shape = shape or Enum.PartType.Block
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end
	local function segment(a: Vector3, b: Vector3, width: number, tint: Color3, material: Enum.Material?)
		add(Vector3.new(width, width, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), tint, material)
	end
	if gearName == "SwiftSneakers" or gearName == "FlameBoots" or gearName == "IceSkates" or gearName == "LightningBoots" then
		local bootColor = if gearName == "FlameBoots" then Color3.fromRGB(89, 56, 39) elseif gearName == "IceSkates" then Color3.fromRGB(126, 224, 246) elseif gearName == "SwiftSneakers" then Color3.fromRGB(30, 73, 143) else dark
		for _, x in { -0.85, 0.85 } do
			add(Vector3.new(1.1, 0.2, 2.3), CFrame.new(x, 0, 0), color, Enum.Material.Neon)
			add(Vector3.new(1.05, 0.5, 1.7), CFrame.new(x, 0.35, -0.3), bootColor)
			add(Vector3.new(1.05, if gearName == "SwiftSneakers" then 0.7 else 1.2, 1.1), CFrame.new(x, if gearName == "SwiftSneakers" then 0.6 else 0.85, 0.25), bootColor)
			if gearName == "FlameBoots" then
				for i = 0, 2 do
					for _, side in { -1, 1 } do
						add(Vector3.new(0.16, 0.5 + i * 0.2, 0.25), CFrame.new(x + side * 0.58, 0.7 + i * 0.2, -0.5 + i * 0.5) * CFrame.Angles(0, 0, side * math.rad(-20)), if i % 2 == 0 then Color3.fromRGB(255, 157, 31) else color, Enum.Material.Neon)
					end
				end
			elseif gearName == "IceSkates" then
				add(Vector3.new(0.16, 0.15, 2.4), CFrame.new(x, -0.35, 0), Color3.fromRGB(200, 249, 255), Enum.Material.Metal)
				for _, z in { -0.8, 0.6 } do add(Vector3.new(0.22, 0.3, 0.22), CFrame.new(x, -0.18, z), Color3.fromRGB(129, 218, 244), Enum.Material.Ice) end
			elseif gearName == "LightningBoots" then
				local bolt = { Vector3.new(0.25, 1.5, -0.56), Vector3.new(-0.2, 1.15, -0.58), Vector3.new(0.18, 1.1, -0.6), Vector3.new(-0.24, 0.75, -0.6) }
				for i = 1, #bolt - 1 do segment(bolt[i] + Vector3.new(x, 0, 0.9), bolt[i + 1] + Vector3.new(x, 0, 0.9), 0.15, color, Enum.Material.Neon) end
			else
				for i = 0, 2 do add(Vector3.new(0.7, 0.08, 0.1), CFrame.new(x, 0.85 + i * 0.12, -0.3), color, Enum.Material.Neon) end
			end
		end
	elseif gearName == "VoidHoverboard" then
		add(Vector3.new(5, 0.3, 2.1), CFrame.new(0, 0, 0), dark, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			add(Vector3.new(0.8, 0.35, 1.7), CFrame.new(side * 2.55, 0.15, 0) * CFrame.Angles(0, 0, side * math.rad(18)), Color3.fromRGB(57, 35, 81), Enum.Material.Metal)
			add(Vector3.new(1.2, 0.1, 1.5), CFrame.new(side * 1.2, 0.24, 0), Color3.fromRGB(153, 74, 218), Enum.Material.Neon)
			add(Vector3.new(1.7, 0.14, 0.95), CFrame.new(side * 1.5, -0.24, 0), color, Enum.Material.Neon)
		end
		for i = 0, 15 do
			local a = i * math.pi / 8
			local b = a + math.pi / 8
			segment(Vector3.new(math.cos(a) * 2.9, -0.65, math.sin(a) * 1.5), Vector3.new(math.cos(b) * 2.9, -0.65, math.sin(b) * 1.5), 0.09, color, Enum.Material.Neon)
		end
	elseif gearName == "GoldenWings" then
		local deep, mid, light = Color3.fromRGB(196, 140, 36), Color3.fromRGB(230, 180, 64), Color3.fromRGB(250, 214, 112)
		add(Vector3.new(1.3, 1.7, 0.4), CFrame.new(0, 0.5, 0.2), Color3.fromRGB(176, 128, 34), Enum.Material.Metal)
		for _, side in { -1, 1 } do
			local p1, p2 = Vector3.new(side * 1.1, 1.65, 0.1), Vector3.new(side * 3.2, 1.8, 0.3)
			local function arm(t: number): Vector3
				return Vector3.zero:Lerp(p1, t):Lerp(p1:Lerp(p2, t), t)
			end
			local previous = arm(0)
			for i = 1, 5 do
				local nextPoint = arm(i / 5)
				segment(previous, nextPoint, 0.22 - i * 0.02, light, Enum.Material.Metal)
				previous = nextPoint
			end
			local rows = {
				{ count = 8, length = 2.5, width = 0.46, tint = light, drop = 0 },
				{ count = 7, length = 1.75, width = 0.42, tint = mid, drop = 0.16 },
				{ count = 6, length = 1.05, width = 0.38, tint = deep, drop = 0.3 },
			}
			for rowIndex, row in rows do
				for j = 0, row.count - 1 do
					local t = (j + 0.5) / row.count
					local base = arm(t) - Vector3.new(0, row.drop, 0.05 * rowIndex)
					local angle = math.rad(18 + 88 * t + rowIndex * 3)
					local direction = Vector3.new(side * math.sin(angle), -math.cos(angle), 0.1 * t).Unit
					local length = row.length * (0.5 + 0.5 * t)
					local center = base + direction * (length / 2)
					add(Vector3.new(row.width, 0.06, length), CFrame.lookAt(center, center + direction, Vector3.zAxis), row.tint:Lerp(deep, (1 - t) * 0.25), Enum.Material.Metal)
				end
			end
		end
	elseif gearName == "WindScarf" then
		add(Vector3.new(2.2, 0.45, 1.6), CFrame.new(0, 0.9, 0), color, Enum.Material.Fabric)
		for i = 0, 3 do
			add(Vector3.new(0.95, 0.2, 1.1), CFrame.new(0.6 + i * 0.5, 0.6 - i * 0.3, 0.2 + i * 0.7) * CFrame.Angles(math.rad(i * 8), math.rad(-i * 10), 0), color, Enum.Material.Fabric)
		end
	elseif gearName == "ShadowCloak" then
		for _, side in { -1, 1 } do
			add(Vector3.new(1.7, 0.4, 1.5), CFrame.new(side * 1, 1.5, 0) * CFrame.Angles(0, 0, side * math.rad(-13)), Color3.fromRGB(19, 14, 29), Enum.Material.Fabric)
			for panel = 0, 2 do
				local length = 3.6 - panel * 0.3
				add(Vector3.new(0.6, length, 0.22), CFrame.new(side * (0.35 + panel * 0.5), 1.4 - length / 2, 0.3 + panel * 0.12), if panel % 2 == 0 then Color3.fromRGB(23, 14, 37) else Color3.fromRGB(42, 22, 66), Enum.Material.Fabric)
				add(Vector3.new(0.08, length - 0.2, 0.24), CFrame.new(side * (0.62 + panel * 0.5), 1.4 - length / 2, 0.32 + panel * 0.12), color, Enum.Material.Fabric)
			end
			add(Vector3.new(0.35, 0.35, 0.35), CFrame.new(side * 0.75, 1.3, -0.7), Color3.fromRGB(135, 111, 176), Enum.Material.Metal, Enum.PartType.Ball)
		end
		for i = 0, 5 do
			local angle = i * math.pi / 3
			add(Vector3.new(0.2, 0.5, 0.12), CFrame.new(math.cos(angle) * 2.6, 0.3 + i % 3 * 0.5, math.sin(angle) * 1.2) * CFrame.Angles(0, angle, math.rad(35)), color, Enum.Material.Neon)
		end
	else
		add(Vector3.new(2, 2, 2), CFrame.new(), color, Enum.Material.Neon)
	end
	local box, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local distance = math.max(size.X, size.Y, size.Z) * 2.1
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(distance * 0.55, distance * 0.4, distance * 0.9), box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function UI.Open(ui: UI, frame: Frame)
	for _, other in ui.Panels do
		other.Visible = other == frame
	end
end

function UI.Toggle(ui: UI, frame: Frame)
	if frame.Visible then
		frame.Visible = false
	else
		UI.Open(ui, frame)
	end
end

local toastOrder = 0
function UI.Toast(ui: UI, text: string, kind: string?)
	local color = COLORS.PanelLight
	if kind == "success" then
		color = COLORS.Green
	elseif kind == "error" then
		color = COLORS.Red
	elseif kind == "warning" then
		color = COLORS.Orange
	elseif kind == "coins" then
		color = COLORS.Yellow
	end

	toastOrder += 1
	local toast = Instance.new("TextLabel")
	toast.LayoutOrder = toastOrder
	toast.Size = UDim2.fromOffset(540, 40)
	toast.BackgroundColor3 = color
	toast.BackgroundTransparency = 0.1
	toast.Font = Enum.Font.FredokaOne
	toast.TextSize = 20
	toast.TextColor3 = if kind == "coins" then Color3.new(0.1, 0.1, 0.1) else COLORS.Text
	toast.TextWrapped = true
	toast.Text = text
	toast.Parent = ui.Toasts
	corner(toast, 10)
	stroke(toast, Color3.new(0, 0, 0), 2)

	-- ما نخليش الإشعارات تتكوم
	local children = {}
	for _, child in ui.Toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(children, child)
		end
	end
	if #children > 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end

	task.delay(3.5, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

return UI
