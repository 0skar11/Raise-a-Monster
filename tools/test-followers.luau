-- Offline follower ownership, eligibility, cap, cleanup and combat policy checks.
-- Run: lune run tools/test-followers.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local config = luau.load(fs.readFile("src/shared/Config.luau"), {
    environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Enum = roblox.Enum },
    injectGlobals = true,
})()
assert(config.Followers, "Config.Followers must be configured")
assert(config.Followers.MaxCount == 5, "The owner requested a maximum of five followers")
local profile = { Data = { Monsters = {} } }
local humanoid = { Health = 100 }
local character = { FindFirstChildOfClass = function(_, class) return if class == "Humanoid" then humanoid else nil end }
local player = { Character = character, Parent = true }
local carried = {}
local stubSignal = { Connect = function() return { Disconnect = function() end } end }
local players = { PlayerAdded = stubSignal, PlayerRemoving = stubSignal, GetPlayers = function() return {} end }
local modules = {
    Config = config,
    MonsterMath = { GetProduction = function() error("Follower combat must not use income") end },
    DataService = { Get = function(who) return if who == player then profile else nil end },
    MonsterModels = {},
    PlotService = { RemoveMonster = function() end },
    CharacterService = {},
}
local services = { Players = players, CollectionService = {}, ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } } }
local environment = {
    game = { GetService = function(_, name) return assert(services[name], name) end },
    script = { Parent = { DataService = "DataService", MonsterModels = "MonsterModels", PlotService = "PlotService", CharacterService = "CharacterService", FollowerService = "FollowerService" } },
    require = function(name) return assert(modules[name], name) end,
    task = { spawn = function() end }, -- policy checks; real visual loop runs below
    Instance = { new = function(class) assert(class == "Folder"); return {} end },
    workspace = {},
}
local followers = luau.load(fs.readFile("src/server/FollowerService.luau"), { environment = environment, injectGlobals = true })()
modules.FollowerService = followers
followers.Init(function(_, id) return carried[id] == true end, function() end)
local monsters = luau.load(fs.readFile("src/server/MonsterService.luau"), { environment = environment, injectGlobals = true })()
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks += 1
end
local commonSpecies
for name, species in config.Species do if species.Rarity == "Common" then commonSpecies = name; break end end
assert(commonSpecies)
local minimum = followers.GetMinLevel()
local function add(id, level)
    profile.Data.Monsters[id] = { Id = id, Species = commonSpecies, Level = level, Xp = 0, Hunger = 100, Happiness = 100, Slot = 1 }
end
local function toggle(id) return select(1, followers.Toggle(player, id)) end
check(not toggle(42), "Reject non-string IDs")
check(not toggle({}), "Reject table IDs")
check(not toggle(""), "Reject empty IDs")
check(not toggle(string.rep("a", 129)), "Reject oversized IDs")
check(not toggle("not-owned"), "Reject unowned IDs")
add("baby", 1)
add("teen", minimum - 1)
check(not toggle("baby"), "Baby must not follow")
check(not toggle("teen"), "Teen must not follow")
add("a", minimum)
check(toggle("a"), "Adult can follow")
check(#followers.GetIds(player) == 1, "Adult added once")
local base = config.Followers.DamagePerRarity.Common
check(followers.GetDamageBonus(player) == base, "Adult rarity damage matches config")
check(monsters.GetAttackDamage(player) == config.Combat.BaseDamage + base, "Attack damage is base plus equipped followers")
add("a2", minimum + 20)
add("a3", minimum)
add("a4", minimum)
add("a5", minimum)
add("a6", minimum)
for _, id in { "a2", "a3", "a4", "a5" } do check(toggle(id), "Can equip up to five") end
check(not toggle("a6") and #followers.GetIds(player) == 5, "Sixth follower rejected")
check(toggle("a") and #followers.GetIds(player) == 4, "Toggle unequips instead of duplicating")
check(toggle("a6"), "Freed slot can be used")
local ids = followers.GetIds(player)
ids[1] = "forged"
check(followers.GetIds(player)[1] ~= "forged", "Snapshot cannot mutate equipped IDs")
carried.a2 = true
check(not table.find(followers.GetIds(player), "a2"), "Carried or arena-locked monster loses follow slot")
check(not toggle("a2"), "Carried monster cannot re-equip")
carried.a2 = nil
profile.Data.Monsters.a3 = nil
check(not table.find(followers.GetIds(player), "a3"), "Missing or sold monster loses follow slot")
check(monsters.TakeMonsterData(player, "a4") ~= nil, "Trading transfer returns owned data")
check(not table.find(followers.GetIds(player), "a4"), "Traded monster immediately unequipped")
profile.Data.Monsters.a5.Level = 1
check(not table.find(followers.GetIds(player), "a5"), "Level downgrade is revalidated")
followers.Clear(player)
check(#followers.GetIds(player) == 0 and followers.GetDamageBonus(player) == 0, "Respawn clear removes slots and bonus")
add("legendary-stage", config.MaxLevel)
check(toggle("legendary-stage"), "Highest evolution stage remains eligible")
local expected = math.floor(base * (1 + math.min(config.Followers.MaxLevelBonus, (config.MaxLevel - minimum) * config.Followers.LevelBonusPerLevel)))
check(followers.GetDamageBonus(player) == expected, "Level bonus is bounded by config")
profile.Data.Monsters["legendary-stage"].Level = 1000000000
check(followers.GetDamageBonus(player) <= math.floor(base * (1 + config.Followers.MaxLevelBonus)), "Huge level cannot exceed bonus cap")
humanoid.Health = 0
check(followers.GetDamageBonus(player) == 0, "Dead player receives no follower damage")
check(not toggle("a"), "Dead player cannot equip")
humanoid.Health = 100
followers.CleanupPlayer(player)
check(#followers.GetIds(player) == 0, "Player cleanup clears session equipment")
local attack = fs.readFile("src/server/MonsterService.luau"):match("function MonsterService.GetAttackDamage.-\nend")
check(attack and not attack:find("Production"), "Production is absent from damage calculation")
print(string.format("PASS: %d follower policy checks (real Config and production server modules)", checks))

-- Lune has real asset Instances, but no engine model transforms or simulation.
-- Supply only those engine operations; execute the actual visual loop/factories.
local visualChecks = 0
local function visualCheck(condition, message)
    assert(condition, message)
    visualChecks += 1
end
local function modelParts(model)
    local result = {}
    for _, item in model:GetDescendants() do
        if item:IsA("BasePart") then table.insert(result, item) end
    end
    return result
end
local function boundsOf(model)
    local pivot = model:GetPivot()
    local low = roblox.Vector3.new(math.huge, math.huge, math.huge)
    local high = -low
    for _, part in modelParts(model) do
        local localFrame = pivot:ToObjectSpace(part.CFrame)
        for _, x in {-0.5, 0.5} do for _, y in {-0.5, 0.5} do for _, z in {-0.5, 0.5} do
            local point = localFrame:PointToWorldSpace(part.Size * roblox.Vector3.new(x, y, z))
            low = roblox.Vector3.new(math.min(low.X, point.X), math.min(low.Y, point.Y), math.min(low.Z, point.Z))
            high = roblox.Vector3.new(math.max(high.X, point.X), math.max(high.Y, point.Y), math.max(high.Z, point.Z))
        end end end
    end
    return pivot * roblox.CFrame.new((low + high) / 2), high - low
end
local modelScales = {}
roblox.implementMethod("Model", "GetPivot", function(model) return model.PrimaryPart.CFrame end)
roblox.implementMethod("Model", "GetBoundingBox", boundsOf)
roblox.implementMethod("Model", "GetExtentsSize", function(model) return select(2, boundsOf(model)) end)
roblox.implementMethod("Model", "GetScale", function(model) return modelScales[model] or 1 end)
roblox.implementMethod("Model", "ScaleTo", function(model, scale)
    local ratio = scale / model:GetScale()
    local origin = model:GetPivot()
    for _, part in modelParts(model) do
        local relative = origin:ToObjectSpace(part.CFrame)
        part.Size *= ratio
        part.CFrame = origin * roblox.CFrame.new(relative.Position * ratio) * relative.Rotation
    end
    for _, joint in model:GetDescendants() do
        if joint:IsA("Motor6D") or joint:IsA("Weld") then
            joint.C0 = roblox.CFrame.new(joint.C0.Position * ratio) * joint.C0.Rotation
            joint.C1 = roblox.CFrame.new(joint.C1.Position * ratio) * joint.C1.Rotation
        end
    end
    modelScales[model] = scale
end)
roblox.implementMethod("Model", "PivotTo", function(model, target)
    local origin = model:GetPivot()
    for _, part in modelParts(model) do part.CFrame = target * origin:ToObjectSpace(part.CFrame) end
end)
local testWorkspace = roblox.Instance.new("Workspace")
roblox.implementMethod("Workspace", "Raycast", function(_, origin)
    return { Position = roblox.Vector3.new(origin.X, 0, origin.Z) }
end)
local serverStorage = roblox.Instance.new("ServerStorage")
local library = roblox.deserializeModel(fs.readFile("assets/AnimationRigs.rbxmx"))[1]
library.Name = "MonsterModels"
library.Parent = serverStorage
local visualRoot = roblox.Instance.new("Part")
visualRoot.Name = "HumanoidRootPart"
visualRoot.Size = roblox.Vector3.new(2, 2, 1)
visualRoot.CFrame = roblox.CFrame.new(0, 4, 0)
visualRoot.Position = visualRoot.CFrame.Position
local visualHumanoid = { Health = 100, HipHeight = 2, Died = stubSignal }
local visualCharacter = {
    FindFirstChild = function(_, name) return if name == "HumanoidRootPart" then visualRoot else nil end,
    FindFirstChildOfClass = function(_, class) return if class == "Humanoid" then visualHumanoid else nil end,
    WaitForChild = function(_, name) return if name == "Humanoid" then visualHumanoid else nil end,
}
local visualPlayer = { UserId = 7, Character = visualCharacter, Parent = true, CharacterRemoving = stubSignal, CharacterAdded = stubSignal }
local visualProfile = { Data = { Monsters = {} } }
local scheduled = {}
local tagged = {}
local visualPlayers = { PlayerAdded = stubSignal, PlayerRemoving = stubSignal, GetPlayers = function() return { visualPlayer } end }
local visualServices = {
    Players = visualPlayers,
    ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
    ServerStorage = serverStorage,
    CollectionService = { AddTag = function(_, model, tag) tagged[model] = tag end },
}
local visualModules = { Config = config, DataService = { Get = function(who) return if who == visualPlayer then visualProfile else nil end } }
local offlineCFrame = table.clone(roblox.CFrame)
offlineCFrame.lookAt = function(position, target)
    local back = (position - target).Unit
    local right = roblox.Vector3.new(0, 1, 0):Cross(back).Unit
    return roblox.CFrame.fromMatrix(position, right, back:Cross(right), back)
end
local function loadRealModule(name, path)
    local env = {
        game = { GetService = function(_, service) return assert(visualServices[service], service) end },
        workspace = testWorkspace,
        script = { Parent = { Config = "Config", MonsterMath = "MonsterMath", DataService = "DataService", MonsterModels = "MonsterModels", PlotService = "PlotService", Build = "Build" } },
        require = function(moduleName) return assert(visualModules[moduleName], moduleName) end,
        task = { spawn = function(callback) table.insert(scheduled, coroutine.create(callback)) end, wait = coroutine.yield },
        RaycastParams = { new = function() return {} end },
    }
    for key, value in roblox do env[key] = value end
    env.CFrame = offlineCFrame
    visualModules[name] = luau.load(fs.readFile(path), { environment = env, injectGlobals = true })()
    return visualModules[name]
end
loadRealModule("MonsterMath", "src/shared/MonsterMath.luau")
loadRealModule("Build", "src/server/Build.luau")
loadRealModule("MonsterModels", "src/server/MonsterModels.luau")
loadRealModule("PlotService", "src/server/PlotService.luau")
local realAnimator = loadRealModule("MonsterAnimator", "src/shared/MonsterAnimator.luau")
local visualFollowers = loadRealModule("FollowerService", "src/server/FollowerService.luau")
visualFollowers.Init(function() return false end, function() end)
local updateLoop = scheduled[#scheduled]
local function tickVisuals()
    local ok, failure = coroutine.resume(updateLoop)
    assert(ok, failure)
end
local function equipVisual(id, species)
    visualProfile.Data.Monsters[id] = { Id = id, Species = species, Level = minimum, Xp = 0, Hunger = 100, Happiness = 100, Slot = 1 }
    visualCheck(select(1, visualFollowers.Toggle(visualPlayer, id)), species .. " can equip")
end
local function checkVisual(model, species)
    visualCheck(model ~= nil and model.PrimaryPart ~= nil, species .. " creates a real visual")
    local bounds, size = model:GetBoundingBox()
    visualCheck(size.X <= config.Followers.Spacing - config.Followers.VisualPadding + 0.001, species .. " fits column spacing")
    visualCheck(size.Z <= config.Followers.RowDistance - config.Followers.VisualPadding + 0.001, species .. " fits row spacing")
    visualCheck(math.abs(bounds.Position.Y - size.Y / 2) < 0.002, species .. " rests on the ground")
    visualCheck(bounds.Position.Z - size.Z / 2 > visualRoot.Position.Z + visualRoot.Size.Z / 2, species .. " stays behind avatar")
    local visibleParts, motors = 0, 0
    for _, child in model:GetDescendants() do
        if child:IsA("BasePart") then
            visualCheck(child.CanCollide == false and child.CanTouch == false and child.CanQuery == false and child.Massless, species .. " has inert visual parts")
            visualCheck(child.Anchored == (child == model.PrimaryPart), species .. " anchors only its root")
            if child.Transparency < 1 then visibleParts += 1 end
        elseif child:IsA("Motor6D") then
            motors += 1
            visualCheck(child.Part0 ~= nil and child.Part1 ~= nil, species .. " retains joint endpoints")
            local joint0 = child.Part0.CFrame * child.C0
            local joint1 = child.Part1.CFrame * child.C1
            visualCheck((joint0.Position - joint1.Position).Magnitude < 0.003, species .. " retains scaled joint alignment")
        end
        visualCheck(not child:IsA("ProximityPrompt") and not child:IsA("ClickDetector") and not child:IsA("LuaSourceContainer") and not child:IsA("BillboardGui"), species .. " has no interaction or income label")
    end
    visualCheck(visibleParts > 0, species .. " contains visible geometry")
    visualCheck(motors > 0, species .. " can use the monster animator")
    visualCheck(model:GetAttribute("FollowerOwner") == visualPlayer.UserId, species .. " has the correct owner")
end
local folderVisuals = testWorkspace:FindFirstChild("MonsterFollowers")
local speciesCount, legacyCount = 0, 0
for species, definition in config.Species do
    visualFollowers.Clear(visualPlayer)
    equipVisual("species-check", species)
    tickVisuals()
    local model = folderVisuals:FindFirstChild("species-check")
    checkVisual(model, species)
    if not definition.Model then
        legacyCount += 1
        visualCheck(tagged[model] == "Monster", species .. " is registered for procedural walking")
        model:SetAttribute("AnimState", "Walk")
        realAnimator.step(realAnimator.new(model), 0.25)
        local animatedLeg = false
        for _, joint in model:GetDescendants() do
            if joint:IsA("Motor6D") and joint:GetAttribute("Role") == "Leg" and joint.Transform ~= roblox.CFrame.new() then animatedLeg = true end
        end
        visualCheck(animatedLeg, species .. " feet receive actual walking transforms")
    end
    speciesCount += 1
end
visualFollowers.Clear(visualPlayer)
local giantSpecies
for species, definition in config.Species do if definition.DisplayName == "Sun Wyrm" then giantSpecies = species; break end end
assert(giantSpecies, "Sun Wyrm regression fixture must exist")
for index = 1, config.Followers.MaxCount do equipVisual("giant-" .. index, giantSpecies) end
visualProfile.Data.Monsters.sixth = { Id = "sixth", Species = giantSpecies, Level = minimum }
visualCheck(not select(1, visualFollowers.Toggle(visualPlayer, "sixth")), "Sixth giant follower is rejected")
tickVisuals()
visualCheck(#folderVisuals:GetChildren() == 5, "Exactly five giant visuals exist")
local giantModels = folderVisuals:GetChildren()
for _, model in giantModels do checkVisual(model, giantSpecies) end
for index, first in giantModels do
    local firstBounds, firstSize = first:GetBoundingBox()
    for otherIndex = index + 1, #giantModels do
        local secondBounds, secondSize = giantModels[otherIndex]:GetBoundingBox()
        local difference = secondBounds.Position - firstBounds.Position
        visualCheck(math.abs(difference.X) >= (firstSize.X + secondSize.X) / 2 + config.Followers.VisualPadding - 0.003
            or math.abs(difference.Z) >= (firstSize.Z + secondSize.Z) / 2 + config.Followers.VisualPadding - 0.003, "Giant followers keep a gap")
    end
end
tickVisuals()
visualCheck(giantModels[1]:GetAttribute("AnimState") == "Idle", "Stationary follower idles")
local prior = giantModels[1]:GetPivot().Position
visualRoot.CFrame = roblox.CFrame.new(0, 4, -10)
visualRoot.Position = visualRoot.CFrame.Position
tickVisuals()
visualCheck(giantModels[1]:GetAttribute("AnimState") == "Walk", "Moving follower walks")
visualCheck((giantModels[1]:GetPivot().Position - prior).Magnitude > 9, "Real visual tracks player movement")
visualRoot.CFrame = roblox.CFrame.new(0, 4, -10) * roblox.CFrame.Angles(0, math.pi / 2, 0)
tickVisuals()
for _, model in giantModels do
    local bounds, size = model:GetBoundingBox()
    local behind = (bounds.Position - visualRoot.Position):Dot(-visualRoot.CFrame.LookVector)
    visualCheck(behind - size.Z / 2 > 0.5, "Turning preserves clearance behind the avatar")
end
visualFollowers.Clear(visualPlayer)
visualCheck(#folderVisuals:GetChildren() == 0, "Cleanup destroys all real visuals")
print(string.format("PASS: %d visual checks across %d real asset/fallback species (%d legacy/Secret), five giants, movement and cleanup", visualChecks, speciesCount, legacyCount))
