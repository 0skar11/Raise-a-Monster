--!strict
-- Halloween 2026 event (everything is gated by Config.Halloween.Enabled / EndsAt):
--  * Mother Invasion every hour: a random wave of the game's Mother monsters walks into the plaza.
--    Damage is tracked per player on the server; everyone who dealt >= 5% of a Mother's HP gets Candy
--    (level x 5) when she dies. No stealing, nothing to carry.
--  * Pumpkin Hunt every 30 minutes: 5 pumpkins (sometimes a golden one) hidden in the plaza for 2 minutes.
--  * Candy is persisted in DataService; when the event ends it is converted to coins.
--  * Pumpkin Merchant NPC + shop (server authoritative), spooky atmosphere and props.
-- Rules that don't need Roblox live in ReplicatedStorage.Shared.HalloweenLogic (and are unit tested).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HalloweenLogic = require(ReplicatedStorage.Shared.HalloweenLogic)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local PlotService = require(script.Parent.PlotService)
local Build = require(script.Parent.Build)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local MonsterAttack = require(script.Parent.MonsterAttack)
local MonsterModels = require(script.Parent.MonsterModels)

local settings = Config.Halloween
local invasionSettings = settings.Invasion
local pumpkinSettings = settings.Pumpkins
local makePart = Build.MakePart

type Invader = {
	Level: number,
	Species: string,
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
local merchantRoot: BasePart? = nil
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
		local hatColor = settings.Items[equipped.Hat].Color
		local hat = makePart({ Name = "PumpkinHat", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.4, 1.7), Color = hatColor, Material = Enum.Material.SmoothPlastic, Anchored = false, Parent = container })
		hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.45, 0)
		local stem = makePart({ Name = "PumpkinStem", Size = Vector3.new(0.3, 0.5, 0.3), Color = Color3.fromRGB(70, 110, 40), Material = Enum.Material.Wood, Anchored = false, Parent = container })
		stem.CFrame = hat.CFrame * CFrame.new(0, 0.85, 0)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = 10
		light.Brightness = 1
		light.Shadows = false
		light.Parent = hat
		weldTo(hat, head)
		weldTo(stem, head)
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
			trail.Color = ColorSequence.new(settings.Items[equipped.Trail].Color, Color3.fromRGB(150, 120, 255))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
			trail.Parent = anchor
		end
		if equipped.Aura and data.Owned[equipped.Aura] then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "CandyAura"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(settings.Items[equipped.Aura].Color, Color3.fromRGB(255, 220, 90))
			emitter.LightEmission = 0.7
			emitter.Rate = 18
			emitter.Lifetime = NumberRange.new(1, 1.8)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			emitter.Shape = Enum.ParticleEmitterShape.Sphere
			emitter.Parent = anchor
		end
	end

	if equipped.Title and data.Owned[equipped.Title] then
		local item = settings.Items[equipped.Title]
		local gui = Instance.new("BillboardGui")
		gui.Name = "HalloweenTitle"
		gui.Size = UDim2.fromOffset(190, 28)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)
		gui.MaxDistance = 70
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.Adornee = head
		gui.Parent = container
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "🎃 " .. (item.TitleText or item.Name)
		label.TextColor3 = item.Color
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
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

local function applyAtmosphere()
	if snapshot then
		return
	end
	local a = settings.Atmosphere
	local saved: AtmosphereSnapshot = { Lighting = {}, Created = {} }
	for _, prop in LIGHTING_PROPS do
		saved.Lighting[prop] = (Lighting :: any)[prop]
	end
	snapshot = saved
	Lighting.ClockTime = a.ClockTime
	Lighting.Brightness = a.Brightness
	Lighting.Ambient = a.Ambient
	Lighting.OutdoorAmbient = a.OutdoorAmbient
	Lighting.FogColor = a.FogColor
	Lighting.FogStart = a.FogStart
	Lighting.FogEnd = a.FogEnd

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local props = {}
		for _, prop in ATMOSPHERE_PROPS do props[prop] = (atmosphere :: any)[prop] end
		saved.Atmosphere, saved.AtmosphereProps = atmosphere, props
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "HalloweenAtmosphere"
		atmosphere.Parent = Lighting
		table.insert(saved.Created, atmosphere)
	end
	local atmo = atmosphere :: Atmosphere
	atmo.Density = a.AtmosphereDensity
	atmo.Offset = a.AtmosphereOffset
	atmo.Color = a.AtmosphereColor
	atmo.Decay = a.AtmosphereDecay
	atmo.Haze = a.Haze

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		saved.Sky, saved.SkyProps = sky, { StarCount = sky.StarCount, CelestialBodiesShown = sky.CelestialBodiesShown }
	else
		sky = Instance.new("Sky")
		sky.Name = "HalloweenSky"
		sky.Parent = Lighting
		table.insert(saved.Created, sky)
	end
	local skyInstance = sky :: Sky
	skyInstance.StarCount = a.StarCount
	skyInstance.CelestialBodiesShown = true

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "HalloweenColor"
	color.TintColor = a.TintColor
	color.Saturation = a.Saturation
	color.Contrast = a.Contrast
	color.Parent = Lighting
	table.insert(saved.Created, color)
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HalloweenBloom"
	bloom.Intensity = a.BloomIntensity
	bloom.Threshold = a.BloomThreshold
	bloom.Size = 24
	bloom.Parent = Lighting
	table.insert(saved.Created, bloom)
end

local function restoreAtmosphere()
	local saved = snapshot
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
	for _, created in saved.Created do
		created:Destroy()
	end
end

-- props -----------------------------------------------------------------------------------------------

local ORANGE = Color3.fromRGB(240, 120, 25)
local FACE = Color3.fromRGB(255, 225, 110)

local function jackOLantern(parent: Instance, position: Vector3, size: number, yaw: number, lit: boolean, tint: Color3?)
	local base = CFrame.new(position + Vector3.new(0, size * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
	local common = { CanCollide = false, CanQuery = false, CanTouch = false, Parent = parent }
	local function part(props: { [string]: any }): Part
		for key, value in common do props[key] = value end
		return makePart(props)
	end
	local body = part({ Name = "Pumpkin", Shape = Enum.PartType.Ball, Size = Vector3.new(size * 1.15, size, size * 1.15), CFrame = base, Color = tint or ORANGE, Material = Enum.Material.SmoothPlastic })
	part({ Name = "Stem", Size = Vector3.new(size * 0.2, size * 0.3, size * 0.2), CFrame = base * CFrame.new(0, size * 0.55, 0), Color = Color3.fromRGB(70, 105, 40), Material = Enum.Material.Wood })
	if lit then
		for _, side in { -1, 1 } do
			part({ Name = "Eye", Size = Vector3.new(size * 0.17, size * 0.2, size * 0.06), CFrame = base * CFrame.new(side * size * 0.22, size * 0.1, -size * 0.56), Color = FACE, Material = Enum.Material.Neon })
		end
		part({ Name = "Mouth", Size = Vector3.new(size * 0.52, size * 0.12, size * 0.06), CFrame = base * CFrame.new(0, -size * 0.2, -size * 0.57), Color = FACE, Material = Enum.Material.Neon })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = settings.Atmosphere.LanternRange
		light.Brightness = 1.3
		light.Shadows = false
		light.Parent = body
	end
end

local function deadTree(parent: Instance, position: Vector3, height: number, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local wood = Color3.fromRGB(46, 34, 40)
	local common = { CanCollide = false, CanQuery = false, CanTouch = false, Color = wood, Material = Enum.Material.Wood, Parent = parent }
	local function part(props: { [string]: any }): Part
		for key, value in common do props[key] = value end
		return makePart(props)
	end
	part({ Name = "DeadTrunk", Size = Vector3.new(1.4, height, 1.4), CFrame = base * CFrame.new(0, height / 2, 0) })
	for index, side in { -1, 1, -1 } do
		part({
			Name = "DeadBranch",
			Size = Vector3.new(0.7, height * 0.5, 0.7),
			CFrame = base * CFrame.new(side * height * 0.18, height * (0.55 + 0.12 * index), 0) * CFrame.Angles(0, index, side * math.rad(40)),
		})
	end
end

local function tombstone(parent: Instance, position: Vector3, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local stone = Color3.fromRGB(110, 110, 120)
	makePart({ Name = "Tombstone", Size = Vector3.new(3, 3.4, 0.9), CFrame = base * CFrame.new(0, 1.7, 0), CanCollide = false, CanQuery = false, CanTouch = false, Color = stone, Material = Enum.Material.Slate, Parent = parent })
	makePart({
		Name = "TombstoneTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 3, 3),
		CFrame = base * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, math.pi / 2, 0),
		CanCollide = false, CanQuery = false, CanTouch = false, Color = stone, Material = Enum.Material.Slate, Parent = parent,
	})
end

local function clearOf(x: number, z: number, margin: number): boolean
	for _, zone in pumpkinSettings.KeepClear do
		if math.sqrt((zone.X - x) ^ 2 + (zone.Z - z) ^ 2) < zone.Radius + margin then
			return false
		end
	end
	return true
end

local function buildProps()
	if propFolder then
		return
	end
	local parent = folder("Props", rootFolder :: Folder)
	propFolder = parent
	local a = settings.Atmosphere
	local random = Random.new(a.Seed)
	local placed, attempts = 0, 0
	while placed < a.PumpkinPropCount and attempts < a.PumpkinPropCount * 12 do
		attempts += 1
		local x = random:NextNumber(Config.Map.PlazaMinX + 2, Config.Map.ZonesStartX - 6)
		local z = random:NextNumber(-Config.Map.PlazaHalfZ + 14, Config.Map.PlazaHalfZ - 14)
		-- keep the path in front of the zone gate and the shop area open
		if clearOf(x, z, 4) then
			placed += 1
			local pos = Vector3.new(x, 0.2, z)
			local yaw = random:NextNumber(0, math.pi * 2)
			local kind = placed % 6
			if kind == 0 then
				deadTree(parent, pos, random:NextNumber(8, 13), yaw)
			elseif kind == 1 then
				tombstone(parent, pos, yaw)
			elseif kind == 2 or kind == 3 then
				jackOLantern(parent, pos, random:NextNumber(2.4, 3.6), yaw, true)
			else
				-- a small pile: one lit jack and two plain pumpkins
				jackOLantern(parent, pos, 3, yaw, true)
				jackOLantern(parent, pos + Vector3.new(2.6, 0, 1.2), 2, yaw + 1, false)
				jackOLantern(parent, pos + Vector3.new(-2.2, 0, 1.8), 1.7, yaw + 2, false, Color3.fromRGB(225, 95, 20))
			end
		end
	end
	-- a lantern on each side of every zone gate road
	for index = 1, #Config.Zones do
		local gateX = Config.Map.ZonesStartX + (index - 1) * Config.Map.ZoneLength
		for _, side in { -1, 1 } do
			jackOLantern(parent, Vector3.new(gateX + 4, 0.2, side * (Config.Map.RoadWidth / 2 + 7)), 3.6, if side < 0 then math.pi / 2 else -math.pi / 2, true)
		end
	end
	-- drifting embers and wisps over the whole plaza
	local centers = {}
	for z = -200, 200, 100 do
		table.insert(centers, Vector3.new((Config.Map.PlazaMinX + Config.Map.ZonesStartX) / 2, 14, z))
	end
	for _, center in centers do
		local emitterPart = makePart({
			Name = "AmbientEmitter", Size = Vector3.new(100, 8, 90), Position = center, Transparency = 1,
			CanCollide = false, CanQuery = false, CanTouch = false, Parent = parent,
		})
		for _, spec in {
			{ Color = Color3.fromRGB(255, 140, 40), Rate = 6, Speed = 1.5 },
			{ Color = Color3.fromRGB(170, 120, 255), Rate = 4, Speed = 0.8 },
		} do
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Wisps"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(spec.Color)
			emitter.LightEmission = 0.8
			emitter.Rate = spec.Rate
			emitter.Lifetime = NumberRange.new(7, 12)
			emitter.Speed = NumberRange.new(spec.Speed * 0.5, spec.Speed)
			emitter.Acceleration = Vector3.new(0, 0.4, 0)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.7), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) })
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.Parent = emitterPart
		end
	end
end

-- merchant --------------------------------------------------------------------------------------------

local function openShopFor(player: Player)
	local root = rootOf(player)
	local merchant = merchantRoot
	if not active or not root or not merchant or not isAlive(player) then
		return
	end
	if (root.Position - merchant.Position).Magnitude > settings.Merchant.ShopDistance then
		return
	end
	pushState(player)
	remotes.HalloweenOpenShop:FireClient(player)
end

local function buildMerchant()
	if merchantRoot then
		return
	end
	local info = settings.Merchant
	local model = Instance.new("Model")
	model.Name = "PumpkinMerchant"
	local origin = CFrame.lookAt(info.Position + Vector3.new(0, 0.2, 0), Vector3.new(info.FaceTowards.X, info.Position.Y + 0.2, info.FaceTowards.Z))
	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		return makePart({
			Name = name, Size = size, CFrame = origin * CFrame.new(offset), Color = color,
			Material = material or Enum.Material.Fabric, Shape = shape or Enum.PartType.Block,
			CanCollide = false, CanQuery = true, CanTouch = false, Parent = model,
		})
	end
	local robe = Color3.fromRGB(58, 30, 84)
	limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), robe)
	limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), robe)
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), robe)
	limb("RobeHem", Vector3.new(2.6, 1.6, 1.5), Vector3.new(0, 1.4, 0), Color3.fromRGB(45, 22, 66))
	limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, -0.3), Color3.fromRGB(70, 38, 100))
	limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, -0.3), Color3.fromRGB(70, 38, 100))
	local head = limb("Head", Vector3.new(2.5, 2.2, 2.5), Vector3.new(0, 5.2, 0), ORANGE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	limb("Stem", Vector3.new(0.4, 0.7, 0.4), Vector3.new(0, 6.5, 0), Color3.fromRGB(70, 105, 40), Enum.Material.Wood)
	for _, side in { -1, 1 } do
		limb("Eye", Vector3.new(0.45, 0.5, 0.2), Vector3.new(side * 0.55, 5.4, -1.15), FACE, Enum.Material.Neon)
	end
	limb("Mouth", Vector3.new(1.3, 0.3, 0.2), Vector3.new(0, 4.7, -1.2), FACE, Enum.Material.Neon)
	local brim = limb("HatBrim", Vector3.new(0.25, 3.4, 3.4), Vector3.new(0, 6.15, 0), Color3.fromRGB(30, 20, 40), Enum.Material.Fabric, Enum.PartType.Cylinder)
	brim.CFrame = origin * CFrame.new(0, 6.15, 0) * CFrame.Angles(0, 0, math.pi / 2)
	limb("HatCone", Vector3.new(2, 1.9, 2), Vector3.new(0, 7.15, 0), Color3.fromRGB(30, 20, 40))
	local lantern = limb("Lantern", Vector3.new(0.9, 1.1, 0.9), Vector3.new(2.1, 2.2, -0.9), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 22
	glow.Brightness = 1.6
	glow.Parent = lantern
	-- a counter piled with pumpkins in front of him
	limb("Counter", Vector3.new(7, 3, 2.4), Vector3.new(0, 1.5, -3.2), Color3.fromRGB(80, 50, 32), Enum.Material.Wood)
	jackOLantern(model, (origin * CFrame.new(-2, 3, -3.2)).Position, 1.8, 0.3, true)
	jackOLantern(model, (origin * CFrame.new(2.2, 3, -3.2)).Position, 1.5, -0.4, false)

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = ""
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = torso
	model.Parent = rootFolder

	local gui, label = Build.MakeBillboard(head, UDim2.fromOffset(240, 60), Vector3.new(0, 4.5, 0), 90)
	gui.AlwaysOnTop = false
	label.Text = '<font color="#FFA030">' .. info.Name .. '</font>\n🎃 Trade your Candy!'
	local prompt = Build.MakePrompt(torso, "MerchantPrompt", "Open Shop", Enum.KeyCode.E, 0)
	prompt.ObjectText = info.Name
	prompt.MaxActivationDistance = info.PromptDistance
	prompt.Triggered:Connect(openShopFor)
	merchantRoot = torso
end

-- Mother Invasion -------------------------------------------------------------------------------------

local function speciesWeights(): { [string]: number }
	local weights: { [string]: number } = {}
	for key, species in Config.Species do
		if species.Model then
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
end

local function settleInvader(invader: Invader, killerName: string)
	if not invader.Alive then
		return
	end
	local rewards = HalloweenLogic.Settle(invader.Tracker, invasionSettings, invader.Level)
	removeInvader(invader)
	local name = Config.Species[invader.Species].DisplayName
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
		pushAll()
	end
end

local function spawnInvader(position: Vector3, level: number, species: string): Invader?
	local info = Config.Species[species].Model
	local template = info and MonsterModels.Get(info.Region, info.Index, "Adult")
	if not info or not template or not invaderFolder then
		return nil
	end
	local model: Model = template
	model:ScaleTo(Config.MotherScale)
	local pivotHeight = (model:GetAttribute("Scale") or 1) * Config.MotherScale
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
	local element = Config.RegionMonsters[info.Region].Region
	local maxHealth = HalloweenLogic.HealthForLevel(invasionSettings, level)

	local gui, label = Build.MakeBillboard(root, UDim2.fromScale(16, 5.5), Vector3.new(0, height + 4, 0), 140)
	gui.Name = "Info"
	gui.AlwaysOnTop = false
	label.Size = UDim2.fromScale(1, 0.6)
	label.Text = string.format(
		'<font color="#FFA030">🎃 %s</font> · Lv %d MOTHER\n<font color="%s">%s</font>',
		Config.Species[species].DisplayName,
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

	local invader: Invader = {
		Level = level,
		Species = species,
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
	for _, spot in pickInvasionSpots(count) do
		local species = HalloweenLogic.WeightedPick(weights, rng:NextNumber()) :: string?
		local level = rng:NextInteger(invasionSettings.MinLevel, invasionSettings.MaxLevel)
		if species and spawnInvader(spot, level, species) then
			spawned += 1
		end
	end
	if spawned > 0 then
		announce(string.format("👹 MOTHER INVASION! %d Mother monsters are attacking the plaza! Defeat them for Candy!", spawned), Color3.fromRGB(255, 110, 40))
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
			if left > 0 then
				announce("The Mothers retreated into the fog... see you next hour!", Color3.fromRGB(200, 200, 200))
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
			-- never leave the plaza, never walk into a base
			position = Vector3.new(
				math.clamp(position.X, area.MinX - 6, area.MaxX + 6),
				pivot.Position.Y,
				math.clamp(position.Z, -area.HalfZ - 10, area.HalfZ + 10)
			)
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

local function pickPumpkinSpots(count: number): { Vector3 }
	local area = pumpkinSettings.Area
	local spots: { Vector3 } = {}
	local attempts = 0
	while #spots < count and attempts < 600 do
		attempts += 1
		local relax = if attempts > 400 then 0.4 else 1
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
	return spots
end

local function endHunt(current: Hunt, message: string?)
	if hunt ~= current then
		return
	end
	hunt = nil
	for _, pumpkin in current.Pumpkins do
		pumpkin.Claimed = true
		if pumpkin.Part.Parent then
			pumpkin.Part:Destroy()
		end
	end
	if message then
		announce(message, Color3.fromRGB(255, 170, 60))
	end
	for _, player in Players:GetPlayers() do
		remotes.HalloweenHint:FireClient(player, nil)
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
		endHunt(current, "🎃 All the pumpkins have been found! See you in half an hour.")
	else
		pushAll()
	end
end

local function makePumpkinModel(position: Vector3, golden: boolean): Part
	local size = if golden then 3.6 else 3
	local color = if golden then Color3.fromRGB(255, 205, 50) else ORANGE
	local body = makePart({
		Name = if golden then "GoldenPumpkin" else "HuntPumpkin", Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 1.15, size, size * 1.15), Position = position + Vector3.new(0, size / 2, 0),
		Color = color, Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		CanCollide = false, CanQuery = true, CanTouch = false, Parent = pumpkinFolder,
	})
	local stem = makePart({
		Name = "Stem", Size = Vector3.new(0.6, 0.9, 0.6), Position = position + Vector3.new(0, size + 0.15, 0),
		Color = Color3.fromRGB(70, 105, 40), Material = Enum.Material.Wood, CanCollide = false, CanQuery = false, CanTouch = false, Parent = body,
	})
	stem.Anchored = true
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
	if rng:NextNumber() < pumpkinSettings.GoldenChance then
		goldenIndex = rng:NextInteger(1, pumpkinSettings.Count)
	end
	for index, spot in pickPumpkinSpots(pumpkinSettings.Count) do
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
	announce(string.format("🎃 PUMPKIN HUNT! %d pumpkins are hiding in the plaza for %d minutes. Follow the hints!", current.Remaining, math.floor(pumpkinSettings.Lifetime / 60)), Color3.fromRGB(255, 150, 40))
	pushAll()
	task.delay(pumpkinSettings.Lifetime, function()
		if hunt == current then
			endHunt(current, "The pumpkins rotted away... next hunt in 30 minutes!")
		end
	end)
	return current.Remaining
end

-- Soft hint: a coarse compass sector and distance band for the nearest pumpkin. Never a position.
local function sendHints(current: Hunt)
	local spots = {}
	for _, pumpkin in current.Pumpkins do
		if not pumpkin.Claimed and pumpkin.Part.Parent then
			table.insert(spots, { X = pumpkin.Part.Position.X, Z = pumpkin.Part.Position.Z })
		end
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local sector, band = HalloweenLogic.Hint(root.Position.X, root.Position.Z, spots, pumpkinSettings.HintBands)
			if sector and band then
				remotes.HalloweenHint:FireClient(player, { Sector = sector, Band = band, Remaining = current.Remaining, EndsIn = math.max(0, math.ceil(current.EndsAt - os.clock())) })
			end
		end
	end
end

-- shop ------------------------------------------------------------------------------------------------

local function nearMerchant(player: Player): boolean
	local root = rootOf(player)
	local merchant = merchantRoot
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
	BoostCap = "You already have the maximum Candy Boost time stored.",
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
			notify(player, "🍬 Candy Boost active: 2x cash!", "success")
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
	applyAtmosphere()
	buildProps()
	buildMerchant()
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
	restoreAtmosphere()
	if rootFolder then
		rootFolder:Destroy()
	end
	rootFolder, invaderFolder, pumpkinFolder, propFolder, merchantRoot = nil, nil, nil, nil, nil
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
		announce(string.format("⚠️ Mother Invasion in %d seconds! Grab your weapons and get ready to defend the plaza!", math.max(1, nextInvasionAt - now)), Color3.fromRGB(255, 90, 60))
	end
	if now >= nextPumpkinAt then
		HalloweenService.StartPumpkinHunt()
		nextPumpkinAt = HalloweenLogic.NextOccurrence(now, pumpkinSettings.Interval, pumpkinSettings.Offset)
	end
	local current = hunt
	if current and os.clock() - current.LastHintAt >= pumpkinSettings.HintInterval then
		current.LastHintAt = os.clock()
		sendHints(current)
	end
end

function HalloweenService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	remotes.HalloweenBuy.OnServerEvent:Connect(onBuy)
	remotes.HalloweenEquip.OnServerEvent:Connect(onEquip)
	remotes.HalloweenSync.OnServerEvent:Connect(onSync)

	if wantActive() then
		HalloweenService.Start()
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
