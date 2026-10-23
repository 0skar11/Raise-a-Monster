-- The Gear Shop is a Studio-authored stall + Blacksmith NPC (Workspace.GearShopWorld). The server must
-- adopt it (never rebuild or move it) and open the shop from its tagged prompt.
local fs = require("@lune/fs")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end

local plot = fs.readFile("src/server/PlotService.luau")
check(plot:find('GetTagged("GearShopStand")', 1, true), "An authored stand replaces the code-made one")
check(plot:find("shopModel:Destroy()", 1, true), "The code-made stall is removed only when an authored stand exists")
check(plot:find('GetTagged("GearShopPrompt")', 1, true) and plot:find('GetInstanceAddedSignal("GearShopPrompt")', 1, true), "Authored prompts are bound, including ones added later")
local bind = plot:match("local function bindGearShopPrompt.-\r?\nend\r?\n") or ""
check(bind:find("PlotService.Callbacks.OpenShop(player)", 1, true) and bind:find("boundGearPrompts[prompt]", 1, true), "A tagged prompt opens the shop and is bound only once")
check(not plot:find('workspace:FindFirstChild("GearShopWorld")', 1, true) or not plot:find("GearShopWorld:Destroy", 1, true), "Code never destroys the authored world")

print(("Gear shop merchant: %d checks PASS"):format(checks))
