--!strict
-- الأسلحة والضرب: المضرب الخشبي للجميع، والأسلحة الإضافية من متجر الـ Gamepass.
-- أي حاجة ممكن تتضرب (الوحوش الأم، الـ Big Boss) بتتسجل هنا كـ Target،
-- ولو مفيش Target قريب السلاح بيضرب أقرب لاعب (برّه القواعد بس).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)

export type Target = {
	Part: BasePart,
	Radius: number, -- نص عرض الهدف، عشان المدى يتحسب من حرفه
	OnHit: (player: Player, damage: number) -> (),
}

type Tag = { Attacker: Player, Time: number }

local CombatService = {}

local targets: { [Target]: boolean } = {}
local lastSwing: { [Player]: number } = {}
local tags: { [Player]: Tag } = {}

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

	-- أنيميشن الضربة بتاع R6
	local animation = Instance.new("StringValue")
	animation.Name = "toolanim"
	animation.Value = "Slash"
	animation.Parent = tool

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
		best.OnHit(player, math.floor(MonsterService.GetAttackDamage(player) * damageMultiplier))
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
		if victimHumanoid then
			tags[victim] = { Attacker = player, Time = now }
			victimHumanoid:TakeDamage(pvpDamage)
		end
	end
end

-- Each Handle's long axis maps to tool-local -Z. Rotate the grip so it points
-- along the character's forward direction when equipped.
local function setForwardGrip(tool: Tool)
	tool.Grip = CFrame.new(0, -0.65, 0) * CFrame.Angles(0, math.rad(90), 0)
end

local function cloneWeaponTemplate(name: string): Tool
	local folder = ReplicatedStorage:WaitForChild("WeaponModels")
	local template = folder:WaitForChild(name)
	assert(template:IsA("Tool"), "Weapon template is missing or invalid: " .. name)
	local tool = template:Clone() :: Tool
	setForwardGrip(tool)
	return tool
end

local function makeBat(): Tool
	local tool = cloneWeaponTemplate("WoodenBat")
	tool.Name = "Bat"
	tool.ToolTip = "Hit the mother monsters!"
	tool.CanBeDropped = false
	return tool
end

local function makeSword(passName: string): Tool
	local stats = Config.WeaponStats[passName]
	assert(stats, "Weapon stats are missing: " .. passName)
	local tool = cloneWeaponTemplate(stats.Template)
	tool.Name = Config.Gamepasses[passName].Name
	tool.ToolTip = Config.Gamepasses[passName].Description
	tool.CanBeDropped = false
	return tool
end
-- بيدّي اللاعب أسلحته (بيتنادى كل ما الشخصية تتولد، عشان الـ Backpack بيتمسح)
function CombatService.GiveWeapons(player: Player, ownedPasses: { [string]: boolean }, ownedWeapons: { [string]: boolean })
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local character = player.Character
	local function has(name: string): boolean
		return backpack:FindFirstChild(name) ~= nil or (character ~= nil and character:FindFirstChild(name) ~= nil)
	end
	local bat = (backpack:FindFirstChild("Bat") or (character and character:FindFirstChild("Bat"))) :: Tool?
	if not bat then
		bat = makeBat()
		bat.Activated:Connect(function()
			swing(player, bat :: Tool, 1, 0, Config.PvP.BatDamage)
		end)
		bat.Parent = backpack
	end
	if bat then
		setForwardGrip(bat)
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and bat then
		humanoid:EquipTool(bat)
	end
	for passName, stats in Config.WeaponStats do
		local displayName = Config.Gamepasses[passName].Name
		if ownedPasses[passName] or ownedWeapons[passName] then
			local existingSword = backpack:FindFirstChild(displayName) or (character and character:FindFirstChild(displayName))
			if existingSword and existingSword:IsA("Tool") then
				setForwardGrip(existingSword)
			elseif not existingSword then
				local sword = makeSword(passName)
				sword.Activated:Connect(function()
					swing(player, sword, stats.DamageMultiplier, stats.ExtraReach, Config.PvP.SwordDamage)
				end)
				sword.Parent = backpack
			end
		end
	end
end

function CombatService.CleanupPlayer(player: Player)
	lastSwing[player] = nil
	tags[player] = nil
	for victim, tag in tags do
		if tag.Attacker == player then
			tags[victim] = nil
		end
	end
end

return CombatService
