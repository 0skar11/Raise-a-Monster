--[[
	MonsterAnimator (ModuleScript — ReplicatedStorage.Shared)
	Procedural animation for Grow-A-Monster rigs.
	Drives Motor6D.Transform from each joint's attributes:
	  Role  : Root | Waist | Neck | Head | Jaw | Ear | Leg | Arm | Forearm | Wing | Wing2 | Tail | Spine | Top | Claw | Abdomen | SpiderLeg
	  Side  : +1 right / -1 left
	  Index : position in a chain (tails, spines, spider legs)
	  Front : true for front legs of 4-legged rigs
	  Axis  : "X" makes a tail bend up/down instead of side to side
	State comes from the model attribute "AnimState" = "Idle" | "Walk" | "Attack".
	Set the model attribute "Procedural" = false to hand control to your own AnimationTracks.
]]

local MonsterAnimator = {}

local STATES = { "Idle", "Walk", "Attack" }
local sin, abs, max, min, pi, floor = math.sin, math.abs, math.max, math.min, math.pi, math.floor

local function collect(model)
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			table.insert(joints, {
				motor = d,
				role = d:GetAttribute("Role") or d.Name,
				side = d:GetAttribute("Side") or 0,
				index = d:GetAttribute("Index") or 0,
				front = d:GetAttribute("Front"),
				axis = d:GetAttribute("Axis") or "Y",
			})
		end
	end
	return joints
end

-- Creatures with no legs at all (slimes, serpents...) hop along instead of walking.
local function isLegless(joints, rig)
	if rig == "Bird" then return false end
	for _, j in ipairs(joints) do
		if j.role == "Leg" or j.role == "SpiderLeg" then return false end
	end
	return true
end

function MonsterAnimator.new(model)
	local joints = collect(model)
	local rig = model:GetAttribute("RigType") or "Quad"
	return {
		model = model,
		joints = joints,
		hop = isLegless(joints, rig),
		rig = model:GetAttribute("RigType") or "Quad",
		scale = model:GetAttribute("Scale") or 1,
		t = (model:GetAttribute("AnimSeed") or 0),
		speed = 1,
		weights = { Idle = 1, Walk = 0, Attack = 0 },
		override = nil,
	}
end

local function legSign(j)
	if j.front == nil then return j.side end
	return (j.front and 1 or -1) * j.side * -1
end

-- Hop cycle for legless bodies: crouch, spring up, stretch in the air, land and squash.
local function hopPose(j, t)
	local r, s, i = j.role, j.side, j.index
	local rx, ry, rz, px, py, pz = 0, 0, 0, 0, 0, 0
	local phase = (t * 3) % pi / pi -- 0 at take-off, 1 at landing
	local air = sin(phase * pi) -- 0 on the ground, 1 at the apex
	local crouch = 1 - air
	if r == "Root" then py = 1.25 * air; rx = -0.22 * (0.5 - phase) * 2; pz = 0
	elseif r == "Top" then py = -0.3 * crouch
	elseif r == "Waist" then rx = 0.1 * (0.5 - phase) * 2
	elseif r == "Neck" then rx = 0.18 * (phase - 0.5) * 2 + 0.05 * crouch
	elseif r == "Head" then rx = 0.1 * crouch
	elseif r == "Jaw" then rx = -0.08 - 0.18 * air
	elseif r == "Ear" then rz = s * (0.1 + 0.3 * crouch); rx = 0.2 * (phase - 0.5)
	elseif r == "Tail" then
		if j.axis == "X" then rx = 0.25 * sin(phase * pi * 2 - i * 0.5) else ry = 0.3 * sin(t * 6 - i * 0.7) end
	elseif r == "Spine" then ry = 0.25 * sin(t * 3 - i * 0.8); rx = 0.22 * sin(phase * pi - i * 0.6)
	elseif r == "Arm" then rz = s * (0.1 + 0.5 * air)
	elseif r == "Forearm" then rx = 0.3 * air
	elseif r == "Wing" then rz = s * (0.1 + 0.6 * air)
	elseif r == "Wing2" then rz = s * 0.4 * sin(phase * pi - 0.5)
	elseif r == "Abdomen" then rx = 0.12 * (0.5 - phase)
	end
	return rx, ry, rz, px, py, pz
end

-- returns rx, ry, rz, px, py, pz (radians / studs at scale 1)
local function pose(rig, state, j, t, combo, hop)
	if hop and state == "Walk" then return hopPose(j, t) end
	local r, s, i = j.role, j.side, j.index
	local rx, ry, rz, px, py, pz = 0, 0, 0, 0, 0, 0

	if state == "Idle" then
		local w = 2
		if r == "Root" then
			if rig == "Slime" then py = 0.18 * abs(sin(t * 2.5))
			elseif rig == "Serpent" then ry = 0.06 * sin(t)
			else py = 0.06 * sin(t * w) end
		elseif r == "Waist" then ry = 0.06 * sin(t * 0.8); rx = 0.03 * sin(t * w)
		elseif r == "Neck" then rx = 0.06 * sin(t * 1.5); ry = 0.18 * sin(t * 0.6)
		elseif r == "Head" then rx = 0.05 * sin(t * 1.5 + 1)
		elseif r == "Jaw" then rx = -0.05 - 0.05 * sin(t * w)
		elseif r == "Ear" then rz = s * 0.12 * sin(t * 3 + s)
		elseif r == "Tail" then
			if j.axis == "X" then rx = 0.08 * sin(t * w - i * 0.5) else ry = 0.22 * sin(t * w - i * 0.7) end
		elseif r == "Spine" then ry = 0.12 * sin(t * w - i * 0.8)
		elseif r == "Wing" then rz = s * 0.12 * sin(t * w)
		elseif r == "Wing2" then rz = s * 0.1 * sin(t * w - 0.6)
		elseif r == "Arm" then rx = 0.05 * sin(t * w); rz = s * 0.04 * sin(t * w)
		elseif r == "Forearm" then rx = 0.12 + 0.05 * sin(t * w)
		elseif r == "Top" then py = 0.12 * sin(t * 2.5 + 1)
		elseif r == "Claw" then ry = s * 0.12 * sin(t * w)
		elseif r == "Abdomen" then rx = 0.05 * sin(t * w)
		elseif r == "SpiderLeg" then rz = s * 0.06 * sin(t * w + i)
		end

	elseif state == "Walk" then
		-- Full-body gait: legs/arms swing in opposition, the torso counter-twists, the spine travels a wave,
		-- head/neck stay stable against the bounce, and tail/ears/wings lag behind the body.
		local w = 6
		local ph = sin(t * w)
		local lag = sin(t * w - 0.9) -- secondary parts follow the main swing a beat late
		local bounce = sin(t * w * 2 - 1.2) -- two bounces per full stride
		local pant = sin(t * w * 2.2)
		if r == "Root" then
			if rig == "Slime" then py = 1.1 * abs(sin(t * 3)); rz = 0.06 * sin(t * 3)
			elseif rig == "Bird" then py = 1.4 + 0.35 * sin(t * 8); rx = -0.12; rz = 0.05 * sin(t * 4)
			elseif rig == "Serpent" then ry = 0.1 * sin(t * 3); rz = 0.04 * sin(t * 3 + 1)
			elseif rig == "Biped" then py = 0.08 + 0.1 * bounce; rz = 0.07 * ph; rx = -0.07 + 0.02 * bounce
			else py = 0.07 + 0.07 * bounce; rz = 0.04 * ph; rx = -0.04 + 0.02 * bounce end
		elseif r == "Leg" then
			if rig == "Bird" then rx = -0.7 + 0.25 * sin(t * 8 + (if s > 0 then 0 else pi))
			elseif rig == "Turtle" then ry = 0.45 * ph * legSign(j); rx = 0.12 * abs(ph)
			else rx = 0.7 * ph * legSign(j) end
		elseif r == "Arm" then
			if rig == "Biped" then rx = -0.7 * ph * s; rz = s * 0.06
			else rx = -0.55 * ph * s end
		elseif r == "Forearm" then rx = 0.4 + 0.3 * lag * s
		elseif r == "Waist" then ry = -0.14 * ph; rz = 0.04 * lag; rx = 0.03 * bounce -- chest twists against the hips
		elseif r == "Neck" then ry = 0.1 * ph; rx = 0.07 * bounce -- head stays level while the body swings
		elseif r == "Head" then rx = -0.05 * bounce; ry = 0.05 * lag
		elseif r == "Jaw" then rx = -0.1 - 0.08 * max(0, pant)
		elseif r == "Ear" then rz = s * 0.2 * lag; rx = 0.12 * bounce
		elseif r == "Tail" then
			if j.axis == "X" then rx = 0.14 * sin(t * w * 2 - i * 0.6) else ry = 0.4 * sin(t * w - i * 0.8) end
		elseif r == "Spine" then ry = 0.4 * sin(t * w - i * 0.9); rz = 0.06 * sin(t * w * 2 - i * 0.7)
		elseif r == "Wing" then
			if rig == "Bird" then rz = s * (0.15 + 0.75 * sin(t * 8))
			else rz = s * (0.2 + 0.25 * lag) end
		elseif r == "Wing2" then
			if rig == "Bird" then rz = s * 0.4 * sin(t * 8 - 0.8)
			else rz = s * 0.25 * sin(t * w - 1.1) end
		elseif r == "Top" then py = -0.25 * abs(sin(t * 3))
		elseif r == "SpiderLeg" then
			local g = ((i + (s > 0 and 1 or 0)) % 2 == 0) and 1 or -1
			ry = s * 0.38 * ph * g
			rz = s * 0.28 * max(0, ph * g)
		elseif r == "Claw" then ry = s * 0.15 * ph
		elseif r == "Abdomen" then rx = 0.08 * lag; rz = 0.04 * ph
		end

	elseif state == "Attack" and combo then
		-- كومبو إيدين (يمين شمال يمين شمال): t = ثواني من بداية الضربة، الضربة i بتنزل عند windup + (i-1)*interval
		local function reach(arm) -- 0 = جارد، 1 = إيد ممدودة
			local a = 0
			for n = 1, combo.hits do
				if (n % 2 == 1) == (arm > 0) then
					local x = (t - (combo.windup + (n - 1) * combo.interval)) / (combo.interval * 0.75)
					a = max(a, 1 - x * x)
				end
			end
			return max(0, a)
		end
		local aR, aL = reach(1), reach(-1)
		local a = if s > 0 then aR else aL
		local guard = min(1, t / max(0.05, combo.windup)) -- بيدخل وضع الجارد في الـ windup
		local twist = aR - aL
		if r == "Root" then py = -0.25 * guard; pz = -0.1 * (aR + aL); rx = -0.1 * guard
		elseif r == "Waist" then ry = 0.4 * twist; rx = -0.08 * guard
		elseif r == "Neck" then ry = -0.35 * twist; rx = 0.05
		elseif r == "Arm" then rx = (0.5 + 1.0 * a) * guard; rz = s * 0.12 * guard
		elseif r == "Forearm" then rx = (2.0 - 1.9 * a) * guard
		elseif r == "Leg" then rx = (if s > 0 then -0.2 else 0.3) * guard
		end
	elseif state == "Attack" then
		local P = 1.1
		local u = (t % P) / P
		local wave = sin(2 * pi * u)
		local wnd, stk = max(0, wave), max(0, -wave)
		local sw = stk - wnd -- -1 (windup) -> +1 (strike): الكنسة من اليمين للشمال
		if r == "Root" then
			if rig == "Slime" then py = 1.3 * wnd; pz = -0.9 * stk
			elseif rig == "Bird" then py = 1.0 + 0.6 * wnd; pz = -1.3 * stk; rx = -0.3 * stk
			elseif rig == "Biped" then py = -0.25 * wnd; pz = 0.3 * wnd - 0.55 * stk; rx = 0.12 * wnd - 0.2 * stk -- ينزل ويرجع ورا ثم يندفع قدام
			else pz = 0.35 * wnd - 0.9 * stk; rx = 0.1 * wnd - 0.15 * stk end
		elseif r == "Waist" then
			if rig == "Biped" then ry = 0.65 * sw; rx = 0.12 * wnd - 0.25 * stk -- الجذع يلف يمين ثم يكنس شمال
			else ry = -0.3 * wnd + 0.4 * stk; rx = 0.1 * wnd - 0.2 * stk end
		elseif r == "Neck" then
			if rig == "Biped" then rx = 0.1 * wnd - 0.1 * stk; ry = -0.45 * sw -- الراس تفضل على الهدف
			else rx = 0.25 * wnd - 0.35 * stk end
		elseif r == "Head" then rx = 0.15 * wnd - 0.2 * stk
		elseif r == "Jaw" then rx = -0.15 - 0.3 * wnd - 0.6 * stk
		elseif r == "Arm" then
			if rig == "Biped" then
				if s > 0 then rz = 1.45; ry = 0.7 * sw + 0.5 -- اليمين: مفرودة أفقي وبتكنس من ورا لقدام
				else rx = -0.6 - 0.6 * stk; rz = -0.25 * (wnd + stk) end -- الشمال: ورا للتوازن
			else rx = 2.3 * wnd - 0.4 * stk end
		elseif r == "Forearm" then
			if rig == "Biped" then rx = if s > 0 then 0.35 * wnd else 0.5
			else rx = 0.2 + 0.6 * wnd end
		elseif r == "Leg" then
			if rig == "Bird" then rx = 0.9 * stk
			elseif rig == "Biped" then rx = if s > 0 then -0.3 * wnd + 0.1 * stk else 0.3 * wnd + 0.15 * stk -- خطوة: الشمال قدام واليمين ورا
			elseif j.front then rx = 0.5 * wnd
			else rx = -0.3 * stk end
		elseif r == "Wing" then rz = s * (0.9 * wnd - 0.3 * stk)
		elseif r == "Wing2" then rz = s * (0.6 * wnd - 0.2 * stk)
		elseif r == "Tail" then
			if j.axis == "X" then rx = -0.06 * wnd + 0.13 * stk else ry = 0.6 * sin(4 * pi * u - i * 0.6) end
		elseif r == "Spine" then ry = 0.3 * sin(t * 6 - i * 0.9); rx = 0.06 * wnd
		elseif r == "Claw" then ry = s * (0.5 * wnd - 0.4 * stk)
		elseif r == "Ear" then rx = -0.4 * (wnd + stk)
		elseif r == "Top" then py = 0.3 * wnd
		elseif r == "Abdomen" then rx = 0.2 * wnd
		elseif r == "SpiderLeg" then
			if i == 1 then rz = s * 0.8 * wnd; ry = s * 0.4 * stk else rz = s * 0.05 * sin(t * 4 + i) end
		end
	end
	return rx, ry, rz, px, py, pz
end

-- apply current weights at current time
function MonsterAnimator.apply(ctrl)
	local sc = ctrl.scale
	local W = ctrl.weights
	for _, j in ipairs(ctrl.joints) do
		local ax, ay, az, bx, by, bz = 0, 0, 0, 0, 0, 0
		for _, st in ipairs(STATES) do
			local w = W[st]
			if w > 0.001 then
				local t = if st == "Attack" and ctrl.attackT then ctrl.attackT else ctrl.t
				local rx, ry, rz, px, py, pz = pose(ctrl.rig, st, j, t, if st == "Attack" then ctrl.combo else nil, ctrl.hop)
				ax = ax + rx * w; ay = ay + ry * w; az = az + rz * w
				bx = bx + px * w; by = by + py * w; bz = bz + pz * w
			end
		end
		j.motor.Transform = CFrame.new(bx * sc, by * sc, bz * sc) * CFrame.Angles(ax, ay, az)
	end
end

function MonsterAnimator.step(ctrl, dt)
	if ctrl.model:GetAttribute("Procedural") == false then return end
	local target = ctrl.override or ctrl.model:GetAttribute("AnimState") or "Idle"
	-- Big monsters take slower, heavier steps; small ones patter faster.
	local cadence = if target == "Walk" then math.clamp(1.3 / math.sqrt(max(0.5, ctrl.scale)), 0.6, 1.5) else 1
	ctrl.t = ctrl.t + dt * ctrl.speed * cadence
	-- Attack restarts on every swing; its strike peak (u = 0.75) lands when the windup ends.
	if target == "Attack" then
		if ctrl.lastTarget ~= "Attack" then ctrl.attackT = 0 end
		local windup = ctrl.model:GetAttribute("AttackWindup") or 0.8
		local hits = ctrl.model:GetAttribute("ComboHits")
		if ctrl.rig == "Biped" and hits and hits > 1 then
			ctrl.combo = { hits = hits, windup = windup, interval = ctrl.model:GetAttribute("ComboInterval") or 0.4 }
			ctrl.attackT = (ctrl.attackT or 0) + dt -- الكومبو بالثواني الحقيقية
		else
			ctrl.combo = nil
			ctrl.attackT = (ctrl.attackT or 0) + dt * (1.1 * 0.75 / max(0.2, windup))
		end
	end
	ctrl.lastTarget = target
	local k = min(1, dt * (if target == "Attack" then 12 else 6))
	for _, st in ipairs(STATES) do
		local tw = (st == target) and 1 or 0
		ctrl.weights[st] = ctrl.weights[st] + (tw - ctrl.weights[st]) * k
	end
	MonsterAnimator.apply(ctrl)
end

MonsterAnimator.STATES = STATES
return MonsterAnimator
