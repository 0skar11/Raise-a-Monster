-- Replace only the map's natural Halloween pumpkins with the classic carved mesh.
-- Pumpkin Hunt pickups live under HalloweenEvent, outside HalloweenWorld.Props, and are never touched here.

local PumpkinDecor = {}

local VERSION = 1
local SOURCE_ASSET_ID = 1051236676
local MESH_ID = "rbxassetid://16973748"
local TEXTURE_ID = "rbxassetid://16973739"
local MESH_SIZE = Vector3.new(1.74819, 1.738895, 1.81699)
local MESH_CENTER = Vector3.new(0, 0.2544275, 0.002035)
local MODEL_PART_NAMES = { Pumpkin = true, PumpkinPart = true, Rib = true, RibPart = true, Stem = true, StemTip = true, Eye = true, Mouth = true }

local function removeMatchingOrnaments(body: Part, oldSize: Vector3, parent: Instance)
	local scale = oldSize.Y
	local expected = {
		Stem = { Vector3.new(0, scale * 0.55, 0) },
		Eye = { Vector3.new(-scale * 0.22, scale * 0.1, -scale * 0.56), Vector3.new(scale * 0.22, scale * 0.1, -scale * 0.56) },
		Mouth = { Vector3.new(0, -scale * 0.2, -scale * 0.57) },
	}
	local tolerance = math.max(0.05, scale * 0.08)
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Pumpkin" then
			local offsets = expected[child.Name]
			if offsets then
				local localPosition = body.CFrame:PointToObjectSpace(child.Position)
				for _, offset in offsets do
					if (localPosition - offset).Magnitude <= tolerance then
						child:Destroy()
						break
					end
				end
			end
		end
	end
end

local function convert(body: BasePart): boolean
	if not body:IsA("Part") then
		warn("[PumpkinDecor] Skipping unsupported pumpkin part:", body:GetFullName())
		return false
	end
	if body:GetAttribute("CarvedPumpkinDecorVersion") == VERSION then
		return false
	end

	local oldSize = body.Size
	local oldCFrame = body.CFrame
	local scale = oldSize.X / MESH_SIZE.X
	local scaledMeshSize = MESH_SIZE * scale
	local parent = body.Parent
	if not parent then
		return false
	end

	removeMatchingOrnaments(body, oldSize, parent)
	body.Shape = Enum.PartType.Block
	body.Size = scaledMeshSize
	body.CFrame = oldCFrame * CFrame.new(0, (scaledMeshSize.Y - oldSize.Y) * 0.5, 0)
	body.Color = Color3.new(1, 1, 1)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = MESH_ID
	mesh.TextureId = TEXTURE_ID
	mesh.Scale = Vector3.new(scale, scale, scale)
	mesh.Offset = -MESH_CENTER * scale
	mesh.Parent = body

	local light = body:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = if light.Range > 0 then light.Range else 8
		light.Brightness = 0.7
		light.Shadows = false
	end
	body:SetAttribute("CarvedPumpkinDecorVersion", VERSION)
	body:SetAttribute("SourceAssetId", SOURCE_ASSET_ID)
	return true
end

local function convertLeafModel(model: Model): boolean
	local body: BasePart? = nil
	local parts = {}
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") or not MODEL_PART_NAMES[child.Name] then
			return false
		end
		if child.Name == "PumpkinPart" or child.Name == "Pumpkin" then
			if body then
				return false
			end
			body = child
		else
			table.insert(parts, child)
		end
	end
	if not body then
		return false
	end
	if not body:IsA("Part") then
		warn("[PumpkinDecor] Skipping unsupported pumpkin part:", body:GetFullName())
		return false
	end
	if body:GetAttribute("CarvedPumpkinDecorVersion") == VERSION then
		return false
	end
	local pivot = model:GetPivot()
	for _, part in parts do
		part:Destroy()
	end
	local changed = convert(body)
	if changed and model.PrimaryPart == nil then
		model.WorldPivot = pivot
	end
	return changed
end

local function applyContainer(container: Instance): number
	local converted = 0
	for _, child in container:GetChildren() do
		if child:IsA("Folder") then
			converted += applyContainer(child)
		elseif child:IsA("Model") then
			if convertLeafModel(child) then
				converted += 1
			else
				local hasDirectPumpkin = false
				for _, modelChild in child:GetChildren() do
					if modelChild:IsA("BasePart") and (modelChild.Name == "Pumpkin" or modelChild.Name == "PumpkinPart") then
						hasDirectPumpkin = true
						break
					end
				end
				if not hasDirectPumpkin then
					converted += applyContainer(child)
				end
			end
		elseif child:IsA("BasePart") and (child.Name == "Pumpkin" or child.Name == "PumpkinPart") then
			if convert(child) then
				converted += 1
			end
		end
	end
	return converted
end

function PumpkinDecor.Apply(props: Instance?): number
	if not props then
		return 0
	end
	return applyContainer(props)
end

function PumpkinDecor.Init()
	local function applyWorld(world: Instance)
		local props = world:FindFirstChild("Props")
		if props then
			PumpkinDecor.Apply(props)
		end
	end

	local existing = workspace:FindFirstChild("HalloweenWorld")
	if existing then
		applyWorld(existing)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "HalloweenWorld" then
			task.defer(applyWorld, child)
		end
	end)
end

return PumpkinDecor
