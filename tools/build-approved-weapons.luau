-- Rebuild the approved Flow bat concepts as editable welded Roblox geometry.
-- Run from repo root: lune run tools/build-approved-weapons.luau
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local V, C, Color = r.Vector3, r.CFrame, r.Color3
local source = fs.readFile("assets/WeaponModels.rbxmx"):gsub("^<%?xml.-%?>%s*", "")
local folder = r.deserializeModel(source)[1]
local void = folder:FindFirstChild("VoidBat")
if not void then void = folder.IceSword:Clone(); void.Name = "VoidBat"; void.Parent = folder end
local styles = { WoodenBat = "Oak", IronBat = "Iron", IronSword = "Iron", ForestSword = "Forest", DesertSword = "Desert", IceSword = "Frost", LavaSword = "Magma", VoidBat = "Void" }
local palette = {
	Oak = { Color.fromRGB(153, 99, 45), Color.fromRGB(211, 167, 76), r.Enum.Material.Wood },
	Iron = { Color.fromRGB(103, 116, 129), Color.fromRGB(166, 180, 194), r.Enum.Material.Metal },
	Forest = { Color.fromRGB(120, 80, 37), Color.fromRGB(112, 234, 48), r.Enum.Material.Wood },
	Desert = { Color.fromRGB(173, 119, 52), Color.fromRGB(231, 190, 94), r.Enum.Material.Wood },
	Frost = { Color.fromRGB(65, 186, 232), Color.fromRGB(189, 247, 255), r.Enum.Material.Ice },
	Magma = { Color.fromRGB(38, 34, 36), Color.fromRGB(255, 104, 20), r.Enum.Material.Slate },
	Void = { Color.fromRGB(34, 18, 61), Color.fromRGB(156, 66, 240), r.Enum.Material.Metal },
}
local total = 0
-- Keep the long bat silhouette at avatar scale. The source design coordinates
-- remain convenient for placing grain, vines, facets and cracks.
local geometryScale = V.new(0.82, 0.64, 0.64)
local uprightGrip = C.new(-0.15, 0, 0) * C.Angles(0, 0, math.rad(-90))
for _, tool in folder:GetChildren() do
	local style = styles[tool.Name]
	if not style then continue end
	tool:ClearAllChildren()
	tool:SetAttribute("VisualStyle", style .. "Bat")
	tool.ToolTip = style .. " Bat"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = uprightGrip
	local colors = palette[style]
	local bodyColor, trimColor, bodyMaterial = colors[1], colors[2], colors[3]
	local handle
	local function part(name, size, cf, tint, material, shape)
		local right, up, back = cf.RightVector * geometryScale, cf.UpVector * geometryScale, cf.ZVector * geometryScale
		local scaledRight = right.Unit
		local scaledBack = scaledRight:Cross(up).Unit
		local scaledUp = scaledBack:Cross(scaledRight)
		local p = r.Instance.new("Part"); p.Name = name
		p.Size = V.new(size.X * right.Magnitude, size.Y * up.Magnitude, size.Z * back.Magnitude)
		p.CFrame = C.fromMatrix(cf.Position * geometryScale, scaledRight, scaledUp, scaledBack)
		p.Color = tint; p.Material = material or bodyMaterial; p.Shape = shape or r.Enum.PartType.Block
		p.TopSurface = r.Enum.SurfaceType.Smooth; p.BottomSurface = r.Enum.SurfaceType.Smooth
		p.Anchored = false; p.Massless = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.Parent = tool
		if handle then
			-- Store the offsets explicitly: offline generation cannot rely on
			-- Studio calculating WeldConstraint's hidden relative frames.
			local weld = r.Instance.new("Weld"); weld.Name = "Weld_" .. name
			weld.C0 = handle.CFrame:ToObjectSpace(p.CFrame); weld.C1 = C.new()
			weld.Part0 = handle; weld.Part1 = p; weld.Parent = p
		end
		total += 1
		return p
	end
	local function cylinder(name, x, length, diameter, tint, material)
		return part(name, V.new(length, diameter, diameter), C.new(x, 0, 0), tint, material, r.Enum.PartType.Cylinder)
	end
	local function beam(name, a, b, width, tint, material)
		local back = (a - b).Unit
		local right = V.new(0, 1, 0):Cross(back)
		if right.Magnitude < 0.001 then right = V.new(1, 0, 0):Cross(back) end
		right = right.Unit
		return part(name, V.new(width, width, (b - a).Magnitude), C.fromMatrix((a + b) / 2, right, back:Cross(right), back), tint, material)
	end
	handle = cylinder("Handle", 0, 1.35, 0.34, if style == "Frost" then Color.fromRGB(216, 237, 242) elseif style == "Void" then Color.fromRGB(65, 30, 96) else Color.fromRGB(53, 39, 31), r.Enum.Material.Fabric)
	cylinder("Pommel", -0.78, 0.22, 0.53, if style == "Oak" or style == "Desert" then trimColor else bodyColor, if style == "Frost" then r.Enum.Material.Ice else r.Enum.Material.Metal)
	for i = 0, 6 do
		local band = cylinder("GripWrap", -0.54 + i * 0.17, 0.035, 0.365, if style == "Frost" then Color.fromRGB(172, 201, 212) else Color.fromRGB(28, 25, 28), r.Enum.Material.Fabric)
		band.CFrame *= C.Angles(0, 0, math.rad(8))
		band:FindFirstChildOfClass("Weld").C0 = handle.CFrame:ToObjectSpace(band.CFrame)
	end
	-- Many overlapping short sections give a continuous widening throat,
	-- instead of three disconnected-looking cylinder shoulders.
	local profile = {
		{ 0.60, 0.34 }, { 1.20, 0.52 }, { 1.85, 0.77 },
		{ 2.60, 0.98 }, { 3.30, 1.08 }, { 4.14, 1.08 },
		{ 4.32, 1.00 }, { 4.42, 0.78 },
	}
	local function diameterAt(x)
		for index = 2, #profile do
			local a, b = profile[index - 1], profile[index]
			if x <= b[1] then
				local alpha = math.clamp((x - a[1]) / (b[1] - a[1]), 0, 1)
				return a[2] + (b[2] - a[2]) * alpha
			end
		end
		return profile[#profile][2]
	end
	for index = 0, 31 do
		local x = 0.66 + index * 0.12
		local name = if index == 2 then "BatThroat" elseif index == 8 then "BarrelLower" elseif index == 16 then "BarrelMiddle" elseif index == 25 then "BarrelUpper" else "TaperedBarrelSection"
		cylinder(name, x, 0.125, diameterAt(x), bodyColor)
	end
	part("RoundedBatCap", V.new(0.30, 0.96, 0.96), C.new(4.30, 0, 0), bodyColor, bodyMaterial, r.Enum.PartType.Ball)
	if style == "Oak" or style == "Desert" then
		for _, x in { 1.2, 3.7 } do
			cylinder("BrassBarrelBand", x, 0.2, if x < 2 then 0.78 else 1.14, trimColor, r.Enum.Material.Metal)
			for i = 0, 3 do
				local angle = i * math.pi / 2
				part("BandRivet", V.new(0.12, 0.12, 0.12), C.new(x, math.sin(angle) * (if x < 2 then 0.4 else 0.58), math.cos(angle) * (if x < 2 then 0.4 else 0.58)), Color.fromRGB(243, 210, 115), r.Enum.Material.Metal, r.Enum.PartType.Ball)
			end
		end
		for side = 0, 4 do
			local angle = side * math.pi * 2 / 5
			for i = 0, 3 do
				local x = 1.45 + i * 0.63
				local radiusA = 0.36 + math.min(i, 2) * 0.085
				local radiusB = 0.36 + math.min(i + 1, 2) * 0.085
				beam("CarvedWoodGrain", V.new(x, math.sin(angle + i * 0.06) * radiusA, math.cos(angle + i * 0.06) * radiusA), V.new(x + 0.62, math.sin(angle + (i + 1) * 0.06) * radiusB, math.cos(angle + (i + 1) * 0.06) * radiusB), 0.025, Color.fromRGB(105, 65, 30), r.Enum.Material.Wood)
			end
		end
	elseif style == "Iron" then
		for _, x in { 1.2, 4.13 } do cylinder("IronReinforcementBand", x, 0.18, if x < 2 then 0.79 else 1.17, Color.fromRGB(65, 74, 86), r.Enum.Material.Metal) end
		for side = 0, 4 do
			local angle = side * math.pi * 2 / 5
			part("ForgedIronPlate", V.new(2.5, 0.16, 0.45), C.new(2.8, math.sin(angle) * 0.47, math.cos(angle) * 0.47) * C.Angles(angle + math.pi / 2, 0, 0), if side % 2 == 0 then bodyColor else bodyColor:Lerp(trimColor, 0.32), r.Enum.Material.Metal)
			for _, x in { 1.75, 2.6, 3.72 } do part("IronPlateRivet", V.new(0.15, 0.15, 0.15), C.new(x, math.sin(angle) * 0.59, math.cos(angle) * 0.59), trimColor, r.Enum.Material.Metal, r.Enum.PartType.Ball) end
		end
	elseif style == "Forest" then
		for vine = 0, 1 do
			for i = 0, 17 do
				local x = 0.7 + i * 0.2
				local a = i * 0.46 + vine * math.pi
				local b = a + 0.46
				local radius = 0.32 + math.min((x - 0.7) / 3.3, 1) * 0.24
				beam("TwistingForestVine", V.new(x, math.sin(a) * radius, math.cos(a) * radius), V.new(x + 0.2, math.sin(b) * radius, math.cos(b) * radius), if vine == 0 then 0.1 else 0.075, if vine == 0 then Color.fromRGB(74, 109, 29) else trimColor, if vine == 0 then r.Enum.Material.Wood else r.Enum.Material.Neon)
			end
		end
		for i = 0, 5 do
			local angle = i * 2.1
			local leaf = part("ForestLeaf", V.new(0.25, 0.73, 0.35), C.new(1.25 + i * 0.52, math.sin(angle) * 0.69, math.cos(angle) * 0.69) * C.Angles(angle, 0, math.rad(35)), if i % 2 == 0 then Color.fromRGB(102, 180, 43) else Color.fromRGB(62, 139, 37), r.Enum.Material.Grass, r.Enum.PartType.Ball)
		end
	elseif style == "Frost" then
		for i = 0, 5 do
			local angle = i * math.pi / 3
			local facet = part("IceCrystalFacet", V.new(2.85, 0.11, 0.47), C.new(2.85, math.sin(angle) * 0.47, math.cos(angle) * 0.47) * C.Angles(angle + math.pi / 2, math.rad(if i % 2 == 0 then 4 else -4), 0), if i % 2 == 0 then trimColor else Color.fromRGB(44, 150, 218), r.Enum.Material.Ice)
			facet.Transparency = 0.15
		end
		for i = 0, 3 do
			local angle = i * math.pi / 2
			part("FrostFloatingCrystal", V.new(0.19, 0.36, 0.19), C.new(2.1 + i * 0.57, math.sin(angle) * 0.95, math.cos(angle) * 0.95) * C.Angles(math.rad(45), 0, math.rad(45)), trimColor, r.Enum.Material.Neon)
		end
	elseif style == "Magma" then
		for side = 0, 5 do
			local angle = side * math.pi / 3
			for i = 0, 4 do
				local x = 1.35 + i * 0.56
				local radius = if x < 2 then 0.4 else 0.55
				local a = angle + (i % 2) * 0.15
				local b = angle + ((i + 1) % 2) * 0.15
				beam("MoltenCrack", V.new(x, math.sin(a) * radius, math.cos(a) * radius), V.new(x + 0.55, math.sin(b) * radius, math.cos(b) * radius), 0.06, trimColor, r.Enum.Material.Neon)
				if i % 2 == 0 then
					beam("MoltenCrackBranch", V.new(x + 0.2, math.sin(a) * radius, math.cos(a) * radius), V.new(x + 0.4, math.sin(a + 0.53) * radius, math.cos(a + 0.53) * radius), 0.045, trimColor, r.Enum.Material.Neon)
				end
			end
		end
	elseif style == "Void" then
		for i = 0, 5 do
			local angle = i * math.pi / 3
			part("VoidBarrelFacet", V.new(2.77, 0.12, 0.39), C.new(2.87, math.sin(angle) * 0.49, math.cos(angle) * 0.49) * C.Angles(angle + math.pi / 2, 0, 0), if i % 2 == 0 then Color.fromRGB(49, 30, 80) else Color.fromRGB(25, 15, 44), r.Enum.Material.Metal)
			part("OrbitingVoidShard", V.new(0.14, 0.38, 0.19), C.new(1.5 + i * 0.48, math.sin(angle) * 0.87, math.cos(angle) * 0.87) * C.Angles(angle, 0, math.rad(35)), trimColor, r.Enum.Material.Neon)
		end
		cylinder("VoidPommelGlow", -0.8, 0.08, 0.54, trimColor, r.Enum.Material.Neon)
	end
	if style == "Forest" or style == "Frost" or style == "Magma" or style == "Void" then
		local attachment = r.Instance.new("Attachment"); attachment.Name = "BatElementAura"; attachment.Position = V.new(3, 0, 0) * geometryScale; attachment.Parent = handle
		local emitter = r.Instance.new("ParticleEmitter"); emitter.Name = "BatElementParticles"; emitter.Texture = if style == "Magma" then "rbxasset://textures/particles/fire_main.dds" elseif style == "Void" then "rbxasset://textures/particles/smoke_main.dds" else "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = r.ColorSequence.new(trimColor); emitter.Rate = if style == "Void" then 7 else 4; emitter.Lifetime = r.NumberRange.new(0.35, 0.7); emitter.Speed = r.NumberRange.new(0.3, 1); emitter.SpreadAngle = r.Vector2.new(180, 180); emitter.LightEmission = 0.7; emitter.Size = r.NumberSequence.new(0.25); emitter.Transparency = r.NumberSequence.new(0.25, 1); emitter.Parent = attachment
	end
end
local serialized = r.serializeModel({ folder }, true)
-- Lune writes the newer Content/uri representation; pinned Rojo 7.4 expects
-- the legacy ParticleEmitter.Texture property with a Content/url value.
serialized = serialized:gsub('<Content name="TextureContent">%s*<uri>(.-)</uri>%s*</Content>', '<Content name="Texture"><url>%1</url></Content>')
assert(not serialized:find("<uri>", 1, true), "Unconverted modern weapon Content property")
local saved = r.deserializeModel(serialized)[1]
for name in styles do
	local tool = assert(saved:FindFirstChild(name), "Lost weapon template " .. name)
	local handle = assert(tool:FindFirstChild("Handle"), "Missing handle")
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") then
			assert(not p.Anchored and p.Massless and not p.CanCollide, "Weapon physics changed")
			if p ~= handle then local weld = p:FindFirstChildOfClass("Weld"); assert(weld and weld.Part0 == handle and weld.Part1 == p, "Broken weapon weld") end
		end
	end
end
fs.writeFile("assets/WeaponModels.rbxmx", serialized)
print("Approved bat templates:", #saved:GetChildren(), "editable Parts:", total, "axis +X; upright grip; explicit weld offsets; legacy Tool names preserved")
