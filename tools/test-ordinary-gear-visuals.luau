-- Build actual equipped models offline: safety, completeness, cleanup and bounded geometry.
-- Run: lune run tools/test-ordinary-gear-visuals
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local env = {}
for key, value in roblox do env[key] = value end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env, injectGlobals = true })()
env.game = { GetService = function() return { Shared = { Config = "Config" } } end }
env.require = function() return config end
local function load(source)
	return luau.load(source, { environment = env, injectGlobals = true })()
end
local service = load(fs.readFile("src/server/CharacterService.luau"))
local function character()
	local model = roblox.Instance.new("Model")
	for name, definition in {
		HumanoidRootPart = { 0, 3, 0, 2, 2, 1 }, Torso = { 0, 3, 0, 2, 2, 1 },
		Head = { 0, 4.5, 0, 2, 1, 1 }, ["Left Leg"] = { -0.5, 1, 0, 1, 2, 1 },
		["Right Leg"] = { 0.5, 1, 0, 1, 2, 1 }, ["Left Arm"] = { -1.5, 3, 0, 1, 2, 1 }, ["Right Arm"] = { 1.5, 3, 0, 1, 2, 1 },
	} do
		local part = roblox.Instance.new("Part")
		part.Name = name; part.Size = roblox.Vector3.new(definition[4], definition[5], definition[6])
		part.CFrame = roblox.CFrame.new(definition[1], definition[2], definition[3]); part.Parent = model
	end
	return model
end
local owned = {}
for key in config.SpeedAccessories do owned[key] = true end
local model = character()
local player = { Character = model }
local expectedMotors = {
	ShadowCloak = { "ShadowOrbitMotor", "ShadowRibbonMotor", "CloakTailL0", "CloakTailR2" },
	VoidHoverboard = { "BoardMotor", "HoverRingMotor" },
	GoldenWings = { "WingMotorL", "WingMotorR" },
	WindScarf = { "ScarfMotor0", "ScarfMotor4", "ScarfFrontMotor0", "ScarfFrontMotor2", "WindSwirlMotor" },
}
for _, key in { "SwiftSneakers", "FlameBoots", "IceSkates", "LightningBoots", "WindScarf", "ShadowCloak", "VoidHoverboard", "GoldenWings" } do
	service.ApplySpeedAccessory(player, owned, key)
	local visuals = model:FindFirstChild("GearVisual_" .. key)
	check(visuals and visuals:GetAttribute("GearReady"), key .. " publishes complete model")
	local count, meshes, motors = 0, 0, {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") then check(child == visuals, key .. " removes previous equipped model") end
	end
	for _, item in visuals:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Transparency < 1 then count += 1 end
			if item:IsA("WedgePart") then meshes += 1 end
			check(not item.Anchored and item.Massless and not item.CanCollide and not item.CanTouch and not item.CanQuery, key .. ": cosmetic physics only")
			check(item.Size.X > 0 and item.Size.Y > 0 and item.Size.Z > 0, key .. ": positive geometry")
			for _, number in { item.CFrame:GetComponents() } do check(number == number and math.abs(number) < 100, key .. ": finite wearable transform") end
		elseif item:IsA("Motor6D") then
			motors[item.Name] = true
			check(item.Part0 and item.Part1 and item.Part0:IsDescendantOf(model) and item.Part1:IsDescendantOf(visuals), key .. ": animation hubs stay inside character")
		elseif item:IsA("WeldConstraint") then
			check(item.Part0 and item.Part1 and item.Part0:IsDescendantOf(model) and item.Part1:IsDescendantOf(visuals), key .. ": all visual pieces remain attached")
		end
	end
	check(count >= 20 and count <= 130, key .. ": bounded visible part budget")
	for _, name in expectedMotors[key] or {} do check(motors[name], key .. ": required animated hub " .. name) end
	if key ~= "WindScarf" then check(meshes > 0, key .. ": sculpted silhouette geometry") end
	print(key, count, "visible parts")
end
service.ApplySpeedAccessory(player, owned, nil)
check(model:GetAttribute("EquippedGear") == nil, "unequip clears selection")
check(#model:GetDescendants() == 7, "unequip clears models and root/limb emitters and trails")
service.ApplySpeedAccessory(player, {}, "GoldenWings")
check(not model:FindFirstChild("GearVisual_GoldenWings"), "unowned gear never builds")
service.Cleanup(player)

-- Optional regression against a supplied previous version: compare Halloween geometry exactly.
if process.args[1] then
	local previous = load(fs.readFile(process.args[1]))
	local function fingerprint(module, key)
		local rig = character()
		module.ApplySpeedAccessory({ Character = rig }, owned, key)
		local rows = {}
		for _, item in rig:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(rows, item.Name .. ":" .. tostring(item.Size) .. ":" .. tostring(item.CFrame) .. ":" .. tostring(item.Color) .. ":" .. tostring(item.Material) .. ":" .. tostring(item.Transparency))
			elseif item:IsA("ParticleEmitter") then
				table.insert(rows, item.Name .. ":" .. item.Texture .. ":" .. tostring(item.Rate) .. ":" .. tostring(item.Color))
			end
		end
		table.sort(rows)
		return table.concat(rows, "\n")
	end
	for _, key in { "WitchBoots", "PhantomCloak", "PumpkinKingWings" } do
		check(fingerprint(service, key) == fingerprint(previous, key), key .. " keeps existing geometry and particles")
	end
end
print(string.format("PASS: %d equipped-gear geometry and cleanup checks", checks))
