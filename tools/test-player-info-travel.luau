-- Execute the actual leaderstats setup and travel layout with offline Roblox instances.
local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function source(path) return fs.readFile(path):gsub("\r\n", "\n") end
local env = table.clone(r)
local player = r.Instance.new("Player")
player.Name = "TestPlayer"
player.DisplayName = "Test Player"
player.Parent = r.Instance.new("Players")
local profile = { Data = { Coins = 123.75, Stats = { Steals = 17 } } }
local update
env.player, env.profile = player, profile
env.DataService = { Get = function() return profile end }
env.task = { spawn = function(callback) update = coroutine.create(callback) end, wait = coroutine.yield }
local server = source("src/server/init.server.luau")
local start = assert(server:find("\tlocal leaderstats =", 1, true))
local finish = assert(server:find("\n\tplayer.CharacterAdded:", start, true))
luau.load(server:sub(start, finish - 1), { environment = env, injectGlobals = true })()
check(#player.leaderstats:GetChildren() == 1 and player.leaderstats.Coins.Value == 123, "Tab exposes Coins only, alongside Roblox player identity")
check(player.Name == "TestPlayer" and player.DisplayName == "Test Player", "Player names remain available to the standard Tab list")
profile.Data.Coins = 456.9
check(coroutine.resume(update), "Leaderstats update runs")
check(player.leaderstats.Coins.Value == 456, "Tab coin amount follows wallet changes")
check(profile.Data.Stats.Steals == 17, "Removing Steals display preserves saved stats")
local enabled
local client = source("src/client/init.client.luau")
start = assert(client:find("StarterGui:SetCoreGuiEnabled", 1, true))
finish = assert(client:find("\n", start, true))
luau.load(client:sub(start, finish - 1), { environment = {
	StarterGui = { SetCoreGuiEnabled = function(_, kind, value) enabled = kind == r.Enum.CoreGuiType.PlayerList and value end }, Enum = r.Enum,
}, injectGlobals = true })()
check(enabled, "Standard Roblox Tab player list is enabled")

local uiSource = source("src/client/UI.luau")
start = assert(uiSource:find("resizeHud = function()", 1, true))
finish = assert(uiSource:find("\n\t\tcoinsLabel.TextSize", start, true))
local layout = uiSource:sub(start, finish - 1) .. "\nend\nresizeHud()"
for _, viewport in { r.Vector2.new(360, 640), r.Vector2.new(519, 800), r.Vector2.new(520, 800), r.Vector2.new(1280, 720) } do
	local items = {}
	for _, name in { "hud", "walletTravel", "coinsFrame", "homeButton", "teleportShopButton", "teleportArenaButton" } do items[name] = r.Instance.new("Frame") end
	items.camera = { ViewportSize = viewport }
	items.GuiService = { GetGuiInset = function() return r.Vector2.zero, r.Vector2.zero end }
	items.hudScale, items.uiScale = {}, { Scale = 1 }
	for key, value in r do items[key] = value end
	luau.load(layout, { environment = items, injectGlobals = true })()
	local home, shop, arena = items.homeButton, items.teleportShopButton, items.teleportArenaButton
	check(home.Position.Y.Offset == shop.Position.Y.Offset and shop.Position.Y.Offset == arena.Position.Y.Offset, "Travel buttons share a row at " .. viewport.X)
	local shopGap = shop.Position.X.Offset - home.Position.X.Offset - home.Size.X.Offset
	local arenaGap = arena.Position.X.Offset - shop.Position.X.Offset - shop.Size.X.Offset
	check(shopGap >= 0 and shopGap <= 8 and arenaGap >= 0 and arenaGap <= 8, "Travel buttons stay grouped without overlaps at " .. viewport.X)
	check(home.Position.X.Offset >= 0 and arena.Position.X.Offset + arena.Size.X.Offset <= items.walletTravel.Size.X.Offset, "Travel group fits the viewport at " .. viewport.X)
	local coins = items.coinsFrame
	check(coins.Position.Y.Offset + coins.Size.Y.Offset <= home.Position.Y.Offset or coins.Position.X.Offset + coins.Size.X.Offset <= home.Position.X.Offset, "Wallet does not overlap grouped buttons at " .. viewport.X)
end
print("PASS:", checks, "player info and travel checks (Coins-only Tab, live wallet updates, enabled player list, grouped responsive travel)")
