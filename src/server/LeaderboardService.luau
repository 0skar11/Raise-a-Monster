--!strict
-- لوحات في الساحة: الأغنى، أكتر حرامي، وأكتر وحوش Legendary.
-- بتستخدم OrderedDataStore عشان تبقى لكل اللاعبين (بعد الـ Publish)،
-- ولو مش متاحة (زي في Studio قبل الـ Publish) بتعرض اللاعبين اللي في السيرفر بس.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local DataService = require(script.Parent.DataService)

type Board = {
	Key: string,
	Title: string,
	Color: Color3,
	Value: (data: DataService.PlayerData) -> number,
	Store: OrderedDataStore?,
	Rows: { TextLabel },
	Position: Vector3,
}

local LeaderboardService = {}

local function countLegendary(data: DataService.PlayerData): number
	local count = 0
	for _, monster in data.Monsters do
		if MonsterMath.GetStage(monster.Level).Name == "Legendary" then
			count += 1
		end
	end
	return count
end

local boards: { Board } = {
	{
		Key = "Richest",
		Title = "💰 Richest",
		Color = Color3.fromRGB(255, 210, 70),
		Value = function(data)
			return math.floor(data.Coins)
		end,
		Store = nil,
		Rows = {},
		Position = Vector3.new(44, 0, 55),
	},
	{
		Key = "Thief",
		Title = "🦹 Top Thief",
		Color = Color3.fromRGB(255, 100, 100),
		Value = function(data)
			return data.Stats.Steals
		end,
		Store = nil,
		Rows = {},
		Position = Vector3.new(44, 0, 80),
	},
	{
		Key = "Legendary",
		Title = "👑 Most Legendary",
		Color = Color3.fromRGB(255, 170, 40),
		Value = countLegendary,
		Store = nil,
		Rows = {},
		Position = Vector3.new(44, 0, 105),
	},
}

local names: { [number]: string } = {}

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and result then result else "Player"
	names[userId] = name
	return name
end

local function buildBoard(folder: Folder, board: Board)
	local cframe = CFrame.lookAt(board.Position, board.Position + Vector3.new(-1, 0, 0))
	for _, side in { -1, 1 } do
		Build.MakePart({
			Name = "Post",
			Size = Vector3.new(0.8, 16, 0.8),
			CFrame = cframe * CFrame.new(side * 5.6, 8, 0.4),
			Color = Color3.fromRGB(70, 50, 35),
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	local panel = Build.MakePart({
		Name = board.Key .. "Board",
		Size = Vector3.new(11, 12, 0.6),
		CFrame = cframe * CFrame.new(0, 9.5, 0),
		Color = Color3.fromRGB(30, 30, 45),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(440, 480)
	gui.LightInfluence = 0
	gui.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 60)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = board.Color
	title.Text = board.Title
	title.Parent = gui
	for i = 1, Config.Leaderboards.TopCount do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -20, 0, 38)
		row.Position = UDim2.fromOffset(10, 62 + (i - 1) * 41)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 40, 60) else Color3.fromRGB(48, 48, 70)
		row.Font = Enum.Font.FredokaOne
		row.TextSize = 26
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Text = ""
		row.Parent = gui
		table.insert(board.Rows, row)
	end
end

local function show(board: Board, entries: { { Name: string, Value: number } })
	for i, row in board.Rows do
		local entry = entries[i]
		if entry then
			local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else "#" .. i
			row.Text = string.format("  %s  %s  ·  %s", medal, entry.Name, MonsterMath.FormatNumber(entry.Value))
		else
			row.Text = ""
		end
	end
end

local function refreshBoard(board: Board)
	-- نحدّث أرقام اللاعبين اللي في السيرفر
	local local_entries = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			local value = board.Value(profile.Data)
			table.insert(local_entries, { Name = player.DisplayName, Value = value })
			local store = board.Store
			if store and not profile.LoadFailed then
				pcall(function()
					store:SetAsync(tostring(player.UserId), value)
				end)
			end
		end
	end

	local store = board.Store
	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, Config.Leaderboards.TopCount)
		end)
		if ok and pages then
			local entries = {}
			for _, item in (pages :: DataStorePages):GetCurrentPage() do
				table.insert(entries, { Name = nameOf(tonumber(item.key) or 0), Value = item.value })
			end
			show(board, entries)
			return
		end
	end
	table.sort(local_entries, function(a, b)
		return a.Value > b.Value
	end)
	show(board, local_entries)
end

function LeaderboardService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = workspace
	for _, board in boards do
		buildBoard(folder, board)
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("Leaderboard_" .. board.Key .. "_v1")
		end)
		if ok then
			board.Store = store
		end
	end
	task.spawn(function()
		task.wait(5)
		while true do
			for _, board in boards do
				refreshBoard(board)
			end
			task.wait(Config.Leaderboards.UpdateInterval)
		end
	end)
end

return LeaderboardService
