--!strict
-- عجلة الحظ اليومية: لفة مجانية كل يوم، والجايزة فلوس أو Candy أو بيضة (Config.Spin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local HalloweenService = require(script.Parent.HalloweenService)

local RewardService = {}

local remotes: { [string]: RemoteEvent }
local busy: { [Player]: boolean } = {}

function RewardService.SpinReadyIn(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return math.max(0, profile.Data.LastSpin + Config.Spin.Cooldown - os.time())
end

-- الأكبر بين الحد الأدنى الثابت ودقايق من دخلك الحالي، فالجايزة تكبر مع المناطق
local function incomeCoins(player: Player, floor: number?, minutes: number?): number
	local amount = floor or 0
	if minutes then
		amount = math.max(amount, math.floor(MonsterService.GetIncomePerSecond(player) * minutes * 60))
	end
	return amount
end

local function giveCoins(player: Player, amount: number, message: string)
	DataService.AddCoins(player, amount)
	MonsterService.Notify(player, message .. " 💰 " .. MonsterMath.FormatNumber(amount), "coins")
end

-- البيضة بتروح القاعدة، ولو مفيش مكان بتتحول فلوس
local function giveEgg(player: Player, eggType: string)
	if not MonsterService.AddEgg(player, eggType) then
		local fallback = math.max(1000, incomeCoins(player, nil, Config.Spin.EggFallbackMinutes))
		giveCoins(player, fallback, "Your base is full, so you got")
	end
end

local function grantPrize(player: Player, prize: Config.SpinPrize)
	if prize.Egg then
		MonsterService.Notify(player, "🎡 You won a " .. prize.Name .. "!", "success")
		giveEgg(player, prize.Egg)
	elseif prize.Candy then
		-- الـ Candy بتشتغل بس وقت حدث Halloween، غير كده بتتحول فلوس
		local granted = HalloweenService.AddCandy(player, prize.Candy)
		if granted > 0 then
			MonsterService.Notify(player, "🎡 You won 🍬 " .. tostring(granted) .. " Candy!", "success")
		else
			local fallback = math.max(prize.Candy * Config.Halloween.CandyToCoinRate, incomeCoins(player, nil, prize.FallbackMinutes))
			giveCoins(player, fallback, "🎡 No Halloween event right now, so you got")
		end
	else
		giveCoins(player, incomeCoins(player, prize.Coins, prize.Minutes), "🎡 You won " .. prize.Name .. ":")
	end
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
		grantPrize(player, prize)
		MonsterService.PushState(player)
	end)
end

function RewardService.CleanupPlayer(player: Player)
	busy[player] = nil
end

function RewardService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	remotes.Spin.OnServerEvent:Connect(spin)
end

return RewardService
