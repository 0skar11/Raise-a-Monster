local fs = require('@lune/fs')
local r = require('@lune/roblox')
local luau = require('@lune/luau')
local workspace = r.Instance.new('Workspace')
local globals = getfenv()
local function env(extra)
 local e = setmetatable(extra or {}, {__index=function(_,k) return r[k] or globals[k] end})
 for k,v in r do if rawget(e,k) == nil then rawset(e,k,v) end end
 for _,k in {'math','string','table','os','pairs','ipairs','type','typeof','tostring','tonumber','assert','error','warn','print','next','select','unpack'} do e[k]=globals[k] end
 return e
end
local config = luau.load(fs.readFile('src/shared/Config.luau'), {environment=env()})()
local Build = {MakePart=function(props)
 local part = r.Instance.new('Part')
 part.Anchored = true
 for k,v in props do if k ~= 'Parent' then
  if k == 'Position' then part.CFrame=r.CFrame.new(v) else part[k]=v end
 end end
 part.Parent=props.Parent
 return part
end}
local map=config.Map
local modules={Config=config,Build=Build,
 PlotService={IslandMinX=map.IslandMinX,ZonesStartX=map.ZonesStartX,PlazaHalfZ=map.PlazaHalfZ},
 ZoneService={ZonesEndX=map.ZonesStartX+#config.Zones*map.ZoneLength,ZoneHalfZ=map.ZoneHalfZ}}
local terrain = luau.load(fs.readFile('src/server/TerrainService.luau'),{environment=env({workspace=workspace,game={GetService=function() return {Shared={Config='Config'}} end},script={Parent={Build='Build',PlotService='PlotService',ZoneService='ZoneService'}},require=function(key) return assert(modules[key],key) end})})()
terrain.Init()
local raw=fs.readFile('assets/StudioWorld.rbxmx'):gsub('^<%?xml.-%?>%s*','')
local world=r.deserializeModel(raw)[1]
local old=world:FindFirstChild('MapBorder');if old then old:Destroy() end
workspace.MapBorder.Parent=world
fs.writeFile('assets/StudioWorld.rbxmx',r.serializeModel({world},true))
print('Baked approved wall preview:',#world.MapBorder:GetDescendants(),'instances')

