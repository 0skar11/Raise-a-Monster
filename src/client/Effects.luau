--!strict
-- موسيقى الماب، أصوات الواجهة، والحركات الخفيفة: الزراير بتكبر وتصغر، الشبابيك بتتفتح بنطة،
-- الإشعارات بتطلع بنطة، والفلوس بتنط لما تزيد. كل الأرقام والأصوات في Config.Audio و Config.UIEffects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.UI)

local Effects = {}

local AUDIO = Config.Audio
local FX = Config.UIEffects
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local sfx: { [string]: Sound } = {}
local lastCoins: number? = nil
local musicOn = true
local music: Sound? = nil

local function assetId(id: number): string
	return "rbxassetid://" .. tostring(id)
end

-- صوت قصير للاعب ده بس
function Effects.Play(name: string)
	local sound = sfx[name]
	if sound then
		SoundService:PlayLocalSound(sound)
	end
end

-- UIScale واحد لكل عنصر، عشان الحركة ماتبوظش المقاسات
local function scaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChild("FxScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Parent = object
	return scale
end

local function tweenScale(object: GuiObject, value: number, info: TweenInfo)
	TweenService:Create(scaleOf(object), info, { Scale = value }):Play()
end

-- الزرار بيكبر مع الماوس، بيصغر لما تدوس، وبيعمل صوت. ولو مكتوب عليه Ready! بينبض.
local function hookButton(button: GuiButton)
	if button:GetAttribute("FxHooked") then
		return
	end
	button:SetAttribute("FxHooked", true)
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		tweenScale(button, FX.HoverScale, QUICK)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		tweenScale(button, 1, QUICK)
	end)
	button.MouseButton1Down:Connect(function()
		tweenScale(button, FX.PressScale, QUICK)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(button, if hovering then FX.HoverScale else 1, POP)
	end)
	button.Activated:Connect(function()
		Effects.Play("Click")
	end)

	if button:IsA("TextButton") then
		local pulsing = false
		local function checkReady()
			if pulsing or not string.find(button.Text, "Ready!", 1, true) then
				return
			end
			pulsing = true
			task.spawn(function()
				while button.Parent and string.find(button.Text, "Ready!", 1, true) do
					if not hovering then
						tweenScale(button, FX.ReadyPulse, TweenInfo.new(0.5, Enum.EasingStyle.Sine))
						task.wait(0.5)
						tweenScale(button, 1, TweenInfo.new(0.5, Enum.EasingStyle.Sine))
					end
					task.wait(0.5)
				end
				pulsing = false
			end)
		end
		button:GetPropertyChangedSignal("Text"):Connect(checkReady)
		checkReady()
	end
end

-- الشباك بيتفتح بنطة صغيرة
local function hookPanel(frame: Frame)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			scaleOf(frame).Scale = FX.PanelPopFrom
			tweenScale(frame, 1, POP)
			Effects.Play("Open")
		end
	end)
end

local function startMusic()
	local ids = {}
	for _, id in AUDIO.MusicIds do
		if id ~= 0 then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "MapMusic"
	sound.Volume = AUDIO.MusicVolume
	sound.Looped = #ids == 1
	sound.Parent = SoundService
	music = sound
	local index = 1
	sound.SoundId = assetId(ids[index])
	sound.Ended:Connect(function()
		index = index % #ids + 1
		sound.SoundId = assetId(ids[index])
		sound:Play()
	end)
	sound:Play()
end

-- زرار صغير يقفل ويفتح المزيكا (في المكان الفاضي في شبكة الأزرار على الشمال)
local function buildMusicButton(ui: UI.UI)
	if not music then
		return
	end
	local toggle = UI.Button(ui.Gui, "🎵\nMusic", UI.Colors.Blue, UDim2.fromOffset(84, 84), UDim2.new(0, 104, 0.5, -46))
	toggle.TextSize = 18
	toggle.Activated:Connect(function()
		musicOn = not musicOn
		local sound = music :: Sound
		sound.Volume = if musicOn then AUDIO.MusicVolume else 0
		toggle.Text = if musicOn then "🎵\nMusic" else "🔇\nMuted"
		toggle.BackgroundColor3 = if musicOn then UI.Colors.Blue else UI.Colors.Gray
	end)
end

-- الفلوس: بتنط ويطلع صوت لما تزيد بس
function Effects.OnCoins(ui: UI.UI, coins: number)
	if lastCoins and coins > lastCoins then
		local frame = ui.CoinsLabel.Parent :: GuiObject
		scaleOf(frame).Scale = FX.CoinsBump
		tweenScale(frame, 1, POP)
		Effects.Play("Coins")
	end
	lastCoins = coins
end

-- صوت الإشعار على حسب نوعه
function Effects.OnNotify(kind: string?)
	if kind == "success" then
		Effects.Play("Success")
	elseif kind == "error" then
		Effects.Play("Error")
	end
end

function Effects.Start(ui: UI.UI)
	for name, id in AUDIO.Sfx do
		if id ~= 0 then
			local sound = Instance.new("Sound")
			sound.Name = "Sfx_" .. name
			sound.SoundId = assetId(id)
			sound.Volume = AUDIO.SfxVolume
			sound.Parent = SoundService
			sfx[name] = sound
		end
	end
	startMusic()
	buildMusicButton(ui)

	-- كل الزراير، حتى اللي بتتعمل بعدين (كروت الشوب، الـ Trade...)
	for _, object in ui.Gui:GetDescendants() do
		if object:IsA("GuiButton") then
			hookButton(object)
		end
	end
	ui.Gui.DescendantAdded:Connect(function(object)
		if object:IsA("GuiButton") then
			task.defer(hookButton, object)
		end
	end)

	-- بيتنده بعد Features.Init، فكل الشبابيك اتعملت خلاص
	for _, panel in ui.Panels do
		hookPanel(panel)
	end

	-- الإشعارات بتطلع بنطة
	ui.Toasts.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			scaleOf(child).Scale = 0.6
			tweenScale(child, 1, POP)
		end
	end)
end

return Effects
