-- Encounter capacity follows the tycoon slots, independently of Studio's player limit.
local GameConfig = require(script.Parent.Config)
local Arena = {
	Origin = CFrame.new(1600, 0.2, 0),
	CombatRadius = 90,
	ArrivalCenter = Vector3.new(0, 0, 123),
	ArrivalSize = Vector3.new(40, 2, 30),
	ConnectorWidth = 24,
	Capacity = GameConfig.MaxPlots,
	ArrivalPoints = {},
}
Arena.ReturnPortalOrigin = Arena.Origin * CFrame.new(0, 0, 137)
for _, z in { 115, 123 } do
	for _, x in { -10, 0, 10 } do
		table.insert(Arena.ArrivalPoints, CFrame.new(x, 3.5, z))
	end
end

function Arena.IsCombatPosition(position: Vector3): boolean
	local localPosition = Arena.Origin:PointToObjectSpace(position)
	return localPosition.X * localPosition.X + localPosition.Z * localPosition.Z <= Arena.CombatRadius ^ 2
		and localPosition.Y >= -8 and localPosition.Y <= 150
end

function Arena.IsArenaBoss(position: Vector3): boolean
	local localPosition = Arena.Origin:PointToObjectSpace(position)
	return math.abs(localPosition.X) < 5 and math.abs(localPosition.Z) < 5
end

return Arena
