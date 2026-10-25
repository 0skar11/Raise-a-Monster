--!strict
-- Local, cosmetic animation of equipped speed gear for every character (Motor6D.Transform is never replicated,
-- so each client drives it itself, the same way MonsterAnimate does for monsters).
-- The server builds the hubs in CharacterService (applyGearEffects); this file only moves them.
--
-- Hoverboard: the rider stands side-on (surf stance) on a board whose long axis follows the travel direction,
-- with its own idle sway, carving glide and a kick-flip jump. It is procedural on purpose: Roblox animation clips
-- have to be uploaded to the platform, which this project never does from here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GearAnimate = {}

type Cache = {
	Visuals: Model,
	Motors: { [string]: Motor6D },
	Emitters: { ParticleEmitter },
	Rates: { [ParticleEmitter]: number },
	Arcs: { BasePart },
	Glows: { BasePart },
	Phase: number,
	Smooth: number,
	Joints: { [string]: { Motor: Motor6D, C0: CFrame } },
	R6: boolean,
	Airborne: boolean,
	AirStart: number,
	LandAt: number,
	FlipSign: number,
	Lean: number,
	Side: number,
	Born: number,
	Base: { [Motor6D]: CFrame },
	PartColors: { [BasePart]: Color3 },
	Dirty: number?,
	Warned: boolean?,
	WingPhase: number,
	StepClock: number,
	StepSide: number,
	Connection: RBXScriptConnection?,
	WingParts: { { Part: BasePart, Color: Color3 } },
}

local caches: { [Model]: Cache } = {}
local sin, cos, clamp, pi = math.sin, math.cos, math.clamp, math.pi

local FEET_DROP = 3 -- distance from the root part to the soles, used as the pivot for leaning
local STANCE_YAW = pi / 2 -- the rider faces the side of the board

local JOINT_NAMES = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

local function captureJoints(character: Model, cache: Cache)
	for _, name in JOINT_NAMES do
		local existing = cache.Joints[name]
		if not existing or not existing.Motor.Parent then
			local joint = character:FindFirstChild(name, true)
			if joint and joint:IsA("Motor6D") then
				cache.Joints[name] = { Motor = joint, C0 = joint.C0 }
			end
		end
	end
end

-- Indexes the gear model. Called again whenever new descendants arrive, because replication can deliver the
-- model in several batches (an early scan would miss e.g. the right wing). Original C0 values and emitter rates
-- are remembered the first time each object is seen, so a re-scan never mistakes an animated value for the original.
local function scan(cache: Cache)
	cache.Motors, cache.Emitters, cache.Arcs, cache.Glows, cache.WingParts = {}, {}, {}, {}, {}
	for _, item in cache.Visuals:GetDescendants() do
		if item:IsA("Motor6D") then
			cache.Motors[item.Name] = item
			if not cache.Base[item] then cache.Base[item] = item.C0 end
		elseif item:IsA("ParticleEmitter") then
			table.insert(cache.Emitters, item)
			if not cache.Rates[item] then cache.Rates[item] = item.Rate end
		elseif item:IsA("BasePart") then
			if item.Name == "GoldenWingFeather" or item.Name == "WingArm" then
				local known = cache.PartColors[item]
				if not known then known = item.Color; cache.PartColors[item] = known end
				table.insert(cache.WingParts, { Part = item, Color = known })
			end
			if item.Name == "LightningArc" or item.Name == "BootLightningEmblem" then table.insert(cache.Arcs, item) end
			if item.Name == "GlowingSole" or item.Name == "SneakerSideGlow" or item.Name == "VoidEngine" or item.Name == "BoardFootPad" then table.insert(cache.Glows, item) end
		end
	end
end

local function build(character: Model, visuals: Model): Cache
	local cache: Cache = {
		Visuals = visuals, Motors = {}, Emitters = {}, Rates = {}, Arcs = {}, Glows = {},
		Phase = math.random() * 10, Smooth = 0, Joints = {}, R6 = true,
		Airborne = false, AirStart = 0, LandAt = -10, FlipSign = 1, Lean = 0, Side = 1, Born = os.clock(), WingParts = {}, Base = {},
		PartColors = {}, WingPhase = 0, StepClock = 0, StepSide = 1, Dirty = os.clock(), Connection = nil,
	}
	scan(cache)
	cache.Connection = visuals.DescendantAdded:Connect(function() cache.Dirty = os.clock() end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	cache.R6 = humanoid == nil or humanoid.RigType == Enum.HumanoidRigType.R6
	return cache
end

-- Puts the body joints back when the gear is removed or the cache is dropped.
local function release(cache: Cache)
	if cache.Connection then cache.Connection:Disconnect(); cache.Connection = nil end
	for _, entry in cache.Joints do
		if entry.Motor.Parent then entry.Motor.C0 = entry.C0 end
	end
end

-- Motor6D.Transform did not take effect on these gear hubs, so each frame we offset C0 instead
-- (the same thing the rider joints already use) relative to the C0 recorded when the cache was built.
local function drive(cache: Cache, motor: Motor6D, offset: CFrame)
	local base = cache.Base[motor]
	if base then motor.C0 = base * offset end
end

-- Ground effects that follow each footstep of the footwear gear (visible to everyone: every client runs this).
local function groundPoint(character: Model, foot: BasePart): Vector3
	local origin = foot.Position
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(origin, Vector3.new(0, -6, 0), params)
	return if result then result.Position + Vector3.new(0, 0.06, 0) else origin - Vector3.new(0, foot.Size.Y / 2, 0)
end

local function effectPart(position: Vector3, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false; part.CastShadow = false
	part.Size = size; part.Position = position; part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Shape = shape or Enum.PartType.Block
	part.Parent = workspace
	return part
end

local function burst(position: Vector3, texture: string, color: ColorSequence, count: number, speed: NumberRange)
	local holder = effectPart(position, Vector3.one * 0.2, Color3.new(1, 1, 1))
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture; emitter.Color = color; emitter.LightEmission = 1; emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.7); emitter.Speed = speed; emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 1)
end

local function ringAt(position: Vector3, color: Color3, startSize: number, endSize: number, life: number)
	local ring = effectPart(position, Vector3.new(0.12, startSize, startSize), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.15
	TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, endSize, endSize), Transparency = 1 }):Play()
	Debris:AddItem(ring, life + 0.1)
end

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function footstep(character: Model, gear: string, direction: Vector3, side: number)
	local foot = character:FindFirstChild(if side > 0 then "Right Leg" else "Left Leg") :: BasePart?
	if not foot then return end
	local at = groundPoint(character, foot)
	if gear == "FlameBoots" then
		-- Burning footprint that smoulders for a moment.
		local print_ = effectPart(at, Vector3.new(1.0, 0.05, 1.7), Color3.fromRGB(24, 14, 10), Enum.Material.Slate)
		print_.CFrame = CFrame.lookAt(at, at + direction)
		local glow = effectPart(at + Vector3.new(0, 0.02, 0), Vector3.new(0.7, 0.05, 1.35), Color3.fromRGB(255, 110, 30))
		glow.CFrame = print_.CFrame
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = FIRE; fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 80, 20)); fire.LightEmission = 1
		fire.Rate = 14; fire.Lifetime = NumberRange.new(0.4, 0.8); fire.Speed = NumberRange.new(1, 2.5); fire.Acceleration = Vector3.new(0, 3, 0)
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }); fire.Parent = glow
		TweenService:Create(glow, TweenInfo.new(1.4), { Transparency = 1 }):Play()
		TweenService:Create(print_, TweenInfo.new(1.6), { Transparency = 1 }):Play()
		task.delay(0.9, function() fire.Enabled = false end)
		Debris:AddItem(print_, 1.8); Debris:AddItem(glow, 1.8)
		burst(at, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 80, 20)), 8, NumberRange.new(3, 7))
	elseif gear == "LightningBoots" then
		ringAt(at, Color3.fromRGB(255, 232, 110), 1.2, 7, 0.4)
		burst(at, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 246, 170), Color3.fromRGB(255, 205, 40)), 10, NumberRange.new(5, 11))
		-- a short forked bolt striking the ground
		local bolt = effectPart(at + Vector3.new(0, 1.2, 0), Vector3.new(0.12, 2.4, 0.12), Color3.fromRGB(255, 250, 190))
		bolt.CFrame = CFrame.new(at + Vector3.new(0, 1.2, 0)) * CFrame.Angles(math.rad(math.random(-14, 14)), 0, math.rad(math.random(-14, 14)))
		TweenService:Create(bolt, TweenInfo.new(0.18), { Transparency = 1 }):Play()
		Debris:AddItem(bolt, 0.25)
	elseif gear == "SwiftSneakers" then
		ringAt(at, Color3.fromRGB(80, 220, 255), 1, 6, 0.35)
		burst(at, SPARKLES, ColorSequence.new(Color3.fromRGB(190, 250, 255), Color3.fromRGB(60, 190, 255)), 12, NumberRange.new(6, 12))
	elseif gear == "WitchBoots" then
		-- a short-lived pumpkin-orange witch sigil (disc, ring and a crossed star) where the heel struck
		local orange, violet = Color3.fromRGB(255, 132, 28), Color3.fromRGB(190, 110, 255)
		local disc = effectPart(at, Vector3.new(0.06, 3.4, 3.4), orange, Enum.Material.Neon, Enum.PartType.Cylinder)
		disc.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
		disc.Transparency = 0.55
		TweenService:Create(disc, TweenInfo.new(1.1), { Transparency = 1 }):Play()
		Debris:AddItem(disc, 1.2)
		for i = 0, 2 do
			local bar = effectPart(at + Vector3.new(0, 0.04, 0), Vector3.new(0.1, 0.05, 3.1), violet)
			bar.CFrame = CFrame.new(at + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, math.rad(i * 60 + math.random(0, 20)), 0)
			bar.Transparency = 0.2
			TweenService:Create(bar, TweenInfo.new(0.9), { Transparency = 1 }):Play()
			Debris:AddItem(bar, 1)
		end
		ringAt(at, orange, 0.8, 6.5, 0.45)
		burst(at, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 200, 100), violet), 12, NumberRange.new(4, 9))
	elseif gear == "IceSkates" then
		-- a thin frost line where the blade cut the ice
		local line = effectPart(at, Vector3.new(0.12, 0.04, 3.2), Color3.fromRGB(215, 245, 255))
		line.CFrame = CFrame.lookAt(at - direction * 1.2, at - direction * 1.2 + direction)
		line.Transparency = 0.25
		TweenService:Create(line, TweenInfo.new(1.1), { Transparency = 1 }):Play()
		Debris:AddItem(line, 1.2)
		burst(at, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 225, 255)), 10, NumberRange.new(2, 6))
	end
end

local function ease(u: number): number
	return 1 - (1 - u) * (1 - u)
end

local FLIP_ANGLE = math.rad(380) -- one full turn plus 20 degrees that settle back as the board lands
local FLIP_TIME = 0.5
local AIR_TIME = 0.62 -- jump power x1.22 -> about 0.62 s in the air
local SETTLE_TIME = 0.18

-- Matches the reference clip: the rider stands tall and relaxed, side-on to the travel direction. On a jump the
-- arms fly up, the rider rises and the board stays lower, flipping around its long axis (380 degrees) and the
-- rider lands back on it.
local function hoverboard(character: Model, cache: Cache, root: BasePart, flat: Vector3, energy: number, moving: boolean, clock: number, pulse: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		-- The pose is fully procedural, so no stock clip may fight it.
		for _, track in animator:GetPlayingAnimationTracks() do track:Stop(0.05) end
	end

	local airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air and root.AssemblyLinearVelocity.Y > -80
	if airborne and not cache.Airborne then
		cache.AirStart = clock
		cache.FlipSign = if math.random() < 0.5 then 1 else -1
	elseif not airborne and cache.Airborne then
		cache.LandAt = clock
	end
	cache.Airborne = airborne
	local airTime = if airborne then clock - cache.AirStart else 0
	local landTime = clock - cache.LandAt
	local u = clamp(airTime / AIR_TIME, 0, 1)

	local localVelocity = root.CFrame:VectorToObjectSpace(flat)
	local forward = clamp(-localVelocity.Z / 30, -1, 1)
	local sideways = clamp(localVelocity.X / 30, -1, 1)
	local idle = 1 - clamp(energy * 3, 0, 1)

	-- Board (hub is under the feet). In the air it drops away below the rider, tips nose-up, flips and returns.
	local rock = sin(clock * 1.6) * 0.025 * idle
	local shiver = -0.03 * (0.5 + 0.5 * sin(clock * (5 + energy * 20))) * (1 - idle * 0.6)
	local drop, flip, nose = 0, 0, 0
	local armsUp = 0 -- 0 = relaxed, 1 = both arms thrown up
	if airborne then
		drop = -2.3 * sin(u * pi) ^ 0.8
		flip = FLIP_ANGLE * (1 - (1 - clamp(airTime / FLIP_TIME, 0, 1)) ^ 3) * cache.FlipSign
		nose = 0.38 * sin(clamp(airTime / 0.35, 0, 1) * pi)
		armsUp = clamp(airTime / 0.12, 0, 1)
	elseif landTime < SETTLE_TIME then
		local k = 1 - landTime / SETTLE_TIME
		flip = (FLIP_ANGLE - math.rad(360)) * k * cache.FlipSign
		shiver -= 0.1 * sin((1 - k) * pi)
		armsUp = k
	end
	local board = cache.Motors.BoardMotor
	if board then
		-- The board's long axis is local Z (built that way on the server): pitch = nose up, roll = flip/bank.
		drive(cache, board, CFrame.new(0, shiver + drop, 0)
			* CFrame.Angles(nose - forward * 0.06, 0, 0)
			* CFrame.Angles(0, 0, flip + rock - sideways * 0.12))
	end
	local ring = cache.Motors.HoverRingMotor
	if ring then
		drive(cache, ring, CFrame.Angles(0, clock * (2 + energy * 14), 0) * CFrame.new(0, -0.05 * pulse, 0))
	end

	-- Rider: stands upright and relaxed, turned side-on (the root joint carries torso, head, arms and legs).
	captureJoints(character, cache)
	local rootJoint = cache.Joints.RootJoint
	if not rootJoint or not cache.R6 then return end
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if torso then
		local facing = root.CFrame:VectorToObjectSpace(torso.CFrame.LookVector)
		if math.abs(facing.X) > 0.2 then cache.Side = if facing.X > 0 then 1 else -1 end
	end
	local breathe = 0.015 * sin(clock * 1.6) * idle
	cache.Lean += ((breathe + (if airborne then 0.05 else 0)) - cache.Lean) * 0.2
	local pivot = CFrame.new(0, -FEET_DROP, 0) * CFrame.Angles(-forward * 0.05, 0, -cache.Lean * cache.Side) * CFrame.new(0, FEET_DROP, 0)
	rootJoint.Motor.C0 = pivot * rootJoint.C0 * CFrame.Angles(0, 0, -STANCE_YAW)

	-- Arms hang slightly away from the body (a little sway), then fly up on a jump.
	local armOut = 0.28 + 0.06 * sin(clock * 1.6 + 1) + armsUp * 1.95
	for _, name in { "Left Shoulder", "Right Shoulder" } do
		local arm = cache.Joints[name]
		if arm then arm.Motor.C0 = arm.C0 * CFrame.Angles(-armOut, 0, 0) end
	end
	-- Feet shoulder-width apart on the two glowing pads; they come together a little in the air.
	local stance = 0.11 - armsUp * 0.07
	for _, name in { "Left Hip", "Right Hip" } do
		local hip = cache.Joints[name]
		if hip then hip.Motor.C0 = hip.C0 * CFrame.Angles(-stance, 0, 0) end
	end
	local neck = cache.Joints.Neck
	if neck then neck.Motor.C0 = neck.C0 end
end

local function step(character: Model, cache: Cache, gear: string, dt: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local pending = cache.Dirty
	if pending and os.clock() - pending > 0.25 then
		cache.Dirty = nil
		scan(cache) -- new parts finished arriving; pick them up
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	local moving = speed > 3
	cache.Smooth += (clamp(speed / 30, 0, 1.4) - cache.Smooth) * math.min(1, dt * 8)
	local energy = cache.Smooth
	cache.Phase += dt * (3 + energy * 9)
	local t = cache.Phase
	local clock = os.clock()

	-- Particles only run while the player moves (boots) or always (aura gear).
	local alwaysOn = gear == "VoidHoverboard" or gear == "ShadowCloak" or gear == "GoldenWings" or gear == "WindScarf" or gear == "PhantomCloak" or gear == "PumpkinKingWings"
	for _, emitter in cache.Emitters do
		emitter.Rate = if alwaysOn then cache.Rates[emitter] * (1 + energy) elseif moving then cache.Rates[emitter] * (1 + energy * 1.5) else 0
	end

	if gear == "LightningBoots" or gear == "SwiftSneakers" then
		for _, arc in cache.Arcs do arc.Transparency = if moving and math.random() < 0.45 then 0.85 else 0 end
	end
	local pulse = 0.5 + 0.5 * sin(clock * 6)
	for _, glow in cache.Glows do glow.Transparency = 0.25 * (1 - pulse) * (if moving then 1 else 0.4) end

	if moving and (gear == "FlameBoots" or gear == "LightningBoots" or gear == "SwiftSneakers" or gear == "IceSkates" or gear == "WitchBoots") then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
			cache.StepClock += dt
			local interval = clamp(0.34 - energy * 0.14, 0.18, 0.34)
			if cache.StepClock >= interval then
				cache.StepClock = 0
				cache.StepSide = -cache.StepSide
				footstep(character, gear, flat.Unit, cache.StepSide)
			end
		end
	end

	if gear == "VoidHoverboard" then
		hoverboard(character, cache, root, flat, energy, moving, clock, pulse)
	elseif gear == "GoldenWings" or gear == "PumpkinKingWings" then
		-- Materialise: the wings start folded up and white-hot, snap open, then cool to gold.
		local born = clock - cache.Born
		local open = ease(clamp(born / 0.9, 0, 1))
		local fold = (1 - open) * 1.45
		local flash = 1 - clamp(born / 1.5, 0, 1)
		if flash > 0 then
			for _, entry in cache.WingParts do entry.Part.Color = entry.Color:Lerp(Color3.fromRGB(255, 250, 230), flash * 0.85) end
		elseif cache.Born > 0 then
			for _, entry in cache.WingParts do entry.Part.Color = entry.Color end
			cache.Born = -1 -- finished; colours are back to normal
		end
		local amplitude = (0.07 + energy * 0.3) * (if gear == "PumpkinKingWings" then 1.35 else 1)
		-- Own, slower clock: about 0.25 flaps/s standing, rising to about 0.65 flaps/s at full speed.
		cache.WingPhase += dt * (1.6 + energy * 2.5)
		local flap = sin(cache.WingPhase) * amplitude
		local lift = sin(clock * 1.1) * 0.03 -- slow breathing
		local left, right = cache.Motors.WingMotorL or cache.Motors.KingWingL, cache.Motors.WingMotorR or cache.Motors.KingWingR
		if (not left or not right) and clock - cache.Born > 3 and not cache.Warned then
			cache.Warned = true
			local names = {}
			for name in cache.Motors do table.insert(names, name) end
			warn("[GearAnimate] wing motor missing. Found:", table.concat(names, ", "))
		end
		if left then drive(cache, left, CFrame.Angles(0.04 * flap, -0.1 * flap, flap + lift - fold)) end
		if right then drive(cache, right, CFrame.Angles(0.04 * flap, 0.1 * flap, -flap - lift + fold)) end
		local orbitL, orbitR = cache.Motors.WingOrbitL, cache.Motors.WingOrbitR
		local spin = clock * (3.2 + energy * 8) * open
		if orbitL then drive(cache, orbitL, CFrame.Angles(spin, 0, 0)) end
		if orbitR then drive(cache, orbitR, CFrame.Angles(-spin, 0, 0)) end
	elseif gear == "WindScarf" then
		for i = 0, 4 do
			local motor = cache.Motors["ScarfMotor" .. i]
			if motor then
				local wave = t * 0.9 - i * 0.9
				drive(cache, motor, CFrame.Angles(0.12 * sin(wave * 0.8) + energy * 0.25, 0.28 * sin(wave) * (0.6 + energy), 0.1 * cos(wave)))
			end
		end
		for i = 0, 2 do
			local motor = cache.Motors["ScarfFrontMotor" .. i]
			if motor then
				local wave = t * 0.7 - i * 0.8
				drive(cache, motor, CFrame.Angles(0.1 * sin(wave) - energy * 0.25, 0.08 * cos(wave), 0.12 * sin(wave * 0.8)))
			end
		end
		local swirl = cache.Motors.WindSwirlMotor
		if swirl then drive(cache, swirl, CFrame.Angles(0, clock * (1.6 + energy * 3), 0)) end
	elseif gear == "PhantomCloak" then
		-- tails ripple one after another, the wisps circle, and the ground mist turns slowly
		for i = 0, 5 do
			local motor = cache.Motors["PhantomTail" .. i]
			if motor then
				local wave = t * 0.8 - i * 0.7
				drive(cache, motor, CFrame.Angles(0.14 * sin(wave * 0.9) + energy * 0.5, 0.22 * sin(wave) * (0.5 + energy), 0.12 * cos(wave + i)))
			end
		end
		local orbit, mist = cache.Motors.PhantomOrbitMotor, cache.Motors.PhantomMistMotor
		if orbit then drive(cache, orbit, CFrame.Angles(0, clock * (1.4 + energy * 3), 0) * CFrame.new(0, 0.18 * sin(clock * 2.1), 0)) end
		if mist then drive(cache, mist, CFrame.Angles(0, -clock * (0.8 + energy), 0)) end
	elseif gear == "ShadowCloak" then
		local shards, ribbons = cache.Motors.ShadowOrbitMotor, cache.Motors.ShadowRibbonMotor
		if shards then drive(cache, shards, CFrame.Angles(0, clock * (1.3 + energy * 2), 0) * CFrame.new(0, 0.12 * sin(clock * 2), 0)) end
		if ribbons then drive(cache, ribbons, CFrame.Angles(0, -clock * 0.7, 0)) end
	end
end

local function drop(character: Model)
	local cache = caches[character]
	if cache then
		release(cache)
		caches[character] = nil
	end
end

function GearAnimate.Start()
	RunService.RenderStepped:Connect(function(dt: number)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local gear = character and character:GetAttribute("EquippedGear")
			if character and type(gear) == "string" then
				local visuals = character:FindFirstChild("GearVisual_" .. gear)
				local cache = caches[character]
				if visuals and visuals:IsA("Model") and visuals:GetAttribute("GearReady") then
					if not cache or cache.Visuals ~= visuals then
						if cache then release(cache) end
						cache = build(character, visuals)
						caches[character] = cache
					end
					step(character, cache, gear, dt)
				elseif cache then
					drop(character)
				end
			elseif character then
				drop(character)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then caches[player.Character] = nil end
	end)
end

return GearAnimate
