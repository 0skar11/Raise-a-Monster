--!strict
-- Bind the exact Studio-authored launchers without changing their artwork.
local AuthoredLaunchers = {}
type Descriptor = { Gui: string, Path: { string } }
local definitions: { [string]: Descriptor } = {
	Shop = { Gui = "ShopGui", Path = { "shop" } },
	Rewards = { Gui = "ShopGui", Path = { "gifts" } },
	Trade = { Gui = "ShopGui", Path = { "trade" } },
	Inventory = { Gui = "inv", Path = { "Group 1" } },
}
local active: { [Instance]: () -> () } = {}

function AuthoredLaunchers.Start(playerGui: Instance, fallback: { [string]: GuiButton }, actions: { [string]: () -> () }): () -> ()
	if active[playerGui] then active[playerGui]() end
	local stopped, pending = false, false
	local bound: { [GuiButton]: RBXScriptConnection } = {}
	local watched: { [Instance]: { RBXScriptConnection } } = {}
	local hidden: { [GuiObject]: { Visible: boolean, Connection: RBXScriptConnection } } = {}
	local connections: { RBXScriptConnection } = {}
	local refresh: () -> ()
	local function schedule()
		if stopped or pending then return end
		pending = true
		task.defer(function() pending = false; if not stopped then refresh() end end)
	end
	local function watch(instance: Instance, properties: { string })
		if watched[instance] then return end
		local list = {}
		for _, property in properties do table.insert(list, instance:GetPropertyChangedSignal(property):Connect(schedule)) end
		watched[instance] = list
	end
	local function visible(instance: Instance): boolean
		local current: Instance? = instance
		while current and current ~= playerGui do
			if current:IsA("GuiObject") then
				local old = hidden[current :: GuiObject]
				if not (if old then old.Visible else (current :: GuiObject).Visible) then return false end
			elseif current:IsA("ScreenGui") and not (current :: ScreenGui).Enabled then return false end
			current = current.Parent
		end
		return current == playerGui
	end
	refresh = function()
		local wanted: { [GuiButton]: boolean } = {}
		local suppress: { [GuiObject]: boolean } = {}
		for key, backup in fallback do
			local action = actions[key]
			if not action then continue end
			local selected: GuiButton = backup
			local descriptor = definitions[key]
			if descriptor then
				local candidates: { GuiButton } = {}
				for _, gui in playerGui:GetChildren() do
					if not gui:IsA("ScreenGui") then continue end
					watch(gui, { "Name", "Enabled" })
					if gui.Name ~= descriptor.Gui then continue end
					local target: Instance? = gui
					for _, name in descriptor.Path do
						if not target then break end
						local match: Instance? = nil
						local count = 0
						for _, child in target:GetChildren() do
							if child:IsA("GuiObject") then watch(child, { "Name", "Visible" }) end
							if child.Name == name then match = child; count += 1 end
						end
						target = if count == 1 then match else nil
					end
					if target and target:IsA("GuiButton") and visible(target) then
						table.insert(candidates, target :: GuiButton)
					end
				end
				if #candidates == 1 then selected = candidates[1] end
			end
			if selected ~= backup then suppress[backup] = true end
			wanted[selected] = true
			if not bound[selected] then
				local target = selected
				bound[target] = target.Activated:Connect(function()
					if stopped or not target:IsDescendantOf(playerGui) or not visible(target) then return end
					action()
				end)
			end
		end
		for button, connection in bound do if not wanted[button] then connection:Disconnect(); bound[button] = nil end end
		for object, record in hidden do
			if suppress[object] then continue end
			record.Connection:Disconnect(); hidden[object] = nil; object.Visible = record.Visible
		end
		for object in suppress do
			if hidden[object] then continue end
			hidden[object] = { Visible = object.Visible, Connection = object:GetPropertyChangedSignal("Visible"):Connect(function() if object.Visible then object.Visible = false end end) }
			object.Visible = false
		end
		for instance, list in watched do
			if instance:IsDescendantOf(playerGui) then continue end
			for _, connection in list do connection:Disconnect() end; watched[instance] = nil
		end
	end
	table.insert(connections, playerGui.DescendantAdded:Connect(schedule))
	table.insert(connections, playerGui.DescendantRemoving:Connect(schedule))
	refresh()
	local function stop()
		if stopped then return end; stopped = true
		for _, connection in connections do connection:Disconnect() end
		for _, connection in bound do connection:Disconnect() end
		for _, list in watched do for _, connection in list do connection:Disconnect() end end
		for object, record in hidden do record.Connection:Disconnect(); object.Visible = record.Visible end
		if active[playerGui] == stop then active[playerGui] = nil end
	end
	active[playerGui] = stop
	return stop
end

return AuthoredLaunchers
