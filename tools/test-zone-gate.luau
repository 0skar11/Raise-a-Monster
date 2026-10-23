-- The zone entrance is a Studio-authored board (Workspace.ZoneGates.ZoneGate_1, tag ZoneGateBoard) that shows the
-- zone, the monsters restart timer and the Halloween timers. The server adopts it, clones it for the other zones,
-- restyles the walls to meet its posts and keeps the restart timer current.
local fs = require("@lune/fs")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end

local zone = fs.readFile("src/server/ZoneService.luau")
check(zone:find('GetTagged("ZoneGateBoard")', 1, true), "The authored gate is found by tag")
check(zone:find("template:Clone()", 1, true) and zone:find('"GateClone"', 1, true), "Other zones get clones of the authored gate")
check(zone:find("RemoveTag(board, \"ZoneGateBoard\")", 1, true), "Clones do not become templates themselves")
check(zone:find("gatePostBounds", 1, true) and zone:find("buildGateWall(folder, x, -ZONE_HALF_Z, leftEdge)", 1, true), "Walls start exactly at the gate posts (one opening)")
local build = zone:match("local function buildGate%(.-\r?\n\tend\r?\n") or ""
check(build:find("adoptAuthoredGate(index, zone, folder)", 1, true), "buildGate prefers the authored gate")
check(zone:find("boardResetLabels", 1, true) and zone:find('gui.Name == "ResetValue"', 1, true), "The restart timer labels are collected from the board")
local timers = zone:match("local function updateGateTimers%(%).-\r?\nend\r?\n") or ""
check(timers:find("boardResetLabels", 1, true) and timers:find("gateLabels", 1, true), "Both the board and any old billboard get the restart timer")
check(not zone:find("ZoneGates:Destroy", 1, true), "Code never destroys the authored gate")

local ui = fs.readFile("src/client/HalloweenUI.luau")
check(ui:find('GetTagged("HalloweenTimerBoard")', 1, true) and ui:find("InvasionValue", 1, true) and ui:find("HuntValue", 1, true), "The client fills the Halloween timers on the board")

print(("Zone gate: %d checks PASS"):format(checks))
