--!strict
-- Presentation only: the server chooses prizes, validates cooldowns, and grants rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local GuiTheme = require(script.Parent.GuiTheme)

local RewardsArcade = {}
local COLORS = {
	Night = Color3.fromRGB(10, 17, 39), Panel = Color3.fromRGB(16, 30, 61),
	Card = Color3.fromRGB(25, 44, 81), Edge = Color3.fromRGB(66, 98, 145),
	Gold = Color3.fromRGB(255, 198, 69), Pale = Color3.fromRGB(255, 238, 167),
	White = Color3.fromRGB(245, 249, 255), Muted = Color3.fromRGB(162, 181, 210),
	Green = Color3.fromRGB(80, 224, 139), Disabled = Color3.fromRGB(45, 60, 87),
}

export type Options = {
	GetState: () -> any,
	ClaimDaily: () -> (),
	Spin: () -> (),
}
export type Controller = {
	Refresh: (self: Controller, state: any) -> (),
	ShowSpinResult: (self: Controller, index: number) -> (),
	Destroy: (self: Controller) -> (),
}

local function rounded(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function outline(object: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color, stroke.Thickness = color, thickness
	stroke.Parent = object
	return stroke
end

local function gradient(object: GuiObject, top: Color3, bottom: Color3)
	local sheen = Instance.new("UIGradient")
	sheen.Color = ColorSequence.new(top, bottom)
	sheen.Rotation = 90
	sheen.Parent = object
end

local function frame(parent: Instance, name: string, color: Color3): Frame
	local item = Instance.new("Frame")
	item.Name, item.BorderSizePixel, item.BackgroundColor3 = name, 0, color
	item.Parent = parent
	return item
end

local function text(parent: Instance, name: string, value: string, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name, item.BackgroundTransparency = name, 1
	item.Font = Enum.Font.FredokaOne
	item.Text, item.TextSize, item.TextColor3 = value, size, color
	item.TextWrapped = true
	item.TextStrokeColor3, item.TextStrokeTransparency = COLORS.Night, 0.5
	item.Parent = parent
	return item
end

local function position(object: GuiObject, x: number, y: number, width: number, height: number)
	object.Position, object.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(width, height)
end

local function button(parent: Instance, name: string): TextButton
	local item = Instance.new("TextButton")
	item.Name, item.BorderSizePixel, item.Font = name, 0, Enum.Font.FredokaOne
	item.TextSize, item.TextColor3 = 20, COLORS.Night
	item.TextWrapped, item.AutoButtonColor = true, true
	item.BackgroundColor3 = COLORS.Gold
	item.Parent = parent
	rounded(item, 9)
	local border = outline(item, COLORS.Pale, 2)
	gradient(item, Color3.new(1, 1, 1), Color3.fromRGB(196, 170, 124))
	GuiTheme.ButtonFeedback(item, border)
	return item
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60) end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Native, transparent artwork remains sharp and needs no new uploaded assets.
local function coin(parent: Instance, name: string): Frame
	local group = frame(parent, name, COLORS.Gold)
	group.BackgroundTransparency = 1
	for index = 1, 3 do
		local medal = frame(group, "Coin" .. index, Color3.fromRGB(255, 187, 34))
		medal.Size = UDim2.fromScale(0.62, 0.62)
		medal.Position = UDim2.fromScale(if index == 1 then 0.04 elseif index == 2 then 0.35 else 0.19, if index == 3 then 0.02 else 0.31)
		rounded(medal, 99)
		outline(medal, Color3.fromRGB(255, 235, 131), 2)
		gradient(medal, Color3.fromRGB(255, 226, 91), Color3.fromRGB(221, 130, 17))
		local star = text(medal, "Stamp", "$", 25, Color3.fromRGB(255, 247, 174))
		star.Size = UDim2.fromScale(1, 1)
		star.TextScaled = true
		local inset = Instance.new("UIPadding")
		inset.PaddingTop, inset.PaddingBottom = UDim.new(0.17, 0), UDim.new(0.17, 0)
		inset.Parent = star
	end
	return group
end

local function egg(parent: Instance, name: string, color: Color3): Frame
	local group = frame(parent, name, color)
	group.BackgroundTransparency = 1
	local shell = frame(group, "Shell", color)
	shell.Position, shell.Size = UDim2.fromScale(0.17, 0.05), UDim2.fromScale(0.66, 0.9)
	rounded(shell, 99)
	outline(shell, color:Lerp(Color3.new(1, 1, 1), 0.65), 2)
	gradient(shell, color:Lerp(Color3.new(1, 1, 1), 0.5), color:Lerp(COLORS.Night, 0.25))
	local shine = frame(shell, "Shine", Color3.new(1, 1, 1))
	shine.BackgroundTransparency, shine.Rotation = 0.25, 22
	shine.Size, shine.Position = UDim2.fromScale(0.15, 0.31), UDim2.fromScale(0.23, 0.15)
	rounded(shine, 99)
	local gem = frame(shell, "Gem", color:Lerp(COLORS.Night, 0.32))
	gem.Size, gem.Position, gem.Rotation = UDim2.fromScale(0.28, 0.22), UDim2.fromScale(0.46, 0.52), 30
	rounded(gem, 3)
	return group
end

-- Each arc is a triangle fan, built from two right-triangle WedgeParts per triangle.
-- The camera faces the XY plane, so there is no perspective distortion across the disc.
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3)
	local ab, ac, bc = b - a, c - a, c - b
	if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then a, c = c, a
	elseif ac.Magnitude > bc.Magnitude then a, b = b, a end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up, back = bc:Cross(right).Unit, bc.Unit
	local height = math.abs(ab:Dot(up))
	for index = 1, 2 do
		local part = Instance.new("WedgePart")
		part.Name, part.Anchored, part.CanCollide, part.CastShadow = "PrizeWedge", true, false, false
		part.Material, part.Color = Enum.Material.SmoothPlastic, color
		part.Size = Vector3.new(0.02, height, math.abs((if index == 1 then ab else ac):Dot(back)))
		part.CFrame = if index == 1 then CFrame.fromMatrix((a + b) / 2, right, up, back)
			else CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		part.Parent = parent
	end
end

function RewardsArcade.Mount(panel: Frame, options: Options): Controller
	local connections: { RBXScriptConnection } = {}
	local destroyed, spinning, pendingSpin, pendingDaily = false, false, false, false
	local lastState: any = nil
	local spinTween: Tween? = nil
	local spinTarget = 0
	local resultIndex: number? = nil
	local animationVersion = 0
	local prizes = Config.Spin.Prizes
	local step = if #prizes > 0 then 360 / #prizes else 360
	local maxDays = math.max(1, Config.Daily.MaxStreak)
	local controller = {} :: any

	panel.BackgroundColor3 = COLORS.Night
	panel.ZIndex = 30
	for _, child in panel:GetChildren() do
		if child.Name == "Ornament" or child.Name == "PixelInset" or child:IsA("UIGradient") then child:Destroy()
		elseif child:IsA("TextLabel") then child.Visible = false
		elseif child:IsA("UIStroke") then child.Color, child.Thickness = COLORS.Gold, 2 end
	end
	local root = frame(panel, "RewardsArcade", COLORS.Night)
	root.BackgroundTransparency, root.Size = 1, UDim2.fromScale(1, 1)
	local nativeScale = Instance.new("UIScale")
	nativeScale.Name, nativeScale.Parent = "NativeRewardsScale", panel
	local screen = panel:FindFirstAncestorOfClass("ScreenGui")
	local inheritedScale = if screen then screen:FindFirstChildOfClass("UIScale") else nil

	local header = frame(root, "Header", COLORS.Panel)
	rounded(header, 10)
	gradient(header, Color3.fromRGB(43, 61, 94), COLORS.Panel)
	local headerLine = frame(header, "GoldRule", COLORS.Gold)
	headerLine.Position, headerLine.Size = UDim2.new(0, 8, 1, -2), UDim2.new(1, -16, 0, 2)
	local gift = Instance.new("ImageLabel")
	local giftCell = GuiTheme.IconRects.Gift
	local atlas = GuiTheme.Atlas
	gift.Name, gift.BackgroundTransparency = "GiftArt", 1
	gift.Image, gift.ScaleType = atlas.Image, Enum.ScaleType.Fit
	gift.ImageRectOffset = Vector2.new(giftCell.X * atlas.CellSize.X, giftCell.Y * atlas.CellSize.Y)
	gift.ImageRectSize, gift.Size, gift.Position = atlas.CellSize, UDim2.fromOffset(56, 54), UDim2.fromOffset(10, 6)
	gift.Parent = header
	local heading = text(header, "Heading", "REWARDS", 31, COLORS.Pale)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local subtitle = text(header, "Subtitle", "YOUR DAILY LOOT DROP", 11, COLORS.Muted)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	local close = panel:FindFirstChild("CloseButton")
	if close and close:IsA("TextButton") then
		close.ZIndex = 10
		close.BackgroundColor3, close.TextColor3, close.TextSize = Color3.fromRGB(197, 43, 79), COLORS.White, 24
	end

	local content = Instance.new("ScrollingFrame")
	content.Name, content.BackgroundTransparency, content.BorderSizePixel = "RewardContent", 1, 0
	content.ScrollBarThickness, content.ScrollBarImageColor3 = 4, COLORS.Gold
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.CanvasSize = UDim2.new()
	content.Parent = root
	local daily = frame(content, "DailyRewards", COLORS.Panel)
	rounded(daily, 10)
	outline(daily, COLORS.Edge, 1)
	local dailyHeading = text(daily, "DailyHeading", "DAILY REWARDS", 21, COLORS.Pale)
	dailyHeading.TextXAlignment = Enum.TextXAlignment.Left
	local dayStatus = text(daily, "DayStatus", "Loading rewards...", 14, COLORS.Muted)
	dayStatus.TextXAlignment = Enum.TextXAlignment.Right

	local track = Instance.new("ScrollingFrame")
	track.Name, track.BackgroundTransparency, track.BorderSizePixel = "DayTrack", 1, 0
	track.ScrollBarThickness, track.ScrollBarImageColor3 = 2, COLORS.Gold
	track.ScrollingDirection, track.Parent = Enum.ScrollingDirection.X, daily
	local dayCards: { any } = {}
	for day = 1, maxDays do
		local tile = frame(track, "Day" .. day, COLORS.Card)
		rounded(tile, 8)
		local border = outline(tile, COLORS.Edge, 1)
		gradient(tile, Color3.fromRGB(40, 63, 106), COLORS.Card)
		local art = if day == maxDays then egg(tile, "Egg", Color3.fromRGB(95, 170, 255)) else coin(tile, "Coins")
		local check = text(tile, "Claimed", "✓", 34, COLORS.Green)
		check.Size, check.Position, check.Visible = UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 3), false
		local caption = text(tile, "Caption", "Day " .. day, 14, COLORS.White)
		caption.Size, caption.Position = UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 1, -24)
		dayCards[day] = { Tile = tile, Border = border, Art = art, Check = check, Caption = caption }
	end
	local reward = frame(daily, "NextReward", COLORS.Night)
	rounded(reward, 8)
	outline(reward, COLORS.Edge, 1)
	local rewardArt = coin(reward, "RewardCoins")
	local rewardCaption = text(reward, "RewardCaption", "NEXT REWARD", 12, COLORS.Muted)
	rewardCaption.TextXAlignment = Enum.TextXAlignment.Left
	local rewardValue = text(reward, "RewardValue", "—", 24, COLORS.Gold)
	rewardValue.TextXAlignment = Enum.TextXAlignment.Left
	local rewardEgg = text(reward, "BonusEgg", "", 13, COLORS.Muted)
	rewardEgg.TextXAlignment = Enum.TextXAlignment.Left
	local dailyButton = button(reward, "ClaimDaily")

	local arcade = frame(content, "SpinArcade", COLORS.Panel)
	rounded(arcade, 10)
	outline(arcade, COLORS.Edge, 1)
	gradient(arcade, Color3.fromRGB(25, 33, 75), COLORS.Night)
	local spinHeading = text(arcade, "SpinHeading", "SPIN WHEEL", 23, COLORS.Pale)
	spinHeading.TextXAlignment = Enum.TextXAlignment.Left
	local spinSubtitle = text(arcade, "SpinSubtitle", "ONE FREE SPIN EVERY " .. tostring(math.floor(Config.Spin.Cooldown / 3600)) .. " HOURS", 11, COLORS.Muted)
	spinSubtitle.TextXAlignment = Enum.TextXAlignment.Left

	local wheelMount = frame(arcade, "WheelMount", COLORS.Gold)
	wheelMount.BackgroundTransparency = 1
	local rim = frame(wheelMount, "GoldenRim", Color3.fromRGB(181, 104, 19))
	rim.Size, rim.Position = UDim2.fromScale(0.96, 0.96), UDim2.fromScale(0.02, 0.02)
	rounded(rim, 999)
	outline(rim, COLORS.Pale, 3)
	gradient(rim, Color3.fromRGB(255, 218, 88), Color3.fromRGB(181, 104, 19))
	local wheel = frame(wheelMount, "PrizeDisc", COLORS.Night)
	wheel.AnchorPoint, wheel.Size, wheel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.5, 0.5)
	wheel.BackgroundTransparency = 1
	local viewport = Instance.new("ViewportFrame")
	viewport.Name, viewport.Size, viewport.BackgroundTransparency = "RadialPrizeWedges", UDim2.fromScale(1, 1), 1
	viewport.Ambient, viewport.LightColor = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	viewport.Parent = wheel
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 20
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, 5 / math.tan(math.rad(10))), Vector3.zero)
	camera.Parent, viewport.CurrentCamera = viewport, camera
	local prizeLabels: { Frame } = {}
	for index, prize in prizes do
		local centerAngle = (index - 1) * step
		local segments = math.max(8, math.ceil(120 / #prizes))
		for segment = 1, segments do
			local first = math.rad(centerAngle - step / 2 + (segment - 1) * step / segments)
			local last = math.rad(centerAngle - step / 2 + segment * step / segments)
			triangle(world, Vector3.zero, Vector3.new(math.sin(first), math.cos(first), 0) * 5, Vector3.new(math.sin(last), math.cos(last), 0) * 5, prize.Color)
		end
		local angle = math.rad(centerAngle)
		local labelGroup = frame(wheel, "Prize" .. index, prize.Color)
		labelGroup.BackgroundTransparency = 1
		labelGroup.AnchorPoint, labelGroup.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.29, 0.27)
		labelGroup.Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.325, 0.5 - math.cos(angle) * 0.325)
		table.insert(prizeLabels, labelGroup)
		local art = if prize.Egg then egg(labelGroup, "Egg", prize.Color:Lerp(Color3.new(1, 1, 1), 0.25)) else coin(labelGroup, "Coins")
		art.Size, art.Position = UDim2.fromScale(0.54, 0.58), UDim2.fromScale(0.23, 0)
		local caption = text(labelGroup, "PrizeName", prize.Name, 16, COLORS.Night)
		caption.TextStrokeTransparency = 1
		caption.Size, caption.Position = UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6)
		caption.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize, limit.MaxTextSize, limit.Parent = 8, 17, caption
	end
	table.insert(connections, wheel:GetPropertyChangedSignal("Rotation"):Connect(function()
		-- Labels travel with the disc while staying readable at every final position.
		for _, label in prizeLabels do label.Rotation = -wheel.Rotation end
	end))
	local hub = frame(wheelMount, "Hub", COLORS.Gold)
	hub.AnchorPoint, hub.Size, hub.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.18, 0.18), UDim2.fromScale(0.5, 0.5)
	rounded(hub, 99)
	outline(hub, COLORS.Pale, 3)
	gradient(hub, Color3.fromRGB(255, 227, 112), Color3.fromRGB(207, 135, 23))
	local hubMark = text(hub, "Star", "★", 29, Color3.fromRGB(255, 245, 183))
	hubMark.Size, hubMark.TextScaled = UDim2.fromScale(1, 1), true
	local pointer = text(wheelMount, "Pointer", "▼", 46, COLORS.Gold)
	pointer.AnchorPoint, pointer.Size, pointer.Position = Vector2.new(0.5, 0.5), UDim2.fromOffset(50, 46), UDim2.fromScale(0.5, 0.045)
	pointer.TextStrokeTransparency, pointer.TextStrokeColor3 = 0, Color3.fromRGB(133, 73, 12)

	local spinInfo = frame(arcade, "SpinInfo", COLORS.Night)
	rounded(spinInfo, 10)
	outline(spinInfo, COLORS.Edge, 1)
	local spinStatus = text(spinInfo, "Status", "FREE SPIN", 12, COLORS.Muted)
	local spinClock = text(spinInfo, "Cooldown", "Loading...", 27, COLORS.White)
	local spinButton = button(spinInfo, "FreeSpin")
	local spinResult = text(arcade, "SpinResult", "Coins or eggs. Your next prize awaits.", 14, COLORS.Muted)

	local function layout()
		if destroyed then return end
		local activeCamera = workspace.CurrentCamera
		if not activeCamera then return end
		local topLeft, bottomRight = GuiService:GetGuiInset()
		local available = activeCamera.ViewportSize - topLeft - bottomRight
		local wideShort = available.X >= 1100 and activeCamera.ViewportSize.Y < 800 and available.Y >= 560
		local width = math.min(if wideShort then 1080 else 790, math.max(240, available.X - 24))
		local height = math.min(760, math.max(180, available.Y - 24))
		nativeScale.Scale = if inheritedScale then 1 / math.max(0.01, inheritedScale.Scale) else 1
		panel.Size = UDim2.fromOffset(width, height)
		position(header, 3, 3, width - 6, 66)
		position(heading, 70, 8, width - 142, 34)
		position(subtitle, 72, 43, width - 145, 14)
		gift.Visible = width >= 350
		if width < 350 then position(heading, 16, 8, width - 85, 34); position(subtitle, 18, 43, width - 86, 14) end
		if close and close:IsA("TextButton") then position(close, width - 56, 13, 44, 44) end
		position(content, 10, 78, width - 20, height - 88)
		local inner = width - 28
		local dailyWidth = if wideShort then math.max(350, inner * 0.36) else inner
		local arcadeWidth = if wideShort then inner - dailyWidth - 14 else inner
		local compact = arcadeWidth < 530
		local sideWheelSize = math.min(340, arcadeWidth - 228, content.Size.Y.Offset - 112)
		local dailyHeight = if wideShort then sideWheelSize + 104 elseif compact then 282 else 246
		position(daily, 4, 4, dailyWidth, dailyHeight)
		position(dailyHeading, 14, 11, dailyWidth - 28, 29)
		position(dayStatus, 14, 40, dailyWidth - 28, 19)
		local tileWidth = math.max(42, (dailyWidth - 28 - (maxDays - 1) * 6) / maxDays)
		position(track, 14, 65, dailyWidth - 28, 78)
		track.CanvasSize = UDim2.fromOffset(maxDays * (tileWidth + 6) - 6, 74)
		for index, card in dayCards do
			position(card.Tile, (index - 1) * (tileWidth + 6), 2, tileWidth, 70)
			card.Art.Size, card.Art.Position = UDim2.fromOffset(36, 39), UDim2.new(0.5, -18, 0, 5)
		end
		position(reward, 12, 151, dailyWidth - 24, dailyHeight - 163)
		local rewardAlignment = if wideShort then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		rewardCaption.TextXAlignment, rewardValue.TextXAlignment, rewardEgg.TextXAlignment = rewardAlignment, rewardAlignment, rewardAlignment
		if wideShort then
			local rewardWidth, rewardHeight = dailyWidth - 24, dailyHeight - 163
			position(rewardArt, (rewardWidth - 100) / 2, 10, 100, 100)
			position(rewardCaption, 12, 116, rewardWidth - 24, 19)
			position(rewardValue, 12, 140, rewardWidth - 24, 36)
			position(rewardEgg, 12, 177, rewardWidth - 24, 22)
			position(dailyButton, 12, rewardHeight - 58, rewardWidth - 24, 46)
		elseif compact then
			position(rewardArt, 9, 5, 54, 54)
			position(rewardCaption, 72, 4, dailyWidth - 110, 17)
			position(rewardValue, 72, 20, dailyWidth - 110, 29)
			position(rewardEgg, 12, 47, dailyWidth - 48, 17)
			position(dailyButton, 10, 68, dailyWidth - 44, 44)
		else
			position(rewardArt, 11, 5, 58, 58)
			position(rewardCaption, 80, 5, dailyWidth * 0.5 - 74, 18)
			position(rewardValue, 80, 23, dailyWidth * 0.5 - 74, 29)
			position(rewardEgg, 80, 50, dailyWidth * 0.5 - 74, 18)
			position(dailyButton, dailyWidth * 0.61, 13, dailyWidth * 0.39 - 37, 48)
		end
		local wheelSize = if wideShort then sideWheelSize elseif compact then math.min(330, arcadeWidth - 26) else math.min(390, arcadeWidth * 0.61)
		-- Desktop keeps the complete disc visible; short / narrow screens retain native scroll.
		local fittingWheelSize = content.Size.Y.Offset - dailyHeight - 26 - 104
		if not wideShort and not compact and fittingWheelSize >= 240 then wheelSize = math.min(wheelSize, fittingWheelSize) end
		local arcadeHeight = if compact then wheelSize + 222 else wheelSize + 104
		position(arcade, if wideShort then dailyWidth + 18 else 4, if wideShort then 4 else dailyHeight + 17, arcadeWidth, arcadeHeight)
		position(spinHeading, 16, 11, arcadeWidth - 32, 31)
		position(spinSubtitle, 17, 43, arcadeWidth - 34, 18)
		if compact then
			position(wheelMount, (arcadeWidth - wheelSize) / 2, 72, wheelSize, wheelSize)
			position(spinInfo, 14, wheelSize + 84, arcadeWidth - 28, 94)
			position(spinStatus, 12, 11, (arcadeWidth - 52) * 0.44, 20)
			position(spinClock, 10, 36, (arcadeWidth - 52) * 0.46, 40)
			position(spinButton, (arcadeWidth - 28) * 0.49, 25, (arcadeWidth - 28) * 0.51 - 12, 48)
			position(spinResult, 14, wheelSize + 185, arcadeWidth - 28, 26)
		else
			position(wheelMount, 14, 74, wheelSize, wheelSize)
			local infoWidth = arcadeWidth - wheelSize - 48
			local infoY = wheelSize * 0.5 - 8
			position(spinInfo, wheelSize + 29, infoY, infoWidth, 164)
			position(spinStatus, 8, 14, infoWidth - 16, 23)
			position(spinClock, 8, 45, infoWidth - 16, 39)
			position(spinButton, 10, 103, infoWidth - 20, 48)
			position(spinResult, wheelSize + 25, infoY + 176, infoWidth + 8, 52)
		end
		content.CanvasSize = UDim2.fromOffset(0, if wideShort then math.max(dailyHeight, arcadeHeight) + 8 else dailyHeight + arcadeHeight + 26)
		if content.CanvasSize.Y.Offset <= content.Size.Y.Offset then content.CanvasPosition = Vector2.zero end
	end

	local function enabled(item: TextButton, available: boolean)
		item.Active, item.Selectable, item.AutoButtonColor = available, available, available
		item.BackgroundColor3 = if available then COLORS.Gold else COLORS.Disabled
		item.TextColor3 = if available then COLORS.Night else COLORS.Muted
	end

	-- Celebration: a short confetti burst from the claim button / the wheel. Pure decoration; never blocks input.
	local confettiColors = { COLORS.Gold, COLORS.Green, Color3.fromRGB(255, 99, 132), Color3.fromRGB(80, 180, 255), COLORS.White }
	local lastDailyIn: number? = nil
	local function burst(origin: GuiObject)
		if destroyed or not panel.Visible then return end
		pcall(function()
			local rootSize, rootPosition = root.AbsoluteSize, root.AbsolutePosition
			if rootSize.X < 1 or rootSize.Y < 1 then return end
			local center = origin.AbsolutePosition + origin.AbsoluteSize / 2 - rootPosition
			local cx, cy = center.X / rootSize.X, center.Y / rootSize.Y
			for index = 1, 26 do
				local piece = Instance.new("Frame")
				piece.Name = "Confetti"
				piece.BorderSizePixel, piece.Active = 0, false
				piece.BackgroundColor3 = confettiColors[(index % #confettiColors) + 1]
				piece.Size = UDim2.fromOffset(math.random(6, 11), math.random(6, 11))
				piece.AnchorPoint = Vector2.new(0.5, 0.5)
				piece.Position = UDim2.fromScale(cx, cy)
				piece.Rotation = math.random(0, 359)
				piece.ZIndex = 60
				piece.Parent = root
				local angle = (index / 26) * math.pi * 2 + math.random() * 0.4
				local distance = 0.12 + math.random() * 0.16
				TweenService:Create(piece, TweenInfo.new(0.9 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(cx + math.cos(angle) * distance, cy + math.sin(angle) * distance * 1.4 + 0.1),
					Rotation = piece.Rotation + math.random(-260, 260),
					BackgroundTransparency = 1,
				}):Play()
				task.delay(1.5, function() piece:Destroy() end)
			end
		end)
	end

	function controller:Refresh(state: any)
		if destroyed then return end
		lastState = state
		if not state then
			dailyButton.Text, spinButton.Text = "Loading...", "Loading..."
			enabled(dailyButton, false); enabled(spinButton, false)
			return
		end
		local dailyIn, spinIn = math.max(0, state.DailyReadyIn or 0), math.max(0, state.SpinReadyIn or 0)
		-- the cooldown jumping from "ready" to "waiting" means the daily reward was just claimed
		if lastDailyIn and lastDailyIn <= 0 and dailyIn > 0 then burst(dailyButton) end
		lastDailyIn = dailyIn
		local savedStreak = math.clamp(math.floor(state.DailyStreak or 0), 0, maxDays)
		local nextDay = math.clamp(math.floor(state.DailyNextDay or math.min(savedStreak + 1, maxDays)), 1, maxDays)
		local streak = if state.DailyNextDay ~= nil then nextDay - 1 else savedStreak
		if dailyIn > 0 then pendingDaily = false end
		dayStatus.Text = string.format("Day %d / %d  ·  %s", nextDay, maxDays, if dailyIn > 0 then "NEXT UP" else "READY TO CLAIM")
		for day, card in dayCards do
			local claimed, selected = day <= streak, day == nextDay
			card.Check.Visible, card.Art.Visible = claimed, not claimed
			card.Tile.BackgroundColor3 = if claimed then Color3.fromRGB(22, 69, 63) elseif selected then Color3.fromRGB(96, 69, 26) else COLORS.Card
			card.Border.Color, card.Border.Thickness = if selected then COLORS.Gold elseif claimed then COLORS.Green else COLORS.Edge, if selected then 2 else 1
			card.Caption.TextColor3 = if selected then COLORS.Pale elseif claimed then COLORS.Green else COLORS.Muted
		end
		rewardValue.Text = MonsterMath.FormatNumber(Config.Daily.CoinsPerDay * nextDay) .. " coins"
		local bonus = Config.Eggs[Config.Daily.Day7Egg]
		rewardEgg.Text = if nextDay == maxDays and bonus then "+ " .. bonus.DisplayName else ""
		dailyButton.Text = if pendingDaily then "Claiming..." elseif dailyIn > 0 then "Ready in " .. clock(dailyIn) else "CLAIM REWARD"
		enabled(dailyButton, dailyIn <= 0 and not pendingDaily and not spinning and not pendingSpin)
		spinStatus.Text = if spinning then "CHOOSING YOUR PRIZE" elseif spinIn > 0 then "FREE SPIN IN" else "YOUR FREE SPIN IS READY"
		spinClock.Text = if spinning then "GOOD LUCK!" elseif pendingSpin then "Starting..." elseif spinIn > 0 then clock(spinIn) else "LET'S GO!"
		spinButton.Text = if spinning then "SPINNING..." elseif pendingSpin then "WAIT..." else "FREE SPIN"
		enabled(spinButton, #prizes > 0 and spinIn <= 0 and not spinning and not pendingSpin and not pendingDaily)
	end

	local function finishSpin()
		animationVersion += 1
		if spinTween then spinTween:Cancel(); spinTween = nil end
		wheel.Rotation = spinTarget % 360
		spinning = false
		if resultIndex and prizes[resultIndex] then
			spinResult.Text, spinResult.TextColor3 = "Prize: " .. prizes[resultIndex].Name, COLORS.Pale
		end
		controller:Refresh(lastState)
	end

	function controller:ShowSpinResult(index: number)
		if destroyed or type(index) ~= "number" or index % 1 ~= 0 or not prizes[index] then return end
		finishSpin()
		pendingSpin, spinning = false, true
		resultIndex = index
		local current = wheel.Rotation % 360
		wheel.Rotation = current
		local desired = (-(index - 1) * step) % 360
		spinTarget = current + 360 * 5 + (desired - current) % 360
		spinResult.Text = "Spinning..."
		controller:Refresh(lastState)
		animationVersion += 1
		local version = animationVersion
		if not panel.Visible then
			finishSpin()
			spinResult.Text = "Prize: " .. prizes[index].Name
			return
		end
		spinTween = TweenService:Create(wheel, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = spinTarget })
		spinTween:Play()
		task.delay(4.6, function()
			if destroyed or version ~= animationVersion then return end
			finishSpin()
			spinResult.Text, spinResult.TextColor3 = "Prize: " .. prizes[index].Name, COLORS.Pale
			burst(wheel)
		end)
	end

	table.insert(connections, dailyButton.Activated:Connect(function()
		if destroyed or not lastState or pendingDaily or pendingSpin or spinning or (lastState.DailyReadyIn or 0) > 0 then return end
		pendingDaily = true
		controller:Refresh(lastState)
		options.ClaimDaily()
		task.delay(3, function() if not destroyed then pendingDaily = false; controller:Refresh(options.GetState()) end end)
	end))
	table.insert(connections, spinButton.Activated:Connect(function()
		if destroyed or not lastState or #prizes == 0 or spinning or pendingSpin or pendingDaily or (lastState.SpinReadyIn or 0) > 0 then return end
		pendingSpin = true
		controller:Refresh(lastState)
		options.Spin()
		task.delay(5, function() if not destroyed and pendingSpin then pendingSpin = false; controller:Refresh(options.GetState()) end end)
	end))
	table.insert(connections, panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible and spinning then finishSpin()
		elseif panel.Visible then layout(); controller:Refresh(options.GetState()) end
	end))
	local viewportConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local activeCamera = workspace.CurrentCamera
		if activeCamera then viewportConnection = activeCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
		layout()
	end
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
	if inheritedScale then table.insert(connections, inheritedScale:GetPropertyChangedSignal("Scale"):Connect(layout)) end
	function controller:Destroy()
		if destroyed then return end
		destroyed = true
		animationVersion += 1
		if spinTween then spinTween:Cancel() end
		if viewportConnection then viewportConnection:Disconnect() end
		for _, connection in connections do connection:Disconnect() end
		root:Destroy()
		nativeScale:Destroy()
	end
	table.insert(connections, panel.Destroying:Connect(function() controller:Destroy() end))
	watchCamera()
	controller:Refresh(options.GetState())
	return controller :: Controller
end

return RewardsArcade
