-- Pets picked up in the monster zones are collected when the player walks out of them, and teleports work anywhere.
local fs = require("@lune/fs")
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local carry = fs.readFile("src/server/CarryService.luau")
local server = fs.readFile("src/server/init.server.luau")
check(carry:find("FromZones", 1, true) and carry:find("root.Position.X < PlotService.ZonesStartX", 1, true), "Carried pets are delivered when leaving the monster zones")
check(carry:find("PlotService.IsInsidePlot(plot, root.Position)", 1, true), "Walking into the base still delivers")
check(not server:find("inside the monster zones", 1, true) and not server:find("root.Position.X >= PlotService.ZonesStartX", 1, true), "Teleport works from inside the monster zones")
check(server:find("You can't teleport while carrying", 1, true), "Teleport is still blocked while carrying")
print(("PASS: collect on exit / teleport anywhere (%d checks)"):format(checks))
