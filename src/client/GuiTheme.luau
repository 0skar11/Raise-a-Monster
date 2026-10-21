--!strict
-- Pixel-framed surfaces and code-native icons matching the authored cube tile.
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GuiTheme = {}

GuiTheme.Colors = {
	Panel = Color3.fromRGB(29, 32, 80),
	PanelLight = Color3.fromRGB(43, 47, 101),
	Text = Color3.fromRGB(255, 251, 235),
	SubText = Color3.fromRGB(210, 210, 235),
	Green = Color3.fromRGB(68, 221, 45),
	Blue = Color3.fromRGB(67, 144, 237),
	Red = Color3.fromRGB(226, 79, 105),
	Yellow = Color3.fromRGB(239, 204, 119),
	Orange = Color3.fromRGB(246, 151, 58),
	Pink = Color3.fromRGB(185, 100, 232),
	Gray = Color3.fromRGB(105, 107, 143),
}

GuiTheme.Atlas = {
	-- Original approved artwork, including its navy background. Image resolved
	-- from uploaded Decal 125394921163890 through Studio InsertService.
	Image = "rbxassetid://116704436062887",
	Size = Vector2.new(1080, 1187),
	CellSize = Vector2.new(360, 296.75),
	Columns = 3,
	Rows = 4,
}
local iconNames = { "Shop", "Gift", "Rebirth", "Pets", "Friends", "Settings", "Coins", "Cash", "Strength", "Play", "Trophy", "Potion" }
local fallbacks = { "🛍️", "🎁", "⭐", "📖", "🤝", "⚙️", "💰", "💵", "💪", "▶", "🏆", "🧪" }
GuiTheme.IconRects = {} :: { [string]: Vector2 }
for index, name in iconNames do
	GuiTheme.IconRects[name] = Vector2.new((index - 1) % GuiTheme.Atlas.Columns, math.floor((index - 1) / GuiTheme.Atlas.Columns))
end

-- The gear overlaps its nominal grid cell. Crop its complete outline instead
-- of displaying a cut edge and the neighboring cell's background.
local iconCrops: { [string]: Rect } = {
	Settings = Rect.new(696, 309, 976, 589),
}

GuiTheme.IconColors = {
	Shop = Color3.fromRGB(21, 177, 231), Gift = Color3.fromRGB(249, 143, 41),
	Friends = Color3.fromRGB(73, 140, 244), Trophy = Color3.fromRGB(79, 201, 70),
	Pets = Color3.fromRGB(168, 93, 231), Settings = Color3.fromRGB(62, 174, 179),
	Play = Color3.fromRGB(85, 201, 119), Rebirth = Color3.fromRGB(220, 105, 228),
	Coins = Color3.fromRGB(246, 186, 36), Cash = Color3.fromRGB(82, 211, 98),
	Strength = Color3.fromRGB(235, 101, 77), Potion = Color3.fromRGB(203, 93, 231),
}
-- Twelve logical pixels per side. Runs merge vertically so the artwork remains
-- crisp at native HUD sizes without creating a frame for every individual pixel.
local glyphs = {
	Shop = { "............", "...AAAAAA...", "..AAAAAAAA..", ".AALAALAALA.", ".AALAALAALA.", "..SSSSSSSS..", "..SWWSSWWS..", "..SWWSSWWS..", "..SWWSSWWS..", "..SSSSSSSS..", "............", "............" },
	Gift = { "............", "...AA.AA....", "..ALLAALLA..", "...AAAAAA...", ".LLLWWWWLLL.", ".AAASWWAAAA.", "..AASWWAAA..", "..AASWWAAA..", "..AASWWAAA..", "..SSSWWSSS..", "............", "............" },
	Friends = { "............", "..LLL..LLL..", "..AAA..AAA..", "..AAA..AAA..", "............", ".LLLLAALLLL.", ".AAAASSAAAA.", ".AAAASSAAAA.", ".AAAASSAAAA.", "..SSS..SSS..", "............", "............" },
	Trophy = { "............", "..LLLLLLLL..", ".LAAAAAAAAL.", ".LAAAAAAAAL.", ".LLAAAAAALL.", "...AAAAAA...", "....AAAA....", ".....AA.....", ".....AA.....", "...LLLLLL...", "...SSSSSS...", "............" },
	Pets = { "............", "..LL....LL..", "..AA.LL.AA..", ".....AA.....", "............", "....LLLL....", "...LAAAAL...", "..LAAAAAAL..", "..AAAAAAAS..", "...SSSSSS...", "............", "............" },
	Settings = { "....LLLL....", "....AAAA....", "..AAAAAAAA..", "..AALLLLAA..", "LAAALSSLAASL", "LAAALSSLAASL", "LAAALSSLAASL", "LAAALSSLAASL", "..AALLLLAA..", "..AAAAAAAA..", "....SSSS....", "....SSSS...." },
	Play = { "............", "............", "..LLLLLLLL..", ".LAAAAAAAAL.", ".AAAWAAAAAA.", ".AAWWWALALA.", ".AAAWAAAAAA.", ".AAAAAALALA.", ".AAAA..AAAA.", "..SS....SS..", "............", "............" },
	Rebirth = { "............", "....LLLLLL..", "...LLAAAALL.", "..LL.....ALL", "..AA......AA", "..AA......AA", "AAAL......AA", ".AAL.....AA.", "..AALLLLLL..", "..AAAAAAA...", "............", "............" },
	Coins = { "............", "...LLLLLL...", "..LAAAAAAL..", ".LAALWLAAAS.", ".AAALWLAAAS.", ".AAALWLAAAS.", ".AAALWLAAAS.", ".AAALWLAAAS.", "..AAAAAASS..", "...SSSSSS...", "............", "............" },
	Cash = { "............", "............", ".LLLLLLLLLL.", ".LAAASSAAAL.", ".LAAWLLWAAL.", ".LAAWLLWAAL.", ".LAAASSAAAL.", ".SSSSSSSSSS.", "............", "............", "............", "............" },
	Strength = { "............", "...LL.LL....", "...AA.AA.LL.", ".LLAA.AA.AA.", ".AAAA.AA.AA.", ".AAAAAAAAAA.", ".AAAAAAAAAA.", "..AAAAAAAA..", "...AAAAAA...", "...SSSSSS...", "............", "............" },
	Potion = { "....LLLL....", "....AAAA....", ".....WW.....", ".....WW.....", "....WWWW....", "...WWLLWW...", "..WAAAAAAW..", "..AAAAAAAS..", "..AAAAAAAS..", "...AAAAAS...", "....SSSS....", "............" },
}

local function decoration(parent: GuiObject, name: string, color: Color3, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Size, frame.Position = size, position
	frame.ZIndex = parent.ZIndex
	frame.Active, frame.Selectable = false, false
	frame.Parent = parent
	return frame
end

function GuiTheme.Icon(parent: GuiObject, name: string, size: UDim2, position: UDim2)
	local icon = Instance.new("Frame")
	icon.Name = name .. "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = size
	icon.Position = position
	icon.ZIndex = parent.ZIndex
	icon.Active = false
	icon.Selectable = false
	icon.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = icon
	local accent = GuiTheme.IconColors[name] or GuiTheme.Colors.Blue
	local colors = { K = Color3.fromRGB(17, 20, 35), A = accent, L = accent:Lerp(Color3.new(1, 1, 1), 0.64), S = accent:Lerp(Color3.fromRGB(12, 19, 43), 0.4), W = Color3.fromRGB(255, 252, 235) }
	local rows = glyphs[name] or glyphs.Play
	local pixels: { { string } } = {}
	for y = 1, 12 do
		pixels[y] = {}
		for x = 1, 12 do pixels[y][x] = rows[y]:sub(x, x) end
	end
	for y = 1, 12 do
		for x = 1, 12 do
			if rows[y]:sub(x, x) ~= "." then
				for dy = -1, 1 do for dx = -1, 1 do
					local yy, xx = y + dy, x + dx
					if yy >= 1 and yy <= 12 and xx >= 1 and xx <= 12 and pixels[yy][xx] == "." then pixels[yy][xx] = "K" end
				end end
			end
		end
	end
	local runs: { [string]: Frame } = {}
	local pieces: { Frame } = {}
	for y = 1, 12 do
		local current: { [string]: Frame } = {}
		local x = 1
		while x <= 12 do
			local color = pixels[y][x]
			local start = x
			while x <= 12 and pixels[y][x] == color do x += 1 end
			if color == "." then continue end
			local key = color .. tostring(start) .. ":" .. tostring(x)
			local piece = runs[key]
			if piece then piece.Size = UDim2.fromScale((x - start) / 12, piece.Size.Y.Scale + 1 / 12)
			else
				piece = decoration(icon, "Pixel", colors[color], UDim2.fromScale((x - start) / 12, 1 / 12), UDim2.fromScale((start - 1) / 12, (y - 1) / 12))
				table.insert(pieces, piece)
			end
			current[key] = piece
		end
		runs = current
	end
	local connection = icon:GetPropertyChangedSignal("ZIndex"):Connect(function() for _, piece in pieces do piece.ZIndex = icon.ZIndex end end)
	icon.Destroying:Connect(function() connection:Disconnect() end)
	return icon
end

function GuiTheme.Gloss(parent: GuiObject)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner and corner.CornerRadius.Scale < 0.5 and corner.CornerRadius.Offset < 30 then corner.CornerRadius = UDim.new(0, 4) end
	local border = parent:FindFirstChildOfClass("UIStroke")
	if border then border.Color = Color3.fromRGB(12, 16, 31); border.Thickness = math.max(2, border.Thickness) end
	if not parent:FindFirstChild("PixelInset") then
		local inset = decoration(parent, "PixelInset", Color3.new(1, 1, 1), UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3))
		inset.BackgroundTransparency = 1
		local outline = Instance.new("UIStroke")
		outline.Color = parent:GetAttribute("PixelAccent") or parent.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.65)
		outline.Thickness = 1
		outline.Transparency = 0.15
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Parent = inset
		local clip = Instance.new("UICorner"); clip.CornerRadius = UDim.new(0, 2); clip.Parent = inset
		local connection = parent:GetPropertyChangedSignal("ZIndex"):Connect(function() inset.ZIndex = parent.ZIndex end)
		inset.Destroying:Connect(function() connection:Disconnect() end)
		parent.Destroying:Connect(function() connection:Disconnect() end)
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(245, 246, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 186, 215)),
	})
	gradient.Parent = parent
end

function GuiTheme.ButtonFeedback(button: TextButton, border: UIStroke)
	button.Active = true
	button.Selectable = true
	button.AutoButtonColor = false
	local hovered = false
	local selected = false
	local pressedInput: InputObject? = nil
	local borderTween: Tween? = nil
	local glossTween: Tween? = nil
	local function refresh()
		if borderTween then borderTween:Cancel() end
		if glossTween then glossTween:Cancel() end
		local pressed = pressedInput ~= nil
		local highlighted = hovered or selected
		local gloss = button:FindFirstChildOfClass("UIGradient")
		local timing = TweenInfo.new(if pressed then 0.08 else 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		borderTween = TweenService:Create(border, timing, {
			Color = Color3.fromRGB(12, 16, 31),
			Thickness = if pressed or selected then 3 else 2,
		})
		borderTween:Play()
		if gloss then
			glossTween = TweenService:Create(gloss, timing, { Offset = Vector2.new(0, if pressed then -0.12 elseif highlighted then 0.08 else 0) })
			glossTween:Play()
		end
	end
	button.MouseEnter:Connect(function() hovered = true; refresh() end)
	button.MouseLeave:Connect(function() hovered = false; pressedInput = nil; refresh() end)
	button.SelectionGained:Connect(function() selected = true; refresh() end)
	button.SelectionLost:Connect(function() selected = false; pressedInput = nil; refresh() end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			pressedInput = input
			refresh()
		end
	end)
	-- نرجع شكل الزر حتى لو اللمسة أو الماوس اتسابوا برّه حدوده.
	local releaseConnection = UserInputService.InputEnded:Connect(function(input)
		if input == pressedInput then pressedInput = nil; refresh() end
	end)
	button.Destroying:Connect(function()
		releaseConnection:Disconnect()
		if borderTween then borderTween:Cancel() end
		if glossTween then glossTween:Cancel() end
	end)
end

function GuiTheme.DecorateButton(button: TextButton, name: string, tile: boolean?)
	button.TextTransparency = 1
	local icon = GuiTheme.Icon(button, name,
		if tile then UDim2.fromOffset(66, 66) else UDim2.fromOffset(32, 32),
		if tile then UDim2.new(0.5, -33, 0, 2) else UDim2.new(0, 8, 0.5, -16))
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextColor3 = GuiTheme.Colors.Text
	caption.TextStrokeColor3 = GuiTheme.Colors.Panel
	caption.TextStrokeTransparency = 0.25
	caption.TextWrapped = true
	caption.TextSize = if tile then 16 else 17
	caption.Size = if tile then UDim2.new(1, -4, 0, 27) else UDim2.new(1, -50, 1, -4)
	caption.Position = if tile then UDim2.new(0, 2, 1, -29) else UDim2.fromOffset(44, 2)
	caption.ZIndex = button.ZIndex
	caption.Active = false
	caption.Selectable = false
	caption.Parent = button
	local function updateText()
		local text = button.Text:match("([^\n]+)$") or button.Text
		if #text > 0 and string.byte(text, 1) >= 128 then
			text = text:gsub("^%S+%s*", "")
		end
		caption.Text = text
	end
	button:GetPropertyChangedSignal("Text"):Connect(updateText)
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		icon.ZIndex = button.ZIndex
		caption.ZIndex = button.ZIndex
	end)
	updateText()
end

-- Match the authored cube button: a colored burst, dark frame and pixel glyph.
function GuiTheme.DecoratePill(button: TextButton, name: string)
	button.TextTransparency = 1
	button:SetAttribute("AccessibleName", name)
	button:SetAttribute("PixelTile", true)
	local accent = GuiTheme.IconColors[name] or GuiTheme.Colors.Blue
	button.BackgroundColor3 = accent
	button.BackgroundTransparency = 0
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(0, 4) end
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then gradient:Destroy() end
	local inset = button:FindFirstChild("PixelInset")
	if inset and inset:IsA("GuiObject") then inset.Visible = false end
	local border = button:FindFirstChildOfClass("UIStroke")
	if border then border.Color = Color3.fromRGB(12, 16, 31); border.Transparency = 0; border.Thickness = 2 end
	local burst = decoration(button, "PixelBurst", accent:Lerp(Color3.new(1, 1, 1), 0.8), UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3))
	burst.ClipsDescendants = true
	for index = 0, 11 do
		local ray = decoration(burst, "Ray", accent:Lerp(Color3.new(1, 1, 1), 0.13), UDim2.fromScale(1.5, 0.13), UDim2.fromScale(0.5, 0.5))
		ray.AnchorPoint = Vector2.new(0, 0.5)
		ray.Rotation = index * 30 + 15
	end
	local icon = GuiTheme.Icon(button, name, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	local function refresh()
		icon.Position = UDim2.fromScale(0.5, 0.5)
		burst.ZIndex = button.ZIndex
		for _, ray in burst:GetChildren() do if ray:IsA("GuiObject") then ray.ZIndex = button.ZIndex end end
		icon.ZIndex = button.ZIndex + 1
	end
	button:GetPropertyChangedSignal("Size"):Connect(refresh)
	button:GetPropertyChangedSignal("ZIndex"):Connect(refresh)
	refresh()
end

return GuiTheme
