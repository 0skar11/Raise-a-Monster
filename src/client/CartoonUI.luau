--!strict
-- Each illustration is an independent uploaded RGBA image. No runtime sprite crops.
local CartoonUI = {}
CartoonUI.Assets = {
	Sky = "rbxassetid://95952111765124",
	Icons = {
		Weapons = "rbxassetid://83324511337603",
		Accessories = "rbxassetid://76885772559439",
		Gamepasses = "rbxassetid://91791153101566",
		CoinsGrowth = "rbxassetid://86257523657285",
		Owned = "rbxassetid://130528843882315",
		DoubleDamage = "rbxassetid://91544825521506",
		AutoCollect = "rbxassetid://103631885104652",
		ExtraSlots = "rbxassetid://93012774470979",
		AutoFeeder = "rbxassetid://113469284695646",
		AutoMinigame = "rbxassetid://117105800307011",
		MonsterCollector = "rbxassetid://80146879973486",
		SummonBoss = "rbxassetid://121176065094437",
		Coins = "rbxassetid://99594259285286",
		Candy = "rbxassetid://138080979842713",
		MythicEgg = "rbxassetid://111945754832151",
		RareEgg = "rbxassetid://87200577180813",
		LuckyEgg = "rbxassetid://83181361478581",
		Gift = "rbxassetid://122162399784475",
		Health = "rbxassetid://94471696324059",
		Speed = "rbxassetid://139358419958122",
	},
}
local ALIASES: { [string]: string } = {
	VIP = "Gamepasses", Forge = "Weapons", ["Coins & Growth"] = "CoinsGrowth",
	AutoCollectBabies = "MonsterCollector", InstantHatch = "ExtraSlots",
	SpeedBoost = "Speed", SkipToAdultOne = "LuckyEgg", SkipToAdultAll = "MonsterCollector",
}
function CartoonUI.Icon(parent: Instance, key: string, size: number): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = key .. "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(size, size)
	icon.Image = (CartoonUI.Assets.Icons :: { [string]: string })[ALIASES[key] or key] or CartoonUI.Assets.Icons.Gift
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	icon.Active, icon.Selectable = false, false
	icon.Parent = parent
	return icon
end
function CartoonUI.ApplyBackdrop(parent: GuiObject): ImageLabel
	local sky = Instance.new("ImageLabel")
	sky.Name = "CartoonSkyBackdrop"
	sky.BackgroundTransparency = 1
	sky.BorderSizePixel = 0
	sky.Size = UDim2.fromScale(1, 1)
	sky.Image = CartoonUI.Assets.Sky
	sky.ScaleType = Enum.ScaleType.Crop
	sky.ZIndex = parent.ZIndex
	sky.Active, sky.Selectable = false, false
	sky.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = sky
	return sky
end
CartoonUI.DecorateShell = CartoonUI.ApplyBackdrop
return CartoonUI
