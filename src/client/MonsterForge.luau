--!strict
-- The forge is presentation only. Purchases and ownership remain server-authoritative.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.UI)
local CartoonUI = require(script.Parent.CartoonUI)
local HudKit = require(script.Parent.HudKit)
local Players = game:GetService("Players")

local MonsterForge = {}
MonsterForge.Assets = {} -- Shared authored artwork lives in CartoonUI.
local C = {
	Ink = Color3.fromRGB(16, 43, 94), Stone = Color3.fromRGB(255, 248, 223), Raised = Color3.fromRGB(255, 255, 249),
	Edge = Color3.fromRGB(137, 200, 232), Bronze = Color3.fromRGB(29, 168, 229), Gold = Color3.fromRGB(255, 209, 57),
	Ivory = Color3.fromRGB(19, 44, 98), Text = Color3.fromRGB(19, 44, 98), Muted = Color3.fromRGB(55, 84, 115),
	Cyan = Color3.fromRGB(0, 201, 214), Blue = Color3.fromRGB(219, 244, 255), Red = Color3.fromRGB(232, 57, 91),
	Green = Color3.fromRGB(157, 235, 44), Disabled = Color3.fromRGB(211, 226, 227),
}
local NAV = { "Weapons", "Accessories", "Gamepasses", "Coins & Growth", "Owned", "Codes", "Gift" }
local EXTRA_TABS: { [string]: boolean } = { Codes = true, Gift = true } -- their own panels instead of the catalog grid

local function frame(parent: Instance, name: string, color: Color3): Frame
	local item = Instance.new("Frame")
	item.Name, item.BackgroundColor3, item.BorderSizePixel = name, color, 0
	item.ZIndex = 31
	item.Parent = parent
	return item
end
local function border(parent: Instance, color: Color3, thickness: number?): UIStroke
	local item = Instance.new("UIStroke")
	item.Color, item.Thickness = color, thickness or 1
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Parent = parent
	return item
end
local function round(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius, item.Parent = UDim.new(0, radius), parent
end
local function shade(parent: Instance, top: Color3, bottom: Color3)
	local item = Instance.new("UIGradient")
	item.Color, item.Rotation = ColorSequence.new(top, bottom), 90
	item.Parent = parent
end
local function text(parent: Instance, name: string, value: string, size: number, color: Color3?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name, item.Text, item.TextSize = name, value, size
	item.BackgroundTransparency, item.BorderSizePixel = 1, 0
	item.TextColor3 = color or C.Text
	item.TextWrapped, item.RichText = true, false
	item.Font = Enum.Font.GothamBold
	item.TextStrokeColor3, item.TextStrokeTransparency = C.Ink, 1
	item.ZIndex = 34
	item.Parent = parent
	return item
end
local function button(parent: Instance, name: string, value: string): TextButton
	local item = Instance.new("TextButton")
	item.Name, item.Text, item.TextSize = name, value, 18
	item.BackgroundColor3, item.TextColor3 = Color3.new(1, 1, 1), C.Ink
	item.Font, item.TextWrapped = Enum.Font.FredokaOne, true
	item.BorderSizePixel, item.AutoButtonColor, item.ZIndex = 0, true, 35
	item.Parent = parent
	round(item, 12)
	border(item, Color3.fromRGB(78, 172, 21), 2)
	shade(item, Color3.fromRGB(192, 255, 69), Color3.fromRGB(112, 219, 35))
	return item
end
local function actionState(item: TextButton, enabled: boolean)
	-- A disabled button must stop using its active gradient as well as its input.
	local gradient = item:FindFirstChildOfClass("UIGradient")
	if gradient then gradient.Enabled = enabled end
	item.BackgroundColor3 = if enabled then Color3.new(1, 1, 1) else C.Disabled
	item.TextColor3 = if enabled then C.Ink else C.Muted
	local outline = item:FindFirstChildOfClass("UIStroke")
	if outline then outline.Color = if enabled then Color3.fromRGB(78, 172, 21) else Color3.fromRGB(153, 177, 186) end
end
local function comma(value: number): string
	local result = tostring(math.floor(value))
	while true do
		local replaced, count = result:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
		result = replaced
		if count == 0 then return result end
	end
end

local function glyph(parent: Instance, kind: string): GuiObject
	if kind == "Codes" then
		return HudKit.TicketIcon(parent, 40)
	end
	local key = if kind == "Forge" then "Weapons" elseif kind == "Coins & Growth" then "CoinsGrowth" else kind
	local icon = CartoonUI.Icon(parent, key, 40)
	icon.Name, icon.ZIndex = "Icon", 34
	return icon
end

local function owned(offer: any, state: any): boolean
	if offer.Kind == "Weapon" then return offer.Key == "Bat" or (state.Weapons or {})[offer.Key] == true or (state.Passes or {})[offer.Key] == true end
	if offer.Kind == "Accessory" then return (state.SpeedAccessories or {})[offer.Key] == true end
	return offer.Kind == "Pass" and (state.Passes or {})[offer.Key] == true
end
local function equipped(offer: any, state: any): boolean
	return (offer.Kind == "Weapon" and (state.EquippedWeapon or "Bat") == offer.Key)
		or (offer.Kind == "Accessory" and state.EquippedSpeedAccessory == offer.Key)
end

function MonsterForge.Mount(root: Frame, scroll: ScrollingFrame, options: any): any
	-- Strip only the previous shop's presentation. Preserve its modal, scale and scroll references.
	for _, child in root:GetChildren() do
		if child ~= scroll and child.Name ~= "NativeShopScale" then child:Destroy() end
	end
	root.ZIndex = 30
	root.ClipsDescendants = false
	HudKit.Body(root)
	-- Dark slate well behind the catalog, nav and panels.
	local catalogCanvas = frame(root, "CatalogCanvas", Color3.fromRGB(38, 40, 54))
	catalogCanvas.ZIndex = 31
	round(catalogCanvas, 4)
	border(catalogCanvas, HudKit.Colors.Ink, 3)
	local header, title = HudKit.Header(root, "ForgeHeader", "Yellow", "Shop")
	header.ZIndex = 33
	local forgeIcon = text(header, "CartIcon", "🛒", 44, C.Ink)
	forgeIcon.Name, forgeIcon.TextWrapped, forgeIcon.TextStrokeTransparency = "Icon", false, 1
	forgeIcon.ZIndex = 37
	-- The old subtitle slot now holds the shop's current section name, in the kit's "- SECTION -" style.
	local subtitle = HudKit.Text(root, "SectionTitle", "", 20)
	subtitle.ZIndex = 33
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	local passHeading = text(header, "PassHeading", "", 21, C.Ivory)
	local close = HudKit.Button(root, "CloseButton", "X", "Red")
	close.ZIndex = 40
	close.Size, close.Position = UDim2.fromOffset(44, 44), UDim2.new(1, -58, 0, 12)
	close.Activated:Connect(function() root.Visible = false end)
	local nav = Instance.new("ScrollingFrame")
	nav.Name, nav.BackgroundColor3, nav.BorderSizePixel, nav.ZIndex = "Categories", C.Stone, 0, 33
	nav.BackgroundTransparency, nav.ScrollBarThickness, nav.ScrollBarImageColor3 = 1, 3, C.Bronze
	nav.ScrollingDirection, nav.CanvasSize, nav.Parent = Enum.ScrollingDirection.Y, UDim2.new(), root
	local tabs: { [string]: TextButton } = {}
	for _, category in NAV do
		local tab = button(nav, category .. "Tab", "")
		tab.BackgroundColor3 = C.Blue
		local gradient = tab:FindFirstChildOfClass("UIGradient")
		if gradient then gradient:Destroy() end
		local stroke = tab:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = HudKit.Colors.Ink end
		glyph(tab, category)
		local caption = text(tab, "Caption", category, 14, C.Text)
		caption.Font = Enum.Font.FredokaOne
		caption.TextXAlignment = Enum.TextXAlignment.Left
		tabs[category] = tab
	end
	for _, child in scroll:GetChildren() do child:Destroy() end
	scroll.Name, scroll.BackgroundTransparency, scroll.BorderSizePixel = "Content", 1, 0
	scroll.AutomaticCanvasSize, scroll.ScrollingDirection = Enum.AutomaticSize.None, Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness, scroll.ScrollBarImageColor3, scroll.ZIndex = 4, C.Bronze, 33
	local empty = text(scroll, "Empty", "Your owned weapons and accessories appear here.", 18, C.Muted)
	empty.Visible = false
	-- Codes and Gift get their own panels beside the nav; the catalog scroll and detail pane hide while one is open.
	local codesPanel = frame(root, "CodesPanel", Color3.new(1, 1, 1))
	codesPanel.BackgroundTransparency, codesPanel.ZIndex, codesPanel.Visible = 1, 33, false
	local codesMessage = HudKit.Text(codesPanel, "Message", "Enter a code to claim a reward!", 22)
	local codeField, codeBox = HudKit.Field(codesPanel, "CodeBoxFrame", "ENTER CODE")
	local redeemButton = HudKit.Button(codesPanel, "RedeemButton", "Redeem", "Green")
	local codesStatus = HudKit.Text(codesPanel, "Status", "", 18)
	local giftPanel = frame(root, "GiftPanel", Color3.new(1, 1, 1))
	giftPanel.BackgroundTransparency, giftPanel.ZIndex, giftPanel.Visible = 1, 33, false
	local giftMessage = HudKit.Text(giftPanel, "Message", "Choose a player to gift", 22)
	local giftList = Instance.new("ScrollingFrame")
	giftList.Name, giftList.BackgroundTransparency, giftList.BorderSizePixel, giftList.ZIndex = "PlayerList", 1, 0, 34
	giftList.ScrollBarThickness, giftList.ScrollBarImageColor3 = 4, HudKit.Colors.Gold
	giftList.ScrollingDirection, giftList.CanvasSize, giftList.Parent = Enum.ScrollingDirection.Y, UDim2.new(), giftPanel
	local giftEmpty = HudKit.Text(giftPanel, "Empty", "No other players here yet", 20)
	giftEmpty.TextColor3 = HudKit.Colors.Muted
	local giftField, giftBox = HudKit.Field(giftPanel, "UserBoxFrame", "PLAYER NAME")
	local giftButton = HudKit.Button(giftPanel, "ConfirmButton", "Gift", "Green")
	local giftIcon = CartoonUI.Icon(giftButton, "Gift", 40)
	giftIcon.Name, giftIcon.ZIndex = "GiftArt", giftButton.ZIndex + 3
	(giftButton:FindFirstChild("Label") :: TextLabel).Visible = false
	local giftStatus = HudKit.Text(giftPanel, "Status", "", 18)
	local detail = frame(root, "SelectedItem", Color3.new(1, 1, 1))
	detail.ZIndex = 33
	round(detail, 14)
	border(detail, C.Cyan, 2)
	shade(detail, Color3.fromRGB(238, 255, 255), Color3.fromRGB(198, 244, 255))
	local detailPreview = frame(detail, "Preview", Color3.new(1, 1, 1))
	round(detailPreview, 14)
	shade(detailPreview, Color3.fromRGB(122, 218, 255), Color3.fromRGB(227, 251, 255))
	border(detailPreview, Color3.fromRGB(247, 255, 255), 2)
	local detailEyebrow = text(detail, "SelectedLabel", "", 12, C.Muted)
	detailEyebrow.Visible = false
	local detailName = text(detail, "Title", "Ice Sword", 25, C.Ivory)
	detailName.Font = Enum.Font.FredokaOne
	local stats = frame(detail, "Stats", C.Ink)
	stats.BackgroundTransparency = 1
	local statA = text(stats, "Primary", "x40\nDAMAGE", 18, C.Text)
	local statB = text(stats, "Secondary", "+2.5\nREACH", 18, C.Text)
	for _, label in { statA, statB } do
		label.BackgroundTransparency, label.BackgroundColor3 = 0, Color3.fromRGB(238, 252, 255)
		round(label, 10)
		border(label, C.Edge, 1)
	end
	-- Keep artwork outside padded TextLabels: UIPadding also moves child GuiObjects.
	local statAIcon = CartoonUI.Icon(stats, "Speed", 28)
	local statBIcon = CartoonUI.Icon(stats, "Health", 28)
	statAIcon.Name, statBIcon.Name = "PrimaryIcon", "SecondaryIcon"
	for _, icon in { statAIcon, statBIcon } do
		icon.Position, icon.ZIndex = UDim2.new(0, 6, 0.5, -14), 35
	end
	local statAPadding = Instance.new("UIPadding")
	statAPadding.Parent = statA
	local statBPadding = Instance.new("UIPadding")
	statBPadding.Parent = statB
	local detailPrice = text(detail, "Price", "26,000 COINS", 21, C.Ivory)
	local detailAction = button(detail, "BuyButton", "BUY WEAPON")
	local detailNote = text(detail, "CollectionNote", "Owned items stay in your collection", 12, C.Muted)
	local offers: { any } = {}
	local selectedCategory, selectedKey = "Weapons", "IceSword"
	local previewKey = ""
	local statKind = "Accessory"
	local pending: { [string]: boolean } = {}
	local prices: { [string]: number } = {}
	local unavailable: { [string]: boolean } = {}
	local loading: { [string]: boolean } = {}
	local alive = true
	local refresh: () -> () = function() end
	local layout: () -> () = function() end
	local function add(offer: any)
		-- UIGradient multiplies this color; white preserves its intended palette.
		local card = frame(scroll, offer.Key .. "Card", Color3.new(1, 1, 1))
		round(card, 16)
		local outline = border(card, Color3.fromRGB(225, 216, 187), 2)
		if offer.Featured and offer.Key == "DoubleDamage" then
			shade(card, Color3.fromRGB(255, 242, 229), Color3.fromRGB(255, 219, 216))
		elseif offer.Featured and offer.Key == "VIP" then
			shade(card, Color3.fromRGB(255, 254, 226), Color3.fromRGB(255, 237, 177))
		else
			shade(card, C.Raised, C.Stone)
		end
		local preview = frame(card, "Preview", Color3.new(1, 1, 1))
		round(preview, 12)
		local previewColors = {
			SwiftSneakers = Color3.fromRGB(104, 220, 250), FlameBoots = Color3.fromRGB(255, 183, 104),
			IceSkates = Color3.fromRGB(158, 214, 255), LightningBoots = Color3.fromRGB(255, 227, 91),
			VoidHoverboard = Color3.fromRGB(232, 170, 255), WindScarf = Color3.fromRGB(193, 170, 250),
			Bat = Color3.fromRGB(255, 222, 151), IronBat = Color3.fromRGB(187, 213, 243), IronSword = Color3.fromRGB(166, 220, 240),
			ForestSword = Color3.fromRGB(168, 228, 157), DesertSword = Color3.fromRGB(255, 205, 128),
			IceSword = Color3.fromRGB(143, 222, 255), LavaSword = Color3.fromRGB(255, 166, 145),
		}
		local previewTint = previewColors[offer.Key] or Color3.fromRGB(170, 227, 253)
		shade(preview, previewTint, previewTint:Lerp(Color3.new(1, 1, 1), 0.66))
		if offer.Kind == "Weapon" then UI.WeaponPreview(preview, offer.Template)
		elseif offer.Kind == "Accessory" then UI.GearPreview(preview, offer.Key)
		else
			local iconKeys = { VIP = "Gamepasses", AutoCollectBabies = "MonsterCollector", InstantHatch = "RareEgg", LuckyEgg = "LuckyEgg",
				SpeedBoost = "Speed", SkipToAdultOne = "CoinsGrowth", SkipToAdultAll = "CoinsGrowth", Coins1000 = "Coins", Coins5000 = "Coins", Coins15000 = "Coins" }
			local art = CartoonUI.Icon(preview, iconKeys[offer.Key] or offer.Key, 96)
			art.Name, art.Size, art.Position, art.ZIndex = "PassArt", UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), 34
		end
		for _, child in preview:GetChildren() do
			if child:IsA("ViewportFrame") then
				child.Position, child.Size, child.ZIndex = UDim2.new(), UDim2.fromScale(1, 1), 33
				child.Ambient = Color3.fromRGB(218, 224, 234)
				if child.CurrentCamera then child.CurrentCamera.FieldOfView = 28 end
			end
		end
		local titleLabel = text(card, "Title", offer.Title, 17, C.Text)
		titleLabel.Font = Enum.Font.FredokaOne
		local description = text(card, "Description", offer.Description, 13, C.Muted)
		local price = text(card, "Price", "", 18, C.Ivory)
		price.Font = Enum.Font.FredokaOne
		round(price, 8)
		local coin = CartoonUI.Icon(card, "Coins", 24)
		coin.Name, coin.ZIndex = "CoinIcon", 34
		coin.Visible = offer.Kind == "Weapon" or offer.Kind == "Accessory"
		local action = button(card, "BuyButton", "")
		offer.Card, offer.Preview, offer.TitleLabel, offer.DescriptionLabel, offer.PriceLabel, offer.Action, offer.Outline, offer.CoinIcon = card, preview, titleLabel, description, price, action, outline, coin
		table.insert(offers, offer)
	end
	-- السيوف مترتبة بقوتها (ضرر الضربة) من الأضعف للأقوى، والـ Bat الأول
	local weaponKeys = { "Bat" }
	local sortedWeapons = {}
	for key in Config.WeaponStats do table.insert(sortedWeapons, key) end
	table.sort(sortedWeapons, function(a, b)
		local damageA, damageB = Config.WeaponStats[a].DamageMultiplier, Config.WeaponStats[b].DamageMultiplier
		if damageA ~= damageB then return damageA < damageB end
		return a < b
	end)
	for _, key in sortedWeapons do table.insert(weaponKeys, key) end
	for _, key in weaponKeys do
		local info = Config.WeaponStats[key]
		local pass = Config.Gamepasses[key]
		add({ Key = key, Kind = "Weapon", Category = "Weapons", Title = if key == "Bat" then "Bat" else pass.Name,
			Description = if key == "Bat" then "Your starter weapon" else pass.Description,
			Price = Config.WeaponCoinPrices[key] or 0, Template = if info then info.Template else "WoodenBat", Stats = info,
			-- سيف الـ VIP مش بيتباع في الشوب: بيظهر في Owned بس لو اللاعب عنده الـ VIP
			OwnedOnly = Config.WeaponCoinPrices[key] == nil and key ~= "Bat" })
	end
	local accessoryKeys = {}
	for key in Config.SpeedAccessories do table.insert(accessoryKeys, key) end
	table.sort(accessoryKeys, function(a, b) return Config.SpeedAccessories[a].Price < Config.SpeedAccessories[b].Price end)
	for _, key in accessoryKeys do
		local info = Config.SpeedAccessories[key]
		add({ Key = key, Kind = "Accessory", Category = "Accessories", Title = info.Name, Description = info.Description, Price = info.Price, Stats = info,
			-- boss-loot gear is never sold: it only shows up under Owned once a boss drop gave it to you
			OwnedOnly = info.LootOnly == true })
	end
	local passKeys = { "DoubleDamage", "VIP", "AutoCollect", "ExtraSlots", "AutoFeeder", "AutoMinigame" }
	for _, key in passKeys do
		local info = Config.Gamepasses[key]
		if info and not info.Hidden then
			add({ Key = key, Kind = "Pass", Category = "Gamepasses", Title = if key == "DoubleDamage" then "x2 DAMAGE" else string.upper(info.Name),
				Description = if key == "DoubleDamage" then "Double every player weapon hit\nPlayer weapons only" elseif key == "VIP" then "x2 monster coins + VIP Sword" else info.Description,
				Price = info.Price, Id = info.Id, Featured = key == "DoubleDamage" or key == "VIP" })
		end
	end
	-- Keep future configured perks reachable without changing the approved six-card hierarchy.
	-- مترتبة بـ Order عشان الترتيب يبقى ثابت مش عشوائي.
	local extraPasses = {}
	for key, info in Config.Gamepasses do
		if not Config.WeaponStats[key] and not info.Hidden and not table.find(passKeys, key) then table.insert(extraPasses, key) end
	end
	table.sort(extraPasses, function(a, b) return Config.Gamepasses[a].Order < Config.Gamepasses[b].Order end)
	for _, key in extraPasses do
		local info = Config.Gamepasses[key]
		add({ Key = key, Kind = "Pass", Category = "Gamepasses", Title = info.Name, Description = info.Description, Price = info.Price, Id = info.Id })
	end
	local productKeys = {}
	for key in Config.Products do table.insert(productKeys, key) end
	table.sort(productKeys, function(a, b) return Config.Products[a].Order < Config.Products[b].Order end)
	for _, key in productKeys do
		local info = Config.Products[key]
		if not info.Hidden then
			add({ Key = key, Kind = "Product", Category = if key == "SummonBoss" then "Gamepasses" else "Coins & Growth",
				Title = info.Name, Description = info.Description, Price = info.Price, Id = info.Id })
		end
	end
	local function token(offer: any): string return offer.Kind .. ":" .. offer.Key end
	local function available(offer: any): boolean
		return not unavailable[token(offer)] and (not offer.Id or offer.Id ~= 0 or RunService:IsStudio())
	end
	local function cost(offer: any): string
		if not offer.Id then return comma(offer.Price) .. " COINS" end
		if offer.Id == 0 then return if RunService:IsStudio() then "TEST FREE (STUDIO)" else "COMING SOON" end
		if unavailable[token(offer)] then return "UNAVAILABLE" end
		if loading[token(offer)] then return "CHECKING PRICE..." end
		return "R$ " .. comma(prices[token(offer)] or offer.Price)
	end
	local function perform(offer: any)
		local state = options.GetState() or {}
		local key = token(offer)
		if pending[key] or not available(offer) or (offer.Kind == "Pass" and owned(offer, state)) then return end
		if offer.Kind == "Weapon" and equipped(offer, state) then return end
		pending[key] = true
		if offer.Kind == "Weapon" then
			if owned(offer, state) then options.Remotes.EquipWeapon:FireServer(offer.Key) else options.Remotes.BuyWeapon:FireServer(offer.Key) end
		elseif offer.Kind == "Accessory" then
			if owned(offer, state) then options.Remotes.EquipSpeedAccessory:FireServer(if equipped(offer, state) then nil else offer.Key)
			else options.Remotes.BuySpeedAccessory:FireServer(offer.Key) end
		elseif offer.Kind == "Pass" then options.BuyPass(offer.Key)
		else options.BuyProduct(offer.Key) end
		refresh()
		task.delay(1.25, function() if alive then pending[key] = nil; refresh() end end)
	end
	for _, offer in offers do
		offer.Action.Activated:Connect(function()
			if offer.Kind == "Weapon" or offer.Kind == "Accessory" then
				selectedKey = offer.Key
				refresh()
				if detail.Parent == scroll then scroll.CanvasPosition = Vector2.zero end
			else perform(offer) end
		end)
	end
	local function selected(): any
		for _, offer in offers do if offer.Key == selectedKey and (offer.Kind == "Weapon" or offer.Kind == "Accessory") then return offer end end
		return offers[1]
	end
	detailAction.Activated:Connect(function() perform(selected()) end)
	local function selectedCopy(offer: any, state: any): string
		if pending[token(offer)] then return "PLEASE WAIT..." end
		if not available(offer) then return "UNAVAILABLE" end
		if equipped(offer, state) then return if offer.Kind == "Accessory" then "UNEQUIP" else "EQUIPPED" end
		if owned(offer, state) then return "EQUIP" end
		return if offer.Kind == "Weapon" then "BUY WEAPON" else "BUY ACCESSORY"
	end
	local function updateDetail(state: any)
		local offer = selected()
		detailName.Text = offer.Title
		detailPrice.Text = if owned(offer, state) then (if equipped(offer, state) then "EQUIPPED" else "OWNED") else cost(offer)
		detailAction.Text = selectedCopy(offer, state)
		detailAction.Active = available(offer) and not pending[token(offer)] and (offer.Kind == "Accessory" or not equipped(offer, state))
		detailAction.Selectable = detailAction.Active
		actionState(detailAction, detailAction.Active)
		if statKind ~= offer.Kind then
			statKind = offer.Kind
			statAIcon:Destroy()
			statBIcon:Destroy()
			statAIcon = CartoonUI.Icon(stats, if offer.Kind == "Weapon" then "DoubleDamage" else "Speed", 28)
			statBIcon = CartoonUI.Icon(stats, if offer.Kind == "Weapon" then "Weapons" else "Health", 28)
			statAIcon.Name, statBIcon.Name = "PrimaryIcon", "SecondaryIcon"
			for _, icon in { statAIcon, statBIcon } do icon.Position, icon.ZIndex = UDim2.new(0, 6, 0.5, -14), 35 end
		end
		if offer.Kind == "Weapon" then
			statA.Text = "x" .. tostring(if offer.Stats then offer.Stats.DamageMultiplier else 1) .. "\nDAMAGE"
			statB.Text = "+" .. tostring(if offer.Stats then offer.Stats.ExtraReach else 0) .. "\nREACH"
		else
			statA.Text = "+" .. tostring(math.floor((offer.Stats.Multiplier - 1) * 100 + 0.5)) .. "%\nSPEED"
			statB.Text = "+" .. tostring(offer.Stats.HealthBonus) .. "\nHEALTH"
		end
		if previewKey ~= token(offer) then
			previewKey = token(offer)
			for _, child in detailPreview:GetChildren() do if child:IsA("ViewportFrame") then child:Destroy() end end
			if offer.Kind == "Weapon" then UI.WeaponPreview(detailPreview, offer.Template) else UI.GearPreview(detailPreview, offer.Key) end
			for _, child in detailPreview:GetChildren() do
				if child:IsA("ViewportFrame") then
					child.Position, child.Size, child.ZIndex = UDim2.new(), UDim2.fromScale(1, 1), 33
					if child.CurrentCamera then child.CurrentCamera.FieldOfView = 28 end
				end
			end
		end
	end
	local function placeCard(offer: any, x: number, y: number, w: number, h: number, mode: string)
		local card = offer.Card
		card.Position, card.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
		local preview, titleLabel, description, price, action = offer.Preview, offer.TitleLabel, offer.DescriptionLabel, offer.PriceLabel, offer.Action
		if mode == "gear" then
			preview.Position, preview.Size = UDim2.fromOffset(9, 9), UDim2.fromOffset(w - 18, h - 80)
			titleLabel.Position, titleLabel.Size, titleLabel.TextSize = UDim2.fromOffset(6, h - 67), UDim2.fromOffset(w - 12, 31), if w < 150 then 14 else 17
			description.Visible = false
			local coinVisible = offer.CoinIcon.Visible
			price.Position, price.Size, price.TextSize = UDim2.fromOffset(if coinVisible then 36 else 12, h - 34), UDim2.fromOffset(w - (if coinVisible then 46 else 24), 26), if w < 150 then 16 else 18
			offer.CoinIcon.Position, offer.CoinIcon.Size = UDim2.fromOffset(9, h - 33), UDim2.fromOffset(24, 24)
			-- A single native selection target includes both item art and its price/state.
			action.Position, action.Size = UDim2.new(), UDim2.fromScale(1, 1)
			action.Text, action.BackgroundTransparency, action.ZIndex = "", 1, 35
			for _, child in action:GetChildren() do if child:IsA("UIStroke") or child:IsA("UIGradient") then child.Enabled = false end end
		else
			local featured = mode == "featured"
			titleLabel.Position, titleLabel.Size = UDim2.fromOffset(8, 6), UDim2.fromOffset(w - 16, if featured then 44 else 32)
			titleLabel.TextSize = if featured then (if w < 250 then 27 else 34) else (if w < 180 then 13 else 16)
			preview.Position = UDim2.fromOffset(8, if featured then 50 else 38)
			preview.Size = UDim2.fromOffset(w - 16, math.max(32, h - (if featured then 148 else 110)))
			description.Visible = featured or mode == "product"
			description.Position, description.Size = UDim2.fromOffset(10, h - 93), UDim2.fromOffset(w - 20, 37)
			description.TextSize = if featured then 13 else 12
			price.Visible = false
			action.Position, action.Size = UDim2.fromOffset(if featured then math.floor(w * 0.18) else 12, h - 51), UDim2.fromOffset(if featured then math.floor(w * 0.64) else w - 24, 44)
			action.TextSize = if featured then 23 else 18
		end
	end
	layout = function()
		local width, height = root.Size.X.Offset, root.Size.Y.Offset
		local compact = width < 780 or height < 390
		local headerHeight = if compact then 66 else 80
		local navWidth = if width < 480 then 86 elseif compact then 140 else 176
		local padding, gap = if compact then 8 else 12, if compact then 8 else 12
		local faceHeight = headerHeight - 6
		header.Position, header.Size = UDim2.fromOffset(6, 6), UDim2.new(1, -12, 0, faceHeight)
		catalogCanvas.Position, catalogCanvas.Size = UDim2.fromOffset(6, headerHeight + 2), UDim2.new(1, -12, 1, -headerHeight - 8)
		local showIcon = width >= 480
		local iconSize = if compact then 40 else 52
		forgeIcon.Visible = showIcon
		forgeIcon.Size, forgeIcon.Position = UDim2.fromOffset(iconSize, iconSize), UDim2.fromOffset(14, math.floor((faceHeight - iconSize) / 2))
		forgeIcon.TextSize = iconSize - 8
		local titleX = if showIcon then iconSize + 28 else 16
		title.Position, title.Size = UDim2.fromOffset(titleX, 0), UDim2.new(1, -titleX - 70, 1, 0)
		title.TextSize = if width < 480 then 26 elseif compact then 32 else 40
		close.Position = UDim2.new(1, -58, 0, 6 + math.floor((faceHeight - 44) / 2))
		passHeading.Visible = false
		passHeading.Position, passHeading.Size = UDim2.fromOffset(520, 14), UDim2.fromOffset(math.max(1, width - 600), 32)
		nav.Position, nav.Size = UDim2.fromOffset(padding, headerHeight + 4), UDim2.fromOffset(navWidth - padding, height - headerHeight - padding - 4)
		-- Seven tabs share the column: they shrink toward the 44px touch minimum, then the column scrolls.
		local tabHeight = math.clamp(math.floor((height - headerHeight - padding - 4 - (#NAV - 1) * 6) / #NAV), 44, if compact then 56 else 66)
		for index, category in NAV do
			local tab = tabs[category]
			tab.Position, tab.Size = UDim2.fromOffset(3, (index - 1) * (tabHeight + 6)), UDim2.fromOffset(navWidth - padding - 7, tabHeight)
			local icon, caption = tab:FindFirstChild("Icon") :: ImageLabel, tab:FindFirstChild("Caption") :: TextLabel
			icon.Visible = width >= 480
			local iconSize = math.min(if compact then 42 else 50, tabHeight - 8)
			icon.Size, icon.Position = UDim2.fromOffset(iconSize, iconSize), UDim2.fromOffset(5, math.floor((tabHeight - iconSize) / 2))
			caption.Position, caption.Size = UDim2.fromOffset(if width < 480 then 4 else iconSize + 9, 2), UDim2.new(1, if width < 480 then -8 else -iconSize - 15, 1, -4)
			caption.TextSize = if width < 480 then 13 elseif compact then 14 else 17
		end
		nav.CanvasSize = UDim2.fromOffset(0, #NAV * (tabHeight + 6))
		local sectionHeight = if compact then 0 else 30
		local contentX, contentY = navWidth + gap, headerHeight + 4 + sectionHeight
		local contentWidth, contentHeight = width - contentX - padding, height - contentY - padding
		local extraTab = EXTRA_TABS[selectedCategory] == true
		subtitle.Visible = sectionHeight > 0
		subtitle.Text = "- " .. string.upper(selectedCategory) .. " -"
		subtitle.Position, subtitle.Size = UDim2.fromOffset(contentX, headerHeight + 4), UDim2.fromOffset(contentWidth, sectionHeight - 2)
		local hasDetail = selectedCategory == "Weapons" or selectedCategory == "Accessories" or selectedCategory == "Owned"
		local stacked = hasDetail and (contentWidth < 370 or contentHeight < 300)
		local detailWidth = if compact then math.min(220, math.floor(contentWidth * 0.43)) else math.floor(contentWidth * 0.4)
		local gridWidth = if hasDetail and not stacked then contentWidth - detailWidth - gap else contentWidth
		scroll.Position, scroll.Size = UDim2.fromOffset(contentX, contentY), UDim2.fromOffset(gridWidth, contentHeight)
		scroll.Visible = not extraTab
		codesPanel.Visible, giftPanel.Visible = selectedCategory == "Codes", selectedCategory == "Gift"
		codesPanel.Position, codesPanel.Size = UDim2.fromOffset(contentX, contentY), UDim2.fromOffset(contentWidth, contentHeight)
		giftPanel.Position, giftPanel.Size = codesPanel.Position, codesPanel.Size
		if extraTab then
			local small = contentWidth < 400
			-- Codes: message, then the input box with Redeem beside it (stacked on narrow screens), then the answer.
			codesMessage.Position, codesMessage.Size, codesMessage.TextSize = UDim2.fromOffset(8, 8), UDim2.fromOffset(contentWidth - 16, 44), if small then 18 else 24
			local redeemWidth = if small then contentWidth - 24 else 170
			local fieldHeight = if small then 52 else 64
			codeField.Position = UDim2.fromOffset(12, 64)
			codeField.Size = UDim2.fromOffset(if small then contentWidth - 24 else contentWidth - 24 - redeemWidth - 12, fieldHeight)
			redeemButton.Position = if small then UDim2.fromOffset(12, 64 + fieldHeight + 10) else UDim2.fromOffset(contentWidth - 12 - redeemWidth, 64)
			redeemButton.Size = UDim2.fromOffset(redeemWidth, fieldHeight)
			codesStatus.Position = UDim2.fromOffset(8, if small then 64 + fieldHeight * 2 + 24 else 64 + fieldHeight + 16)
			codesStatus.Size = UDim2.fromOffset(contentWidth - 16, 52)
			-- Gift: heading, player list, then the name box with its confirm button and a status line.
			giftMessage.Position, giftMessage.Size, giftMessage.TextSize = UDim2.fromOffset(8, 4), UDim2.fromOffset(contentWidth - 16, 36), if small then 18 else 24
			local rowHeight, statusHeight = if small then 48 else 60, 26
			local rowY = contentHeight - 12 - statusHeight - rowHeight
			local listHeight = math.max(48, rowY - 48 - 8)
			giftList.Position, giftList.Size = UDim2.fromOffset(12, 46), UDim2.fromOffset(contentWidth - 24, listHeight)
			giftEmpty.Position, giftEmpty.Size = UDim2.fromOffset(12, 46 + math.floor(listHeight / 2) - 18), UDim2.fromOffset(contentWidth - 24, 36)
			giftField.Position, giftField.Size = UDim2.fromOffset(12, rowY), UDim2.fromOffset(contentWidth - 24 - 80, rowHeight)
			giftButton.Position, giftButton.Size = UDim2.fromOffset(contentWidth - 12 - 72, rowY), UDim2.fromOffset(72, rowHeight)
			giftIcon.Size = UDim2.fromOffset(rowHeight - 14, rowHeight - 14)
			giftIcon.Position = UDim2.new(0.5, -(rowHeight - 14) / 2, 0.4, -(rowHeight - 14) / 2)
			giftStatus.Position, giftStatus.Size = UDim2.fromOffset(8, contentHeight - 12 - statusHeight + 2), UDim2.fromOffset(contentWidth - 16, statusHeight)
			codeBox.TextSize, giftBox.TextSize = if small then 18 else 24, if small then 18 else 24
		end
		detail.Visible = hasDetail
		detail.Parent = if stacked then scroll else root
		detail.Position = if stacked then UDim2.fromOffset(0, 0) else UDim2.fromOffset(contentX + gridWidth + gap, contentY)
		detail.Size = UDim2.fromOffset(if stacked then gridWidth - 6 else detailWidth, if stacked then 338 else contentHeight)
		local dw, dh = detail.Size.X.Offset, detail.Size.Y.Offset
		local shortDetail = dh < 320
		detailEyebrow.Position, detailEyebrow.Size = UDim2.fromOffset(10, 8), UDim2.fromOffset(dw - 20, 16)
		detailName.Position, detailName.Size, detailName.TextSize = UDim2.fromOffset(8, 8), UDim2.fromOffset(dw - 16, 43), if dw < 240 then 20 else 25
		local statsHeight = if shortDetail then 48 else 65
		stats.Position, stats.Size = UDim2.fromOffset(10, 57), UDim2.fromOffset(dw - 20, statsHeight)
		local sw = (dw - 26) / 2
		statA.Position, statA.Size, statA.TextSize = UDim2.new(), UDim2.fromOffset(sw, statsHeight), if shortDetail then 14 else 17
		statB.Position, statB.Size, statB.TextSize = UDim2.fromOffset(sw + 6, 0), UDim2.fromOffset(sw, statsHeight), if shortDetail then 14 else 17
		local showStatIcons = dw >= 250
		statAIcon.Visible, statBIcon.Visible = showStatIcons, showStatIcons
		statAIcon.Position = UDim2.fromOffset(6, math.floor((statsHeight - 28) / 2))
		statBIcon.Position = UDim2.fromOffset(sw + 12, math.floor((statsHeight - 28) / 2))
		statAPadding.PaddingLeft, statBPadding.PaddingLeft = UDim.new(0, if showStatIcons then 40 else 0), UDim.new(0, if showStatIcons then 40 else 0)
		local previewY = 63 + statsHeight
		detailPreview.Position = UDim2.fromOffset(8, previewY)
		detailPreview.Size = UDim2.fromOffset(dw - 16, math.max(0, dh - previewY - 104))
		detailPrice.Position, detailPrice.Size, detailPrice.TextSize = UDim2.fromOffset(8, dh - 94), UDim2.fromOffset(dw - 16, 30), if dw < 240 then 17 else 21
		detailAction.Position, detailAction.Size, detailAction.TextSize = UDim2.fromOffset(10, dh - 62), UDim2.fromOffset(dw - 20, 44), if dw < 240 then 16 else 20
		detailNote.Visible = not shortDetail
		detailNote.Position, detailNote.Size = UDim2.fromOffset(4, dh - 17), UDim2.fromOffset(dw - 8, 15)
		local state = options.GetState() or {}
		local visible = {}
		for _, offer in offers do
			offer.Card.Visible = (offer.Category == selectedCategory and not offer.OwnedOnly) or (selectedCategory == "Owned" and (offer.Kind == "Weapon" or offer.Kind == "Accessory") and owned(offer, state))
			if offer.Card.Visible then table.insert(visible, offer) end
		end
		local bottom = if stacked then dh + gap else 0
		if selectedCategory == "Gamepasses" then
			local columns = if contentWidth < 370 then 1 else 2
			local featuredHeight = if compact then 230 else math.floor(contentHeight * 0.58)
			local featuredWidth = math.floor((gridWidth - 6 - (columns - 1) * gap) / columns)
			local featuredCount, smallCount = 0, 0
			-- الكروت الصغيرة كلها في صف واحد على الديسكتوب (4 أو أكتر لما تتضاف جيمباسات جديدة)
				local plainCount = 0
				for _, offer in visible do if not offer.Featured then plainCount += 1 end end
				local smallColumns = if compact then (if gridWidth < 370 then 1 else 2) else math.clamp(plainCount, 4, 6)
			local smallWidth = math.floor((gridWidth - 6 - (smallColumns - 1) * gap) / smallColumns)
			local smallHeight = if compact then 173 else contentHeight - featuredHeight - gap
			for _, offer in visible do
				if offer.Featured then
					placeCard(offer, (featuredCount % columns) * (featuredWidth + gap), math.floor(featuredCount / columns) * (featuredHeight + gap), featuredWidth, featuredHeight, "featured")
					featuredCount += 1
				end
			end
			local smallY = math.ceil(featuredCount / columns) * (featuredHeight + gap)
			for _, offer in visible do
				if not offer.Featured then
					placeCard(offer, (smallCount % smallColumns) * (smallWidth + gap), smallY + math.floor(smallCount / smallColumns) * (smallHeight + gap), smallWidth, smallHeight, "pass")
					smallCount += 1
				end
			end
			bottom = smallY + math.ceil(smallCount / smallColumns) * (smallHeight + gap) - gap
		else
			local columns = if selectedCategory == "Coins & Growth" then math.clamp(math.floor(gridWidth / 220), 1, 3) else math.clamp(math.floor(gridWidth / 142), 1, 3)
			local cardWidth = math.floor((gridWidth - 6 - (columns - 1) * gap) / columns)
			local cardHeight = if selectedCategory == "Coins & Growth" then 236 elseif compact then 174 else math.floor((contentHeight - gap) / 2)
			for index, offer in visible do
				placeCard(offer, ((index - 1) % columns) * (cardWidth + gap), bottom + math.floor((index - 1) / columns) * (cardHeight + gap), cardWidth, cardHeight, if selectedCategory == "Coins & Growth" then "product" else "gear")
			end
			bottom += math.ceil(#visible / columns) * (cardHeight + gap) - (if #visible > 0 then gap else 0)
		end
		empty.Position, empty.Size = UDim2.fromOffset(8, if stacked then dh + gap else 18), UDim2.fromOffset(math.max(1, gridWidth - 22), 80)
		empty.Visible = #visible == 0
		scroll.CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, bottom))
		scroll.ScrollBarThickness = if bottom > contentHeight then 4 else 0
	end
	refresh = function()
		if not alive then return end
		local state = options.GetState() or {}
		for _, offer in offers do
			local isOwned, isEquipped = owned(offer, state), equipped(offer, state)
			local isGear = offer.Kind == "Weapon" or offer.Kind == "Accessory"
			offer.PriceLabel.Text = if isOwned then (if isEquipped then "EQUIPPED" else "OWNED") else cost(offer)
			offer.PriceLabel.TextColor3 = if isOwned then Color3.fromRGB(36, 112, 49) else C.Ivory
			offer.Outline.Color = if isGear and selectedKey == offer.Key then C.Cyan elseif offer.Key == "DoubleDamage" then Color3.fromRGB(246, 133, 120) elseif offer.Key == "VIP" then Color3.fromRGB(222, 170, 51) else C.Edge
			offer.Outline.Thickness = if isGear and selectedKey == offer.Key then 3 else 1.5
			if not isGear then
				offer.Action.Text = if isOwned then "OWNED" elseif pending[token(offer)] then "OPENING..." else cost(offer)
				offer.Action.Active = available(offer) and not isOwned and not pending[token(offer)]
				offer.Action.Selectable = offer.Action.Active
				actionState(offer.Action, offer.Action.Active)
			end
			if offer.Key == "SkipToAdultAll" and options.AdultCandidates then
				local count = #options.AdultCandidates()
				offer.DescriptionLabel.Text = tostring(count) .. " current " .. (if count == 1 then "monster" else "monsters") .. " below Adult. Future monsters excluded."
			end
		end
		for category, tab in tabs do
			tab.BackgroundColor3 = if category == selectedCategory then HudKit.Colors.Gold else C.Blue
			local caption = tab:FindFirstChild("Caption") :: TextLabel
			caption.TextColor3 = C.Text
			local stroke = tab:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color, stroke.Thickness = HudKit.Colors.Ink, if category == selectedCategory then 3 else 2 end
		end
		updateDetail(state)
		layout()
	end
	for category, tab in tabs do
		tab.Activated:Connect(function()
			selectedCategory = category
			if category == "Accessories" then selectedKey = accessoryKeys[1]
			elseif category == "Weapons" then if not Config.WeaponStats[selectedKey] and selectedKey ~= "Bat" then selectedKey = "IceSword" end
			elseif category == "Owned" then selectedKey = "Bat" end
			scroll.CanvasPosition = Vector2.zero
			if category == "Gift" then refreshGiftList() end
			refresh()
		end)
	end
	-- Codes: the server validates, rate limits and rewards; this only sends the typed text.
	local function setStatus(label: TextLabel, value: string, good: boolean?)
		label.Text = value
		label.TextColor3 = if good == true then Color3.fromRGB(150, 255, 90) elseif good == false then Color3.fromRGB(255, 120, 130) else HudKit.Colors.White
	end
	local redeemLockedUntil = 0
	redeemButton.Activated:Connect(function()
		local code = string.sub(codeBox.Text, 1, 32)
		if code:match("^%s*$") then setStatus(codesStatus, "Type a code first.", false); return end
		if os.clock() < redeemLockedUntil then return end
		local remote = options.Remotes.RedeemCode
		if not remote then setStatus(codesStatus, "Codes are not available right now.", false); return end
		redeemLockedUntil = os.clock() + 1.5
		setStatus(codesStatus, "Checking...", nil)
		remote:FireServer(code)
	end)
	local redeemResult = options.Remotes.RedeemResult
	if redeemResult then
		redeemResult.OnClientEvent:Connect(function(ok: any, message: any)
			if not alive then return end
			setStatus(codesStatus, tostring(message), ok == true)
			if ok == true then codeBox.Text = "" end
		end)
	end
	-- Gift: lists the other players in this server. There is no gifting economy yet, so Confirm only explains that.
	local function refreshGiftList()
		for _, child in giftList:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		local others = {}
		for _, member in Players:GetPlayers() do
			if member ~= Players.LocalPlayer then table.insert(others, member) end
		end
		table.sort(others, function(a, b) return a.Name < b.Name end)
		for index, member in others do
			local picked = giftBox.Text == member.Name
			local row = HudKit.Button(giftList, member.Name, member.DisplayName .. "  @" .. member.Name, if picked then "Yellow" else "Blue")
			row.Position, row.Size = UDim2.fromOffset(0, (index - 1) * 54), UDim2.new(1, -8, 0, 48)
			row.Activated:Connect(function()
				giftBox.Text = member.Name
				setStatus(giftStatus, "", nil)
				refreshGiftList()
			end)
		end
		giftList.CanvasSize = UDim2.fromOffset(0, #others * 54)
		giftEmpty.Visible = #others == 0
	end
	giftButton.Activated:Connect(function()
		if giftBox.Text:match("^%s*$") then setStatus(giftStatus, "Pick a player first.", false); return end
		setStatus(giftStatus, "Gifting is coming soon!", nil)
	end)
	Players.PlayerAdded:Connect(function() if alive and giftPanel.Visible then refreshGiftList() end end)
	Players.PlayerRemoving:Connect(function() if alive and giftPanel.Visible then task.defer(refreshGiftList) end end)
	root:GetPropertyChangedSignal("Size"):Connect(layout)
	root:GetPropertyChangedSignal("Visible"):Connect(function() if root.Visible then refresh() end end)
	refresh()
	-- Marketplace prices may be regional. The native Roblox prompt remains the final confirmation.
	local ok, marketplace = pcall(function() return game:GetService("MarketplaceService") end)
	if ok and marketplace then
		for _, offer in offers do
			if offer.Id and offer.Id ~= 0 then
				loading[token(offer)] = true
				task.spawn(function()
					local fetched, info = pcall(function() return marketplace:GetProductInfo(offer.Id, if offer.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product) end)
					if not alive then return end
					loading[token(offer)] = nil
					if fetched and type(info) == "table" then
						if info.IsForSale == false then unavailable[token(offer)] = true
						elseif type(info.PriceInRobux) == "number" then prices[token(offer)] = info.PriceInRobux end
					end
					refresh()
				end)
			end
		end
	end
	return { Refresh = function() refresh() end, Destroy = function() alive = false end }
end

return MonsterForge
