--!strict
-- Halloween event client: event timers, the Pumpkin Merchant shop panel and the pumpkin hint arrow.
-- The server owns every rule; this module only displays state and sends item ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local HalloweenLogic = require(ReplicatedStorage.Shared.HalloweenLogic)
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

	-- Event timers (top centre; the Candy amount lives in the authored CandyCounter GUI, see CandyCounter.luau) ---------------------------------------
	local pill = Instance.new("Frame")
	pill.Name = "HalloweenCandy"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 58)
	pill.Size = UDim2.fromOffset(300, 28)
	pill.BackgroundColor3 = COLORS.Panel
	pill.Visible = false
	pill.Parent = ui.Gui
	UI.Corner(pill, 10)
	UI.Stroke(pill, Color3.fromRGB(255, 140, 40), 2)
	local timerLabel = UI.Label(pill, "", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(8, 2), 14)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.TextColor3 = COLORS.SubText

	-- Pumpkin hint ----------------------------------------------------------------------------------
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "PumpkinHint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.Position = UDim2.new(0.5, 0, 0, 92)
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
	local frame, title = UI.Panel(ui.Gui, "HalloweenShop", UDim2.fromOffset(640, 500), "🎃 Pumpkin Merchant", Color3.fromRGB(255, 150, 50))
	table.insert(ui.Panels, frame)
	-- Draw the shop above the other HUD frames (the paw icon frame etc.) without touching them.
	frame.ZIndex = 100
	-- Other ScreenGuis (e.g. the golden-paw "inv" button) share DisplayOrder 0 and are created later, so they
	-- would draw over this panel. Lift our whole ScreenGui above them only while the shop is open
	-- (still below OfflineEarnings 30 / Settings 50).
	local baseDisplayOrder = ui.Gui.DisplayOrder
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		ui.Gui.DisplayOrder = if frame.Visible then math.max(baseDisplayOrder, 10) else baseDisplayOrder
	end)
	local balance = UI.Label(frame, "", UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, 50), 18)
	balance.Name = "Balance"
	balance.TextXAlignment = Enum.TextXAlignment.Left
	balance.TextColor3 = COLORS.SubText
	local convertNote = UI.Label(frame, "", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 72), 14)
	convertNote.Name = "ConvertNote"
	convertNote.TextXAlignment = Enum.TextXAlignment.Left
	convertNote.TextColor3 = COLORS.SubText
	convertNote.TextTruncate = Enum.TextTruncate.AtEnd
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.Position = UDim2.fromOffset(12, 98)
	scroll.Size = UDim2.new(1, -24, 1, -110)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local cards: { [string]: { Frame: Frame, Desc: TextLabel, Button: TextButton } } = {}
	for index, entry in sortedItems() do
		local item = entry.Item
		local card = Instance.new("Frame")
		card.Name = entry.Id
		card.LayoutOrder = index
		card.Size = UDim2.new(1, -12, 0, 76)
		card.BackgroundColor3 = COLORS.PanelLight
		card.Parent = scroll
		UI.Corner(card, 8)
		UI.Stroke(card, item.Color, 2)
		local name = UI.Label(card, item.Name .. string.format("  <font color='#FFAA3C'>🍬 %s</font>", tostring(item.Cost)), UDim2.new(1, -190, 0, 28), UDim2.fromOffset(12, 4), 22)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = item.Color
		local desc = UI.Label(card, item.Description, UDim2.new(1, -190, 0, 40), UDim2.fromOffset(12, 32), 15)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextColor3 = COLORS.SubText
		local buy = UI.Button(card, "Buy", COLORS.Green, UDim2.fromOffset(150, 48), UDim2.new(1, -162, 0.5, -24))
		buy.TextSize = 18
		cards[entry.Id] = { Frame = card, Desc = desc, Button = buy }
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

	local function refreshShop()
		if not state then
			return
		end
		balance.Text = string.format("🍬 You have %d Candy", state.Candy)
		convertNote.Text = string.format("Leftover Candy turns into %d coins each when the event ends", state.ConvertRate or settings.CandyToCoinRate)
		for id, card in cards do
			local item = settings.Items[id]
			local owned = state.Owned and state.Owned[id] == true
			local cosmetic = item.Kind == "Hat" or item.Kind == "Trail" or item.Kind == "Aura" or item.Kind == "Title"
			if cosmetic and owned then
				local equipped = state.Equipped and state.Equipped[item.Kind] == id
				card.Button.Text = if equipped then "Unequip" else "Equip"
				card.Button.BackgroundColor3 = if equipped then COLORS.Orange else COLORS.Blue
			elseif item.Unique and owned then
				card.Button.Text = "Owned"
				card.Button.BackgroundColor3 = COLORS.Gray
			else
				local affordable = state.Candy >= item.Cost
				card.Button.Text = if affordable then "Buy 🍬 " .. item.Cost else "Need 🍬 " .. item.Cost
				card.Button.BackgroundColor3 = if affordable then COLORS.Green else COLORS.Gray
			end
		end
	end

	local function refreshPill()
		if not state or not state.Enabled then
			pill.Visible = false
			hintLabel.Visible = false
			return
		end
		pill.Visible = true
		local elapsed = os.clock() - stateAt
		local parts = {}
		local boost = (state.BoostLeft or 0) - elapsed
		if boost > 0 then
			table.insert(parts, "2x cash " .. clock(boost))
		end
		if (state.InvadersAlive or 0) > 0 then
			table.insert(parts, "👹 " .. state.InvadersAlive .. " Mothers!")
		else
			table.insert(parts, "Invasion " .. clock((state.NextInvasionIn or 0) - elapsed))
		end
		if (state.HuntRemaining or 0) > 0 then
			table.insert(parts, "🎃 " .. state.HuntRemaining .. " left")
		else
			table.insert(parts, "Hunt " .. clock((state.NextPumpkinsIn or 0) - elapsed))
		end
		timerLabel.Text = table.concat(parts, " · ")
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
			local events = workspace:FindFirstChild("HalloweenEvent")
			local merchant = events and events:FindFirstChild("PumpkinMerchant")
			local anchor = merchant and merchant:FindFirstChild("Torso")
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
