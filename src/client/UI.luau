--!strict
-- بيبني كل الواجهة بالكود (مفيش حاجة محتاجة تتعمل بإيدك في StarterGui).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)

local COLORS = {
	Panel = Color3.fromRGB(30, 30, 45),
	PanelLight = Color3.fromRGB(48, 48, 70),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(190, 190, 210),
	Green = Color3.fromRGB(70, 200, 100),
	Blue = Color3.fromRGB(70, 140, 255),
	Red = Color3.fromRGB(230, 70, 70),
	Yellow = Color3.fromRGB(255, 200, 50),
	Orange = Color3.fromRGB(255, 140, 40),
	Pink = Color3.fromRGB(255, 100, 170),
	Gray = Color3.fromRGB(110, 110, 120),
}

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel }

export type UI = {
	Gui: ScreenGui,
	CoinsLabel: TextLabel,
	PendingLabel: TextLabel,
	ShopButton: TextButton,
	UpgradesButton: TextButton,
	ShopFrame: Frame,
	ShopScroll: ScrollingFrame,
	ShopContentBottom: number,
	EggButtons: { [string]: TextButton },
	UpgradesFrame: Frame,
	SlotsInfo: TextLabel,
	SlotsButton: TextButton,
	LockInfo: TextLabel,
	LockButton: TextButton,
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

local function stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
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
	stroke(b, Color3.new(0, 0, 0), 2)
	return b
end

local function panel(parent: Instance, name: string, size: UDim2, title: string, titleColor: Color3): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = size
	f.BackgroundColor3 = COLORS.Panel
	f.Visible = false
	f.Parent = parent
	corner(f, 16)
	stroke(f, titleColor, 3)

	local titleLabel = label(f, title, UDim2.new(1, -60, 0, 44), UDim2.fromOffset(16, 6), 30)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = titleColor

	local close = button(f, "X", COLORS.Red, UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8))
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
	local function rescale()
		local viewport = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 700), 0.55, 1.2)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	-- الفلوس فوق
	local coinsFrame = Instance.new("Frame")
	coinsFrame.AnchorPoint = Vector2.new(0.5, 0)
	coinsFrame.Position = UDim2.new(0.5, 0, 0, 8)
	coinsFrame.Size = UDim2.fromOffset(260, 64)
	coinsFrame.BackgroundColor3 = COLORS.Panel
	coinsFrame.BackgroundTransparency = 0.15
	coinsFrame.Parent = gui
	corner(coinsFrame, 14)
	stroke(coinsFrame, COLORS.Yellow, 3)
	local coinsLabel = label(coinsFrame, "💰 0", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 2), 32)
	coinsLabel.TextColor3 = COLORS.Yellow
	local pendingLabel = label(coinsFrame, "", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 40), 16)
	pendingLabel.TextColor3 = COLORS.SubText

	-- أزرار الشمال
	local shopButton = button(gui, "🥚\nShop", COLORS.Pink, UDim2.fromOffset(84, 84), UDim2.new(0, 12, 0.5, -92))
	shopButton.TextSize = 22
	local upgradesButton = button(gui, "⬆️\nUpgrades", COLORS.Blue, UDim2.fromOffset(84, 84), UDim2.new(0, 12, 0.5, 8))
	upgradesButton.TextSize = 18

	local panels: { Frame } = {}

	-- المتجر -------------------------------------------------------------------
	local shopFrame = panel(gui, "Shop", UDim2.fromOffset(700, 560), "🥚 Shop", COLORS.Pink)
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
	local eggButtons: { [string]: TextButton } = {}
	local sortedEggs = {}
	for _, eggType in Config.ShopEggs do
		local egg = Config.Eggs[eggType]
		if egg then
			table.insert(sortedEggs, { Type = eggType, Egg = egg })
		end
	end
	if #sortedEggs == 0 then
		local empty = label(shopScroll, "🥚 Eggs: coming soon...", UDim2.new(1, -40, 0, 60), UDim2.fromOffset(20, 10), 28)
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

	-- الترقيات ----------------------------------------------------------------------
	local upgradesFrame = panel(gui, "Upgrades", UDim2.fromOffset(460, 300), "⬆️ Upgrades", COLORS.Blue)
	table.insert(panels, upgradesFrame)

	local slotsInfo = label(upgradesFrame, "", UDim2.new(1, -32, 0, 50), UDim2.fromOffset(16, 60), 18)
	slotsInfo.TextXAlignment = Enum.TextXAlignment.Left
	local slotsButton = button(upgradesFrame, "", COLORS.Green, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 112))
	local lockInfo = label(upgradesFrame, "", UDim2.new(1, -32, 0, 50), UDim2.fromOffset(16, 166), 18)
	lockInfo.TextXAlignment = Enum.TextXAlignment.Left
	local lockButton = button(upgradesFrame, "", COLORS.Green, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 218))

	-- لوحة الوحش ------------------------------------------------------------------
	local monsterFrame, monsterName = panel(gui, "Monster", UDim2.fromOffset(440, 468), "", COLORS.Green)
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
	local accessoriesButton = button(monsterFrame, "👒 Accessories", COLORS.Blue, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 362))
	local sellButton = button(monsterFrame, "", COLORS.Red, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 412))

	-- الإشعارات --------------------------------------------------------------------
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.AnchorPoint = Vector2.new(0.5, 0)
	toasts.Position = UDim2.new(0.5, 0, 0, 84)
	toasts.Size = UDim2.fromOffset(560, 300)
	toasts.BackgroundTransparency = 1
	toasts.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toasts

	return {
		Gui = gui,
		CoinsLabel = coinsLabel,
		PendingLabel = pendingLabel,
		ShopButton = shopButton,
		UpgradesButton = upgradesButton,
		ShopFrame = shopFrame,
		ShopScroll = shopScroll,
		ShopContentBottom = if #sortedEggs > 0 then 316 else 80,
		EggButtons = eggButtons,
		UpgradesFrame = upgradesFrame,
		SlotsInfo = slotsInfo,
		SlotsButton = slotsButton,
		LockInfo = lockInfo,
		LockButton = lockButton,
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
