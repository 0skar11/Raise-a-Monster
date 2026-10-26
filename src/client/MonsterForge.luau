--!strict
-- The forge is presentation only. Purchases and ownership remain server-authoritative.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.UI)
local CartoonUI = require(script.Parent.CartoonUI)

local MonsterForge = {}
MonsterForge.Assets = {} -- Shared authored artwork lives in CartoonUI.
local C = {
	Ink = Color3.fromRGB(16, 43, 94), Stone = Color3.fromRGB(255, 248, 223), Raised = Color3.fromRGB(255, 255, 249),
	Edge = Color3.fromRGB(137, 200, 232), Bronze = Color3.fromRGB(29, 168, 229), Gold = Color3.fromRGB(255, 209, 57),
	Ivory = Color3.fromRGB(19, 44, 98), Text = Color3.fromRGB(19, 44, 98), Muted = Color3.fromRGB(55, 84, 115),
	Cyan = Color3.fromRGB(0, 201, 214), Blue = Color3.fromRGB(219, 244, 255), Red = Color3.fromRGB(232, 57, 91),
	Green = Color3.fromRGB(157, 235, 44), Disabled = Color3.fromRGB(211, 226, 227),
}
local NAV = { "Weapons", "Accessories", "Gamepasses", "Coins & Growth", "Owned" }

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

local function glyph(parent: Instance, kind: string): ImageLabel
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
	root.BackgroundColor3, root.BorderSizePixel, root.ZIndex = C.Stone, 0, 30
	root.ClipsDescendants = false
	round(root, 16)
	border(root, C.Bronze, 3)
	local shell = CartoonUI.DecorateShell(root)
	shell.ZIndex = 30
	local catalogCanvas = frame(root, "CatalogCanvas", C.Stone)
	catalogCanvas.ZIndex = 31
	round(catalogCanvas, 14)
	local header = frame(root, "ForgeHeader", Color3.fromRGB(31, 177, 236))
	header.ZIndex = 33
	header.BackgroundTransparency = 0.12
	round(header, 12)
	local forgeIcon = glyph(header, "Forge")
	local title = text(header, "Title", "MONSTER FORGE", 34, C.Gold)
	title.Font = Enum.Font.FredokaOne
	title.TextStrokeColor3, title.TextStrokeTransparency = C.Ink, 0
	title.TextXAlignment = Enum.TextXAlignment.Center
	local subtitle = text(header, "Subtitle", "Gear up. Hit harder.", 14, Color3.new(1, 1, 1))
	subtitle.TextStrokeColor3, subtitle.TextStrokeTransparency = C.Ink, 0.2
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	local passHeading = text(header, "PassHeading", "", 21, C.Ivory)
	local close = button(root, "CloseButton", "X")
	close.BackgroundColor3, close.TextColor3, close.TextSize = C.Red, Color3.new(1, 1, 1), 24
	local closeStroke = close:FindFirstChildOfClass("UIStroke")
	if closeStroke then closeStroke.Color = Color3.fromRGB(160, 34, 72) end
	local closeGradient = close:FindFirstChildOfClass("UIGradient")
	if closeGradient then closeGradient:Destroy() end
	close.Size, close.Position = UDim2.fromOffset(44, 44), UDim2.new(1, -56, 0, 10)
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
		if stroke then stroke.Color = C.Edge end
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
	local detail = frame(root, "SelectedItem", Color3.new(1, 1, 1))
	detail.ZIndex = 33
	round(detail, 14)
	border(detail, C.Cyan, 2)
	shade(detail, Color3.fromRGB(238, 255, 255), Color3.fromRGB(198, 244, 255))
	local detailPreview = frame(detail, "Preview", C.Blue)
	detailPreview.BackgroundTransparency = 1
	local detailEyebrow = text(detail, "SelectedLabel", "", 12, C.Muted)
	detailEyebrow.Visible = false
	local detailName = text(detail, "Title", "Ice Sword", 25, C.Ivory)
	detailName.Font = Enum.Font.FredokaOne
	local stats = frame(detail, "Stats", C.Ink)
	stats.BackgroundTransparency = 1
	local statA = text(stats, "Primary", "x40\nweapon damage", 18, C.Text)
	local statB = text(stats, "Secondary", "+2.5\nreach", 18, C.Text)
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
		round(card, 12)
		local outline = border(card, C.Edge, 1)
		if offer.Featured and offer.Key == "DoubleDamage" then
			shade(card, Color3.fromRGB(255, 242, 229), Color3.fromRGB(255, 219, 216))
		elseif offer.Featured and offer.Key == "VIP" then
			shade(card, Color3.fromRGB(255, 254, 226), Color3.fromRGB(255, 237, 177))
		else
			shade(card, C.Raised, C.Stone)
		end
		local preview = frame(card, "Preview", Color3.new(1, 1, 1))
		round(preview, 10)
		local previewColors = {
			SwiftSneakers = Color3.fromRGB(168, 236, 255), FlameBoots = Color3.fromRGB(255, 211, 157),
			IceSkates = Color3.fromRGB(208, 237, 255), LightningBoots = Color3.fromRGB(255, 239, 142),
			VoidHoverboard = Color3.fromRGB(247, 211, 255), WindScarf = Color3.fromRGB(222, 211, 255),
		}
		local previewTint = previewColors[offer.Key] or Color3.fromRGB(211, 239, 255)
		shade(preview, Color3.new(1, 1, 1), previewTint)
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
			end
		end
		local titleLabel = text(card, "Title", offer.Title, 17, C.Text)
		titleLabel.Font = Enum.Font.FredokaOne
		local description = text(card, "Description", offer.Description, 13, C.Muted)
		local price = text(card, "Price", "", 18, C.Ivory)
		local action = button(card, "BuyButton", "")
		offer.Card, offer.Preview, offer.TitleLabel, offer.DescriptionLabel, offer.PriceLabel, offer.Action, offer.Outline = card, preview, titleLabel, description, price, action, outline
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
			statA.Text = "x" .. tostring(if offer.Stats then offer.Stats.DamageMultiplier else 1) .. "\nweapon damage"
			statB.Text = "+" .. tostring(if offer.Stats then offer.Stats.ExtraReach else 0) .. "\nreach"
		else
			statA.Text = "+" .. tostring(math.floor((offer.Stats.Multiplier - 1) * 100 + 0.5)) .. "%\nspeed"
			statB.Text = "+" .. tostring(offer.Stats.HealthBonus) .. "\nhealth"
		end
		if previewKey ~= token(offer) then
			previewKey = token(offer)
			for _, child in detailPreview:GetChildren() do child:Destroy() end
			if offer.Kind == "Weapon" then UI.WeaponPreview(detailPreview, offer.Template) else UI.GearPreview(detailPreview, offer.Key) end
			for _, child in detailPreview:GetChildren() do
				if child:IsA("ViewportFrame") then child.Position, child.Size, child.ZIndex = UDim2.new(), UDim2.fromScale(1, 1), 33 end
			end
		end
	end
	local function placeCard(offer: any, x: number, y: number, w: number, h: number, mode: string)
		local card = offer.Card
		card.Position, card.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
		local preview, titleLabel, description, price, action = offer.Preview, offer.TitleLabel, offer.DescriptionLabel, offer.PriceLabel, offer.Action
		if mode == "gear" then
			preview.Position, preview.Size = UDim2.fromOffset(6, 6), UDim2.fromOffset(w - 12, h - 75)
			titleLabel.Position, titleLabel.Size, titleLabel.TextSize = UDim2.fromOffset(4, h - 66), UDim2.fromOffset(w - 8, 31), if w < 150 then 12 else 15
			description.Visible = false
			price.Position, price.Size, price.TextSize = UDim2.fromOffset(4, h - 34), UDim2.fromOffset(w - 8, 28), 17
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
		local compact = width < 840 or height < 420
		local headerHeight = if compact then 58 else 70
		local navWidth = if width < 480 then 86 elseif compact then 126 else 162
		local padding, gap = if compact then 8 else 12, if compact then 8 else 12
		header.Position, header.Size = UDim2.fromOffset(6, 6), UDim2.new(1, -12, 0, headerHeight - 6)
		catalogCanvas.Position, catalogCanvas.Size = UDim2.fromOffset(6, headerHeight), UDim2.new(1, -12, 1, -headerHeight - 6)
		forgeIcon.Position = UDim2.fromOffset(14, if compact then 8 else 13)
		title.Position, title.Size, title.TextSize = UDim2.fromOffset(if width < 480 then 8 else 58, 1), UDim2.fromOffset(math.max(120, width - (if width < 480 then 74 else 126)), if compact then 30 else 39), if width < 480 then 20 elseif compact then 27 else 34
		forgeIcon.Visible = width >= 480
		subtitle.Position, subtitle.Size, subtitle.TextSize = UDim2.fromOffset(if width < 480 then 8 else 58, if compact then 30 else 40), UDim2.fromOffset(math.max(120, width - (if width < 480 then 74 else 126)), 18), if width < 480 then 11 else 14
		passHeading.Visible = false
		passHeading.Position, passHeading.Size = UDim2.fromOffset(520, 14), UDim2.fromOffset(math.max(1, width - 600), 32)
		nav.Position, nav.Size = UDim2.fromOffset(padding, headerHeight + 4), UDim2.fromOffset(navWidth - padding, height - headerHeight - padding - 4)
		local tabHeight = if compact then 48 else 65
		for index, category in NAV do
			local tab = tabs[category]
			tab.Position, tab.Size = UDim2.fromOffset(0, (index - 1) * (tabHeight + 2)), UDim2.fromOffset(navWidth - padding - 4, tabHeight)
			local icon, caption = tab:FindFirstChild("Icon") :: ImageLabel, tab:FindFirstChild("Caption") :: TextLabel
			icon.Visible = width >= 480
			icon.Position = UDim2.fromOffset(6, math.floor((tabHeight - 40) / 2))
			caption.Position, caption.Size = UDim2.fromOffset(if width < 480 then 4 else 50, 2), UDim2.new(1, if width < 480 then -8 else -54, 1, -4)
			caption.TextSize = if width < 480 then 12 elseif compact then 12 else 15
		end
		nav.CanvasSize = UDim2.fromOffset(0, #NAV * (tabHeight + 2))
		local contentX, contentY = navWidth + gap, headerHeight + 4
		local contentWidth, contentHeight = width - contentX - padding, height - contentY - padding
		local hasDetail = selectedCategory == "Weapons" or selectedCategory == "Accessories" or selectedCategory == "Owned"
		local stacked = hasDetail and (contentWidth < 370 or contentHeight < 300)
		local detailWidth = if compact then math.min(220, math.floor(contentWidth * 0.43)) else math.floor(contentWidth * 0.4)
		local gridWidth = if hasDetail and not stacked then contentWidth - detailWidth - gap else contentWidth
		scroll.Position, scroll.Size = UDim2.fromOffset(contentX, contentY), UDim2.fromOffset(gridWidth, contentHeight)
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
			tab.BackgroundColor3 = if category == selectedCategory then Color3.fromRGB(67, 229, 237) else C.Blue
			local caption = tab:FindFirstChild("Caption") :: TextLabel
			caption.TextColor3 = C.Text
			local stroke = tab:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color, stroke.Thickness = if category == selectedCategory then C.Cyan else C.Edge, if category == selectedCategory then 2.5 else 1.5 end
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
			refresh()
		end)
	end
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
