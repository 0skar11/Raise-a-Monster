-- Exercise the real procedural builder. Compare its animation graph before and
-- after the Halloween skin, including all growth stages and clone isolation.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
-- Windows checkouts may use CRLF. Normalize before any source instrumentation
-- so the baseline cannot silently keep the new skin enabled.
local source = fs.readFile("src/server/MonsterModels.luau"):gsub("\r\n", "\n")
local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end
local function loadModels(skinEnabled)
	local serverStorage = roblox.Instance.new("ServerStorage")
	local env = {}
	for key, value in roblox do env[key] = value end
	env.workspace = roblox.Instance.new("Workspace")
	env.game = { GetService = function(_, service)
		if service == "ServerStorage" then return serverStorage end
		if service == "CollectionService" then return { AddTag = function() end } end
		error(service)
	end }
	env.task = { wait = function() end }
	-- An isolated empty library exercises Get's actual on-demand builder without
	-- loading thousands of unrelated templates or moving Studio-authored rigs.
	local testSource, libraryReplacements = source:gsub("local library = nil", 'local library = Instance.new("Folder")')
	check(libraryReplacements == 1, "Harness isolates exactly one template library")
	if not skinEnabled then
		local skinReplacements
		testSource, skinReplacements = testSource:gsub("dressHalloween%(r, c, name%)\n\telse", "addFX(r, c, rarity, f)\n\telse")
		check(skinReplacements == 1, "Baseline disables exactly one Halloween skin call")
	end
	return luau.load(testSource, { environment = env, injectGlobals = true })()
end
local actual, original = loadModels(true), loadModels(false)
local animationEnv = {}
for key, value in roblox do animationEnv[key] = value end
local animator = luau.load(fs.readFile("src/shared/MonsterAnimator.luau"), { environment = animationEnv, injectGlobals = true })()
local features = {
	{ "GhostShell", "GhostSocketR", "GhostCurl" },
	{ "ImpSkull", "Rib1R", "ImpBone" },
	{ "PumpkinHead", "PumpkinLobe0", "CrownBand" },
	{ "CatHead", "CatEar", "CatCharm" },
	{ "WrappedHead", "ChestBandage0", "LooseBandage" },
	{ "VampireFangR", "CapeR", "HighCollarR" },
	{ "TombstoneHead", "GraveShoulder", "MossPatch" },
	{ "WraithHood", "ScytheShaft", "RobeHem0" },
}
local function motors(model)
	local result = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then result[descendant.Name] = descendant end
	end
	return result
end
local function contains(model, object)
	return object ~= nil and object:IsDescendantOf(model)
end
local function topology(model, baseline, label)
	local before, after = motors(baseline), motors(model)
	local count = 0
	for name, joint in before do
		local current = after[name]
		check(current ~= nil, label .. " retains " .. name)
		check(current.Part0.Name == joint.Part0.Name and current.Part1.Name == joint.Part1.Name, label .. " retains joint endpoints")
		check(current.C0 == joint.C0 and current.C1 == joint.C1, label .. " retains bind transforms")
		check(current.Part0.Size == joint.Part0.Size and current.Part1.Size == joint.Part1.Size, label .. " retains animation bone sizes")
		for _, attribute in { "Role", "Side", "Index", "Axis", "Front" } do
			check(current:GetAttribute(attribute) == joint:GetAttribute(attribute), label .. " retains " .. attribute)
		end
		count += 1
	end
	local afterCount = 0
	for _ in after do afterCount += 1 end
	check(afterCount == count, label .. " has no extra animation joints")
end
for index = 1, 8 do
	local babyPositions = {}
	for _, stage in { "Baby", "Teen", "Adult" } do
		local model, baseline = actual.Get(6, index, stage), original.Get(6, index, stage)
		local label = index .. "/" .. stage
		check(model ~= nil and model.PrimaryPart ~= nil, label .. " has a root")
		check(model:GetAttribute("HalloweenVisualVersion") == 1, label .. " uses new skin")
		check(baseline:GetAttribute("HalloweenVisualVersion") == nil, label .. " baseline is genuinely unskinned")
		check(baseline:FindFirstChild("AuraFX", true) ~= nil, label .. " baseline retains original rarity decoration")
		check(baseline:FindFirstChild(features[index][1], true) == nil, label .. " baseline lacks new geometry")
		for _, attribute in { "MonsterId", "MonsterName", "Region", "Rarity", "Stage", "RigType", "Scale", "AnimState" } do
			check(model:GetAttribute(attribute) == baseline:GetAttribute(attribute), label .. " preserves " .. attribute)
		end
		topology(model, baseline, label)
		local controller, originalController = animator.new(model), animator.new(baseline)
		for _, state in { "Idle", "Walk", "Attack" } do
			model:SetAttribute("AnimState", state)
			baseline:SetAttribute("AnimState", state)
			for _ = 1, 12 do
				animator.step(controller, 1 / 30)
				animator.step(originalController, 1 / 30)
			end
			for name, joint in motors(model) do
				check(joint.Transform == motors(baseline)[name].Transform, label .. " retains " .. state .. " poses")
			end
		end
		for _, feature in features[index] do check(model:FindFirstChild(feature, true) ~= nil, label .. " has " .. feature) end
		local visible, total = 0, 0
		local scale = model:GetAttribute("Scale")
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") then
				total += 1
				check(child.CanCollide == false and child.Massless == (child ~= model.PrimaryPart), label .. " preserves inert geometry")
				check(child.Anchored == (child == model.PrimaryPart), label .. " anchors only root")
				local d = child.Size
				check(d.X > 0 and d.Y > 0 and d.Z > 0, label .. " has positive dimensions")
				check(not child:IsA("Part") or child.Shape ~= roblox.Enum.PartType.Ball, label .. " avoids native Ball aspect-ratio rendering")
				if child.Transparency < 1 then
					visible += 1
					check(not child.CanTouch and not child.CanQuery, label .. " appearance cannot affect gameplay queries")
					local weld = child:FindFirstChildOfClass("WeldConstraint")
					check(weld ~= nil and weld.Part1 == child and contains(model, weld.Part0), label .. " has no dangling visual weld")
					local corners = child.CFrame.Position.Y - (math.abs(child.CFrame.RightVector.Y) * d.X + math.abs(child.CFrame.UpVector.Y) * d.Y + math.abs(child.CFrame.LookVector.Y) * d.Z) / 2
					check(corners >= -0.25 * scale, label .. " stays near ground plane: " .. child.Name)
					local position = child.CFrame.Position / scale
					check(math.abs(position.X) <= 8 and math.abs(position.Z) <= 6 and position.Y <= 15, label .. " has bounded geometry")
				end
			elseif child:IsA("WeldConstraint") then
				check(contains(model, child.Part0) and contains(model, child.Part1), label .. " weld references its own model")
			end
			check(not child:IsA("Fire") and not child:IsA("ParticleEmitter"), label .. " avoids legacy FX clutter")
		end
		check(visible >= 12 and total <= 90, label .. " stays within part budget (" .. total .. ")")
		local first = model:FindFirstChild(features[index][1], true)
		local normalized = first.Size / scale
		if stage == "Baby" then babyPositions.Size = normalized else check((normalized - babyPositions.Size).Magnitude < 0.0001, label .. " growth scales visual dimensions") end
		first.Color = roblox.Color3.new(1, 0, 1)
		check(actual.Get(6, index, stage):FindFirstChild(features[index][1], true).Color ~= first.Color, label .. " clone changes do not mutate template")
		print(label, "parts", total, "visible", visible)
	end
end
-- An authored library may already contain old or incomplete Halloween models.
-- Get must refresh all growth stages, even when the requested stage is current.
local function halloweenFolder()
	return actual.Build():FindFirstChild("Halloween"):FindFirstChild("01_GhostSlime")
end
local function checkRefreshed(previous, label)
	local result = actual.Get(6, 1, "Adult")
	local current = halloweenFolder()
	check(current ~= previous, label .. " replaces stale species folder")
	check(result:GetAttribute("HalloweenVisualVersion") == 1, label .. " returns current skin")
	for _, stage in { "Baby", "Teen", "Adult" } do
		local template = current:FindFirstChild(stage)
		check(template ~= nil and template:GetAttribute("HalloweenVisualVersion") == 1, label .. " refreshes " .. stage)
		check(template:FindFirstChild("GhostShell") ~= nil, label .. " rebuilds geometry for " .. stage)
	end
	check(actual.Get(6, 1, "Baby") ~= nil and halloweenFolder() == current, label .. " reuses current templates")
end
for _, stage in { "Baby", "Teen", "Adult" } do
	local previous = halloweenFolder()
	previous:FindFirstChild(stage):Destroy()
	local oldTemplate = original.Get(6, 1, stage)
	check(oldTemplate:GetAttribute("HalloweenVisualVersion") == nil, "Cache fixture is genuinely old: " .. stage)
	oldTemplate.Parent = previous
	checkRefreshed(previous, "Unversioned " .. stage)
end
do
	local previous = halloweenFolder()
	previous:FindFirstChild("Teen"):Destroy()
	checkRefreshed(previous, "Missing Teen")
	previous = halloweenFolder()
	previous:FindFirstChild("Baby"):SetAttribute("HalloweenVisualVersion", 0)
	checkRefreshed(previous, "Stale version")
end
-- All non-event templates still take the exact original path.
for region, definition in actual.Regions do
	if region == 6 then continue end
	for index in definition.monsters do
		local model, baseline = actual.Get(region, index, "Adult"), original.Get(region, index, "Adult")
		check(roblox.serializeModel({ model }, true) == roblox.serializeModel({ baseline }, true), "Other species unchanged: " .. region .. "/" .. index)
	end
end
print(("PASS: %d Halloween model checks (24 skins, verified old baseline, rig graph, bounds, welds, growth, clone isolation, stale template refresh and unchanged other species)"):format(checks))
