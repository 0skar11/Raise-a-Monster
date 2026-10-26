-- Encounter capacity follows the tycoon slots, independently of Studio's player limit.
local GameConfig = require(script.Parent.Config)
local Arena = {
	Origin = CFrame.new(GameConfig.Boss.Position),
	CombatRadius = 90,
	ArrivalCenter = Vector3.new(0, 0, 123),
	ArrivalSize = Vector3.new(40, 2, 30),
	ConnectorWidth = 24,
	Capacity = GameConfig.MaxPlots,
	ArrivalPoints = {},
}
Arena.ReturnPortalOrigin = Arena.Origin * CFrame.new(0, 0, 137)
local columns = math.ceil(Arena.Capacity / 2)
local spacing = math.min(10, 32 / math.max(1, columns - 1))
for index = 1, Arena.Capacity do
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)
	table.insert(Arena.ArrivalPoints, CFrame.new((column - (columns - 1) / 2) * spacing, 3.5, 115 + row * 8))
end

function Arena.IsCombatPosition(position: Vector3): boolean
	local localPosition = Arena.Origin:PointToObjectSpace(position)
	return localPosition.X * localPosition.X + localPosition.Z * localPosition.Z <= Arena.CombatRadius ^ 2
		and localPosition.Y >= -8 and localPosition.Y <= 150
end

function Arena.IsArenaBoss(position: Vector3): boolean
	-- Bosses can pursue players anywhere inside the encounter. The server also
	-- snapshots this identity when spawning, so combat guards never depend on
	-- remaining within five studs of the emergence seal.
	return Arena.IsCombatPosition(position)
end

return Arena
