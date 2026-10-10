--!strict
-- واجهة الأنظمة الجديدة: تليبورت، الهدية اليومية، عجلة الحظ، الـ Gamepasses في المتجر،
-- الإكسسوارات، الألعاب الصغيرة، الـ Trading، الـ Arena، والإعلانات الكبيرة.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)

local COLORS = UI.Colors
local player = Players.LocalPlayer

local Features = {}

local ui: UI.UI
local remotes: { [string]: RemoteEvent }
local getState: () -> any
local getOpenMonster: () -> string?

-- عناصر بتتحدث مع كل StateUpdate
local statusLabel: TextLabel
local rewardsButton: TextButton
local dailyInfo: TextLabel
local dailyClaim: TextButton
local spinGo: TextButton
local passButtons: { [string]: TextButton } = {}
local speedAccessoryButtons: { [string]: TextButton } = {}
local weaponButtons: { [string]: TextButton } = {}
local accessoryRows: { [string]: { Row: Frame, Button: TextButton, Info: TextLabel } } = {}
local accessoriesFrame: Frame
local miniGameFrame: Frame

-- أدوات ------------------------------------------------------------------------------------

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

local function rarityHex(rarity: string): string
	local info = Config.Rarities[rarity]
	return if info then "#" .. info.Color:ToHex() else "#FFFFFF"
end

local function makeList(parent: Instance, size: UDim2, position: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = size
	scroll.Position = position
	scroll.BackgroundColor3 = COLORS.PanelLight
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent
	UI.Corner(scroll, 10)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = scroll
	return scroll
end

local function clearList(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function sortedMonsters(): { any }
	local state = getState()
	local list = {}
	if state then
		for _, monster in state.Monsters do
			if not monster.Carried then
				table.insert(list, monster)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Production > b.Production
	end)
	return list
end

local function monsterText(monster: any): string
	-- وحوشك جاية بـ DisplayName، وعرض اللاعب التاني في الـ Trade جاي بـ Name
	local name = monster.DisplayName or monster.Name or "?"
	return string.format('<font color="%s">%s</font>  Lv %d', rarityHex(monster.Rarity), name, monster.Level)
end

local function fillMonsters(scroll: ScrollingFrame, isSelected: (any) -> boolean, onClick: (any) -> ())
	clearList(scroll)
	for index, monster in sortedMonsters() do
		local entry = UI.Button(scroll, monsterText(monster), if isSelected(monster) then COLORS.Green else COLORS.Panel, UDim2.new(1, 0, 0, 38), UDim2.new())
		entry.LayoutOrder = index
		entry.TextSize = 17
		entry.Activated:Connect(function()
			onClick(monster)
		end)
	end
end

local function fillPlayers(scroll: ScrollingFrame, onClick: (Player) -> ())
	clearList(scroll)
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			count += 1
			local entry = UI.Button(scroll, other.DisplayName, COLORS.Panel, UDim2.new(1, 0, 0, 38), UDim2.new())
			entry.LayoutOrder = count
			entry.Activated:Connect(function()
				onClick(other)
			end)
		end
	end
	if count == 0 then
		local empty = UI.Label(scroll, "No other players in this server yet.", UDim2.new(1, 0, 0, 40), UDim2.new(), 16)
		empty.TextColor3 = COLORS.SubText
	end
end

local function newPanel(name: string, size: UDim2, title: string, color: Color3): Frame
	local frame = UI.Panel(ui.Gui, name, size, title, color)
	table.insert(ui.Panels, frame)
	return frame
end

-- إعلانات كبيرة -----------------------------------------------------------------------------

local banner: TextLabel
local bannerToken = 0
local function buildBanner()
	banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 132)
	banner.Size = UDim2.fromOffset(760, 64)
	banner.BackgroundColor3 = COLORS.Panel
	banner.BackgroundTransparency = 0.1
	banner.Font = Enum.Font.FredokaOne
	banner.TextSize = 24
	banner.TextWrapped = true
	banner.TextColor3 = COLORS.Yellow
	banner.Visible = false
	banner.ZIndex = 20
	banner.Parent = ui.Gui
	UI.Corner(banner, 14)
	UI.Stroke(banner, COLORS.Yellow, 3)
end

local function announce(text: string, color: Color3?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color or COLORS.Yellow
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color or COLORS.Yellow
	end
	banner.Visible = true
	task.delay(6, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

-- Popup (طلبات الـ Trade والـ Arena) ----------------------------------------------------------

local popup: Frame
local popupTitle: TextLabel
local popupBody: Frame
local popupToken = 0

local function buildPopup()
	popup = Instance.new("Frame")
	-- في النص تحت (اليمين بتغطيه لستة اللاعبين بتاعة Roblox)
	popup.AnchorPoint = Vector2.new(0.5, 1)
	popup.Position = UDim2.new(0.5, 0, 1, -206)
	popup.Size = UDim2.fromOffset(340, 300)
	popup.BackgroundColor3 = COLORS.Panel
	popup.Visible = false
	popup.ZIndex = 10
	popup.Parent = ui.Gui
	UI.Corner(popup, 14)
	UI.Stroke(popup, COLORS.Orange, 3)
	popupTitle = UI.Label(popup, "", UDim2.new(1, -20, 0, 54), UDim2.fromOffset(10, 6), 20)
	popupBody = Instance.new("Frame")
	popupBody.BackgroundTransparency = 1
	popupBody.Position = UDim2.fromOffset(10, 64)
	popupBody.Size = UDim2.new(1, -20, 1, -74)
	popupBody.Parent = popup
end

local function showPopup(title: string, timeout: number, build: (body: Frame, close: () -> ()) -> ())
	popupToken += 1
	local token = popupToken
	for _, child in popupBody:GetChildren() do
		child:Destroy()
	end
	popupTitle.Text = title
	local function close()
		if popupToken == token then
			popup.Visible = false
		end
	end
	build(popupBody, close)
	popup.Visible = true
	task.delay(timeout, close)
end

-- تليبورت وأزرار جانبية -----------------------------------------------------------------------

local function buildButtons()
	-- ZIndex 0 عشان أي لوحة تتفتح تبقى فوقهم. فوق خالص في النص، على جنبي الفلوس
	local home = UI.Button(ui.Gui, "🏠 Home", COLORS.Green, UDim2.fromOffset(150, 44), UDim2.new(0.5, -292, 0, 18))
	home.ZIndex = 0
	home.Activated:Connect(function()
		remotes.Teleport:FireServer("Home")
	end)
	local shop = UI.Button(ui.Gui, "🥚 To Shop", COLORS.Pink, UDim2.fromOffset(150, 44), UDim2.new(0.5, 142, 0, 18))
	shop.ZIndex = 0
	shop.Activated:Connect(function()
		remotes.Teleport:FireServer("Shop")
	end)

	-- الأزرار على الشمال شبكة عمودين (اليمين بتغطيه لستة اللاعبين بتاعة Roblox وبتاكل الضغطات)
	rewardsButton = UI.Button(ui.Gui, "🎁\nRewards", COLORS.Yellow, UDim2.fromOffset(84, 84), UDim2.new(0, 12, 0.5, -138))
	rewardsButton.TextSize = 18

	statusLabel = UI.Label(ui.Gui, "", UDim2.fromOffset(420, 26), UDim2.new(0.5, -210, 0, 76), 18)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.ZIndex = 0
end

-- المتجر: الإكسسوارات والأسلحة بعملات اللعبة، ثم الـ Gamepasses والـ Boosts -----------------

local function buildShopExtras()
	local y = ui.ShopContentBottom
	local function section(title: string)
		local header = UI.Label(ui.ShopScroll, title, UDim2.new(1, -32, 0, 34), UDim2.fromOffset(16, y), 24)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = COLORS.Yellow
		y += 40
	end
	local function card(index: number, perRow: number, name: string, description: string, price: number, color: Color3, onBuy: () -> (), currency: string?): TextButton
		local width = math.floor((640 - (perRow - 1) * 10) / perRow)
		local column = (index - 1) % perRow
		local row = math.floor((index - 1) / perRow)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(width, 156)
		frame.Position = UDim2.fromOffset(16 + column * (width + 10), y + row * 168)
		frame.BackgroundColor3 = COLORS.PanelLight
		frame.Parent = ui.ShopScroll
		UI.Corner(frame, 12)
		UI.Stroke(frame, color, 2)
		local title = UI.Label(frame, name, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(5, 6), 20)
		title.TextColor3 = color
		local desc = UI.Label(frame, description, UDim2.new(1, -10, 0, 60), UDim2.fromOffset(5, 38), 15)
		desc.TextColor3 = COLORS.SubText
		local buy = UI.Button(frame, (currency or "R$ ") .. price, COLORS.Green, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 106))
		buy.Activated:Connect(onBuy)
		return buy
	end

	section("🏃 Player Accessories · Coins")
	local speedAccessories = {}
	for name, accessory in Config.SpeedAccessories do
		table.insert(speedAccessories, { Name = name, Accessory = accessory })
	end
	table.sort(speedAccessories, function(a, b)
		return a.Accessory.Order < b.Accessory.Order
	end)
	for i, entry in speedAccessories do
		local accessory = entry.Accessory
		speedAccessoryButtons[entry.Name] = card(i, 4, accessory.Name, accessory.Description .. string.format(" · Speed +%d%% · HP +%d", math.floor((accessory.Multiplier - 1) * 100 + 0.5), accessory.HealthBonus), accessory.Price, accessory.Color, function()
			remotes.BuySpeedAccessory:FireServer(entry.Name)
		end, "💰 ")
	end
	y += math.ceil(#speedAccessories / 4) * 168

	section("⚔️ Weapons · Coins")
	local weapons = {}
	for name, stats in Config.WeaponStats do
		local pass = Config.Gamepasses[name]
		table.insert(weapons, { Name = name, Pass = pass })
	end
	table.sort(weapons, function(a, b)
		return a.Pass.Order < b.Pass.Order
	end)
	for i, entry in weapons do
		local price = Config.WeaponCoinPrices[entry.Name]
		if price then
			weaponButtons[entry.Name] = card(i, 4, entry.Pass.Name, entry.Pass.Description, price, COLORS.Red, function()
				remotes.BuyWeapon:FireServer(entry.Name)
			end, "💰 ")
		end
	end
	y += math.ceil(#weapons / 4) * 168

	section("⭐ Gamepasses · Robux")
	local passes = {}
	for name, pass in Config.Gamepasses do
		if not Config.WeaponStats[name] then
			table.insert(passes, { Name = name, Pass = pass })
		end
	end
	table.sort(passes, function(a, b)
		return a.Pass.Order < b.Pass.Order
	end)
	for i, entry in passes do
		passButtons[entry.Name] = card(i, #passes, entry.Pass.Name, entry.Pass.Description, entry.Pass.Price, COLORS.Yellow, function()
			remotes.BuyPass:FireServer(entry.Name)
		end)
	end
	y += 168

	section("⚡ Boosts")
	local products = {}
	for name, product in Config.Products do
		table.insert(products, { Name = name, Product = product })
	end
	table.sort(products, function(a, b)
		return a.Product.Order < b.Product.Order
	end)
	for i, entry in products do
		card(i, #products, entry.Product.Name, entry.Product.Description, entry.Product.Price, COLORS.Blue, function()
			remotes.BuyProduct:FireServer(entry.Name)
		end)
	end
	y += 168
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromOffset(1, 10)
	spacer.Position = UDim2.fromOffset(0, y)
	spacer.Parent = ui.ShopScroll
end

-- الهدية اليومية وعجلة الحظ في شباك واحد: اليومية على الشمال والعجلة على اليمين ----------------

local function buildRewards()
	local frame = newPanel("Rewards", UDim2.fromOffset(820, 470), "🎁 Rewards", COLORS.Yellow)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.82
	scale.Parent = frame
	rewardsButton.Activated:Connect(function()
		UI.Toggle(ui, frame)
	end)

	local dailyTitle = UI.Label(frame, "🎁 Daily Reward", UDim2.fromOffset(360, 30), UDim2.fromOffset(16, 60), 24)
	dailyTitle.TextColor3 = COLORS.Yellow
	dailyInfo = UI.Label(frame, "", UDim2.fromOffset(360, 110), UDim2.fromOffset(16, 110), 20)
	dailyClaim = UI.Button(frame, "Claim", COLORS.Green, UDim2.fromOffset(360, 50), UDim2.fromOffset(16, 404))
	dailyClaim.Activated:Connect(function()
		remotes.ClaimDaily:FireServer()
	end)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.fromOffset(2, 390)
	divider.Position = UDim2.fromOffset(392, 60)
	divider.BackgroundColor3 = COLORS.PanelLight
	divider.BorderSizePixel = 0
	divider.Parent = frame

	local spinTitle = UI.Label(frame, "🎡 Spin Wheel", UDim2.fromOffset(400, 30), UDim2.fromOffset(410, 60), 24)
	spinTitle.TextColor3 = COLORS.Orange
	local wheel = Instance.new("Frame")
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromOffset(610, 250)
	wheel.Size = UDim2.fromOffset(300, 300)
	wheel.BackgroundColor3 = COLORS.PanelLight
	wheel.Parent = frame
	UI.Corner(wheel, 150)
	UI.Stroke(wheel, COLORS.Orange, 4)
	local prizes = Config.Spin.Prizes
	local step = 360 / #prizes
	for i, prize in prizes do
		local angle = math.rad((i - 1) * step)
		local chip = UI.Label(wheel, prize.Name, UDim2.fromOffset(104, 40), UDim2.new(0.5, math.sin(angle) * 100 - 52, 0.5, -math.cos(angle) * 100 - 20), 16)
		chip.BackgroundTransparency = 0
		chip.BackgroundColor3 = prize.Color
		chip.TextColor3 = Color3.fromRGB(25, 25, 30)
		chip.Rotation = (i - 1) * step
		UI.Corner(chip, 10)
	end
	local pointer = UI.Label(frame, "▼", UDim2.fromOffset(40, 40), UDim2.fromOffset(590, 82), 34)
	pointer.TextColor3 = COLORS.Red
	pointer.ZIndex = 3
	spinGo = UI.Button(frame, "SPIN!", COLORS.Green, UDim2.fromOffset(392, 50), UDim2.fromOffset(412, 404))
	spinGo.Activated:Connect(function()
		remotes.Spin:FireServer()
	end)

	remotes.SpinResult.OnClientEvent:Connect(function(index: number)
		UI.Open(ui, frame)
		local current = wheel.Rotation % 360
		wheel.Rotation = current
		-- الجايزة رقم index لازم توقف تحت السهم اللي فوق
		local target = 360 * 5 - (index - 1) * step
		TweenService:Create(wheel, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = target }):Play()
	end)
end

-- الإكسسوارات -----------------------------------------------------------------------------------

local function buildAccessories()
	-- كل وحش بيظهرله القبعة والنضارة بتوعه هو بس
	accessoriesFrame = newPanel("Accessories", UDim2.fromOffset(500, 210), "👒 Accessories", COLORS.Blue)
	local list = makeList(accessoriesFrame, UDim2.new(1, -32, 1, -76), UDim2.fromOffset(16, 60))
	local sorted = {}
	for name, accessory in Config.Accessories do
		table.insert(sorted, { Name = name, Accessory = accessory })
	end
	table.sort(sorted, function(a, b)
		return a.Accessory.Order < b.Accessory.Order
	end)
	for index, entry in sorted do
		local accessory = entry.Accessory
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundColor3 = COLORS.Panel
		row.LayoutOrder = index
		row.Visible = false
		row.Parent = list
		UI.Corner(row, 10)
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(30, 30)
		swatch.Position = UDim2.fromOffset(10, 11)
		swatch.BackgroundColor3 = accessory.Color
		swatch.Parent = row
		UI.Corner(swatch, 8)
		local bonus = if accessory.Bonus > 0 then string.format(" · +%d%% coins", math.floor(accessory.Bonus * 100 + 0.5)) else ""
		local info = UI.Label(row, accessory.Name .. bonus, UDim2.new(1, -200, 1, 0), UDim2.fromOffset(50, 0), 17)
		info.TextXAlignment = Enum.TextXAlignment.Left
		local action = UI.Button(row, "", COLORS.Green, UDim2.fromOffset(130, 38), UDim2.new(1, -138, 0, 7))
		action.TextSize = 16
		action.Activated:Connect(function()
			local state = getState()
			local monsterId = getOpenMonster()
			if not state then
				return
			end
			if not state.Accessories[entry.Name] then
				remotes.BuyAccessory:FireServer(entry.Name, monsterId)
				return
			end
			if not monsterId then
				return
			end
			local monster = nil
			for _, m in state.Monsters do
				if m.Id == monsterId then
					monster = m
				end
			end
			if not monster then
				return
			end
			local wearing = monster[accessory.Slot] == entry.Name
			remotes.EquipAccessory:FireServer(monsterId, accessory.Slot, if wearing then nil else entry.Name)
		end)
		accessoryRows[entry.Name] = { Row = row, Button = action, Info = info }
	end
	ui.AccessoriesButton.Activated:Connect(function()
		UI.Open(ui, accessoriesFrame)
		Features.Refresh()
	end)
end

local function refreshAccessories(state: any)
	local monsterId = getOpenMonster()
	local monster = nil
	for _, m in state.Monsters do
		if m.Id == monsterId then
			monster = m
		end
	end
	for name, row in accessoryRows do
		local accessory = Config.Accessories[name]
		row.Row.Visible = monster ~= nil and monster.Species == accessory.Species
		if not state.Accessories[name] then
			row.Button.Text = "💰 " .. MonsterMath.FormatNumber(accessory.Cost)
			row.Button.BackgroundColor3 = if state.Coins >= accessory.Cost then COLORS.Green else COLORS.Gray
		elseif monster and monster[accessory.Slot] == name then
			row.Button.Text = "Take off"
			row.Button.BackgroundColor3 = COLORS.Red
		else
			row.Button.Text = "Wear"
			row.Button.BackgroundColor3 = COLORS.Blue
		end
	end
end

-- الألعاب الصغيرة ------------------------------------------------------------------------------

local function buildMiniGames()
	local chooser = newPanel("MiniGames", UDim2.fromOffset(420, 250), "🎮 Play a mini-game", COLORS.Pink)
	local catch = UI.Button(chooser, "⚾ Catch the Ball\nClick the balls!", COLORS.Blue, UDim2.fromOffset(186, 120), UDim2.fromOffset(16, 70))
	local run = UI.Button(chooser, "🏃 Run Together\nRun as far as you can!", COLORS.Orange, UDim2.fromOffset(186, 120), UDim2.fromOffset(218, 70))
	local function start(gameName: string)
		local monsterId = getOpenMonster()
		if monsterId then
			remotes.MiniGameStart:FireServer(monsterId, gameName)
		end
		chooser.Visible = false
	end
	catch.Activated:Connect(function()
		start("Catch")
	end)
	run.Activated:Connect(function()
		start("Run")
	end)
	-- زرار Play بقى بيفتح الألعاب
	ui.PlayButton.Activated:Connect(function()
		UI.Open(ui, chooser)
	end)

	-- الشاشة اللي اللعبة بتتلعب فيها
	miniGameFrame = Instance.new("Frame")
	miniGameFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	miniGameFrame.Position = UDim2.fromScale(0.5, 0.5)
	miniGameFrame.Size = UDim2.fromOffset(620, 420)
	miniGameFrame.BackgroundColor3 = COLORS.Panel
	miniGameFrame.BackgroundTransparency = 0.15
	miniGameFrame.Visible = false
	miniGameFrame.ZIndex = 5
	miniGameFrame.Parent = ui.Gui
	UI.Corner(miniGameFrame, 16)
	UI.Stroke(miniGameFrame, COLORS.Pink, 3)
	local header = UI.Label(miniGameFrame, "", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 6), 26)
	header.ZIndex = 6
	local ball = UI.Button(miniGameFrame, "⚾", COLORS.Yellow, UDim2.fromOffset(70, 70), UDim2.fromOffset(270, 200))
	ball.TextSize = 36
	ball.ZIndex = 6
	UI.Corner(ball, 35)

	local score = 0
	local playingCatch = false
	local runPanel = UI.Label(ui.Gui, "", UDim2.fromOffset(460, 46), UDim2.new(0.5, -230, 0, 104), 24)
	runPanel.BackgroundTransparency = 0.15
	runPanel.BackgroundColor3 = COLORS.Panel
	runPanel.Visible = false
	UI.Corner(runPanel, 12)

	ball.Activated:Connect(function()
		if not playingCatch then
			return
		end
		score += 1
		ball.Position = UDim2.fromOffset(math.random(20, 530), math.random(70, 330))
	end)

	remotes.MiniGameState.OnClientEvent:Connect(function(info: any)
		if info.Done then
			playingCatch = false
			miniGameFrame.Visible = false
			runPanel.Visible = false
			return
		end
		if info.Game == "Catch" and not playingCatch then
			playingCatch = true
			score = 0
			miniGameFrame.Visible = true
			ball.Visible = true
			ball.Position = UDim2.fromOffset(270, 200)
			local duration = info.TimeLeft :: number
			task.spawn(function()
				local started = os.clock()
				while playingCatch and os.clock() - started < duration do
					header.Text = string.format("⚾ Catch the ball!   Score: %d   ⏳ %ds", score, math.ceil(duration - (os.clock() - started)))
					task.wait(0.1)
				end
				if playingCatch then
					playingCatch = false
					header.Text = "Done! Score: " .. score
					remotes.MiniGameFinish:FireServer(score)
					task.wait(1)
					miniGameFrame.Visible = false
				end
			end)
		elseif info.Game == "Run" then
			runPanel.Visible = true
			runPanel.Text = string.format("🏃 Run with your monster!  %d / %d studs  ⏳ %ds", info.Progress or 0, info.Target or 0, math.ceil(info.TimeLeft or 0))
		end
	end)
end

-- الـ Trading -----------------------------------------------------------------------------------

local function buildTrade()
	local tradeButton = UI.Button(ui.Gui, "🤝\nTrade", COLORS.Green, UDim2.fromOffset(84, 84), UDim2.new(0, 104, 0.5, -138))
	tradeButton.TextSize = 18
	local picker = newPanel("TradePicker", UDim2.fromOffset(380, 400), "🤝 Trade with...", COLORS.Green)
	local playerList = makeList(picker, UDim2.new(1, -32, 1, -76), UDim2.fromOffset(16, 60))
	tradeButton.Activated:Connect(function()
		fillPlayers(playerList, function(other)
			remotes.TradeRequest:FireServer(other.UserId)
			picker.Visible = false
		end)
		UI.Toggle(ui, picker)
	end)

	-- شباك الـ Trade نفسه
	local window = newPanel("Trade", UDim2.fromOffset(640, 470), "🤝 Trade", COLORS.Green)
	local mineTitle = UI.Label(window, "Your offer (tap to add/remove)", UDim2.fromOffset(290, 24), UDim2.fromOffset(16, 56), 17)
	mineTitle.TextXAlignment = Enum.TextXAlignment.Left
	local theirTitle = UI.Label(window, "", UDim2.fromOffset(290, 24), UDim2.fromOffset(330, 56), 17)
	theirTitle.TextXAlignment = Enum.TextXAlignment.Left
	local mineList = makeList(window, UDim2.fromOffset(294, 290), UDim2.fromOffset(16, 84))
	local theirList = makeList(window, UDim2.fromOffset(294, 290), UDim2.fromOffset(330, 84))
	local readyButton = UI.Button(window, "Ready ✓", COLORS.Green, UDim2.fromOffset(294, 50), UDim2.fromOffset(16, 400))
	local status = UI.Label(window, "", UDim2.fromOffset(180, 50), UDim2.fromOffset(330, 400), 16)
	local cancel = UI.Button(window, "Cancel", COLORS.Red, UDim2.fromOffset(100, 50), UDim2.fromOffset(524, 400))

	local current: any = nil
	local function selectedIds(): { string }
		local ids = {}
		if current then
			for _, monster in current.MyOffer do
				table.insert(ids, monster.Id)
			end
		end
		return ids
	end
	local function render()
		if not current then
			return
		end
		local selected = {}
		for _, id in selectedIds() do
			selected[id] = true
		end
		fillMonsters(mineList, function(monster)
			return selected[monster.Id] == true
		end, function(monster)
			local ids = selectedIds()
			local index = table.find(ids, monster.Id)
			if index then
				table.remove(ids, index)
			elseif #ids < Config.Trade.MaxOffer then
				table.insert(ids, monster.Id)
			end
			remotes.TradeSetOffer:FireServer(ids)
		end)
		clearList(theirList)
		for index, monster in current.TheirOffer do
			local entry = UI.Label(theirList, monsterText(monster), UDim2.new(1, 0, 0, 34), UDim2.new(), 17)
			entry.LayoutOrder = index
		end
		theirTitle.Text = current.PartnerName .. "'s offer"
		readyButton.Text = if current.MyReady then "Waiting... (tap to undo)" else "Ready ✓"
		readyButton.BackgroundColor3 = if current.MyReady then COLORS.Gray else COLORS.Green
		status.Text = if current.TheirReady then "✅ " .. current.PartnerName .. " is ready" else "⏳ " .. current.PartnerName .. " is choosing"
	end
	readyButton.Activated:Connect(function()
		if current then
			remotes.TradeReady:FireServer(not current.MyReady)
		end
	end)
	cancel.Activated:Connect(function()
		remotes.TradeCancel:FireServer()
	end)
	-- لو قفل الشباك بالـ X بنلغي الـ Trade
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible and current then
			remotes.TradeCancel:FireServer()
		end
	end)

	remotes.TradeUpdate.OnClientEvent:Connect(function(state: any)
		current = state
		if state then
			UI.Open(ui, window)
			render()
		else
			window.Visible = false
		end
	end)

	remotes.TradeIncoming.OnClientEvent:Connect(function(fromUserId: number, fromName: string)
		showPopup("🤝 " .. fromName .. " wants to trade with you!", Config.Trade.RequestTimeout, function(body, close)
			local accept = UI.Button(body, "Accept", COLORS.Green, UDim2.new(0.5, -6, 0, 50), UDim2.fromOffset(0, 150))
			local decline = UI.Button(body, "Decline", COLORS.Red, UDim2.new(0.5, -6, 0, 50), UDim2.new(0.5, 6, 0, 150))
			accept.Activated:Connect(function()
				remotes.TradeRespond:FireServer(fromUserId, true)
				close()
			end)
			decline.Activated:Connect(function()
				remotes.TradeRespond:FireServer(fromUserId, false)
				close()
			end)
		end)
	end)
end

-- الـ Arena -------------------------------------------------------------------------------------

local function buildArena()
	local arenaButton = UI.Button(ui.Gui, "⚔️\nArena", COLORS.Red, UDim2.fromOffset(84, 84), UDim2.new(0, 12, 0.5, -46))
	arenaButton.TextSize = 18
	local picker = newPanel("ArenaPicker", UDim2.fromOffset(640, 470), "⚔️ Monster Arena", COLORS.Red)
	local hint = UI.Label(picker, "Pick an opponent and your fighter. The winner takes coins AND the loser's monster!", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 52), 16)
	hint.TextColor3 = COLORS.SubText
	local playersTitle = UI.Label(picker, "Opponent", UDim2.fromOffset(290, 24), UDim2.fromOffset(16, 96), 17)
	playersTitle.TextXAlignment = Enum.TextXAlignment.Left
	local monstersTitle = UI.Label(picker, "Your fighter", UDim2.fromOffset(290, 24), UDim2.fromOffset(330, 96), 17)
	monstersTitle.TextXAlignment = Enum.TextXAlignment.Left
	local playerList = makeList(picker, UDim2.fromOffset(294, 270), UDim2.fromOffset(16, 122))
	local monsterList = makeList(picker, UDim2.fromOffset(294, 270), UDim2.fromOffset(330, 122))
	local challenge = UI.Button(picker, "Challenge!", COLORS.Gray, UDim2.new(1, -32, 0, 48), UDim2.fromOffset(16, 406))

	local chosenPlayer: Player? = nil
	local chosenMonster: string? = nil
	local function renderPicker()
		fillPlayers(playerList, function(other)
			chosenPlayer = other
			playersTitle.Text = "Opponent: " .. other.DisplayName
		end)
		fillMonsters(monsterList, function(monster)
			return monster.Id == chosenMonster
		end, function(monster)
			chosenMonster = monster.Id
			renderPicker()
		end)
		challenge.BackgroundColor3 = if chosenPlayer and chosenMonster then COLORS.Green else COLORS.Gray
	end
	arenaButton.Activated:Connect(function()
		chosenPlayer = nil
		chosenMonster = nil
		playersTitle.Text = "Opponent"
		renderPicker()
		UI.Toggle(ui, picker)
	end)
	challenge.Activated:Connect(function()
		if chosenPlayer and chosenMonster then
			remotes.ArenaChallenge:FireServer(chosenPlayer.UserId, chosenMonster)
			picker.Visible = false
		end
	end)

	remotes.ArenaIncoming.OnClientEvent:Connect(function(fromUserId: number, fromName: string, monsterName: string)
		showPopup("⚔️ " .. fromName .. " challenges you with " .. monsterName .. "! Pick your fighter:", Config.Arena.RequestTimeout, function(body, close)
			local list = makeList(body, UDim2.new(1, 0, 1, -56), UDim2.new())
			fillMonsters(list, function()
				return false
			end, function(monster)
				remotes.ArenaRespond:FireServer(fromUserId, monster.Id)
				close()
			end)
			local decline = UI.Button(body, "Decline", COLORS.Red, UDim2.new(1, 0, 0, 46), UDim2.new(0, 0, 1, -48))
			decline.Activated:Connect(function()
				remotes.ArenaRespond:FireServer(fromUserId, nil)
				close()
			end)
		end)
	end)

	-- المعركة
	local battle = Instance.new("Frame")
	battle.AnchorPoint = Vector2.new(0.5, 0)
	battle.Position = UDim2.new(0.5, 0, 0, 200)
	battle.Size = UDim2.fromOffset(560, 190)
	battle.BackgroundColor3 = COLORS.Panel
	battle.BackgroundTransparency = 0.1
	battle.Visible = false
	battle.Parent = ui.Gui
	UI.Corner(battle, 16)
	UI.Stroke(battle, COLORS.Red, 3)
	local myName = UI.Label(battle, "", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 8), 18)
	myName.TextXAlignment = Enum.TextXAlignment.Left
	local myBar = UI.Bar(battle, COLORS.Green, UDim2.fromOffset(16, 34))
	local theirName = UI.Label(battle, "", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 70), 18)
	theirName.TextXAlignment = Enum.TextXAlignment.Left
	local theirBar = UI.Bar(battle, COLORS.Red, UDim2.fromOffset(16, 96))
	local log = UI.Label(battle, "", UDim2.new(1, -32, 0, 50), UDim2.fromOffset(16, 132), 20)
	log.TextColor3 = COLORS.Yellow
	local token = 0
	remotes.ArenaUpdate.OnClientEvent:Connect(function(state: any)
		token += 1
		local myToken = token
		if not state then
			battle.Visible = false
			return
		end
		battle.Visible = true
		myName.Text = "🔵 You: " .. state.MyName
		theirName.Text = "🔴 Them: " .. state.TheirName
		UI.SetBar(myBar, state.MyHealth / state.MyMax, string.format("%d / %d", math.floor(state.MyHealth), state.MyMax))
		UI.SetBar(theirBar, state.TheirHealth / state.TheirMax, string.format("%d / %d", math.floor(state.TheirHealth), state.TheirMax))
		log.Text = if state.Done then (if state.Won then "🏆 YOU WON! " else "💔 You lost. ") .. state.Log else state.Log
		if state.Done then
			task.delay(5, function()
				if token == myToken then
					battle.Visible = false
				end
			end)
		end
	end)
end

-- التحديث ---------------------------------------------------------------------------------------

function Features.Refresh()
	local state = getState()
	if not state then
		return
	end

	-- الحالة تحت الفلوس: Speed Boost والحاجة اللي شايلها
	local parts = {}
	if state.Carrying then
		table.insert(parts, "🎒 Carrying a monster: walk it home!")
	end
	if state.BoostLeft and state.BoostLeft > 0 then
		table.insert(parts, "💨 Boost " .. formatTime(state.BoostLeft))
	end
	if state.CoinMultiplier and state.CoinMultiplier > 1 then
		table.insert(parts, "👑 VIP x" .. state.CoinMultiplier)
	end
	statusLabel.Text = table.concat(parts, "   ")

	-- الهدية اليومية
	local dailyIn = state.DailyReadyIn or 0
	local streak = state.DailyStreak or 0
	local nextDay = math.min(streak + 1, Config.Daily.MaxStreak)
	dailyInfo.Text = string.format(
		"Day %d / %d\nNext reward: 💰 %s%s",
		nextDay,
		Config.Daily.MaxStreak,
		MonsterMath.FormatNumber(Config.Daily.CoinsPerDay * nextDay),
		if nextDay == Config.Daily.MaxStreak then " + " .. Config.Eggs[Config.Daily.Day7Egg].DisplayName else ""
	)
	dailyClaim.Text = if dailyIn > 0 then "Ready in " .. formatTime(dailyIn) else "Claim!"
	dailyClaim.BackgroundColor3 = if dailyIn > 0 then COLORS.Gray else COLORS.Green

	-- عجلة الحظ
	local spinIn = state.SpinReadyIn or 0
	spinGo.Text = if spinIn > 0 then "Free spin in " .. formatTime(spinIn) else "SPIN!"
	spinGo.BackgroundColor3 = if spinIn > 0 then COLORS.Gray else COLORS.Green
	rewardsButton.Text = if dailyIn > 0 and spinIn > 0 then "🎁\nRewards" else "🎁\nReady!"

	-- الـ Gamepasses
	local passes = state.Passes or {}
	for name, button in passButtons do
		if passes[name] then
			button.Text = "Owned ✓"
			button.BackgroundColor3 = COLORS.Gray
		else
			button.Text = "R$ " .. Config.Gamepasses[name].Price
			button.BackgroundColor3 = COLORS.Green
		end
	end
	local speedAccessories = state.SpeedAccessories or {}
	for name, button in speedAccessoryButtons do
		local accessory = Config.SpeedAccessories[name]
		if speedAccessories[name] then
			button.Text = "Owned ✓"
			button.BackgroundColor3 = COLORS.Gray
		else
			button.Text = "💰 " .. MonsterMath.FormatNumber(accessory.Price)
			button.BackgroundColor3 = COLORS.Green
		end
	end
	local weapons = state.Weapons or {}
	for name, button in weaponButtons do
		if weapons[name] or passes[name] then
			button.Text = "Owned ✓"
			button.BackgroundColor3 = COLORS.Gray
		else
			button.Text = "💰 " .. MonsterMath.FormatNumber(Config.WeaponCoinPrices[name])
			button.BackgroundColor3 = COLORS.Green
		end
	end

	if accessoriesFrame.Visible then
		refreshAccessories(state)
	end
end

function Features.Init(newUi: UI.UI, allRemotes: { [string]: RemoteEvent }, stateGetter: () -> any, openMonsterGetter: () -> string?)
	ui = newUi
	remotes = allRemotes
	getState = stateGetter
	getOpenMonster = openMonsterGetter

	buildBanner()
	buildPopup()
	buildButtons()
	buildShopExtras()
	buildRewards()
	buildAccessories()
	buildMiniGames()
	buildTrade()
	buildArena()

	remotes.Announce.OnClientEvent:Connect(function(text: string, color: Color3?)
		announce(text, color)
	end)

	-- العدادات (Daily / Spin / Boost) بتعد كل ثانية
	task.spawn(function()
		while true do
			task.wait(1)
			local state = getState()
			if state then
				for _, key in { "DailyReadyIn", "SpinReadyIn", "BoostLeft" } do
					if state[key] and state[key] > 0 then
						state[key] = math.max(0, state[key] - 1)
					end
				end
				Features.Refresh()
			end
		end
	end)
end

return Features
