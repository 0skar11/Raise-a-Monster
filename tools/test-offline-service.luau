local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local base = table.clone(getfenv())
for key, value in roblox do base[key] = value end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = base })()
local mathEnv = table.clone(base)
mathEnv.script = { Parent = { Config = "Config" } }
mathEnv.require = function() return config end
local mathModule = luau.load(fs.readFile("src/shared/MonsterMath.luau"), { environment = mathEnv })()
local cases = luau.load(fs.readFile("tools/offline-service-cases.luau"))()
print(cases(config, mathModule, function(injected)
	local env = table.clone(base)
	for key, value in injected do env[key] = value end
	return luau.load(fs.readFile("src/server/MonsterService.luau"), { environment = env })()
end))
