-- Run: lune run tools/test-player-attack.luau
-- Execute the production swing/animation path with deterministic tracks and time.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local source = fs.readFile("src/server/CombatService.luau")
local helpers = assert(source:match('(local PLAYER_ATTACK_ANIMATION.-)function CombatService.Register'))
local start = assert(source:find("local function swing(", 1, true))
local finish = assert(source:find("\t-- الأول: أقرب وحش", start, true))
local swing = source:sub(start, finish - 1) .. "end\n"
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			callbacks[callback] = true
			return { Disconnect = function() callbacks[callback] = nil end }
		end,
		Fire = function(_, ...)
			local pending = {}
			for callback in callbacks do table.insert(pending, callback) end
			for _, callback in pending do if callbacks[callback] then callback(...) end end
		end,
	}
end
local now, sounds = 100, 0
local pending, debris, tracks = {}, {}, {}
local animator = {
	LoadAnimation = function()
		local track = { IsPlaying = false, Plays = 0, Destroyed = false }
		function track:Play() self.Plays += 1; self.IsPlaying = true end
		function track:Stop() self.IsPlaying = false end
		function track:Destroy() self.Destroyed = true end
		table.insert(tracks, track)
		return track
	end,
}
local humanoid = { Health = 100, Died = signal() }
function humanoid:FindFirstChildOfClass() return animator end
local player = { UserId = 1, Character = {}, CharacterRemoving = signal() }
local children = {}
local tool = { Parent = player.Character, Grip = roblox.CFrame.new(), AncestryChanged = signal() }
function tool:GetAttribute() return 1 end
function tool:GetChildren() return children end
function tool:FindFirstChild() return {} end
local instance = {
	new = function(class)
		local value = { ClassName = class }
		function value:Destroy() self.Destroyed = true; self.Parent = nil end
		return value
	end,
}
local env = {
	Instance = instance,
	Enum = roblox.Enum,
	CFrame = roblox.CFrame,
	Config = { Combat = { AttackCooldown = 0.35, Sounds = { Swing = "" } } },
	Debris = { AddItem = function(_, item) table.insert(debris, item) end },
	task = { delay = function(delay, callback) table.insert(pending, { At = now + delay, Callback = callback }) end },
	os = { clock = function() return now end },
	math = math, -- الضربة بقت بتحسب نغمة الصوت بـ math
	getRoot = function() return {} end,
	getHumanoid = function() return humanoid end,
	playSound = function() sounds += 1 end,
}
local attack, cleanup = luau.load("local lastSwing = {}\n" .. helpers .. swing .. "return swing, clearAttack", { environment = env })()
local function hit() attack(player, tool, 1, 0, 10) end
local function advance(seconds)
	now += seconds
	local remaining = {}
	for _, item in pending do
		if item.At <= now then item.Callback() else table.insert(remaining, item) end
	end
	pending = remaining
end
local grip = tool.Grip
hit()
local track = tracks[1]
check(track.Plays == 1 and not track.Looped, "first swing plays one non-looping attack")
check(#debris == 0, "custom track does not issue a competing Slash")
for _ = 1, 100 do hit() end
check(track.Plays == 1 and sounds == 1, "rapid spam obeys existing attack cooldown")
advance(0.4); hit()
check(track.Plays == 1 and sounds == 2, "accepted swings do not rewind an unfinished attack")
track.IsPlaying = false
advance(0.4); hit()
check(track.Plays == 2 and #tracks == 1, "completed attacks replay the cached track")
tool.Parent = {}
tool.AncestryChanged:Fire()
check(track.Destroyed and not track.IsPlaying and tool.Grip == grip, "unequip stops attack and restores grip")
tool.Parent = player.Character
advance(0.4); hit()
check(#tracks == 2 and tracks[2].Plays == 1, "reequip creates a fresh attack")
humanoid.Died:Fire()
check(tracks[2].Destroyed and tool.Grip == grip, "death releases animation and grip")
advance(0.4); hit()
player.CharacterRemoving:Fire()
check(tracks[3].Destroyed, "respawn releases cached track")
advance(0.4); hit()
cleanup(player)
cleanup(player)
check(tracks[4].Destroyed and tool.Grip == grip, "player cleanup is safe to repeat")
advance(1)
check(tool.Grip == grip, "obsolete delayed callbacks cannot change restored grip")
animator = nil
advance(0.4); hit()
check(#debris == 1 and debris[1].Value == "Slash", "missing Animator retains expiring default Slash fallback")
cleanup(player)
print(string.format("PASS: %d player M1 animation checks", checks))
