--!strict
-- Shared navy and gold surfaces, with the approved glossy icon atlas.
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

function GuiTheme.Icon(parent: GuiObject, name: string, size: UDim2, position: UDim2)
	local cell = GuiTheme.IconRects[name] or Vector2.zero
	local crop = iconCrops[name] or Rect.new(
		cell.X * GuiTheme.Atlas.CellSize.X,
		cell.Y * GuiTheme.Atlas.CellSize.Y,
		(cell.X + 1) * GuiTheme.Atlas.CellSize.X,
		(cell.Y + 1) * GuiTheme.Atlas.CellSize.Y
	)
	local icon = Instance.new("Frame")
	icon.Name = name .. "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = size
	icon.Position = position
	icon.ZIndex = parent.ZIndex
	icon.Active = false
	icon.Selectable = false
	icon.Parent = parent

	-- Normalized clipping survives Roblox resizing the delivered texture. Pixel
	-- rectangles and the protected ContentImageSize property cannot do that.
	-- CanvasGroup lets the gear's rounded clip include the atlas child.
	local viewport = if name == "Settings" then Instance.new("CanvasGroup") else Instance.new("Frame")
	viewport.Name = "AtlasViewport"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ClipsDescendants = true
	viewport.Active = false
	viewport.Selectable = false
	viewport.Parent = icon
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = crop.Width / crop.Height
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = viewport
	local image = Instance.new("ImageLabel")
	image.Name = "AtlasImage"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(GuiTheme.Atlas.Size.X / crop.Width, GuiTheme.Atlas.Size.Y / crop.Height)
	image.Position = UDim2.fromScale(-crop.Min.X / crop.Width, -crop.Min.Y / crop.Height)
	image.Image = GuiTheme.Atlas.Image
	image.ScaleType = Enum.ScaleType.Stretch
	image.Active = false
	image.Selectable = false
	image.Parent = viewport
	if name == "Settings" then
		local clip = Instance.new("UICorner")
		clip.CornerRadius = UDim.new(1, 0)
		clip.Parent = viewport
	end

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.BackgroundTransparency = 1
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.Font = Enum.Font.FredokaOne
	fallback.TextScaled = true
	fallback.TextColor3 = GuiTheme.Colors.Yellow
	fallback.Text = fallbacks[table.find(iconNames, name) or 1]
	fallback.Active = false
	fallback.Selectable = false
	fallback.Parent = icon
	local function refresh()
		-- The configured atlas was verified in Studio. Its cropped labels can
		-- render while IsLoaded remains false; loading flags must not cover it.
		fallback.Visible = image.Image == ""
		viewport.Visible = true
		viewport.ZIndex = icon.ZIndex
		image.ZIndex = icon.ZIndex
		fallback.ZIndex = icon.ZIndex + 1
	end
	local connections = {
		image:GetPropertyChangedSignal("Image"):Connect(refresh),
		icon:GetPropertyChangedSignal("ZIndex"):Connect(refresh),
	}
	table.insert(connections, icon.Destroying:Connect(function()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
	end))
	refresh()
	return icon
end

function GuiTheme.Gloss(parent: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(231, 229, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(157, 153, 205)),
	})
	gradient.Parent = parent
end

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

-- Extra dressing for modal panels: an accent title band, pixel corner brackets, a bottom accent line
-- and a light sheen that sweeps the band each time the panel opens. Everything is decoration (never
-- active) and lives in one "Ornament" folder-like frame so it can't affect layout or input.
function GuiTheme.Dress(panel: Frame, accent: Color3)
	if panel:FindFirstChild("Ornament") then return end
	local colors = GuiTheme.Colors
	local ornament = decoration(panel, "Ornament", Color3.new(1, 1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
	ornament.BackgroundTransparency = 1
	ornament.ClipsDescendants = false

	-- Bright, glossy title band (reference: the Store header): light accent at the top fading to a deeper
	-- accent at the bottom, with a pale highlight stripe across the upper third.
	local band = decoration(ornament, "TitleBand", accent, UDim2.new(1, -8, 0, 54), UDim2.fromOffset(4, 4))
	band.ClipsDescendants = true
	local bandGradient = Instance.new("UIGradient")
	bandGradient.Rotation = 90
	bandGradient.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.35), accent:Lerp(colors.Panel, 0.35))
	bandGradient.Parent = band
	local highlight = decoration(band, "Highlight", Color3.new(1, 1, 1), UDim2.new(1, -8, 0, 8), UDim2.fromOffset(4, 4))
	highlight.BackgroundTransparency = 0.78
	local highlightCorner = Instance.new("UICorner"); highlightCorner.CornerRadius = UDim.new(0, 4); highlightCorner.Parent = highlight
	local bandCorner = Instance.new("UICorner"); bandCorner.CornerRadius = UDim.new(0, 2); bandCorner.Parent = band
	local bandLine = decoration(ornament, "TitleLine", accent, UDim2.new(1, -8, 0, 3), UDim2.fromOffset(4, 58))
	local bandShadow = decoration(ornament, "TitleLineShadow", Color3.fromRGB(12, 16, 31), UDim2.new(1, -8, 0, 2), UDim2.fromOffset(4, 61))

	local brackets: { Frame } = {}
	local function bracket(anchorX: number, anchorY: number)
		local sx, sy = if anchorX == 0 then 1 else -1, if anchorY == 0 then 1 else -1
		local ox, oy = if anchorX == 0 then 7 else -7, if anchorY == 0 then 67 else -7
		local horizontal = decoration(ornament, "BracketH", accent, UDim2.fromOffset(16, 3), UDim2.new(anchorX, ox + (if sx < 0 then -16 else 0), anchorY, oy + (if sy < 0 then -3 else 0)))
		local vertical = decoration(ornament, "BracketV", accent, UDim2.fromOffset(3, 16), UDim2.new(anchorX, ox + (if sx < 0 then -3 else 0), anchorY, oy + (if sy < 0 then -16 else 0)))
		table.insert(brackets, horizontal)
		table.insert(brackets, vertical)
	end
	bracket(0, 1)
	bracket(1, 1)
	-- the top brackets sit under the band, so only the bottom pair is drawn plus studs under the band
	for _, x in { 12, -16 } do
		local stud = decoration(ornament, "Stud", accent:Lerp(Color3.new(1, 1, 1), 0.35), UDim2.fromOffset(4, 4), UDim2.new(if x > 0 then 0 else 1, x, 0, 66))
		table.insert(brackets, stud)
	end

	local sheen = decoration(band, "Sheen", Color3.new(1, 1, 1), UDim2.new(0, 36, 2, 0), UDim2.new(-0.2, 0, -0.5, 0))
	sheen.BackgroundTransparency = 0.82
	sheen.Rotation = 18
	sheen.Visible = false

	local parts: { GuiObject } = { band, highlight, bandLine, bandShadow, sheen }
	for _, part in brackets do table.insert(parts, part) end
	local function syncZ()
		ornament.ZIndex = panel.ZIndex
		for _, part in parts do part.ZIndex = panel.ZIndex end
	end
	syncZ()
	local zConnection = panel:GetPropertyChangedSignal("ZIndex"):Connect(syncZ)
	local sheenTween: Tween? = nil
	local visibleConnection = panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then return end
		if sheenTween then sheenTween:Cancel() end
		sheen.Position = UDim2.new(-0.2, 0, -0.5, 0)
		sheen.Visible = true
		sheenTween = TweenService:Create(sheen, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(1.1, 0, -0.5, 0) })
		sheenTween.Completed:Once(function() sheen.Visible = false end)
		sheenTween:Play()
	end)
	panel.Destroying:Connect(function()
		zConnection:Disconnect()
		visibleConnection:Disconnect()
		if sheenTween then sheenTween:Cancel() end
	end)
end

-- Item card dressing: accent strip on the left, a soft inner glow stroke and a hover lift.
function GuiTheme.Card(card: GuiObject, accent: Color3)
	if card:FindFirstChild("CardAccent") then return end
	local strip = decoration(card, "CardAccent", accent, UDim2.new(0, 4, 1, -8), UDim2.fromOffset(4, 4))
	strip.ZIndex = card.ZIndex
	local glow = Instance.new("UIStroke")
	glow.Name = "CardGlow"
	glow.Color = accent
	glow.Thickness = 1
	glow.Transparency = 0.55
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Parent = card
	card.MouseEnter:Connect(function()
		TweenService:Create(glow, TweenInfo.new(0.12), { Transparency = 0, Thickness = 2 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(glow, TweenInfo.new(0.16), { Transparency = 0.55, Thickness = 1 }):Play()
	end)
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
	local gloss = button:FindFirstChildOfClass("UIGradient")
	local function refresh()
		if borderTween then borderTween:Cancel() end
		if glossTween then glossTween:Cancel() end
		local pressed = pressedInput ~= nil
		local highlighted = hovered or selected
		local timing = TweenInfo.new(if pressed then 0.08 else 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		borderTween = TweenService:Create(border, timing, {
			Color = if highlighted and not pressed then GuiTheme.Colors.Text else GuiTheme.Colors.Yellow,
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

-- Broad, native pixel navigation pills match the approved Flow reference.
function GuiTheme.DecoratePill(button: TextButton, name: string)
	button.TextTransparency = 1
	button:SetAttribute("AccessibleName", name)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(1, 0) end
	local icon = GuiTheme.Icon(button, name, UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	local function refresh()
		local iconSize = math.max(32, math.floor(button.Size.Y.Offset * 0.72))
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = button.ZIndex
	end
	button:GetPropertyChangedSignal("Size"):Connect(refresh)
	button:GetPropertyChangedSignal("ZIndex"):Connect(refresh)
	refresh()
end

return GuiTheme
