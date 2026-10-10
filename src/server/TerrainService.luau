--!strict
-- جبال حوالين الماب كلها (Terrain) عشان من بعيد تبان تضاريس طبيعية مش حيطة،
-- ومعاها حاجز مخفي على الحدود يمنع اللاعبين يطلعوا برّه أو يقعوا في الـ Void.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local PlotService = require(script.Parent.PlotService)
local ZoneService = require(script.Parent.ZoneService)

type Style = {
	Body: Enum.Material, -- سفح الجبل
	Peak: Enum.Material, -- القمم اللي ورا
	Cap: Enum.Material?, -- تلج فوق القمم العالية
	Lava: boolean, -- خطوط حمم نازلة على السفح
}

-- ورا القواعد والساحة
local BASE_STYLE: Style = { Body = Enum.Material.Grass, Peak = Enum.Material.Rock, Cap = Enum.Material.Snow, Lava = false }
-- بالترتيب زي Config.Zones
local ZONE_STYLES: { Style } = {
	{ Body = Enum.Material.Grass, Peak = Enum.Material.Grass, Cap = Enum.Material.Snow, Lava = false }, -- Meadow: تلال خضرا
	{ Body = Enum.Material.Grass, Peak = Enum.Material.Rock, Cap = Enum.Material.Snow, Lava = false }, -- Forest: صخور
	{ Body = Enum.Material.Basalt, Peak = Enum.Material.Basalt, Cap = nil, Lava = true }, -- Lava Canyon: منحدرات وحمم
	{ Body = Enum.Material.Slate, Peak = Enum.Material.Slate, Cap = nil, Lava = false }, -- Shadow Realm: قمم بنفسجي
}

local SPACING = 26 -- المسافة بين الجبال على الحدود
local CORNER_EXTENSION = 30 -- قد إيه الجبال بتكمّل بعد الأركان اللي لبرّه
local BARRIER_HEIGHT = 400

type Segment = {
	From: Vector3,
	To: Vector3,
	Normal: Vector3, -- لبرّه الماب
	ExtendStart: boolean, -- ركن لبرّه: الجبال تكمّل بعده
	ExtendEnd: boolean,
}

local TerrainService = {}

local function styleAt(x: number): Style
	if x < PlotService.ZonesStartX then
		return BASE_STYLE
	end
	local zoneLength = (ZoneService.ZonesEndX - PlotService.ZonesStartX) / #Config.Zones
	local index = math.clamp(math.floor((x - PlotService.ZonesStartX) / zoneLength) + 1, 1, #ZONE_STYLES)
	return ZONE_STYLES[index]
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

local function buildMountains(terrain: Terrain)
	local random = Random.new(2026)
	local segments, innerCorners = boundary()
	local up = Vector3.new(0, 1, 0)
	local filled = 0

	for _, segment in segments do
		local offset = segment.To - segment.From
		local length = offset.Magnitude
		local direction = offset.Unit
		local t = if segment.ExtendStart then -CORNER_EXTENSION else 0
		local stop = length + (if segment.ExtendEnd then CORNER_EXTENSION else 0)
		while t <= stop do
			local point = segment.From + direction * t
			local style = styleAt(point.X)

			-- قرب الأركان اللي لجوه الجبل بيصغر عشان مايدخلش جوه الماب
			local cap = math.huge
			if not segment.ExtendStart then
				cap = math.min(cap, t - 1)
			end
			if not segment.ExtendEnd then
				cap = math.min(cap, length - t - 1)
			end

			local radius = math.min(random:NextNumber(38, 58), cap)
			if radius >= 6 then
				-- السفح: بيبدأ من حدود الماب بالظبط
				local slope = point + segment.Normal * (radius * 0.95 + 2) - up * (radius * 0.3)
				terrain:FillBall(slope, radius, style.Body)

				-- قمة عالية ورا السفح
				local peakRadius = math.min(random:NextNumber(34, 52), cap)
				local back = math.max(radius * 0.95 + 2 + random:NextNumber(18, 34), peakRadius + 2)
				local peak = point + segment.Normal * back + up * random:NextNumber(peakRadius * 0.7, peakRadius * 1.5)
				terrain:FillBall(peak, peakRadius, style.Peak)
				if style.Cap and peak.Y + peakRadius > 85 then
					terrain:FillBall(peak + up * (peakRadius * 0.8), peakRadius * 0.35, style.Cap)
				end

				-- خطوط حمم نازلة على السفح ناحية الماب
				if style.Lava and random:NextNumber() < 0.6 then
					for angle = 0.35, 1.2, 0.17 do
						local surface = slope + (-segment.Normal * math.cos(angle) + up * math.sin(angle)) * radius
						terrain:FillBall(surface, 3.5, Enum.Material.CrackedLava)
					end
				end
			end

			filled += 1
			if filled % 6 == 0 then
				task.wait()
			end
			t += SPACING * random:NextNumber(0.8, 1.2)
		end
	end

	for _, inner in innerCorners do
		for _, size in { 34, 20, 11 } do
			local center = inner.Corner + (inner.A + inner.B) * (size + 1) - up * (size * 0.2)
			terrain:FillBall(center, size, BASE_STYLE.Body)
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
		local length = offset.Magnitude + 8
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

function TerrainService.Init()
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(100, 165, 75))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(90, 60, 130))
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(60, 45, 45))

	local folder = Instance.new("Folder")
	folder.Name = "MapBorder"
	folder.Parent = workspace
	buildBarrier(folder)
	task.spawn(buildMountains, terrain)
end

return TerrainService
