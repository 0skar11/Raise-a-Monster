--!strict
-- واجهة الأنظمة الجديدة: تليبورت، الهدية اليومية، عجلة الحظ، الـ Gamepasses في المتجر،
-- الإكسسوارات، الألعاب الصغيرة، الـ Trading، الـ Arena، والإعلانات الكبيرة.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)
local RewardsArcade = require(script.Parent.RewardsArcade)
local TravelControls = require(script.Parent.TravelControls)
local MonsterForge = require(script.Parent.MonsterForge)

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
local launcherActions: { [string]: () -> () } = {}
local rewardsController: any
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
	popup.Active = true
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
	TravelControls.Start(ui.Gui.Parent, {
		HomeButton = ui.HomeButton, TeleportShopButton = ui.TeleportShopButton, TeleportArenaButton = ui.TeleportArenaButton,
	}, function(destination) remotes.Teleport:FireServer(destination) end)

	rewardsButton = ui.NavigationButtons.Rewards

	statusLabel = UI.Label(ui.Hud, "", UDim2.new(1, -32, 0, 26), UDim2.fromOffset(16, 76), 16)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.ZIndex = 0
	local walletTravel = ui.Hud:FindFirstChild("WalletTravel")
	if walletTravel and walletTravel:IsA("GuiObject") then
		local status = statusLabel
		local function placeStatus()
			local bottom = walletTravel.AbsolutePosition.Y - ui.Hud.AbsolutePosition.Y + walletTravel.AbsoluteSize.Y
			status.Position = UDim2.fromOffset(16, bottom + 4)
		end
		walletTravel:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeStatus)
		walletTravel:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStatus)
		placeStatus()
	end
end

-- المتجر: الإكسسوارات والأسلحة بعملات اللعبة، ثم الـ Gamepasses والـ Boosts -----------------

local refreshShopCatalog: () -> () = function() end
local refreshAdultChooser: () -> () = function() end
local refreshAdultSummary: () -> () = function() end
local openAdultChooser: (() -> ())? = nil

local function adultCandidates(): { any }
	local adultLevel: number? = nil
	for _, stage in Config.Stages do
		if stage.Name == "Adult" then adultLevel = stage.MinLevel; break end
	end
	local state = getState()
	local candidates = {}
	if not state or not adultLevel then return candidates end
	for _, monster in state.Monsters or {} do
		if type(monster.Id) == "string" and monster.Id ~= "" and type(monster.Level) == "number"
			and monster.Level < adultLevel and monster.Available == true and not monster.Carried and not monster.InTrade then
			table.insert(candidates, monster)
		end
	end
	table.sort(candidates, function(a, b)
		local aProduction, bProduction = a.Production or 0, b.Production or 0
		return if aProduction == bProduction then a.Id < b.Id else aProduction > bProduction
	end)
	return candidates
end

local function offerAvailable(id: number): boolean
	return id ~= 0 or RunService:IsStudio()
end

local function buyPass(name: string)
	local pass = Config.Gamepasses[name]
	if pass and offerAvailable(pass.Id) and not ((getState() or {}).Passes or {})[name] then remotes.BuyPass:FireServer(name) end
end

local function buyProduct(name: string)
	local product = Config.Products[name]
	if not product or not offerAvailable(product.Id) then return end
	if name == "SkipToAdultOne" then
		if openAdultChooser then openAdultChooser() end
		return
	elseif name == "SkipToAdultAll" and #adultCandidates() == 0 then
		UI.Toast(ui, "No available monsters below Adult in your collection.", "warning")
		return
	end
	remotes.BuyProduct:FireServer(name)
end

local function buildAdultChooser()
	local frame = newPanel("SkipToAdultChooser", UDim2.fromOffset(500, 400), "SKIP TO ADULT", COLORS.Pink)
	local title = frame:FindFirstChildWhichIsA("TextLabel")
	if title then title.TextSize = 24 end
	local scale = Instance.new("UIScale")
	scale.Name = "NativeAdultChooserScale"
	scale.Parent = frame
	local shopScale = ui.GearFrame:FindFirstChild("NativeShopScale") :: UIScale?
	local function fit()
		frame.Size = UDim2.fromOffset(math.min(500, ui.GearFrame.Size.X.Offset), math.min(400, ui.GearFrame.Size.Y.Offset))
		if shopScale then scale.Scale = shopScale.Scale end
	end
	ui.GearFrame:GetPropertyChangedSignal("Size"):Connect(fit)
	if shopScale then shopScale:GetPropertyChangedSignal("Scale"):Connect(fit) end
	fit()
	local price = Config.Products.SkipToAdultOne and Config.Products.SkipToAdultOne.Price or 29
	local info = UI.Label(frame, "Choose 1 current monster for R$ " .. tostring(price) .. ". Future monsters excluded.", UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 54), 16)
	info.Name = "Scope"
	local list = makeList(frame, UDim2.new(1, -32, 1, -120), UDim2.fromOffset(16, 104))
	list.Name = "Monsters"
	local rowsSignature = ""
	refreshAdultChooser = function()
		if not frame.Visible then return end
		local candidates = adultCandidates()
		local parts = {}
		for _, monster in candidates do
			table.insert(parts, monster.Id .. ":" .. monsterText(monster))
		end
		local signature = table.concat(parts, "|")
		if signature == rowsSignature then return end
		rowsSignature = signature
		clearList(list)
		for index, monster in candidates do
			local entry = UI.Button(list, monsterText(monster), COLORS.Panel, UDim2.new(1, 0, 0, 44), UDim2.new())
			entry.Name = monster.Id
			entry.LayoutOrder = index
			entry.TextSize = 17
			entry.Activated:Connect(function()
				local product = Config.Products.SkipToAdultOne
				if not product or not offerAvailable(product.Id) then return end
				-- Recheck fresh state; the server validates again before prompting.
				for _, candidate in adultCandidates() do
					if candidate.Id == monster.Id then
						remotes.BuyProduct:FireServer("SkipToAdultOne", candidate.Id)
						UI.Open(ui, ui.GearFrame)
						return
					end
				end
				refreshAdultChooser()
			end)
		end
		if #candidates == 0 then
			local empty = UI.Label(list, "No available monsters below Adult in your collection.", UDim2.new(1, 0, 0, 60), UDim2.new(), 16)
			empty.Name = "Empty"
			empty.TextColor3 = COLORS.SubText
		end
	end
	openAdultChooser = function()
		rowsSignature = "refresh"
		UI.Open(ui, frame)
		refreshAdultChooser()
	end
end

local function buildShopExtras()
	buildAdultChooser()
	local controller = MonsterForge.Mount(ui.GearFrame, ui.GearScroll, {
		GetState = getState,
		Remotes = remotes,
		BuyPass = buyPass,
		BuyProduct = buyProduct,
		AdultCandidates = adultCandidates,
	})
	refreshShopCatalog = function() controller:Refresh() end
end

-- الهدية اليومية وعجلة الحظ في شباك واحد: اليومية على الشمال والعجلة على اليمين ----------------

local function buildRewards()
	local frame = newPanel("Rewards", UDim2.fromOffset(960, 720), "Rewards", COLORS.Yellow)
	launcherActions.Rewards = function() UI.Toggle(ui, frame) end
	rewardsController = RewardsArcade.Mount(frame, {
		GetState = getState,
		ClaimDaily = function() remotes.ClaimDaily:FireServer() end,
		Spin = function() remotes.Spin:FireServer() end,
	})
	remotes.SpinResult.OnClientEvent:Connect(function(index: number)
		UI.Open(ui, frame)
		rewardsController:ShowSpinResult(index)
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
	miniGameFrame.Active = true
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
		remotes.MiniGameCatch:FireServer()
		ball.Position = UDim2.fromOffset(math.random(20, 530), math.random(70, 330))
	end)

	remotes.MiniGameState.OnClientEvent:Connect(function(info: any)
		if info.Done then
			playingCatch = false
			miniGameFrame.Visible = false
			runPanel.Visible = false
			return
		end
		if info.Game == "Catch" and playingCatch and type(info.Score) == "number" then
			score = math.clamp(math.floor(info.Score), 0, Config.MiniGames.Catch.MaxCatches)
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
					remotes.MiniGameFinish:FireServer()
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
	local picker = newPanel("TradePicker", UDim2.fromOffset(380, 400), "🤝 Trade with...", COLORS.Green)
	local playerList = makeList(picker, UDim2.new(1, -32, 1, -76), UDim2.fromOffset(16, 60))
	launcherActions.Trade = function()
		fillPlayers(playerList, function(other)
			remotes.TradeRequest:FireServer(other.UserId)
			picker.Visible = false
		end)
		UI.Toggle(ui, picker)
	end

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
	local arenaButton = ui.NavigationButtons.Arena
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
	if arenaButton then
		arenaButton.Activated:Connect(function()
			chosenPlayer = nil
			chosenMonster = nil
			playersTitle.Text = "Opponent"
			renderPicker()
			UI.Toggle(ui, picker)
		end)
	end
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

	refreshShopCatalog()
	refreshAdultChooser()
	refreshAdultSummary()

	-- الحالة تحت الفلوس: Speed Boost والحاجة اللي شايلها
	local parts = {}
	if state.SaveDisabled then
		table.insert(parts, "⚠ Saving unavailable · progress is not saved")
	end
	if state.Carrying then
		table.insert(parts, "🎒 Carrying a monster: walk it home!")
	end
	if state.BoostLeft and state.BoostLeft > 0 then
		table.insert(parts, "💨 Boost " .. formatTime(state.BoostLeft))
	end
	if state.CoinMultiplier and state.CoinMultiplier > 1 then
		table.insert(parts, "💰 Income x" .. state.CoinMultiplier)
	end
	statusLabel.Text = table.concat(parts, "   ")

	if rewardsController then rewardsController:Refresh(state) end
	local dailyIn = state.DailyReadyIn or 0
	local spinIn = state.SpinReadyIn or 0
	rewardsButton.Text = if dailyIn > 0 and spinIn > 0 then "Rewards" else "Rewards!"


	if accessoriesFrame.Visible then
		refreshAccessories(state)
	end
end

-- The inventory lives in another module; once it exists, the launcher (authored golden paw, or the
-- built-in button as a fallback) is bound to it.
local startLaunchers: (() -> ())? = nil
function Features.SetInventoryOpener(open: () -> ())
	launcherActions.Inventory = open
	if startLaunchers then startLaunchers() end
end

function Features.Init(newUi: UI.UI, allRemotes: { [string]: RemoteEvent }, stateGetter: () -> any, openMonsterGetter: () -> string?)
	ui = newUi
	remotes = allRemotes
	getState = stateGetter
	getOpenMonster = openMonsterGetter
	launcherActions = { Shop = function() UI.Open(ui, ui.GearFrame) end }

	buildBanner()
	buildPopup()
	buildButtons()
	buildShopExtras()
	buildRewards()
	buildAccessories()
	buildMiniGames()
	buildTrade()
	buildArena()
	startLaunchers = function()
		local AuthoredLaunchers = require(script.Parent.AuthoredLaunchers)
		AuthoredLaunchers.Start(ui.Gui.Parent, {
			Shop = ui.ShopButton, Rewards = rewardsButton, Trade = ui.NavigationButtons.Trade,
			Inventory = ui.InventoryButton,
		}, launcherActions)
	end
	startLaunchers()

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
