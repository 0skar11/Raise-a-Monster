--!strict
-- إعدادات محلية للجلسة الحالية؛ زر الرجوع يفضل ظاهر لو واجهة اللعب اتخفت.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudKit = require(script.Parent.HudKit)
local UserInputService = game:GetService("UserInputService")

local Settings = {}
local previousCleanup: (() -> ())? = nil
local DISTANCES = { 200, 450, 900 }
local DISTANCE_NAMES = { "Near", "Medium", "Far" }
local DECOR_NAMES: { [string]: boolean } = { Bush = true, Flower = true, Leaves = true, Pine = true, IceCrystal = true, Cactus = true, CactusArm = true, Rock = true, CliffTreeCrown = true }

type Decor = { Original: number, Hidden: boolean, Effects: { [Instance]: boolean } }

function Settings.Init(ui: { Gui: ScreenGui }): () -> ()
	if previousCleanup then previousCleanup() end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local connections: { RBXScriptConnection } = {}
	local alive = true
	local originalGuiEnabled = ui.Gui.Enabled
	local volume = 100
	local lastAudible = 100
	local distanceIndex = 3
	local renderDirty = true
	local lastPosition: Vector3? = nil
	local decor: { [BasePart]: Decor } = {}
	local soundConnections: { [Sound]: { RBXScriptConnection } } = {}
	local routedSounds: { [Sound]: boolean } = {}
	local musicOriginalGroups: { [Sound]: { Group: SoundGroup? } } = {}
	local groupParents: { [SoundGroup]: Instance } = {}
	local master = Instance.new("SoundGroup")
	master.Name = "RaiseAMonsterLocalMaster"
	master.Volume = 1
	master.Parent = SoundService
	local musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "RaiseAMonsterLocalMusic"
	musicGroup.Volume = 1
	musicGroup.Parent = master
	local musicOn = true
	-- The server keeps the player's choices (volume, music button, scenery distance) so a mute survives rejoining.
	-- Nothing is sent until the saved values have been applied, so the defaults can never overwrite them.
	local saveRemote = require(ReplicatedStorage.Shared.Remotes).Get().SaveSettings
	local settingsLoaded = false
	local saveToken = 0
	local function saveSoon()
		if not settingsLoaded then return end
		saveToken += 1
		local token = saveToken
		task.delay(1, function()
			if alive and token == saveToken then
				saveRemote:FireServer({ Volume = volume, MusicOn = musicOn, DistanceIndex = distanceIndex })
			end
		end)
	end

	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(connections, signal:Connect(callback))
	end
	local function routeGroup(group: SoundGroup)
		if group == master or group:IsDescendantOf(master) then return end
		local root = group
		local ancestor = root.Parent
		while ancestor and ancestor ~= game do
			if ancestor:IsA("SoundGroup") then root = ancestor end
			ancestor = ancestor.Parent
		end
		if root.Parent and not groupParents[root] then
			groupParents[root] = root.Parent
			root.Parent = master
		end
	end
	local function watchSound(sound: Sound)
		if soundConnections[sound] then return end
		local function route()
			if not alive then return end
			local group = sound.SoundGroup
			-- The boss theme is mandatory: it never goes through the master volume or the music button.
			if sound:GetAttribute("RaiseAMonsterForcedMusic") == true then
				if sound.SoundGroup == musicGroup or sound.SoundGroup == master then sound.SoundGroup = nil end
				return
			end
			local backgroundMusic = sound:IsDescendantOf(SoundService)
				and (sound:GetAttribute("RaiseAMonsterMusic") == true or sound.Name == "BackgroundMusic" or sound.Name == "MapMusic")
			if backgroundMusic then
				if not musicOriginalGroups[sound] then musicOriginalGroups[sound] = { Group = group } end
				if group ~= musicGroup then sound.SoundGroup = musicGroup end
				return
			end
			if musicOriginalGroups[sound] then
				local original = musicOriginalGroups[sound]
				musicOriginalGroups[sound] = nil
				sound.SoundGroup = original.Group
				group = original.Group
			end
			if group then
				routeGroup(group)
			else
				routedSounds[sound] = true
				sound.SoundGroup = master
			end
		end
		soundConnections[sound] = {}
		table.insert(soundConnections[sound], sound:GetPropertyChangedSignal("SoundGroup"):Connect(route))
		table.insert(soundConnections[sound], sound:GetPropertyChangedSignal("Name"):Connect(route))
		table.insert(soundConnections[sound], sound.Destroying:Connect(function()
			for _, connection in soundConnections[sound] or {} do connection:Disconnect() end
			soundConnections[sound] = nil
			routedSounds[sound] = nil
			musicOriginalGroups[sound] = nil
		end))
		route()
	end
	connect(game.DescendantAdded, function(instance: Instance)
		if instance:IsA("Sound") then watchSound(instance)
		elseif instance:IsA("SoundGroup") and instance ~= master then routeGroup(instance) end
	end)
	for _, instance in game:GetDescendants() do
		if instance:IsA("SoundGroup") then routeGroup(instance)
		elseif instance:IsA("Sound") then watchSound(instance) end
	end

	local function eligible(part: BasePart): boolean
		if not part.Anchored or part.CanCollide or not DECOR_NAMES[part.Name] then return false end
		local parent = part.Parent
		if not parent then return false end
		local knownFolder = parent.Name == "MapBorder" and parent.Parent == workspace
		local zones = parent.Parent
		if parent.Name:match("^Zone%d+_") and zones and zones.Name == "Zones" then
			knownFolder = zones.Parent == workspace or (zones.Parent ~= nil and zones.Parent.Name == "Map" and zones.Parent.Parent == workspace)
		end
		if not knownFolder then return false end
		for _, child in part:GetDescendants() do
			if child:IsA("ProximityPrompt") or child:IsA("ClickDetector") then return false end
		end
		return true
	end
	local function rememberEffect(instance: Instance, record: Decor)
		if instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") or instance:IsA("Light") or instance:IsA("Smoke") or instance:IsA("Fire") or instance:IsA("Sparkles") then
			record.Effects[instance] = (instance :: any).Enabled
			if record.Hidden then (instance :: any).Enabled = false end
		end
	end
	local function consider(instance: Instance)
		if instance:IsA("BasePart") and not decor[instance] and eligible(instance) then
			local record: Decor = { Original = instance.LocalTransparencyModifier, Hidden = false, Effects = {} }
			decor[instance] = record
			for _, child in instance:GetDescendants() do rememberEffect(child, record) end
			renderDirty = true
		else
			local part = instance:FindFirstAncestorWhichIsA("BasePart")
			if part and decor[part] then rememberEffect(instance, decor[part]) end
		end
	end
	connect(workspace.DescendantAdded, consider)
	connect(workspace.DescendantRemoving, function(instance: Instance)
		if instance:IsA("BasePart") then
			local record = decor[instance]
			if record then
				instance.LocalTransparencyModifier = record.Original
				for effect, enabled in record.Effects do if effect.Parent then (effect :: any).Enabled = enabled end end
				decor[instance] = nil
			end
		end
	end)
	for _, instance in workspace:GetDescendants() do consider(instance) end
	task.spawn(function()
		while alive do
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local camera = workspace.CurrentCamera
			local position = if root and root:IsA("BasePart") then root.Position elseif camera then camera.CFrame.Position else nil
			if position and (renderDirty or not lastPosition or (position - lastPosition).Magnitude >= 8) then
				lastPosition = position
				renderDirty = false
				for part, record in decor do
					if part.Parent then
						local hidden = eligible(part) and (part.Position - position).Magnitude > DISTANCES[distanceIndex] + part.Size.Magnitude / 2
						if hidden ~= record.Hidden then
							record.Hidden = hidden
							part.LocalTransparencyModifier = if hidden then 1 else record.Original
							for effect, enabled in record.Effects do if effect.Parent then (effect :: any).Enabled = if hidden then false else enabled end end
						end
					end
				end
			end
			task.wait(0.25)
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RaiseAMonsterSettings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local topbarColor = Color3.fromRGB(21, 22, 24)
	local function topbarButton(name: string, label: string): TextButton
		local item = Instance.new("TextButton")
		item.Name = name
		item.Size = UDim2.fromOffset(44, 44)
		item.BackgroundColor3 = topbarColor
		item.BorderSizePixel = 0
		item.Text = ""
		item.AutoButtonColor = true
		item.Active = true
		item.Selectable = true
		item:SetAttribute("AccessibleName", label)
		item.Parent = gui
		local circle = Instance.new("UICorner")
		circle.CornerRadius = UDim.new(1, 0)
		circle.Parent = item
		return item
	end
	local toggle = topbarButton("SettingsToggle", "Settings")
	local gear = Instance.new("ImageLabel")
	gear.Name = "SettingsIcon"
	gear.BackgroundTransparency = 1
	gear.Size = UDim2.fromOffset(24, 24)
	gear.Position = UDim2.fromOffset(10, 10)
	gear.Image = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png"
	gear.ImageColor3 = Color3.new(1, 1, 1)
	gear.Active = false
	gear.Selectable = false
	gear.Parent = toggle
	local musicToggle = topbarButton("MusicToggle", "Mute music")
	local note = Instance.new("Frame")
	note.Name = "MusicIcon"
	note.BackgroundTransparency = 1
	note.Size = UDim2.fromOffset(24, 24)
	note.Position = UDim2.fromOffset(10, 10)
	note.Parent = musicToggle
	local function notePart(name: string, x: number, y: number, width: number, height: number, color: Color3, circular: boolean?): Frame
		local part = Instance.new("Frame")
		part.Name = name
		part.Position = UDim2.fromOffset(x, y)
		part.Size = UDim2.fromOffset(width, height)
		part.BackgroundColor3 = color
		part.BorderSizePixel = 0
		part.Active = false
		part.Selectable = false
		part.Parent = note
		if circular then
			local curve = Instance.new("UICorner")
			curve.CornerRadius = UDim.new(1, 0)
			curve.Parent = part
		end
		return part
	end
	local iconWhite = Color3.new(1, 1, 1)
	notePart("LeftHead", 0, 16, 8, 6, iconWhite, true).Rotation = -20
	notePart("RightHead", 13, 13, 8, 6, iconWhite, true).Rotation = -20
	notePart("LeftStem", 5, 3, 3, 17, iconWhite)
	notePart("RightStem", 18, 0, 3, 17, iconWhite)
	notePart("Beam", 5, 2, 16, 3, iconWhite).Rotation = -13
	local slashCutout = notePart("MutedCutout", 9, -4, 6, 32, topbarColor)
	slashCutout.Rotation = -45
	local slash = notePart("MutedSlash", 11, -4, 2, 32, iconWhite)
	slash.Rotation = -45
	local function refreshMusic()
		musicGroup.Volume = if musicOn then 1 else 0
		slashCutout.Visible = not musicOn
		slash.Visible = not musicOn
		musicToggle:SetAttribute("AccessibleName", if musicOn then "Mute music" else "Unmute music")
		musicToggle:SetAttribute("MusicMuted", not musicOn)
	end
	musicToggle.Activated:Connect(function() musicOn = not musicOn; refreshMusic(); saveSoon() end)
	refreshMusic()
	-- The settings window follows the HUD kit: blue/purple header, slate body and one row per setting.
	local PANEL_WIDTH, PANEL_HEIGHT = 420, 430
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	HudKit.Body(panel)
	local header, headerTitle = HudKit.Header(panel, "Header", "Settings", "Settings")
	header.Position, header.Size = UDim2.fromOffset(6, 6), UDim2.new(1, -12, 0, 60)
	local gear = Instance.new("ImageLabel")
	gear.Name, gear.BackgroundTransparency, gear.Size, gear.Position = "SettingsArt", 1, UDim2.fromOffset(34, 34), UDim2.fromOffset(16, 13)
	gear.Image, gear.ZIndex, gear.Active = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png", header.ZIndex + 3, false
	gear.Parent = header
	headerTitle.Position, headerTitle.Size, headerTitle.TextSize = UDim2.fromOffset(60, 0), UDim2.new(1, -130, 1, 0), 32
	local close = HudKit.Button(panel, "CloseButton", "X", "Red")
	close.Position, close.Size, close.ZIndex = UDim2.new(1, -58, 0, 14), UDim2.fromOffset(44, 44), 20
	local content = Instance.new("ScrollingFrame")
	content.Name = "SettingsContent"
	content.Position = UDim2.fromOffset(10, 76)
	content.Size = UDim2.new(1, -20, 1, -86)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = HudKit.Colors.Gold
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ZIndex = panel.ZIndex + 2
	content.Parent = panel
	local rows = Instance.new("UIListLayout")
	rows.Padding, rows.SortOrder, rows.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, content
	local function row(name: string, title: string, note: string?, height: number, order: number): Frame
		local item = Instance.new("Frame")
		item.Name, item.LayoutOrder = name, order
		item.Size, item.BackgroundColor3, item.BorderSizePixel = UDim2.new(1, -10, 0, height), HudKit.Colors.Row, 0
		item.ZIndex = content.ZIndex + 1
		item.Parent = content
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = item
		local edge = Instance.new("UIStroke")
		edge.Color, edge.Thickness = HudKit.Colors.Shadow, 2
		edge.Parent = item
		local label = HudKit.Text(item, "Title", title, 22)
		label.Position, label.Size, label.TextXAlignment = UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 28), Enum.TextXAlignment.Left
		label.TextWrapped = false
		if note then
			local hint = Instance.new("TextLabel")
			hint.Name, hint.BackgroundTransparency, hint.ZIndex = "Description", 1, item.ZIndex + 1
			hint.Position, hint.Size = UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 18)
			hint.Font, hint.TextSize, hint.TextColor3 = Enum.Font.GothamBold, 12, HudKit.Colors.Muted
			hint.TextXAlignment, hint.Text = Enum.TextXAlignment.Left, note
			hint.Parent = item
		end
		return item
	end
	local function stateLabel(parent: Instance): TextLabel
		local label = HudKit.Text(parent, "State", "ON", 20)
		label.TextXAlignment = Enum.TextXAlignment.Right
		return label
	end
	local function place(item: GuiObject, x: UDim, y: number, width: UDim, height: number)
		item.Position, item.Size = UDim2.new(x.Scale, x.Offset, 0, y), UDim2.new(width.Scale, width.Offset, 0, height)
	end

	-- Master audio: down / up steps, the current level and an ON / OFF switch (OFF is muted).
	local audioRow = row("MasterAudio", "Master audio", nil, 96, 1)
	local quieter = HudKit.Button(audioRow, "Quieter", "-", "Blue")
	local louder = HudKit.Button(audioRow, "Louder", "+", "Blue")
	local audioValue = HudKit.Text(audioRow, "Level", "100%", 22)
	local muteToggle = HudKit.Toggle(audioRow, "Mute")
	local muteState = stateLabel(audioRow)
	place(quieter, UDim.new(0, 12), 46, UDim.new(0, 56), 40)
	place(louder, UDim.new(0, 74), 46, UDim.new(0, 56), 40)
	place(audioValue, UDim.new(0, 138), 46, UDim.new(0, 64), 40)
	place(muteToggle, UDim.new(1, -96), 46, UDim.new(0, 84), 40)
	place(muteState, UDim.new(1, -148), 46, UDim.new(0, 48), 40)
	-- Decor distance: three choices, the chosen one lit up.
	local distanceRow = row("DecorDistance", "Decor distance", "Distant scenery only. Gameplay stays visible.", 104, 2)
	local distanceButtons: { TextButton } = {}
	local refreshControls: () -> () = function() end
	for index, name in DISTANCE_NAMES do
		local option = HudKit.Button(distanceRow, name, name, "Blue")
		place(option, UDim.new((index - 1) / 3, if index == 1 then 12 else 6), 56, UDim.new(1 / 3, if index == 3 then -18 else -12), 40)
		table.insert(distanceButtons, option)
		option.Activated:Connect(function() distanceIndex = index; renderDirty = true; refreshControls(); saveSoon() end)
	end
	-- Interface: ON shows the game UI, OFF hides it (this window stays so it can be switched back).
	local interfaceRow = row("Interface", "Game interface", nil, 64, 3)
	local interfaceToggle = HudKit.Toggle(interfaceRow, "ShowUI")
	local interfaceState = stateLabel(interfaceRow)
	place(interfaceToggle, UDim.new(1, -96), 12, UDim.new(0, 84), 40)
	place(interfaceState, UDim.new(1, -148), 12, UDim.new(0, 48), 40)
	local resetRow = row("Reset", "Reset settings", nil, 64, 4)
	local reset = HudKit.Button(resetRow, "Reset", "Reset", "Yellow")
	place(reset, UDim.new(1, -128), 12, UDim.new(0, 116), 40)
	local function refresh()
		master.Volume = volume / 100
		audioValue.Text = tostring(volume) .. "%"
		HudKit.SetToggle(muteToggle, volume > 0)
		muteState.Text = if volume > 0 then "ON" else "OFF"
		for index, option in distanceButtons do
			HudKit.SetPalette(option, if index == distanceIndex then "Yellow" else "Blue")
		end
		HudKit.SetToggle(interfaceToggle, ui.Gui.Enabled)
		interfaceState.Text = if ui.Gui.Enabled then "ON" else "OFF"
	end
	refreshControls = refresh
	local function changeVolume(value: number)
		volume = math.clamp(value, 0, 100)
		if volume > 0 then lastAudible = volume end
		refresh()
		saveSoon()
	end
	quieter.Activated:Connect(function() changeVolume(volume - 10) end)
	louder.Activated:Connect(function() changeVolume(volume + 10) end)
	muteToggle.Activated:Connect(function() changeVolume(if volume == 0 then lastAudible else 0) end)
	interfaceToggle.Activated:Connect(function() ui.Gui.Enabled = not ui.Gui.Enabled; refresh() end)
	reset.Activated:Connect(function()
		distanceIndex = 3
		renderDirty = true
		ui.Gui.Enabled = true
		musicOn = true
		refreshMusic()
		changeVolume(100)
	end)
	connect(ui.Gui:GetPropertyChangedSignal("Enabled"), refresh)
	local function show(open: boolean)
		panel.Visible = open
		if open then
			if UserInputService.GamepadEnabled then GuiService.SelectedObject = close end
		else
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(panel) then
				GuiService.SelectedObject = toggle
			end
		end
	end
	toggle.Activated:Connect(function() show(not panel.Visible) end)
	close.Activated:Connect(function() show(false) end)
	connect(UserInputService.InputBegan, function(input: InputObject)
		if panel.Visible and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then show(false) end
	end)
	local function layout()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		local ok, topbar = pcall(function() return GuiService.TopbarInset end)
		local left = if ok and topbar.Min.X > 0 then topbar.Min.X + 8 else 184
		local top = if ok then topbar.Min.Y + math.max(0, math.floor((topbar.Height - 44) / 2)) else 8
		local right = if ok and topbar.Max.X > left then math.min(topbar.Max.X - 8, viewport.X - 8) else viewport.X - 8
		if right - left < 96 then
			-- On narrow screens, use our own row below the reserved Roblox controls.
			left = 8
			top = if ok then math.max(58, topbar.Max.Y + 8) else 60
		end
		musicToggle.Position = UDim2.fromOffset(left, top)
		toggle.Position = UDim2.fromOffset(left + 52, top)
		local panelTop = math.max(top + 52, if ok then topbar.Max.Y + 8 else 58)
		local width = math.min(PANEL_WIDTH, math.max(1, viewport.X - 16))
		panel.Size = UDim2.fromOffset(width, math.min(PANEL_HEIGHT, math.max(64, viewport.Y - panelTop - 12)))
		panel.Position = UDim2.fromOffset(math.clamp(left + 52, 8, math.max(8, viewport.X - width - 8)), panelTop)
	end
	connect(GuiService:GetPropertyChangedSignal("TopbarInset"), layout)
	local viewportConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
		layout()
	end
	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
	watchCamera()
	refresh()

	-- Apply what the server saved (it arrives as Player attributes once the profile has loaded).
	local function applySaved()
		if settingsLoaded or player:GetAttribute("SettingsLoaded") ~= true then return end
		local savedVolume = player:GetAttribute("SettingsVolume")
		local savedMusic = player:GetAttribute("SettingsMusicOn")
		local savedDistance = player:GetAttribute("SettingsDistance")
		if type(savedVolume) == "number" then
			volume = math.clamp(savedVolume, 0, 100)
			if volume > 0 then lastAudible = volume end
		end
		if type(savedMusic) == "boolean" then musicOn = savedMusic end
		if type(savedDistance) == "number" and DISTANCES[savedDistance] then distanceIndex = savedDistance end
		renderDirty = true
		settingsLoaded = true
		refresh()
		refreshMusic()
	end
	connect(player:GetAttributeChangedSignal("SettingsLoaded"), applySaved)
	applySaved()

	local function cleanup()
		if not alive then return end
		alive = false
		for _, connection in connections do connection:Disconnect() end
		if viewportConnection then viewportConnection:Disconnect() end
		for _, list in soundConnections do for _, connection in list do connection:Disconnect() end end
		for sound, original in musicOriginalGroups do if sound.Parent and sound.SoundGroup == musicGroup then sound.SoundGroup = original.Group end end
		for sound in routedSounds do if sound.Parent and sound.SoundGroup == master then sound.SoundGroup = nil end end
		for group, parent in groupParents do if group.Parent == master and parent.Parent then group.Parent = parent end end
		-- نحافظ على أي مجموعة صوت لسه جوه المجموعة المحلية وقت الإزالة.
		for _, child in master:GetChildren() do if child:IsA("SoundGroup") and child ~= musicGroup then child.Parent = SoundService end end
		musicGroup:Destroy()
		master:Destroy()
		for part, record in decor do
			if part.Parent then part.LocalTransparencyModifier = record.Original end
			for effect, enabled in record.Effects do if effect.Parent then (effect :: any).Enabled = enabled end end
		end
		ui.Gui.Enabled = originalGuiEnabled
		show(false)
		gui:Destroy()
	end
	previousCleanup = cleanup
	return cleanup
end

return Settings
