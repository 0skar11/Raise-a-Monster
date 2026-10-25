-- Run the production Vine coroutine, relocating its victim between real drag steps.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local base = table.clone(getfenv())
for key, value in r do base[key] = value end
local function load(path, env)
	return luau.load(fs.readFile(path), { environment = env or base, debugName = path })()
end
local config = load("src/shared/Config.luau")
local arenaEnv = table.clone(base)
arenaEnv.script = { Parent = { Config = "config" } }
arenaEnv.require = function() return config end
local arena = load("src/shared/HalloweenArenaConfig.luau", arenaEnv)
local source = fs.readFile("src/server/BossAttacks.luau"):gsub("return BossAttacks%s*$", "return vineGrab")
local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end

local function scenario(change, expectedCancel)
	local parent = r.Instance.new("Folder")
	local backingRoot = r.Instance.new("Part")
	-- Lune does not couple Part.Position to CFrame like Studio does.
	local root = setmetatable({}, {
		__index = function(_, key)
			if key == "Position" then return backingRoot.CFrame.Position end
			if key == "IsA" then return function(_, className) return backingRoot:IsA(className) end end
			return backingRoot[key]
		end,
		__newindex = function(_, key, value) backingRoot[key] = value end,
	})
	root.Name, root.Parent = "HumanoidRootPart", parent
	root.CFrame = arena.Origin * r.CFrame.new(0, 3, 60)
	root.AssemblyLinearVelocity = r.Vector3.zero
	local humanoid = { Health = 1000, HipHeight = 2, FloorMaterial = r.Enum.Material.Slate }
	function humanoid:TakeDamage(amount) self.Health -= amount end
	local character = {
		FindFirstChild = function() return root end,
		FindFirstChildOfClass = function() return humanoid end,
	}
	local player = { Character = character }
	local contextAlive = true
	local ctx = {
		Part = { Position = arena.Origin.Position }, Ground = arena.Origin.Position.Y,
		BodyRadius = 10, IsAlive = function() return contextAlive end,
	}
	local queue, delays, speeds = {}, {}, {}
	local inPull = false
	local env = table.clone(base)
	env.task = {
		wait = function(seconds) if inPull then coroutine.yield() end; return seconds end,
		spawn = function(fn) table.insert(queue, coroutine.create(fn)) end,
		delay = function(seconds, fn) table.insert(delays, { Seconds = seconds, Run = fn }) end,
	}
	local shared = { Config = "config", HalloweenArenaConfig = "arena", Remotes = "remotes" }
	env.game = { GetService = function(_, name)
		if name == "Players" then return { GetPlayers = function() return { player } end }
		elseif name == "ReplicatedStorage" then return { Shared = shared }
		else return {} end
	end }
	env.script = { Parent = { CharacterService = "character", HalloweenService = "halloween", MonsterService = "monster" } }
	env.require = function(key)
		if key == "config" then return config
		elseif key == "arena" then return arena
		elseif key == "remotes" then return { Get = function() return {
			BossFx = { FireAllClients = function() end }, PlayerHurt = { FireClient = function() end },
		} end }
		elseif key == "character" then return { SetSpeedFactor = function(_, name, factor)
			check(name == "BossRoot", "Unexpected speed factor")
			table.insert(speeds, factor == nil and "reset" or factor)
		end }
		else return {} end
	end
	local vine = luau.load(source, { environment = env })()
	vine(ctx, nil, 1, 1)
	check(#queue == 1 and #delays == 1, "Vine did not land and schedule its drag/reset")
	check(speeds[1] == 0, "Vine no longer roots the victim")
	local function step()
		inPull = true
		local ok, message = coroutine.resume(queue[1])
		inPull = false
		assert(ok, message)
	end
	local before = root.CFrame
	step()
	check(root.CFrame ~= before, "Initial legal drag step did not move the victim")
	if change then change(root, humanoid, player, function() contextAlive = false end, parent) end
	local relocated = root.CFrame
	local velocity = root.AssemblyLinearVelocity
	while coroutine.status(queue[1]) ~= "dead" do step() end
	if expectedCancel then
		check(root.CFrame == relocated, "Vine dragged a departed/dead/replaced victim after the next wait")
		check(root.AssemblyLinearVelocity == velocity, "Vine changed departed victim velocity")
	else
		check(math.abs((root.Position - arena.Origin.Position).Z - 16) < .001, "Legal six-step drag stopped early")
	end
	check(delays[1].Seconds == config.Boss.Attacks.VineRootSeconds, "Root reset duration changed")
	delays[1].Run()
	check(speeds[#speeds] == "reset", "Cancelled drag left BossRoot speed factor set")
	parent:Destroy()
end

scenario(nil, false)
scenario(function(root) root.CFrame = r.CFrame.new(20, 4, 40) end, true) -- HOME travel
scenario(function(root) root.CFrame = arena.Origin * r.CFrame.new(0, 3.5, 123) end, true) -- protected arrival
scenario(function(_, _, _, endBoss) endBoss() end, true)
scenario(function(_, humanoid) humanoid.Health = 0 end, true)
scenario(function(root, _, player, _, parent)
	local replacement = r.Instance.new("Part")
	replacement.Parent, replacement.CFrame = parent, r.CFrame.new(20, 4, 40)
	local spawn = replacement.CFrame
	player.Character = { FindFirstChild = function() return replacement end, FindFirstChildOfClass = function() return { Health = 100 } end }
	check(replacement.CFrame == spawn and root.Parent ~= nil, "Respawn fixture removed old character too early")
end, true)
print(("PASS: Vine cancellation after HOME/arrival travel, boss end, death and character replacement; legal drag and delayed speed cleanup (%d checks)"):format(checks))
