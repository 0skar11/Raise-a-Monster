--!strict
-- الهدية اليومية (بتكبر مع الـ Streak) وعجلة الحظ (لفة مجانية كل يوم وفيها بيض نادر).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)

local RewardService = {}

local remotes: { [string]: RemoteEvent }
local busy: { [Player]: boolean } = {}

function RewardService.DailyReadyIn(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return math.max(0, profile.Data.Daily.LastClaim + Config.Daily.Cooldown - os.time())
end

function RewardService.SpinReadyIn(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return math.max(0, profile.Data.LastSpin + Config.Spin.Cooldown - os.time())
end

-- البيضة بتروح القاعدة، ولو مفيش مكان بتتحول فلوس
local function giveEgg(player: Player, eggType: string)
	if not MonsterService.AddEgg(player, eggType) then
		local fallback = 1000
		DataService.AddCoins(player, fallback)
		MonsterService.Notify(player, "Your base is full, so you got 💰 " .. MonsterMath.FormatNumber(fallback) .. " instead!", "coins")
	end
end

local function claimDaily(player: Player)
	local profile = DataService.Get(player)
	if not profile or busy[player] then
		return
	end
	if RewardService.DailyReadyIn(player) > 0 then
		MonsterService.Notify(player, "Come back later for your next daily reward!", "info")
		return
	end
	local daily = profile.Data.Daily
	local now = os.time()
	if daily.LastClaim > 0 and now - daily.LastClaim <= Config.Daily.StreakReset then
		daily.Streak = math.min(daily.Streak + 1, Config.Daily.MaxStreak)
	else
		daily.Streak = 1
	end
	daily.LastClaim = now
	local coins = Config.Daily.CoinsPerDay * daily.Streak
	DataService.AddCoins(player, coins)
	MonsterService.Notify(player, string.format("🎁 Day %d reward: +%s coins!", daily.Streak, MonsterMath.FormatNumber(coins)), "coins")
	if daily.Streak >= Config.Daily.MaxStreak then
		giveEgg(player, Config.Daily.Day7Egg)
		daily.Streak = 0 -- بعد اليوم السابع بتبدأ من الأول
	end
	MonsterService.PushState(player)
end

local function pickPrize(): number
	local total = 0
	for _, prize in Config.Spin.Prizes do
		total += prize.Weight
	end
	local roll = math.random() * total
	for index, prize in Config.Spin.Prizes do
		roll -= prize.Weight
		if roll <= 0 then
			return index
		end
	end
	return 1
end

local function spin(player: Player)
	local profile = DataService.Get(player)
	if not profile or busy[player] then
		return
	end
	if RewardService.SpinReadyIn(player) > 0 then
		MonsterService.Notify(player, "Your free spin isn't ready yet!", "info")
		return
	end
	busy[player] = true
	profile.Data.LastSpin = os.time()
	local index = pickPrize()
	local prize = Config.Spin.Prizes[index]
	remotes.SpinResult:FireClient(player, index)
	MonsterService.PushState(player)

	-- نستنى العجلة تخلص لفّ قبل ما ندّي الجايزة
	task.delay(4.5, function()
		busy[player] = nil
		if not player.Parent then
			return
		end
		if prize.Coins then
			DataService.AddCoins(player, prize.Coins)
			MonsterService.Notify(player, "🎡 You won " .. prize.Name .. "!", "coins")
		elseif prize.Egg then
			MonsterService.Notify(player, "🎡 You won a " .. prize.Name .. "!", "success")
			giveEgg(player, prize.Egg)
		end
		MonsterService.PushState(player)
	end)
end

function RewardService.CleanupPlayer(player: Player)
	busy[player] = nil
end

function RewardService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	remotes.ClaimDaily.OnServerEvent:Connect(claimDaily)
	remotes.Spin.OnServerEvent:Connect(spin)
end

return RewardService
