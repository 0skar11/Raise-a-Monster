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
	local bossLabel: TextLabel? = nil
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
		if portal.Name == "HalloweenPortal" then
			-- boss respawn timer floating above the entrance portal
			local box, size = portal:GetBoundingBox()
			local anchor = Instance.new("Part")
			anchor.Name = "BossTimerAnchor"
			anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
			anchor.Transparency = 1
			anchor.Size = Vector3.one
			anchor.Position = box.Position + Vector3.new(0, size.Y / 2 + 5, 0)
			anchor.Parent = portal
			local gui = Instance.new("BillboardGui")
			gui.Name = "BossTimer"
			gui.Adornee = anchor
			gui.Size = UDim2.fromOffset(300, 84)
			gui.AlwaysOnTop = true
			gui.MaxDistance = 400
			gui.Parent = anchor
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.RichText = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.2
			label.Parent = gui
			bossLabel = label
		end
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
		if bossLabel and bossLabel.Parent then
			if workspace:GetAttribute("BossAlive") then
				bossLabel.Text = '<font color="#FF6A3C">💀 PUMPKIN TITAN IS ALIVE!</font>'
			else
				local nextAt = workspace:GetAttribute("BossNextSpawnAt")
				if type(nextAt) == "number" then
					local left = math.max(0, math.ceil(nextAt - workspace:GetServerTimeNow()))
					bossLabel.Text = string.format('<font color="#C878FF">💀 BOSS SPAWNS IN</font>\n%02d:%02d', left // 60, left % 60)
				else
					bossLabel.Text = '<font color="#C878FF">💀 BOSS</font>'
				end
			end
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
