--!strict
-- Egg Keeper: a man beside the Pumpkin Merchant who holds a Halloween egg. His "Talk" prompt opens the monster
-- store. The server owns everything: it accepts only the bundle sizes in Config.EggStore, opens a Robux Developer
-- Product prompt, and grants only inside the receipt callback: the eggs through MonsterService.AddEgg (the normal
-- hatch path rolls the monster, with Luck applied there) and the Luck timer in the player's saved data.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EggStoreMath = require(ReplicatedStorage.Shared.EggStoreMath)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local Build = require(script.Parent.Build)

local settings = Config.EggStore
local npc = settings.Npc
local TAG_KEEPER = "EggKeeper"

local EggStoreService = {}

local remotes: { [string]: RemoteEvent }
local keeperModel: Model? = nil
local lastRequest: { [Player]: number } = {}

local function storeOpen(): boolean
	local event = Config.Halloween
	return event.Enabled and (event.EndsAt == 0 or os.time() < event.EndsAt)
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < settings.Cooldown then
		return true
	end
	lastRequest[player] = now
	return false
end

-- Where he stands RIGHT NOW (he may have been moved in Studio): never the Config position.
local function keeperPart(): BasePart?
	local model = keeperModel
	if not model or not model:IsDescendantOf(workspace) then
		return nil
	end
	local part = model:FindFirstChild("Torso")
	return if part and part:IsA("BasePart") then part else nil
end

local function nearKeeper(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local keeper = keeperPart()
	if not root or not root:IsA("BasePart") or not keeper or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - keeper.Position).Magnitude <= npc.StoreDistance
end

local function storeState(player: Player): { [string]: any }
	local profile = DataService.Get(player)
	return { LuckLeft = if profile then EggStoreMath.LuckLeft(profile.Data.EggLuckUntil, os.time()) else 0 }
end

local function openStore(player: Player)
	if not storeOpen() or not nearKeeper(player) or rateLimited(player) then
		return
	end
	-- the store shows a real portrait of every monster the egg can hatch (built server-side, replicated to this player only)
	local request = (MonsterService :: any).RequestPortraits
	local egg = Config.Eggs[settings.Egg]
	if request and egg then
		local species: { string } = {}
		for name in egg.Weights do
			table.insert(species, name)
		end
		pcall(request, player, species)
	end
	remotes.OpenEggStore:FireClient(player, storeState(player))
end

-- Every purchase re-checks the whole situation on the server; the client's button state means nothing.
local function canShop(player: Player): boolean
	if not storeOpen() then
		MonsterService.Notify(player, "The Egg Keeper's store is closed.", "error")
		return false
	end
	if not nearKeeper(player) or not DataService.Get(player) then
		return false
	end
	return true
end

-- Robux purchases ------------------------------------------------------------------------------------------------
-- The remotes below only OPEN a Marketplace prompt after every check passes. Nothing is granted here: the eggs and
-- the Luck time are granted in EggStoreService.ProcessReceipt (called from the one MarketplaceService.ProcessReceipt).

local PROMPT_TIMEOUT = 120 -- seconds a prompt may stay "open" if Roblox never reports it finished
local pending: { [Player]: { ProductId: number, At: number } } = {}
local processing: { [string]: boolean } = {}

local function safeProfile(player: Player): DataService.Profile?
	local profile = DataService.Get(player)
	if not profile or profile.LoadFailed or profile.Closing or profile.CanSave == false then
		return nil
	end
	return profile
end

local function prompt(player: Player, productId: number)
	if productId <= 0 then
		-- Product not created in the Creator Dashboard yet: refuse BEFORE any prompt so nothing can be charged.
		MonsterService.Notify(player, "This item is not available yet. You were not charged.", "info")
		return
	end
	local open = pending[player]
	if open and os.clock() - open.At < PROMPT_TIMEOUT then
		MonsterService.Notify(player, "Finish the current purchase window first.", "info")
		return
	end
	pending[player] = { ProductId = productId, At = os.clock() }
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		pending[player] = nil
		MonsterService.Notify(player, "The purchase window could not open. You were not charged.", "error")
	end
end

local function buyBundle(player: Player, count: unknown)
	local bundle = EggStoreMath.FindBundle(count)
	if not bundle or rateLimited(player) or not canShop(player) then
		return
	end
	if not safeProfile(player) or not Config.Eggs[settings.Egg] then
		MonsterService.Notify(player, "Purchases are unavailable right now. You were not charged.", "error")
		return
	end
	prompt(player, EggStoreMath.BundleProductId(bundle))
end

local function buyLuck(player: Player)
	if rateLimited(player) or not canShop(player) then
		return
	end
	local profile = safeProfile(player)
	if not profile then
		MonsterService.Notify(player, "Purchases are unavailable right now. You were not charged.", "error")
		return
	end
	-- Refuse at the cap BEFORE prompting: Robux must never be taken for nothing.
	if not EggStoreMath.ExtendLuck(profile.Data.EggLuckUntil, os.time()) then
		MonsterService.Notify(player, "Your Luck is already at the maximum time!", "error")
		return
	end
	prompt(player, EggStoreMath.LuckProductId())
end

-- True when the receipt is one of this store's products (so MonetizationService routes it here).
function EggStoreService.IsStoreProduct(productId: unknown): boolean
	return (EggStoreMath.ProductFor(productId)) ~= nil
end

-- Grants a paid receipt exactly once. true = PurchaseGranted (saved), false = NotProcessedYet (Roblox retries).
function EggStoreService.ProcessReceipt(player: Player, receipt: any): boolean
	local kind, bundle = EggStoreMath.ProductFor(receipt.ProductId)
	local profile = safeProfile(player)
	local id = receipt.PurchaseId
	if not kind or not profile or type(id) ~= "string" or #id == 0 or processing[id] then
		return false
	end
	processing[id] = true
	local ok, saved = pcall(function(): boolean
		if profile.Data.ProcessedReceipts[id] ~= true then
			if kind == "Bundle" and bundle then
				local eggType = settings.Egg
				if not Config.Eggs[eggType] then return false end
				local granted = 0
				for _ = 1, bundle.Count do
					if MonsterService.AddEgg(player, eggType, true) then granted += 1 else break end
				end
				if granted == 0 then return false end
				-- AddEgg only fails without a profile; a partial grant is recorded as done so a retry cannot duplicate eggs.
				profile.Data.ProcessedReceipts[id] = true
				MonsterService.Notify(player, string.format("🥚 %d x %s added! Eggs without a free slot wait in your Pets menu.", granted, Config.Eggs[eggType].DisplayName), "success")
			else
				local now = os.time()
				local extended = EggStoreMath.ExtendLuck(profile.Data.EggLuckUntil, now)
				-- Prompts are refused at the cap, so this only clamps a rare race; it is never stacked past the cap.
				local newUntil = extended or (now + settings.Luck.MaxSeconds)
				profile.Data.EggLuckUntil = math.max(profile.Data.EggLuckUntil, math.min(newUntil, now + settings.Luck.MaxSeconds))
				profile.Data.ProcessedReceipts[id] = true
				MonsterService.Notify(player, string.format("🍀 Luck x%d active for %d minutes!", settings.Luck.Multiplier, math.ceil((profile.Data.EggLuckUntil - now) / 60)), "success")
			end
		end
		return DataService.Save(player) == true
	end)
	processing[id] = nil
	if not ok or not saved or safeProfile(player) ~= profile then
		return false
	end
	pending[player] = nil
	MonsterService.PushState(player)
	if remotes and remotes.EggStoreState then
		remotes.EggStoreState:FireClient(player, storeState(player))
	end
	return true
end

-- The man ----------------------------------------------------------------------------------------------

-- A friendly Halloween wizard: robe with a flared skirt, flowing cape, a tall bent pointed hat, a big white beard
-- and a jack-o'-lantern on his belt, cradling a big floating pumpkin-face egg. Everything is plain anchored parts
-- built from one origin, so the model can be moved in Studio and the idle animation follows it.
local PURPLE_DARK = Color3.fromRGB(46, 24, 82)
local PURPLE = Color3.fromRGB(94, 48, 150)
local PURPLE_LIGHT = Color3.fromRGB(150, 92, 214)
local ORANGE = Color3.fromRGB(255, 122, 24)
local ORANGE_DARK = Color3.fromRGB(196, 78, 10)
local GOLD = Color3.fromRGB(255, 200, 60)
local SKIN = Color3.fromRGB(245, 206, 160)
local BONE = Color3.fromRGB(246, 242, 232)
local FACE_GLOW = Color3.fromRGB(255, 226, 96)

local function buildKeeper(): Model
	local model = Instance.new("Model")
	model.Name = "EggKeeper"
	local origin = CFrame.lookAt(npc.Position + Vector3.new(0, 0.2, 0), Vector3.new(npc.FaceTowards.X, npc.Position.Y + 0.2, npc.FaceTowards.Z))
	local animated: { { Part: BasePart, Group: string } } = {}

	-- cf is relative to the keeper's origin (feet on the ground, he faces -Z).
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, group: string?): Part
		local part = Build.MakePart({
			Name = name, Size = size, CFrame = origin * cf, Color = color,
			Material = material or Enum.Material.Fabric, Shape = shape or Enum.PartType.Block,
			CanCollide = false, CanQuery = true, CanTouch = false, Parent = model,
		})
		if group then
			table.insert(animated, { Part = part, Group = group })
		end
		return part
	end
	-- a vertical disc/cylinder (the cylinder axis is X, so it is turned to stand up)
	local function disc(name: string, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material?, group: string?): Part
		return piece(name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder, group)
	end
	local function ball(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?, group: string?): Part
		local part = piece(name, size, CFrame.new(center), color, material or Enum.Material.SmoothPlastic, Enum.PartType.Block, group)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		return part
	end
	-- a block laid along a line from a to b (arms)
	local function segment(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): Part
		local length = (b - a).Magnitude
		return piece(name, Vector3.new(thickness, thickness, length), CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2), color, material)
	end

	-- boots and legs (the robe hides most of them)
	for _, side in { -1, 1 } do
		piece("Leg", Vector3.new(0.9, 1.8, 0.9), CFrame.new(side * 0.5, 1.1, 0), Color3.fromRGB(36, 24, 52))
		piece("Boot", Vector3.new(1, 0.7, 1.6), CFrame.new(side * 0.5, 0.35, -0.3), Color3.fromRGB(58, 36, 26), Enum.Material.Leather)
		piece("BootToe", Vector3.new(0.9, 0.5, 0.5), CFrame.new(side * 0.5, 0.4, -1.15), Color3.fromRGB(70, 44, 30), Enum.Material.Leather)
		piece("BootBuckle", Vector3.new(0.7, 0.2, 0.12), CFrame.new(side * 0.5, 0.62, -0.78), GOLD, Enum.Material.Metal)
	end

	-- robe: flared skirt, torso, belt, collar
	disc("RobeHem", 3.5, 0.5, Vector3.new(0, 0.95, 0), PURPLE_DARK)
	disc("RobeHemTrim", 3.6, 0.22, Vector3.new(0, 0.75, 0), ORANGE)
	disc("RobeSkirt", 3.0, 0.9, Vector3.new(0, 1.55, 0), PURPLE)
	disc("RobeWaist", 2.6, 0.7, Vector3.new(0, 2.25, 0), PURPLE)
	local torso = piece("Torso", Vector3.new(2.1, 2, 1.2), CFrame.new(0, 3.1, 0), PURPLE)
	piece("Sash", Vector3.new(2.2, 0.4, 1.3), CFrame.new(0, 2.35, 0), ORANGE)
	piece("SashBuckle", Vector3.new(0.6, 0.6, 0.15), CFrame.new(0, 2.35, -0.68), GOLD, Enum.Material.Metal)
	piece("Placket", Vector3.new(0.35, 1.6, 0.12), CFrame.new(0, 3.3, -0.62), ORANGE)
	for index, y in { 3.75, 3.3, 2.85 } do
		ball("Button" .. index, Vector3.new(0.28, 0.28, 0.2), Vector3.new(0, y, -0.7), GOLD, Enum.Material.Metal)
	end
	disc("Collar", 2.9, 0.4, Vector3.new(0, 4.05, 0), PURPLE_DARK)
	disc("CollarTrim", 3.0, 0.14, Vector3.new(0, 3.9, 0), ORANGE)

	-- cape hanging behind him (inside lining is orange)
	piece("Cape", Vector3.new(2.7, 3.7, 0.18), CFrame.new(0, 2.55, 0.85) * CFrame.Angles(math.rad(7), 0, 0), PURPLE_DARK, nil, nil, "Cape")
	piece("CapeLining", Vector3.new(2.5, 3.5, 0.1), CFrame.new(0, 2.55, 0.74) * CFrame.Angles(math.rad(7), 0, 0), ORANGE_DARK, nil, nil, "Cape")
	piece("CapeClaspL", Vector3.new(0.4, 0.4, 0.2), CFrame.new(-1.0, 4.0, 0.62), GOLD, Enum.Material.Metal)
	piece("CapeClaspR", Vector3.new(0.4, 0.4, 0.2), CFrame.new(1.0, 4.0, 0.62), GOLD, Enum.Material.Metal)

	-- arms reaching forward to cradle the egg, with sleeves, orange cuffs and hands
	for _, side in { -1, 1 } do
		local shoulder = Vector3.new(side * 1.45, 3.85, 0)
		local wrist = Vector3.new(side * 1.5, 3.0, -1.55)
		ball("Shoulder", Vector3.new(1.25, 1.25, 1.25), shoulder, PURPLE_LIGHT, Enum.Material.Fabric)
		segment("Sleeve", shoulder, wrist, 1.05, PURPLE)
		local hand = Vector3.new(side * 1.5, 2.9, -1.95)
		segment("Cuff", wrist:Lerp(hand, 0.25) + Vector3.new(0, 0, 0.05), wrist + Vector3.new(0, -0.05, -0.1), 1.2, ORANGE)
		ball("Hand", Vector3.new(0.75, 0.75, 0.75), hand, SKIN)
	end

	-- head, face, beard
	local head = piece("Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.8, 0), SKIN, Enum.Material.SmoothPlastic, nil, "Head")
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.3, 1.3, 1.3)
	headMesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	ball("Beard", Vector3.new(1.55, 1.5, 0.95), Vector3.new(0, 3.9, -0.42), BONE, Enum.Material.Fabric, "Head")
	ball("BeardTip", Vector3.new(0.95, 1.3, 0.7), Vector3.new(0, 3.35, -0.5), BONE, Enum.Material.Fabric, "Head")
	ball("Mustache", Vector3.new(1.25, 0.34, 0.5), Vector3.new(0, 4.68, -0.62), BONE, Enum.Material.Fabric, "Head")
	ball("BrowL", Vector3.new(0.55, 0.2, 0.25), Vector3.new(-0.33, 5.2, -0.66), BONE, Enum.Material.Fabric, "Head")
	ball("BrowR", Vector3.new(0.55, 0.2, 0.25), Vector3.new(0.33, 5.2, -0.66), BONE, Enum.Material.Fabric, "Head")

	-- tall pointed hat with an orange band, gold buckle and a bent tip
	disc("HatBrim", 3.7, 0.2, Vector3.new(0, 5.42, 0), PURPLE_DARK, nil, "Head")
	disc("HatBrimTrim", 3.78, 0.1, Vector3.new(0, 5.34, 0), ORANGE, nil, "Head")
	for index = 0, 7 do
		local diameter = 2.3 - index * 0.2
		disc("Hat" .. (index + 1), diameter, 0.5, Vector3.new(0.016 * index * index, 5.7 + index * 0.36, 0), PURPLE, nil, "Head")
	end
	ball("HatTip", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0.016 * 49 + 0.05, 8.4, 0), PURPLE_LIGHT, nil, "Head")
	disc("HatBand", 2.4, 0.4, Vector3.new(0, 5.68, 0), ORANGE, nil, "Head")
	piece("HatBuckle", Vector3.new(0.6, 0.45, 0.14), CFrame.new(0, 5.68, -1.18), GOLD, Enum.Material.Metal, nil, "Head")
	piece("HatBuckleHole", Vector3.new(0.3, 0.22, 0.16), CFrame.new(0, 5.68, -1.19), ORANGE_DARK, nil, nil, "Head")

	-- a little jack-o'-lantern on his belt
	local lantern = ball("BeltPumpkin", Vector3.new(0.95, 0.8, 0.95), Vector3.new(-1.35, 2.2, -0.75), ORANGE)
	piece("BeltPumpkinStem", Vector3.new(0.14, 0.26, 0.14), CFrame.new(-1.35, 2.68, -0.75), Color3.fromRGB(70, 130, 40), Enum.Material.Wood)
	for _, side in { -1, 1 } do
		piece("BeltPumpkinEye", Vector3.new(0.14, 0.16, 0.08), CFrame.new(-1.35 + side * 0.2, 2.28, -1.2), FACE_GLOW, Enum.Material.Neon)
	end
	piece("BeltPumpkinMouth", Vector3.new(0.4, 0.1, 0.08), CFrame.new(-1.35, 2.06, -1.2), FACE_GLOW, Enum.Material.Neon)
	local lanternLight = Instance.new("PointLight")
	lanternLight.Color, lanternLight.Range, lanternLight.Brightness = ORANGE, 8, 1
	lanternLight.Parent = lantern

	-- magic circle under his feet
	disc("MagicCircle", 7.4, 0.12, Vector3.new(0, 0.06, 0), Color3.fromRGB(40, 18, 70), Enum.Material.SmoothPlastic)
	disc("MagicRingOuter", 7.2, 0.14, Vector3.new(0, 0.07, 0), ORANGE, Enum.Material.Neon)
	disc("MagicRingInner", 6.7, 0.16, Vector3.new(0, 0.08, 0), Color3.fromRGB(40, 18, 70), Enum.Material.SmoothPlastic)
	disc("MagicRingCore", 4.4, 0.18, Vector3.new(0, 0.09, 0), PURPLE_LIGHT, Enum.Material.Neon)
	disc("MagicCore", 4.1, 0.2, Vector3.new(0, 0.1, 0), Color3.fromRGB(40, 18, 70), Enum.Material.SmoothPlastic)

	-- The Halloween egg: a big orange ellipsoid with purple bands and spots and a glowing carved face.
	local ex, ey, ez = 1.45, 1.95, 1.45 -- radii
	local eggCenter = Vector3.new(0, 3.55, -2.55)
	local egg = ball("HalloweenEgg", Vector3.new(ex * 2, ey * 2, ez * 2), eggCenter, ORANGE, Enum.Material.SmoothPlastic, "Egg")
	local function frontZ(x: number, y: number): number -- the egg's front surface at a face-plane point
		return eggCenter.Z - ez * math.sqrt(math.max(0, 1 - (x / ex) ^ 2 - (y / ey) ^ 2))
	end
	for index, height in { 1.2, -1.15 } do
		local across = 2 * ex * math.sqrt(1 - (height / ey) ^ 2) + 0.12
		disc("EggBand" .. index, across, 0.3, eggCenter + Vector3.new(0, height, 0), PURPLE, Enum.Material.SmoothPlastic, "Egg")
	end
	for index, dir in { Vector3.new(-0.8, 0.28, -0.52), Vector3.new(0.82, -0.2, -0.5), Vector3.new(-0.55, -0.62, -0.5), Vector3.new(0.6, 0.58, -0.52), Vector3.new(-0.2, 0.1, 0.95), Vector3.new(0.9, 0.2, 0.4) } do
		local unit = dir.Unit
		ball("EggSpot" .. index, Vector3.new(0.5, 0.5, 0.3), eggCenter + Vector3.new(unit.X * ex, unit.Y * ey, unit.Z * ez), PURPLE, Enum.Material.SmoothPlastic, "Egg")
	end
	-- carved face: two angry triangle eyes and a toothy grin, glowing from inside
	for _, side in { -1, 1 } do
		local x, y = side * 0.5, 0.55
		local z = frontZ(x, y) + 0.03
		local eye = piece("EggEye", Vector3.new(0.12, 0.46, 0.5), CFrame.new(eggCenter.X + x, eggCenter.Y + y, z) * CFrame.Angles(0, if side < 0 then math.pi / 2 else -math.pi / 2, 0), FACE_GLOW, Enum.Material.Neon, Enum.PartType.Wedge, "Egg")
		eye.CanQuery = false
	end
	local nose = piece("EggNose", Vector3.new(0.12, 0.28, 0.3), CFrame.new(eggCenter.X, eggCenter.Y + 0.05, frontZ(0, 0.05) + 0.03) * CFrame.Angles(0, math.pi / 2, 0), FACE_GLOW, Enum.Material.Neon, Enum.PartType.Wedge, "Egg")
	nose.CanQuery = false
	for index, x in { -0.72, -0.36, 0, 0.36, 0.72 } do
		local y = -0.75 + 0.3 * (x / 0.72) ^ 2 + (if index % 2 == 0 then -0.1 else 0)
		piece("EggTooth" .. index, Vector3.new(0.3, 0.3, 0.12), CFrame.new(eggCenter.X + x, eggCenter.Y + y, frontZ(x, y) + 0.04), FACE_GLOW, Enum.Material.Neon, nil, "Egg")
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 20
	light.Brightness = 2
	light.Parent = egg
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "EggAura"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 170, 50), Color3.fromRGB(190, 110, 255))
	sparkles.LightEmission = 0.9
	sparkles.Size = NumberSequence.new(0.4, 0)
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Rate = 10
	sparkles.Speed = NumberRange.new(0.6, 1.8)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = egg

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = ""
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = torso
	CollectionService:AddTag(model, TAG_KEEPER)
	model.Parent = workspace

	-- Billboard in the same style as the Pumpkin Merchant's.
	local gui, label = Build.MakeBillboard(head, UDim2.fromOffset(240, 60), Vector3.new(0, 4.6, 0), 90)
	gui.AlwaysOnTop = false
	label.Text = '<font color="#FFA030">' .. npc.Name .. '</font>\n🎃 Halloween Eggs!'

	-- Idle loop: the egg floats and turns, the cape sways, the head and hat tilt. Skipped where there is no RunService.
	pcall(function()
		local RunService = game:GetService("RunService")
		local relative: { CFrame }? = nil
		local clockTime, accumulator = 0, 0
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not model.Parent then
				connection:Disconnect()
				return
			end
			clockTime += dt
			accumulator += dt
			if accumulator < 1 / 20 then
				return
			end
			accumulator = 0
			local base = torso.CFrame
			if not relative then
				local list = {}
				for index, entry in animated do
					list[index] = base:ToObjectSpace(entry.Part.CFrame)
				end
				relative = list
			end
			local bob = math.sin(clockTime * 1.7) * 0.28
			local turn = math.sin(clockTime * 0.8) * 0.2
			local sway = math.sin(clockTime * 1.1) * 0.05
			local tilt = math.sin(clockTime * 0.9) * 0.03
			local eggPivot = CFrame.new(eggCenter - Vector3.new(0, 3.1, 0)) -- egg centre in torso space
			for index, entry in animated do
				local rel = (relative :: { CFrame })[index]
				if entry.Group == "Egg" then
					entry.Part.CFrame = base * CFrame.new(0, bob, 0) * eggPivot * CFrame.Angles(0, turn, 0) * eggPivot:Inverse() * rel
				elseif entry.Group == "Cape" then
					local hinge = CFrame.new(0, 0.9, 0.8)
					entry.Part.CFrame = base * hinge * CFrame.Angles(sway * 2, 0, 0) * hinge:Inverse() * rel
				elseif entry.Group == "Head" then
					local neck = CFrame.new(0, 0.9, 0)
					entry.Part.CFrame = base * neck * CFrame.Angles(tilt, math.sin(clockTime * 0.6) * 0.05, tilt * 1.5) * neck:Inverse() * rel
				end
			end
		end)
	end)
	return model
end

-- Adopt a Studio-authored keeper (tagged "EggKeeper") untouched; build the default only when none exists.
local function adoptKeeper()
	local model: Model? = nil
	for _, tagged in CollectionService:GetTagged(TAG_KEEPER) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(workspace) then
			model = tagged
			break
		end
	end
	keeperModel = model or buildKeeper()
	local part = keeperPart()
	if not part then
		warn("[EggStoreService] the Egg Keeper has no Torso part")
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Build.MakePrompt(part, "EggKeeperPrompt", "Talk", Enum.KeyCode.E, 0)
		prompt.ObjectText = npc.Name
		prompt.MaxActivationDistance = npc.PromptDistance
	end
	prompt.Enabled = true
	prompt.Triggered:Connect(openStore)
end

-- Hatch hook: the weights to roll with. Luck only re-weights the eggs in Config.EggStore.Luck.Eggs while it lasts.
function EggStoreService.AdjustHatchWeights(player: Player, eggType: string, weights: { [string]: number }): { [string]: number }
	local profile = DataService.Get(player)
	if profile and EggStoreMath.AppliesLuck(eggType) and EggStoreMath.LuckLeft(profile.Data.EggLuckUntil, os.time()) > 0 then
		return EggStoreMath.LuckWeights(weights, true)
	end
	return weights
end

function EggStoreService.Init(remoteEvents: { [string]: RemoteEvent })
	remotes = remoteEvents
	if storeOpen() then
		local built, failure = pcall(adoptKeeper)
		if not built then
			warn("[EggStoreService] could not set up the Egg Keeper:", failure)
		end
	end
	remotes.BuyEggBundle.OnServerEvent:Connect(buyBundle)
	remotes.BuyEggLuck.OnServerEvent:Connect(buyLuck)
	pcall(function()
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number)
			local player = Players:GetPlayerByUserId(userId)
			local open = player and pending[player]
			if player and open and open.ProductId == productId then
				pending[player] = nil
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		pending[player] = nil
	end)
end

return EggStoreService
