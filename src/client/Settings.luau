--!strict
-- إعدادات محلية للجلسة الحالية؛ زر الرجوع يفضل ظاهر لو واجهة اللعب اتخفت.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local GuiTheme = require(script.Parent.GuiTheme)
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
	local white = GuiTheme.Colors.Text
	local background = GuiTheme.Colors.Panel
	local function round(object: GuiObject, radius: number)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, math.min(4, radius))
		corner.Parent = object
	end
	local function text(parent: Instance, value: string, position: UDim2, size: UDim2, fontSize: number): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = position
		label.Size = size
		label.Font = Enum.Font.FredokaOne
		label.Text = value
		label.TextColor3 = white
		label.TextSize = fontSize
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = parent
		return label
	end
	local function button(parent: Instance, value: string, position: UDim2, size: UDim2): TextButton
		local item = Instance.new("TextButton")
		item.Position = position
		item.Size = size
		item.BackgroundColor3 = GuiTheme.Colors.PanelLight
		item.TextColor3 = white
		item.Text = value
		item.Font = Enum.Font.FredokaOne
		item.TextSize = 15
		item.Selectable = true
		item.Active = true
		item.AutoButtonColor = false
		item.Parent = parent
		round(item, 9)
		local border = Instance.new("UIStroke")
		border.Color = GuiTheme.Colors.Yellow
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Parent = item
		GuiTheme.Gloss(item)
		GuiTheme.ButtonFeedback(item, border)
		return item
	end
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
	musicToggle.Activated:Connect(function() musicOn = not musicOn; refreshMusic() end)
	refreshMusic()
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.fromOffset(296, 314)
	panel.BackgroundColor3 = background
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	panel:SetAttribute("PixelAccent", GuiTheme.Colors.Blue)
	round(panel, 12)
	local panelBorder = Instance.new("UIStroke")
	panelBorder.Color = GuiTheme.Colors.Yellow
	panelBorder.Thickness = 2
	panelBorder.Parent = panel
	GuiTheme.Gloss(panel)
	text(panel, "Settings", UDim2.fromOffset(16, 12), UDim2.fromOffset(200, 32), 20)
	local close = button(panel, "X", UDim2.new(1, -52, 0, 6), UDim2.fromOffset(44, 44))
	local content = Instance.new("ScrollingFrame")
	content.Name = "SettingsContent"
	content.Position = UDim2.fromOffset(0, 56)
	content.Size = UDim2.new(1, 0, 1, -64)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = GuiTheme.Colors.Yellow
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.CanvasSize = UDim2.fromOffset(0, 250)
	content.Parent = panel
	text(content, "Master audio", UDim2.fromOffset(16, 0), UDim2.new(1, -100, 0, 24), 15)
	local audioValue = text(content, "100%", UDim2.new(1, -80, 0, 0), UDim2.fromOffset(64, 24), 15)
	local quieter = button(content, "−", UDim2.fromOffset(16, 28), UDim2.new(0.22, -8, 0, 44))
	local louder = button(content, "+", UDim2.new(0.22, 16, 0, 28), UDim2.new(0.22, -8, 0, 44))
	local mute = button(content, "Mute", UDim2.new(0.5, 4, 0, 28), UDim2.new(0.5, -20, 0, 44))
	text(content, "Decor distance", UDim2.fromOffset(16, 80), UDim2.new(0.5, 0, 0, 24), 15)
	local renderValue = text(content, "Far", UDim2.new(0.5, 16, 0, 80), UDim2.new(0.5, -32, 0, 24), 15)
	local distanceButtons: { TextButton } = {}
	local refreshControls: () -> () = function() end
	for index, name in DISTANCE_NAMES do
		local option = button(content, name, UDim2.new((index - 1) / 3, 16 - (index - 1) * 8, 0, 108), UDim2.new(1 / 3, -16, 0, 44))
		table.insert(distanceButtons, option)
		option.Activated:Connect(function() distanceIndex = index; renderDirty = true; refreshControls() end)
	end
	text(content, "Distant scenery only. Gameplay stays visible.", UDim2.fromOffset(16, 158), UDim2.new(1, -32, 0, 32), 13)
	local hide = button(content, "Hide UI", UDim2.fromOffset(16, 198), UDim2.new(0.5, -20, 0, 44))
	local reset = button(content, "Reset", UDim2.new(0.5, 4, 0, 198), UDim2.new(0.5, -20, 0, 44))
	local function refresh()
		master.Volume = volume / 100
		audioValue.Text = tostring(volume) .. "%"
		mute.Text = if volume == 0 then "Unmute" else "Mute"
		renderValue.Text = DISTANCE_NAMES[distanceIndex]
		for index, option in distanceButtons do
			option.Text = DISTANCE_NAMES[index]
			option.BackgroundColor3 = if index == distanceIndex then GuiTheme.Colors.Blue else GuiTheme.Colors.PanelLight
		end
		hide.Text = if ui.Gui.Enabled then "Hide UI" else "Show UI"
	end
	refreshControls = refresh
	local function changeVolume(value: number)
		volume = math.clamp(value, 0, 100)
		if volume > 0 then lastAudible = volume end
		refresh()
	end
	quieter.Activated:Connect(function() changeVolume(volume - 10) end)
	louder.Activated:Connect(function() changeVolume(volume + 10) end)
	mute.Activated:Connect(function() changeVolume(if volume == 0 then lastAudible else 0) end)
	hide.Activated:Connect(function() ui.Gui.Enabled = not ui.Gui.Enabled; refresh() end)
	reset.Activated:Connect(function()
		distanceIndex = 3
		renderDirty = true
		ui.Gui.Enabled = true
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
		local width = math.min(296, math.max(1, viewport.X - 16))
		panel.Size = UDim2.fromOffset(width, math.min(314, math.max(64, viewport.Y - panelTop - 12)))
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
