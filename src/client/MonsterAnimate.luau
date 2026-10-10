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
	local camera = workspace.CurrentCamera
	local ctrls = {}
	local function add(m)
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			ctrls[m] = MonsterAnimator.new(m)
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
				MonsterAnimator.step(c, dt)
			end
		end
	end)
end

return MonsterAnimate
