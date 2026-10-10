--!strict
-- الأسلحة والضرب: المضرب الخشبي لكل الناس، وسيف الـ VIP لأصحاب الـ Gamepass.
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

local function cloneWeaponTemplate(name: string): Tool
	local folder = ReplicatedStorage:WaitForChild("WeaponModels")
	local template = folder:WaitForChild(name)
	assert(template:IsA("Tool"), "Weapon template is missing or invalid: " .. name)
	return template:Clone() :: Tool
end

local function makeBat(): Tool
	local tool = cloneWeaponTemplate("WoodenBat")
	tool.Name = "Bat"
	tool.ToolTip = "Hit the mother monsters!"
	tool.CanBeDropped = false
	tool.GripPos = Vector3.new(0, 0, 0.6)
	return tool
end

local function makeSword(): Tool
	local tool = cloneWeaponTemplate("IceSword")
	tool.Name = "VIP Sword"
	tool.ToolTip = "VIP: hits much harder!"
	tool.CanBeDropped = false
	tool.GripPos = Vector3.new(0, 0, 0.4)
	return tool
end
-- بيدّي اللاعب أسلحته (بيتنادى كل ما الشخصية تتولد، عشان الـ Backpack بيتمسح)
function CombatService.GiveWeapons(player: Player, hasSword: boolean)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local character = player.Character
	local function has(name: string): boolean
		return backpack:FindFirstChild(name) ~= nil or (character ~= nil and character:FindFirstChild(name) ~= nil)
	end
	if not has("Bat") then
		local bat = makeBat()
		bat.Activated:Connect(function()
			swing(player, bat, 1, 0, Config.PvP.BatDamage)
		end)
		bat.Parent = backpack
	end
	if hasSword and not has("VIP Sword") then
		local sword = makeSword()
		sword.Activated:Connect(function()
			swing(player, sword, Config.VIPSword.DamageMultiplier, Config.VIPSword.ExtraReach, Config.PvP.SwordDamage)
		end)
		sword.Parent = backpack
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
