-- Production geometry at approved desktop and phone sizes. Real rendering needs Studio.
local h = require("./monster-forge-harness")()
local ui, r = h.UI, h.Roblox
local checks = 0
local function check(ok,message) assert(ok,message); checks += 1 end
local function rect(item,w,h)
 local iw,ih=item.Size.X.Scale*w+item.Size.X.Offset,item.Size.Y.Scale*h+item.Size.Y.Offset
 return {x=item.Position.X.Scale*w+item.Position.X.Offset-item.AnchorPoint.X*iw,y=item.Position.Y.Scale*h+item.Position.Y.Offset-item.AnchorPoint.Y*ih,w=iw,h=ih}
end
local function overlap(a,b) return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end
local expected={Weapons=1,Accessories=0,Gamepasses=0,["Coins & Growth"]=0,Owned=3}
for key in h.Config.WeaponStats do if h.Config.WeaponCoinPrices[key]~=nil then expected.Weapons+=1 end end -- سيف الـ VIP بيظهر في Owned بس
for _,info in h.Config.SpeedAccessories do if not info.LootOnly then expected.Accessories+=1 end end -- gear dropped by the boss only shows under Owned
for key,p in h.Config.Products do if not p.Hidden then expected[if key=="SummonBoss" then "Gamepasses" else "Coins & Growth"]+=1 end end
for key,p in h.Config.Gamepasses do if not h.Config.WeaponStats[key] and not p.Hidden then expected.Gamepasses+=1 end end
for _,v in {{1366,768},{1606,686},{750,381},{1920,1080},{320,568},{568,320},{480,320}} do
 h.Resize(v[1],v[2]); local w,ht=ui.GearFrame.Size.X.Offset,ui.GearFrame.Size.Y.Offset
 check(w<=1060 and ht<=520 and w<=v[1]-24 and ht<=v[2]-60,"Forge fits viewport and safe inset")
 check(ui.GearFrame.ZIndex==30 and ui.Gui.DisplayOrder==5,"Forge uses modal layer and existing screen order")
 check(math.abs(ui.Gui:FindFirstChildOfClass("UIScale").Scale*ui.GearFrame.NativeShopScale.Scale-1)<0.0001,"Native text and touch sizes survive HUD scaling")
 local nav,close=rect(ui.GearFrame.Categories,w,ht),rect(ui.GearFrame.CloseButton,w,ht)
 check(close.w>=44 and close.h>=44 and close.x>=0 and close.x+close.w<=w and close.y>=0 and close.y+close.h<=ht,"Close remains a visible native touch target")
 check(nav.y>=close.y+close.h and nav.y+nav.h<=ht,"Left navigation clears header")
 for _,category in {"Weapons","Accessories","Gamepasses","Coins & Growth","Owned"} do
  h.Tab(category); local body=rect(ui.GearScroll,w,ht)
  check(body.x>=nav.x+nav.w and body.h>=100 and body.x+body.w<=w and body.y+body.h<=ht,"Catalog stays in shell")
  local visible={}
  for _,card in ui.GearScroll:GetChildren() do
   if card:IsA("Frame") and card.Visible and card.Name:sub(-4)=="Card" then
    local b=rect(card,body.w,body.h)
    check(b.x>=0 and b.x+b.w<=body.w-4 and b.y>=0 and b.y+b.h<=ui.GearScroll.CanvasSize.Y.Offset,"Card fits scroll canvas")
    for _,other in visible do check(not overlap(b,other),"Cards do not overlap") end
    table.insert(visible,b)
    local a=rect(card.BuyButton,b.w,b.h)
    check(a.w>=44 and a.h>=44 and a.x>=0 and a.y>=0 and a.x+a.w<=b.w and a.y+a.h<=b.h,"Every offer retains a native touch target")
    for _,name in {"Preview","Title","Description","Price"} do
     local item=card:FindFirstChild(name)
     if item.Visible then local q=rect(item,b.w,b.h); check(q.x>=0 and q.y>=0 and q.x+q.w<=b.w and q.y+q.h<=b.h,"Offer art and copy fit inside card") end
    end
   end
  end
  check(#visible==expected[category],"Configured offers retained: "..category)
  local tab=ui.GearFrame.Categories:FindFirstChild(category.."Tab")
  check(tab.Size.X.Offset>=44 and tab.Size.Y.Offset>=44,"Native left navigation targets")
  if category=="Gamepasses" and w>=840 and ht>=420 then
   check(ui.GearScroll.ScrollBarThickness==0 and ui.GearScroll.CanvasSize.Y.Offset==body.h,"Desktop passes fit without scrolling")
   check(h.Card("DoubleDamage").Position.Y.Offset==h.Card("VIP").Position.Y.Offset and h.Card("DoubleDamage").Size.X.Offset>h.Card("AutoCollect").Size.X.Offset,"Two featured passes above four smaller cards")
  end
  local detail=h.Detail()
  if detail.Visible then
   local d=rect(detail,if detail.Parent==ui.GearScroll then body.w else w,if detail.Parent==ui.GearScroll then body.h else ht)
   local a=rect(detail.BuyButton,d.w,d.h)
   check(a.w>=44 and a.h==44 and a.y+a.h<=d.h,"Selected purchase action retains native target")
   local regions={}
   for _,name in {"SelectedLabel","Title","Stats","Preview","Price","BuyButton","CollectionNote"} do
    local item=detail:FindFirstChild(name)
    if item.Visible then
     local q=rect(item,d.w,d.h)
     check(q.x>=0 and q.y>=0 and q.x+q.w<=d.w and q.y+q.h<=d.h,"Selected detail content fits its panel")
     for _,other in regions do check(not overlap(q,other),"Selected preview, stats, price and action never overlap") end
     table.insert(regions,q)
    end
   end
   if detail.Parent~=ui.GearScroll then check(not overlap(body,d) and d.x+d.w<=w and d.y+d.h<=ht,"Selected detail remains beside catalog") end
  end
 end
end
print(string.format("PASS: %d Monster Forge responsive geometry checks",checks))
