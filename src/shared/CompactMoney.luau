--!strict
-- Display-only formatting. Never replace the stored balance with this text.

local CompactMoney = {}
local suffixes = { "", "k", "m", "b", "t" }

local function decimal(value: number): string
	return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

function CompactMoney.Format(value: number): string
	if value ~= value or math.abs(value) == math.huge then
		return "—"
	end
	local magnitude = math.abs(value)
	local sign = if value < 0 then "-" else ""
	if magnitude < 1000 then
		local whole = math.floor(magnitude)
		return if whole == 0 then "0" else sign .. tostring(whole)
	end

	local index = 1
	while magnitude >= 1000 and index < #suffixes do
		magnitude /= 1000
		index += 1
	end
	local roundingUnit = 1000 ^ (index - 1) / 100
	magnitude = math.floor(math.abs(value) / roundingUnit + 0.5) / 100
	if magnitude >= 1000 and index < #suffixes then
		magnitude /= 1000
		index += 1
	end

	-- Keep even balances beyond the supported suffix range inside the label.
	if magnitude >= 1000 then
		local exponent = math.floor(math.log10(math.abs(value)))
		local mantissa = math.floor(math.abs(value) / 10 ^ exponent * 100 + 0.5) / 100
		if mantissa >= 10 then
			mantissa /= 10
			exponent += 1
		end
		return sign .. decimal(mantissa) .. "e" .. tostring(exponent)
	end

	return sign .. decimal(magnitude) .. suffixes[index]
end

return CompactMoney
