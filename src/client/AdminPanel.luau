--!strict
-- Admin panel (F4). Built only after the server confirms this player is in Config.Admin.Usernames; the server
-- re-checks every action, so this is just the remote control.
--
-- Layout: a draggable window with a target picker (ME + every player in the server) and four tabs:
--   PLAYER (heal / teleport), GIVE (coins, candy, eggs, monsters), EVENTS (invasion, hunt, rain, announce), BOSS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local AdminPanel = {}

local PANEL = Color3.fromRGB(26, 20, 46)
local RAISED = Color3.fromRGB(38, 30, 62)
local RAISED_HOVER = Color3.fromRGB(58, 46, 94)
local GOLD = Color3.fromRGB(255, 190, 60)
local INK = Color3.fromRGB(245, 240, 255)
local MUTED = Color3.fromRGB(165, 155, 195)
local GREEN = Color3.fromRGB(34, 130, 84)
local PURPLE = Color3.fromRGB(104, 62, 176)
local RED = Color3.fromRGB(176, 52, 66)
local ORANGE = Color3.fromRGB(190, 82, 30)
local BLUE = Color3.fromRGB(38, 110, 190)

local player = Players.LocalPlayer

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent: Instance, all: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, all)
	p.PaddingRight = UDim.new(0, all)
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.Parent = parent
end

local function list(parent: Instance, gap: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function label(parent: Instance, text: string, size: number, color: Color3, order: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBlack else Enum.Font.GothamBold
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Size = UDim2.new(1, 0, 0, size + 6)
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.LayoutOrder = order
	item.Parent = parent
	return item
end

local function button(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = color
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextSize = 14
	item.TextColor3 = INK
	item.LayoutOrder = order
	item.Parent = parent
	corner(item, 8)
	item.MouseEnter:Connect(function()
		TweenService:Create(item, TweenInfo.new(0.12), { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.18) }):Play()
	end)
	item.MouseLeave:Connect(function()
		TweenService:Create(item, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
	end)
	item.Activated:Connect(function()
		item.BackgroundColor3 = Color3.new(1, 1, 1)
		TweenService:Create(item, TweenInfo.new(0.3), { BackgroundColor3 = color }):Play()
		onClick()
	end)
	return item
end

local function field(parent: Instance, placeholder: string, order: number, width: UDim?): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = RAISED
	box.Font = Enum.Font.Gotham
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = MUTED
	box.Text = ""
	box.TextColor3 = INK
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.Size = UDim2.new(width or UDim.new(1, 0), 0, 0, 32)
	box.LayoutOrder = order
	box.Parent = parent
	corner(box, 8)
	stroke(box, PURPLE, 1, 0.5)
	return box
end

local function row(parent: Instance, order: number, height: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height or 34)
	frame.LayoutOrder = order
	frame.Parent = parent
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = frame
	return frame
end

local function grid(parent: Instance, order: number, cellWidth: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = parent
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(0, cellWidth, 0, 32)
	g.CellPadding = UDim2.fromOffset(6, 6)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = frame
	return frame
end

local function parseAmount(text: string): number?
	local raw = text:lower():gsub(",", ""):gsub("%s+", "")
	local number, suffix = raw:match("^([%d%.]+)(%a*)$")
	local value = tonumber(number)
	if not value then
		return nil
	end
	local multipliers = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }
	return value * (multipliers[suffix] or 1)
end

function AdminPanel.Start(playerGui: PlayerGui, remotes: { [string]: RemoteEvent })
	local built = false
	remotes.AdminAccess.OnClientEvent:Connect(function(allowed: boolean, _names: { string })
		if not allowed or built then
			return
		end
		built = true

		local selectedTarget = "" -- "" means me
		local function send(action: string, extra: { [string]: any }?)
			local args: { [string]: any } = { Target = selectedTarget }
			for key, value in extra or {} do
				args[key] = value
			end
			remotes.AdminAction:FireServer(action, args)
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "AdminPanel"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 90
		gui.Parent = playerGui

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.AnchorPoint = Vector2.new(1, 0.5)
		panel.Position = UDim2.new(1, -16, 0.5, 0)
		panel.Size = UDim2.fromOffset(460, 560)
		panel.BackgroundColor3 = PANEL
		panel.Visible = false
		panel.Parent = gui
		corner(panel, 14)
		stroke(panel, GOLD, 2)
		local panelGradient = Instance.new("UIGradient")
		panelGradient.Color = ColorSequence.new(Color3.fromRGB(30, 22, 52), PANEL)
		panelGradient.Rotation = 90
		panelGradient.Parent = panel

		-- header (drag handle)
		local header = Instance.new("Frame")
		header.BackgroundColor3 = RAISED
		header.Size = UDim2.new(1, 0, 0, 42)
		header.Parent = panel
		corner(header, 14)
		local headerFix = Instance.new("Frame") -- squares off the header's bottom corners
		headerFix.BackgroundColor3 = RAISED
		headerFix.BorderSizePixel = 0
		headerFix.Position = UDim2.new(0, 0, 1, -14)
		headerFix.Size = UDim2.new(1, 0, 0, 14)
		headerFix.Parent = header
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = "🛠  ADMIN PANEL"
		title.TextColor3 = GOLD
		title.TextSize = 18
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(14, 0)
		title.Size = UDim2.new(1, -120, 1, 0)
		title.Parent = header
		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.Gotham
		hint.Text = "F4 to toggle · drag to move"
		hint.TextColor3 = MUTED
		hint.TextSize = 11
		hint.TextXAlignment = Enum.TextXAlignment.Right
		hint.Position = UDim2.new(1, -150, 0, 0)
		hint.Size = UDim2.fromOffset(100, 42)
		hint.Parent = header
		local close = button(header, "X", RED, 0, function()
			panel.Visible = false
		end)
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -8, 0.5, 0)
		close.Size = UDim2.fromOffset(30, 28)

		-- dragging
		local dragStart: Vector2? = nil
		local panelStart = Vector2.zero
		header.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragStart = Vector2.new(input.Position.X, input.Position.Y)
				panelStart = panel.AbsolutePosition + panel.AbsoluteSize * panel.AnchorPoint
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
				local target = panelStart + delta
				panel.Position = UDim2.fromOffset(target.X, target.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragStart = nil
			end
		end)

		-- target picker: ME + every player
		local targetBar = Instance.new("ScrollingFrame")
		targetBar.BackgroundTransparency = 1
		targetBar.BorderSizePixel = 0
		targetBar.Position = UDim2.fromOffset(10, 50)
		targetBar.Size = UDim2.new(1, -20, 0, 38)
		targetBar.ScrollBarThickness = 3
		targetBar.CanvasSize = UDim2.new()
		targetBar.AutomaticCanvasSize = Enum.AutomaticSize.X
		targetBar.ScrollingDirection = Enum.ScrollingDirection.X
		targetBar.Parent = panel
		local targetLayout = Instance.new("UIListLayout")
		targetLayout.FillDirection = Enum.FillDirection.Horizontal
		targetLayout.Padding = UDim.new(0, 6)
		targetLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
		targetLayout.Parent = targetBar

		local targetChips: { [string]: TextButton } = {}
		local function paintTargets()
			for name, chip in targetChips do
				local selected = (name == "ME" and selectedTarget == "") or name == selectedTarget
				chip.BackgroundColor3 = if selected then GOLD else RAISED
				chip.TextColor3 = if selected then Color3.fromRGB(30, 20, 5) else INK
			end
		end
		local function rebuildTargets()
			for _, chip in targetChips do
				chip:Destroy()
			end
			table.clear(targetChips)
			local names = { "ME" }
			for _, other in Players:GetPlayers() do
				if other ~= player then
					table.insert(names, other.Name)
				end
			end
			if selectedTarget ~= "" and not table.find(names, selectedTarget) then
				selectedTarget = ""
			end
			for index, name in names do
				local chip = Instance.new("TextButton")
				chip.AutoButtonColor = false
				chip.Font = Enum.Font.GothamBold
				chip.Text = name
				chip.TextSize = 13
				chip.Size = UDim2.fromOffset(math.max(52, #name * 8 + 22), 30)
				chip.LayoutOrder = index
				chip.Parent = targetBar
				corner(chip, 15)
				chip.Activated:Connect(function()
					selectedTarget = if name == "ME" then "" else name
					paintTargets()
				end)
				targetChips[name] = chip
			end
			paintTargets()
		end
		Players.PlayerAdded:Connect(rebuildTargets)
		Players.PlayerRemoving:Connect(function()
			task.defer(rebuildTargets)
		end)
		rebuildTargets()

		-- tabs
		local tabBar = Instance.new("Frame")
		tabBar.BackgroundTransparency = 1
		tabBar.Position = UDim2.fromOffset(10, 94)
		tabBar.Size = UDim2.new(1, -20, 0, 34)
		tabBar.Parent = panel
		local tabLayout = Instance.new("UIListLayout")
		tabLayout.FillDirection = Enum.FillDirection.Horizontal
		tabLayout.Padding = UDim.new(0, 6)
		tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabLayout.Parent = tabBar

		local pages: { [string]: ScrollingFrame } = {}
		local tabButtons: { [string]: TextButton } = {}
		local function showTab(name: string)
			for key, page in pages do
				page.Visible = key == name
				tabButtons[key].BackgroundColor3 = if key == name then PURPLE else RAISED
			end
		end
		local function makePage(name: string, order: number): ScrollingFrame
			local page = Instance.new("ScrollingFrame")
			page.BackgroundTransparency = 1
			page.BorderSizePixel = 0
			page.Position = UDim2.fromOffset(10, 136)
			page.Size = UDim2.new(1, -20, 1, -146)
			page.CanvasSize = UDim2.new()
			page.AutomaticCanvasSize = Enum.AutomaticSize.Y
			page.ScrollBarThickness = 4
			page.Visible = false
			page.Parent = panel
			list(page, 8)
			pages[name] = page
			local tab = button(tabBar, string.upper(name), RAISED, order, function()
				showTab(name)
			end)
			tab.Size = UDim2.new(0.25, -5, 1, 0)
			tabButtons[name] = tab
			return page
		end

		-- PLAYER ---------------------------------------------------------------------------------------------------------
		local playerPage = makePage("Player", 1)
		label(playerPage, "Acts on the player selected above (ME by default).", 12, MUTED, 1)
		local playerGrid = grid(playerPage, 2, 208)
		button(playerGrid, "❤ Heal", GREEN, 1, function() send("Heal") end)
		button(playerGrid, "🚶 Go to player", PURPLE, 2, function() send("Goto") end)
		button(playerGrid, "🧲 Bring player", PURPLE, 3, function() send("Bring") end)
		button(playerGrid, "💀 Go to Boss", ORANGE, 4, function() send("GoToBoss") end)
		button(playerGrid, "❤ Heal everyone", GREEN, 5, function() send("HealAll") end)

		-- GIVE -----------------------------------------------------------------------------------------------------------
		local givePage = makePage("Give", 2)
		label(givePage, "COINS", 12, GOLD, 1, true)
		local coinAmount = field(givePage, "Amount (1k, 5m, 2.5b, 1t, 3qa ...)", 2)
		local coinChips = row(givePage, 3)
		for _, preset in { "1k", "1m", "1b", "1t", "1qa" } do
			local chip = button(coinChips, preset, RAISED, 0, function()
				coinAmount.Text = preset
			end)
			chip.Size = UDim2.fromOffset(56, 28)
		end
		button(givePage, "Give coins", GREEN, 4, function()
			send("GiveCoins", { Amount = parseAmount(coinAmount.Text) })
		end).Size = UDim2.new(1, 0, 0, 34)

		label(givePage, "CANDY", 12, GOLD, 5, true)
		local candyAmount = field(givePage, "Amount (100, 1k, 10k ...)", 6)
		local candyChips = row(givePage, 7)
		for _, preset in { "100", "1k", "10k", "100k" } do
			local chip = button(candyChips, preset, RAISED, 0, function()
				candyAmount.Text = preset
			end)
			chip.Size = UDim2.fromOffset(56, 28)
		end
		button(givePage, "Give candy", GREEN, 8, function()
			send("GiveCandy", { Amount = parseAmount(candyAmount.Text) })
		end).Size = UDim2.new(1, 0, 0, 34)

		label(givePage, "EGGS (tap one to give it)", 12, GOLD, 9, true)
		local eggGrid = grid(givePage, 10, 100)
		local eggKeys = {}
		for key in Config.Eggs do
			table.insert(eggKeys, key)
		end
		table.sort(eggKeys)
		for index, key in eggKeys do
			button(eggGrid, key, RAISED, index, function() send("GiveEgg", { Name = key }) end)
		end

		label(givePage, "MONSTERS (filter, then tap)", 12, GOLD, 11, true)
		local monsterFilter = field(givePage, "Filter by name or key, e.g. Void, Dragon, Pumpkin", 12)
		local monsterHolder = Instance.new("Frame")
		monsterHolder.BackgroundTransparency = 1
		monsterHolder.Size = UDim2.new(1, 0, 0, 0)
		monsterHolder.AutomaticSize = Enum.AutomaticSize.Y
		monsterHolder.LayoutOrder = 13
		monsterHolder.Parent = givePage
		list(monsterHolder, 4)
		local speciesKeys = {}
		for key in Config.Species do
			table.insert(speciesKeys, key)
		end
		table.sort(speciesKeys)
		local function refreshMonsters()
			for _, child in monsterHolder:GetChildren() do
				if child:IsA("GuiButton") then
					child:Destroy()
				end
			end
			local needle = string.lower(monsterFilter.Text)
			local shown = 0
			for _, key in speciesKeys do
				local species = Config.Species[key]
				local haystack = string.lower(key .. " " .. species.DisplayName .. " " .. species.Rarity)
				if needle == "" or haystack:find(needle, 1, true) then
					shown += 1
					if shown > 14 then
						break
					end
					local entry = button(monsterHolder, string.format("%s  ·  %s  ·  %s", species.DisplayName, species.Rarity, key), RAISED, shown, function()
						send("GiveMonster", { Name = key })
					end)
					entry.Size = UDim2.new(1, 0, 0, 28)
					entry.TextSize = 12
					entry.TextXAlignment = Enum.TextXAlignment.Left
					local pad = Instance.new("UIPadding")
					pad.PaddingLeft = UDim.new(0, 10)
					pad.Parent = entry
				end
			end
		end
		monsterFilter:GetPropertyChangedSignal("Text"):Connect(refreshMonsters)
		refreshMonsters()

		-- EVENTS ---------------------------------------------------------------------------------------------------------
		local eventsPage = makePage("Events", 3)
		label(eventsPage, "MOTHER INVASION", 12, GOLD, 1, true)
		local countRow = row(eventsPage, 2, 34)
		local count = 5
		local countLabel = Instance.new("TextLabel")
		countLabel.BackgroundColor3 = RAISED
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextColor3 = INK
		countLabel.TextSize = 15
		countLabel.Size = UDim2.fromOffset(150, 30)
		countLabel.LayoutOrder = 2
		countLabel.Parent = countRow
		corner(countLabel, 8)
		local function paintCount()
			countLabel.Text = string.format("Mothers: %d", count)
		end
		paintCount()
		local minus = button(countRow, "-", RAISED, 1, function()
			count = math.max(3, count - 1)
			paintCount()
		end)
		minus.Size = UDim2.fromOffset(34, 30)
		local plus = button(countRow, "+", RAISED, 3, function()
			count = math.min(10, count + 1)
			paintCount()
		end)
		plus.Size = UDim2.fromOffset(34, 30)
		button(countRow, "Start invasion", ORANGE, 4, function()
			send("StartInvasion", { Amount = count })
		end).Size = UDim2.fromOffset(160, 30)
		label(eventsPage, "OTHER EVENTS", 12, GOLD, 3, true)
		local eventGrid = grid(eventsPage, 4, 208)
		button(eventGrid, "🎃 Pumpkin Hunt", ORANGE, 1, function() send("StartPumpkinHunt") end)
		button(eventGrid, "🌧 Monster Rain", BLUE, 2, function() send("MonsterRain") end)
		label(eventsPage, "ANNOUNCEMENT", 12, GOLD, 5, true)
		local announceText = field(eventsPage, "Text shown to everyone (max 120 characters)", 6)
		button(eventsPage, "📢 Send announcement", PURPLE, 7, function()
			send("Announce", { Text = announceText.Text })
		end).Size = UDim2.new(1, 0, 0, 34)

		-- BOSS -----------------------------------------------------------------------------------------------------------
		local bossPage = makePage("Boss", 4)
		label(bossPage, "BIG BOSS (the Pumpkin Titan)", 12, GOLD, 1, true)
		local bossGrid = grid(bossPage, 2, 208)
		button(bossGrid, "💀 Spawn boss", RED, 1, function() send("SpawnBoss") end)
		local killButton: TextButton
		killButton = button(bossGrid, "☠ Kill boss", RAISED, 2, function()
			if killButton.Text == "☠ Kill boss" then
				killButton.Text = "Tap again to confirm"
				task.delay(2.5, function()
					killButton.Text = "☠ Kill boss"
				end)
			else
				killButton.Text = "☠ Kill boss"
				send("KillBoss")
			end
		end)
		label(bossPage, "SET HEALTH", 12, GOLD, 3, true)
		local healthRow = row(bossPage, 4, 32)
		for _, percent in { 100, 75, 50, 25, 10 } do
			local chip = button(healthRow, percent .. "%", RAISED, 0, function()
				send("BossHealth", { Amount = percent })
			end)
			chip.Size = UDim2.fromOffset(60, 30)
		end
		label(bossPage, "FORCE AN ATTACK", 12, GOLD, 5, true)
		local attackGrid = grid(bossPage, 6, 136)
		for index, name in { "Sweep", "Slam", "Bombs", "Vine", "Pulse", "Rain" } do
			button(attackGrid, name, ORANGE, index, function() send("BossAttack", { Name = name }) end)
		end
		label(bossPage, "Attacks and health use the boss that is alive right now; spawn one first.", 12, MUTED, 7)

		showTab("Player")

		local function toggle()
			panel.Visible = not panel.Visible
		end
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			if input.KeyCode == Config.Admin.OpenKey then
				toggle()
			end
		end)
	end)
	remotes.AdminAction:FireServer("Hello")
end

return AdminPanel
