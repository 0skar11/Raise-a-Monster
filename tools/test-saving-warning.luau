-- Execute the actual status rendering portion of Features.Refresh offline.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local source = fs.readFile("src/client/Features.luau"):gsub("\r\n", "\n")
local start = assert(source:find("function Features.Refresh()", 1, true))
local finish = assert(source:find("\n\t-- الهدية اليومية", start, true))
local renderSource = source:sub(start, finish - 1) .. "\nend\nFeatures.Refresh()\nreturn statusLabel.Text"
local function render(state)
	return luau.load(renderSource, { environment = {
		Features = {}, getState = function() return state end, refreshShopCatalog = function() end,
		statusLabel = { Text = "" }, formatTime = tostring,
	}, injectGlobals = true })()
end
assert(render({ SaveDisabled = true }):find("progress is not saved", 1, true), "Offline Studio session must keep a visible saving warning")
assert(render({ SaveDisabled = false }) == "", "Healthy session must not show a stale warning")
assert(render({ SaveDisabled = true, Carrying = true }):find("progress is not saved", 1, true), "Other HUD status must not hide saving warning")
print("PASS: persistent saving warning appears only when progress cannot save, including alongside other HUD status")
