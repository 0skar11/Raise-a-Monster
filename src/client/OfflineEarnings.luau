--!strict
-- A historical receipt for server-calculated offline income. Never claims coins.
local TweenService = game:GetService("TweenService")

local GuiTheme = require(script.Parent.GuiTheme)
local COLORS = GuiTheme.Colors

export type Controller = {
	Update: (state: any) -> (),
	Destroy: () -> (),
}

local OfflineEarnings = {}

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
	if minutes < 1 then return "less than a minute" end
	local days = math.floor(minutes / 1440)
	local hours = math.floor(minutes / 60) % 24
	local remainder = minutes % 60
	if days > 0 then return string.format("%dd %dh %dm", days, hours, remainder) end
	if hours > 0 then return string.format("%dh %dm", hours, remainder) end
	return string.format("%dm", remainder)
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
	item.ZIndex = 2
	item.Parent = parent
	return item
end

local function surface(parent: Instance, name: string, color: Color3, accent: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame:SetAttribute("PixelAccent", accent)
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(12, 16, 31)
	border.Thickness = 2
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = frame
	GuiTheme.Gloss(frame)
	return frame
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
		local card = surface(bounds, "OfflineReceipt", COLORS.Panel, COLORS.Yellow)
		currentCard = card
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card:SetAttribute("ReceiptId", receipt.Id)
		card:SetAttribute("CoinsEarned", earned)
		card:SetAttribute("CollectibleOnArrival", pending)
		local scale = Instance.new("UIScale")
		scale.Parent = card

		local title = label(card, "Title", "Welcome back!", 26, COLORS.Text)
		local away = label(card, "AwayDuration", "Away for " .. awayTime(seconds), 14, COLORS.SubText)
		local badge = label(card, "Status", "OFFLINE", 11, COLORS.Green)
		badge.TextXAlignment = Enum.TextXAlignment.Right

		local hero = surface(card, "Earnings", COLORS.PanelLight, COLORS.Yellow)
		hero.ZIndex = 2
		local coin = GuiTheme.Icon(hero, "Coins", UDim2.fromOffset(58, 58), UDim2.fromOffset(12, 19))
		coin.ZIndex = 3
		local caption = label(hero, "EarningsCaption", "YOUR MONSTERS EARNED", 11, COLORS.SubText)
		caption.ZIndex = 3
		local amount = label(hero, "EarnedAmount", "+0", 38, COLORS.Yellow)
		amount.ZIndex = 3
		amount.TextScaled = true
		amount:SetAttribute("ExactAmount", exactCoins(earned))
		local amountLimit = Instance.new("UITextSizeConstraint")
		amountLimit.MinTextSize = 14
		amountLimit.MaxTextSize = 38
		amountLimit.Parent = amount
		local unit = label(hero, "Currency", "coins while you were away", 12, COLORS.Text)
		unit.ZIndex = 3

		local pendingCaption = label(card, "PendingCaption", "READY TO COLLECT ON ARRIVAL", 11, COLORS.SubText)
		local pendingAmount = label(card, "PendingAmount", exactCoins(pending) .. " coins", 20, COLORS.Text)
		pendingAmount.TextScaled = true
		local pendingLimit = Instance.new("UITextSizeConstraint")
		pendingLimit.MinTextSize = 12
		pendingLimit.MaxTextSize = 20
		pendingLimit.Parent = pendingAmount
		local growth = if grown > 0 then string.format("%d monster%s grew. ", grown, if grown == 1 then "" else "s") else ""
		local details = label(card, "CollectionHint", growth .. "Collect at your stands. Auto-collect may have banked it.", 13, COLORS.SubText)
		details.TextWrapped = true
		details.TextYAlignment = Enum.TextYAlignment.Top

		local close = Instance.new("TextButton")
		close.Name = "Dismiss"
		close.Text = "Got it"
		close.Font = Enum.Font.FredokaOne
		close.TextSize = 20
		close.TextColor3 = Color3.fromRGB(16, 42, 24)
		close.BackgroundColor3 = COLORS.Green
		close.BorderSizePixel = 0
		close.ZIndex = 2
		close:SetAttribute("AccessibleName", "Dismiss offline earnings receipt")
		close.Parent = card
		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 4)
		closeCorner.Parent = close
		local closeBorder = Instance.new("UIStroke")
		closeBorder.Color = Color3.fromRGB(12, 16, 31)
		closeBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		closeBorder.Thickness = 2
		closeBorder.Parent = close
		GuiTheme.Gloss(close)
		GuiTheme.ButtonFeedback(close, closeBorder)

		local function layout()
			local viewport = bounds.AbsoluteSize
			local compact = viewport.Y < 390
			local height = if compact then 306 else 354
			scale.Scale = math.min(1, math.max(1, viewport.Y - 24) / height)
			local width = math.min(380, math.max(1, viewport.X - 32) / scale.Scale)
			card.Size = UDim2.fromOffset(width, height)
			card.Position = UDim2.fromScale(0.5, 0.5)
			title.Position = UDim2.fromOffset(20, if compact then 12 else 18)
			title.Size = UDim2.new(1, -116, 0, 30)
			title.TextSize = if width < 330 then 23 else 26
			away.Position = UDim2.fromOffset(20, if compact then 42 else 50)
			away.Size = UDim2.new(1, -40, 0, 18)
			badge.Position = UDim2.new(1, -86, 0, if compact then 20 else 28)
			badge.Size = UDim2.fromOffset(66, 16)
			hero.Position = UDim2.fromOffset(16, if compact then 66 else 80)
			hero.Size = UDim2.new(1, -32, 0, if compact then 84 else 100)
			coin.Position = UDim2.fromOffset(12, if compact then 12 else 20)
			coin.Size = UDim2.fromOffset(54, 54)
			caption.Position = UDim2.fromOffset(78, if compact then 8 else 13)
			caption.Size = UDim2.new(1, -90, 0, 16)
			amount.Position = UDim2.fromOffset(78, if compact then 23 else 32)
			amount.Size = UDim2.new(1, -90, 0, if compact then 32 else 38)
			unit.Position = UDim2.fromOffset(78, if compact then 58 else 74)
			unit.Size = UDim2.new(1, -90, 0, 17)
			unit.TextSize = if width < 330 then 11 else 12
			pendingCaption.Position = UDim2.fromOffset(20, if compact then 162 else 194)
			pendingCaption.Size = UDim2.new(1, -40, 0, 16)
			pendingAmount.Position = UDim2.fromOffset(20, if compact then 181 else 214)
			pendingAmount.Size = UDim2.new(1, -40, 0, 24)
			details.Position = UDim2.fromOffset(20, if compact then 211 else 248)
			details.Size = UDim2.new(1, -40, 0, if compact then 30 else 36)
			details.TextSize = if compact then 12 else 13
			close.Position = UDim2.new(0, 16, 1, -58)
			close.Size = UDim2.new(1, -32, 0, 44)
		end
		local layoutConnection = bounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		layout()

		local counter = Instance.new("NumberValue")
		local counterConnection = counter.Changed:Connect(function(value: number)
			amount.Text = "+" .. exactCoins(math.min(earned, value))
		end)
		local countTween = TweenService:Create(counter, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = earned })
		local completedConnection: RBXScriptConnection? = nil
		completedConnection = countTween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed then amount.Text = "+" .. exactCoins(earned) end
			counterConnection:Disconnect()
			if completedConnection then completedConnection:Disconnect(); completedConnection = nil end
			counter:Destroy()
		end)
		local closeConnection = close.Activated:Connect(dismiss)
		stopCard = function()
			layoutConnection:Disconnect()
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
