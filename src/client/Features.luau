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
local TravelControls = require(script.Parent.TravelControls)

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
local dailyInfo: TextLabel
local dailyClaim: TextButton
local spinGo: TextButton
local passButtons: { [string]: TextButton } = {}
local productButtons: { [string]: TextButton } = {}
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

local function offerAvailable(id: number): boolean
	return id ~= 0 or RunService:IsStudio()
end

local function refreshOffer(button: TextButton, id: number, owned: boolean)
	local available = offerAvailable(id) and not owned
	button.Text = if owned then "Owned ✓" elseif id == 0 then (if RunService:IsStudio() then "Test free (Studio)" else "Coming soon") else "Buy"
	button.BackgroundColor3 = if available then COLORS.Green else COLORS.Gray
	button.Active = available
	button.Selectable = available
end

local function buyPass(name: string)
	local pass = Config.Gamepasses[name]
	if pass and offerAvailable(pass.Id) and not ((getState() or {}).Passes or {})[name] then remotes.BuyPass:FireServer(name) end
end

local function buyProduct(name: string)
	local product = Config.Products[name]
	if product and offerAvailable(product.Id) then remotes.BuyProduct:FireServer(name) end
end

local function buildShopExtras()
	local scroll = ui.GearScroll
	local selected = "Weapons"
	local cards: { { Frame: Frame, Category: string, Price: number, Owned: () -> boolean } } = {}
	local tabs: { [string]: TextButton } = {}
	local tabScroll = Instance.new("ScrollingFrame")
	tabScroll.Name = "Categories"
	tabScroll.BackgroundTransparency = 1
	tabScroll.BorderSizePixel = 0
	tabScroll.ScrollBarThickness = 3
	tabScroll.ScrollBarImageColor3 = COLORS.Yellow
	tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
	tabScroll.CanvasSize = UDim2.fromOffset(0, 0)
	tabScroll.Parent = ui.GearFrame
	local eggsButton: TextButton? = nil
	local empty = UI.Label(scroll, "No gear owned yet. Buy an item to find it here.", UDim2.new(1, -16, 0, 80), UDim2.fromOffset(0, 12), 20)
	empty.TextColor3 = COLORS.SubText
	empty.Visible = false
	local function ownedWeapon(name: string): boolean
		local state = getState() or {}
		return name == "Bat" or (state.Weapons or {})[name] == true or (state.Passes or {})[name] == true
	end
	local function card(parent: Instance, name: string, description: string, price: number, icon: string, onBuy: () -> (), currency: string): (Frame, TextButton)
		local frame = Instance.new("Frame")
		frame.Name = name .. "Card"
		frame.Size = UDim2.fromOffset(216, 260)
		frame.BackgroundColor3 = COLORS.Panel
		frame.Parent = parent
		UI.Corner(frame, 12)
		UI.Stroke(frame, COLORS.Yellow, 2)
		local title = UI.Label(frame, name, UDim2.new(1, -20, 0, 36), UDim2.fromOffset(10, 92), 18)
		title.Name = "Title"
		title.TextColor3 = COLORS.Text
		local preview = Instance.new("Frame")
		preview.Name = "Preview"
		preview.BackgroundTransparency = 1
		preview.Size = UDim2.new(1, -20, 0, 84)
		preview.Position = UDim2.fromOffset(10, 4)
		preview.Parent = frame
		if icon:sub(1, 7) == "Weapon:" then
			UI.WeaponPreview(preview, icon:sub(8))
		elseif icon:sub(1, 5) == "Gear:" then
			UI.GearPreview(preview, icon:sub(6))
		else
			UI.Icon(preview, icon, UDim2.fromOffset(80, 80), UDim2.new(0.5, -40, 0.5, -40))
		end
		for _, child in preview:GetChildren() do
			if child:IsA("ViewportFrame") then child.Position = UDim2.fromScale(0, 0); child.Size = UDim2.fromScale(1, 1) end
		end
		local desc = UI.Label(frame, description, UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 130), 14)
		desc.Name = "Description"
		desc.TextColor3 = COLORS.SubText
		local costText = if currency == "Coins " then MonsterMath.FormatNumber(price) .. " Coins" else currency .. MonsterMath.FormatNumber(price)
		local cost = UI.Label(frame, costText, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 176), 18)
		cost.Name = "Price"
		cost.TextColor3 = COLORS.Yellow
		local buy = UI.Button(frame, "Buy", COLORS.Green, UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 206))
		buy.Name = "BuyButton"
		buy.TextSize = 18
		buy.Activated:Connect(onBuy)
		return frame, buy
	end
	local function catalog(category: string, name: string, description: string, price: number, icon: string, onBuy: () -> (), owned: (() -> boolean)?, currency: string?): TextButton
		local frame, buy = card(scroll, name, description, price, icon, onBuy, currency or "Coins ")
		table.insert(cards, { Frame = frame, Category = category, Price = price, Owned = owned or function() return false end })
		return buy
	end
	local function layout()
		-- The panel cancels the HUD scale. Cards keep their native text/touch size.
		local width = if ui.GearFrame.Size.X.Offset > 0 then ui.GearFrame.Size.X.Offset else 740
		local height = if ui.GearFrame.Size.Y.Offset > 0 then ui.GearFrame.Size.Y.Offset else 470
		local padding = if width < 500 then 12 else 16
		tabScroll.Position = UDim2.fromOffset(padding, 58)
		tabScroll.Size = UDim2.new(1, -padding * 2, 0, 48)
		local tabWidth = math.max(116, math.floor((width - padding * 2 - 32) / 5))
		for index, category in { "Weapons", "Accessories", "Coin Packs", "Owned", "Perks" } do
			local tab = tabs[category]
			if tab then
				tab.Size = UDim2.fromOffset(tabWidth, 44)
				tab.Position = UDim2.fromOffset((index - 1) * (tabWidth + 8), 0)
				tab.Text = string.upper(category)
			end
		end
		tabScroll.CanvasSize = UDim2.fromOffset(5 * (tabWidth + 8) - 8, 0)
		scroll.Position = UDim2.fromOffset(padding, 114)
		scroll.Size = UDim2.new(1, -padding * 2, 1, -128)
		local availableWidth = width - padding * 2 - 12
		local horizontal = height < 340 and availableWidth >= 400
		local columns = if horizontal then 1 else math.clamp(math.floor((availableWidth + 12) / 206), 1, 3)
		local cardWidth = math.floor((availableWidth - (columns - 1) * 12) / columns)
		local cardHeight = if horizontal then 164 else 260
		local count = 0
		for _, entry in cards do
			local visible = entry.Category == selected or (selected == "Owned" and (entry.Category == "Weapons" or entry.Category == "Accessories") and entry.Owned())
			entry.Frame.Visible = visible
			if visible then
				local frame = entry.Frame
				frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
				frame.Position = UDim2.fromOffset((count % columns) * (cardWidth + 12), math.floor(count / columns) * (cardHeight + 12) + 4)
				local preview = frame:FindFirstChild("Preview") :: Frame
				preview.Position = UDim2.fromOffset(10, if horizontal then 22 else 4)
				preview.Size = if horizontal then UDim2.fromOffset(112, 112) else UDim2.new(1, -20, 0, 84)
				local textX = if horizontal then 136 else 10
				local function place(name: string, y: number, height: number)
					local item = frame:FindFirstChild(name) :: GuiObject
					item.Position = UDim2.fromOffset(textX, y)
					item.Size = UDim2.new(1, -textX - 10, 0, height)
				end
				place("Title", if horizontal then 8 else 92, 36)
				place("Description", if horizontal then 44 else 130, 44)
				place("Price", if horizontal then 88 else 176, 22)
				place("BuyButton", if horizontal then 112 else 206, 44)
				count += 1
			end
		end
		empty.Visible = count == 0
		local bottom = math.max(84, math.ceil(count / columns) * (cardHeight + 12) + 8)
		if eggsButton then
			eggsButton.Visible = selected == "Perks"
			eggsButton.Position = UDim2.fromOffset(0, bottom)
			eggsButton.Size = UDim2.fromOffset(availableWidth, 44)
			if eggsButton.Visible then bottom += 56 end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, bottom)
		for name, tab in tabs do
			tab.BackgroundColor3 = if name == selected then COLORS.Text else COLORS.Panel
			tab.TextColor3 = if name == selected then COLORS.Panel else COLORS.Text
			local border = tab:FindFirstChildOfClass("UIStroke")
			if border then border.Thickness = if name == selected then 3 else 1 end
		end
	end
	refreshShopCatalog = layout
	local categories = { "Weapons", "Accessories", "Coin Packs", "Owned", "Perks" }
	for index, category in categories do
		local tab = UI.Button(tabScroll, string.upper(category), COLORS.Panel, UDim2.fromOffset(132, 44), UDim2.fromOffset((index - 1) * 140, 0))
		tab.Name = category .. "Tab"
		tab.TextSize = 16
		tabs[category] = tab
		tab.Activated:Connect(function() selected = category; scroll.CanvasPosition = Vector2.zero; layout() end)
	end
	weaponButtons.Bat = catalog("Weapons", "Wooden Bat", "Your starter weapon", 0, "Weapon:WoodenBat", function()
		remotes.EquipWeapon:FireServer("Bat")
	end, function() return true end)
	local weapons = {}
	for name in Config.WeaponStats do table.insert(weapons, name) end
	table.sort(weapons, function(a, b) return Config.WeaponCoinPrices[a] < Config.WeaponCoinPrices[b] end)
	for _, name in weapons do
		local pass = Config.Gamepasses[name]
		weaponButtons[name] = catalog("Weapons", pass.Name, pass.Description, Config.WeaponCoinPrices[name], "Weapon:" .. Config.WeaponStats[name].Template, function()
			if ownedWeapon(name) then remotes.EquipWeapon:FireServer(name) else remotes.BuyWeapon:FireServer(name) end
		end, function() return ownedWeapon(name) end)
	end
	local accessories = {}
	for name, accessory in Config.SpeedAccessories do table.insert(accessories, { Name = name, Accessory = accessory }) end
	table.sort(accessories, function(a, b) return a.Accessory.Price < b.Accessory.Price end)
	for _, entry in accessories do
		local accessory = entry.Accessory
		local function owned(): boolean return ((getState() or {}).SpeedAccessories or {})[entry.Name] == true end
		speedAccessoryButtons[entry.Name] = catalog("Accessories", accessory.Name, string.format("Speed +%d%%  •  HP +%d", math.floor((accessory.Multiplier - 1) * 100 + 0.5), accessory.HealthBonus), accessory.Price, "Gear:" .. entry.Name, function()
			local state = getState() or {}
			if owned() then
				remotes.EquipSpeedAccessory:FireServer(if state.EquippedSpeedAccessory == entry.Name then nil else entry.Name)
			else remotes.BuySpeedAccessory:FireServer(entry.Name) end
		end, owned)
	end
	local passes = {}
	for name, pass in Config.Gamepasses do
		if not Config.WeaponStats[name] and not pass.Hidden and name ~= "AutoFeeder" then table.insert(passes, { Name = name, Pass = pass }) end
	end
	table.sort(passes, function(a, b) return a.Pass.Price < b.Pass.Price end)
	for _, entry in passes do
		local buy = catalog("Perks", entry.Pass.Name, entry.Pass.Description, entry.Pass.Price, if entry.Name == "AutoMinigame" then "Play" else "Rebirth", function() buyPass(entry.Name) end, function() return ((getState() or {}).Passes or {})[entry.Name] == true end, "R$ ")
		passButtons[entry.Name] = buy
		refreshOffer(buy, entry.Pass.Id, false)
	end
	local products = {}
	for name, product in Config.Products do table.insert(products, { Name = name, Product = product }) end
	table.sort(products, function(a, b) return a.Product.Price < b.Product.Price end)
	for _, entry in products do
		local product = entry.Product
		local buy = catalog(if product.Coins then "Coin Packs" else "Perks", product.Name, product.Description, product.Price, if product.Coins then "Coins" else "Potion", function() buyProduct(entry.Name) end, nil, "R$ ")
		productButtons[entry.Name] = buy
		refreshOffer(buy, product.Id, false)
	end
	local feeder = Config.Gamepasses.AutoFeeder
	local buy = catalog("Perks", feeder.Name, feeder.Description, feeder.Price, "Pets", function() buyPass("AutoFeeder") end, function() return ((getState() or {}).Passes or {}).AutoFeeder == true end, "R$ ")
	passButtons.AutoFeeder = buy
	refreshOffer(buy, feeder.Id, false)
	if next(ui.EggButtons) then
		local eggs = UI.Button(scroll, "Eggs", COLORS.Pink, UDim2.fromOffset(184, 44), UDim2.fromOffset(0, 0))
		eggsButton = eggs
		eggs.Activated:Connect(function() UI.Open(ui, ui.EggShopFrame) end)
	end
	table.sort(cards, function(a, b)
		return if a.Price == b.Price then a.Frame.Name < b.Frame.Name else a.Price < b.Price
	end)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	ui.GearFrame:GetPropertyChangedSignal("Size"):Connect(layout)
	layout()
end

-- الهدية اليومية وعجلة الحظ في شباك واحد: اليومية على الشمال والعجلة على اليمين ----------------

local function buildRewards()
	local frame = newPanel("Rewards", UDim2.fromOffset(820, 470), "🎁 Rewards", COLORS.Yellow)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.82
	scale.Parent = frame
	launcherActions.Rewards = function()
		UI.Toggle(ui, frame)
	end

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

	refreshShopCatalog()

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
	rewardsButton.Text = if dailyIn > 0 and spinIn > 0 then "Rewards" else "Rewards!"

	-- الـ Gamepasses
	local passes = state.Passes or {}
	for name, button in passButtons do
		refreshOffer(button, Config.Gamepasses[name].Id, passes[name] == true)
	end
	for name, button in productButtons do refreshOffer(button, Config.Products[name].Id, false) end
	local speedAccessories = state.SpeedAccessories or {}
	for name, button in speedAccessoryButtons do
		local accessory = Config.SpeedAccessories[name]
		if speedAccessories[name] then
			local equipped = state.EquippedSpeedAccessory == name
			button.Text = if equipped then "Equipped · Unequip" else "Equip"
			button.BackgroundColor3 = if equipped then COLORS.Gray else COLORS.Blue
		else
			button.Text = "Buy"
			button.BackgroundColor3 = COLORS.Green
		end
	end
	local weapons = state.Weapons or {}
	for name, button in weaponButtons do
		if name == "Bat" or weapons[name] or passes[name] then
			local equipped = (state.EquippedWeapon or "Bat") == name
			button.Text = if equipped then "Equipped ✓" else "Equip"
			button.BackgroundColor3 = if equipped then COLORS.Gray else COLORS.Blue
		else
			button.Text = "Buy"
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
	local AuthoredLaunchers = require(script.Parent.AuthoredLaunchers)
	AuthoredLaunchers.Start(ui.Gui.Parent, {
		Shop = ui.ShopButton, Rewards = rewardsButton, Trade = ui.NavigationButtons.Trade,
	}, launcherActions)

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
