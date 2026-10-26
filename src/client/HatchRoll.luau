--!strict
-- The egg-hatch roll. The server has already decided and saved the monster (MonsterService.hatch fires HatchResult);
-- this only animates a reel of every monster the egg can give and lands on that result. Mockup: docs/hatch-roll-prototype.html
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local HatchRollMath = require(ReplicatedStorage.Shared.HatchRollMath)
local GuiTheme = require(script.Parent.GuiTheme)

local HatchRoll = {}

export type Result = { EggType: string, Species: string, Mutation: string?, Slot: number, MonsterId: string }

local CARD_W, CARD_H, GAP = 132, 176, 10
local STEP = CARD_W + GAP
local REEL_W, REEL_H = 748, 196
local WIN_INDEX, TOTAL = HatchRollMath.WinIndex, HatchRollMath.TotalCards
local pctText, secretPct, mutationOdds = HatchRollMath.PctText, HatchRollMath.SecretPct, HatchRollMath.MutationOdds
local INK = Color3.fromRGB(12, 16, 31)
local TEXT = Color3.fromRGB(255, 251, 235)
local FONT = Enum.Font.FredokaOne
local PARTICLES = { Common = 10, Uncommon = 18, Rare = 32, Epic = 50, Legendary = 75, Mythic = 100, Secret = 90 }
local SHAKE = { Common = 0, Uncommon = 0, Rare = 4, Epic = 8, Legendary = 14, Mythic = 20, Secret = 24 }

-- Roblox's own built-in sounds (they ship with the client, so there is nothing to upload or license).
local SOUNDS = {
	Tick = "rbxasset://sounds/clickfast.wav", -- reel card passing the pointer
	Crack = "rbxasset://sounds/snap.mp3", -- egg shell cracking
	Burst = "rbxasset://sounds/impact_explosion_03.mp3", -- egg bursts open
	Open = "rbxasset://sounds/action_jump.mp3", -- the roll window swooshes in
	Land = "rbxasset://sounds/bass.wav", -- the reel settles
	Thump = "rbxasset://sounds/action_jump_land.mp3",
	Ping = "rbxasset://sounds/electronicpingshort.wav", -- reveal chime, pitched by rarity
	Fanfare = "rbxasset://sounds/victory.wav", -- Legendary and above
	Button = "rbxasset://sounds/button.wav", -- Collect
	Skip = "rbxasset://sounds/switch.wav",
}
local SFX_SCALE = Config.Audio.SfxVolume / 0.5 -- the game's SFX volume setting (0.5 = as authored)

local RARITY_WHITE = Color3.fromRGB(255, 255, 255)
local function rarityColor(rarity: string): Color3
	local info = Config.Rarities[rarity]
	return if info then info.Color else Config.Rarities.Common.Color
end
local function rarityOrder(rarity: string): number
	local info = Config.Rarities[rarity]
	return if info then info.Order else 1
end

-- ---------------------------------------------------------------- gui helpers

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end
local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.ApplyStrokeMode = color, thickness, Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name, f.Size, f.Position, f.BorderSizePixel = name, size, position, 0
	f.BackgroundColor3 = color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = if color then 0 else 1
	f.ZIndex = z or 2
	f.Active = false
	f.Parent = parent
	return f
end
local function label(parent: Instance, name: string, text: string, size: number, position: UDim2, dimensions: UDim2, color: Color3?, z: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name, l.Text, l.TextSize, l.Font = name, text, size, FONT
	l.TextColor3, l.BackgroundTransparency = color or TEXT, 1
	l.TextStrokeColor3, l.TextStrokeTransparency = INK, 0.35
	l.Position, l.Size, l.ZIndex = position, dimensions, z or 3
	l.Active = false
	l.Parent = parent
	return l
end
local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- ---------------------------------------------------------------- monster previews (server-built, see MonsterPortraits.Request)

local function previewKey(species: string): string
	return table.concat({ species, MonsterMath.GetStage(1).Name, "", "", "" }, "|")
end

local function findPreview(species: string): Model?
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local catalog = if gui then gui:FindFirstChild("MonsterPortraitModels") else nil
	local model = if catalog then catalog:FindFirstChild(previewKey(species)) else nil
	if model and model:IsA("Model") then return model end
	return nil
end

-- Clones the preview into a ViewportFrame. false = not available (yet); the caller keeps a placeholder and retries.
local function mountModel(viewport: ViewportFrame, species: string, yaw: number): boolean
	local source = findPreview(species)
	if not source then return false end
	local ok = pcall(function()
		local copy = source:Clone()
		local world = Instance.new("WorldModel")
		copy:PivotTo(CFrame.Angles(0, math.rad(yaw), 0))
		copy.Parent = world
		local box, size = copy:GetBoundingBox()
		if size.Magnitude < 0.01 then error("empty preview") end
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		-- AbsoluteSize can still be zero right after parenting; a roughly square frame is the safe default
		local aspect = if viewport.AbsoluteSize.Y > 1 then math.max(0.4, viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y) else 1.1
		local fit = math.max(size.Y, size.X / aspect) / (2 * math.tan(math.rad(16))) + size.Z * 0.55
		local target = box.Position + Vector3.new(0, size.Y * 0.03, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(fit * 0.10, fit * 0.10, fit), target)
		world.Parent, camera.Parent = viewport, viewport
		viewport.CurrentCamera = camera
	end)
	return ok
end

local function newViewport(parent: Instance, z: number): ViewportFrame
	local v = Instance.new("ViewportFrame")
	v.Name, v.BackgroundTransparency, v.ZIndex, v.Active = "Model", 1, z, false
	v.Ambient, v.LightColor, v.LightDirection = Color3.fromRGB(205, 213, 255), Color3.fromRGB(255, 239, 208), Vector3.new(-1, -1, -2)
	v.Parent = parent
	return v
end

-- ---------------------------------------------------------------- one roll

local roll: { Gui: ScreenGui?, Skip: boolean, Done: boolean } = { Gui = nil, Skip = false, Done = false }
local activeCleanup: (() -> ())? = nil
local tickers: { [string]: (number) -> () } = {}
local tickerConnection: RBXScriptConnection? = nil

local function setTicker(name: string, fn: ((number) -> ())?)
	tickers[name] = fn :: any
	if next(tickers) and not tickerConnection then
		tickerConnection = RunService.RenderStepped:Connect(function(dt)
			for _, step in tickers do step(dt) end
		end)
	elseif not next(tickers) and tickerConnection then
		tickerConnection:Disconnect()
		tickerConnection = nil
	end
end

local function clamp01(x: number): number return math.clamp(x, 0, 1) end

local function runRoll(result: Result, fast: boolean, more: boolean, getState: () -> any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local species = Config.Species[result.Species]
	local egg = Config.Eggs[result.EggType]
	local rarity = species.Rarity
	local color = if rarity == "Secret" then RARITY_WHITE else rarityColor(rarity)
	local order = rarityOrder(rarity)
	local accent = if egg then egg.Color:Lerp(Color3.fromRGB(180, 90, 230), 0.25) else GuiTheme.Colors.Pink
	local t = if fast then 0.45 else 1
	local random = Random.new()
	roll.Skip, roll.Done = false, false

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.DisplayOrder, gui.ResetOnSpawn, gui.IgnoreGuiInset = "HatchRoll", 500, false, true -- above the boss bar and every HUD
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	roll.Gui = gui

	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local scaleFactor = math.clamp(math.min(view.X / 820, view.Y / 640), 0.42, 1.15)

	local dim = frame(gui, "Dim", UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(6, 5, 24), 1)
	dim.BackgroundTransparency = 1
	dim.Active = true -- swallow clicks behind the roll
	tween(dim, 0.25, { BackgroundTransparency = 0.25 })

	local stage = frame(gui, "Stage", UDim2.fromScale(1, 1), UDim2.new(), nil, 2)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scaleFactor
	uiScale.Parent = stage

	local connections: { RBXScriptConnection } = {}
	local alive = true
	local function cleanup()
		alive = false
		for _, c in connections do c:Disconnect() end
		setTicker("spin", nil); setTicker("rays", nil); setTicker("particles", nil); setTicker("hero", nil); setTicker("waiters", nil)
		gui:Destroy()
		roll.Gui = nil
		activeCleanup = nil
	end
	activeCleanup = cleanup

	-- Sounds live in the ScreenGui (played as 2D sounds) so Settings' sound routing and mute cover them automatically.
	local lastTick = 0
	local function sfx(name: string, volume: number?, speed: number?)
		if not alive then return end
		local sound = Instance.new("Sound")
		sound.SoundId = SOUNDS[name]
		sound.Volume = math.clamp((volume or 0.5) * SFX_SCALE, 0, 2)
		sound.PlaybackSpeed = speed or 1
		sound.Parent = gui
		sound.Ended:Once(function() sound:Destroy() end)
		sound:Play()
		task.delay(6, function() if sound.Parent then sound:Destroy() end end)
	end
	local function tickSound(cardRarityName: string)
		local now = os.clock()
		if now - lastTick < (if fast then 0.06 else 0.04) then return end
		lastTick = now
		sfx("Tick", if fast then 0.25 else 0.4, 0.85 + rarityOrder(cardRarityName) * 0.09)
	end
	-- the reveal chime climbs with rarity: one ping, an arpeggio, then a fanfare for the big ones
	local function revealSound(rarityName: string)
		local rank = rarityOrder(rarityName)
		if rarityName == "Secret" then
			sfx("Land", 1, 0.5)
			sfx("Burst", 0.5, 0.6)
			sfx("Fanfare", 0.5, 0.7)
			for i, speed in { 0.7, 0.6, 0.5 } do task.delay(0.18 * i, sfx, "Ping", 0.5, speed) end
			return
		end
		local notes = { 1, 1.19, 1.5, 1.78 }
		for i = 1, math.clamp(rank - 1, 1, 4) do task.delay(0.1 * (i - 1), sfx, "Ping", 0.5, notes[i] * (0.8 + rank * 0.04)) end
		if rank >= 4 then sfx("Thump", 0.6, 1.1) end
		if rank >= 5 then sfx("Fanfare", 0.5, 1) end
		if rank >= 6 then sfx("Burst", 0.4, 1.7) end
	end

	-- particles (small frames simulated on RenderStepped; capped for mobile)
	local particles: { { Frame: Frame, X: number, Y: number, VX: number, VY: number, Life: number, Max: number, Spin: number } } = {}
	local fxLayer = frame(gui, "Fx", UDim2.fromScale(1, 1), UDim2.new(), nil, 40)
	local function burst(x: number, y: number, amount: number, colors: { Color3 }, speed: number)
		for _ = 1, math.min(amount, 110 - #particles) do
			local p = Instance.new("Frame")
			local s = random:NextInteger(5, 10)
			p.Size, p.BorderSizePixel, p.BackgroundColor3 = UDim2.fromOffset(s, s), 0, colors[random:NextInteger(1, #colors)]
			p.AnchorPoint, p.ZIndex = Vector2.new(0.5, 0.5), 41
			p.Position = UDim2.fromOffset(x, y)
			p.Parent = fxLayer
			local angle, v = random:NextNumber() * math.pi * 2, speed * (0.35 + random:NextNumber() * 0.9)
			table.insert(particles, { Frame = p, X = x, Y = y, VX = math.cos(angle) * v, VY = math.sin(angle) * v - speed * 0.25, Life = 0, Max = 0.9 + random:NextNumber() * 0.9, Spin = (random:NextNumber() - 0.5) * 12 })
		end
		setTicker("particles", function(dt)
			for i = #particles, 1, -1 do
				local p = particles[i]
				p.Life += dt
				p.VY += 900 * dt
				p.X += p.VX * dt
				p.Y += p.VY * dt
				if p.Life >= p.Max then
					p.Frame:Destroy()
					table.remove(particles, i)
				else
					p.Frame.Position = UDim2.fromOffset(p.X, p.Y)
					p.Frame.Rotation += p.Spin
					p.Frame.BackgroundTransparency = clamp01((p.Life / p.Max - 0.5) * 2)
				end
			end
			if #particles == 0 then setTicker("particles", nil) end
		end)
	end
	local function shake(amount: number)
		if amount <= 0 then return end
		task.spawn(function()
			for i = 1, 10 do
				if not alive then return end
				local fall = 1 - i / 10
				stage.Position = UDim2.fromOffset(random:NextNumber(-amount, amount) * fall, random:NextNumber(-amount, amount) * fall)
				task.wait(0.03)
			end
			if alive then stage.Position = UDim2.new() end
		end)
	end
	local center = Vector2.new(view.X / 2, view.Y / 2)

	-- skip / collect input
	local collectRequested = false
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
			if roll.Done then collectRequested = true else roll.Skip = true end
		elseif input.KeyCode == Enum.KeyCode.Escape and roll.Done then
			collectRequested = true
		end
	end))

	-- 1. the egg cracks (models for the reel are being built by the server meanwhile) -----------------------------------
	local eggColor = if egg then egg.Color else Color3.fromRGB(235, 225, 200)
	local eggFrame = frame(stage, "Egg", UDim2.fromOffset(150, 190), UDim2.fromOffset(center.X / scaleFactor, center.Y / scaleFactor), eggColor, 3)
	eggFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(eggFrame, 75)
	stroke(eggFrame, INK, 4)
	for _, spot in { { 0.3, 0.55, 0.2 }, { 0.65, 0.4, 0.16 }, { 0.55, 0.75, 0.22 } } do
		local dot = frame(eggFrame, "Spot", UDim2.fromScale(spot[3], spot[3] * 0.8), UDim2.fromScale(spot[1], spot[2]), Color3.new(0, 0, 0), 4)
		dot.BackgroundTransparency = 0.82
		corner(dot, 40)
	end
	local flash = frame(gui, "Flash", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1), 50)
	flash.BackgroundTransparency = 1
	flash.Active = false
	local crackStart = os.clock()
	local crackLength = 2.2 * t
	local cracksHeard = 0
	setTicker("spin", function()
		local u = clamp01((os.clock() - crackStart) / crackLength)
		if cracksHeard < 3 and u > ({ 0.3, 0.6, 0.85 })[cracksHeard + 1] then
			cracksHeard += 1
			sfx("Crack", 0.55, 0.85 + cracksHeard * 0.15)
		end
		local power = 3 + u * u * 14
		eggFrame.Rotation = math.sin(os.clock() * (10 + u * 26)) * power
		local pulse = 1 + u * u * 0.08
		eggFrame.Size = UDim2.fromOffset(150 * pulse, 190 * pulse)
	end)
	while alive and os.clock() - crackStart < crackLength and not roll.Skip do task.wait() end
	if not alive then return end
	roll.Skip = false
	setTicker("spin", nil)
	sfx("Burst", 0.6, 1.5)
	flash.BackgroundTransparency = 0.05
	tween(flash, 0.4, { BackgroundTransparency = 1 })
	burst(center.X, center.Y, 34, { eggColor, Color3.new(1, 1, 1), accent }, 520)
	shake(8)
	eggFrame:Destroy()

	-- 2. the roll ---------------------------------------------------------------------------------------------------
	local panel = frame(stage, "Panel", UDim2.fromOffset(780, 590), UDim2.fromOffset(view.X / 2 / scaleFactor, view.Y / 2 / scaleFactor), GuiTheme.Colors.Panel, 5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	sfx("Open", 0.5, 1.3)
	corner(panel, 4)
	stroke(panel, INK, 3)
	GuiTheme.Backdrop(panel, 4)
	GuiTheme.Dress(panel, accent)
	local panelScale = Instance.new("UIScale")
	panelScale.Scale = 0.82
	panelScale.Parent = panel
	tween(panelScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	label(panel, "Title", egg and string.upper(egg.DisplayName) or "EGG", 26, UDim2.fromOffset(18, 6), UDim2.fromOffset(420, 48), TEXT, 8).TextXAlignment = Enum.TextXAlignment.Left
	local sub = label(panel, "Sub", "Hatching…", 18, UDim2.new(1, -250, 0, 6), UDim2.fromOffset(232, 48), TEXT, 8)
	sub.TextXAlignment = Enum.TextXAlignment.Right

	local reel = frame(panel, "Reel", UDim2.fromOffset(REEL_W, REEL_H), UDim2.fromOffset(16, 76), Color3.fromRGB(16, 18, 52), 6)
	reel.ClipsDescendants = true
	corner(reel, 4)
	local reelStroke = stroke(reel, INK, 3)
	local track = frame(reel, "Track", UDim2.fromOffset(TOTAL * STEP, REEL_H), UDim2.new(), nil, 6)
	local strip = HatchRollMath.BuildStrip(result.EggType, result.Species, random)
	local cards: { Frame } = {}
	local cardScales: { UIScale } = {}
	local waiters: { { Viewport: ViewportFrame, Species: string, Yaw: number, Placeholder: TextLabel } } = {}
	local cardRarity: { string } = {}
	for index, entry in strip do
		local sp = Config.Species[entry.Key]
		local mystery = entry.Mystery == true
		local r = if mystery then "Secret" else sp.Rarity
		local rc = if mystery or r == "Secret" then RARITY_WHITE else rarityColor(r)
		cardRarity[index] = r
		local card = frame(track, "Card" .. index, UDim2.fromOffset(CARD_W, CARD_H), UDim2.fromOffset((index - 1) * STEP, 10), rc:Lerp(GuiTheme.Colors.PanelLight, 0.78), 7)
		corner(card, 5)
		stroke(card, INK, 3)
		local bottom = frame(card, "Bottom", UDim2.new(1, -6, 0, 5), UDim2.new(0, 3, 1, -8), rc, 8)
		bottom.BackgroundTransparency = 0.1
		local cs = Instance.new("UIScale")
		cs.Parent = card
		cards[index], cardScales[index] = card, cs
		local holder = frame(card, "ModelHolder", UDim2.new(1, -8, 0, 108), UDim2.fromOffset(4, 6), nil, 8)
		if mystery then
			local q = label(holder, "Q", "?", 78, UDim2.new(), UDim2.fromScale(1, 1), TEXT, 9)
			q.TextTransparency = 0.05
		else
			local viewport = newViewport(holder, 9)
			viewport.Size = UDim2.fromScale(1, 1)
			local placeholder = label(holder, "Loading", "…", 28, UDim2.new(), UDim2.fromScale(1, 1), GuiTheme.Colors.SubText, 9)
			if mountModel(viewport, entry.Key, 155) then placeholder:Destroy() else table.insert(waiters, { Viewport = viewport, Species = entry.Key, Yaw = 155, Placeholder = placeholder }) end
		end
		local name = label(card, "Name", if mystery then "???" else sp.DisplayName, 15, UDim2.fromOffset(2, 116), UDim2.new(1, -4, 0, 22), TEXT, 9)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		label(card, "Pct", pctText(entry.Pct), 21, UDim2.fromOffset(2, 138), UDim2.new(1, -4, 0, 28), rc, 9)
	end
	-- models still being built by the server: keep trying for a few seconds, never error
	local waitStart = os.clock()
	setTicker("waiters", function()
		if os.clock() - waitStart > 10 or #waiters == 0 then setTicker("waiters", nil); return end
		for i = #waiters, 1, -1 do
			local w = waiters[i]
			if not w.Viewport.Parent then
				table.remove(waiters, i)
			elseif mountModel(w.Viewport, w.Species, w.Yaw) then
				w.Placeholder:Destroy()
				table.remove(waiters, i)
			end
		end
	end)

	local function edge(name: string, left: boolean)
		local e = frame(reel, name, UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(if left then 0 else 0.82, 0), Color3.fromRGB(16, 18, 52), 12)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new(if left then 0 else 1, if left then 1 else 0)
		g.Parent = e
	end
	edge("EdgeL", true)
	edge("EdgeR", false)
	local pointer = frame(reel, "Pointer", UDim2.fromOffset(4, REEL_H), UDim2.new(0.5, -2, 0, 0), Color3.new(1, 1, 1), 14)
	pointer.BackgroundTransparency = 0.15
	for _, top in { true, false } do
		local arrow = label(reel, "Arrow", if top then "▼" else "▲", 26, UDim2.new(0.5, -14, if top then 0 else 1, if top then -4 else -26), UDim2.fromOffset(28, 28), GuiTheme.Colors.Yellow, 15)
		arrow.TextStrokeTransparency = 0
	end
	local skip = Instance.new("TextButton")
	skip.Name, skip.Text, skip.Font, skip.TextSize, skip.TextColor3 = "Skip", "Skip ⏭", FONT, 15, TEXT
	skip.BackgroundColor3, skip.BackgroundTransparency, skip.ZIndex = INK, 0.25, 16
	skip.Size, skip.Position = UDim2.fromOffset(74, 28), UDim2.new(1, -82, 0, 8)
	skip.AutoButtonColor = true
	corner(skip, 4)
	skip.Parent = reel
	table.insert(connections, skip.Activated:Connect(function() sfx("Skip", 0.5, 1); roll.Skip = true end))
	local status = label(panel, "Status", "Rolling…", 19, UDim2.fromOffset(16, 276), UDim2.fromOffset(REEL_W, 26), GuiTheme.Colors.SubText, 8)

	-- legend: every monster in the egg with its odds
	local legend = frame(panel, "Legend", UDim2.fromOffset(REEL_W, 270), UDim2.fromOffset(16, 308), Color3.fromRGB(16, 18, 54), 6)
	legend.BackgroundTransparency = 0.25
	corner(legend, 4)
	stroke(legend, INK, 3)
	local pool = HatchRollMath.PoolFor(result.EggType)
	label(legend, "Heading", "WHAT'S INSIDE", 16, UDim2.fromOffset(10, 4), UDim2.fromOffset(300, 22), GuiTheme.Colors.Yellow, 8).TextXAlignment = Enum.TextXAlignment.Left
	local count = label(legend, "Count", #pool .. " possible monsters", 14, UDim2.new(1, -250, 0, 4), UDim2.fromOffset(240, 22), GuiTheme.Colors.SubText, 8)
	count.TextXAlignment = Enum.TextXAlignment.Right
	local byRarity: { [string]: number } = {}
	for _, entry in pool do
		if not entry.Mystery then
			local r = Config.Species[entry.Key].Rarity
			byRarity[r] = (byRarity[r] or 0) + entry.Pct
		end
	end
	local rarityList: { string } = {}
	for r in byRarity do table.insert(rarityList, r) end
	table.sort(rarityList, function(a, b) return rarityOrder(a) < rarityOrder(b) end)
	local bar = frame(legend, "OddsBar", UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 30), INK, 8)
	corner(bar, 3)
	local sumPct = 0
	for _, r in rarityList do sumPct += byRarity[r] end
	local used = 0
	local summary: { string } = {}
	for _, r in rarityList do
		local w = byRarity[r] / math.max(sumPct, 1)
		local seg = frame(bar, r, UDim2.new(w, 0, 1, 0), UDim2.fromScale(used, 0), rarityColor(r), 9)
		used += w
		table.insert(summary, r .. " " .. pctText(byRarity[r]))
	end
	label(legend, "Summary", table.concat(summary, "  ·  "), 13, UDim2.fromOffset(10, 44), UDim2.new(1, -20, 0, 20), GuiTheme.Colors.SubText, 8).TextXAlignment = Enum.TextXAlignment.Left
	local grid = frame(legend, "Grid", UDim2.new(1, -20, 0, 150), UDim2.fromOffset(10, 68), nil, 8)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize, layout.CellPadding = UDim2.fromOffset(176, 46), UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local gridWaiters: { { Viewport: ViewportFrame, Species: string, Placeholder: TextLabel? } } = {}
	for index, entry in pool do
		local r = if entry.Mystery then "Secret" else Config.Species[entry.Key].Rarity
		local rc = if r == "Secret" then RARITY_WHITE else rarityColor(r)
		local cell = frame(grid, "Cell" .. index, UDim2.fromOffset(176, 46), UDim2.new(), GuiTheme.Colors.Panel, 9)
		cell.LayoutOrder = index
		corner(cell, 4)
		stroke(cell, INK, 2)
		frame(cell, "Accent", UDim2.new(0, 5, 1, -6), UDim2.fromOffset(3, 3), rc, 10)
		local thumb = frame(cell, "Thumb", UDim2.fromOffset(40, 40), UDim2.fromOffset(12, 3), nil, 10)
		if entry.Mystery then
			label(thumb, "Q", "?", 30, UDim2.new(), UDim2.fromScale(1, 1), TEXT, 11)
		else
			local vp = newViewport(thumb, 11)
			vp.Size = UDim2.fromScale(1, 1)
			if not mountModel(vp, entry.Key, 155) then table.insert(gridWaiters, { Viewport = vp, Species = entry.Key }) end
		end
		local n = label(cell, "Name", if entry.Mystery then "Secret ???" else Config.Species[entry.Key].DisplayName, 14, UDim2.fromOffset(56, 4), UDim2.fromOffset(78, 22), TEXT, 10)
		n.TextXAlignment, n.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
		local rl = label(cell, "Rarity", r, 12, UDim2.fromOffset(56, 24), UDim2.fromOffset(78, 16), rc, 10)
		rl.TextXAlignment = Enum.TextXAlignment.Left
		local pl = label(cell, "Pct", pctText(entry.Pct), 17, UDim2.new(1, -62, 0, 0), UDim2.fromOffset(58, 46), rc, 10)
		pl.TextXAlignment = Enum.TextXAlignment.Right
	end
	if #gridWaiters > 0 then
		task.spawn(function()
			local started = os.clock()
			while alive and #gridWaiters > 0 and os.clock() - started < 10 do
				for i = #gridWaiters, 1, -1 do
					local w = gridWaiters[i]
					if not w.Viewport.Parent or mountModel(w.Viewport, w.Species, 155) then table.remove(gridWaiters, i) end
				end
				task.wait(0.25)
			end
		end)
	end
	local notes: { string } = {}
	local hasMystery = pool[#pool] ~= nil and pool[#pool].Mystery == true
	if hasMystery then
		table.insert(notes, string.format("Odds above are for this egg's own monsters. Separately, every hatch has a %s chance of a Secret monster instead.", pctText(secretPct(result.EggType))))
	end
	local mutationParts: { string } = {}
	for _, m in mutationOdds() do table.insert(mutationParts, string.format("%s %s (x%g)", m.Name, pctText(m.Pct), m.Mult)) end
	table.insert(notes, "Mutation chance on any monster: " .. table.concat(mutationParts, " · "))
	local foot = label(legend, "Foot", table.concat(notes, "\n"), 12, UDim2.new(0, 10, 1, -50), UDim2.new(1, -20, 0, 46), GuiTheme.Colors.SubText, 8)
	foot.TextWrapped, foot.TextXAlignment, foot.TextYAlignment = true, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top

	-- the spin: fast start, long ease-out, small overshoot that settles back, then a glide to the exact centre
	task.wait(0.45 * t)
	local jitter = (random:NextNumber() * 0.56 - 0.28) * CARD_W
	local distance = (WIN_INDEX - 1) * STEP + CARD_W / 2 + jitter - REEL_W / 2
	local over = CARD_W * (0.14 + random:NextNumber() * 0.1)
	local k = if order >= 4 then 4.6 else 3.5
	local duration = if fast then 2.6 else 5.2
	local settle = 0.5 * t + 0.05
	local lastIndex, hot = 0, nil :: Frame?
	local function setHot(index: number)
		if hot then
			local previous = table.find(cards, hot)
			if previous then tween(cardScales[previous], 0.1, { Scale = 1 }) end
		end
		local card = cards[index]
		hot = card
		if card then
			tween(cardScales[index], 0.08, { Scale = 1.1 })
			local r = cardRarity[index]
			reelStroke.Color = if r == "Secret" then RARITY_WHITE else rarityColor(r)
		end
	end
	local started = os.clock()
	local position = 0
	while alive do
		local elapsed = os.clock() - started
		if roll.Skip then position = distance; break end
		if elapsed < duration then
			position = (distance + over) * (1 - (1 - elapsed / duration) ^ k)
		elseif elapsed < duration + settle then
			local u = (elapsed - duration) / settle
			local e = if u < 0.5 then 2 * u * u else 1 - (-2 * u + 2) ^ 2 / 2
			position = distance + over * (1 - e)
		else
			position = distance
			break
		end
		track.Position = UDim2.fromOffset(-position, 0)
		local index = math.floor((position + REEL_W / 2) / STEP) + 1
		if index ~= lastIndex and index >= 1 and index <= TOTAL then
			lastIndex = index
			setHot(index)
			tickSound(cardRarity[index])
		end
		RunService.RenderStepped:Wait()
	end
	if not alive then return end
	roll.Skip = false
	skip.Visible = false
	-- glide the winner exactly under the pointer
	local glideFrom, glideStart = position, os.clock()
	while alive and os.clock() - glideStart < 0.32 * t + 0.02 do
		local u = clamp01((os.clock() - glideStart) / (0.32 * t + 0.02))
		local e = 1 - (1 - u) ^ 3
		track.Position = UDim2.fromOffset(-(glideFrom - jitter * e), 0)
		RunService.RenderStepped:Wait()
	end
	if not alive then return end
	track.Position = UDim2.fromOffset(-(distance - jitter), 0)
	setHot(WIN_INDEX)
	reelStroke.Color = color
	status.Text = "It's " .. species.DisplayName .. "!"
	sfx("Land", 0.7, 1.1)
	sfx("Thump", 0.5, 0.9)
	task.wait(0.55 * t)

	-- 3. reveal -----------------------------------------------------------------------------------------------------------
	roll.Done = true
	local reveal = frame(gui, "Reveal", UDim2.fromScale(1, 1), UDim2.new(), nil, 20)
	local back = frame(reveal, "Back", UDim2.fromScale(1, 1), UDim2.new(), if rarity == "Secret" then Color3.fromRGB(4, 2, 12) else color:Lerp(Color3.fromRGB(6, 5, 24), 0.85), 1)
	back.BackgroundTransparency = 1
	tween(back, 0.5, { BackgroundTransparency = 0.08 })
	local heroSize = math.floor(math.min(view.Y * 0.36, view.X * 0.6, 260))
	local heroCenter = Vector2.new(view.X / 2, view.Y * (if view.Y > view.X then 0.3 else 0.36))
	-- rays
	local rays = frame(reveal, "Rays", UDim2.fromOffset(0, 0), UDim2.fromOffset(heroCenter.X, heroCenter.Y), nil, 2)
	for i = 0, 11 do
		local ray = frame(rays, "Ray", UDim2.fromOffset(view.X + view.Y, 22), UDim2.new(), color, 2)
		ray.AnchorPoint, ray.Rotation, ray.BackgroundTransparency = Vector2.new(0.5, 0.5), i * 15, 0.84
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
	end
	local spinAngle = 0
	setTicker("rays", function(dt) spinAngle += dt * 12; rays.Rotation = spinAngle end)
	-- hero model flies from the winning card to the centre
	local winCard = cards[WIN_INDEX]
	local winHolder = winCard:FindFirstChild("ModelHolder") :: GuiObject
	local hero = frame(reveal, "Hero", UDim2.fromOffset(winHolder.AbsoluteSize.X, winHolder.AbsoluteSize.Y), UDim2.fromOffset(winHolder.AbsolutePosition.X + winHolder.AbsoluteSize.X / 2, winHolder.AbsolutePosition.Y + winHolder.AbsoluteSize.Y / 2), nil, 5)
	hero.AnchorPoint = Vector2.new(0.5, 0.5)
	local heroViewport = newViewport(hero, 6)
	heroViewport.Size = UDim2.fromScale(1, 1)
	local mutation = Config.Mutations
	local tint: Color3? = nil
	for _, m in mutation do if m.Name == result.Mutation and m.Color then tint = m.Color end end
	if result.Mutation == "Rainbow" then tint = Color3.new(1, 1, 1) end
	local mounted = mountModel(heroViewport, result.Species, 155)
	if not mounted then label(hero, "Fallback", species.DisplayName, 22, UDim2.new(), UDim2.fromScale(1, 1), TEXT, 7).TextWrapped = true end
	winHolder.Visible = false
	tween(hero, 0.7 * t + 0.1, { Size = UDim2.fromOffset(heroSize, heroSize), Position = UDim2.fromOffset(heroCenter.X, heroCenter.Y) }, Enum.EasingStyle.Back)
	if tint then heroViewport.ImageColor3 = (tint :: Color3):Lerp(Color3.new(1, 1, 1), 0.55) end
	local bobT = 0
	setTicker("hero", function(dt)
		bobT += dt
		hero.Rotation = math.sin(bobT * 1.6) * 2
		if result.Mutation == "Rainbow" then heroViewport.ImageColor3 = Color3.fromHSV((os.clock() * 0.3) % 1, 0.45, 1) end
	end)
	revealSound(rarity)
	for i = 1, 3 do
		local ring = frame(reveal, "Ring", UDim2.fromOffset(60, 60), UDim2.fromOffset(heroCenter.X, heroCenter.Y), nil, 3)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		corner(ring, 1000)
		local s = stroke(ring, color, 7)
		task.delay((i - 1) * 0.13, function()
			if not alive then return end
			tween(ring, 0.9 + i * 0.2, { Size = UDim2.fromOffset(view.X * 1.4, view.X * 1.4) }, Enum.EasingStyle.Quint)
			tween(s, 0.9 + i * 0.2, { Transparency = 1 }, Enum.EasingStyle.Quint)
		end)
	end
	task.wait(0.5 * t)
	local colors = if rarity == "Secret" then { Color3.new(1, 1, 1), Color3.fromRGB(169, 140, 255), Color3.fromRGB(30, 30, 40) } else { color, Color3.new(1, 1, 1), Color3.fromRGB(255, 228, 90) }
	burst(heroCenter.X, heroCenter.Y, PARTICLES[rarity] or 20, colors, 380 + order * 60)
	shake(SHAKE[rarity] or 0)
	if rarity == "Secret" then
		for _ = 1, 2 do
			flash.BackgroundTransparency = 0.1
			tween(flash, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.22)
		end
	end

	-- name, chips, stats, collect button
	local info = frame(reveal, "Info", UDim2.fromOffset(620, 230), UDim2.fromOffset(view.X / 2, heroCenter.Y + heroSize / 2 + 6), nil, 6)
	info.AnchorPoint = Vector2.new(0.5, 0)
	local infoScale = Instance.new("UIScale")
	infoScale.Scale = math.clamp(view.X / 700, 0.5, 1)
	infoScale.Parent = info
	local nameLabel = label(info, "Name", species.DisplayName, 46, UDim2.new(), UDim2.fromOffset(620, 54), TEXT, 7)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextTransparency = 1
	tween(nameLabel, 0.35, { TextTransparency = 0 })
	local chips = frame(info, "Chips", UDim2.fromOffset(620, 34), UDim2.fromOffset(0, 60), nil, 7)
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection, chipLayout.HorizontalAlignment, chipLayout.Padding = Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, UDim.new(0, 8)
	chipLayout.Parent = chips
	local function chip(text: string, background: Color3, textColor: Color3?)
		local c = Instance.new("TextLabel")
		c.Text, c.Font, c.TextSize, c.TextColor3 = text, FONT, 20, textColor or TEXT
		c.BackgroundColor3, c.ZIndex = background, 8
		c.AutomaticSize, c.Size = Enum.AutomaticSize.X, UDim2.fromOffset(0, 32)
		corner(c, 4)
		stroke(c, INK, 3)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.Parent = c
		c.Parent = chips
	end
	chip(string.upper(rarity), color, if rarity == "Secret" then INK else TEXT)
	local state = getState()
	local owned = false
	if state and state.Monsters then
		for _, m in state.Monsters do
			if m.Species == result.Species and m.Id ~= result.MonsterId then owned = true end
		end
	end
	if state and not owned then chip("NEW!", Color3.fromRGB(255, 190, 40), Color3.fromRGB(74, 36, 0)) end
	if result.Mutation then
		local mutColor = Color3.fromRGB(43, 47, 101)
		for _, m in Config.Mutations do if m.Name == result.Mutation and m.Color then mutColor = m.Color end end
		if result.Mutation == "Rainbow" then mutColor = Color3.fromRGB(190, 90, 255) end
		chip("✨ " .. result.Mutation, mutColor, if result.Mutation == "Toxic" or result.Mutation == "Golden" then INK else TEXT)
	end
	local production = species.BaseProduction * MonsterMath.GetMutationMultiplier(result.Mutation)
	if state and state.Monsters then
		for _, m in state.Monsters do if m.Id == result.MonsterId and m.Production then production = m.Production end end
	end
	local where = if result.Slot and result.Slot > 0 then "Placed in slot " .. result.Slot else "Sent to your Bench"
	local stats = label(info, "Stats", string.format("💰 +%s coins/sec     📍 %s", MonsterMath.FormatNumber(production), where), 20, UDim2.fromOffset(0, 104), UDim2.fromOffset(620, 30), GuiTheme.Colors.SubText, 7)
	stats.TextTransparency = 1
	tween(stats, 0.4, { TextTransparency = 0 })
	local collect = Instance.new("TextButton")
	collect.Name, collect.Text, collect.Font, collect.TextSize, collect.TextColor3 = "Collect", "Collect", FONT, 24, TEXT
	collect.BackgroundColor3, collect.ZIndex = GuiTheme.Colors.Green, 8
	collect.Size, collect.Position = UDim2.fromOffset(180, 50), UDim2.fromOffset(220, 146)
	collect.AutoButtonColor = true
	corner(collect, 5)
	stroke(collect, INK, 3)
	collect.Parent = info
	table.insert(connections, collect.Activated:Connect(function() sfx("Button", 0.6, 1); collectRequested = true end))
	if more then collect.Text = "Next ▶" end
	task.wait(0.4 * t)
	local autoAt = if fast and more then os.clock() + 1.6 else math.huge
	while alive and not collectRequested and os.clock() < autoAt do task.wait(0.05) end
	if not alive then return end
	tween(back, 0.25, { BackgroundTransparency = 1 })
	tween(dim, 0.25, { BackgroundTransparency = 1 })
	task.wait(0.25)
	cleanup()
end

-- ---------------------------------------------------------------- queue

local queue: { Result } = {}
local running = false

local function valid(result: any): boolean
	return type(result) == "table"
		and type(result.EggType) == "string" and Config.Eggs[result.EggType] ~= nil
		and type(result.Species) == "string" and Config.Species[result.Species] ~= nil
		and type(result.MonsterId) == "string"
end

local function drain(getState: () -> any)
	if running then return end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local result = table.remove(queue, 1) :: Result
			local more = #queue > 0
			local ok, err = pcall(runRoll, result, more, more, getState)
			if not ok then
				warn("HatchRoll failed:", err)
				if activeCleanup then activeCleanup() end
			end
		end
		running = false
	end)
end

function HatchRoll.Start(remotes: { [string]: RemoteEvent }, getState: () -> any)
	remotes.HatchResult.OnClientEvent:Connect(function(result: any)
		if not valid(result) then return end
		table.insert(queue, result :: Result)
		drain(getState)
	end)
end

return HatchRoll
