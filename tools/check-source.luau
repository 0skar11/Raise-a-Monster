-- Compile every production Luau source without loading Roblox services.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local count = 0
local function visit(directory)
	for _, name in fs.readDir(directory) do
		local path = directory .. "/" .. name
		if fs.isDir(path) then
			visit(path)
		elseif name:match("%.luau$") then
			local ok, result = pcall(luau.compile, fs.readFile(path))
			assert(ok and result:byte(1) ~= 0, path .. ": " .. tostring(result))
			count += 1
		end
	end
end
visit("src")
print(string.format("PASS: compiled %d production Luau sources", count))
