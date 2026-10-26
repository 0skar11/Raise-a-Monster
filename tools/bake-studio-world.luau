-- Run with Lune from the project root. Executes only map construction, not gameplay.
local fs = require('@lune/fs')
local r = require('@lune/roblox')
local luau = require('@lune/luau')
local process = require('@lune/process')
local game = r.deserializePlace(fs.readFile(process.args[1]))
-- Build in an empty workspace so an older preview/runtime map cannot duplicate
-- the generated floor. Editable rigs are read from a clone and never rewritten.
local sourceWorkspace = game:GetService('Workspace')
-- Lune 0.11 does not keep imported PrimaryPart refs reliably; the rigs' pivot is always their HumanoidRootPart.
for _, item in game:GetDescendants() do
 if item:IsA('Model') then
  local root = item:FindFirstChild('HumanoidRootPart', true)
  if root and root:IsA('BasePart') then item.PrimaryPart = root end
 end
end
local workspace = r.Instance.new('Workspace')
local authoredRigs = sourceWorkspace:FindFirstChild('AnimationRigs')
if authoredRigs then authoredRigs:Clone().Parent = workspace end
local signal = { Connect = function() return { Disconnect = function() end } end }
r.implementMethod('CollectionService', 'GetTagged', function() return {} end)
r.implementMethod('CollectionService', 'GetInstanceAddedSignal', function() return signal end)
r.implementProperty('BasePart', 'Touched', function() return signal end)
r.implementProperty('ProximityPrompt', 'Triggered', function() return signal end)
local function parts(model)
 local result = {}
 for _, item in model:GetDescendants() do if item:IsA('BasePart') then table.insert(result,item) end end
 return result
end
-- Lune 0.11 can resolve a cloned model's PrimaryPart to an unrelated instance, so only trust a real BasePart inside the model.
local function pivotPart(model)
 local primary=model.PrimaryPart
 if primary and primary:IsA('BasePart') and primary:IsDescendantOf(model) then return primary end
 return model:FindFirstChild('HumanoidRootPart',true) or parts(model)[1]
end
r.implementMethod('Model','GetPivot',function(model) local part=pivotPart(model) return part and part.CFrame or r.CFrame.new() end)
r.implementMethod('Model','PivotTo',function(model, target)
 local old = model:GetPivot()
 for _, part in parts(model) do part.CFrame = target * old:ToObjectSpace(part.CFrame) end
end)
r.implementMethod('Model','ScaleTo',function(model, scale)
 local origin=model:GetPivot()
 for _, part in parts(model) do
  local cf=origin:ToObjectSpace(part.CFrame)
  part.Size *= scale
  part.CFrame=origin * r.CFrame.new(cf.Position * scale) * cf.Rotation
 end
 for _, joint in model:GetDescendants() do
  if joint:IsA('Motor6D') or joint:IsA('Weld') then
   joint.C0=r.CFrame.new(joint.C0.Position*scale)*joint.C0.Rotation
   joint.C1=r.CFrame.new(joint.C1.Position*scale)*joint.C1.Rotation
  end
 end
end)
r.implementMethod('Model','GetExtentsSize',function(model)
 local low=r.Vector3.new(math.huge,math.huge,math.huge)
 local high=-low
 for _, p in parts(model) do
  for _, x in {-0.5,0.5} do for _, y in {-0.5,0.5} do for _, z in {-0.5,0.5} do
   local v=p.CFrame:PointToWorldSpace(p.Size*r.Vector3.new(x,y,z))
   low=r.Vector3.new(math.min(low.X,v.X),math.min(low.Y,v.Y),math.min(low.Z,v.Z))
   high=r.Vector3.new(math.max(high.X,v.X),math.max(high.Y,v.Y),math.max(high.Z,v.Z))
  end end end
 end
 return high-low
end)
local cache={}
local stubs={ MonsterService={}, CarryService={}, MonsterAttack={}, CombatService={Register=function() return {} end,Unregister=function() end} }
local globals=getfenv()
local offlineCFrame=table.clone(r.CFrame)
offlineCFrame.lookAt=function(position,target,up)
 local back=position-target
 if back.Magnitude<1e-8 then return r.CFrame.new(position) end
 back=back.Unit
 local right=(up or r.Vector3.new(0,1,0)):Cross(back)
 if right.Magnitude<1e-8 then right=r.Vector3.new(1,0,0):Cross(back) end
 right=right.Unit
 return r.CFrame.fromMatrix(position,right,back:Cross(right),back)
end
local function loadModule(item)
 if cache[item] then return cache[item] end
 if stubs[item.Name] then return stubs[item.Name] end
 local env=setmetatable({game=game,workspace=workspace,script=item,require=loadModule,CFrame=offlineCFrame,
  task={spawn=function() end,delay=function() end,wait=function() end},
  Random={new=function(seed)
   local state=seed or 12345
   return {NextNumber=function(_, a,b) state=(state*48271)%2147483647; local n=state/2147483647; return (a or 0)+n*((b or 1)-(a or 0)) end}
  end}}, {__index=function(_,key) return r[key] or globals[key] end})
 for key,value in r do if rawget(env,key)==nil then rawset(env,key,value) end end
 for _,key in {'math','string','table','os','pairs','ipairs','type','typeof','tostring','tonumber','assert','error','warn','print','next','select','unpack'} do env[key]=globals[key] end
 local fn=luau.load(item.Source,{environment=env,debugName=item.Name})
 cache[item]=fn()
 if item.Name=='Build' then
  local makePart=cache[item].MakePart
  cache[item].MakePart=function(props)
   if props.Position and not props.CFrame then
    local translated=table.clone(props)
    translated.CFrame=r.CFrame.new(props.Position)
    translated.Position=nil
    return makePart(translated)
   end
   return makePart(props)
  end
 end
 return cache[item]
end
local server=game:GetService('ServerScriptService').Server
local plotService=loadModule(server.PlotService)
local zoneService=loadModule(server.ZoneService)
local config=loadModule(game:GetService('ReplicatedStorage').Shared.Config)
plotService.Init()
zoneService.Init()
loadModule(server.TerrainService).Init()
local world=r.Instance.new('Folder'); world.Name='StudioWorld'; world.Parent=workspace
workspace.Map.Parent=world; workspace.Zones.Parent=world; workspace.MapBorder.Parent=world
world:SetAttribute('GeneratedPreview',true)

local function near(actual,expected,label)
 assert((actual-expected).Magnitude<0.001,label..' differs from the runtime layout')
end
local function bounds(part)
 local low=r.Vector3.new(math.huge,math.huge,math.huge)
 local high=-low
 for _,x in {-0.5,0.5} do for _,y in {-0.5,0.5} do for _,z in {-0.5,0.5} do
  local point=part.CFrame:PointToWorldSpace(part.Size*r.Vector3.new(x,y,z))
  low=r.Vector3.new(math.min(low.X,point.X),math.min(low.Y,point.Y),math.min(low.Z,point.Z))
  high=r.Vector3.new(math.max(high.X,point.X),math.max(high.Y,point.Y),math.max(high.Z,point.Z))
 end end end
 return low,high
end
local function solidFloor(part,position,size)
 assert(part and part:IsA('BasePart') and part.Anchored and part.CanCollide,'Missing solid floor')
 near(part.CFrame.Position,position,part:GetFullName()..' position')
 near(part.Size,size,part:GetFullName()..' size')
 near(part.CFrame.UpVector,r.Vector3.new(0,1,0),part:GetFullName()..' orientation')
end
local floor=world.Map.Ground
solidFloor(floor,r.Vector3.new((plotService.IslandMinX+plotService.LobbyMaxX)/2,-1,(plotService.PlazaHalfZ+config.Map.IslandMinZ)/2),
 r.Vector3.new(plotService.LobbyMaxX-plotService.IslandMinX,2,plotService.PlazaHalfZ-config.Map.IslandMinZ))
solidFloor(world.Map.Plaza,r.Vector3.new((config.Map.PlazaMinX+config.Map.PlazaMaxX)/2,0.1,0),
 r.Vector3.new(config.Map.PlazaMaxX-config.Map.PlazaMinX,0.2,404))
solidFloor(world.Map.ZoneConnector,r.Vector3.new((plotService.LobbyMaxX+plotService.ZonesStartX)/2,-1,0),
 r.Vector3.new(plotService.ZonesStartX-plotService.LobbyMaxX,2,zoneService.ZoneHalfZ*2))
solidFloor(world.Map.NorthPlotPath,r.Vector3.new(0,0.1,-236),r.Vector3.new(20,0.2,68))
solidFloor(world.Map.SouthPlotPath,r.Vector3.new(0,0.1,236),r.Vector3.new(20,0.2,68))
local plots=plotService.GetPlots()
assert(#plots==10 and #plots==config.MaxPlots,'Expected six original and four additional plots')
for index,plot in plots do
 local position=plot.CFrame.Position
 if index<=6 then
  near(position,r.Vector3.new(-40,0,(index-3.5)*68),'Original plot position')
 else
  near(position,r.Vector3.new(if index%2==1 then -40 else 40,0,if index<=8 then -238 else 238),'Additional plot position')
  near(plot.CFrame.LookVector,r.Vector3.new(if index%2==1 then 1 else -1,0,0),'Additional plot faces access lane')
 end
 local low,high=bounds(plot.Model.Floor)
 assert(low.X>=config.Map.IslandMinX and high.X<=config.Map.LobbyMaxX and low.Z>=config.Map.IslandMinZ and high.Z<=config.Map.PlazaHalfZ,'Unsupported plot floor')
 for otherIndex=1,index-1 do
  local otherLow,otherHigh=bounds(plots[otherIndex].Model.Floor)
  assert(not (high.X>otherLow.X+0.001 and low.X<otherHigh.X-0.001 and high.Z>otherLow.Z+0.001 and low.Z<otherHigh.Z-0.001),'Plot floors overlap')
 end
end
near(world.Map.CenterSpawn.CFrame.Position,config.Map.SpawnPosition,'CenterSpawn position')
local counter=world.Map.EggShop.Counter
near(counter.CFrame.Position,config.Shop.Position+r.Vector3.new(0,2,0),'Gear Shop position')
local shopPrompt=counter:FindFirstChild('ShopPrompt')
assert(shopPrompt and shopPrompt:IsA('ProximityPrompt'),'Missing Gear Shop prompt')
local counterLow,counterHigh=bounds(counter)
assert(counterLow.X>=config.Map.PlazaMinX and counterHigh.X<=config.Map.PlazaMaxX
 and counterLow.Z>=-zoneService.ZoneHalfZ and counterHigh.Z<=zoneService.ZoneHalfZ,
 'Gear Shop is unsupported by the compact plaza')
local zoneLength=(zoneService.ZonesEndX-plotService.ZonesStartX)/#config.Zones
local nestCount,motherCount=0,0
local shopMotherDistance,teleportMotherDistance=math.huge,math.huge
for index,zone in config.Zones do
 local folder=world.Zones:FindFirstChild('Zone'..index..'_'..zone.Name)
 assert(folder,'Missing monster zone')
 local x0=plotService.ZonesStartX+(index-1)*zoneLength
 solidFloor(folder.Ground,r.Vector3.new(x0+zoneLength/2,-1,0),r.Vector3.new(zoneLength,2,zoneService.ZoneHalfZ*2))
 solidFloor(folder.Road,r.Vector3.new(x0+zoneLength/2,0.1,0),r.Vector3.new(zoneLength,0.2,config.Map.RoadWidth))
 local nestIndex=0
 for _,item in folder:GetChildren() do
  if item:IsA('BasePart') and item.Name=='Nest' then
   nestIndex+=1;nestCount+=1
   near(item.CFrame.Position,r.Vector3.new(x0+zoneLength*nestIndex/(config.NestsPerZone+1),config.Map.NestTop/2,
    if nestIndex%2==1 then -config.Map.NestZ else config.Map.NestZ),'Nest position')
   local low,high=bounds(item)
   assert(low.X>=x0-0.001 and high.X<=x0+zoneLength+0.001 and low.Z>=-zoneService.ZoneHalfZ and high.Z<=zoneService.ZoneHalfZ,
    'Nest is unsupported by its zone ground')
   assert(math.abs(low.Y)<0.001,'Nest does not rest on the ground')
  elseif item:IsA('Folder') and string.match(item.Name,'^Nest%d+$') then
   local mother=item:FindFirstChild('Mother')
   assert(mother and mother:IsA('Model') and mother.PrimaryPart,'Missing mother spawn')
   motherCount+=1
   local number=tonumber(string.match(item.Name,'%d+'))
   local expected=r.Vector3.new(x0+zoneLength*number/(config.NestsPerZone+1),0,
    if number%2==1 then -config.Map.NestZ else config.Map.NestZ)
   local position=mother.PrimaryPart.CFrame.Position
   near(r.Vector3.new(position.X,0,position.Z),expected,'Mother spawn position')
   local shopPosition=counter.CFrame.Position
   local teleportPosition=plotService.ShopTeleportCFrame.Position
   shopMotherDistance=math.min(shopMotherDistance,(expected-r.Vector3.new(shopPosition.X,0,shopPosition.Z)).Magnitude)
   teleportMotherDistance=math.min(teleportMotherDistance,(expected-r.Vector3.new(teleportPosition.X,0,teleportPosition.Z)).Magnitude)
   assert(mother.PrimaryPart.CFrame.LookVector:Dot(r.Vector3.new(0,0,if expected.Z<0 then 1 else -1))>0.999,
    'Mother faces away from the road')
  end
 end
 assert(nestIndex==config.NestsPerZone,'Incorrect nest count')
end
local function overlaps(low,high,minX,maxX,minZ,maxZ)
 return high.X>minX+0.001 and low.X<maxX-0.001 and high.Z>minZ+0.001 and low.Z<maxZ-0.001
end
local borderCount=0
for _,part in world.MapBorder:GetDescendants() do if part:IsA('BasePart') then
 borderCount+=1
 local low,high=bounds(part)
 assert(not overlaps(low,high,plotService.IslandMinX,plotService.LobbyMaxX,config.Map.IslandMinZ,plotService.PlazaHalfZ)
  and not overlaps(low,high,plotService.LobbyMaxX,zoneService.ZonesEndX,-zoneService.ZoneHalfZ,zoneService.ZoneHalfZ),
  'Map border enters playable ground: '..part.Name)
end end
assert(#world:GetChildren()==3,'Generated world has duplicate folders')
assert(motherCount==#config.Zones*config.NestsPerZone,'Incorrect mother count')
assert(shopMotherDistance>config.Combat.MotherLeashRange,'Gear Shop counter is inside a mother leash')
assert(teleportMotherDistance>config.Combat.MotherLeashRange,'Gear Shop teleport is inside a mother leash')
-- The old code-made Gear Shop stall was deleted on purpose (the authored Blacksmith stand replaces it at runtime):
-- it is checked above but must not come back into the saved preview.
local oldShop=world.Map:FindFirstChild('EggShop'); if oldShop then oldShop:Destroy() end
local serialized=r.serializeModel({world},true)
local savedWorld=r.deserializeModel(serialized)[1]
assert(savedWorld:GetAttribute('GeneratedPreview')==true
 and typeof(savedWorld:GetAttribute('GeneratedPreview'))=='boolean','GeneratedPreview does not roundtrip as Boolean true')
assert(not savedWorld.Map:FindFirstChild('EggShop'),'The deleted Gear Shop stall came back into the preview')
fs.writeFile('assets/StudioWorld.rbxmx',serialized)
print('Baked map instances:',#world:GetDescendants(),'Solid ground sections:',#config.Zones+1,
 'Supported nests:',nestCount,'Mothers facing road:',motherCount,'External border parts:',borderCount,
 'Counter-to-mother clearance:',shopMotherDistance,'Teleport-to-mother clearance:',teleportMotherDistance,
 'GeneratedPreview Boolean true; animation rig assets preserved')
