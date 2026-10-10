--!strict
-- نقطة البداية للسيرفر: بتشغّل كل الخدمات وبتربطها ببعض.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.CharacterService)
local MonsterModels = require(script.MonsterModels)
local DataService = require(script.DataService)
local PlotService = require(script.PlotService)
local MonsterService = require(script.MonsterService)
local StealService = require(script.StealService)
local CombatService = require(script.CombatService)
local CarryService = require(script.CarryService)
local ZoneService = require(script.ZoneService)
local TerrainService = require(script.TerrainService)
local MonetizationService = require(script.MonetizationService)
local EventService = require(script.EventService)
local LeaderboardService = require(script.LeaderboardService)
local RewardService = require(script.RewardService)
local TradeService = require(script.TradeService)
local ArenaService = require(script.ArenaService)

local remotes = Remotes.Get()

-- Hooks (عشان MonsterService مايحتاجش يعمل require للخدمات اللي بتعتمد عليه)
MonsterService.HasPass = MonetizationService.HasPass
MonsterService.ExtraState = function(player: Player): { [string]: any }
	local profile = DataService.Get(player)
	return {
		Passes = MonetizationService.GetOwnedPasses(player),
		BoostLeft = MonetizationService.BoostLeft(player),
		DailyReadyIn = RewardService.DailyReadyIn(player),
		SpinReadyIn = RewardService.SpinReadyIn(player),
		DailyStreak = if profile then profile.Data.Daily.Streak else 0,
		Carrying = CarryService.IsCarrying(player),
	}
end

CharacterService.Init()
MonsterModels.Build() -- الوحوش الـ Rig (موجودين في ServerStorage.MonsterModels)
PlotService.Init()
MonsterService.Init(remotes)
StealService.Init()
CarryService.Init()
ZoneService.Init()
TerrainService.Init()
MonetizationService.Init(remotes)
EventService.Init()
LeaderboardService.Init()
RewardService.Init(remotes)
TradeService.Init(remotes)
ArenaService.Init(remotes)
DataService.StartAutosave()

PlotService.Callbacks.Collect = MonsterService.Collect
PlotService.Callbacks.Lock = MonsterService.Lock
PlotService.Callbacks.Care = MonsterService.OpenMonster
PlotService.Callbacks.OpenShop = function(player)
	remotes.OpenShop:FireClient(player)
end

-- تليبورت للبيت أو المتجر (مش شغال جوه مناطق الوحوش، ولا وانت شايل وحش)
local lastTeleport: { [Player]: number } = {}
remotes.Teleport.OnServerEvent:Connect(function(player: Player, where: unknown)
	if where ~= "Home" and where ~= "Shop" then
		return
	end
	local now = os.clock()
	if lastTeleport[player] and now - lastTeleport[player] < 2 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if root.Position.X >= PlotService.ZonesStartX then
		MonsterService.Notify(player, "🚫 You can't teleport from inside the monster zones!", "error")
		return
	end
	if CarryService.IsCarrying(player) then
		MonsterService.Notify(player, "🚫 You can't teleport while carrying something! Walk it home.", "error")
		return
	end
	lastTeleport[player] = now
	if where == "Home" then
		PlotService.SendHome(player)
	else
		character:PivotTo(CFrame.new(PlotService.ShopPosition + Vector3.new(0, 4, 10)))
	end
end)

local function onCharacter(player: Player, character: Model)
	PlotService.SendHome(player)
	CharacterService.UpdateSpeed(player)
	CombatService.GiveWeapons(player, MonetizationService.HasPass(player, "VIPSword"))
	MonetizationService.OnCharacter(player)
	task.spawn(function()
		CharacterService.ApplyAppearance(player, character)
		CharacterService.UpdateSpeed(player)
	end)
end

local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	if not player.Parent then
		DataService.Release(player)
		return
	end

	local plot = PlotService.Assign(player)
	if not plot then
		player:Kick("This server is full, please try another one.")
		DataService.Release(player)
		return
	end

	MonetizationService.SetupPlayer(player)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Data.Coins
	coins.Parent = leaderstats
	-- الـ Steals: لما تموّت حد شايل وحش وتاخده منه
	local steals = Instance.new("IntValue")
	steals.Name = "Steals"
	steals.Value = profile.Data.Stats.Steals
	steals.Parent = leaderstats
	leaderstats.Parent = player

	task.spawn(function()
		while player.Parent and DataService.Get(player) == profile do
			coins.Value = math.floor(profile.Data.Coins)
			steals.Value = profile.Data.Stats.Steals
			task.wait(0.5)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		task.wait()
		onCharacter(player, character)
	end)
	local character = player.Character
	if character and not CharacterService.IsR6(character) then
		-- اتولد قبل ما الـ R6 يجهز: نولّده تاني
		player:LoadCharacter()
	elseif character then
		onCharacter(player, character)
	end

	MonsterService.SetupPlayer(player)

	if profile.LoadFailed then
		MonsterService.Notify(player, "⚠️ Could not load your data. Progress will NOT be saved this session.", "error")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastTeleport[player] = nil
	StealService.CleanupPlayer(player)
	CombatService.CleanupPlayer(player)
	TradeService.CleanupPlayer(player)
	ArenaService.CleanupPlayer(player)
	RewardService.CleanupPlayer(player)
	ZoneService.CleanupPlayer(player)
	MonetizationService.CleanupPlayer(player)
	CharacterService.Cleanup(player)
	MonsterService.CleanupPlayer(player)
	PlotService.Release(player)
	DataService.Release(player)
end)
