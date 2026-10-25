--!strict
-- محطة الصندوق المجاني بين لوحتين الـ Leaderboards: اللاعب يشاهد إعلان فيديو بمكافأة (Roblox Rewarded Video)
-- ويستلم Config.Products.AdChest. الجايزة بتتدّي من MarketplaceService.ProcessReceipt بس (شرط Roblox)،
-- مش من نتيجة ShowRewardedVideoAdAsync. السيرفر بيتحقق من المسافة والـ cooldown، والكلاينت بيتأكد إن فيه إعلان.

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local MonetizationService = require(script.Parent.MonetizationService)

local AdChestService = {}

local busy: { [Player]: boolean } = {}

-- بالثواني: كام باقي لحد ما اللاعب يقدر يفتح الصندوق تاني
function AdChestService.ReadyIn(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return math.max(0, (profile.Data.LastAdChest or 0) + Config.AdChest.Cooldown - os.time())
end

-- المبلغ اللي اللوحة بتعرضه للاعب (الأكبر بين الحد الأدنى ودقايق دخله)، نفس حسبة MonetizationService
function AdChestService.RewardAmount(player: Player): number
	local product = Config.Products.AdChest
	local amount = product.Coins or 0
	if product.Minutes then
		amount = math.max(amount, math.floor(MonsterService.GetIncomePerSecond(player) * product.Minutes * 60))
	end
	return amount
end

local function nearStation(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - Config.AdChest.Position).Magnitude <= Config.AdChest.Reach
end

local function request(player: Player)
	local profile = DataService.Get(player)
	if not profile or profile.LoadFailed or busy[player] then
		return
	end
	if not nearStation(player) then
		return
	end
	if AdChestService.ReadyIn(player) > 0 then
		MonsterService.Notify(player, "The free chest is recharging. Come back soon!", "info")
		return
	end
	local product = Config.Products.AdChest
	if product.Id == 0 then
		-- مفيش منتج مربوط لسه: في Studio بنجرّب بالهدية من غير إعلان، وعلى السيرفر الحقيقي بنقول قريباً
		if RunService:IsStudio() then
			if MonetizationService.GrantProduct(player, "AdChest") then
				MonsterService.Notify(player, "🧪 Studio test: free chest without an ad.", "success")
			end
			MonsterService.PushState(player)
		else
			MonsterService.Notify(player, "The free chest is coming soon!", "info")
		end
		return
	end
	busy[player] = true
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(product.Id)
		return AdService:ShowRewardedVideoAdAsync(player, reward, Config.AdChest.PlacementId)
	end)
	busy[player] = nil
	if not ok then
		warn("[AdChestService] Rewarded ad failed:", result)
		MonsterService.Notify(player, "No ad is available right now. Try again in a bit.", "info")
	elseif result == Enum.ShowAdResult.AdNotReady then
		MonsterService.Notify(player, "No ad is available right now. Try again in a bit.", "info")
	end
	-- الجايزة بتوصل من ProcessReceipt لما اللاعب يخلّص الإعلان كله
end

-- البناء ---------------------------------------------------------------------------------------------

local function buildStation(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "AdChestStation"
	folder.Parent = workspace
	-- نفس اتجاه لوحات الـ Leaderboards: الواجهة ناحية -X
	local base = CFrame.lookAt(Config.AdChest.Position, Config.AdChest.Position + Vector3.new(-1, 0, 0))
	-- الصندوق والدايرة 7 studs قدام اللوحة (ناحية اللاعبين، -Z المحلي = -X في العالم)
	local spot = base * CFrame.new(0, 0, -7)

	-- قاعدة حجرية بإطار رفيع بدل الدايرة الكبيرة شديدة الإضاءة.
	Build.MakePart({
		Name = "ChestRim", Size = Vector3.new(8.8, 0.12, 7.2),
		CFrame = spot * CFrame.new(0, 0.35, 0),
		Color = Color3.fromRGB(80, 220, 120), Material = Enum.Material.Neon,
		CanCollide = false, Parent = folder,
	})
	Build.MakePart({
		Name = "ChestPlinth", Size = Vector3.new(8.5, 0.6, 6.9),
		CFrame = spot * CFrame.new(0, 0.65, 0),
		Color = Color3.fromRGB(32, 48, 38), Material = Enum.Material.Slate,
		Parent = folder,
	})

	-- Keep the existing BasePart interaction contract for the AdChest client module.
	local chest = Build.MakePart({
		Name = "Chest", Size = Vector3.new(4.2, 2.6, 3.2), CFrame = spot * CFrame.new(0, 2.25, 0),
		Color = Color3.fromRGB(104, 63, 35), Material = Enum.Material.Wood,
		CanCollide = false, Parent = folder,
	})
	local labelHeight = 3.6
	-- Creator Store: Treasure Chest by StarModelX, asset 1880922775.
	-- The checked, script-free template is stored locally; no runtime asset loading.
	local template = ServerStorage:FindFirstChild("AdChest")
	if template and template:IsA("Model") then
		local visual = template:Clone()
		visual.Name = "ChestVisual"
		local _, originalSize = visual:GetBoundingBox()
		local span = math.max(originalSize.X, originalSize.Z)
		if span > 0 then
			visual:ScaleTo(visual:GetScale() * 6 / span)
		end
		visual:PivotTo(spot)
		local bounds, size = visual:GetBoundingBox()
		local bottom = bounds.Position.Y - size.Y / 2
		visual:PivotTo(visual:GetPivot() + Vector3.new(0, spot.Position.Y + 0.95 - bottom, 0))
		for _, item in visual:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanTouch = true, false, false
			elseif item:IsA("LuaSourceContainer") then
				item:Destroy()
			end
		end
		chest.CFrame = spot * CFrame.new(0, 0.95 + size.Y / 2, 0)
		chest.Transparency = 1
		labelHeight = size.Y / 2 + 1.1
		visual.Parent = folder
	else
		warn("[AdChestService] Missing ServerStorage.AdChest template; showing fallback chest.")
	end

	-- "FREE!" فوق الصندوق
	local free = Instance.new("BillboardGui")
	free.Name, free.Size, free.StudsOffset, free.MaxDistance, free.Adornee = "FreeLabel", UDim2.fromOffset(180, 64), Vector3.new(0, labelHeight, 0), 120, chest
	free.Parent = chest
	local freeText = Instance.new("TextLabel")
	freeText.Size, freeText.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	freeText.Font, freeText.TextScaled, freeText.Text = Enum.Font.FredokaOne, true, "FREE!"
	freeText.TextColor3, freeText.TextStrokeTransparency, freeText.TextStrokeColor3 = Color3.fromRGB(78, 255, 90), 0, Color3.fromRGB(18, 60, 24)
	freeText.Parent = free

	-- اللوحة: عمودين ولوحة خضرا عليها "Watch Ad to Collect" (المبلغ بيتحدّث عند كل لاعب من الكلاينت)
	for _, side in { -1, 1 } do
		Build.MakePart({
			Name = "Post", Size = Vector3.new(0.8, 14, 0.8), CFrame = base * CFrame.new(side * 7.4, 7, 0.4),
			Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood, Parent = folder,
		})
	end
	local board = Build.MakePart({
		Name = "AdBoard", Size = Vector3.new(15, 7.5, 0.6), CFrame = base * CFrame.new(0, 10.5, 0),
		Color = Color3.fromRGB(22, 70, 40), Material = Enum.Material.SmoothPlastic, Parent = folder,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.CanvasSize, gui.LightInfluence = "Gui", Enum.NormalId.Front, Vector2.new(600, 300), 0
	gui.Parent = board
	local function label(name: string, text: string, position: UDim2, size: UDim2, color: Color3, alignment: Enum.TextXAlignment): TextLabel
		local item = Instance.new("TextLabel")
		item.Name, item.Text, item.Position, item.Size = name, text, position, size
		item.BackgroundTransparency, item.Font, item.TextScaled = 1, Enum.Font.FredokaOne, true
		item.TextColor3, item.TextXAlignment = color, alignment
		item.TextStrokeTransparency, item.TextStrokeColor3 = 0.2, Color3.fromRGB(10, 40, 18)
		item.Parent = gui
		return item
	end
	local banner = Instance.new("Frame")
	banner.Name, banner.Position, banner.Size = "Banner", UDim2.fromOffset(150, 10), UDim2.fromOffset(300, 46)
	banner.BackgroundColor3, banner.BorderSizePixel = Color3.fromRGB(60, 150, 70), 0
	banner.Parent = gui
	label("ClickToClaim", "CLICK TO CLAIM", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(190, 255, 120), Enum.TextXAlignment.Center).Parent = banner
	label("Caption", "Watch Ad to Collect:", UDim2.fromOffset(24, 76), UDim2.fromOffset(360, 44), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
	label("Amount", "💰 ...", UDim2.fromOffset(24, 128), UDim2.fromOffset(380, 110), Color3.fromRGB(78, 255, 90), Enum.TextXAlignment.Left)
	label("Timer", "", UDim2.fromOffset(24, 244), UDim2.fromOffset(380, 40), Color3.fromRGB(255, 226, 120), Enum.TextXAlignment.Left)
	label("Cash", "💵", UDim2.fromOffset(420, 90), UDim2.fromOffset(160, 150), Color3.new(1, 1, 1), Enum.TextXAlignment.Center)

	-- الزرار اللي اللاعب بيدوس عليه (Roblox بتشترط إن اللاعب هو اللي يبدأ الإعلان)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "AdPrompt", "Watch Ad", "Free Chest (video ad)"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 12, false
	prompt.KeyboardKeyCode, prompt.Parent = Enum.KeyCode.E, chest
	return folder
end

function AdChestService.CleanupPlayer(player: Player)
	busy[player] = nil
end

function AdChestService.Init(remotes: { [string]: RemoteEvent })
	buildStation()
	remotes.RequestAdChest.OnServerEvent:Connect(request)
	Players.PlayerRemoving:Connect(AdChestService.CleanupPlayer)
end

return AdChestService
