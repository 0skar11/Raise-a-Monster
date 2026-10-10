--!strict
-- Gamepasses و Developer Products.
-- الـ Ids بتتحط في Config.Gamepasses و Config.Products بعد ما تعملهم من Creator Dashboard.
-- لو Id = 0 وانت في Studio، الزرار بيدّيك الحاجة مجاناً عشان تقدر تجرّبها.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)

local MonetizationService = {}

local owned: { [Player]: { [string]: boolean } } = {}
local boostUntil: { [Player]: number } = {}
local lastPrompt: { [Player]: number } = {}

function MonetizationService.HasPass(player: Player, name: string): boolean
	local set = owned[player]
	return set ~= nil and set[name] == true
end

function MonetizationService.GetOwnedPasses(player: Player): { [string]: boolean }
	return owned[player] or {}
end

function MonetizationService.BoostLeft(player: Player): number
	return math.max(0, (boostUntil[player] or 0) - os.clock())
end

-- لما الـ Pass يتفعّل (اشترى أو دخل وهو معاه)
local function onPassGranted(player: Player, name: string)
	if name == "VIPSword" then
		CombatService.GiveWeapons(player, MonetizationService.GetOwnedPasses(player))
	elseif Config.WeaponStats[name] then
		CombatService.GiveWeapons(player, MonetizationService.GetOwnedPasses(player))
	elseif name == "ExtraSlots" then
		PlotService.SetUnlockedSlots(player, MonsterService.GetUnlockedSlots(player))
	end
	MonsterService.PushState(player)
end

local function grantPass(player: Player, name: string)
	owned[player] = owned[player] or {}
	if owned[player][name] then
		return
	end
	owned[player][name] = true
	onPassGranted(player, name)
end

-- Developer Products: بيرجع true لو اتنفذ
local function grantProduct(player: Player, name: string): boolean
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
		local start = math.max(os.clock(), boostUntil[player] or 0)
		boostUntil[player] = start + Config.SpeedBoost.Duration
		CharacterService.SetSpeedFactor(player, "Boost", Config.SpeedBoost.Multiplier)
		MonsterService.Notify(player, "💨 Speed Boost for 10 minutes!", "success")
		return true
	end
	return false
end

local function buyPass(player: Player, name: unknown)
	if type(name) ~= "string" then
		return
	end
	local pass = Config.Gamepasses[name]
	if not pass then
		return
	end
	if MonetizationService.HasPass(player, name) then
		MonsterService.Notify(player, "You already own " .. pass.Name .. "!", "info")
		return
	end
	if pass.Id == 0 then
		if RunService:IsStudio() then
			grantPass(player, name)
			MonsterService.Notify(player, "🧪 Studio test: you got " .. pass.Name .. " for free.", "success")
		else
			MonsterService.Notify(player, pass.Name .. " is coming soon!", "info")
		end
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

local function buyProduct(player: Player, name: unknown)
	if type(name) ~= "string" then
		return
	end
	local product = Config.Products[name]
	if not product then
		return
	end
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < 1 then
		return
	end
	lastPrompt[player] = now
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
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

local function loadPasses(player: Player)
	for name, pass in Config.Gamepasses do
		if pass.Id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and has then
				grantPass(player, name)
			end
		end
	end
end

function MonetizationService.SetupPlayer(player: Player)
	owned[player] = owned[player] or {}
	task.spawn(loadPasses, player)
end

-- بيتنادى كل ما الشخصية تتولد
function MonetizationService.OnCharacter(player: Player)
	if MonetizationService.BoostLeft(player) > 0 then
		CharacterService.SetSpeedFactor(player, "Boost", Config.SpeedBoost.Multiplier)
	end
end

function MonetizationService.CleanupPlayer(player: Player)
	owned[player] = nil
	boostUntil[player] = nil
	lastPrompt[player] = nil
end

function MonetizationService.Init(remotes: { [string]: RemoteEvent })
	remotes.BuyPass.OnServerEvent:Connect(buyPass)
	remotes.BuyProduct.OnServerEvent:Connect(buyProduct)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
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
		if not player or not DataService.Get(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for name, product in Config.Products do
			if product.Id == receipt.ProductId then
				if grantProduct(player, name) then
					MonsterService.PushState(player)
					task.spawn(DataService.Save, player)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- الـ Speed Boost بيخلص
	task.spawn(function()
		while true do
			task.wait(1)
			for player, untilTime in boostUntil do
				if os.clock() >= untilTime then
					boostUntil[player] = nil
					CharacterService.SetSpeedFactor(player, "Boost", nil)
					if player.Parent then
						MonsterService.Notify(player, "Your Speed Boost ended.", "info")
					end
				end
			end
		end
	end)
end

return MonetizationService
