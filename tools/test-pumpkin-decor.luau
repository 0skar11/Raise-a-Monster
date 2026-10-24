-- Offline conversion checks for natural pumpkins under HalloweenWorld.Props.
local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local checks = 0
-- Roblox Vector3/CFrame values use single precision; tolerate sub-millistud rounding.
local GEOMETRY_EPSILON = 1e-4
local function check(value, message)
	assert(value, message)
	checks += 1
end

r.implementMethod("Model", "GetPivot", function(model)
	return model.WorldPivot
end)

local environment = table.clone(getfenv())
for key, value in r do
	environment[key] = value
end
local PumpkinVisual = luau.load(fs.readFile("src/shared/PumpkinVisual.luau"), { environment = environment })()
environment.game = { GetService = function() return { Shared = { PumpkinVisual = "PumpkinVisual" } } end }
environment.require = function(key) assert(key == "PumpkinVisual"); return PumpkinVisual end
local PumpkinDecor = luau.load(fs.readFile("src/server/PumpkinDecor.luau"), { environment = environment, injectGlobals = true })()

local function part(parent, name, className)
	local item = r.Instance.new(className or "Part")
	item.Name = name
	item.Parent = parent
	return item
end

local ornaments = { "Rib", "RibPart", "Stem", "StemTip", "Eye", "Mouth", "Zig", "Tooth", "MouthCorner", "Nose" }
-- Lune stores numeric attributes at native precision; compare the same property roundtrip.
local sourceReference = r.Instance.new("Folder")
sourceReference:SetAttribute("SourceAssetId", 1051236676)
local expectedSourceAssetId = sourceReference:GetAttribute("SourceAssetId")
sourceReference:Destroy()
local props = r.Instance.new("Folder")
props.Name = "Props"
local lanterns = r.Instance.new("Folder")
lanterns.Name = "JackOLanterns"
lanterns.Parent = props
local patches = r.Instance.new("Folder")
patches.Name = "PumpkinPatches"
patches.Parent = props
local patchFolder = r.Instance.new("Folder")
patchFolder.Name = "Patch_1"
patchFolder.Parent = patches

local expected = {}
local function addLeaf(parent, modelName, index)
	local model = r.Instance.new("Model")
	model.Name = modelName
	model.Parent = parent
	local oldSize = r.Vector3.new(3.67, 3.11, 3.67)
	local oldCFrame = r.CFrame.new(index * 5, 7, -index * 2) * r.CFrame.Angles(0, index * 0.17, 0)
	local pivot = r.CFrame.new(index * 4, 9, -index) * r.CFrame.Angles(0, index * 0.03, 0)
	model.WorldPivot = pivot
	local body = part(model, if modelName == "FlatPumpkin" then "Pumpkin" else "PumpkinPart")
	body.Size = oldSize
	body.CFrame = oldCFrame
	for _, ornament in ornaments do
		part(model, ornament, if ornament == "Nose" then "WedgePart" else "Part")
	end
	table.insert(expected, { Body = body, OldSize = oldSize, OldCFrame = oldCFrame, Pivot = model.WorldPivot, Model = model })
	return body
end

for index = 1, 65 do
	addLeaf(lanterns, "Jack_" .. index, index)
end
for index = 1, 31 do
	addLeaf(patchFolder, "PatchPumpkin_" .. index, index + 65)
end

local fallback = part(props, "Pumpkin")
local fallbackSize = r.Vector3.new(3.67, 3.11, 3.67)
local fallbackCFrame = r.CFrame.new(485, 7, -194) * r.CFrame.Angles(0, 1.2, 0)
fallback.Size = fallbackSize
fallback.CFrame = fallbackCFrame
-- The original generated fallback decor is a flat body with sibling ornament Parts.
for _, name in { "Stem", "Eye", "Mouth" } do
	local sibling = part(props, name)
	local localOffset = if name == "Stem" then r.Vector3.new(0, 3.11 * 0.55, 0)
		elseif name == "Eye" then r.Vector3.new(-3.11 * 0.22, 3.11 * 0.1, -3.11 * 0.56)
		else r.Vector3.new(0, -3.11 * 0.2, -3.11 * 0.57)
	sibling.CFrame = fallback.CFrame * r.CFrame.new(localOffset)
	sibling.Position = sibling.CFrame.Position
end
local flatPromptBody = part(props, "Pumpkin")
flatPromptBody.Size = r.Vector3.new(3.6, 3.2, 3.6)
local flatPrompt = r.Instance.new("ProximityPrompt")
flatPrompt.Parent = flatPromptBody

local unsafeFolder = r.Instance.new("Folder")
unsafeFolder.Name = "UnsafeDecor"
unsafeFolder.Parent = props
local unsafeModel = r.Instance.new("Model")
unsafeModel.Name = "InteractivePumpkin"
unsafeModel.Parent = unsafeFolder
local unsafeBody = part(unsafeModel, "PumpkinPart")
unsafeBody.Size = r.Vector3.new(3.6, 3.2, 3.6)
local interaction = r.Instance.new("ProximityPrompt")
interaction.Parent = unsafeBody
local unknownModel = r.Instance.new("Model")
unknownModel.Name = "UnknownDecor"
unknownModel.Parent = unsafeFolder
local unknownBody = part(unknownModel, "PumpkinPart")
part(unknownModel, "UnknownGameplayPart")

local outsideHunt = r.Instance.new("Folder")
outsideHunt.Name = "HalloweenEvent"
local huntPickup = part(outsideHunt, "HuntPumpkin")
local converted = PumpkinDecor.Apply(props)
check(converted == 97, "Converts nested leaf pumpkins and the flat fallback only")
check(huntPickup.Parent == outsideHunt and huntPickup.Name == "HuntPumpkin", "Hunt pickup outside Props is untouched")
check(unsafeBody:GetAttribute("CarvedPumpkinDecorVersion") == nil and interaction.Parent == unsafeBody, "Prompt-bearing gameplay pumpkin is skipped intact")
check(flatPromptBody:GetAttribute("CarvedPumpkinDecorVersion") == nil and flatPrompt.Parent == flatPromptBody, "Prompt-bearing flat pumpkin is skipped intact")
check(unknownBody:GetAttribute("CarvedPumpkinDecorVersion") == nil and unknownModel:FindFirstChild("UnknownGameplayPart") ~= nil, "Unknown model contents are skipped intact")

for _, item in expected do
	local body = item.Body
	local lowerBefore = item.OldCFrame.Position.Y - item.OldSize.Y * 0.5
	local lowerAfter = body.CFrame.Position.Y - body.Size.Y * 0.5
	check(math.abs(lowerBefore - lowerAfter) < GEOMETRY_EPSILON, "Converted pumpkin bottom remains aligned to the original ground position")
	check(math.abs(body.Size.X - item.OldSize.X) < GEOMETRY_EPSILON, "Converted pumpkin preserves its original width")
	check(math.abs(body.CFrame.LookVector:Dot(item.OldCFrame.LookVector) - 1) < GEOMETRY_EPSILON, "Converted pumpkin preserves its rotation")
	check(item.Model.WorldPivot == item.Pivot, "Parent model pivot metadata is preserved")
	check(body:GetAttribute("SourceAssetId") == expectedSourceAssetId, "Converted pumpkin records the selected source asset")
	for _, ornament in ornaments do
		check(item.Model:FindFirstChild(ornament) == nil, "Known carved mesh companion is removed: " .. ornament)
	end
	local mesh = body:FindFirstChildOfClass("SpecialMesh")
	check(mesh ~= nil and mesh.MeshId == "rbxassetid://16973748" and mesh.TextureId == "rbxassetid://16973739", "Carved mesh and texture are attached")
end
check(PumpkinDecor.Apply(props) == 0, "A second pass does not add another mesh or reconvert parts")
check(#fallback:GetChildren() == 1 and fallback:FindFirstChildOfClass("SpecialMesh") ~= nil, "Flat fallback has one mesh after conversion")
check(math.abs((fallback.CFrame.Position.Y - fallback.Size.Y * 0.5) - (fallbackCFrame.Position.Y - fallbackSize.Y * 0.5)) < GEOMETRY_EPSILON, "Flat fallback preserves its original bottom position")

print(string.format("PASS: %d pumpkin decoration checks", checks))
