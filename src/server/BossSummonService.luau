--!strict
-- A receipt buys a durable summon, not an unreliable one-shot world mutation.
-- Persist the credit before spawning. A server crash leaves it recoverable on rejoin;
-- after spawning, keep a server-local receipt set until the debit is saved as well.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MonsterService = require(script.Parent.MonsterService)

local BossSummonService = {}
local busy: { [Player]: boolean } = {}
local delivered: { [string]: boolean } = {}
local remotes: { [string]: RemoteEvent } = {}

local function safeProfile(player: Player): DataService.Profile?
	local profile = DataService.Get(player)
	if not profile or profile.LoadFailed or profile.Closing or profile.CanSave == false then return nil end
	return profile
end

function BossSummonService.CanPrompt(player: Player): boolean
	local profile = safeProfile(player)
	if not profile then return false end
	if EventService.IsBossAlive() then
		MonsterService.Notify(player, "The Pumpkin Titan is already here! Defeat it before buying another summon.", "info")
		return false
	end
	if next(profile.Data.PendingBossSummons) then
		MonsterService.Notify(player, "Your paid summon is waiting safely and will appear as soon as the arena is free.", "info")
		return false
	end
	return true
end

function BossSummonService.Deliver(player: Player)
	local profile = safeProfile(player)
	if not profile or busy[player] or not next(profile.Data.PendingBossSummons) then return end
	local receiptId, robux = next(profile.Data.PendingBossSummons)
	-- Debit retries go first, even when other paid summons are waiting for a boss.
	for id, spent in profile.Data.PendingBossSummons do
		if delivered[id] then receiptId, robux = id, spent; break end
	end
	local alreadyDelivered = delivered[receiptId] == true
	-- A waiting credit is read-only throughout the fight.
	if not alreadyDelivered and EventService.IsBossAlive() then return end
	busy[player] = true
	if not alreadyDelivered then
		-- Also makes the credit durable if its original receipt save timed out.
		local saved = DataService.Save(player)
		if not saved or safeProfile(player) ~= profile then busy[player] = nil; return end
		local ok, spawned = pcall(EventService.SpawnBoss, true)
		if not ok or spawned ~= true then busy[player] = nil; return end
		delivered[receiptId] = true
		-- Display names come from the authenticated Player, never the request.
		if remotes.BossSummoned then
			remotes.BossSummoned:FireAllClients({
				UserId = player.UserId, Name = player.Name,
				DisplayName = player.DisplayName, Robux = robux,
			})
		end
		MonsterService.Notify(player, "🎃 Your paid Pumpkin Titan summon is here! Enter the Halloween portal.", "success")
	end
	profile.Data.PendingBossSummons[receiptId] = nil
	-- If this fails, retries in this server use delivered[]; a replacement server
	-- can recover the credit because the original world effect is gone with it.
	if not DataService.Save(player) and safeProfile(player) == profile then
		profile.Data.PendingBossSummons[receiptId] = robux
	end
	busy[player] = nil
end

function BossSummonService.ProcessReceipt(player: Player, receipt: any): boolean
	local profile = safeProfile(player)
	if not profile or busy[player] or receipt.ProductId ~= Config.Products.SummonBoss.Id
		or type(receipt.PurchaseId) ~= "string" or #receipt.PurchaseId == 0 then return false end
	local id = receipt.PurchaseId
	busy[player] = true
	if profile.Data.ProcessedReceipts[id] ~= true then
		local spent = receipt.CurrencySpent
		profile.Data.PendingBossSummons[id] = if type(spent) == "number" and spent == spent and spent >= 0 and spent < math.huge
			then math.floor(spent) else Config.Products.SummonBoss.Price
		profile.Data.ProcessedReceipts[id] = true
	end
	local saved = DataService.Save(player)
	busy[player] = nil
	if not saved or safeProfile(player) ~= profile then return false end
	if next(profile.Data.PendingBossSummons) then
		MonsterService.Notify(player, "Purchase confirmed! Your Pumpkin Titan summon is reserved for this server; it waits safely if the arena is busy.", "success")
		task.spawn(BossSummonService.Deliver, player)
	end
	return true -- a saved credit is already a delivered, recoverable purchase benefit
end

function BossSummonService.Init(allRemotes: { [string]: RemoteEvent })
	remotes = allRemotes
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(BossSummonService.Deliver, player)
				if not ok then
					busy[player] = nil
					warn("[BossSummonService] Delivery will retry:", err)
				end
			end
		end
	end)
end

return BossSummonService
