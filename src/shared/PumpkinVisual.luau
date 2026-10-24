-- One approved carved pumpkin for decorations, pickups, hats and attack visuals.
-- Apply changes only appearance: callers keep their own physics, prompts and gameplay.
local PumpkinVisual = {}

PumpkinVisual.MeshId = "rbxassetid://16973748"
PumpkinVisual.TextureId = "rbxassetid://16973739"
PumpkinVisual.SourceAssetId = 1051236676
PumpkinVisual.MeshSize = Vector3.new(1.74819, 1.738895, 1.81699)
PumpkinVisual.MeshCenter = Vector3.new(0, 0.2544275, 0.002035)
PumpkinVisual.Version = 1

function PumpkinVisual.Apply(body: Part, width: number, tint: Color3?): Part
	assert(width > 0, "Pumpkin width must be positive")
	local scale = width / PumpkinVisual.MeshSize.X
	for _, child in body:GetChildren() do
		if child:IsA("SpecialMesh") then child:Destroy() end
	end
	body.Shape = Enum.PartType.Block
	body.Size = PumpkinVisual.MeshSize * scale
	body.Color = tint or Color3.new(1, 1, 1)
	body.Material = Enum.Material.SmoothPlastic
	body.Reflectance = 0
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId, mesh.TextureId = PumpkinVisual.MeshId, PumpkinVisual.TextureId
	mesh.Scale, mesh.Offset = Vector3.one * scale, -PumpkinVisual.MeshCenter * scale
	mesh.Parent = body
	body:SetAttribute("PumpkinVisualVersion", PumpkinVisual.Version)
	body:SetAttribute("SourceAssetId", PumpkinVisual.SourceAssetId)
	return body
end

function PumpkinVisual.Create(name: string, width: number, cframe: CFrame, tint: Color3?): Part
	local body = Instance.new("Part")
	body.Name, body.CFrame = name, cframe
	body.Anchored, body.CanCollide, body.CanQuery, body.CanTouch = true, false, false, false
	body.TopSurface, body.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return PumpkinVisual.Apply(body, width, tint)
end

-- Animated heads keep their authored joint bounds and hat/attachment positions.
function PumpkinVisual.Fit(body: Part, tint: Color3?): Part
	local size = body.Size
	PumpkinVisual.Apply(body, size.X, tint)
	body.Size = size
	local mesh = body:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh
	mesh.Scale = size / PumpkinVisual.MeshSize
	mesh.Offset = -PumpkinVisual.MeshCenter * mesh.Scale
	return body
end

return PumpkinVisual
