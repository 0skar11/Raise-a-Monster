--!strict
-- Admin panel backend. Only the usernames in Config.Admin.Usernames are ever told they are admins, and every action is
-- re-checked here, so a client that fakes the panel can do nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local HalloweenService = require(script.Parent.HalloweenService)

local AdminService = {}

local MAX_COINS = 1e15
local MAX_CANDY = 1e7
local ACTION_COOLDOWN = 0.15

local adminIds: { [number]: boolean } = {}
local adminNames: { [string]: boolean } = {}
local lastAction: { [Player]: number } = {}
local started = false

for _, name in Config.Admin.Usernames do
	adminNames[string.lower(name)] = true
end

function AdminService.IsAdmin(player: Player): boolean
	return adminIds[player.UserId] == true or adminNames[string.lower(player.Name)] == true
end

local function findPlayer(name: unknown): Player?
	if type(name) ~= "string" or #name == 0 or #name > 40 then
		return nil
	end
	local lowered = string.lower(name)
	for _, candidate in Players:GetPlayers() do
		if string.lower(candidate.Name) == lowered or string.lower(candidate.DisplayName) == lowered then
			return candidate
		end
	end
	for _, candidate in Players:GetPlayers() do
		if string.sub(string.lower(candidate.Name), 1, #lowered) == lowered then
			return candidate
		end
	end
	return nil
end

local function amountOf(value: unknown, maximum: number): number?
	if type(value) ~= "number" or value ~= value or value < 1 or value > maximum then
		return nil
	end
	return math.floor(value)
end

local function aliveRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- Each action returns (ok, message). `target` is the player it applies to (the admin unless another was named).
local actions: { [string]: (admin: Player, target: Player, args: { [string]: any }) -> (boolean, string) } = {
	GiveCoins = function(_, target, args)
		local amount = amountOf(args.Amount, MAX_COINS)
		if not amount then return false, "Enter a coin amount from 1 to 1e15." end
		DataService.AddCoins(target, amount)
		MonsterService.PushState(target)
		return true, string.format("Gave %s %d coins.", target.Name, amount)
	end,
	GiveCandy = function(_, target, args)
		local amount = amountOf(args.Amount, MAX_CANDY)
		if not amount then return false, "Enter a Candy amount from 1 to 10,000,000." end
		local granted = HalloweenService.AddCandy(target, amount)
		return granted > 0, if granted > 0 then string.format("Gave %s %d Candy.", target.Name, granted) else "The Halloween event is not running."
	end,
	GiveEgg = function(_, target, args)
		local eggType = args.Name
		if type(eggType) ~= "string" or not Config.Eggs[eggType] then return false, "Unknown egg type." end
		local ok = MonsterService.AddEgg(target, eggType)
		return ok, if ok then string.format("Gave %s a %s egg.", target.Name, eggType) else "Could not add the egg."
	end,
	GiveMonster = function(_, target, args)
		local species = args.Name
		if type(species) ~= "string" or not Config.Species[species] then return false, "Unknown species key." end
		local ok = MonsterService.AddMonster(target, species)
		MonsterService.PushState(target)
		return ok, if ok then string.format("Gave %s a %s.", target.Name, Config.Species[species].DisplayName) else "Could not add the monster."
	end,
	Heal = function(_, target)
		local _, humanoid = aliveRoot(target)
		if not humanoid then return false, "That player is not alive." end
		humanoid.Health = humanoid.MaxHealth
		return true, "Healed " .. target.Name .. "."
	end,
	Goto = function(admin, target)
		local mine = aliveRoot(admin)
		local theirs = aliveRoot(target)
		if not mine or not theirs then return false, "Both players must be alive." end
		mine.CFrame = theirs.CFrame * CFrame.new(0, 0, 5)
		return true, "Teleported to " .. target.Name .. "."
	end,
	Bring = function(admin, target)
		local mine = aliveRoot(admin)
		local theirs = aliveRoot(target)
		if not mine or not theirs then return false, "Both players must be alive." end
		theirs.CFrame = mine.CFrame * CFrame.new(0, 0, -5)
		return true, "Brought " .. target.Name .. " to you."
	end,
	StartInvasion = function(_, _, args)
		local count = if type(args.Amount) == "number" then math.clamp(math.floor(args.Amount), 3, 10) else nil
		local spawned = HalloweenService.StartInvasion(count)
		return spawned > 0, if spawned > 0 then string.format("Started a Mother Invasion (%d Mothers).", spawned) else "The Halloween event is not running."
	end,
	StartPumpkinHunt = function()
		local spawned = HalloweenService.StartPumpkinHunt()
		return spawned > 0, if spawned > 0 then "Started a Pumpkin Hunt." else "The Halloween event is not running."
	end,
	Announce = function(_, _, args)
		local text = args.Text
		if type(text) ~= "string" or #text == 0 or #text > 120 then return false, "Announcements are 1-120 characters." end
		MonsterService.Announce("📢 " .. text, Color3.fromRGB(255, 220, 120))
		return true, "Announcement sent."
	end,
}

function AdminService.Init(remotes: { [string]: RemoteEvent })
	if started then
		return
	end
	started = true

	-- Resolve the allow-listed names to UserIds once (a renamed account then still matches by id).
	task.spawn(function()
		for _, name in Config.Admin.Usernames do
			local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
			if ok and type(id) == "number" then
				adminIds[id] = true
			end
		end
	end)

	local function actionNames(): { string }
		local names = {}
		for name in actions do table.insert(names, name) end
		table.sort(names)
		return names
	end

	remotes.AdminAction.OnServerEvent:Connect(function(player: Player, action: unknown, args: unknown)
		if not AdminService.IsAdmin(player) then
			return -- silently ignore: non-admins get no hint that the panel exists
		end
		if action == "Hello" then
			remotes.AdminAccess:FireClient(player, true, actionNames())
			return
		end
		if type(action) ~= "string" or not actions[action] then
			return
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
			return
		end
		lastAction[player] = now
		local safeArgs: { [string]: any } = if type(args) == "table" then args :: any else {}
		local targetName = safeArgs.Target
		local target: Player? = player
		if type(targetName) == "string" and #targetName > 0 then
			target = findPlayer(targetName)
		end
		if not target then
			MonsterService.Notify(player, "🛠 Player not found.", "error")
			return
		end
		local ok, message = actions[action](player, target :: Player, safeArgs)
		print(string.format("[Admin] %s (%d) %s -> %s: %s", player.Name, player.UserId, action, (target :: Player).Name, message))
		MonsterService.Notify(player, "🛠 " .. message, if ok then "success" else "error")
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return AdminService
