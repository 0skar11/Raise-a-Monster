--!strict
-- Admin panel (F4). Built only after the server confirms this player is in Config.Admin.Usernames; the server
-- re-checks every action, so this is just the remote control.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local AdminPanel = {}

local PANEL = Color3.fromRGB(18, 14, 28)
local RAISED = Color3.fromRGB(40, 32, 60)
local GOLD = Color3.fromRGB(255, 190, 60)
local INK = Color3.fromRGB(245, 240, 255)
local GREEN = Color3.fromRGB(34, 120, 78)
local PURPLE = Color3.fromRGB(96, 56, 160)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Size = UDim2.new(1, 0, 0, size + 8)
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.LayoutOrder = order
	item.Parent = parent
	return item
end

local function field(parent: Instance, placeholder: string, order: number): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = RAISED
	box.Font = Enum.Font.Gotham
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(150, 140, 175)
	box.Text = ""
	box.TextColor3 = INK
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.Size = UDim2.new(1, 0, 0, 34)
	box.LayoutOrder = order
	box.Parent = parent
	corner(box, 8)
	return box
end

function AdminPanel.Start(playerGui: PlayerGui, remotes: { [string]: RemoteEvent })
	local built = false
	remotes.AdminAccess.OnClientEvent:Connect(function(allowed: boolean, _names: { string })
		if not allowed or built then
			return
		end
		built = true

		local gui = Instance.new("ScreenGui")
		gui.Name = "AdminPanel"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 90
		gui.IgnoreGuiInset = false
		gui.Enabled = true
		gui.Parent = playerGui

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.AnchorPoint = Vector2.new(1, 0.5)
		panel.Position = UDim2.new(1, -16, 0.5, 0)
		panel.Size = UDim2.fromOffset(330, 470)
		panel.BackgroundColor3 = PANEL
		panel.Visible = false
		panel.Parent = gui
		corner(panel, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD
		stroke.Thickness = 2
		stroke.Parent = panel

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = "🛠 ADMIN PANEL"
		title.TextColor3 = GOLD
		title.TextSize = 20
		title.Position = UDim2.fromOffset(14, 8)
		title.Size = UDim2.new(1, -60, 0, 28)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = panel

		local close = Instance.new("TextButton")
		close.Text = "✕"
		close.Font = Enum.Font.GothamBold
		close.TextSize = 16
		close.TextColor3 = INK
		close.BackgroundColor3 = Color3.fromRGB(150, 40, 60)
		close.Size = UDim2.fromOffset(30, 28)
		close.Position = UDim2.new(1, -40, 0, 8)
		close.Parent = panel
		corner(close, 8)

		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.fromOffset(12, 44)
		scroll.Size = UDim2.new(1, -24, 1, -54)
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollBarThickness = 5
		scroll.Parent = panel
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroll

		local target = field(scroll, "Player name (blank = me)", 1)
		local amount = field(scroll, "Amount (coins / candy / Mothers 3-10)", 2)
		local name = field(scroll, "Egg type or species key (e.g. Lucky, Void_9)", 3)
		local text = field(scroll, "Announcement text", 4)
		local eggs = {}
		for key in Config.Eggs do table.insert(eggs, key) end
		table.sort(eggs)
		label(scroll, "Eggs: " .. table.concat(eggs, ", "), 12, Color3.fromRGB(170, 160, 195), 5)
		label(scroll, "Species keys look like Region_1..10 (Grassland, Desert, Ice, Volcano, Void) or HalloweenGhostSlime / HalloweenSkeletonImp / HalloweenPumpkinKing.", 12, Color3.fromRGB(170, 160, 195), 6)

		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = 7
		grid.Parent = scroll
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0.5, -4, 0, 36)
		gridLayout.CellPadding = UDim2.fromOffset(8, 8)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid

		local buttons = {
			{ "Give coins", "GiveCoins", GREEN },
			{ "Give candy", "GiveCandy", GREEN },
			{ "Give egg", "GiveEgg", GREEN },
			{ "Give monster", "GiveMonster", GREEN },
			{ "Heal", "Heal", PURPLE },
			{ "Go to player", "Goto", PURPLE },
			{ "Bring player", "Bring", PURPLE },
			{ "Announce", "Announce", PURPLE },
			{ "Mother invasion", "StartInvasion", Color3.fromRGB(170, 70, 30) },
			{ "Pumpkin hunt", "StartPumpkinHunt", Color3.fromRGB(170, 70, 30) },
		}
		for order, spec in buttons do
			local button = Instance.new("TextButton")
			button.Text = spec[1]
			button.Font = Enum.Font.GothamBold
			button.TextSize = 14
			button.TextColor3 = INK
			button.BackgroundColor3 = spec[3]
			button.LayoutOrder = order
			button.Parent = grid
			corner(button, 8)
			button.Activated:Connect(function()
				remotes.AdminAction:FireServer(spec[2], {
					Target = target.Text,
					Amount = tonumber(amount.Text),
					Name = name.Text,
					Text = text.Text,
				})
			end)
		end

		-- small launcher so the panel can also be opened with the mouse / on touch
		local launcher = Instance.new("TextButton")
		launcher.Name = "AdminLauncher"
		launcher.Text = "🛠"
		launcher.Font = Enum.Font.GothamBold
		launcher.TextSize = 18
		launcher.TextColor3 = GOLD
		launcher.BackgroundColor3 = PANEL
		launcher.AnchorPoint = Vector2.new(1, 0)
		launcher.Position = UDim2.new(1, -16, 0, 56)
		launcher.Size = UDim2.fromOffset(36, 36)
		launcher.Parent = gui
		corner(launcher, 10)

		local function toggle()
			panel.Visible = not panel.Visible
		end
		launcher.Activated:Connect(toggle)
		close.Activated:Connect(function() panel.Visible = false end)
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
