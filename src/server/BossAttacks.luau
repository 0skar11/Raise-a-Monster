--!strict
-- The Pumpkin Titan's attack kit. Everything that matters (who gets hit, damage, timing) is decided here on the server;
-- the client (BossFx) only draws the telegraphs and effects from the "BossFx" remote.
--
-- Phases follow the boss's health: below 75% it adds Pumpkin Bombs and Vine Grab, below 50% it enrages and adds Heart
-- Pulse and chained combos, below 25% it adds Jack-o'-lantern Rain and chains up to three moves with short cooldowns.
-- Every phase also shortens the telegraphs and raises the damage.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local HalloweenService = require(script.Parent.HalloweenService)
local MonsterService = require(script.Parent.MonsterService)

local remotes = Remotes.Get()
local attacks = Config.Boss.Attacks

export type Context = {
	Part: BasePart, -- the invisible hitbox
	Model: Model?,
	BodyRadius: number,
	Ground: number, -- ground height under the boss
	IsAlive: () -> boolean,
	HealthFraction: () -> number,
	State: { VulnerableUntil: number, Enraged: boolean, IntroUntil: number },
}

type Target = { Player: Player, Root: BasePart, Humanoid: Humanoid }

local BossAttacks = {}

local PLAYER_RADIUS = 1.5

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function fx(kind: string, data: { [string]: any })
	remotes.BossFx:FireAllClients(kind, data)
end

local function phaseOf(fraction: number): number
	local at = attacks.PhaseAt
	if fraction <= at[3] then
		return 4
	elseif fraction <= at[2] then
		return 3
	elseif fraction <= at[1] then
		return 2
	end
	return 1
end

local function origin(ctx: Context): Vector3
	return Vector3.new(ctx.Part.Position.X, ctx.Ground, ctx.Part.Position.Z)
end

local function headPosition(ctx: Context): Vector3
	local head = ctx.Model and ctx.Model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return ctx.Part.Position + Vector3.new(0, ctx.Part.Size.Y * 0.4, 0)
end

local function heartPosition(ctx: Context): Vector3
	local heart = ctx.Model and ctx.Model:FindFirstChild("Heart_Gold")
	if heart and heart:IsA("BasePart") then
		return heart.Position
	end
	return ctx.Part.Position
end

local function aliveTargets(ctx: Context): { Target }
	local list: { Target } = {}
	local center = origin(ctx)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and flat(root.Position - center).Magnitude <= attacks.AggroRange then
			table.insert(list, { Player = player, Root = root, Humanoid = humanoid })
		end
	end
	return list
end

local function airborne(target: Target, ground: number): boolean
	local foot = target.Root.Position.Y - target.Humanoid.HipHeight - target.Root.Size.Y / 2
	return target.Humanoid.FloorMaterial == Enum.Material.Air and foot > ground + 1.8
end

local function hurt(target: Target, amount: number, color: Color3)
	if target.Humanoid.Health <= 0 then
		return
	end
	target.Humanoid:TakeDamage(amount)
	remotes.PlayerHurt:FireClient(target.Player, math.floor(amount + 0.5), color)
end

local function pause(ctx: Context, seconds: number): boolean
	task.wait(seconds)
	return ctx.IsAlive()
end

local function setAnim(ctx: Context, state: string)
	if ctx.Model then
		ctx.Model:SetAttribute("AnimState", state)
	end
end

-- Turn the model toward a direction (smoothly), keeping its position.
local function face(ctx: Context, direction: Vector3)
	local model = ctx.Model
	if not model or direction.Magnitude < 0.01 then
		return
	end
	local startCFrame = model:GetPivot()
	local position = startCFrame.Position
	local flatDir = flat(direction).Unit
	local goal = CFrame.lookAt(position, position + flatDir) * CFrame.Angles(0, math.rad(Config.Boss.ModelYaw), 0)
	for step = 1, 4 do
		if not ctx.IsAlive() or not model.Parent then
			return
		end
		model:PivotTo(startCFrame:Lerp(goal, step / 4))
		task.wait(0.04)
	end
end

local ORANGE = Color3.fromRGB(255, 120, 30)
local RED = Color3.fromRGB(255, 70, 40)
local GREEN = Color3.fromRGB(120, 230, 90)

-- Attacks ---------------------------------------------------------------------------------------------------------
-- Each one blocks until its strike lands. `scale` shortens the telegraph, `power` multiplies damage.

local function inCone(root: Vector3, from: Vector3, direction: Vector3, range: number, halfAngle: number, bodyRadius: number): boolean
	local offset = flat(root - from)
	local distance = offset.Magnitude
	if distance > range + PLAYER_RADIUS then
		return false
	end
	if distance <= bodyRadius + PLAYER_RADIUS then
		return true
	end
	return offset.Unit:Dot(direction) >= math.cos(math.rad(halfAngle))
end

local function sweep(ctx: Context, target: Target, scale: number, power: number)
	local from = origin(ctx)
	local direction = flat(target.Root.Position - from)
	direction = if direction.Magnitude > 0.1 then direction.Unit else flat(ctx.Part.CFrame.LookVector).Unit
	face(ctx, direction)
	local windup = attacks.SweepWindup * scale
	local passes = if ctx.State.Enraged then 2 else 1
	for pass = 1, passes do
		if pass == 2 then
			-- the second swing re-aims at whoever is closest now
			local list = aliveTargets(ctx)
			local best: Target? = nil
			local bestDistance = math.huge
			for _, candidate in list do
				local distance = flat(candidate.Root.Position - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
			if best then
				direction = flat(best.Root.Position - from).Unit
				face(ctx, direction)
			end
			windup = attacks.SweepWindup * scale * 0.55
		end
		setAnim(ctx, "Attack")
		fx("Sweep", { Origin = from, Direction = direction, Range = attacks.SweepRange, Angle = attacks.SweepHalfAngle * 2, Windup = windup, Pass = pass })
		if not pause(ctx, windup) then
			return
		end
		for _, candidate in aliveTargets(ctx) do
			if inCone(candidate.Root.Position, from, direction, attacks.SweepRange, attacks.SweepHalfAngle, ctx.BodyRadius) then
				hurt(candidate, Config.Boss.Damage * attacks.SweepDamage * power, ORANGE)
			end
		end
		if not pause(ctx, 0.15) then
			return
		end
	end
	setAnim(ctx, "Idle")
end

local function slam(ctx: Context, _target: Target, scale: number, power: number, phase: number)
	local from = origin(ctx)
	local windup = attacks.SlamWindup * scale
	local waves = { { attacks.SlamRadius, 0 }, { attacks.SlamOuter, attacks.SlamWaveGap } }
	if phase >= 4 then
		table.insert(waves, { attacks.SlamFar, attacks.SlamWaveGap * 2 })
	end
	setAnim(ctx, "Attack")
	fx("Slam", { Origin = from, Waves = waves, Windup = windup, Inner = ctx.BodyRadius })
	if not pause(ctx, windup) then
		return
	end
	local previous = 0
	local elapsed = 0
	for index, wave in waves do
		local radius, delay = wave[1], wave[2]
		if delay > elapsed then
			if not pause(ctx, delay - elapsed) then
				return
			end
			elapsed = delay
		end
		for _, candidate in aliveTargets(ctx) do
			local distance = flat(candidate.Root.Position - from).Magnitude
			local lower = if index == 1 then 0 else previous
			if distance >= lower and distance <= radius + PLAYER_RADIUS and not airborne(candidate, ctx.Ground) then
				hurt(candidate, Config.Boss.Damage * attacks.SlamDamage * power, RED)
			end
		end
		previous = radius
	end
	setAnim(ctx, "Idle")
end

local function firePatch(ctx: Context, center: Vector3, radius: number, power: number)
	fx("BombFire", { Center = center, Radius = radius, Duration = attacks.BombFireSeconds })
	task.spawn(function()
		local ticks = math.floor(attacks.BombFireSeconds / 0.5)
		for _ = 1, ticks do
			task.wait(0.5)
			if not ctx.IsAlive() then
				return
			end
			for _, candidate in aliveTargets(ctx) do
				if flat(candidate.Root.Position - center).Magnitude <= radius + PLAYER_RADIUS and not airborne(candidate, ctx.Ground) then
					hurt(candidate, Config.Boss.Damage * attacks.BombFireDamage * power, ORANGE)
				end
			end
		end
	end)
end

local function bombs(ctx: Context, _target: Target, scale: number, power: number, phase: number)
	local list = aliveTargets(ctx)
	if #list == 0 then
		return
	end
	local count = math.min(10, 2 + phase + #list)
	local from = headPosition(ctx)
	local windup = attacks.BombWindup * scale
	setAnim(ctx, "Attack")
	for index = 1, count do
		if not ctx.IsAlive() then
			return
		end
		local victim = list[(index - 1) % #list + 1]
		local velocity = flat(victim.Root.AssemblyLinearVelocity)
		-- later phases lead the target, so just walking away in a line stops working
		local lead = velocity * (0.5 + 0.18 * phase)
		local scatter = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * (if index <= #list then 2 else 12)
		local center = Vector3.new(victim.Root.Position.X, ctx.Ground, victim.Root.Position.Z) + lead + scatter
		fx("Bomb", { From = from, Center = center, Radius = attacks.BombRadius, Windup = windup })
		task.delay(windup, function()
			if not ctx.IsAlive() then
				return
			end
			for _, candidate in aliveTargets(ctx) do
				if flat(candidate.Root.Position - center).Magnitude <= attacks.BombRadius + PLAYER_RADIUS then
					hurt(candidate, Config.Boss.Damage * attacks.BombDamage * power, ORANGE)
				end
			end
			firePatch(ctx, center, attacks.BombRadius * 0.9, power)
		end)
		task.wait(attacks.BombStagger)
	end
	setAnim(ctx, "Idle")
end

local function vineGrab(ctx: Context, _target: Target, scale: number, power: number)
	local list = aliveTargets(ctx)
	if #list == 0 then
		return
	end
	-- it goes for the player furthest away: standing back is not safe
	local from = origin(ctx)
	local victim = list[1]
	local far = -1.0
	for _, candidate in list do
		local distance = flat(candidate.Root.Position - from).Magnitude
		if distance > far then
			victim, far = candidate, distance
		end
	end
	local center = Vector3.new(victim.Root.Position.X, ctx.Ground, victim.Root.Position.Z)
	local windup = attacks.VineWindup * scale
	face(ctx, center - from)
	setAnim(ctx, "Attack")
	fx("Vine", { From = heartPosition(ctx), Base = from, Center = center, Radius = attacks.VineRadius, Windup = windup })
	if not pause(ctx, windup) then
		return
	end
	for _, candidate in aliveTargets(ctx) do
		if flat(candidate.Root.Position - center).Magnitude <= attacks.VineRadius + PLAYER_RADIUS and not airborne(candidate, ctx.Ground) then
			hurt(candidate, Config.Boss.Damage * attacks.VineDamage * power, GREEN)
			CharacterService.SetSpeedFactor(candidate.Player, "BossRoot", 0)
			task.delay(attacks.VineRootSeconds, function()
				CharacterService.SetSpeedFactor(candidate.Player, "BossRoot", nil)
			end)
			fx("VineGrabbed", { Player = candidate.Player, Seconds = attacks.VineRootSeconds })
			-- drag the victim to the boss's feet in a few quick steps
			local destination = from + flat(candidate.Root.Position - from).Unit * (ctx.BodyRadius + 6)
			task.spawn(function()
				for step = 1, 6 do
					if candidate.Humanoid.Health <= 0 or not candidate.Root.Parent then
						return
					end
					local here = candidate.Root.Position
					local target = Vector3.new(destination.X, here.Y, destination.Z)
					candidate.Root.CFrame = CFrame.new(here:Lerp(target, step / 6)) * candidate.Root.CFrame.Rotation
					task.wait(0.06)
				end
			end)
		end
	end
	setAnim(ctx, "Idle")
end

local function heartPulse(ctx: Context, _target: Target, scale: number, power: number, phase: number)
	local from = origin(ctx)
	local windup = attacks.PulseWindup * scale
	local count = if phase >= 4 then 4 else 3
	local base = math.random() * math.tau
	local safe: { Vector3 } = {}
	for index = 1, count do
		local angle = base + (index - 1) * math.tau / count + (math.random() - 0.5) * 0.5
		local distance = 28 + math.random() * 30
		table.insert(safe, Vector3.new(from.X + math.cos(angle) * distance, ctx.Ground, from.Z + math.sin(angle) * distance))
	end
	-- while it charges, the chest is exposed: hits on the boss do extra damage
	ctx.State.VulnerableUntil = os.clock() + windup + 0.5
	setAnim(ctx, "Attack")
	fx("HeartPulse", { Origin = from, Heart = heartPosition(ctx), Safe = safe, SafeRadius = attacks.PulseSafeRadius, Radius = attacks.PulseRadius, Windup = windup })
	if not pause(ctx, windup) then
		return
	end
	for _, candidate in aliveTargets(ctx) do
		local position = flat(candidate.Root.Position)
		local covered = false
		for _, spot in safe do
			if (position - flat(spot)).Magnitude <= attacks.PulseSafeRadius then
				covered = true
				break
			end
		end
		if not covered and flat(candidate.Root.Position - from).Magnitude <= attacks.PulseRadius then
			hurt(candidate, Config.Boss.Damage * attacks.PulseDamage * power, Color3.fromRGB(255, 200, 80))
		end
	end
	if not pause(ctx, 0.4) then
		return
	end
	setAnim(ctx, "Idle")
end

local function rain(ctx: Context, _target: Target, scale: number, power: number)
	local deadline = os.clock() + attacks.RainSeconds
	local windup = attacks.RainWindup * scale
	setAnim(ctx, "Attack")
	fx("RainStart", { Origin = origin(ctx), Seconds = attacks.RainSeconds })
	local drops = 0
	while os.clock() < deadline and ctx.IsAlive() do
		local list = aliveTargets(ctx)
		if #list == 0 then
			break
		end
		local victim = list[math.random(1, #list)]
		drops += 1
		local golden = drops % 7 == 0
		local aimed = drops % 3 == 0
		local velocity = flat(victim.Root.AssemblyLinearVelocity)
		local offset = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * (if aimed then 3 else 18)
		local center = Vector3.new(victim.Root.Position.X, ctx.Ground, victim.Root.Position.Z) + offset + (if aimed then velocity * 0.6 else Vector3.zero)
		fx("Rain", { Center = center, Radius = attacks.RainRadius, Windup = windup, Golden = golden })
		task.delay(windup, function()
			if not ctx.IsAlive() then
				return
			end
			for _, candidate in aliveTargets(ctx) do
				if flat(candidate.Root.Position - center).Magnitude <= attacks.RainRadius + PLAYER_RADIUS then
					if golden then
						HalloweenService.AddCandy(candidate.Player, attacks.RainCandy)
					else
						hurt(candidate, Config.Boss.Damage * attacks.RainDamage * power, ORANGE)
					end
				end
			end
		end)
		task.wait(attacks.RainTick * scale)
	end
	setAnim(ctx, "Idle")
	pause(ctx, windup)
end

-- The fight loop ---------------------------------------------------------------------------------------------------

local function enrage(ctx: Context)
	setAnim(ctx, "Attack")
	MonsterService.Announce("💢 The Pumpkin Titan is ENRAGED! Its swings are faster and its heart is exposed!", Color3.fromRGB(255, 110, 40))
	fx("Rage", { Origin = origin(ctx), Seconds = attacks.EnrageSeconds })
	if ctx.Model then
		ctx.Model:SetAttribute("Enraged", true)
	end
	ctx.State.Enraged = true
	pause(ctx, attacks.EnrageSeconds)
	setAnim(ctx, "Idle")
end

type Move = { Name: string, Weight: number, MinPhase: number }

function BossAttacks.Run(ctx: Context)
	task.spawn(function()
		local phase = 1
		local lastPulse = -math.huge
		local lastRain = -math.huge
		local function runMoveUnsafe(name: string, pick: Target, scale: number, power: number, movePhase: number)
			if name == "Sweep" then
				sweep(ctx, pick, scale, power)
			elseif name == "Slam" then
				slam(ctx, pick, scale, power, movePhase)
			elseif name == "Bombs" then
				bombs(ctx, pick, scale, power, movePhase)
			elseif name == "Vine" then
				vineGrab(ctx, pick, scale, power)
			elseif name == "Pulse" then
				lastPulse = os.clock()
				heartPulse(ctx, pick, scale, power, movePhase)
			elseif name == "Rain" then
				lastRain = os.clock()
				rain(ctx, pick, scale, power)
			end
		end
		-- a bug in one move must never stop the whole fight
		local function runMove(name: string, pick: Target, scale: number, power: number, movePhase: number)
			local ok, err = pcall(runMoveUnsafe, name, pick, scale, power, movePhase)
			if not ok then
				warn("[BossAttacks]", name, err)
				setAnim(ctx, "Idle")
			end
		end
		local last = ""
		local function choose(target: Target, distance: number): string
			local pool: { Move } = {
				{ Name = "Sweep", Weight = if distance < 46 then 4 else 0.6, MinPhase = 1 },
				{ Name = "Slam", Weight = if distance < 64 then 3 else 1, MinPhase = 1 },
				{ Name = "Bombs", Weight = 2.5, MinPhase = 2 },
				{ Name = "Vine", Weight = 2, MinPhase = 2 },
				{ Name = "Pulse", Weight = if os.clock() - lastPulse > attacks.PulseCooldown then 2.5 else 0, MinPhase = 3 },
				{ Name = "Rain", Weight = if os.clock() - lastRain > attacks.RainCooldown then 3 else 0, MinPhase = 4 },
			}
			local total = 0
			for _, move in pool do
				if move.MinPhase <= phase and move.Name ~= last then
					total += move.Weight
				end
			end
			local roll = math.random() * total
			for _, move in pool do
				if move.MinPhase <= phase and move.Name ~= last then
					roll -= move.Weight
					if roll <= 0 then
						return move.Name
					end
				end
			end
			return "Slam"
		end

		while ctx.IsAlive() do
			task.wait(0.25)
			local list = aliveTargets(ctx)
			if #list == 0 or os.clock() < ctx.State.IntroUntil then
				continue
			end
			-- Studio only: set the attribute DebugAttack (Sweep/Slam/Bombs/Vine/Pulse/Rain) on the BigBoss part to fire a move
			-- right now, and DebugPhase to pick the phase it is used at.
			local forced = if RunService:IsStudio() then ctx.Part:GetAttribute("DebugAttack") else nil
			if type(forced) == "string" then
				ctx.Part:SetAttribute("DebugAttack", nil)
				local forcedPhase = ctx.Part:GetAttribute("DebugPhase")
				local usePhase = if type(forcedPhase) == "number" then forcedPhase else phase
				if usePhase >= 3 and not ctx.State.Enraged then
					ctx.State.Enraged = true
					if ctx.Model then
						ctx.Model:SetAttribute("Enraged", true)
					end
				end
				local debugScale = ctx.Part:GetAttribute("DebugScale") -- slow telegraphs down to inspect them
				local forcedScale = if type(debugScale) == "number" then debugScale else attacks.WindupScale[usePhase]
				runMove(forced, list[1], forcedScale, attacks.DamageScale[usePhase], usePhase)
				continue
			end
			local newPhase = phaseOf(ctx.HealthFraction())
			if newPhase > phase then
				phase = newPhase
				fx("Phase", { Phase = phase, Origin = origin(ctx) })
				if phase == 2 then
					MonsterService.Announce("🎃 The Titan is waking up... Bombs and grasping vines!", Color3.fromRGB(255, 170, 60))
				elseif phase == 4 then
					MonsterService.Announce("☠️ The Titan is desperate! Pumpkins rain from the sky!", Color3.fromRGB(255, 90, 60))
				end
				if phase >= 3 and not ctx.State.Enraged then
					enrage(ctx)
					continue
				end
			end
			local scale = attacks.WindupScale[phase] * (if ctx.State.Enraged then 0.92 else 1)
			local power = attacks.DamageScale[phase]
			local from = origin(ctx)
			local chain = 1
			local chance = attacks.ChainChance[phase]
			if math.random() < chance then
				chain = if phase >= 4 and math.random() < 0.5 then 3 else 2
			end
			for link = 1, chain do
				if not ctx.IsAlive() then
					break
				end
				local current = aliveTargets(ctx)
				if #current == 0 then
					break
				end
				local pick = current[1]
				local pickDistance = math.huge
				for _, candidate in current do
					local distance = flat(candidate.Root.Position - from).Magnitude
					if distance < pickDistance then
						pick, pickDistance = candidate, distance
					end
				end
				local name = choose(pick, pickDistance)
				last = name
				runMove(name, pick, scale, power, phase)
				if link < chain then
					task.wait(0.35 * scale)
				end
			end
			task.wait(attacks.Cooldown[phase] * (if ctx.State.Enraged then 0.85 else 1))
		end
	end)
end

return BossAttacks
