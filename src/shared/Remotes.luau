--!strict
-- السيرفر بيعمل الـ RemoteEvents، والكلاينت بيستناها.

local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	-- سيرفر → كلاينت
	"StateUpdate", -- (state)
	"Notify", -- (text, kind)
	"OpenShop", -- ()
	"OpenMonster", -- (monsterId)
	-- كلاينت → سيرفر
	"BuyEgg", -- (eggType)
	"FeedMonster", -- (monsterId)
	"PlayMonster", -- (monsterId)
	"SellMonster", -- (monsterId)
	"BuyUpgrade", -- (upgradeName)
	"Teleport", -- ("Home" | "Shop")
	"BuyPass", -- (passName)
	"BuyProduct", -- (productName)
	"ClaimDaily", -- ()
	"Spin", -- ()
	"BuyAccessory", -- (accessoryName, monsterId)
	"EquipAccessory", -- (monsterId, slot, accessoryName?)
	"MiniGameStart", -- (monsterId, gameName)
	"MiniGameFinish", -- (score)
	"TradeRequest", -- (targetUserId)
	"TradeRespond", -- (fromUserId, accepted)
	"TradeSetOffer", -- ({ monsterId })
	"TradeReady", -- (ready)
	"TradeCancel", -- ()
	"ArenaChallenge", -- (targetUserId, monsterId)
	"ArenaRespond", -- (fromUserId, monsterId?)  monsterId = nil يعني رفض
	-- سيرفر → كلاينت (زيادة)
	"Announce", -- (text, color)  إعلان كبير لكل السيرفر
	"SpinResult", -- (prizeIndex)
	"MiniGameState", -- ({ Game, TimeLeft, Progress, Done, Xp })
	"TradeUpdate", -- (trade state | nil)
	"TradeIncoming", -- (fromUserId, fromName)
	"ArenaIncoming", -- (fromUserId, fromName, monsterName)
	"ArenaUpdate", -- (battle state | nil)
}

local Remotes = {}

function Remotes.Get(): { [string]: RemoteEvent }
	local result: { [string]: RemoteEvent } = {}
	local folder: Instance
	if RunService:IsServer() then
		local existing = script.Parent:FindFirstChild("RemoteEvents")
		if existing then
			folder = existing
		else
			folder = Instance.new("Folder")
			folder.Name = "RemoteEvents"
			folder.Parent = script.Parent
		end
		for _, name in EVENT_NAMES do
			local remote = folder:FindFirstChild(name) :: RemoteEvent?
			if not remote then
				local created = Instance.new("RemoteEvent")
				created.Name = name
				created.Parent = folder
				remote = created
			end
			result[name] = remote :: RemoteEvent
		end
	else
		folder = script.Parent:WaitForChild("RemoteEvents")
		for _, name in EVENT_NAMES do
			result[name] = folder:WaitForChild(name) :: RemoteEvent
		end
	end
	return result
end

return Remotes
