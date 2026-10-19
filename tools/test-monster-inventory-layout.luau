-- Execute the real MonsterInventory.Init and UI widget constructors offline.
-- Geometry is resolved from actual production instances; Lune has no GUI renderer.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function signal()
    local listeners = {}
    return { Connect = function(_, fn) table.insert(listeners, fn); return { Disconnect = function() end } end,
        Fire = function(_, ...) for _, fn in listeners do fn(...) end end }
end
local properties, activated = {}, {}
local function changed(instance, name)
    properties[instance] = properties[instance] or {}
    properties[instance][name] = properties[instance][name] or signal()
    return properties[instance][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", changed)
r.implementProperty("TextButton", "Activated", function(button)
    activated[button] = activated[button] or signal()
    return activated[button]
end)
local colors = {}
for _, name in { "Panel", "PanelLight", "Text", "SubText", "Yellow", "Green", "Red", "Blue", "Gray" } do colors[name] = r.Color3.new(0.5, 0.5, 0.5) end
local modules = {
    Config = { Followers = { MinLevel = 25, MaxCount = 5 } }, MonsterMath = { FormatNumber = tostring },
    GuiTheme = { Colors = colors, Gloss = function() end, ButtonFeedback = function() end },
}
local camera = { ViewportSize = r.Vector2.new(480, 320), GetPropertyChangedSignal = changed }
local workspace = { CurrentCamera = camera, GetPropertyChangedSignal = changed }
local guiService = { GetGuiInset = function() return r.Vector2.new(0, 36), r.Vector2.zero end }
local input = { GamepadEnabled = true }
local services = {
    ReplicatedStorage = { Shared = { Config = "Config", MonsterMath = "MonsterMath" } },
    TweenService = {}, GuiService = guiService, UserInputService = input,
}
local env = {
    game = { GetService = function(_, name) return assert(services[name], name) end },
    workspace = workspace, script = { Parent = { UI = "UI", GuiTheme = "GuiTheme" } },
    require = function(name) return assert(modules[name], name) end,
}
for key, value in r do env[key] = value end
modules.UI = luau.load(fs.readFile("src/client/UI.luau"), { environment = env, injectGlobals = true })()
local inventory = luau.load(fs.readFile("src/client/MonsterInventory.luau"), { environment = env, injectGlobals = true })()
local ui = { Gui = r.Instance.new("ScreenGui"), Panels = {} }
local scale = r.Instance.new("UIScale")
scale.Scale = 0.6
scale.Parent = ui.Gui
local state = { Monsters = {}, Eggs = { { Slot = 3 } }, UnlockedSlots = 3, MaxSlots = 6 }
for index = 1, 12 do
    table.insert(state.Monsters, { Id = "Monster" .. index, DisplayName = "Monster " .. index, Species = "Blob", Level = index, ActualIncome = 100 - index, Slot = if index <= 2 then index else 0 })
end
local calls, remotes = {}, {}
for _, name in { "PlaceMonster", "AutoPlaceMonsters", "BenchMonster" } do
    remotes[name] = { FireServer = function(_, ...) table.insert(calls, { Name = name, Args = table.pack(...) }) end }
end
local viewed
local controller = inventory.Init(ui, remotes, function() return state end, function(id) viewed = id end)
controller.Open()
local frame = controller.Frame
local body = assert(frame:FindFirstChild("InventoryContent"))
local collection = assert(body:FindFirstChild("Collection"))
local slots = assert(body:FindFirstChild("BaseSlots"))
local function button(text)
    for _, item in frame:GetDescendants() do if item:IsA("TextButton") and item.Text == text then return item end end
    error("Missing button " .. text)
end
local auto, bench, view = button("Auto Place"), button("Move to bench"), button("View selected")
local function rectangle(item, width, height)
    local w = item.Size.X.Scale * width + item.Size.X.Offset
    local h = item.Size.Y.Scale * height + item.Size.Y.Offset
    local x = item.Position.X.Scale * width + item.Position.X.Offset - item.AnchorPoint.X * w
    local y = item.Position.Y.Scale * height + item.Position.Y.Offset - item.AnchorPoint.Y * h
    return { x = x, y = y, w = w, h = h }
end
for _, viewport in { r.Vector2.new(480, 320), r.Vector2.new(568, 320), r.Vector2.new(320, 568), r.Vector2.new(1280, 720) } do
    camera.ViewportSize = viewport
    changed(camera, "ViewportSize"):Fire()
    local w, h = frame.Size.X.Offset, frame.Size.Y.Offset
    check(w <= viewport.X - 16 and h <= viewport.Y - 52, "Panel fits viewport and 36px inset")
    check(math.abs(scale.Scale * frame.NativeInventoryScale.Scale - 1) < 0.0001, "Native 44px targets survive HUD scale")
    local bodyRect = rectangle(body, w, h)
    local closeRect = rectangle(frame.CloseButton, w, h)
    check(bodyRect.y >= closeRect.y + closeRect.h and bodyRect.y + bodyRect.h <= h, "Fixed close control is outside scrolling body")
    local regions = {}
    for _, item in body:GetChildren() do
        if item:IsA("GuiObject") then
            local rect = rectangle(item, bodyRect.w, bodyRect.h)
            check(rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= bodyRect.w and rect.y + rect.h <= body.CanvasSize.Y.Offset, "Content stays inside scroll canvas: " .. item.Name)
            check(rect.w > 0 and rect.h > 0, "Positive content dimensions")
            for _, other in regions do
                check(not (rect.x < other.x + other.w and other.x < rect.x + rect.w and rect.y < other.y + other.h and other.y < rect.y + rect.h), "No overlap between actual body instances")
            end
            table.insert(regions, rect)
        end
    end
    for _, item in { auto, bench, view, frame.CloseButton } do
        local rect = rectangle(item, bodyRect.w, bodyRect.h)
        check(rect.w >= 44 and rect.h >= 44, "Action targets remain at least 44px")
    end
    for _, scroll in { collection, slots } do
        local rect = rectangle(scroll, bodyRect.w, bodyRect.h)
        check(scroll.AutomaticCanvasSize == r.Enum.AutomaticSize.Y and rect.h >= 68, "Lists scroll with at least one complete row visible")
        local rowsHeight, count = 7, 0
        for _, item in scroll:GetChildren() do
            if item:IsA("TextButton") then
                count += 1
                rowsHeight += item.Size.Y.Offset + 9
                check(item.Size.Y.Offset >= 44, "Collection and slot touch targets stay native sized")
            end
        end
        check(count > 0 and rowsHeight > rect.h, "Long list reaches beyond visible area using automatic canvas")
    end
    if viewport.Y == 320 or viewport.X == 320 then
        check(body.CanvasSize.Y.Offset > bodyRect.h, "Compact viewport can scroll to footer without overlap")
    end
    local footer = rectangle(bench, bodyRect.w, bodyRect.h)
    local bottomScroll = body.CanvasSize.Y.Offset - bodyRect.h
    check(footer.y + footer.h - math.max(0, bottomScroll) <= bodyRect.h, "Footer reachable at end of outer canvas")
end
check(guiService.SelectedObject == auto, "Gamepad opens with focus on Auto Place")
collection.CanvasPosition = r.Vector2.new(0, 80)
slots.CanvasPosition = r.Vector2.new(0, 30)
local selected = collection:FindFirstChild("Monster1")
guiService.SelectedObject = selected
selected.Activated:Fire()
check(guiService.SelectedObject == collection:FindFirstChild("Monster1") and guiService.SelectedObject ~= selected, "Selecting monster preserves gamepad focus after row rebuild")
check(collection.CanvasPosition.Y == 80 and slots.CanvasPosition.Y == 30, "Selection preserves both list scroll positions")
check(bench.Active and bench.Selectable and view.Active, "Selected placed monster enables bench and view")
slots.Slot2.Activated:Fire()
check(calls[#calls].Name == "PlaceMonster" and calls[#calls].Args[1] == "Monster1" and calls[#calls].Args[2] == 2, "Occupied slot requests selected-monster swap")
check(slots.Slot2.Text:find("Swap") ~= nil, "Occupied slot displays Swap")
local before = #calls
slots.Slot3.Activated:Fire()
slots.Slot4.Activated:Fire()
check(#calls == before, "Egg and locked slots reject place requests")
auto.Activated:Fire()
check(calls[#calls].Name == "AutoPlaceMonsters", "Auto Place uses correct remote")
bench.Activated:Fire()
check(calls[#calls].Name == "BenchMonster" and calls[#calls].Args[1] == "Monster1", "Bench uses selected ID")
view.Activated:Fire()
check(viewed == "Monster1", "View opens selected monster")
local cursor, reached = auto, {}
for _ = 1, 40 do
    reached[cursor] = true
    local nextButton = cursor.NextSelectionDown
    check(nextButton ~= nil and nextButton.NextSelectionUp == cursor, "Gamepad links are reciprocal")
    cursor = nextButton
    if cursor == auto then break end
end
check(reached[bench] and reached[view] and reached[slots.Slot6] and reached[collection.Monster12] and reached[frame.CloseButton], "Gamepad cycle reaches every action, list and close")
state.Monsters[1].Carried = true
controller.Refresh()
before = #calls
bench.Activated:Fire()
check(#calls == before and not bench.Selectable, "Unavailable monster cannot be benched or focused via bench action")
state.Monsters = {}
controller.Refresh()
check(not bench.Active and not view.Active and #collection:GetChildren() >= 3, "Empty collection clears selection safely")
frame.CloseButton.Activated:Fire()
check(not frame.Visible, "Fixed close button closes panel")
print(string.format("PASS: %d actual MonsterInventory layout, interaction and gamepad checks", checks))
