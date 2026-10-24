-- Both portal directions are decided and validated on the server.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.HalloweenPortalConfig)
local Builder = require(Shared.HalloweenPortalBuilder)
local Arena = require(script.Parent.HalloweenArenaService)
local CarryService = require(script.Parent.CarryService)
local Service = {}
local pending = {}
local lastAttempt = {}
local started = false

local function connectPortal(portal: Model, outbound: boolean)
	local trigger = portal:FindFirstChild("TeleportTrigger")
	assert(trigger and trigger:IsA("BasePart"), "Halloween portal trigger is missing")
	portal:SetAttribute("DestinationPlaceId", outbound and Config.DestinationPlaceId or 0)
	portal:SetAttribute("TeleportEnabled", not outbound or Config.DestinationMode == "Arena" or Config.DestinationPlaceId > 0)
	portal:SetAttribute("Destination", outbound and "HalloweenArena" or "VoidRoad")
	trigger.Touched:Connect(function(hit)
		local external = outbound and Config.DestinationMode ~= "Arena"
		if external and Config.DestinationPlaceId <= 0 then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or pending[player] or (outbound and CarryService.IsCarrying(player)) then return end
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
			if external then
				TeleportService:TeleportAsync(Config.DestinationPlaceId, { player })
			else
				local destination = if outbound then Arena.NextArrival() else Config.Origin * CFrame.new(0, 3.5, -12)
				character:PivotTo(destination)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end)
		if not external or not ok then pending[player] = nil end
		if not ok then warn("[HalloweenPortal] Teleport failed:", message) end
	end)
end

function Service.Init()
	if started then return end
	started = true
	local portal = workspace:FindFirstChild("HalloweenPortal")
	if not portal then
		portal = Builder.Build(Config.Origin)
		portal.Parent = workspace
	end
	local arena = Arena.Init()
	connectPortal(portal, true)
	local returnPortal = arena:FindFirstChild("ReturnPortal")
	assert(returnPortal and returnPortal:IsA("Model"), "Halloween arena return portal is missing")
	connectPortal(returnPortal, false)
	TeleportService.TeleportInitFailed:Connect(function(player, _, _, placeId)
		if placeId == Config.DestinationPlaceId then pending[player] = nil end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player], lastAttempt[player] = nil, nil
	end)
end

return Service
