--!nonstrict
-- Idle life for the Studio-authored Halloween decorations (Workspace.HalloweenWorld). Everything is purely
-- visual and LOCAL to each client (no replication cost, no server writes):
--   * HalloweenSpider / HalloweenFloat models bob (and slowly turn) around where they currently are. If a model
--     is moved by anything else its new place becomes the new base, so this never fights the designer's edits.
--   * HalloweenEyes blink now and then.
--   * The Pumpkin Merchant (tag HalloweenMerchant) breathes and looks around via his R6 Motor6D transforms.
-- Nothing runs in Edit mode, so the authored layout is always exactly what the designer placed.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local HalloweenDecor = {}

local RANGE = 220 -- only animate decorations this close to the camera
local STEP = 1 / 20

type Floater = { Base: CFrame, Last: CFrame, Phase: number, Bob: number, Spin: number, Speed: number }
local floaters: { [Model]: Floater } = {}
local blinkers: { [Model]: { Parts: { BasePart }, NextAt: number, OpenAt: number } } = {}
local merchants: { [Model]: { Root: Motor6D?, Neck: Motor6D?, Arm: Motor6D?, Phase: number } } = {}
local rng = Random.new()

local function registerFloater(model: Instance)
	if not model:IsA("Model") or floaters[model] then
		return
	end
	local pivot = model:GetPivot()
	floaters[model] = {
		Base = pivot,
		Last = pivot,
		Phase = model:GetAttribute("Phase") or 0,
		Bob = model:GetAttribute("Bob") or 0.3,
		Spin = model:GetAttribute("Spin") or 0.12,
		Speed = model:GetAttribute("Speed") or 1.4,
	}
end

local function registerEyes(model: Instance)
	if not model:IsA("Model") or blinkers[model] then
		return
	end
	local parts = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	blinkers[model] = { Parts = parts, NextAt = os.clock() + rng:NextNumber(1, 6), OpenAt = 0 }
end

local function registerMerchant(model: Instance)
	if not model:IsA("Model") or merchants[model] then
		return
	end
	local torso = model:FindFirstChild("Torso")
	local root = model:FindFirstChild("HumanoidRootPart")
	merchants[model] = {
		Root = root and root:FindFirstChild("RootJoint"),
		Neck = torso and torso:FindFirstChild("Neck"),
		Arm = torso and torso:FindFirstChild("Left Shoulder"),
		Phase = rng:NextNumber(0, 6),
	}
end

local function unregister(instance: Instance)
	floaters[instance :: Model] = nil
	blinkers[instance :: Model] = nil
	merchants[instance :: Model] = nil
end

function HalloweenDecor.Init()
	for _, tag in { "HalloweenSpider", "HalloweenFloat" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(registerFloater)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)
		for _, model in CollectionService:GetTagged(tag) do
			registerFloater(model)
		end
	end
	CollectionService:GetInstanceAddedSignal("HalloweenEyes"):Connect(registerEyes)
	CollectionService:GetInstanceRemovedSignal("HalloweenEyes"):Connect(unregister)
	for _, model in CollectionService:GetTagged("HalloweenEyes") do
		registerEyes(model)
	end
	CollectionService:GetInstanceAddedSignal("HalloweenMerchant"):Connect(registerMerchant)
	CollectionService:GetInstanceRemovedSignal("HalloweenMerchant"):Connect(unregister)
	for _, model in CollectionService:GetTagged("HalloweenMerchant") do
		registerMerchant(model)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < STEP then
			return
		end
		accumulator = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()

		for model, state in floaters do
			if not model:IsDescendantOf(workspace) then
				floaters[model] = nil
				continue
			end
			local current = model:GetPivot()
			-- something else moved it: that is the new base, we only ever add our own small offset
			if (current.Position - state.Last.Position).Magnitude > 0.02 then
				state.Base = current
			end
			if (state.Base.Position - eye).Magnitude > RANGE then
				state.Last = current
				continue
			end
			local lift = math.sin(now * state.Speed + state.Phase) * state.Bob
			local turn = math.sin(now * 0.55 + state.Phase * 1.7) * state.Spin
			local rotation = state.Base - state.Base.Position
			local nextPivot = CFrame.new(state.Base.Position + Vector3.new(0, lift, 0)) * rotation * CFrame.Angles(0, turn, 0)
			model:PivotTo(nextPivot)
			state.Last = nextPivot
		end

		for model, state in blinkers do
			if not model:IsDescendantOf(workspace) then
				blinkers[model] = nil
				continue
			end
			if state.OpenAt > 0 and now >= state.OpenAt then
				state.OpenAt = 0
				for _, part in state.Parts do part.Transparency = 0 end
			elseif state.OpenAt == 0 and now >= state.NextAt then
				state.OpenAt = now + 0.18
				state.NextAt = now + rng:NextNumber(2.5, 7)
				for _, part in state.Parts do part.Transparency = 1 end
			end
		end

		for model, state in merchants do
			if not model:IsDescendantOf(workspace) then
				merchants[model] = nil
				continue
			end
			local pivot = model:GetPivot().Position
			if (pivot - eye).Magnitude > 120 then
				continue
			end
			local t = now + state.Phase
			-- R6 joint frames: joint Z is world up for RootJoint/Neck, and the swing axis for the shoulders
			if state.Root then
				state.Root.Transform = CFrame.new(0, 0, math.sin(t * 1.6) * 0.06)
			end
			if state.Neck then
				state.Neck.Transform = CFrame.Angles(0, 0, math.sin(t * 0.45) * 0.45)
			end
			if state.Arm then
				state.Arm.Transform = CFrame.Angles(0, 0, math.sin(t * 1.1) * 0.09)
			end
		end
	end)
end

return HalloweenDecor
