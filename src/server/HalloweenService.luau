--!strict
-- Halloween 2026 event (everything is gated by Config.Halloween.Enabled / EndsAt):
--  * Mother Invasion every hour: a random wave of the game's Mother monsters walks into the plaza.
--    Damage is tracked per player on the server; everyone who dealt >= 5% of a Mother's HP gets Candy
--    (level x 5) when she dies. No stealing, nothing to carry.
--  * Pumpkin Hunt every 30 minutes: 5 pumpkins (sometimes a golden one) hidden in the plaza for 2 minutes.
--  * Candy is persisted in DataService; when the event ends it is converted to coins.
--  * Pumpkin Merchant NPC + shop (server authoritative), spooky atmosphere and props.
-- Rules that don't need Roblox live in ReplicatedStorage.Shared.HalloweenLogic (and are unit tested).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local HalloweenLogic = require(ReplicatedStorage.Shared.HalloweenLogic)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local PumpkinVisual = require(ReplicatedStorage.Shared.PumpkinVisual)
local PlotService = require(script.Parent.PlotService)
local Build = require(script.Parent.Build)
local HalloweenProps = require(script.Parent.HalloweenProps)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CharacterService = require(script.Parent.CharacterService)
local MonsterAttack = require(script.Parent.MonsterAttack)
local MonsterModels = require(script.Parent.MonsterModels)
local ZoneService = require(script.Parent.ZoneService)

local settings = Config.Halloween
local invasionSettings = settings.Invasion
local pumpkinSettings = settings.Pumpkins
local makePart = Build.MakePart

type Invader = {
	Level: number,
	Species: string,
	Title: string, -- shown name: the Mother's species name
	HeldNest: Vector3?, -- the zone nest this Mother took over (its regular Mother returns when this one is gone)
	Element: string,
	Model: Model,
	Root: BasePart,
	Tracker: HalloweenLogic.Tracker,
	Target: CombatService.Target?,
	Style: Config.MotherStyle,
	Fill: Frame,
	Text: TextLabel,
	Home: Vector3,
	BodyRadius: number,
	Alive: boolean,
	Aggro: number?, -- UserId of the last player who hit it
	Moving: boolean,
	NextAttackAt: number,
	WindingUntil: number,
	Engaged: boolean,
}
type Pumpkin = { Part: BasePart, Golden: boolean, Candy: number, Claimed: boolean }
type Hunt = { Id: number, Pumpkins: { Pumpkin }, Remaining: number, EndsAt: number, LastHintAt: number }
type AtmosphereSnapshot = {
	Lighting: { [string]: any },
	Created: { Instance },
	Atmosphere: Atmosphere?,
	AtmosphereProps: { [string]: any }?,
	Sky: Sky?,
	SkyProps: { [string]: any }?,
}

local HalloweenService = {}

local remotes: { [string]: RemoteEvent } = {}
local active = false
local rootFolder: Folder? = nil
local invaderFolder: Folder? = nil
local pumpkinFolder: Folder? = nil
local propFolder: Folder? = nil
local merchantModel: Model? = nil -- the Studio-authored (or fallback-built) Pumpkin Merchant character
local merchantPromptConnection: RBXScriptConnection? = nil
local stashedWorld: Folder? = nil -- Workspace.HalloweenWorld while the event is off (runtime only, never destroyed)
local snapshot: AtmosphereSnapshot? = nil
local invaders: { Invader } = {}
local hunt: Hunt? = nil
local huntCounter = 0
local invasionCounter = 0
local nextInvasionAt = 0
local nextPumpkinAt = 0
local announcedInvasionAt = 0
local lastBuy: { [Player]: number } = {}
local lastPick: { [Player]: number } = {}
local lastSync: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local rng = Random.new()

-- helpers --------------------------------------------------------------------------------------------

local function wantActive(): boolean
	if settings.Enabled ~= true then
		return false
	end
	return not (settings.EndsAt > 0 and os.time() >= settings.EndsAt)
end

local function hdata(player: Player): DataService.HalloweenData?
	local profile = DataService.Get(player)
	if not profile or profile.Closing == true then
		return nil
	end
	return profile.Data.Halloween
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and rootOf(player) ~= nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function announce(text: string, color: Color3?)
	MonsterService.Announce(text, color or Color3.fromRGB(255, 150, 40))
end

local function notify(player: Player, text: string, kind: string?)
	if player.Parent then
		MonsterService.Notify(player, text, kind)
	end
end

local function folder(name: string, parent: Instance): Folder
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- state sync ------------------------------------------------------------------------------------------

local function buildState(player: Player): { [string]: any }
	local data = hdata(player)
	local now = os.time()
	local owned, equipped = {}, {}
	if data then
		for id in data.Owned do owned[id] = true end
		for slot, id in data.Equipped do equipped[slot] = id end
	end
	local aliveCount = 0
	for _, invader in invaders do
		if invader.Alive then aliveCount += 1 end
	end
	local current = hunt
	return {
		Enabled = active,
		Name = settings.Name,
		Candy = if data then data.Candy else 0,
		TotalCandy = if data then data.TotalCandy else 0,
		Owned = owned,
		Equipped = equipped,
		BoostLeft = if data then HalloweenLogic.BoostLeft(data, now) else 0,
		NextInvasionIn = if active then math.max(0, nextInvasionAt - now) else 0,
		NextPumpkinsIn = if active then math.max(0, nextPumpkinAt - now) else 0,
		InvadersAlive = aliveCount,
		HuntRemaining = if current then current.Remaining else 0,
		HuntEndsIn = if current then math.max(0, math.ceil(current.EndsAt - os.clock())) else 0,
		ConvertRate = settings.CandyToCoinRate,
	}
end

local function pushState(player: Player)
	if player.Parent and remotes.HalloweenState then
		remotes.HalloweenState:FireClient(player, buildState(player))
	end
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		pushState(player)
	end
end

local function saveSoon(player: Player)
	DataService.QueueSave(player)
end

-- Candy -----------------------------------------------------------------------------------------------

function HalloweenService.AddCandy(player: Player, amount: number): number
	if not active then
		return 0
	end
	local data = hdata(player)
	if not data then
		return 0
	end
	local granted = HalloweenLogic.AwardCandy(data :: any, amount, settings.CandyCap)
	if granted > 0 then
		saveSoon(player)
		pushState(player)
	end
	return granted
end

-- Leftover Candy becomes coins at Config.Halloween.CandyToCoinRate. Safe to call repeatedly.
function HalloweenService.ConvertCandy(player: Player): number
	local data = hdata(player)
	if not data or data.Candy < 1 then
		return 0
	end
	local coins, candy = HalloweenLogic.ConvertAll(data :: any, settings.CandyToCoinRate)
	if coins > 0 then
		DataService.AddCoins(player, coins)
	end
	if candy > 0 then
		notify(player, string.format("🎃 Halloween is over! %d Candy turned into %d coins.", candy, coins), "coins")
		saveSoon(player)
		MonsterService.PushState(player)
	end
	pushState(player)
	return coins
end

function HalloweenService.GetCashMultiplier(player: Player): number
	if not active then
		return 1
	end
	local data = hdata(player)
	if not data then
		return 1
	end
	return HalloweenLogic.CashMultiplier(data :: any, os.time(), settings.Items)
end

-- Cosmetics -------------------------------------------------------------------------------------------

local function removeCosmetics(character: Model)
	local existing = character:FindFirstChild("HalloweenCosmetics")
	if existing then
		existing:Destroy()
	end
end

local function weldTo(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

local function applyCosmetics(player: Player)
	local character = player.Character
	if not character then
		return
	end
	removeCosmetics(character)
	if not active then
		return
	end
	local data = hdata(player)
	local root = rootOf(player)
	local head = character:FindFirstChild("Head")
	if not data or not root or not head or not head:IsA("BasePart") then
		return
	end
	local container = Instance.new("Model")
	container.Name = "HalloweenCosmetics"
	local equipped = data.Equipped

	if equipped.Hat and data.Owned[equipped.Hat] then
		local hatItem = settings.Items[equipped.Hat]
		local hat = PumpkinVisual.Create("PumpkinHat", hatItem.HatSize or 1.7, CFrame.new(), hatItem.Tint)
		hat.Parent = container
		hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + hat.Size.Y / 2 - 0.25, 0)
		if hatItem.Tint then
			-- The pumpkin texture is orange and Part.Color never tints a textured mesh, so a glowing untextured shell in
			-- the hat's colour is laid over it (the carved face still shows through).
			local shell = PumpkinVisual.Create("HatTint", (hatItem.HatSize or 1.7) * 1.04, hat.CFrame, hatItem.Tint)
			local shellMesh = shell:FindFirstChildOfClass("SpecialMesh")
			if shellMesh then
				shellMesh.TextureId = ""
			end
			shell.Material = Enum.Material.Neon
			shell.Transparency = 0.4
			shell.Parent = container
			weldTo(shell, hat)
		end
		local light = Instance.new("PointLight")
		light.Color = if hatItem.Tint then hatItem.Color else Color3.fromRGB(255, 150, 50)
		light.Range = 10
		light.Brightness = 1
		light.Shadows = false
		light.Parent = hat
		weldTo(hat, head)
	end

	if equipped.Trail or equipped.Aura then
		local anchor = makePart({ Name = "CosmeticAnchor", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, Anchored = false, Parent = container })
		anchor.CFrame = root.CFrame
		weldTo(anchor, root)
		if equipped.Trail and data.Owned[equipped.Trail] then
			local top = Instance.new("Attachment")
			top.Name = "TrailTop"
			top.Position = Vector3.new(0, 0.9, 0.4)
			top.Parent = anchor
			local bottom = Instance.new("Attachment")
			bottom.Name = "TrailBottom"
			bottom.Position = Vector3.new(0, -1.2, 0.4)
			bottom.Parent = anchor
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Lifetime = 0.9
			trail.MinLength = 0.1
			trail.LightEmission = 0.6
			local trailItem = settings.Items[equipped.Trail]
			trail.Color = ColorSequence.new(trailItem.Color, trailItem.Color2 or Color3.fromRGB(150, 120, 255))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
			trail.Parent = anchor
		end
		if equipped.Aura and data.Owned[equipped.Aura] then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "CandyAura"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			local auraItem = settings.Items[equipped.Aura]
			emitter.Color = ColorSequence.new(auraItem.Color, auraItem.Color2 or Color3.fromRGB(255, 220, 90))
			emitter.LightEmission = 1
			emitter.Rate = 70
			emitter.Lifetime = NumberRange.new(1.2, 2.2)
			emitter.Speed = NumberRange.new(2, 5)
			emitter.Acceleration = Vector3.new(0, 2.5, 0)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.RotSpeed = NumberRange.new(-90, 90)
			emitter.Shape = Enum.ParticleEmitterShape.Sphere
			emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			emitter.Parent = anchor
			-- a soft glow cloud around the body so the aura reads from far away
			local glow = Instance.new("ParticleEmitter")
			glow.Name = "AuraGlow"
			glow.Texture = "rbxasset://textures/particles/smoke_main.dds"
			glow.Color = ColorSequence.new(auraItem.Color)
			glow.LightEmission = 1
			glow.Rate = 10
			glow.Lifetime = NumberRange.new(1.2, 1.8)
			glow.Speed = NumberRange.new(0.2, 0.8)
			glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(1, 5.5) })
			glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
			glow.Parent = anchor
			local auraLight = Instance.new("PointLight")
			auraLight.Color = auraItem.Color
			auraLight.Range = 14
			auraLight.Brightness = 1.5
			auraLight.Shadows = false
			auraLight.Parent = anchor
		end
	end

	if equipped.Title and data.Owned[equipped.Title] then
		local item = settings.Items[equipped.Title]
		-- Prestige: the dearer the title, the richer the plaque (rank among all titles by Candy price, 1 to 4).
		local pricier, titles = 0, 0
		for _, other in settings.Items do
			if other.Kind == "Title" then
				titles += 1
				if other.Cost < item.Cost then pricier += 1 end
			end
		end
		local tier = math.clamp(1 + math.floor(pricier / math.max(1, titles - 1) * 3.999), 1, 4)
		local ornaments = { "", "✦", item.Icon or "🎃", "✦ " .. (item.Icon or "🎃") }
		local ornament = ornaments[tier]
		local message = (item.TitleText or item.Name)
		if ornament ~= "" then message = ornament .. " " .. message .. " " .. ornament end
		local width = math.clamp((utf8.len(message) or 12) * 8 + 34, 120, 260)
		local height = 20 + tier * 2
		local gui = Instance.new("BillboardGui")
		gui.Name = "HalloweenTitle"
		gui.Size = UDim2.fromOffset(width + 12, height + 12)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)
		gui.MaxDistance = 70
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.Adornee = head
		gui.Parent = container
		local function pill(parent: Instance, name: string, size: UDim2): Frame
			local frame = Instance.new("Frame")
			frame.Name = name
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = size
			frame.BorderSizePixel = 0
			frame.Parent = parent
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
			return frame
		end
		if tier >= 3 then
			-- soft halo behind the plaque
			local halo = pill(gui, "Halo", UDim2.fromOffset(width + 10, height + 10))
			halo.BackgroundColor3 = item.Color
			halo.BackgroundTransparency = if tier == 4 then 0.55 else 0.72
		end
		local plaque = pill(gui, "Plaque", UDim2.fromOffset(width, height))
		plaque.BackgroundColor3 = Color3.new(1, 1, 1)
		local plaqueGradient = Instance.new("UIGradient")
		plaqueGradient.Color = ColorSequence.new(Color3.fromRGB(46, 26, 74):Lerp(item.Color, 0.18), Color3.fromRGB(14, 8, 26))
		plaqueGradient.Rotation = 90
		plaqueGradient.Parent = plaque
		local rim = Instance.new("UIStroke")
		rim.Color = item.Color
		rim.Thickness = 1 + tier * 0.5
		rim.Parent = plaque
		if tier >= 2 then
			local rimGradient = Instance.new("UIGradient")
			local bright = item.Color:Lerp(Color3.new(1, 1, 1), 0.6)
			rimGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, item.Color),
				ColorSequenceKeypoint.new(0.5, bright),
				ColorSequenceKeypoint.new(1, item.Color),
			})
			rimGradient.Parent = rim
			-- glossy highlight across the top half
			local shine = pill(plaque, "Shine", UDim2.new(0.88, 0, 0.36, 0))
			shine.Position = UDim2.fromScale(0.5, 0.3)
			shine.BackgroundColor3 = Color3.new(1, 1, 1)
			shine.BackgroundTransparency = 0.82
		end
		if tier == 4 then
			-- inner gold line for the top tier
			local inner = pill(plaque, "InnerLine", UDim2.new(1, -6, 1, -6))
			inner.BackgroundTransparency = 1
			local innerStroke = Instance.new("UIStroke")
			innerStroke.Color = Color3.fromRGB(255, 226, 140)
			innerStroke.Thickness = 1
			innerStroke.Transparency = 0.25
			innerStroke.Parent = inner
		end
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.new(1, -18, 1, -6)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = message
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = plaque
		local textGradient = Instance.new("UIGradient")
		textGradient.Color = if tier == 4
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 220)),
				ColorSequenceKeypoint.new(0.55, item.Color),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 70)),
			})
			else ColorSequence.new(Color3.new(1, 1, 1), item.Color)
		textGradient.Rotation = 90
		textGradient.Parent = label
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(12, 6, 24)
		textStroke.Thickness = 1.5
		textStroke.Parent = label
	end

	container.Parent = character
end
HalloweenService.ApplyCosmetics = applyCosmetics

function HalloweenService.OnCharacter(player: Player)
	pcall(applyCosmetics, player)
end

-- atmosphere ------------------------------------------------------------------------------------------

local LIGHTING_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogColor", "FogStart", "FogEnd" }
local ATMOSPHERE_PROPS = { "Density", "Offset", "Color", "Decay", "Haze" }

-- The spooky night is event-only: it is held by "reasons" (Invasion = from the warning until every Mother is
-- gone, Hunt = while a Pumpkin Hunt runs). Any reason held -> night; none -> the original day lighting.
-- The original values are snapshotted once and stay snapshotted until the fade back to day has finished,
-- so overlapping events can never restore mid-event and a re-trigger during the fade-out just fades back in.
local nightHolds: { [string]: boolean } = {}
local nightTweens: { Tween } = {}
local nightToken = 0
local nightTarget = false

local function cancelNightTweens()
	for _, tween in nightTweens do
		tween:Cancel()
	end
	table.clear(nightTweens)
end

local function fade(instance: Instance, goal: { [string]: any }, seconds: number)
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	table.insert(nightTweens, tween)
	tween:Play()
end

local function captureAtmosphere(): AtmosphereSnapshot
	local existing = snapshot
	if existing then
		return existing
	end
	local saved: AtmosphereSnapshot = { Lighting = {}, Created = {} }
	for _, prop in LIGHTING_PROPS do
		saved.Lighting[prop] = (Lighting :: any)[prop]
	end
	snapshot = saved
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local props = {}
		for _, prop in ATMOSPHERE_PROPS do props[prop] = (atmosphere :: any)[prop] end
		saved.Atmosphere, saved.AtmosphereProps = atmosphere, props
	else
		-- starts invisible (density 0) so the fade-in has something to fade from
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "HalloweenAtmosphere"
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Parent = Lighting
		table.insert(saved.Created, atmosphere)
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		saved.Sky, saved.SkyProps = sky, { StarCount = sky.StarCount, CelestialBodiesShown = sky.CelestialBodiesShown }
	else
		sky = Instance.new("Sky")
		sky.Name = "HalloweenSky"
		sky.StarCount = 0
		sky.Parent = Lighting
		table.insert(saved.Created, sky)
	end
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "HalloweenColor"
	color.Parent = Lighting
	table.insert(saved.Created, color)
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HalloweenBloom"
	bloom.Intensity = 0
	bloom.Threshold = settings.Atmosphere.BloomThreshold
	bloom.Size = 24
	bloom.Parent = Lighting
	table.insert(saved.Created, bloom)
	return saved
end

local function destroyAtmosphereFx(saved: AtmosphereSnapshot)
	for _, created in saved.Created do
		created:Destroy()
	end
end

local function fadeToNight()
	local a = settings.Atmosphere
	local saved = captureAtmosphere()
	cancelNightTweens()
	local seconds = a.FadeSeconds
	fade(Lighting, {
		ClockTime = a.ClockTime, Brightness = a.Brightness, Ambient = a.Ambient, OutdoorAmbient = a.OutdoorAmbient,
		FogColor = a.FogColor, FogStart = a.FogStart, FogEnd = a.FogEnd,
	}, seconds)
	local atmosphere = saved.Atmosphere or Lighting:FindFirstChild("HalloweenAtmosphere")
	if atmosphere and atmosphere:IsA("Atmosphere") then
		fade(atmosphere, { Density = a.AtmosphereDensity, Offset = a.AtmosphereOffset, Color = a.AtmosphereColor, Decay = a.AtmosphereDecay, Haze = a.Haze }, seconds)
	end
	local sky = saved.Sky or Lighting:FindFirstChild("HalloweenSky")
	if sky and sky:IsA("Sky") then
		sky.CelestialBodiesShown = true
		fade(sky, { StarCount = a.StarCount }, seconds)
	end
	local color = Lighting:FindFirstChild("HalloweenColor")
	if color and color:IsA("ColorCorrectionEffect") then
		fade(color, { TintColor = a.TintColor, Saturation = a.Saturation, Contrast = a.Contrast }, seconds)
	end
	local bloom = Lighting:FindFirstChild("HalloweenBloom")
	if bloom and bloom:IsA("BloomEffect") then
		fade(bloom, { Intensity = a.BloomIntensity }, seconds)
	end
end

-- Instant, complete restore (Stop / shutdown).
local function restoreAtmosphere()
	local saved = snapshot
	nightToken += 1
	nightTarget = false
	cancelNightTweens()
	if not saved then
		return
	end
	snapshot = nil
	for prop, value in saved.Lighting do
		(Lighting :: any)[prop] = value
	end
	if saved.Atmosphere and saved.AtmosphereProps and saved.Atmosphere.Parent then
		for prop, value in saved.AtmosphereProps do
			(saved.Atmosphere :: any)[prop] = value
		end
	end
	if saved.Sky and saved.SkyProps and saved.Sky.Parent then
		for prop, value in saved.SkyProps do
			(saved.Sky :: any)[prop] = value
		end
	end
	destroyAtmosphereFx(saved)
end

local function fadeToDay()
	local saved = snapshot
	if not saved then
		return
	end
	cancelNightTweens()
	local seconds = settings.Atmosphere.FadeSeconds
	nightToken += 1
	local token = nightToken
	local goal: { [string]: any } = {}
	for prop, value in saved.Lighting do goal[prop] = value end
	fade(Lighting, goal, seconds)
	local atmosphere = saved.Atmosphere or Lighting:FindFirstChild("HalloweenAtmosphere")
	if atmosphere and atmosphere.Parent and atmosphere:IsA("Atmosphere") then
		fade(atmosphere, saved.AtmosphereProps or { Density = 0, Haze = 0 }, seconds)
	end
	local sky = saved.Sky or Lighting:FindFirstChild("HalloweenSky")
	if sky and sky.Parent and sky:IsA("Sky") then
		fade(sky, { StarCount = if saved.SkyProps then saved.SkyProps.StarCount else 0 }, seconds)
	end
	local color = Lighting:FindFirstChild("HalloweenColor")
	if color and color:IsA("ColorCorrectionEffect") then
		fade(color, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }, seconds)
	end
	local bloom = Lighting:FindFirstChild("HalloweenBloom")
	if bloom and bloom:IsA("BloomEffect") then
		fade(bloom, { Intensity = 0 }, seconds)
	end
	task.delay(seconds + 0.1, function()
		-- a newer fade (or a hard restore) owns the lighting now
		if nightToken ~= token or snapshot ~= saved then
			return
		end
		restoreAtmosphere()
	end)
end

local function refreshNight()
	local wanted = nightHolds.Boss == true -- the Big Boss brings the night with it, event running or not
	if active and not wanted then
		for _, held in nightHolds do
			if held then wanted = true break end
		end
	end
	if wanted == nightTarget then
		return
	end
	nightTarget = wanted
	nightToken += 1
	if wanted then
		fadeToNight()
	else
		fadeToDay()
	end
end

local function setNight(reason: string, on: boolean)
	nightHolds[reason] = on or nil
	refreshNight()
end

-- the Big Boss holds the night for as long as it is alive
function HalloweenService.SetBossNight(on: boolean)
	setNight("Boss", on)
end

-- exposed for tests / debugging
function HalloweenService.IsNight(): boolean
	return nightTarget
end

-- props -----------------------------------------------------------------------------------------------

local ORANGE = Color3.fromRGB(240, 120, 25)

local jackOLantern = HalloweenProps.JackOLantern
local clearOf = HalloweenProps.ClearOf

-- Workspace.HalloweenWorld is authored in Studio (Edit mode) so the decorations and the merchant are visible
-- without pressing Play and stay wherever the designer moved them. The server only ADOPTS what is there. Only
-- when something is missing does it build the code-made default, into the same folder structure.
local TAG_MERCHANT = "HalloweenMerchant"

local function ensureWorld(): Folder
	local existing = workspace:FindFirstChild("HalloweenWorld")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = folder("HalloweenWorld", workspace)
	created:SetAttribute("AutoBuilt", true)
	return created
end

-- Event off: take the authored world out of the running game (the saved place is untouched, nothing is
-- destroyed or moved) and bring it back, as authored, when the event starts.
local function hideWorld()
	local world = workspace:FindFirstChild("HalloweenWorld")
	if world and world:IsA("Folder") then
		if world:GetAttribute("AutoBuilt") == true then
			world:Destroy()
		else
			stashedWorld = world
			world.Parent = nil
		end
	end
end

local function showWorld()
	local stashed = stashedWorld
	stashedWorld = nil
	if stashed and not workspace:FindFirstChild("HalloweenWorld") then
		stashed.Parent = workspace
	end
end

local function buildProps()
	if propFolder then
		return
	end
	local world = ensureWorld()
	local authored = world:FindFirstChild("Props")
	if world:GetAttribute("AutoBuilt") ~= true then
		-- A Studio-authored world: adopt whatever is left (possibly nothing). Decorations the designer deleted
		-- stay deleted; the default set is only for a place that has no authored world at all.
		propFolder = (if authored and authored:IsA("Folder") then authored else world) :: Folder
		return
	end
	if authored and authored:IsA("Folder") and #authored:GetChildren() > 0 then
		propFolder = authored -- adopt: the decorations already exist, leave them exactly as they are
		return
	end
	local parent = authored or folder("Props", world)
	parent:SetAttribute("AutoBuilt", true)
	propFolder = parent :: Folder
	HalloweenProps.Populate(parent)
end

-- merchant --------------------------------------------------------------------------------------------

local function findMerchantModel(): Model?
	for _, tagged in CollectionService:GetTagged(TAG_MERCHANT) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(workspace) then
			return tagged
		end
	end
	local world = workspace:FindFirstChild("HalloweenWorld")
	local named = world and world:FindFirstChild("PumpkinMerchant", true)
	return if named and named:IsA("Model") then named else nil
end

-- Where the merchant stands RIGHT NOW (he may have been moved in Studio): never the Config position.
local function merchantPart(): BasePart?
	local model = merchantModel
	if not model or not model:IsDescendantOf(workspace) then
		model = findMerchantModel()
		merchantModel = model
	end
	if not model then
		return nil
	end
	local part = model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if part and part:IsA("BasePart") then part else nil
end

local function openShopFor(player: Player)
	local root = rootOf(player)
	local merchant = merchantPart()
	if not active or not root or not merchant or not isAlive(player) then
		return
	end
	if (root.Position - merchant.Position).Magnitude > settings.Merchant.ShopDistance then
		return
	end
	pushState(player)
	remotes.HalloweenOpenShop:FireClient(player)
end

-- Fallback only (the authored merchant is missing): a simple code-built merchant at Config.Halloween.Merchant,
-- built into the same HalloweenWorld/Merchant folder and tagged so the normal adoption path wires it.
local function buildDefaultMerchant()
	local world = ensureWorld()
	local holder = world:FindFirstChild("Merchant") or folder("Merchant", world)
	holder:SetAttribute("AutoBuilt", true)
	HalloweenProps.BuildMerchant(holder)
end

-- Dresses the merchant stall with the full "Pumpkin Merchant" look at runtime: layered cloak, gold trim, tall bent
-- witch hat, glowing staff, striped canopy with lanterns and a sign, candy jar, bubbling cauldron, rune rug,
-- floating sparkles and a plaque name tag. Everything is positioned relative to HIS Torso, so it follows him if the
-- designer moves him. Only the standard stall (Torso/Head/Counter/HatCone) is dressed; a differently authored
-- merchant is left untouched. Idempotent via the "Dressed" attribute.
local function dressMerchant(model: Model)
	if model:GetAttribute("Dressed") == true then
		return
	end
	local torso = model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	if not (torso and torso:IsA("BasePart") and head and head:IsA("BasePart") and model:FindFirstChild("Counter") and model:FindFirstChild("HatCone")) then
		return
	end
	model:SetAttribute("Dressed", true)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant:Destroy() -- the old two-line label is replaced by the plaque below
		end
	end
	local origin = torso.CFrame * CFrame.new(0, -3, 0) -- feet level, facing the customers (-Z)
	local dressing = folder("Dressing", model)

	local GOLD = Color3.fromRGB(255, 205, 80)
	local PURPLE = Color3.fromRGB(92, 48, 138)
	local DEEP = Color3.fromRGB(38, 18, 62)
	local WOOD = Color3.fromRGB(96, 62, 38)
	local CANDY_PINK = Color3.fromRGB(255, 90, 170)
	local CANDY_GREEN = Color3.fromRGB(110, 255, 120)
	local CANDY_YELLOW = Color3.fromRGB(255, 225, 80)
	local CANDY_CYAN = Color3.fromRGB(90, 225, 255)

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?, rotation: CFrame?): Part
		return makePart({
			Name = name, Size = size, CFrame = origin * CFrame.new(offset) * (rotation or CFrame.new()), Color = color,
			Material = material or Enum.Material.Fabric, Shape = shape or Enum.PartType.Block,
			CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Parent = dressing,
		})
	end
	-- Cylinders lie along X by default: these two rotations make them stand upright or point along Z.
	local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
	local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
	local function light(parent: Instance, color: Color3, range: number, brightness: number)
		local pointLight = Instance.new("PointLight")
		pointLight.Color = color
		pointLight.Range = range
		pointLight.Brightness = brightness
		pointLight.Shadows = false
		pointLight.Parent = parent
	end
	local function sparkles(parent: Instance, name: string, colors: ColorSequence, rate: number, size: number, speed: number, lifetime: number, rise: number)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = colors
		emitter.LightEmission = 0.9
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
		emitter.Speed = NumberRange.new(speed * 0.4, speed)
		emitter.Acceleration = Vector3.new(0, rise, 0)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = parent
	end

	-- rune rug under the whole stall ------------------------------------------------------------------------
	part("RugGold", Vector3.new(0.06, 15.2, 15.2), Vector3.new(0, 0.05, -1.6), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	part("RugRune", Vector3.new(0.06, 14.2, 14.2), Vector3.new(0, 0.07, -1.6), Color3.fromRGB(190, 110, 255), Enum.Material.Neon, Enum.PartType.Cylinder, UPRIGHT).Transparency = 0.35
	part("RugCloth", Vector3.new(0.06, 13.4, 13.4), Vector3.new(0, 0.09, -1.6), DEEP, Enum.Material.Fabric, Enum.PartType.Cylinder, UPRIGHT)
	part("RugInner", Vector3.new(0.06, 9.4, 9.4), Vector3.new(0, 0.11, -1.6), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT).Transparency = 0.2
	part("RugCenter", Vector3.new(0.06, 9.0, 9.0), Vector3.new(0, 0.13, -1.6), PURPLE, Enum.Material.Fabric, Enum.PartType.Cylinder, UPRIGHT)

	-- cloak, mantle, trim -----------------------------------------------------------------------------------
	part("CloakUpper", Vector3.new(2.4, 2.8, 0.3), Vector3.new(0, 3.1, 0.78), DEEP, nil, nil, CFrame.Angles(0.08, 0, 0))
	part("CloakLower", Vector3.new(3.0, 2.6, 0.3), Vector3.new(0, 1.3, 1.12), PURPLE, nil, nil, CFrame.Angles(0.16, 0, 0))
	part("CloakTrim", Vector3.new(3.1, 0.2, 0.4), Vector3.new(0, 0.1, 1.38), GOLD, Enum.Material.Metal, nil, CFrame.Angles(0.16, 0, 0))
	part("Collar", Vector3.new(2.7, 0.55, 1.5), Vector3.new(0, 4.15, 0.05), PURPLE)
	part("CollarTrim", Vector3.new(2.8, 0.12, 1.6), Vector3.new(0, 4.45, 0.05), GOLD, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part("Mantle", Vector3.new(1.5, 0.55, 1.5), Vector3.new(side * 1.3, 4.0, 0), PURPLE)
		part("MantleTrim", Vector3.new(1.55, 0.12, 1.55), Vector3.new(side * 1.3, 4.3, 0), GOLD, Enum.Material.Metal)
		part("Cuff", Vector3.new(1.12, 0.3, 1.12), Vector3.new(side * 1.5, 2.2, -0.3), GOLD, Enum.Material.Metal)
		part("Glove", Vector3.new(1.05, 0.5, 1.05), Vector3.new(side * 1.5, 1.85, -0.3), Color3.fromRGB(28, 18, 38))
	end
	part("HemTrim", Vector3.new(2.75, 0.2, 1.65), Vector3.new(0, 0.62, 0), GOLD, Enum.Material.Metal)
	part("FrontSash", Vector3.new(0.4, 2.4, 0.14), Vector3.new(0, 2.9, -0.58), GOLD, Enum.Material.Metal)
	part("Belt", Vector3.new(2.15, 0.38, 1.1), Vector3.new(0, 2.2, 0), Color3.fromRGB(46, 28, 20), Enum.Material.Leather)
	local buckle = part("Buckle", Vector3.new(0.6, 0.52, 0.16), Vector3.new(0, 2.2, -0.6), GOLD, Enum.Material.Metal)
	part("BuckleGem", Vector3.new(0.26, 0.26, 0.18), Vector3.new(0, 2.2, -0.65), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
	light(buckle, Color3.fromRGB(255, 140, 50), 7, 0.8)
	light(head, Color3.fromRGB(255, 150, 50), 12, 1.2) -- the pumpkin head glows from inside

	-- tall bent witch hat -----------------------------------------------------------------------------------
	part("HatBand", Vector3.new(0.45, 2.15, 2.15), Vector3.new(0, 6.4, 0), Color3.fromRGB(255, 120, 30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, UPRIGHT)
	part("HatBuckle", Vector3.new(0.62, 0.6, 0.14), Vector3.new(0, 6.4, -1.1), GOLD, Enum.Material.Metal)
	part("HatMid", Vector3.new(1.5, 1.4, 1.5), Vector3.new(0.1, 8.4, 0), Color3.fromRGB(30, 20, 40), nil, nil, CFrame.Angles(0, 0, -0.14))
	part("HatBend", Vector3.new(1.0, 1.2, 1.0), Vector3.new(0.5, 9.5, 0), Color3.fromRGB(30, 20, 40), nil, nil, CFrame.Angles(0, 0, -0.42))
	part("HatTip", Vector3.new(0.6, 0.9, 0.6), Vector3.new(1.0, 10.4, 0), Color3.fromRGB(30, 20, 40), nil, nil, CFrame.Angles(0, 0, -0.8))
	local tipGem = part("HatTipGem", Vector3.new(0.5, 0.5, 0.5), Vector3.new(1.35, 10.85, 0), Color3.fromRGB(255, 140, 40), Enum.Material.Neon, Enum.PartType.Ball)
	light(tipGem, Color3.fromRGB(255, 150, 60), 10, 1)

	-- glowing staff -----------------------------------------------------------------------------------------
	part("StaffPole", Vector3.new(8.4, 0.34, 0.34), Vector3.new(-2.0, 4.2, -1.0), WOOD, Enum.Material.Wood, Enum.PartType.Cylinder, UPRIGHT)
	part("StaffGrip", Vector3.new(0.9, 0.46, 0.46), Vector3.new(-2.0, 3.0, -1.0), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	part("StaffRing", Vector3.new(0.14, 2.0, 2.0), Vector3.new(-2.0, 8.5, -1.0), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	for _, angle in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
		part("StaffClaw", Vector3.new(0.14, 0.9, 0.14), Vector3.new(-2.0 + math.cos(angle) * 0.85, 8.1, -1.0 + math.sin(angle) * 0.85), GOLD, Enum.Material.Metal)
	end
	local orb = part("StaffOrb", Vector3.new(1.35, 1.35, 1.35), Vector3.new(-2.0, 8.6, -1.0), Color3.fromRGB(255, 130, 35), Enum.Material.Neon, Enum.PartType.Ball)
	light(orb, Color3.fromRGB(255, 150, 60), 26, 2)
	sparkles(orb, "OrbSparks", ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 110, 200)), 14, 0.7, 2.5, 1.6, 1.5)
	TweenService:Create(orb, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = orb.Position + Vector3.new(0, 0.35, 0) }):Play()

	-- striped canopy, lanterns, sign ------------------------------------------------------------------------
	for _, side in { -1, 1 } do
		part("StallPost", Vector3.new(9.6, 0.55, 0.55), Vector3.new(side * 3.9, 4.8, -3.2), WOOD, Enum.Material.Wood, Enum.PartType.Cylinder, UPRIGHT)
		part("PostCap", Vector3.new(0.5, 0.8, 0.8), Vector3.new(side * 3.9, 9.7, -3.2), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	end
	for strip = 1, 8 do
		local x = (strip - 4.5) * 1.0
		local color = if strip % 2 == 0 then Color3.fromRGB(70, 36, 108) else Color3.fromRGB(255, 125, 30)
		part("Canopy", Vector3.new(1.02, 0.22, 4.2), Vector3.new(x, 9.2, -3.7), color, nil, nil, CFrame.Angles(0.2, 0, 0))
		local fringe = part("Fringe", Vector3.new(0.62, 0.62, 0.62), Vector3.new(x, 8.55, -5.6), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		fringe.Transparency = 0
	end
	for _, side in { -1, 1 } do
		part("LanternChain", Vector3.new(1.3, 0.07, 0.07), Vector3.new(side * 3.3, 7.8, -5.5), Color3.fromRGB(60, 60, 70), Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
		local lantern = part("StallLantern", Vector3.new(0.9, 1.2, 0.9), Vector3.new(side * 3.3, 6.6, -5.5), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
		part("LanternCap", Vector3.new(1.1, 0.18, 1.1), Vector3.new(side * 3.3, 7.3, -5.5), GOLD, Enum.Material.Metal)
		light(lantern, Color3.fromRGB(255, 150, 60), 16, 1.4)
	end
	local sign = part("Sign", Vector3.new(4.6, 1.3, 0.24), Vector3.new(0, 7.3, -5.55), Color3.fromRGB(44, 26, 18), Enum.Material.Wood)
	part("SignFrame", Vector3.new(4.9, 1.6, 0.16), Vector3.new(0, 7.3, -5.48), GOLD, Enum.Material.Metal)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	signGui.CanvasSize = Vector2.new(460, 130)
	signGui.LightInfluence = 0
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.FredokaOne
	signText.TextScaled = true
	signText.Text = "🍬 CANDY SHOP 🎃"
	signText.TextColor3 = GOLD
	signText.Parent = signGui
	local signStroke = Instance.new("UIStroke")
	signStroke.Color = Color3.fromRGB(30, 10, 10)
	signStroke.Thickness = 3
	signStroke.Parent = signText

	-- counter dressing: runner, trim, candy jar, lollipops -------------------------------------------------
	part("CounterRunner", Vector3.new(7.2, 0.12, 2.5), Vector3.new(0, 3.06, -3.2), PURPLE)
	part("CounterTrim", Vector3.new(7.1, 0.28, 0.12), Vector3.new(0, 2.5, -4.42), GOLD, Enum.Material.Metal)
	part("CounterTrimTop", Vector3.new(7.1, 0.12, 0.12), Vector3.new(0, 3.0, -4.42), GOLD, Enum.Material.Metal)
	local jar = part("CandyJar", Vector3.new(1.6, 1.3, 1.3), Vector3.new(0.1, 3.8, -3.3), Color3.fromRGB(190, 230, 255), Enum.Material.Glass, Enum.PartType.Cylinder, UPRIGHT)
	jar.Transparency = 0.45
	part("JarLid", Vector3.new(0.22, 1.4, 1.4), Vector3.new(0.1, 4.6, -3.3), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	local candyColors = { CANDY_PINK, CANDY_GREEN, CANDY_YELLOW, CANDY_CYAN }
	local candySpots = { { -0.3, 3.4, -3.3 }, { 0.5, 3.45, -3.1 }, { 0.1, 3.5, -3.6 }, { -0.1, 4.0, -3.2 }, { 0.4, 4.05, -3.45 }, { -0.35, 4.1, -3.45 } }
	for index, spot in candySpots do
		part("JarCandy", Vector3.new(0.42, 0.42, 0.42), Vector3.new(spot[1], spot[2], spot[3]), candyColors[(index - 1) % #candyColors + 1], Enum.Material.Neon, Enum.PartType.Ball)
	end
	for index, x in { -1.3, -0.8, 1.5, 2.0 } do
		part("PopStick", Vector3.new(1.7, 0.09, 0.09), Vector3.new(x, 3.95, -3.9), Color3.fromRGB(245, 240, 230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, UPRIGHT)
		part("PopCandy", Vector3.new(0.12, 0.95, 0.95), Vector3.new(x, 4.9, -3.9), candyColors[index], Enum.Material.Neon, Enum.PartType.Cylinder, ALONG_Z)
	end

	-- bubbling cauldron + pumpkin pile ---------------------------------------------------------------------
	part("Cauldron", Vector3.new(2.9, 2.9, 2.9), Vector3.new(-5.2, 1.5, -2.4), Color3.fromRGB(34, 34, 40), Enum.Material.Metal, Enum.PartType.Ball)
	part("CauldronRim", Vector3.new(0.3, 2.35, 2.35), Vector3.new(-5.2, 2.55, -2.4), Color3.fromRGB(58, 58, 66), Enum.Material.Metal, Enum.PartType.Cylinder, UPRIGHT)
	local brew = part("Brew", Vector3.new(0.1, 2.0, 2.0), Vector3.new(-5.2, 2.6, -2.4), Color3.fromRGB(110, 255, 90), Enum.Material.Neon, Enum.PartType.Cylinder, UPRIGHT)
	light(brew, Color3.fromRGB(110, 255, 90), 14, 1.3)
	sparkles(brew, "Bubbles", ColorSequence.new(Color3.fromRGB(150, 255, 120), Color3.fromRGB(230, 255, 180)), 12, 0.55, 2, 1.8, 2)
	for _, leg in { { -6.1, -1.7 }, { -4.3, -1.7 }, { -5.2, -3.4 } } do
		part("CauldronLeg", Vector3.new(0.4, 0.7, 0.4), Vector3.new(leg[1], 0.35, leg[2]), Color3.fromRGB(26, 26, 32), Enum.Material.Metal)
	end
	jackOLantern(dressing, (origin * CFrame.new(5.3, 0, -2.4)).Position + Vector3.new(0, 0.2, 0), 2.6, 0.5, true)
	jackOLantern(dressing, (origin * CFrame.new(6.5, 0, -3.1)).Position + Vector3.new(0, 0.2, 0), 1.8, -0.3, false)
	jackOLantern(dressing, (origin * CFrame.new(5.6, 2.6, -2.5)).Position, 1.5, 0.9, true)

	-- floating candy sparkles over the stall ---------------------------------------------------------------
	local aura = part("StallSparkles", Vector3.new(11, 6, 9), Vector3.new(0, 5.5, -2.2), Color3.new(1, 1, 1))
	aura.Transparency = 1
	aura.Shape = Enum.PartType.Block
	sparkles(aura, "CandySparkles", ColorSequence.new({
		ColorSequenceKeypoint.new(0, CANDY_PINK), ColorSequenceKeypoint.new(0.5, CANDY_YELLOW), ColorSequenceKeypoint.new(1, CANDY_CYAN),
	}), 9, 0.8, 0.8, 4, 0.5)

	-- name plaque (prestige style) -------------------------------------------------------------------------
	local plaqueGui = Instance.new("BillboardGui")
	plaqueGui.Name = "MerchantPlaque"
	plaqueGui.Size = UDim2.fromOffset(280, 70)
	plaqueGui.StudsOffset = Vector3.new(0, 7.2, 0)
	plaqueGui.MaxDistance = 95
	plaqueGui.AlwaysOnTop = false
	plaqueGui.LightInfluence = 0
	plaqueGui.Adornee = head
	plaqueGui.Parent = dressing
	local halo = Instance.new("Frame")
	halo.AnchorPoint = Vector2.new(0.5, 0)
	halo.Position = UDim2.new(0.5, 0, 0, 0)
	halo.Size = UDim2.fromOffset(266, 42)
	halo.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
	halo.BackgroundTransparency = 0.6
	halo.BorderSizePixel = 0
	halo.Parent = plaqueGui
	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(0.5, 0)
	haloCorner.Parent = halo
	local plaque = Instance.new("Frame")
	plaque.AnchorPoint = Vector2.new(0.5, 0.5)
	plaque.Position = UDim2.fromScale(0.5, 0.5)
	plaque.Size = UDim2.new(1, -8, 1, -8)
	plaque.BackgroundColor3 = Color3.new(1, 1, 1)
	plaque.BorderSizePixel = 0
	plaque.Parent = halo
	local plaqueCorner = Instance.new("UICorner")
	plaqueCorner.CornerRadius = UDim.new(0.5, 0)
	plaqueCorner.Parent = plaque
	local plaqueGradient = Instance.new("UIGradient")
	plaqueGradient.Color = ColorSequence.new(Color3.fromRGB(78, 42, 120), Color3.fromRGB(16, 8, 30))
	plaqueGradient.Rotation = 90
	plaqueGradient.Parent = plaque
	local plaqueRim = Instance.new("UIStroke")
	plaqueRim.Thickness = 3
	plaqueRim.Color = GOLD
	plaqueRim.Parent = plaque
	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.fromScale(0.5, 0.5)
	nameLabel.Size = UDim2.new(1, -30, 1, -8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.Text = "🎃 " .. settings.Merchant.Name .. " 🎃"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Parent = plaque
	local nameGradient = Instance.new("UIGradient")
	nameGradient.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 170, 60))
	nameGradient.Rotation = 90
	nameGradient.Parent = nameLabel
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(20, 8, 30)
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLabel
	local tagline = Instance.new("TextLabel")
	tagline.AnchorPoint = Vector2.new(0.5, 0)
	tagline.Position = UDim2.new(0.5, 0, 0, 44)
	tagline.Size = UDim2.fromOffset(240, 22)
	tagline.BackgroundTransparency = 1
	tagline.Font = Enum.Font.FredokaOne
	tagline.TextScaled = true
	tagline.Text = "🍬 Trade your Candy! 🍬"
	tagline.TextColor3 = Color3.fromRGB(255, 190, 235)
	tagline.Parent = plaqueGui
	local taglineStroke = Instance.new("UIStroke")
	taglineStroke.Color = Color3.fromRGB(30, 10, 40)
	taglineStroke.Thickness = 2
	taglineStroke.Parent = tagline
end

-- Adopt the authored merchant (find by tag/name, never move or rebuild it), make sure his prompt exists and
-- opens the shop. Builds the default only if no merchant exists at all.
local function adoptMerchant()
	local model = findMerchantModel()
	if not model then
		local authoredWorld = workspace:FindFirstChild("HalloweenWorld") or stashedWorld
		if authoredWorld and authoredWorld:GetAttribute("AutoBuilt") ~= true then
			-- the designer removed the merchant on purpose: he stays removed (no shop prompt either)
			merchantModel = nil
			return
		end
		buildDefaultMerchant()
		model = findMerchantModel()
	end
	merchantModel = model
	local part = merchantPart()
	if not model or not part then
		warn("[HalloweenService] no Pumpkin Merchant found or built")
		return
	end
	local dressed, dressFailure = pcall(dressMerchant, model)
	if not dressed then
		warn("[HalloweenService] merchant dressing failed:", dressFailure)
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local found = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		prompt = found
	end
	if not prompt then
		prompt = Build.MakePrompt(part, "MerchantPrompt", "Open Shop", Enum.KeyCode.E, 0)
		prompt.ObjectText = settings.Merchant.Name
		prompt.MaxActivationDistance = settings.Merchant.PromptDistance
	end
	prompt.Enabled = true
	if merchantPromptConnection then
		merchantPromptConnection:Disconnect()
	end
	merchantPromptConnection = prompt.Triggered:Connect(openShopFor)
end

-- Mother Invasion -------------------------------------------------------------------------------------

local function speciesWeights(): { [string]: number }
	local weights: { [string]: number } = {}
	for key, species in Config.Species do
		if species.Model and not species.EventOnly then
			weights[key] = Config.NestRarityWeights[species.Rarity] or 1
		end
	end
	return weights
end

local function updateBar(invader: Invader)
	local tracker = invader.Tracker
	invader.Fill.Size = UDim2.fromScale(math.clamp(tracker.Health / tracker.MaxHealth, 0, 1), 1)
	invader.Text.Text = MonsterMath.FormatNumber(math.max(0, tracker.Health)) .. " / " .. MonsterMath.FormatNumber(tracker.MaxHealth)
end

local function removeInvader(invader: Invader)
	invader.Alive = false
	CombatService.Unregister(invader.Target)
	invader.Target = nil
	invader.Model:Destroy()
	local index = table.find(invaders, invader)
	if index then
		table.remove(invaders, index)
	end
	if invader.HeldNest then
		ZoneService.ReleaseNest(invader.HeldNest)
		invader.HeldNest = nil
	end
end

local function settleInvader(invader: Invader, killerName: string)
	if not invader.Alive then
		return
	end
	local rewards = HalloweenLogic.Settle(invader.Tracker, invasionSettings, invader.Level)
	removeInvader(invader)
	local name = invader.Title
	announce(string.format("🎃 %s finished off a Lv %d %s Mother!", killerName, invader.Level, name), Color3.fromRGB(255, 170, 60))
	for _, reward in rewards do
		local player = Players:GetPlayerByUserId(reward.UserId)
		if player then
			local granted = HalloweenService.AddCandy(player, reward.Candy)
			if granted > 0 then
				notify(player, string.format("🍬 +%d Candy for helping defeat the Lv %d %s!", granted, invader.Level, name), "success")
			end
		end
	end
	if #invaders == 0 then
		announce("🎃 The Mother Invasion has been repelled! Great teamwork!", Color3.fromRGB(120, 255, 140))
		setNight("Invasion", false)
		pushAll()
	end
end

local function spawnInvader(position: Vector3, level: number, species: string, heldNest: Vector3?): Invader?
	local info = Config.Species[species].Model
	local template = info and MonsterModels.Get(info.Region, info.Index, "Adult")
	if not info or not template or not invaderFolder then
		return nil
	end
	local model: Model = template
	local motherScale = Config.MotherScale
	local title = Config.Species[species].DisplayName
	model:ScaleTo(motherScale)
	local pivotHeight = (model:GetAttribute("Scale") or 1) * motherScale
	model:SetAttribute("PivotHeight", pivotHeight)
	local focus = Vector3.new(Config.Map.PlazaMinX + 40, position.Y + pivotHeight, 0)
	model:PivotTo(CFrame.lookAt(position + Vector3.new(0, pivotHeight, 0), focus))
	model.Name = "Mother"
	model:SetAttribute("AnimState", "Idle")
	model:SetAttribute("HalloweenInvader", true)
	model.Parent = invaderFolder
	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return nil
	end

	local styles = Config.MotherAttacks.Styles
	local rigType = model:GetAttribute("RigType") :: string
	local combo = Config.MotherAttacks.ComboStyles[rigType]
	local style: Config.MotherStyle = if combo and level >= 30 then combo else (styles[rigType] or styles.Quad)
	model:SetAttribute("AttackWindup", style.Windup)
	model:SetAttribute("ComboHits", style.Hits)
	model:SetAttribute("ComboInterval", style.HitInterval)
	local extents = model:GetExtentsSize()
	local height = extents.Y - pivotHeight
	-- the event monsters live in the extra Halloween model region, which has no zone element: they use Void's
	local regionInfo = Config.RegionMonsters[info.Region]
	local element = if regionInfo then regionInfo.Region else "Void"
	local maxHealth = HalloweenLogic.HealthForLevel(invasionSettings, level)

	local gui, label = Build.MakeBillboard(root, UDim2.fromScale(16, 5.5), Vector3.new(0, height + 4, 0), 140)
	gui.Name = "Info"
	gui.AlwaysOnTop = false
	label.Size = UDim2.fromScale(1, 0.6)
	label.Text = string.format(
		'<font color="#FFA030">🎃 %s</font> · Lv %d MOTHER\n<font color="%s">%s</font>',
		title,
		level,
		Build.ColorToHex(Config.Rarities[Config.Species[species].Rarity].Color),
		Config.Species[species].Rarity
	)
	local bar = Instance.new("Frame")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromScale(1, 0.32)
	bar.Position = UDim2.fromScale(0, 0.66)
	bar.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 120, 30)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local text = Instance.new("TextLabel")
	text.Name = "HealthText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.ZIndex = 2
	text.Parent = bar
	local glowFire = Instance.new("Fire")
	glowFire.Color = Color3.fromRGB(255, 130, 30)
	glowFire.SecondaryColor = Color3.fromRGB(120, 40, 160)
	glowFire.Size = 6
	glowFire.Heat = 4
	glowFire.Parent = root
	-- Halloween dressing for the regular Mother: a haunted outline, a jack-o'-lantern glow, drifting wisps and embers
	local haunt = Instance.new("Highlight")
	haunt.Name = "HauntedGlow"
	haunt.FillColor = Color3.fromRGB(255, 120, 30)
	haunt.FillTransparency = 0.85
	haunt.OutlineColor = Color3.fromRGB(170, 70, 255)
	haunt.OutlineTransparency = 0.25
	haunt.DepthMode = Enum.HighlightDepthMode.Occluded
	haunt.Parent = model
	local lantern = Instance.new("PointLight")
	lantern.Color = Color3.fromRGB(255, 140, 40)
	lantern.Range = 22
	lantern.Brightness = 2
	lantern.Shadows = false
	lantern.Parent = root
	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "SpookyWisps"
	wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(170, 90, 255), Color3.fromRGB(60, 20, 90))
	wisps.LightEmission = 0.6
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	wisps.Lifetime = NumberRange.new(2, 3.5)
	wisps.Rate = 8
	wisps.Speed = NumberRange.new(1, 3)
	wisps.SpreadAngle = Vector2.new(180, 180)
	wisps.Acceleration = Vector3.new(0, 3, 0)
	wisps.Parent = root
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "PumpkinEmbers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 90, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Rate = 14
	embers.Speed = NumberRange.new(2, 6)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Parent = root

	local invader: Invader = {
		Level = level,
		Species = species,
		Title = title,
		HeldNest = heldNest,
		Element = element,
		Model = model,
		Root = root,
		Tracker = HalloweenLogic.NewTracker(maxHealth),
		Target = nil,
		Style = style,
		Fill = fill,
		Text = text,
		Home = Vector3.new(position.X, position.Y, position.Z),
		BodyRadius = math.max(extents.X, extents.Z) / 2,
		Alive = true,
		Aggro = nil,
		Moving = false,
		NextAttackAt = 0,
		WindingUntil = 0,
		Engaged = false,
	}
	updateBar(invader)
	invader.Target = CombatService.Register({
		Part = root,
		Radius = invader.BodyRadius,
		OnHit = function(player: Player, damage: number)
			-- only a loaded, living, in-game player's hit is recorded; the damage number itself comes from
			-- CombatService (cooldown + weapon validated there), never from a client-supplied value.
			if not invader.Alive or not active or not player.Parent or not DataService.Get(player) then
				return
			end
			local applied = invader.Tracker:Record(player.UserId, damage)
			if applied <= 0 then
				return
			end
			invader.Aggro = player.UserId
			PlotService.Flash(model, Color3.fromRGB(255, 80, 80))
			updateBar(invader)
			if invader.Tracker.Health <= 0 then
				settleInvader(invader, player.DisplayName)
			end
		end,
	})
	table.insert(invaders, invader)
	return invader
end

-- Event Mothers take over zone nests (one per nest, at random): the nest holds either its regular Mother or an
-- event Mother, never both. Only if there are no nests (e.g. a bare test place) do they use the open plaza.
local function pickNestSpots(count: number): { Vector3 }
	local centers = ZoneService.GetNestCenters()
	for index = #centers, 2, -1 do
		local swap = rng:NextInteger(1, index)
		centers[index], centers[swap] = centers[swap], centers[index]
	end
	local spots: { Vector3 } = {}
	for index = 1, math.min(count, #centers) do
		table.insert(spots, centers[index])
	end
	return spots
end

local function pickInvasionSpots(count: number): { Vector3 }
	local area = invasionSettings.Area
	local spots: { Vector3 } = {}
	local attempts = 0
	local spacing = invasionSettings.SpawnSpacing
	while #spots < count and attempts < 400 do
		attempts += 1
		local relax = if attempts > 250 then 0.5 else 1
		local candidate = Vector3.new(rng:NextNumber(area.MinX, area.MaxX), 0.2, rng:NextNumber(-area.HalfZ, area.HalfZ))
		local ok = true
		for _, other in spots do
			if flatDistance(candidate, other) < spacing * relax then
				ok = false
				break
			end
		end
		if ok and clearOf(candidate.X, candidate.Z, 6) then
			table.insert(spots, candidate)
		end
	end
	return spots
end

function HalloweenService.StartInvasion(forcedCount: number?): number
	if not active or not invaderFolder then
		return 0
	end
	-- an unfinished previous wave runs off before the next one arrives
	for _, leftover in table.clone(invaders) do
		removeInvader(leftover)
	end
	invasionCounter += 1
	local waveId = invasionCounter
	local count = forcedCount or HalloweenLogic.RollInvasionCount(invasionSettings, rng:NextNumber())
	count = math.max(invasionSettings.MinCount, math.floor(count))
	local weights = speciesWeights()
	local spawned = 0
	local nestSpots = pickNestSpots(count)
	local fromNests = #nestSpots > 0
	for _, spot in (if fromNests then nestSpots else pickInvasionSpots(count)) do
		local level = rng:NextInteger(invasionSettings.MinLevel, invasionSettings.MaxLevel)
		local species = HalloweenLogic.WeightedPick(weights, rng:NextNumber()) :: string?
		local held = fromNests and ZoneService.HoldNest(spot)
		if species and spawnInvader(spot, level, species, if held then spot else nil) then
			spawned += 1
		elseif held then
			ZoneService.ReleaseNest(spot)
		end
	end
	setNight("Invasion", spawned > 0)
	if spawned > 0 then
		announce(string.format("👹 MOTHER INVASION! %d haunted Mothers have risen in the monster zones! Defeat them for Candy!", spawned), Color3.fromRGB(255, 110, 40))
		pushAll()
		task.delay(invasionSettings.Lifetime, function()
			if invasionCounter ~= waveId or not active then
				return
			end
			local left = 0
			for _, invader in table.clone(invaders) do
				left += 1
				removeInvader(invader)
			end
			setNight("Invasion", false)
			if left > 0 then
				announce("The Mothers retreated into the fog... see you in half an hour!", Color3.fromRGB(200, 200, 200))
				pushAll()
			end
		end)
	end
	return spawned
end

local function invaderStep(dt: number)
	local area = invasionSettings.Area
	local now = os.clock()
	for _, invader in table.clone(invaders) do
		if not invader.Alive or not invader.Model.Parent then
			continue
		end
		if now < invader.WindingUntil then
			continue
		end
		local pivot = invader.Model:GetPivot()
		local nearest: Player? = nil
		local nearestRoot: BasePart? = nil
		local bestScore = math.huge
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and isAlive(player) and not CombatService.IsInSafeZone(root.Position) then
				local distance = flatDistance(root.Position, pivot.Position)
				local isAggro = invader.Aggro == player.UserId
				local inRange = distance <= invasionSettings.NoticeRange or (isAggro and distance <= invasionSettings.LeashRange)
				if inRange then
					local score = if isAggro then distance - 1000 else distance
					if score < bestScore then
						nearest, nearestRoot, bestScore = player, root, score
					end
				end
			end
		end
		if invader.Aggro and not nearest then
			invader.Aggro = nil
		end

		local goal = invader.Home
		local stopDistance = 0.5
		if nearestRoot then
			goal = nearestRoot.Position
			stopDistance = invader.BodyRadius + 2
		end
		local offset = Vector3.new(goal.X - pivot.Position.X, 0, goal.Z - pivot.Position.Z)
		local distance = offset.Magnitude
		local moving = distance > stopDistance
		if moving then
			local step = math.min(invasionSettings.ChaseSpeed * dt, distance - stopDistance)
			local position = pivot.Position + offset.Unit * step
			if invader.HeldNest then
				-- a nest Mother roams around her own nest (never snapped back to the plaza box below)
				local fromHome = Vector3.new(position.X - invader.Home.X, 0, position.Z - invader.Home.Z)
				if fromHome.Magnitude > invasionSettings.LeashRange then
					position = Vector3.new(invader.Home.X, pivot.Position.Y, invader.Home.Z) + fromHome.Unit * invasionSettings.LeashRange
				end
			else
				-- never leave the plaza, never walk into a base
				position = Vector3.new(
					math.clamp(position.X, area.MinX - 6, area.MaxX + 6),
					pivot.Position.Y,
					math.clamp(position.Z, -area.HalfZ - 10, area.HalfZ + 10)
				)
			end
			invader.Model:PivotTo(CFrame.lookAt(position, position + offset.Unit))
		end
		if moving ~= invader.Moving then
			invader.Moving = moving
			invader.Model:SetAttribute("AnimState", if moving then "Walk" else "Idle")
		end

		-- M1 on whoever is within reach
		if nearestRoot and nearest then
			local style = invader.Style
			local reach = if style.Shape == "Slam" then style.Radius else math.min(style.Range, Config.MotherAttacks.AggroRange)
			local current = invader.Model:GetPivot()
			if flatDistance(nearestRoot.Position, current.Position) <= invader.BodyRadius + reach then
				if not invader.Engaged then
					invader.Engaged = true
					invader.NextAttackAt = math.max(invader.NextAttackAt, now + Config.MotherAttacks.FirstAttackDelay)
				end
				if now >= invader.NextAttackAt then
					local look = Vector3.new(nearestRoot.Position.X, current.Position.Y, nearestRoot.Position.Z)
					if (look - current.Position).Magnitude > 0.1 then
						invader.Model:PivotTo(CFrame.lookAt(current.Position, look))
					end
					invader.Model:SetAttribute("AnimState", "Attack")
					invader.Moving = false
					local model = invader.Model
					local windup = MonsterAttack.Start({
						Model = model,
						Root = invader.Root,
						BodyRadius = invader.BodyRadius,
						Target = nearestRoot,
						Style = style,
						Element = invader.Element,
						Damage = HalloweenLogic.DamageForLevel(invasionSettings, invader.Level),
						IsValid = function()
							return invader.Alive and active
						end,
					})
					invader.WindingUntil = now + windup + 0.25
					invader.NextAttackAt = now + windup + style.Cooldown
					task.delay(windup + 0.25, function()
						if invader.Alive and not invader.Moving then
							model:SetAttribute("AnimState", "Idle")
						end
					end)
				end
			else
				invader.Engaged = false
			end
		else
			invader.Engaged = false
		end
	end
end

-- Pumpkin Hunt ----------------------------------------------------------------------------------------

-- Where a pumpkin can hide in the monster zones: anywhere between the walls, away from every Mother nest.
local function pickZoneSpot(others: { Vector3 }, relax: number): Vector3?
	local pad = pumpkinSettings.ZonePadding
	local minX = pumpkinSettings.ZoneArea.MinX + pad
	local maxX = pumpkinSettings.ZoneArea.MaxX - pad
	local halfZ = pumpkinSettings.ZoneArea.HalfZ - pad
	local nestCenters = ZoneService.GetNestCenters(true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { pumpkinFolder :: Instance, invaderFolder :: Instance }
	for _ = 1, 30 do
		local x, z = rng:NextNumber(minX, maxX), rng:NextNumber(-halfZ, halfZ)
		local candidate = Vector3.new(x, 0.2, z)
		local ok = true
		for _, center in nestCenters do
			if flatDistance(candidate, center) < pumpkinSettings.NestClear then
				ok = false
				break
			end
		end
		if ok then
			for _, other in others do
				if flatDistance(candidate, other) < pumpkinSettings.MinSpacing * relax then
					ok = false
					break
				end
			end
		end
		if ok then
			local hit = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -240, 0), params)
			return Vector3.new(x, if hit then hit.Position.Y else 0.2, z)
		end
	end
	return nil
end

-- Each pumpkin hides either in the plaza or in the monster zones (ZonesShare of them go to the zones).
local function pickPumpkinSpots(count: number): { Vector3 }
	local area = pumpkinSettings.Area
	local spots: { Vector3 } = {}
	local attempts = 0
	while #spots < count and attempts < 900 do
		attempts += 1
		local relax = if attempts > 600 then 0.4 else 1
		if rng:NextNumber() < pumpkinSettings.ZonesShare then
			local zoneSpot = pickZoneSpot(spots, relax)
			if zoneSpot then
				table.insert(spots, zoneSpot)
			end
		else
			local candidate = Vector3.new(rng:NextNumber(area.MinX, area.MaxX), 0.2, rng:NextNumber(-area.HalfZ, area.HalfZ))
			local ok = clearOf(candidate.X, candidate.Z, 0)
			if ok then
				for _, other in spots do
					if flatDistance(candidate, other) < pumpkinSettings.MinSpacing * relax then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(spots, candidate)
			end
		end
	end
	return spots
end

local function endHunt(current: Hunt, message: string?)
	if hunt ~= current then
		return
	end
	hunt = nil
	setNight("Hunt", false)
	for _, pumpkin in current.Pumpkins do
		pumpkin.Claimed = true
		if pumpkin.Part.Parent then
			pumpkin.Part:Destroy()
		end
	end
	if message then
		announce(message, Color3.fromRGB(255, 170, 60))
	end
	pushAll()
end

local function claimPumpkin(player: Player, current: Hunt, pumpkin: Pumpkin)
	if hunt ~= current or pumpkin.Claimed or not active then
		return
	end
	local now = os.clock()
	if lastPick[player] and now - lastPick[player] < pumpkinSettings.PickupDebounce then
		return
	end
	local root = rootOf(player)
	if not root or not isAlive(player) or not pumpkin.Part.Parent or not hdata(player) then
		return
	end
	-- trust the player's real position, not the fact that the prompt fired
	if (root.Position - pumpkin.Part.Position).Magnitude > pumpkinSettings.PickupDistance then
		return
	end
	lastPick[player] = now
	pumpkin.Claimed = true
	pumpkin.Part:Destroy()
	current.Remaining -= 1
	local granted = HalloweenService.AddCandy(player, pumpkin.Candy)
	if pumpkin.Golden then
		announce(string.format("✨ %s found the GOLDEN PUMPKIN (+%d Candy)!", player.DisplayName, granted), Color3.fromRGB(255, 220, 80))
	else
		notify(player, string.format("🎃 Pumpkin found! +%d Candy (%d left)", granted, current.Remaining), "success")
	end
	if current.Remaining <= 0 then
		endHunt(current, "🎃 All the pumpkins have been found! See you in 15 minutes.")
	else
		pushAll()
	end
end

local function makePumpkinModel(position: Vector3, golden: boolean): Part
	local size = if golden then 3.8 else 3.2
	-- a glossy jack-o'-lantern candy bowl: ribbed pumpkin, carved face, and a heap of lollipops and sweets on top
	local tint = if golden then Color3.fromRGB(255, 225, 120) else nil
	local height = PumpkinVisual.MeshSize.Y * (size * 1.1) / PumpkinVisual.MeshSize.X
	local focus = Vector3.new(Config.Map.PlazaMinX + 40, position.Y, 0)
	local flat = Vector3.new(position.X, position.Y, position.Z)
	local base = if (focus - flat).Magnitude > 1 then CFrame.lookAt(flat, focus) else CFrame.new(flat)
	local function add(parent: Instance, props: { [string]: any }, offset: CFrame): Part
		props.CFrame = base * offset
		props.Anchored = true
		props.CanCollide = false
		props.CanQuery = false
		props.CanTouch = false
		props.Parent = parent
		if props.Material == nil then props.Material = Enum.Material.SmoothPlastic end
		local created = makePart(props)
		created.Reflectance = props.Reflectance or 0.06
		return created
	end
	local body = add(pumpkinFolder :: Instance, {
		Name = if golden then "GoldenPumpkin" else "HuntPumpkin",
		Size = Vector3.new(size * 1.1, height, size * 1.05), Color = Color3.new(1, 1, 1),
	}, CFrame.new(0, height / 2, 0))
	PumpkinVisual.Apply(body, size * 1.1, tint)
	body.CanQuery = true
	-- lollipops: a flat swirl disc on a stick, fanned out of the top
	local pastel = {
		{ Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 150, 40) },
		{ Color3.fromRGB(190, 150, 255), Color3.fromRGB(150, 225, 130) },
		{ Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 245, 235) },
	}
	local lollipops = {
		{ x = -0.30, tilt = 22, rise = 1.15 },
		{ x = 0.06, tilt = -4, rise = 1.4 },
		{ x = 0.36, tilt = -26, rise = 1.1 },
	}
	for index, pop in lollipops do
		local pair = pastel[index]
		local stickLength = size * pop.rise
		local mount = CFrame.new(pop.x * size, height * 0.9, 0) * CFrame.Angles(0, 0, math.rad(pop.tilt))
		add(body, { Name = "LollipopStick", Size = Vector3.new(size * 0.05, stickLength, size * 0.05), Color = Color3.fromRGB(245, 240, 230) }, mount * CFrame.new(0, stickLength / 2, 0))
		local discSize = size * (0.46 - (index - 1) * 0.03)
		local discPos = mount * CFrame.new(0, stickLength, 0) * CFrame.Angles(0, math.rad(90), 0)
		add(body, { Name = "LollipopDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.07, discSize, discSize), Color = pair[1] }, discPos)
		add(body, { Name = "LollipopSwirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.075, discSize * 0.6, discSize * 0.6), Color = pair[2] }, discPos * CFrame.new(size * 0.005, 0, 0))
		add(body, { Name = "LollipopCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.08, discSize * 0.25, discSize * 0.25), Color = pair[1] }, discPos * CFrame.new(size * 0.01, 0, 0))
	end
	-- sweets piled in the opening and spilling out of the mouth
	local sweets = {
		{ Vector3.new(-0.5, 0.98, 0.1), 0.26, Color3.fromRGB(255, 190, 60) },
		{ Vector3.new(0.52, 0.96, -0.05), 0.24, Color3.fromRGB(160, 225, 120) },
		{ Vector3.new(-0.12, 1.02, 0.25), 0.22, Color3.fromRGB(190, 150, 255) },
		{ Vector3.new(0.18, 1.02, -0.22), 0.25, Color3.fromRGB(255, 130, 40) },
		{ Vector3.new(0.42, 0.2, -0.54), 0.2, Color3.fromRGB(255, 220, 90) },
		{ Vector3.new(-0.46, 0.18, -0.55), 0.18, Color3.fromRGB(160, 225, 120) },
		{ Vector3.new(0.03, 0.1, -0.6), 0.2, Color3.fromRGB(190, 150, 255) },
	}
	for _, sweet in sweets do
		local diameter = size * sweet[2]
		add(body, { Name = "Sweet", Shape = Enum.PartType.Ball, Size = Vector3.new(diameter, diameter, diameter), Color = sweet[3] },
			CFrame.new(sweet[1].X * size, height * sweet[1].Y - diameter * 0.2, sweet[1].Z * size))
	end
	-- wrapped candies: a small barrel with a twisted wrapper at each end
	for index, wrapperColor in { Color3.fromRGB(255, 150, 40), Color3.fromRGB(190, 150, 255) } do
		local wrapSide = if index == 1 then -1 else 1
		local at = CFrame.new(wrapSide * size * 0.28, height * 1.02, size * 0.16) * CFrame.Angles(0, math.rad(40 * wrapSide), math.rad(20 * wrapSide))
		add(body, { Name = "WrappedCandy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.3, size * 0.17, size * 0.17), Color = wrapperColor }, at)
		for _, end_ in { -1, 1 } do
			add(body, { Name = "Wrapper", Size = Vector3.new(size * 0.1, size * 0.2, size * 0.04), Color = wrapperColor }, at * CFrame.new(end_ * size * 0.2, 0, 0))
		end
	end
	local light = Instance.new("PointLight")
	light.Color = if golden then Color3.fromRGB(255, 230, 120) else Color3.fromRGB(255, 150, 50)
	light.Range = if golden then 20 else 12
	light.Brightness = if golden then 2.2 else 1.2
	light.Shadows = false
	light.Parent = body
	return body
end

function HalloweenService.StartPumpkinHunt(): number
	if not active or not pumpkinFolder then
		return 0
	end
	if hunt then
		endHunt(hunt :: Hunt, nil)
	end
	huntCounter += 1
	local current: Hunt = { Id = huntCounter, Pumpkins = {}, Remaining = 0, EndsAt = os.clock() + pumpkinSettings.Lifetime, LastHintAt = 0 }
	local goldenIndex: number? = nil
	local count = rng:NextInteger(pumpkinSettings.CountMin, pumpkinSettings.CountMax)
	if rng:NextNumber() < pumpkinSettings.GoldenChance then
		goldenIndex = rng:NextInteger(1, count)
	end
	for index, spot in pickPumpkinSpots(count) do
		local golden = goldenIndex == index
		local part = makePumpkinModel(spot, golden)
		local pumpkin: Pumpkin = {
			Part = part,
			Golden = golden,
			Candy = HalloweenLogic.PumpkinCandy(pumpkinSettings, golden, rng:NextNumber()),
			Claimed = false,
		}
		local prompt = Build.MakePrompt(part, "PumpkinPrompt", "Pick up", Enum.KeyCode.E, 0.2)
		prompt.ObjectText = if golden then "Golden Pumpkin" else "Pumpkin"
		prompt.MaxActivationDistance = 10
		prompt.Triggered:Connect(function(player: Player)
			claimPumpkin(player, current, pumpkin)
		end)
		table.insert(current.Pumpkins, pumpkin)
		current.Remaining += 1
	end
	if current.Remaining == 0 then
		return 0
	end
	hunt = current
	setNight("Hunt", true)
	announce(string.format("🎃 PUMPKIN HUNT! %d pumpkins are hiding in the plaza and the monster zones for %d minutes. Go find them!", current.Remaining, math.floor(pumpkinSettings.Lifetime / 60)), Color3.fromRGB(255, 150, 40))
	pushAll()
	task.delay(pumpkinSettings.Lifetime, function()
		if hunt == current then
			endHunt(current, "The pumpkins rotted away... next hunt in 15 minutes!")
		end
	end)
	return current.Remaining
end

-- shop ------------------------------------------------------------------------------------------------

local function nearMerchant(player: Player): boolean
	local root = rootOf(player)
	local merchant = merchantPart()
	return root ~= nil and merchant ~= nil and (root.Position - merchant.Position).Magnitude <= settings.Merchant.ShopDistance * 1.5
end

local function countSpecies(data: any, species: string): number
	local count = 0
	for _, monster in data.Monsters do
		if monster.Species == species then count += 1 end
	end
	return count
end

local function countRecords(records: any): number
	local count = 0
	for _ in records do count += 1 end
	return count
end

local REASONS = {
	NoCandy = "Not enough Candy!",
	Owned = "You already own that!",
	BoostCap = "You already have the maximum boost time stored.",
	Unknown = "That item isn't available.",
}

local function onBuy(player: Player, itemId: unknown)
	if type(itemId) ~= "string" then
		return
	end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < settings.Merchant.PurchaseCooldown then
		return
	end
	lastBuy[player] = now
	if not active then
		notify(player, "The Halloween event is over.", "error")
		return
	end
	if busy[player] or not nearMerchant(player) then
		return
	end
	local profile = DataService.Get(player)
	local data = hdata(player)
	if not profile or not data then
		return
	end
	busy[player] = true
	local done, failure = pcall(function()
		-- Speed has its own timer (the same one as the Robux Speed Boost), so its stacking cap is checked here.
		local speedItem = settings.Items[itemId]
		if speedItem and speedItem.Kind == "Speed"
			and math.max(0, profile.Data.SpeedBoostUntil - os.time()) + (speedItem.Duration or 0) > (speedItem.MaxBoostSeconds or 0) then
			notify(player, REASONS.BoostCap, "error")
			return
		end
		local ok, reason, purchase = HalloweenLogic.ApplyPurchase(data :: any, itemId, settings.Items, os.time(), rng:NextNumber())
		if not ok or not purchase then
			notify(player, REASONS[reason] or "Can't buy that right now.", "error")
			return
		end
		local item = settings.Items[itemId]
		local granted = true
		if purchase.Kind == "Egg" then
			local eggType = purchase.EggType :: string
			local before = countRecords(profile.Data.Eggs)
			if Config.Eggs[eggType] then
				local called, result = pcall(MonsterService.AddEgg, player, eggType)
				-- judge by the egg record itself, so a render error can't both grant and refund
				granted = (called and result == true) or countRecords(profile.Data.Eggs) > before
				if not called then
					warn("[HalloweenService] AddEgg failed:", result)
				end
			else
				granted = false
			end
			if granted then
				notify(player, string.format("🥚 The Haunted Egg turned out to be a %s!", Config.Eggs[eggType].DisplayName), "success")
			end
		elseif purchase.Kind == "Monster" then
			local species = purchase.Species :: string
			local before = countSpecies(profile.Data, species)
			local called, result = pcall(MonsterService.AddMonster, player, species, nil)
			granted = (called and result == true) or countSpecies(profile.Data, species) > before
			if not called then
				warn("[HalloweenService] AddMonster failed:", result)
			end
		end
		if not granted then
			purchase.Undo()
			notify(player, "Couldn't deliver that item, your Candy was not spent.", "error")
			return
		end
		if purchase.Kind == "Boost" then
			notify(player, string.format("🍬 %s active: %dx cash!", item.Name, item.Multiplier or 2), "success")
			MonsterService.PushState(player)
		elseif purchase.Kind == "Speed" then
			profile.Data.SpeedBoostUntil = math.max(os.time(), profile.Data.SpeedBoostUntil) + (item.Duration or 0)
			CharacterService.SetSpeedFactor(player, "Boost", item.Multiplier or Config.SpeedBoost.Multiplier)
			notify(player, string.format("💨 %s active for %d minutes!", item.Name, math.floor((item.Duration or 0) / 60)), "success")
			MonsterService.PushState(player)
		elseif purchase.Kind == "Hat" or purchase.Kind == "Trail" or purchase.Kind == "Aura" or purchase.Kind == "Title" then
			notify(player, "🎃 " .. item.Name .. " unlocked and equipped!", "success")
			pcall(applyCosmetics, player)
		end
		saveSoon(player)
	end)
	busy[player] = nil
	if not done then
		warn("[HalloweenService] purchase failed:", failure)
	end
	pushState(player)
end

local function onEquip(player: Player, itemId: unknown, equip: unknown)
	if type(itemId) ~= "string" or type(equip) ~= "boolean" or not active then
		return
	end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < settings.Merchant.PurchaseCooldown then
		return
	end
	lastBuy[player] = now
	local data = hdata(player)
	if not data or not HalloweenLogic.SetEquipped(data :: any, itemId, settings.Items, equip) then
		return
	end
	applyCosmetics(player)
	saveSoon(player)
	pushState(player)
end

local function onSync(player: Player)
	local now = os.clock()
	if lastSync[player] and now - lastSync[player] < 1 then
		return
	end
	lastSync[player] = now
	pushState(player)
end

-- lifecycle -------------------------------------------------------------------------------------------

function HalloweenService.Start()
	if active then
		return
	end
	active = true
	local existing = workspace:FindFirstChild("HalloweenEvent")
	if existing then
		existing:Destroy()
	end
	rootFolder = folder("HalloweenEvent", workspace)
	invaderFolder = folder("Invaders", rootFolder :: Folder)
	pumpkinFolder = folder("Pumpkins", rootFolder :: Folder)
	showWorld()
	buildProps() -- adopts Workspace.HalloweenWorld.Props (builds a default only if it is missing)
	adoptMerchant() -- adopts the authored Pumpkin Merchant wherever he stands now
	local now = os.time()
	nextInvasionAt = HalloweenLogic.NextOccurrence(now, invasionSettings.Interval, invasionSettings.Offset)
	nextPumpkinAt = HalloweenLogic.NextOccurrence(now, pumpkinSettings.Interval, pumpkinSettings.Offset)
	announce("🎃 " .. settings.Name .. " has begun! Visit the Pumpkin Merchant and watch for Mother Invasions and Pumpkin Hunts!", Color3.fromRGB(255, 150, 40))
	for _, player in Players:GetPlayers() do
		applyCosmetics(player)
	end
	pushAll()
end

function HalloweenService.Stop()
	if not active then
		return
	end
	active = false
	invasionCounter += 1 -- cancels pending despawn timers
	for _, invader in table.clone(invaders) do
		removeInvader(invader)
	end
	table.clear(invaders)
	if hunt then
		endHunt(hunt :: Hunt, nil)
	end
	hunt = nil
	table.clear(nightHolds)
	restoreAtmosphere()
	if rootFolder then
		rootFolder:Destroy() -- runtime-only objects (invaders, pumpkin pickups)
	end
	if merchantPromptConnection then
		merchantPromptConnection:Disconnect()
		merchantPromptConnection = nil
	end
	hideWorld() -- the authored decorations/merchant are stashed (never destroyed) until the event runs again
	rootFolder, invaderFolder, pumpkinFolder, propFolder, merchantModel = nil, nil, nil, nil, nil
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			removeCosmetics(character)
		end
		HalloweenService.ConvertCandy(player)
	end
	announce("🎃 " .. settings.Name .. " has ended. Leftover Candy was converted into coins. Thanks for playing!", Color3.fromRGB(200, 200, 200))
end

function HalloweenService.IsActive(): boolean
	return active
end

-- Called after a profile loads. When the event isn't running, any leftover Candy is converted here.
function HalloweenService.SetupPlayer(player: Player)
	if active then
		task.spawn(applyCosmetics, player)
		pushState(player)
	else
		HalloweenService.ConvertCandy(player)
		pushState(player)
	end
end

function HalloweenService.CleanupPlayer(player: Player)
	lastBuy[player] = nil
	lastPick[player] = nil
	lastSync[player] = nil
	busy[player] = nil
end

local function schedulerStep()
	local wanted = wantActive()
	if wanted and not active then
		HalloweenService.Start()
	elseif not wanted and active then
		HalloweenService.Stop()
	end
	if not active then
		return
	end
	local now = os.time()
	if now >= nextInvasionAt then
		HalloweenService.StartInvasion()
		nextInvasionAt = HalloweenLogic.NextOccurrence(now, invasionSettings.Interval, invasionSettings.Offset)
		announcedInvasionAt = 0
	elseif nextInvasionAt - now <= invasionSettings.AnnounceBefore and announcedInvasionAt ~= nextInvasionAt then
		announcedInvasionAt = nextInvasionAt
		setNight("Invasion", true) -- night falls with the 60 s warning
		announce(string.format("⚠️ Mother Invasion in %d seconds! Grab your weapons and get ready to defend the plaza!", math.max(1, nextInvasionAt - now)), Color3.fromRGB(255, 90, 60))
	end
	if now >= nextPumpkinAt then
		HalloweenService.StartPumpkinHunt()
		nextPumpkinAt = HalloweenLogic.NextOccurrence(now, pumpkinSettings.Interval, pumpkinSettings.Offset)
	end
end

function HalloweenService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	remotes.HalloweenBuy.OnServerEvent:Connect(onBuy)
	remotes.HalloweenEquip.OnServerEvent:Connect(onEquip)
	remotes.HalloweenSync.OnServerEvent:Connect(onSync)

	if wantActive() then
		HalloweenService.Start()
	else
		hideWorld() -- event off: the authored decorations are not part of the running game
	end

	task.spawn(function()
		local last = os.clock()
		local lastPush = 0
		local lastSchedule = 0
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			if active and #invaders > 0 then
				local ok, err = pcall(invaderStep, dt)
				if not ok then
					warn("[HalloweenService] invader step failed:", err)
				end
			end
			if now - lastSchedule >= 1 then
				lastSchedule = now
				local ok, err = pcall(schedulerStep)
				if not ok then
					warn("[HalloweenService] scheduler failed:", err)
				end
			end
			if active and now - lastPush >= 15 then
				lastPush = now
				pushAll()
			end
		end
	end)

	-- Studio only: trigger or end the event from the Command Bar for testing.
	if RunService:IsStudio() then
		local debugFolder = ServerStorage:FindFirstChild("RaiseAMonsterDebug") or folder("RaiseAMonsterDebug", ServerStorage)
		local function bind(name: string, callback: (...any) -> ())
			if debugFolder:FindFirstChild(name) then
				return
			end
			local event = Instance.new("BindableEvent")
			event.Name = name
			event.Event:Connect(callback)
			event.Parent = debugFolder
		end
		bind("HalloweenInvasion", function(count: number?) HalloweenService.StartInvasion(count) end)
		bind("HalloweenPumpkins", function() HalloweenService.StartPumpkinHunt() end)
		bind("HalloweenToggle", function()
			settings.Enabled = not settings.Enabled
			print("[HalloweenService] Config.Halloween.Enabled =", settings.Enabled)
		end)
		bind("HalloweenCandy", function(amount: number?)
			local first = Players:GetPlayers()[1]
			if first then HalloweenService.AddCandy(first, amount or 1000) end
		end)
	end
end

return HalloweenService
