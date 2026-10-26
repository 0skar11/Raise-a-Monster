--!strict
-- Egg Keeper monster store. Presentation only: prices are Robux; the server validates, opens the Marketplace prompt
-- and grants the eggs / Luck only from the purchase receipt.
-- The buttons only ever send a bundle size (1/3/8) or "buy luck"; the odds shown come from the same shared math.
-- Look: a chunky cartoon "Store" window (outlined white text, glossy green buy buttons, dark rounded outcome tiles).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EggStoreMath = require(ReplicatedStorage.Shared.EggStoreMath)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)

local settings = Config.EggStore

local EggStore = {}

local ORANGE = Color3.fromRGB(255, 122, 24)
local ORANGE_DARK = Color3.fromRGB(190, 78, 8)
local PURPLE = Color3.fromRGB(122, 52, 190)
local GREEN = Color3.fromRGB(86, 214, 56)
local GREEN_LIGHT = Color3.fromRGB(150, 246, 96)
local GREEN_DARK = Color3.fromRGB(28, 112, 28)
local GRAY = Color3.fromRGB(128, 134, 148)
local GRAY_DARK = Color3.fromRGB(62, 66, 78)
local INK = Color3.fromRGB(14, 12, 34)
local GLOW = Color3.fromRGB(255, 226, 96)
local WHITE = Color3.new(1, 1, 1)

local WIDTH, HEIGHT = 700, 580
local CARD_HEIGHT = 364

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius <= 1 then UDim.new(radius, 0) else UDim.new(0, radius)
	corner.Parent = parent
end

local function outline(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = color, thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function gradient(parent: Instance, colors: { Color3 }, rotation: number): UIGradient
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / math.max(1, #colors - 1), color))
	end
	local item = Instance.new("UIGradient")
	item.Color = ColorSequence.new(points)
	item.Rotation = rotation
	item.Parent = parent
	return item
end

local function box(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, radius: number?): Frame
	local item = Instance.new("Frame")
	item.Name, item.Size, item.Position, item.BackgroundColor3 = name, size, position, color
	item.BorderSizePixel = 0
	item.Parent = parent
	if radius then round(item, radius) end
	return item
end

-- Bold white text with a heavy dark outline.
local function shout(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number, color: Color3?): TextLabel
	local item = UI.Label(parent, text, size, position, textSize)
	item.TextColor3 = color or WHITE
	item.TextStrokeColor3, item.TextStrokeTransparency = INK, 0
	item.TextWrapped = false
	return item
end

-- The width of the egg picture at a height offset from its centre (a stadium: round top and bottom).
local function chord(dy: number, width: number, height: number): number
	local radius = width / 2
	local straight = height / 2 - radius
	local d = math.abs(dy)
	if d <= straight then return width end
	return 2 * math.sqrt(math.max(0, radius ^ 2 - (d - straight) ^ 2))
end

-- Monster pictures: the server builds a baby-stage preview per species into PlayerGui.MonsterPortraitModels.
local function previewFor(species: string): Model?
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local catalog = if gui then gui:FindFirstChild("MonsterPortraitModels") else nil
	local key = table.concat({ species, MonsterMath.GetStage(1).Name, "", "", "" }, "|")
	local model = if catalog then catalog:FindFirstChild(key) else nil
	return if model and model:IsA("Model") then model else nil
end

local function mountPortrait(viewport: ViewportFrame, species: string): boolean
	local source = previewFor(species)
	if not source then return false end
	local mounted = pcall(function()
		local copy = source:Clone()
		local world = Instance.new("WorldModel")
		copy:PivotTo(CFrame.Angles(0, math.rad(155), 0))
		copy.Parent = world
		local center, size = copy:GetBoundingBox()
		if size.Magnitude < 0.01 then error("empty preview") end
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		local aspect = if viewport.AbsoluteSize.Y > 1 then math.max(0.4, viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y) else 1.4
		local fit = math.max(size.Y, size.X / aspect) / (2 * math.tan(math.rad(16))) + size.Z * 0.55
		local target = center.Position + Vector3.new(0, size.Y * 0.03, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(fit * 0.1, fit * 0.1, fit), target)
		world.Parent, camera.Parent = viewport, viewport
		viewport.CurrentCamera = camera
	end)
	return mounted
end

-- The drawn Halloween egg: glossy orange body, purple bands and spots, glowing carved pumpkin face.
local function drawEgg(parent: GuiObject, centerX: number, centerY: number): Frame
	local W, H = 112, 142
	local holder = box(parent, "EggPicture", UDim2.fromOffset(W + 24, H + 30), UDim2.fromOffset(centerX - (W + 24) / 2, centerY - (H + 30) / 2), WHITE)
	holder.BackgroundTransparency = 1
	local cx, cy = (W + 24) / 2, (H + 30) / 2 - 4

	local shadow = box(holder, "Shadow", UDim2.fromOffset(W * 0.86, 16), UDim2.fromOffset(cx - W * 0.43, cy + H / 2 - 4), INK, 0.5)
	shadow.BackgroundTransparency = 0.55

	local glow = box(holder, "Glow", UDim2.fromOffset(W + 22, H + 22), UDim2.fromOffset(cx - (W + 22) / 2, cy - (H + 22) / 2), Color3.fromRGB(255, 190, 80), 0.5)
	glow.BackgroundTransparency = 0.78

	local body = box(holder, "Body", UDim2.fromOffset(W, H), UDim2.fromOffset(cx - W / 2, cy - H / 2), ORANGE, 0.5)
	gradient(body, { Color3.fromRGB(255, 186, 70), Color3.fromRGB(255, 122, 24), Color3.fromRGB(214, 84, 10) }, 90)
	outline(body, Color3.fromRGB(104, 42, 8), 4)

	for index, dy in { -H * 0.27, H * 0.30 } do
		local width = chord(dy, W, H) - 2
		local band = box(body, "Band" .. index, UDim2.fromOffset(width, 15), UDim2.fromOffset((W - width) / 2, H / 2 + dy - 7), PURPLE)
		gradient(band, { Color3.fromRGB(160, 90, 230), Color3.fromRGB(98, 40, 160) }, 90)
		-- zigzag dots along the band
		for step = 0, 3 do
			local dot = box(band, "Dot", UDim2.fromOffset(6, 6), UDim2.fromOffset(width * (0.14 + step * 0.24) - 3, 4.5), Color3.fromRGB(255, 190, 80), 0.5)
			dot.BackgroundTransparency = 0.1
		end
	end
	for _, spot in { { -0.33, -0.05, 12 }, { 0.3, 0.08, 10 }, { -0.28, 0.43, 9 }, { 0.32, -0.42, 9 } } do
		local dot = box(body, "Spot", UDim2.fromOffset(spot[3], spot[3]), UDim2.fromOffset(W / 2 + spot[1] * W - spot[3] / 2, H / 2 + spot[2] * H - spot[3] / 2), PURPLE, 0.5)
		dot.BackgroundTransparency = 0.15
	end

	-- carved face
	local function glowShape(name: string, size: Vector2, x: number, y: number, rotation: number, radius: number): Frame
		local shape = box(body, name, UDim2.fromOffset(size.X, size.Y), UDim2.fromOffset(x - size.X / 2, y - size.Y / 2), GLOW, radius)
		shape.Rotation = rotation
		gradient(shape, { Color3.fromRGB(255, 250, 170), Color3.fromRGB(255, 190, 40) }, 90)
		outline(shape, Color3.fromRGB(110, 40, 6), 2.5)
		return shape
	end
	glowShape("EyeL", Vector2.new(24, 15), W / 2 - 19, H / 2 - 14, 24, 3)
	glowShape("EyeR", Vector2.new(24, 15), W / 2 + 19, H / 2 - 14, -24, 3)
	glowShape("Nose", Vector2.new(11, 11), W / 2, H / 2 + 1, 45, 2)
	local mouth = glowShape("Mouth", Vector2.new(58, 22), W / 2, H / 2 + 19, 0, 8)
	for index, x in { 0.2, 0.42, 0.64 } do
		local tooth = box(mouth, "ToothTop" .. index, UDim2.fromOffset(7, 7), UDim2.fromOffset(58 * x - 3.5, -1), ORANGE_DARK, 1)
		tooth.BackgroundColor3 = Color3.fromRGB(150, 56, 8)
	end
	for index, x in { 0.31, 0.53, 0.75 } do
		local tooth = box(mouth, "ToothBottom" .. index, UDim2.fromOffset(7, 7), UDim2.fromOffset(58 * x - 3.5, 16), ORANGE_DARK, 1)
		tooth.BackgroundColor3 = Color3.fromRGB(150, 56, 8)
	end

	-- glossy highlight
	local shine = box(body, "Shine", UDim2.fromOffset(20, 42), UDim2.fromOffset(15, 20), WHITE, 0.5)
	shine.BackgroundTransparency = 0.5
	shine.Rotation = 18
	local shineDot = box(body, "ShineDot", UDim2.fromOffset(9, 9), UDim2.fromOffset(20, 68), WHITE, 0.5)
	shineDot.BackgroundTransparency = 0.5
	return holder
end

-- A four-leaf clover built from shapes (each leaf is a heart: two lobes and a diamond).
local function drawClover(parent: GuiObject, centerX: number, centerY: number): Frame
	local size = 124
	local holder = box(parent, "Clover", UDim2.fromOffset(size, size), UDim2.fromOffset(centerX - size / 2, centerY - size / 2), WHITE)
	holder.BackgroundTransparency = 1
	local middle = size / 2
	local function heart(leaf: Frame, grow: number, color: Color3)
		local lobe = 36 + grow
		for _, side in { -1, 1 } do
			local circle = box(leaf, "Lobe", UDim2.fromOffset(lobe, lobe), UDim2.fromOffset(32 + side * 15 - lobe / 2, 30 - 10 - lobe / 2 + 4), color, 0.5)
			circle.BackgroundColor3 = color
		end
		local tip = box(leaf, "Tip", UDim2.fromOffset(30 + grow, 30 + grow), UDim2.fromOffset(32 - (30 + grow) / 2, 34 - (30 + grow) / 2 + 6), color, 3)
		tip.Rotation = 45
	end
	local leaves: { Frame } = {}
	for index, angle in { 0, 90, 180, 270 } do
		local radians = math.rad(angle)
		local leaf = box(holder, "Leaf" .. index, UDim2.fromOffset(64, 64), UDim2.fromOffset(middle + math.sin(radians) * 25 - 32, middle - math.cos(radians) * 25 - 32), WHITE)
		leaf.BackgroundTransparency = 1
		leaf.Rotation = angle
		table.insert(leaves, leaf)
	end
	for _, leaf in leaves do heart(leaf, 7, Color3.fromRGB(16, 84, 20)) end
	for _, leaf in leaves do
		heart(leaf, 0, Color3.fromRGB(52, 184, 40))
	end
	-- lighter inner shine on each leaf
	for _, leaf in leaves do
		local shineLeaf = box(leaf, "Shine", UDim2.fromOffset(16, 9), UDim2.fromOffset(14, 14), Color3.fromRGB(190, 255, 150), 0.5)
		shineLeaf.BackgroundTransparency = 0.45
		shineLeaf.Rotation = -30
	end
	local stem = box(holder, "Stem", UDim2.fromOffset(9, 40), UDim2.fromOffset(middle + 10, middle + 20), Color3.fromRGB(40, 140, 40), 4)
	stem.Rotation = -35
	stem.ZIndex = 0
	outline(stem, Color3.fromRGB(20, 96, 24), 2)
	return holder
end

local function styleBuy(button: TextButton, enabled: boolean)
	button.BackgroundColor3 = WHITE
	local border = button:FindFirstChildOfClass("UIStroke")
	if border then border.Color = if enabled then GREEN_DARK else GRAY_DARK end
	local grad = button:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = if enabled
			then ColorSequence.new(GREEN_LIGHT, GREEN, Color3.fromRGB(44, 160, 36))
			else ColorSequence.new(Color3.fromRGB(170, 176, 190), GRAY, Color3.fromRGB(98, 104, 118))
	end
end

-- A chunky green buy button: Robux price on top, the bold label below.
local function buyButton(parent: GuiObject, name: string, size: UDim2, position: UDim2, price: number, title: string, priceSize: number, titleSize: number): TextButton
	local button = UI.Button(parent, "", GREEN, size, position)
	button.Name = name
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(0, 14) end
	for _, child in button:GetChildren() do
		if child:IsA("UIGradient") then child:Destroy() end
	end
	local border = button:FindFirstChildOfClass("UIStroke")
	if border then border.Thickness = 3.5 end
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = button
	local row = box(button, "PriceRow", UDim2.new(1, 0, if title == "" then 1 else 0.46, 0), UDim2.fromOffset(0, if title == "" then 0 else 4), WHITE)
	row.BackgroundTransparency = 1
	row.ZIndex = button.ZIndex + 3
	-- Robux price in the same "R$ 99" style as the repo's other paid UI (Pumpkin Titan summon, Adult skips).
	local amount = shout(row, "R$ " .. tostring(price), UDim2.fromScale(1, 1), UDim2.new(), priceSize)
	amount.Name = "Price"
	amount.TextXAlignment = Enum.TextXAlignment.Center
	amount.TextYAlignment = Enum.TextYAlignment.Center
	amount.ZIndex = row.ZIndex
	if title ~= "" then
		local text = shout(button, title, UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, 0.47), titleSize)
		text.Name = "Title"
		text.TextStrokeColor3 = GREEN_DARK
		text.TextStrokeTransparency = 0
		text.ZIndex = button.ZIndex + 3
	end
	styleBuy(button, true)
	return button
end

function EggStore.Init(ui: UI.UI, remotes: { [string]: RemoteEvent }, getState: () -> any)
	local player = Players.LocalPlayer
	local luckLeft, luckAt = 0, os.clock()

	local frame, titleLabel = UI.Panel(ui.Gui, "EggStore", UDim2.fromOffset(WIDTH, HEIGHT), "Store", Color3.fromRGB(255, 168, 28))
	table.insert(ui.Panels, frame)
	frame.BackgroundColor3 = Color3.fromRGB(255, 232, 150)
	local baseDisplayOrder = ui.Gui.DisplayOrder

	-- little red shop icon in the title bar, like the reference
	titleLabel.Position = UDim2.fromOffset(66, 6)
	local shop = box(frame, "ShopIcon", UDim2.fromOffset(44, 36), UDim2.fromOffset(16, 10), Color3.fromRGB(226, 40, 64), 8)
	shop.ZIndex = 4
	outline(shop, Color3.fromRGB(120, 12, 30), 2.5)
	gradient(shop, { Color3.fromRGB(255, 96, 112), Color3.fromRGB(196, 24, 52) }, 90)
	for index = 0, 2 do
		local stripe = box(shop, "Stripe" .. index, UDim2.fromOffset(10, 11), UDim2.fromOffset(4 + index * 13, 3), WHITE, 3)
		stripe.ZIndex = 5
	end
	local window = box(shop, "Window", UDim2.fromOffset(30, 11), UDim2.fromOffset(7, 20), Color3.fromRGB(255, 214, 120), 4)
	window.ZIndex = 5

	-- Phones and small windows: shrink the whole window to fit.
	local fit = Instance.new("UIScale")
	fit.Parent = frame
	local function rescale()
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		fit.Scale = math.clamp(math.min((view.X - 16) / WIDTH, (view.Y - 24) / HEIGHT), 0.3, 1.1)
	end
	rescale()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale) end

	-- Egg card -----------------------------------------------------------------------------------------
	local card = box(frame, "EggCard", UDim2.new(1, -24, 0, CARD_HEIGHT), UDim2.fromOffset(12, 60), Color3.fromRGB(122, 52, 190), 18)
	gradient(card, { Color3.fromRGB(104, 52, 200), Color3.fromRGB(214, 70, 170), Color3.fromRGB(255, 132, 36), Color3.fromRGB(255, 206, 64) }, 28)
	outline(card, Color3.fromRGB(58, 24, 100), 3.5)
	card.ClipsDescendants = true
	for index, spec in { { 90, 40, 70 }, { 300, 250, 50 }, { 480, 30, 90 }, { 600, 270, 60 }, { 30, 280, 44 } } do
		local bubble = box(card, "Sparkle" .. index, UDim2.fromOffset(spec[3], spec[3]), UDim2.fromOffset(spec[1], spec[2]), WHITE, 0.5)
		bubble.BackgroundTransparency = 0.88
	end

	local heading = shout(card, "Halloween Egg!", UDim2.new(1, -150, 0, 44), UDim2.fromOffset(150, 2), 36)
	heading.TextXAlignment = Enum.TextXAlignment.Center

	drawEgg(card, 76, 150)
	local tag = box(card, "NewTag", UDim2.fromOffset(64, 26), UDim2.fromOffset(2, 12), Color3.fromRGB(255, 62, 86), 13)
	tag.Rotation = -16
	tag.ZIndex = 6
	outline(tag, WHITE, 2)
	gradient(tag, { Color3.fromRGB(255, 110, 124), Color3.fromRGB(230, 30, 62) }, 90)
	local tagText = shout(tag, "NEW!", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 20)
	tagText.ZIndex = 7
	local eggNote = shout(card, "Up to Mythic!", UDim2.fromOffset(140, 22), UDim2.fromOffset(6, 232), 17, Color3.fromRGB(255, 240, 150))

	-- Outcome tiles: one per monster the egg can hatch, with the live odds (Luck included).
	local weights = Config.Eggs[settings.Egg].Weights
	local species: { string } = {}
	for name in weights do table.insert(species, name) end
	table.sort(species, function(a, b)
		if weights[a] ~= weights[b] then return weights[a] > weights[b] end
		return a < b
	end)
	local rarest = species[#species]

	local tilesHolder = box(card, "Outcomes", UDim2.fromOffset(514, 224), UDim2.fromOffset(150, 50), WHITE)
	tilesHolder.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.CellSize, grid.CellPadding = UDim2.fromOffset(122, 108), UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tilesHolder

	local tiles: { [string]: { Odds: TextLabel, Up: Frame } } = {}
	local waiting: { { Viewport: ViewportFrame, Species: string, Placeholder: TextLabel } } = {}
	for index, name in species do
		local definition = Config.Species[name]
		local rarity = Config.Rarities[definition.Rarity]
		local top = name == rarest
		local tile = box(tilesHolder, name, UDim2.fromOffset(122, 108), UDim2.new(), Color3.fromRGB(40, 24, 66), 14)
		tile.LayoutOrder = index
		gradient(tile, { Color3.fromRGB(70, 42, 108), Color3.fromRGB(26, 14, 46) }, 90)
		outline(tile, if top then GLOW else rarity.Color:Lerp(INK, 0.35), if top then 3.5 else 2.5)

		local backdrop = box(tile, "Backdrop", UDim2.fromOffset(100, 100), UDim2.fromOffset(11, -4), rarity.Color, 0.5)
		backdrop.BackgroundTransparency = 0.82

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Portrait"
		viewport.BackgroundTransparency = 1
		viewport.Size, viewport.Position = UDim2.new(1, -8, 0, 64), UDim2.fromOffset(4, 18)
		viewport.Ambient, viewport.LightColor = Color3.fromRGB(205, 213, 255), Color3.fromRGB(255, 239, 208)
		viewport.LightDirection = Vector3.new(-1, -1, -2)
		viewport.Active = false
		viewport.Parent = tile
		local placeholder = shout(tile, "...", UDim2.fromOffset(100, 40), UDim2.fromOffset(11, 30), 24)
		placeholder.TextColor3 = rarity.Color
		if mountPortrait(viewport, name) then
			placeholder:Destroy()
		else
			table.insert(waiting, { Viewport = viewport, Species = name, Placeholder = placeholder })
		end

		local nameLabel = shout(tile, definition.DisplayName, UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 3), 13, Color3.fromRGB(236, 228, 255))
		nameLabel.TextStrokeTransparency = 0.25
		local odds = shout(tile, "", UDim2.new(1, -4, 0, 24), UDim2.fromOffset(2, 82), 22, rarity.Color:Lerp(WHITE, 0.2))
		odds.Name = "Odds"
		local up = box(tile, "LuckUp", UDim2.fromOffset(30, 16), UDim2.new(1, -34, 0, 20), Color3.fromRGB(72, 210, 60), 8)
		outline(up, WHITE, 1.5)
		up.Visible = false
		up.ZIndex = 8
		local upText = shout(up, "UP", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 11)
		upText.ZIndex = 9
		if top then
			local ribbon = box(tile, "Ribbon", UDim2.fromOffset(62, 17), UDim2.new(0.5, -31, 0, -9), Color3.fromRGB(255, 190, 40), 9)
			ribbon.ZIndex = 8
			outline(ribbon, INK, 2)
			local ribbonText = shout(ribbon, "ODDS", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 12, Color3.fromRGB(70, 28, 6))
			ribbonText.TextStrokeTransparency = 1
			ribbonText.ZIndex = 9
		end
		tiles[name] = { Odds = odds, Up = up }
	end

	local function refreshOdds(luckActive: boolean)
		local base = EggStoreMath.Odds(weights, false)
		local live = EggStoreMath.Odds(weights, luckActive)
		for name, tile in tiles do
			tile.Odds.Text = string.format("%.1f%%", live[name])
			tile.Up.Visible = live[name] > base[name] + 0.001
		end
	end

	-- Buy buttons --------------------------------------------------------------------------------------
	local buttons: { { Button: TextButton, Price: number } } = {}
	local buttonWidth = (WIDTH - 24 - 24 - 20) / 3
	for index, bundle in settings.Bundles do
		local price = EggStoreMath.BundlePrice(bundle)
		local button = buyButton(card, "Buy" .. bundle.Count, UDim2.fromOffset(buttonWidth, 62), UDim2.fromOffset(12 + (index - 1) * (buttonWidth + 10), CARD_HEIGHT - 78), price, string.format("Buy %d", bundle.Count), 20, 28)
		if bundle.Discount > 0 then
			local save = box(button, "Save", UDim2.fromOffset(58, 22), UDim2.new(1, -62, 0, -10), Color3.fromRGB(255, 62, 86), 11)
			outline(save, WHITE, 2)
			gradient(save, { Color3.fromRGB(255, 110, 124), Color3.fromRGB(226, 28, 60) }, 90)
			save.ZIndex = button.ZIndex + 6
			save.Rotation = 4
			local saveText = shout(save, string.format("-%d%%", math.floor(bundle.Discount * 100 + 0.5)), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 15)
			saveText.ZIndex = save.ZIndex + 1
		end
		button.Activated:Connect(function()
			remotes.BuyEggBundle:FireServer(bundle.Count)
		end)
		table.insert(buttons, { Button = button, Price = price })
	end

	-- Luck card ----------------------------------------------------------------------------------------
	local luck = box(frame, "LuckCard", UDim2.new(1, -24, 0, 128), UDim2.fromOffset(12, 60 + CARD_HEIGHT + 12), Color3.fromRGB(96, 214, 60), 18)
	gradient(luck, { Color3.fromRGB(150, 240, 96), Color3.fromRGB(70, 180, 50), Color3.fromRGB(48, 150, 44) }, 90)
	outline(luck, GREEN_DARK, 3.5)
	luck.ClipsDescendants = true
	for index, spec in { { 150, -20, 90 }, { 380, 70, 70 }, { 280, -30, 50 } } do
		local ray = box(luck, "Shine" .. index, UDim2.fromOffset(spec[3], spec[3]), UDim2.fromOffset(spec[1], spec[2]), WHITE, 0.5)
		ray.BackgroundTransparency = 0.88
	end
	drawClover(luck, 76, 66)
	local luckTitle = shout(luck, "EGG LUCK", UDim2.fromOffset(300, 36), UDim2.fromOffset(150, 8), 32)
	luckTitle.TextXAlignment = Enum.TextXAlignment.Left
	local luckBig = shout(luck, string.format("x%d + %d min", settings.Luck.Multiplier, math.floor(settings.Luck.Duration / 60)), UDim2.fromOffset(300, 48), UDim2.fromOffset(150, 42), 42, Color3.fromRGB(255, 244, 150))
	luckBig.TextXAlignment = Enum.TextXAlignment.Left
	local luckInfo = UI.Label(luck, "Boosts Legendary + Mythic odds of Halloween Eggs", UDim2.fromOffset(330, 30), UDim2.fromOffset(150, 94), 14)
	luckInfo.TextColor3 = Color3.fromRGB(14, 66, 18)
	luckInfo.TextXAlignment = Enum.TextXAlignment.Left
	luckInfo.TextYAlignment = Enum.TextYAlignment.Top
	local luckButton = buyButton(luck, "BuyLuck", UDim2.fromOffset(150, 62), UDim2.new(1, -164, 0.5, -42), settings.Luck.Price, "", 24, 24)
	local luckTimer = shout(luck, "", UDim2.fromOffset(150, 24), UDim2.new(1, -164, 0.5, 26), 18, Color3.fromRGB(255, 244, 150))

	-- Refresh (the server still decides; this only greys buttons that cannot work) ------------------------
	local function refresh()
		-- Robux items are always buyable; only Luck greys out at its time cap (the server refuses it before any prompt).
		for _, entry in buttons do
			styleBuy(entry.Button, true)
		end
		local timeLeft = math.max(0, luckLeft - (os.clock() - luckAt))
		styleBuy(luckButton, timeLeft + settings.Luck.Duration <= settings.Luck.MaxSeconds)
		luckTimer.Text = if timeLeft > 0 then clock(timeLeft) .. " left" else ""
		refreshOdds(timeLeft > 0) -- the boosted odds drop by themselves when the timer runs out
		for index = #waiting, 1, -1 do
			local entry = waiting[index]
			if not entry.Viewport.Parent then
				table.remove(waiting, index)
			elseif mountPortrait(entry.Viewport, entry.Species) then
				entry.Placeholder:Destroy()
				table.remove(waiting, index)
			end
		end
	end
	luckButton.Activated:Connect(function()
		remotes.BuyEggLuck:FireServer()
	end)

	local function setLuck(state: any)
		luckLeft = if type(state) == "table" and type(state.LuckLeft) == "number" then math.max(0, state.LuckLeft) else 0
		luckAt = os.clock()
		refresh()
	end

	remotes.OpenEggStore.OnClientEvent:Connect(function(state: any)
		setLuck(state)
		UI.Open(ui, frame)
	end)
	remotes.EggStoreState.OnClientEvent:Connect(setLuck)

	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		ui.Gui.DisplayOrder = if frame.Visible then math.max(baseDisplayOrder, 10) else baseDisplayOrder
	end)

	-- Timers tick locally; the store closes when you walk away from the keeper.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 or not frame.Visible then
			return
		end
		accumulator = 0
		refresh()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local keeper = CollectionService:GetTagged("EggKeeper")[1]
		local anchor = keeper and keeper:FindFirstChild("Torso")
		if not root or not anchor or not anchor:IsA("BasePart") or not root:IsA("BasePart")
			or (root.Position - anchor.Position).Magnitude > settings.Npc.StoreDistance * 1.3 then
			frame.Visible = false
		end
	end)
	refresh()
end

return EggStore
