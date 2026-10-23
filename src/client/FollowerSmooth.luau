--!strict
-- Client-side interpolation for follower monsters. The server positions them ~20 times a second; this shows
-- them gliding at the display frame rate instead. Purely visual: it only moves the root of models inside
-- workspace.MonsterFollowers toward the pose the server last replicated.
local RunService = game:GetService("RunService")

local FollowerSmooth = {}

local RATE = 16 -- exponential catch-up rate (higher = tighter)
local SNAP_DISTANCE = 40 -- farther than this (respawn, zone travel) we just jump

type Entry = { Shown: CFrame, Written: CFrame, Target: CFrame }

function FollowerSmooth.Init()
	local folder = workspace:WaitForChild("MonsterFollowers", 30)
	if not folder then
		return
	end
	local entries: { [Model]: Entry } = {}
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			entries[child] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local rate = 1 - math.exp(-RATE * math.min(dt, 0.1))
		for _, model in folder:GetChildren() do
			local root = if model:IsA("Model") then model.PrimaryPart else nil
			if not model:IsA("Model") or not root then
				continue
			end
			local current = root.CFrame
			local entry = entries[model]
			if not entry then
				entries[model] = { Shown = current, Written = current, Target = current }
				continue
			end
			-- anything that differs from what we last wrote came from the server: that is the new target
			if current ~= entry.Written then
				entry.Target = current
			end
			if (entry.Shown.Position - entry.Target.Position).Magnitude > SNAP_DISTANCE then
				entry.Shown = entry.Target
			else
				entry.Shown = entry.Shown:Lerp(entry.Target, rate)
			end
			root.CFrame = entry.Shown
			entry.Written = root.CFrame
		end
	end)
end

return FollowerSmooth
