-- Execute production pursuit, turning, targeting and the fight coroutine.
-- Studio remains responsible for replication and native Motor6D rendering.
local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local base = table.clone(getfenv())
for key, value in r do base[key] = value end
-- This bundled Lune reverses Z in CFrame.lookAt (including +Z => -Z).
-- Supply Roblox's documented basis construction for this compatibility gap.
base.CFrame = table.clone(r.CFrame)
base.CFrame.lookAt = function(from, to, up)
	local forward = (to - from).Unit
	local right = forward:Cross(up or r.Vector3.yAxis).Unit
	return r.CFrame.fromMatrix(from, right, right:Cross(forward), -forward)
end
local function load(path, env, source)
	return luau.load(source or fs.readFile(path), { environment = env or base, debugName = path })()
end
local config = load("src/shared/Config.luau")
local arenaEnv = table.clone(base)
arenaEnv.script, arenaEnv.require = { Parent = { Config = "config" } }, function() return config end
local arena = load("src/shared/HalloweenArenaConfig.luau", arenaEnv)
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function near(a, b) return (a - b).Magnitude < 0.002 end
local function sameFrame(a, b)
	return near(a.Position, b.Position) and a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end
local origin = arena.Origin.Position
local now, players, effects, moved, threads = 0, {}, {}, {}, {}
local yielding = false
local env = table.clone(base)
env.os = table.clone(os); env.os.clock = function() return now end
env.math = table.clone(math); env.math.random = function() return 0 end
local function schedule(fn, delay)
	local record = { Thread = coroutine.create(fn), At = now + (delay or 0), Delay = delay or 0 }
	table.insert(threads, record)
end
env.task = {
	wait = function(seconds) if yielding then return coroutine.yield(seconds or 1/30) end; return seconds or 1/30 end,
	spawn = function(fn) schedule(fn) end,
	delay = function(seconds, fn) schedule(fn, seconds) end,
}
local shared = { Config = "config", HalloweenArenaConfig = "arena", Remotes = "remotes" }
local runService = { IsStudio = function() return false end, Heartbeat = { Wait = function() return env.task.wait(1/30) end } }
env.game = { GetService = function(_, name)
	if name == "Players" then return { GetPlayers = function() return players end }
	elseif name == "RunService" then return runService
	elseif name == "ReplicatedStorage" then return { Shared = shared }
	else return {} end
end }
env.script = { Parent = setmetatable({}, { __index = function(_, key) return key end }) }
env.require = function(key)
	if key == "config" then return config
	elseif key == "arena" then return arena
	elseif key == "remotes" then return { Get = function() return {
		BossFx = { FireAllClients = function(_, kind, data) table.insert(effects, { Kind = kind, Data = data, At = now }) end },
		PlayerHurt = { FireClient = function() end },
	} end }
	elseif key == "CharacterService" then return { SetSpeedFactor = function() end }
	else return { Announce = function() end } end
end
local source = fs.readFile("src/server/BossAttacks.luau"):gsub("return BossAttacks%s*$",
	"return {Nearest=nearestTarget,Step=chaseStep,Face=face,Targets=aliveTargets,StrikeCenter=strikeCenter,Vine=vineGrab,Run=BossAttacks.Run}")
local attack = load("src/server/BossAttacks.luau", env, source)
local eventEnv = table.clone(env)
eventEnv.require = function(key)
	if key == "Config" then return config elseif key == "HalloweenArenaConfig" then return arena
	elseif key == "Remotes" then return env.require("remotes") else return {} end
end
eventEnv.game = { GetService = function(_, name)
	if name == "ReplicatedStorage" then return { Shared = { Config = "Config", MonsterMath = "MonsterMath", HalloweenArenaConfig = "HalloweenArenaConfig", Remotes = "Remotes" } }
	else return {} end
end }
local facing = load("src/server/EventService.luau", eventEnv,
	fs.readFile("src/server/EventService.luau"):gsub("return EventService%s*$", "return spawnFacing"))
check(facing(origin).LookVector:Dot((arena.Origin:PointToWorldSpace(arena.ArrivalCenter) - origin).Unit) > .99999,
	"Spawn does not face the actual arrival courtyard")
local oldArrival = arena.ArrivalCenter
arena.ArrivalCenter = r.Vector3.new(1, 0, 0)
check(facing(origin).LookVector:Dot(r.Vector3.xAxis) > .99999, "Unit arrival vector fell back to the wrong direction")
arena.ArrivalCenter = oldArrival

local function characterAt(offset, health)
	local root = { CFrame = r.CFrame.new(origin + offset), Parent = true, Size = r.Vector3.new(2, 2, 1), AssemblyLinearVelocity = r.Vector3.zero }
	setmetatable(root, { __index = function(self, key)
		if key == "Position" then return self.CFrame.Position elseif key == "IsA" then return function() return true end end
	end })
	local humanoid = { Health = health or 1000, HipHeight = 2, FloorMaterial = r.Enum.Material.Slate }
	function humanoid:TakeDamage(amount) self.Health -= amount end
	local character = { FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end }
	return { Character = character }, root, humanoid
end
local function fixture(offset)
	local part = { CFrame = r.CFrame.new(origin + (offset or r.Vector3.zero) + r.Vector3.new(0, 14, 0)) * facing(origin).Rotation }
	local attributes = {}
	function part:GetAttribute(key) return attributes[key] end
	function part:SetAttribute(key, value) attributes[key] = value end
	setmetatable(part, { __index = function(self, key) if key == "Position" then return self.CFrame.Position end end })
	local authoredOffset = r.CFrame.new(2.5, 5.5, -1.25) * r.CFrame.Angles(.11, .37, -.08)
	local model = { Parent = true, Frame = part.CFrame * authoredOffset, Attributes = {} }
	function model:GetPivot() return self.Frame end
	function model:FindFirstChild() return nil end
	function model:PivotTo(frame) self.Frame = frame; table.insert(moved, { At = now, Frame = frame, Part = part.CFrame }) end
	function model:SetAttribute(key, value) self.Attributes[key] = value end
	local alive = true
	return { Part = part, Model = model, BodyRadius = 13, MoveRadius = 19, ModelOffset = authoredOffset,
		ArenaBoss = true, Ground = origin.Y, State = { IntroUntil = 0, Enraged = false, VulnerableUntil = 0 },
		IsAlive = function() return alive end, HealthFraction = function() return 1 end }, function() alive = false end
end
local nearPlayer, nearRoot, nearHumanoid = characterAt(r.Vector3.new(0, 3, 55))
local farPlayer, farRoot = characterAt(r.Vector3.new(0, 3, -85))
local deadPlayer = characterAt(r.Vector3.new(1, 3, 0), 0)
local stagingPlayer = characterAt(r.Vector3.new(0, 3, 123))
players = { farPlayer, deadPlayer, stagingPlayer, nearPlayer }
local ctx = fixture()
local nearest, distance = attack.Nearest(ctx)
check(nearest and nearest.Player == nearPlayer and math.abs(distance - 55) < .001, "Pursuit did not select nearest alive combat player")
check(#attack.Targets(ctx) == 2, "Dead/staging characters joined combat")
check(not attack.Step(ctx, nearest, .1), "Far target was immediately attackable")
check(near(ctx.Part.Position, origin + r.Vector3.new(0, 14, 1.4)), "Pursuit did not use configured server speed")
check(sameFrame(ctx.Model:GetPivot(), ctx.Part.CFrame * ctx.ModelOffset), "Visual did not follow hitbox with imported pivot")
check(ctx.Model.Attributes.AnimState == "Walk", "Moving Titan has no walk pose signal")
local previous = ctx.Part.CFrame
attack.Step(ctx, nearest, 30)
check((ctx.Part.Position - previous.Position).Magnitude <= 1.401, "Slow frame teleported Titan")
for _ = 1, 100 do if attack.Step(ctx, nearest, .1) then break end end
check(math.abs((nearRoot.Position - ctx.Part.Position).Magnitude^2 - (config.Boss.AttackRange^2 + 11^2)) < .02,
	"Boss did not stop at configured horizontal attack distance")
previous = ctx.Part.CFrame
check(attack.Step(ctx, nearest, .1) and ctx.Part.CFrame == previous and ctx.Model.Attributes.AnimState == "Idle",
	"Boss continued walking into player after reaching attack range")
attack.Face(ctx, r.Vector3.xAxis)
check(ctx.Part.CFrame.LookVector:Dot(r.Vector3.xAxis) > .99999 and near(ctx.Part.Position, previous.Position), "Attack facing moved ground anchor or faced wrong axis")
check(sameFrame(ctx.Model:GetPivot(), ctx.Part.CFrame * ctx.ModelOffset), "Turning discarded imported pivot/model yaw")

nearRoot.CFrame = arena.Origin * r.CFrame.new(0, 3, 123)
previous = ctx.Part.CFrame
check(not attack.Step(ctx, nearest, .1) and ctx.Part.CFrame == previous, "Departed target was chased into arrival")
check(attack.Nearest(ctx).Player == farPlayer, "Target not reacquired after arrival travel")
nearRoot.CFrame = arena.Origin * r.CFrame.new(0, 3, 20); nearHumanoid.Health = 0
check(attack.Nearest(ctx).Player == farPlayer, "Dead target retained pursuit priority")
nearHumanoid.Health = 1000
nearPlayer.Character = { FindFirstChild = function() return farRoot end, FindFirstChildOfClass = function() return nearHumanoid end }
check(not attack.Step(ctx, nearest, .1) and ctx.Part.CFrame == previous, "Stale character root moved the boss after respawn")

local boundary, stopBoundary = fixture(r.Vector3.new(68, 0, 0))
local edge, edgeRoot = characterAt(r.Vector3.new(89, 3, 0))
players = { edge, stagingPlayer }
local target = attack.Nearest(boundary)
check(attack.Step(boundary, target, .1), "Legal rim target was not attackable from safe footprint")
-- Pursuing a player diagonally along the rim can reach the wall before attack range.
boundary.Part.CFrame = r.CFrame.new(origin + r.Vector3.new(0, 14, 68)) * facing(origin).Rotation
boundary.Model:PivotTo(boundary.Part.CFrame * boundary.ModelOffset)
edgeRoot.CFrame = arena.Origin * r.CFrame.new(30, 3, 84)
for _ = 1, 100 do attack.Step(boundary, target, .1) end
check((r.Vector3.new(boundary.Part.Position.X, origin.Y, boundary.Part.Position.Z) - origin).Magnitude + boundary.MoveRadius + 3 <= arena.CombatRadius + .001,
	"Full visual footprint crossed arena wall")
check(arena.IsArenaBoss(boundary.Part.Position), "Moved boss lost arena identity")
check(#attack.Targets(boundary) == 1, "Moving boss made staging targetable")
local strike = attack.StrikeCenter(boundary, origin + r.Vector3.new(0, 0, 123), 9)
check((strike - origin).Magnitude + 9 + 1.5 <= arena.CombatRadius + .001, "Moved boss painted arrival hazards")
local frozen = boundary.Part.CFrame
boundary.State.IntroUntil = 100
check(not attack.Step(boundary, target, .1) and boundary.Part.CFrame == frozen, "Boss moved during entrance")
boundary.State.IntroUntil = 0; stopBoundary()
check(not attack.Step(boundary, target, .1) and boundary.Part.CFrame == frozen, "Dead boss kept moving")

-- Vine's repeated drag steps must keep the protected-arrival guard after movement.
threads = {}
local movedBoss = fixture(r.Vector3.new(20, 0, 30))
local grabbed, grabbedRoot = characterAt(r.Vector3.new(20, 3, 65))
players = { grabbed }
attack.Vine(movedBoss, nil, 1, 1)
local drag = nil
for _, record in threads do if record.At == now then drag = record.Thread end end
check(drag ~= nil, "Moved boss did not schedule a legal Vine grab")
yielding = true
local beforeDrag = grabbedRoot.CFrame
local ok, message = coroutine.resume(drag)
assert(ok, message)
check(grabbedRoot.CFrame ~= beforeDrag, "Vine from moved boss failed its first legal pull")
grabbedRoot.CFrame = arena.Origin * r.CFrame.new(0, 3, 123)
local arrivalFrame = grabbedRoot.CFrame
ok, message = coroutine.resume(drag)
assert(ok, message)
yielding = false
check(coroutine.status(drag) == "dead" and grabbedRoot.CFrame == arrivalFrame, "Moved boss dragged arrival player after travel")

-- Run the unmodified fight loop through approach, telegraph and damage impact.
now, effects, moved, threads = 0, {}, {}, {}
local fighter, fighterRoot, fighterHumanoid = characterAt(r.Vector3.new(0, 3, 60))
players = { fighter, stagingPlayer }
local running, stopRunning = fixture()
attack.Run(running)
local firstStrike, attackFrame, left = nil, nil, false
yielding = true
while now < 7 do
	local record = nil
	for _, item in threads do
		if coroutine.status(item.Thread) ~= "dead" and (not record or item.At < record.At) then record = item end
	end
	if not record or record.At > 7 then break end
	now = record.At
	local ok, delay = coroutine.resume(record.Thread, record.Delay)
	assert(ok, delay)
	if coroutine.status(record.Thread) ~= "dead" then record.Delay = delay or 1/30; record.At = now + record.Delay end
	if not firstStrike then
		for _, effect in effects do
			if effect.Kind == "Sweep" or effect.Kind == "Slam" then firstStrike, attackFrame = effect, running.Part.CFrame; break end
		end
	end
	if firstStrike and not left then
		check((fighterRoot.Position - r.Vector3.new(running.Part.Position.X, fighterRoot.Position.Y, running.Part.Position.Z)).Magnitude <= config.Boss.AttackRange + .1,
			"Fight loop attacked before approach completed")
		fighterRoot.CFrame = arena.Origin * r.CFrame.new(0, 3, 123)
		left = true
	end
	if firstStrike then check(running.Part.CFrame == attackFrame, "Boss slid during telegraph/recovery or chased arrival after strike") end
end
yielding = false
stopRunning()
check(firstStrike ~= nil and left, "Production fight loop never chased and attacked")
check(fighterHumanoid.Health == 1000, "Player who reached arrival during windup took damage")
check(sameFrame(running.Model:GetPivot(), running.Part.CFrame * running.ModelOffset), "Fight coroutine separated visual and hitbox")
print(("PASS: production boss pursuit, spawn facing, imported pivot, nearest eligibility, bounded movement, stopping, lifecycle and windup staging immunity (%d checks)"):format(checks))
