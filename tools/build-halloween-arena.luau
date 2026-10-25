-- Deterministic standalone arena export; does not modify the user's place file.
local fs=require("@lune/fs")
local roblox=require("@lune/roblox")
local luau=require("@lune/luau")
local env=setmetatable({}, {__index=getfenv()})
for k,v in roblox do env[k]=v end
local function load(path) return luau.load(fs.readFile(path),{environment=env,debugName=path})() end
local pumpkin=load("src/shared/PumpkinVisual.luau")
local dependencies={PumpkinVisual=pumpkin}
env.script={Parent={PumpkinVisual="PumpkinVisual",HalloweenPortalBuilder="HalloweenPortalBuilder"}}
env.require=function(name) return assert(dependencies[name],"Unexpected dependency "..tostring(name)) end
dependencies.HalloweenPortalBuilder=load("src/shared/HalloweenPortalBuilder.luau")
local builder=load("src/shared/HalloweenArenaBuilder.luau")
local config={Origin=roblox.CFrame.new(1600,.2,0),CombatRadius=90,Capacity=6,ArrivalCenter=roblox.Vector3.new(0,0,120),ArrivalSize=roblox.Vector3.new(40,1,30),ConnectorWidth=24,ReturnPortalOrigin=roblox.CFrame.new(1600,.2,137)}
if fs.isFile("src/shared/HalloweenArenaConfig.luau") then
	-- Config depends on the game config for the six authored tycoon positions.
	local gameConfig=load("src/shared/Config.luau")
	dependencies.Config=gameConfig
	env.script.Parent.Config="Config"
	config=load("src/shared/HalloweenArenaConfig.luau")
end
local model=builder.Build(config)
local xml=roblox.serializeModel({model},true)
xml=xml:gsub('(<Item class="SpecialMesh".-</Item>)',function(item)
	item=item:gsub('<Content name="MeshContent">%s*<uri>(.-)</uri>%s*</Content>','<Content name="MeshId"><url>%1</url></Content>')
	return item:gsub('<Content name="TextureContent">%s*<uri>(.-)</uri>%s*</Content>','<Content name="TextureId"><url>%1</url></Content>')
end)
xml=xml:gsub('<Content name="TextureContent">%s*<uri>(.-)</uri>%s*</Content>','<Content name="Texture"><url>%1</url></Content>')
assert(not xml:find("<uri>"),"Unconverted Content property")
fs.writeFile("assets/HalloweenArena.rbxmx",xml)
print("PASS: exported HalloweenArena with "..#model:GetDescendants().." descendants")
