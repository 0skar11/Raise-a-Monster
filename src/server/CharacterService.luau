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

function CharacterService.UpdateHealth(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local maximum = Config.PlayerBaseHealth + (healthBonuses[player] or 0)
	if humanoid.MaxHealth == maximum then return end
	-- Preserve current health percentage: buying gear never revives a dead player.
	local fraction = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	humanoid.MaxHealth = maximum
	humanoid.Health = maximum * fraction
end

function CharacterService.ApplySpeedAccessory(player: Player, owned: { [string]: boolean })
	local bonus = 0
	for name, accessory in Config.SpeedAccessories do
		if owned[name] then bonus = math.max(bonus, accessory.HealthBonus) end
	end
	healthBonuses[player] = bonus
	CharacterService.UpdateHealth(player)
	local multiplier = CharacterService.GetSpeedAccessoryMultiplier(owned)
	CharacterService.SetSpeedFactor(player, "SpeedAccessory", if multiplier > 1 then multiplier else nil)
end

function CharacterService.GetSpeedAccessoryMultiplier(owned: { [string]: boolean }): number
	local best = 1
	for name, accessory in Config.SpeedAccessories do
		if owned[name] then
			best = math.max(best, accessory.Multiplier)
		end
	end
	return best
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
