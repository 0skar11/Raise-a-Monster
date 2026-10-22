-- Actual Settings UI and sound routing; Studio checks texture loading and rasterization.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn)
			local item = { Callback = fn, Connected = true }; table.insert(listeners, item)
			return { Disconnect = function() item.Connected = false end }
		end,
		Fire = function(_, ...) for _, item in listeners do if item.Connected then item.Callback(...) end end end,
	}
end
local signals = {}
local function event(item, name)
	signals[item] = signals[item] or {}
	signals[item][name] = signals[item][name] or signal()
	return signals[item][name]
end
r.implementMethod("Instance", "GetPropertyChangedSignal", event)
r.implementMethod("Instance", "WaitForChild", function(item, name) return assert(item:FindFirstChild(name), name) end)
r.implementProperty("Instance", "Destroying", function(item) return event(item, "Destroying") end)
r.implementProperty("TextButton", "Activated", function(item) return event(item, "Activated") end)
local root = r.Instance.new("Folder")
local soundService = r.Instance.new("SoundService"); soundService.Parent = root
local player = r.Instance.new("Player"); player.Parent = root
local playerGui = r.Instance.new("PlayerGui"); playerGui.Parent = player
local gui = r.Instance.new("ScreenGui"); gui.Enabled = true; gui.Parent = playerGui
local camera = { ViewportSize = r.Vector2.new(1096, 676), GetPropertyChangedSignal = event }
local workspace = { CurrentCamera = camera, DescendantAdded = signal(), DescendantRemoving = signal(),
	GetPropertyChangedSignal = event, GetDescendants = function() return {} end }
local guiService = { TopbarInset = r.Rect.new(172, 0, 940, 58), GetPropertyChangedSignal = event }
local input = { InputBegan = signal(), GamepadEnabled = false }
local added = signal()
local sounds = {}
local function sound(name, parent, group)
	-- Lune cannot write nil to SoundGroup; mock this reflected Ref property only.
	local item = { Name = name, Parent = parent, Volume = 0.3, SoundGroup = group, Destroying = signal() }
	function item:IsA(class) return class == "Sound" or class == "Instance" end
	function item:IsDescendantOf(ancestor) return self.Parent == ancestor or (self.Parent and self.Parent:IsDescendantOf(ancestor)) end
	function item:GetAttribute() return nil end
	item.GetPropertyChangedSignal = event
	table.insert(sounds, item); return item
end
local background = sound("BackgroundMusic", soundService)
local map = sound("MapMusic", soundService)
local sfx = sound("CoinPickup", soundService)
local originalGroup = r.Instance.new("SoundGroup"); originalGroup.Name = "OriginalAudio"; originalGroup.Parent = soundService
local groupedMusic = sound("BackgroundMusic", soundService, originalGroup)
local services = { Players = { LocalPlayer = player }, SoundService = soundService, GuiService = guiService, UserInputService = input }
local colors = {}
for _, name in { "Text", "Panel", "PanelLight", "Yellow", "Blue" } do colors[name] = r.Color3.new(0.5, 0.5, 0.5) end
local env = { game = { GetService = function(_, name) return assert(services[name], name) end,
	GetDescendants = function()
		local descendants = root:GetDescendants()
		for _, item in sounds do table.insert(descendants, item) end
		return descendants
	end, DescendantAdded = added }, workspace = workspace,
	script = { Parent = { GuiTheme = "GuiTheme" } },
	require = function() return { Colors = colors, Gloss = function() end, ButtonFeedback = function() end } end,
	task = { spawn = function() end, wait = function() error("Unscheduled render loop") end },
}
for key, value in r do env[key] = value end
local settings = luau.load(fs.readFile("src/client/Settings.luau"), { environment = env, injectGlobals = true })()
local cleanup = settings.Init({ Gui = gui })
local controls = assert(playerGui:FindFirstChild("RaiseAMonsterSettings"))
local toggle, music = controls.SettingsToggle, controls.MusicToggle
local panel = controls.SettingsPanel
local master = assert(soundService:FindFirstChild("RaiseAMonsterLocalMaster"))
local musicGroup = assert(master:FindFirstChild("RaiseAMonsterLocalMusic"))
for _, button in { toggle, music } do
	check(button.Size == r.UDim2.fromOffset(44, 44), "Topbar controls keep native 44px hit bounds")
	check(button.BackgroundColor3 == r.Color3.fromRGB(21, 22, 24), "Topbar controls use reference dark circles")
	check(button:FindFirstChildOfClass("UICorner").CornerRadius == r.UDim.new(1, 0), "Topbar controls are circular")
	check(button.Text == "" and button:FindFirstChild("PixelBurst") == nil, "Topbar controls have no old pixel or text decoration")
end
check(toggle.SettingsIcon.Image == "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png" and toggle.SettingsIcon.ImageColor3 == r.Color3.new(1, 1, 1), "Settings uses the verified bundled white gear")
check(music.MusicIcon.LeftHead:FindFirstChildOfClass("UICorner") ~= nil and music.MusicIcon.Beam.BackgroundColor3 == r.Color3.new(1, 1, 1), "Music uses a smooth authored white musical note")
check(not music.MusicIcon.MutedSlash.Visible and not music:GetAttribute("MusicMuted"), "Audible music starts without a muted slash")
for _, item in { background, map, groupedMusic } do check(item.SoundGroup == musicGroup, "Existing background music is routed through the music subgroup") end
check(sfx.SoundGroup == master and master.Volume == 1 and musicGroup.Volume == 1, "SFX and master levels are independent from music mute")
music.Activated:Fire()
check(musicGroup.Volume == 0 and master.Volume == 1 and sfx.Volume == 0.3 and background.Volume == 0.3, "Music toggle mutes only the subgroup without rewriting playback volumes or SFX")
check(music:GetAttribute("MusicMuted") and music.MusicIcon.MutedSlash.Visible and music:GetAttribute("AccessibleName") == "Unmute music", "Muted state exposes both slash and action name")
local later = sound("MapMusic", soundService); added:Fire(later)
check(later.SoundGroup == musicGroup and musicGroup.Volume == 0, "Music created later inherits the existing muted state")
local laterSfx = sound("ButtonClick", soundService); added:Fire(laterSfx)
check(laterSfx.SoundGroup == master and master.Volume == 1, "New SFX still use the independent master group")
-- Background volume updates (including combat ducking) cannot undo music mute.
background.Volume = 0.18
check(musicGroup.Volume == 0, "Combat volume ducking cannot unmute the subgroup")
music.Activated:Fire()
check(musicGroup.Volume == 1 and not music.MusicIcon.MutedSlash.Visible, "Music unmute restores its subgroup")
toggle.Activated:Fire(); check(panel.Visible, "Settings circle opens the existing settings panel")
panel:FindFirstChild("SettingsContent")
local function contentButton(label)
	for _, child in panel.SettingsContent:GetChildren() do if child:IsA("TextButton") and child.Text == label then return child end end
	error("Missing existing setting: " .. label)
end
contentButton("Mute").Activated:Fire()
check(master.Volume == 0 and musicGroup.Volume == 1, "Existing master mute still controls all audio without changing music preference")
contentButton("Unmute").Activated:Fire()
check(master.Volume == 1, "Existing master unmute restores audio")
contentButton("Hide UI").Activated:Fire()
check(not gui.Enabled and controls.Enabled and toggle.Visible and music.Visible, "Topbar controls remain usable when gameplay UI is hidden")
contentButton("Reset").Activated:Fire(); check(gui.Enabled and master.Volume == 1, "Existing reset still restores master and gameplay UI")
for _, sample in {
	{ Width = 1096, Height = 676, Inset = r.Rect.new(172, 0, 940, 58) },
	{ Width = 320, Height = 568, Inset = r.Rect.new(172, 0, 264, 58) },
	{ Width = 568, Height = 320, Inset = r.Rect.new(172, 0, 512, 58) },
	{ Width = 320, Height = 568, Inset = r.Rect.new(172, 0, 316, 58) },
} do
	camera.ViewportSize = r.Vector2.new(sample.Width, sample.Height); guiService.TopbarInset = sample.Inset
	event(camera, "ViewportSize"):Fire(); event(guiService, "TopbarInset"):Fire()
	local x, y = music.Position.X.Offset, music.Position.Y.Offset
	check(toggle.Position.X.Offset == x + 52 and toggle.Position.Y.Offset == y, "Topbar pair keeps a consistent 8px gap")
	check(x >= 8 and toggle.Position.X.Offset + 44 <= sample.Width - 8, "Topbar pair fits desktop and mobile width")
	check(y >= sample.Inset.Max.Y or (x >= sample.Inset.Min.X and toggle.Position.X.Offset + 44 <= sample.Inset.Max.X), "Custom controls avoid reserved Roblox menu, chat and right controls")
	check(panel.Position.Y.Offset >= y + 52 and panel.Position.Y.Offset + panel.Size.Y.Offset <= sample.Height - 12, "Settings panel fits below the control row")
end
cleanup()
check(playerGui:FindFirstChild("RaiseAMonsterSettings") == nil and soundService:FindFirstChild("RaiseAMonsterLocalMaster") == nil, "Cleanup removes only owned UI and sound groups")
check(groupedMusic.SoundGroup == originalGroup and originalGroup.Parent == soundService, "Cleanup restores preexisting music group and its original parent")
check(background.SoundGroup == nil and later.SoundGroup == nil and sfx.SoundGroup == nil, "Cleanup restores initially ungrouped sounds")
check(gui.Enabled, "Cleanup preserves gameplay UI enabled state")
print(string.format("PASS: %d settings topbar and music routing checks", checks))
