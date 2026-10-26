--!strict
-- Presentation only: the server chooses prizes, validates cooldowns, and grants rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local GuiTheme = require(script.Parent.GuiTheme)
local CartoonUI = require(script.Parent.CartoonUI)

local RewardsArcade = {}
local COLORS = {
	Night = Color3.fromRGB(18, 35, 82), Panel = Color3.fromRGB(255, 248, 226),
	Card = Color3.fromRGB(229, 247, 255), Edge = Color3.fromRGB(81, 192, 224),
	Gold = Color3.fromRGB(255, 199, 55), Pale = Color3.fromRGB(255, 231, 121),
	White = Color3.fromRGB(255, 255, 255), Muted = Color3.fromRGB(53, 79, 118),
	Green = Color3.fromRGB(150, 237, 36), Disabled = Color3.fromRGB(211, 226, 235),
	Sky = Color3.fromRGB(40, 185, 248), Cyan = Color3.fromRGB(31, 213, 235),
}

export type Options = {
	GetState: () -> any,
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
	sheen.Name = "SurfaceGradient"
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
	item.Font, item.RichText = Enum.Font.GothamBold, false
	item.Text, item.TextSize, item.TextColor3 = value, size, color
	item.TextWrapped = true
	item.TextStrokeColor3, item.TextStrokeTransparency = COLORS.Night, 1
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
	item.BackgroundColor3 = COLORS.Green
	item.Parent = parent
	rounded(item, 9)
	local border = outline(item, Color3.fromRGB(53, 148, 15), 2)
	gradient(item, Color3.new(1, 1, 1), Color3.fromRGB(190, 226, 139))
	GuiTheme.ButtonFeedback(item, border)
	return item
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60) end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
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
	local destroyed, spinning, pendingSpin = false, false, false
	local lastState: any = nil
	local spinTween: Tween? = nil
	local spinTarget = 0
	local resultIndex: number? = nil
	local animationVersion = 0
	local prizes = Config.Spin.Prizes
	local step = if #prizes > 0 then 360 / #prizes else 360
	local controller = {} :: any

	panel.BackgroundColor3 = COLORS.Sky
	panel.ZIndex = 30
	for _, child in panel:GetChildren() do
		if child.Name == "Ornament" or child.Name == "PixelInset" or child.Name == "ModalBackdrop" or child:IsA("UIGradient") then child:Destroy()
		elseif child:IsA("TextLabel") then child.Visible = false
		elseif child:IsA("UIStroke") then child.Color, child.Thickness = COLORS.Cyan, 3 end
	end
	local backdrop = CartoonUI.ApplyBackdrop(panel)
	local root = frame(panel, "RewardsArcade", COLORS.Panel)
	root.BackgroundTransparency, root.Size = 1, UDim2.fromScale(1, 1)
	local nativeScale = Instance.new("UIScale")
	nativeScale.Name, nativeScale.Parent = "NativeRewardsScale", panel
	local screen = panel:FindFirstAncestorOfClass("ScreenGui")
	local inheritedScale = if screen then screen:FindFirstChildOfClass("UIScale") else nil

	local header = frame(root, "Header", COLORS.Sky)
	rounded(header, 10)
	gradient(header, Color3.fromRGB(107, 225, 255), COLORS.Sky)
	local headerLine = frame(header, "GoldRule", COLORS.Gold)
	headerLine.Position, headerLine.Size = UDim2.new(0, 8, 1, -2), UDim2.new(1, -16, 0, 2)
	local gift = CartoonUI.Icon(header, "Gift", 48)
	gift.Name, gift.Size, gift.Position = "GiftArt", UDim2.fromOffset(48, 48), UDim2.fromOffset(14, 8)
	local heading = text(header, "Heading", "REWARDS", 31, COLORS.Gold)
	heading.Font, heading.TextStrokeTransparency = Enum.Font.FredokaOne, 0.05
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local subtitle = text(header, "Subtitle", "Your daily loot drop", 11, COLORS.Night)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	local close = panel:FindFirstChild("CloseButton")
	if close and close:IsA("TextButton") then
		close.ZIndex = 40
		close.BackgroundColor3, close.TextColor3, close.TextSize = Color3.fromRGB(243, 72, 94), COLORS.White, 24
		for _, child in close:GetChildren() do
			if child:IsA("UIGradient") then child:Destroy() end
		end
	end

	local content = Instance.new("ScrollingFrame")
	content.Name, content.BackgroundTransparency, content.BorderSizePixel = "RewardContent", 1, 0
	content.ScrollBarThickness, content.ScrollBarImageColor3 = 4, COLORS.Edge
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.CanvasSize = UDim2.new()
	content.Parent = root
	local arcade = frame(content, "SpinArcade", COLORS.Panel)
	rounded(arcade, 16)
	outline(arcade, Color3.fromRGB(255, 227, 159), 2)
	local spinHeading = text(arcade, "SpinHeading", "SPIN WHEEL", 23, COLORS.Night)
	spinHeading.Font = Enum.Font.FredokaOne
	spinHeading.TextXAlignment = Enum.TextXAlignment.Left
	local spinSubtitle = text(arcade, "SpinSubtitle", "ONE FREE SPIN EVERY " .. tostring(math.floor(Config.Spin.Cooldown / 3600)) .. " HOURS", 11, COLORS.Muted)
	spinSubtitle.TextXAlignment = Enum.TextXAlignment.Left

	local wheelMount = frame(arcade, "WheelMount", COLORS.Gold)
	wheelMount.BackgroundTransparency = 1
	local rim = frame(wheelMount, "GoldenRim", COLORS.Gold)
	rim.Size, rim.Position = UDim2.fromScale(0.96, 0.96), UDim2.fromScale(0.02, 0.02)
	rounded(rim, 999)
	outline(rim, COLORS.Night, 2)
	gradient(rim, Color3.fromRGB(255, 242, 160), Color3.fromRGB(231, 151, 24))
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
		local iconName = if prize.Egg == "Mythic" then "MythicEgg" elseif prize.Egg == "Rare" then "RareEgg"
			elseif prize.Egg then "LuckyEgg" elseif prize.Candy then "Candy" else "Coins"
		local art = CartoonUI.Icon(labelGroup, iconName, 64)
		art.Name = if prize.Egg then "Egg" elseif prize.Candy then "Candy" else "Coins"
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
	gradient(hub, Color3.fromRGB(255, 245, 170), Color3.fromRGB(241, 169, 39))
	local hubMark = CartoonUI.Icon(hub, "Gift", 44)
	hubMark.Size, hubMark.Position = UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1)
	-- Countable native geometry for the fixed pointer; no platform-dependent glyph.
	local pointer = frame(wheelMount, "Pointer", COLORS.Gold)
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint, pointer.Size, pointer.Position = Vector2.new(0.5, 0), UDim2.fromOffset(36, 32), UDim2.fromScale(0.5, 0.025)
	for row = 0, 15 do
		local edge = frame(pointer, "PointerEdge", COLORS.Night)
		position(edge, row, row * 2, 36 - row * 2, 2)
		if row >= 2 and row < 13 then
			local fill = frame(pointer, "PointerFill", COLORS.Gold)
			position(fill, row + 3, row * 2, 30 - row * 2, 2)
		end
	end

	local spinInfo = frame(arcade, "SpinInfo", COLORS.Card)
	rounded(spinInfo, 14)
	outline(spinInfo, COLORS.Edge, 2)
	local spinStatus = text(spinInfo, "Status", "FREE SPIN", 12, COLORS.Muted)
	local spinClock = text(spinInfo, "Cooldown", "Loading...", 27, COLORS.Night)
	spinClock.Font = Enum.Font.FredokaOne
	local spinButton = button(spinInfo, "FreeSpin")
	local spinResult = text(arcade, "SpinResult", "Coins, candy or eggs. Your next prize awaits.", 14, COLORS.Muted)

	local function layout()
		if destroyed then return end
		local activeCamera = workspace.CurrentCamera
		if not activeCamera then return end
		local topLeft, bottomRight = GuiService:GetGuiInset()
		local available = activeCamera.ViewportSize - topLeft - bottomRight
		local width = math.min(790, math.max(240, available.X - 24))
		local height = math.min(760, math.max(180, available.Y - 24))
		nativeScale.Scale = (if inheritedScale then 1 / math.max(0.01, inheritedScale.Scale) else 1) * GuiTheme.ModalShrink(activeCamera.ViewportSize)
		panel.Size = UDim2.fromOffset(width, height)
		position(header, 3, 3, width - 6, 66)
		position(heading, 70, 8, width - 142, 34)
		position(subtitle, 72, 43, width - 145, 14)
		gift.Visible = width >= 350
		if width < 350 then position(heading, 16, 8, width - 85, 34); position(subtitle, 18, 43, width - 86, 14) end
		if close and close:IsA("TextButton") then position(close, width - 56, 13, 44, 44) end
		position(content, 10, 78, width - 20, height - 88)
		local inner = width - 28
		local arcadeWidth = inner
		local compact = arcadeWidth < 530
		local wheelSize = if compact then math.min(330, arcadeWidth - 26) else math.min(390, arcadeWidth * 0.61)
		-- Desktop keeps the complete disc visible; short / narrow screens retain native scroll.
		local fittingWheelSize = content.Size.Y.Offset - 8 - 104
		if not compact and fittingWheelSize >= 240 then wheelSize = math.min(wheelSize, fittingWheelSize) end
		local arcadeHeight = if compact then wheelSize + 222 else wheelSize + 104
		position(arcade, 4, 4, arcadeWidth, arcadeHeight)
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
		content.CanvasSize = UDim2.fromOffset(0, arcadeHeight + 8)
		if content.CanvasSize.Y.Offset <= content.Size.Y.Offset then content.CanvasPosition = Vector2.zero end
	end

	local function enabled(item: TextButton, available: boolean)
		item.Active, item.Selectable, item.AutoButtonColor = available, available, available
		item.BackgroundColor3 = if available then COLORS.Green else COLORS.Disabled
		item.TextColor3 = if available then COLORS.Night else COLORS.Muted
		local sheen = item:FindFirstChildOfClass("UIGradient")
		if sheen then sheen.Enabled = available end
		local border = item:FindFirstChildOfClass("UIStroke")
		if border then border.Color = if available then Color3.fromRGB(53, 148, 15) else Color3.fromRGB(149, 177, 196) end
	end

	-- Celebration: a short confetti burst from the claim button / the wheel. Pure decoration; never blocks input.
	local confettiColors = { COLORS.Gold, COLORS.Green, Color3.fromRGB(255, 99, 132), Color3.fromRGB(80, 180, 255), COLORS.White }
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
			spinButton.Text = "Loading..."
			enabled(spinButton, false)
			return
		end
		local spinIn = math.max(0, state.SpinReadyIn or 0)
		spinStatus.Text = if spinning then "CHOOSING YOUR PRIZE" elseif spinIn > 0 then "FREE SPIN IN" else "YOUR FREE SPIN IS READY"
		spinClock.Text = if spinning then "GOOD LUCK!" elseif pendingSpin then "Starting..." elseif spinIn > 0 then clock(spinIn) else "LET'S GO!"
		spinButton.Text = if spinning then "SPINNING..." elseif pendingSpin then "WAIT..." else "FREE SPIN"
		enabled(spinButton, #prizes > 0 and spinIn <= 0 and not spinning and not pendingSpin)
	end

	local function finishSpin()
		animationVersion += 1
		if spinTween then spinTween:Cancel(); spinTween = nil end
		wheel.Rotation = spinTarget % 360
		spinning = false
		if resultIndex and prizes[resultIndex] then
			spinResult.Text, spinResult.TextColor3 = "Prize: " .. prizes[resultIndex].Name, COLORS.Night
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
			spinResult.Text, spinResult.TextColor3 = "Prize: " .. prizes[index].Name, COLORS.Night
			burst(wheel)
		end)
	end

	table.insert(connections, spinButton.Activated:Connect(function()
		if destroyed or not lastState or #prizes == 0 or spinning or pendingSpin or (lastState.SpinReadyIn or 0) > 0 then return end
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
		backdrop:Destroy()
		nativeScale:Destroy()
	end
	table.insert(connections, panel.Destroying:Connect(function() controller:Destroy() end))
	watchCamera()
	controller:Refresh(options.GetState())
	return controller :: Controller
end

return RewardsArcade
