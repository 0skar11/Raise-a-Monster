-- Touch entry is handled on the server; clients never select a destination.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.HalloweenPortalConfig)
local Builder = require(Shared.HalloweenPortalBuilder)
local CarryService = require(script.Parent.CarryService)
local Service = {}
local pending = {}
local lastAttempt = {}
local started = false

function Service.Init()
	if started then return end
	started = true
	local portal = workspace:FindFirstChild("HalloweenPortal")
	if not portal then
		portal = Builder.Build(Config.Origin)
		portal.Parent = workspace
	end
	local trigger = portal:FindFirstChild("TeleportTrigger")
	assert(trigger and trigger:IsA("BasePart"), "Halloween portal trigger is missing")
	portal:SetAttribute("DestinationPlaceId", Config.DestinationPlaceId)
	portal:SetAttribute("TeleportEnabled", Config.DestinationPlaceId > 0)
	trigger.Touched:Connect(function(hit)
		if Config.DestinationPlaceId <= 0 then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or pending[player] or CarryService.IsCarrying(player) then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return end
		local position = trigger.CFrame:PointToObjectSpace(root.Position)
		local half = trigger.Size / 2 + Vector3.new(3, 3, 3)
		if math.abs(position.X) > half.X or math.abs(position.Y) > half.Y or math.abs(position.Z) > half.Z then return end
		local now = os.clock()
		if lastAttempt[player] and now - lastAttempt[player] < Config.Cooldown then return end
		lastAttempt[player], pending[player] = now, true
		local ok, message = pcall(function()
			TeleportService:TeleportAsync(Config.DestinationPlaceId, { player })
		end)
		if not ok then
			pending[player] = nil
			warn("[HalloweenPortal] Teleport failed:", message)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, _, _, placeId)
		if placeId == Config.DestinationPlaceId then pending[player] = nil end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player], lastAttempt[player] = nil, nil
	end)
end

return Service
