--!strict
-- أحداث الماب:
--  • Monster Rain كل ساعة: وحش نادر بيقع في نص الماب، وأول واحد يمسكه ويوصله قاعدته ياخده.
--  • Big Boss كل شوية (عشوائي): وحش ضخم دمه وضربته عاليين، لازم الكل يتجمع يقتله،
--    ولما يموت بيسيب بيضة Secret. اللي يشيلها بيمشي أبطأ شوية لحد ما يوصلها قاعدته.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CarryService = require(script.Parent.CarryService)

local EventService = {}

local RAIN_POSITION = Vector3.new(20, 0.2, 0) -- نص الساحة قدام القواعد
local BOSS_COLOR = Color3.fromRGB(40, 20, 50)

type Boss = {
	Part: BasePart,
	Health: number,
	MaxHealth: number,
	Fill: Frame,
	Text: TextLabel,
	Target: CombatService.Target,
	Dead: boolean,
}

local eventsFolder: Folder
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
	removeBoss(current)
	MonsterService.Announce("💀 " .. killer.DisplayName .. " landed the final hit on the BIG BOSS! A SECRET EGG dropped!", Color3.fromRGB(200, 120, 255))
	CarryService.SpawnPickup(
		{ Kind = "Egg", EggType = "Secret" },
		Vector3.new(position.X, 0.2, position.Z),
		Config.Boss.Lifetime,
		"🌌 SECRET EGG! Carry it home (it's heavy)"
	)
end

function EventService.SpawnBoss()
	if boss then
		return
	end
	local settings = Config.Boss
	local maxHealth = math.max(settings.MinHealth, settings.HealthPerPlayer * #Players:GetPlayers())
	local part = Build.MakePart({
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

	local gui, label = Build.MakeBillboard(part, UDim2.fromScale(30, 8), Vector3.new(0, settings.Size / 2 + 5, 0), 400)
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

	local current: Boss
	current = {
		Part = part,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Fill = fill,
		Text = text,
		Dead = false,
		Target = CombatService.Register({
			Part = part,
			Radius = settings.Size / 2,
			OnHit = function(player: Player, damage: number)
				if current.Dead then
					return
				end
				current.Health -= damage
				part.Color = Color3.fromRGB(255, 90, 90)
				task.delay(0.1, function()
					if part.Parent then
						part.Color = BOSS_COLOR
					end
				end)
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

	-- بيضرب كل اللي جنبه
	task.spawn(function()
		while not current.Dead do
			task.wait(settings.AttackInterval)
			if current.Dead then
				break
			end
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 then
					local flat = Vector3.new(root.Position.X - part.Position.X, 0, root.Position.Z - part.Position.Z)
					if flat.Magnitude <= settings.AttackRange then
						humanoid:TakeDamage(settings.Damage)
					end
				end
			end
		end
	end)

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
