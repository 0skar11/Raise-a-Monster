--!nonstrict
-- Drives the Studio-authored "CandyCounter" ScreenGui (StarterGui, a smaller copy of CashCounter that sits
-- just above it). The GUI itself is authored in Studio so it is visible in Edit mode with a placeholder "0";
-- this module only finds it, shows the player's Candy in the same compact format as the cash counter and plays
-- the same pop / flip / floating "+X" FX when Candy goes up. It never creates the GUI when it exists.
-- Candy comes from the HalloweenState remote (server authoritative); the counter hides when the event is off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CompactMoney = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CompactMoney"))

-- Plain digits up to 50k (25,000 reads better than 25K), compact above that.
local function formatCandy(value: number): string
	value = math.floor(value + 0.5)
	if math.abs(value) >= 50000 then
		return CompactMoney.Format(value)
	end
	local digits = tostring(math.abs(value))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	grouped = grouped:gsub("^,", "")
	return (if value < 0 then "-" else "") .. grouped
end

local CandyCounter = {}

local GAIN_COLOR = Color3.fromRGB(255, 245, 140)
local LOSS_COLOR = Color3.fromRGB(255, 70, 70)
local GLINT = Color3.fromRGB(255, 225, 235)
local FX_SCALE = 0.7 -- the counter is ~65% of the cash counter, so its FX travel less

local QUAD_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BACK_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local rng = Random.new()

local function easeOutBack(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

function CandyCounter.Init(playerGui: Instance, remotes: { [string]: RemoteEvent }): () -> ()
	local gui = playerGui:WaitForChild("CandyCounter", 15)
	if not gui or not gui:IsA("ScreenGui") then
		warn("[CandyCounter] StarterGui.CandyCounter is missing; the Candy counter is disabled")
		return function() end
	end
	local icon = gui:WaitForChild("CandyIcon") :: GuiObject
	local label = gui:WaitForChild("TextLabel") :: TextLabel
	local stroke = label:WaitForChild("UIStroke") :: UIStroke

	local BASE_COLOR = label.TextColor3
	local BASE_THICKNESS = stroke.Thickness
	local BASE_ICON_SIZE = icon.Size

	-- hidden until the server says whether the event is running (avoids a flash when it is off)
	gui.Enabled = false

	local fx = gui:FindFirstChild("FX") or Instance.new("Frame")
	fx.Name = "FX"
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.Active = false
	fx.ZIndex = 10
	fx.Parent = gui

	local textScale = label:FindFirstChild("PopScale") or Instance.new("UIScale")
	textScale.Name = "PopScale"
	textScale.Parent = label

	local tweens: { [string]: Tween } = {}
	local function play(key: string, inst: Instance, info: TweenInfo, goal: { [string]: any })
		if tweens[key] then
			tweens[key]:Cancel()
		end
		local tween = TweenService:Create(inst, info, goal)
		tweens[key] = tween
		tween:Play()
	end

	local function swell(amount: number)
		textScale.Scale = amount
		play("textPop", textScale, BACK_OUT, { Scale = 1 })
	end

	local function flash(color: Color3)
		label.TextColor3 = color
		play("color", label, QUAD_OUT, { TextColor3 = BASE_COLOR })
		stroke.Thickness = BASE_THICKNESS + 2
		play("stroke", stroke, QUAD_OUT, { Thickness = BASE_THICKNESS })
	end

	-- icon flip: squash to a sliver, then spring back open
	local flipping = false
	local function iconFlip()
		if flipping then
			return
		end
		flipping = true
		local squash = TweenService:Create(icon, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Size = UDim2.fromOffset(4, BASE_ICON_SIZE.Y.Offset) })
		squash.Completed:Once(function()
			local open = TweenService:Create(icon, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = BASE_ICON_SIZE })
			open.Completed:Once(function()
				flipping = false
			end)
			open:Play()
		end)
		squash:Play()
	end

	local activeFloaters, activeSweets, activeSparkles = 0, 0, 0

	local function sparkle(pos: Vector2, color: Color3, size: number, drift: Vector2, life: number)
		if activeSparkles >= 40 then
			return
		end
		activeSparkles += 1
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.Size = UDim2.fromOffset(size, size)
		frame.Position = UDim2.fromOffset(pos.X, pos.Y)
		frame.Rotation = 45
		frame.ZIndex = 11
		frame.Parent = fx
		local tween = TweenService:Create(frame, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(pos.X + drift.X, pos.Y + drift.Y),
			Size = UDim2.fromOffset(1, 1),
			BackgroundTransparency = 1,
			Rotation = 45 + rng:NextNumber(-180, 180),
		})
		tween.Completed:Once(function()
			frame:Destroy()
			activeSparkles -= 1
		end)
		tween:Play()
	end

	-- "+X" bursts out of the number, arcs up and over, then falls with a sparkle trail
	local function floater(text: string, color: Color3)
		if activeFloaters >= 6 then
			return
		end
		activeFloaters += 1
		local lp = label.AbsolutePosition - fx.AbsolutePosition
		local ls = label.AbsoluteSize
		local p0 = Vector2.new(lp.X + ls.X + 10, lp.Y + ls.Y / 2)
		local jitterX = rng:NextNumber(-8, 8)
		local p1 = p0 + Vector2.new(55 + jitterX, -75) * FX_SCALE
		local p2 = p0 + Vector2.new(115 + jitterX, -25) * FX_SCALE
		local p3 = p0 + Vector2.new(105 + jitterX, 120) * FX_SCALE

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Size = UDim2.fromOffset(160, 40)
		t.Position = UDim2.fromOffset(p0.X, p0.Y)
		t.FontFace = label.FontFace
		t.Text = text
		t.TextSize = 26
		t.TextColor3 = Color3.new(1, 1, 1)
		t.ZIndex = 12
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.4)),
		})
		grad.Parent = t
		local st = Instance.new("UIStroke")
		st.Thickness = 2.5
		st.Color = Color3.new(0, 0, 0)
		st.Parent = t
		local sc = Instance.new("UIScale")
		sc.Scale = 0.2
		sc.Parent = t
		t.Parent = fx

		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local d = rng:NextNumber(20, 42)
			sparkle(p0, i % 2 == 0 and Color3.new(1, 1, 1) or color, rng:NextInteger(5, 8),
				Vector2.new(math.cos(a) * d, math.sin(a) * d), 0.45)
		end

		local DURATION = 1.15
		local elapsed, trailClock = 0, 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local u = math.min(1, elapsed / DURATION)
			local inv = 1 - u
			local pos = p0 * (inv ^ 3) + p1 * (3 * inv * inv * u) + p2 * (3 * inv * u * u) + p3 * (u ^ 3)
			t.Position = UDim2.fromOffset(pos.X, pos.Y)
			local tan = (p1 - p0) * (3 * inv * inv) + (p2 - p1) * (6 * inv * u) + (p3 - p2) * (3 * u * u)
			t.Rotation = math.clamp(math.deg(math.atan2(tan.Y, tan.X)) * 0.35, -30, 30)
			local s
			if u < 0.15 then
				s = 0.2 + (1.4 - 0.2) * easeOutBack(u / 0.15)
			elseif u < 0.3 then
				s = 1.4 + (1 - 1.4) * ((u - 0.15) / 0.15)
			else
				s = 1 + (0.55 - 1) * ((u - 0.3) / 0.7)
			end
			sc.Scale = s
			if u > 0.6 then
				local f = (u - 0.6) / 0.4
				t.TextTransparency = f
				st.Transparency = f
			end
			trailClock += dt
			if trailClock > 0.04 and u < 0.9 then
				trailClock = 0
				sparkle(pos + Vector2.new(rng:NextNumber(-6, 6), rng:NextNumber(-4, 4)),
					rng:NextInteger(1, 3) == 1 and Color3.new(1, 1, 1) or color,
					rng:NextInteger(3, 6), Vector2.new(rng:NextNumber(-8, 8), rng:NextNumber(8, 20)), 0.4)
			end
			if u >= 1 then
				conn:Disconnect()
				t:Destroy()
				activeFloaters -= 1
			end
		end)
	end

	-- little candies pop up and to the right, then fall
	local function candyBurst(count: number)
		local origin = icon.AbsolutePosition - fx.AbsolutePosition + icon.AbsoluteSize / 2
		for _ = 1, count do
			if activeSweets >= 14 then
				return
			end
			activeSweets += 1
			local c = Instance.new("TextLabel")
			local size = rng:NextInteger(14, 20)
			c.BackgroundTransparency = 1
			c.Text = "🍬"
			c.TextScaled = true
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Size = UDim2.fromOffset(size, size)
			c.Position = UDim2.fromOffset(origin.X, origin.Y)
			c.Rotation = rng:NextNumber(0, 360)
			c.ZIndex = 11
			c.Parent = fx
			local angle = rng:NextNumber(-1.4, -0.2)
			local dist = rng:NextNumber(35, 80)
			local target = UDim2.fromOffset(origin.X + math.cos(angle) * dist, origin.Y + math.sin(angle) * dist)
			local up = TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = target, Rotation = c.Rotation + rng:NextNumber(-220, 220) })
			up:Play()
			up.Completed:Once(function()
				local down = TweenService:Create(c, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = target + UDim2.fromOffset(0, 30), TextTransparency = 1, Size = UDim2.fromOffset(4, 4) })
				down:Play()
				down.Completed:Once(function()
					c:Destroy()
					activeSweets -= 1
				end)
			end)
		end
	end

	-- number + state ---------------------------------------------------------------------------------------
	local displayed = 0
	local target = 0
	local last = 0
	local first = true
	label.Text = formatCandy(0)

	local renderConn = RunService.RenderStepped:Connect(function(dt)
		if displayed ~= target then
			displayed += (target - displayed) * math.min(1, dt * 9)
			if math.abs(target - displayed) < 0.5 then
				displayed = target
			end
			label.Text = formatCandy(math.floor(displayed + 0.5))
		end
		-- idle: a slow pink glint pulsing across the candy
		local glow = (math.sin(os.clock() * 2.5) + 1) / 2
		if icon:IsA("TextLabel") then
			icon.TextColor3 = Color3.new(1, 1, 1):Lerp(GLINT, glow * 0.35)
		end
	end)

	local function onState(state: any)
		if type(state) ~= "table" then
			return
		end
		gui.Enabled = state.Enabled == true
		local value = if type(state.Candy) == "number" then math.max(0, math.floor(state.Candy)) else 0
		if first then
			-- first sync after joining: show it, no celebration
			first = false
			displayed, target, last = value, value, value
			label.Text = formatCandy(value)
			return
		end
		local diff = value - last
		last = value
		target = value
		if diff > 0 then
			swell(1.15 + math.min(0.3, math.log10(diff + 1) * 0.07))
			flash(GAIN_COLOR)
			iconFlip()
			floater("+" .. formatCandy(diff), BASE_COLOR)
			candyBurst(diff >= 100 and 5 or 3)
		elseif diff < 0 then
			flash(LOSS_COLOR)
			floater(formatCandy(diff), LOSS_COLOR)
		end
	end

	local stateConn = remotes.HalloweenState.OnClientEvent:Connect(onState)
	return function()
		stateConn:Disconnect()
		renderConn:Disconnect()
	end
end

return CandyCounter
