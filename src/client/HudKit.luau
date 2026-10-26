--!strict
-- The "HUD kit" look shared by the Lucky Wheel, Shop, Codes, Gift and Settings windows: a dark slate body,
-- chunky black outlines, bright gradient headers and 3D buttons. Presentation only; callers own every behaviour.
local HudKit = {}

HudKit.Colors = {
	Body = Color3.fromRGB(50, 50, 65), Edge = Color3.fromRGB(82, 82, 107), Shadow = Color3.fromRGB(21, 21, 21),
	Ink = Color3.fromRGB(0, 0, 0), White = Color3.new(1, 1, 1), Row = Color3.fromRGB(52, 67, 91),
	Slate = Color3.fromRGB(30, 42, 57), Field = Color3.fromRGB(22, 24, 30), Muted = Color3.fromRGB(200, 205, 220),
	Gold = Color3.fromRGB(255, 214, 70),
}

-- top / bottom are the face gradient, lip is the darker band under a button, rim colours the inner white outline.
type Palette = { Top: Color3, Bottom: Color3, Lip: Color3, Rim: Color3 }
HudKit.Palettes = {
	Yellow = { Top = Color3.fromRGB(255, 235, 60), Bottom = Color3.fromRGB(255, 150, 20), Lip = Color3.fromRGB(170, 95, 0), Rim = Color3.fromRGB(255, 210, 40) },
	Blue = { Top = Color3.fromRGB(100, 190, 255), Bottom = Color3.fromRGB(25, 100, 235), Lip = Color3.fromRGB(15, 55, 160), Rim = Color3.fromRGB(70, 160, 255) },
	Purple = { Top = Color3.fromRGB(220, 120, 255), Bottom = Color3.fromRGB(150, 40, 230), Lip = Color3.fromRGB(90, 20, 150), Rim = Color3.fromRGB(200, 90, 255) },
	Green = { Top = Color3.fromRGB(150, 255, 90), Bottom = Color3.fromRGB(50, 205, 40), Lip = Color3.fromRGB(20, 120, 30), Rim = Color3.fromRGB(90, 255, 100) },
	Red = { Top = Color3.fromRGB(255, 90, 120), Bottom = Color3.fromRGB(225, 25, 60), Lip = Color3.fromRGB(150, 10, 40), Rim = Color3.fromRGB(255, 60, 90) },
	Settings = { Top = Color3.fromRGB(70, 200, 255), Bottom = Color3.fromRGB(150, 80, 255), Lip = Color3.fromRGB(40, 50, 150), Rim = Color3.fromRGB(70, 160, 255) },
	Grey = { Top = Color3.fromRGB(205, 211, 224), Bottom = Color3.fromRGB(128, 136, 156), Lip = Color3.fromRGB(70, 76, 94), Rim = Color3.fromRGB(190, 196, 210) },
} :: { [string]: Palette }

local function stroke(parent: Instance, color: Color3, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local item = Instance.new("UIStroke")
	item.Color, item.Thickness = color, thickness
	item.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	item.Parent = parent
	return item
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

-- White bold text with the kit's thick black outline.
function HudKit.Outline(label: Instance, thickness: number?): UIStroke
	return stroke(label, HudKit.Colors.Ink, thickness or 2.5, Enum.ApplyStrokeMode.Contextual)
end

function HudKit.Text(parent: Instance, name: string, value: string, size: number): TextLabel
	local item = Instance.new("TextLabel")
	item.Name, item.Text, item.TextSize = name, value, size
	item.BackgroundTransparency, item.BorderSizePixel = 1, 0
	item.Font, item.TextColor3, item.TextWrapped = Enum.Font.FredokaOne, HudKit.Colors.White, true
	item.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	item.Parent = parent
	HudKit.Outline(item)
	return item
end

-- The slate window body with the kit's two-tone edge.
function HudKit.Body(item: GuiObject, radius: number?)
	item.BackgroundColor3, item.BackgroundTransparency, item.BorderSizePixel = HudKit.Colors.Body, 0, 0
	corner(item, radius or 4)
	stroke(item, HudKit.Colors.Shadow, 8)
	stroke(item, HudKit.Colors.Edge, 3)
end

local function faceGradient(item: GuiObject, palette: Palette, lipStart: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "SurfaceGradient"
	gradient.Rotation = 90
	if lipStart then
		-- Hard colour stops draw the darker lip of the 3D button inside one gradient.
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, palette.Top), ColorSequenceKeypoint.new(lipStart, palette.Bottom),
			ColorSequenceKeypoint.new(math.min(1, lipStart + 0.001), palette.Lip), ColorSequenceKeypoint.new(1, palette.Lip),
		})
	else
		gradient.Color = ColorSequence.new(palette.Top, palette.Bottom)
	end
	gradient.Parent = item
end

-- A coloured window header: black outline, gradient face and a white inner rim. Returns the header and its title.
function HudKit.Header(parent: Instance, name: string, paletteName: string, title: string): (Frame, TextLabel)
	local palette = HudKit.Palettes[paletteName] or HudKit.Palettes.Yellow
	local header = Instance.new("Frame")
	header.Name, header.BackgroundColor3, header.BorderSizePixel = name, Color3.new(1, 1, 1), 0
	header.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	header.Parent = parent
	stroke(header, HudKit.Colors.Ink, 4)
	faceGradient(header, palette)
	local rim = Instance.new("Frame")
	rim.Name, rim.BackgroundTransparency, rim.BorderSizePixel = "Rim", 1, 0
	rim.Size, rim.Position, rim.ZIndex = UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), header.ZIndex + 1
	rim.Parent = header
	local rimStroke = stroke(rim, HudKit.Colors.White, 3)
	rimStroke.Transparency = 0.25
	local label = HudKit.Text(header, "Title", title, 36)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = false
	label.ZIndex = header.ZIndex + 3
	return header, label
end

-- 3D kit button. Text is drawn by a child label (a gradient on the button would tint the button's own text).
function HudKit.Button(parent: Instance, name: string, value: string, paletteName: string): TextButton
	local palette = HudKit.Palettes[paletteName] or HudKit.Palettes.Green
	local item = Instance.new("TextButton")
	item.Name, item.Text, item.BorderSizePixel = name, "", 0
	item.BackgroundColor3, item.AutoButtonColor = Color3.new(1, 1, 1), false
	item.Active, item.Selectable = true, true
	item.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	item.Parent = parent
	corner(item, 6)
	stroke(item, HudKit.Colors.Ink, 3)
	faceGradient(item, palette, 0.86)
	local rim = Instance.new("Frame")
	rim.Name, rim.BackgroundTransparency, rim.BorderSizePixel = "Rim", 1, 0
	rim.Size, rim.Position, rim.ZIndex = UDim2.new(1, -6, 0.86, -6), UDim2.fromOffset(3, 3), item.ZIndex + 1
	rim.Parent = item
	corner(rim, 4)
	local rimStroke = stroke(rim, HudKit.Colors.White, 2)
	rimStroke.Transparency = 0.3
	local label = HudKit.Text(item, "Label", value, 22)
	label.Size, label.Position = UDim2.fromScale(0.9, 0.78), UDim2.fromScale(0.05, 0.02)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize, limit.Parent = 8, 30, label
	item:SetAttribute("Palette", paletteName)
	return item
end

-- Recolours a button built by HudKit.Button (used for selected / unselected choices).
function HudKit.SetPalette(item: TextButton, paletteName: string)
	local palette = HudKit.Palettes[paletteName]
	local gradient = item:FindFirstChildOfClass("UIGradient")
	if not palette or not gradient then return end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.Top), ColorSequenceKeypoint.new(0.86, palette.Bottom),
		ColorSequenceKeypoint.new(0.861, palette.Lip), ColorSequenceKeypoint.new(1, palette.Lip),
	})
	item:SetAttribute("Palette", paletteName)
end

function HudKit.SetText(item: TextButton, value: string)
	local label = item:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then label.Text = value end
end

-- Disabled buttons drop their gradient (so no active sheen remains) as well as their input.
function HudKit.SetEnabled(item: TextButton, enabled: boolean)
	item.Active, item.Selectable = enabled, enabled
	local gradient = item:FindFirstChildOfClass("UIGradient")
	if gradient then gradient.Enabled = enabled end
	item.BackgroundColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromRGB(110, 117, 136)
end

-- Dark recessed input box (the kit's code / user box).
function HudKit.Field(parent: Instance, name: string, placeholder: string): (Frame, TextBox)
	local field = Instance.new("Frame")
	field.Name, field.BackgroundColor3, field.BorderSizePixel = name, Color3.new(1, 1, 1), 0
	field.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	field.Parent = parent
	corner(field, 4)
	stroke(field, HudKit.Colors.Ink, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(40, 44, 56), Color3.fromRGB(20, 40, 24))
	gradient.Parent = field
	local box = Instance.new("TextBox")
	box.Name, box.BackgroundTransparency, box.BorderSizePixel = "Input", 1, 0
	box.Size, box.Position, box.ZIndex = UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0), field.ZIndex + 1
	box.Font, box.TextSize, box.TextColor3 = Enum.Font.FredokaOne, 24, HudKit.Colors.White
	box.PlaceholderText, box.PlaceholderColor3 = placeholder, Color3.fromRGB(140, 146, 164)
	box.Text, box.ClearTextOnFocus, box.TextXAlignment = "", false, Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.Parent = field
	return field, box
end

function HudKit.SetToggle(bar: TextButton, on: boolean)
	local knob = bar:FindFirstChild("Knob") :: Frame
	local gradient = knob:FindFirstChildOfClass("UIGradient") :: UIGradient
	knob.Position = if on then UDim2.new(0.5, 2, 0, 4) else UDim2.fromOffset(4, 4)
	gradient.Color = if on then ColorSequence.new(Color3.fromRGB(212, 255, 0), Color3.fromRGB(0, 255, 8))
		else ColorSequence.new(Color3.fromRGB(205, 211, 224), Color3.fromRGB(128, 136, 156))
	bar:SetAttribute("On", on)
end

-- ON / OFF switch. The knob sits right (green) when on and left (grey) when off.
function HudKit.Toggle(parent: Instance, name: string): TextButton
	local bar = Instance.new("TextButton")
	bar.Name, bar.Text, bar.BorderSizePixel = name, "", 0
	bar.BackgroundColor3, bar.AutoButtonColor = HudKit.Colors.Slate, false
	bar.Active, bar.Selectable = true, true
	bar.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	bar.Parent = parent
	corner(bar, 8)
	stroke(bar, Color3.fromRGB(16, 20, 26), 2)
	local knob = Instance.new("Frame")
	knob.Name, knob.BackgroundColor3, knob.BorderSizePixel = "Knob", Color3.new(1, 1, 1), 0
	knob.Size, knob.ZIndex = UDim2.new(0.5, -4, 1, -8), bar.ZIndex + 1
	knob.Parent = bar
	corner(knob, 6)
	stroke(knob, Color3.fromRGB(16, 20, 26), 2)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = knob
	HudKit.SetToggle(bar, true)
	return bar
end

-- A drawn gold ticket for the Codes tab (the shared icon set has no code art).
function HudKit.TicketIcon(parent: Instance, size: number): Frame
	local ticket = Instance.new("Frame")
	ticket.Name, ticket.BackgroundColor3, ticket.BorderSizePixel = "Icon", Color3.new(1, 1, 1), 0
	ticket.Size, ticket.Rotation = UDim2.fromOffset(size, math.floor(size * 0.68)), -12
	ticket.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	ticket.Parent = parent
	corner(ticket, 6)
	stroke(ticket, Color3.fromRGB(120, 66, 0), 2.5)
	faceGradient(ticket, HudKit.Palettes.Yellow)
	local text = Instance.new("TextLabel")
	text.Name, text.BackgroundTransparency, text.Size = "Mark", 1, UDim2.fromScale(1, 1)
	text.Font, text.Text, text.TextScaled = Enum.Font.FredokaOne, "CODE", true
	text.TextColor3, text.ZIndex = Color3.fromRGB(120, 66, 0), ticket.ZIndex + 1
	text.Parent = ticket
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = text
	return ticket
end

return HudKit
