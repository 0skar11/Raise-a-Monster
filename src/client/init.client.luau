--!strict
-- الكلاينت: الواجهة، إظهار/إخفاء أزرار الـ ProximityPrompt، وتأثير الـ Rainbow.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.UI)

local player = Players.LocalPlayer
local remotes = Remotes.Get()
local ui = UI.Create(player:WaitForChild("PlayerGui") :: PlayerGui)

local state: any = nil
local openMonsterId: string? = nil
local sellConfirmUntil = 0

-- تحديث الواجهة ---------------------------------------------------------------------

local function findMonster(id: string?): any
	if not state or not id then
		return nil
	end
	for _, monster in state.Monsters do
		if monster.Id == id then
			return monster
		end
	end
	return nil
end

local function refreshMonsterPanel()
	if not ui.MonsterFrame.Visible then
		return
	end
	local monster = findMonster(openMonsterId)
	if not monster or monster.Carried then
		ui.MonsterFrame.Visible = false
		return
	end
	local rarity = Config.Rarities[monster.Rarity]
	ui.MonsterName.Text = monster.DisplayName
	ui.MonsterName.TextColor3 = rarity.Color
	ui.MonsterInfo.Text = string.format(
		"%s · %s · Level %d%s",
		monster.Rarity,
		monster.Stage,
		monster.Level,
		if monster.Mutation then " · ✨ " .. monster.Mutation else ""
	)

	if monster.MaxLevel then
		UI.SetBar(ui.XpBar, 1, "MAX LEVEL")
	else
		UI.SetBar(
			ui.XpBar,
			monster.Xp / monster.XpNeeded,
			string.format("%d / %d", math.floor(monster.Xp), monster.XpNeeded)
		)
	end
	UI.SetBar(ui.HungerBar, monster.Hunger / 100, string.format("%d%%", math.floor(monster.Hunger)))
	UI.SetBar(ui.HappyBar, monster.Happiness / 100, string.format("%d%%", math.floor(monster.Happiness)))

	-- المرحلة الجاية
	local nextStage = nil
	for _, stage in Config.Stages do
		if stage.MinLevel > monster.Level then
			nextStage = stage
			break
		end
	end
	local nextText = if nextStage
		then string.format("\nEvolves into %s at Lv %d", nextStage.Name, nextStage.MinLevel)
		else "\nFully evolved! 👑"
	local warning = ""
	if monster.Hunger < Config.LowNeedsThreshold or monster.Happiness < Config.LowNeedsThreshold then
		warning = " (sad monsters make less!)"
	end
	ui.ProductionLabel.Text = "💰 +" .. MonsterMath.FormatNumber(monster.Production) .. "/s" .. warning .. nextText

	ui.FeedButton.Text = "🍖 Feed (" .. MonsterMath.FormatNumber(monster.FoodCost) .. ")"
	ui.FeedButton.BackgroundColor3 = if state.Coins >= monster.FoodCost then UI.Colors.Orange else UI.Colors.Gray

	if monster.PlayReadyIn > 0 then
		ui.PlayButton.Text = string.format("🎾 Play (%ds)", math.ceil(monster.PlayReadyIn))
		ui.PlayButton.BackgroundColor3 = UI.Colors.Gray
	else
		ui.PlayButton.Text = "🎾 Play"
		ui.PlayButton.BackgroundColor3 = UI.Colors.Pink
	end

	if os.clock() < sellConfirmUntil then
		ui.SellButton.Text = "Tap again to confirm sell"
	else
		ui.SellButton.Text = "Sell for 💰 " .. MonsterMath.FormatNumber(monster.SellValue)
	end
end

local function refresh()
	if not state then
		return
	end
	ui.CoinsLabel.Text = "💰 " .. MonsterMath.FormatNumber(state.Coins)
	local production = 0
	for _, monster in state.Monsters do
		if not monster.Carried then
			production += monster.Production
		end
	end
	ui.PendingLabel.Text = string.format(
		"+%s/s · %s waiting at your base",
		MonsterMath.FormatNumber(production),
		MonsterMath.FormatNumber(state.PendingCoins)
	)

	for eggType, eggButton in ui.EggButtons do
		local egg = Config.Eggs[eggType]
		eggButton.BackgroundColor3 = if state.Coins >= egg.Cost then UI.Colors.Green else UI.Colors.Gray
	end

	local used = #state.Monsters + #state.Eggs
	ui.SlotsInfo.Text = string.format("🏠 Base slots: %d / %d  (used: %d)", state.UnlockedSlots, state.MaxSlots, used)
	if state.NextSlotCost then
		ui.SlotsButton.Text = "Unlock slot · 💰 " .. MonsterMath.FormatNumber(state.NextSlotCost)
		ui.SlotsButton.BackgroundColor3 = if state.Coins >= state.NextSlotCost then UI.Colors.Green else UI.Colors.Gray
	else
		ui.SlotsButton.Text = "MAX"
		ui.SlotsButton.BackgroundColor3 = UI.Colors.Gray
	end

	ui.LockInfo.Text = string.format("🔒 Base lock lasts %ds", state.LockDuration)
	if state.NextLockCost then
		ui.LockButton.Text = "+" .. Config.LockDurationPerUpgrade .. "s lock · 💰 " .. MonsterMath.FormatNumber(state.NextLockCost)
		ui.LockButton.BackgroundColor3 = if state.Coins >= state.NextLockCost then UI.Colors.Green else UI.Colors.Gray
	else
		ui.LockButton.Text = "MAX"
		ui.LockButton.BackgroundColor3 = UI.Colors.Gray
	end

	refreshMonsterPanel()
end

-- الأحداث -------------------------------------------------------------------------------

remotes.StateUpdate.OnClientEvent:Connect(function(newState)
	state = newState
	refresh()
end)

remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
	UI.Toast(ui, text, kind)
end)

remotes.OpenShop.OnClientEvent:Connect(function()
	UI.Open(ui, ui.ShopFrame)
end)

remotes.OpenMonster.OnClientEvent:Connect(function(monsterId: string)
	openMonsterId = monsterId
	sellConfirmUntil = 0
	UI.Open(ui, ui.MonsterFrame)
	refresh()
end)

ui.ShopButton.Activated:Connect(function()
	UI.Toggle(ui, ui.ShopFrame)
end)
ui.UpgradesButton.Activated:Connect(function()
	UI.Toggle(ui, ui.UpgradesFrame)
end)

for eggType, eggButton in ui.EggButtons do
	eggButton.Activated:Connect(function()
		remotes.BuyEgg:FireServer(eggType)
	end)
end

ui.SlotsButton.Activated:Connect(function()
	remotes.BuyUpgrade:FireServer("Slots")
end)
ui.LockButton.Activated:Connect(function()
	remotes.BuyUpgrade:FireServer("Lock")
end)

ui.FeedButton.Activated:Connect(function()
	if openMonsterId then
		remotes.FeedMonster:FireServer(openMonsterId)
	end
end)
ui.PlayButton.Activated:Connect(function()
	if openMonsterId then
		remotes.PlayMonster:FireServer(openMonsterId)
	end
end)
ui.SellButton.Activated:Connect(function()
	if not openMonsterId then
		return
	end
	if os.clock() < sellConfirmUntil then
		sellConfirmUntil = 0
		remotes.SellMonster:FireServer(openMonsterId)
		ui.MonsterFrame.Visible = false
	else
		sellConfirmUntil = os.clock() + 3
		refresh()
	end
end)

-- أزرار الـ Prompt: "Care" لوحوشك بس، "Steal" لوحوش غيرك بس، و"Lock" لقاعدتك بس.
local function setupPrompt(prompt: ProximityPrompt)
	if prompt.Name == "CarePrompt" or prompt.Name == "StealPrompt" then
		local model = prompt.Parent and prompt.Parent.Parent
		if not model then
			return
		end
		local isMine = model:GetAttribute("OwnerUserId") == player.UserId
		prompt.Enabled = if prompt.Name == "CarePrompt" then isMine else not isMine
	elseif prompt.Name == "LockPrompt" then
		local function update()
			prompt.Enabled = prompt:GetAttribute("OwnerUserId") == player.UserId
		end
		prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(update)
		update()
	end
end

local function watchMap(map: Instance)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			setupPrompt(descendant)
		end
	end
	map.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			-- نستنى لحظة عشان الـ attributes توصل
			task.defer(setupPrompt, descendant)
		end
	end)
end
watchMap(workspace:WaitForChild("Map"))

-- تأثير الـ Rainbow ---------------------------------------------------------------
local rainbowParts: { [BasePart]: boolean } = {}
local function addRainbow(instance: Instance)
	if instance:IsA("BasePart") then
		rainbowParts[instance] = true
	end
end
for _, instance in CollectionService:GetTagged("RainbowPart") do
	addRainbow(instance)
end
CollectionService:GetInstanceAddedSignal("RainbowPart"):Connect(addRainbow)
CollectionService:GetInstanceRemovedSignal("RainbowPart"):Connect(function(instance)
	rainbowParts[instance :: BasePart] = nil
end)
RunService.RenderStepped:Connect(function()
	local hue = (os.clock() * 0.25) % 1
	for part in rainbowParts do
		part.Color = Color3.fromHSV(hue, 0.8, 1)
	end
end)

-- العدّاد في لوحة الوحش (Play cooldown) بيتحدث مع كل StateUpdate، وكمان كل نص ثانية.
task.spawn(function()
	while true do
		task.wait(0.5)
		refreshMonsterPanel()
	end
end)

UI.Toast(ui, "Welcome to Raise a Monster! Hatch your egg, care for your monster and steal others' 👀", "info")
