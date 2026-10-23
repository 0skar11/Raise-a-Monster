--!strict
-- جبال حوالين الماب كلها (Terrain) عشان من بعيد تبان تضاريس طبيعية مش حيطة،
-- ومعاها حاجز مخفي على الحدود يمنع اللاعبين يطلعوا برّه أو يقعوا في الـ Void.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local PlotService = require(script.Parent.PlotService)
local ZoneService = require(script.Parent.ZoneService)

-- درجات الصخر والنباتات بتتغير مع كل منطقة.
local PALETTES = {
	{ Stone = Color3.fromRGB(100, 112, 123), Top = Color3.fromRGB(91, 155, 66), Material = Enum.Material.Slate, Cap = Enum.Material.Grass },
	{ Stone = Color3.fromRGB(188, 140, 88), Top = Color3.fromRGB(223, 192, 126), Material = Enum.Material.Sandstone, Cap = Enum.Material.Sand },
	{ Stone = Color3.fromRGB(132, 191, 216), Top = Color3.fromRGB(233, 249, 255), Material = Enum.Material.Glacier, Cap = Enum.Material.Snow },
	{ Stone = Color3.fromRGB(73, 56, 60), Top = Color3.fromRGB(158, 66, 44), Material = Enum.Material.Basalt, Cap = Enum.Material.CrackedLava },
	{ Stone = Color3.fromRGB(73, 50, 104), Top = Color3.fromRGB(104, 66, 146), Material = Enum.Material.Slate, Cap = Enum.Material.Slate },
}
local BARRIER_HEIGHT = 400
local UP = Vector3.new(0, 1, 0)

-- Keep positive local Z explicitly outside the map. This also avoids a
-- lookAt orientation difference in the offline Studio preview baker.
local function outwardFrame(point: Vector3, normal: Vector3): CFrame
	return CFrame.fromMatrix(point, UP:Cross(normal), UP, normal)
end

type Segment = {
	From: Vector3,
	To: Vector3,
	Normal: Vector3, -- لبرّه الماب
	ExtendStart: boolean, -- ركن لبرّه: الجبال تكمّل بعده
	ExtendEnd: boolean,
}

local TerrainService = {}

local function paletteAt(x: number)
	local zoneLength = (ZoneService.ZonesEndX - PlotService.ZonesStartX) / #Config.Zones
	local index = math.clamp(math.floor((x - PlotService.ZonesStartX) / zoneLength) + 1, 1, #PALETTES)
	return PALETTES[index], index
end

-- حدود الماب: منطقة القواعد عريضة، والمناطق أضيق (وادي بين الجبال).
local function boundary(): ({ Segment }, { { Corner: Vector3, A: Vector3, B: Vector3 } })
	local minX = PlotService.IslandMinX
	local midX = PlotService.ZonesStartX
	local maxX = ZoneService.ZonesEndX
	local bigZ = PlotService.PlazaHalfZ
	local smallZ = ZoneService.ZoneHalfZ
	local function v(x: number, z: number): Vector3
		return Vector3.new(x, 0, z)
	end
	local segments: { Segment } = {
		{ From = v(minX, -bigZ), To = v(minX, bigZ), Normal = v(-1, 0), ExtendStart = true, ExtendEnd = true },
		{ From = v(minX, -bigZ), To = v(midX, -bigZ), Normal = v(0, -1), ExtendStart = true, ExtendEnd = true },
		{ From = v(minX, bigZ), To = v(midX, bigZ), Normal = v(0, 1), ExtendStart = true, ExtendEnd = true },
		{ From = v(midX, -bigZ), To = v(midX, -smallZ), Normal = v(1, 0), ExtendStart = true, ExtendEnd = false },
		{ From = v(midX, bigZ), To = v(midX, smallZ), Normal = v(1, 0), ExtendStart = true, ExtendEnd = false },
		{ From = v(midX, -smallZ), To = v(maxX, -smallZ), Normal = v(0, -1), ExtendStart = false, ExtendEnd = true },
		{ From = v(midX, smallZ), To = v(maxX, smallZ), Normal = v(0, 1), ExtendStart = false, ExtendEnd = true },
		{ From = v(maxX, -smallZ), To = v(maxX, smallZ), Normal = v(1, 0), ExtendStart = true, ExtendEnd = true },
	}
	-- الأركان اللي لجوه (بين منطقة القواعد والمناطق) محتاجة جبال صغيرة تقفلها
	local innerCorners = {
		{ Corner = v(midX, -smallZ), A = v(1, 0), B = v(0, -1) },
		{ Corner = v(midX, smallZ), A = v(1, 0), B = v(0, 1) },
	}
	return segments, innerCorners
end

-- مجسمات متدرجة بدل كرات Terrain الضخمة؛ موجودة كمان في معاينة Studio.
local function buildCliffs(folder: Folder)
	local settings = Config.MapBorder
	local segments = boundary()
	local bay = 0
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
		return Build.MakePart({Name = name, Size = size, CFrame = cf, Color = color,
			Material = material, CanTouch = false, Parent = folder})
	end
	for _, segment in segments do
		local originalLength = (segment.To - segment.From).Magnitude
		local direction = (segment.To - segment.From).Unit
		-- Overlap the full 50-stud cliff depth at outside corners. Clip the
		-- first/last bay at inside corners so none of its width enters the valley.
		local startExtension = if segment.ExtendStart then 50 else 0
		local endExtension = if segment.ExtendEnd then 50 else 0
		local start = segment.From - direction * startExtension
		local length = originalLength + startExtension + endExtension
		local bays = math.ceil(length / settings.Spacing)
		local width = length / bays
		for i = 1, bays do
			bay += 1
			local bayStart = math.max(0, (i - 1) * width - 0.5)
			local bayEnd = math.min(length, i * width + 0.5)
			local bayWidth = bayEnd - bayStart
			local distance = (bayStart + bayEnd) / 2
			local point = start + direction * distance
			local onOriginalEdge = distance >= startExtension and distance <= startExtension + originalLength
			local palette, region = paletteAt(point.X)
			local basis = outwardFrame(point, segment.Normal)
			part("RetainingStone", Vector3.new(bayWidth, 7, 5), basis * CFrame.new(0, 3.5, 3), palette.Stone, palette.Material)
			for layer, height in {settings.LowHeight, settings.MiddleHeight, settings.HighHeight} do
				local variation = math.sin(bay * 1.7 + layer) * 3
				local depth = 14
				local offset = 6 + (layer - 1) * 14
				local wedge = Instance.new("WedgePart")
				wedge.Name = "CliffFacet"
				wedge.Anchored = true
				wedge.Size = Vector3.new(bayWidth, height + variation, depth)
				wedge.CFrame = basis * CFrame.new(0, (height + variation) / 2, offset + depth / 2)
				wedge.Color = palette.Stone:Lerp(Color3.new(1, 1, 1), layer * 0.035)
				wedge.Material = palette.Material
				wedge.CanTouch = false
				wedge.Parent = folder
				-- Solid backing joins the terraces and supports each ledge;
				-- a wedge alone leaves open triangular seams below the next tier.
				part("CliffBackfill", Vector3.new(bayWidth, height + variation, 7), basis * CFrame.new(0, (height + variation) / 2, offset + 12), wedge.Color, palette.Material)
				-- العشب على منصة ورا الحافة، عشان الشكل يفضل صخري ومتدرج.
				part("CliffLedge", Vector3.new(bayWidth, 1.2, 7), basis * CFrame.new(0, height + variation + 0.4, offset + 12), palette.Top, palette.Cap)
			end
			if onOriginalEdge and region == 1 and i % 3 == 0 then
				local height = settings.HighHeight + math.sin(bay * 1.7 + 3) * 3
				local tree = basis * CFrame.new(0, height + 1, 47)
				part("CliffTreeTrunk", Vector3.new(1.4, 6, 1.4), tree * CFrame.new(0, 3, 0), Color3.fromRGB(108, 74, 44), Enum.Material.Wood)
				for tier = 1, 3 do
					local leaf = part("CliffTreeCrown", Vector3.new(7 - tier, 3.5, 7 - tier), tree * CFrame.new(0, 4 + tier * 2, 0) * CFrame.Angles(0, math.rad(tier * 25), 0), palette.Top, Enum.Material.Grass)
					leaf.CanCollide = false
				end
			end
		end
	end
end

-- حاجز مخفي على حدود الماب: محدش يطلع على الجبال أو يقع برّه
local function buildBarrier(folder: Folder)
	local segments = boundary()
	for _, segment in segments do
		local offset = segment.To - segment.From
		local middle = (segment.From + segment.To) / 2 + segment.Normal * 2
		local alongX = math.abs(offset.X) > math.abs(offset.Z)
		-- Extra tangential length crosses the walkable valley at its concave
		-- entrance corners. Exact edge lengths already meet without a gap.
		local length = offset.Magnitude
		Build.MakePart({
			Name = "Barrier",
			Size = if alongX then Vector3.new(length, BARRIER_HEIGHT, 4) else Vector3.new(4, BARRIER_HEIGHT, length),
			Position = middle + Vector3.new(0, BARRIER_HEIGHT / 2 - 10, 0),
			Transparency = 1,
			CanCollide = true,
			CanTouch = false,
			CanQuery = false,
			Parent = folder,
		})
	end
end

-- أرض اللعب كلها Parts؛ نمسح تضاريس الجبال القديمة اللي بقت جوه الأرض
-- بعد التوسيع، وبعدها الشريط الخارجي. مجسمات القواعد والديكور تفضل زي ما هي.
local function clearLegacyBorder()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then return end
	local lobbyWidth = PlotService.ZonesStartX - PlotService.IslandMinX
	terrain:FillBlock(CFrame.new((PlotService.IslandMinX + PlotService.ZonesStartX) / 2, 70, 0),
		Vector3.new(lobbyWidth, 220, PlotService.PlazaHalfZ * 2), Enum.Material.Air)
	local zonesLength = ZoneService.ZonesEndX - PlotService.ZonesStartX
	terrain:FillBlock(CFrame.new((PlotService.ZonesStartX + ZoneService.ZonesEndX) / 2, 70, 0),
		Vector3.new(zonesLength, 220, ZoneService.ZoneHalfZ * 2), Enum.Material.Air)
	local segments = boundary()
	for _, segment in segments do
		local length = (segment.To - segment.From).Magnitude
		local center = (segment.From + segment.To) / 2 + segment.Normal * 100 + Vector3.new(0, 70, 0)
		terrain:FillBlock(outwardFrame(center, segment.Normal), Vector3.new(length + 120, 220, 200), Enum.Material.Air)
	end
end

function TerrainService.Init()
	clearLegacyBorder()
	local old = workspace:FindFirstChild("MapBorder")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "MapBorder"
	folder.Parent = workspace
	buildBarrier(folder)
	buildCliffs(folder)
end

return TerrainService
