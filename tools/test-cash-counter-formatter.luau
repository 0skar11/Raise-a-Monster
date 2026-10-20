-- Run the real formatter against fake GUI signals, including respawn/replacement.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local compact = luau.load(fs.readFile("src/shared/CompactMoney.luau"))()
local function signal()
	local callbacks = {}
	local result = {}
	function result:Connect(callback)
		local token = {}
		callbacks[token] = callback
		return { Disconnect = function() callbacks[token] = nil end }
	end
	function result:Fire(...)
		for token, callback in table.clone(callbacks) do
			if callbacks[token] then callback(...) end
		end
	end
	function result:Count()
		local count = 0
		for _ in callbacks do count += 1 end
		return count
	end
	return result
end
local methods = {}
function methods:IsA(className) return self.ClassName == className end
function methods:GetChildren() return table.clone(self.Children) end
function methods:GetDescendants()
	local result = {}
	for _, child in self.Children do
		table.insert(result, child)
		for _, nested in child:GetDescendants() do table.insert(result, nested) end
	end
	return result
end
function methods:GetPropertyChangedSignal(property)
	assert(property == "Text", "Only display text may be observed")
	return self.TextChanged
end
local function instance(className, name, text)
	return setmetatable({
		ClassName = className, Name = name, Children = {}, Properties = { Text = text or "" },
		TextChanged = signal(), ChildAdded = signal(), ChildRemoved = signal(),
		DescendantAdded = signal(), DescendantRemoving = signal(),
	}, {
		__index = function(self, key) return methods[key] or self.Properties[key] end,
		__newindex = function(self, key, value)
			if key == "Text" then
				if self.Properties.Text ~= value then self.Properties.Text = value; self.TextChanged:Fire() end
			else rawset(self, key, value) end
		end,
	})
end
local function descendantsIncluding(child)
	local result = child:GetDescendants()
	table.insert(result, 1, child)
	return result
end
local function add(parent, child)
	child.Parent = parent
	table.insert(parent.Children, child)
	parent.ChildAdded:Fire(child)
	local ancestor = parent
	while ancestor do
		for _, descendant in descendantsIncluding(child) do ancestor.DescendantAdded:Fire(descendant) end
		ancestor = ancestor.Parent
	end
end
local function remove(parent, child)
	local ancestor = parent
	while ancestor do
		for _, descendant in descendantsIncluding(child) do ancestor.DescendantRemoving:Fire(descendant) end
		ancestor = ancestor.Parent
	end
	table.remove(parent.Children, assert(table.find(parent.Children, child)))
	child.Parent = nil
	parent.ChildRemoved:Fire(child)
end
local shared = { WaitForChild = function(_, name) assert(name == "CompactMoney"); return "CompactMoney" end }
local replicated = { WaitForChild = function(_, name) assert(name == "Shared"); return shared end }
local formatter = luau.load(fs.readFile("src/client/CashCounterFormatter.luau"), { environment = {
	game = { GetService = function(_, name) assert(name == "ReplicatedStorage"); return replicated end },
	require = function(name) assert(name == "CompactMoney"); return compact end,
}, injectGlobals = true })()
local checks = 0
local function check(condition, message) checks += 1; assert(condition, message) end

local playerGui = instance("PlayerGui", "PlayerGui")
local other = instance("ScreenGui", "OtherGui")
local outside = instance("TextLabel", "Coins", "1,830,343,050,955")
add(other, outside); add(playerGui, other)
local cash = instance("ScreenGui", "CashCounter")
local frame = instance("Frame", "OriginalStudioFrame")
local balance = instance("TextLabel", "Balance", "1,830,343,050,955")
balance.Font = "OriginalFont"
balance.Position = "OriginalPosition"
local shadow = instance("TextLabel", "Shadow", balance.Text)
local title = instance("TextLabel", "Title", "COINS")
local income = instance("TextLabel", "Income", "+14,000/s")
local delta = instance("TextLabel", "Delta", "+14,000")
local malformed = instance("TextLabel", "Malformed", "14,5")
local textbox = instance("TextBox", "Input", "14,000")
for _, label in { balance, shadow, title, income, delta, malformed, textbox } do add(frame, label) end
add(cash, frame); add(playerGui, cash)
local stop = formatter.Start(playerGui)
check(balance.Text == "1.83t" and shadow.Text == "1.83t", "Initial balance and shadow must both fit")
check(balance.Parent == frame and balance.Font == "OriginalFont" and balance.Position == "OriginalPosition", "Studio design must be preserved")
check(title.Text == "COINS" and income.Text == "+14,000/s", "Do not rewrite titles or mixed text")
check(delta.Text == "+14k", "Do not lose the plus sign on numeric deltas")
check(malformed.Text == "14,5" and textbox.Text == "14,000", "Ignore malformed grouping and text entry")
check(outside.Text == "1,830,343,050,955" and outside.TextChanged:Count() == 0, "Do not observe other GUIs")
balance.Text = "14,000,000"
check(balance.Text == "14m", "Source writer updates must be abbreviated")
balance.Text = "-14,000"
check(balance.Text == "-14k", "Signed numeric text must remain signed")
balance.Text = "14k"
check(balance.Text == "14k", "Already compact text must remain intact")
for i = 1, 50 do
	balance.Text = tostring(14000000 + i * 1000000)
	check(balance.Text == tostring(14 + i) .. "m", "Repeated full-number writes must stay compact without recursion")
end
check(balance.TextChanged:Count() == 1, "Repeated writes must not add connections")
local late = instance("TextButton", "LateBalance", "14,000")
add(frame, late)
check(late.Text == "14k", "Observe numeric text descendants added later")
remove(frame, late)
check(late.TextChanged:Count() == 0, "Removed labels must be disconnected")
late.Text = "14,000,000"
check(late.Text == "14,000,000", "Do not rewrite detached labels")
add(frame, late)
check(late.Text == "14m" and late.TextChanged:Count() == 1, "Reattached labels get exactly one connection")
remove(playerGui, cash)
check(balance.TextChanged:Count() == 0 and cash.DescendantAdded:Count() == 0 and cash.DescendantRemoving:Count() == 0, "Removed GUI must release all connections")
balance.Text = "14,000"
check(balance.Text == "14,000", "Old respawn GUI must no longer be observed")
local replacement = instance("ScreenGui", "CashCounter")
local replacementBalance = instance("TextLabel", "Balance", "999,999")
add(replacement, replacementBalance); add(playerGui, replacement)
check(replacementBalance.Text == "1m", "Replacement CashCounter must be detected")
local second = instance("ScreenGui", "CashCounter")
local secondBalance = instance("TextLabel", "Balance", "14,000,000")
add(second, secondBalance); add(playerGui, second)
check(secondBalance.Text == "14m", "Handle multiple CashCounter instances without cloning")
local stopAgain = formatter.Start(playerGui)
check(playerGui.ChildAdded:Count() == 1 and replacementBalance.TextChanged:Count() == 1, "Repeated Start must replace old subscriptions")
stop()
replacementBalance.Text = "14,000"
check(replacementBalance.Text == "14k", "An old stop function must not stop the new observer")
stopAgain(); stopAgain()
check(playerGui.ChildAdded:Count() == 0 and playerGui.ChildRemoved:Count() == 0 and replacementBalance.TextChanged:Count() == 0 and secondBalance.TextChanged:Count() == 0, "Stop must clean every subscription and be idempotent")
replacementBalance.Text = "14,000,000"
check(replacementBalance.Text == "14,000,000", "Stopped formatter must not keep changing text")
print(string.format("PASS: %d CashCounter formatter checks", checks))
