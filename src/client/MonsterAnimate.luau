--[[
	MonsterAnimate (from MonsterAnimateClient.lua)
	Animates every model tagged "Monster" using ReplicatedStorage.Shared.MonsterAnimator.
	Server code controls a monster by setting:  model:SetAttribute("AnimState", "Walk")
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MonsterAnimator = require(ReplicatedStorage.Shared.MonsterAnimator)

local MonsterAnimate = {}

local MAX_DIST = 300
local CYCLE = { "Idle", "Walk", "Attack" }

function MonsterAnimate.Start()
	local ctrls = {}
	local function build(m)
		local controller = MonsterAnimator.new(m)
		controller.tracks = {}
		local animations = m:FindFirstChild("Animations")
		local animator = m:FindFirstChildWhichIsA("Animator", true)
		if animations and animator then
			for _, animation in animations:GetChildren() do
				if animation:IsA("Animation") and table.find(CYCLE, animation.Name) and animation.AnimationId ~= "" then
					local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
					if ok then
						track.Looped = animation.Name ~= "Attack"
						controller.tracks[animation.Name] = track
					else
						warn("[MonsterAnimate] Could not load", m.Name, animation.Name, track)
					end
				end
			end
		end
		ctrls[m] = controller
	end
	local function add(m)
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			build(m)
			-- A monster that appears at runtime (a follower, a spawned mother) can reach the client before all its
			-- joints have replicated; a controller built from a half-loaded model animates nothing. Rebuild it while
			-- joints are still arriving (first seconds only).
			local connection
			connection = m.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("Motor6D") and ctrls[m] then build(m) end
				if not m.Parent and connection then connection:Disconnect() end
			end)
			task.delay(4, function() if connection then connection:Disconnect() end end)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("Monster")) do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("Monster"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Monster"):Connect(function(m)
		ctrls[m] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then return end
		local now = os.clock()
		local camPos = camera.CFrame.Position
		for m, c in pairs(ctrls) do
			local root = m.PrimaryPart
			if not m.Parent or not root then
				ctrls[m] = nil
			elseif (root.Position - camPos).Magnitude < MAX_DIST * c.scale then
				if m:GetAttribute("ShowcaseCycle") then
					local off = m:GetAttribute("AnimSeed") or 0
					c.override = CYCLE[math.floor((now + off) / 4) % 3 + 1]
				end
				local state = c.override or m:GetAttribute("AnimState") or "Idle"
				local track = c.tracks[state]
				if c.activeTrack ~= track then
					if c.activeTrack then c.activeTrack:Stop(0.15) end
					c.activeTrack = track
					if track then track:Play(0.15) end
				end
				if not track then MonsterAnimator.step(c, dt) end
			end
		end
	end)
end

return MonsterAnimate
