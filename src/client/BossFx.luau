--!strict
-- Big Boss visuals: telegraphs on the ground, strikes, shockwaves, bombs, vines, the heart pulse, the rain and the rage.
-- The server (BossAttacks) decides damage and timing; this module only draws, using the exact numbers it was sent, so
-- every red zone you see is the zone that really hurts.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local PumpkinVisual = require(ReplicatedStorage.Shared.PumpkinVisual)

local BossFx = {}

local player = Players.LocalPlayer
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local WINDUP_SOUND = Config.Boss.Audio.Windup
local IMPACT_SOUND = Config.Boss.Audio.Impact
local GROWL_SOUND = Config.Boss.Audio.Growl

local RED = Color3.fromRGB(255, 62, 38)
local ORANGE = Color3.fromRGB(255, 130, 30)
local AMBER = Color3.fromRGB(255, 190, 70)
local GREEN = Color3.fromRGB(110, 230, 80)
local GOLD = Color3.fromRGB(255, 215, 90)
local DARK = Color3.fromRGB(60, 36, 28)

local fxFolder = Instance.new("Folder")
fxFolder.Name = "BossFx"
fxFolder.Parent = workspace

local gui: ScreenGui? = nil
local flashFrame: Frame? = nil
local bannerLabel: TextLabel? = nil

-- helpers --------------------------------------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function fxPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = fxFolder
	return part
end

local function wedgePart(parent: Instance, color: Color3, transparency: number): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanQuery = false
	wedge.CanTouch = false
	wedge.CastShadow = false
	wedge.Material = Enum.Material.Neon
	wedge.Color = color
	wedge.Transparency = transparency
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Size = Vector3.new(0.05, 0.05, 0.05)
	wedge.Parent = parent
	return wedge
end

-- A flat/3D triangle built from two wedges (a, b, c are world points); updates the given wedge pair in place.
local function triangle(a: Vector3, b: Vector3, c: Vector3, w1: WedgePart, w2: WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		w1.Size = Vector3.new(0.05, 0.05, 0.05)
		w2.Size = Vector3.new(0.05, 0.05, 0.05)
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(0.05, math.max(height, 0.05), math.max(math.abs(ab:Dot(back)), 0.05))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.05, math.max(height, 0.05), math.max(math.abs(ac:Dot(back)), 0.05))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function playSound(id: string, position: Vector3, volume: number, speed: number)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = position, Transparency = 1 })
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMaxDistance = 260
	sound.Parent = holder
	sound:Play()
	if id == IMPACT_SOUND then
		-- every hit also carries a deep groan, so it reads as the Titan and not as a plain explosion
		local growl = Instance.new("Sound")
		growl.SoundId = GROWL_SOUND
		growl.Volume = math.min(volume * 0.6, 1)
		growl.PlaybackSpeed = math.clamp(speed * 0.55, 0.22, 0.5)
		growl.RollOffMaxDistance = 260
		growl.Parent = holder
		growl:Play()
	end
	Debris:AddItem(holder, 4)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function groundY(position: Vector3): number
	local include: { Instance } = { workspace.Terrain }
	local zones = workspace:FindFirstChild("Zones")
	if zones then
		table.insert(include, zones)
	end
	rayParams.FilterDescendantsInstances = include
	local result = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -120, 0), rayParams)
	return if result then result.Position.Y else position.Y
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- camera shake (one shared loop, stronger when you are close) ------------------------------------------------------
local shakeStrength = 0
local shakeEndsAt = 0
local shakeDuration = 1
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local left = shakeEndsAt - os.clock()
	if left <= 0 then
		if shakeStrength > 0 then
			shakeStrength = 0
			humanoid.CameraOffset = Vector3.zero
		end
		return
	end
	local s = shakeStrength * (left / shakeDuration)
	humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
end)

local function shake(strength: number, duration: number, at: Vector3?)
	local scaled = strength
	if at then
		local root = localRoot()
		if root then
			local distance = (root.Position - at).Magnitude
			scaled = strength * math.clamp(1.15 - distance / 170, 0.12, 1)
		end
	end
	if scaled >= shakeStrength * (math.max(0, shakeEndsAt - os.clock()) / shakeDuration) then
		shakeStrength = scaled
		shakeDuration = duration
		shakeEndsAt = os.clock() + duration
	end
end

local function flash(color: Color3, transparency: number, seconds: number)
	local frame = flashFrame
	if not frame then
		return
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	tween(frame, seconds, { BackgroundTransparency = 1 })
end

local function banner(text: string, color: Color3, seconds: number)
	local label = bannerLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.25
	local scale = label:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	task.delay(seconds, function()
		if label.Text == text then
			tween(label, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

-- shapes ------------------------------------------------------------------------------------------------------------

local function disc(center: Vector3, radius: number, color: Color3, transparency: number): Part
	return fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, math.max(radius * 2, 0.1), math.max(radius * 2, 0.1)),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency,
	})
end

-- A ring of short blocks (outline of a circle).
local function ringOutline(center: Vector3, radius: number, color: Color3, transparency: number, width: number, height: number): { Part }
	local segments = math.clamp(math.floor(radius * 1.4), 24, 72)
	local parts: { Part } = {}
	for index = 1, segments do
		local angle = (index - 0.5) / segments * math.tau
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		table.insert(parts, fxPart({
			Size = Vector3.new(width, height, radius * math.tau / segments * 1.12),
			CFrame = CFrame.lookAt(position, position + tangent),
			Color = color,
			Transparency = transparency,
		}))
	end
	return parts
end

-- An expanding shock ring (a wall of blocks that travels outward and fades).
local function waveRing(center: Vector3, r0: number, r1: number, seconds: number, color: Color3, height: number, thickness: number)
	local segments = math.clamp(math.floor(r1 * 0.9), 28, 80)
	local blocks: { Part } = {}
	for _ = 1, segments do
		table.insert(blocks, fxPart({ Color = color, Transparency = 0.1, Size = Vector3.new(thickness, height, 1) }))
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - started) / seconds, 0, 1)
		local eased = 1 - (1 - u) ^ 2
		local radius = r0 + (r1 - r0) * eased
		local chord = radius * math.tau / segments * 1.15
		local tall = height * (1 - u * 0.6)
		for index, block in blocks do
			local angle = (index - 0.5) / segments * math.tau
			local position = center + Vector3.new(math.cos(angle) * radius, tall / 2, math.sin(angle) * radius)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			block.Size = Vector3.new(thickness, tall, chord)
			block.CFrame = CFrame.lookAt(position, position + tangent)
			block.Transparency = 0.1 + 0.9 * u * u
		end
		if u >= 1 then
			connection:Disconnect()
			for _, block in blocks do
				block:Destroy()
			end
		end
	end)
end

-- Jagged glowing cracks radiating from a point.
local function cracks(center: Vector3, count: number, length: number, color: Color3, lifetime: number)
	for index = 1, count do
		local angle = (index / count) * math.tau + (math.random() - 0.5) * 0.4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = center + Vector3.new(0, 0.18, 0)
		local segments = math.random(4, 7)
		for _ = 1, segments do
			local step = length / segments * (0.7 + math.random() * 0.6)
			local bend = direction:Cross(Vector3.yAxis) * (math.random() - 0.5) * 0.9
			local nextPosition = position + (direction + bend).Unit * step
			local piece = fxPart({
				Size = Vector3.new(0.45, 0.1, (nextPosition - position).Magnitude),
				CFrame = CFrame.lookAt((position + nextPosition) / 2, nextPosition),
				Color = color,
				Transparency = 0.05,
			})
			tween(piece, lifetime, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(piece, lifetime + 0.1)
			position = nextPosition
		end
	end
end

-- Rock chunks thrown up and landing again.
local function debris(center: Vector3, count: number, speed: number, colors: { Color3 })
	local pieces = {}
	for _ = 1, count do
		local angle = math.random() * math.tau
		local out = speed * (0.4 + math.random() * 0.8)
		local size = 0.5 + math.random() * 1.5
		table.insert(pieces, {
			Part = fxPart({
				Material = Enum.Material.Slate,
				Size = Vector3.new(size, size * (0.6 + math.random() * 0.6), size),
				Position = center + Vector3.new(0, 1, 0),
				Color = colors[math.random(1, #colors)],
				CFrame = CFrame.new(center + Vector3.new(0, 1, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			}),
			Velocity = Vector3.new(math.cos(angle) * out, speed * (0.7 + math.random() * 0.9), math.sin(angle) * out),
			Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8,
		})
	end
	local started = os.clock()
	local last = started
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		for _, piece in pieces do
			piece.Velocity += Vector3.new(0, -70 * dt, 0)
			local part = piece.Part
			part.CFrame = CFrame.new(part.Position + piece.Velocity * dt) * part.CFrame.Rotation * CFrame.Angles(piece.Spin.X * dt, piece.Spin.Y * dt, piece.Spin.Z * dt)
		end
		if now - started > 1.6 then
			connection:Disconnect()
			for _, piece in pieces do
				piece.Part:Destroy()
			end
		end
	end)
end

local function burst(position: Vector3, color: Color3, secondary: Color3, amount: number, size: number, fire: boolean?)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = position, Transparency = 1 })
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(color, secondary)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.55), NumberSequenceKeypoint.new(1, 0) })
	sparks.Speed = NumberRange.new(size * 6, size * 14)
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 0
	sparks.Parent = attachment
	sparks:Emit(amount)
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = if fire then FIRE else SMOKE
	cloud.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.2), secondary)
	cloud.LightEmission = if fire then 0.9 else 0.15
	cloud.Transparency = NumberSequence.new(0.1, 1)
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 1.3), NumberSequenceKeypoint.new(1, size * 3.2) })
	cloud.Speed = NumberRange.new(size * 2, size * 5)
	cloud.Lifetime = NumberRange.new(0.6, 1.2)
	cloud.SpreadAngle = Vector2.new(180, 60)
	cloud.Rate = 0
	cloud.Parent = attachment
	cloud:Emit(math.floor(amount / 2))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 10
	light.Brightness = 6
	light.Parent = holder
	tween(light, 0.6, { Brightness = 0 })
	Debris:AddItem(holder, 2)
end

local function fireball(position: Vector3, radius: number, color: Color3, seconds: number)
	local ball = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 0.4, Position = position, Color = color, Transparency = 0.1 })
	tween(ball, seconds, { Size = Vector3.one * radius * 2, Transparency = 1 })
	Debris:AddItem(ball, seconds + 0.1)
	local core = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 0.3, Position = position, Color = Color3.new(1, 0.95, 0.75), Transparency = 0 })
	tween(core, seconds * 0.7, { Size = Vector3.one * radius * 1.3, Transparency = 1 })
	Debris:AddItem(core, seconds)
end

local function carvedPumpkin(size: number, tint: Color3?): Part
	local body = fxPart({})
	PumpkinVisual.Apply(body, size, tint)
	local light = Instance.new("PointLight")
	light.Color = ORANGE
	light.Range = size * 6
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = body
	return body
end

-- A pumpkin bomb / falling pumpkin: the carved lantern with a fiery trail.
local function pumpkinProjectile(size: number): Part
	local body = carvedPumpkin(size)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.5, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.5, 0)
	a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(AMBER, RED)
	trail.LightEmission = 1
	trail.Lifetime = 0.4
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = body
	return body
end

-- Move a pumpkin along an arc from `from` to `to` between `startAt` and `endAt` (os.clock times).
local function flyArc(body: Part, from: Vector3, to: Vector3, startAt: number, endAt: number, height: number, onLand: (() -> ())?)
	body.Position = from
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now < startAt then
			return
		end
		local u = math.clamp((now - startAt) / math.max(endAt - startAt, 0.05), 0, 1)
		local position = from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * height, 0)
		body.CFrame = CFrame.new(position) * CFrame.Angles(u * 9, u * 5, 0)
		if u >= 1 then
			connection:Disconnect()
			body:Destroy()
			if onLand then
				onLand()
			end
		end
	end)
end

-- a ground marker: outline + filling disc that grows to the full zone exactly when the strike lands
local function growingZone(center: Vector3, radius: number, windup: number, color: Color3)
	local outline = ringOutline(center + Vector3.new(0, 0.22, 0), radius, color, 0.1, 0.55, 0.12)
	local floorDisc = disc(center + Vector3.new(0, 0.14, 0), radius, color, 0.82)
	local fill = disc(center + Vector3.new(0, 0.18, 0), 0.5, color, 0.55)
	tween(fill, windup, { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - started) / windup
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * (8 + u * 14))
		floorDisc.Transparency = 0.86 - 0.18 * pulse * (0.4 + u)
		for _, part in outline do
			part.Transparency = 0.25 - 0.2 * pulse
		end
		if u >= 1 then
			connection:Disconnect()
		end
	end)
	return function()
		connection:Disconnect()
		for _, part in outline do
			part:Destroy()
		end
		floorDisc:Destroy()
		fill:Destroy()
	end
end

-- Boss animation -----------------------------------------------------------------------------------------------------
-- The Titan's body is driven here, not by the generic Biped animator (the server sets Procedural = false on it), so every
-- pose is timed against the same numbers as the telegraph: the windup peak lands just before the strike.
-- Poses are rotations (radians) per joint plus an optional vertical offset: { rx, ry, rz, py }.
-- Arm rx > 0 swings the arm forward/up, rz > 0 swings the right arm outward (mirrored for the left), torso ry > 0 turns left.

type Pose = { [string]: { number } }

local JOINTS = { "LowerTorso", "UpperTorso", "Head", "ArmR", "ArmL", "ForearmR", "ForearmL", "LegR", "LegL" }
local animator: any = nil
local pendingAnim: { Name: string, Params: { [string]: any }?, At: number }? = nil -- an animation that arrived before the model streamed in
local throwCount = 0

local function lerpPose(a: Pose, b: Pose, u: number): Pose
	local result: Pose = {}
	for _, joint in JOINTS do
		local pa, pb = a[joint], b[joint]
		if pa or pb then
			local out = {}
			for index = 1, 4 do
				local va = if pa then pa[index] or 0 else 0
				local vb = if pb then pb[index] or 0 else 0
				out[index] = va + (vb - va) * u
			end
			result[joint] = out
		end
	end
	return result
end

local function mirror(pose: Pose): Pose
	local result: Pose = {}
	for joint, v in pose do
		local name = joint
		if joint:sub(-1) == "R" and (joint:sub(1, 3) == "Arm" or joint:sub(1, 3) == "For" or joint:sub(1, 3) == "Leg") then
			name = joint:sub(1, -2) .. "L"
		elseif joint:sub(-1) == "L" and (joint:sub(1, 3) == "Arm" or joint:sub(1, 3) == "For" or joint:sub(1, 3) == "Leg") then
			name = joint:sub(1, -2) .. "R"
		end
		result[name] = { v[1] or 0, -(v[2] or 0), -(v[3] or 0), v[4] or 0 }
	end
	return result
end

local function sampleKeys(keys: { { any } }, t: number): Pose
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for index = 2, #keys do
		local k0, k1 = keys[index - 1], keys[index]
		if t <= k1[1] then
			local u = (t - k0[1]) / math.max(k1[1] - k0[1], 1e-4)
			u = u * u * (3 - 2 * u)
			return lerpPose(k0[2], k1[2], u)
		end
	end
	return keys[#keys][2]
end

-- Each animation returns its keyframes {time, pose} and its total length.
local ANIMS: { [string]: (any) -> ({ { any } }, number) } = {}

ANIMS.Sweep = function(params)
	local w = params.Windup or 1.1
	local keys = {
		{ 0, {} },
		{ w * 0.4, { UpperTorso = { 0, -0.7, 0 }, ArmR = { 1.0, 0, 1.5 }, ForearmR = { 0.6 }, ArmL = { 0.3, 0, -0.5 }, Head = { 0, 0.3, 0 } } },
		{ w - 0.12, { UpperTorso = { -0.1, -0.9, 0 }, ArmR = { 1.25, 0, 1.75 }, ForearmR = { 0.8 }, ArmL = { 0.3, 0, -0.6 }, Head = { 0, 0.35, 0 } } },
		{ w + 0.1, { UpperTorso = { 0.15, 0.95, 0 }, ArmR = { 1.1, 0, -0.55 }, ForearmR = { -0.1 }, ArmL = { 0.6, 0, -1.0 }, Head = { 0, -0.4, 0 } } },
		{ w + 0.55, { UpperTorso = { 0.05, 0.45, 0 }, ArmR = { 0.6, 0, -0.2 }, ArmL = { 0.3, 0, -0.5 } } },
		{ w + 1.0, {} },
	}
	if params.Pass == 2 then
		for _, key in keys do
			key[2] = mirror(key[2])
		end
	end
	return keys, w + 1.0
end

ANIMS.Slam = function(params)
	local w = params.Windup or 1.4
	local keys = {
		{ 0, {} },
		{ w * 0.5, { ArmR = { 1.9, 0, 0.25 }, ArmL = { 1.9, 0, -0.25 }, ForearmR = { 0.4 }, ForearmL = { 0.4 }, UpperTorso = { -0.25 }, Head = { -0.15 } } },
		{ w - 0.15, { ArmR = { 2.8, 0, 0.2 }, ArmL = { 2.8, 0, -0.2 }, ForearmR = { 0.9 }, ForearmL = { 0.9 }, UpperTorso = { -0.5 }, Head = { -0.35 }, LowerTorso = { 0, 0, 0, -0.4 }, LegR = { -0.2 }, LegL = { -0.2 } } },
		{ w + 0.04, { ArmR = { 0.45, 0, 0.1 }, ArmL = { 0.45, 0, -0.1 }, ForearmR = { 0.2 }, ForearmL = { 0.2 }, UpperTorso = { 0.75 }, Head = { 0.35 }, LowerTorso = { 0, 0, 0, -1.7 }, LegR = { -0.5 }, LegL = { -0.5 } } },
		{ w + 0.9, { ArmR = { 0.5 }, ArmL = { 0.5 }, UpperTorso = { 0.5 }, Head = { 0.25 }, LowerTorso = { 0, 0, 0, -1.2 } } },
		{ w + 1.6, {} },
	}
	return keys, w + 1.6
end

ANIMS.Throw = function(params)
	local keys = {
		{ 0, {} },
		{ 0.1, { UpperTorso = { -0.2, -0.35, 0 }, ArmR = { -0.9, 0, 0.5 }, ForearmR = { 0.6 }, ArmL = { 0.4, 0, -0.4 }, Head = { -0.1 } } },
		{ 0.24, { UpperTorso = { 0.3, 0.45, 0 }, ArmR = { 2.4, 0, 0.15 }, ForearmR = { -0.1 }, ArmL = { 0.2, 0, -0.7 }, Head = { 0.1, -0.2, 0 } } },
		{ 0.6, {} },
	}
	if params.Right == false then
		for _, key in keys do
			key[2] = mirror(key[2])
		end
	end
	return keys, 0.6
end

ANIMS.Vine = function(params)
	local w = params.Windup or 1.5
	local keys = {
		{ 0, {} },
		{ w * 0.45, { ArmR = { 1.9, 0, 0.15 }, ForearmR = { 0.15 }, ArmL = { -0.4, 0, -0.6 }, UpperTorso = { 0.1, -0.15, 0 }, Head = { 0.15 } } },
		{ w - 0.05, { ArmR = { 2.0, 0, 0.05 }, ForearmR = { 0.9 }, ArmL = { -0.5, 0, -0.7 }, UpperTorso = { 0.18, -0.2, 0 }, Head = { 0.2 } } },
		{ w + 0.2, { ArmR = { 1.4, 0, 0.1 }, ForearmR = { 1.3 }, ArmL = { 0.2, 0, -0.4 }, UpperTorso = { 0.3 }, Head = { 0.3 } } },
		{ w + 0.8, {} },
	}
	return keys, w + 0.8
end

ANIMS.Pulse = function(params)
	local w = params.Windup or 3.4
	local keys = {
		{ 0, {} },
		{ w * 0.3, { ArmR = { 0.6, 0, 1.35 }, ArmL = { 0.6, 0, -1.35 }, ForearmR = { 0.4 }, ForearmL = { 0.4 }, UpperTorso = { -0.3 }, Head = { -0.35 } } },
		{ w - 0.1, { ArmR = { 0.7, 0, 1.5 }, ArmL = { 0.7, 0, -1.5 }, ForearmR = { 0.5 }, ForearmL = { 0.5 }, UpperTorso = { -0.4 }, Head = { -0.5 }, LowerTorso = { 0, 0, 0, 0.3 } } },
		{ w + 0.1, { ArmR = { 1.6, 0, -0.1 }, ArmL = { 1.6, 0, 0.1 }, ForearmR = { 1.0 }, ForearmL = { 1.0 }, UpperTorso = { 0.55 }, Head = { 0.35 }, LowerTorso = { 0, 0, 0, -0.6 } } },
		{ w + 1.0, {} },
	}
	return keys, w + 1.0, w
end

ANIMS.Rain = function(params)
	local s = params.Seconds or 5.5
	local keys = {
		{ 0, {} },
		{ 0.5, { ArmR = { 2.7, 0, 0.5 }, ArmL = { 2.7, 0, -0.5 }, ForearmR = { 0.3 }, ForearmL = { 0.3 }, UpperTorso = { -0.3 }, Head = { -0.5 } } },
		{ s, { ArmR = { 2.8, 0, 0.6 }, ArmL = { 2.8, 0, -0.6 }, ForearmR = { 0.4 }, ForearmL = { 0.4 }, UpperTorso = { -0.35 }, Head = { -0.55 } } },
		{ s + 0.9, {} },
	}
	return keys, s + 0.9
end

ANIMS.Rage = function(params)
	local s = params.Seconds or 2.2
	local beat = function(u: number)
		return { ArmR = { 1.0, 0, 0.1 }, ArmL = { 1.0, 0, -0.1 }, ForearmR = { 1.4 }, ForearmL = { 1.4 }, UpperTorso = { -0.35 + 0.1 * u }, Head = { -0.3 } }
	end
	local open = { ArmR = { 0.7, 0, 1.1 }, ArmL = { 0.7, 0, -1.1 }, ForearmR = { 0.3 }, ForearmL = { 0.3 }, UpperTorso = { -0.5 }, Head = { -0.55 } }
	local keys = {
		{ 0, {} },
		{ s * 0.2, open },
		{ s * 0.32, beat(0) },
		{ s * 0.42, open },
		{ s * 0.54, beat(0) },
		{ s * 0.64, open },
		{ s * 0.76, beat(0) },
		{ s * 0.9, { ArmR = { 0.4, 0, 1.4 }, ArmL = { 0.4, 0, -1.4 }, UpperTorso = { -0.6 }, Head = { -0.7 } } },
		{ s + 0.7, {} },
	}
	return keys, s + 0.7
end

ANIMS.Enter = function(params)
	local s = params.Seconds or 4
	local keys = {
		{ 0, { UpperTorso = { 0.6 }, Head = { 0.55 }, ArmR = { 0.35, 0, 0.1 }, ArmL = { 0.35, 0, -0.1 }, LowerTorso = { 0, 0, 0, -1.4 }, LegR = { -0.4 }, LegL = { -0.4 } } },
		{ s * 0.55, { UpperTorso = { 0.4 }, Head = { 0.35 }, ArmR = { 0.3 }, ArmL = { 0.3 }, LowerTorso = { 0, 0, 0, -0.9 } } },
		{ s * 0.85, { UpperTorso = { -0.15 }, Head = { -0.25 }, ArmR = { 0.5, 0, 0.5 }, ArmL = { 0.5, 0, -0.5 }, LowerTorso = { 0, 0, 0, -0.2 } } },
		{ s, { UpperTorso = { -0.55 }, Head = { -0.7 }, ArmR = { 0.8, 0, 1.45 }, ArmL = { 0.8, 0, -1.45 }, ForearmR = { 0.4 }, ForearmL = { 0.4 } } },
		{ s + 0.8, {} },
	}
	return keys, s + 0.8
end

ANIMS.Death = function()
	local keys = {
		{ 0, { UpperTorso = { -0.4 }, Head = { -0.6 }, ArmR = { 0.8, 0, 1.2 }, ArmL = { 0.8, 0, -1.2 } } },
		{ 0.5, { UpperTorso = { 0.2 }, Head = { 0.3 }, ArmR = { 0.4, 0, 0.7 }, ArmL = { 0.4, 0, -0.7 }, LowerTorso = { 0, 0, 0, -1.2 }, LegR = { -0.5 }, LegL = { -0.5 } } },
		{ 1.5, { UpperTorso = { 1.0 }, Head = { 0.7 }, ArmR = { -0.2, 0, 0.3 }, ArmL = { -0.2, 0, -0.3 }, LowerTorso = { 0, 0, 0, -3 }, LegR = { -1.0 }, LegL = { -1.0 } } },
	}
	return keys, 1.6
end

local function idlePose(t: number): Pose
	return {
		LowerTorso = { 0, 0, 0, 0.12 * math.sin(t * 1.4) },
		UpperTorso = { 0.03 * math.sin(t * 1.4), 0.04 * math.sin(t * 0.6), 0 },
		Head = { 0.05 * math.sin(t * 1.1), 0.14 * math.sin(t * 0.5), 0 },
		ArmR = { 0.04 * math.sin(t * 1.7), 0, 0.03 * math.sin(t * 1.3) },
		ArmL = { 0.04 * math.sin(t * 1.7 + 1), 0, -0.03 * math.sin(t * 1.3 + 1) },
		ForearmR = { 0.06 + 0.04 * math.sin(t * 1.9) },
		ForearmL = { 0.06 + 0.04 * math.sin(t * 1.9 + 1) },
	}
end

local function playAnim(name: string, params: { [string]: any }?)
	local a = animator
	local builder = ANIMS[name]
	if not builder then
		return
	end
	if not a then
		pendingAnim = { Name = name, Params = params, At = os.clock() }
		return
	end
	local keys, duration, shakeUntil = builder(params or {})
	a.Current = { Keys = keys, Start = os.clock(), Duration = duration, Name = name, Shake = shakeUntil }
end

local function handPosition(right: boolean): Vector3?
	local a = animator
	if not a then
		return nil
	end
	local part = a.Model:FindFirstChild(if right then "ForearmR" else "ForearmL")
	if part and part:IsA("BasePart") then
		return part.Position + Vector3.new(0, 1, 0)
	end
	return nil
end

local function startAnimator(model: Model)
	local joints: { [string]: Motor6D } = {}
	local resolved = 0
	local function resolveJoints()
		for _, name in JOINTS do
			if not joints[name] then
				local part = model:FindFirstChild(name)
				local motor = part and part:FindFirstChildOfClass("Motor6D")
				if motor then
					joints[name] = motor
					resolved += 1
				end
			end
		end
	end
	resolveJoints()
	local state: { [string]: { number } } = {}
	local a = { Model = model, Current = nil, Joints = joints, Ticks = 0 }
	animator = a
	local pending = pendingAnim
	pendingAnim = nil
	if pending and os.clock() - pending.At < 6 then
		playAnim(pending.Name, pending.Params)
		if a.Current then
			a.Current.Start = pending.At -- keep the original timing
		end
	end
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then
			connection:Disconnect()
			if animator == a then
				animator = nil
			end
			return
		end
		a.Ticks += 1
		if resolved < #JOINTS then
			resolveJoints() -- a 330-part model replicates over several frames
		end
		local now = os.clock()
		local pose: Pose = idlePose(now)
		local current = a.Current
		if current then
			local t = now - current.Start
			if t >= current.Duration and current.Name ~= "Death" then
				a.Current = nil
			else
				local extra = sampleKeys(current.Keys, math.min(t, current.Duration))
				local added: Pose = {}
				for _, joint in JOINTS do
					local base, more = pose[joint], extra[joint]
					if base or more then
						added[joint] = {
							(if base then base[1] or 0 else 0) + (if more then more[1] or 0 else 0),
							(if base then base[2] or 0 else 0) + (if more then more[2] or 0 else 0),
							(if base then base[3] or 0 else 0) + (if more then more[3] or 0 else 0),
							(if base then base[4] or 0 else 0) + (if more then more[4] or 0 else 0),
						}
					end
				end
				pose = added
				-- the heart-pulse charge trembles harder as it builds
				if current.Shake and t < current.Shake then
					local power = (t / current.Shake) ^ 2 * 0.07
					for _, joint in { "UpperTorso", "Head", "ArmR", "ArmL" } do
						local v = pose[joint] or { 0, 0, 0, 0 }
						pose[joint] = { v[1] + (math.random() - 0.5) * power, v[2] + (math.random() - 0.5) * power, v[3] + (math.random() - 0.5) * power, v[4] }
					end
				end
			end
		end
		local follow = 1 - math.exp(-dt * 26)
		for name, motor in joints do
			local target = pose[name] or { 0, 0, 0, 0 }
			local have = state[name] or { 0, 0, 0, 0 }
			local out = {}
			for index = 1, 4 do
				out[index] = have[index] + ((target[index] or 0) - have[index]) * follow
			end
			state[name] = out
			motor.Transform = CFrame.new(0, out[4], 0) * CFrame.Angles(out[1], out[2], out[3])
		end
	end)
end

-- Boss presentation: a big screen-top health bar, dimmed lights during the entrance, heavier music, captions ----------

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local bossBar: { Frame: Frame, Fill: Frame, Lag: Frame, Count: TextLabel, Name: TextLabel }? = nil
local barConnection: RBXScriptConnection? = nil
local captionLabel: TextLabel? = nil

local function caption(text: string, color: Color3, seconds: number)
	local label = captionLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 1
	tween(label, 0.25, { TextTransparency = 0 })
	task.delay(seconds, function()
		if label.Text == text then
			tween(label, 0.4, { TextTransparency = 1 })
		end
	end)
end

local function dimLights(amount: number, seconds: number)
	tween(Lighting, seconds, { Brightness = Lighting:GetAttribute("BossBaseBrightness") * amount })
end

local function restoreLights(seconds: number)
	tween(Lighting, seconds, { Brightness = Lighting:GetAttribute("BossBaseBrightness") })
end

-- the normal background music pauses and the boss theme plays until the boss is gone. The theme is flagged as music so
-- the player's music button (Settings) still mutes it.
local bossTheme: Sound? = nil
local function setBossMusic(on: boolean)
	local background = SoundService:FindFirstChild("BackgroundMusic")
	if on then
		if background and background:IsA("Sound") then
			background:Pause()
		end
		if not bossTheme then
			local theme = Instance.new("Sound")
			theme.Name = "BossMusic"
			theme.SoundId = Config.Boss.Audio.Music
			theme.Looped = true
			theme.Volume = 0
			theme:SetAttribute("RaiseAMonsterMusic", true)
			theme.Parent = SoundService
			bossTheme = theme
		end
		local theme = bossTheme :: Sound
		theme.PlaybackSpeed = 1
		theme:Play()
		tween(theme, 2.5, { Volume = Config.Boss.Audio.MusicVolume })
	else
		local theme = bossTheme
		bossTheme = nil
		if theme then
			tween(theme, 2, { Volume = 0 })
			task.delay(2.2, function()
				theme:Destroy()
			end)
		end
		if background and background:IsA("Sound") then
			background:Resume()
		end
	end
end

local function enrageMusic()
	if bossTheme then
		tween(bossTheme, 1.5, { PlaybackSpeed = Config.Boss.Audio.RageSpeed })
	end
end

local function showBossBar(part: BasePart, fillSeconds: number)
	local screen = gui
	if not screen then
		return
	end
	if bossBar then
		bossBar.Frame:Destroy()
		bossBar = nil
	end
	if barConnection then
		barConnection:Disconnect()
	end
	local frame = Instance.new("Frame")
	frame.Name = "BossBar"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 52)
	frame.Size = UDim2.fromOffset(660, 62)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 7
	frame.Parent = screen
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 26)
	name.Font = Enum.Font.FredokaOne
	name.Text = "BOSS  -  THE PUMPKIN TITAN"
	name.TextColor3 = Color3.fromRGB(255, 190, 90)
	name.TextSize = 22
	name.TextStrokeTransparency = 0.3
	name.ZIndex = 8
	name.Parent = frame
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 28)
	back.Size = UDim2.new(1, 0, 0, 26)
	back.BackgroundColor3 = Color3.fromRGB(25, 12, 18)
	back.BorderSizePixel = 0
	back.ZIndex = 7
	back.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 150, 50)
	stroke.Thickness = 2
	stroke.Parent = back
	local lag = Instance.new("Frame")
	lag.Size = UDim2.fromScale(0, 1)
	lag.BackgroundColor3 = Color3.fromRGB(255, 240, 220)
	lag.BorderSizePixel = 0
	lag.ZIndex = 8
	lag.Parent = back
	local lagCorner = Instance.new("UICorner")
	lagCorner.CornerRadius = UDim.new(0, 8)
	lagCorner.Parent = lag
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 70, 30)
	fill.BorderSizePixel = 0
	fill.ZIndex = 9
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(220, 50, 20))
	gradient.Parent = fill
	-- phase marks at 75 / 50 / 25 %
	for _, fraction in Config.Boss.Attacks.PhaseAt do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(fraction, 0)
		tick.Size = UDim2.new(0, 3, 1, 0)
		tick.BackgroundColor3 = Color3.fromRGB(10, 5, 8)
		tick.BorderSizePixel = 0
		tick.ZIndex = 10
		tick.Parent = back
	end
	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromScale(1, 1)
	count.Font = Enum.Font.GothamBold
	count.TextSize = 15
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.4
	count.ZIndex = 11
	count.Text = ""
	count.Parent = back
	frame.Position = UDim2.new(0.5, 0, 0, -80)
	tween(frame, 0.5, { Position = UDim2.new(0.5, 0, 0, 52) }, Enum.EasingStyle.Back)
	local bar = { Frame = frame, Fill = fill, Lag = lag, Count = count, Name = name }
	bossBar = bar
	local started = os.clock()
	local shown = 0
	barConnection = RunService.RenderStepped:Connect(function(dt)
		if not part.Parent then
			if barConnection then
				barConnection:Disconnect()
			end
			tween(frame, 0.5, { Position = UDim2.new(0.5, 0, 0, -90) })
			task.delay(0.6, function()
				frame:Destroy()
			end)
			if bossBar == bar then
				bossBar = nil
			end
			return
		end
		local max = part:GetAttribute("MaxHealth") or 1
		local health = part:GetAttribute("Health") or max
		local target = math.clamp(health / max, 0, 1)
		-- during the entrance the bar fills up from empty; afterwards it follows the real health
		local intro = math.clamp((os.clock() - started) / fillSeconds, 0, 1)
		local cap = 1 - (1 - intro) ^ 3
		shown += (math.min(target, cap) - shown) * math.min(1, dt * 8)
		fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
		local trail = lag.Size.X.Scale
		lag.Size = UDim2.fromScale(math.max(shown, trail - dt * 0.25), 1)
		count.Text = MonsterMath.FormatNumber(math.max(0, math.floor(health + 0.5))) .. " / " .. MonsterMath.FormatNumber(math.floor(max + 0.5))
	end)
end

-- handlers ------------------------------------------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.Sweep = function(data)
	playAnim("Sweep", { Windup = data.Windup, Pass = data.Pass })
	local origin: Vector3 = data.Origin
	local direction: Vector3 = data.Direction
	local range: number = data.Range
	local angle: number = data.Angle
	local windup: number = data.Windup
	local ground = groundY(origin)
	local base = Vector3.new(origin.X, ground + 0.16, origin.Z)
	local steps = 16
	local half = math.rad(angle / 2)
	local baseAngle = math.atan2(direction.Z, direction.X)
	local fan: { { WedgePart } } = {}
	for _ = 1, steps do
		table.insert(fan, { wedgePart(fxFolder, RED, 0.62), wedgePart(fxFolder, RED, 0.62) })
	end
	local fill: { { WedgePart } } = {}
	for _ = 1, steps do
		table.insert(fill, { wedgePart(fxFolder, AMBER, 0.45), wedgePart(fxFolder, AMBER, 0.45) })
	end
	local function layout(list: { { WedgePart } }, reach: number, lift: number)
		for index = 1, steps do
			local a0 = baseAngle - half + (index - 1) / steps * half * 2
			local a1 = baseAngle - half + index / steps * half * 2
			local p0 = base + Vector3.new(math.cos(a0), 0, math.sin(a0)) * reach + Vector3.new(0, lift, 0)
			local p1 = base + Vector3.new(math.cos(a1), 0, math.sin(a1)) * reach + Vector3.new(0, lift, 0)
			triangle(base + Vector3.new(0, lift, 0), p0, p1, list[index][1], list[index][2])
		end
	end
	layout(fan, range, 0)
	local edges = {}
	for _, sign in { -1, 1 } do
		local a = baseAngle + sign * half
		local tip = base + Vector3.new(math.cos(a), 0, math.sin(a)) * range
		table.insert(edges, fxPart({
			Size = Vector3.new(0.5, 0.12, range),
			CFrame = CFrame.lookAt((base + tip) / 2 + Vector3.new(0, 0.08, 0), tip + Vector3.new(0, 0.08, 0)),
			Color = RED,
			Transparency = 0.1,
		}))
	end
	local rim = ringOutline(base, range, RED, 0.2, 0.5, 0.1)
	-- keep only the rim blocks that are inside the cone
	for index = #rim, 1, -1 do
		local offset = flat(rim[index].Position - base)
		if offset.Magnitude > 0.1 and offset.Unit:Dot(direction) < math.cos(half) then
			rim[index]:Destroy()
			table.remove(rim, index)
		end
	end
	playSound(WINDUP_SOUND, origin, 0.9, 0.7)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - started) / windup, 0, 1)
		layout(fill, range * (u ^ 1.5), 0.05)
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * (10 + u * 16))
		for _, pair in fan do
			pair[1].Transparency = 0.78 - 0.28 * pulse
			pair[2].Transparency = pair[1].Transparency
		end
		if u >= 1 then
			connection:Disconnect()
		end
	end)
	task.delay(windup, function()
		-- the strike: the zone flares white-hot, a slash crescent races through it, and the ground throws debris
		for _, pair in fill do
			pair[1].Color = Color3.new(1, 0.9, 0.7)
			pair[2].Color = pair[1].Color
			tween(pair[1], 0.4, { Transparency = 1 })
			tween(pair[2], 0.4, { Transparency = 1 })
		end
		for _, pair in fan do
			tween(pair[1], 0.35, { Transparency = 1 })
			tween(pair[2], 0.35, { Transparency = 1 })
		end
		for _, edge in edges do
			tween(edge, 0.3, { Transparency = 1 })
		end
		for _, part in rim do
			tween(part, 0.3, { Transparency = 1 })
		end
		for sweepIndex = 1, 3 do
			local reach = range * (0.55 + sweepIndex * 0.15)
			local pieces: { Part } = {}
			local count = 20
			for index = 1, count do
				pieces[index] = fxPart({ Color = if sweepIndex == 2 then Color3.new(1, 0.95, 0.8) else AMBER, Transparency = 0.15, Size = Vector3.new(0.5, 0.6, reach * half * 2 / count * 1.3) })
			end
			local slashStart = os.clock() + (sweepIndex - 1) * 0.03
			local slashConnection: RBXScriptConnection
			slashConnection = RunService.RenderStepped:Connect(function()
				local u = math.clamp((os.clock() - slashStart) / 0.28, 0, 1)
				for index, piece in pieces do
					local t = (index - 0.5) / count
					local a = baseAngle - half + t * half * 2
					local reveal = u * 1.25 - t * 0.25
					piece.Transparency = if reveal <= 0 then 1 else math.clamp(0.1 + (u - t * 0.7) * 1.4, 0.1, 1)
					local radius = reach * (0.92 + 0.12 * u)
					local position = base + Vector3.new(math.cos(a) * radius, 1.6 + math.sin(t * math.pi) * 1.2, math.sin(a) * radius)
					local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
					piece.CFrame = CFrame.lookAt(position, position + tangent)
				end
				if u >= 1 then
					slashConnection:Disconnect()
					for _, piece in pieces do
						piece:Destroy()
					end
				end
			end)
		end
		for _, pair in fan do
			Debris:AddItem(pair[1], 0.6)
			Debris:AddItem(pair[2], 0.6)
		end
		for _, pair in fill do
			Debris:AddItem(pair[1], 0.6)
			Debris:AddItem(pair[2], 0.6)
		end
		for _, edge in edges do
			Debris:AddItem(edge, 0.6)
		end
		for _, part in rim do
			Debris:AddItem(part, 0.6)
		end
		for fraction = 0.3, 1, 0.23 do
			local spot = base + direction * (range * fraction)
			burst(spot + Vector3.new(0, 1, 0), AMBER, RED, 10, 1.4, true)
			debris(spot, 3, 20, { DARK, Color3.fromRGB(120, 80, 50) })
		end
		playSound(IMPACT_SOUND, origin + direction * (range * 0.5), 1, 0.6)
		shake(0.9, 0.35, origin)
	end)
end

handlers.Slam = function(data)
	playAnim("Slam", { Windup = data.Windup })
	local origin: Vector3 = data.Origin
	local waves: { { number } } = data.Waves
	local windup: number = data.Windup
	local ground = groundY(origin)
	local base = Vector3.new(origin.X, ground, origin.Z)
	local inner = waves[1][1]
	local clear = growingZone(base, inner, windup, RED)
	-- the outer waves are outlined in gold so you can see where the next ring will pass
	local outlines: { { Part } } = {}
	for index = 2, #waves do
		table.insert(outlines, ringOutline(base + Vector3.new(0, 0.2, 0), waves[index][1], GOLD, 0.3, 0.5, 0.1))
	end
	playSound(WINDUP_SOUND, origin, 1, 0.55)
	task.delay(windup, function()
		clear()
		cracks(base, 18, inner * 1.05, ORANGE, 2.6)
		debris(base, 22, 36, { DARK, Color3.fromRGB(110, 78, 50), Color3.fromRGB(70, 70, 82) })
		for index, wave in waves do
			local radius, delay = wave[1], wave[2]
			task.delay(delay, function()
				local from = if index == 1 then 4 else waves[index - 1][1]
				waveRing(base + Vector3.new(0, 0.1, 0), from, radius, 0.5, if index == 1 then RED else ORANGE, 4.5 - index * 0.7, 1.4)
				waveRing(base + Vector3.new(0, 0.1, 0), from * 0.92, radius * 0.97, 0.55, Color3.new(1, 0.9, 0.7), 1.4, 0.6)
				burst(base + Vector3.new(0, 1, 0), ORANGE, DARK, 40 - index * 8, 2.2, index == 1)
				playSound(IMPACT_SOUND, base, 1, 0.5 + index * 0.05)
				shake(1.5 - index * 0.2, 0.5, origin)
				if index > 1 then
					local ring = outlines[index - 1]
					if ring then
						for _, part in ring do
							tween(part, 0.4, { Transparency = 1 })
							Debris:AddItem(part, 0.5)
						end
					end
				end
			end)
		end
	end)
end

handlers.Bomb = function(data)
	local from: Vector3 = data.From
	local center: Vector3 = data.Center
	local radius: number = data.Radius
	local windup: number = data.Windup
	local ground = groundY(center)
	local spot = Vector3.new(center.X, ground, center.Z)
	local clear = growingZone(spot, radius, windup, ORANGE)
	local body = pumpkinProjectile(4)
	local now = os.clock()
	throwCount += 1
	local hand = handPosition(throwCount % 2 == 1) or from
	playAnim("Throw", { Right = throwCount % 2 == 1 })
	-- the pumpkin leaves the hand at once and lands exactly when the zone finishes filling
	flyArc(body, hand, spot + Vector3.new(0, 1.2, 0), now + 0.18, now + windup, math.max(16, (spot - hand).Magnitude * 0.45), function()
		clear()
		fireball(spot + Vector3.new(0, 2, 0), radius * 0.95, ORANGE, 0.5)
		waveRing(spot + Vector3.new(0, 0.1, 0), 1, radius, 0.4, AMBER, 2.6, 1)
		burst(spot + Vector3.new(0, 1.5, 0), AMBER, RED, 36, 2.1, true)
		cracks(spot, 7, radius * 0.9, ORANGE, 1.6)
		debris(spot, 8, 24, { DARK, Color3.fromRGB(120, 70, 30) })
		playSound(IMPACT_SOUND, spot, 0.95, 0.85)
		shake(0.55, 0.3, spot)
	end)
	playSound(WINDUP_SOUND, from, 0.5, 1.4)
end

handlers.BombFire = function(data)
	local center: Vector3 = data.Center
	local radius: number = data.Radius
	local duration: number = data.Duration
	local ground = groundY(center)
	local spot = Vector3.new(center.X, ground, center.Z)
	local scorch = disc(spot + Vector3.new(0, 0.12, 0), radius, Color3.fromRGB(40, 20, 12), 0.35)
	scorch.Material = Enum.Material.Slate
	local glow = disc(spot + Vector3.new(0, 0.16, 0), radius * 0.92, ORANGE, 0.78)
	local rim = ringOutline(spot + Vector3.new(0, 0.2, 0), radius, ORANGE, 0.2, 0.4, 0.1)
	local holder = fxPart({ Size = Vector3.one * 0.2, Position = spot + Vector3.new(0, 0.5, 0), Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = ORANGE
	light.Range = radius * 3
	light.Brightness = 2.5
	light.Parent = holder
	for _ = 1, 9 do
		local angle = math.random() * math.tau
		local distance = math.sqrt(math.random()) * radius * 0.85
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = spot + Vector3.new(math.cos(angle) * distance, 0.3, math.sin(angle) * distance)
		attachment.Parent = holder
		local flame = Instance.new("ParticleEmitter")
		flame.Texture = FIRE
		flame.Color = ColorSequence.new(AMBER, RED)
		flame.LightEmission = 0.9
		flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.3) })
		flame.Speed = NumberRange.new(3, 7)
		flame.Lifetime = NumberRange.new(0.6, 1.1)
		flame.Rate = 7
		flame.EmissionDirection = Enum.NormalId.Top
		flame.SpreadAngle = Vector2.new(12, 12)
		flame.Parent = attachment
	end
	task.delay(math.max(duration - 0.9, 0.1), function()
		for _, child in holder:GetDescendants() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		tween(light, 0.8, { Brightness = 0 })
		tween(glow, 0.8, { Transparency = 1 })
		tween(scorch, 0.8, { Transparency = 1 })
		for _, part in rim do
			tween(part, 0.8, { Transparency = 1 })
		end
	end)
	Debris:AddItem(holder, duration + 1.2)
	Debris:AddItem(scorch, duration + 1)
	Debris:AddItem(glow, duration + 1)
	for _, part in rim do
		Debris:AddItem(part, duration + 1)
	end
end

handlers.Vine = function(data)
	playAnim("Vine", { Windup = data.Windup })
	local from: Vector3 = data.From
	local base: Vector3 = data.Base
	local center: Vector3 = data.Center
	local radius: number = data.Radius
	local windup: number = data.Windup
	local ground = groundY(center)
	local spot = Vector3.new(center.X, ground, center.Z)
	local green = Color3.fromRGB(70, 150, 50)
	local clear = growingZone(spot, radius, windup, GREEN)
	-- the vine itself snakes out of the boss toward the victim
	local segments = 22
	local pieces: { Part } = {}
	local start = Vector3.new(base.X, ground + 1, base.Z)
	local points: { Vector3 } = {}
	for index = 0, segments do
		local t = index / segments
		local wobble = math.sin(t * math.pi * 5) * 2.2 * math.sin(t * math.pi)
		local side = (spot - start):Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local position = start:Lerp(spot, t) + side * wobble + Vector3.new(0, 1.2 + math.sin(t * math.pi) * 2.5, 0)
		table.insert(points, position)
	end
	for index = 1, segments do
		local a, b = points[index], points[index + 1]
		local piece = fxPart({
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Grass,
			Size = Vector3.new((b - a).Magnitude * 1.1, 0.9 - index / segments * 0.35, 0.9 - index / segments * 0.35),
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
			Color = green,
			Transparency = 1,
		})
		pieces[index] = piece
		if index % 3 == 0 then
			local thorn = Instance.new("WedgePart")
			thorn.Anchored = true
			thorn.CanCollide = false
			thorn.CanQuery = false
			thorn.Material = Enum.Material.Wood
			thorn.Color = Color3.fromRGB(150, 100, 50)
			thorn.Size = Vector3.new(0.18, 0.9, 0.5)
			thorn.CFrame = CFrame.lookAt(a, a + Vector3.new(0, 1, 0) + (b - a).Unit:Cross(Vector3.yAxis) * 0.4)
			thorn.Transparency = 1
			thorn.Parent = fxFolder
			Debris:AddItem(thorn, windup + 1.2)
			task.delay(index / segments * 0.5, function()
				thorn.Transparency = 0
			end)
		end
		task.delay(index / segments * 0.5, function()
			piece.Transparency = 0
			tween(piece, 0.15, { Size = piece.Size })
		end)
		Debris:AddItem(piece, windup + 1.2)
	end
	-- thorny roots rising under the victim's position: they grow while the zone fills
	local thorns: { Part } = {}
	for index = 1, 10 do
		local angle = index / 10 * math.tau
		local distance = radius * (0.35 + 0.6 * (index % 3) / 2)
		local thorn = fxPart({
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(60, 120, 40),
			Size = Vector3.new(0.2, 0.9, 0.9),
			CFrame = CFrame.new(spot + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.3,
		})
		table.insert(thorns, thorn)
		tween(thorn, windup, { Size = Vector3.new(2.2 + math.random(), 0.9, 0.9), CFrame = thorn.CFrame * CFrame.new(0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	playSound(WINDUP_SOUND, base, 0.7, 1.2)
	task.delay(windup, function()
		clear()
		for _, thorn in thorns do
			local position = thorn.Position
			thorn.CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
			thorn.Size = Vector3.new(8 + math.random() * 3, 1.1, 1.1)
			tween(thorn, 0.8, { Transparency = 1 })
			Debris:AddItem(thorn, 0.9)
		end
		burst(spot + Vector3.new(0, 2, 0), GREEN, Color3.fromRGB(40, 90, 30), 30, 1.8)
		waveRing(spot + Vector3.new(0, 0.1, 0), 1, radius, 0.35, GREEN, 3, 0.8)
		debris(spot, 8, 20, { Color3.fromRGB(60, 110, 40), DARK })
		playSound(IMPACT_SOUND, spot, 0.8, 1.1)
		shake(0.5, 0.25, spot)
		for _, piece in pieces do
			tween(piece, 0.5, { Transparency = 1 })
		end
	end)
end

handlers.VineGrabbed = function(data)
	local victim: Player = data.Player
	local seconds: number = data.Seconds
	local character = victim.Character
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(70, 160, 50)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = GREEN
	highlight.Parent = character
	Debris:AddItem(highlight, seconds)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local leaves = Instance.new("ParticleEmitter")
		leaves.Texture = SPARKLE
		leaves.Color = ColorSequence.new(GREEN, Color3.fromRGB(40, 100, 30))
		leaves.LightEmission = 0.3
		leaves.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		leaves.Speed = NumberRange.new(4, 9)
		leaves.Lifetime = NumberRange.new(0.5, 1)
		leaves.Rate = 40
		leaves.SpreadAngle = Vector2.new(180, 180)
		leaves.Parent = attachment
		Debris:AddItem(attachment, seconds)
	end
	if victim == player then
		flash(GREEN, 0.75, 0.6)
		shake(0.7, 0.5)
	end
end

handlers.HeartPulse = function(data)
	playAnim("Pulse", { Windup = data.Windup })
	local origin: Vector3 = data.Origin
	local heart: Vector3 = data.Heart
	local safe: { Vector3 } = data.Safe
	local safeRadius: number = data.SafeRadius
	local radius: number = data.Radius
	local windup: number = data.Windup
	local ground = groundY(origin)
	local base = Vector3.new(origin.X, ground, origin.Z)
	-- safe pumpkin lanterns
	local cleanups = {}
	for _, spot in safe do
		local position = Vector3.new(spot.X, groundY(spot), spot.Z)
		local floorDisc = disc(position + Vector3.new(0, 0.15, 0), safeRadius, GREEN, 0.6)
		local rim = ringOutline(position + Vector3.new(0, 0.22, 0), safeRadius, GREEN, 0.05, 0.7, 0.14)
		local column = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(34, safeRadius * 1.5, safeRadius * 1.5), CFrame = CFrame.new(position + Vector3.new(0, 17, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = GREEN, Transparency = 0.86 })
		local lantern = carvedPumpkin(8)
		local lift = lantern.Size.Y / 2
		lantern.CFrame = CFrame.lookAt(position + Vector3.new(0, lift, 0), Vector3.new(origin.X, position.Y + lift, origin.Z))
		local lanternLight = lantern:FindFirstChildOfClass("PointLight")
		if lanternLight then
			lanternLight.Range = safeRadius * 3
			lanternLight.Brightness = 3.2
			lanternLight.Color = GREEN
		end
		local label = Instance.new("BillboardGui")
		label.Size = UDim2.fromOffset(120, 36)
		label.StudsOffset = Vector3.new(0, 8, 0)
		label.AlwaysOnTop = true
		label.MaxDistance = 400
		label.Parent = lantern
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.Text = "SAFE"
		text.TextScaled = true
		text.TextColor3 = GREEN
		text.TextStrokeTransparency = 0
		text.Parent = label
		table.insert(cleanups, function()
			floorDisc:Destroy()
			column:Destroy()
			lantern:Destroy()
			for _, part in rim do
				part:Destroy()
			end
		end)
		local pulseStart = os.clock()
		local pulseConnection: RBXScriptConnection
		pulseConnection = RunService.RenderStepped:Connect(function()
			if os.clock() - pulseStart > windup + 0.3 then
				pulseConnection:Disconnect()
				return
			end
			local pulse = 0.5 + 0.5 * math.sin((os.clock() - pulseStart) * 6)
			column.Transparency = 0.9 - 0.1 * pulse
			floorDisc.Transparency = 0.7 - 0.2 * pulse
		end)
	end
	-- the danger zone is the whole arena: an outer ring shows how far the pulse reaches
	local reach = ringOutline(base + Vector3.new(0, 0.25, 0), math.min(radius, 120), RED, 0.35, 0.7, 0.12)
	-- exposed chest: gold light grows, sparks converge, a label tells everyone to hit it
	local holder = fxPart({ Size = Vector3.one * 0.3, Position = heart + Vector3.new(0, 0, -2.5), Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 12
	light.Brightness = 0
	light.Parent = holder
	tween(light, windup, { Brightness = 12, Range = 60 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local core = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Position = heart + Vector3.new(0, 0, -2.5), Color = GOLD, Transparency = 0.2 })
	tween(core, windup, { Size = Vector3.one * 7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(260, 60)
	tag.StudsOffset = Vector3.new(0, 7, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 500
	tag.Parent = holder
	local tagText = Instance.new("TextLabel")
	tagText.Size = UDim2.fromScale(1, 1)
	tagText.BackgroundTransparency = 1
	tagText.Font = Enum.Font.FredokaOne
	tagText.Text = "HIT THE HEART!"
	tagText.TextScaled = true
	tagText.TextColor3 = GOLD
	tagText.TextStrokeTransparency = 0
	tagText.Parent = tag
	-- converging sparks
	local sparkCount = 56
	for index = 1, sparkCount do
		task.delay(windup * 0.8 * (index / sparkCount), function()
			local angle = math.random() * math.tau
			local lift = (math.random() - 0.3) * 18
			local start = heart + Vector3.new(math.cos(angle) * 24, lift, math.sin(angle) * 24)
			local spark = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Position = start, Color = GOLD })
			tween(spark, windup * 0.2, { Position = heart + Vector3.new(0, 0, -2.5), Size = Vector3.one * 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(spark, windup * 0.2 + 0.1)
		end)
	end
	playSound(WINDUP_SOUND, origin, 1, 0.45)
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < windup - 0.2 do
			shake(0.18 + 0.4 * ((os.clock() - started) / windup), 0.4, origin)
			task.wait(0.3)
		end
	end)
	task.delay(windup, function()
		-- the pulse
		local shell = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = heart, Color = GOLD, Transparency = 0.25, Material = Enum.Material.ForceField })
		tween(shell, 0.7, { Size = Vector3.one * radius * 2, Transparency = 1 })
		Debris:AddItem(shell, 0.8)
		fireball(heart, 14, Color3.new(1, 0.9, 0.55), 0.6)
		for index = 1, 3 do
			task.delay(index * 0.12, function()
				waveRing(base + Vector3.new(0, 0.1, 0), 4, radius, 0.8, if index == 2 then Color3.new(1, 1, 1) else GOLD, 5, 1.4)
			end)
		end
		burst(heart, GOLD, ORANGE, 70, 3)
		playSound(IMPACT_SOUND, origin, 1, 0.4)
		shake(1.6, 0.8, origin)
		-- am I covered? covered players see a green shield flash, everyone else gets blinded
		local root = localRoot()
		if root then
			local covered = false
			for _, spot in safe do
				if (flat(root.Position) - flat(spot)).Magnitude <= safeRadius then
					covered = true
					break
				end
			end
			if covered then
				flash(GREEN, 0.8, 0.5)
			else
				flash(Color3.new(1, 0.95, 0.7), 0.15, 0.9)
			end
		end
		for _, clean in cleanups do
			task.delay(0.35, clean)
		end
		for _, part in reach do
			tween(part, 0.3, { Transparency = 1 })
			Debris:AddItem(part, 0.4)
		end
		tween(core, 0.35, { Transparency = 1, Size = Vector3.one * 12 })
		tween(light, 0.6, { Brightness = 0 })
		Debris:AddItem(core, 0.5)
		Debris:AddItem(holder, 0.8)
	end)
end

handlers.RainStart = function(data)
	playAnim("Rain", { Seconds = data.Seconds })
	banner("LOOK UP!", AMBER, 1.8)
	shake(0.25, 0.8)
	playSound(WINDUP_SOUND, data.Origin, 1, 0.4)
end

handlers.Rain = function(data)
	local center: Vector3 = data.Center
	local radius: number = data.Radius
	local windup: number = data.Windup
	local golden: boolean = data.Golden
	local ground = groundY(center)
	local spot = Vector3.new(center.X, ground, center.Z)
	local color = if golden then GOLD else RED
	local floorDisc = disc(spot + Vector3.new(0, 0.14, 0), radius, color, 0.7)
	local outline = ringOutline(spot + Vector3.new(0, 0.2, 0), radius, color, 0.1, 0.45, 0.1)
	local shadow = disc(spot + Vector3.new(0, 0.18, 0), 0.5, Color3.new(0, 0, 0), 0.6)
	tween(shadow, windup, { Size = Vector3.new(0.2, radius * 1.6, radius * 1.6), Transparency = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local body = pumpkinProjectile(if golden then 3.4 else 3)
	if golden then
		body.Color = GOLD
	end
	local now = os.clock()
	flyArc(body, spot + Vector3.new((math.random() - 0.5) * 6, 75, (math.random() - 0.5) * 6), spot + Vector3.new(0, 1, 0), now, now + windup, 0, function()
		floorDisc:Destroy()
		shadow:Destroy()
		for _, part in outline do
			part:Destroy()
		end
		if golden then
			burst(spot + Vector3.new(0, 1.5, 0), GOLD, Color3.new(1, 1, 0.8), 40, 1.6)
			waveRing(spot + Vector3.new(0, 0.1, 0), 1, radius * 0.9, 0.4, GOLD, 1.6, 0.6)
			playSound(IMPACT_SOUND, spot, 0.6, 1.8)
		else
			fireball(spot + Vector3.new(0, 1.8, 0), radius * 0.8, ORANGE, 0.4)
			waveRing(spot + Vector3.new(0, 0.1, 0), 1, radius, 0.35, AMBER, 2.2, 0.9)
			burst(spot + Vector3.new(0, 1, 0), AMBER, RED, 22, 1.6, true)
			debris(spot, 5, 20, { DARK, Color3.fromRGB(130, 80, 30) })
			playSound(IMPACT_SOUND, spot, 0.8, 0.95)
			shake(0.4, 0.2, spot)
		end
	end)
end

handlers.Rage = function(data)
	playAnim("Rage", { Seconds = data.Seconds })
	local origin: Vector3 = data.Origin
	local seconds: number = data.Seconds
	local ground = groundY(origin)
	local base = Vector3.new(origin.X, ground, origin.Z)
	banner("ENRAGED!", RED, 2.4)
	flash(RED, 0.82, 0.8)
	playSound(WINDUP_SOUND, origin, 1, 0.35)
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < seconds do
			shake(1.1, 0.5, origin)
			task.wait(0.3)
		end
	end)
	for index = 1, 4 do
		task.delay(0.35 * index, function()
			waveRing(base + Vector3.new(0, 0.1, 0), 6, 80 + index * 12, 1, RED, 6 - index, 1.6)
			burst(base + Vector3.new(0, 3, 0), RED, ORANGE, 30, 3, true)
			cracks(base, 12, 30 + index * 8, RED, 2.5)
		end)
	end
	debris(base, 26, 44, { DARK, Color3.fromRGB(120, 70, 40) })
	playSound(IMPACT_SOUND, origin, 1, 0.35)
end

handlers.Entrance = function(data)
	local position: Vector3 = data.Position
	local height: number = data.Height
	local buildUp: number = data.BuildUp
	local rise: number = data.Rise
	local roar: number = data.Roar
	local total = buildUp + rise + roar
	local ground = groundY(position)
	local base = Vector3.new(position.X, ground, position.Z)
	local part = data.Part :: BasePart?
	-- the server fades the world to night as the boss spawns, so the entrance dims relative to the night brightness
	Lighting:SetAttribute("BossBaseBrightness", Config.Halloween.Atmosphere.Brightness)
	setBossMusic(true)

	-- 1. the path behind you crumbles, the light dies, the ground starts to tremble
	dimLights(0.35, buildUp * 0.8)
	caption("THE PATH BEHIND YOU CRUMBLES...", AMBER, buildUp * 0.9)
	local gate = Vector3.new(Config.Map.ZonesStartX + 6, ground, 0)
	cracks(gate, 12, 26, ORANGE, 3)
	debris(gate + Vector3.new(0, 0, 0), 14, 24, { DARK, Color3.fromRGB(110, 78, 50) })
	burst(gate + Vector3.new(0, 3, 0), Color3.fromRGB(170, 130, 90), DARK, 20, 3)
	playSound(WINDUP_SOUND, position, 1, 0.3)

	-- 2. the build-up: a low rumble and dust shaking loose, nothing visible yet
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < buildUp do
			local u = (os.clock() - started) / buildUp
			shake(0.15 + 0.4 * u, 0.35, position)
			burst(base + Vector3.new(math.random(-40, 40), 12 + math.random() * 10, math.random(-40, 40)), Color3.fromRGB(160, 125, 90), DARK, 4, 1.6)
			task.wait(0.22)
		end
	end)

	-- 3. the reveal: it climbs out feet first while the camera tilts up its body
	task.delay(buildUp, function()
		playAnim("Enter", { Seconds = rise })
		caption("", Color3.new(1, 1, 1), 0.1)
		for index = 1, 5 do
			task.delay((index - 1) * rise / 5, function()
				cracks(base, 10 + index * 2, 14 + index * 9, ORANGE, 3)
				waveRing(base + Vector3.new(0, 0.1, 0), 4, 20 + index * 11, 0.9, if index % 2 == 0 then ORANGE else AMBER, 2.5, 1)
				debris(base, 10, 26 + index * 4, { DARK, Color3.fromRGB(110, 78, 50) })
				burst(base + Vector3.new(math.random(-10, 10), 1, math.random(-10, 10)), Color3.fromRGB(170, 130, 90), DARK, 16, 3.2)
			end)
		end
		task.spawn(function()
			local started = os.clock()
			while os.clock() - started < rise do
				local u = (os.clock() - started) / rise
				shake(0.4 + 0.9 * u, 0.4, position)
				task.wait(0.25)
			end
		end)
	end)

	-- the camera: only for players close enough to watch, ends the moment the roar is over
	local root = localRoot()
	local camera = workspace.CurrentCamera
	if camera and root and (root.Position - base).Magnitude < 230 and Config.Boss.IntroCamera then
		local startedAt = os.clock() + buildUp * 0.6
		local lastAt = os.clock() + total - 0.4
		local away = flat(root.Position - base)
		away = if away.Magnitude > 1 then away.Unit else Vector3.new(-1, 0, 0)
		local side = away:Cross(Vector3.yAxis) * 14
		local name = "BossIntroCamera"
		pcall(function()
			RunService:UnbindFromRenderStep(name)
		end)
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
			local now = os.clock()
			if now < startedAt then
				return
			end
			if now > lastAt then
				RunService:UnbindFromRenderStep(name)
				camera.CameraType = Enum.CameraType.Custom
				return
			end
			local u = math.clamp((now - startedAt) / (lastAt - startedAt), 0, 1)
			local eased = u * u * (3 - 2 * u)
			camera.CameraType = Enum.CameraType.Scriptable
			local eye = base + away * (88 - 24 * eased) + side * (1 - eased) + Vector3.new(0, 12 + 14 * eased, 0)
			local focus = base + Vector3.new(0, 1 + height * 0.72 * eased, 0)
			camera.CFrame = CFrame.lookAt(eye, focus)
			camera.FieldOfView = 62 + 12 * eased
		end)
	end

	-- 4. the name card + 5. the boss bar filling up from empty
	local screen = gui
	local nameAt = buildUp + rise * 0.78
	if screen then
		local bars: { Frame } = {}
		for _, top in { true, false } do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Color3.new(0, 0, 0)
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0, if top then 0 else 1)
			bar.Position = UDim2.fromScale(0, if top then 0 else 1)
			bar.Size = UDim2.new(1, 0, 0, 0)
			bar.ZIndex = 4
			bar.Parent = screen
			task.delay(buildUp * 0.5, function()
				tween(bar, 0.6, { Size = UDim2.new(1, 0, 0.11, 0) }, Enum.EasingStyle.Quad)
			end)
			table.insert(bars, bar)
		end
		local chip = Instance.new("TextLabel")
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.7)
		chip.Size = UDim2.fromOffset(120, 30)
		chip.BackgroundColor3 = Color3.fromRGB(220, 50, 25)
		chip.Font = Enum.Font.GothamBlack
		chip.Text = "B O S S"
		chip.TextColor3 = Color3.new(1, 1, 1)
		chip.TextSize = 18
		chip.BackgroundTransparency = 1
		chip.TextTransparency = 1
		chip.ZIndex = 6
		chip.Parent = screen
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 8)
		chipCorner.Parent = chip
		local title = Instance.new("TextLabel")
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.78)
		title.Size = UDim2.fromOffset(900, 110)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.Text = "THE PUMPKIN TITAN"
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 150, 40)
		title.TextTransparency = 1
		title.TextStrokeColor3 = Color3.fromRGB(70, 20, 0)
		title.TextStrokeTransparency = 1
		title.ZIndex = 6
		title.Parent = screen
		local scale = Instance.new("UIScale")
		scale.Scale = 2.6
		scale.Parent = title
		local sub = Instance.new("TextLabel")
		sub.AnchorPoint = Vector2.new(0.5, 0.5)
		sub.Position = UDim2.fromScale(0.5, 0.86)
		sub.Size = UDim2.fromOffset(700, 36)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.Text = "D E F E A T   I T   T O G E T H E R"
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(255, 225, 160)
		sub.TextTransparency = 1
		sub.ZIndex = 6
		sub.Parent = screen
		task.delay(nameAt, function()
			title.TextTransparency = 0
			title.TextStrokeTransparency = 0.2
			tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			chip.BackgroundTransparency = 0
			chip.TextTransparency = 0
			tween(sub, 0.6, { TextTransparency = 0 })
			shake(1.2, 0.4)
			flash(Color3.fromRGB(255, 160, 60), 0.75, 0.5)
			if part then
				showBossBar(part, math.max(rise * 0.22 + roar, 1.2))
			end
		end)
		task.delay(total + 0.5, function()
			tween(title, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(sub, 0.6, { TextTransparency = 1 })
			tween(chip, 0.6, { BackgroundTransparency = 1, TextTransparency = 1 })
			for _, bar in bars do
				tween(bar, 0.6, { Size = UDim2.new(1, 0, 0, 0) })
			end
			task.delay(0.8, function()
				title:Destroy()
				sub:Destroy()
				chip:Destroy()
				for _, bar in bars do
					bar:Destroy()
				end
			end)
		end)
	end

	-- 8. the roar: the dust blasts out and the whole arena reacts (lights flicker back on)
	task.delay(buildUp + rise, function()
		caption("", Color3.new(1, 1, 1), 0.1)
		fireball(base + Vector3.new(0, height * 0.5, 0), 26, ORANGE, 0.8)
		for index = 1, 3 do
			task.delay(index * 0.15, function()
				waveRing(base + Vector3.new(0, 0.1, 0), 6, 95, 1, if index == 2 then Color3.new(1, 0.9, 0.7) else RED, 5, 1.5)
				waveRing(base + Vector3.new(0, 0.1, 0), 4, 110, 1.3, Color3.fromRGB(170, 135, 100), 3.5, 2.4)
			end)
		end
		for _ = 1, 6 do
			burst(base + Vector3.new(math.random(-30, 30), 3, math.random(-30, 30)), Color3.fromRGB(175, 140, 105), DARK, 22, 4.5)
		end
		burst(base + Vector3.new(0, height * 0.55, 0), AMBER, RED, 60, 3.2, true)
		playSound(IMPACT_SOUND, position, 1, 0.3)
		shake(1.6, 0.8, position)
		for flicker = 1, 4 do
			task.delay(flicker * 0.09, function()
				Lighting.Brightness = Lighting:GetAttribute("BossBaseBrightness") * (if flicker % 2 == 0 then 0.35 else 1.1)
			end)
		end
		task.delay(0.5, function()
			restoreLights(1.4)
		end)
	end)
end

handlers.Phase = function(data)
	local phase: number = data.Phase
	local origin: Vector3 = data.Origin
	local ground = groundY(origin)
	waveRing(Vector3.new(origin.X, ground + 0.1, origin.Z), 6, 46, 0.8, AMBER, 3, 1)
	banner("PHASE " .. tostring(phase), AMBER, 1.6)
	if phase >= 3 then
		enrageMusic()
	end
	shake(0.5, 0.5, origin)
end

handlers.Death = function(data)
	local position: Vector3 = data.Position
	local ground = groundY(position)
	local base = Vector3.new(position.X, ground, position.Z)
	local middle = base + Vector3.new(0, 18, 0)
	playAnim("Death", {})
	setBossMusic(false)
	banner("THE TITAN FALLS!", GOLD, 3)
	shake(0.9, 1.0, position)
	-- the body fades out as it hits the ground
	local model = animator and animator.Model
	if model then
		local started = os.clock() + 0.9
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			if not model.Parent then
				connection:Disconnect()
				return
			end
			local u = math.clamp((os.clock() - started) / 0.8, 0, 1)
			if u > 0 then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = u
					end
				end
			end
		end)
	end
	task.delay(1.0, function()
		flash(Color3.new(1, 0.9, 0.6), 0.2, 1.2)
		fireball(middle, 34, ORANGE, 1.1)
		fireball(middle, 22, Color3.new(1, 0.95, 0.7), 0.8)
		for index = 1, 4 do
			task.delay(index * 0.18, function()
				waveRing(base + Vector3.new(0, 0.1, 0), 4, 90, 1.1, if index % 2 == 0 then GOLD else ORANGE, 6, 1.6)
				burst(middle + Vector3.new(math.random(-8, 8), math.random(-6, 6), math.random(-8, 8)), AMBER, RED, 50, 3.2, true)
			end)
		end
		cracks(base, 22, 44, ORANGE, 3.5)
		debris(base, 40, 56, { Color3.fromRGB(226, 92, 24), DARK, Color3.fromRGB(110, 70, 40), Color3.fromRGB(60, 120, 40) })
		-- a shower of candy
		local candyColors = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 220, 90), Color3.fromRGB(150, 220, 120), Color3.fromRGB(190, 150, 255), Color3.fromRGB(255, 150, 60) }
		for _ = 1, 60 do
			local candy = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.8 + math.random()), Position = middle, Color = candyColors[math.random(1, #candyColors)], Material = Enum.Material.SmoothPlastic })
			local goal = base + Vector3.new((math.random() - 0.5) * 70, 0.8, (math.random() - 0.5) * 70)
			local startAt = os.clock()
			local duration = 0.9 + math.random() * 0.7
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local u = math.clamp((os.clock() - startAt) / duration, 0, 1)
				candy.Position = middle:Lerp(goal, u) + Vector3.new(0, math.sin(u * math.pi) * 22, 0)
				if u >= 1 then
					connection:Disconnect()
					tween(candy, 1.2, { Transparency = 1 })
					Debris:AddItem(candy, 1.3)
				end
			end)
		end
		playSound(IMPACT_SOUND, position, 1, 0.3)
		shake(1.8, 1.4, position)
	end)
end

-- ambient: embers, a breathing heart light and glowing eyes on the boss, plus the rage aura --------------------------

local function partNamed(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local function dress(model: Model)
	if model:GetAttribute("BossFxDressed") then
		return
	end
	model:SetAttribute("BossFxDressed", true)
	-- the model has ~330 parts and streams in over several frames: wait until its child count stops growing
	local last, stable, waited = -1, false, 0
	while not stable and waited < 8 do
		local count = #model:GetChildren()
		stable = count == last and count > 200
		last = count
		task.wait(0.15)
		waited += 0.15
	end
	startAnimator(model)
	-- 7. sell the scale: a slow, heavy heartbeat that shakes the ground and kicks up dust at its feet
	task.spawn(function()
		while model.Parent do
			task.wait(2.6)
			local root = model.PrimaryPart
			if root and model:GetAttribute("Procedural") == false and root.Parent then
				local feet = Vector3.new(root.Position.X, groundY(root.Position), root.Position.Z)
				shake(0.14, 0.3, feet)
				burst(feet + Vector3.new(math.random(-8, 8), 0.5, math.random(-8, 8)), Color3.fromRGB(170, 135, 100), DARK, 6, 2.2)
			end
		end
	end)
	local head = partNamed(model, "Head")
	local heart = partNamed(model, "Heart_Gold")
	local lantern = partNamed(model, "Pumpkin_Head_Inner_Lantern")
	if head then
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 1, 0)
		attachment.Parent = head
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = SPARKLE
		embers.Color = ColorSequence.new(AMBER, RED)
		embers.LightEmission = 1
		embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		embers.Speed = NumberRange.new(2, 6)
		embers.Lifetime = NumberRange.new(1.4, 2.6)
		embers.Acceleration = Vector3.new(0, 5, 0)
		embers.Rate = 10
		embers.SpreadAngle = Vector2.new(60, 60)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Parent = attachment
	end
	if lantern then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 160, 50)
		glow.Range = 34
		glow.Brightness = 2.2
		glow.Parent = lantern
	end
	local heartLight: PointLight? = nil
	if heart then
		heartLight = Instance.new("PointLight")
		heartLight.Color = GOLD
		heartLight.Range = 20
		heartLight.Brightness = 2
		heartLight.Parent = heart
	end
	local rage: { Instance } = {}
	local function setRage(on: boolean)
		for _, item in rage do
			item:Destroy()
		end
		table.clear(rage)
		if not on then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 60, 20)
		highlight.FillTransparency = 0.88
		highlight.OutlineColor = Color3.fromRGB(255, 120, 40)
		highlight.OutlineTransparency = 0.25
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		table.insert(rage, highlight)
		for _, name in { "ForearmR", "ForearmL", "Head" } do
			local part = partNamed(model, name)
			if part then
				local attachment = Instance.new("Attachment")
				attachment.Parent = part
				local flame = Instance.new("ParticleEmitter")
				flame.Texture = FIRE
				flame.Color = ColorSequence.new(AMBER, RED)
				flame.LightEmission = 1
				flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
				flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) })
				flame.Speed = NumberRange.new(4, 9)
				flame.Lifetime = NumberRange.new(0.5, 0.9)
				flame.Rate = 18
				flame.SpreadAngle = Vector2.new(30, 30)
				flame.EmissionDirection = Enum.NormalId.Top
				flame.Parent = attachment
				table.insert(rage, attachment)
			end
		end
	end
	model:GetAttributeChangedSignal("Enraged"):Connect(function()
		setRage(model:GetAttribute("Enraged") == true)
	end)
	setRage(model:GetAttribute("Enraged") == true)
	-- breathing heart light, flickering eye light
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock()
		if heartLight then
			heartLight.Brightness = 2 + 1.4 * math.sin(t * 2.2)
		end
		if lantern then
			local glow = lantern:FindFirstChildOfClass("PointLight")
			if glow then
				glow.Brightness = 2.2 + 0.5 * math.sin(t * 9) + 0.3 * math.sin(t * 23)
			end
		end
	end)
end

local function watch(eventsFolder: Instance)
	local function check(child: Instance)
		if child.Name == "BigBoss" then
			local function look()
				local model = child:FindFirstChild("PumpkinTitan")
				if model and model:IsA("Model") then
					task.defer(dress, model)
				end
			end
			child.ChildAdded:Connect(look)
			look()
		end
	end
	eventsFolder.ChildAdded:Connect(check)
	for _, child in eventsFolder:GetChildren() do
		check(child)
	end
end

-- Studio test hooks: BossFx.Play("Slam", { Windup = 3 }) poses the boss; DebugState reports the animator.
function BossFx.Play(name: string, params: { [string]: any }?)
	playAnim(name, params)
end

function BossFx.DebugState(): { [string]: any }
	local a = animator
	if not a then
		return { Running = false }
	end
	local count = 0
	for _ in a.Joints or {} do
		count += 1
	end
	return { Running = true, Joints = count, Current = a.Current and a.Current.Name, Ticks = a.Ticks }
end

function BossFx.Start(remotes: { [string]: RemoteEvent }, playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "BossFxGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 80
	screen.Parent = playerGui
	gui = screen
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.ZIndex = 1
	overlay.Parent = screen
	flashFrame = overlay
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.16, 0)
	label.Size = UDim2.fromOffset(640, 90)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.ZIndex = 5
	label.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = label
	bannerLabel = label
	local small = Instance.new("TextLabel")
	small.AnchorPoint = Vector2.new(0.5, 0)
	small.Position = UDim2.new(0.5, 0, 0.8, 0)
	small.Size = UDim2.fromOffset(760, 34)
	small.BackgroundTransparency = 1
	small.Font = Enum.Font.GothamBold
	small.TextScaled = true
	small.Text = ""
	small.TextTransparency = 1
	small.TextStrokeTransparency = 0.5
	small.ZIndex = 5
	small.Parent = screen
	captionLabel = small

	remotes.BossFx.OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler and type(data) == "table" then
			task.spawn(handler, data)
		end
	end)
	task.spawn(function()
		local events = workspace:FindFirstChild("Events") or workspace:WaitForChild("Events", 60)
		if events then
			watch(events)
		end
	end)
end

return BossFx
