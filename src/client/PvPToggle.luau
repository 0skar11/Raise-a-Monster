--!strict
-- Left-edge button rail: the Studio-authored Shop / Gifts / Trade / Monsters buttons plus the PvP toggle,
-- stacked top-down and centred vertically on the left edge. The authored buttons keep their own artwork and size; only their
-- vertical position is managed here, from their own size scale, so the rail stays evenly spaced on every
-- aspect ratio and never runs into the cash counter at the bottom-left.
-- The server owns the PvP flag and the 60s death protection; this only asks for a change and shows PvPState.
local RunService = game:GetService("RunService")

local PvPToggle = {}

local ON_COLOR = Color3.fromRGB(190, 52, 52)
local OFF_COLOR = Color3.fromRGB(52, 140, 80)
local SHIELD_COLOR = Color3.fromRGB(70, 120, 200)

local GAP = 0.25 -- of the first button's height
local REFERENCE_HEIGHT = 70 -- the first authored button at the size the PvP button was designed against

type Rail = { Gui: string, Path: { string } }
local RAIL: { Rail } = {
	{ Gui = "ShopGui", Path = { "shop" } },
	{ Gui = "ShopGui", Path = { "gifts" } },
	{ Gui = "ShopGui", Path = { "trade" } },
	{ Gui = "inv", Path = { "Group 1" } },
}

function PvPToggle.Start(remotes: { [string]: RemoteEvent }, playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PvPToggle", false, 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- same safe area as the authored launchers
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "PvPButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 18
	button.TextWrapped = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = true
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = Color3.fromRGB(255, 220, 100), 2
	stroke.Parent = button

	local function find(entry: Rail): GuiObject?
		local current: Instance? = playerGui:FindFirstChild(entry.Gui)
		if not current or not current:IsA("ScreenGui") then return nil end
		for _, name in entry.Path do
			current = current:FindFirstChild(name)
			if not current then return nil end
		end
		return if (current :: Instance):IsA("GuiObject") then current :: GuiObject else nil
	end

	-- Height of an authored button from its own size scale (not AbsoluteSize, so hover UIScale pops don't shift the rail).
	local function heightOf(item: GuiObject, screen: Vector2): number
		local size = item.Size
		return math.min(size.X.Scale * screen.X + size.X.Offset, size.Y.Scale * screen.Y + size.Y.Offset)
	end

	local function place()
		local screen = gui.AbsoluteSize
		if screen.Y <= 0 then return end
		-- Pass 1: measure the rail (authored buttons + the PvP button) so it can be centred as one block.
		local items: { GuiObject } = {}
		local heights: { number } = {}
		for _, entry in RAIL do
			local item = find(entry)
			if item then
				table.insert(items, item)
				table.insert(heights, heightOf(item, screen))
			end
		end
		local baseHeight = if #heights > 0 then heights[1] else REFERENCE_HEIGHT
		local gap = baseHeight * GAP
		local unit = baseHeight / REFERENCE_HEIGHT
		local pvpWidth = math.max(96, math.round(112 * unit))
		local pvpHeight = math.max(34, math.round(44 * unit))
		local total = pvpHeight
		for _, height in heights do total += height + gap end

		-- Pass 2: lay the block out, vertically centred on the screen.
		local y = (screen.Y - total) / 2
		local lastX: UDim = UDim.new(0.0515, 0)
		for index, item in items do
			local height = heights[index]
			local position = item.Position
			local target = UDim2.new(position.X.Scale, position.X.Offset, 0, math.round(y + height / 2))
			if item.Position ~= target then item.Position = target end
			lastX = position.X
			y += height + gap
		end
		button.Size = UDim2.fromOffset(pvpWidth, pvpHeight)
		button.TextSize = math.clamp(math.round(18 * unit), 14, 24)
		-- under the last authored button, on the same x anchor
		button.Position = UDim2.new(lastX.Scale, lastX.Offset, 0, math.round(y))
	end

	local enabled = true
	local protectedUntil = 0

	local function refresh()
		place()
		local left = math.ceil(protectedUntil - os.clock())
		if left > 0 then
			button.Text = string.format("🛡 Protected %ds", left)
			button.BackgroundColor3 = SHIELD_COLOR
		elseif enabled then
			button.Text = "⚔ PvP: ON"
			button.BackgroundColor3 = ON_COLOR
		else
			button.Text = "🕊 PvP: OFF"
			button.BackgroundColor3 = OFF_COLOR
		end
	end

	button.Activated:Connect(function()
		remotes.SetPvP:FireServer(not enabled)
	end)

	remotes.PvPState.OnClientEvent:Connect(function(isEnabled: boolean, protectedSeconds: number)
		enabled = isEnabled
		protectedUntil = os.clock() + protectedSeconds
		refresh()
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		refresh()
	end)
	refresh()
end

return PvPToggle
