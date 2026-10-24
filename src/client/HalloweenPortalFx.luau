local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ArenaConfig = require(game:GetService("ReplicatedStorage").Shared.HalloweenArenaConfig)
local Fx = {}
local started = false

function Fx.Init()
	if started then return end
	started = true
	local portals = {}
	local function bind(portal)
		if not portal or portals[portal] then return end
		local trigger = portal:FindFirstChild("TeleportTrigger")
		if not trigger then return end
		local center = trigger.CFrame * CFrame.new(0, 1, -.12)
		local bands = {}
		for _, part in portal:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Vortex") then
				table.insert(bands, { Part = part, Offset = center:ToObjectSpace(part.CFrame) })
			end
		end
		portals[portal] = { Center = center, Bands = bands }
	end
	-- Own client effect only: the rest of the world keeps its existing lighting.
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "HalloweenArenaLocalTint"
	tint.TintColor = Color3.fromRGB(220, 212, 255)
	tint.Brightness, tint.Contrast, tint.Saturation = -.035, .1, -.08
	tint.Enabled = false
	tint.Parent = Lighting
	local elapsed = 0
	local refresh = 1
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		refresh += dt
		if refresh >= .25 then
			refresh = 0
			bind(workspace:FindFirstChild("HalloweenPortal"))
			local arena = workspace:FindFirstChild("HalloweenArena")
			bind(arena and arena:FindFirstChild("ReturnPortal"))
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local position = root and ArenaConfig.Origin:PointToObjectSpace(root.Position)
			tint.Enabled = position ~= nil and math.abs(position.X) <= 145 and position.Z >= -145 and position.Z <= 160
		end
		for portal, data in portals do
			if not portal.Parent then
				portals[portal] = nil
			else
				local spin = data.Center * CFrame.Angles(0, 0, elapsed * .32)
				for _, band in data.Bands do
					if band.Part.Parent then band.Part.CFrame = spin * band.Offset end
				end
			end
		end
	end)
end

return Fx
