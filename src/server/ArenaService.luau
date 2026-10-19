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
local lastArenaChallenge: { [Player]: number } = {}

local remotes: { [string]: RemoteEvent }
local challenges: { [Player]: { [Player]: Challenge } } = {} -- challenges[target][from]
local fighting: { [Player]: boolean } = {}
local lastChallengeAt: { [Player]: number } = {}
local SIGN_IDLE = '<font color="#FF6060">⚔️ MONSTER ARENA ⚔️</font>\nChallenge someone from the Arena button'

type Arena = {
	Index: number,
	Center: Vector3,
	Entrance: Vector3, -- unit vector from the centre towards the plaza
	Pedestals: { BasePart },
	Sign: TextLabel,
	Busy: boolean,
}
local arenas: { Arena } = {}
local lastArenaIndex: { [Player]: number } = {}

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

local function buildArena(index: number, center: Vector3): Arena
	local radius = Config.Arena.Radius
	local entrance = Vector3.xAxis -- the gate always faces the grey plaza, away from the bases and the map edge
	local folder = Instance.new("Folder")
	folder.Name = "MonsterArena" .. index
	folder.Parent = workspace
	local stone = Color3.fromRGB(120, 110, 100)
	local function part(props: { [string]: any }): Part
		props.Parent = folder
		return Build.MakePart(props)
	end
	local function disc(name: string, diameter: number, height: number, y: number, color: Color3, material: Enum.Material)
		return part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material,
		})
	end
	-- Flow design: a paved plaza, a red stone rim, then the sand fighting pit.
	disc("ArenaPlaza", (radius + 10) * 2, 0.5, 0.25, Color3.fromRGB(150, 146, 138), Enum.Material.Cobblestone)
	disc("ArenaFloor", (radius + 2) * 2, 0.7, 0.4, Color3.fromRGB(150, 60, 60), Enum.Material.Slate)
	disc("ArenaRing", radius * 2, 0.8, 0.45, Color3.fromRGB(205, 175, 120), Enum.Material.Sand)
	disc("ArenaCircle", radius * 0.9, 0.85, 0.5, Color3.fromRGB(190, 160, 108), Enum.Material.Sand)

	local pedestals: { BasePart } = {}
	for _, side in { -1, 1 } do
		table.insert(pedestals, part({
			Name = "ArenaPedestal",
			Size = Vector3.new(8, 1.5, 8),
			Position = center + Vector3.new(side * radius * 0.5, 1.2, 0),
			Color = if side < 0 then Color3.fromRGB(70, 130, 255) else Color3.fromRGB(255, 80, 80),
			Material = Enum.Material.Neon,
		}))
	end

	-- Pillars with torches around the pit.
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if direction:Dot(entrance) > 0.9 then continue end -- keep the entrance path clear
		local at = center + direction * (radius + 3)
		part({ Name = "ArenaPillar", Size = Vector3.new(2.4, 9, 2.4), Position = at + Vector3.new(0, 4.5, 0), Color = stone, Material = Enum.Material.Cobblestone })
		local torch = part({ Name = "ArenaTorch", Size = Vector3.new(1.2, 1.6, 1.2), Position = at + Vector3.new(0, 9.8, 0), Color = Color3.fromRGB(255, 150, 50), Material = Enum.Material.Neon, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 80)
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = torch
	end

	-- Two tiers of spectator steps, left open at the entrance.
	for tier = 1, 2 do
		local steps = 28
		for i = 0, steps - 1 do
			local angle = i / steps * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			if direction:Dot(entrance) < 0.82 then
				local at = center + direction * (radius + 4 + tier * 2.6)
				part({
					Name = "ArenaStep",
					Size = Vector3.new(2.8, tier * 1.6, 4.4),
					CFrame = CFrame.lookAt(at + Vector3.new(0, tier * 0.8, 0), center + Vector3.new(0, tier * 0.8, 0)),
					Color = if i % 2 == 0 then Color3.fromRGB(135, 128, 118) else Color3.fromRGB(118, 112, 104),
					Material = Enum.Material.Slate,
				})
			end
		end
	end

	-- Entrance arch facing the plaza.
	local gate = center + entrance * (radius + 7)
	for _, side in { -1, 1 } do
		part({ Name = "ArenaGatePost", Size = Vector3.new(3, 14, 3), Position = gate + Vector3.new(0, 7, side * 8), Color = stone, Material = Enum.Material.Cobblestone })
	end
	part({ Name = "ArenaGateBeam", Size = Vector3.new(3.4, 3, 21), Position = gate + Vector3.new(0, 15, 0), Color = Color3.fromRGB(170, 55, 55), Material = Enum.Material.SmoothPlastic })
	part({ Name = "ArenaPath", Size = Vector3.new(26, 0.3, 10), Position = center + entrance * (radius + 22) + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(165, 150, 128), Material = Enum.Material.Cobblestone, CanCollide = false })

	local signPart = part({
		Name = "ArenaSign",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 16, 0),
		Transparency = 1,
		CanCollide = false,
	})
	local gui, label = Build.MakeBillboard(signPart, UDim2.fromScale(28, 7), Vector3.zero, 260)
	gui.AlwaysOnTop = false
	label.Text = SIGN_IDLE
	return { Index = index, Center = center, Entrance = entrance, Pedestals = pedestals, Sign = label, Busy = false }
end

local function fighterLabel(fighter: Fighter): string
	return string.format("%s\n❤️ %d / %d", fighter.Name, math.max(0, math.floor(fighter.Health)), fighter.MaxHealth)
end

local function showFighter(arena: Arena, fighter: Fighter, pedestal: BasePart, monster: MonsterMath.MonsterData)
	local model = PlotService.BuildMonsterModel(monster)
	local body = model.PrimaryPart :: BasePart
	local facing = arena.Center + Vector3.new(0, pedestal.Position.Y, 0)
	model:PivotTo(CFrame.lookAt(pedestal.Position + Vector3.new(0, 0.75 + PlotService.PivotHeight(model) + 0.1, 0), facing))
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

local function finishBattle(arena: Arena, a: Fighter, b: Fighter, winner: Fighter, loser: Fighter)
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
		arena.Busy = false
		arena.Sign.Text = SIGN_IDLE
	end)
end

local function runBattle(arena: Arena, a: Fighter, b: Fighter)
	arena.Busy = true
	arena.Sign.Text = string.format('<font color="#FF6060">⚔️ %s vs %s ⚔️</font>', a.Player.DisplayName, b.Player.DisplayName)
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
		if model then
			PlotService.Flash(model, Color3.fromRGB(255, 80, 80))
		end
		-- أنيميشن: اللي بيضرب بيهاجم
		if attacker.Model then
			attacker.Model:SetAttribute("AnimState", "Attack")
		end
		if defender.Model then
			defender.Model:SetAttribute("AnimState", "Idle")
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
	finishBattle(arena, a, b, winner, loser)
end

local function ownMonster(player: Player, monsterId: unknown): MonsterMath.MonsterData?
	if type(monsterId) ~= "string" then
		return nil
	end
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[monsterId]
	if not monster or MonsterService.IsUnavailable(player, monsterId) then
		return nil
	end
	return monster
end

local function onChallenge(player: Player, targetUserId: unknown, monsterId: unknown)
	local now = os.clock()
	if type(targetUserId) ~= "number" or fighting[player]
		or now - (lastChallengeAt[player] or -math.huge) < Config.Arena.RequestCooldown
	then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local monster = ownMonster(player, monsterId)
	if not target or target == player or not monster then
		return
	end
	local targetChallenges = challenges[target]
	if targetChallenges and targetChallenges[player] and now - targetChallenges[player].Time < Config.Arena.RequestTimeout then
		return
	end
	lastChallengeAt[player] = now
	challenges[target] = challenges[target] or {}
	challenges[target][player] = { From = player, MonsterId = monsterId :: string, Time = now }
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
	local arena: Arena? = nil
	for _, candidate in arenas do
		if not candidate.Busy then arena = candidate; break end
	end
	if not arena then
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
	arena.Busy = true
	showFighter(arena, a, arena.Pedestals[1], theirs)
	showFighter(arena, b, arena.Pedestals[2], mine)
	task.spawn(runBattle, arena, a, b)
end

-- Each press goes to a different arena than last time, unless that one has a fight going.
function ArenaService.GetTeleportCFrame(player: Player): CFrame
	local count = #arenas
	local index = ((lastArenaIndex[player] or 0) % count) + 1
	if arenas[index].Busy then
		for offset = 1, count - 1 do
			local other = ((index - 1 + offset) % count) + 1
			if not arenas[other].Busy then index = other; break end
		end
	end
	lastArenaIndex[player] = index
	local arena = arenas[index]
	local spot = arena.Center + arena.Entrance * (Config.Arena.Radius + 18) + Vector3.new(0, 4, 0)
	return CFrame.lookAt(spot, arena.Center + Vector3.new(0, 4, 0))
end

function ArenaService.CleanupPlayer(player: Player)
	lastArenaIndex[player] = nil
	challenges[player] = nil
	lastChallengeAt[player] = nil
	for _, pending in challenges do
		pending[player] = nil
	end
end

function ArenaService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	for index, position in Config.Arena.Positions do
		table.insert(arenas, buildArena(index, position))
	end
	remotes.ArenaChallenge.OnServerEvent:Connect(onChallenge)
	remotes.ArenaRespond.OnServerEvent:Connect(onRespond)
end

return ArenaService
