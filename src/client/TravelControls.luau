--!strict
-- Prefer the original pixel travel buttons; keep one working travel row active.
local Workspace = game:GetService("Workspace")
local TravelControls = {}
local active: { [Instance]: () -> () } = {}
local destinations = { HomeButton = "Home", TeleportShopButton = "Shop", TeleportArenaButton = "Arena" }
local order = { "HomeButton", "TeleportShopButton", "TeleportArenaButton" }
local imported: { [string]: { Name: string, Image: string } } = {
	HomeButton = { Name = "RollButton_2", Image = "rbxassetid://138727217312430" },
	TeleportShopButton = { Name = "ShopButton", Image = "rbxassetid://111500305245467" },
	TeleportArenaButton = { Name = "RollButton_3", Image = "rbxassetid://122186044632966" },
}

function TravelControls.Start(playerGui: Instance, fallback: { [string]: TextButton }, teleport: (string) -> ()): () -> ()
	if active[playerGui] then active[playerGui]() end
	local stopped, pending = false, false
	local bound: { [TextButton]: RBXScriptConnection } = {}
	local hidden: { [GuiObject]: { Visible: boolean, Connection: RBXScriptConnection } } = {}
	local watched: { [Instance]: { RBXScriptConnection } } = {}
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local refresh: () -> ()
	local function schedule()
		if pending or stopped then return end
		pending = true
		task.defer(function() pending = false; if not stopped then refresh() end end)
	end
	local function watch(instance: Instance, properties: { string })
		if watched[instance] then return end
		local list = {}
		for _, property in properties do table.insert(list, instance:GetPropertyChangedSignal(property):Connect(schedule)) end
		watched[instance] = list
	end
	local function originallyVisible(instance: Instance): boolean
		local current: Instance? = instance
		while current and current ~= playerGui do
			if current:IsA("GuiObject") then
				local record = hidden[current :: GuiObject]
				if not (if record then record.Visible else (current :: GuiObject).Visible) then return false end
			elseif current:IsA("ScreenGui") and not (current :: ScreenGui).Enabled then
				return false
			end
			current = current.Parent
		end
		return current == playerGui
	end
	local function viewportWidth(): number
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize.X else 1280
	end
	local function nativeOwns(gui: Instance): boolean
		if gui.Name ~= "ToShop" or not gui:IsA("ScreenGui") then return false end
		local owns = false
		for _, child in gui:GetChildren() do
			if not child:IsA("LocalScript") then continue end
			watch(child, { "Name", "Enabled" })
			if child.Name == "TeleportToShop" and child.Enabled then owns = true end
		end
		return owns
	end
	refresh = function()
		local selected: { [string]: TextButton } = fallback
		local selectedBar: GuiObject? = nil
		local original: { [string]: TextButton }? = nil
		local originalNativeOwner = false
		local rounded: { { Bar: GuiObject, Buttons: { [string]: TextButton }, Complete: boolean } } = {}
		local originalButtons: { TextButton } = {}
		for _, gui in playerGui:GetChildren() do
			if not gui:IsA("ScreenGui") then continue end
			watch(gui, { "Enabled", "Name" })
			if gui.Name == "ToShop" then
				local nativeOwner = nativeOwns(gui)
				local matches: { [string]: { TextButton } } = {}
				for name in destinations do matches[name] = {} end
				for _, branch in gui:GetChildren() do
					if not branch:IsA("GuiObject") then continue end
					watch(branch, { "Name", "Visible" })
					if not branch:IsA("TextButton") then continue end
					for _, image in branch:GetChildren() do
						if not image:IsA("ImageLabel") and not image:IsA("ImageButton") then continue end
						watch(image, { "Image", "Visible", "ImageTransparency" })
					end
					for name, spec in imported do
						if branch.Name ~= spec.Name then continue end
						local identified, visibleImage = false, false
						for _, image in branch:GetChildren() do
							if (image:IsA("ImageLabel") or image:IsA("ImageButton")) and image.Image == spec.Image then
								identified = true
								if originallyVisible(image) and image.ImageTransparency < 1 then visibleImage = true end
							end
						end
						if identified and originallyVisible(branch) then table.insert(originalButtons, branch) end
						if visibleImage then table.insert(matches[name], branch) end
					end
				end
				if not original and #matches.HomeButton == 1 and #matches.TeleportShopButton == 1 and #matches.TeleportArenaButton == 1 then
					original = { HomeButton = matches.HomeButton[1], TeleportShopButton = matches.TeleportShopButton[1], TeleportArenaButton = matches.TeleportArenaButton[1] }
					originalNativeOwner = nativeOwner
				end
			elseif gui.Name == "TravelBar" then
				for _, child in gui:GetChildren() do if child:IsA("GuiObject") then watch(child, { "Name", "Visible" }) end end
				local bar = gui:FindFirstChild("Bar")
				if not bar or not bar:IsA("GuiObject") then continue end
				local buttons: { [string]: TextButton } = {}
				local complete = true
				for name in destinations do
					local button = bar:FindFirstChild(name)
					if not button or not button:IsA("TextButton") then complete = false; continue end
					watch(button, { "Name", "Visible" })
					buttons[name] = button
					if not originallyVisible(button) then complete = false end
				end
				table.insert(rounded, { Bar = bar, Buttons = buttons, Complete = complete and originallyVisible(bar) })
			end
		end
		if original then
			selected = original
		else
			for _, candidate in rounded do
				if not candidate.Complete then continue end
				selected, selectedBar = candidate.Buttons, candidate.Bar
				local scale = selectedBar:FindFirstChild("ResponsiveScale")
				if scale and scale:IsA("UIScale") then scale.Scale = 1 end
				local width = math.min(424, math.max(24, viewportWidth() - 24))
				local buttonWidth = math.floor((width - 16) / 3)
				selectedBar.Size = UDim2.fromOffset(width, 44)
				for index, name in order do
					selected[name].Size = UDim2.fromOffset(if index == 3 then width - (buttonWidth + 8) * 2 else buttonWidth, 44)
					selected[name].Position = UDim2.fromOffset((index - 1) * (buttonWidth + 8), 0)
				end
				break
			end
		end
		local suppress: { [GuiObject]: boolean } = {}
		for _, candidate in rounded do if candidate.Bar ~= selectedBar and originallyVisible(candidate.Bar) then suppress[candidate.Bar] = true end end
		local wanted: { [TextButton]: boolean } = {}
		local chosen: { [TextButton]: boolean } = {}
		for name, destination in destinations do
			local button = selected[name]
			chosen[button] = true
			if not originalNativeOwner then
				wanted[button] = true
				if not bound[button] then
					bound[button] = button.Activated:Connect(function()
						-- The native script can be enabled before the deferred refresh.
						if button.Parent and nativeOwns(button.Parent) then return end
						teleport(destination)
					end)
				end
			end
			if button ~= fallback[name] then suppress[fallback[name]] = true end
		end
		for _, button in originalButtons do if not chosen[button] then suppress[button] = true end end
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
	local function watchCamera()
		if cameraConnection then cameraConnection:Disconnect() end
		local camera = Workspace.CurrentCamera
		cameraConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule) else nil
		schedule()
	end
	table.insert(connections, playerGui.DescendantAdded:Connect(schedule))
	table.insert(connections, playerGui.DescendantRemoving:Connect(schedule))
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
	watchCamera()
	refresh()
	local function stop()
		if stopped then return end; stopped = true
		for _, connection in connections do connection:Disconnect() end
		if cameraConnection then cameraConnection:Disconnect() end
		for _, connection in bound do connection:Disconnect() end
		for _, list in watched do for _, connection in list do connection:Disconnect() end end
		for object, record in hidden do record.Connection:Disconnect(); object.Visible = record.Visible end
		if active[playerGui] == stop then active[playerGui] = nil end
	end
	active[playerGui] = stop
	return stop
end
return TravelControls
