--!strict
-- Halloween event client: event timers, the Pumpkin Merchant shop panel and the pumpkin hint arrow.
-- The server owns every rule; this module only displays state and sends item ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local HalloweenLogic = require(ReplicatedStorage.Shared.HalloweenLogic)
local CompactMoney = require(ReplicatedStorage.Shared.CompactMoney)

-- Plain digits up to 50k (25,000 reads better than 25K), compact above that.
local function formatCandy(value: number): string
	value = math.floor(value + 0.5)
	if math.abs(value) >= 50000 then
		return CompactMoney.Format(value)
	end
	local digits = tostring(math.abs(value))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	grouped = grouped:gsub("^,", "")
	return (if value < 0 then "-" else "") .. grouped
end
local UI = require(script.Parent.UI)

local settings = Config.Halloween
local COLORS = UI.Colors
local ARROWS = { "⬆", "↗", "➡", "↘", "⬇", "↙", "⬅", "↖" }
local BAND_TEXT = { "very close!", "getting warmer", "far away" }

local HalloweenUI = {}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function sortedItems(): { { Id: string, Item: Config.HalloweenItem } }
	local list = {}
	for id, item in settings.Items do
		table.insert(list, { Id = id, Item = item })
	end
	table.sort(list, function(a, b)
		return a.Item.Order < b.Item.Order
	end)
	return list
end

function HalloweenUI.Init(ui: UI.UI, remotes: { [string]: RemoteEvent })
	local player = Players.LocalPlayer
	local state: any = nil
	local stateAt = os.clock()
	local hint: any = nil
	local hintAt = 0

	-- Pumpkin hint ----------------------------------------------------------------------------------
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "PumpkinHint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.Position = UDim2.new(0.5, 0, 0, 60)
	hintLabel.Size = UDim2.fromOffset(330, 40)
	hintLabel.BackgroundColor3 = COLORS.Panel
	hintLabel.BackgroundTransparency = 0.15
	hintLabel.Font = Enum.Font.FredokaOne
	hintLabel.TextSize = 20
	hintLabel.TextColor3 = Color3.fromRGB(255, 190, 80)
	hintLabel.Visible = false
	hintLabel.Parent = ui.Gui
	UI.Corner(hintLabel, 10)
	UI.Stroke(hintLabel, Color3.fromRGB(255, 140, 40), 2)

	-- Shop panel -------------------------------------------------------------------------------------
	local PURPLE = Color3.fromRGB(176, 96, 255)
	local CANDY = Color3.fromRGB(255, 170, 60)
	local CATEGORIES = {
		{ Name = "Boosts", Icon = "⚡", Kinds = { Boost = true } },
		{ Name = "Cosmetics", Icon = "🎩", Kinds = { Hat = true, Trail = true, Aura = true, Title = true } },
		{ Name = "Eggs", Icon = "🥚", Kinds = { Egg = true } },
		{ Name = "Monsters", Icon = "👹", Kinds = { Monster = true } },
	}
	local ICONS = {
		Boost = "⚡", Hat = "🎩", Trail = "👻", Aura = "✨", Title = "🏷️", Egg = "🥚",
		HalloweenGhostSlime = "👻", HalloweenSkeletonImp = "💀", HalloweenPumpkinKing = "🎃",
	}
	local GREETINGS = {
		"Boo! Got any Candy for me?",
		"Hehehe… treats for tricks!",
		"Pick something spooky, traveler.",
		"The Pumpkin King is hungry for Candy…",
	}

	local frame, title = UI.Panel(ui.Gui, "HalloweenShop", UDim2.fromOffset(720, 540), "🎃 Pumpkin Merchant", PURPLE)
	table.insert(ui.Panels, frame)
	-- Draw the shop above the other HUD frames (the paw icon frame etc.) without touching them.
	frame.ZIndex = 100
	-- Other ScreenGuis (e.g. the golden-paw "inv" button) share DisplayOrder 0 and are created later, so they
	-- would draw over this panel. Lift our whole ScreenGui above them only while the shop is open
	-- (still below OfflineEarnings 30 / Settings 50).
	local baseDisplayOrder = ui.Gui.DisplayOrder
	frame.BackgroundColor3 = Color3.fromRGB(30, 18, 52)
	-- The panel's ornament (title band, brackets) follows the panel's ZIndex, so lift the title and close
	-- button above it.
	title.ZIndex = 102
	local closeButton = frame:FindFirstChild("CloseButton")
	if closeButton and closeButton:IsA("GuiObject") then
		closeButton.ZIndex = 102
	end

	-- Cobweb corners and a hanging spider (pure decoration, never active).
	local decor = Instance.new("Frame")
	decor.Name = "SpookyDecor"
	decor.BackgroundTransparency = 1
	decor.Size = UDim2.fromScale(1, 1)
	decor.Active = false
	decor.ClipsDescendants = true
	decor.ZIndex = 100
	decor.Parent = frame
	local function web(anchorX: number, anchorY: number)
		local root = Instance.new("Frame")
		root.Name = "Cobweb"
		root.BackgroundTransparency = 1
		root.AnchorPoint = Vector2.new(anchorX, anchorY)
		root.Position = UDim2.fromScale(anchorX, anchorY)
		root.Size = UDim2.fromOffset(120, 120)
		root.Active = false
		root.ZIndex = 100
		root.Parent = decor
		local function line(length: number, rotation: number, thickness: number)
			local l = Instance.new("Frame")
			l.BackgroundColor3 = Color3.fromRGB(235, 230, 255)
			l.BackgroundTransparency = 0.72
			l.BorderSizePixel = 0
			l.AnchorPoint = Vector2.new(0, 0.5)
			l.Position = UDim2.fromScale(anchorX, anchorY)
			l.Size = UDim2.fromOffset(length, thickness)
			l.Rotation = rotation
			l.Active = false
			l.ZIndex = 100
			l.Parent = root
			return l
		end
		-- spokes toward the panel centre, then three cross-threads
		local base = (if anchorX == 0 then 0 else 180) + (if anchorY == 0 then 0 else -0)
		local flip = if (anchorX == 0) == (anchorY == 0) then 1 else -1
		for _, angle in { 10, 35, 55, 80 } do
			line(112, base + angle * flip * (if anchorX == 0 then 1 else -1), 1.5)
		end
		for _, ring in { 30, 58, 88 } do
			for step = 1, 3 do
				local a1, a2 = math.rad(10 + (step - 1) * 25 + 5), math.rad(10 + step * 25 + 5)
				local mid = (a1 + a2) / 2
				local cx = (if anchorX == 0 then 1 else -1) * math.cos(mid) * ring
				local cy = (if anchorY == 0 then 1 else -1) * math.sin(mid) * ring
				local seg = Instance.new("Frame")
				seg.BackgroundColor3 = Color3.fromRGB(235, 230, 255)
				seg.BackgroundTransparency = 0.78
				seg.BorderSizePixel = 0
				seg.AnchorPoint = Vector2.new(0.5, 0.5)
				seg.Position = UDim2.new(anchorX, cx, anchorY, cy)
				seg.Size = UDim2.fromOffset(ring * 0.46, 1.5)
				seg.Rotation = math.deg(mid) * (if (anchorX == 0) == (anchorY == 0) then 1 else -1) + 90
				seg.Active = false
				seg.ZIndex = 100
				seg.Parent = root
			end
		end
	end
	web(0, 1)
	web(1, 1)

	local thread = Instance.new("Frame")
	thread.Name = "SpiderThread"
	thread.BackgroundColor3 = Color3.fromRGB(235, 230, 255)
	thread.BackgroundTransparency = 0.35
	thread.BorderSizePixel = 0
	thread.AnchorPoint = Vector2.new(0.5, 0)
	thread.Position = UDim2.new(1, -118, 0, 0)
	thread.Size = UDim2.fromOffset(2, 58)
	thread.Active = false
	thread.ZIndex = 101
	thread.Parent = frame
	local spider = Instance.new("TextLabel")
	spider.Name = "Spider"
	spider.BackgroundTransparency = 1
	spider.AnchorPoint = Vector2.new(0.5, 0)
	spider.Position = UDim2.fromScale(0.5, 1)
	spider.Size = UDim2.fromOffset(34, 30)
	spider.Text = "🕷️"
	spider.TextSize = 26
	spider.Font = Enum.Font.GothamBold
	spider.Active = false
	spider.ZIndex = 101
	spider.Parent = thread
	local spiderTween: Tween? = nil
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		ui.Gui.DisplayOrder = if frame.Visible then math.max(baseDisplayOrder, 10) else baseDisplayOrder
		if spiderTween then
			spiderTween:Cancel()
			spiderTween = nil
		end
		if frame.Visible then
			thread.Size = UDim2.fromOffset(2, 40)
			spiderTween = game:GetService("TweenService"):Create(thread, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromOffset(2, 66) })
			spiderTween:Play()
		end
	end)

	-- Merchant header: portrait, speech bubble, Candy balance.
	local header = Instance.new("Frame")
	header.Name = "MerchantHeader"
	header.Position = UDim2.fromOffset(14, 72)
	header.Size = UDim2.new(1, -28, 0, 88)
	header.BackgroundColor3 = Color3.fromRGB(45, 26, 78)
	header.Parent = frame
	UI.Corner(header, 8)
	UI.Stroke(header, PURPLE, 2)
	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.fromOffset(6, 6)
	portrait.Size = UDim2.fromOffset(76, 76)
	portrait.BackgroundColor3 = Color3.fromRGB(26, 14, 44)
	portrait.Ambient = Color3.fromRGB(170, 140, 210)
	portrait.LightColor = Color3.fromRGB(255, 220, 170)
	portrait.Parent = header
	UI.Corner(portrait, 6)
	UI.Stroke(portrait, CANDY, 2)
	local portraitFallback = UI.Label(portrait, "🎃", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 40)
	local portraitBuilt = false
	local function buildPortrait()
		if portraitBuilt then
			return
		end
		local merchant = game:GetService("CollectionService"):GetTagged("HalloweenMerchant")[1]
		if not merchant or not merchant:IsA("Model") then
			return
		end
		local ok = pcall(function()
			local copy = merchant:Clone()
			for _, d in copy:GetDescendants() do
				if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
					d:Destroy()
				end
			end
			copy.Parent = portrait
			local head = copy:FindFirstChild("Head") :: BasePart?
			if not head then
				return
			end
			local camera = Instance.new("Camera")
			local forward = head.CFrame.LookVector
			camera.CFrame = CFrame.lookAt(head.Position + forward * 4.4 + Vector3.new(0, 0.4, 0), head.Position + Vector3.new(0, 0.1, 0))
			camera.FieldOfView = 38
			camera.Parent = portrait
			portrait.CurrentCamera = camera
			portraitFallback.Visible = false
			portraitBuilt = true
		end)
		if not ok then
			portraitFallback.Visible = true
		end
	end
	local speech = Instance.new("Frame")
	speech.Name = "Speech"
	speech.Position = UDim2.fromOffset(92, 10)
	speech.Size = UDim2.new(1, -300, 0, 68)
	speech.BackgroundColor3 = Color3.fromRGB(255, 248, 230)
	speech.Parent = header
	UI.Corner(speech, 10)
	UI.Stroke(speech, Color3.fromRGB(12, 16, 31), 2)
	local speechText = UI.Label(speech, GREETINGS[1], UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), 18)
	speechText.Name = "SpeechText"
	speechText.TextColor3 = Color3.fromRGB(60, 30, 20)
	speechText.TextXAlignment = Enum.TextXAlignment.Left
	local pointer = Instance.new("Frame")
	pointer.Name = "SpeechPointer"
	pointer.BackgroundColor3 = speech.BackgroundColor3
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.fromOffset(0, 34)
	pointer.Size = UDim2.fromOffset(14, 14)
	pointer.Rotation = 45
	pointer.BorderSizePixel = 0
	pointer.Parent = speech
	local candyPill = Instance.new("Frame")
	candyPill.Name = "CandyPill"
	candyPill.AnchorPoint = Vector2.new(1, 0.5)
	candyPill.Position = UDim2.new(1, -8, 0.5, 0)
	candyPill.Size = UDim2.fromOffset(190, 66)
	candyPill.BackgroundColor3 = Color3.fromRGB(60, 34, 20)
	candyPill.Parent = header
	UI.Corner(candyPill, 8)
	UI.Stroke(candyPill, CANDY, 3)
	local candyCaption = UI.Label(candyPill, "YOUR CANDY", UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 5), 13)
	candyCaption.TextColor3 = Color3.fromRGB(255, 205, 140)
	local balance = UI.Label(candyPill, "", UDim2.new(1, -12, 0, 34), UDim2.fromOffset(6, 24), 28)
	balance.Name = "Balance"
	balance.TextColor3 = CANDY
	balance.TextStrokeColor3 = Color3.fromRGB(12, 16, 31)
	balance.TextStrokeTransparency = 0.2
	local convertNote = UI.Label(frame, "", UDim2.new(1, -28, 0, 16), UDim2.fromOffset(14, 163), 13)
	convertNote.Name = "ConvertNote"
	convertNote.TextXAlignment = Enum.TextXAlignment.Left
	convertNote.TextColor3 = COLORS.SubText
	convertNote.TextTruncate = Enum.TextTruncate.AtEnd

	-- Category tabs
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(14, 184)
	tabBar.Size = UDim2.new(1, -28, 0, 36)
	tabBar.Parent = frame
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar
	local activeCategory = 1
	local tabs: { TextButton } = {}

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.Position = UDim2.fromOffset(12, 228)
	scroll.Size = UDim2.new(1, -24, 1, -240)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = PURPLE
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.CellSize = UDim2.new(1 / 3, -10, 0, 218)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingRight = UDim.new(0, 12)
	gridPadding.PaddingBottom = UDim.new(0, 6)
	gridPadding.Parent = scroll

	local GuiTheme = (require(script.Parent.GuiTheme) :: any)
	local cards: { [string]: { Frame: Frame, Desc: TextLabel, Button: TextButton, Tag: TextLabel } } = {}
	for index, entry in sortedItems() do
		local item = entry.Item
		local premium = item.Unique == true
		local card = Instance.new("Frame")
		card.Name = entry.Id
		card.LayoutOrder = index
		card.BackgroundColor3 = if premium then Color3.fromRGB(70, 36, 24) else COLORS.PanelLight
		card.Parent = scroll
		UI.Corner(card, 8)
		UI.Stroke(card, item.Color, if premium then 3 else 2)
		if GuiTheme.Card then
			GuiTheme.Card(card, item.Color)
		end
		local art = Instance.new("Frame")
		art.Name = "Art"
		art.Position = UDim2.fromOffset(10, 10)
		art.Size = UDim2.new(1, -20, 0, 72)
		art.BackgroundColor3 = item.Color:Lerp(Color3.fromRGB(20, 12, 36), 0.78)
		art.Parent = card
		UI.Corner(art, 6)
		local artGradient = Instance.new("UIGradient")
		artGradient.Rotation = 90
		artGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 175))
		artGradient.Parent = art
		local icon = UI.Label(art, ICONS[item.Species or ""] or ICONS[item.Kind] or "🎃", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 44)
		icon.Name = "Icon"
		local tag = UI.Label(card, "", UDim2.fromOffset(112, 18), UDim2.new(1, -118, 0, 14), 12)
		tag.Name = "Tag"
		tag.BackgroundColor3 = if premium then Color3.fromRGB(255, 170, 40) else Color3.fromRGB(80, 220, 110)
		tag.BackgroundTransparency = 0
		tag.TextColor3 = Color3.fromRGB(20, 12, 8)
		tag.Visible = premium
		tag.Text = if premium then "ONE PER PLAYER" else ""
		tag.ZIndex = 3
		UI.Corner(tag, 4)
		local name = UI.Label(card, item.Name, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 86), 19)
		name.TextColor3 = item.Color
		name.TextStrokeColor3 = Color3.fromRGB(12, 16, 31)
		name.TextStrokeTransparency = 0.35
		local desc = UI.Label(card, item.Description, UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 108), 13)
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextColor3 = COLORS.SubText
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		local buy = UI.Button(card, "Buy", COLORS.Green, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 1, -50))
		buy.TextSize = 18
		cards[entry.Id] = { Frame = card, Desc = desc, Button = buy, Tag = tag }
		buy.Activated:Connect(function()
			local item2 = settings.Items[entry.Id]
			local owned = state and state.Owned and state.Owned[entry.Id]
			if owned and (item2.Kind == "Hat" or item2.Kind == "Trail" or item2.Kind == "Aura" or item2.Kind == "Title") then
				local equipped = state.Equipped and state.Equipped[item2.Kind] == entry.Id
				remotes.HalloweenEquip:FireServer(entry.Id, not equipped)
			else
				remotes.HalloweenBuy:FireServer(entry.Id)
			end
		end)
	end

	local function applyCategory()
		local category = CATEGORIES[activeCategory]
		for id, card in cards do
			card.Frame.Visible = category.Kinds[settings.Items[id].Kind] == true
		end
		for index, tab in tabs do
			local on = index == activeCategory
			tab.BackgroundColor3 = if on then PURPLE else Color3.fromRGB(58, 40, 92)
			tab.TextColor3 = if on then Color3.new(1, 1, 1) else COLORS.SubText
		end
		scroll.CanvasPosition = Vector2.new(0, 0)
	end
	for index, category in CATEGORIES do
		local tab = UI.Button(tabBar, category.Icon .. "  " .. category.Name, Color3.fromRGB(58, 40, 92), UDim2.new(0.25, -8, 1, 0), UDim2.fromOffset(0, 0))
		tab.LayoutOrder = index
		tab.TextSize = 17
		tabs[index] = tab
		tab.Activated:Connect(function()
			activeCategory = index
			applyCategory()
		end)
	end
	applyCategory()

	local function refreshShop()
		if not state then
			return
		end
		balance.Text = "🍬 " .. formatCandy(state.Candy)
		convertNote.Text = string.format("Leftover Candy turns into %d coins each when the event ends", state.ConvertRate or settings.CandyToCoinRate)
		for id, card in cards do
			local item = settings.Items[id]
			local owned = state.Owned and state.Owned[id] == true
			local cosmetic = item.Kind == "Hat" or item.Kind == "Trail" or item.Kind == "Aura" or item.Kind == "Title"
			if cosmetic and owned then
				local equipped = state.Equipped and state.Equipped[item.Kind] == id
				card.Button.Text = if equipped then "Unequip" else "Equip"
				card.Button.BackgroundColor3 = if equipped then COLORS.Orange else COLORS.Blue
				card.Tag.Visible = true
				card.Tag.Text = if equipped then "EQUIPPED" else "OWNED"
				card.Tag.BackgroundColor3 = if equipped then Color3.fromRGB(80, 220, 110) else Color3.fromRGB(150, 160, 200)
			elseif item.Unique and owned then
				card.Button.Text = "Owned"
				card.Button.BackgroundColor3 = COLORS.Gray
				card.Tag.Visible = true
				card.Tag.Text = "YOURS!"
				card.Tag.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
			else
				local affordable = state.Candy >= item.Cost
				card.Button.Text = if affordable then "Buy  🍬 " .. formatCandy(item.Cost) else "Need  🍬 " .. formatCandy(item.Cost)
				card.Button.BackgroundColor3 = if affordable then COLORS.Green else COLORS.Gray
				card.Tag.Visible = item.Unique == true
				card.Tag.Text = if item.Unique then "ONE PER PLAYER" else ""
				card.Tag.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
			end
		end
	end

	-- The event timers live on the Studio-authored entrance board (Workspace.HalloweenWorld.EntranceBoard):
	-- every SurfaceGui tagged "HalloweenTimerBoard" has InvasionValue / HuntValue / BoostValue labels that this
	-- function keeps current (the client computes the countdowns locally between server pushes).
	local function setBoard(invasion: string, hunt: string, boost: string)
		for _, board in game:GetService("CollectionService"):GetTagged("HalloweenTimerBoard") do
			for name, value in { InvasionValue = invasion, HuntValue = hunt, BoostValue = boost } do
				local label = board:FindFirstChild(name, true)
				if label and label:IsA("TextLabel") then
					label.Text = value
				end
			end
		end
	end

	local function refreshPill()
		if not state or not state.Enabled then
			setBoard("--:--", "--:--", "")
			hintLabel.Visible = false
			return
		end
		local elapsed = os.clock() - stateAt
		local boost = (state.BoostLeft or 0) - elapsed
		local invasion = if (state.InvadersAlive or 0) > 0 then "👹 " .. state.InvadersAlive .. " Mothers!" else clock((state.NextInvasionIn or 0) - elapsed)
		local hunt = if (state.HuntRemaining or 0) > 0 then "🎃 " .. state.HuntRemaining .. " left" else clock((state.NextPumpkinsIn or 0) - elapsed)
		setBoard(invasion, hunt, if boost > 0 then "⚡ 2x cash " .. clock(boost) else "")
	end

	local function refreshHint()
		local current = hint
		if not current or not state or not state.Enabled or os.clock() - hintAt > (current.EndsIn or 0) + 2 then
			hintLabel.Visible = false
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			hintLabel.Visible = false
			return
		end
		-- sector 0 = world +X, counter-clockwise; show it relative to where the camera is looking
		local dx, dz = HalloweenLogic.SectorDirection(current.Sector)
		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector
		local forward = Vector2.new(look.X, look.Z)
		local side = Vector2.new(right.X, right.Z)
		if forward.Magnitude < 0.01 then
			forward = Vector2.new(0, -1)
			side = Vector2.new(1, 0)
		end
		forward, side = forward.Unit, side.Unit
		local target = Vector2.new(dx, dz)
		local angle = math.atan2(target:Dot(side), target:Dot(forward))
		local index = math.floor(angle / (math.pi / 4) + 0.5) % 8
		hintLabel.Text = string.format("%s Pumpkin %s · %d left", ARROWS[index + 1], BAND_TEXT[current.Band] or "", current.Remaining or 0)
		hintLabel.Visible = true
	end

	local function onState(newState: any)
		state = newState
		stateAt = os.clock()
		refreshShop()
		refreshPill()
	end

	remotes.HalloweenState.OnClientEvent:Connect(onState)
	remotes.HalloweenHint.OnClientEvent:Connect(function(newHint: any)
		hint = if type(newHint) == "table" then newHint else nil
		hintAt = os.clock()
		refreshHint()
	end)
	remotes.HalloweenOpenShop.OnClientEvent:Connect(function()
		UI.Open(ui, frame)
		buildPortrait()
		speechText.Text = GREETINGS[math.random(1, #GREETINGS)]
		refreshShop()
		remotes.HalloweenSync:FireServer()
	end)

	-- Timers tick locally; the hint arrow follows the camera; the shop closes when you walk away.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		refreshPill()
		refreshHint()
		if frame.Visible then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- the merchant is Studio-authored (Workspace.HalloweenWorld) and may have been moved: find him by tag
			local merchant = game:GetService("CollectionService"):GetTagged("HalloweenMerchant")[1]
			local anchor = merchant and (merchant:FindFirstChild("Torso") or merchant:FindFirstChild("HumanoidRootPart"))
			if not root or not anchor or not anchor:IsA("BasePart") or not root:IsA("BasePart")
				or (root.Position - anchor.Position).Magnitude > settings.Merchant.ShopDistance * 1.3 then
				frame.Visible = false
			end
		end
	end)
	title.TextSize = 28
	remotes.HalloweenSync:FireServer()
end

return HalloweenUI
