--!strict
-- كل اللاعبين بيلعبوا بشخصيات R6 من غير ما نحتاج نعمل Publish ونغيّر Game Settings:
-- بنحط Rig من نوع R6 كـ StarterCharacter، وبعدين نلبّسه شكل اللاعب نفسه (هدومه وإكسسواراته).

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

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

function CharacterService.Cleanup(player: Player)
	descriptions[player] = nil
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
