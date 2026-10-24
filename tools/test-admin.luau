-- Admin panel: allow-list config and wiring/source contracts (the live panel needs a Studio playtest).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function environment()
	local env = table.clone(getfenv())
	for key, value in r do env[key] = value end
	return env
end
local Config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = environment() })()
local function read(path) return fs.readFile(path) end

local names = {}
for _, name in Config.Admin.Usernames do names[name:lower()] = true end
check(#Config.Admin.Usernames == 2 and names["drg1youssif"] and names["exoo96"], "Only the two allow-listed usernames are admins")
check(Config.Admin.OpenKey ~= nil and read("src/shared/Config.luau"):find("OpenKey = Enum.KeyCode.F4", 1, true), "The panel opens with F4")

local remotes = read("src/shared/Remotes.luau")
check(remotes:find('"AdminAction"', 1, true) and remotes:find('"AdminAccess"', 1, true), "Admin remotes exist")
local service = read("src/server/AdminService.luau")
check(service:find("if not AdminService.IsAdmin(player) then", 1, true), "Server rejects non-admin actions")
check(service:find("remotes.AdminAccess:FireClient(player, true", 1, true) and not service:find("FireAllClients", 1, true), "Only admins are told the panel exists")
check(service:find("ACTION_COOLDOWN", 1, true) and service:find("MAX_COINS", 1, true), "Admin actions are rate limited and clamped")
check(read("src/server/init.server.luau"):find("AdminService.Init(remotes)", 1, true), "AdminService is started")
check(read("src/client/init.client.luau"):find("AdminPanel.Start", 1, true), "The client starts the admin panel")
for _, action in { "HealAll", "GoToBoss", "MonsterRain", "SpawnBoss", "KillBoss", "BossHealth", "BossAttack" } do
	check(service:find("\t" .. action .. " = function", 1, true), "Admin action exists: " .. action)
end
local panel = read("src/client/AdminPanel.luau")
for _, action in { "HealAll", "GoToBoss", "MonsterRain", "SpawnBoss", "KillBoss", "BossHealth", "BossAttack", "GiveCoins", "GiveCandy", "GiveEgg", "GiveMonster", "Announce" } do
	check(panel:find('"' .. action .. '"', 1, true), "Panel sends: " .. action)
end
check(read("src/server/BossAttacks.luau"):find("AdminAttack", 1, true), "Boss reads the admin-forced attack")
print(("PASS: admin panel (%d checks)"):format(checks))
