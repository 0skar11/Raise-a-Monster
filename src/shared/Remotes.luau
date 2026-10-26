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
	"PlaceMonster", -- (monsterId, unlockedSlot), swaps safely with current occupant
	"BenchMonster", -- (monsterId), retains ownership and stops plot income
	"PlaceEgg", -- (eggId, unlockedSlot), puts a waiting bench egg in a free slot and starts its hatch timer
	"AutoPlaceMonsters", -- (), ranks owned available monsters by actual production
	"ToggleFollower", -- (monsterId), server validates adult ownership and limit
	"BuyUpgrade", -- (upgradeName)
	"Teleport", -- ("Home" | "Shop")
	"BuyPass", -- (passName)
	"BuyWeapon", -- (weaponName), paid with in-game coins
	"EquipWeapon", -- (weaponName), server checks coin/pass ownership; "Bat" is free
	"BuyProduct", -- (productName)
	"Spin", -- ()
	"RequestAdChest", -- (), بعد ما الكلاينت يتأكد إن فيه إعلان؛ السيرفر يتحقق من المسافة والـ cooldown
	"BuyAccessory", -- (accessoryName, monsterId)
	"BuySpeedAccessory", -- (accessoryName)
	"EquipSpeedAccessory", -- (accessoryName?), nil removes the selected player accessory
	"EquipAccessory", -- (monsterId, slot, accessoryName?)
	"MiniGameStart", -- (monsterId, gameName)
	"MiniGameCatch", -- () محاولة التقاط؛ السيرفر يحدد النقاط ويحد المعدل
	"MiniGameFinish", -- () إنهاء Catch بعد انتهاء الوقت؛ لا تُقبل نتيجة من العميل
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
	"MonsterAttack", -- (attack) علامة ضربة الوحش على الأرض + الـ VFX لكل اللاعبين
	"PlayerHurt", -- (damage, color) اللاعب اتضرب: هزة كاميرا ولون أحمر
	"HitFeedback", -- (position, damage, crit) رقم الضرر فوق الهدف للي ضرب
	-- Halloween event (all server validated; the client only ever sends an item id string)
	"HalloweenState", -- (state) Candy, owned/equipped items, boost time left, event timers
	"HalloweenOpenShop", -- () the Pumpkin Merchant prompt was used close enough to the merchant
	"HalloweenHint", -- ({ Sector, Band, Remaining } | nil) soft pumpkin direction, never the exact spot
	"HalloweenBuy", -- (itemId)
	"HalloweenEquip", -- (itemId, equip)
	"HalloweenSync", -- () ask for a fresh HalloweenState
	-- Admin panel (server checks Config.Admin.Usernames on every call; non-admins are ignored)
	"AdminAction", -- ("Hello" | actionName, { Target: string?, Amount: number?, Name: string?, Text: string? })
	"AdminAccess", -- (true, { actionNames }) only ever sent to an admin
	-- Big Boss attack visuals (server decides damage; the client only draws)
	"BossFx", -- (kind, data)
	"BossLoot", -- ({ Share, Rank, Fighters, Needed, Items = { { Icon, Name, Detail, Rarity } } }) the loot you won from the Pumpkin Titan
	"BossSummoned", -- ({ UserId, Name, DisplayName, Robux }) server-confirmed paid summon announcement
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
