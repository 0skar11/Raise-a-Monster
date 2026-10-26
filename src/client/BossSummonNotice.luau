--!strict
-- A premium, server-confirmed entrance card. No purchase UI event can show it.
local TweenService = game:GetService("TweenService")
local BossSummonNotice = {}

function BossSummonNotice.Start(remotes: { [string]: RemoteEvent }, playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "BossSummonNotice", false, 85
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local card = Instance.new("Frame")
	card.Name, card.AnchorPoint = "SummonCard", Vector2.new(0.5, 0)
	card.Position, card.Size = UDim2.new(0.5, 0, 0, -140), UDim2.new(0.92, 0, 0, 104)
	card.BackgroundColor3, card.BorderSizePixel, card.Visible = Color3.fromRGB(17, 20, 35), 0, false
	card.Parent = gui
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize, bounds.Parent = Vector2.new(420, 104), card
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 13), card
	local edge = Instance.new("UIStroke")
	edge.Color, edge.Thickness, edge.Transparency, edge.Parent = Color3.fromRGB(239, 186, 91), 1.3, 0.12, card
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 35, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 21, 37)),
	})
	gradient.Rotation, gradient.Parent = 12, card
	local function label(name: string, x: number, y: number, widthOffset: number, height: number, size: number, color: Color3): TextLabel
		local item = Instance.new("TextLabel")
		item.Name, item.BackgroundTransparency, item.RichText = name, 1, false
		item.Position, item.Size = UDim2.new(0, x, 0, y), UDim2.new(1, widthOffset, 0, height)
		item.TextColor3, item.Font, item.TextSize = color, Enum.Font.GothamBold, size
		item.TextXAlignment, item.TextWrapped = Enum.TextXAlignment.Left, false
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.Parent = card
		return item
	end
	local title = label("Title", 73, 7, -88, 15, 10, Color3.fromRGB(241, 195, 112))
	title.Text = "PUMPKIN TITAN  ·  SUMMONED"
	title.TextXAlignment = Enum.TextXAlignment.Left
	local name = label("Summoner", 73, 23, -174, 26, 18, Color3.fromRGB(255, 248, 233))
	local username = label("Username", 73, 48, -88, 16, 11, Color3.fromRGB(186, 190, 208))
	local hint = label("PortalHint", 73, 75, -88, 17, 10, Color3.fromRGB(201, 181, 222))
	hint.Text = "The Halloween portal is open"
	local avatar = Instance.new("ImageLabel")
	avatar.Name, avatar.Position, avatar.Size = "SummonerAvatar", UDim2.fromOffset(14, 29), UDim2.fromOffset(46, 46)
	avatar.BackgroundColor3, avatar.BorderSizePixel, avatar.Parent = Color3.fromRGB(53, 43, 66), 0, card
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius, avatarCorner.Parent = UDim.new(1, 0), avatar
	local avatarRing = Instance.new("UIStroke")
	avatarRing.Color, avatarRing.Thickness, avatarRing.Transparency, avatarRing.Parent = Color3.fromRGB(235, 188, 105), 1.5, 0.1, avatar
	local price = Instance.new("Frame")
	price.Name, price.AnchorPoint = "PricePill", Vector2.new(1, 0)
	price.Position, price.Size = UDim2.new(1, -10, 0, 23), UDim2.fromOffset(79, 24)
	price.BackgroundColor3, price.BorderSizePixel, price.Parent = Color3.fromRGB(235, 188, 105), 0, card
	local priceCorner = Instance.new("UICorner")
	priceCorner.CornerRadius, priceCorner.Parent = UDim.new(1, 0), price
	local payment = Instance.new("TextLabel")
	payment.Name, payment.BackgroundTransparency, payment.Size = "Payment", 1, UDim2.fromScale(1, 1)
	payment.Font, payment.TextSize, payment.TextColor3 = Enum.Font.GothamBold, 11, Color3.fromRGB(34, 27, 42)
	payment.TextXAlignment, payment.Parent = Enum.TextXAlignment.Center, price
	local queue: { any } = {}
	local showing = false
	remotes.BossSummoned.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.UserId) ~= "number" or type(data.DisplayName) ~= "string"
			or type(data.Name) ~= "string" or type(data.Robux) ~= "number" then return end
		table.insert(queue, data)
		if showing then return end
		showing = true
		task.spawn(function()
			while #queue > 0 and gui.Parent do
				local nextNotice = table.remove(queue, 1)
				name.Text = nextNotice.DisplayName
				username.Text = "@" .. nextNotice.Name
				payment.Text = "R$ " .. tostring(nextNotice.Robux) .. " PAID"
				avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", nextNotice.UserId)
				card.Position, card.Visible = UDim2.new(0.5, 0, 0, -140), true
				TweenService:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 14) }):Play()
				task.wait(6)
				local exit = TweenService:Create(card, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -140) })
				exit:Play()
				exit.Completed:Wait()
				card.Visible = false
			end
			showing = false
		end)
	end)
end

return BossSummonNotice
