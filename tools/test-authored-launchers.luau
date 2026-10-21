-- Exercise exact authored launcher selection, callbacks, and lifecycle cleanup.
local fs, luau = require("@lune/fs"), require("@lune/luau")
local function signal()
	local callbacks = {}
	local out = {}
	function out:Connect(callback)
		local key = {}; callbacks[key] = callback
		return { Disconnect = function() callbacks[key] = nil end }
	end
	function out:Fire(...) for key, callback in table.clone(callbacks) do if callbacks[key] then callback(...) end end end
	function out:Count() local n = 0; for _ in callbacks do n += 1 end; return n end
	return out
end
local methods = {}
function methods:IsA(class)
	return self.ClassName == class or (class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton"))
		or (class == "GuiObject" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton" or self.ClassName == "Frame" or self.ClassName == "ImageLabel"))
end
function methods:GetChildren() return table.clone(self.Children) end
function methods:FindFirstChild(name) for _, child in self.Children do if child.Name == name then return child end end end
function methods:IsDescendantOf(ancestor) local p = self.Parent; while p do if p == ancestor then return true end; p = p.Parent end; return false end
function methods:GetPropertyChangedSignal(name) self.Signals[name] = self.Signals[name] or signal(); return self.Signals[name] end
local function node(class, name, values)
	local properties = { Name = name, Visible = true, Enabled = true, Position = "original position", Size = "original size", Text = "original text", Image = "original image" }
	for key, value in values or {} do properties[key] = value end
	return setmetatable({ ClassName = class, Children = {}, Signals = {}, Properties = properties, Activated = signal(), DescendantAdded = signal(), DescendantRemoving = signal() }, {
		__index = function(self, key) return methods[key] or self.Properties[key] end,
		__newindex = function(self, key, value) if self.Properties[key] ~= value then self.Properties[key] = value; self:GetPropertyChangedSignal(key):Fire() end end,
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
local launchers = luau.load(fs.readFile("src/client/AuthoredLaunchers.luau"), { environment = {
	task = { defer = function(callback) table.insert(pending, callback) end },
}, injectGlobals = true })()
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local root, generated = node("PlayerGui", "PlayerGui"), node("ScreenGui", "RaiseAMonsterUI")
add(root, generated)
local fallback, actions, counts = {}, {}, {}
for _, name in { "Shop", "Rewards", "Trade" } do
	fallback[name] = node("TextButton", name); add(generated, fallback[name]); counts[name] = 0
	actions[name] = function() counts[name] += 1 end
end
local stop = launchers.Start(root, fallback, actions); flush()
for name, button in fallback do button.Activated:Fire(); check(counts[name] == 1 and button.Visible, name .. " fallback works before authored controls arrive") end
local shop, button = node("ScreenGui", "ShopGui"), node("TextButton", "shop")
add(shop, button); add(root, shop); flush()
check(button.Visible and not fallback.Shop.Visible and fallback.Rewards.Visible and fallback.Trade.Visible, "Only the exact replacement's fallback is hidden")
check(button.Activated:Count() == 1 and fallback.Shop.Activated:Count() == 0, "Exactly one Shop input owner exists")
button.Activated:Fire(); check(counts.Shop == 2, "Authored Shop invokes the existing callback")
check(button.Position == "original position" and button.Size == "original size" and button.Text == "original text" and button.Image == "original image", "Authored appearance and placement are untouched")
for i = 1, 8 do add(generated, node("Frame", "Unrelated" .. i)); flush() end
check(button.Activated:Count() == 1, "Unrelated descendants do not add duplicate handlers")
fallback.Shop.Visible = true; flush(); check(not fallback.Shop.Visible, "A legacy updater cannot reshow the duplicate launcher")
button.Visible = false; flush(); check(fallback.Shop.Visible and button.Activated:Count() == 0, "Hidden authored control restores a reachable fallback")
button.Visible = true; flush(); check(not fallback.Shop.Visible and button.Activated:Count() == 1, "Showing authored control restores its single callback")
shop.Enabled = false; flush(); check(fallback.Shop.Visible and button.Visible, "Disabling authored GUI restores fallback without changing authored visibility")
shop.Enabled = true; flush(); check(not fallback.Shop.Visible, "Re-enabled GUI is selected again")
button.Name = "Another button"; flush(); check(fallback.Shop.Visible and button.Activated:Count() == 0, "Wrong button names never claim the action")
button.Name = "shop"; flush(); check(button.Activated:Count() == 1, "Restored exact name becomes active again")
local duplicateChild = node("TextButton", "shop"); add(shop, duplicateChild); flush()
check(fallback.Shop.Visible and button.Activated:Count() == 0 and duplicateChild.Activated:Count() == 0, "Duplicate children at the exact path cannot select the wrong control")
remove(shop, duplicateChild); flush()
local duplicate, duplicateButton = node("ScreenGui", "ShopGui"), node("TextButton", "shop")
add(duplicate, duplicateButton); add(root, duplicate); flush()
check(fallback.Shop.Visible and button.Visible and duplicateButton.Visible, "Ambiguous authored GUI preserves both artworks and uses fallback")
remove(root, duplicate); flush(); check(not fallback.Shop.Visible and button.Activated:Count() == 1, "Resolving ambiguity restores one authored binding")
local custom, customButton = node("ScreenGui", "Framewisp_Keep"), node("TextButton", "shop")
add(custom, customButton); add(root, custom); flush()
check(custom.Enabled and customButton.Visible and customButton.Activated:Count() == 0, "No semantic or geometry guessing touches other authored UI")
local gifts, trade = node("ImageButton", "gifts"), node("TextButton", "trade")
add(shop, gifts); add(shop, trade); flush()
for name, authored in { Rewards = gifts, Trade = trade } do
	check(not fallback[name].Visible and authored.Visible and authored.Activated:Count() == 1, name .. " exact Studio control replaces only its matching fallback")
	authored.Activated:Fire(); check(counts[name] == 2, name .. " invokes its existing panel callback once")
	check(authored.Position == "original position" and authored.Size == "original size" and authored.Text == "original text", name .. " artwork and authored layout are preserved")
end
gifts.Visible = false; flush(); check(fallback.Rewards.Visible and not fallback.Trade.Visible, "Each launcher falls back independently when an authored sibling is hidden")
gifts.Visible = true; flush()
remove(root, shop); flush(); check(fallback.Shop.Visible and button.Activated:Count() == 0, "Removing authored GUI disconnects input and restores fallback")
check(shop.Signals.Enabled:Count() == 0 and button.Signals.Visible:Count() == 0, "Removed control property watchers are cleaned up")
add(root, shop); flush()
local oldButton = button
remove(shop, oldButton)
button = node("ImageButton", "shop"); add(shop, button); flush()
check(oldButton.Activated:Count() == 0 and button.Activated:Count() == 1 and not fallback.Shop.Visible, "Replacing the authored button disconnects the old instance and binds the new one once")
local beforeReplacement = counts.Shop; oldButton.Activated:Fire(); button.Activated:Fire()
check(counts.Shop == beforeReplacement + 1, "Only the replacement's activation opens its existing panel")
stop(); flush()
check(fallback.Shop.Visible and button.Visible and button.Activated:Count() == 0, "Cleanup restores original visibility without altering authored artwork")
for name, backup in fallback do check(backup.Activated:Count() == 0, name .. " fallback callback is disconnected on cleanup") end
check(root.DescendantAdded:Count() == 0 and root.DescendantRemoving:Count() == 0, "Cleanup disconnects root observers")
local again = launchers.Start(root, fallback, actions); local replacement = launchers.Start(root, fallback, actions); flush()
check(button.Activated:Count() == 1, "Repeated Start replaces the old controller instead of duplicating bindings")
again(); check(button.Activated:Count() == 1, "Stale cleanup cannot disconnect a newer controller")
replacement(); flush()
print("Authored launchers: " .. checks .. " checks PASS")
