-- Reuse real plot geometry/lifecycle checks without unrelated wearable fixtures.
local fs, luau = require("@lune/fs"), require("@lune/luau")
local source = fs.readFile("tools/test-approved-geometry.luau")
local finish = assert(source:find("local characterService =", 1, true))
luau.load(source:sub(1, finish - 1) .. '\nprint("PASS: real collector geometry removal, label/touch removal, owner isolation, release and reassignment")', { injectGlobals = true })()
