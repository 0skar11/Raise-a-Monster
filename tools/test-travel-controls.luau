-- Exercise the real controller against imported pixel controls and fallbacks.
local fs, luau, roblox = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local function signal()
	local callbacks = {}
	local s = {}
	function s:Connect(callback) local key = {}; callbacks[key] = callback; return { Disconnect = function() callbacks[key] = nil end } end
	function s:Fire(...) for key, callback in table.clone(callbacks) do if callbacks[key] then callback(...) end end end
	function s:Count() local n = 0; for _ in callbacks do n += 1 end; return n end
	return s
end
local methods = {}
function methods:IsA(class) return self.ClassName == class or (class == "GuiObject" and (self.ClassName == "Frame" or self.ClassName == "TextLabel" or self.ClassName == "TextButton" or self.ClassName == "ImageLabel" or self.ClassName == "ImageButton")) end
function methods:GetFullName() return if self.Parent then self.Parent:GetFullName() .. "." .. self.Name else self.Name end
function methods:GetChildren() return table.clone(self.Children) end
function methods:GetDescendants() local out = {}; for _, child in self.Children do table.insert(out, child); for _, nested in child:GetDescendants() do table.insert(out, nested) end end; return out end
function methods:FindFirstChild(name) for _, child in self.Children do if child.Name == name then return child end end end
function methods:IsDescendantOf(ancestor) local p = self.Parent; while p do if p == ancestor then return true end; p = p.Parent end; return false end
function methods:GetPropertyChangedSignal(name) if not self.Signals[name] then self.Signals[name] = signal() end; return self.Signals[name] end
local function node(class, name, props)
	local values = { Name = name, Visible = true, Enabled = true, Text = "", Image = "", ImageTransparency = 0, AbsolutePosition = roblox.Vector2.new(300, 40), AbsoluteSize = roblox.Vector2.new(130, 44) }
	for key, value in props or {} do values[key] = value end
	return setmetatable({ ClassName = class, Children = {}, Signals = {}, Values = values, Activated = signal(), DescendantAdded = signal(), DescendantRemoving = signal() }, {
		__index = function(self, key) return methods[key] or self.Values[key] end,
		__newindex = function(self, key, value) if self.Values[key] ~= value then self.Values[key] = value; self:GetPropertyChangedSignal(key):Fire() end end,
	})
end
local function add(parent, child)
	child.Parent = parent; table.insert(parent.Children, child)
	local p = parent; while p do p.DescendantAdded:Fire(child); p = p.Parent end
end
local function remove(parent, child)
	local p = parent; while p do p.DescendantRemoving:Fire(child); p = p.Parent end
	table.remove(parent.Children, assert(table.find(parent.Children, child))); child.Parent = nil
end
local pending = {}
local function flush() while #pending > 0 do local batch = pending; pending = {}; for _, callback in batch do callback() end end end
local workspace = node("Workspace", "Workspace", { CurrentCamera = node("Camera", "Camera", { ViewportSize = roblox.Vector2.new(1280, 720) }) })
local controls = luau.load(fs.readFile("src/client/TravelControls.luau"), { environment = {
	game = { GetService = function(_, name) assert(name == "Workspace"); return workspace end },
	task = { defer = function(callback) table.insert(pending, callback) end }, UDim2 = roblox.UDim2,
}, injectGlobals = true })()
local checks = 0
local function check(condition, message) checks += 1; assert(condition, message) end
local root = node("PlayerGui", "PlayerGui")
local fallback = {}
for _, name in { "HomeButton", "TeleportShopButton", "TeleportArenaButton" } do fallback[name] = node("TextButton", name) end
local sent = {}
local function teleport(destination) table.insert(sent, destination) end
local stop = controls.Start(root, fallback, teleport); flush()
fallback.HomeButton.Activated:Fire()
check(sent[#sent] == "Home" and fallback.HomeButton.Visible, "Generated fallback works before either authored row arrives")
local gui, bar = node("ScreenGui", "TravelBar"), node("Frame", "Bar")
add(gui, bar); add(root, gui); flush()
check(fallback.HomeButton.Visible and not bar.Visible, "An incomplete rounded row cannot replace the working fallback")
local rounded = {}
for name in fallback do rounded[name] = node("TextButton", name); add(bar, rounded[name]) end
local scale = node("UIScale", "ResponsiveScale", { Scale = 1 }); add(bar, scale); flush()
for name, button in fallback do check(not button.Visible and button.Activated:Count() == 0, "Rounded row replaces generated fallback once: " .. name) end
check(bar.Visible and rounded.HomeButton.Activated:Count() == 1, "Late completion enables the rounded backup row")

local spec = {
	ShopButton = { Image = "111500305245467", Destination = "Shop" },
	RollButton_2 = { Image = "138727217312430", Destination = "Home" },
	RollButton_3 = { Image = "122186044632966", Destination = "Arena" },
}
local pixelRoot, pixel, images, captions = node("ScreenGui", "ToShop"), {}, {}, {}
for name, item in spec do
	pixel[name] = node("TextButton", name, { AbsolutePosition = roblox.Vector2.new(300, -80), AbsoluteSize = roblox.Vector2.new(130, 44) })
	images[name] = node("ImageLabel", if name == "ShopButton" then "RollButtonBackground" else "Background", { Image = "rbxassetid://" .. item.Image })
	captions[name] = node("TextLabel", "sssssssssss", { Text = item.Destination:upper() })
	add(pixel[name], images[name]); add(pixel[name], captions[name])
	if name ~= "RollButton_3" then add(pixelRoot, pixel[name]) end
end
add(root, pixelRoot); flush()
check(bar.Visible and not pixel.ShopButton.Visible and not pixel.RollButton_2.Visible, "A partial imported row yields to the complete backup and avoids mixed duplicate controls")
add(pixelRoot, pixel.RollButton_3); flush()
check(not bar.Visible and not fallback.HomeButton.Visible, "The complete original pixel row hides both rounded and generated controls")
for name, item in spec do
	check(pixel[name].Visible and images[name].Visible and captions[name].Visible, "Original pixel artwork and its caption remain visible: " .. name)
	check(pixel[name].AbsolutePosition.Y == -80 and pixel[name].Size == nil and pixel[name].Position == nil, "Imported geometry is preserved even before layout: " .. name)
	local before = #sent; pixel[name].Activated:Fire()
	check(#sent == before + 1 and sent[#sent] == item.Destination and pixel[name].Activated:Count() == 1, "Pixel button maps to the correct destination exactly once: " .. name)
end
check(rounded.HomeButton.Activated:Count() == 0 and fallback.HomeButton.Activated:Count() == 0, "Inactive button sets release every controller action")
local nativeScript = node("LocalScript", "TeleportToShop")
add(pixelRoot, nativeScript); flush()
for name in spec do check(pixel[name].Visible and pixel[name].Activated:Count() == 0, "Enabled native TeleportToShop owns the imported binding without hiding its artwork: " .. name) end
check(not bar.Visible and not fallback.HomeButton.Visible, "Delegating to the native script keeps other travel rows hidden")
nativeScript.Enabled = false; flush()
for name, item in spec do
	local before = #sent; pixel[name].Activated:Fire()
	check(pixel[name].Activated:Count() == 1 and #sent == before + 1 and sent[#sent] == item.Destination, "Disabled native script yields exactly one controller binding: " .. name)
end
nativeScript.Enabled = true
local beforeNativeRefresh = #sent; pixel.ShopButton.Activated:Fire()
check(#sent == beforeNativeRefresh, "Newly enabled native ownership blocks a stale callback before deferred refresh")
flush()
check(pixel.ShopButton.Activated:Count() == 0, "Re-enabling native ownership releases the module callback")
nativeScript.Name = "OtherScript"; flush()
check(pixel.ShopButton.Activated:Count() == 1, "Renaming the native script releases ownership to this controller")
nativeScript.Name = "TeleportToShop"; flush()
check(pixel.ShopButton.Activated:Count() == 0, "Restoring the native script name releases this controller binding")
remove(pixelRoot, nativeScript); flush()
check(pixel.ShopButton.Activated:Count() == 1 and nativeScript.Signals.Enabled:Count() == 0, "Removing the native script restores one binding and disconnects its property watchers")
local unrelatedScript = node("Script", "TeleportToShop"); add(pixelRoot, unrelatedScript); flush()
check(pixel.ShopButton.Activated:Count() == 1, "A server Script with the same name cannot claim client travel ownership")
remove(pixelRoot, unrelatedScript); flush()
bar.Visible = true; flush()
check(not bar.Visible and pixel.ShopButton.Visible, "A rounded GUI updater cannot bring the duplicate controls back")
local custom = node("ScreenGui", "Framewisp_Keep")
local customCaption = node("TextLabel", "SHOP", { Text = "SHOP" }); add(custom, customCaption); add(root, custom)
local cash = node("ScreenGui", "CashCounter")
local cashImage = node("ImageLabel", "RollButtonBackground", { Image = "rbxassetid://111500305245467" }); add(cash, cashImage); add(root, cash); flush()
check(custom.Enabled and customCaption.Visible and cash.Enabled and cashImage.Visible, "Other Framewisp, cash, and settings content is never suppressed by semantic or geometry guesses")
for i = 1, 8 do add(custom, node("Frame", "Unrelated" .. i)); flush() end
check(pixel.ShopButton.Activated:Count() == 1, "Unrelated tree changes never accumulate action handlers")

pixelRoot.Enabled = false; flush()
check(bar.Visible and pixel.ShopButton.Visible and rounded.HomeButton.Activated:Count() == 1, "Disabled imported roots restore their original visibility and reactivate the backup")
pixelRoot.Enabled = true; flush()
check(not bar.Visible and pixel.ShopButton.Activated:Count() == 1, "Re-enabling imports selects them without duplicate handlers")
images.ShopButton.Image = "rbxassetid://999999"; flush()
check(bar.Visible and pixel.ShopButton.Activated:Count() == 0 and rounded.HomeButton.Activated:Count() == 1, "An unrecognized asset invalidates the imported set and releases its binding")
images.ShopButton.Image = "rbxassetid://111500305245467"; flush()
check(not bar.Visible and pixel.ShopButton.Visible, "Late replacement by the verified image restores the pixel row")
images.ShopButton.ImageTransparency = 1; flush()
check(bar.Visible and not pixel.RollButton_2.Visible, "A missing visible image uses one complete backup row")
images.ShopButton.ImageTransparency = 0; flush()
check(not bar.Visible and pixel.RollButton_2.Visible, "Visible imported artwork can become primary again")
pixel.ShopButton.Visible = false; flush()
check(bar.Visible and not pixel.ShopButton.Visible, "An author-hidden imported button is respected and triggers the backup")
pixel.ShopButton.Visible = true; flush()
check(not bar.Visible and pixel.ShopButton.Visible, "An author can reveal an imported button again without a tree change")
pixel.ShopButton.Name = "OtherButton"; flush()
check(bar.Visible and pixel.ShopButton.Activated:Count() == 0, "Renaming outside the verified button path releases its route")
pixel.ShopButton.Name = "ShopButton"; flush()
check(not bar.Visible and pixel.ShopButton.Activated:Count() == 1, "Restoring the verified name restores the pixel primary")
pixelRoot.Name = "ToHome"; flush()
check(bar.Visible and pixel.ShopButton.Visible, "Identical assets outside the verified ToShop root are preserved and unbound")
pixelRoot.Name = "ToShop"; flush()
check(not bar.Visible, "Restoring the exact root selects its original artwork again")
remove(pixelRoot, pixel.ShopButton); add(cash, pixel.ShopButton); flush()
check(bar.Visible and pixel.ShopButton.Visible and pixel.ShopButton.Activated:Count() == 0, "Reparenting outside the import releases binding without hiding unrelated cash content")
remove(cash, pixel.ShopButton); add(pixelRoot, pixel.ShopButton); flush()
check(not bar.Visible and pixel.ShopButton.Activated:Count() == 1, "Reinserting a verified button restores one route")
remove(root, pixelRoot); flush()
check(bar.Visible and pixel.ShopButton.Visible and pixel.ShopButton.Activated:Count() == 0 and images.ShopButton.Signals.Image:Count() == 0, "Removing imports restores their properties and releases image subscriptions")
gui.Enabled = false; flush()
check(fallback.HomeButton.Visible and fallback.HomeButton.Activated:Count() == 1, "Unavailable authored rows select the generated fallback")
gui.Enabled = true; flush()
workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(360, 640); flush()
check(bar.Size.X.Offset == 336 and rounded.TeleportArenaButton.Position.X.Offset + rounded.TeleportArenaButton.Size.X.Offset == 336, "Rounded backup alone remains responsive on a small viewport")
check(rounded.HomeButton.Size.Y.Offset == 44 and scale.Scale == 1, "Backup buttons retain a 44px touch height")
add(root, pixelRoot); flush()
check(not bar.Visible and pixel.ShopButton.Visible and pixel.ShopButton.AbsolutePosition.Y == -80, "Pixel artwork is selected again without resizing its authored geometry")

local stopAgain = controls.Start(root, fallback, teleport); flush(); stop()
check(pixel.ShopButton.Activated:Count() == 1 and not bar.Visible, "Repeated Start replaces subscriptions; the old Stop cannot stop the new controller")
stopAgain(); stopAgain(); flush()
check(bar.Visible and fallback.HomeButton.Visible and pixel.ShopButton.Visible and pixel.ShopButton.Activated:Count() == 0 and root.DescendantAdded:Count() == 0, "Teardown restores all owned visibility and disconnects actions idempotently")
local initiallyHiddenRoot = node("PlayerGui", "OtherPlayerGui")
local initiallyHiddenFallback = {}
for name in fallback do initiallyHiddenFallback[name] = node("TextButton", name, { Visible = false }) end
local stopHidden = controls.Start(initiallyHiddenRoot, initiallyHiddenFallback, teleport); flush(); stopHidden(); flush()
check(not initiallyHiddenFallback.HomeButton.Visible, "Teardown preserves fallback buttons that were initially hidden")
print("PASS:", checks, "primary travel controls checks")
