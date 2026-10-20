--!strict
-- Prefer the authored travel bar and suppress only identifiable legacy travel artwork.
local Workspace = game:GetService("Workspace")
local TravelControls = {}
local active: { [Instance]: () -> () } = {}
local destinations = { HomeButton = "Home", TeleportShopButton = "Shop", TeleportArenaButton = "Arena" }
local order = { "HomeButton", "TeleportShopButton", "TeleportArenaButton" }
-- These are the verified imported controls in ToShop, whose initial layout can
-- place their artwork above the viewport. Match their identity, not geometry.
local legacyArtwork: { [string]: string } = {
	ShopButton = "rbxassetid://111500305245467",
	RollButton_2 = "rbxassetid://138727217312430",
	RollButton_3 = "rbxassetid://122186044632966",
}
local semantic = { HOME = true, SHOP = true, ARENA = true, TOHOME = true, TOSHOP = true, TOARENA = true,
	HOMEBUTTON = true, TELEPORTSHOPBUTTON = true, TELEPORTARENABUTTON = true }
local function travelName(value: string): boolean
	return semantic[(value:upper():gsub("[%s_%-]", ""))] == true
end
local function legacyRoot(gui: Instance): boolean
	return gui:IsA("ScreenGui") and (gui.Name:match("^Framewisp_") ~= nil or gui.Name == "ToShop" or gui.Name == "ToHome" or gui.Name == "ToArena")
end
local function imageObject(instance: Instance): boolean
	return instance:IsA("ImageLabel") or instance:IsA("ImageButton")
end

function TravelControls.Start(playerGui: Instance, fallback: { [string]: TextButton }, teleport: (string) -> ()): () -> ()
	if active[playerGui] then active[playerGui]() end
	local stopped, pending = false, false
	local bound: { [TextButton]: RBXScriptConnection } = {}
	local hidden: { [GuiObject]: { Visible: boolean, Connection: RBXScriptConnection } } = {}
	local watched: { [Instance]: { RBXScriptConnection } } = {}
	local geometryWatched: { [Instance]: { RBXScriptConnection } } = {}
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local reportedImages: { [Instance]: string } = {}
	local reportedMissing = false
	local refresh: () -> ()
	local function schedule()
		if pending or stopped then return end
		pending = true
		task.defer(function() pending = false; if not stopped then refresh() end end)
	end
	local function viewport(): Vector2
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	local function smallTravelObject(instance: Instance): boolean
		if not instance:IsA("GuiObject") then return false end
		local object = instance :: GuiObject
		local position, size = object.AbsolutePosition, object.AbsoluteSize
		local view = viewport()
		local center = position.X + size.X / 2
		return size.X >= 60 and size.X <= 200 and size.Y > 0 and size.Y <= 100
			and position.Y >= 0 and position.Y <= 130 and center >= view.X * 0.08 and center <= view.X * 0.92
	end
	local function watchGeometry(instance: Instance)
		if geometryWatched[instance] then return end
		geometryWatched[instance] = { instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule), instance:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule), instance:GetPropertyChangedSignal("Visible"):Connect(schedule), instance:GetPropertyChangedSignal("Name"):Connect(schedule) }
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
	local function imageColumn(image: GuiObject, button: TextButton): boolean
		local position, size = image.AbsolutePosition, image.AbsoluteSize
		local target, targetSize = button.AbsolutePosition, button.AbsoluteSize
		if targetSize.X < 60 or targetSize.Y <= 0 then return false end
		local view = viewport()
		local centerX, centerY = position.X + size.X / 2, position.Y + size.Y / 2
		return size.X >= math.max(60, targetSize.X * 0.65) and size.X <= math.min(220, targetSize.X * 1.4)
			and size.Y >= math.max(18, targetSize.Y * 0.4) and size.Y <= math.min(100, targetSize.Y * 1.8)
			and position.X >= 0 and position.X + size.X <= view.X and position.Y >= 0
			and math.abs(centerX - (target.X + targetSize.X / 2)) <= math.max(18, math.min(40, targetSize.X * 0.3))
			and centerY >= target.Y - targetSize.Y * 0.8 and centerY <= target.Y + targetSize.Y * 0.65
	end
	local function imageDescription(image: GuiObject): string
		local position, size = image.AbsolutePosition, image.AbsoluteSize
		return string.format("%s [%s] x=%.0f y=%.0f w=%.0f h=%.0f", image:GetFullName(), (image :: ImageLabel).Image, position.X, position.Y, size.X, size.Y)
	end
	refresh = function()
		local selected: { [string]: TextButton } = fallback
		local primary: ScreenGui? = nil
		local suppress: { [GuiObject]: boolean } = {}
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and not watched[gui] then watched[gui] = { gui:GetPropertyChangedSignal("Enabled"):Connect(schedule), gui:GetPropertyChangedSignal("Name"):Connect(schedule) } end
			if gui.Name ~= "TravelBar" or not gui:IsA("ScreenGui") then continue end
			if not gui.Enabled then continue end
			local bar = gui:FindFirstChild("Bar")
			if not bar or not bar:IsA("GuiObject") then continue end
			local buttons: { [string]: TextButton } = {}
			local complete = true
			for name in destinations do
				local candidate = bar:FindFirstChild(name)
				if not candidate or not candidate:IsA("TextButton") then complete = false; break end
				buttons[name] = candidate
			end
			if not complete then continue end
			if primary then suppress[bar] = true; continue end
			primary, selected = gui, buttons
			watchGeometry(bar)
			for _, button in buttons do watchGeometry(button) end
			local scale = bar:FindFirstChild("ResponsiveScale")
			if scale and scale:IsA("UIScale") then scale.Scale = 1 end
			local width = math.min(424, math.max(24, viewport().X - 24))
			local buttonWidth = math.floor((width - 16) / 3)
			bar.Size = UDim2.fromOffset(width, 44)
			for index, name in order do
				buttons[name].Size = UDim2.fromOffset(if index == 3 then width - (buttonWidth + 8) * 2 else buttonWidth, 44)
				buttons[name].Position = UDim2.fromOffset((index - 1) * (buttonWidth + 8), 0)
			end
		end
		local wanted: { [TextButton]: boolean } = {}
		for name, destination in destinations do
			local button = selected[name]
			wanted[button] = true
			if not bound[button] then bound[button] = button.Activated:Connect(function() teleport(destination) end) end
			fallback[name].Visible = primary == nil
		end
		for button, connection in bound do if not wanted[button] then connection:Disconnect(); bound[button] = nil end end
		if primary then
			local images: { GuiObject } = {}
			for _, gui in playerGui:GetChildren() do
				if not legacyRoot(gui) then continue end
				for _, instance in gui:GetDescendants() do
					if imageObject(instance) then
						watchGeometry(instance)
						local ancestor = instance.Parent
						while ancestor and ancestor ~= gui do
							if ancestor:IsA("GuiObject") then watchGeometry(ancestor) end
							ancestor = ancestor.Parent
						end
						if not watched[instance] then watched[instance] = { instance:GetPropertyChangedSignal("Image"):Connect(schedule), instance:GetPropertyChangedSignal("ImageTransparency"):Connect(schedule) } end
						local image = instance :: ImageLabel
						local branch = image.Parent
						if gui.Name == "ToShop" and image.Name == "RollButtonBackground" and branch
							and branch.Parent == gui and branch:IsA("GuiObject") and legacyArtwork[branch.Name] == image.Image then
							if originallyVisible(branch) then
								-- Hide the complete verified button so its transparent input
								-- surface cannot remain over the primary travel controls.
								suppress[branch :: GuiObject] = true
								if reportedImages[image] ~= image.Image then
									reportedImages[image] = image.Image
									print("[TravelControls] Matched legacy travel artwork: " .. imageDescription(image))
								end
							end
						elseif image.Image ~= "" and image.ImageTransparency < 1 and originallyVisible(image) then
							table.insert(images, image)
						end
					end
					if instance:IsA("TextLabel") or instance:IsA("TextButton") then
						if not watched[instance] then watched[instance] = { instance:GetPropertyChangedSignal("Text"):Connect(schedule), instance:GetPropertyChangedSignal("Name"):Connect(schedule) } end
					end
					local identified = travelName(instance.Name)
						or ((instance:IsA("TextLabel") or instance:IsA("TextButton")) and travelName((instance :: TextLabel).Text))
						or ((gui.Name == "ToShop" or gui.Name == "ToHome" or gui.Name == "ToArena") and instance.Parent == gui)
					if identified and instance:IsA("GuiObject") and not geometryWatched[instance] then
						watchGeometry(instance)
					end
					if not identified or not smallTravelObject(instance) then continue end
					local branch = instance :: GuiObject
					while branch.Parent ~= gui and branch.Parent and smallTravelObject(branch.Parent) do
						branch = branch.Parent :: GuiObject; watchGeometry(branch)
					end
					suppress[branch] = true
				end
			end
			-- Image-only imports have no semantic labels. Suppress them only when
			-- exactly one visible image aligns with each of the three real buttons.
			local columns: { { GuiObject } } = { {}, {}, {} }
			for _, image in images do
				for index, name in order do
					if imageColumn(image, selected[name]) then table.insert(columns[index], image) end
				end
			end
			local group: { GuiObject }? = nil
			if #columns[1] == 1 and #columns[2] == 1 and #columns[3] == 1 then
				local a, b, c = columns[1][1], columns[2][1], columns[3][1]
				local ay = a.AbsolutePosition.Y + a.AbsoluteSize.Y / 2
				local by = b.AbsolutePosition.Y + b.AbsoluteSize.Y / 2
				local cy = c.AbsolutePosition.Y + c.AbsoluteSize.Y / 2
				if a ~= b and b ~= c and a ~= c and math.max(ay, by, cy) - math.min(ay, by, cy) <= 18 then group = { a, b, c } end
			end
			if group then
				local changed, details = false, {}
				for _, image in group do
					suppress[image] = true
					local source = (image :: ImageLabel).Image
					if reportedImages[image] ~= source then changed = true; reportedImages[image] = source end
					table.insert(details, imageDescription(image))
				end
				if changed then print("[TravelControls] Matched legacy image row: " .. table.concat(details, " | ")) end
			elseif not reportedMissing and selected.HomeButton.AbsoluteSize.X >= 60 then
				local details = {}
				for _, image in images do
					if image.AbsolutePosition.Y <= selected.HomeButton.AbsolutePosition.Y + selected.HomeButton.AbsoluteSize.Y and #details < 15 then table.insert(details, imageDescription(image)) end
				end
				if #details > 0 then
					reportedMissing = true
					print("[TravelControls] Unmatched legacy images (preserved): " .. table.concat(details, " | "))
				end
			end
		end
		for object, record in hidden do
			if suppress[object] then continue end
			record.Connection:Disconnect(); hidden[object] = nil; object.Visible = record.Visible
		end
		for object in suppress do
			if hidden[object] then continue end
			local visible = object.Visible
			hidden[object] = { Visible = visible, Connection = object:GetPropertyChangedSignal("Visible"):Connect(function() if object.Visible then object.Visible = false end end) }
			object.Visible = false
		end
		for instance, list in watched do
			if instance:IsDescendantOf(playerGui) then continue end
			for _, connection in list do connection:Disconnect() end; watched[instance] = nil
		end
		for instance, list in geometryWatched do
			if instance:IsDescendantOf(playerGui) then continue end
			for _, connection in list do connection:Disconnect() end; geometryWatched[instance] = nil
		end
		for instance in reportedImages do if not instance:IsDescendantOf(playerGui) then reportedImages[instance] = nil end end
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
		for _, list in geometryWatched do for _, connection in list do connection:Disconnect() end end
		for object, record in hidden do record.Connection:Disconnect(); object.Visible = record.Visible end
		for _, button in fallback do button.Visible = true end
		if active[playerGui] == stop then active[playerGui] = nil end
	end
	active[playerGui] = stop
	return stop
end
return TravelControls
