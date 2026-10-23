-- Production selection, state, purchase routing, dynamic pricing and Adult chooser.
local create=require("./monster-forge-harness")
local h=create()
local checks=0
local function check(ok,message) assert(ok,message); checks+=1 end
local function called(name,key) local call=h.Last(); return call and call.Name==name and call.Args[1]==key end
local function unmodulatedCards()
	for _,card in h.UI.GearScroll:GetChildren() do
		if card:IsA("Frame") and card.Name:sub(-4)=="Card" and card.BackgroundColor3~=h.Roblox.Color3.new(1,1,1) then return false end
	end
	return true
end
local function hasGradient(key,top,bottom)
	local gradient=h.Card(key):FindFirstChildOfClass("UIGradient")
	local points=if gradient then gradient.Color.Keypoints else {}
	return gradient and gradient.Rotation==90 and #points==2 and points[1].Value==h.Roblox.Color3.fromRGB(table.unpack(top)) and points[2].Value==h.Roblox.Color3.fromRGB(table.unpack(bottom))
end
check(unmodulatedCards(),"White card bases preserve gradient colors without multiplying them into black")
check(hasGradient("Bat",{24,37,45},{7,15,20}),"Ordinary cards retain the intended dark blue gradient")
check(hasGradient("DoubleDamage",{74,10,10},{25,8,9}),"Featured damage card retains its red gradient")
check(hasGradient("VIP",{70,39,10},{24,16,8}),"Featured VIP card retains its warm gold gradient")
check(h.Card("Bat").Preview:FindFirstChild("WeaponPreview")~=nil,"Weapon cards use actual native 3D preview class")
check(h.Detail().Stats.Primary.Text=="x40\nweapon damage" and h.Detail().Stats.Secondary.Text=="+2.5\nreach","Hero uses actual configured weapon stats")
check(h.Card("IronSword").Price.Text=="EQUIPPED" and h.Card("Bat").Price.Text=="OWNED","Equipped and owned states remain distinct")
check(h.Card("IceSword").Price.Text=="26,000 COINS" and h.Card("LavaSword").Price.Text=="104,000 COINS","Current coin prices remain exact")
h.Select("Bat"); check(#h.Calls==0 and h.Detail().Title.Text=="Bat","Selecting a card updates hero without purchasing")
h.Action(); check(called("EquipWeapon","Bat"),"Starter equips through original remote")
h.Flush(); h.Select("IronSword"); local count=#h.Calls; h.Action(); check(#h.Calls==count and h.Detail().BuyButton.Text=="EQUIPPED","Equipped weapon sends no redundant request")
h.Select("LavaSword"); h.Action(); check(called("BuyWeapon","LavaSword"),"Unowned weapon retains coin purchase remote")
count=#h.Calls; h.Action(); check(#h.Calls==count and h.Detail().BuyButton.Text=="PLEASE WAIT...","Pending request suppresses repeat activation")
h.State.Weapons.LavaSword=true; h.State.EquippedWeapon="LavaSword"; h.Flush(); h.Refresh()
check(h.Detail().BuyButton.Text=="EQUIPPED" and h.Card("LavaSword").Price.Text=="EQUIPPED","Server state refresh updates both hero and card")
h.Tab("Accessories"); h.Select("SwiftSneakers"); h.Action(); check(called("EquipSpeedAccessory","SwiftSneakers"),"Owned accessory equips without purchasing")
h.State.EquippedSpeedAccessory="SwiftSneakers"; h.Flush(); h.Action(); check(called("EquipSpeedAccessory",nil) and h.Last().Args.n==1,"Accessory unequip preserves explicit nil argument")
h.Flush(); h.Select("ShadowCloak"); h.Action(); check(called("BuySpeedAccessory","ShadowCloak"),"Unowned accessory keeps coin purchase route")
h.Tab("Owned"); check(h.Card("Bat").Visible and h.Card("SwiftSneakers").Visible and not h.Card("ShadowCloak").Visible,"Owned category filters current gear")
h.State.SpeedAccessories.ShadowCloak=true; h.Refresh(); check(h.Card("ShadowCloak").Visible,"Owned category reacts to purchase state")
h.Tab("Gamepasses"); h.Card("AutoFeeder").BuyButton.Activated:Fire(); check(called("BuyPass","AutoFeeder"),"Permanent pass keeps server purchase flow")
h.State.Passes.AutoFeeder=true; h.Flush(); h.Refresh(); count=#h.Calls; h.Card("AutoFeeder").BuyButton.Activated:Fire()
check(h.Card("AutoFeeder").BuyButton.Text=="OWNED" and not h.Card("AutoFeeder").BuyButton.Active and #h.Calls==count,"Confirmed pass ownership prevents duplicate purchases")
check(unmodulatedCards(),"Ownership and category refresh preserve the unmodulated card background")
h.Tab("Coins & Growth"); h.Card("Coins1000").BuyButton.Activated:Fire(); check(called("BuyProduct","Coins1000"),"Coin pack retains product purchase route")
h.Flush(); h.Card("Coins1000").BuyButton.Activated:Fire(); check(called("BuyProduct","Coins1000"),"Coin packs remain repeatable")
count=#h.Calls; h.Card("InstantHatch").BuyButton.Activated:Fire(); check(#h.Calls==count and h.Card("InstantHatch").BuyButton.Text=="COMING SOON" and not h.Card("InstantHatch").BuyButton.Active,"Unconfigured live offers stay unavailable")
local adult=25; for _,stage in h.Config.Stages do if stage.Name=="Adult" then adult=stage.MinLevel end end
h.State.Monsters={{Id="eligible",DisplayName="Sprout",Rarity="Common",Level=adult-1,Production=1,Available=true},{Id="carried",DisplayName="Carried",Rarity="Common",Level=1,Available=true,Carried=true},{Id="adult",Level=adult,Available=true}}
h.Refresh(); check(h.Card("SkipToAdultAll").Description.Text:find("1 current monster",1,true),"Growth scope reflects only current eligible monsters")
h.Card("SkipToAdultOne").BuyButton.Activated:Fire(); local chooser=h.UI.Gui:FindFirstChild("SkipToAdultChooser")
check(chooser and chooser.Visible and chooser.Monsters:FindFirstChild("eligible") and not chooser.Monsters:FindFirstChild("carried") and not chooser.Monsters:FindFirstChild("adult"),"Single growth retains eligible-monster chooser")
chooser.Monsters.eligible.Activated:Fire(); check(called("BuyProduct","SkipToAdultOne") and h.Last().Args[2]=="eligible" and h.UI.GearFrame.Visible,"Chooser retains explicit monster ID and returns to forge")
h.Flush(); h.Card("SkipToAdultAll").BuyButton.Activated:Fire(); check(called("BuyProduct","SkipToAdultAll"),"All-growth retains original purchase flow")
h.UI.GearFrame.CloseButton.Activated:Fire(); check(not h.UI.GearFrame.Visible,"Native close control closes modal")
local market=create({Market=function(id) return {PriceInRobux=if id==2052905177 then 245 else 88,IsForSale=true} end})
check(market.Card("DoubleDamage").BuyButton.Text=="CHECKING PRICE...","Marketplace price lookup exposes loading state")
market.Fetch(); check(market.Card("DoubleDamage").BuyButton.Text=="R$ 245" and market.Card("Coins1000").BuyButton.Text=="R$ 88","Real Marketplace pass/product prices replace configured fallback")
local failed=create({Market=function() error("offline fixture") end}); failed.Fetch()
check(failed.Card("DoubleDamage").BuyButton.Text=="R$ 299" and failed.Card("DoubleDamage").BuyButton.Active,"Transient lookup failure retains configured offer")
local unavailable=create({Market=function() return {IsForSale=false} end}); unavailable.Fetch(); unavailable.Card("DoubleDamage").BuyButton.Activated:Fire()
check(unavailable.Card("DoubleDamage").BuyButton.Text=="UNAVAILABLE" and not unavailable.Card("DoubleDamage").BuyButton.Active and #unavailable.Calls==0,"Unavailable Marketplace offers cannot send purchase requests")
local studio=create({Studio=true}); studio.Card("InstantHatch").BuyButton.Activated:Fire(); check(studio.Last().Name=="BuyProduct" and studio.Last().Args[1]=="InstantHatch","Studio free test keeps explicit original route")
print(string.format("PASS: %d Monster Forge selection, state, purchase, pricing and growth checks",checks))
