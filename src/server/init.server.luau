--!strict
-- نقطة البداية للسيرفر: بتشغّل كل الخدمات وبتربطها ببعض.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.CharacterService)
local DataService = require(script.DataService)
local PlotService = require(script.PlotService)
local MonsterService = require(script.MonsterService)
local StealService = require(script.StealService)
local ZoneService = require(script.ZoneService)
local TerrainService = require(script.TerrainService)

local remotes = Remotes.Get()

CharacterService.Init()
PlotService.Init()
MonsterService.Init(remotes)
StealService.Init()
ZoneService.Init()
TerrainService.Init()
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
	local steals: IntValue? = nil
	if Config.Steal.Enabled then
		local value = Instance.new("IntValue")
		value.Name = "Steals"
		value.Value = profile.Data.Stats.Steals
		value.Parent = leaderstats
		steals = value
	end
	leaderstats.Parent = player

	task.spawn(function()
		while player.Parent and DataService.Get(player) == profile do
			coins.Value = math.floor(profile.Data.Coins)
			if steals then
				steals.Value = profile.Data.Stats.Steals
			end
			task.wait(0.5)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		task.wait()
		PlotService.SendHome(player)
		ZoneService.GiveBat(player)
		task.spawn(CharacterService.ApplyAppearance, player, character)
	end)
	local character = player.Character
	if character and not CharacterService.IsR6(character) then
		-- اتولد قبل ما الـ R6 يجهز: نولّده تاني
		player:LoadCharacter()
	elseif character then
		PlotService.SendHome(player)
		ZoneService.GiveBat(player)
		task.spawn(CharacterService.ApplyAppearance, player, character)
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
	ZoneService.CleanupPlayer(player)
	CharacterService.Cleanup(player)
	MonsterService.CleanupPlayer(player)
	PlotService.Release(player)
	DataService.Release(player)
end)
