-- Offline geometry, gameplay guard and portrait-bank fixture.
-- Lune has no native GUI renderer and cannot assign nil to ViewportFrame.CurrentCamera.
-- Client deferred portrait mounting is therefore skipped, and only that camera-clear
-- assignment is adapted in the loaded test source. Production modules are unchanged.
-- Real portrait visibility, camera framing, clone cleanup and text fit require Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local count = 0
local function check(ok, message) assert(ok, message); count += 1 end
local function signal()
	local callbacks = {}
	return { Connect = function(_, callback)
		local key = {}; callbacks[key] = callback
		return { Disconnect = function() callbacks[key] = nil end }
	end, Fire = function(_, ...) for _, callback in callbacks do callback(...) end end }
end
local changed, events = {}, {}
local cameraRefs = {}
r.implementProperty("ViewportFrame", "CurrentCamera", function(item) return cameraRefs[item] end, function(item, value) cameraRefs[item] = value end)
local function propertySignal(item, name)
	changed[item] = changed[item] or {}; changed[item][name] = changed[item][name] or signal()
	return changed[item][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", propertySignal)
r.implementProperty("Instance", "DescendantAdded", function(item) return propertySignal(item, "DescendantAdded") end)
r.implementProperty("TextButton", "Activated", function(item) return propertySignal(item, "Activated") end)
r.implementMethod("Model", "PivotTo", function() end)
r.implementMethod("Model", "GetBoundingBox", function() return r.CFrame.new(), r.Vector3.new(4, 6, 3) end)
local viewport = r.Vector2.new(1200, 760)
local function geometry(item)
	if item:IsA("ScreenGui") then return r.Vector2.zero, viewport end
	local parent = item.Parent
	local origin, parentSize = if parent then geometry(parent) else r.Vector2.zero, viewport
	if parent then origin, parentSize = geometry(parent) end
	local size = r.Vector2.new(item.Size.X.Scale * parentSize.X + item.Size.X.Offset, item.Size.Y.Scale * parentSize.Y + item.Size.Y.Offset)
	local pos = origin + r.Vector2.new(item.Position.X.Scale * parentSize.X + item.Position.X.Offset, item.Position.Y.Scale * parentSize.Y + item.Position.Y.Offset)
	pos -= r.Vector2.new(item.AnchorPoint.X * size.X, item.AnchorPoint.Y * size.Y)
	if parent and parent:IsA("ScrollingFrame") then pos -= parent.CanvasPosition end
	return pos, size
end
for _, class in { "Frame", "ScrollingFrame", "ViewportFrame", "TextButton", "TextLabel" } do
	r.implementProperty(class, "AbsolutePosition", function(item) local p = geometry(item); return p end)
	r.implementProperty(class, "AbsoluteSize", function(item) local _, size = geometry(item); return size end)
end
local deferred = {}
local allowDeferred = false -- Lune does not expose Roblox's read-only AbsolutePosition; Studio covers portrait visibility.
local taskStub = { defer = function(fn) table.insert(deferred, fn) end, wait = function() end }
local function drain() if not allowDeferred then deferred = {}; return end; local n = 0; while #deferred > 0 do n += 1; check(n < 100, "deferred work bounded"); local fn = table.remove(deferred, 1); fn() end end
local player = r.Instance.new("Player"); player.Name = "Owner"; player.UserId = 123
local playerGui = r.Instance.new("PlayerGui"); playerGui.Parent = player
local shared = { Config = "Config", MonsterMath = "MonsterMath" }
local collectionService = { GetTags = function() return {} end, RemoveTag = function() end, GetTagged = function() return {} end }
local guiService = { GetGuiInset = function() return r.Vector2.zero, r.Vector2.zero end }
local camera = { ViewportSize = viewport, GetPropertyChangedSignal = propertySignal }
local workspace = { CurrentCamera = camera, GetPropertyChangedSignal = propertySignal }
local playersService = { LocalPlayer = player, PlayerRemoving = signal() }
local replicated = r.Instance.new("ReplicatedStorage")
local services = {
	Players = playersService, CollectionService = collectionService, GuiService = guiService,
	UserInputService = { GamepadEnabled = true }, ReplicatedStorage = { Shared = shared }, TweenService = {},
}
local config = { Followers = { MinLevel = 25, MaxCount = 5 }, Rarities = { Mythic = { Color = r.Color3.fromRGB(180, 80, 240) } } }
local mathModule = { GetStage = function(level) return { Name = if level >= 25 then "Adult" else "Baby" } end, FormatNumber = tostring }
local ui = { Gui = r.Instance.new("ScreenGui"), Panels = {} }; ui.Gui.Parent = playerGui
local uiModule = {}
function uiModule.Panel(parent, name, size)
	local frame = r.Instance.new("Frame"); frame.Name = name; frame.Size = size; frame.AnchorPoint = r.Vector2.new(0.5,0.5); frame.Position = r.UDim2.fromScale(0.5,0.5); frame.Visible = false; frame.Parent = parent
	local title = r.Instance.new("TextLabel"); title.Parent = frame
	local close = r.Instance.new("TextButton"); close.Name = "CloseButton"; close.Parent = frame
	return frame, title
end
function uiModule.Open(_, frame) frame.Visible = true; propertySignal(frame,"Visible"):Fire() end
local modules = { Config = config, MonsterMath = mathModule, UI = uiModule }
local env = { game = { GetService = function(_, name) return assert(services[name],name) end }, workspace = workspace, script = { Parent = { UI = "UI", PlotService = "PlotService" } }, require = function(name) return assert(modules[name],name) end, task = taskStub }
for k,v in r do env[k] = v end
local clientSource = fs.readFile("src/client/MonsterVault.luau"):gsub("entry%.Viewport%.CurrentCamera = nil", "-- Lune cannot assign nil to CurrentCamera; native Studio verifies this line")
local vault = luau.load(clientSource, { environment = env, injectGlobals = true })()
local state = { Monsters = {}, MaxSlots = 6, UnlockedSlots = 3, Eggs = { { Slot = 3 } }, FollowingIds = {}, FollowerLimit = 5 }
for index = 1, 15 do table.insert(state.Monsters, { Id = "M"..index, Species = "ActualSpecies", DisplayName = "Reality Titan "..index, Rarity = "Mythic", Stage = "Adult", Level = 26, ActualIncome = 100-index, Slot = if index <= 2 then index else 0, CanFollow = true }) end
local calls, remotes = {}, {}
for _, name in { "AutoPlaceMonsters", "PlaceMonster", "BenchMonster", "ToggleFollower" } do remotes[name] = { FireServer = function(_, ...) table.insert(calls, { Name = name, Args = {...} }) end } end
local viewed
local controller = vault.Init(ui, remotes, function() return state end, function(id) viewed = id end)
controller.Open(); drain()
local frame = controller.Frame
local function find(name) local item = frame:FindFirstChild(name,true); return assert(item,name) end
check(find("M1").Visible, "real monster card exists")
check(find("Counts").Text == "15 owned  ·  2 placed  ·  13 on bench", "counts reflect state")
check(find("SelectedName").Text == "Reality Titan 1", "highest income selected")
local left = find("CollectionPane")
local grid = find("Collection"):FindFirstChildOfClass("UIGridLayout")
check(grid.FillDirectionMaxCells == 3, "desktop 3 columns")
check(find("AutoPlaceButton").Size.Y.Offset >= 44 and find("AllTab").Size.Y.Offset >= 44, "touch targets")
propertySignal(find("AutoPlaceButton"),"Activated"):Fire()
check(calls[#calls].Name == "AutoPlaceMonsters", "auto place unchanged")
propertySignal(find("Slot3"),"Activated"):Fire()
check(#calls == 1, "hatching egg cannot place")
propertySignal(find("Slot2"),"Activated"):Fire()
check(calls[#calls].Name == "PlaceMonster" and calls[#calls].Args[1] == "M1" and calls[#calls].Args[2] == 2, "swap remote args unchanged")
state.Monsters[1].Carried = true; controller.Refresh()
propertySignal(find("BenchButton"),"Activated"):Fire()
check(calls[#calls].Name == "PlaceMonster", "carried cannot bench")
propertySignal(find("ViewMonsterButton"),"Activated"):Fire(); check(viewed == nil, "carried cannot view")
state.Monsters[1].Carried = nil; state.Monsters[1].Following = true; state.FollowingIds = {"M1","M2","M3","M4","M5"}; controller.Refresh()
propertySignal(find("ToggleFollowerButton"),"Activated"):Fire(); check(calls[#calls].Name == "ToggleFollower", "full capacity can remove existing follower")
state.Monsters[1].Following = nil; controller.Refresh(); local previous = #calls
propertySignal(find("ToggleFollowerButton"),"Activated"):Fire(); check(#calls == previous, "follower cap enforced before sending")
propertySignal(find("BenchTab"),"Activated"):Fire(); check(not find("M1").Visible and find("M3").Visible, "bench filter actual slots")
viewport = r.Vector2.new(390,320); camera.ViewportSize = viewport; propertySignal(camera,"ViewportSize"):Fire(); drain()
check(grid.FillDirectionMaxCells == 2, "mobile two columns")
check(frame.Size.X.Offset == 370, "mobile fits viewport")
check(find("InventoryContent").CanvasSize.Y.Offset > frame.Size.Y.Offset, "short viewport scrolls")
local detailHeight = find("SelectedMonster").Size.Y.Offset
check(find("SelectionHint").Position.Y.Offset >= find("Placement").Position.Y.Offset + find("Placement").Size.Y.Offset, "status does not overlap hint")
check(find("BenchButton").Position.Y.Offset >= find("SelectionHint").Position.Y.Offset + find("SelectionHint").Size.Y.Offset, "hint does not overlap action")
frame.Visible = false; propertySignal(frame,"Visible"):Fire(); drain()
for _, child in frame:GetDescendants() do check(not child:IsA("WorldModel"), "hidden frame releases model clones") end
controller.Destroy(); check(#ui.Panels == 0 and frame.Parent == nil, "destroy removes modal and panel reference")

local builds = 0
allowDeferred = true
modules.PlotService = { BuildMonsterModel = function(monster)
	builds += 1
	local model = r.Instance.new("Model")
	local part = r.Instance.new("Part"); part.Name = "ActualBody"; part.Parent = model
	local script = r.Instance.new("Script"); script.Parent = model
	local prompt = r.Instance.new("ProximityPrompt"); prompt.Parent = part
	local particles = r.Instance.new("ParticleEmitter"); particles.Parent = part
	local humanoid = r.Instance.new("Humanoid"); humanoid.Parent = model
	return model
end }
local portraits = luau.load(fs.readFile("src/server/MonsterPortraits.luau"), { environment = env, injectGlobals = true })()
portraits.Sync(player, { a = state.Monsters[1], b = state.Monsters[2] }); drain()
local bank = assert(playerGui:FindFirstChild("MonsterPortraitModels"))
check(bank:GetAttribute("OwnerUserId") == 123, "bank owner exact")
check(bank.Parent == playerGui, "bank replicates only under owner PlayerGui")
check(#bank:GetChildren() == 1 and builds == 1, "identical appearances deduplicated")
for _, item in bank:GetDescendants() do
	check(not item:IsA("LuaSourceContainer") and not item:IsA("ProximityPrompt") and not item:IsA("ParticleEmitter") and not item:IsA("Humanoid"), "unsafe descendant removed")
	if item:IsA("BasePart") then check(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery, "portrait parts inert") end
end
portraits.Sync(player, { a = state.Monsters[1] }); drain(); check(builds == 1, "unchanged sync does not rebuild")
portraits.Sync(player, {}); drain(); check(#bank:GetChildren() == 0, "sold monster appearance removed")
portraits.Remove(player); check(bank.Parent == nil, "player cleanup releases bank")
print(string.format("PASS: Monster Vault fixture (%d assertions)",count))


