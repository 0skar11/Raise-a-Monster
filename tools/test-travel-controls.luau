-- Exercise the real controller with GUI/signal fixtures, including late authored bars.
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
local diagnostics = {}
local controls = luau.load(fs.readFile("src/client/TravelControls.luau"), { environment = {
	game = { GetService = function(_, name) assert(name == "Workspace"); return workspace end },
	task = { defer = function(callback) table.insert(pending, callback) end }, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2,
	print = function(message) table.insert(diagnostics, tostring(message)) end,
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
check(sent[#sent] == "Home" and fallback.HomeButton.Visible, "Fallback works before the primary bar arrives")
local gui, bar = node("ScreenGui", "TravelBar"), node("Frame", "Bar")
add(gui, bar); add(root, gui); flush()
check(fallback.HomeButton.Visible, "Incomplete authored bar must not remove working fallback")
local buttons = {}
for name in fallback do buttons[name] = node("TextButton", name); add(bar, buttons[name]) end
local scale = node("UIScale", "ResponsiveScale", { Scale = 1 }); add(bar, scale); flush()
for name, button in fallback do check(not button.Visible and button.Activated:Count() == 0, "Primary replaces fallback without a second active binding: " .. name) end
for name, destination in { HomeButton = "Home", TeleportShopButton = "Shop", TeleportArenaButton = "Arena" } do
	buttons[name].Activated:Fire(); check(sent[#sent] == destination and buttons[name].Activated:Count() == 1, "Primary fires the correct destination exactly once: " .. name)
end
local legacy = node("ScreenGui", "Framewisp_OldTravel")
local oldButton = node("Frame", "ButtonShell")
local text = node("TextLabel", "Caption", { Text = "HOME" })
local image = node("ImageLabel", "OldArtwork")
add(oldButton, text); add(oldButton, image); add(legacy, oldButton)
local unrelated = node("TextLabel", "Balance", { Text = "14k", AbsolutePosition = roblox.Vector2.new(10, 600) }); add(legacy, unrelated)
add(root, legacy); flush()
check(not oldButton.Visible and image.Visible, "Hide only the identified small legacy branch, preserving its children for restoration")
check(unrelated.Visible and legacy.Enabled, "A mixed legacy ScreenGui and its cash content are not disabled")
oldButton.Visible = true
check(not oldButton.Visible, "The old updater cannot reactivate the duplicate travel artwork")
oldButton.AbsoluteSize = roblox.Vector2.new(500, 300); flush()
check(oldButton.Visible and not text.Visible and image.Visible, "A legacy shell expanded into unrelated UI must be restored; hide only the still-valid caption")
oldButton.AbsoluteSize = roblox.Vector2.new(130, 44); flush()
check(not oldButton.Visible and text.Visible, "A bounded shell may be suppressed again without changing its child's original visibility")
local shop = node("ScreenGui", "ShopGui"); local shopTitle = node("TextLabel", "Title", { Text = "SHOP" }); add(shop, shopTitle); add(root, shop); flush()
check(shopTitle.Visible and shop.Enabled, "The actual shop GUI must not be hidden")
local unknown = node("ImageLabel", "UnidentifiedArtwork"); add(legacy, unknown); flush()
check(unknown.Visible, "Unknown image-only artwork must not be guessed or deleted")
-- Reproduce the observed three old images above/behind the real primary row.
local primaryPositions = { HomeButton = 307, TeleportShopButton = 451, TeleportArenaButton = 595 }
for name, x in primaryPositions do
	buttons[name].AbsolutePosition = roblox.Vector2.new(x, 240)
	buttons[name].AbsoluteSize = roblox.Vector2.new(136, 44)
end
local imageRoots = { node("ScreenGui", "Framewisp_ImageHome"), node("ScreenGui", "Framewisp_ImageShop"), node("ScreenGui", "Framewisp_ImageArena") }
local imageLayer = node("Frame", "Layer", { Visible = false })
add(imageRoots[1], imageLayer)
local oldImages = {
	node("ImageLabel", "Imported1", { Image = "rbxassetid://10001", AbsolutePosition = roblox.Vector2.new(306, 219), AbsoluteSize = roblox.Vector2.new(111, 40) }),
	node("ImageButton", "Imported2", { Image = "rbxassetid://10002", AbsolutePosition = roblox.Vector2.new(453, 205), AbsoluteSize = roblox.Vector2.new(137, 48) }),
	node("ImageLabel", "Imported3", { Image = "rbxassetid://10003", AbsolutePosition = roblox.Vector2.new(620, 218), AbsoluteSize = roblox.Vector2.new(116, 40) }),
}
add(imageLayer, oldImages[1]); add(imageRoots[2], oldImages[2]); add(imageRoots[3], oldImages[3])
for _, imageRoot in imageRoots do add(root, imageRoot) end; flush()
check(oldImages[2].Visible and oldImages[3].Visible, "A hidden ancestor makes the image row incomplete; preserve the other columns")
imageLayer.Visible = true; flush()
check(not oldImages[1].Visible and not oldImages[2].Visible and not oldImages[3].Visible, "Exact screenshot positions match and hide all three image-only imports when their parent becomes visible")
check(imageRoots[1].Enabled and imageLayer.Visible, "Image cleanup never disables whole retained GUI containers")
local matchedMessages = 0
for _, message in diagnostics do if message:find("Matched legacy image row", 1, true) then matchedMessages += 1 end end
check(matchedMessages == 1 and diagnostics[#diagnostics]:find("rbxassetid://10001", 1, true) ~= nil, "A successful row reports its actual paths and asset IDs once")
oldImages[1].Visible = true; flush()
check(not oldImages[1].Visible and not oldImages[2].Visible and not oldImages[3].Visible, "Controller-owned hidden state remains an originally visible coherent group")
local messageCount = #diagnostics
add(imageRoots[2], node("Frame", "Unrelated")); flush()
check(#diagnostics == messageCount, "Unrelated refreshes do not spam diagnostic logs")
local ambiguity = node("ImageLabel", "AnotherImport", { Image = "rbxassetid://20001", AbsolutePosition = oldImages[1].AbsolutePosition, AbsoluteSize = oldImages[1].AbsoluteSize })
add(imageRoots[1], ambiguity); flush()
check(oldImages[1].Visible and oldImages[2].Visible and oldImages[3].Visible and ambiguity.Visible, "Ambiguous image columns are all preserved instead of guessing")
remove(imageRoots[1], ambiguity); flush()
check(not oldImages[1].Visible and not oldImages[2].Visible and not oldImages[3].Visible, "Removing ambiguity restores the uniquely identified row")
oldImages[3].Image = ""; flush()
check(oldImages[1].Visible and oldImages[2].Visible, "Partial rows and empty image placeholders do not suppress other UI")
oldImages[3].Image = "rbxassetid://10003"; flush()
check(not oldImages[1].Visible and not oldImages[2].Visible and not oldImages[3].Visible, "Late image content is matched without requiring a tree or geometry change")
imageRoots[3].Enabled = false; flush()
check(oldImages[1].Visible and oldImages[2].Visible, "Disabled retained roots invalidate the group and restore its other images")
imageRoots[3].Enabled = true; flush()
oldImages[2].AbsolutePosition = roblox.Vector2.new(453, 300); flush()
check(oldImages[1].Visible and oldImages[2].Visible and oldImages[3].Visible, "An image moved away from the primary row restores the whole unmatched group")
oldImages[2].AbsolutePosition = roblox.Vector2.new(453, 205); flush()
local cashRoot = node("ScreenGui", "CashCounter")
local protectedImage = node("ImageLabel", "CashGraphic", { Image = "rbxassetid://10001", AbsolutePosition = oldImages[1].AbsolutePosition, AbsoluteSize = oldImages[1].AbsoluteSize })
add(cashRoot, protectedImage); add(root, cashRoot); flush()
check(protectedImage.Visible and not oldImages[1].Visible, "CashCounter is excluded even with matching content and geometry")
oldImages[3].AbsolutePosition = roblox.Vector2.new(620, 247); flush()
check(oldImages[1].Visible and oldImages[2].Visible and oldImages[3].Visible, "Three images with inconsistent row heights are not treated as one old travel bar")
oldImages[3].AbsolutePosition = roblox.Vector2.new(620, 218); flush()
remove(imageRoots[3], oldImages[3]); add(cashRoot, oldImages[3]); flush()
check(oldImages[1].Visible and oldImages[2].Visible and oldImages[3].Visible, "Reparenting an image outside the retained travel roots restores it")
remove(cashRoot, oldImages[3]); add(imageRoots[3], oldImages[3]); flush()
for _, imageRoot in imageRoots do remove(root, imageRoot) end; remove(root, cashRoot); flush()
check(oldImages[1].Visible and oldImages[2].Visible and oldImages[3].Visible and oldImages[1].Signals.Image:Count() == 0, "Removed retained roots restore images and release their subscriptions")
-- Actual Studio paths and asset IDs: layout reported negative Y during startup.
local exactRoot = node("ScreenGui", "ToShop")
local exactButtons, exactImages = {}, {}
local retainedAssets = { ShopButton = "111500305245467", RollButton_2 = "138727217312430", RollButton_3 = "122186044632966" }
for name, asset in retainedAssets do
	local props = { AbsolutePosition = roblox.Vector2.new(300, -80), AbsoluteSize = roblox.Vector2.new(130, 44) }
	exactButtons[name] = node("TextButton", name, props)
	exactImages[name] = node("ImageLabel", "RollButtonBackground", {
		Image = "rbxassetid://" .. asset, AbsolutePosition = roblox.Vector2.new(300, -80), AbsoluteSize = roblox.Vector2.new(130, 44),
	})
	add(exactButtons[name], exactImages[name])
	local caption = node("TextLabel", "sssssssssss", { Text = "SHOP", AbsolutePosition = roblox.Vector2.new(300, -80) })
	add(exactButtons[name], caption); add(exactRoot, exactButtons[name])
end
add(root, exactRoot); flush()
for name in retainedAssets do
	check(not exactButtons[name].Visible and exactImages[name].Visible, "Verified Studio artwork hides its full input branch even at negative Y: " .. name)
end
local exactDiagnosticCount = 0
for _, message in diagnostics do if message:find("Matched legacy travel artwork", 1, true) then exactDiagnosticCount += 1 end end
check(exactDiagnosticCount == 3, "Each verified path and asset is logged once")
exactButtons.ShopButton.Visible = true; flush()
check(not exactButtons.ShopButton.Visible, "An old updater cannot reactivate a verified legacy input branch")
exactImages.ShopButton.Image = "rbxassetid://999999"; flush()
check(exactButtons.ShopButton.Visible and not exactButtons.RollButton_2.Visible, "Replacing an asset restores only that legacy branch")
exactImages.ShopButton.Image = "rbxassetid://111500305245467"; flush()
check(not exactButtons.ShopButton.Visible, "Restoring the verified asset suppresses its branch again")
exactImages.ShopButton.ImageTransparency = 1; flush()
check(not exactButtons.ShopButton.Visible, "Transparent verified artwork still suppresses its legacy caption and input branch")
exactImages.ShopButton.ImageTransparency = 0; flush()
exactImages.ShopButton.Visible = false; flush()
check(not exactButtons.ShopButton.Visible, "An invisible verified background cannot leave its legacy caption and input active")
exactImages.ShopButton.Visible = true; flush()
exactImages.ShopButton.Name = "UnrelatedArtwork"; flush()
check(exactButtons.ShopButton.Visible, "Renaming the image outside the verified path restores the branch")
exactImages.ShopButton.Name = "RollButtonBackground"; flush()
check(not exactButtons.ShopButton.Visible, "Restoring the exact image path suppresses the legacy branch")
exactButtons.ShopButton.Name = "UnrelatedButton"; flush()
check(exactButtons.ShopButton.Visible, "Renaming the button outside the verified path restores it")
exactButtons.ShopButton.Name = "ShopButton"; flush()
check(not exactButtons.ShopButton.Visible, "Restoring the verified button path suppresses it again")
local exactOtherRoot = node("ScreenGui", "CashCounter"); add(root, exactOtherRoot)
remove(exactRoot, exactButtons.ShopButton); add(exactOtherRoot, exactButtons.ShopButton); flush()
check(exactButtons.ShopButton.Visible and exactOtherRoot.Enabled, "Reparenting the same verified artwork to CashCounter restores the whole branch")
remove(exactOtherRoot, exactButtons.ShopButton); add(exactRoot, exactButtons.ShopButton); flush()
check(not exactButtons.ShopButton.Visible, "Reparenting back to the verified ToShop path suppresses it")
local unrelatedExactImage = node("ImageLabel", "RollButtonBackground", { Image = "rbxassetid://111500305245467", AbsolutePosition = roblox.Vector2.new(300, -80) })
local unrelatedExactBranch = node("ImageButton", "UnrelatedButton", { AbsolutePosition = roblox.Vector2.new(300, -80) })
add(unrelatedExactBranch, unrelatedExactImage); add(exactRoot, unrelatedExactBranch); flush()
check(unrelatedExactBranch.Visible and unrelatedExactImage.Visible, "A matching asset elsewhere in ToShop is preserved")
exactRoot.Enabled = false; flush()
check(exactButtons.ShopButton.Visible and exactButtons.RollButton_2.Visible and exactButtons.RollButton_3.Visible, "Disabling ToShop restores every previously visible exact branch")
exactRoot.Enabled = true; flush()
check(not exactButtons.ShopButton.Visible and not exactButtons.RollButton_2.Visible and not exactButtons.RollButton_3.Visible, "Re-enabling ToShop suppresses all verified branches without geometry")
exactRoot.Name = "ToHome"; flush()
check(exactButtons.ShopButton.Visible and exactButtons.RollButton_2.Visible, "Matching artwork in another legacy ScreenGui is not treated as the verified ToShop import")
exactRoot.Name = "ToShop"; flush()
remove(root, exactRoot); remove(root, exactOtherRoot); flush()
check(exactButtons.ShopButton.Visible and exactImages.ShopButton.Signals.Image:Count() == 0 and exactButtons.ShopButton.Signals.Name:Count() == 0, "Removing the exact legacy root restores its controls and releases asset and path subscriptions")
for _, button in buttons do button.AbsolutePosition = roblox.Vector2.new(300, 40); button.AbsoluteSize = roblox.Vector2.new(130, 44) end; flush()
local side = node("TextLabel", "Shop", { Text = "SHOP", AbsolutePosition = roblox.Vector2.new(10, 400) }); add(legacy, side); flush()
check(side.Visible, "Side navigation remains outside legacy top-travel cleanup")
local toShop = node("ScreenGui", "ToShop"); local importedImage = node("ImageLabel", "Imported"); add(toShop, importedImage); add(root, toShop); flush()
check(not importedImage.Visible, "The known standalone ToShop artwork is suppressed")
local lateShell = node("Frame", "LateShell")
local lateHome = node("TextLabel", "LateCaption", { Text = "HOME", AbsoluteSize = roblox.Vector2.zero })
add(lateShell, lateHome); add(legacy, lateShell); flush()
check(lateShell.Visible, "An unlaid-out candidate must not hide an unidentified branch")
lateHome.AbsoluteSize = roblox.Vector2.new(130, 44); flush()
check(not lateShell.Visible, "Legacy artwork hides when delayed GUI layout becomes valid without a text/tree change")
lateHome.AbsolutePosition = roblox.Vector2.new(300, 400); flush()
check(lateShell.Visible, "A candidate moved outside top travel bounds is restored")
workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(360, 640); flush()
check(bar.Size.X.Offset == 336 and math.abs(buttons.TeleportArenaButton.Position.X.Offset + buttons.TeleportArenaButton.Size.X.Offset - 336) < 0.001, "Primary row fits a small viewport with 12px side margins")
check(buttons.HomeButton.Size.Y.Offset == 44 and scale.Scale == 1, "Mobile travel controls retain 44px touch height")
workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1280, 720); flush()
gui.Enabled = false; flush()
check(fallback.HomeButton.Visible and oldButton.Visible and importedImage.Visible, "Disabling primary restores fallback and previously visible legacy branches")
gui.Enabled = true; flush()
check(not fallback.HomeButton.Visible and not oldButton.Visible and buttons.HomeButton.Activated:Count() == 1, "Re-enabling primary does not duplicate action connections")
remove(root, gui); flush()
check(fallback.HomeButton.Visible and buttons.HomeButton.Activated:Count() == 0 and oldButton.Visible, "Removed bars release actions and restore fallback")
add(root, gui); flush()
check(not fallback.HomeButton.Visible and buttons.HomeButton.Activated:Count() == 1, "A respawn/reinserted bar binds only once")
for i = 1, 10 do local extra = node("TextLabel", "Unrelated" .. i); add(legacy, extra); flush() end
check(buttons.HomeButton.Activated:Count() == 1, "Unrelated GUI additions cannot accumulate click handlers")
local stopAgain = controls.Start(root, fallback, teleport); flush(); stop()
check(buttons.HomeButton.Activated:Count() == 1, "Repeated Start replaces subscriptions; old Stop cannot stop the new controller")
stopAgain(); stopAgain(); flush()
check(fallback.HomeButton.Visible and oldButton.Visible and buttons.HomeButton.Activated:Count() == 0 and root.DescendantAdded:Count() == 0, "Stop is idempotent and cleans every active route")
print("PASS:", checks, "primary travel controls checks")
