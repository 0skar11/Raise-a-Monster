--!strict
-- محطة الصندوق المجاني (جانب اللاعب): بتعرض مبلغه هو على اللوحة، وبتتأكد إن فيه إعلان قبل ما تطلبه من السيرفر.
-- الجايزة والـ cooldown والمسافة كلها بيتحقق منها السيرفر.

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local UI = require(script.Parent.UI)

local AdChest = {}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Roblox بتشترط نسأل عن توفّر إعلان قبل ما نعرضه (وقت الضغط بالظبط)
local function adAvailable(): boolean
	if Config.Products.AdChest.Id == 0 then
		return RunService:IsStudio() -- وضع الاختبار من غير إعلان حقيقي
	end
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	return ok and result ~= nil and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

function AdChest.Init(ui: UI.UI, remotes: { [string]: RemoteEvent }, getState: () -> any)
	local station = workspace:WaitForChild("AdChestStation", 60)
	if not station then
		return
	end
	local chest = station:WaitForChild("Chest")
	local prompt = chest:WaitForChild("AdPrompt") :: ProximityPrompt
	local gui = station:WaitForChild("AdBoard"):WaitForChild("Gui")
	local amount = gui:WaitForChild("Amount") :: TextLabel
	local timer = gui:WaitForChild("Timer") :: TextLabel

	local checking = false
	prompt.Triggered:Connect(function()
		if checking then
			return
		end
		local state = getState()
		if state and (state.AdChestReadyIn or 0) > 0 then
			UI.Toast(ui, "The free chest recharges in " .. clock(state.AdChestReadyIn) .. ".", "info")
			return
		end
		checking = true
		local available = adAvailable()
		checking = false
		if available then
			remotes.RequestAdChest:FireServer()
		else
			UI.Toast(ui, "No ad is available right now. Try again in a bit.", "info")
		end
	end)

	-- اللوحة بتتحدّث عند كل لاعب بمبلغه (محلي بس، مش بيتغيّر عند غيره)
	task.spawn(function()
		while station.Parent do
			local state = getState()
			if state then
				amount.Text = "💰 " .. MonsterMath.FormatNumber(state.AdRewardCoins or 0)
				local waitTime = state.AdChestReadyIn or 0
				timer.Text = if waitTime > 0 then "Ready in " .. clock(waitTime) else ""
				prompt.Enabled = waitTime <= 0
			end
			task.wait(0.5)
		end
	end)
end

return AdChest
