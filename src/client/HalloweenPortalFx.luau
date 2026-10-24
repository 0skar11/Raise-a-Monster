local RunService = game:GetService("RunService")
local Fx = {}

function Fx.Init()
	local portal = workspace:WaitForChild("HalloweenPortal", 30)
	if not portal then return end
	local trigger = portal:WaitForChild("TeleportTrigger", 10)
	if not trigger then return end
	-- The trigger center is y=12; the vortex center is y=13 in builder space.
	local center = trigger.CFrame * CFrame.new(0, 1, -.12)
	local bands = {}
	for _, part in portal:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Vortex") then
			table.insert(bands, { Part = part, Offset = center:ToObjectSpace(part.CFrame) })
		end
	end
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not portal.Parent then connection:Disconnect(); return end
		elapsed += dt
		local spin = center * CFrame.Angles(0, 0, elapsed * .32)
		for _, band in bands do band.Part.CFrame = spin * band.Offset end
	end)
end

return Fx
