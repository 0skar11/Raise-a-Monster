--!strict
-- أحداث الماب:
--  • Monster Rain كل ساعة: وحش نادر بيقع في نص الماب، وأول واحد يمسكه ويوصله قاعدته ياخده.
--  • Big Boss كل شوية (عشوائي): وحش ضخم دمه وضربته عاليين، لازم الكل يتجمع يقتله،
--    ولما يموت بيسيب بيضة Secret. اللي يشيلها بيمشي أبطأ شوية لحد ما يوصلها قاعدته.

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
	end
end

local function killBoss(current: Boss, killer: Player)
	local position = current.Part.Position
	-- it stops fighting at once but stays for a moment so the collapse animation and the explosion can play
	current.Dead = true
	CombatService.Unregister(current.Target)
	remotes.BossFx:FireAllClients("Death", { Position = position })
	MonsterService.Announce("💀 " .. killer.DisplayName .. " landed the final hit on the BIG BOSS! A SECRET EGG is dropping!", Color3.fromRGB(200, 120, 255))
	task.delay(Config.Boss.DeathSeconds, function()
		removeBoss(current)
		CarryService.SpawnPickup(
			{ Kind = "Egg", EggType = "Secret" },
			Vector3.new(position.X, 0.2, position.Z),
			Config.Boss.Lifetime,
			"🌌 SECRET EGG! Carry it home (it's heavy)"
		)
	end)
end

-- The authored Pumpkin Titan (imported into ServerStorage.BossModels): a scaled, grounded clone that faces the plaza,
-- plus its height and body radius. Returns nil when the model is not in the place, and the plain cube is used instead.
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
	local toward = Vector3.new(Config.Map.PlazaMinX + 40 - ground.X, 0, 0)
	local direction = if toward.Magnitude > 1 then toward else Vector3.new(-1, 0, 0)
	local facing = CFrame.lookAt(ground, ground + direction) * CFrame.Angles(0, math.rad(settings.ModelYaw), 0)
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
		Target = CombatService.Register({
			Part = part,
			Radius = bodyRadius,
			OnHit = function(player: Player, damage: number)
				if current.Dead or os.clock() < state.IntroUntil then
					return -- it cannot be hurt while it is still climbing out of the ground
				end
				current.Health -= damage * (if os.clock() < state.VulnerableUntil then Config.Boss.Attacks.PulseExposedBonus else 1)
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
	updateBossBar(current)
	MonsterService.Announce("💀 A BIG BOSS appeared in Zone 1! Everyone team up to defeat it and win a SECRET EGG!", Color3.fromRGB(200, 120, 255))

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
			task.wait(math.random(Config.Boss.MinInterval, Config.Boss.MaxInterval))
			EventService.SpawnBoss()
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
