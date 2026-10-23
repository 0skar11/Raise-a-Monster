--!strict
-- الكلاينت: الواجهة، إظهار/إخفاء أزرار الـ ProximityPrompt، وتأثير الـ Rainbow.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

-- Roblox's Tab player list already provides player names and the Coins leaderstat.
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.UI)
local Features = require(script.Features)
local MonsterAnimate = require(script.MonsterAnimate)
local GearAnimate = require(script.GearAnimate)
local CombatFx = require(script.CombatFx)
local Settings = require(script.Settings)
local MonsterInventory = require(script.MonsterInventory)
local Effects = require(script.Effects)
local CashCounterFormatter = require(script.CashCounterFormatter)
local HalloweenUI = require(script.HalloweenUI)
local CandyCounter = require(script.CandyCounter)

local player = Players.LocalPlayer
local remotes = Remotes.Get()
local ui = UI.Create(player:WaitForChild("PlayerGui") :: PlayerGui)
CashCounterFormatter.Start(player:WaitForChild("PlayerGui"))

local state: any = nil
local openMonsterId: string? = nil
local sellConfirmUntil = 0
local inventory: any = nil

Features.Init(ui, remotes, function()
	return state
end, function()
	return openMonsterId
end)

Settings.Init(ui)
task.spawn(CandyCounter.Init, player:WaitForChild("PlayerGui"), remotes) -- own thread so a missing GUI can't stall startup
HalloweenUI.Init(ui, remotes)

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
		ui.PlayButton.Text = string.format("🎮 Play (%ds)", math.ceil(monster.PlayReadyIn))
		ui.PlayButton.BackgroundColor3 = UI.Colors.Gray
	else
		ui.PlayButton.Text = "🎮 Mini-game"
		ui.PlayButton.BackgroundColor3 = UI.Colors.Pink
	end

	local count = #(state.FollowingIds or {})
	local limit = state.FollowerLimit or Config.Followers.MaxCount
	local minimumLevel = state.FollowerMinLevel or Config.Followers.MinLevel
	local canFollow = monster.CanFollow == true and count < limit
	ui.FollowButton.Active = canFollow or monster.Following == true
	ui.FollowButton.Selectable = ui.FollowButton.Active
	ui.FollowButton.BackgroundColor3 = if monster.Following then UI.Colors.Green elseif canFollow then UI.Colors.Blue else UI.Colors.Gray
	ui.FollowButton.Text = if monster.Following then string.format("Stop following · %d/%d", count, limit)
		elseif canFollow then string.format("Follow · %d/%d · +damage", count, limit)
		elseif monster.Level < minimumLevel then string.format("Adult Lv %d+ required · %d/%d", minimumLevel, count, limit)
		elseif monster.Available == false then "Unavailable while carried or in use"
		elseif count >= limit then string.format("%d/%d following · stop one first", count, limit)
		else "This monster is unavailable to follow"

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
	Effects.OnCoins(ui, state.Coins)
	local production = 0
	for _, monster in state.Monsters do
		if monster.Placed == true and not monster.Carried then
			production += monster.Production
		end
	end
	ui.PendingLabel.Text = string.format("+%s/s", MonsterMath.FormatNumber(production))

	for eggType, eggButton in ui.EggButtons do
		local egg = Config.Eggs[eggType]
		eggButton.BackgroundColor3 = if state.Coins >= egg.Cost then UI.Colors.Green else UI.Colors.Gray
	end

	refreshMonsterPanel()
	Features.Refresh()
	if inventory then inventory.Refresh() end
end

inventory = MonsterInventory.Init(ui, remotes, function() return state end, function(id)
	openMonsterId = id
	sellConfirmUntil = 0
	UI.Open(ui, ui.MonsterFrame)
	refreshMonsterPanel()
end)
-- The authored golden-paw launcher (or the built-in button as a fallback) opens the inventory.
Features.SetInventoryOpener(function() inventory.Open() end)

-- الأحداث -------------------------------------------------------------------------------

remotes.StateUpdate.OnClientEvent:Connect(function(newState)
	state = newState
	refresh()
end)

remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
	UI.Toast(ui, text, kind)
	Effects.OnNotify(kind)
end)

remotes.OpenShop.OnClientEvent:Connect(function()
	UI.Open(ui, ui.GearFrame)
end)

remotes.OpenMonster.OnClientEvent:Connect(function(monsterId: string)
	openMonsterId = monsterId
	sellConfirmUntil = 0
	UI.Open(ui, ui.MonsterFrame)
	refresh()
end)

for eggType, eggButton in ui.EggButtons do
	eggButton.Activated:Connect(function()
		remotes.BuyEgg:FireServer(eggType)
	end)
end

ui.FollowButton.Activated:Connect(function()
	local monster = findMonster(openMonsterId)
	local hasCapacity = state and #(state.FollowingIds or {}) < (state.FollowerLimit or Config.Followers.MaxCount)
	if monster and (monster.Following or monster.CanFollow and hasCapacity) then remotes.ToggleFollower:FireServer(monster.Id) end
end)

ui.FeedButton.Activated:Connect(function()
	if openMonsterId then
		remotes.FeedMonster:FireServer(openMonsterId)
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
-- الوحوش الـ Rig: الطفرة Rainbow عبارة عن Highlight بيتلوّن
local rainbowHighlights: { [Highlight]: boolean } = {}
for _, instance in CollectionService:GetTagged("RainbowHighlight") do
	rainbowHighlights[instance :: Highlight] = true
end
CollectionService:GetInstanceAddedSignal("RainbowHighlight"):Connect(function(instance)
	rainbowHighlights[instance :: Highlight] = true
end)
CollectionService:GetInstanceRemovedSignal("RainbowHighlight"):Connect(function(instance)
	rainbowHighlights[instance :: Highlight] = nil
end)
RunService.RenderStepped:Connect(function()
	local hue = (os.clock() * 0.25) % 1
	local color = Color3.fromHSV(hue, 0.8, 1)
	for part in rainbowParts do
		part.Color = color
	end
	for highlight in rainbowHighlights do
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end)

-- أنيميشن الوحوش (Idle / Walk / Attack) من MonsterAnimator
MonsterAnimate.Start()
GearAnimate.Start()

-- ضربات الوحوش، أرقام الضرر، والموسيقى
CombatFx.Start(ui, remotes, UI.Button)
Effects.Start(ui)

-- العدّاد في لوحة الوحش (Play cooldown) بيتحدث مع كل StateUpdate، وكمان كل نص ثانية.
task.spawn(function()
	while true do
		task.wait(0.5)
		refreshMonsterPanel()
	end
end)

UI.Toast(ui, "Welcome to Raise a Monster! Hatch your egg, hunt monsters with your bat and carry them home 🏃", "info")
