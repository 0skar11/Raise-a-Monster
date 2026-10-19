--!strict
-- اختيار من المجموعة ثم خانة مفتوحة؛ السيرفر وحده بيقرر النقل والدخل.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)

local MonsterInventory = {}

function MonsterInventory.Init(ui: UI.UI, remotes: { [string]: RemoteEvent }, getState: () -> any, openMonster: ((string) -> ())?)
	local colors = UI.Colors
	local frame, title = UI.Panel(ui.Gui, "MonsterInventory", UDim2.fromOffset(740, 600), "Monster collection", colors.Yellow)
	title.Size = UDim2.new(1, -80, 0, 44)
	table.insert(ui.Panels, frame)
	local counts = UI.Label(frame, "", UDim2.new(1, -240, 0, 42), UDim2.fromOffset(18, 52), 17)
	counts.TextXAlignment = Enum.TextXAlignment.Left
	counts.TextColor3 = colors.SubText
	local auto = UI.Button(frame, "Auto Place", colors.Green, UDim2.fromOffset(192, 44), UDim2.new(1, -210, 0, 54))
	local collectionTitle = UI.Label(frame, "YOUR MONSTERS", UDim2.new(0.55, -22, 0, 28), UDim2.fromOffset(18, 104), 17)
	collectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	local slotTitle = UI.Label(frame, "BASE SLOTS", UDim2.new(0.45, -22, 0, 28), UDim2.new(0.55, 4, 0, 104), 17)
	slotTitle.TextXAlignment = Enum.TextXAlignment.Left
	local function makeScroll(name: string, size: UDim2, position: UDim2): ScrollingFrame
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = name
		scroll.Size = size
		scroll.Position = position
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 5
		scroll.ScrollBarImageColor3 = colors.Yellow
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 9)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroll
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 3)
		padding.PaddingRight = UDim.new(0, 9)
		padding.PaddingTop = UDim.new(0, 3)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = scroll
		return scroll
	end
	local collection = makeScroll("Collection", UDim2.new(0.55, -22, 1, -230), UDim2.fromOffset(18, 140))
	local slots = makeScroll("BaseSlots", UDim2.new(0.45, -22, 1, -230), UDim2.new(0.55, 4, 0, 140))
	local hint = UI.Label(frame, "Only placed monsters earn coins. Select one, then tap an unlocked slot.", UDim2.new(1, -36, 0, 34), UDim2.new(0, 18, 1, -83), 15)
	hint.TextColor3 = colors.SubText
	local bench = UI.Button(frame, "Move to bench", colors.Blue, UDim2.new(0.55, -22, 0, 44), UDim2.new(0, 18, 1, -50))
	local view = UI.Button(frame, "View selected", colors.PanelLight, UDim2.new(0.45, -22, 0, 44), UDim2.new(0.55, 4, 1, -50))
	local follow = UI.Button(frame, "Select an adult to follow", colors.Gray, UDim2.new(1, -36, 0, 44), UDim2.new(0, 18, 1, -50))
	follow.Name = "ToggleFollowerButton"
	bench.TextSize, view.TextSize, follow.TextSize = 16, 16, 16
	-- Keep native-size controls in a scrollable body when the viewport is short.
	-- The close button stays outside this body and is always reachable.
	local body = Instance.new("ScrollingFrame")
	body.Name = "InventoryContent"
	body.Position = UDim2.fromOffset(0, 54)
	body.Size = UDim2.new(1, 0, 1, -62)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 5
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.Parent = frame
	for _, item in { counts, auto, collectionTitle, slotTitle, collection, slots, hint, bench, view, follow } do item.Parent = body end
	local nativeScale = Instance.new("UIScale")
	nativeScale.Name = "NativeInventoryScale"
	nativeScale.Parent = frame
	local globalScale = ui.Gui:FindFirstChildOfClass("UIScale")
	local function resize()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local topLeft, bottomRight = Vector2.zero, Vector2.zero
		pcall(function() topLeft, bottomRight = GuiService:GetGuiInset() end)
		local viewport = camera.ViewportSize - topLeft - bottomRight
		nativeScale.Scale = if globalScale then 1 / math.max(0.01, globalScale.Scale) else 1
		local width, height = math.min(740, math.max(1, viewport.X - 16)), math.min(600, math.max(1, viewport.Y - 16))
		frame.Size = UDim2.fromOffset(width, height)
		title.TextSize = if width < 520 then 22 else 30
		if width < 520 then
			auto.Size, auto.Position = UDim2.fromOffset(132, 44), UDim2.new(1, -144, 0, 2)
			counts.Size, counts.Position, counts.TextSize = UDim2.new(1, -164, 0, 48), UDim2.fromOffset(12, 0), 14
			collectionTitle.Position, collectionTitle.Size = UDim2.fromOffset(12, 52), UDim2.new(1, -24, 0, 26)
			collection.Position, collection.Size = UDim2.fromOffset(12, 82), UDim2.new(1, -24, 0, 200)
			slotTitle.Position, slotTitle.Size = UDim2.fromOffset(12, 288), UDim2.new(1, -24, 0, 26)
			slots.Position, slots.Size = UDim2.fromOffset(12, 318), UDim2.new(1, -24, 0, 200)
			hint.Position, hint.Size = UDim2.fromOffset(12, 524), UDim2.new(1, -24, 0, 52)
			bench.Position, bench.Size = UDim2.fromOffset(12, 582), UDim2.new(0.5, -18, 0, 44)
			view.Position, view.Size = UDim2.new(0.5, 6, 0, 582), UDim2.new(0.5, -18, 0, 44)
			follow.Position, follow.Size = UDim2.fromOffset(12, 632), UDim2.new(1, -24, 0, 44)
			body.CanvasSize = UDim2.fromOffset(0, 684)
		else
			local contentHeight = math.max(450, height - 62)
			auto.Size, auto.Position = UDim2.fromOffset(192, 44), UDim2.new(1, -210, 0, 2)
			counts.Size, counts.Position, counts.TextSize = UDim2.new(1, -240, 0, 42), UDim2.fromOffset(18, 0), 17
			collectionTitle.Position, collectionTitle.Size = UDim2.fromOffset(18, 52), UDim2.new(0.55, -22, 0, 28)
			slotTitle.Position, slotTitle.Size = UDim2.new(0.55, 4, 0, 52), UDim2.new(0.45, -22, 0, 28)
			collection.Position, collection.Size = UDim2.fromOffset(18, 88), UDim2.new(0.55, -22, 0, contentHeight - 232)
			slots.Position, slots.Size = UDim2.new(0.55, 4, 0, 88), UDim2.new(0.45, -22, 0, contentHeight - 232)
			hint.Position, hint.Size = UDim2.fromOffset(18, contentHeight - 138), UDim2.new(1, -36, 0, 34)
			bench.Position, bench.Size = UDim2.fromOffset(18, contentHeight - 98), UDim2.new(0.55, -22, 0, 44)
			view.Position, view.Size = UDim2.new(0.55, 4, 0, contentHeight - 98), UDim2.new(0.45, -22, 0, 44)
			follow.Position, follow.Size = UDim2.fromOffset(18, contentHeight - 48), UDim2.new(1, -36, 0, 44)
			body.CanvasSize = UDim2.fromOffset(0, contentHeight)
		end
	end
	local cameraConnection: RBXScriptConnection? = nil
	local function connectCamera()
		if cameraConnection then cameraConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
		resize()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)
	if globalScale then globalScale:GetPropertyChangedSignal("Scale"):Connect(resize) end
	connectCamera()
	local selectedId: string? = nil
	local controller = { Frame = frame }
	local function selected(): any
		local state = getState()
		for _, monster in if state then state.Monsters or {} else {} do
			if monster.Id == selectedId then return monster end
		end
		return nil
	end
	local function available(monster: any): boolean
		return monster ~= nil and monster.Available ~= false and not monster.Carried and not monster.InTrade
	end
	local function clearRows(scroll: ScrollingFrame)
		for _, child in scroll:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	end
	function controller.Refresh()
		if not frame.Visible then return end
		local state = getState()
		if not state then return end
		local chosen = selected()
		if not chosen then selectedId = nil end
		local rows = table.clone(state.Monsters or {})
		table.sort(rows, function(a, b)
			local incomeA, incomeB = a.ActualIncome or a.Production or 0, b.ActualIncome or b.Production or 0
			if incomeA ~= incomeB then return incomeA > incomeB end
			return a.Id < b.Id
		end)
		local placed, benched = 0, 0
		local occupants = {}
		for _, monster in rows do
			if monster.Slot > 0 then placed += 1; occupants[monster.Slot] = monster else benched += 1 end
		end
		local eggs = {}
		for _, egg in state.Eggs or {} do if egg.Slot and egg.Slot > 0 then eggs[egg.Slot] = true end end
		counts.Text = string.format("%d owned  ·  %d placed  ·  %d on bench", #rows, placed, benched)
		local collectionPosition, slotsPosition = collection.CanvasPosition, slots.CanvasPosition
		local focused = GuiService.SelectedObject
		local focusParent = if focused then focused.Parent else nil
		local focusName = if focused then focused.Name else nil
		clearRows(collection)
		clearRows(slots)
		for index, monster in rows do
			local status = if monster.Carried then "Carried" elseif monster.InTrade then "In trade" elseif monster.Slot > 0 then "Slot " .. monster.Slot else "Bench"
			if monster.Following then status ..= " · Following" end
			local text = string.format("%s  ·  Lv %d\n%s  ·  %s%s/s", monster.DisplayName or monster.Species, monster.Level, status, if monster.Slot > 0 then "" else "Potential ", MonsterMath.FormatNumber(monster.ActualIncome or monster.Production or 0))
			local row = UI.Button(collection, text, if selectedId == monster.Id then colors.Blue else colors.PanelLight, UDim2.new(1, 0, 0, 68), UDim2.new())
			row.Name = monster.Id
			row.TextSize = 16
			row.LayoutOrder = index
			row.Activated:Connect(function() selectedId = monster.Id; controller.Refresh() end)
		end
		if #rows == 0 then
			UI.Label(collection, "Collect a monster from the zones and carry it home. Extra monsters stay safe on your bench.", UDim2.new(1, 0, 0, 110), UDim2.new(), 17).TextColor3 = colors.SubText
		end
		for slot = 1, state.MaxSlots or 0 do
			local unlocked = slot <= (state.UnlockedSlots or 0)
			local occupant = occupants[slot]
			local slotAvailable = unlocked and not eggs[slot] and (not occupant or available(occupant))
			local name = if not unlocked then "Locked" elseif eggs[slot] then "Egg hatching" elseif occupant then occupant.DisplayName else "Empty"
			local action = if chosen and slotAvailable and available(chosen) then (if occupant and occupant.Id ~= chosen.Id then "Swap" else "Place") else ""
			local row = UI.Button(slots, string.format("%d  ·  %s\n%s", slot, name, action), if not unlocked then colors.Gray elseif occupant then colors.PanelLight else colors.Panel, UDim2.new(1, 0, 0, 62), UDim2.new())
			row.Name = "Slot" .. slot
			row.TextSize = 16
			row.LayoutOrder = slot
			row.Activated:Connect(function()
				local current = selected()
				if current and available(current) and slotAvailable then remotes.PlaceMonster:FireServer(current.Id, slot) end
			end)
		end
		collection.CanvasPosition, slots.CanvasPosition = collectionPosition, slotsPosition
		local canBench = chosen ~= nil and available(chosen) and chosen.Slot > 0
		bench.Active = canBench
		bench.Selectable = canBench
		bench.BackgroundColor3 = if canBench then colors.Blue else colors.Gray
		view.Active = chosen ~= nil and available(chosen)
		view.Selectable = view.Active
		view.BackgroundColor3 = if view.Active then colors.PanelLight else colors.Gray
		local followerCount = #(state.FollowingIds or {})
		local followerLimit = state.FollowerLimit or Config.Followers.MaxCount
		local minimumLevel = state.FollowerMinLevel or Config.Followers.MinLevel
		local isFollowing = chosen ~= nil and chosen.Following == true
		local canFollow = chosen ~= nil and available(chosen) and chosen.CanFollow == true and followerCount < followerLimit
		follow.Active = isFollowing or canFollow
		follow.Selectable = follow.Active
		follow.BackgroundColor3 = if isFollowing then colors.Green elseif canFollow then colors.Blue else colors.Gray
		follow.Text = if isFollowing then string.format("Stop following · %d/%d", followerCount, followerLimit)
			elseif not chosen then string.format("Select an adult to follow · %d/%d", followerCount, followerLimit)
			elseif chosen.Level < minimumLevel then string.format("Adult Lv %d+ required to follow", minimumLevel)
			elseif not available(chosen) then "Unavailable while carried or in use"
			elseif followerCount >= followerLimit then string.format("%d/%d following · stop one first", followerCount, followerLimit)
			elseif canFollow then string.format("Follow selected · %d/%d · +damage", followerCount, followerLimit)
			else "This monster is unavailable to follow"
		hint.Text = if chosen then "Selected: " .. chosen.DisplayName .. ". Replaced monsters stay in your collection." else "Only placed monsters earn coins. Select one, then tap an unlocked slot."
		local navigation = { auto }
		local close = frame:FindFirstChild("CloseButton")
		if close and close:IsA("GuiButton") then table.insert(navigation, 1, close) end
		for _, scroll in { collection, slots } do
			local buttons = {}
			for _, child in scroll:GetChildren() do if child:IsA("GuiButton") then table.insert(buttons, child) end end
			table.sort(buttons, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			for _, button in buttons do table.insert(navigation, button) end
		end
		if bench.Selectable then table.insert(navigation, bench) end
		if view.Selectable then table.insert(navigation, view) end
		if follow.Selectable then table.insert(navigation, follow) end
		for index, button in navigation do
			button.NextSelectionDown = navigation[index % #navigation + 1]
			button.NextSelectionUp = navigation[(index - 2) % #navigation + 1]
		end
		if (focusParent == collection or focusParent == slots) and focusName then
			GuiService.SelectedObject = focusParent:FindFirstChild(focusName) or auto
		elseif focused == bench and not bench.Selectable or focused == view and not view.Selectable or focused == follow and not follow.Selectable then
			GuiService.SelectedObject = auto
		end
	end
	function controller.Open()
		UI.Open(ui, frame)
		controller.Refresh()
		if game:GetService("UserInputService").GamepadEnabled then GuiService.SelectedObject = auto end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function() if frame.Visible then controller.Refresh() end end)
	auto.Activated:Connect(function() remotes.AutoPlaceMonsters:FireServer() end)
	bench.Activated:Connect(function()
		local monster = selected()
		if available(monster) and monster.Slot > 0 then remotes.BenchMonster:FireServer(monster.Id) end
	end)
	view.Activated:Connect(function()
		local monster = selected()
		if openMonster and available(monster) then openMonster(monster.Id) end
	end)
	follow.Activated:Connect(function()
		local monster = selected()
		local state = getState()
		local hasCapacity = state and #(state.FollowingIds or {}) < (state.FollowerLimit or Config.Followers.MaxCount)
		if monster and (monster.Following == true or available(monster) and monster.CanFollow == true and hasCapacity) then
			remotes.ToggleFollower:FireServer(monster.Id)
		end
	end)
	return controller
end

return MonsterInventory
