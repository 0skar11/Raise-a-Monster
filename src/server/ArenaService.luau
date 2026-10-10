--!strict
-- Monster Arena: معارك وحوش 1 ضد 1.
-- لاعب بيتحدى لاعب بوحش، التاني يقبل ويختار وحشه، والمعركة بتتعرض في الـ Arena اللي في الساحة.
-- الكسبان بياخد فلوس + الوحش اللي خسر.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)

type Fighter = {
	Player: Player,
	MonsterId: string,
	Name: string,
	Health: number,
	MaxHealth: number,
	Attack: number,
	Model: Model?,
	Label: TextLabel?,
}

type Challenge = { From: Player, MonsterId: string, Time: number }

local ArenaService = {}

local remotes: { [string]: RemoteEvent }
local challenges: { [Player]: { [Player]: Challenge } } = {} -- challenges[target][from]
local fighting: { [Player]: boolean } = {}
local battleRunning = false
local pedestals: { BasePart } = {}
local arenaSign: TextLabel

-- قوة الوحش في المعركة: الندرة والـ Level والمرحلة والطفرة
local function fighterStats(monster: MonsterMath.MonsterData): (number, number)
	local species = Config.Species[monster.Species]
	local rarity = Config.Rarities[species.Rarity]
	local score = (rarity.Order * 10 + monster.Level * 2 + MonsterMath.GetStageIndex(monster.Level) * 15)
		* MonsterMath.GetMutationMultiplier(monster.Mutation)
	return math.floor(100 + score * 5), 8 + score * 0.6
end

local function setCarried(player: Player, monsterId: string, value: boolean)
	local set = MonsterService.Carried[player]
	if not set then
		set = {}
		MonsterService.Carried[player] = set
	end
	set[monsterId] = if value then true else nil
end

local function buildArena()
	local center = Config.Arena.Position
	local folder = Instance.new("Folder")
	folder.Name = "MonsterArena"
	folder.Parent = workspace
	Build.MakePart({
		Name = "ArenaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 36, 36),
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 60, 60),
		Material = Enum.Material.Slate,
		Parent = folder,
	})
	Build.MakePart({
		Name = "ArenaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 30, 30),
		CFrame = CFrame.new(center + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 170, 120),
		Material = Enum.Material.Sand,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		local pedestal = Build.MakePart({
			Name = "ArenaPedestal",
			Size = Vector3.new(7, 1.5, 7),
			Position = center + Vector3.new(0, 1.2, side * 9),
			Color = if side < 0 then Color3.fromRGB(70, 130, 255) else Color3.fromRGB(255, 80, 80),
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		table.insert(pedestals, pedestal)
	end
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		Build.MakePart({
			Name = "ArenaPillar",
			Size = Vector3.new(2, 8, 2),
			Position = center + Vector3.new(math.cos(angle) * 17, 4, math.sin(angle) * 17),
			Color = Color3.fromRGB(120, 110, 100),
			Material = Enum.Material.Cobblestone,
			Parent = folder,
		})
	end
	local signPart = Build.MakePart({
		Name = "ArenaSign",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 14, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	local gui, label = Build.MakeBillboard(signPart, UDim2.fromScale(28, 7), Vector3.zero, 220)
	gui.AlwaysOnTop = false
	label.Text = '<font color="#FF6060">⚔️ MONSTER ARENA ⚔️</font>\nChallenge someone from the Arena button'
	arenaSign = label
end

local function fighterLabel(fighter: Fighter): string
	return string.format("%s\n❤️ %d / %d", fighter.Name, math.max(0, math.floor(fighter.Health)), fighter.MaxHealth)
end

local function showFighter(fighter: Fighter, pedestal: BasePart, monster: MonsterMath.MonsterData)
	local model = PlotService.BuildMonsterModel(monster)
	local body = model.PrimaryPart :: BasePart
	local facing = Config.Arena.Position + Vector3.new(0, pedestal.Position.Y, 0)
	model:PivotTo(CFrame.lookAt(pedestal.Position + Vector3.new(0, 0.75 + body.Size.Y / 2 + 0.6, 0), facing))
	local info = body:FindFirstChild("Info")
	local label = info and info:FindFirstChild("Label") :: TextLabel?
	model.Parent = pedestal.Parent
	fighter.Model = model
	fighter.Label = label
	if label then
		label.Text = fighterLabel(fighter)
	end
end

local function sendState(a: Fighter, b: Fighter, log: string, done: boolean, winner: Player?)
	for _, pair in { { a, b }, { b, a } } do
		local me, them = pair[1], pair[2]
		if me.Player.Parent then
			remotes.ArenaUpdate:FireClient(me.Player, {
				MyName = me.Name,
				TheirName = them.Name,
				MyHealth = math.max(0, me.Health),
				MyMax = me.MaxHealth,
				TheirHealth = math.max(0, them.Health),
				TheirMax = them.MaxHealth,
				Log = log,
				Done = done,
				Won = winner == me.Player,
			})
		end
	end
end

local function finishBattle(a: Fighter, b: Fighter, winner: Fighter, loser: Fighter)
	setCarried(a.Player, a.MonsterId, false)
	setCarried(b.Player, b.MonsterId, false)
	fighting[a.Player] = nil
	fighting[b.Player] = nil

	local winnerProfile = DataService.Get(winner.Player)
	local lostMonster = if loser.Player.Parent then MonsterService.TakeMonsterData(loser.Player, loser.MonsterId) else nil
	local prize = Config.Arena.PrizeCoins
	if lostMonster then
		prize += math.floor(MonsterMath.GetSellValue(lostMonster) * Config.Arena.PrizeValueShare)
	end
	if winner.Player.Parent and winnerProfile then
		DataService.AddCoins(winner.Player, prize)
		winnerProfile.Data.Stats.ArenaWins += 1
		if lostMonster and not MonsterService.InsertMonsterData(winner.Player, lostMonster) then
			-- مفيش مكان: بياخد قيمته فلوس
			DataService.AddCoins(winner.Player, MonsterMath.GetSellValue(lostMonster))
			MonsterService.Notify(winner.Player, "Your base was full, so you got the monster's value in coins.", "info")
		end
		MonsterService.Notify(winner.Player, "🏆 You won the battle! +" .. MonsterMath.FormatNumber(prize) .. " coins and " .. loser.Name .. "!", "success")
	end
	if loser.Player.Parent then
		MonsterService.Notify(loser.Player, "💔 You lost the battle and " .. loser.Name .. ".", "error")
	end
	MonsterService.Announce("⚔️ " .. winner.Player.DisplayName .. "'s " .. winner.Name .. " beat " .. loser.Player.DisplayName .. "'s " .. loser.Name .. " in the Arena!", Color3.fromRGB(255, 120, 120))
	for _, fighter in { a, b } do
		if fighter.Player.Parent then
			MonsterService.PushState(fighter.Player)
			task.spawn(DataService.Save, fighter.Player)
		end
	end

	task.delay(4, function()
		for _, fighter in { a, b } do
			if fighter.Model then
				fighter.Model:Destroy()
			end
		end
		battleRunning = false
		arenaSign.Text = '<font color="#FF6060">⚔️ MONSTER ARENA ⚔️</font>\nChallenge someone from the Arena button'
	end)
end

local function runBattle(a: Fighter, b: Fighter)
	battleRunning = true
	arenaSign.Text = string.format('<font color="#FF6060">⚔️ %s vs %s ⚔️</font>', a.Player.DisplayName, b.Player.DisplayName)
	sendState(a, b, "The battle begins!", false, nil)
	task.wait(1.5)
	local attacker, defender = a, b
	if math.random() < 0.5 then
		attacker, defender = b, a
	end
	for _ = 1, Config.Arena.MaxTurns do
		if not a.Player.Parent or not b.Player.Parent then
			break
		end
		local damage = math.floor(attacker.Attack * (0.75 + math.random() * 0.5))
		defender.Health -= damage
		if defender.Label then
			defender.Label.Text = fighterLabel(defender)
		end
		local model = defender.Model
		if model and model.PrimaryPart then
			local body = model.PrimaryPart
			local original = body.Color
			body.Color = Color3.fromRGB(255, 80, 80)
			task.delay(0.15, function()
				if body.Parent then
					body.Color = original
				end
			end)
		end
		sendState(a, b, attacker.Name .. " hits for " .. damage .. "!", false, nil)
		if defender.Health <= 0 then
			break
		end
		attacker, defender = defender, attacker
		task.wait(Config.Arena.TurnTime)
	end

	-- لو حد خرج من السيرفر، التاني هو الكسبان. غير كده الأعلى في نسبة الـ HP.
	local winner: Fighter
	if not a.Player.Parent then
		winner = b
	elseif not b.Player.Parent then
		winner = a
	else
		winner = if a.Health / a.MaxHealth >= b.Health / b.MaxHealth then a else b
	end
	local loser = if winner == a then b else a
	sendState(a, b, winner.Name .. " wins!", true, winner.Player)
	finishBattle(a, b, winner, loser)
end

local function ownMonster(player: Player, monsterId: unknown): MonsterMath.MonsterData?
	if type(monsterId) ~= "string" then
		return nil
	end
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[monsterId]
	if not monster or MonsterService.IsCarried(player, monsterId) then
		return nil
	end
	return monster
end

local function onChallenge(player: Player, targetUserId: unknown, monsterId: unknown)
	if type(targetUserId) ~= "number" or fighting[player] then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local monster = ownMonster(player, monsterId)
	if not target or target == player or not monster then
		return
	end
	challenges[target] = challenges[target] or {}
	challenges[target][player] = { From = player, MonsterId = monsterId :: string, Time = os.clock() }
	remotes.ArenaIncoming:FireClient(target, player.UserId, player.DisplayName, MonsterMath.GetDisplayName(monster))
	MonsterService.Notify(player, "⚔️ Challenge sent to " .. target.DisplayName .. "!", "info")
end

local function onRespond(player: Player, fromUserId: unknown, monsterId: unknown)
	if type(fromUserId) ~= "number" then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local pending = challenges[player]
	local challenge = from and pending and pending[from]
	if not from or not pending or not challenge then
		return
	end
	pending[from] = nil
	if monsterId == nil then
		MonsterService.Notify(from, player.DisplayName .. " declined your Arena challenge.", "info")
		return
	end
	if os.clock() - challenge.Time > Config.Arena.RequestTimeout then
		MonsterService.Notify(player, "That challenge expired.", "error")
		return
	end
	if battleRunning then
		MonsterService.Notify(player, "The Arena is busy, try again in a moment!", "error")
		MonsterService.Notify(from, "The Arena is busy, try again in a moment!", "error")
		return
	end
	local mine = ownMonster(player, monsterId)
	local theirs = ownMonster(from, challenge.MonsterId)
	if not mine or not theirs or fighting[player] or fighting[from] then
		MonsterService.Notify(player, "This battle can't start right now.", "error")
		return
	end

	local function makeFighter(owner: Player, id: string, monster: MonsterMath.MonsterData): Fighter
		local health, attack = fighterStats(monster)
		return {
			Player = owner,
			MonsterId = id,
			Name = MonsterMath.GetDisplayName(monster),
			Health = health,
			MaxHealth = health,
			Attack = attack,
			Model = nil,
			Label = nil,
		}
	end
	local a = makeFighter(from, challenge.MonsterId, theirs)
	local b = makeFighter(player, monsterId :: string, mine)
	-- الوحوش مقفولة لحد ما المعركة تخلص (مفيش بيع ولا Trade)
	fighting[from] = true
	fighting[player] = true
	setCarried(from, a.MonsterId, true)
	setCarried(player, b.MonsterId, true)
	showFighter(a, pedestals[1], theirs)
	showFighter(b, pedestals[2], mine)
	task.spawn(runBattle, a, b)
end

function ArenaService.CleanupPlayer(player: Player)
	challenges[player] = nil
	for _, pending in challenges do
		pending[player] = nil
	end
end

function ArenaService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	buildArena()
	remotes.ArenaChallenge.OnServerEvent:Connect(onChallenge)
	remotes.ArenaRespond.OnServerEvent:Connect(onRespond)
end

return ArenaService
