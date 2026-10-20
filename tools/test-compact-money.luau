-- Offline boundary coverage for display text; no Roblox account is involved.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local formatter = luau.load(fs.readFile("src/shared/CompactMoney.luau"))()

local fixtures = {
	{ 0, "0" },
	{ 14, "14" },
	{ 14.9, "14" },
	{ 999, "999" },
	{ 999.99, "999" },
	{ 1000, "1k" },
	{ 1005, "1.01k" },
	{ 1010, "1.01k" },
	{ 1250, "1.25k" },
	{ 14000, "14k" },
	{ 14500, "14.5k" },
	{ 999994, "999.99k" },
	{ 999995, "1m" },
	{ 999999, "1m" },
	{ 1000000, "1m" },
	{ 1005000, "1.01m" },
	{ 14000000, "14m" },
	{ 999999999, "1b" },
	{ 14000000000, "14b" },
	{ 999999999999, "1t" },
	{ 1830343050955, "1.83t" },
	{ 14000000000000, "14t" },
	{ 999999999999999, "1e15" },
	{ 1000000000000000, "1e15" },
	{ 1.7976931348623157e308, "1.8e308" },
	{ -0.5, "0" },
	{ -14, "-14" },
	{ -14000, "-14k" },
	{ -1830343050955, "-1.83t" },
	{ math.huge, "—" },
	{ -math.huge, "—" },
	{ 0 / 0, "—" },
}
for _, fixture in fixtures do
	local actual = formatter.Format(fixture[1])
	assert(actual == fixture[2], string.format("%s: expected %s, got %s", tostring(fixture[1]), fixture[2], actual))
end

-- Catch accidental long or uppercase output across multiple magnitude ranges.
local samples = { 1000, 999999, 14000000, 1830343050955, 1e18, 1e100, 1e308 }
for _, value in samples do
	local output = formatter.Format(value)
	assert(#output <= 9 and not output:match("[KMBT,]"), output)
end
print(string.format("PASS: %d compact-money checks", #fixtures + #samples))
