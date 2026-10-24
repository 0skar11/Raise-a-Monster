-- Run from repo root with Lune. Does not read or rewrite the user's place file.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local environment = setmetatable({}, { __index = getfenv() })
for key, value in roblox do environment[key] = value end
local function load(path)
	return luau.load(fs.readFile(path), { environment = environment, debugName = path })()
end
local config = load("src/shared/HalloweenPortalConfig.luau")
local pumpkin = load("src/shared/PumpkinVisual.luau")
environment.script = { Parent = { PumpkinVisual = "PumpkinVisual" } }
environment.require = function(key)
	assert(key == "PumpkinVisual", "Unexpected builder dependency")
	return pumpkin
end
local builder = load("src/shared/HalloweenPortalBuilder.luau")
local model = builder.Build(config.Origin)
-- Lune emits modern TextureContent; pinned Rojo 7.4 expects legacy Texture URLs.
local xml = roblox.serializeModel({ model }, true)
xml = xml:gsub('(<Item class="SpecialMesh".-</Item>)', function(item)
	item = item:gsub('<Content name="MeshContent">%s*<uri>(.-)</uri>%s*</Content>', '<Content name="MeshId"><url>%1</url></Content>')
	return item:gsub('<Content name="TextureContent">%s*<uri>(.-)</uri>%s*</Content>', '<Content name="TextureId"><url>%1</url></Content>')
end)
xml = xml:gsub('<Content name="TextureContent">%s*<uri>(.-)</uri>%s*</Content>', '<Content name="Texture"><url>%1</url></Content>')
assert(not xml:find("<uri>"), "Unconverted Content property")
fs.writeFile("assets/HalloweenPortal.rbxmx", xml)
print("PASS: exported HalloweenPortal with " .. #model:GetDescendants() .. " descendants")
