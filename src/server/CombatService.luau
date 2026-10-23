--!strict
-- الأسلحة والضرب: المضرب للجميع، والأسلحة بعملات اللعبة مع دعم ملكية الـ Gamepass القديمة.
-- أي حاجة ممكن تتضرب (الوحوش الأم، الـ Big Boss) بتتسجل هنا كـ Target،
-- ولو مفيش Target قريب السلاح بيضرب أقرب لاعب (برّه القواعد بس).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)

-- تشغيل صوت في مكان معين
local function playSound(parent: Instance, soundId: string, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- عمل مؤثر بصري (VFX) بسيط عند الإصابة
local function spawnHitVfx(position: Vector3, color: Color3?)
	local part = Instance.new("Part")
	part.Name = "HitEffect"
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 220, 100))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.LightEmission = 1
	emitter.Texture = "rbxassetid://243098777" -- لمعة بسيطة
	emitter.Speed = NumberRange.new(5, 10)
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment

	emitter:Emit(10)
	Debris:AddItem(part, 1)
end

export type Target = {
	Part: BasePart,
	Radius: number, -- نص عرض الهدف، عشان المدى يتحسب من حرفه
	OnHit: (player: Player, damage: number) -> (),
}

type Tag = { Attacker: Player, Time: number }

local CombatService = {}

local remotes = Remotes.Get()

local targets: { [Target]: boolean } = {}
local lastSwing: { [Player]: number } = {}
local PLAYER_ATTACK_ANIMATION = "rbxassetid://130100478675595"
type AttackState = {
	Tool: Tool,
	Animator: Animator?,
	Track: AnimationTrack?,
	Grip: CFrame,
	Generation: number,
	Connections: { RBXScriptConnection },
}
local attacks: { [Player]: AttackState } = {}
local tags: { [Player]: Tag } = {}

local function clearAttack(player: Player)
	local state = attacks[player]
	if not state then return end
	attacks[player] = nil
	for _, connection in state.Connections do connection:Disconnect() end
	state.Tool.Grip = state.Grip
	if state.Track then
		state.Track:Stop(0)
		state.Track:Destroy()
	end
end

local function animateSwing(player: Player, tool: Tool, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local state = attacks[player]
	if state and (state.Tool ~= tool or state.Animator ~= animator) then
		clearAttack(player)
		state = nil
	end
	if not state then
		local track: AnimationTrack? = nil
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = PLAYER_ATTACK_ANIMATION
			track = animator:LoadAnimation(animation)
			animation:Destroy()
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
		end
		state = { Tool = tool, Animator = animator, Track = track, Grip = tool.Grip, Generation = 0, Connections = {} }
		attacks[player] = state
		table.insert(state.Connections, tool.AncestryChanged:Connect(function()
			if tool.Parent ~= player.Character then clearAttack(player) end
		end))
		table.insert(state.Connections, humanoid.Died:Connect(function() clearAttack(player) end))
		table.insert(state.Connections, player.CharacterRemoving:Connect(function() clearAttack(player) end))
	end

	-- The authored attack owns the arms; a default Slash would blend into it.
	for _, child in tool:GetChildren() do
		if child.Name == "toolanim" and child:IsA("StringValue") then child:Destroy() end
	end
	local track = state.Track
	if track then
		-- Spam must not rewind an attack before it can finish.
		if not track.IsPlaying then track:Play() end
	else
		local animation = Instance.new("StringValue")
		animation.Name = "toolanim"
		animation.Value = "Slash"
		animation.Parent = tool
		Debris:AddItem(animation, Config.Combat.AttackCooldown)
	end

	state.Generation += 1
	local generation = state.Generation
	tool.Grip = state.Grip * CFrame.Angles(math.rad(45), 0, 0)
	task.delay(0.15, function()
		if attacks[player] == state and state.Generation == generation then tool.Grip = state.Grip end
	end)
end

function CombatService.Register(target: Target): Target
	targets[target] = true
	return target
end

function CombatService.Unregister(target: Target?)
	if target then
		targets[target] = nil
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- اللاعب جوه أي قاعدة؟ (القواعد أمان: مفيش ضرب لاعبين فيها)
function CombatService.IsInSafeZone(position: Vector3): boolean
	for _, plot in PlotService.GetPlots() do
		if PlotService.IsInsidePlot(plot, position) then
			return true
		end
	end
	return false
end

-- مين آخر حد ضرب اللاعب ده في آخر شوية ثواني (عشان ياخد اللي كان شايله لو مات)
function CombatService.GetKiller(victim: Player): Player?
	local tag = tags[victim]
	if tag and os.clock() - tag.Time <= Config.Carry.KillCreditTime and tag.Attacker.Parent then
		return tag.Attacker
	end
	return nil
end

local function swing(player: Player, tool: Tool, damageMultiplier: number, extraReach: number, pvpDamage: number)
	if tool.Parent ~= player.Character or tool:GetAttribute("GameWeaponOwner") ~= player.UserId then return end
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < Config.Combat.AttackCooldown then
		return
	end
	lastSwing[player] = now
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- أصوات الضرب
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if handle then
		playSound(handle, Config.Combat.Sounds.Swing, 0.6)
	end

	animateSwing(player, tool, humanoid)

	-- الأول: أقرب وحش أم أو Boss في المدى
	local best: Target? = nil
	local bestDistance = math.huge
	for target in targets do
		if target.Part.Parent then
			local distance = flatDistance(root.Position, target.Part.Position) - target.Radius
			if distance <= Config.Combat.BatReach + extraReach and distance < bestDistance then
				best = target
				bestDistance = distance
			end
		end
	end
	if best then
		local crit = math.random() < Config.Combat.CritChance
		local passMultiplier = if MonsterService.HasPass(player, "DoubleDamage") then Config.DoubleDamageMultiplier else 1
		local damage = math.floor(MonsterService.GetAttackDamage(player) * damageMultiplier * passMultiplier * (if crit then Config.Combat.CritMultiplier else 1))
		local hitPosition = best.Part.Position
		best.OnHit(player, damage)
		playSound(best.Part, Config.Combat.Sounds.Hit, if crit then 1 else 0.8)
		spawnHitVfx(hitPosition, if crit then Color3.fromRGB(255, 170, 40) else nil)
		remotes.HitFeedback:FireClient(player, hitPosition + Vector3.new(0, best.Radius + 2, 0), damage, crit)
		return
	end

	-- مفيش: نضرب أقرب لاعب (برّه القواعد)
	if CombatService.IsInSafeZone(root.Position) then
		return
	end
	local victim: Player? = nil
	local victimDistance = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = getRoot(other)
			local otherHumanoid = getHumanoid(other)
			if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
				local distance = (otherRoot.Position - root.Position).Magnitude
				if distance <= Config.PvP.Reach + extraReach and distance < victimDistance and not CombatService.IsInSafeZone(otherRoot.Position) then
					victim = other
					victimDistance = distance
				end
			end
		end
	end
	if victim then
		local victimHumanoid = getHumanoid(victim)
		local victimRoot = getRoot(victim)
		if victimHumanoid and victimRoot then
			tags[victim] = { Attacker = player, Time = now }
			local passMultiplier = if MonsterService.HasPass(player, "DoubleDamage") then Config.DoubleDamageMultiplier else 1
			local damage = math.floor((pvpDamage + MonsterService.GetFollowerDamageBonus(player) * Config.Followers.PvpDamageScale) * damageMultiplier * passMultiplier)
			victimHumanoid:TakeDamage(damage)
			playSound(victimRoot, Config.Combat.Sounds.Hit, 0.8)
			spawnHitVfx(victimRoot.Position)
			remotes.HitFeedback:FireClient(player, victimRoot.Position + Vector3.new(0, 3, 0), damage, false)
			remotes.PlayerHurt:FireClient(victim, damage, Color3.fromRGB(255, 60, 60))
		end
	end
end

-- Templates extend along Handle +X. With Roblox's equipped-tool hold pose,
-- a -90 degree Z grip puts the barrel above the hand instead of forward.
-- The blade direction is measured from the model itself (handle origin -> centre of the other parts),
-- so a template authored along another axis still ends up pointing straight up.
local function bladeAxis(tool: Tool): Vector3
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return Vector3.xAxis end
	local sum, count = Vector3.zero, 0
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") and item ~= handle then
			sum += handle.CFrame:PointToObjectSpace(item.CFrame.Position)
			count += 1
		end
	end
	local direction = if count > 0 then sum / count else Vector3.zero
	if direction.Magnitude < 0.2 then
		-- Single-part weapon: use the longest side of the handle.
		local size = handle.Size
		direction = if size.X >= size.Y and size.X >= size.Z then Vector3.xAxis elseif size.Y >= size.Z then Vector3.yAxis else Vector3.zAxis
	end
	local ax, ay, az = math.abs(direction.X), math.abs(direction.Y), math.abs(direction.Z)
	if ax >= ay and ax >= az then return Vector3.xAxis * math.sign(direction.X) end
	if ay >= az then return Vector3.yAxis * math.sign(direction.Y) end
	return Vector3.zAxis * math.sign(direction.Z)
end

local function setUprightGrip(tool: Tool)
	local axis = bladeAxis(tool)
	if axis == Vector3.xAxis then
		tool.Grip = CFrame.new(-0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
		return
	end
	-- Grip maps the hand's up direction onto the blade axis (Handle = hand * Grip^-1).
	local helper = if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local right = helper:Cross(axis).Unit
	tool.Grip = CFrame.fromMatrix(-0.15 * axis, right, axis, right:Cross(axis))
end

local function cloneWeaponTemplate(name: string): Tool
	local folder = ReplicatedStorage:WaitForChild("WeaponModels")
	local template = folder:WaitForChild(name)
	assert(template:IsA("Tool"), "Weapon template is missing or invalid: " .. name)
	local tool = template:Clone() :: Tool
	setUprightGrip(tool)
	return tool
end

local function makeBat(): Tool
	local tool = cloneWeaponTemplate("WoodenBat")
	tool.Name = "Bat"
	tool.ToolTip = "Hit the mother monsters!"
	tool.CanBeDropped = false
	tool:SetAttribute("GameWeaponKey", "Bat")
	return tool
end

local function makeSword(passName: string): Tool
	local stats = Config.WeaponStats[passName]
	assert(stats, "Weapon stats are missing: " .. passName)
	local tool = cloneWeaponTemplate(stats.Template)
	tool.Name = Config.Gamepasses[passName].Name
	tool.ToolTip = Config.Gamepasses[passName].Description
	tool.CanBeDropped = false
	tool:SetAttribute("GameWeaponKey", passName)
	return tool
end
-- سلاح واحد ظاهر؛ تبديله مايمسحش ملكية الأسلحة التانية.
function CombatService.GiveWeapons(player: Player, ownedPasses: { [string]: boolean }, ownedWeapons: { [string]: boolean }, selected: string?)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	local character = player.Character
	local key = selected or "Bat"
	if key ~= "Bat" and (not Config.WeaponStats[key] or (ownedPasses[key] ~= true and ownedWeapons[key] ~= true)) then key = "Bat" end
	local starterGear = player:FindFirstChild("StarterGear")
	local containers: { Instance } = { backpack }
	if character then table.insert(containers, character) end
	if starterGear then table.insert(containers, starterGear) end
	local equippedTool: Tool? = nil
	for _, container in containers do
		for _, item in container:GetChildren() do
			local itemKey = item:GetAttribute("GameWeaponKey")
			if item:IsA("Tool") and item:GetAttribute("GameWeaponOwner") == player.UserId and type(itemKey) == "string" and (itemKey == "Bat" or Config.WeaponStats[itemKey]) then
				if itemKey == key and not equippedTool and container ~= starterGear then equippedTool = item else item:Destroy() end
			end
		end
	end
	if not equippedTool then
		local stats = Config.WeaponStats[key]
		local created = if key == "Bat" then makeBat() else makeSword(key)
		created:SetAttribute("GameWeaponOwner", player.UserId)
		created.Activated:Connect(function()
			swing(player, created, if stats then stats.DamageMultiplier else 1, if stats then stats.ExtraReach else 0, if stats then Config.PvP.SwordDamage else Config.PvP.BatDamage)
		end)
		created.Parent = backpack
		equippedTool = created
	end
	setUprightGrip(equippedTool)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then humanoid:EquipTool(equippedTool) end
end

function CombatService.CleanupPlayer(player: Player)
	clearAttack(player)
	lastSwing[player] = nil
	tags[player] = nil
	for victim, tag in tags do
		if tag.Attacker == player then
			tags[victim] = nil
		end
	end
end

return CombatService
