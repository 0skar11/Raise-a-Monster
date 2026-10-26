--!strict
-- Gamepasses و Developer Products.
-- الـ Ids بتتحط في Config.Gamepasses و Config.Products بعد ما تعملهم من Creator Dashboard.
-- لو Id = 0 وانت في Studio، الزرار بيدّيك الحاجة مجاناً عشان تقدر تجرّبها.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)

local MonetizationService = {}
-- Bound by the server bootstrap; the client can only request a Marketplace prompt.
MonetizationService.CanPromptBossSummon = function(_player: Player): boolean return false end
MonetizationService.ProcessBossSummonReceipt = function(_player: Player, _receipt: any): boolean return false end

-- Egg Keeper developer products share this one ProcessReceipt (Roblox allows a single callback).
MonetizationService.IsEggStoreProduct = function(_productId: unknown): boolean return false end
MonetizationService.ProcessEggStoreReceipt = function(_player: Player, _receipt: any): boolean return false end

local owned: { [Player]: { [string]: boolean } } = {}
local lastPrompt: { [Player]: number } = {}
local lastGearAction: { [Player]: number } = {}
local processingReceipts: { [string]: boolean } = {}
local adultBusy: { [Player]: boolean } = {}
local adultPrompts: { [Player]: any } = {}

local function isAdultProduct(name: string): boolean
	return name == "SkipToAdultOne" or name == "SkipToAdultAll"
end

local function validAdultIntent(intent: any, name: string, productId: number): boolean
	if type(intent) ~= "table" or intent.ProductName ~= name or intent.ProductId ~= productId
		or type(intent.Token) ~= "string" or type(intent.Targets) ~= "table" or #intent.Targets == 0 then return false end
	if intent.Status ~= "Prepared" and intent.Status ~= "Prompting" and intent.Status ~= "Applied" then return false end
	if intent.ReceiptId ~= nil and type(intent.ReceiptId) ~= "string" then return false end
	if name == "SkipToAdultOne" and #intent.Targets ~= 1 then return false end
	for _, target in intent.Targets do
		if type(target) ~= "table" or type(target.Id) ~= "string" or type(target.Identity) ~= "string" then return false end
	end
	return true
end

local function promptAdultProduct(player: Player, name: string, selectedId: unknown)
	local profile = DataService.Get(player)
	local product = Config.Products[name]
	if not profile or profile.LoadFailed or profile.Closing or profile.CanSave == false or adultBusy[player] then return end
	if adultPrompts[player] then
		MonsterService.Notify(player, "Finish the current purchase window before choosing another Adult purchase.", "info")
		return
	end
	if product.Id <= 0 then
		MonsterService.Notify(player, product.Name .. " is coming soon!", "info")
		return
	end
	local intent = profile.Data.PendingAdultPurchase
	if intent then
		-- Only a never-prompted, durably prepared selection may be retried.
		-- An uncertain/disconnected prompt is kept for its delayed receipt.
		if not validAdultIntent(intent, name, product.Id) or intent.Status ~= "Prepared"
			or (name == "SkipToAdultOne" and intent.Targets[1].Id ~= selectedId) then
			MonsterService.Notify(player, "Your previous Adult purchase is still pending. Its original monsters are reserved for that purchase.", "info")
			return
		end
	else
		local targets = MonsterService.SnapshotAdultTargets(player, selectedId, name == "SkipToAdultAll", DataService.NewPurchaseToken)
		if #targets == 0 then
			MonsterService.Notify(player, "Select an available monster below Adult level. Adult, carried and trading monsters are excluded.", "error")
			return
		end
		intent = { Token = DataService.NewPurchaseToken(), ProductName = name, ProductId = product.Id, Status = "Prepared", Targets = targets }
		profile.Data.PendingAdultPurchase = intent
	end
	adultBusy[player] = true
	local prepared = DataService.Save(player)
	if not prepared or DataService.Get(player) ~= profile or profile.Closing then
		adultBusy[player] = nil
		MonsterService.Notify(player, "Your selection could not be saved. No purchase window was opened; try again when saving is available.", "error")
		return
	end
	intent.Status = "Prompting"
	local ready = DataService.Save(player)
	if not ready or DataService.Get(player) ~= profile or profile.Closing then
		intent.Status = "Prepared"
		adultBusy[player] = nil
		MonsterService.Notify(player, "Your selection could not be saved. No purchase window was opened; try again when saving is available.", "error")
		return
	end
	-- Saving yields: a target may have grown, left inventory or entered a trade.
	-- Never open a paid prompt when none of the original targets still qualify.
	if not MonsterService.HasEligibleAdultTargets(player, intent.Targets) then
		intent.Status = "Prepared"
		profile.Data.PendingAdultPurchase = nil
		if not DataService.Save(player) and DataService.Get(player) == profile then profile.Data.PendingAdultPurchase = intent end
		adultBusy[player] = nil
		MonsterService.Notify(player, "Your selected monsters are no longer available below Adult level. No purchase window was opened.", "info")
		return
	end
	adultPrompts[player] = intent
	local ok = pcall(function() MarketplaceService:PromptProductPurchase(player, product.Id) end)
	adultBusy[player] = nil
	if not ok then
		-- A thrown Marketplace call is uncertain: never replace its frozen targets.
		MonsterService.Notify(player, "The purchase window could not open. Your original selection remains pending safely.", "error")
	end
end

local function giveWeapons(player: Player)
	local profile = DataService.Get(player)
	CombatService.GiveWeapons(
		player,
		MonetizationService.GetOwnedPasses(player),
		if profile then profile.Data.Weapons else {},
		if profile then profile.Data.EquippedWeapon else "Bat"
	)
end

function MonetizationService.HasPass(player: Player, name: string): boolean
	local set = owned[player]
	return set ~= nil and (set[name] == true or (name == "VIPSword" and set.VIP == true))
end

function MonetizationService.GetOwnedPasses(player: Player): { [string]: boolean }
	local set = table.clone(owned[player] or {})
	if set.VIP then set.VIPSword = true end
	return set
end

function MonetizationService.BoostLeft(player: Player): number
	local profile = DataService.Get(player)
	return math.max(0, (profile and profile.Data.SpeedBoostUntil or 0) - os.time())
end

-- لما الـ Pass يتفعّل (اشترى أو دخل وهو معاه)
local function onPassGranted(player: Player, name: string)
	if name == "VIPSword" or name == "VIP" then
		giveWeapons(player)
	elseif Config.WeaponStats[name] then
		giveWeapons(player)
	elseif name == "AutoCollect" then
		PlotService.SetCollectorEnabled(player, false)
	elseif name == "ExtraSlots" then
		local unlocked = MonsterService.GetUnlockedSlots(player)
		PlotService.SetUnlockedSlots(player, unlocked)
		local profile = DataService.Get(player)
		if profile then
			local baseUnlocked = math.min(Config.MaxSlots, Config.BaseSlots + (profile.Data.SlotUpgrades or 0))
			for _, monster in profile.Data.Monsters do
				if monster.Slot > baseUnlocked and MonsterService.IsPlaced(player, monster) then PlotService.UpdateMonster(player, monster, false) end
			end
			for _, egg in profile.Data.Eggs do
				if egg.Slot > baseUnlocked and egg.Slot <= unlocked then PlotService.RenderEgg(player, egg.Id, egg.EggType, egg.Slot) end
			end
		end
	end
	MonsterService.PushState(player)
end

local function grantPass(player: Player, name: string)
	local session = owned[player]
	if not session or session[name] then
		return
	end
	session[name] = true
	onPassGranted(player, name)
end

-- Developer Products: بيرجع true لو اتنفذ
local function grantProduct(player: Player, name: string): boolean
	local product = Config.Products[name]
	if product and product.Coins then
		if not DataService.Get(player) then
			return false
		end
		-- الأكبر بين الحد الأدنى الثابت ودقايق الدخل الحالي، فالحزمة تفضل مفيدة في أي منطقة
		local amount = product.Coins
		if product.Minutes then
			amount = math.max(amount, math.floor(MonsterService.GetIncomePerSecond(player) * product.Minutes * 60))
		end
		DataService.AddCoins(player, amount)
		if name == "AdChest" then
			local profile = DataService.Get(player)
			if profile then profile.Data.LastAdChest = os.time() end
		end
		MonsterService.Notify(player, "💰 +" .. MonsterMath.FormatNumber(amount) .. " coins!", "success")
		return true
	end
	if name == "InstantHatch" then
		if not MonsterService.HatchAllNow(player) then
			MonsterService.Notify(player, "You have no eggs to hatch right now!", "error")
			return false
		end
		MonsterService.Notify(player, "⚡ All your eggs are hatching now!", "success")
		return true
	elseif name == "LuckyEgg" then
		if not MonsterService.AddEgg(player, "Lucky") then
			MonsterService.Notify(player, "Your base is full! Free a slot first.", "error")
			return false
		end
		return true
	elseif name == "SpeedBoost" then
		local profile = DataService.Get(player)
		if not profile then
			return false
		end
		local start = math.max(os.time(), profile.Data.SpeedBoostUntil)
		profile.Data.SpeedBoostUntil = start + Config.SpeedBoost.Duration
		CharacterService.SetSpeedFactor(player, "Boost", Config.SpeedBoost.Multiplier)
		MonsterService.Notify(player, "💨 Speed Boost for 10 minutes!", "success")
		return true
	end
	return false
end
-- الصندوق المجاني بيستخدمها في وضع الاختبار (Studio) لما Id المنتج لسه 0
MonetizationService.GrantProduct = grantProduct

local function buyPass(player: Player, name: unknown)
	if type(name) ~= "string" then
		return
	end
	if Config.WeaponStats[name] then
		MonsterService.Notify(player, "Weapons are bought with coins from the shop now.", "info")
		return
	end
	local pass = Config.Gamepasses[name]
	if not pass or pass.Hidden then
		return
	end
	if MonetizationService.HasPass(player, name) then
		MonsterService.Notify(player, "You already own " .. pass.Name .. "!", "info")
		return
	end
	local profile = DataService.Get(player)
	if not profile or profile.LoadFailed or profile.Closing or profile.CanSave == false or not owned[player] then return end
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < Config.Monetization.PromptCooldown then return end
	lastPrompt[player] = now
	if pass.Id == 0 then
		if RunService:IsStudio() and name ~= "AutoMinigame" then
			grantPass(player, name)
			MonsterService.Notify(player, "🧪 Studio test: you got " .. pass.Name .. " for free.", "success")
		else
			MonsterService.Notify(player, pass.Name .. " is coming soon!", "info")
		end
		return
	end
	local ok = pcall(function() MarketplaceService:PromptGamePassPurchase(player, pass.Id) end)
	if not ok then MonsterService.Notify(player, "The purchase window could not open. Please try again.", "error") end
end

local function buyWeapon(player: Player, name: unknown)
	if type(name) ~= "string" or #name > 64 or not Config.WeaponStats[name] then
		return
	end
	local profile = DataService.Get(player)
	local price = Config.WeaponCoinPrices[name]
	local pass = Config.Gamepasses[name]
	if not profile or type(profile.Data.Weapons) ~= "table" or not price or not pass then
		return
	end
	if profile.Data.Weapons[name] == true or MonetizationService.HasPass(player, name) then
		MonsterService.Notify(player, "You already own " .. pass.Name .. "!", "info")
		return
	end
	if not DataService.TrySpend(player, price) then
		MonsterService.Notify(player, "Not enough coins!", "error")
		return
	end
	profile.Data.Weapons[name] = true
	profile.Data.EquippedWeapon = name
	giveWeapons(player)
	MonsterService.Notify(player, "⚔️ You bought " .. pass.Name .. "!", "success")
	MonsterService.PushState(player)
	task.spawn(DataService.Save, player)
end

local function equipWeapon(player: Player, name: unknown)
	if type(name) ~= "string" or #name > 64 or (name ~= "Bat" and not Config.WeaponStats[name]) then return end
	local profile = DataService.Get(player)
	if not profile or type(profile.Data.Weapons) ~= "table" then return end
	if name ~= "Bat" and profile.Data.Weapons[name] ~= true and not MonetizationService.HasPass(player, name) then return end
	local now = os.clock()
	if lastGearAction[player] and now - lastGearAction[player] < Config.Security.GearEquipCooldown then return end
	lastGearAction[player] = now
	if profile.Data.EquippedWeapon == name then return end
	profile.Data.EquippedWeapon = name
	giveWeapons(player)
	MonsterService.PushState(player)
	DataService.QueueSave(player)
end

local function buyProduct(player: Player, name: unknown, selectedId: unknown)
	if type(name) ~= "string" then
		return
	end
	local product = Config.Products[name]
	if not product or product.Hidden then -- الصندوق بيتدّي بالإعلان بس، مش بالشراء
		return
	end
	local profile = DataService.Get(player)
	if not profile or profile.LoadFailed or profile.Closing or profile.CanSave == false then
		MonsterService.Notify(player, "Purchases are unavailable while saving is offline.", "error")
		return
	end
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < Config.Monetization.PromptCooldown then
		return
	end
	lastPrompt[player] = now
	if name == "SummonBoss" and not MonetizationService.CanPromptBossSummon(player) then return end
	if isAdultProduct(name) then
		promptAdultProduct(player, name, selectedId)
		return
	end
	if product.Id == 0 then
		if RunService:IsStudio() then
			if grantProduct(player, name) then
				MonsterService.Notify(player, "🧪 Studio test: " .. product.Name .. " for free.", "success")
			end
		else
			MonsterService.Notify(player, product.Name .. " is coming soon!", "info")
		end
		MonsterService.PushState(player)
		return
	end
	local ok = pcall(function() MarketplaceService:PromptProductPurchase(player, product.Id) end)
	if not ok then MonsterService.Notify(player, "The purchase window could not open. Please try again.", "error") end
end

local function loadPasses(player: Player, session: { [string]: boolean })
	for name, pass in Config.Gamepasses do
		if pass.Id ~= 0 then
			for attempt = 1, Config.Monetization.OwnershipRetries do
				if owned[player] ~= session then return end
				local ok, has = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
				end)
				-- A Marketplace response can arrive after PlayerRemoving or another setup.
				if owned[player] ~= session then return end
				if ok then
					if has then grantPass(player, name) end
					break
				end
				if attempt < Config.Monetization.OwnershipRetries then task.wait(attempt * Config.Monetization.OwnershipRetryDelay) end
			end
		end
	end
end

function MonetizationService.SetupPlayer(player: Player)
	local session = {}
	owned[player] = session
	task.spawn(loadPasses, player, session)
end

-- بيتنادى كل ما الشخصية تتولد
function MonetizationService.OnCharacter(player: Player)
	if MonetizationService.BoostLeft(player) > 0 then
		CharacterService.SetSpeedFactor(player, "Boost", Config.SpeedBoost.Multiplier)
	end
end

function MonetizationService.CleanupPlayer(player: Player)
	owned[player] = nil
	lastPrompt[player] = nil
	lastGearAction[player] = nil
	adultPrompts[player] = nil
end

function MonetizationService.Init(remotes: { [string]: RemoteEvent })
	remotes.BuyPass.OnServerEvent:Connect(buyPass)
	remotes.BuyWeapon.OnServerEvent:Connect(buyWeapon)
	remotes.EquipWeapon.OnServerEvent:Connect(equipWeapon)
	remotes.BuyProduct.OnServerEvent:Connect(buyProduct)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local active = player and adultPrompts[player]
		if not player or not active or active.ProductId ~= productId then return end
		adultPrompts[player] = nil
		if purchased then return end -- Receipts alone grant purchases.
		task.spawn(function()
			while adultBusy[player] do task.wait() end
			local profile = DataService.Get(player)
			if not profile or profile.Closing or profile.Data.PendingAdultPurchase ~= active or active.ReceiptId then return end
			adultBusy[player] = true
			profile.Data.PendingAdultPurchase = nil
			local saved = DataService.Save(player)
			if not saved and DataService.Get(player) == profile and profile.Data.PendingAdultPurchase == nil then
				-- Keep the original targets until cancellation itself is durable.
				active.Status = "Prepared"
				profile.Data.PendingAdultPurchase = active
			end
			adultBusy[player] = nil
		end)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased or passId <= 0 or not owned[player] then
			return
		end
		for name, pass in Config.Gamepasses do
			if pass.Id == passId then
				grantPass(player, name)
				MonsterService.Notify(player, "🎉 Thanks! You now own " .. pass.Name .. "!", "success")
			end
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local profile = player and DataService.Get(player)
		if not player or not profile or profile.LoadFailed or profile.Closing or type(receipt.PurchaseId) ~= "string" or #receipt.PurchaseId == 0 then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if MonetizationService.IsEggStoreProduct(receipt.ProductId) then
			return if MonetizationService.ProcessEggStoreReceipt(player, receipt)
				then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for name, product in Config.Products do
			if product.Id > 0 and product.Id == receipt.ProductId then
				local purchaseId = receipt.PurchaseId
				if name == "SummonBoss" then
					return if MonetizationService.ProcessBossSummonReceipt(player, receipt)
						then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
				end
				if isAdultProduct(name) then
					if processingReceipts[purchaseId] or adultBusy[player] then return Enum.ProductPurchaseDecision.NotProcessedYet end
					local intent = profile.Data.PendingAdultPurchase
					local alreadyProcessed = profile.Data.ProcessedReceipts[purchaseId] == true
					if not alreadyProcessed and (not validAdultIntent(intent, name, product.Id)
						or intent.Status == "Prepared" or (intent.ReceiptId and intent.ReceiptId ~= purchaseId)) then
						return Enum.ProductPurchaseDecision.NotProcessedYet
					end
					processingReceipts[purchaseId], adultBusy[player] = true, true
					local changed = {}
					if not alreadyProcessed then
						local applied = MonsterService.ApplyAdultTargets(player, intent.Targets)
						if not applied then
							processingReceipts[purchaseId], adultBusy[player] = nil, nil
							return Enum.ProductPurchaseDecision.NotProcessedYet
						end
						changed = applied
						intent.ReceiptId = purchaseId
						intent.Status = "Applied"
						profile.Data.ProcessedReceipts[purchaseId] = true
					end
					local completing = intent and intent.ReceiptId == purchaseId
					if completing then profile.Data.PendingAdultPurchase = nil end
					local saved = DataService.Save(player)
					if not saved and completing and DataService.Get(player) == profile and profile.Data.PendingAdultPurchase == nil then
						profile.Data.PendingAdultPurchase = intent
					end
					processingReceipts[purchaseId], adultBusy[player] = nil, nil
					-- Rendering is cosmetic and cannot turn a durable reward into another grant.
					pcall(MonsterService.RefreshAdultTargets, player, changed)
					if saved then
						-- A receipt can arrive before its prompt Finished event. Keep the
						-- prompt active so that late event cannot cancel a newer selection.
						MonsterService.PushState(player)
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				if profile.Data.ProcessedReceipts[purchaseId] then
					return if DataService.Save(player)
						then Enum.ProductPurchaseDecision.PurchaseGranted
						else Enum.ProductPurchaseDecision.NotProcessedYet
				end
				if processingReceipts[purchaseId] then
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				processingReceipts[purchaseId] = true
				local granted = grantProduct(player, name)
				if granted then
					profile.Data.ProcessedReceipts[purchaseId] = true
					local saved = DataService.Save(player)
					processingReceipts[purchaseId] = nil
					if saved then
						MonsterService.PushState(player)
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				processingReceipts[purchaseId] = nil
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- الـ Speed Boost بيخلص
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if profile and profile.Data.SpeedBoostUntil > 0 and os.time() >= profile.Data.SpeedBoostUntil then
					profile.Data.SpeedBoostUntil = 0
					CharacterService.SetSpeedFactor(player, "Boost", nil)
					MonsterService.Notify(player, "Your Speed Boost ended.", "info")
				end
			end
		end
	end)
end

return MonetizationService
