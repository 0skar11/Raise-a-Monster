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
	card.Position, card.Size = UDim2.new(0.5, 0, 0, -230), UDim2.new(0.92, 0, 0, 172)
	card.BackgroundColor3, card.BorderSizePixel, card.Visible = Color3.fromRGB(31, 18, 54), 0, false
	card.Parent = gui
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize, bounds.Parent = Vector2.new(650, 172), card
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 14), card
	local edge = Instance.new("UIStroke")
	edge.Color, edge.Thickness, edge.Parent = Color3.fromRGB(255, 186, 66), 2, card
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 38, 115)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(32, 20, 56)),
	})
	gradient.Rotation, gradient.Parent = 25, card
	local function label(name: string, y: number, height: number, size: number, color: Color3): TextLabel
		local item = Instance.new("TextLabel")
		item.Name, item.BackgroundTransparency, item.RichText = name, 1, false
		item.Position, item.Size = UDim2.new(0, 88, 0, y), UDim2.new(1, -104, 0, height)
		item.TextColor3, item.Font, item.TextSize = color, Enum.Font.GothamBold, size
		item.TextXAlignment, item.TextWrapped = Enum.TextXAlignment.Left, true
		item.Parent = card
		return item
	end
	local title = label("Title", 10, 32, 14, Color3.fromRGB(255, 196, 80))
	title.Text = "PUMPKIN TITAN SUMMONED"
	local name = label("Summoner", 43, 48, 21, Color3.fromRGB(255, 245, 224))
	local payment = label("Payment", 90, 32, 12, Color3.fromRGB(245, 190, 131))
	local hint = label("PortalHint", 124, 36, 12, Color3.fromRGB(207, 192, 230))
	hint.Text = "Enter the Halloween portal on the Void road. Everyone can fight!"
	local avatar = Instance.new("ImageLabel")
	avatar.Name, avatar.Position, avatar.Size = "SummonerAvatar", UDim2.fromOffset(14, 53), UDim2.fromOffset(62, 62)
	avatar.BackgroundColor3, avatar.BorderSizePixel, avatar.Parent = Color3.fromRGB(53, 31, 76), 0, card
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius, avatarCorner.Parent = UDim.new(1, 0), avatar
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
				payment.Text = "@" .. nextNotice.Name .. " · PAID R$ " .. tostring(nextNotice.Robux)
				avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", nextNotice.UserId)
				card.Position, card.Visible = UDim2.new(0.5, 0, 0, -230), true
				TweenService:Create(card, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 20) }):Play()
				task.wait(7)
				local exit = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -230) })
				exit:Play()
				exit.Completed:Wait()
				card.Visible = false
			end
			showing = false
		end)
	end)
end

return BossSummonNotice
