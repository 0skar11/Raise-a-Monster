--!strict
-- نقطة البداية للسيرفر: بتشغّل كل الخدمات وبتربطها ببعض.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.DataService)
local PlotService = require(script.PlotService)
local MonsterService = require(script.MonsterService)
local StealService = require(script.StealService)

local remotes = Remotes.Get()

PlotService.Init()
MonsterService.Init(remotes)
StealService.Init()
DataService.StartAutosave()

PlotService.Callbacks.Collect = MonsterService.Collect
PlotService.Callbacks.Lock = MonsterService.Lock
PlotService.Callbacks.Care = MonsterService.OpenMonster
PlotService.Callbacks.OpenShop = function(player)
	remotes.OpenShop:FireClient(player)
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

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Data.Coins
	coins.Parent = leaderstats
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

	player.CharacterAdded:Connect(function()
		task.wait()
		PlotService.SendHome(player)
	end)
	if player.Character then
		PlotService.SendHome(player)
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
	StealService.CleanupPlayer(player)
	MonsterService.CleanupPlayer(player)
	PlotService.Release(player)
	DataService.Release(player)
end)
