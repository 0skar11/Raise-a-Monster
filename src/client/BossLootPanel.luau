--!strict
-- The loot you won from the Pumpkin Titan: a centred panel with one card per drop (rarity-coloured, revealed one
-- after another), your damage / share / rank, and a Collect button. The server decides everything; this only draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)

local BossLootPanel = {}

local ORANGE = Color3.fromRGB(255, 150, 50)
local CREAM = Color3.fromRGB(255, 244, 222)
local CARD_W, CARD_H = 172, 214
local AUTO_CLOSE = 20

local current: CanvasGroup? = nil

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local created = TweenService:Create(object, info, goal)
	created:Play()
	return created
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextStrokeTransparency = 0.55
	l.Parent = parent
	return l
end

local function rarityColor(rarity: string): Color3
	local info = Config.Rarities[rarity]
	return if info then info.Color else Config.Rarities.Common.Color
end

local function rarityRank(rarity: string): number
	local info = Config.Rarities[rarity]
	return if info then info.Order else 1
end

local function buildCard(parent: Instance, drop: any, index: number): Frame
	local color = rarityColor(drop.Rarity)
	local rank = rarityRank(drop.Rarity)
	local card = Instance.new("Frame")
	card.Name = "Card" .. index
	card.LayoutOrder = index
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = Color3.fromRGB(40, 24, 62)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = parent
	corner(card, 14)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(40, 24, 62), 0.78), Color3.fromRGB(24, 14, 40))
	gradient.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = if rank >= 5 then 3 else 2
	stroke.Parent = card

	local pill = Instance.new("Frame")
	pill.Name = "RarityPill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 10)
	pill.Size = UDim2.fromOffset(104, 22)
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	pill.Parent = card
	corner(pill, 11)
	local pillText = label(pill, "Text", string.upper(drop.Rarity), 13, Color3.fromRGB(20, 10, 30), Enum.Font.GothamBlack)
	pillText.Size = UDim2.fromScale(1, 1)
	pillText.TextStrokeTransparency = 1

	local glow = Instance.new("Frame")
	glow.Name = "IconGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, 82)
	glow.Size = UDim2.fromOffset(86, 86)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.78
	glow.BorderSizePixel = 0
	glow.Parent = card
	corner(glow, 43)
	local icon = label(card, "Icon", drop.Icon, 56, Color3.new(1, 1, 1))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0, 82)
	icon.Size = UDim2.fromOffset(86, 86)
	icon.TextStrokeTransparency = 1
	icon.ZIndex = 2

	local name = label(card, "Name", drop.Name, 17, CREAM, Enum.Font.FredokaOne)
	name.Position = UDim2.fromOffset(8, 128)
	name.Size = UDim2.new(1, -16, 0, 42)
	local detail = label(card, "Detail", drop.Detail, 12, Color3.fromRGB(190, 176, 214), Enum.Font.Gotham)
	detail.TextStrokeTransparency = 1
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.Position = UDim2.fromOffset(10, 170)
	detail.Size = UDim2.new(1, -20, 0, 38)

	if rank >= 5 then
		-- legendary and above: a sweeping shine and a pulsing frame
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.Size = UDim2.fromScale(1, 1)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.82
		shine.BorderSizePixel = 0
		shine.ZIndex = 3
		shine.Parent = card
		local sweep = Instance.new("UIGradient")
		sweep.Rotation = 25
		sweep.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
		})
		sweep.Offset = Vector2.new(-1, 0)
		sweep.Parent = shine
		task.spawn(function()
			while card.Parent do
				sweep.Offset = Vector2.new(-1, 0)
				tween(sweep, 1.4, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
				task.wait(1.1)
			end
		end)
		task.spawn(function()
			while card.Parent do
				tween(stroke, 0.8, { Thickness = 5 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
				tween(stroke, 0.8, { Thickness = 2.5 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
			end
		end)
	end
	return card
end

local function close(panel: CanvasGroup, backdrop: Frame)
	if current ~= panel then
		return
	end
	current = nil
	tween(panel, 0.25, { Position = UDim2.new(0.5, 0, 0.56, 0), GroupTransparency = 1 })
	tween(backdrop, 0.25, { BackgroundTransparency = 1 })
	task.delay(0.3, function()
		backdrop:Destroy()
	end)
end

local function show(screen: ScreenGui, data: any)
	if current then
		local old = current
		current = nil
		if old.Parent then
			old.Parent:Destroy()
		end
	end
	local items: { any } = if type(data.Items) == "table" then data.Items else {}
	local share = if type(data.Share) == "number" then data.Share else 0
	local damage = if type(data.Damage) == "number" then data.Damage else 0

	local backdrop = Instance.new("Frame")
	backdrop.Name = "LootBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 3, 14)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	tween(backdrop, 0.3, { BackgroundTransparency = 0.45 })

	local panel = Instance.new("CanvasGroup")
	panel.Name = "LootPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.62, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	local cardsWide = math.max(1, #items)
	panel.Size = UDim2.fromOffset(math.max(420, cardsWide * (CARD_W + 12) + 56), 0)
	panel.BackgroundColor3 = Color3.fromRGB(28, 15, 44)
	panel.BorderSizePixel = 0
	panel.GroupTransparency = 1
	panel.Parent = backdrop
	current = panel
	corner(panel, 20)
	local panelGradient = Instance.new("UIGradient")
	panelGradient.Rotation = 90
	panelGradient.Color = ColorSequence.new(Color3.fromRGB(58, 30, 84), Color3.fromRGB(22, 11, 36))
	panelGradient.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 3
	stroke.Parent = panel
	local scale = Instance.new("UIScale")
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / (panel.Size.X.Offset + 40), viewport.Y / 560), 0.55, 1)
	scale.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 20), UDim.new(0, 28), UDim.new(0, 28)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local title = label(panel, "Title", "🎃  PUMPKIN TITAN LOOT  🎃", 30, Color3.fromRGB(255, 190, 90), Enum.Font.FredokaOne)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 38)
	title.TextWrapped = false
	title.TextScaled = true
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 30
	titleLimit.Parent = title

	local summaryText = string.format("You dealt <b>%s</b> damage  ·  <font color=\"#FFB347\">%.1f%%</font> of its HP", MonsterMath.FormatNumber(damage), share * 100)
	if type(data.Rank) == "number" and type(data.Fighters) == "number" then
		summaryText ..= string.format("  ·  Rank <b>#%d</b> of %d", data.Rank, data.Fighters)
	end
	local summary = label(panel, "Summary", summaryText, 16, Color3.fromRGB(226, 214, 244), Enum.Font.Gotham)
	summary.RichText = true
	summary.LayoutOrder = 2
	summary.Size = UDim2.new(1, 0, 0, 22)
	summary.TextWrapped = false
	summary.TextStrokeTransparency = 1

	local divider = Instance.new("Frame")
	divider.LayoutOrder = 3
	divider.Size = UDim2.new(0.8, 0, 0, 2)
	divider.BackgroundColor3 = ORANGE
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.Parent = panel

	local cardsRow = Instance.new("Frame")
	cardsRow.Name = "Cards"
	cardsRow.LayoutOrder = 4
	cardsRow.BackgroundTransparency = 1
	cardsRow.Size = UDim2.new(1, 0, 0, if #items > 0 then CARD_H + 8 else 96)
	cardsRow.Parent = panel
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 12)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = cardsRow

	local cards: { Frame } = {}
	if #items == 0 then
		local needed = if type(data.Needed) == "number" then data.Needed else Config.BossLoot.MinShare
		local empty = label(cardsRow, "Empty", string.format("💀  No loot this time.\nDeal at least %d%% of the boss's HP to earn a share!", math.floor(needed * 100 + 0.5)), 18, Color3.fromRGB(214, 202, 236), Enum.Font.GothamMedium)
		empty.Size = UDim2.new(1, 0, 1, 0)
		empty.TextWrapped = true
	else
		for index, drop in items do
			local card = buildCard(cardsRow, drop, index)
			card.Size = UDim2.fromOffset(0, 0) -- pops in below
			table.insert(cards, card)
		end
	end

	local collect = Instance.new("TextButton")
	collect.Name = "Collect"
	collect.LayoutOrder = 5
	collect.Size = UDim2.fromOffset(220, 46)
	collect.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
	collect.AutoButtonColor = true
	collect.Font = Enum.Font.FredokaOne
	collect.Text = "COLLECT"
	collect.TextSize = 24
	collect.TextColor3 = Color3.fromRGB(40, 16, 6)
	collect.Parent = panel
	corner(collect, 12)
	local collectGradient = Instance.new("UIGradient")
	collectGradient.Rotation = 90
	collectGradient.Color = ColorSequence.new(Color3.fromRGB(255, 196, 70), Color3.fromRGB(255, 120, 24))
	collectGradient.Parent = collect
	local hint = label(panel, "Hint", "Gear drops are under Owned in the shop · eggs wait in your Pets menu", 12, Color3.fromRGB(160, 146, 190), Enum.Font.Gotham)
	hint.LayoutOrder = 6
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.TextWrapped = false
	hint.TextStrokeTransparency = 1
	hint.Visible = #items > 0

	collect.Activated:Connect(function()
		close(panel, backdrop)
	end)

	-- reveal: the panel rises in, then each card pops open, the rarer the later
	tween(panel, 0.4, { Position = UDim2.new(0.5, 0, 0.5, 0), GroupTransparency = 0 }, Enum.EasingStyle.Back)
	for index, card in cards do
		task.delay(0.45 + (index - 1) * 0.5, function()
			if card.Parent then
				tween(card, 0.45, { Size = UDim2.fromOffset(CARD_W, CARD_H) }, Enum.EasingStyle.Back)
			end
		end)
	end
	task.delay(AUTO_CLOSE, function()
		if current == panel then
			close(panel, backdrop)
		end
	end)
end

function BossLootPanel.Start(remotes: { [string]: RemoteEvent }, playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "BossLootGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 90
	screen.Parent = playerGui
	remotes.BossLoot.OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			-- let the boss's death animation finish before the loot appears
			task.delay(0.4, show, screen, data)
		end
	end)
end

return BossLootPanel
