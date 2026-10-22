-- Execute the real shop catalog and chooser with offline Roblox instances.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
-- Reuse the existing actual-UI harness, stopping before its layout assertions.
local source = fs.readFile("tools/test-shop-layout.luau")
source = source:sub(1, assert(source:find("features.Context(ui,", 1, true)) - 1)
source = source:gsub("Build = buildShopExtras, Context", "RefreshAdult = function() refreshAdultChooser(); refreshAdultSummary() end, Build = buildShopExtras, Context", 1)
local h = luau.load(source .. [[
return { Config = config, Features = features, UI = ui, UiModule = uiModule,
 State = state, Calls = calls, Remotes = remotes, Camera = camera, Changed = changed }
]], { injectGlobals = true })()
local one = h.Config.Products.SkipToAdultOne
local all = h.Config.Products.SkipToAdultAll
check(one and one.Price == 29 and all and all.Price == 100, "Configured one-time growth prices are 29 and 100 Robux")
-- Synthetic Marketplace IDs are fixtures and are not written to production Config.
one.Id, all.Id = 990001, 990002
local warnings = {}
h.UiModule.Toast = function(_, message) table.insert(warnings, message) end
local function monster(id, level, fields)
	local result = { Id = id, Level = level, DisplayName = id, Rarity = "Common", Production = 10, Available = true }
	for key, value in fields or {} do result[key] = value end
	return result
end
local adultLevel
for _, stage in h.Config.Stages do if stage.Name == "Adult" then adultLevel = stage.MinLevel end end
check(adultLevel ~= nil, "Adult threshold comes from the configured stages")
local placed = monster("placed", adultLevel - 1, { Placed = true, Slot = 1 })
local benched = monster("benched", 1, { Benched = true, Slot = 0 })
h.State.Monsters = {
	placed, benched, monster("adult", adultLevel), monster("elder", h.Config.MaxLevel),
	monster("carried", 1, { Carried = true }), monster("trade", 1, { InTrade = true }),
	monster("busy", 1, { Available = false }), monster("unknown", 1, { Available = nil }),
}
-- Setting nil through the fields helper cannot replace a field, so remove explicitly.
h.State.Monsters[#h.State.Monsters].Available = nil
h.Features.Context(h.UI, function() return h.State end, h.Remotes)
h.Features.Build()
local cards = h.UI.GearScroll
local oneCard = cards:FindFirstChild(one.Name .. "Card")
local allCard = cards:FindFirstChild(all.Name .. "Card")
check(oneCard ~= nil and allCard ~= nil, "Both offers use the existing shop catalog")
check(oneCard.Price.Text:find("29", 1, true) and allCard.Price.Text:find("100", 1, true), "Actual cards display their configured Robux prices")
check(allCard.Description.Text:find("2 current monsters", 1, true) and allCard.Description.Text:find("Future monsters excluded", 1, true), "All offer states live current count and excludes future monsters")
local before = #h.Calls
oneCard.BuyButton.Activated:Fire()
local chooser = h.UI.Gui:FindFirstChild("SkipToAdultChooser")
local list = chooser.Monsters
check(chooser.Visible and #h.Calls == before, "One offer opens target selection before any purchase request")
check(list:FindFirstChild("placed") and list:FindFirstChild("benched"), "Both placed and benched current monsters are selectable")
for _, excluded in { "adult", "elder", "carried", "trade", "busy", "unknown" } do
	check(list:FindFirstChild(excluded) == nil, "Ineligible monster is not offered: " .. excluded)
end
check(chooser.Scope.Text:find("29", 1, true) and chooser.Scope.Text:find("Future monsters excluded", 1, true), "Selection explains price and current-inventory scope")
for _, viewport in { r.Vector2.new(1096, 676), r.Vector2.new(320, 568), r.Vector2.new(568, 320), r.Vector2.new(480, 320) } do
	h.Camera.ViewportSize = viewport
	h.Changed(h.Camera, "ViewportSize"):Fire()
	h.Changed(h.UI.GearFrame, "Size"):Fire()
	h.Changed(h.UI.GearFrame.NativeShopScale, "Scale"):Fire()
	check(chooser.Size.X.Offset <= viewport.X - 24 and chooser.Size.Y.Offset <= viewport.Y - 60, "Chooser fits the usable viewport")
	check(math.abs(h.UI.Gui:FindFirstChildOfClass("UIScale").Scale * chooser.NativeAdultChooserScale.Scale - 1) < 0.0001, "Chooser rows remain native pixels")
	check(list.placed.Size.Y.Offset >= 44 and list.benched.Size.Y.Offset >= 44, "Choice rows keep native touch height")
	check(list.Position.Y.Offset + list.Size.Y.Scale * chooser.Size.Y.Offset + list.Size.Y.Offset <= chooser.Size.Y.Offset - 16, "Scrollable choices fit inside the panel")
end
list.benched.Activated:Fire()
local call = h.Calls[#h.Calls]
check(call.Name == "BuyProduct" and call.Args.n == 2 and call.Args[1] == "SkipToAdultOne" and call.Args[2] == "benched", "Choosing a monster sends exactly product plus selected ID")
check(not chooser.Visible and h.UI.GearFrame.Visible, "Selection returns to the existing shop while Roblox handles confirmation")
-- A removed, traded or already-grown target cannot use a stale row callback.
for _, change in { "removed", "grown", "unavailable" } do
	placed.Level, placed.Available = adultLevel - 1, true
	h.State.Monsters = { placed }
	oneCard.BuyButton.Activated:Fire()
	local stale = list.placed
	if change == "removed" then h.State.Monsters = {} elseif change == "grown" then placed.Level = adultLevel else placed.Available = false end
	before = #h.Calls
	stale.Activated:Fire()
	check(#h.Calls == before and list:FindFirstChild("placed") == nil, "Stale target is rechecked before purchase: " .. change)
end
h.State.Monsters = { benched }
h.Features.RefreshAdult()
check(list:FindFirstChild("benched") ~= nil and list:FindFirstChild("Empty") == nil, "An open chooser updates from current state")
check(allCard.Description.Text:find("1 current monster below Adult", 1, true), "All count updates with current eligibility")
allCard.BuyButton.Activated:Fire()
call = h.Calls[#h.Calls]
check(call.Name == "BuyProduct" and call.Args.n == 1 and call.Args[1] == "SkipToAdultAll", "All request sends no client-supplied target list")
h.State.Monsters = {}
before = #h.Calls
allCard.BuyButton.Activated:Fire()
check(#h.Calls == before and #warnings == 1, "Empty inventory cannot start an All purchase")
one.Id = 0
oneCard.BuyButton.Activated:Fire()
check(#h.Calls == before, "An unconfigured product never prompts in the live client")
check(cards:FindFirstChild("1,000 CoinsCard") ~= nil and h.UI.NavigationButtons.Shop ~= nil, "Existing offers and navigation remain present")
print(string.format("PASS: %d adult product client checks", checks))
