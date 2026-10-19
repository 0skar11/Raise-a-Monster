--!strict
-- كل اللاعبين بيلعبوا بشخصيات R6 من غير ما نحتاج نعمل Publish ونغيّر Game Settings:
-- بنحط Rig من نوع R6 كـ StarterCharacter، وبعدين نلبّسه شكل اللاعب نفسه (هدومه وإكسسواراته).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)

local CharacterService = {}

local descriptions: { [Player]: HumanoidDescription } = {}

local function getDescription(player: Player): HumanoidDescription?
	local cached = descriptions[player]
	if cached then
		return cached
	end
	if player.UserId <= 0 then
		return nil
	end
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if ok and result then
		descriptions[player] = result
		return result
	end
	return nil
end

function CharacterService.IsR6(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
end

-- بيلبّس شخصية الـ R6 شكل اللاعب. بيستنى، فشغّله في task.spawn.
function CharacterService.ApplyAppearance(player: Player, character: Model)
	local description = getDescription(player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not description or not humanoid or not character.Parent then
		return
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not ok then
		warn("[CharacterService] Could not apply appearance for", player.Name, err)
	end
end

-- سرعة المشي = Config.WalkSpeed × كل العوامل (شايل وحش، Speed Boost، ...)
local speedFactors: { [Player]: { [string]: number } } = {}
local healthBonuses: { [Player]: number } = {}

function CharacterService.UpdateSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = Config.WalkSpeed
	for _, factor in speedFactors[player] or {} do
		speed *= factor
	end
	humanoid.WalkSpeed = speed
end

function CharacterService.SetSpeedFactor(player: Player, reason: string, factor: number?)
	local factors = speedFactors[player]
	if not factors then
		factors = {}
		speedFactors[player] = factors
	end
	factors[reason] = factor
	CharacterService.UpdateSpeed(player)
end

function CharacterService.UpdateHealth(player: Player, refillOnSpawn: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local maximum = Config.PlayerBaseHealth + (healthBonuses[player] or 0)
	local health = humanoid.Health
	-- تبديل المعدات مايعالجش اللاعب؛ الملء الكامل للولادة الجديدة بس.
	humanoid.MaxHealth = maximum
	humanoid.Health = if refillOnSpawn and health > 0 then maximum else math.min(health, maximum)
end

-- Cosmetics are welded to the actual limbs and rebuilt on selection/respawn.
-- They never change the avatar's collision, movement physics or combat stats.
local function applyGearEffects(player: Player, selected: string?)
	local character = player.Character
	if not character then return end
	local old = {}
	for _, item in character:GetDescendants() do if item:GetAttribute("GearVFX") then table.insert(old, item) end end
	for _, item in old do item:Destroy() end
	character:SetAttribute("EquippedGear", selected)
	-- Hoverboard riders jump 1.5x higher (jump height grows with the square of the take-off speed).
	local jumper = character:FindFirstChildOfClass("Humanoid")
	if jumper then
		local baseJump = character:GetAttribute("BaseJumpPower")
		if type(baseJump) ~= "number" then baseJump = jumper.JumpPower; character:SetAttribute("BaseJumpPower", baseJump) end
		jumper.UseJumpPower = true
		jumper.JumpPower = (baseJump :: number) * (if selected == "VoidHoverboard" then math.sqrt(1.5) else 1)
	end
	local accessory = selected and Config.SpeedAccessories[selected]
	local root = character:FindFirstChild("HumanoidRootPart")
	if not selected or not accessory or not root or not root:IsA("BasePart") then return end
	local visuals = Instance.new("Model")
	visuals.Name = "GearVisual_" .. selected
	visuals:SetAttribute("GearVFX", true)
	-- Parented only after everything is built (end of this function): the whole model then reaches clients together,
	-- otherwise a client could cache a half-replicated model and animate only the parts that had arrived (one wing).
	local color = accessory.Color
	local dark = Color3.fromRGB(29, 30, 45)
	local function part(name: string, target: BasePart, size: Vector3, offset: CFrame, tint: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local item = Instance.new("Part")
		item.Name = name; item.Size = size; item.CFrame = target.CFrame * offset
		item.Color = tint; item.Material = material or Enum.Material.SmoothPlastic
		item.Shape = shape or Enum.PartType.Block
		item.TopSurface = Enum.SurfaceType.Smooth; item.BottomSurface = Enum.SurfaceType.Smooth
		item.Anchored = false; item.Massless = true; item.CanCollide = false; item.CanTouch = false; item.CanQuery = false
		item.Parent = visuals
		local weld = Instance.new("WeldConstraint"); weld.Name = "GearWeld"; weld.Part0 = target; weld.Part1 = item; weld.Parent = item
		return item
	end
	-- An invisible hub joined by a Motor6D; GearAnimate (client) drives Motor6D.Transform for movement.
	local function motorHub(name: string, parent: BasePart, offset: CFrame): BasePart
		local hub = Instance.new("Part")
		hub.Name = name .. "Hub"; hub.Size = Vector3.new(0.2, 0.2, 0.2); hub.Transparency = 1
		hub.CFrame = parent.CFrame * offset
		hub.Anchored = false; hub.Massless = true; hub.CanCollide = false; hub.CanTouch = false; hub.CanQuery = false
		hub.Parent = visuals
		local motor = Instance.new("Motor6D")
		motor.Name = name; motor.Part0 = parent; motor.Part1 = hub; motor.C0 = offset; motor.Parent = hub
		return hub
	end
	local function segment(name: string, target: BasePart, a: Vector3, b: Vector3, width: number, tint: Color3, material: Enum.Material?)
		return part(name, target, Vector3.new(width, width, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), tint, material)
	end
	local function particles(target: BasePart, texture: string, rate: number, size: number, position: Vector3?): (Attachment, ParticleEmitter)
		local attachment = Instance.new("Attachment"); attachment.Name = "GearEffect"; attachment:SetAttribute("GearVFX", true); attachment.Position = position or Vector3.zero; attachment.Parent = target
		local emitter = Instance.new("ParticleEmitter"); emitter.Name = "GearParticles"; emitter.Texture = texture; emitter.Color = ColorSequence.new(color)
		emitter.Rate = rate; emitter.Lifetime = NumberRange.new(0.6, 1.1); emitter.Speed = NumberRange.new(0.8, 2.2); emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.LightEmission = 0.65; emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }); emitter.Parent = attachment
		return attachment, emitter
	end
	local function trail(leg: BasePart, bottom: number)
		local a = Instance.new("Attachment"); a.Name = "GearTrailStart"; a:SetAttribute("GearVFX", true); a.Position = Vector3.new(0, bottom, 0.6); a.Parent = leg
		local b = Instance.new("Attachment"); b.Name = "GearTrailEnd"; b:SetAttribute("GearVFX", true); b.Position = a.Position + Vector3.new(0, 0.38, 0); b.Parent = leg
		local effect = Instance.new("Trail"); effect.Attachment0 = a; effect.Attachment1 = b; effect.Color = ColorSequence.new(color); effect.Lifetime = 0.22; effect.LightEmission = 0.8; effect.Transparency = NumberSequence.new(0.3, 1); effect.Parent = a
	end
	local function footwear(leg: BasePart)
		local y = -leg.Size.Y / 2
		local scale = math.clamp(leg.Size.X, 0.7, 1.3)
		local bootColor = if selected == "FlameBoots" then Color3.fromRGB(86, 48, 34)
			elseif selected == "IceSkates" then Color3.fromRGB(118, 214, 244)
			elseif selected == "SwiftSneakers" then Color3.fromRGB(26, 52, 138)
			elseif selected == "LightningBoots" then Color3.fromRGB(52, 55, 64)
			else dark
		local bootMaterial = if selected == "LightningBoots" then Enum.Material.Slate elseif selected == "IceSkates" then Enum.Material.Ice else Enum.Material.SmoothPlastic
		part("GlowingSole", leg, Vector3.new(1.16 * scale, 0.2, 1.83), CFrame.new(0, y + 0.01, -0.27), color, Enum.Material.Neon)
		part("BootToe", leg, Vector3.new(1.12 * scale, 0.49, 1.58), CFrame.new(0, y + 0.34, -0.31), bootColor, bootMaterial)
		part("BootAnkle", leg, Vector3.new(1.1 * scale, if selected == "SwiftSneakers" then 0.95 else 1.03, 1.08), CFrame.new(0, y + (if selected == "SwiftSneakers" then 0.88 else 0.74), 0.05), bootColor, bootMaterial)
		part("ToeCap", leg, Vector3.new(0.98 * scale, 0.17, 0.39), CFrame.new(0, y + 0.54, -0.89), if selected == "IceSkates" then Color3.fromRGB(217, 255, 255) else bootColor:Lerp(color, 0.35), bootMaterial)
		for i = 0, 2 do part("BootLace", leg, Vector3.new(0.71 * scale, 0.07, 0.09), CFrame.new(0, y + 0.63 + i * 0.12, -0.52), if selected == "SwiftSneakers" then color else Color3.fromRGB(202, 217, 227), if selected == "SwiftSneakers" then Enum.Material.Neon else Enum.Material.SmoothPlastic) end
		if selected == "SwiftSneakers" then
			-- High-top sneaker: neon cuff, neon laces, a wave stripe along each side.
			part("SneakerCuff", leg, Vector3.new(1.14 * scale, 0.08, 1.12), CFrame.new(0, y + 1.34, 0.05), color, Enum.Material.Neon)
			for _, x in { -0.57, 0.57 } do
				part("SneakerSideGlow", leg, Vector3.new(0.05, 0.11, 1.22), CFrame.new(x * scale, y + 0.36, -0.21), color, Enum.Material.Neon)
				for i = 0, 2 do
					part("SneakerStripe", leg, Vector3.new(0.05, 0.09, 0.5), CFrame.new(x * scale, y + 0.78 + math.sin(i * 1.6) * 0.1, -0.35 + i * 0.36) * CFrame.Angles(math.rad(if i % 2 == 0 then 18 else -18), 0, 0), color, Enum.Material.Neon)
				end
			end
			trail(leg, y)
		elseif selected == "FlameBoots" then
			for _, side in { -1, 1 } do
				for i = 0, 2 do
					part("FlameTongue", leg, Vector3.new(0.16, 0.45 + i * 0.16, 0.24), CFrame.new(side * 0.58 * scale, y + 0.44 + i * 0.16, -0.48 + i * 0.42) * CFrame.Angles(0, 0, side * math.rad(-20)), if i % 2 == 0 then Color3.fromRGB(255, 157, 31) else color, Enum.Material.Neon)
				end
				-- flame emblem on the outer side of the boot
				part("FlameEmblem", leg, Vector3.new(0.06, 0.55, 0.4), CFrame.new(side * 0.57 * scale, y + 0.82, -0.1) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
				part("FlameEmblemTip", leg, Vector3.new(0.06, 0.34, 0.22), CFrame.new(side * 0.57 * scale, y + 1.12, -0.2) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(255, 200, 70), Enum.Material.Neon)
			end
			local _, emitter = particles(leg, "rbxasset://textures/particles/fire_main.dds", 18, 1.15, Vector3.new(0, y + 0.45, 0.45)); emitter.Acceleration = Vector3.new(0, 3.2, 0)
			local _, embers = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 14, 0.35, Vector3.new(0, y + 0.2, 0.2)); embers.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 80, 20)); embers.Speed = NumberRange.new(2, 5)
		elseif selected == "IceSkates" then
			part("SkateBlade", leg, Vector3.new(0.16, 0.15, 2.08), CFrame.new(0, y - 0.34, -0.27), Color3.fromRGB(200, 249, 255), Enum.Material.Metal)
			part("SkateCurl", leg, Vector3.new(0.16, 0.42, 0.16), CFrame.new(0, y - 0.2, -1.3) * CFrame.Angles(math.rad(38), 0, 0), Color3.fromRGB(200, 249, 255), Enum.Material.Metal)
			for _, z in { -0.82, 0.4 } do part("SkateBladeSupport", leg, Vector3.new(0.22, 0.3, 0.22), CFrame.new(0, y - 0.17, z), Color3.fromRGB(129, 218, 244), Enum.Material.Ice) end
			-- Crystal facets: tilted ice chunks so the boot reads as faceted ice.
			for i = 0, 6 do
				local ax, az = math.sin(i * 2.3), math.cos(i * 1.7)
				local chunk = part("IceFacet", leg, Vector3.new(0.34 + (i % 3) * 0.12, 0.3 + (i % 2) * 0.2, 0.34 + (i % 4) * 0.08), CFrame.new(ax * 0.5 * scale, y + 0.4 + (i % 4) * 0.28, az * 0.6) * CFrame.Angles(math.rad(25 * ax), math.rad(40 * i), math.rad(30 * az)), Color3.fromRGB(165 + i * 6, 232, 255), Enum.Material.Ice)
				chunk.Transparency = 0.1
			end
			for _, side in { -1, 1 } do part("IceBootFacet", leg, Vector3.new(0.17, 0.88, 0.72), CFrame.new(side * 0.51 * scale, y + 0.78, 0.08) * CFrame.Angles(0, 0, side * math.rad(-18)), Color3.fromRGB(175, 245, 255), Enum.Material.Ice) end
			local _, sparkle = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 16, 0.55, Vector3.new(0, y + 0.15, 0.3)); sparkle.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255), Color3.fromRGB(150, 220, 255)); sparkle.Speed = NumberRange.new(1, 3)
			trail(leg, y - 0.25)
		elseif selected == "LightningBoots" then
			local bolt = { Vector3.new(0.23, y + 1.22, -0.51), Vector3.new(-0.18, y + 0.88, -0.53), Vector3.new(0.16, y + 0.87, -0.54), Vector3.new(-0.22, y + 0.52, -0.55) }
			for i = 1, #bolt - 1 do segment("BootLightningEmblem", leg, bolt[i], bolt[i + 1], 0.15, color, Enum.Material.Neon) end
			for _, side in { -1, 1 } do
				-- lightning emblem on the side of the boot
				local sideBolt = { Vector3.new(side * 0.57 * scale, y + 1.2, -0.05), Vector3.new(side * 0.57 * scale, y + 0.95, -0.3), Vector3.new(side * 0.57 * scale, y + 0.98, 0.05), Vector3.new(side * 0.57 * scale, y + 0.68, -0.22) }
				for i = 1, #sideBolt - 1 do segment("BootLightningEmblem", leg, sideBolt[i], sideBolt[i + 1], 0.13, color, Enum.Material.Neon) end
				local arc = { Vector3.new(side * 0.55, y + 0.6, 0.2), Vector3.new(side * 0.92, y + 0.95, 0.15), Vector3.new(side * 0.75, y + 1.2, 0.05), Vector3.new(side * 1.04, y + 1.42, -0.1) }
				for i = 1, #arc - 1 do segment("LightningArc", leg, arc[i], arc[i + 1], 0.045, Color3.fromRGB(233, 255, 171), Enum.Material.Neon) end
			end
			local _, spark = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 16, 0.45, Vector3.new(0, y + 0.3, 0.2)); spark.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 200, 40)); spark.Speed = NumberRange.new(2, 5)
			trail(leg, y)
		end
	end
	if selected == "SwiftSneakers" or selected == "FlameBoots" or selected == "IceSkates" or selected == "LightningBoots" then
		for _, names in { { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } } do
			local foot = character:FindFirstChild(names[1]) or character:FindFirstChild(names[2])
			if foot and foot:IsA("BasePart") then footwear(foot) end
		end
	elseif selected == "ShadowCloak" then
		local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or root
		if not torso:IsA("BasePart") then torso = root end
		for _, side in { -1, 1 } do
			part("CloakShoulderMantle", torso, Vector3.new(1.35, 0.3, 1.22), CFrame.new(side * 0.79, 0.68, 0.2) * CFrame.Angles(0, 0, side * math.rad(-13)), Color3.fromRGB(19, 14, 29), Enum.Material.Fabric)
			part("RaisedCloakCollar", torso, Vector3.new(0.28, 1.14, 1.05), CFrame.new(side * 0.78, 1.03, 0.46) * CFrame.Angles(0, 0, side * math.rad(-28)), Color3.fromRGB(37, 19, 58), Enum.Material.Fabric)
			for panel = 0, 2 do
				local x = side * (0.27 + panel * 0.4)
				local length = 3.25 - panel * 0.24
				part("SplitCloakTail", torso, Vector3.new(0.48, length, 0.2), CFrame.new(x, -length / 2 + 0.45, 0.69 + panel * 0.12) * CFrame.Angles(math.rad(9 + panel * 4), 0, side * math.rad(5)), if panel % 2 == 0 then Color3.fromRGB(23, 14, 37) else Color3.fromRGB(42, 22, 66), Enum.Material.Fabric)
				part("VioletCloakLining", torso, Vector3.new(0.07, length - 0.15, 0.22), CFrame.new(x + side * 0.2, -length / 2 + 0.45, 0.7 + panel * 0.12) * CFrame.Angles(math.rad(9 + panel * 4), 0, side * math.rad(5)), color, Enum.Material.Fabric)
			end
			part("CloakClasp", torso, Vector3.new(0.29, 0.29, 0.18), CFrame.new(side * 0.6, 0.53, -0.57), Color3.fromRGB(135, 111, 176), Enum.Material.Metal, Enum.PartType.Ball)
		end
		segment("CloakChain", torso, Vector3.new(-0.6, 0.53, -0.59), Vector3.new(0, 0.37, -0.64), 0.09, Color3.fromRGB(89, 77, 120), Enum.Material.Metal)
		segment("CloakChain", torso, Vector3.new(0, 0.37, -0.64), Vector3.new(0.6, 0.53, -0.59), 0.09, Color3.fromRGB(89, 77, 120), Enum.Material.Metal)
		-- Broken violet rings and black shards create a visibly stronger final aura.
		local ribbonHub = motorHub("ShadowRibbonMotor", root, CFrame.identity)
		local shardHub = motorHub("ShadowOrbitMotor", root, CFrame.identity)
		for layer = 1, 2 do
			for i = 0, 15 do
				if i % 5 ~= 0 then
					local angle = i * math.pi / 8 + layer * 0.7
					local a = Vector3.new(math.cos(angle) * (2.1 + layer * 0.2), -0.8 + layer * 1.1 + math.sin(angle) * 0.22, math.sin(angle) * 1.45)
					local b = Vector3.new(math.cos(angle + 0.3) * (2.1 + layer * 0.2), -0.8 + layer * 1.1 + math.sin(angle + 0.3) * 0.22, math.sin(angle + 0.3) * 1.45)
					local ring = segment("ShadowAuraRibbon", ribbonHub, a, b, 0.075, if layer == 1 then color else Color3.fromRGB(73, 23, 126), Enum.Material.Neon); ring.Transparency = 0.15
				end
			end
		end
		for i = 0, 7 do
			local angle = i * math.pi / 4
			part("OrbitingShadowShard", shardHub, Vector3.new(0.2, 0.4 + i % 3 * 0.12, 0.11), CFrame.new(math.cos(angle) * 2.1, -1 + i % 4, math.sin(angle) * 1.4) * CFrame.Angles(0, angle, math.rad(35)), Color3.fromRGB(25, 11, 43), Enum.Material.Neon)
		end
		for _, x in { -1.35, 0, 1.35 } do
			local _, emitter = particles(root, "rbxasset://textures/particles/smoke_main.dds", 12, 3.8, Vector3.new(x, -0.8, 0.55)); emitter.Color = ColorSequence.new(Color3.fromRGB(13, 5, 24), color); emitter.SpreadAngle = Vector2.new(180, 180); emitter.Acceleration = Vector3.new(0, 1.5, 0); emitter.Lifetime = NumberRange.new(1.2, 2)
		end
		particles(root, "rbxasset://textures/particles/sparkles_main.dds", 14, 0.55)
		-- Reference details: glowing violet trim down both front edges, tall pointed collar tips,
		-- and a low shadow mist that pools around the feet.
		for _, side in { -1, 1 } do
			part("CloakFrontTrim", torso, Vector3.new(0.09, 3.3, 0.1), CFrame.new(side * 0.44, -1.15, -0.63), color, Enum.Material.Neon)
			part("CloakCollarTip", torso, Vector3.new(0.2, 0.7, 0.5), CFrame.new(side * 0.82, 1.6, 0.35) * CFrame.Angles(math.rad(-15), 0, side * math.rad(-22)), color, Enum.Material.Neon)
		end
		local _, mist = particles(root, "rbxasset://textures/particles/smoke_main.dds", 24, 3.4, Vector3.new(0, -2.8, 0))
		mist.Color = ColorSequence.new(Color3.fromRGB(14, 6, 26), Color3.fromRGB(110, 50, 190)); mist.SpreadAngle = Vector2.new(90, 180)
		mist.Speed = NumberRange.new(2, 4); mist.Lifetime = NumberRange.new(1, 1.6); mist.Acceleration = Vector3.new(0, 0.4, 0)
		local highlight = Instance.new("Highlight"); highlight.Name = "ShadowAuraHighlight"; highlight:SetAttribute("GearVFX", true); highlight.FillColor = Color3.fromRGB(37, 11, 61); highlight.FillTransparency = 0.82; highlight.OutlineColor = color; highlight.OutlineTransparency = 0.38; highlight.DepthMode = Enum.HighlightDepthMode.Occluded; highlight.Parent = character
	elseif selected == "VoidHoverboard" then
		-- Same design as before; the board hub bobs/tilts and the wake ring spins (see GearAnimate).
		local board = motorHub("BoardMotor", root, CFrame.new(0, -2.95, 0))
		local y = 0
		-- The long axis points along the travel direction (root -Z). Built that way here, not rotated at runtime,
		-- so the board is right even before any client animation runs.
		local face = CFrame.Angles(0, math.pi / 2, 0)
		part("HoverboardDeck", board, Vector3.new(4.1, 0.24, 1.75), face * CFrame.new(0, y, 0), dark, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			part("HoverboardNose", board, Vector3.new(0.67, 0.3, 1.42), face * CFrame.new(side * 2.1, y + 0.13, 0) * CFrame.Angles(0, 0, side * math.rad(18)), Color3.fromRGB(57, 35, 81), Enum.Material.Metal)
			part("BoardFootPad", board, Vector3.new(1.45, 0.08, 1.3), face * CFrame.new(side * 1.0, y + 0.19, 0), color, Enum.Material.Neon)
			part("VoidEngine", board, Vector3.new(1.38, 0.12, 0.78), face * CFrame.new(side * 1.18, y - 0.2, 0), color, Enum.Material.Neon)
		end
		for _, z in { -0.85, 0.85 } do part("HoverboardLightStrip", board, Vector3.new(3.82, 0.09, 0.07), face * CFrame.new(0, y - 0.06, z), color, Enum.Material.Neon) end
		local wake = motorHub("HoverRingMotor", board, CFrame.new(0, -0.43, 0) * face)
		for i = 0, 15 do
			local a = i * math.pi / 8
			local b = a + math.pi / 8
			local ring = segment("HoverWakeRing", wake, Vector3.new(math.cos(a) * 2.35, 0, math.sin(a) * 1.25), Vector3.new(math.cos(b) * 2.35, 0, math.sin(b) * 1.25), 0.07, color, Enum.Material.Neon); ring.Transparency = 0.25
		end
		local _, emitter = particles(board, "rbxasset://textures/particles/sparkles_main.dds", 14, 0.7, Vector3.new(0, y - 0.35, 0)); emitter.SpreadAngle = Vector2.new(180, 180); emitter.Speed = NumberRange.new(0.2, 0.8)
		-- Pink ribbon that streams behind the board (the board's short axis is the ribbon width).
		local ribbonA = Instance.new("Attachment"); ribbonA.Name = "HoverTrailA"; ribbonA:SetAttribute("GearVFX", true); ribbonA.Position = Vector3.new(-0.7, y + 0.1, 1.9); ribbonA.Parent = board
		local ribbonB = Instance.new("Attachment"); ribbonB.Name = "HoverTrailB"; ribbonB:SetAttribute("GearVFX", true); ribbonB.Position = Vector3.new(0.7, y + 0.1, 1.9); ribbonB.Parent = board
		local ribbon = Instance.new("Trail"); ribbon.Name = "HoverRibbon"; ribbon.Attachment0 = ribbonA; ribbon.Attachment1 = ribbonB
		ribbon.Color = ColorSequence.new(color, Color3.fromRGB(255, 190, 245)); ribbon.Lifetime = 0.7; ribbon.LightEmission = 1; ribbon.MinLength = 0.05
		ribbon.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }); ribbon.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.4) }); ribbon.Parent = ribbonA
		local underglow = Instance.new("PointLight"); underglow.Name = "HoverUnderglow"; underglow:SetAttribute("GearVFX", true); underglow.Color = color; underglow.Range = 12; underglow.Brightness = 1.4; underglow.Shadows = false; underglow.Parent = board
	elseif selected == "GoldenWings" then
		-- Reference design: a mounted pair of large swept wings. A curved golden leading edge carries three
		-- overlapping feather rows (long primaries, secondaries, short coverts) that darken towards the body.
		local deep, mid, light = Color3.fromRGB(196, 140, 36), Color3.fromRGB(230, 180, 64), Color3.fromRGB(250, 214, 112)
		part("WingMount", root, Vector3.new(1.3, 1.4, 0.25), CFrame.new(0, 0.55, 0.6), Color3.fromRGB(176, 128, 34), Enum.Material.Metal)
		part("WingMountCrest", root, Vector3.new(0.62, 0.62, 0.18), CFrame.new(0, 0.55, 0.8) * CFrame.Angles(0, 0, math.rad(45)), light, Enum.Material.Neon)
		for _, side in { -1, 1 } do
			local wing = motorHub(if side < 0 then "WingMotorL" else "WingMotorR", root, CFrame.new(side * 0.8, 0.9, 0.75))
			local p1, p2 = Vector3.new(side * 1.1, 1.65, 0.1), Vector3.new(side * 3.2, 1.8, 0.3)
			local function arm(t: number): Vector3
				return Vector3.zero:Lerp(p1, t):Lerp(p1:Lerp(p2, t), t)
			end
			local previous = arm(0)
			for i = 1, 5 do
				local nextPoint = arm(i / 5)
				segment("WingArm", wing, previous, nextPoint, 0.22 - i * 0.02, light, Enum.Material.Metal)
				previous = nextPoint
			end
			local rows = {
				{ count = 8, length = 2.5, width = 0.46, tint = light, drop = 0 },
				{ count = 7, length = 1.75, width = 0.42, tint = mid, drop = 0.16 },
				{ count = 6, length = 1.05, width = 0.38, tint = deep, drop = 0.3 },
			}
			for rowIndex, row in rows do
				for j = 0, row.count - 1 do
					local t = (j + 0.5) / row.count
					local base = arm(t) - Vector3.new(0, row.drop, 0.05 * rowIndex)
					local angle = math.rad(18 + 88 * t + rowIndex * 3) -- from hanging down at the shoulder to sweeping up-out at the tip
					local direction = Vector3.new(side * math.sin(angle), -math.cos(angle), 0.1 * t).Unit
					local length = row.length * (0.5 + 0.5 * t)
					local center = base + direction * (length / 2)
					part("GoldenWingFeather", wing, Vector3.new(row.width, 0.06, length), CFrame.lookAt(center, center + direction, Vector3.zAxis), row.tint:Lerp(deep, (1 - t) * 0.25), Enum.Material.Metal)
					if rowIndex == 1 and j % 2 == 0 then
						-- glowing spine along every other primary feather
						local lifted = center + Vector3.new(0, 0, 0.04)
						part("WingRib", wing, Vector3.new(0.05, 0.05, length * 0.9), CFrame.lookAt(lifted, lifted + direction, Vector3.zAxis), Color3.fromRGB(255, 240, 170), Enum.Material.Neon)
					end
				end
			end
			-- Ornate spiral crest at the root of each wing (as in the reference), plus a glittering trail from the tip.
			local spiralPrevious: Vector3? = nil
			for i = 0, 7 do
				local angle = i * 0.6
				local radius = 0.42 - i * 0.04
				local point = Vector3.new(side * (0.2 + math.cos(angle) * radius + i * 0.05), 0.2 + math.sin(angle) * radius, 0.12)
				if spiralPrevious then segment("WingSpiral", wing, spiralPrevious, point, 0.08, light, Enum.Material.Neon) end
				spiralPrevious = point
			end
			local tip = part("WingTip", wing, Vector3.new(0.12, 0.12, 0.12), CFrame.new(arm(1)), light, Enum.Material.Neon, Enum.PartType.Ball)
			local tipA = Instance.new("Attachment"); tipA.Name = "WingTipA"; tipA:SetAttribute("GearVFX", true); tipA.Position = Vector3.new(0, 0.22, 0); tipA.Parent = tip
			local tipB = Instance.new("Attachment"); tipB.Name = "WingTipB"; tipB:SetAttribute("GearVFX", true); tipB.Position = Vector3.new(0, -0.22, 0); tipB.Parent = tip
			local tipTrail = Instance.new("Trail"); tipTrail.Name = "WingTipTrail"; tipTrail.Attachment0 = tipA; tipTrail.Attachment1 = tipB
			tipTrail.Color = ColorSequence.new(Color3.fromRGB(255, 244, 200), light); tipTrail.Lifetime = 0.9; tipTrail.LightEmission = 1; tipTrail.MinLength = 0.03
			tipTrail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }); tipTrail.Parent = tipA
			-- A bead orbits mid-wing and leaves a ring of light (animated in GearAnimate).
			local orbit = motorHub(if side < 0 then "WingOrbitL" else "WingOrbitR", wing, CFrame.new(side * 1.9, 1.2, 0))
			local bead = part("WingOrbitBead", orbit, Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.8, 0), light, Enum.Material.Neon, Enum.PartType.Ball)
			local ringA = Instance.new("Attachment"); ringA.Name = "WingRingA"; ringA:SetAttribute("GearVFX", true); ringA.Position = Vector3.new(-0.25, 0, 0); ringA.Parent = bead
			local ringB = Instance.new("Attachment"); ringB.Name = "WingRingB"; ringB:SetAttribute("GearVFX", true); ringB.Position = Vector3.new(0.25, 0, 0); ringB.Parent = bead
			local ring = Instance.new("Trail"); ring.Name = "WingRingTrail"; ring.Attachment0 = ringA; ring.Attachment1 = ringB
			ring.Color = ColorSequence.new(Color3.fromRGB(255, 244, 200), light); ring.Lifetime = 0.55; ring.LightEmission = 1; ring.MinLength = 0.03
			ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }); ring.Parent = ringA
			local _, sparkles = particles(wing, "rbxasset://textures/particles/sparkles_main.dds", 12, 0.5, Vector3.new(side * 1.8, 1.0, 0))
			sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 232, 150)); sparkles.Lifetime = NumberRange.new(1.2, 2); sparkles.SpreadAngle = Vector2.new(180, 180); sparkles.Speed = NumberRange.new(0.3, 1.4)
		end
		local glow = Instance.new("PointLight"); glow.Name = "WingGlow"; glow:SetAttribute("GearVFX", true); glow.Color = light; glow.Range = 10; glow.Brightness = 0.9; glow.Shadows = false; glow.Parent = root
	elseif selected == "WindScarf" then
		-- Thick wrap round the neck, one long tail over the chest, one streaming behind, and a wind swirl with leaves.
		for _, x in { -0.62, 0.62 } do part("WindScarfWrap", root, Vector3.new(0.7, 0.42, 1.3), CFrame.new(x * 0.9, 0.88, 0.02) * CFrame.Angles(0, 0, math.rad(x * 14)), color, Enum.Material.Fabric) end
		part("WindScarfCollar", root, Vector3.new(1.75, 0.34, 1.3), CFrame.new(0, 0.9, 0), color, Enum.Material.Fabric)
		part("WindScarfKnot", root, Vector3.new(0.6, 0.55, 0.45), CFrame.new(0.55, 0.65, -0.66), color:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Fabric)
		-- Back tail chain: each piece hinged on the previous one so the scarf ripples.
		local previous: BasePart = root
		local previousCFrame = CFrame.identity
		for i = 0, 4 do
			local at = CFrame.new(0.45 + i * 0.22, 0.75 - i * 0.12, 0.85 + i * 0.7) * CFrame.Angles(math.rad(i * 7), math.rad(-i * 8), 0) * CFrame.new(0, 0, -0.42)
			local hub = motorHub("ScarfMotor" .. i, previous, previousCFrame:Inverse() * at)
			local piece = part("WindScarfTail", hub, Vector3.new(0.78 - i * 0.04, 0.16, 0.9), CFrame.new(0, 0, 0.45), color, Enum.Material.Fabric)
			if i == 4 then piece.Size = Vector3.new(0.5, 0.16, 1.1) end
			previous, previousCFrame = hub, at
		end
		-- Front tail hanging down the chest.
		local frontPrevious: BasePart = root
		local frontCFrame = CFrame.identity
		for i = 0, 2 do
			local at = CFrame.new(-0.5 + i * 0.05, 0.6 - i * 0.62, -0.68 - i * 0.04) * CFrame.Angles(math.rad(-4), 0, 0) * CFrame.new(0, 0.31, 0)
			local hub = motorHub("ScarfFrontMotor" .. i, frontPrevious, frontCFrame:Inverse() * at)
			part("WindScarfFrontTail", hub, Vector3.new(0.62 - i * 0.06, 0.66, 0.14), CFrame.new(0, -0.31, 0), color, Enum.Material.Fabric)
			frontPrevious, frontCFrame = hub, at
		end
		-- Wind swirl rings around the waist (spun by GearAnimate).
		local swirl = motorHub("WindSwirlMotor", root, CFrame.new(0, -0.6, 0))
		for ring = 0, 1 do
			for i = 0, 17 do
				if i % 6 ~= 5 then
					local a0 = i * math.pi / 9 + ring * 1.1
					local a1 = a0 + math.pi / 9
					local r = 2.1 + ring * 0.35
					local h = 0.3 + ring * 0.9
					local wind = segment("WindSwirlRing", swirl, Vector3.new(math.cos(a0) * r, h + math.sin(a0 * 2) * 0.15, math.sin(a0) * r), Vector3.new(math.cos(a1) * r, h + math.sin(a1 * 2) * 0.15, math.sin(a1) * r), 0.06, Color3.fromRGB(235, 248, 255), Enum.Material.Neon)
					wind.Transparency = 0.45
				end
			end
		end
		local _, leaves = particles(root, "rbxasset://textures/particles/sparkles_main.dds", 8, 0.7, Vector3.new(0, 0, 0)); leaves.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 230, 255)); leaves.SpreadAngle = Vector2.new(180, 180); leaves.Speed = NumberRange.new(2, 4); leaves.Lifetime = NumberRange.new(1.5, 2.5)
		local _, emitter = particles(root, "rbxasset://textures/particles/smoke_main.dds", 6, 0.8); emitter.Acceleration = Vector3.new(0, 2, -5)
	end
	visuals:SetAttribute("GearReady", true)
	visuals.Parent = character
end

function CharacterService.ApplySpeedAccessory(player: Player, owned: { [string]: boolean }, selected: string?)
	local accessory = selected and owned[selected] == true and Config.SpeedAccessories[selected]
	healthBonuses[player] = if accessory then accessory.HealthBonus else 0
	CharacterService.UpdateHealth(player)
	local multiplier = CharacterService.GetSpeedAccessoryMultiplier(owned, selected)
	CharacterService.SetSpeedFactor(player, "SpeedAccessory", if multiplier > 1 then multiplier else nil)
	applyGearEffects(player, if accessory then selected else nil)
end

function CharacterService.GetSpeedAccessoryMultiplier(owned: { [string]: boolean }, selected: string?): number
	local accessory = selected and owned[selected] == true and Config.SpeedAccessories[selected]
	return if accessory then accessory.Multiplier else 1
end

function CharacterService.Cleanup(player: Player)
	descriptions[player] = nil
	speedFactors[player] = nil
	healthBonuses[player] = nil
end

function CharacterService.Init()
	if StarterPlayer:FindFirstChild("StarterCharacter") then
		return
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if ok and rig then
		rig.Name = "StarterCharacter"
		rig.Parent = StarterPlayer
	else
		warn("[CharacterService] Could not create the R6 character:", rig)
	end
end

return CharacterService
