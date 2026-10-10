--[[
	MonsterModels (ModuleScript): builds the rigged monster templates at server start.
	Adapted from GrowAMonster_RiggedGenerator.lua (same rigs, regions and colors).
	Templates: ServerStorage.MonsterModels.<Region>.<NN_Name>.Baby / Teen / Adult
	Every model: HumanoidRootPart (PrimaryPart, anchored) + Motor6D joints + tag "Monster",
	animated on the client by ReplicatedStorage.Shared.MonsterAnimator.
	Feet touch the ground when the root is at height = model:GetAttribute("Scale").
]]

-- ========================= SETTINGS =========================

local STAGES = {
	{ name = "Baby", scale = 0.5 },
	{ name = "Teen", scale = 0.72 },
	{ name = "Adult", scale = 1.0 },
}

local RARITY = {
	Common    = { scale = 1.00, color = Color3.fromRGB(180, 180, 180), light = 0 },
	Uncommon  = { scale = 1.08, color = Color3.fromRGB(70, 210, 90),   light = 0 },
	Rare      = { scale = 1.18, color = Color3.fromRGB(60, 150, 255),  light = 0.8 },
	Epic      = { scale = 1.30, color = Color3.fromRGB(170, 80, 255),  light = 1.4 },
	Legendary = { scale = 1.45, color = Color3.fromRGB(255, 190, 40),  light = 2.0, sparkle = 6 },
	Mythic    = { scale = 1.70, color = Color3.fromRGB(255, 70, 70),   light = 3.0, sparkle = 18 },
}
local RARITY_ORDER = { "Common", "Common", "Uncommon", "Uncommon", "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" }

-- ========================= HELPERS =========================
local V = Vector3.new
local rgb = Color3.fromRGB
local M = Enum.Material
local rad = math.rad
local WHITE = rgb(250, 250, 250)
local SIDES = { { 1, "R" }, { -1, "L" } }

local function copy(t)
	local n = {}
	if t then for k, v in pairs(t) do n[k] = v end end
	return n
end

local function pal(t)
	t.main2 = t.main2 or t.main
	t.acc = t.acc or t.sec
	t.acc2 = t.acc2 or t.acc
	t.dark = t.dark or rgb(30, 28, 34)
	t.eye = t.eye or rgb(20, 20, 26)
	t.glow = t.glow or t.acc
	t.mat = t.mat or M.SmoothPlastic
	return t
end

-- ========================= RIG BUILDER =========================
local Rig = {}
Rig.__index = Rig

function Rig.new(model, s)
	local self = setmetatable({ model = model, s = s, bones = {}, n = 0, joints = 0 }, Rig)
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = V(2, 2, 2) * s
	hrp.CFrame = CFrame.new(0, 1 * s, 0)
	hrp.Transparency = 1
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.Parent = model
	model.PrimaryPart = hrp
	self.bones.Root = hrp
	local ac = Instance.new("AnimationController")
	ac.Name = "AnimationController"
	local an = Instance.new("Animator")
	an.Parent = ac
	ac.Parent = model
	return self
end

function Rig:mk(name, size, pos, color, mat, o)
	o = o or {}
	local s = self.s
	local p = Instance.new(o.wedge and "WedgePart" or "Part")
	p.Name = name
	p.Size = size * s
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.Transparency = o.tr or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	local cf = CFrame.new(pos * s)
	if o.rot then
		cf = cf * CFrame.Angles(rad(o.rot[1]), rad(o.rot[2]), rad(o.rot[3]))
	end
	p.CFrame = cf
	p.Parent = self.model
	self.n = self.n + 1
	return p
end

-- a bone is a visible part joined to its parent bone with a Motor6D at `joint`
function Rig:bone(name, parent, joint, size, pos, color, mat, o)
	o = o or {}
	local p0 = self.bones[parent]
	assert(p0, "missing parent bone " .. tostring(parent) .. " for " .. name)
	local p = self:mk(name, size, pos, color, mat, o)
	local jcf = CFrame.new(joint * self.s)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p
	m.C0 = p0.CFrame:Inverse() * jcf
	m.C1 = p.CFrame:Inverse() * jcf
	m:SetAttribute("Role", o.role or name)
	if o.side then m:SetAttribute("Side", o.side) end
	if o.index then m:SetAttribute("Index", o.index) end
	if o.axis then m:SetAttribute("Axis", o.axis) end
	if o.front ~= nil then m:SetAttribute("Front", o.front) end
	m.Parent = p0
	self.bones[name] = p
	self.joints = self.joints + 1
	return p
end

-- a detail part welded to a bone
function Rig:part(bone, name, size, pos, color, mat, o)
	local b = self.bones[bone]
	assert(b, "missing bone " .. tostring(bone) .. " for " .. name)
	local p = self:mk(name, size, pos, color, mat, o)
	local w = Instance.new("WeldConstraint")
	w.Part0 = b
	w.Part1 = p
	w.Parent = p
	return p
end

-- mirrored pair of details on one bone (+X = right)
function Rig:sym(bone, name, size, pos, color, mat, o)
	self:part(bone, name .. "R", size, pos, color, mat, o)
	local o2 = copy(o)
	if o and o.rot then o2.rot = { o.rot[1], -o.rot[2], -o.rot[3] } end
	self:part(bone, name .. "L", size, V(-pos.X, pos.Y, pos.Z), color, mat, o2)
end

-- ========================= DETAIL HELPERS =========================
local function eyes(r, bone, c, x, y, fz, sz)
	if c.glowEyes then
		r:sym(bone, "Eye", V(sz * 1.15, sz * 0.62, 0.15), V(x, y, fz - 0.06), c.glow, M.Neon, { rot = { 0, 0, 14 } })
		r:sym(bone, "Brow", V(sz * 1.35, sz * 0.24, 0.14), V(x, y + sz * 0.55, fz - 0.07), c.dark, M.SmoothPlastic, { rot = { 0, 0, 18 } })
	else
		r:sym(bone, "Eye", V(sz, sz * 1.2, 0.15), V(x, y, fz - 0.06), WHITE, M.SmoothPlastic)
		r:sym(bone, "Pupil", V(sz * 0.62, sz * 0.8, 0.1), V(x - sz * 0.06, y - sz * 0.12, fz - 0.14), c.eye, M.SmoothPlastic)
		r:sym(bone, "Shine", V(sz * 0.24, sz * 0.24, 0.05), V(x + sz * 0.12, y + sz * 0.26, fz - 0.19), WHITE, M.Neon)
	end
end

local function crystal(r, bone, c, x, y, z, h, tilt)
	local w = 0.32 * h + 0.25
	r:part(bone, "Crystal", V(w, h, w), V(x, y + h / 2, z), c.glow, M.Neon, { tr = 0.15, rot = { 0, 45, tilt or 0 } })
	r:part(bone, "CrystalTip", V(w * 0.55, h * 0.35, w * 0.55), V(x, y + h + h * 0.12, z), c.glow, M.Neon, { tr = 0.1, rot = { 0, 45, tilt or 0 } })
end

local CLUSTER = {
	{ 0, 0, 0, 1.0 }, { 0.9, 0.3, 0.2, 0.75 }, { -0.9, 0.2, -0.3, 0.8 }, { 0.2, 0.7, 0.8, 0.7 },
	{ -0.3, 0.6, -0.9, 0.7 }, { 0.5, -0.4, -0.8, 0.6 }, { -0.6, -0.3, 0.8, 0.65 }, { 0, 1.1, 0, 0.6 },
}
local function cluster(r, bone, name, cx, cy, cz, rr, color, mat, n)
	for i = 1, (n or #CLUSTER) do
		local d = CLUSTER[i]
		local sz = rr * 1.3 * d[4]
		r:part(bone, name, V(sz, sz, sz), V(cx + d[1] * rr, cy + d[2] * rr, cz + d[3] * rr), color, mat or M.Grass, { rot = { 0, i * 17, 0 } })
	end
end

local function flames(r, bone, c, x, y, z, k)
	r:part(bone, "Flame", V(0.9 * k, 1.3 * k, 0.9 * k), V(x, y + 0.65 * k, z), c.glow, M.Neon, { rot = { 0, 45, 0 }, tr = 0.1 })
	r:part(bone, "FlameTip", V(0.55 * k, 0.9 * k, 0.55 * k), V(x + 0.1 * k, y + 1.45 * k, z), c.glow, M.Neon, { rot = { 0, 20, 12 }, tr = 0.15 })
	r:part(bone, "FlameCore", V(0.45 * k, 0.8 * k, 0.45 * k), V(x, y + 0.6 * k, z - 0.1), rgb(255, 235, 140), M.Neon, { rot = { 0, 20, 0 } })
end

local function cracks(r, bone, c, cx, cy, fz, w, h)
	local L = { { -0.25, 0.1, 20, 0.7 }, { 0.2, -0.15, -25, 0.6 }, { 0.05, 0.3, 70, 0.4 }, { -0.1, -0.35, 60, 0.35 } }
	for _, d in ipairs(L) do
		r:part(bone, "Crack", V(0.14, h * d[4], 0.08), V(cx + d[1] * w, cy + d[2] * h, fz - 0.04), c.glow, M.Neon, { rot = { 0, 0, d[3] } })
	end
end

local function stars(r, bone, c, cy, rr)
	local L = { { 1, 0.4, 0.3 }, { -1.1, 0.8, -0.4 }, { 0.3, 1.3, 1 }, { -0.4, 0.2, -1.2 }, { 0.8, 1.0, -0.9 } }
	for _, d in ipairs(L) do
		r:part(bone, "Star", V(0.3, 0.3, 0.3), V(d[1] * rr, cy + d[2] * rr, d[3] * rr), c.glow, M.Neon, { rot = { 45, 45, 0 } })
	end
end

-- dorsal fins / spikes (wedge, swept back)
local function fins(r, bone, c, y, z1, z2, n, k, glow)
	for i = 0, n - 1 do
		local t = (n == 1) and 0.5 or i / (n - 1)
		local z = z1 + (z2 - z1) * t
		local h = k * (1 - math.abs(t - 0.35) * 0.7)
		r:part(bone, "Spike", V(0.3, h, h * 0.9), V(0, y + h / 2, z), glow and c.glow or c.acc, glow and M.Neon or c.mat, { wedge = true })
	end
end

local TAILS = {
	fluffy = { { 0.7, 0.7, 1.1, 0.5, "main" }, { 1.0, 1.0, 1.1, 0.4, "sec" } },
	bigfox = { { 0.9, 0.9, 1.3, 0.5, "main" }, { 1.3, 1.3, 1.4, 0.5, "main" }, { 1.1, 1.1, 0.8, 0.2, "sec" } },
	thin = { { 0.32, 0.32, 1.0, 0.5, "main" }, { 0.3, 0.3, 1.0, 0.4, "main" }, { 0.45, 0.45, 0.5, 0.2, "acc" } },
	long = { { 1.0, 0.8, 1.4, -0.2, "main" }, { 0.8, 0.65, 1.4, -0.2, "main" }, { 0.6, 0.5, 1.3, -0.15, "main" }, { 0.4, 0.35, 1.2, -0.1, "acc" } },
	nub = { { 0.7, 0.7, 0.6, 0.1, "sec" } },
	flame = { { 0.6, 0.6, 1.2, 0.6, "glow" }, { 0.8, 1.2, 0.8, 0.6, "glow" } },
	dragon = { { 1.6, 1.3, 1.6, -0.3, "main" }, { 1.3, 1.05, 1.5, -0.25, "main" }, { 1.0, 0.85, 1.4, -0.2, "main" }, { 0.75, 0.65, 1.3, -0.1, "main" }, { 0.5, 0.45, 1.2, 0, "main" } },
}
local function tailChain(r, c, kind, y, z, k, parent, axis)
	local prev = parent or "Body"
	for i, sg in ipairs(TAILS[kind]) do
		local w, h, L, dy, col = sg[1] * k, sg[2] * k, sg[3], sg[4], sg[5]
		local name = "Tail" .. i
		r:bone(name, prev, V(0, y, z), V(w, h, L), V(0, y + dy / 2, z + L / 2), c[col], (col == "glow") and M.Neon or c.mat,
			{ role = "Tail", index = i, axis = axis })
		y = y + dy
		z = z + L * 0.85
		prev = name
	end
	return prev, y, z
end

-- ========================= ARCHETYPES =========================
local ARCH = {}

-- SLIME ---------------------------------------------------------
function ARCH.slime(r, c, f)
	local tr = f.tr or 0.1
	r:bone("Body", "Root", V(0, 1.4, 0), V(4.4, 2.6, 4.4), V(0, 1.3, 0), c.main, c.mat, { role = "Root", tr = tr })
	r:part("Body", "Rim", V(4.9, 0.45, 4.9), V(0, 0.22, 0), c.main2, c.mat, { tr = tr })
	r:part("Body", "Side", V(4.0, 2.2, 4.8), V(0, 1.4, 0), c.main, c.mat, { tr = tr })
	r:part("Body", "Side2", V(4.8, 2.2, 4.0), V(0, 1.4, 0), c.main, c.mat, { tr = tr })
	r:part("Body", "Core", V(2.2, 1.6, 2.2), V(0, 1.6, 0), c.sec, M.Neon, { tr = 0.45 })
	eyes(r, "Body", c, 0.95, 2.0, -2.4, 0.8)
	r:part("Body", "Mouth", V(1.0, 0.22, 0.1), V(0, 1.15, -2.42), c.dark)
	r:part("Body", "MouthIn", V(0.6, 0.18, 0.08), V(0, 1.0, -2.43), rgb(230, 100, 120))
	r:sym("Body", "Blush", V(0.55, 0.25, 0.05), V(1.65, 1.35, -2.43), c.acc2, M.SmoothPlastic, { tr = 0.25 })
	-- top blob is its own bone so it jiggles
	r:bone("Top", "Body", V(0, 2.6, 0), V(3.4, 1.2, 3.4), V(0, 3.15, 0), c.main, c.mat, { role = "Top", tr = tr })
	r:part("Top", "TopCap", V(2.2, 0.7, 2.2), V(0, 4.0, 0), c.main, c.mat, { tr = tr })
	if f.leaf then
		r:part("Top", "Stem", V(0.3, 1.0, 0.3), V(0, 4.8, 0), rgb(110, 80, 50))
		r:part("Top", "LeafR", V(1.8, 0.2, 0.9), V(0.85, 5.2, 0), c.acc, M.Grass, { rot = { 0, 0, 25 } })
		r:part("Top", "LeafL", V(1.4, 0.2, 0.8), V(-0.7, 5.05, 0.1), c.acc, M.Grass, { rot = { 0, 30, -20 } })
	end
	if f.crystal then
		crystal(r, "Top", c, 0, 4.1, 0, 1.8, 0)
		crystal(r, "Top", c, 0.9, 3.6, 0.5, 1.1, -20)
		crystal(r, "Top", c, -0.9, 3.6, -0.3, 1.2, 20)
	end
	if f.sand then
		r:part("Top", "Peak", V(1.4, 1.4, 1.4), V(0, 4.6, 0), c.main, c.mat, { rot = { 0, 45, 0 } })
		r:part("Top", "Tip", V(0.7, 0.9, 0.7), V(0.2, 5.5, 0), c.sec, c.mat, { rot = { 0, 20, -15 } })
		r:part("Top", "Swirl", V(1.6, 0.3, 1.6), V(0, 4.2, 0), c.sec, c.mat, { rot = { 0, 20, 0 } })
	end
	if f.magma then
		flames(r, "Top", c, 0, 4.2, 0, 1.2)
		cracks(r, "Body", c, 0, 1.4, -2.4, 3.4, 1.8)
		r:sym("Body", "Rock", V(1.3, 1.0, 1.3), V(2.0, 2.4, 1.0), c.main2, c.mat, { rot = { 0, 30, 15 } })
	end
	if f.void then
		r:part("Top", "HornR", V(0.5, 1.4, 0.5), V(1.0, 4.6, 0), c.glow, M.Neon, { rot = { 0, 0, -22 } })
		r:part("Top", "HornL", V(0.5, 1.4, 0.5), V(-1.0, 4.6, 0), c.glow, M.Neon, { rot = { 0, 0, 22 } })
		stars(r, "Body", c, 3.3, 2.6)
	end
end

-- QUADRUPED -----------------------------------------------------
function ARCH.quad(r, c, f)
	local bulk = f.bulk or 1
	local legH = f.legH or 1.8
	local len = f.len or 1
	local bw, bh = 2.7 * bulk, 2.2 * bulk
	local bl = 3.8 * len * (0.6 + 0.4 * bulk)
	local by = legH + bh / 2
	r:bone("Body", "Root", V(0, by, 0), V(bw, bh, bl), V(0, by, 0), c.main, c.mat, { role = "Root" })
	r:part("Body", "Back", V(bw * 0.8, 0.35, bl * 0.85), V(0, by + bh / 2 + 0.15, 0), c.main, c.mat)
	r:part("Body", "Belly", V(bw * 0.72, 0.3, bl * 0.75), V(0, by - bh / 2 - 0.1, 0), c.sec, c.mat)
	r:part("Body", "Chest", V(bw * 0.78, bh * 0.75, 0.4), V(0, by - 0.05, -bl / 2 - 0.15), c.sec, c.mat)
	r:part("Body", "Rump", V(bw * 0.85, bh * 0.8, 0.35), V(0, by + 0.05, bl / 2 + 0.12), c.main2, c.mat)
	r:sym("Body", "Flank", V(0.3, bh * 0.75, bl * 0.8), V(bw / 2 + 0.1, by, 0), c.main2, c.mat)

	-- legs (4 bones)
	local lw = 0.65 + 0.35 * bulk
	local lx = bw / 2 - lw / 2
	local zs = { F = -bl / 2 + lw / 2 + 0.2, B = bl / 2 - lw / 2 - 0.2 }
	for _, fb in ipairs({ "F", "B" }) do
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local name = "Leg" .. fb .. sn
			local x, z = sx * lx, zs[fb]
			local h = legH + 0.4
			r:bone(name, "Body", V(x, legH + 0.2, z), V(lw, h, lw), V(x, h / 2, z), c.main2, c.mat,
				{ role = "Leg", side = sx, front = (fb == "F") })
			if fb == "B" then
				r:part(name, "Thigh", V(lw * 1.25, legH * 0.55 + 0.3, lw * 1.4), V(x, legH * 0.72 + 0.15, z + 0.05), c.main, c.mat)
			else
				r:part(name, "Shoulder", V(lw * 1.15, legH * 0.4 + 0.3, lw * 1.2), V(x, legH * 0.8 + 0.15, z), c.main, c.mat)
			end
			r:part(name, "Paw", V(lw * 1.2, 0.4, lw * 1.4), V(x, 0.2, z - 0.12), c.sec, c.mat)
			r:part(name, "Toes", V(lw * 0.9, 0.12, 0.08), V(x, 0.26, z - 0.12 - lw * 0.7 - 0.03), c.dark)
		end
	end

	-- head (big, chibi)
	local hs = 2.2 * (f.headMul or 1) * (0.78 + 0.22 * bulk)
	local hy = by + bh * 0.3 + hs * 0.38 + (f.headUp or 0)
	local hz = -bl / 2 - hs * 0.22
	local fz = hz - hs * 0.475
	r:bone("Head", "Body", V(0, by + bh * 0.25, -bl / 2 + 0.2), V(hs, hs * 0.9, hs * 0.95), V(0, hy, hz), c.main, c.mat, { role = "Neck" })
	r:part("Head", "Crown", V(hs * 0.82, 0.3, hs * 0.8), V(0, hy + hs * 0.45 + 0.12, hz + 0.05), c.main, c.mat)
	r:sym("Head", "Cheek", V(0.3, hs * 0.45, hs * 0.65), V(hs / 2 + 0.1, hy - hs * 0.12, hz - 0.05), c.main2, c.mat)
	local sl = f.snout or 1
	local snL = hs * 0.36 * sl
	r:part("Head", "Snout", V(hs * 0.56, hs * 0.3, snL), V(0, hy - hs * 0.1, fz - snL / 2 + 0.05), c.sec, c.mat)
	r:part("Head", "Nose", V(hs * 0.24, hs * 0.14, 0.18), V(0, hy + hs * 0.04, fz - snL + 0.05), c.dark)
	r:bone("Jaw", "Head", V(0, hy - hs * 0.28, fz + 0.15), V(hs * 0.48, hs * 0.13, snL * 0.95), V(0, hy - hs * 0.31, fz - snL / 2 + 0.1), c.sec, c.mat, { role = "Jaw" })
	r:part("Jaw", "Tongue", V(hs * 0.24, 0.08, snL * 0.5), V(0, hy - hs * 0.25, fz - snL * 0.35), rgb(235, 110, 130))
	eyes(r, "Head", c, hs * 0.25, hy + hs * 0.1, fz, hs * 0.2)
	local top = hy + hs * 0.45

	-- ears (bones, they twitch)
	local e = f.ears
	if e then
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local name = "Ear" .. sn
			local ex, ez = sx * hs * 0.3, hz + hs * 0.1
			if e == "pointy" or e == "big" or e == "tall" then
				local W = ({ pointy = 0.38, big = 0.5, tall = 0.32 })[e] * hs
				local H = ({ pointy = 0.42, big = 0.62, tall = 0.8 })[e] * hs
				r:bone(name, "Head", V(ex, top, ez), V(0.3, H, W), V(ex + sx * W * 0.1, top + H / 2 - 0.05, ez), c.main, c.mat,
					{ role = "Ear", side = sx, wedge = true, rot = { 0, sx * 90, 0 } })
				r:part(name, "Inner", V(0.12, H * 0.62, W * 0.55), V(ex + sx * W * 0.12, top + H * 0.3, ez - 0.18), c.acc2, M.SmoothPlastic,
					{ wedge = true, rot = { 0, sx * 90, 0 } })
			elseif e == "long" then
				r:bone(name, "Head", V(ex * 0.75, top, ez), V(hs * 0.22, hs * 0.95, 0.32), V(ex * 0.75, top + hs * 0.45, ez), c.main, c.mat,
					{ role = "Ear", side = sx, rot = { 0, 0, -sx * 8 } })
				r:part(name, "Inner", V(hs * 0.12, hs * 0.75, 0.1), V(ex * 0.75, top + hs * 0.43, ez - 0.18), c.acc2, M.SmoothPlastic, { rot = { 0, 0, -sx * 8 } })
			elseif e == "round" then
				r:bone(name, "Head", V(ex * 1.1, top, ez), V(hs * 0.3, hs * 0.3, 0.32), V(ex * 1.1, top + hs * 0.1, ez), c.main, c.mat, { role = "Ear", side = sx })
				r:part(name, "Inner", V(hs * 0.16, hs * 0.16, 0.1), V(ex * 1.1, top + hs * 0.1, ez - 0.18), c.sec)
			end
		end
	end

	if f.tail then tailChain(r, c, f.tail, by + bh * 0.2, bl / 2 + 0.2, bulk) end

	-- extras
	if f.horn then
		local hk = hs / 2.2
		for i = 0, 3 do
			local w = (0.5 - i * 0.1) * hk
			r:part("Head", "Horn" .. i, V(w, 0.45 * hk, w), V(0, top + 0.2 * hk + i * 0.42 * hk, hz - hs * 0.15), (i % 2 == 0) and c.acc or WHITE, M.Neon, { rot = { 0, 45, 0 } })
		end
	end
	if f.mane then
		for i = 0, 3 do
			r:part("Head", "Mane" .. i, V(0.35, hs * 0.42, hs * 0.38), V(0, top + 0.05 - i * 0.22, hz + hs * 0.2 + i * 0.32), c.acc, M.SmoothPlastic, { wedge = true })
		end
		for i = 0, 2 do
			r:part("Body", "ManeB" .. i, V(0.35, 0.6, 0.6), V(0, by + bh / 2 + 0.6, -bl / 2 + 0.4 + i * 0.55), c.acc, M.SmoothPlastic, { wedge = true })
		end
	end
	if f.antlers then
		local am = f.antlerGlow and M.Neon or c.mat
		local ac = f.antlerGlow and c.glow or c.acc
		r:sym("Head", "Antler", V(0.25, 1.6, 0.25), V(hs * 0.3 + 0.25, top + 0.75, hz), ac, am, { rot = { 0, 0, -20 } })
		r:sym("Head", "AntlerB", V(0.22, 1.0, 0.22), V(hs * 0.3 + 0.9, top + 1.55, hz), ac, am, { rot = { 0, 0, -60 } })
		r:sym("Head", "AntlerC", V(0.2, 0.9, 0.2), V(hs * 0.3 + 0.45, top + 1.35, hz - 0.35), ac, am, { rot = { -40, 0, -10 } })
		r:sym("Head", "AntlerD", V(0.2, 0.9, 0.2), V(hs * 0.3 + 0.65, top + 1.95, hz), ac, am, { rot = { 0, 0, -8 } })
	end
	if f.tusks then
		r:sym("Jaw", "Tusk", V(0.26, 0.9, 0.26), V(hs * 0.24, hy - hs * 0.1, fz - snL * 0.6), c.acc, M.SmoothPlastic, { rot = { -25, 0, -15 } })
	end
	if f.rhinoHorn then
		r:part("Head", "Horn", V(0.6, 1.6, 1.0), V(0, hy + 0.75, fz - snL * 0.6), c.acc, c.mat, { wedge = true, rot = { 0, 180, 0 } })
		r:part("Head", "Horn2", V(0.45, 0.9, 0.7), V(0, top + 0.35, hz - hs * 0.25), c.acc, c.mat, { wedge = true, rot = { 0, 180, 0 } })
	end
	if f.collar then
		r:part("Body", "Collar", V(bw * 0.9, 0.45, 0.9), V(0, by + bh * 0.3, -bl / 2 - 0.1), c.acc, M.Foil)
		r:part("Body", "Gem", V(0.4, 0.4, 0.15), V(0, by + bh * 0.2, -bl / 2 - 0.6), rgb(80, 200, 255), M.Neon, { rot = { 0, 0, 45 } })
		r:part("Head", "Headband", V(hs * 1.03, 0.3, hs * 0.98), V(0, hy + hs * 0.25, hz), c.acc, M.Foil)
	end
	if f.spikes then fins(r, "Body", c, by + bh / 2 + 0.2, -bl / 2 + 0.4, bl / 2 - 0.3, f.spikes, 0.95 * bulk, f.spikeGlow) end
	if f.crystals then
		crystal(r, "Body", c, 0, by + bh / 2 - 0.1, -bl * 0.25, 1.4 * bulk, 0)
		crystal(r, "Body", c, 0.5, by + bh / 2 - 0.1, bl * 0.05, 1.1 * bulk, -18)
		crystal(r, "Body", c, -0.5, by + bh / 2 - 0.1, bl * 0.25, 1.0 * bulk, 18)
	end
	if f.moss then cluster(r, "Body", "Moss", 0, by + bh / 2 + 0.2, 0, 0.6 * bulk, c.acc, M.Grass, 5) end
	if f.cactus then
		for i = 1, 6 do
			local sx = (i % 2 == 0) and 1 or -1
			r:part("Body", "Needle", V(0.35, 0.08, 0.08), V(sx * (bw / 2 + 0.4), by + ((i % 3) - 1) * 0.5, -bl / 3 + i * 0.35), rgb(250, 245, 220))
		end
		r:part("Head", "Flower", V(0.8, 0.35, 0.8), V(0, top + 0.15, hz), c.acc, M.SmoothPlastic, { rot = { 0, 45, 0 } })
		r:part("Head", "FlowerMid", V(0.35, 0.4, 0.35), V(0, top + 0.25, hz), rgb(255, 230, 90))
	end
	if f.lavaSpots then
		for i = 1, 4 do
			local sx = (i % 2 == 0) and 1 or -1
			r:part("Body", "LavaSpot", V(0.12, 0.5, 0.6), V(sx * (bw / 2 + 0.26), by + 0.2 * (i - 2), -bl / 2 + i * bl / 5), c.glow, M.Neon)
		end
	end
	if f.flames then
		for i = 1, 3 do flames(r, "Body", c, 0, by + bh / 2, -bl / 2 + i * bl / 4, 0.7 * bulk) end
	end
	if f.stars then stars(r, "Body", c, by + bh, 2.5) end
end

-- BIPED (golems, apes, penguin, bee, mummy, titans) ------------
function ARCH.biped(r, c, f)
	local k = f.bulk or 1
	local legH = 2.2 * (f.legMul or 1)
	local legW = 1.4 * k
	local pelY = legH + 0.6 * k
	r:bone("LowerTorso", "Root", V(0, pelY, 0), V(3.4 * k, 1.3 * k, 2.3 * k), V(0, pelY, 0), c.main2, c.mat, { role = "Root" })
	local tw, th, td = 4.2 * k, 2.9 * k, 2.6 * k
	local waistY = pelY + 0.5 * k
	local ty = waistY + th / 2
	r:bone("UpperTorso", "LowerTorso", V(0, waistY, 0), V(tw, th, td), V(0, ty, 0), c.main, c.mat, { role = "Waist" })
	r:part("UpperTorso", "Chest", V(tw * 0.62, th * 0.5, 0.25), V(0, ty + 0.2 * k, -td / 2 - 0.08), f.penguin and c.sec or c.main2, c.mat)
	r:part("UpperTorso", "Traps", V(tw * 0.8, 0.4 * k, td * 0.8), V(0, ty + th / 2 + 0.15, 0), c.main, c.mat)

	for _, S in ipairs(SIDES) do
		local sx, sn = S[1], S[2]
		-- legs
		local lname = "Leg" .. sn
		local lx = sx * 0.95 * k
		local lh = legH + 0.5 * k
		r:bone(lname, "LowerTorso", V(lx, legH + 0.3 * k, 0), V(legW, lh, legW), V(lx, lh / 2, 0), c.main2, c.mat, { role = "Leg", side = sx })
		r:part(lname, "Foot", V(legW + 0.25, 0.5, legW + 0.6), V(lx, 0.25, -0.25), c.sec, c.mat)
		-- arms
		local armU, armL = 1.6 * k * (f.armMul or 1), 1.5 * k * (f.armMul or 1)
		local ax = sx * (tw / 2 + 0.65 * k)
		local sy = ty + th / 2 - 0.5 * k
		local an, fn = "Arm" .. sn, "Forearm" .. sn
		r:bone(an, "UpperTorso", V(ax, sy, 0), V(1.2 * k, armU + 0.3, 1.2 * k), V(ax, sy - armU / 2, 0), c.main, c.mat, { role = "Arm", side = sx })
		r:part(an, "Shoulder", V(1.7 * k, 1.3 * k, 1.7 * k), V(ax, sy, 0), c.sec, c.mat)
		r:bone(fn, an, V(ax, sy - armU, 0), V(1.3 * k, armL, 1.3 * k), V(ax, sy - armU - armL / 2, 0), c.main, c.mat, { role = "Forearm", side = sx })
		r:part(fn, "Fist", V(1.65 * k, 1.25 * k, 1.65 * k), V(ax, sy - armU - armL - 0.3 * k, 0), c.main2, c.mat)
		if f.penguin then
			r:part(lname, "FootP", V(legW + 0.5, 0.3, legW + 1.0), V(lx, 0.15, -0.55), c.acc)
		end
	end

	-- head
	local hs = 2.3 * (f.headMul or 1) * (0.78 + 0.22 * k)
	local hy = ty + th / 2 + hs * 0.45
	local hz = -0.25
	local fz = hz - hs * 0.45
	r:bone("Head", "UpperTorso", V(0, ty + th / 2, -0.1), V(hs, hs * 0.9, hs * 0.9), V(0, hy, hz), c.main, c.mat, { role = "Neck" })
	r:part("Head", "Jawline", V(hs * 0.85, hs * 0.25, hs * 0.85), V(0, hy - hs * 0.45, hz), c.main2, c.mat)
	eyes(r, "Head", c, hs * 0.24, hy + hs * 0.08, fz, hs * 0.21)
	if not f.penguin and not f.stripes then
		r:part("Head", "Mouth", V(hs * 0.4, hs * 0.08, 0.1), V(0, hy - hs * 0.22, fz - 0.05), c.dark)
	end
	local top = hy + hs * 0.45
	local sy = ty + th / 2 - 0.5 * k
	local ax = tw / 2 + 0.65 * k

	if f.penguin then
		r:part("UpperTorso", "Belly", V(tw * 0.72, th * 0.85, 0.2), V(0, ty - 0.1, -td / 2 - 0.12), c.sec)
		r:part("LowerTorso", "BellyLow", V(3.4 * k * 0.7, 1.2 * k, 0.2), V(0, pelY, -2.3 * k / 2 - 0.1), c.sec)
		r:part("Head", "Face", V(hs * 0.75, hs * 0.55, 0.15), V(0, hy - 0.05, fz - 0.02), c.sec)
		r:part("Head", "Beak", V(0.75 * hs / 2.2, 0.45 * hs / 2.2, 0.9 * hs / 2.2), V(0, hy - hs * 0.15, fz - 0.4), c.acc, M.SmoothPlastic, { wedge = true })
	end
	if f.core then
		r:part("UpperTorso", "Core", V(1.0, 1.0, 0.3) * k, V(0, ty + 0.2, -td / 2 - 0.16), c.glow, M.Neon, { rot = { 0, 0, 45 } })
	end
	if f.cracks then
		cracks(r, "UpperTorso", c, 0, ty, -td / 2 - 0.12, tw, th)
		for _, S in ipairs(SIDES) do
			r:part("Forearm" .. S[2], "ArmCrack", V(0.14, 1.1 * k, 0.08), V(S[1] * ax, sy - 2.2 * k, -0.68 * k), c.glow, M.Neon, { rot = { 0, 0, 15 } })
		end
	end
	if f.canopy then
		cluster(r, "Head", "Leaves", 0, top + 1.0 * k, 0.2, 1.3 * k, c.acc, M.Grass)
		r:sym("Head", "Branch", V(0.4, 1.8, 0.4) * k, V(hs * 0.5, top + 0.4, 0.2), c.main2, c.mat, { rot = { 0, 0, -35 } })
		for _, S in ipairs(SIDES) do
			cluster(r, "Arm" .. S[2], "LeavesS", S[1] * ax, sy + 0.9 * k, 0, 0.7 * k, c.acc, M.Grass, 4)
		end
	end
	if f.moss then cluster(r, "UpperTorso", "Moss", tw * 0.2, ty + th * 0.35, -td / 2, 0.5 * k, c.sec, M.Grass, 4) end
	if f.flowers then
		local P = { { 1, 0.6 }, { -1.3, 0.2 }, { 0.4, -0.7 }, { -0.5, 1.0 }, { 1.5, -0.3 } }
		for i, p in ipairs(P) do
			r:part("UpperTorso", "Flower", V(0.6, 0.6, 0.25) * k, V(p[1] * k, ty + p[2] * k, -td / 2 - 0.14), (i % 2 == 0) and c.acc2 or c.acc, M.SmoothPlastic, { rot = { 0, 0, 45 } })
		end
		cluster(r, "Head", "HeadFlowers", 0, top + 0.3, hz, 0.4 * k, c.acc, M.SmoothPlastic, 5)
		for _, S in ipairs(SIDES) do
			r:part("Arm" .. S[2], "ShoulderFlower", V(0.7, 0.7, 0.7) * k, V(S[1] * ax, sy + 0.9 * k, 0), c.acc2, M.SmoothPlastic, { rot = { 45, 45, 0 } })
		end
	end
	if f.stripes then
		for i = -1, 1 do
			r:part("UpperTorso", "Stripe", V(tw + 0.06, 0.45 * k, td + 0.06), V(0, ty + i * 0.85 * k, 0), c.sec)
		end
		r:part("LowerTorso", "Stinger", V(0.5, 0.5, 1.0), V(0, pelY - 0.2, 2.3 * k / 2 + 0.5), c.sec, M.SmoothPlastic, { wedge = true, rot = { 0, 180, 0 } })
		r:sym("Head", "Antenna", V(0.15, 1.2, 0.15), V(hs * 0.25, top + 0.5, hz), c.sec, M.SmoothPlastic, { rot = { 0, 0, -20 } })
		r:sym("Head", "AntennaTip", V(0.38, 0.38, 0.38), V(hs * 0.25 + 0.25, top + 1.12, hz), c.sec)
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			r:bone("Wing" .. sn, "UpperTorso", V(sx * 0.9 * k, ty + th * 0.3, td / 2), V(2.6 * k, 0.15, 1.6 * k), V(sx * 2.0 * k, ty + th * 0.45, td / 2 + 0.7), c.acc, M.Glass,
				{ role = "Wing", side = sx, tr = 0.35, rot = { 0, sx * 25, sx * 30 } })
		end
	end
	if f.bandages then
		local Y = { -0.35, -0.05, 0.25, 0.45 }
		for i, yy in ipairs(Y) do
			r:part("UpperTorso", "Bandage", V(tw + 0.12, 0.3, td + 0.12), V(0, ty + yy * th, 0), c.sec, M.Fabric, { rot = { 0, 0, (i % 2 == 0) and 9 or -9 } })
		end
		r:part("Head", "HeadWrap", V(hs + 0.1, 0.35, hs * 0.9 + 0.1), V(0, hy + 0.3 * hs, hz), c.sec, M.Fabric, { rot = { 0, 0, 8 } })
		r:part("Head", "HeadWrap2", V(hs + 0.1, 0.3, hs * 0.9 + 0.1), V(0, hy - 0.25 * hs, hz), c.sec, M.Fabric, { rot = { 0, 0, -6 } })
		for _, S in ipairs(SIDES) do
			r:part("Forearm" .. S[2], "ArmWrap", V(1.42 * k, 0.3, 1.42 * k), V(S[1] * ax, sy - 2.3 * k, 0), c.sec, M.Fabric, { rot = { 0, 0, 12 } })
			r:part("Leg" .. S[2], "LegWrap", V(legW + 0.12, 0.3, legW + 0.12), V(S[1] * 0.95 * k, legH * 0.55, 0), c.sec, M.Fabric, { rot = { 0, 0, -10 } })
		end
	end
	if f.headdress then
		r:part("Head", "Nemes", V(hs + 0.5, hs * 0.5, hs + 0.4), V(0, top + 0.05, hz + 0.1), c.acc, M.Foil)
		r:sym("Head", "NemesFlap", V(0.5, hs * 1.3, hs * 0.7), V(hs / 2 + 0.25, hy - hs * 0.3, hz + 0.1), c.acc, M.Foil)
		for i = 1, 3 do
			r:sym("Head", "NemesStripe", V(0.52, 0.18, hs * 0.72), V(hs / 2 + 0.25, hy - hs * 0.3 - i * 0.35 + 0.35, hz + 0.1), c.sec)
		end
		r:part("Head", "Cobra", V(0.35, 0.65, 0.22), V(0, top + 0.42, fz - 0.12), c.acc, M.Foil)
		r:part("Head", "Beard", V(0.35, 0.8, 0.3), V(0, hy - hs * 0.6, fz + 0.1), c.sec)
		r:part("UpperTorso", "Collar", V(tw * 0.9, 0.5, td + 0.2), V(0, ty + th / 2 - 0.2, 0), c.sec)
		r:part("LowerTorso", "Belt", V(3.4 * k + 0.1, 0.45, 2.3 * k + 0.1), V(0, pelY + 0.3, 0), c.acc, M.Foil)
	end
	if f.crystals then
		for _, S in ipairs(SIDES) do crystal(r, "Arm" .. S[2], c, S[1] * ax, sy + 0.6 * k, 0, 1.5 * k, -S[1] * 20) end
		crystal(r, "UpperTorso", c, 0.6 * k, ty + th / 2 - 0.2, td / 2 - 0.3, 2.0 * k, 10)
		crystal(r, "UpperTorso", c, -0.7 * k, ty + th / 2 - 0.2, td / 2 - 0.2, 1.5 * k, -15)
	end
	if f.horns then
		r:sym("Head", "Horn", V(0.55, 1.7, 0.55) * k, V(hs * 0.42, top + 0.6 * k, hz), c.acc, c.mat, { rot = { 0, 0, -28 } })
		r:sym("Head", "HornTip", V(0.38, 0.9, 0.38) * k, V(hs * 0.42 + 0.75 * k, top + 1.55 * k, hz), c.glow, M.Neon, { rot = { 0, 0, -10 } })
	end
	if f.crown then
		for i = -2, 2 do
			r:part("Head", "CrownSpike", V(0.3, 0.9 - math.abs(i) * 0.15, 0.3) * k, V(i * hs * 0.2, top + 0.4 * k, hz - hs * 0.3), c.glow, M.Neon, { rot = { 0, 45, 0 } })
		end
	end
	if f.flames then
		flames(r, "Head", c, 0, top - 0.1, hz, 1.05 * k)
		for _, S in ipairs(SIDES) do flames(r, "Arm" .. S[2], c, S[1] * ax, sy + 0.5 * k, 0, 0.75 * k) end
	end
	if f.wingsBig then
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local wy = ty + th * 0.35
			r:bone("Wing" .. sn, "UpperTorso", V(sx * tw * 0.35, wy, td / 2), V(5 * k, 0.5, 0.5), V(sx * (tw * 0.35 + 2.3 * k), wy + 1.1 * k, td / 2 + 0.3), c.main2, c.mat,
				{ role = "Wing", side = sx, rot = { 0, 0, sx * 25 } })
			r:part("Wing" .. sn, "Membrane", V(5 * k, 0.2, 3.2 * k), V(sx * (tw * 0.35 + 2.3 * k), wy + 0.9 * k, td / 2 + 1.9 * k), c.glow, M.Neon, { tr = 0.25, rot = { 0, 0, sx * 25 } })
		end
	end
	if f.icicles then
		for i = -2, 2 do
			r:part("UpperTorso", "Icicle", V(0.32, 0.9, 0.32) * k, V(i * tw * 0.2, ty - th / 2 - 0.3, -td / 2 + 0.15), c.glow, M.Ice, { tr = 0.2, rot = { 0, 45, 0 } })
		end
	end
end

-- BIRD (griffin, phoenix, raven) --------------------------------
function ARCH.bird(r, c, f)
	local gy = f.griffin and 0.9 or 0
	local by = 3.3 + gy
	r:bone("Body", "Root", V(0, by, 0), V(2.4, 2.2, 3.2), V(0, by, 0), c.main, c.mat, { role = "Root" })
	r:part("Body", "Chest", V(2.0, 1.8, 0.4), V(0, by - 0.1, -1.75), c.sec, c.mat)
	r:part("Body", "Back", V(2.0, 0.3, 2.6), V(0, by + 1.2, 0.1), c.main2, c.mat)
	local hy, hz = by + 1.7, -1.8
	local fz = hz - 0.95
	r:bone("Head", "Body", V(0, by + 0.9, -1.2), V(1.9, 1.8, 1.9), V(0, hy, hz), c.main, c.mat, { role = "Neck" })
	r:part("Head", "Beak", V(0.75, 0.55, 1.1), V(0, hy - 0.15, fz - 0.55), c.acc, c.mat, { wedge = true })
	r:part("Head", "BeakLow", V(0.6, 0.22, 0.7), V(0, hy - 0.5, fz - 0.35), c.acc2, c.mat)
	eyes(r, "Head", c, 0.5, hy + 0.22, fz, 0.42)
	if f.crest then
		for i = 0, 2 do
			r:part("Head", "Crest" .. i, V(0.25, 1.1 - i * 0.2, 0.9), V(0, hy + 1.2 - i * 0.1, hz + 0.1 + i * 0.5), c.glow, M.Neon, { wedge = true })
		end
	end
	local wm = f.glowWings and M.Neon or c.mat
	local wc = f.glowWings and c.glow or c.sec
	for _, S in ipairs(SIDES) do
		local sx, sn = S[1], S[2]
		local wy = by + 0.6
		r:bone("Wing" .. sn, "Body", V(sx * 1.1, wy, -0.4), V(2.8, 0.35, 2.2), V(sx * 2.4, wy + 0.45, 0.1), c.main, c.mat, { role = "Wing", side = sx, rot = { 0, 0, sx * 20 } })
		r:part("Wing" .. sn, "Cover", V(2.6, 0.3, 1.1), V(sx * 2.4, wy + 0.55, -0.55), c.main2, c.mat, { rot = { 0, 0, sx * 20 } })
		r:bone("Wing2" .. sn, "Wing" .. sn, V(sx * 3.7, wy + 0.95, 0.1), V(2.6, 0.3, 1.9), V(sx * 4.9, wy + 1.6, 0.4), c.sec, c.mat, { role = "Wing2", side = sx, rot = { 0, 0, sx * 32 } })
		for i = 0, 2 do
			r:part("Wing2" .. sn, "Feather" .. i, V(1.4, 0.22, 0.5), V(sx * (4.6 + i * 0.55), wy + 1.3 + i * 0.35, 1.35 + i * 0.15), wc, wm, { rot = { 0, -sx * 15, sx * 32 } })
		end
		r:part("Wing2" .. sn, "Tip", V(1.6, 0.25, 0.9), V(sx * 6.2, wy + 2.4, 0.6), wc, wm, { rot = { 0, -sx * 10, sx * 40 } })
	end
	r:bone("Tail1", "Body", V(0, by + 0.2, 1.5), V(1.6, 0.3, 2.0), V(0, by - 0.1, 2.4), c.sec, c.mat, { role = "Tail", index = 1, axis = "X" })
	r:part("Tail1", "TailTip", V(1.8, 0.25, 0.9), V(0, by - 0.35, 3.6), wc, wm)
	if f.phoenix then
		for i = -1, 1 do
			r:part("Tail1", "Plume", V(0.4, 0.25, 3.4), V(i * 0.7, by - 0.6, 4.9), c.glow, M.Neon, { tr = 0.1, rot = { -12, i * 18, 0 } })
		end
	end
	if f.griffin then
		local legTop = by - 1.0
		for _, fb in ipairs({ "F", "B" }) do
			for _, S in ipairs(SIDES) do
				local sx, sn = S[1], S[2]
				local name = "Leg" .. fb .. sn
				local z = (fb == "F") and -1.0 or 1.1
				local front = fb == "F"
				local w = front and 0.6 or 0.9
				r:bone(name, "Body", V(sx * 0.8, legTop, z), V(w, legTop + 0.2, w), V(sx * 0.8, (legTop + 0.2) / 2, z), front and c.acc or c.main2, c.mat,
					{ role = "Leg", side = sx, front = front })
				if front then
					r:part(name, "Talon", V(0.85, 0.3, 1.1), V(sx * 0.8, 0.15, z - 0.3), c.acc)
				else
					r:part(name, "Haunch", V(1.2, 1.6, 1.5), V(sx * 0.85, legTop - 0.5, z + 0.1), c.main, c.mat)
					r:part(name, "RearPaw", V(1.0, 0.35, 1.2), V(sx * 0.8, 0.17, z - 0.2), c.sec)
				end
			end
		end
		r:part("Body", "LionTail", V(0.3, 0.3, 2.2), V(0, by - 0.2, 2.6), c.main2, c.mat, { rot = { 25, 0, 0 } })
	else
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local top = by - 0.9
			r:bone("Leg" .. sn, "Body", V(sx * 0.6, top, 0.2), V(0.32, top + 0.1, 0.32), V(sx * 0.6, (top + 0.1) / 2, 0.2), c.acc, M.SmoothPlastic, { role = "Leg", side = sx })
			r:part("Leg" .. sn, "Foot", V(0.9, 0.2, 1.1), V(sx * 0.6, 0.1, -0.1), c.acc)
			r:part("Leg" .. sn, "Thigh", V(0.8, 0.8, 0.9), V(sx * 0.6, top - 0.2, 0.2), c.main2, c.mat)
		end
	end
end

-- DRAGON / WYRM -------------------------------------------------
function ARCH.dragon(r, c, f)
	local k = f.bulk or 1
	local legH = 2.0
	local bw, bh, bl = 3.2 * k, 2.8 * k, 5.0 * k
	local by = legH + bh / 2
	r:bone("Body", "Root", V(0, by, 0), V(bw, bh, bl), V(0, by, 0), c.main, c.mat, { role = "Root" })
	r:part("Body", "Belly", V(bw * 0.72, 0.4, bl * 0.85), V(0, by - bh / 2 - 0.1, 0), c.sec, c.mat)
	for i = -2, 2 do
		r:part("Body", "BellyPlate", V(bw * 0.6, 0.15, 0.6), V(0, by - bh / 2 - 0.32, i * bl * 0.18), c.sec, c.mat)
	end
	r:part("Body", "Chest", V(bw * 0.8, bh * 0.8, 0.5), V(0, by, -bl / 2 - 0.2), c.sec, c.mat)
	r:sym("Body", "Flank", V(0.3, bh * 0.7, bl * 0.8), V(bw / 2 + 0.1, by + 0.1, 0), c.main2, c.mat)

	local lx = bw / 2 - 0.5
	for _, fb in ipairs({ "F", "B" }) do
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local name = "Leg" .. fb .. sn
			local z = (fb == "F") and (-bl / 2 + 0.9) or (bl / 2 - 0.9)
			local h = legH + 0.5
			r:bone(name, "Body", V(sx * lx, legH + 0.3, z), V(1.3 * k, h, 1.3 * k), V(sx * lx, h / 2, z), c.main2, c.mat, { role = "Leg", side = sx, front = (fb == "F") })
			r:part(name, "Thigh", V(1.6 * k, legH * 0.6, 1.8 * k), V(sx * lx, legH * 0.75 + 0.2, z + 0.1), c.main, c.mat)
			r:part(name, "Foot", V(1.5 * k, 0.45, 1.7 * k), V(sx * lx, 0.22, z - 0.25), c.main2, c.mat)
			for t = -1, 1 do
				r:part(name, "Claw", V(0.28, 0.35, 0.55), V(sx * lx + t * 0.45 * k, 0.18, z - 0.25 - 0.85 * k - 0.2), c.acc, c.mat, { wedge = true })
			end
		end
	end

	local fzb = -bl / 2
	r:bone("Neck", "Body", V(0, by + 0.6, fzb + 0.3), V(1.7 * k, 1.7 * k, 2.4), V(0, by + 1.4, fzb - 0.6), c.main, c.mat, { role = "Neck", rot = { 35, 0, 0 } })
	r:part("Neck", "NeckBelly", V(1.2 * k, 0.3, 2.0), V(0, by + 0.9, fzb - 0.8), c.sec, c.mat, { rot = { 35, 0, 0 } })
	local hy, hz = by + 2.9, fzb - 2.1
	r:bone("Head", "Neck", V(0, by + 2.3, fzb - 1.3), V(2.3, 1.8, 2.4), V(0, hy, hz), c.main, c.mat, { role = "Head" })
	r:part("Head", "Snout", V(1.7, 0.95, 1.9), V(0, hy - 0.3, hz - 2.0), c.main, c.mat)
	r:part("Head", "Brow", V(2.4, 0.4, 0.9), V(0, hy + 0.75, hz - 0.85), c.main2, c.mat)
	r:sym("Head", "Nostril", V(0.25, 0.2, 0.1), V(0.42, hy - 0.05, hz - 2.97), c.dark)
	r:sym("Head", "Fang", V(0.2, 0.42, 0.2), V(0.55, hy - 0.95, hz - 2.4), WHITE)
	local ce = copy(c)
	ce.glowEyes = true
	eyes(r, "Head", ce, 0.72, hy + 0.3, hz - 1.2, 0.45)
	r:sym("Head", "Horn", V(0.45, 1.9, 0.45), V(0.75, hy + 1.3, hz + 0.7), c.acc, c.mat, { rot = { 40, 0, -15 } })
	r:sym("Head", "HornSmall", V(0.32, 1.0, 0.32), V(1.15, hy + 0.5, hz + 0.9), c.acc, c.mat, { rot = { 60, 0, -40 } })
	r:sym("Head", "Frill", V(0.2, 1.0, 1.0), V(1.2, hy, hz + 0.6), c.acc, c.mat, { wedge = true })
	r:bone("Jaw", "Head", V(0, hy - 0.65, hz + 0.6), V(1.5, 0.42, 2.5), V(0, hy - 0.98, hz - 1.3), c.sec, c.mat, { role = "Jaw" })
	r:sym("Jaw", "LowFang", V(0.18, 0.35, 0.18), V(0.5, hy - 0.65, hz - 2.2), WHITE)

	local wm = f.glowWings and M.Neon or c.mat
	local wc = f.glowWings and c.glow or c.sec
	local wtr = f.glowWings and 0.2 or 0
	for _, S in ipairs(SIDES) do
		local sx, sn = S[1], S[2]
		local wy = by + bh / 2
		r:bone("Wing" .. sn, "Body", V(sx * (bw / 2 - 0.2), wy - 0.2, -0.6), V(4.6, 0.45, 0.45), V(sx * (bw / 2 + 1.9), wy + 0.65, -0.6), c.main2, c.mat,
			{ role = "Wing", side = sx, rot = { 0, 0, sx * 22 } })
		r:part("Wing" .. sn, "Membrane", V(4.4, 0.18, 3.2), V(sx * (bw / 2 + 1.9), wy + 0.55, 1.0), wc, wm, { tr = wtr, rot = { 0, 0, sx * 22 } })
		local ex, ey = sx * (bw / 2 + 4.05), wy + 1.5
		r:bone("Wing2" .. sn, "Wing" .. sn, V(ex, ey, -0.6), V(3.4, 0.35, 0.35), V(ex + sx * 1.45, ey + 1.0, -0.5), c.main2, c.mat,
			{ role = "Wing2", side = sx, rot = { 0, 0, sx * 35 } })
		r:part("Wing2" .. sn, "Membrane2", V(3.2, 0.16, 3.0), V(ex + sx * 1.4, ey + 0.85, 1.0), wc, wm, { tr = wtr, rot = { 0, 0, sx * 35 } })
		r:part("Wing2" .. sn, "WingClaw", V(0.3, 0.5, 0.3), V(ex + sx * 2.9, ey + 2.05, -0.5), c.acc, c.mat, { rot = { 0, 0, sx * 35 } })
	end

	local last, ty, tz = tailChain(r, c, "dragon", by - 0.1, bl / 2 - 0.2, k)
	r:part(last, "TailBlade", V(0.3, 1.3, 1.5), V(0, ty + 0.2, tz + 0.5), f.spikeGlow and c.glow or c.acc, f.spikeGlow and M.Neon or c.mat, { wedge = true, rot = { 0, 180, 0 } })
	for i = 1, 4 do
		r:part("Tail" .. i, "TailSpike", V(0.3, 0.7 - i * 0.1, 0.7), V(0, by + 0.5 - i * 0.25, bl / 2 + 0.4 + (i - 1) * 1.3), f.spikeGlow and c.glow or c.acc, f.spikeGlow and M.Neon or c.mat, { wedge = true })
	end
	fins(r, "Body", c, by + bh / 2, -bl / 2 + 0.6, bl / 2 - 0.4, 5, 1.0 * k, f.spikeGlow)
	if f.crystals then
		crystal(r, "Body", c, 0.7, by + bh / 2 - 0.1, -0.6, 1.6 * k, -15)
		crystal(r, "Body", c, -0.7, by + bh / 2 - 0.1, 0.9, 1.3 * k, 15)
	end
	if f.flames then
		flames(r, "Body", c, 0.8, by + bh / 2, -1.2, 0.8 * k)
		flames(r, "Body", c, -0.8, by + bh / 2, 1.0, 0.7 * k)
		r:part("Jaw", "Breath", V(0.9, 0.9, 1.6), V(0, hy - 0.7, hz - 3.4), c.glow, M.Neon, { tr = 0.25 })
	end
	if f.cracks then
		for i = -1, 1 do
			r:sym("Body", "LavaVein", V(0.08, bh * 0.6, 0.15), V(bw / 2 + 0.27, by, i * bl * 0.3), c.glow, M.Neon, { rot = { 25 * i, 0, 0 } })
		end
	end
end

-- SERPENT -------------------------------------------------------
function ARCH.serpent(r, c, f)
	local n = 8
	local P = {}
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local w = 2.3 - t * 1.4
		local x = math.sin(i * 0.9) * 1.6
		local z = -3 + (i - 1) * 1.65
		local y = w / 2 + ((i <= 3) and (3 - i) * 1.3 + 0.4 or 0)
		P[i] = { x, y, z, w }
	end
	for i = 1, n do
		local x, y, z, w = P[i][1], P[i][2], P[i][3], P[i][4]
		local name = "Seg" .. i
		if i == 1 then
			r:bone(name, "Root", V(x, y, z), V(w, w, 1.9), V(x, y, z), c.main, c.mat, { role = "Root" })
		else
			local p = P[i - 1]
			r:bone(name, "Seg" .. (i - 1), V((p[1] + x) / 2, (p[2] + y) / 2, (p[3] + z) / 2), V(w, w, 1.9), V(x, y, z), c.main, c.mat, { role = "Spine", index = i - 1 })
		end
		r:part(name, "Belly", V(w * 0.8, 0.25, 1.7), V(x, y - w / 2 - 0.08, z), c.sec, c.mat)
		r:part(name, "Fin", V(0.22, w * 0.5, 1.2), V(x, y + w / 2 + w * 0.2, z), c.glow, M.Neon, { tr = 0.1, wedge = true })
	end
	local hx, hy, hz = P[1][1], P[1][2] + 1.2, P[1][3] - 1.6
	r:bone("Head", "Seg1", V(hx, P[1][2] + 0.6, P[1][3] - 0.8), V(2.6, 2.0, 3.0), V(hx, hy, hz), c.main, c.mat, { role = "Neck" })
	r:part("Head", "Snout", V(1.9, 1.0, 1.6), V(hx, hy - 0.3, hz - 2.0), c.main, c.mat)
	r:bone("Jaw", "Head", V(hx, hy - 0.75, hz + 0.6), V(1.7, 0.45, 2.4), V(hx, hy - 1.05, hz - 1.4), c.sec, c.mat, { role = "Jaw" })
	r:sym("Jaw", "Fang", V(0.18, 0.4, 0.18), V(0.55, hy - 0.7, hz - 2.3), WHITE)
	local ce = copy(c)
	ce.glowEyes = true
	r:sym("Head", "Eye", V(0.55, 0.32, 0.15), V(0.8, hy + 0.35, hz - 1.56), c.glow, M.Neon, { rot = { 0, 0, 14 } })
	r:sym("Head", "Horn", V(0.42, 1.8, 0.42), V(0.8, hy + 1.3, hz + 0.8), c.acc, c.mat, { rot = { 45, 0, -15 } })
	if f.crest then
		r:part("Head", "Crest", V(0.3, 1.4, 2.0), V(hx, hy + 1.3, hz + 0.6), c.glow, M.Neon, { tr = 0.1, wedge = true })
	end
	if f.whiskers then
		r:sym("Head", "Whisker", V(0.12, 0.12, 3.2), V(1.3, hy - 0.4, hz - 1.6), c.glow, M.Neon, { rot = { 0, -35, -10 } })
	end
	if f.fins then
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			r:bone("Wing" .. sn, "Seg2", V(P[2][1] + sx * 0.9, P[2][2], P[2][3]), V(4.0, 0.2, 2.4), V(P[2][1] + sx * 2.8, P[2][2] + 0.9, P[2][3] + 0.6), c.glow, M.Neon,
				{ role = "Wing", side = sx, tr = 0.25, rot = { 0, sx * 15, sx * 28 } })
		end
	end
	if f.crystals then
		crystal(r, "Seg4", c, P[4][1], P[4][2] + P[4][4] / 2, P[4][3], 1.4, 0)
		crystal(r, "Seg5", c, P[5][1], P[5][2] + P[5][4] / 2, P[5][3], 1.1, 15)
	end
	if f.stars then stars(r, "Seg3", c, 3.0, 3.6) end
end

-- SPIDER --------------------------------------------------------
function ARCH.spider(r, c, f)
	r:bone("Body", "Root", V(0, 2.3, -0.8), V(2.4, 1.5, 2.4), V(0, 2.3, -0.8), c.main, c.mat, { role = "Root" })
	r:part("Body", "HeadCap", V(1.9, 0.5, 1.6), V(0, 3.2, -1.1), c.main2, c.mat)
	for i = 0, 2 do
		r:part("Body", "EyeRow" .. i, V(0.3, 0.3, 0.12), V(-0.5 + i * 0.5, 2.65, -2.06), c.glow, M.Neon)
	end
	r:sym("Body", "EyeBig", V(0.42, 0.42, 0.12), V(0.35, 2.15, -2.06), c.glow, M.Neon)
	r:sym("Body", "Fang", V(0.25, 0.7, 0.25), V(0.4, 1.35, -2.0), c.acc, c.mat, { rot = { -15, 0, 0 } })
	r:bone("Abdomen", "Body", V(0, 2.6, 0.4), V(3.4, 2.8, 3.6), V(0, 3.0, 2.0), c.main, c.mat, { role = "Abdomen" })
	r:part("Abdomen", "Mark", V(1.4, 0.15, 1.8), V(0, 4.45, 2.0), c.glow, M.Neon, { rot = { 0, 45, 0 } })
	r:part("Abdomen", "Mark2", V(0.6, 0.15, 0.6), V(0, 4.45, 3.2), c.glow, M.Neon, { rot = { 0, 45, 0 } })
	r:part("Abdomen", "Spinneret", V(1.0, 1.0, 0.4), V(0, 2.6, 3.9), c.sec, c.mat)
	for i = 1, 4 do
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local z = -1.8 + (i - 1) * 0.55
			local yaw = (i - 2.5) * 22
			local up, lo = "Leg" .. sn .. i, "Knee" .. sn .. i
			r:bone(up, "Body", V(sx * 1.0, 2.6, z), V(2.8, 0.42, 0.42), V(sx * 2.25, 3.35, z + (i - 2.5) * 0.4), c.main2, c.mat,
				{ role = "SpiderLeg", side = sx, index = i, rot = { 0, sx * -yaw, sx * 35 } })
			local kz = z + (i - 2.5) * 0.8
			r:bone(lo, up, V(sx * 3.4, 4.0, kz), V(0.4, 3.9, 0.4), V(sx * 3.75, 2.0, kz + (i - 2.5) * 0.3), c.main2, c.mat,
				{ role = "SpiderKnee", side = sx, index = i, rot = { 0, 0, -sx * 10 } })
			r:part(lo, "Joint", V(0.6, 0.6, 0.6), V(sx * 3.4, 4.0, kz), c.sec, c.mat)
		end
	end
end

-- SCORPION ------------------------------------------------------
function ARCH.scorpion(r, c, f)
	r:bone("Body", "Root", V(0, 1.5, 0), V(2.6, 1.3, 3.6), V(0, 1.5, 0), c.main, c.mat, { role = "Root" })
	for i = -1, 1 do
		r:part("Body", "Plate", V(2.3, 0.3, 1.0), V(0, 2.2, i * 1.1), c.sec, c.mat)
	end
	r:part("Body", "Head", V(2.0, 1.0, 1.4), V(0, 1.5, -2.4), c.main, c.mat)
	local ce = copy(c)
	ce.glowEyes = true
	eyes(r, "Body", ce, 0.45, 1.75, -3.1, 0.32)
	for _, S in ipairs(SIDES) do
		local sx, sn = S[1], S[2]
		r:bone("Claw" .. sn, "Body", V(sx * 0.9, 1.6, -2.6), V(0.65, 0.65, 2.4), V(sx * 1.5, 1.6, -3.4), c.main, c.mat, { role = "Claw", side = sx, rot = { 0, sx * -25, 0 } })
		r:part("Claw" .. sn, "Pincer", V(1.3, 1.0, 1.5), V(sx * 2.2, 1.7, -4.6), c.main2, c.mat)
		r:part("Claw" .. sn, "PincerA", V(0.45, 0.45, 1.3), V(sx * 2.45, 1.75, -5.8), c.main2, c.mat, { wedge = true, rot = { 0, 180, 0 } })
		r:part("Claw" .. sn, "PincerB", V(0.38, 0.38, 1.0), V(sx * 1.9, 1.7, -5.6), c.main2, c.mat, { wedge = true, rot = { 0, 180, 0 } })
		for i = 1, 3 do
			r:bone("Leg" .. sn .. i, "Body", V(sx * 1.2, 1.4, -1.3 + i * 0.9), V(2.4, 0.38, 0.38), V(sx * 2.1, 1.2, -1.3 + i * 0.9), c.main2, c.mat,
				{ role = "SpiderLeg", side = sx, index = i, rot = { 0, 0, sx * -25 } })
			r:part("Leg" .. sn .. i, "Foot", V(0.38, 1.3, 0.38), V(sx * 3.2, 0.65, -1.3 + i * 0.9), c.main2, c.mat)
		end
	end
	local P = { { 2.1, 2.3 }, { 3.0, 3.0 }, { 4.1, 3.3 }, { 5.2, 3.0 }, { 5.9, 2.1 }, { 6.0, 1.1 } }
	local prev, py, pz = "Body", 1.8, 1.8
	for i, p in ipairs(P) do
		local w = 1.15 - i * 0.08
		local name = "Tail" .. i
		r:bone(name, prev, V(0, (py + p[1]) / 2, (pz + p[2]) / 2), V(w, w, w), V(0, p[1], p[2]), (i % 2 == 0) and c.sec or c.main, c.mat,
			{ role = "Tail", index = i, axis = "X" })
		prev, py, pz = name, p[1], p[2]
	end
	r:part(prev, "Stinger", V(0.45, 0.45, 1.3), V(0, 5.5, 0.4), c.glow, M.Neon, { rot = { -40, 0, 0 } })
	r:part(prev, "StingerBulb", V(0.8, 0.8, 0.8), V(0, 5.9, 1.0), c.acc, c.mat)
end

-- TURTLE / SHELLED ----------------------------------------------
function ARCH.turtle(r, c, f)
	r:bone("Body", "Root", V(0, 2.1, 0), V(4.6, 1.4, 5.2), V(0, 2.1, 0), c.main, c.mat, { role = "Root" })
	r:part("Body", "ShellRim", V(5.0, 0.4, 5.6), V(0, 1.35, 0), c.sec, c.mat)
	r:part("Body", "Dome", V(3.8, 1.2, 4.3), V(0, 3.3, 0), c.main, c.mat)
	r:part("Body", "DomeTop", V(2.6, 0.6, 3.0), V(0, 4.2, 0), c.main2, c.mat)
	r:part("Body", "Plastron", V(3.8, 0.4, 4.4), V(0, 1.0, 0), c.sec, c.mat)
	for i = -1, 1 do
		r:part("Body", "Plate", V(1.1, 0.2, 1.1), V(0, 4.55, i * 1.0), c.acc, c.mat, { rot = { 0, 45, 0 } })
	end
	local hz = -3.3
	r:bone("Head", "Body", V(0, 1.8, -2.4), V(1.8, 1.55, 2.0), V(0, 2.1, hz), c.sec, c.mat, { role = "Neck" })
	r:part("Head", "Neck", V(1.2, 1.0, 1.2), V(0, 1.7, -2.6), c.sec, c.mat)
	eyes(r, "Head", c, 0.45, 2.35, hz - 1.0, 0.4)
	r:part("Head", "Mouth", V(0.8, 0.12, 0.1), V(0, 1.72, hz - 1.02), c.dark)
	for _, fb in ipairs({ "F", "B" }) do
		for _, S in ipairs(SIDES) do
			local sx, sn = S[1], S[2]
			local z = (fb == "F") and -1.8 or 1.8
			r:bone("Leg" .. fb .. sn, "Body", V(sx * 1.9, 1.3, z), V(1.35, 1.4, 1.35), V(sx * 1.95, 0.7, z), c.sec, c.mat, { role = "Leg", side = sx, front = (fb == "F") })
			r:part("Leg" .. fb .. sn, "Toe", V(1.1, 0.15, 0.1), V(sx * 1.95, 0.2, z - 0.72), c.dark)
		end
	end
	r:bone("Tail1", "Body", V(0, 1.3, 2.6), V(0.6, 0.5, 1.0), V(0, 1.1, 3.0), c.sec, c.mat, { role = "Tail", index = 1 })
	if f.tree then
		r:part("Body", "Trunk", V(0.8, 2.4, 0.8), V(0, 5.6, 0), rgb(110, 75, 45), M.Wood)
		cluster(r, "Body", "Leaves", 0, 7.3, 0, 1.2, c.acc, M.Grass)
		r:part("Body", "Mushroom", V(0.8, 0.3, 0.8), V(1.4, 4.0, 1.2), rgb(230, 70, 60))
	end
	if f.crystal then
		crystal(r, "Body", c, 0, 4.3, -0.3, 2.0, 0)
		crystal(r, "Body", c, 1.0, 3.7, 0.8, 1.3, -20)
		crystal(r, "Body", c, -1.0, 3.7, 0.6, 1.4, 20)
		crystal(r, "Body", c, 0.3, 3.8, 1.6, 1.0, 10)
	end
	if f.bands then
		for i = -2, 2 do
			r:part("Body", "Band", V(3.95, 0.3, 0.35), V(0, 3.95 - math.abs(i) * 0.15, i * 0.8), c.acc, c.mat)
		end
		r:part("Head", "SnoutLong", V(0.8, 0.7, 1.2), V(0, 1.85, hz - 1.4), c.sec, c.mat)
		r:sym("Head", "Ear", V(0.5, 0.7, 0.2), V(0.6, 3.0, hz + 0.4), c.sec, c.mat)
	end
end

-- ========================= MONSTER DATA =========================
local REGIONS = {
	{
		name = "Grassland",
		floor = { color = rgb(90, 170, 70), mat = M.Grass },
		monsters = {
			{ "Leaf Slime", "slime", pal({ main = rgb(90, 205, 95), sec = rgb(160, 255, 150), acc = rgb(60, 160, 60), acc2 = rgb(255, 150, 170), glow = rgb(130, 255, 130) }), { leaf = true } },
			{ "Bunnycorn", "quad", pal({ main = rgb(248, 248, 252), main2 = rgb(235, 232, 245), sec = rgb(255, 200, 220), acc = rgb(255, 140, 200), acc2 = rgb(255, 180, 210), glow = rgb(255, 170, 230) }), { bulk = 0.7, legH = 1.3, ears = "long", tail = "fluffy", horn = true, mane = true, headMul = 1.3, snout = 0.6 } },
			{ "Wood Turtle", "turtle", pal({ main = rgb(120, 85, 50), main2 = rgb(140, 100, 60), sec = rgb(140, 170, 90), acc = rgb(80, 150, 60), mat = M.Wood }), { tree = true } },
			{ "Flower Golem", "biped", pal({ main = rgb(125, 115, 95), main2 = rgb(105, 95, 80), sec = rgb(95, 145, 70), acc = rgb(255, 150, 200), acc2 = rgb(255, 245, 250), mat = M.Slate }), { flowers = true, moss = true } },
			{ "Beehive Beast", "biped", pal({ main = rgb(245, 190, 40), main2 = rgb(230, 170, 30), sec = rgb(45, 32, 22), acc = rgb(235, 245, 255), glow = rgb(255, 220, 60) }), { stripes = true, bulk = 1.1, legMul = 0.7, headMul = 1.15 } },
			{ "Moss Deer", "quad", pal({ main = rgb(125, 92, 62), sec = rgb(205, 185, 145), acc = rgb(95, 155, 70), acc2 = rgb(230, 190, 170) }), { legH = 2.6, bulk = 0.8, ears = "pointy", antlers = true, moss = true, tail = "nub", snout = 1.1 } },
			{ "Treant", "biped", pal({ main = rgb(105, 72, 45), main2 = rgb(85, 60, 38), sec = rgb(90, 65, 42), acc = rgb(70, 155, 60), glow = rgb(180, 255, 120), mat = M.Wood, glowEyes = true }), { canopy = true, armMul = 1.2, bulk = 1.1 } },
			{ "Verdant Griffin", "bird", pal({ main = rgb(80, 155, 80), main2 = rgb(70, 130, 65), sec = rgb(225, 235, 205), acc = rgb(235, 190, 60), glow = rgb(150, 255, 150) }), { griffin = true, crest = true } },
			{ "Solar Stag", "quad", pal({ main = rgb(242, 200, 85), main2 = rgb(225, 180, 70), sec = rgb(255, 240, 190), acc = rgb(255, 220, 90), acc2 = rgb(255, 200, 150), glow = rgb(255, 225, 110) }), { legH = 2.8, bulk = 0.9, antlers = true, antlerGlow = true, ears = "pointy", tail = "nub", snout = 1.1 } },
			{ "Gaia Titan", "biped", pal({ main = rgb(95, 75, 55), main2 = rgb(80, 62, 45), sec = rgb(65, 135, 60), acc = rgb(75, 175, 70), glow = rgb(110, 255, 130), mat = M.Slate, glowEyes = true }), { canopy = true, core = true, cracks = true, moss = true, bulk = 1.3 } },
		},
	},
	{
		name = "Desert",
		floor = { color = rgb(225, 190, 130), mat = M.Sand },
		monsters = {
			{ "Sand Slime", "slime", pal({ main = rgb(238, 205, 145), main2 = rgb(220, 185, 125), sec = rgb(255, 235, 185), acc2 = rgb(255, 170, 140), mat = M.Sand }), { sand = true, tr = 0 } },
			{ "Cactus Pup", "quad", pal({ main = rgb(85, 165, 75), sec = rgb(155, 210, 125), acc = rgb(255, 95, 145), acc2 = rgb(200, 240, 170) }), { bulk = 0.7, legH = 1.3, headMul = 1.25, ears = "pointy", tail = "thin", cactus = true, snout = 0.8 } },
			{ "Sand Fox", "quad", pal({ main = rgb(238, 160, 70), sec = rgb(255, 242, 225), acc = rgb(205, 110, 45), acc2 = rgb(255, 210, 180) }), { bulk = 0.75, legH = 1.8, ears = "big", tail = "bigfox", snout = 1.3 } },
			{ "Armadillo", "turtle", pal({ main = rgb(175, 135, 95), main2 = rgb(160, 120, 85), sec = rgb(145, 105, 75), acc = rgb(205, 165, 115) }), { bands = true } },
			{ "Scorpion", "scorpion", pal({ main = rgb(205, 55, 40), main2 = rgb(170, 40, 30), sec = rgb(150, 30, 25), acc = rgb(45, 22, 20), glow = rgb(255, 140, 50) }), {} },
			{ "Mummy", "biped", pal({ main = rgb(222, 208, 172), main2 = rgb(205, 190, 155), sec = rgb(185, 165, 125), glow = rgb(120, 255, 200), mat = M.Fabric, glowEyes = true }), { bandages = true, bulk = 0.9 } },
			{ "Anubis Hound", "quad", pal({ main = rgb(32, 32, 38), main2 = rgb(28, 28, 32), sec = rgb(60, 60, 72), acc = rgb(235, 185, 55), glow = rgb(255, 205, 70), glowEyes = true }), { legH = 2.6, bulk = 0.85, ears = "tall", collar = true, tail = "thin", snout = 1.4 } },
			{ "Sand Dragon", "dragon", pal({ main = rgb(212, 172, 102), main2 = rgb(190, 150, 85), sec = rgb(242, 218, 165), acc = rgb(165, 112, 62), glow = rgb(255, 205, 105), mat = M.Sandstone }), {} },
			{ "Pharaoh Golem", "biped", pal({ main = rgb(228, 188, 72), main2 = rgb(205, 165, 60), sec = rgb(40, 82, 175), acc = rgb(255, 215, 85), glow = rgb(80, 205, 255), mat = M.Sandstone, glowEyes = true }), { headdress = true, core = true, bulk = 1.15 } },
			{ "Sun Wyrm", "dragon", pal({ main = rgb(255, 125, 35), main2 = rgb(235, 95, 25), sec = rgb(255, 205, 70), acc = rgb(255, 240, 160), glow = rgb(255, 175, 45) }), { flames = true, glowWings = true, spikeGlow = true, bulk = 1.1 } },
		},
	},
	{
		name = "Ice",
		floor = { color = rgb(220, 240, 255), mat = M.Snow },
		monsters = {
			{ "Ice Slime", "slime", pal({ main = rgb(150, 212, 255), main2 = rgb(130, 195, 245), sec = rgb(225, 245, 255), acc2 = rgb(255, 190, 220), glow = rgb(175, 232, 255), mat = M.Glass }), { crystal = true, tr = 0.2 } },
			{ "Penguin", "biped", pal({ main = rgb(32, 38, 55), main2 = rgb(28, 32, 45), sec = rgb(245, 245, 250), acc = rgb(255, 165, 40) }), { penguin = true, bulk = 0.75, legMul = 0.25, armMul = 0.6, headMul = 1.15 } },
			{ "Ice Wolf", "quad", pal({ main = rgb(236, 246, 255), main2 = rgb(215, 232, 248), sec = rgb(175, 212, 242), acc = rgb(120, 200, 255), acc2 = rgb(170, 215, 245), glow = rgb(150, 222, 255) }), { legH = 2.2, bulk = 0.9, ears = "pointy", tail = "fluffy", crystals = true, snout = 1.3 } },
			{ "Frost Turtle", "turtle", pal({ main = rgb(92, 152, 212), main2 = rgb(120, 175, 225), sec = rgb(205, 232, 250), acc = rgb(165, 222, 255), glow = rgb(160, 225, 255), mat = M.Ice }), { crystal = true } },
			{ "Crystal Bear", "quad", pal({ main = rgb(175, 175, 232), main2 = rgb(155, 155, 215), sec = rgb(222, 222, 255), acc = rgb(200, 170, 255), glow = rgb(205, 175, 255) }), { bulk = 1.4, legH = 1.8, ears = "round", tail = "nub", crystals = true, snout = 0.9 } },
			{ "Snow Golem", "biped", pal({ main = rgb(242, 246, 255), main2 = rgb(222, 232, 248), sec = rgb(192, 216, 242), acc = rgb(120, 190, 255), glow = rgb(140, 212, 255), mat = M.Snow, glowEyes = true }), { bulk = 1.15, crystals = true, icicles = true } },
			{ "Ice Dragon", "dragon", pal({ main = rgb(122, 182, 242), main2 = rgb(100, 160, 225), sec = rgb(222, 242, 255), acc = rgb(182, 232, 255), glow = rgb(150, 232, 255), mat = M.Ice }), { crystals = true } },
			{ "Blizzard Phoenix", "bird", pal({ main = rgb(172, 202, 255), main2 = rgb(150, 182, 245), sec = rgb(232, 212, 255), acc = rgb(240, 245, 255), glow = rgb(192, 162, 255) }), { crest = true, glowWings = true, phoenix = true } },
			{ "Glacial Titan", "biped", pal({ main = rgb(102, 162, 222), main2 = rgb(85, 140, 200), sec = rgb(202, 232, 255), acc = rgb(160, 225, 255), glow = rgb(140, 222, 255), mat = M.Ice, glowEyes = true }), { bulk = 1.3, crystals = true, core = true, icicles = true } },
			{ "Frost Leviathan", "serpent", pal({ main = rgb(82, 142, 232), main2 = rgb(65, 120, 210), sec = rgb(202, 232, 255), acc = rgb(232, 162, 255), glow = rgb(162, 202, 255), mat = M.Ice }), { fins = true, crest = true, crystals = true } },
		},
	},
	{
		name = "Volcano",
		floor = { color = rgb(60, 40, 38), mat = M.Basalt },
		monsters = {
			{ "Magma Slime", "slime", pal({ main = rgb(62, 42, 40), main2 = rgb(80, 50, 45), sec = rgb(255, 110, 30), acc2 = rgb(255, 120, 60), glow = rgb(255, 125, 35), mat = M.Basalt }), { magma = true, tr = 0 } },
			{ "Lava Lizard", "quad", pal({ main = rgb(72, 42, 36), sec = rgb(255, 105, 35), acc = rgb(255, 150, 40), glow = rgb(255, 120, 35), mat = M.Basalt }), { bulk = 0.75, legH = 0.9, len = 1.3, tail = "long", snout = 1.4, lavaSpots = true, headMul = 0.9, headUp = -0.3, spikes = 5, spikeGlow = true } },
			{ "Fire Boar", "quad", pal({ main = rgb(152, 52, 32), main2 = rgb(125, 42, 26), sec = rgb(92, 32, 22), acc = rgb(255, 242, 222), acc2 = rgb(255, 140, 90), glow = rgb(255, 125, 35) }), { bulk = 1.1, legH = 1.6, ears = "pointy", tusks = true, spikes = 5, spikeGlow = true, tail = "nub", snout = 0.9 } },
			{ "Rock Rhino", "quad", pal({ main = rgb(72, 62, 62), main2 = rgb(60, 52, 52), sec = rgb(110, 95, 90), acc = rgb(125, 115, 105), glow = rgb(255, 115, 40), mat = M.Slate }), { bulk = 1.4, legH = 1.8, rhinoHorn = true, ears = "pointy", tail = "thin", lavaSpots = true } },
			{ "Flame Ape", "biped", pal({ main = rgb(62, 36, 30), main2 = rgb(80, 45, 35), sec = rgb(255, 112, 32), acc = rgb(255, 192, 62), glow = rgb(255, 125, 35), mat = M.Basalt, glowEyes = true }), { armMul = 1.45, legMul = 0.75, headMul = 0.95, flames = true, cracks = true } },
			{ "Lava Golem", "biped", pal({ main = rgb(52, 42, 42), main2 = rgb(65, 50, 48), sec = rgb(90, 60, 50), glow = rgb(255, 105, 25), mat = M.Basalt, glowEyes = true }), { bulk = 1.25, cracks = true, core = true } },
			{ "Inferno Wolf", "quad", pal({ main = rgb(62, 26, 22), main2 = rgb(50, 22, 18), sec = rgb(255, 82, 22), acc = rgb(255, 172, 42), acc2 = rgb(255, 120, 40), glow = rgb(255, 112, 25), glowEyes = true }), { legH = 2.2, ears = "pointy", tail = "flame", spikes = 6, spikeGlow = true, flames = true, snout = 1.3 } },
			{ "Magma Dragon", "dragon", pal({ main = rgb(82, 32, 26), main2 = rgb(65, 26, 22), sec = rgb(255, 112, 32), acc = rgb(42, 32, 32), glow = rgb(255, 120, 35), mat = M.Basalt }), { cracks = true, spikeGlow = true, flames = true } },
			{ "Molten Titan", "biped", pal({ main = rgb(46, 36, 36), main2 = rgb(58, 44, 42), sec = rgb(255, 142, 32), acc = rgb(70, 55, 50), glow = rgb(255, 142, 42), mat = M.Basalt, glowEyes = true }), { bulk = 1.35, cracks = true, core = true, horns = true } },
			{ "Fire Overlord", "biped", pal({ main = rgb(125, 22, 12), main2 = rgb(95, 18, 10), sec = rgb(255, 162, 42), acc = rgb(255, 222, 122), glow = rgb(255, 95, 22), mat = M.CrackedLava, glowEyes = true }), { bulk = 1.2, horns = true, wingsBig = true, flames = true, crown = true, cracks = true } },
		},
	},
	{
		name = "Void",
		floor = { color = rgb(40, 28, 62), mat = M.Slate },
		monsters = {
			{ "Shadow Slime", "slime", pal({ main = rgb(72, 42, 122), main2 = rgb(55, 32, 95), sec = rgb(172, 92, 255), acc2 = rgb(220, 140, 255), glow = rgb(192, 112, 255), mat = M.Glass }), { void = true, tr = 0.15 } },
			{ "Void Cat", "quad", pal({ main = rgb(36, 26, 56), main2 = rgb(48, 34, 72), sec = rgb(72, 52, 112), acc = rgb(202, 122, 255), acc2 = rgb(160, 90, 220), glow = rgb(202, 122, 255), glowEyes = true }), { bulk = 0.7, legH = 1.6, ears = "pointy", tail = "thin", headMul = 1.2, snout = 0.6, stars = true } },
			{ "Dark Deer", "quad", pal({ main = rgb(46, 36, 72), main2 = rgb(56, 44, 86), sec = rgb(92, 72, 142), acc = rgb(192, 112, 255), acc2 = rgb(140, 100, 200), glow = rgb(192, 112, 255), glowEyes = true }), { legH = 2.6, bulk = 0.8, antlers = true, antlerGlow = true, ears = "pointy", tail = "nub", snout = 1.1 } },
			{ "Void Spider", "spider", pal({ main = rgb(42, 32, 62), main2 = rgb(55, 40, 82), sec = rgb(92, 62, 142), acc = rgb(160, 120, 210), glow = rgb(202, 112, 255) }), {} },
			{ "Chaos Hound", "quad", pal({ main = rgb(36, 26, 56), main2 = rgb(30, 22, 48), sec = rgb(122, 62, 182), acc = rgb(222, 122, 255), glow = rgb(222, 122, 255), glowEyes = true }), { legH = 2.2, spikes = 6, spikeGlow = true, ears = "tall", tail = "thin", snout = 1.3 } },
			{ "Eclipse Raven", "bird", pal({ main = rgb(32, 26, 46), main2 = rgb(26, 22, 38), sec = rgb(72, 52, 112), acc = rgb(82, 62, 122), acc2 = rgb(60, 45, 90), glow = rgb(192, 112, 255), glowEyes = true }), { crest = true, glowWings = true } },
			{ "Abyss Golem", "biped", pal({ main = rgb(42, 32, 62), main2 = rgb(52, 38, 78), sec = rgb(82, 52, 132), glow = rgb(202, 102, 255), mat = M.Slate, glowEyes = true }), { bulk = 1.2, crystals = true, core = true, cracks = true } },
			{ "Void Dragon", "dragon", pal({ main = rgb(42, 26, 72), main2 = rgb(34, 22, 58), sec = rgb(112, 62, 182), acc = rgb(212, 132, 255), glow = rgb(212, 132, 255) }), { spikeGlow = true, crystals = true, glowWings = true } },
			{ "Celestial Serpent", "serpent", pal({ main = rgb(242, 242, 255), main2 = rgb(220, 220, 245), sec = rgb(192, 172, 255), acc = rgb(132, 202, 255), glow = rgb(172, 202, 255) }), { whiskers = true, stars = true, crest = true } },
			{ "Reality Titan", "biped", pal({ main = rgb(32, 22, 52), main2 = rgb(42, 28, 68), sec = rgb(152, 82, 232), acc = rgb(232, 182, 255), glow = rgb(192, 102, 255), mat = M.Slate, glowEyes = true }), { bulk = 1.35, horns = true, crystals = true, core = true, cracks = true, crown = true } },
		},
	},
}

local RIG_TYPE = { slime = "Slime", quad = "Quad", biped = "Biped", bird = "Bird", dragon = "Dragon", serpent = "Serpent", spider = "Spider", scorpion = "Scorpion", turtle = "Turtle" }

-- ========================= FX =========================
local function addFX(r, c, rarity, f)
	local rr = RARITY[rarity]
	local hot = f.flames or f.magma
	if rr.light <= 0 and not hot then return end
	local s = r.s
	local body = r.bones.Body or r.bones.LowerTorso or r.bones.Seg1
	local aura = Instance.new("Attachment")
	aura.Name = "AuraFX"
	aura.Parent = body
	if rr.light > 0 then
		local l = Instance.new("PointLight")
		l.Color = c.glow
		l.Brightness = rr.light
		l.Range = 12 * s
		l.Parent = aura
	end
	if rr.sparkle then
		local p = Instance.new("ParticleEmitter")
		p.Name = "RarityParticles"
		p.Color = ColorSequence.new(c.glow, rr.color)
		p.LightEmission = 1
		p.Rate = rr.sparkle
		p.Lifetime = NumberRange.new(1, 2)
		p.Speed = NumberRange.new(0.5, 1.5)
		p.SpreadAngle = Vector2.new(180, 180)
		p.Size = NumberSequence.new(0.35 * s, 0)
		p.Transparency = NumberSequence.new(0.1, 1)
		p.Parent = aura
	end
	if hot then
		local fire = Instance.new("Fire")
		fire.Color = c.glow
		fire.SecondaryColor = rgb(255, 230, 120)
		fire.Size = 3 * s
		fire.Heat = 4
		fire.Parent = aura
	end
end

-- ========================= BUILD =========================
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local function slug(name)
	return (string.gsub(name, "%s+", ""))
end

local function buildMonster(def, regionName, idx, stage, parent)
	local name, arch, c, f = def[1], def[2], def[3], def[4] or {}
	local rarity = RARITY_ORDER[idx]
	local s = stage.scale * RARITY[rarity].scale
	local model = Instance.new("Model")
	model.Name = stage.name
	local r = Rig.new(model, s)
	local builder = ARCH[arch]
	if not builder then error("Unknown archetype " .. tostring(arch) .. " for " .. name) end
	builder(r, c, f)
	addFX(r, c, rarity, f)
	model:SetAttribute("MonsterId", regionName .. "_" .. idx)
	model:SetAttribute("MonsterName", name)
	model:SetAttribute("Region", regionName)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Stage", stage.name)
	model:SetAttribute("RigType", RIG_TYPE[arch])
	model:SetAttribute("Scale", s)
	model:SetAttribute("AnimState", "Idle")
	CollectionService:AddTag(model, "Monster")
	model.Parent = parent
	return model, r, rarity
end

local function label(model, text, rarity, height)
	local g = Instance.new("BillboardGui")
	g.Name = "NameTag"
	g.Size = UDim2.new(0, 220, 0, 50)
	g.StudsOffset = Vector3.new(0, height, 0)
	g.AlwaysOnTop = true
	g.Adornee = model.PrimaryPart
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = text .. "\n" .. rarity
	t.TextColor3 = RARITY[rarity].color
	t.TextStrokeTransparency = 0
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Parent = g
	g.Parent = model.PrimaryPart
end


-- ========================= MODULE API =========================
local MonsterModels = {}

MonsterModels.Regions = REGIONS
MonsterModels.RarityOrder = RARITY_ORDER

local library = nil

-- الـ Templates موجودة جاهزة في الماب (ServerStorage.MonsterModels من assets/MonsterModels.rbxmx)
-- عشان الـ Animator يقدر يفتحها في Studio. لو مش موجودة، بنبنيها بالكود.
function MonsterModels.Build()
	if library then
		return library
	end
	local existing = ServerStorage:FindFirstChild("MonsterModels")
	if existing and existing:FindFirstChild(REGIONS[1].name) then
		library = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local lib = Instance.new("Folder")
	lib.Name = "MonsterModels"
	for _, region in ipairs(REGIONS) do
		local rf = Instance.new("Folder")
		rf.Name = region.name
		rf.Parent = lib
		for mi, def in ipairs(region.monsters) do
			local mf = Instance.new("Folder")
			mf.Name = string.format("%02d_%s", mi, slug(def[1]))
			mf.Parent = rf
			for _, stage in ipairs(STAGES) do
				buildMonster(def, region.name, mi, stage, mf)
			end
		end
		task.wait()
	end
	lib.Parent = ServerStorage
	library = lib
	return lib
end

-- regionIndex / monsterIndex بيبدأوا من 1، و stage = "Baby" | "Teen" | "Adult"
function MonsterModels.Get(regionIndex, monsterIndex, stage)
	local lib = library or MonsterModels.Build()
	local region = REGIONS[regionIndex]
	local def = region and region.monsters[monsterIndex]
	if not def then
		return nil
	end
	local folder = lib:FindFirstChild(region.name)
	local monster = folder and folder:FindFirstChild(string.format("%02d_%s", monsterIndex, slug(def[1])))
	local template = monster and monster:FindFirstChild(stage)
	return template and template:Clone() or nil
end

return MonsterModels
