-- Offline geometry/lifecycle checks. Does not replace a Studio visual playtest.
-- Run from repo root: lune run tools/test-approved-geometry.luau
local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local signals = {}
local function signal(instance)
	if not signals[instance] then
		local listeners = {}
		signals[instance] = { Connect = function(_, callback) table.insert(listeners, callback); return { Disconnect = function() end } end, Fire = function(_, ...) for _, callback in listeners do callback(...) end end }
	end
	return signals[instance]
end
r.implementProperty("BasePart", "Touched", signal)
r.implementProperty("ProximityPrompt", "Triggered", signal)
local function parts(model)
	local items = {}; for _, child in model:GetDescendants() do if child:IsA("BasePart") then table.insert(items, child) end end; return items
end
r.implementMethod("Model", "GetPivot", function(model) return model.PrimaryPart and model.PrimaryPart.CFrame or r.CFrame.new() end)
r.implementMethod("Model", "PivotTo", function(model, target) local old = model:GetPivot(); for _, p in parts(model) do p.CFrame = target * old:ToObjectSpace(p.CFrame) end end)
local cframe = table.clone(r.CFrame)
cframe.lookAt = function(a, b)
	local back = a - b; if back.Magnitude < 1e-8 then return r.CFrame.new(a) end; back = back.Unit
	local right = r.Vector3.new(0, 1, 0):Cross(back)
	if right.Magnitude < 1e-8 then right = r.Vector3.new(1, 0, 0):Cross(back) end; right = right.Unit
	return r.CFrame.fromMatrix(a, right, back:Cross(right), back)
end
local replicated = r.Instance.new("ReplicatedStorage")
local weapons = r.deserializeModel(fs.readFile("assets/WeaponModels.rbxmx"):gsub("^<%?xml.-%?>%s*", ""))[1]; weapons.Parent = replicated
local workspace = r.Instance.new("Workspace")
local currentOwner, visitor
local services = { ReplicatedStorage = replicated, StarterPlayer = r.Instance.new("StarterPlayer"), CollectionService = { GetTagged = function() return {} end, GetInstanceAddedSignal = function() return { Connect = function() return { Disconnect = function() end } end } end }, Players = { GetPlayerFromCharacter = function(_, model) if currentOwner and model == currentOwner.Character then return currentOwner end; return visitor end } }
local modules = { MonsterModels = {} }
local shared = { Config = "Config", MonsterMath = "MonsterMath" }; replicated.Name = "ReplicatedStorage"
local sharedFolder = r.Instance.new("Folder"); sharedFolder.Name = "Shared"; sharedFolder.Parent = replicated
for name in shared do local mod = r.Instance.new("ModuleScript"); mod.Name = name; mod.Parent = sharedFolder end
local function load(name, path)
	local env = { game = { GetService = function(_, service) return assert(services[service], service) end }, workspace = workspace, script = { Parent = { Build = "Build", MonsterModels = "MonsterModels", Config = "Config", MonsterMath = "MonsterMath" } }, require = function(id) return assert(modules[if type(id) == "string" then id else id.Name], tostring(id)) end, task = { delay = function() end, spawn = function() end }, CFrame = cframe }
	for key, value in r do if env[key] == nil then env[key] = value end end
	modules[name] = luau.load(fs.readFile(path), { environment = env, injectGlobals = true })()
	return modules[name]
end
local config = load("Config", "src/shared/Config.luau")
load("MonsterMath", "src/shared/MonsterMath.luau")
local build = load("Build", "src/server/Build.luau")
local makePart = build.MakePart
build.MakePart = function(props)
	if props.Position and not props.CFrame then local translated = table.clone(props); translated.CFrame = r.CFrame.new(props.Position); translated.Position = nil; return makePart(translated) end
	return makePart(props)
end
local plotService = load("PlotService", "src/server/PlotService.luau")
plotService.Init()
check(#plotService.GetPlots() == config.MaxPlots, "Sanctuary preserves plot capacity")
for _, plot in plotService.GetPlots() do
	check(plot.Model.Floor.Material == r.Enum.Material.Grass, "Sanctuary has grass floor")
	local unlocked = 0
	check(#plot.Pedestals == config.MaxSlots, "All real expansion slots exist")
	for slot, pad in plot.Pedestals do
		if pad:GetAttribute("Unlocked") then unlocked += 1 end
		check(pad:GetAttribute("Unlocked") == (slot <= config.BaseSlots), "Exactly starting slots are unlocked")
		local locked = pad.Parent.LockedGeometry.FutureExpansion
		check(locked.Transparency == (if slot <= config.BaseSlots then 1 else 0), "Expansion label matches initial ownership")
		for _, p in pad.Parent.UnlockedGeometry:GetChildren() do if p:IsA("BasePart") then check(p.Transparency == (if slot <= config.BaseSlots then 0 else 1), "Round fence visibility matches slot state") end end
		local slotPosition = plot.CFrame:PointToObjectSpace(plotService.GetSlotCFrame(plot, slot).Position)
		check(math.abs(slotPosition.X) < 27 and math.abs(slotPosition.Z) < 28, "Slot stays on sanctuary ground")
	end
	check(unlocked == 3 and config.BaseSlots == 3, "Three habitats start unlocked")
	for _, p in plot.Model:GetDescendants() do
		check(not p.Name:lower():find("dock") and not p.Name:lower():find("fishing") and p.Name ~= "Pillar" and p.Name ~= "CenterCrystal", "No fishing area or old corner pylons")
		if p:IsA("BasePart") then check(p.Anchored, "Map pieces remain individually editable anchored Parts") end
	end
end
local function player(id)
	local p = r.Instance.new("Player"); p.UserId = id; p.DisplayName = "TestPlayer" .. id
	local character = r.Instance.new("Model"); character.Name = "TestCharacter"; character.Parent = workspace; p.Character = character
	local humanoid = r.Instance.new("Humanoid"); humanoid.Health = 100; humanoid.MaxHealth = 100; humanoid.Parent = character
	for _, name in { "HumanoidRootPart", "Torso", "Left Leg", "Right Leg" } do local item = r.Instance.new("Part"); item.Name = name; item.Size = r.Vector3.new(if name == "Torso" then 2 else 1, 2, 1); item.Parent = character end
	return p
end
currentOwner, visitor = player(1), player(2)
local plot = assert(plotService.Assign(currentOwner))
plotService.SetUnlockedSlots(currentOwner, 4)
check(plot.Pedestals[4]:GetAttribute("Unlocked") and plot.Pedestals[4].Parent.LockedGeometry.FutureExpansion.Transparency == 1, "Upgrade unlocks fourth round habitat")
local collections = 0; plotService.Callbacks.Collect = function() collections += 1 end
signals[plot.Model.Collector]:Fire(currentOwner.Character.HumanoidRootPart)
signals[plot.Model.Collector]:Fire(visitor.Character.HumanoidRootPart)
check(collections == 1, "Collection retains owner checks on the corner chest")
local collector = plot.Model.Collector
check(#plot.CollectorParts == 5, "Collector includes pad, chest, lid and both bands")
plotService.SetCollectorEnabled(currentOwner, false)
for _, part in plot.CollectorParts do check(part.Parent == nil, "AutoCollect removes all collector geometry from the world") end
check(not collector:IsDescendantOf(workspace) and not plot.CollectorLabel:IsDescendantOf(workspace), "Collection target and label are absent from Workspace")
signals[collector]:Fire(currentOwner.Character.HumanoidRootPart)
check(collections == 1, "Stale touch event cannot manually collect for AutoCollect owner")
check(plotService.GetPlot(visitor) == nil and plotService.GetPlots()[2].Model:FindFirstChild("Collector"), "Other plots retain their collectors")
plotService.RenderMonster(currentOwner, { Id = "Benched", Slot = 0 })
plotService.UpdateMonster(currentOwner, { Id = "Benched", Slot = 0 }, true)
plotService.RenderEgg(currentOwner, "BenchEgg", config.ShopEggs[1], 0)
check(#plot.MonstersFolder:GetChildren() == 0 and #plot.EggsFolder:GetChildren() == 0, "Benched monsters and eggs have no habitat visual")
plotService.Release(currentOwner)
check(plot.CollectorEnabled and plot.Model.Collector == collector, "Release restores the original collector")
for _, part in plot.CollectorParts do check(part.Parent == plot.Model, "Release restores all collector pieces") end
local reassigned = assert(plotService.Assign(visitor))
check(reassigned == plot and plot.CollectorEnabled, "New owner receives a working collector on the freed plot")
signals[collector]:Fire(visitor.Character.HumanoidRootPart)
check(collections == 2, "Reassigned collector accepts the new owner")
plotService.Release(visitor)
check(not plot.Pedestals[4]:GetAttribute("Unlocked") and plot.Pedestals[1]:GetAttribute("Unlocked"), "Release restores three starting habitats")
local characterService = load("CharacterService", "src/server/CharacterService.luau")
local features = { SwiftSneakers = "SneakerSideGlow", FlameBoots = "FlameTongue", IceSkates = "SkateBlade", LightningBoots = "BootLightningEmblem", VoidHoverboard = "HoverboardDeck", ShadowCloak = "SplitCloakTail", WindScarf = "WindScarfCollar", GoldenWings = "GoldenWingFeather" }
for gear, feature in features do
	characterService.ApplySpeedAccessory(currentOwner, { [gear] = true }, gear)
	local visual = assert(currentOwner.Character:FindFirstChild("GearVisual_" .. gear))
	check(visual:FindFirstChild(feature, true) ~= nil, gear .. " has actual approved mesh detail")
	local visualCount = 0
	for _, child in currentOwner.Character:GetChildren() do if child.Name:match("^GearVisual_") then visualCount += 1 end end
	check(visualCount == 1, "Gear switch removes previous model")
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") then
			check(p.Massless and not p.Anchored and not p.CanCollide and not p.CanTouch, "Worn geometry preserves movement physics")
			local weld = p:FindFirstChildOfClass("WeldConstraint"); check(weld and weld.Part1 == p and weld.Part0:IsDescendantOf(currentOwner.Character), "Every wearable part follows avatar limb")
		end
	end
	if gear == "ShadowCloak" then check(visual:FindFirstChild("ShadowAuraRibbon", true) and visual:FindFirstChild("OrbitingShadowShard", true), "Final cloak has dark violet aura geometry") end
end
characterService.ApplySpeedAccessory(currentOwner, {}, nil)
check(not currentOwner.Character:FindFirstChildWhichIsA("ParticleEmitter", true) and not currentOwner.Character:FindFirstChild("GearVisual_ShadowCloak"), "Unequip cleans geometry and effects")
for _, name in { "WoodenBat", "IronBat", "IronSword", "ForestSword", "DesertSword", "IceSword", "LavaSword", "VoidBat" } do
	local tool = assert(weapons:FindFirstChild(name)); local handle = assert(tool:FindFirstChild("Handle")); local count = 0
	for _, p in tool:GetDescendants() do if p:IsA("BasePart") then
		count += 1
		check(not p.Anchored and not p.CanCollide and p.Massless, "Bat geometry preserves Tool physics")
		if p ~= handle then local weld = p:FindFirstChildOfClass("WeldConstraint"); check(weld and weld.Part0 == handle and weld.Part1 == p, "Serialized bat weld references resolve") end
	end end
	check(count >= 20 and tool:FindFirstChild("BarrelUpper"), "Legacy weapon template uses chunky bat geometry")
	check(tool.BarrelUpper.CFrame.Position.X > handle.CFrame.Position.X + 3, "Bat keeps existing upright-grip local +X axis")
end
print("PASS:", checks, "approved geometry checks (3/10 habitats, unlock/release, owner collection, bench guards, wearable welds/cleanup, bat templates)")
