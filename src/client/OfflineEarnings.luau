--!strict
-- A historical receipt for server-calculated offline income. Never claims coins.
-- Compact card: pops in, glowing border, bobbing coin, count-up amount, drifting sparkles, shine on the amount plate.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GuiTheme = require(script.Parent.GuiTheme)
local MonsterMath = require(game:GetService("ReplicatedStorage").Shared.MonsterMath)
local COLORS = GuiTheme.Colors

export type Controller = {
	Update: (state: any) -> (),
	Destroy: () -> (),
}

local OfflineEarnings = {}

local GOLD = Color3.fromRGB(255, 205, 80)
local GOLD_LIGHT = Color3.fromRGB(255, 240, 170)
local INK = Color3.fromRGB(12, 16, 31)

local function nonNegative(value: any): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.max(0, value)
end

local function exactCoins(value: number): string
	local digits = string.format("%.0f", math.floor(value))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	local result = grouped:gsub("^,", "")
	return result
end

local function awayTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	if minutes < 1 then return "under 1m" end
	local days = math.floor(minutes / 1440)
	local hours = math.floor(minutes / 60) % 24
	local remainder = minutes % 60
	if days > 0 then return string.format("%dd %dh", days, hours) end
	if hours > 0 then return string.format("%dh %dm", hours, remainder) end
	return string.format("%dm", remainder)
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function label(parent: Instance, name: string, text: string, fontSize: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.FredokaOne
	item.TextSize = fontSize
	item.Text = text
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.ZIndex = 3
	item.Parent = parent
	return item
end

function OfflineEarnings.Create(playerGui: PlayerGui): Controller
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfflineEarnings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 30
	gui.Parent = playerGui

	local bounds = Instance.new("Frame")
	bounds.Name = "SafeBounds"
	bounds.BackgroundTransparency = 1
	bounds.Size = UDim2.fromScale(1, 1)
	bounds.Parent = gui

	local seenIds: { [string]: boolean } = {}
	local currentCard: Frame? = nil
	local stopCard: (() -> ())? = nil
	local destroyed = false
	local controller = {} :: Controller

	local function dismiss()
		if stopCard then stopCard(); stopCard = nil end
		if currentCard then currentCard:Destroy(); currentCard = nil end
	end

	function controller.Update(state: any)
		if destroyed or type(state) ~= "table" then return end
		local receipt = state.OfflineEarnings
		if type(receipt) ~= "table" or type(receipt.Id) ~= "string" or receipt.Id == "" then return end
		if seenIds[receipt.Id] then return end
		local earned = math.floor(nonNegative(receipt.CoinsEarned))
		local grown = math.floor(nonNegative(receipt.MonstersGrown))
		local seconds = nonNegative(receipt.SecondsAway)
		if seconds <= 0 or (earned < 1 and grown < 1) then return end
		seenIds[receipt.Id] = true
		dismiss()

		local pending = math.floor(nonNegative(receipt.CollectiblePending))
		local WIDTH, HEIGHT = 300, 204

		local card = Instance.new("Frame")
		card.Name = "OfflineReceipt"
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromOffset(WIDTH, HEIGHT)
		card.BackgroundColor3 = Color3.fromRGB(26, 22, 66)
		card.BorderSizePixel = 0
		card:SetAttribute("ReceiptId", receipt.Id)
		card:SetAttribute("CoinsEarned", earned)
		card:SetAttribute("CollectibleOnArrival", pending)
		card.Parent = bounds
		currentCard = card
		corner(card, 16)
		local cardFill = Instance.new("UIGradient")
		cardFill.Color = ColorSequence.new(Color3.fromRGB(46, 38, 108), Color3.fromRGB(18, 14, 46))
		cardFill.Rotation = 90
		cardFill.Parent = card
		local border = Instance.new("UIStroke")
		border.Thickness = 2.5
		border.Color = Color3.new(1, 1, 1)
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Parent = card
		local borderGradient = Instance.new("UIGradient")
		borderGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 40)),
			ColorSequenceKeypoint.new(0.4, GOLD_LIGHT),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 120, 200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 40)),
		})
		borderGradient.Parent = border
		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = card

		-- header
		local title = label(card, "Title", "WELCOME BACK!", 20, GOLD_LIGHT)
		title.Position = UDim2.fromOffset(16, 10)
		title.Size = UDim2.new(1, -110, 0, 24)
		local badge = Instance.new("Frame")
		badge.Name = "Status"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -14, 0, 12)
		badge.Size = UDim2.fromOffset(72, 20)
		badge.BackgroundColor3 = Color3.fromRGB(14, 12, 36)
		badge.BorderSizePixel = 0
		badge.ZIndex = 3
		badge.Parent = card
		corner(badge, 10)
		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = COLORS.Green
		badgeStroke.Thickness = 1.2
		badgeStroke.Parent = badge
		local away = label(badge, "AwayDuration", "🌙 " .. awayTime(seconds), 12, COLORS.Green)
		away.Size = UDim2.fromScale(1, 1)
		away.TextXAlignment = Enum.TextXAlignment.Center

		-- amount plate
		local hero = Instance.new("Frame")
		hero.Name = "Earnings"
		hero.Position = UDim2.fromOffset(12, 42)
		hero.Size = UDim2.new(1, -24, 0, 68)
		hero.BackgroundColor3 = Color3.fromRGB(12, 10, 34)
		hero.BackgroundTransparency = 0.1
		hero.BorderSizePixel = 0
		hero.ClipsDescendants = true
		hero.ZIndex = 2
		hero.Parent = card
		corner(hero, 12)
		local heroStroke = Instance.new("UIStroke")
		heroStroke.Color = GOLD
		heroStroke.Thickness = 1.5
		heroStroke.Transparency = 0.35
		heroStroke.Parent = hero

		local coin = GuiTheme.Icon(hero, "Coins", UDim2.fromOffset(46, 46), UDim2.fromOffset(12, 11))
		coin.ZIndex = 4
		local caption = label(hero, "EarningsCaption", "YOUR MONSTERS EARNED", 10, Color3.fromRGB(190, 180, 240))
		caption.Position = UDim2.fromOffset(68, 6)
		caption.Size = UDim2.new(1, -78, 0, 14)
		local amount = label(hero, "EarnedAmount", "+0", 34, GOLD)
		amount.Position = UDim2.fromOffset(68, 18)
		amount.Size = UDim2.new(1, -78, 0, 34)
		amount.TextScaled = true
		amount.TextStrokeColor3 = Color3.fromRGB(90, 40, 0)
		amount.TextStrokeTransparency = 0.35
		amount:SetAttribute("ExactAmount", exactCoins(earned))
		local amountLimit = Instance.new("UITextSizeConstraint")
		amountLimit.MinTextSize = 14
		amountLimit.MaxTextSize = 34
		amountLimit.Parent = amount
		local unit = label(hero, "Currency", "coins while you were away", 11, Color3.fromRGB(235, 230, 255))
		unit.Position = UDim2.fromOffset(68, 50)
		unit.Size = UDim2.new(1, -78, 0, 14)

		local shine = Instance.new("Frame")
		shine.AnchorPoint = Vector2.new(0.5, 0.5)
		shine.Size = UDim2.new(0, 36, 2.4, 0)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.82
		shine.BorderSizePixel = 0
		shine.Rotation = 18
		shine.ZIndex = 5
		shine.Parent = hero
		local shineGradient = Instance.new("UIGradient")
		shineGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		shineGradient.Parent = shine

		-- pending line
		local pendingCaption = label(card, "PendingCaption", "READY AT YOUR STANDS", 10, Color3.fromRGB(190, 180, 240))
		pendingCaption.Position = UDim2.fromOffset(18, 120)
		pendingCaption.Size = UDim2.new(0.5, -18, 0, 12)
		local pendingAmount = label(card, "PendingAmount", MonsterMath.FormatNumber(pending) .. " coins", 18, COLORS.Text)
		pendingAmount.Position = UDim2.fromOffset(18, 133)
		pendingAmount.Size = UDim2.new(0.5, -18, 0, 20)
		pendingAmount:SetAttribute("ExactAmount", exactCoins(pending))
		local growth = if grown > 0 then string.format("🌱 %d monster%s grew", grown, if grown == 1 then "" else "s") else "Auto-collect may have banked it"
		local details = label(card, "CollectionHint", growth, 11, Color3.fromRGB(210, 205, 240))
		details.AnchorPoint = Vector2.new(1, 0)
		details.Position = UDim2.new(1, -16, 0, 122)
		details.Size = UDim2.new(0.5, -4, 0, 34)
		details.TextXAlignment = Enum.TextXAlignment.Right
		details.TextWrapped = true
		details.TextYAlignment = Enum.TextYAlignment.Center

		-- button
		local close = Instance.new("TextButton")
		close.Name = "Dismiss"
		close.Text = "GOT IT"
		close.Font = Enum.Font.FredokaOne
		close.TextSize = 18
		close.TextColor3 = Color3.fromRGB(12, 44, 20)
		close.BackgroundColor3 = COLORS.Green
		close.BorderSizePixel = 0
		close.AnchorPoint = Vector2.new(0.5, 1)
		close.Position = UDim2.new(0.5, 0, 1, -10)
		close.Size = UDim2.new(1, -24, 0, 32)
		close.ZIndex = 3
		close:SetAttribute("AccessibleName", "Dismiss offline earnings receipt")
		close.Parent = card
		corner(close, 10)
		local closeBorder = Instance.new("UIStroke")
		closeBorder.Color = INK
		closeBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		closeBorder.Thickness = 2
		closeBorder.Parent = close
		local closeGradient = Instance.new("UIGradient")
		closeGradient.Color = ColorSequence.new(Color3.fromRGB(150, 255, 120), Color3.fromRGB(40, 190, 50))
		closeGradient.Rotation = 90
		closeGradient.Parent = close
		GuiTheme.ButtonFeedback(close, closeBorder)

		-- sparkles drifting around the plate
		local sparkles: { Frame } = {}
		for index = 1, 5 do
			local sparkle = Instance.new("Frame")
			sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
			sparkle.Size = UDim2.fromOffset(6 + index % 3 * 2, 6 + index % 3 * 2)
			sparkle.Rotation = 45
			sparkle.BackgroundColor3 = GOLD_LIGHT
			sparkle.BorderSizePixel = 0
			sparkle.ZIndex = 6
			sparkle.Parent = hero
			sparkles[index] = sparkle
		end

		-- fit small screens
		local function layout()
			local viewport = bounds.AbsoluteSize
			local fit = math.min(1, math.max(1, viewport.X - 24) / WIDTH, math.max(1, viewport.Y - 24) / HEIGHT)
			card:SetAttribute("FitScale", fit)
		end
		local layoutConnection = bounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		layout()

		local started = os.clock()
		local frameConnection = RunService.RenderStepped:Connect(function()
			local now = os.clock() - started
			borderGradient.Rotation = (now * 80) % 360
			coin.Position = UDim2.fromOffset(12, 11 + math.sin(now * 3.2) * 3)
			coin.Rotation = math.sin(now * 2.1) * 6
			shine.Position = UDim2.new(-0.1 + ((now * 0.5) % 1.8) * 0.75, 0, 0.5, 0)
			for index, sparkle in sparkles do
				local phase = now * (0.7 + index * 0.18) + index * 1.9
				sparkle.Position = UDim2.new(0.25 + (index - 1) * 0.17, math.sin(phase * 1.3) * 8, 0.15 + 0.7 * (0.5 + 0.5 * math.sin(phase)), 0)
				sparkle.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(phase * 2))
			end
		end)

		-- pop in
		local fit = (card:GetAttribute("FitScale") :: number?) or 1
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()

		local counter = Instance.new("NumberValue")
		local counterConnection = counter.Changed:Connect(function(value: number)
			amount.Text = "+" .. MonsterMath.FormatNumber(math.min(earned, value))
		end)
		local countTween = TweenService:Create(counter, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = earned })
		local completedConnection: RBXScriptConnection? = nil
		completedConnection = countTween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed then
				amount.Text = "+" .. MonsterMath.FormatNumber(earned)
				-- a little pulse when the number lands
				local pulse = Instance.new("UIScale")
				pulse.Parent = amount
				TweenService:Create(pulse, TweenInfo.new(0.12), { Scale = 1.12 }):Play()
				task.delay(0.12, function()
					TweenService:Create(pulse, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end)
			end
			counterConnection:Disconnect()
			if completedConnection then completedConnection:Disconnect(); completedConnection = nil end
			counter:Destroy()
		end)
		local closeConnection = close.Activated:Connect(dismiss)
		stopCard = function()
			layoutConnection:Disconnect()
			frameConnection:Disconnect()
			closeConnection:Disconnect()
			if completedConnection then completedConnection:Disconnect(); completedConnection = nil end
			counterConnection:Disconnect()
			countTween:Cancel()
			counter:Destroy()
		end
		countTween:Play()
	end

	function controller.Destroy()
		if destroyed then return end
		destroyed = true
		dismiss()
		gui:Destroy()
	end
	gui.Destroying:Connect(function()
		destroyed = true
		dismiss()
	end)

	return controller
end

return OfflineEarnings
