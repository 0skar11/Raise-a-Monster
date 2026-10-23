--!strict
-- Static previews replicate only through their owner's PlayerGui. The gameplay
-- builder remains the single source for species, stage, mutations and accessories.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local PlotService = require(script.Parent.PlotService)

local Portraits = {}
type Bank = {
	Folder: Folder,
	Desired: { [string]: any },
	Running: boolean,
	Alive: boolean,
}
local banks: { [Player]: Bank } = {}

local function key(monster: any): string
	return table.concat({ monster.Species, MonsterMath.GetStage(monster.Level).Name,
		monster.Mutation or "", monster.Hat or "", monster.Glasses or "" }, "|")
end

local function strip(model: Model)
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("LayerCollector") or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector") or item:IsA("ParticleEmitter") or item:IsA("Trail")
			or item:IsA("Beam") or item:IsA("Sound") or item:IsA("Light") or item:IsA("Highlight")
			or item:IsA("Fire") or item:IsA("Smoke") or item:IsA("Sparkles")
			or item:IsA("Humanoid") or item:IsA("AnimationController") or item:IsA("Animation")
			or item:IsA("Constraint") then
			item:Destroy()
		else
			for _, tag in CollectionService:GetTags(item) do CollectionService:RemoveTag(item, tag) end
			if item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery = true, false, false, false
			end
		end
	end
	for _, tag in CollectionService:GetTags(model) do CollectionService:RemoveTag(model, tag) end
	model:SetAttribute("Procedural", false)
	model:SetAttribute("AnimState", nil)
	model:PivotTo(CFrame.new())
end

-- Accept the authoritative monster dictionary. Never accepts client-submitted data.
-- No cloning occurs for unchanged appearance keys; at most two builds per frame.
function Portraits.Sync(player: Player, monsters: { [string]: any })
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local bank = banks[player]
	if not bank or bank.Folder.Parent ~= playerGui then
		if bank then bank.Alive = false; bank.Folder:Destroy() end
		local folder = Instance.new("Folder")
		folder.Name = "MonsterPortraitModels"
		folder:SetAttribute("OwnerUserId", player.UserId)
		folder.Parent = playerGui
		bank = { Folder = folder, Desired = {}, Running = false, Alive = true }
		banks[player] = bank
	end
	local desired: { [string]: any } = {}
	for _, monster in monsters do desired[key(monster)] = table.clone(monster) end
	bank.Desired = desired
	for _, model in bank.Folder:GetChildren() do if not desired[model.Name] then model:Destroy() end end
	if bank.Running then return end
	bank.Running = true
	local currentBank = bank
	task.defer(function()
		local builtThisFrame = 0
		while currentBank.Alive and currentBank.Folder.Parent == playerGui do
			local nextKey: string?, nextMonster: any = nil, nil
			for appearance, monster in currentBank.Desired do
				if not currentBank.Folder:FindFirstChild(appearance) then nextKey, nextMonster = appearance, monster; break end
			end
			if not nextKey then break end
			local model: Model? = nil
			local ok, err = pcall(function()
				model = PlotService.BuildMonsterModel(nextMonster)
				strip(model :: Model)
				model.Name = nextKey :: string
				model:SetAttribute("Species", nextMonster.Species)
				model:SetAttribute("Stage", MonsterMath.GetStage(nextMonster.Level).Name)
				if currentBank.Alive and currentBank.Desired[nextKey :: string] and currentBank.Folder.Parent == playerGui then
					model.Parent = currentBank.Folder
				else model:Destroy() end
			end)
			if not ok then
				if model then model:Destroy() end
				-- A broken source is omitted for this sync rather than spinning forever.
				currentBank.Desired[nextKey :: string] = nil
				warn("Monster portrait unavailable:", nextMonster.Species, err)
			end
			builtThisFrame += 1
			if builtThisFrame >= 2 then builtThisFrame = 0; task.wait() end
		end
		currentBank.Running = false
	end)
end

function Portraits.Remove(player: Player)
	local bank = banks[player]
	if not bank then return end
	bank.Alive = false
	bank.Folder:Destroy()
	banks[player] = nil
end

Players.PlayerRemoving:Connect(Portraits.Remove)
return Portraits
