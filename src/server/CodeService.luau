--!strict
-- Promo codes for the shop's Codes tab. The client only sends the typed text; the server normalises it,
-- looks it up in Config.Codes, remembers the redemption in the player's saved data and grants the reward.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)

local CodeService = {}

local COOLDOWN = 1.5
local MAX_LENGTH = 32
local lastAttempt: { [Player]: number } = {}

local function normalise(raw: unknown): string?
	if type(raw) ~= "string" or #raw > MAX_LENGTH then return nil end
	local cleaned = string.upper((raw:gsub("^%s+", ""):gsub("%s+$", "")))
	if cleaned == "" then return nil end
	return cleaned
end

function CodeService.Init(remotes: { [string]: RemoteEvent })
	remotes.RedeemCode.OnServerEvent:Connect(function(player: Player, raw: unknown)
		local now = os.clock()
		if lastAttempt[player] and now - lastAttempt[player] < COOLDOWN then return end
		lastAttempt[player] = now
		local profile = DataService.Get(player)
		if not profile or profile.Closing == true then return end
		local code = normalise(raw)
		local reward = if code then Config.Codes[code] else nil
		if not code or not reward then
			remotes.RedeemResult:FireClient(player, false, "That code is not valid.")
			return
		end
		if profile.Data.RedeemedCodes[code] == true then
			remotes.RedeemResult:FireClient(player, false, "You already used that code.")
			return
		end
		-- No yield between the check and the write, so a code can never be claimed twice.
		profile.Data.RedeemedCodes[code] = true
		DataService.AddCoins(player, reward.Coins)
		DataService.QueueSave(player)
		MonsterService.PushState(player)
		remotes.RedeemResult:FireClient(player, true, string.format("Code redeemed! +%d coins", reward.Coins))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttempt[player] = nil
	end)
end

return CodeService
