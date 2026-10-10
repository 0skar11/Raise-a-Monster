--!strict
-- تبديل وحوش بين لاعبين: واحد يبعت طلب، التاني يقبل، كل واحد يختار وحوشه،
-- والتبديل بيحصل بس لما الاتنين يدوسوا "Ready" (شاشة تأكيد من الطرفين).
-- أي تغيير في العرض بيلغي الـ Ready عند الاتنين عشان محدش يتخدع.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)

type Trade = {
	Players: { Player },
	Offers: { [Player]: { string } },
	Ready: { [Player]: boolean },
}

local TradeService = {}

local remotes: { [string]: RemoteEvent }
local trades: { [Player]: Trade } = {}
local requests: { [Player]: { [Player]: number } } = {} -- requests[target][from] = وقت الطلب

local function partnerOf(trade: Trade, player: Player): Player
	return if trade.Players[1] == player then trade.Players[2] else trade.Players[1]
end

local function summarize(player: Player, ids: { string }): { any }
	local profile = DataService.Get(player)
	local result = {}
	for _, id in ids do
		local monster = profile and profile.Data.Monsters[id]
		if monster then
			local species = Config.Species[monster.Species]
			table.insert(result, {
				Id = id,
				Name = MonsterMath.GetDisplayName(monster),
				Rarity = species and species.Rarity or "Common",
				Level = monster.Level,
			})
		end
	end
	return result
end

local function sendUpdate(trade: Trade)
	for _, player in trade.Players do
		local partner = partnerOf(trade, player)
		remotes.TradeUpdate:FireClient(player, {
			PartnerName = partner.DisplayName,
			MyOffer = summarize(player, trade.Offers[player]),
			TheirOffer = summarize(partner, trade.Offers[partner]),
			MyReady = trade.Ready[player] == true,
			TheirReady = trade.Ready[partner] == true,
		})
	end
end

local function closeTrade(trade: Trade, message: string?)
	for _, player in trade.Players do
		if trades[player] == trade then
			trades[player] = nil
		end
		if player.Parent then
			remotes.TradeUpdate:FireClient(player, nil)
			if message then
				MonsterService.Notify(player, message, "info")
			end
		end
	end
end

local function validOffer(player: Player, ids: { string }): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local seen: { [string]: boolean } = {}
	for _, id in ids do
		if seen[id] or not profile.Data.Monsters[id] or MonsterService.IsCarried(player, id) then
			return false
		end
		seen[id] = true
	end
	return true
end

local function execute(trade: Trade)
	local a, b = trade.Players[1], trade.Players[2]
	local offerA, offerB = trade.Offers[a], trade.Offers[b]
	if not validOffer(a, offerA) or not validOffer(b, offerB) then
		closeTrade(trade, "Trade cancelled: a monster is not available anymore.")
		return
	end
	-- كل واحد لازم يبقى عنده مكان للي جاي له
	if MonsterService.CountFreeSlots(a) + #offerA < #offerB or MonsterService.CountFreeSlots(b) + #offerB < #offerA then
		closeTrade(trade, "Trade cancelled: not enough free slots in a base.")
		return
	end
	local fromA, fromB = {}, {}
	for _, id in offerA do
		local monster = MonsterService.TakeMonsterData(a, id)
		if monster then
			table.insert(fromA, monster)
		end
	end
	for _, id in offerB do
		local monster = MonsterService.TakeMonsterData(b, id)
		if monster then
			table.insert(fromB, monster)
		end
	end
	for _, monster in fromA do
		MonsterService.InsertMonsterData(b, monster)
	end
	for _, monster in fromB do
		MonsterService.InsertMonsterData(a, monster)
	end
	closeTrade(trade)
	for _, player in trade.Players do
		MonsterService.Notify(player, "🤝 Trade complete!", "success")
		MonsterService.PushState(player)
		task.spawn(DataService.Save, player)
	end
end

local function onRequest(player: Player, targetUserId: unknown)
	if type(targetUserId) ~= "number" or trades[player] then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if trades[target] then
		MonsterService.Notify(player, target.DisplayName .. " is already trading.", "error")
		return
	end
	requests[target] = requests[target] or {}
	requests[target][player] = os.clock()
	remotes.TradeIncoming:FireClient(target, player.UserId, player.DisplayName)
	MonsterService.Notify(player, "📨 Trade request sent to " .. target.DisplayName, "info")
end

local function onRespond(player: Player, fromUserId: unknown, accepted: unknown)
	if type(fromUserId) ~= "number" then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local pending = requests[player]
	local sentAt = from and pending and pending[from]
	if not from or not pending or not sentAt then
		return
	end
	pending[from] = nil
	if accepted ~= true then
		MonsterService.Notify(from, player.DisplayName .. " declined your trade.", "info")
		return
	end
	if os.clock() - sentAt > Config.Trade.RequestTimeout or trades[player] or trades[from] then
		MonsterService.Notify(player, "That trade request expired.", "error")
		return
	end
	local trade: Trade = { Players = { from, player }, Offers = { [from] = {}, [player] = {} }, Ready = {} }
	trades[from] = trade
	trades[player] = trade
	sendUpdate(trade)
end

local function onSetOffer(player: Player, ids: unknown)
	local trade = trades[player]
	if not trade or type(ids) ~= "table" then
		return
	end
	local clean: { string } = {}
	for _, id in ids :: { any } do
		if type(id) == "string" and #clean < Config.Trade.MaxOffer then
			table.insert(clean, id)
		end
	end
	if not validOffer(player, clean) then
		return
	end
	trade.Offers[player] = clean
	trade.Ready = {} -- أي تغيير بيلغي التأكيد
	sendUpdate(trade)
end

local function onReady(player: Player, ready: unknown)
	local trade = trades[player]
	if not trade then
		return
	end
	trade.Ready[player] = ready == true
	local partner = partnerOf(trade, player)
	if trade.Ready[player] and trade.Ready[partner] then
		execute(trade)
	else
		sendUpdate(trade)
	end
end

local function onCancel(player: Player)
	local trade = trades[player]
	if trade then
		closeTrade(trade, player.DisplayName .. " cancelled the trade.")
	end
end

function TradeService.CleanupPlayer(player: Player)
	onCancel(player)
	requests[player] = nil
	for _, pending in requests do
		pending[player] = nil
	end
end

function TradeService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	remotes.TradeRequest.OnServerEvent:Connect(onRequest)
	remotes.TradeRespond.OnServerEvent:Connect(onRespond)
	remotes.TradeSetOffer.OnServerEvent:Connect(onSetOffer)
	remotes.TradeReady.OnServerEvent:Connect(onReady)
	remotes.TradeCancel.OnServerEvent:Connect(onCancel)
end

return TradeService
