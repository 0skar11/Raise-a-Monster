local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.HalloweenArenaConfig)
local Builder = require(Shared.HalloweenArenaBuilder)
local Arena = {}
local nextArrival = 0

function Arena.Init(): Model
	local model = workspace:FindFirstChild("HalloweenArena")
	if not model then
		model = Builder.Build(Config)
		model.Parent = workspace
	end
	model:SetAttribute("PlayerCapacity", Config.Capacity)
	return model
end

function Arena.NextArrival(): CFrame
	nextArrival = nextArrival % math.min(Config.Capacity, #Config.ArrivalPoints) + 1
	return Config.Origin * Config.ArrivalPoints[nextArrival]
end

return Arena
