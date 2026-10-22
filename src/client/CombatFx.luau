--!strict
-- مؤثرات القتال على الكلاينت: علامة ضربة الوحش على الأرض، القذيفة، الانفجار،
-- أرقام الضرر، هزة الكاميرا لما تتضرب، والموسيقى بزرار Mute.
-- الضرر نفسه بيتحسب في السيرفر (MonsterAttack)، هنا شكل بس.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local CombatFx = {}

local player = Players.LocalPlayer
local settings = Config.MotherAttacks
local lastCombat = 0

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "CombatFx"
fxFolder.Parent = workspace

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function fxPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = fxFolder
	return part
end

local function playSound(id: string, position: Vector3, volume: number, speed: number)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = position, Transparency = 1 })
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMaxDistance = 180
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 3)
end

-- الأرض تحت النقطة دي (عشان العلامة تبقى لازقة في الأرض)
local function groundY(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include: { Instance } = { workspace.Terrain }
	local zones = workspace:FindFirstChild("Zones")
	if zones then
		table.insert(include, zones)
	end
	params.FilterDescendantsInstances = include
	local result = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), params)
	return if result then result.Position.Y else 0
end

local function circleCFrame(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

local function burst(position: Vector3, color: Color3, secondary: Color3, element: string, amount: number, size: number)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = position, Transparency = 1 })
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(color, secondary)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Speed = NumberRange.new(size * 4, size * 8)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Rate = 0
	sparks.Parent = attachment
	sparks:Emit(amount)

	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = if element == "Fire" then FIRE else SMOKE
	cloud.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25))
	cloud.LightEmission = if element == "Fire" or element == "Void" then 0.8 else 0.2
	cloud.Transparency = NumberSequence.new(0.2, 1)
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 1.2), NumberSequenceKeypoint.new(1, size * 2.5) })
	cloud.Speed = NumberRange.new(size * 1.5, size * 3)
	cloud.Lifetime = NumberRange.new(0.5, 0.9)
	cloud.SpreadAngle = Vector2.new(180, 30)
	cloud.Rate = 0
	cloud.Parent = attachment
	cloud:Emit(math.floor(amount / 2))

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 6
	light.Brightness = 4
	light.Parent = holder
	tween(light, 0.5, { Brightness = 0 })
	Debris:AddItem(holder, 1.5)
end

-- موجة دايرية بتكبر وتختفي
local function shockwave(center: Vector3, radius: number, color: Color3)
	local ring = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = circleCFrame(center + Vector3.new(0, 0.2, 0)),
		Color = color,
		Transparency = 0.2,
	})
	tween(ring, 0.35, { Size = Vector3.new(0.3, radius * 2.2, radius * 2.2), Transparency = 1 })
	Debris:AddItem(ring, 0.5)
end

-- القذيفة بتطير في قوس وبتوصل مع آخر الـ Windup
local function projectile(from: Vector3, to: Vector3, color: Color3, secondary: Color3, windup: number)
	local ball = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Position = from, Color = color })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color, secondary)
	trail.LightEmission = 1
	trail.Lifetime = 0.3
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = ball
	local flight = math.min(windup * 0.7, 0.6)
	local launchAt = os.clock() + (windup - flight)
	local height = math.max(6, (to - from).Magnitude * 0.35)
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now < launchAt then
			return
		end
		local u = math.clamp((now - launchAt) / flight, 0, 1)
		ball.Position = from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * height, 0)
		if u >= 1 then
			connection:Disconnect()
			ball:Destroy()
		end
	end)
	Debris:AddItem(ball, windup + 1)
end

local function coneBlast(origin: Vector3, direction: Vector3, range: number, angle: number, color: Color3, secondary: Color3, element: string)
	local holder = fxPart({ Size = Vector3.one * 0.2, CFrame = CFrame.lookAt(origin, origin + direction), Transparency = 1 })
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if element == "Fire" then FIRE elseif element == "Sand" then SMOKE else SPARKLE
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Color = ColorSequence.new(color, secondary)
	emitter.LightEmission = if element == "Sand" then 0.2 else 0.9
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	emitter.Speed = NumberRange.new(range * 2.2, range * 2.8)
	emitter.Lifetime = NumberRange.new(0.35, 0.45)
	emitter.SpreadAngle = Vector2.new(angle / 2, 8)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(60)
	Debris:AddItem(holder, 1.2)
end

local function shakeCamera(strength: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local endAt = os.clock() + duration
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local left = endAt - os.clock()
		if left <= 0 or humanoid.Parent == nil then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local s = strength * (left / duration)
		humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end)
end

local function onMonsterAttack(data: any)
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - data.Center).Magnitude > settings.FxDistance then
		return
	end
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local nearMe = myRoot ~= nil and (myRoot.Position - data.Center).Magnitude < data.Radius + data.Range + 20
	if nearMe then
		lastCombat = os.clock()
	end

	local floor = groundY(data.Center)
	local center = Vector3.new(data.Center.X, floor, data.Center.Z)
	local origin = Vector3.new(data.Origin.X, groundY(data.Origin) + 0.1, data.Origin.Z)
	if data.Shape == "Lob" then
		projectile(data.Origin + Vector3.new(0, 3, 0), center + Vector3.new(0, 1, 0), data.Color, data.Secondary, data.Windup)
	end
	playSound(settings.Sounds.Windup, data.Origin, 0.5, 0.8)

	task.delay(data.Windup, function()
		-- الوحش مات قبل ما يضرب؟ يبقى مفيش ضربة
		if data.Model ~= nil and data.Model.Parent == nil then
			return
		end
		if data.Shape == "Cone" then
			coneBlast(origin + Vector3.new(0, 2, 0), data.Direction, data.Range, data.Angle, data.Color, data.Secondary, data.Element)
			burst(origin + data.Direction * (data.Range * 0.6) + Vector3.new(0, 1, 0), data.Color, data.Secondary, data.Element, 14, 1.5)
		else
			shockwave(center, data.Radius, data.Color)
			burst(center + Vector3.new(0, 1, 0), data.Color, data.Secondary, data.Element, 30, math.clamp(data.Radius / 6, 1, 3))
		end
		playSound(settings.Sounds.Impact, center, 0.9, 0.65)
		if nearMe then
			shakeCamera(0.35, 0.2)
		end
	end)
end

-- أرقام الضرر -------------------------------------------------------------------

local function floatingText(position: Vector3, text: string, color: Color3, scale: number)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = position + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2), Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.3
	uiScale.Parent = label
	tween(uiScale, 0.18, { Scale = scale }, Enum.EasingStyle.Back)
	tween(holder, 0.8, { Position = holder.Position + Vector3.new(0, 4, 0) })
	task.delay(0.45, function()
		tween(label, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(holder, 0.9)
end

local function onHitFeedback(position: Vector3, damage: number, crit: boolean)
	lastCombat = os.clock()
	if crit then
		floatingText(position, "CRIT! " .. damage, Color3.fromRGB(255, 190, 40), 1.35)
		shakeCamera(0.25, 0.12)
	else
		floatingText(position, tostring(damage), Color3.new(1, 1, 1), 1)
	end
end

local function onPlayerHurt(flash: Frame, damage: number, color: Color3)
	lastCombat = os.clock()
	flash.BackgroundColor3 = Color3.fromRGB(255, 40, 40):Lerp(color, 0.3)
	flash.BackgroundTransparency = 0.7
	tween(flash, 0.4, { BackgroundTransparency = 1 })
	shakeCamera(0.6, 0.25)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		floatingText(root.Position + Vector3.new(0, 3.5, 0), "-" .. damage, Color3.fromRGB(255, 80, 80), 0.9)
	end
end

-- الموسيقى ---------------------------------------------------------------------

local function startMusic(ui: any, button: (any, string, Color3, UDim2, UDim2) -> TextButton)
	local music = Instance.new("Sound")
	music.Name = "BackgroundMusic"
	music:SetAttribute("RaiseAMonsterMusic", true)
	music.SoundId = Config.Music.SoundId
	music.Looped = true
	music.Volume = Config.Music.Volume
	music.Parent = SoundService
	music:Play()

	-- التحكم في الصوت بقى من Settings، من غير زر بيغطي زر Trade.

	-- بتوطى وقت القتال وبترجع بالراحة بعده
	task.spawn(function()
		while true do
			task.wait(0.25)
			local target = if os.clock() - lastCombat < 4 then Config.Music.CombatVolume else Config.Music.Volume
			music.Volume += (target - music.Volume) * 0.25
		end
	end)
end

function CombatFx.Start(ui: any, remotes: { [string]: RemoteEvent }, button: (any, string, Color3, UDim2, UDim2) -> TextButton)
	local flash = Instance.new("Frame")
	flash.Name = "HurtFlash"
	flash.Position = UDim2.fromOffset(0, -60)
	flash.Size = UDim2.new(1, 0, 1, 60)
	flash.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.ZIndex = 0
	flash.Parent = ui.Gui

	remotes.MonsterAttack.OnClientEvent:Connect(onMonsterAttack)
	remotes.HitFeedback.OnClientEvent:Connect(onHitFeedback)
	remotes.PlayerHurt.OnClientEvent:Connect(function(damage: number, color: Color3)
		onPlayerHurt(flash, damage, color)
	end)
	startMusic(ui, button)
end

return CombatFx
