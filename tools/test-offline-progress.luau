local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local env = table.clone(getfenv())
for key, value in roblox do env[key] = value end
local config = luau.load(fs.readFile("src/shared/Config.luau"), { environment = env })()
env.script = { Parent = { Config = "Config" } }
env.require = function() return config end
local mathModule = luau.load(fs.readFile("src/shared/MonsterMath.luau"), { environment = env })()
local cases = luau.load(fs.readFile("tools/offline-progress-cases.luau"))()
print(cases(config, mathModule))
