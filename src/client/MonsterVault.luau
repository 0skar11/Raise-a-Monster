--!strict
-- Collection presentation only. The existing server remotes retain every authority check.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)
local GuiTheme = require(script.Parent.GuiTheme)

local Vault = {}

-- Decorative tweens only: failures (e.g. a stubbed TweenService) must never break the panel.
local function play(object: Instance, seconds: number, properties: { [string]: any }, style: Enum.EasingStyle?): Tween?
	local ok, tween = pcall(function()
		return TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	end)
	if ok and tween then
		tween:Play()
		return tween
	end
	return nil
end
local SHINY = { Legendary = true, Mythic = true, Secret = true }
local C = {
	Ink = Color3.fromRGB(30, 22, 74), Panel = Color3.fromRGB(46, 34, 108), Raised = Color3.fromRGB(66, 50, 138),
	Line = Color3.fromRGB(140, 118, 210), Text = Color3.fromRGB(255, 250, 233), Muted = Color3.fromRGB(170, 192, 216),
	Gold = Color3.fromRGB(255, 201, 86), Mint = Color3.fromRGB(109, 255, 174), Cyan = Color3.fromRGB(78, 221, 255),
	Violet = Color3.fromRGB(191, 124, 255), Disabled = Color3.fromRGB(56, 70, 92),
}
local MAX_PREVIEWS = 20

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- A simple drawn egg (no assets): a rounded body in the egg's colour, three spots and a highlight.
local function buildEggArt(parent: GuiObject, name: string): Frame
	local root = Instance.new("Frame")
	root.Name, root.BorderSizePixel, root.AnchorPoint = name, 0, Vector2.new(0.5, 0.5)
	root.Position, root.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.7)
	root.Parent = parent
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio, ratio.DominantAxis = 0.78, Enum.DominantAxis.Height
	ratio.Parent = root
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = root
	for index, spot in { { 0.30, 0.38, 0.22 }, { 0.62, 0.55, 0.18 }, { 0.38, 0.72, 0.15 } } do
		local dot = Instance.new("Frame")
		dot.Name, dot.BorderSizePixel, dot.BackgroundColor3, dot.BackgroundTransparency = "Spot" .. index, 0, Color3.new(0, 0, 0), 0.82
		dot.AnchorPoint, dot.Position, dot.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(spot[1], spot[2]), UDim2.fromScale(spot[3], spot[3] * 0.78)
		dot.Parent = root
		local dotRound = Instance.new("UICorner")
		dotRound.CornerRadius = UDim.new(0.5, 0)
		dotRound.Parent = dot
	end
	local shine = Instance.new("Frame")
	shine.Name, shine.BorderSizePixel, shine.BackgroundColor3, shine.BackgroundTransparency = "Shine", 0, Color3.new(1, 1, 1), 0.55
	shine.AnchorPoint, shine.Position, shine.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.3, 0.25), UDim2.fromScale(0.14, 0.2)
	shine.Rotation = 20
	shine.Parent = root
	local shineRound = Instance.new("UICorner")
	shineRound.CornerRadius = UDim.new(0.5, 0)
	shineRound.Parent = shine
	return root
end

local function corners(item: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = item
end

local function outline(item: GuiObject, tint: Color3, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color, stroke.Thickness = tint, thickness or 1
	stroke.Parent = item
	return stroke
end

local function surface(parent: Instance, name: string, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name, frame.BackgroundColor3, frame.BorderSizePixel = name, color, 0
	frame.Parent = parent
	corners(frame, 9)
	return frame
end

local function text(parent: Instance, name: string, value: string, fontSize: number, tint: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name, label.Text, label.TextSize = name, value, fontSize
	label.TextColor3, label.BackgroundTransparency = tint or C.Text, 1
	label.Font = Enum.Font.FredokaOne
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function button(parent: Instance, name: string, caption: string, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name, item.Text, item.BackgroundColor3 = name, caption, color
	item.Font, item.TextSize, item.TextColor3 = Enum.Font.FredokaOne, 16, C.Text
	item.TextWrapped, item.AutoButtonColor, item.BorderSizePixel = true, true, 0
	item.Size = UDim2.fromOffset(100, 44)
	item.Parent = parent
	corners(item, 7)
	outline(item, C.Line)
	return item
end

local function setEnabled(item: TextButton, enabled: boolean, color: Color3)
	item.Active, item.Selectable, item.AutoButtonColor = enabled, enabled, enabled
	item.BackgroundColor3 = if enabled then color else C.Disabled
	item.TextTransparency = if enabled then 0 else 0.25
end

local function available(monster: any): boolean
	return monster ~= nil and monster.Available ~= false and not monster.Carried and not monster.InTrade
end

local function income(monster: any): number
	return monster.ActualIncome or monster.Production or 0
end

local function monsterStatus(monster: any): string
	if monster.Carried then return "Carried" end
	if monster.InTrade then return "In trade" end
	if monster.Available == false then return "In use" end
	if (monster.Slot or 0) > 0 then return "Placed · Slot " .. monster.Slot end
	return "On bench"
end

local function rarityColor(monster: any): Color3
	local rarity = Config.Rarities[monster.Rarity]
	return if rarity then rarity.Color else C.Violet
end

-- خلفية الكارت بلون الندرة (فاتحة فوق وأغمق تحت)، والـ Secret غامق عشان يبان سري
local function cardGradient(color: Color3, rarity: string?): ColorSequence
	if rarity == "Secret" then
		return ColorSequence.new(Color3.fromRGB(78, 62, 126), Color3.fromRGB(16, 11, 34))
	end
	return ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.1), color:Lerp(C.Ink, 0.55))
end

-- A model is looked up by the exact species/stage, or the local player's exact
-- monster ID. A similarly named monster belonging to another player is never used.
local function findSource(monster: any): Model?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return nil end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local catalog = if playerGui then playerGui:FindFirstChild("MonsterPortraitModels") else nil
	local appearance = table.concat({ monster.Species, monster.Stage or MonsterMath.GetStage(monster.Level).Name,
		monster.Mutation or "", monster.Hat or "", monster.Glasses or "" }, "|")
	local source = if catalog and catalog:GetAttribute("OwnerUserId") == localPlayer.UserId then catalog:FindFirstChild(appearance) else nil
	if source and source:IsA("Model") and source:GetAttribute("Species") == monster.Species then return source end
	for _, item in CollectionService:GetTagged("Monster") do
		if item:IsA("Model") and item:IsDescendantOf(workspace)
			and item:GetAttribute("OwnerUserId") == localPlayer.UserId
			and item:GetAttribute("MonsterId") == monster.Id then return item end
	end
	return nil
end

local function sanitize(copy: Model)
	for _, item in copy:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("LayerCollector") or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector") or item:IsA("ParticleEmitter") or item:IsA("Trail")
			or item:IsA("Beam") or item:IsA("Sound") or item:IsA("Light") or item:IsA("Highlight")
			or item:IsA("Fire") or item:IsA("Smoke") or item:IsA("Sparkles")
			or item:IsA("Humanoid") or item:IsA("AnimationController") or item:IsA("Animation")
			or item:IsA("Constraint") then
			item:Destroy()
		else
			for _, tag in CollectionService:GetTags(item) do CollectionService:RemoveTag(item, tag) end
			if item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery = true, false, false, false
			end
		end
	end
	for _, tag in CollectionService:GetTags(copy) do CollectionService:RemoveTag(copy, tag) end
end

-- Drop-in API for MonsterInventory.Init. No extra ScreenGui or remote listener.
function Vault.Init(ui: UI.UI, remotes: { [string]: RemoteEvent }, getState: () -> any, openMonster: ((string) -> ())?)
	local existing = ui.Gui:FindFirstChild("MonsterInventory")
	assert(not existing, "Remove the old MonsterInventory.Init call before constructing MonsterVault")
	local frame, title = UI.Panel(ui.Gui, "MonsterInventory", UDim2.fromOffset(1100, 690), "", C.Gold)
	frame.ZIndex = 30
	frame:SetAttribute("VaultBuild", 2)
	local legacyHeader = frame:FindFirstChild("Ornament")
	if legacyHeader and legacyHeader:IsA("GuiObject") then legacyHeader.Visible = false end
	-- The replacement stays inside the same modal slot and UI.Open lifecycle.
	title.Visible = false
	-- UI.Panel's generic title band sits at this panel's ZIndex and would cover the Vault's own header.
	local genericBand = frame:FindFirstChild("Ornament")
	if genericBand then genericBand:Destroy() end
	frame.BackgroundColor3 = C.Ink
	frame.ClipsDescendants = true
	GuiTheme.Backdrop(frame, 8)
	table.insert(ui.Panels, frame)
	local close = frame:FindFirstChild("CloseButton") :: TextButton
	local header = surface(frame, "VaultHeader", C.Panel)
	header.Position, header.Size = UDim2.fromOffset(5, 5), UDim2.new(1, -10, 0, 78)
	header.ZIndex = close.ZIndex
	local band = Instance.new("UIGradient")
	band.Color = ColorSequence.new(C.Raised, C.Panel)
	band.Rotation, band.Parent = 15, header
	-- A light sheen sweeps across the header every time the Vault opens.
	header.ClipsDescendants = true
	local sheen = Instance.new("Frame")
	sheen.Name, sheen.BackgroundColor3, sheen.BackgroundTransparency = "OpenSheen", Color3.new(1, 1, 1), 0.86
	sheen.BorderSizePixel, sheen.Rotation, sheen.Visible = 0, 18, false
	sheen.Size, sheen.Position = UDim2.new(0, 70, 2, 0), UDim2.new(-0.15, 0, -0.5, 0)
	sheen.Active, sheen.ZIndex = false, header.ZIndex
	sheen.Parent = header
	local sheenTween: Tween? = nil
	local sheenConnection = frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then return end
		if sheenTween then sheenTween:Cancel() end
		sheen.Position, sheen.Visible = UDim2.new(-0.15, 0, -0.5, 0), true
		sheenTween = play(sheen, 0.8, { Position = UDim2.new(1.1, 0, -0.5, 0) })
		if sheenTween then
			sheenTween.Completed:Once(function() sheen.Visible = false end)
		else
			sheen.Visible = false
		end
	end)
	local heading = text(header, "VaultTitle", "MONSTER VAULT", 31, C.Gold)
	heading.Position, heading.Size = UDim2.fromOffset(18, 4), UDim2.new(1, -292, 0, 42)
	heading.TextStrokeColor3, heading.TextStrokeTransparency = C.Ink, 0.2
	local counts = text(header, "Counts", "Your collection", 14, C.Muted)
	counts.Position, counts.Size = UDim2.fromOffset(20, 48), UDim2.new(1, -274, 0, 22)
	local auto = button(header, "AutoPlaceButton", "↔  AUTO PLACE", Color3.fromRGB(24, 124, 78))
	auto.Position, auto.Size = UDim2.new(1, -264, 0, 17), UDim2.fromOffset(198, 44)
	outline(auto, C.Mint, 2)
	close.Position, close.Size, close.ZIndex = UDim2.new(1, -58, 0, 15), UDim2.fromOffset(44, 44), 5
	close.TextSize = 24
	local rule = surface(frame, "HeaderRule", C.Gold)
	rule.Position, rule.Size = UDim2.fromOffset(8, 82), UDim2.new(1, -16, 0, 2)
	local body = Instance.new("ScrollingFrame")
	body.Name, body.BackgroundTransparency, body.BorderSizePixel = "InventoryContent", 1, 0
	body.ScrollBarThickness, body.ScrollBarImageColor3 = 4, C.Line
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.CanvasSize = UDim2.new()
	body.Parent = frame
	local left = surface(body, "CollectionPane", C.Ink)
	local tabs = surface(left, "Filters", C.Ink)
	tabs.Size = UDim2.new(1, 0, 0, 44)
	local tabButtons: { [string]: TextButton } = {}
	for index, name in { "All", "Placed", "Bench" } do
		local item = button(tabs, name .. "Tab", string.upper(name), C.Raised)
		item.Position, item.Size = UDim2.new((index - 1) / 3, 3, 0, 0), UDim2.new(1 / 3, -6, 0, 44)
		tabButtons[name] = item
	end
	local collection = Instance.new("ScrollingFrame")
	collection.Name, collection.BackgroundTransparency, collection.BorderSizePixel = "Collection", 1, 0
	collection.Position, collection.ScrollBarThickness = UDim2.fromOffset(2, 54), 4
	collection.ScrollBarImageColor3, collection.CanvasSize = C.Cyan, UDim2.new()
	collection.AutomaticCanvasSize = Enum.AutomaticSize.Y
	collection.ScrollingDirection = Enum.ScrollingDirection.Y
	collection.Parent = left
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding, grid.SortOrder = UDim2.fromOffset(10, 10), Enum.SortOrder.LayoutOrder
	grid.Parent = collection
	local empty = text(left, "EmptyCollection", "Your next monster belongs here.\nCollect one in the zones and carry it home.", 19, C.Muted)
	empty.Position, empty.Size, empty.Visible = UDim2.fromOffset(18, 110), UDim2.new(1, -36, 0, 130), false
	local slotPanel = surface(left, "SlotsPanel", C.Panel)
	outline(slotPanel, C.Line)
	local slotHeading = text(slotPanel, "SlotHeading", "BASE SLOTS", 16, C.Gold)
	slotHeading.Position, slotHeading.Size = UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 24)
	local slots = Instance.new("ScrollingFrame")
	slots.Name, slots.BackgroundTransparency, slots.BorderSizePixel = "BaseSlots", 1, 0
	slots.Position, slots.Size = UDim2.fromOffset(10, 34), UDim2.new(1, -20, 0, 66)
	slots.ScrollBarThickness, slots.ScrollBarImageColor3 = 3, C.Gold
	slots.ScrollingDirection = Enum.ScrollingDirection.X
	slots.CanvasSize, slots.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.X
	slots.Parent = slotPanel
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection, slotLayout.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 8)
	slotLayout.SortOrder, slotLayout.Parent = Enum.SortOrder.LayoutOrder, slots
	local details = surface(body, "SelectedMonster", C.Panel)
	outline(details, C.Line)
	local selectedName = text(details, "SelectedName", "CHOOSE A MONSTER", 22)
	selectedName.Position, selectedName.Size = UDim2.fromOffset(15, 8), UDim2.new(1, -30, 0, 48)
	local stage = text(details, "Stage", "Your collection, up close", 13, C.Violet)
	stage.Position, stage.Size = UDim2.fromOffset(15, 56), UDim2.new(1, -30, 0, 22)
	local hero = surface(details, "Hero", C.Ink)
	hero.ClipsDescendants = true
	local heroGradient = Instance.new("UIGradient")
	heroGradient.Color, heroGradient.Rotation, heroGradient.Parent = ColorSequence.new(C.Raised, C.Ink), 90, hero
	local stats = surface(details, "Stats", C.Ink)
	outline(stats, C.Line)
	local levelLabel = text(stats, "Level", "LEVEL\n—", 18, C.Text)
	levelLabel.Position, levelLabel.Size = UDim2.fromOffset(12, 4), UDim2.new(0.45, -12, 1, -8)
	local incomeLabel = text(stats, "Income", "INCOME\n—", 18, C.Gold)
	incomeLabel.Position, incomeLabel.Size = UDim2.new(0.45, 0, 0, 4), UDim2.new(0.55, -10, 1, -8)
	local status = text(details, "Placement", "Only placed monsters earn coins", 14, C.Mint)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local equip = button(details, "EquipToggleButton", "Select a monster", C.Raised)
	local view = button(details, "ViewMonsterButton", "View monster", C.Raised)
	local follow = button(details, "ToggleFollowerButton", "Select an adult to follow", C.Raised)
	local hint = text(details, "SelectionHint", "Select a card, then tap an unlocked base slot.", 13, C.Muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	local selectedId: string? = nil
	local filter = "All"
	local destroyed = false
	local connections: { RBXScriptConnection } = { sheenConnection }
	local cards: { [string]: any } = {}
	local eggCards: { [string]: any } = {}
	local slotRows: { [number]: any } = {}
	local portraits: { any } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local layoutQueued = false
	local controller = { Frame = frame }
	local function connect(signal: any, callback: (...any) -> ())
		table.insert(connections, signal:Connect(callback))
	end
	local function selected(): any
		local state = getState()
		for _, monster in if state then state.Monsters or {} else {} do if monster.Id == selectedId then return monster end end
		return nil
	end
	-- Eggs that wait on the bench (Slot 0) have no hatch timer yet; they live in this menu until placed.
	local function selectedEgg(): any
		local state = getState()
		for _, egg in if state then state.Eggs or {} else {} do
			if egg.Id == selectedId and (egg.Slot or 0) <= 0 then return egg end
		end
		return nil
	end
	local function makePortrait(parent: GuiObject, kind: string): any
		local viewport = Instance.new("ViewportFrame")
		viewport.Name, viewport.BackgroundTransparency = "MonsterPortrait", 1
		viewport.Size, viewport.Ambient = UDim2.fromScale(1, 1), Color3.fromRGB(205, 213, 255)
		viewport.LightColor, viewport.LightDirection = Color3.fromRGB(255, 239, 208), Vector3.new(-1, -1, -2)
		viewport.Active, viewport.Parent = false, parent
		local fallback = text(parent, "PortraitStatus", "Preview loading", 13, C.Muted)
		fallback.TextXAlignment = Enum.TextXAlignment.Center
		fallback.Position, fallback.Size = UDim2.fromScale(0, 0.4), UDim2.fromScale(1, 0.2)
		local entry = { Viewport = viewport, Fallback = fallback, Kind = kind }
		table.insert(portraits, entry)
		return entry
	end
	local heroPortrait = makePortrait(hero, "Hero")
	local heroEgg = buildEggArt(hero, "HeroEgg")
	heroEgg.Visible = false
	local function unmount(entry: any)
		if entry.World then entry.World:Destroy(); entry.World = nil end
		if entry.Camera then entry.Camera:Destroy(); entry.Camera = nil end
		entry.Viewport.CurrentCamera = nil
		entry.Key = nil
		entry.Fallback.Visible = entry.Monster ~= nil or entry.Kind == "Hero"
		entry.Fallback.Text = if entry.Kind == "Slot" then "" elseif entry.Monster then "Preview loading" else "Select a monster"
	end
	local function discardPortrait(entry: any)
		unmount(entry)
		local index = table.find(portraits, entry)
		if index then table.remove(portraits, index) end
	end
	local function previewVisible(entry: any): boolean
		if not frame.Visible or not entry.Monster or not entry.Viewport.Parent then return false end
		local item: Instance? = entry.Viewport
		local point, size = entry.Viewport.AbsolutePosition, entry.Viewport.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return false end
		while item and item ~= frame do
			if item:IsA("GuiObject") then
				if not item.Visible then return false end
				if item.ClipsDescendants then
					local p, s = item.AbsolutePosition, item.AbsoluteSize
					if point.X + size.X <= p.X or point.X >= p.X + s.X or point.Y + size.Y <= p.Y or point.Y >= p.Y + s.Y then return false end
				end
			end
			item = item.Parent
		end
		return true
	end
	local function mount(entry: any)
		local monster = entry.Monster
		local key = table.concat({ monster.Id, monster.Species, monster.Stage or "", monster.Mutation or "", monster.Hat or "", monster.Glasses or "",
			tostring(math.floor(entry.Viewport.AbsoluteSize.X)), tostring(math.floor(entry.Viewport.AbsoluteSize.Y)) }, ":")
		if entry.Key == key and entry.World and entry.World.Parent then return end
		unmount(entry)
		local source = findSource(monster)
		if not source then return end
		local copy: Model? = nil
		local world: WorldModel? = nil
		local camera: Camera? = nil
		local ok = pcall(function()
			copy = source:Clone()
			if not copy then return end
			sanitize(copy)
			world = Instance.new("WorldModel")
			copy:PivotTo(CFrame.Angles(0, math.rad(155), 0))
			copy.Parent = world
			local box, size = copy:GetBoundingBox()
			if size.Magnitude < 0.01 then error("Empty portrait") end
			camera = Instance.new("Camera")
			camera.FieldOfView = 32
			local aspect = math.max(0.4, entry.Viewport.AbsoluteSize.X / math.max(1, entry.Viewport.AbsoluteSize.Y))
			local fit = math.max(size.Y, size.X / aspect) / (2 * math.tan(math.rad(16))) + size.Z * 0.55
			local target = box.Position + Vector3.new(0, size.Y * 0.03, 0)
			camera.CFrame = CFrame.lookAt(target + Vector3.new(fit * 0.10, fit * 0.10, fit), target)
			world.Parent, camera.Parent = entry.Viewport, entry.Viewport
			entry.Viewport.CurrentCamera = camera
			entry.World, entry.Camera, entry.Key = world, camera, key
			entry.Fallback.Visible = false
		end)
		if not ok or not entry.World then
			if copy then copy:Destroy() end
			if world then world:Destroy() end
			if camera then camera:Destroy() end
		end
	end
	local function syncPortraits()
		if destroyed then return end
		local wanted: { any } = {}
		for _, entry in portraits do
			if previewVisible(entry) then table.insert(wanted, entry) else unmount(entry) end
		end
		table.sort(wanted, function(a, b)
			local ap = if a.Kind == "Hero" then 0 elseif a.Kind == "Card" then 1 else 2
			local bp = if b.Kind == "Hero" then 0 elseif b.Kind == "Card" then 1 else 2
			if ap ~= bp then return ap < bp end
			return a.Viewport.AbsolutePosition.Y < b.Viewport.AbsolutePosition.Y
		end)
		for index, entry in wanted do if index <= MAX_PREVIEWS then mount(entry) else unmount(entry) end end
	end
	local function queuePortraits()
		if layoutQueued or destroyed then return end
		layoutQueued = true
		task.defer(function() layoutQueued = false; syncPortraits() end)
	end
	local function createCard(id: string): any
		local item = button(collection, id, "", C.Raised)
		item.ClipsDescendants = true
		local border = item:FindFirstChildOfClass("UIStroke") :: UIStroke
		-- Hover pop: the card grows a touch under the cursor.
		local pop = Instance.new("UIScale")
		pop.Name, pop.Parent = "HoverPop", item
		pcall(function()
			item.MouseEnter:Connect(function() play(pop, 0.12, { Scale = 1.035 }) end)
			item.MouseLeave:Connect(function() play(pop, 0.16, { Scale = 1 }) end)
		end)
		-- Shimmer for the rarest monsters (enabled per card in Refresh).
		local shine = Instance.new("Frame")
		shine.Name, shine.BackgroundColor3, shine.BackgroundTransparency = "Shine", Color3.new(1, 1, 1), 0.87
		shine.BorderSizePixel, shine.Rotation, shine.Visible, shine.Active = 0, 20, false, false
		shine.Size, shine.Position = UDim2.new(0, 34, 1.6, 0), UDim2.new(-0.3, 0, -0.3, 0)
		shine.Parent = item
		local backdrop = Instance.new("UIGradient")
		backdrop.Color, backdrop.Rotation, backdrop.Parent = ColorSequence.new(C.Raised, C.Ink), 90, item
		-- هالة فاتحة ورا الوحش وضل بيضاوي تحت رجليه، زي كروت المجموعة
		local glow = Instance.new("Frame")
		glow.Name, glow.BorderSizePixel, glow.Active = "Glow", 0, false
		glow.AnchorPoint, glow.Position, glow.Size = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, -6), UDim2.fromScale(0.8, 0.6)
		glow.BackgroundColor3, glow.BackgroundTransparency = Color3.new(1, 1, 1), 0.88
		glow.Parent = item
		corners(glow, 999)
		local floorShadow = Instance.new("Frame")
		floorShadow.Name, floorShadow.BorderSizePixel, floorShadow.Active = "FloorShadow", 0, false
		floorShadow.AnchorPoint, floorShadow.Position, floorShadow.Size = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 1, -56), UDim2.new(0.62, 0, 0, 14)
		floorShadow.BackgroundColor3, floorShadow.BackgroundTransparency = Color3.new(0, 0, 0), 0.58
		floorShadow.Parent = item
		corners(floorShadow, 999)
		local portraitHolder = surface(item, "PortraitArea", C.Ink)
		portraitHolder.BackgroundTransparency = 1
		portraitHolder.Position, portraitHolder.Size = UDim2.fromOffset(2, 28), UDim2.new(1, -4, 1, -74)
		local portrait = makePortrait(portraitHolder, "Card")
		-- الاسم فوق بخط أبيض عريض وحدود غامقة
		local name = text(item, "MonsterName", "", 18)
		name.Position, name.Size = UDim2.new(0, 6, 0, 4), UDim2.new(1, -12, 0, 26)
		name.TextXAlignment, name.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
		name.TextWrapped, name.TextScaled = false, true
		name.TextColor3, name.TextStrokeTransparency, name.TextStrokeColor3 = Color3.new(1, 1, 1), 0, Color3.fromRGB(18, 12, 44)
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MinTextSize, nameLimit.MaxTextSize, nameLimit.Parent = 11, 19, name
		local level = text(item, "Level", "", 14, C.Cyan)
		level.Position, level.Size = UDim2.new(0, 10, 1, -24), UDim2.new(0.40, 0, 0, 22)
		local production = text(item, "Production", "", 14, C.Gold)
		production.Position, production.Size = UDim2.new(0.40, 0, 1, -24), UDim2.new(0.60, -9, 0, 22)
		production.TextXAlignment = Enum.TextXAlignment.Right
		local badge = surface(item, "PlacementBadge", C.Ink)
		badge.BackgroundTransparency = 0.4
		badge.Position, badge.Size = UDim2.new(0, 8, 1, -49), UDim2.new(1, -16, 0, 21)
		local badgeLabel = text(badge, "Status", "", 12, C.Mint)
		badgeLabel.Position, badgeLabel.Size = UDim2.fromOffset(5, 0), UDim2.new(1, -10, 1, 0)
		local connection = item.Activated:Connect(function() selectedId = id; controller.Refresh() end)
		return { Button = item, Shine = shine, ShineTween = nil, Border = border, Gradient = backdrop, Portrait = portrait, Name = name, Level = level, Income = production, Badge = badgeLabel, Connection = connection }
	end
	local function createEggCard(id: string): any
		local item = button(collection, id, "", C.Raised)
		item.ClipsDescendants = true
		local border = item:FindFirstChildOfClass("UIStroke") :: UIStroke
		local backdrop = Instance.new("UIGradient")
		backdrop.Color, backdrop.Rotation, backdrop.Parent = ColorSequence.new(C.Raised, C.Ink), 90, item
		local art = surface(item, "EggArea", C.Ink)
		art.BackgroundTransparency = 1
		art.Position, art.Size = UDim2.fromOffset(2, 30), UDim2.new(1, -4, 1, -85)
		local egg = buildEggArt(art, "Egg")
		local name = text(item, "EggName", "", 16)
		name.Position, name.Size = UDim2.new(0, 10, 1, -57), UDim2.new(1, -20, 0, 32)
		name.TextYAlignment = Enum.TextYAlignment.Center
		local kind = text(item, "Kind", "EGG", 14, C.Cyan)
		kind.Position, kind.Size = UDim2.new(0, 10, 1, -24), UDim2.new(0.40, 0, 0, 22)
		local timeLabel = text(item, "HatchTime", "", 14, C.Gold)
		timeLabel.Position, timeLabel.Size = UDim2.new(0.40, 0, 1, -24), UDim2.new(0.60, -9, 0, 22)
		timeLabel.TextXAlignment = Enum.TextXAlignment.Right
		local badge = surface(item, "WaitingBadge", C.Panel)
		badge.Position, badge.Size = UDim2.fromOffset(8, 8), UDim2.new(1, -16, 0, 25)
		outline(badge, C.Line)
		local badgeLabel = text(badge, "Status", "Waiting for a slot", 12, C.Gold)
		badgeLabel.Position, badgeLabel.Size = UDim2.fromOffset(5, 0), UDim2.new(1, -10, 1, 0)
		local connection = item.Activated:Connect(function() selectedId = id; controller.Refresh() end)
		return { Button = item, Border = border, Gradient = backdrop, Egg = egg, Name = name, Time = timeLabel, Connection = connection }
	end
	local function createSlot(index: number): any
		local item = button(slots, "Slot" .. index, "", C.Raised)
		item.Size, item.LayoutOrder, item.ClipsDescendants = UDim2.fromOffset(62, 62), index, true
		local portrait = makePortrait(item, "Slot")
		portrait.Viewport.Position, portrait.Viewport.Size = UDim2.fromOffset(0, 12), UDim2.new(1, 0, 1, -12)
		portrait.Fallback.Visible = false
		local number = text(item, "SlotNumber", tostring(index), 14)
		number.Position, number.Size, number.ZIndex = UDim2.fromOffset(5, 1), UDim2.new(1, -10, 0, 17), 2
		local caption = text(item, "SlotState", "", 11, C.Muted)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.Position, caption.Size = UDim2.fromOffset(0, 25), UDim2.new(1, 0, 0, 34)
		local connection = item.Activated:Connect(function()
			local waitingEgg, eggState = selectedEgg(), getState()
			if waitingEgg and eggState then
				-- a waiting egg goes into any free unlocked slot (it never swaps with a monster)
				if index > (eggState.UnlockedSlots or 0) or not remotes.PlaceEgg then return end
				for _, other in eggState.Eggs or {} do if other.Slot == index then return end end
				for _, occupant in eggState.Monsters or {} do if occupant.Slot == index then return end end
				remotes.PlaceEgg:FireServer(waitingEgg.Id, index)
				return
			end
			local chosen, state = selected(), getState()
			if not chosen or not state or not available(chosen) or index > (state.UnlockedSlots or 0) then return end
			for _, egg in state.Eggs or {} do if egg.Slot == index then return end end
			for _, occupant in state.Monsters or {} do if occupant.Slot == index and not available(occupant) then return end end
			remotes.PlaceMonster:FireServer(chosen.Id, index)
		end)
		return { Button = item, Portrait = portrait, Caption = caption, Connection = connection }
	end
	local function resize()
		if destroyed then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local insetA, insetB = Vector2.zero, Vector2.zero
		pcall(function() insetA, insetB = GuiService:GetGuiInset() end)
		local viewport = camera.ViewportSize - insetA - insetB
		local width, height = math.min(1100, math.max(240, viewport.X - 20)), math.min(690, math.max(200, viewport.Y - 20))
		frame.Size = UDim2.fromOffset(width, height)
		local mobile = width < 720
		local headerHeight = if mobile then 120 else 84
		header.Size = UDim2.new(1, -10, 0, headerHeight - 5)
		heading.TextSize = if mobile then 24 else 31
		heading.Size = UDim2.new(1, if mobile then -82 else -292, 0, 42)
		counts.Size = UDim2.new(1, if mobile then -32 else -274, 0, 22)
		auto.Position = if mobile then UDim2.fromOffset(18, 70) else UDim2.new(1, -264, 0, 17)
		auto.Size = if mobile then UDim2.fromOffset(180, 44) else UDim2.fromOffset(198, 44)
		rule.Position = UDim2.fromOffset(8, headerHeight)
		body.Position, body.Size = UDim2.fromOffset(12, headerHeight + 10), UDim2.new(1, -24, 1, -headerHeight - 20)
		local contentWidth = width - 28
		local contentHeight = if mobile then 1128 else math.max(440, height - headerHeight - 22) -- 440 keeps every detail button (incl. Follow) on screen in short windows
		body.CanvasSize = UDim2.fromOffset(0, contentHeight)
		local leftWidth = if mobile then contentWidth else math.floor(contentWidth * 0.64) - 6
		local leftHeight = if mobile then 546 else contentHeight
		left.Position, left.Size = UDim2.new(), UDim2.fromOffset(leftWidth, leftHeight)
		collection.Size = UDim2.fromOffset(leftWidth - 5, leftHeight - 176)
		local columns = if mobile then 2 else 3
		local cellWidth = math.floor((leftWidth - 9 - (columns - 1) * 10) / columns)
		grid.CellSize = UDim2.fromOffset(cellWidth, if mobile then 206 else math.clamp(math.floor((leftHeight - 186) / 2), 174, 218))
		grid.FillDirectionMaxCells = columns
		slotPanel.Position, slotPanel.Size = UDim2.fromOffset(1, leftHeight - 112), UDim2.fromOffset(leftWidth - 2, 108)
		local detailWidth = if mobile then contentWidth else contentWidth - leftWidth - 12
		local detailHeight = if mobile then 568 else contentHeight
		details.Position = if mobile then UDim2.fromOffset(0, 558) else UDim2.fromOffset(leftWidth + 12, 0)
		details.Size = UDim2.fromOffset(detailWidth, detailHeight)
		local heroHeight = detailHeight - 344
		hero.Position, hero.Size = UDim2.fromOffset(8, 82), UDim2.new(1, -16, 0, heroHeight)
		stats.Position, stats.Size = UDim2.fromOffset(9, 90 + heroHeight), UDim2.new(1, -18, 0, 64)
		status.Position, status.Size = UDim2.fromOffset(10, 160 + heroHeight), UDim2.new(1, -20, 0, 24)
		equip.Position, equip.Size = UDim2.fromOffset(10, detailHeight - 116), UDim2.new(0.5, -15, 0, 46)
		view.Position, view.Size = UDim2.new(0.5, 5, 0, detailHeight - 116), UDim2.new(0.5, -15, 0, 46)
		follow.Position, follow.Size = UDim2.fromOffset(10, detailHeight - 62), UDim2.new(1, -20, 0, 48)
		hint.Position, hint.Size = UDim2.fromOffset(10, detailHeight - 158), UDim2.new(1, -20, 0, 36)
		queuePortraits()
	end
	local nativeScale = Instance.new("UIScale")
	nativeScale.Name, nativeScale.Parent = "NativeInventoryScale", frame
	local globalScale = ui.Gui:FindFirstChildOfClass("UIScale")
	local function rescale()
		local camera = workspace.CurrentCamera
		local shrink = if camera then GuiTheme.ModalShrink(camera.ViewportSize) else 1
		nativeScale.Scale = (if globalScale then 1 / math.max(0.01, globalScale.Scale) else 1) * shrink
		resize()
	end
	local function connectCamera()
		if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
		local camera = workspace.CurrentCamera
		if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
		rescale()
	end
	local function firstFreeSlot(state: any): number?
		local taken: { [number]: boolean } = {}
		for _, monster in state.Monsters or {} do if (monster.Slot or 0) > 0 then taken[monster.Slot] = true end end
		for _, egg in state.Eggs or {} do if egg.Slot then taken[egg.Slot] = true end end
		for index = 1, state.UnlockedSlots or 0 do if not taken[index] then return index end end
		return nil
	end
	function controller.Refresh()
		if destroyed or not frame.Visible then return end
		local state = getState()
		if not state then return end
		local rows = table.clone(state.Monsters or {})
		table.sort(rows, function(a, b) if income(a) ~= income(b) then return income(a) > income(b) end; return a.Id < b.Id end)
		local occupants: { [number]: any } = {}
		local byId: { [string]: any } = {}
		local placed, benched = 0, 0
		for _, monster in rows do
			byId[monster.Id] = monster
			if (monster.Slot or 0) > 0 then occupants[monster.Slot] = monster; placed += 1 else benched += 1 end
		end
		local benchEggs: { any } = {}
		local eggById: { [string]: any } = {}
		for _, egg in state.Eggs or {} do
			if (egg.Slot or 0) <= 0 then table.insert(benchEggs, egg); eggById[egg.Id] = egg end
		end
		table.sort(benchEggs, function(a, b) return a.Id < b.Id end)
		local chosenEgg = if selectedId then eggById[selectedId] else nil
		local chosen = if selectedId and not chosenEgg then byId[selectedId] else nil
		if not chosen and not chosenEgg then
			chosen = rows[1]
			chosenEgg = if chosen then nil else benchEggs[1]
			selectedId = if chosen then chosen.Id elseif chosenEgg then chosenEgg.Id else nil
		end
		counts.Text = string.format("%d owned  ·  %d placed  ·  %d on bench", #rows, placed, benched)
			.. (if #benchEggs > 0 then string.format("  ·  %d egg%s waiting", #benchEggs, if #benchEggs == 1 then "" else "s") else "")
		local totals = { All = #rows + #benchEggs, Placed = placed, Bench = benched + #benchEggs }
		for name, item in tabButtons do
			item.Text = string.format("%s  %d", string.upper(name), totals[name])
			item.BackgroundColor3 = if filter == name then Color3.fromRGB(16, 107, 142) else C.Raised
			local border = item:FindFirstChildOfClass("UIStroke") :: UIStroke
			border.Color, border.Thickness = if filter == name then C.Cyan else C.Line, if filter == name then 2 else 1
		end
		for id, card in cards do
			if not byId[id] then card.Connection:Disconnect(); discardPortrait(card.Portrait); if card.ShineTween then card.ShineTween:Cancel() end; card.Button:Destroy(); cards[id] = nil end
		end
		local shown = 0
		local navigation: { GuiButton } = { close, auto, tabButtons.All, tabButtons.Placed, tabButtons.Bench }
		for _, monster in rows do
			local card = cards[monster.Id]
			if not card then card = createCard(monster.Id); cards[monster.Id] = card end
			local show = filter == "All" or filter == "Placed" and (monster.Slot or 0) > 0 or filter == "Bench" and (monster.Slot or 0) <= 0
			card.Button.Visible = show
			card.Button.Selectable = show
			if show then shown += 1; card.Button.LayoutOrder = shown; table.insert(navigation, card.Button) end
			card.Name.Text, card.Level.Text = monster.DisplayName or monster.Species, "Lv " .. monster.Level
			card.Income.Text = MonsterMath.FormatNumber(income(monster)) .. "/s"
			card.Badge.Text = monsterStatus(monster) .. (if monster.Following then " · Following" else "")
			card.Badge.TextColor3 = if (monster.Slot or 0) > 0 then C.Mint else C.Muted
			card.Border.Color, card.Border.Thickness = if selectedId == monster.Id then C.Mint else rarityColor(monster):Lerp(C.Line, 0.45), if selectedId == monster.Id then 3 else 1.5
			card.Gradient.Color = cardGradient(rarityColor(monster), monster.Rarity)
			-- the rarest cards glint every few seconds (one looping tween with a pause between sweeps)
			local shiny = show and SHINY[monster.Rarity or ""] == true
			card.Shine.Visible = shiny
			if shiny and not card.ShineTween then
				card.Shine.Position = UDim2.new(-0.3, 0, -0.3, 0)
				local ok, tween = pcall(function()
					return TweenService:Create(card.Shine, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, 2.6 + (#monster.Id % 7) * 0.4), { Position = UDim2.new(1.2, 0, -0.3, 0) })
				end)
				if ok and tween then card.ShineTween = tween; tween:Play() end
			elseif not shiny and card.ShineTween then
				card.ShineTween:Cancel()
				card.ShineTween = nil
			end
			card.Portrait.Monster = monster
		end
		-- Waiting eggs come first (All and Bench tabs), each with its colour and the hatch time it will start with.
		for id, card in eggCards do
			if not eggById[id] then card.Connection:Disconnect(); card.Button:Destroy(); eggCards[id] = nil end
		end
		for index, egg in benchEggs do
			local card = eggCards[egg.Id]
			if not card then card = createEggCard(egg.Id); eggCards[egg.Id] = card end
			local definition = Config.Eggs[egg.EggType]
			local tint = if definition then definition.Color else C.Gold
			local show = filter ~= "Placed"
			card.Button.Visible, card.Button.Selectable = show, show
			if show then shown += 1; card.Button.LayoutOrder = index - 100000; table.insert(navigation, card.Button) end
			card.Name.Text = if definition then definition.DisplayName else "Egg"
			card.Time.Text = "⏱ " .. clock(egg.SecondsLeft or (definition and definition.HatchTime) or 0)
			card.Egg.BackgroundColor3 = tint
			card.Border.Color, card.Border.Thickness = if selectedId == egg.Id then C.Mint else tint:Lerp(C.Line, 0.45), if selectedId == egg.Id then 3 else 1.5
			card.Gradient.Color = cardGradient(tint)
		end
		empty.Visible = shown == 0
		empty.Text = if #rows == 0 and #benchEggs == 0 then "Your next monster belongs here.\nCollect one in the zones and carry it home." else "No monsters here yet.\nTry another collection tab."
		local eggs: { [number]: boolean } = {}
		for _, egg in state.Eggs or {} do if egg.Slot then eggs[egg.Slot] = true end end
		for index, slot in slotRows do
			if index > (state.MaxSlots or 0) then slot.Connection:Disconnect(); discardPortrait(slot.Portrait); slot.Button:Destroy(); slotRows[index] = nil end
		end
		for index = 1, state.MaxSlots or 0 do
			local slot = slotRows[index]
			if not slot then slot = createSlot(index); slotRows[index] = slot end
			local occupant = occupants[index]
			local unlocked = index <= (state.UnlockedSlots or 0)
			local usable = unlocked and not eggs[index] and (not occupant or available(occupant))
			local eggFits = chosenEgg ~= nil and unlocked and not eggs[index] and not occupant
			slot.Button.Active = (chosen ~= nil and available(chosen) and usable) or eggFits
			slot.Button.Selectable = slot.Button.Active
			slot.Button.AutoButtonColor = slot.Button.Active
			if slot.Button.Selectable then table.insert(navigation, slot.Button) end
			slot.Portrait.Monster = if unlocked and not eggs[index] then occupant else nil
			slot.Caption.Text = if not unlocked then "LOCKED" elseif eggs[index] then "EGG" elseif not occupant then "EMPTY" else ""
			slot.Button.BackgroundColor3 = if not unlocked then C.Disabled else C.Raised
			local border = slot.Button:FindFirstChildOfClass("UIStroke") :: UIStroke
			border.Color = if chosen and chosen.Slot == index then C.Mint elseif slot.Button.Active then C.Gold else C.Line
		end
		heroPortrait.Monster = chosen
		selectedName.Text = if chosen then chosen.DisplayName or chosen.Species else "CHOOSE A MONSTER"
		stage.Text = if chosen then string.upper(chosen.Rarity or "") .. "  ·  " .. string.upper(chosen.Stage or MonsterMath.GetStage(chosen.Level).Name) else "Your collection, up close"
		stage.TextColor3 = if chosen then rarityColor(chosen) else C.Violet
		heroGradient.Color = ColorSequence.new(if chosen then rarityColor(chosen):Lerp(C.Panel, 0.78) else C.Raised, C.Ink)
		levelLabel.Text = if chosen then "LEVEL\n" .. chosen.Level else "LEVEL\n—"
		incomeLabel.Text = if chosen then (if (chosen.Slot or 0) > 0 then "INCOME\n" else "POTENTIAL\n") .. MonsterMath.FormatNumber(income(chosen)) .. "/s" else "INCOME\n—"
		status.Text = if chosen then monsterStatus(chosen) else "Only placed monsters earn coins"
		setEnabled(view, openMonster ~= nil and available(chosen), C.Raised)
		-- Equip puts the selected monster in the first free unlocked base slot; Unequip sends it back to the bench.
		local isPlaced = chosen ~= nil and (chosen.Slot or 0) > 0
		local freeSlot = firstFreeSlot(state)
		local usable = chosen ~= nil and available(chosen)
		setEnabled(equip, usable and (isPlaced or freeSlot ~= nil), if isPlaced then Color3.fromRGB(150, 60, 70) else Color3.fromRGB(23, 105, 72))
		equip.Text = if not chosen then "Select a monster"
			elseif not usable then "In use"
			elseif isPlaced then "Unequip"
			elseif freeSlot then string.format("Equip  ·  slot %d", freeSlot)
			else "No free slot"
		local followerCount, followerLimit = #(state.FollowingIds or {}), state.FollowerLimit or Config.Followers.MaxCount
		local minimumLevel = state.FollowerMinLevel or Config.Followers.MinLevel
		local isFollowing = chosen ~= nil and chosen.Following == true
		local canFollow = available(chosen) and chosen.CanFollow == true and followerCount < followerLimit
		setEnabled(follow, isFollowing or canFollow, if isFollowing then Color3.fromRGB(23, 105, 72) else Color3.fromRGB(64, 49, 112))
		follow.Text = if isFollowing then string.format("Stop following · %d/%d", followerCount, followerLimit)
			elseif not chosen then string.format("Select an adult · %d/%d following", followerCount, followerLimit)
			elseif not available(chosen) then "Unavailable while carried or in use"
			elseif chosen.Level < minimumLevel then string.format("Adult Lv %d+ required", minimumLevel)
			elseif followerCount >= followerLimit then string.format("%d/%d following · stop one first", followerCount, followerLimit)
			elseif canFollow then string.format("Follow · %d/%d · +damage", followerCount, followerLimit)
			else "Unavailable to follow"
		heroEgg.Visible = chosenEgg ~= nil
		if chosenEgg then
			local definition = Config.Eggs[chosenEgg.EggType]
			local tint = if definition then definition.Color else C.Gold
			heroPortrait.Monster = nil
			heroEgg.BackgroundColor3 = tint
			heroGradient.Color = ColorSequence.new(tint:Lerp(C.Panel, 0.78), C.Ink)
			selectedName.Text = if definition then definition.DisplayName else "Egg"
			stage.Text, stage.TextColor3 = "EGG  ·  WAITING FOR A SLOT", C.Gold
			levelLabel.Text = "HATCH TIME\n" .. clock(chosenEgg.SecondsLeft or (definition and definition.HatchTime) or 0)
			incomeLabel.Text = "TIMER STARTS\nWHEN PLACED"
			status.Text = "Waiting in your Pets menu"
			hint.Text = "Tap a free base slot, or press Place, to start the hatch timer."
			setEnabled(view, false, C.Raised)
			setEnabled(equip, freeSlot ~= nil, Color3.fromRGB(23, 105, 72))
			equip.Text = if freeSlot then string.format("Place egg  ·  slot %d", freeSlot) else "No free slot"
			setEnabled(follow, false, C.Raised)
			follow.Text = "Eggs cannot follow"
		end
		hint.Text = if chosenEgg then "Tap a free base slot, or press Place, to start the hatch timer." elseif chosen then "Tap an unlocked base slot to place or swap.\nOnly placed monsters earn coins." else "Select a card, then tap an unlocked base slot."
		for _, item in { equip, view, follow } do if item.Selectable then table.insert(navigation, item) end end
		for index, item in navigation do
			item.NextSelectionDown, item.NextSelectionUp = navigation[index % #navigation + 1], navigation[(index - 2) % #navigation + 1]
		end
		local focused = GuiService.SelectedObject
		if focused and focused:IsDescendantOf(frame) and (not focused.Selectable or not focused.Visible) then GuiService.SelectedObject = auto end
		queuePortraits()
	end
	function controller.Open()
		if destroyed then return end
		UI.Open(ui, frame)
		controller.Refresh()
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = auto end
	end
	function controller.Destroy()
		if destroyed then return end
		destroyed = true
		for _, connection in connections do connection:Disconnect() end
		if cameraConnection then cameraConnection:Disconnect() end
		for _, card in cards do card.Connection:Disconnect() end
		for _, slot in slotRows do slot.Connection:Disconnect() end
		for _, portrait in portraits do unmount(portrait) end
		local index = table.find(ui.Panels, frame)
		if index then table.remove(ui.Panels, index) end
		frame:Destroy()
	end
	for name, item in tabButtons do connect(item.Activated, function() filter = name; collection.CanvasPosition = Vector2.zero; controller.Refresh() end) end
	connect(auto.Activated, function() remotes.AutoPlaceMonsters:FireServer() end)
	connect(view.Activated, function() local monster = selected(); if openMonster and available(monster) then openMonster(monster.Id) end end)
	connect(equip.Activated, function()
		local waitingEgg, eggState = selectedEgg(), getState()
		if waitingEgg and eggState then
			local freeSlot = firstFreeSlot(eggState)
			if freeSlot and remotes.PlaceEgg then remotes.PlaceEgg:FireServer(waitingEgg.Id, freeSlot) end
			return
		end
		local monster, state = selected(), getState()
		if not monster or not state or not available(monster) then return end
		if (monster.Slot or 0) > 0 then
			remotes.BenchMonster:FireServer(monster.Id)
		else
			local slot = firstFreeSlot(state)
			if slot then remotes.PlaceMonster:FireServer(monster.Id, slot) end
		end
	end)
	connect(follow.Activated, function()
		local monster, state = selected(), getState()
		local capacity = state and #(state.FollowingIds or {}) < (state.FollowerLimit or Config.Followers.MaxCount)
		if monster and (monster.Following == true or available(monster) and monster.CanFollow == true and capacity) then remotes.ToggleFollower:FireServer(monster.Id) end
	end)
	connect(frame:GetPropertyChangedSignal("Visible"), function()
		if frame.Visible then controller.Refresh() else for _, entry in portraits do unmount(entry) end end
	end)
	connect(body:GetPropertyChangedSignal("CanvasPosition"), queuePortraits)
	connect(collection:GetPropertyChangedSignal("CanvasPosition"), queuePortraits)
	connect(slots:GetPropertyChangedSignal("CanvasPosition"), queuePortraits)
	connect(collection:GetPropertyChangedSignal("AbsoluteSize"), queuePortraits)
	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), connectCamera)
	if globalScale then connect(globalScale:GetPropertyChangedSignal("Scale"), rescale) end
	-- Template replication can complete after the collection has opened.
	if ui.Gui.Parent then
		connect(ui.Gui.Parent.DescendantAdded, function(item)
			if frame.Visible and (item:IsA("Model") or item:IsA("BasePart")) then queuePortraits() end
		end)
	end
	connectCamera()
	return controller
end

Vault.Create = Vault.Init
return Vault
