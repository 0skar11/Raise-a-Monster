--!strict
-- Preserve the Studio-authored CashCounter and shorten only its numeric text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CompactMoney = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CompactMoney"))

local CashCounterFormatter = {}
local active: { [Instance]: () -> () } = {}

local function formatText(text: string): string?
	local raw = text:match("^%s*(.-)%s*$") :: string
	local integer = raw:match("^[+-]?(%d[%d,]*)%.?%d*$")
	if not integer then return nil end
	if integer:find(",", 1, true) then
		local first = true
		for group in (integer .. ","):gmatch("(.-),") do
			if not group:match("^%d+$") or (first and #group > 3) or (not first and #group ~= 3) then return nil end
			first = false
		end
	end
	local value = tonumber((raw:gsub(",", "")))
	if not value or value ~= value or math.abs(value) == math.huge then return nil end
	local formatted = CompactMoney.Format(value)
	return if raw:sub(1, 1) == "+" then "+" .. formatted else formatted
end

function CashCounterFormatter.Start(playerGui: Instance): () -> ()
	if active[playerGui] then active[playerGui]() end
	local tracked: { [Instance]: { Connections: { RBXScriptConnection }, Labels: { [Instance]: RBXScriptConnection } } } = {}
	local function unwatchGui(gui: Instance)
		local record = tracked[gui]
		if not record then return end
		tracked[gui] = nil
		for _, connection in record.Connections do connection:Disconnect() end
		for _, connection in record.Labels do connection:Disconnect() end
	end
	local function watchGui(gui: Instance)
		if gui.Name ~= "CashCounter" or not gui:IsA("ScreenGui") or tracked[gui] then return end
		local record = { Connections = {}, Labels = {} }
		tracked[gui] = record
		local function watchLabel(instance: Instance)
			if not (instance:IsA("TextLabel") or instance:IsA("TextButton")) or record.Labels[instance] then return end
			local label = instance :: TextLabel
			local updating = false
			local function update()
				if updating then return end
				local formatted = formatText(label.Text)
				if not formatted or label.Text == formatted then return end
				updating = true
				label.Text = formatted
				updating = false
			end
			record.Labels[instance] = label:GetPropertyChangedSignal("Text"):Connect(update)
			update()
		end
		table.insert(record.Connections, gui.DescendantAdded:Connect(watchLabel))
		table.insert(record.Connections, gui.DescendantRemoving:Connect(function(instance)
			local connection = record.Labels[instance]
			if connection then connection:Disconnect(); record.Labels[instance] = nil end
		end))
		for _, instance in gui:GetDescendants() do watchLabel(instance) end
	end

	local connections = {
		playerGui.ChildAdded:Connect(watchGui),
		playerGui.ChildRemoved:Connect(unwatchGui),
	}
	for _, gui in playerGui:GetChildren() do watchGui(gui) end
	local stopped = false
	local function stop()
		if stopped then return end
		stopped = true
		for _, connection in connections do connection:Disconnect() end
		for gui in tracked do unwatchGui(gui) end
		if active[playerGui] == stop then active[playerGui] = nil end
	end
	active[playerGui] = stop
	return stop
end

return CashCounterFormatter
