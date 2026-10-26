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

	-- Ordinary gear uses shaped solids and restrained emissive accents. All pieces still live in
	-- the one unpublished model so equipping/replication remains atomic.
	local function wedge(name: string, target: BasePart, size: Vector3, offset: CFrame, tint: Color3, material: Enum.Material?): WedgePart
		local item = Instance.new("WedgePart")
		item.Name = name; item.Size = size; item.CFrame = target.CFrame * offset
		item.Color = tint; item.Material = material or Enum.Material.SmoothPlastic
		item.TopSurface = Enum.SurfaceType.Smooth; item.BottomSurface = Enum.SurfaceType.Smooth
		item.Anchored = false; item.Massless = true; item.CanCollide = false; item.CanTouch = false; item.CanQuery = false
		item.Parent = visuals
		local weld = Instance.new("WeldConstraint"); weld.Name = "GearWeld"; weld.Part0 = target; weld.Part1 = item; weld.Parent = item
		return item
	end
	local function buildOrdinaryGear(): boolean
		if selected == "SwiftSneakers" or selected == "FlameBoots" or selected == "IceSkates" or selected == "LightningBoots" then
			for _, names in { { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } } do
				local leg = character:FindFirstChild(names[1]) or character:FindFirstChild(names[2])
				if not leg or not leg:IsA("BasePart") then continue end
				local y = -leg.Size.Y / 2
				local sx = math.clamp(leg.Size.X * 0.88, 0.62, 1.14)
				local function shoe(name: string, size: Vector3, position: Vector3, tint: Color3, material: Enum.Material?, rotation: CFrame?)
					return part(name, leg, Vector3.new(size.X * sx, size.Y, size.Z), CFrame.new(position.X * sx, y + position.Y, position.Z) * (rotation or CFrame.identity), tint, material)
				end
				if selected == "SwiftSneakers" then
					local navy, mesh, rubber = Color3.fromRGB(20, 39, 71), Color3.fromRGB(52, 89, 120), Color3.fromRGB(224, 237, 238)
					shoe("SneakerOutsole", Vector3.new(1.1, 0.14, 1.85), Vector3.new(0, 0.02, -0.27), navy)
					shoe("SneakerFoamMidsole", Vector3.new(1.12, 0.19, 1.77), Vector3.new(0, 0.17, -0.28), rubber)
					shoe("SneakerWovenUpper", Vector3.new(1.04, 0.45, 1.22), Vector3.new(0, 0.45, -0.11), mesh, Enum.Material.Fabric)
					wedge("SneakerSweptToe", leg, Vector3.new(1.04 * sx, 0.37, 0.69), CFrame.new(0, y + 0.44, -0.93), navy, Enum.Material.SmoothPlastic)
					shoe("SneakerHeelCounter", Vector3.new(1.07, 0.69, 0.22), Vector3.new(0, 0.59, 0.56), navy)
					shoe("SneakerPaddedCollar", Vector3.new(1.08, 0.22, 1.04), Vector3.new(0, 1.01, 0.08), navy, Enum.Material.Fabric)
					shoe("SneakerTongue", Vector3.new(0.48, 0.65, 0.14), Vector3.new(0, 0.8, -0.51), navy, Enum.Material.Fabric, CFrame.Angles(math.rad(-12), 0, 0))
					for i = 0, 3 do
						shoe("SneakerLace", Vector3.new(0.66, 0.045, 0.06), Vector3.new(0, 0.59 + i * 0.12, -0.59 + i * 0.026), rubber, Enum.Material.Fabric, CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 8 else -8)))
					end
					for _, side in { -1, 1 } do
						local a = Vector3.new(side * 0.545 * sx, y + 0.43, -0.86)
						local b = Vector3.new(side * 0.56 * sx, y + 0.56, -0.18)
						local c = Vector3.new(side * 0.545 * sx, y + 0.83, 0.28)
						segment("SneakerSideGlow", leg, a, b, 0.055, color, Enum.Material.Neon)
						segment("SneakerSideGlow", leg, b, c, 0.055, color, Enum.Material.Neon)
						shoe("SneakerHeelWing", Vector3.new(0.08, 0.48, 0.55), Vector3.new(side * 0.53, 0.72, 0.29), navy, Enum.Material.SmoothPlastic, CFrame.Angles(math.rad(-17), 0, 0))
						shoe("SneakerAirWindow", Vector3.new(0.04, 0.08, 0.45), Vector3.new(side * 0.568, 0.19, 0.25), color, Enum.Material.Neon)
					end
					for i = 0, 3 do shoe("SneakerTread", Vector3.new(0.98, 0.055, 0.12), Vector3.new(0, -0.07, -0.9 + i * 0.43), navy) end
					shoe("SneakerHeelPull", Vector3.new(0.17, 0.27, 0.1), Vector3.new(0, 1.12, 0.54), color, Enum.Material.Fabric)
					trail(leg, y)
				elseif selected == "FlameBoots" then
					local coal, armor, bronze = Color3.fromRGB(31, 27, 29), Color3.fromRGB(65, 46, 39), Color3.fromRGB(145, 83, 41)
					shoe("EmberTread", Vector3.new(1.13, 0.19, 1.88), Vector3.new(0, 0.02, -0.25), coal, Enum.Material.Slate)
					shoe("EmberBootCore", Vector3.new(1.03, 1.35, 1.06), Vector3.new(0, 0.77, 0.05), coal)
					shoe("EmberArmoredToe", Vector3.new(1.08, 0.43, 1.17), Vector3.new(0, 0.39, -0.45), armor, Enum.Material.Metal)
					wedge("EmberToeBevel", leg, Vector3.new(1.08 * sx, 0.32, 0.47), CFrame.new(0, y + 0.35, -1.07), bronze, Enum.Material.Metal)
					shoe("EmberShinPlate", Vector3.new(0.82, 0.8, 0.18), Vector3.new(0, 1.0, -0.57), armor, Enum.Material.Metal, CFrame.Angles(math.rad(-8), 0, 0))
					shoe("EmberShinCrest", Vector3.new(0.25, 0.27, 0.09), Vector3.new(0, 1.12, -0.69), color, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(45)))
					for _, side in { -1, 1 } do
						for i = 0, 2 do
							shoe("EmberLayeredScale", Vector3.new(0.13, 0.4, 0.76), Vector3.new(side * 0.54, 0.61 + i * 0.3, 0.04), if i % 2 == 0 then armor else bronze, Enum.Material.Metal, CFrame.Angles(math.rad(-13), 0, side * math.rad(-9)))
							shoe("EmberVent", Vector3.new(0.045, 0.07, 0.46), Vector3.new(side * 0.63, 0.59 + i * 0.3, -0.04), color, Enum.Material.Neon, CFrame.Angles(math.rad(-13), 0, 0))
						end
						shoe("EmberHeelExhaust", Vector3.new(0.28, 0.42, 0.23), Vector3.new(side * 0.34, 0.53, 0.68), bronze, Enum.Material.Metal)
						shoe("EmberExhaustCore", Vector3.new(0.16, 0.2, 0.05), Vector3.new(side * 0.34, 0.53, 0.81), Color3.fromRGB(255, 174, 52), Enum.Material.Neon)
					end
					for i = 0, 2 do shoe("EmberToeRidge", Vector3.new(0.93, 0.065, 0.09), Vector3.new(0, 0.65, -0.93 + i * 0.2), bronze, Enum.Material.Metal) end
					local _, fire = particles(leg, "rbxasset://textures/particles/fire_main.dds", 12, 0.75, Vector3.new(0, y + 0.45, 0.67)); fire.Acceleration = Vector3.new(0, 2.6, 0)
					local _, sparks = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 8, 0.25, Vector3.new(0, y + 0.2, 0.5)); sparks.Speed = NumberRange.new(1, 3)
				elseif selected == "IceSkates" then
					local blue, frost, steel = Color3.fromRGB(61, 126, 164), Color3.fromRGB(213, 242, 249), Color3.fromRGB(147, 174, 191)
					shoe("FrostSkateBoot", Vector3.new(1.01, 0.97, 1.06), Vector3.new(0, 0.77, 0.08), blue, Enum.Material.SmoothPlastic)
					shoe("FrostSkateToe", Vector3.new(1.04, 0.43, 1.45), Vector3.new(0, 0.38, -0.32), frost, Enum.Material.SmoothPlastic)
					wedge("FrostSweptToe", leg, Vector3.new(1.04 * sx, 0.3, 0.5), CFrame.new(0, y + 0.33, -1.14), blue, Enum.Material.Ice)
					shoe("FrostSole", Vector3.new(1.08, 0.13, 1.88), Vector3.new(0, 0.1, -0.24), blue)
					shoe("SkateBlade", Vector3.new(0.11, 0.15, 2.45), Vector3.new(0, -0.4, -0.3), steel, Enum.Material.Metal)
					shoe("SkateBladeEdge", Vector3.new(0.055, 0.04, 2.26), Vector3.new(0, -0.49, -0.26), frost, Enum.Material.Neon)
					for _, z in { -0.93, 0.4 } do
						shoe("SkateBladeBridge", Vector3.new(0.19, 0.38, 0.22), Vector3.new(0, -0.16, z), steel, Enum.Material.Metal)
					end
					wedge("SkateBladeNose", leg, Vector3.new(0.11, 0.28, 0.36), CFrame.new(0, y - 0.29, -1.59), steel, Enum.Material.Metal)
					for _, side in { -1, 1 } do
						for i = 0, 2 do
							wedge("FrostAnkleCrystal", leg, Vector3.new(0.24, 0.55 + i * 0.17, 0.45), CFrame.new(side * 0.51 * sx, y + 0.99 + i * 0.08, -0.24 + i * 0.31) * CFrame.Angles(0, side * math.rad(15), side * math.rad(-17)), frost:Lerp(color, i * 0.22), Enum.Material.Ice)
						end
						shoe("FrostSideInlay", Vector3.new(0.06, 0.085, 1.35), Vector3.new(side * 0.54, 0.35, -0.31), color, Enum.Material.Neon)
					end
					for i = 0, 3 do shoe("FrostLace", Vector3.new(0.54, 0.045, 0.065), Vector3.new(0, 0.64 + i * 0.13, -0.49), frost, Enum.Material.Fabric) end
					local _, snow = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 10, 0.35, Vector3.new(0, y - 0.3, 0.5)); snow.Speed = NumberRange.new(0.5, 2)
					trail(leg, y - 0.4)
				else
					local graphite, silver, insulation = Color3.fromRGB(34, 40, 53), Color3.fromRGB(113, 131, 151), Color3.fromRGB(15, 22, 33)
					shoe("StormRubberSole", Vector3.new(1.13, 0.18, 1.88), Vector3.new(0, 0.03, -0.25), insulation)
					shoe("StormBootCore", Vector3.new(1.04, 1.35, 1.05), Vector3.new(0, 0.8, 0.06), graphite)
					shoe("StormToeArmor", Vector3.new(1.09, 0.4, 1.32), Vector3.new(0, 0.39, -0.39), silver, Enum.Material.Metal)
					wedge("StormToeBevel", leg, Vector3.new(1.09 * sx, 0.31, 0.49), CFrame.new(0, y + 0.35, -1.08), graphite, Enum.Material.Metal)
					shoe("StormShinShield", Vector3.new(0.85, 0.99, 0.19), Vector3.new(0, 1.0, -0.56), silver, Enum.Material.Metal, CFrame.Angles(math.rad(-7), 0, 0))
					local bolt = { Vector3.new(0.18, y + 1.38, -0.69), Vector3.new(-0.17, y + 1.02, -0.7), Vector3.new(0.15, y + 1.04, -0.71), Vector3.new(-0.18, y + 0.64, -0.72) }
					for i = 1, #bolt - 1 do segment("BootLightningEmblem", leg, bolt[i], bolt[i + 1], 0.085, color, Enum.Material.Neon) end
					for _, side in { -1, 1 } do
						shoe("StormAnkleGuard", Vector3.new(0.16, 0.74, 0.83), Vector3.new(side * 0.55, 0.83, 0.07), graphite, Enum.Material.Metal, CFrame.Angles(0, 0, side * math.rad(-8)))
						part("StormCoil", leg, Vector3.new(0.11, 0.44, 0.44), CFrame.new(side * 0.66 * sx, y + 1.0, 0.1), silver, Enum.Material.Metal, Enum.PartType.Cylinder)
						part("StormCoilCore", leg, Vector3.new(0.13, 0.23, 0.23), CFrame.new(side * 0.67 * sx, y + 1.0, 0.1), color, Enum.Material.Neon, Enum.PartType.Cylinder)
						local arc = { Vector3.new(side * 0.69 * sx, y + 1.0, 0.05), Vector3.new(side * 0.88 * sx, y + 1.24, -0.08), Vector3.new(side * 0.76 * sx, y + 1.37, -0.2), Vector3.new(side * 0.91 * sx, y + 1.55, -0.1) }
						for i = 1, #arc - 1 do segment("LightningArc", leg, arc[i], arc[i + 1], 0.035, Color3.fromRGB(255, 243, 172), Enum.Material.Neon) end
						shoe("StormSoleChannel", Vector3.new(0.045, 0.055, 1.47), Vector3.new(side * 0.57, 0.12, -0.25), color, Enum.Material.Neon)
					end
					local _, sparks = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 9, 0.3, Vector3.new(0, y + 0.35, 0.3)); sparks.Speed = NumberRange.new(1, 4)
					trail(leg, y)
				end
			end
			return true
		elseif selected == "ShadowCloak" then
			local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or root
			if not torso:IsA("BasePart") then torso = root end
			local velvet, lining, silver = Color3.fromRGB(19, 15, 30), Color3.fromRGB(61, 32, 86), Color3.fromRGB(138, 122, 169)
			for _, side in { -1, 1 } do
				for layer = 0, 2 do
					part("ShadowLayeredMantle", torso, Vector3.new(0.72, 0.16, 1.25 - layer * 0.14), CFrame.new(side * (0.57 + layer * 0.25), 1.02 - layer * 0.22, 0.16) * CFrame.Angles(math.rad(8), 0, side * math.rad(-28)), if layer == 1 then lining else velvet, Enum.Material.Fabric)
				end
				wedge("ShadowHighCollar", torso, Vector3.new(0.28, 1.3, 1.0), CFrame.new(side * 0.82, 1.18, 0.36) * CFrame.Angles(0, 0, side * math.rad(-21)), velvet, Enum.Material.Fabric)
				for panel = 0, 2 do
					local length = 3.1 + (if panel == 1 then 0.4 else 0) - panel * 0.12
					local hub = motorHub("CloakTail" .. (if side < 0 then "L" else "R") .. panel, torso, CFrame.new(side * (0.23 + panel * 0.42), 0.75, 0.63 + panel * 0.08) * CFrame.Angles(math.rad(8 + panel * 4), 0, side * math.rad(5)))
					part("ShadowPleatedTail", hub, Vector3.new(0.48, length - 0.44, 0.15), CFrame.new(0, -(length - 0.44) / 2, 0), if panel % 2 == 0 then velvet else lining, Enum.Material.Fabric)
					wedge("ShadowTatteredHem", hub, Vector3.new(0.15, 0.48, 0.72), CFrame.fromMatrix(Vector3.new(0, -length + 0.2, 0), Vector3.zAxis, Vector3.xAxis, Vector3.yAxis), velvet, Enum.Material.Fabric)
					part("ShadowTailPiping", hub, Vector3.new(0.035, length - 0.32, 0.17), CFrame.new(side * 0.23, -length / 2 + 0.13, 0), color, Enum.Material.Neon)
				end
				part("ShadowFrontDrape", torso, Vector3.new(0.53, 2.5, 0.16), CFrame.new(side * 0.88, -0.48, -0.61) * CFrame.Angles(0, 0, side * math.rad(9)), velvet, Enum.Material.Fabric)
				part("ShadowDrapeLining", torso, Vector3.new(0.075, 2.36, 0.18), CFrame.new(side * 0.65, -0.48, -0.63) * CFrame.Angles(0, 0, side * math.rad(9)), lining, Enum.Material.Fabric)
			end
			part("ShadowGorget", torso, Vector3.new(0.65, 0.55, 0.17), CFrame.new(0, 0.71, -0.63) * CFrame.Angles(0, 0, math.rad(45)), silver, Enum.Material.Metal)
			part("ShadowGorgetGem", torso, Vector3.new(0.24, 0.34, 0.1), CFrame.new(0, 0.71, -0.75) * CFrame.Angles(0, 0, math.rad(45)), color, Enum.Material.Neon)
			for _, side in { -1, 1 } do segment("ShadowClaspChain", torso, Vector3.new(0, 0.66, -0.7), Vector3.new(side * 0.95, 0.95, -0.52), 0.065, silver, Enum.Material.Metal) end
			local orbit = motorHub("ShadowOrbitMotor", root, CFrame.identity)
			local ribbons = motorHub("ShadowRibbonMotor", root, CFrame.identity)
			for i = 0, 5 do
				local a = i * math.pi / 3
				wedge("OrbitingShadowShard", orbit, Vector3.new(0.17, 0.7, 0.32), CFrame.new(math.cos(a) * 2.2, -0.65 + i % 3 * 0.7, math.sin(a) * 1.6) * CFrame.Angles(0, a, math.rad(25)), lining, Enum.Material.Glass)
				if i % 2 == 0 then
					segment("ShadowAuraRibbon", ribbons, Vector3.new(math.cos(a) * 2.3, -2.7, math.sin(a) * 2.3), Vector3.new(math.cos(a + 0.7) * 2.3, -2.7, math.sin(a + 0.7) * 2.3), 0.045, color, Enum.Material.Neon)
				end
			end
			local _, mist = particles(root, "rbxasset://textures/particles/smoke_main.dds", 10, 2.8, Vector3.new(0, -2.6, 0)); mist.Color = ColorSequence.new(velvet, lining); mist.SpreadAngle = Vector2.new(90, 180); mist.Speed = NumberRange.new(0.6, 1.5)
			return true
		elseif selected == "VoidHoverboard" then
			local hull, rim, alloy = Color3.fromRGB(23, 20, 40), Color3.fromRGB(69, 42, 91), Color3.fromRGB(113, 101, 135)
			local board = motorHub("BoardMotor", root, CFrame.new(0, -2.95, 0))
			part("HoverboardDeck", board, Vector3.new(1.7, 0.2, 3.35), CFrame.new(0, 0, 0), hull, Enum.Material.Metal)
			for _, end_ in { -1, 1 } do
				wedge("HoverboardSweptTip", board, Vector3.new(1.7, 0.25, 0.88), CFrame.new(0, 0.02, end_ * 2.05) * CFrame.Angles(0, if end_ < 0 then 0 else math.pi, 0), rim, Enum.Material.Metal)
				part("BoardFootPad", board, Vector3.new(1.35, 0.055, 0.93), CFrame.new(0, 0.13, end_ * 0.95), Color3.fromRGB(48, 42, 64), Enum.Material.Slate)
				for i = -1, 1 do part("BoardGripTread", board, Vector3.new(1.12, 0.025, 0.045), CFrame.new(0, 0.17, end_ * 0.95 + i * 0.23), alloy, Enum.Material.Metal) end
				for _, side in { -1, 1 } do
					wedge("HoverboardSideFin", board, Vector3.new(0.22, 0.42, 0.8), CFrame.new(side * 0.88, -0.08, end_ * 1.45) * CFrame.Angles(0, if end_ > 0 then math.pi else 0, side * math.rad(-20)), rim, Enum.Material.Metal)
					part("VoidEngineHousing", board, Vector3.new(0.55, 0.4, 0.85), CFrame.new(side * 0.55, -0.29, end_ * 1.12), alloy, Enum.Material.Metal)
					part("VoidEngine", board, Vector3.new(0.35, 0.07, 0.62), CFrame.new(side * 0.55, -0.52, end_ * 1.12), color, Enum.Material.Neon)
				end
			end
			for _, side in { -1, 1 } do
				segment("HoverboardLightStrip", board, Vector3.new(side * 0.87, 0.0, -1.7), Vector3.new(side * 0.87, 0.0, 1.7), 0.045, color, Enum.Material.Neon)
			end
			part("VoidCentralReactor", board, Vector3.new(0.13, 0.68, 0.68), CFrame.new(0, -0.03, 0) * CFrame.Angles(0, 0, math.pi / 2), alloy, Enum.Material.Metal, Enum.PartType.Cylinder)
			part("VoidReactorCore", board, Vector3.new(0.15, 0.38, 0.38), CFrame.new(0, 0.015, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon, Enum.PartType.Cylinder)
			local wake = motorHub("HoverRingMotor", board, CFrame.new(0, -0.66, 0))
			for i = 0, 11 do
				if i % 4 ~= 3 then
					local a, b = i * math.pi / 6, (i + 0.8) * math.pi / 6
					local ring = segment("HoverWakeRing", wake, Vector3.new(math.cos(a) * 1.15, 0, math.sin(a) * 1.15), Vector3.new(math.cos(b) * 1.15, 0, math.sin(b) * 1.15), 0.045, color, Enum.Material.Neon); ring.Transparency = 0.3
				end
			end
			local a = Instance.new("Attachment"); a.Name = "HoverTrailA"; a.Position = Vector3.new(-0.55, -0.25, 2.15); a.Parent = board
			local b = Instance.new("Attachment"); b.Name = "HoverTrailB"; b.Position = Vector3.new(0.55, -0.25, 2.15); b.Parent = board
			local ribbon = Instance.new("Trail"); ribbon.Name = "HoverRibbon"; ribbon.Attachment0 = a; ribbon.Attachment1 = b; ribbon.Color = ColorSequence.new(color); ribbon.Lifetime = 0.6; ribbon.LightEmission = 0.8; ribbon.Transparency = NumberSequence.new(0.25, 1); ribbon.Parent = a
			local _, exhaust = particles(board, "rbxasset://textures/particles/sparkles_main.dds", 8, 0.35, Vector3.new(0, -0.4, 1.5)); exhaust.Speed = NumberRange.new(0.2, 0.7)
			return true
		elseif selected == "GoldenWings" then
			local deep, gold, ivory = Color3.fromRGB(125, 80, 29), Color3.fromRGB(220, 165, 61), Color3.fromRGB(255, 224, 145)
			part("WingMount", root, Vector3.new(0.92, 1.35, 0.28), CFrame.new(0, 0.5, 0.64), deep, Enum.Material.Metal)
			part("WingMountCrest", root, Vector3.new(0.55, 0.55, 0.12), CFrame.new(0, 0.65, 0.84) * CFrame.Angles(0, 0, math.pi / 4), gold, Enum.Material.Metal)
			part("WingMountGem", root, Vector3.new(0.2, 0.3, 0.08), CFrame.new(0, 0.65, 0.93), ivory, Enum.Material.Neon)
			for _, side in { -1, 1 } do
				local wing = motorHub(if side < 0 then "WingMotorL" else "WingMotorR", root, CFrame.new(side * 0.75, 0.85, 0.73))
				local function curve(t: number): Vector3
					return Vector3.new(side * (0.2 + 3.75 * t), 0.35 + 2.6 * t - 1.15 * t * t, 0.1 + t * 0.28)
				end
				for i = 1, 5 do segment("WingArm", wing, curve((i - 1) / 5), curve(i / 5), 0.14, gold, Enum.Material.Metal) end
				for row = 1, 3 do
					local count = if row == 1 then 8 elseif row == 2 then 6 else 5
					for i = 0, count - 1 do
						local t = (i + 0.4) / count
						local base = curve(t) + Vector3.new(0, -0.1 * row, -0.11 * row)
						local angle = math.rad(12 + t * 65)
						local direction = Vector3.new(side * math.sin(angle), -math.cos(angle), 0)
						local length = (if row == 1 then 3.15 elseif row == 2 then 2.15 else 1.25) * (0.72 + 0.28 * t)
						local width = if row == 1 then 0.78 elseif row == 2 then 0.7 else 0.64
						local tint = (if row == 1 then ivory elseif row == 2 then gold else deep):Lerp(gold, (1 - t) * 0.3)
						-- Explicit axes keep the broad feather face in the wing's XY plane.
						-- The thickness axis is depth; lookAt's up argument is not consistent in offline Roblox runtimes.
						local at = CFrame.fromMatrix(base + direction * length / 2, Vector3.new(direction.Y, -direction.X, 0), Vector3.zAxis, -direction)
						part("GoldenWingFeather", wing, Vector3.new(width, 0.085, length * 0.72), at * CFrame.new(0, 0, length * 0.14), tint, Enum.Material.Metal)
						wedge("GoldenFeatherPoint", wing, Vector3.new(0.085, width, length * 0.42), at * CFrame.new(0, 0, -length * 0.29) * CFrame.Angles(0, 0, math.pi / 2), tint, Enum.Material.Metal)
						if row == 1 then
							part("GoldenFeatherSpine", wing, Vector3.new(0.035, 0.1, length * 0.82), at, gold, Enum.Material.Metal)
						end
					end
				end
				local tip = part("WingTip", wing, Vector3.new(0.12, 0.12, 0.12), CFrame.new(curve(1)), ivory, Enum.Material.Neon, Enum.PartType.Ball)
				local a = Instance.new("Attachment"); a.Position = Vector3.new(0, 0.15, 0); a.Parent = tip
				local b = Instance.new("Attachment"); b.Position = Vector3.new(0, -0.15, 0); b.Parent = tip
				local trail_ = Instance.new("Trail"); trail_.Name = "WingTipTrail"; trail_.Attachment0 = a; trail_.Attachment1 = b; trail_.Color = ColorSequence.new(ivory); trail_.Lifetime = 0.65; trail_.LightEmission = 0.7; trail_.Transparency = NumberSequence.new(0.3, 1); trail_.Parent = a
				local _, dust = particles(wing, "rbxasset://textures/particles/sparkles_main.dds", 4, 0.3, curve(0.8)); dust.Color = ColorSequence.new(ivory); dust.Speed = NumberRange.new(0.2, 0.6)
			end
			return true
		elseif selected == "WindScarf" then
			local cloth, fold, trim = Color3.fromRGB(181, 218, 225), Color3.fromRGB(126, 176, 189), Color3.fromRGB(237, 247, 237)
			for layer = 0, 2 do
				part("WindScarfFold", root, Vector3.new(1.75 - layer * 0.07, 0.18, 1.34), CFrame.new(0, 0.81 + layer * 0.16, 0.03) * CFrame.Angles(math.rad(4), 0, math.rad(-7 + layer * 5)), if layer == 1 then fold else cloth, Enum.Material.Fabric)
			end
			part("WindScarfKnot", root, Vector3.new(0.57, 0.48, 0.45), CFrame.new(0.62, 0.75, -0.66) * CFrame.Angles(math.rad(10), 0, math.rad(-24)), fold, Enum.Material.Fabric)
			local previous: BasePart = root
			local previousCFrame = CFrame.identity
			for i = 0, 4 do
				local at = CFrame.new(0.48 + i * 0.17, 0.83 - i * 0.09, 0.71 + i * 0.64) * CFrame.Angles(math.rad(i * 5), math.rad(-i * 7), 0)
				local hub = motorHub("ScarfMotor" .. i, previous, previousCFrame:Inverse() * at)
				local width = 0.82 - i * 0.045
				part("WindScarfTail", hub, Vector3.new(width, 0.11, 0.76), CFrame.new(0, 0, 0.36), cloth, Enum.Material.Fabric)
				part("WindScarfTailFold", hub, Vector3.new(0.14, 0.06, 0.74), CFrame.new(-width * 0.15, 0.075, 0.36) * CFrame.Angles(0, 0, math.rad(12)), fold, Enum.Material.Fabric)
				for _, side in { -1, 1 } do part("WindScarfStitch", hub, Vector3.new(0.035, 0.035, 0.74), CFrame.new(side * (width / 2 - 0.04), 0.07, 0.36), trim, Enum.Material.Fabric) end
				if i == 4 then
					for fringe = -2, 2 do part("WindScarfFringe", hub, Vector3.new(0.055, 0.08, 0.28), CFrame.new(fringe * 0.12, 0, 0.83), trim, Enum.Material.Fabric) end
				end
				previous, previousCFrame = hub, at
			end
			previous, previousCFrame = root, CFrame.identity
			for i = 0, 2 do
				local at = CFrame.new(0.51 - i * 0.13, 0.58 - i * 0.59, -0.71 - i * 0.04) * CFrame.Angles(math.rad(-6), 0, math.rad(-10))
				local hub = motorHub("ScarfFrontMotor" .. i, previous, previousCFrame:Inverse() * at)
				part("WindScarfFrontTail", hub, Vector3.new(0.62, 0.67, 0.12), CFrame.new(0, -0.3, 0), cloth, Enum.Material.Fabric)
				for _, side in { -1, 1 } do part("WindScarfFrontStitch", hub, Vector3.new(0.035, 0.63, 0.03), CFrame.new(side * 0.26, -0.3, -0.08), trim, Enum.Material.Fabric) end
				if i == 2 then for fringe = -2, 2 do part("WindScarfFrontFringe", hub, Vector3.new(0.05, 0.22, 0.08), CFrame.new(fringe * 0.12, -0.73, 0), trim, Enum.Material.Fabric) end end
				previous, previousCFrame = hub, at
			end
			local swirl = motorHub("WindSwirlMotor", root, CFrame.new(0, -0.7, 0))
			for i = 0, 7 do
				local a = i * math.pi / 4
				if i % 3 ~= 2 then
					local ribbon = segment("WindSwirlRing", swirl, Vector3.new(math.cos(a) * 2.1, 0.25 * math.sin(a), math.sin(a) * 1.6), Vector3.new(math.cos(a + 0.45) * 2.1, 0.25 * math.sin(a + 0.45), math.sin(a + 0.45) * 1.6), 0.035, color, Enum.Material.Neon); ribbon.Transparency = 0.55
				end
			end
			local _, air = particles(root, "rbxasset://textures/particles/sparkles_main.dds", 5, 0.3); air.Color = ColorSequence.new(trim, fold); air.Speed = NumberRange.new(0.5, 1.2)
			return true
		end
		return false
	end
	local function footwear(leg: BasePart)
		local y = -leg.Size.Y / 2
		local scale = math.clamp(leg.Size.X, 0.7, 1.3)
		local bootColor = Color3.fromRGB(42, 18, 68)
		local bootMaterial = Enum.Material.SmoothPlastic
		part("GlowingSole", leg, Vector3.new(1.16 * scale, 0.2, 1.83), CFrame.new(0, y + 0.01, -0.27), color, Enum.Material.Neon)
		part("BootToe", leg, Vector3.new(1.12 * scale, 0.49, 1.58), CFrame.new(0, y + 0.34, -0.31), bootColor, bootMaterial)
		part("BootAnkle", leg, Vector3.new(1.1 * scale, 1.03, 1.08), CFrame.new(0, y + (0.74), 0.05), bootColor, bootMaterial)
		part("ToeCap", leg, Vector3.new(0.98 * scale, 0.17, 0.39), CFrame.new(0, y + 0.54, -0.89), bootColor:Lerp(color, 0.35), bootMaterial)
		for i = 0, 2 do part("BootLace", leg, Vector3.new(0.71 * scale, 0.07, 0.09), CFrame.new(0, y + 0.63 + i * 0.12, -0.52), Color3.fromRGB(202, 217, 227), Enum.Material.SmoothPlastic) end
		do
			-- Hexed Witch Boots: a tall plum shaft with a flared brim, a curled pointed toe, a gold buckle,
			-- glowing crescent moons, a hanging charm, and violet flame wisps along the sole.
			local violet, plum, gold = Color3.fromRGB(86, 38, 132), Color3.fromRGB(42, 18, 68), Color3.fromRGB(240, 184, 64)
			part("WitchShaft", leg, Vector3.new(1.08 * scale, 0.95, 1.06), CFrame.new(0, y + 1.34, 0.05), plum, Enum.Material.Fabric)
			part("WitchCuffBrim", leg, Vector3.new(1.5 * scale, 0.1, 1.48), CFrame.new(0, y + 1.9, 0.05), violet, Enum.Material.Fabric)
			part("WitchCuffBand", leg, Vector3.new(1.16 * scale, 0.16, 1.14), CFrame.new(0, y + 1.78, 0.05), color, Enum.Material.Neon)
			local toe = { Vector3.new(0, y + 0.42, -1.0), Vector3.new(0, y + 0.52, -1.5), Vector3.new(0, y + 0.84, -1.84), Vector3.new(0, y + 1.3, -1.8) }
			for i = 1, #toe - 1 do segment("WitchToeCurl", leg, toe[i], toe[i + 1], 0.52 - i * 0.12, violet, Enum.Material.Fabric) end
			part("WitchToeTip", leg, Vector3.new(0.26, 0.26, 0.26), CFrame.new(toe[#toe]), color, Enum.Material.Neon, Enum.PartType.Ball)
			part("WitchBuckle", leg, Vector3.new(0.5, 0.5, 0.1), CFrame.new(0, y + 1.14, -0.5), gold, Enum.Material.Metal)
			part("WitchBuckleGem", leg, Vector3.new(0.22, 0.22, 0.12), CFrame.new(0, y + 1.14, -0.55), color, Enum.Material.Neon)
			for _, side in { -1, 1 } do
				part("WitchMoon", leg, Vector3.new(0.05, 0.5, 0.5), CFrame.new(side * 0.56 * scale, y + 1.3, 0.05), color, Enum.Material.Neon, Enum.PartType.Cylinder)
				part("WitchMoonBite", leg, Vector3.new(0.07, 0.44, 0.44), CFrame.new(side * 0.57 * scale, y + 1.35, 0.17), plum, Enum.Material.Fabric, Enum.PartType.Cylinder)
				part("WitchStar", leg, Vector3.new(0.05, 0.14, 0.14), CFrame.new(side * 0.56 * scale, y + 0.92, -0.3) * CFrame.Angles(math.rad(45), 0, 0), Color3.fromRGB(255, 226, 120), Enum.Material.Neon)
			end
			part("WitchCharm", leg, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, y + 1.0, 0.62), gold, Enum.Material.Metal, Enum.PartType.Ball)
			part("WitchCharmEye", leg, Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, y + 1.0, 0.76), color, Enum.Material.Neon, Enum.PartType.Ball)
			local _, wisp = particles(leg, "rbxasset://textures/particles/fire_main.dds", 8, 0.8, Vector3.new(0, y + 0.3, -1.1))
			wisp.Color = ColorSequence.new(Color3.fromRGB(190, 110, 255), color); wisp.Acceleration = Vector3.new(0, 2.4, 0)
			local _, spark = particles(leg, "rbxasset://textures/particles/sparkles_main.dds", 14, 0.4, Vector3.new(0, y + 0.15, 0.2))
			spark.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(180, 90, 255)); spark.Speed = NumberRange.new(2, 4)
			trail(leg, y)
		end
	end
	if buildOrdinaryGear() then
		-- The ordinary builder completed the selected design.
	elseif selected == "WitchBoots" then
		for _, names in { { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } } do
			local foot = character:FindFirstChild(names[1]) or character:FindFirstChild(names[2])
			if foot and foot:IsA("BasePart") then footwear(foot) end
		end
	elseif selected == "PhantomCloak" then
		-- Phantom Shroud: a pale, see-through hood and mantle, six tattered tails that ripple (GearAnimate), a glowing
		-- brooch, three orbiting wisps with light trails, and an ectoplasm mist along the ground.
		local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or root
		if not torso:IsA("BasePart") then torso = root end
		local pale, deep, spirit = Color3.fromRGB(226, 255, 250), Color3.fromRGB(26, 74, 92), Color3.fromRGB(190, 255, 246)
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local back = part("PhantomHoodBack", head, Vector3.new(2.3, 1.7, 0.36), CFrame.new(0, 0.15, 0.62), pale, Enum.Material.Glass); back.Transparency = 0.28
			local top = part("PhantomHoodTop", head, Vector3.new(2.3, 0.3, 1.6), CFrame.new(0, 0.74, 0.1), pale, Enum.Material.Glass); top.Transparency = 0.28
			local peak = part("PhantomHoodPeak", head, Vector3.new(0.55, 1.1, 0.5), CFrame.new(0, 1.0, 0.85) * CFrame.Angles(math.rad(-34), 0, 0), spirit, Enum.Material.Glass); peak.Transparency = 0.2
			for _, side in { -1, 1 } do
				local cheek = part("PhantomHoodSide", head, Vector3.new(0.3, 1.55, 1.34), CFrame.new(side * 1.13, 0.1, 0.05), pale, Enum.Material.Glass); cheek.Transparency = 0.28
				part("PhantomHoodRim", head, Vector3.new(0.07, 1.5, 0.07), CFrame.new(side * 1.1, 0.12, -0.64), color, Enum.Material.Neon)
			end
			part("PhantomHoodBrow", head, Vector3.new(2.2, 0.07, 0.07), CFrame.new(0, 0.76, -0.69), color, Enum.Material.Neon)
		end
		for _, side in { -1, 1 } do
			local mantle = part("PhantomMantle", torso, Vector3.new(1.55, 0.3, 1.45), CFrame.new(side * 0.95, 1.0, 0.1) * CFrame.Angles(0, 0, side * math.rad(-14)), pale, Enum.Material.Glass); mantle.Transparency = 0.22
			part("PhantomMantleEdge", torso, Vector3.new(1.5, 0.06, 0.08), CFrame.new(side * 0.98, 0.86, -0.62) * CFrame.Angles(0, 0, side * math.rad(-14)), color, Enum.Material.Neon)
		end
		for i = 0, 5 do
			local x = -0.85 + i * 0.34
			local length = 3.5 - math.abs(x) * 0.9 + (i % 2) * 0.55
			local hub = motorHub("PhantomTail" .. i, torso, CFrame.new(x, 0.95, 0.6) * CFrame.Angles(math.rad(7), 0, 0))
			local panel = part("PhantomTailPanel", hub, Vector3.new(0.36, length, 0.1), CFrame.new(0, -length / 2, 0), pale:Lerp(color, (i % 3) * 0.18), Enum.Material.Glass); panel.Transparency = 0.3
			part("PhantomTailEdge", hub, Vector3.new(0.06, length, 0.13), CFrame.new(0.19, -length / 2, 0), color, Enum.Material.Neon)
			local tip = part("PhantomTailTip", hub, Vector3.new(0.3, 0.3, 0.1), CFrame.new(0, -length - 0.05, 0) * CFrame.Angles(0, 0, math.rad(45)), color, Enum.Material.Neon); tip.Transparency = 0.2
			if i == 1 or i == 4 then
				local a = Instance.new("Attachment"); a.Name = "PhantomTrailA"; a:SetAttribute("GearVFX", true); a.Position = Vector3.new(-0.15, 0, 0); a.Parent = tip
				local b = Instance.new("Attachment"); b.Name = "PhantomTrailB"; b:SetAttribute("GearVFX", true); b.Position = Vector3.new(0.15, 0, 0); b.Parent = tip
				local ecto = Instance.new("Trail"); ecto.Name = "PhantomTailTrail"; ecto.Attachment0 = a; ecto.Attachment1 = b
				ecto.Color = ColorSequence.new(spirit, color); ecto.Lifetime = 0.8; ecto.LightEmission = 1; ecto.MinLength = 0.03
				ecto.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }); ecto.Parent = a
			end
		end
		-- glowing brooch on the chest, held by a thin chain
		part("PhantomBrooch", torso, Vector3.new(0.5, 0.5, 0.2), CFrame.new(0, 0.7, -0.6), Color3.fromRGB(72, 96, 112), Enum.Material.Metal, Enum.PartType.Ball)
		part("PhantomBroochCore", torso, Vector3.new(0.3, 0.3, 0.16), CFrame.new(0, 0.7, -0.68), color, Enum.Material.Neon, Enum.PartType.Ball)
		segment("PhantomChain", torso, Vector3.new(-0.9, 0.95, -0.55), Vector3.new(0, 0.7, -0.62), 0.07, Color3.fromRGB(150, 186, 200), Enum.Material.Metal)
		segment("PhantomChain", torso, Vector3.new(0, 0.7, -0.62), Vector3.new(0.9, 0.95, -0.55), 0.07, Color3.fromRGB(150, 186, 200), Enum.Material.Metal)
		-- three wisps circle the wearer, each leaving a ring of light
		local orbit = motorHub("PhantomOrbitMotor", root, CFrame.identity)
		for i = 0, 2 do
			local angle = i * math.pi * 2 / 3
			local wisp = part("PhantomWisp", orbit, Vector3.new(0.42, 0.42, 0.42), CFrame.new(math.cos(angle) * 2.3, -0.4 + i * 0.75, math.sin(angle) * 1.7), color, Enum.Material.Neon, Enum.PartType.Ball); wisp.Transparency = 0.1
			part("PhantomWispCore", orbit, Vector3.new(0.2, 0.2, 0.2), CFrame.new(math.cos(angle) * 2.3, -0.4 + i * 0.75, math.sin(angle) * 1.7), Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball)
			local a = Instance.new("Attachment"); a.Name = "PhantomWispA"; a:SetAttribute("GearVFX", true); a.Position = Vector3.new(0, 0.3, 0); a.Parent = wisp
			local b = Instance.new("Attachment"); b.Name = "PhantomWispB"; b:SetAttribute("GearVFX", true); b.Position = Vector3.new(0, -0.3, 0); b.Parent = wisp
			local ring = Instance.new("Trail"); ring.Name = "PhantomWispTrail"; ring.Attachment0 = a; ring.Attachment1 = b
			ring.Color = ColorSequence.new(Color3.new(1, 1, 1), color); ring.Lifetime = 0.9; ring.LightEmission = 1; ring.MinLength = 0.03
			ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }); ring.Parent = a
		end
		local mist = motorHub("PhantomMistMotor", root, CFrame.new(0, -2.7, 0))
		for i = 0, 17 do
			if i % 6 ~= 5 then
				local a0, a1 = i * math.pi / 9, (i + 1) * math.pi / 9
				local ring = segment("PhantomMistRing", mist, Vector3.new(math.cos(a0) * 2.2, 0, math.sin(a0) * 2.2), Vector3.new(math.cos(a1) * 2.2, 0, math.sin(a1) * 2.2), 0.07, color, Enum.Material.Neon); ring.Transparency = 0.45
			end
		end
		local _, ectoplasm = particles(root, "rbxasset://textures/particles/smoke_main.dds", 20, 3.2, Vector3.new(0, -2.8, 0))
		ectoplasm.Color = ColorSequence.new(deep, Color3.fromRGB(150, 255, 235)); ectoplasm.SpreadAngle = Vector2.new(90, 180); ectoplasm.Speed = NumberRange.new(1.5, 3.5)
		ectoplasm.Lifetime = NumberRange.new(1.1, 1.8); ectoplasm.Acceleration = Vector3.new(0, 0.6, 0)
		ectoplasm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		local _, souls = particles(root, "rbxasset://textures/particles/sparkles_main.dds", 16, 0.6, Vector3.new(0, 0.5, 0)); souls.Speed = NumberRange.new(0.6, 2); souls.SpreadAngle = Vector2.new(180, 180); souls.Acceleration = Vector3.new(0, 1.2, 0)
		local aura = Instance.new("Highlight"); aura.Name = "PhantomAuraHighlight"; aura:SetAttribute("GearVFX", true); aura.FillColor = deep; aura.FillTransparency = 0.88; aura.OutlineColor = color; aura.OutlineTransparency = 0.45; aura.DepthMode = Enum.HighlightDepthMode.Occluded; aura.Parent = character
		local glow = Instance.new("PointLight"); glow.Name = "PhantomGlow"; glow:SetAttribute("GearVFX", true); glow.Color = color; glow.Range = 11; glow.Brightness = 1; glow.Shadows = false; glow.Parent = root
	elseif selected == "PumpkinKingWings" then
		-- Pumpkin King Wings: bat wings (bone arm, five fingers, ember-lit lava membrane) on a carved mount with a
		-- jack-o-lantern crest, plus a flaming gold crown on the head. KingWingL / KingWingR flap in GearAnimate.
		local bone, boneDark, amber, ember = Color3.fromRGB(46, 24, 58), Color3.fromRGB(26, 14, 36), Color3.fromRGB(255, 176, 40), Color3.fromRGB(255, 76, 12)
		local gold = Color3.fromRGB(240, 184, 64)
		part("KingWingMount", root, Vector3.new(1.45, 1.6, 0.3), CFrame.new(0, 0.5, 0.6), boneDark, Enum.Material.Metal)
		part("KingWingMountRim", root, Vector3.new(1.6, 1.75, 0.12), CFrame.new(0, 0.5, 0.74), gold, Enum.Material.Metal)
		local face = part("KingJackFace", root, Vector3.new(1.05, 0.95, 0.4), CFrame.new(0, 0.5, 0.88), color, Enum.Material.Neon, Enum.PartType.Ball)
		face.Transparency = 0.05
		part("KingJackStem", root, Vector3.new(0.2, 0.32, 0.2), CFrame.new(0, 1.05, 0.88) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(70, 110, 36), Enum.Material.Wood)
		for _, side in { -1, 1 } do
			part("KingJackEye", root, Vector3.new(0.26, 0.26, 0.1), CFrame.new(side * 0.25, 0.68, 1.04) * CFrame.Angles(0, 0, math.rad(45)), boneDark, Enum.Material.SmoothPlastic)
		end
		for i = 0, 3 do
			part("KingJackTooth", root, Vector3.new(0.16, 0.12, 0.1), CFrame.new(-0.3 + i * 0.2, 0.3 + (i % 2) * 0.09, 1.04), boneDark, Enum.Material.SmoothPlastic)
		end
		for _, side in { -1, 1 } do
			local wing = motorHub(if side < 0 then "KingWingL" else "KingWingR", root, CFrame.new(side * 0.8, 0.9, 0.75))
			local elbow, wrist, bodyAnchor = Vector3.new(side * 1.2, 1.5, 0), Vector3.new(side * 2.8, 2.3, 0.05), Vector3.new(side * 0.35, -1.5, 0)
			local tips = {
				Vector3.new(side * 5.1, 3.1, 0.1),
				Vector3.new(side * 5.2, 1.5, 0.08),
				Vector3.new(side * 4.2, -0.2, 0.06),
				Vector3.new(side * 2.8, -1.2, 0.04),
				bodyAnchor,
			}
			segment("KingWingArm", wing, Vector3.zero, elbow, 0.24, bone, Enum.Material.Metal)
			segment("KingWingForearm", wing, elbow, wrist, 0.2, bone, Enum.Material.Metal)
			part("KingWingElbow", wing, Vector3.new(0.34, 0.34, 0.34), CFrame.new(elbow), color, Enum.Material.Neon, Enum.PartType.Ball)
			part("KingWingWrist", wing, Vector3.new(0.3, 0.3, 0.3), CFrame.new(wrist), color, Enum.Material.Neon, Enum.PartType.Ball)
			-- thumb claw
			segment("KingWingClaw", wing, wrist, wrist + Vector3.new(side * 0.1, 0.95, 0.12), 0.1, amber, Enum.Material.Neon)
			-- fingers
			for index, tip in tips do
				segment("KingWingFinger", wing, wrist, tip, if index == #tips then 0.07 else 0.13 - index * 0.012, bone, Enum.Material.Metal)
				if index < #tips then part("KingWingFingerTip", wing, Vector3.new(0.14, 0.14, 0.14), CFrame.new(tip), amber, Enum.Material.Neon, Enum.PartType.Ball) end
			end
			-- membrane: strips between neighbouring fingers, hot red near the body and amber at the tips
			for gap = 1, #tips - 1 do
				local steps = 5
				for step = 1, steps do
					local t0, t1 = (step - 1) / steps + 0.06, step / steps + 0.06
					local a0, b0 = wrist + (tips[gap] - wrist) * t0, wrist + (tips[gap + 1] - wrist) * t0
					local a1, b1 = wrist + (tips[gap] - wrist) * math.min(t1, 1), wrist + (tips[gap + 1] - wrist) * math.min(t1, 1)
					local center = (a0 + b0 + a1 + b1) / 4
					local across = (b0 - a0) + (b1 - a1)
					local along = (a1 - a0) + (b1 - b0)
					if across.Magnitude > 0.01 and along.Magnitude > 0.01 then
						local xAxis = across.Unit
						local zAxis = xAxis:Cross(along).Unit
						local yAxis = zAxis:Cross(xAxis)
						local piece = part("KingWingMembrane", wing, Vector3.new(across.Magnitude / 2 + 0.05, along.Magnitude / 2 + 0.04, 0.04), CFrame.fromMatrix(center, xAxis, yAxis, zAxis), ember:Lerp(amber, (step - 1) / steps), Enum.Material.Neon)
						piece.Transparency = 0.18 + (gap % 2) * 0.06
					end
				end
			end
			-- wing-tip embers
			local tipPart = part("KingWingTip", wing, Vector3.new(0.12, 0.12, 0.12), CFrame.new(tips[1]), amber, Enum.Material.Neon, Enum.PartType.Ball)
			local tipA = Instance.new("Attachment"); tipA.Name = "KingTipA"; tipA:SetAttribute("GearVFX", true); tipA.Position = Vector3.new(0, 0.24, 0); tipA.Parent = tipPart
			local tipB = Instance.new("Attachment"); tipB.Name = "KingTipB"; tipB:SetAttribute("GearVFX", true); tipB.Position = Vector3.new(0, -0.24, 0); tipB.Parent = tipPart
			local flame = Instance.new("Trail"); flame.Name = "KingWingTrail"; flame.Attachment0 = tipA; flame.Attachment1 = tipB
			flame.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), ember); flame.Lifetime = 0.8; flame.LightEmission = 1; flame.MinLength = 0.03
			flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }); flame.Parent = tipA
			local _, embers = particles(wing, "rbxasset://textures/particles/sparkles_main.dds", 16, 0.5, Vector3.new(side * 3.4, 0.8, 0))
			embers.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), ember); embers.Lifetime = NumberRange.new(1.2, 2.2); embers.SpreadAngle = Vector2.new(180, 180); embers.Speed = NumberRange.new(0.4, 1.8); embers.Acceleration = Vector3.new(0, 1.6, 0)
		end
		-- flaming crown on the head
		local crownBase = character:FindFirstChild("Head")
		if crownBase and crownBase:IsA("BasePart") then
			part("KingCrownBand", crownBase, Vector3.new(1.4, 0.2, 1.4), CFrame.new(0, 0.62, 0), gold, Enum.Material.Metal)
			part("KingCrownGlow", crownBase, Vector3.new(1.46, 0.07, 1.46), CFrame.new(0, 0.55, 0), color, Enum.Material.Neon)
			for i = 0, 4 do
				local angle = i * math.pi * 2 / 5
				local height = if i % 2 == 0 then 0.8 else 0.55
				part("KingCrownSpike", crownBase, Vector3.new(0.22, height, 0.22), CFrame.new(math.cos(angle) * 0.55, 0.72 + height / 2, math.sin(angle) * 0.55), amber, Enum.Material.Neon)
				part("KingCrownJewel", crownBase, Vector3.new(0.14, 0.14, 0.14), CFrame.new(math.cos(angle) * 0.7, 0.62, math.sin(angle) * 0.7), ember, Enum.Material.Neon, Enum.PartType.Ball)
			end
			local _, crownFire = particles(crownBase, "rbxasset://textures/particles/fire_main.dds", 16, 1.0, Vector3.new(0, 1.2, 0))
			crownFire.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), ember); crownFire.Acceleration = Vector3.new(0, 3, 0); crownFire.Lifetime = NumberRange.new(0.5, 0.9)
		end
		local glow = Instance.new("PointLight"); glow.Name = "KingGlow"; glow:SetAttribute("GearVFX", true); glow.Color = color; glow.Range = 12; glow.Brightness = 1.2; glow.Shadows = false; glow.Parent = root

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
