--!strict
-- أحداث الماب:
--  • Monster Rain كل ساعة: وحش نادر بيقع في نص الماب، وأول واحد يمسكه ويوصله قاعدته ياخده.
--  • Big Boss كل شوية (عشوائي): وحش ضخم دمه وضربته عاليين، لازم الكل يتجمع يقتله،
--    ولما يموت كل واحد ضربه بما يكفي ياخد لوت حسب نسبة ضرره (BossLoot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CarryService = require(script.Parent.CarryService)
local BossAttacks = require(script.Parent.BossAttacks)
local HalloweenService = require(script.Parent.HalloweenService)
local BossLoot = require(script.Parent.BossLoot)
local ArenaConfig = require(ReplicatedStorage.Shared.HalloweenArenaConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EventService = {}

local RAIN_POSITION = Vector3.new(20, 0.2, 0) -- نص الساحة قدام القواعد
local BOSS_COLOR = Color3.fromRGB(40, 20, 50)

type Boss = {
	Part: BasePart,
	Model: Model?,
	Health: number,
	MaxHealth: number,
	Fill: Frame,
	Text: TextLabel,
	Target: CombatService.Target,
	Dead: boolean,
	Contributors: { [number]: BossLoot.Contributor }, -- by UserId: everyone who damaged it and how much
	BoardDirty: boolean,
}

local eventsFolder: Folder
local remotes = Remotes.Get()
local boss: Boss? = nil

-- Monster Rain ----------------------------------------------------------------------------

function EventService.MonsterRain()
	local pool = Config.MonsterRain.Species
	local species = pool[math.random(1, #pool)]
	local cargo: CarryService.Cargo = {
		Kind = "Monster",
		Species = species,
		Mutation = MonsterService.RollMutation(Config.MonsterRain.MutationChanceMultiplier),
	}
	CarryService.SpawnPickup(cargo, RAIN_POSITION, Config.MonsterRain.Lifetime, "🌧️ MONSTER RAIN! Grab it and run home!", 140)
	MonsterService.Announce("🌧️ MONSTER RAIN! A " .. CarryService.CargoName(cargo) .. " is falling in the middle of the map!", Color3.fromRGB(120, 200, 255))
end

-- Big Boss ---------------------------------------------------------------------------------

local function updateBossBar(current: Boss)
	current.Part:SetAttribute("MaxHealth", current.MaxHealth)
	current.Part:SetAttribute("Health", math.max(0, current.Health))
	current.Fill.Size = UDim2.fromScale(math.clamp(current.Health / current.MaxHealth, 0, 1), 1)
	current.Text.Text = MonsterMath.FormatNumber(math.max(0, current.Health)) .. " / " .. MonsterMath.FormatNumber(current.MaxHealth)
end

local function removeBoss(current: Boss)
	current.Dead = true
	CombatService.Unregister(current.Target)
	current.Part:Destroy()
	if boss == current then
		boss = nil
		workspace:SetAttribute("BossAlive", false)
		HalloweenService.SetBossNight(false) -- day returns once the boss is gone
	end
end

-- Damage board under the boss: one small line per fighter, strongest first (no background, outlined text).
local function boardText(current: Boss): string
	local rows: { BossLoot.Contributor } = {}
	for _, contributor in current.Contributors do
		table.insert(rows, contributor)
	end
	table.sort(rows, function(a, b)
		if a.Damage ~= b.Damage then
			return a.Damage > b.Damage
		end
		return a.Name < b.Name
	end)
	local lines = {}
	for index = 1, math.min(#rows, Config.BossLoot.BoardRows) do
		local row = rows[index]
		local name = row.Name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		lines[index] = string.format('<font color="%s">%d. %s</font>  <font color="#FFD36B">%s</font>  <font color="#FF9A3C">%.1f%%</font>',
			if index == 1 then "#FFFFFF" else "#D9D2E9", index, name, MonsterMath.FormatNumber(row.Damage),
			row.Damage / current.MaxHealth * 100)
	end
	return table.concat(lines, "\n")
end

local function killBoss(current: Boss, killer: Player)
	local position = current.Part.Position
	-- it stops fighting at once but stays for a moment so the collapse animation and the explosion can play
	current.Dead = true
	CombatService.Unregister(current.Target)
	remotes.BossFx:FireAllClients("Death", { Position = position })
	MonsterService.Announce("💀 " .. killer.DisplayName .. " landed the final hit on the BIG BOSS! Loot is shared out by damage!", Color3.fromRGB(200, 120, 255))
	-- the final blow always counts as a fight, even for an admin test kill with no recorded damage
	if next(current.Contributors) == nil then
		current.Contributors[killer.UserId] = { Player = killer, Name = killer.DisplayName, Damage = current.MaxHealth }
	end
	local fighters: { BossLoot.Contributor } = {}
	for _, contributor in current.Contributors do
		table.insert(fighters, contributor)
	end
	task.delay(Config.Boss.DeathSeconds, function()
		removeBoss(current)
		BossLoot.Distribute(fighters, current.MaxHealth)
	end)
end

-- The authored Pumpkin Titan (imported into ServerStorage.BossModels): a scaled, grounded clone that faces the plaza,
-- plus its height and body radius. Returns nil when the model is not in the place, and the plain cube is used instead.
local function spawnFacing(ground: Vector3): CFrame
	local toward = if ArenaConfig.IsArenaBoss(ground)
		then ArenaConfig.Origin:PointToWorldSpace(ArenaConfig.ArrivalCenter) - ground
		else Vector3.new(Config.Map.PlazaMinX + 40 - ground.X, 0, 0)
	toward = Vector3.new(toward.X, 0, toward.Z)
	local direction = if toward.Magnitude > 0.001 then toward else Vector3.new(-1, 0, 0)
	return CFrame.lookAt(ground, ground + direction)
end

local function cloneBossModel(): (Model?, number, number, CFrame?)
	local settings = Config.Boss
	local storage = ServerStorage:FindFirstChild(settings.ModelFolder)
	local template = storage and storage:FindFirstChild(settings.ModelName)
	if not template or not template:IsA("Model") then
		return nil, 0, 0, nil
	end
	local model = template:Clone()
	-- a rigged Titan keeps only its root anchored (Motor6D joints + the client animator move the rest);
	-- a plain static model is anchored part by part
	local rigged = model.PrimaryPart ~= nil and model:FindFirstChildWhichIsA("Motor6D", true) ~= nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = not rigged or descendant == model.PrimaryPart
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	local _, size = model:GetBoundingBox()
	if size.Y < 0.1 then
		model:Destroy()
		return nil, 0, 0, nil
	end
	model:ScaleTo(model:GetScale() * settings.ModelHeight / size.Y)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivotOffset = boxCFrame:ToObjectSpace(model:GetPivot())
	local ground = settings.Position
	local facing = spawnFacing(ground) * CFrame.Angles(0, math.rad(settings.ModelYaw), 0)
	local standing = facing * CFrame.new(0, boxSize.Y / 2, 0) * pivotOffset
	model:PivotTo(standing)
	if rigged then
		model:SetAttribute("Procedural", false) -- the client's BossFx animator poses it, timed to every attack
		model:SetAttribute("Scale", settings.ModelHeight / 6.5) -- animator amplitude (a normal Adult is ~6.5 studs tall)
		model:SetAttribute("AnimState", "Idle")
		CollectionService:AddTag(model, "Monster")
	end
	return model, boxSize.Y, math.max(boxSize.X, boxSize.Z) / 2, standing
end

function EventService.SpawnBoss()
	if boss then
		return
	end
	local settings = Config.Boss
	local arenaBoss = ArenaConfig.IsArenaBoss(settings.Position)
	local maxHealth = math.max(settings.MinHealth, settings.HealthPerPlayer * #Players:GetPlayers())
	local model, modelHeight, modelRadius, standing = cloneBossModel()
	local part: BasePart
	local bodyRadius: number
	local labelHeight: number
	local highlight: Highlight? = nil
	if model then
		-- invisible hitbox around the chest; the model rides inside it so it disappears with the boss
		bodyRadius = modelRadius * 0.7
		labelHeight = modelHeight * 0.5 + 6
		part = Build.MakePart({
			Name = "BigBoss",
			Size = Vector3.new(bodyRadius * 2, modelHeight * 0.7, bodyRadius * 2),
			Position = settings.Position + Vector3.new(0, modelHeight * 0.35, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = true,
			Parent = eventsFolder,
		})
		model.Name = "PumpkinTitan"
		model.Parent = part
		highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 70, 40)
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		highlight.Parent = model
	else
		bodyRadius = settings.Size / 2
		labelHeight = settings.Size / 2 + 5
		part = Build.MakePart({
			Name = "BigBoss",
			Size = Vector3.one * settings.Size,
			Position = settings.Position + Vector3.new(0, settings.Size / 2, 0),
			Color = BOSS_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = eventsFolder,
		})
		local fire = Instance.new("Fire")
		fire.Color = Color3.fromRGB(170, 60, 255)
		fire.SecondaryColor = Color3.fromRGB(60, 20, 120)
		fire.Size = 14
		fire.Parent = part
	end

	part.CFrame = CFrame.new(part.Position) * spawnFacing(settings.Position).Rotation
	part:SetAttribute("HalloweenArenaBoss", arenaBoss)
	local modelOffset = if standing then part.CFrame:ToObjectSpace(standing) else nil
	local gui, label = Build.MakeBillboard(part, UDim2.fromScale(30, 8), Vector3.new(0, labelHeight, 0), 400)
	gui.AlwaysOnTop = false
	label.Size = UDim2.fromScale(1, 0.55)
	label.Text = '<font color="#C878FF">💀 BIG BOSS 💀</font>\nTeam up to defeat it!'
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 0.35)
	bar.Position = UDim2.fromScale(0, 0.62)
	bar.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(190, 60, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.ZIndex = 2
	text.Parent = bar

	-- damage board: sits below the boss, no background
	local board = Instance.new("BillboardGui")
	board.Name = "DamageBoard"
	board.Size = UDim2.fromScale(22, 6)
	board.StudsOffset = Vector3.new(0, -(part.Size.Y / 2) + 3, 0)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = 260
	board.Adornee = part
	board.Parent = part
	local boardLabel = Instance.new("TextLabel")
	boardLabel.Name = "Rows"
	boardLabel.Size = UDim2.fromScale(1, 1)
	boardLabel.BackgroundTransparency = 1
	boardLabel.Font = Enum.Font.GothamBold
	boardLabel.RichText = true
	boardLabel.TextScaled = true
	boardLabel.TextXAlignment = Enum.TextXAlignment.Center
	boardLabel.TextYAlignment = Enum.TextYAlignment.Top
	boardLabel.TextColor3 = Color3.new(1, 1, 1)
	boardLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	boardLabel.TextStrokeTransparency = 0.15
	boardLabel.Text = ""
	boardLabel.Parent = board

	local state = { VulnerableUntil = 0, Enraged = false, IntroUntil = if model then os.clock() + settings.IntroBuildUp + settings.IntroRise + settings.IntroRoar else 0 }
	local current: Boss
	current = {
		Part = part,
		Model = model,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Fill = fill,
		Text = text,
		Dead = false,
		Contributors = {},
		BoardDirty = false,
		Target = CombatService.Register({
			Part = part,
			Radius = bodyRadius,
			OnHit = function(player: Player, damage: number)
				if current.Dead or os.clock() < state.IntroUntil then
					return -- it cannot be hurt while it is still climbing out of the ground
				end
				local character = player.Character
				local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
				local attackerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
				if arenaBoss and (not attackerRoot or not attackerRoot:IsA("BasePart") or not attackerHumanoid
					or attackerHumanoid.Health <= 0 or not ArenaConfig.IsCombatPosition(attackerRoot.Position)) then
					return -- the arrival courtyard is outside the encounter in both directions
				end
				local dealt = math.min(current.Health, damage * (if os.clock() < state.VulnerableUntil then Config.Boss.Attacks.PulseExposedBonus else 1))
				current.Health -= dealt
				local contributor = current.Contributors[player.UserId]
				if not contributor then
					contributor = { Player = player, Name = player.DisplayName, Damage = 0 }
					current.Contributors[player.UserId] = contributor
				end
				contributor.Damage += dealt
				current.BoardDirty = true
				if highlight then
					highlight.FillTransparency = 0.45
					task.delay(0.1, function()
						if highlight.Parent then
							highlight.FillTransparency = 1
						end
					end)
				else
					part.Color = Color3.fromRGB(255, 90, 90)
					task.delay(0.1, function()
						if part.Parent then
							part.Color = BOSS_COLOR
						end
					end)
				end
				if current.Health <= 0 then
					killBoss(current, player)
				else
					updateBossBar(current)
				end
			end,
		}),
	}
	boss = current
	task.spawn(function()
		while not current.Dead and boardLabel.Parent do
			if current.BoardDirty then
				current.BoardDirty = false
				boardLabel.Text = boardText(current)
			end
			task.wait(0.4)
		end
	end)
	workspace:SetAttribute("BossAlive", true)
	HalloweenService.SetBossNight(true) -- night falls the moment it appears
	updateBossBar(current)
	MonsterService.Announce("💀 The PUMPKIN TITAN appeared! Enter the Halloween portal at the end of the Void road and fight for epic loot!", Color3.fromRGB(200, 120, 255))

	if model and standing then
		remotes.BossFx:FireAllClients("Entrance", { Position = part.Position, BuildUp = settings.IntroBuildUp, Rise = settings.IntroRise, Roar = settings.IntroRoar, Height = modelHeight, Part = part })
		local below = standing - Vector3.new(0, modelHeight * 0.95, 0)
		model:PivotTo(below)
		task.spawn(function()
			task.wait(settings.IntroBuildUp) -- nothing visible while the ground rumbles
			local started = os.clock()
			while model.Parent and os.clock() - started < settings.IntroRise do
				local u = (os.clock() - started) / settings.IntroRise
				local eased = 1 - (1 - u) ^ 3
				model:PivotTo(below:Lerp(standing, eased))
				task.wait()
			end
			if model.Parent then
				model:PivotTo(standing)
			end
		end)
	end

	-- the full attack kit (sweeps, slams, bombs, vines, heart pulse, rain, rage) escalates as its health drops
	BossAttacks.Run({
		Part = part,
		Model = model,
		BodyRadius = bodyRadius,
		MoveRadius = if model then modelRadius else bodyRadius,
		ModelOffset = modelOffset,
		ArenaBoss = arenaBoss,
		Ground = settings.Position.Y,
		IsAlive = function()
			return not current.Dead
		end,
		HealthFraction = function()
			return math.clamp(current.Health / current.MaxHealth, 0, 1)
		end,
		State = state,
	})

	-- لو محدش قتله بيمشي
	task.delay(settings.Lifetime, function()
		if boss == current and not current.Dead then
			removeBoss(current)
			MonsterService.Announce("The Big Boss got away... maybe next time!", Color3.fromRGB(200, 200, 200))
		end
	end)
end

-- Admin controls: all act on the boss that is alive right now and return false when there is none.
function EventService.IsBossAlive(): boolean
	return boss ~= nil and not boss.Dead
end

function EventService.GetBossPosition(): Vector3?
	local current = boss
	if current and not current.Dead then
		return current.Part.Position
	end
	return nil
end

function EventService.KillBoss(killer: Player): boolean
	local current = boss
	if not current or current.Dead then
		return false
	end
	-- straight to the kill: OnHit would ignore an admin who is outside the arena or while the boss is still rising
	current.Health = 0
	updateBossBar(current)
	killBoss(current, killer)
	return true
end

function EventService.SetBossHealthFraction(fraction: number): boolean
	local current = boss
	if not current or current.Dead then
		return false
	end
	current.Health = math.max(1, current.MaxHealth * math.clamp(fraction, 0, 1))
	updateBossBar(current)
	return true
end

function EventService.ForceBossAttack(name: string): boolean
	local current = boss
	if not current or current.Dead then
		return false
	end
	current.Part:SetAttribute("AdminAttack", name)
	return true
end

function EventService.Init()
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(Config.MonsterRain.Interval)
			EventService.MonsterRain()
		end
	end)
	task.spawn(function()
		while true do
			-- wall-clock slots: every server spawns the boss at the same moment, and the portal timer reads BossNextSpawnAt
			local now = workspace:GetServerTimeNow()
			local nextAt = (math.floor(now / Config.Boss.Interval) + 1) * Config.Boss.Interval
			workspace:SetAttribute("BossNextSpawnAt", nextAt)
			task.wait(math.max(0, nextAt - now))
			EventService.SpawnBoss()
			task.wait(1)
		end
	end)

	-- في Studio بس: تقدر تشغّل الأحداث من الـ Command Bar عشان تجرّبها:
	--   game.ServerStorage.RaiseAMonsterDebug.MonsterRain:Fire()
	--   game.ServerStorage.RaiseAMonsterDebug.Boss:Fire()
	if RunService:IsStudio() then
		local folder = Instance.new("Folder")
		folder.Name = "RaiseAMonsterDebug"
		-- KillBoss: آخر ضربة باسم أول لاعب (عشان تجرّب بيضة الـ Secret من غير مئات الضربات)
		local function killBossForTest()
			local current = boss
			local first = Players:GetPlayers()[1]
			if current and first then
				current.Target.OnHit(first, current.Health + 1)
			end
		end
		for name, callback in { MonsterRain = EventService.MonsterRain, Boss = EventService.SpawnBoss, KillBoss = killBossForTest } do
			local event = Instance.new("BindableEvent")
			event.Name = name
			event.Event:Connect(callback)
			event.Parent = folder
		end
		folder.Parent = game:GetService("ServerStorage")
	end
end

return EventService
