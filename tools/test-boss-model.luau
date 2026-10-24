-- Big Boss: every 3 hours, and it uses the imported Pumpkin Titan model when it is in the place.
local fs = require("@lune/fs")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local config = fs.readFile("src/shared/Config.luau")
local events = fs.readFile("src/server/EventService.luau")
check(config:find("MinInterval = 10800", 1, true) and config:find("MaxInterval = 10800", 1, true), "The Big Boss arrives every 3 hours")
check(config:find('ModelName = "PumpkinTitan"', 1, true) and config:find('ModelFolder = "BossModels"', 1, true), "The boss model location is configured")
check(events:find("ServerStorage:FindFirstChild(settings.ModelFolder)", 1, true) and events:find("cloneBossModel()", 1, true), "SpawnBoss clones the imported model")
check(events:find("else\n\t\tbodyRadius = settings.Size / 2", 1, true) or events:find("bodyRadius = settings.Size / 2", 1, true), "The plain cube remains the fallback")
check(events:find("model.Parent = part", 1, true), "The model is removed together with the boss hitbox")
check(fs.isFile("assets/PumpkinBossPreview/PumpkinTitan.fbx"), "The source FBX is in the project")
print(("PASS: big boss model wiring (%d checks)"):format(checks))
