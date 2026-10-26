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
local MonsterAttack = require(script.MonsterAttack)
local TerrainService = require(script.TerrainService)
local MonetizationService = require(script.MonetizationService)
local EventService = require(script.EventService)
local BossSummonService = require(script.BossSummonService)
local LeaderboardService = require(script.LeaderboardService)
local RewardService = require(script.RewardService)
local AdChestService = require(script.AdChestService)
local MonsterPortraits = require(script.MonsterPortraits)
local TradeService = require(script.TradeService)
local ArenaService = require(script.ArenaService)
local HalloweenService = require(script.HalloweenService)
local PumpkinDecor = require(script.PumpkinDecor)
local AdminService = require(script.AdminService)
local HalloweenPortalService = require(script.HalloweenPortalService)

local remotes = Remotes.Get()

-- Hooks (عشان MonsterService مايحتاجش يعمل require للخدمات اللي بتعتمد عليه)
MonsterService.HasPass = MonetizationService.HasPass
MonetizationService.CanPromptBossSummon = BossSummonService.CanPrompt
MonetizationService.ProcessBossSummonReceipt = BossSummonService.ProcessReceipt
MonsterService.SyncPortraits = MonsterPortraits.Sync
-- Halloween Candy Boost (inert unless Config.Halloween is running)
MonsterService.GetEventMultiplier = HalloweenService.GetCashMultiplier
MonsterService.ExtraState = function(player: Player): { [string]: any }
	local profile = DataService.Get(player)
	return {
		Passes = MonetizationService.GetOwnedPasses(player),
		BoostLeft = MonetizationService.BoostLeft(player),
		SpinReadyIn = RewardService.SpinReadyIn(player),
		AdChestReadyIn = AdChestService.ReadyIn(player),
		AdRewardCoins = AdChestService.RewardAmount(player),
		Carrying = CarryService.IsCarrying(player),
		CanSave = profile ~= nil and profile.CanSave,
		TemporarySession = profile ~= nil and profile.Temporary == true,
	}
end

CharacterService.Init()
MonsterModels.Build() -- الوحوش الـ Rig (موجودين في ServerStorage.MonsterModels)
-- StudioWorld is an edit-mode preview. Runtime services rebuild it with live callbacks.
local studioWorld = workspace:FindFirstChild("StudioWorld")
if studioWorld and studioWorld:GetAttribute("GeneratedPreview") then
	studioWorld:Destroy()
end
PlotService.Init()
MonsterService.Init(remotes)
StealService.Init()
CarryService.Init()
ZoneService.Init()
TerrainService.Init()
MonetizationService.Init(remotes)
EventService.Init()
BossSummonService.Init(remotes)
HalloweenService.Init(remotes)
PumpkinDecor.Init()
LeaderboardService.Init()
RewardService.Init(remotes)
AdChestService.Init(remotes)
TradeService.Init(remotes)
ArenaService.Init(remotes)
AdminService.Init(remotes)
HalloweenPortalService.Init()
DataService.StartAutosave()

PlotService.Callbacks.Collect = MonsterService.Collect
PlotService.Callbacks.Lock = MonsterService.Lock
PlotService.Callbacks.Upgrade = function(player)
	MonsterService.BuyUpgrade(player, "Slots")
end
PlotService.Callbacks.Care = MonsterService.OpenMonster
PlotService.Callbacks.OpenShop = function(player)
	remotes.OpenShop:FireClient(player)
end

-- تليبورت للبيت أو المتجر أو الأرينا من أي مكان في الماب (مش شغال وانت شايل وحش)
local lastTeleport: { [Player]: number } = {}
remotes.Teleport.OnServerEvent:Connect(function(player: Player, where: unknown)
	if where ~= "Home" and where ~= "Shop" and where ~= "Arena" then
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
	if CarryService.IsCarrying(player) then
		MonsterService.Notify(player, "🚫 You can't teleport while carrying something! Walk it home.", "error")
		return
	end
	lastTeleport[player] = now
	if where == "Home" then
		PlotService.SendHome(player)
	elseif where == "Arena" then
		character:PivotTo(ArenaService.GetTeleportCFrame(player))
	else
		character:PivotTo(PlotService.ShopTeleportCFrame)
	end
end)

local function onCharacter(player: Player, character: Model)
	PlotService.SendHome(player)
	CharacterService.UpdateSpeed(player)
	local profile = DataService.Get(player)
	if profile then
		CharacterService.ApplySpeedAccessory(player, profile.Data.SpeedAccessories, profile.Data.EquippedSpeedAccessory)
		CharacterService.UpdateHealth(player, true)
	end
	CombatService.GiveWeapons(player, MonetizationService.GetOwnedPasses(player), if profile then profile.Data.Weapons else {}, if profile then profile.Data.EquippedWeapon else "Bat")
	MonetizationService.OnCharacter(player)
	HalloweenService.OnCharacter(player)
	task.spawn(function()
		CharacterService.ApplyAppearance(player, character)
		if player.Character ~= character then return end
		HalloweenService.OnCharacter(player) -- ApplyDescription can replace accessories, so re-apply
		CharacterService.UpdateSpeed(player)
		CharacterService.UpdateHealth(player)
		if profile then CharacterService.ApplySpeedAccessory(player, profile.Data.SpeedAccessories, profile.Data.EquippedSpeedAccessory) end
		task.wait()
		if player.Character == character then
			CombatService.GiveWeapons(player, MonetizationService.GetOwnedPasses(player), if profile then profile.Data.Weapons else {}, if profile then profile.Data.EquippedWeapon else "Bat")
		end
	end)
end

local initializedPlayers: { [Player]: boolean } = {}
local function onPlayerAdded(player: Player)
	if initializedPlayers[player] then return end
	initializedPlayers[player] = true
	local profile = DataService.Load(player)
	if profile.LoadFailed and not profile.Temporary then
		player:Kick("Your saved progress could not be loaded safely. Please wait a moment and rejoin.")
		DataService.Release(player)
		return
	end
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
	leaderstats.Parent = player

	task.spawn(function()
		while player.Parent and DataService.Get(player) == profile do
			coins.Value = math.floor(profile.Data.Coins)
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
	HalloweenService.SetupPlayer(player)

	if profile.Temporary then
		MonsterService.Notify(player, "Studio test session: saving is unavailable. Your live progress is safe; changes here will not be saved.", "error")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	initializedPlayers[player] = nil
	lastTeleport[player] = nil
	StealService.CleanupPlayer(player)
	CombatService.CleanupPlayer(player)
	TradeService.CleanupPlayer(player)
	ArenaService.CleanupPlayer(player)
	RewardService.CleanupPlayer(player)
	ZoneService.CleanupPlayer(player)
	MonsterAttack.CleanupPlayer(player)
	HalloweenService.CleanupPlayer(player)
	MonetizationService.CleanupPlayer(player)
	CharacterService.Cleanup(player)
	MonsterService.CleanupPlayer(player)
	PlotService.Release(player)
	DataService.Release(player)
end)

-- Studio-only test helpers: /follow gives an adult monster that follows you; /dragon gives an adult dragon.
if game:GetService("RunService"):IsStudio() then
	local Config = require(ReplicatedStorage.Shared.Config)
	local FollowerService = require(script.FollowerService)
	local function hookChat(player: Player)
		player.Chatted:Connect(function(message: string)
			local dragonKeys = { desert = "Desert_8", ice = "Ice_7", volcano = "Volcano_8", void = "Void_8" }
			local dragonRegion = message:lower():match("^/dragon%s*(%a*)$")
			if dragonRegion then
				-- /dragon [desert|ice|volcano|void]: an adult dragon straight into your inventory.
				local profile = DataService.Get(player)
				if not profile then warn("[/dragon] profile is not loaded yet") return end
				local key = dragonKeys[dragonRegion] or dragonKeys.volcano
				local before = {}
				for id in profile.Data.Monsters do before[id] = true end
				if MonsterService.AddMonster(player, key) then
					for id, monster in profile.Data.Monsters do
						if not before[id] then monster.Level = FollowerService.GetMinLevel() end
					end
					MonsterService.PushState(player)
				end
				return
			end
			if message:lower() ~= "/follow" then return end
			local profile = DataService.Get(player)
			if not profile then warn("[/follow] profile is not loaded yet") return end
			local before = {}
			for id in profile.Data.Monsters do before[id] = true end
			MonsterService.AddMonster(player, next(Config.Species))
			for id, monster in profile.Data.Monsters do
				if not before[id] then
					monster.Level = FollowerService.GetMinLevel()
					print("[/follow]", FollowerService.Toggle(player, id))
				end
			end
			MonsterService.PushState(player)
		end)
	end
	Players.PlayerAdded:Connect(hookChat)
	for _, player in Players:GetPlayers() do hookChat(player) end
end
