--!strict
-- اختيار المرافقين والضرر في السيرفر؛ المجسمات للعرض فقط ومش بتنتج دخل إضافي.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local MonsterModels = require(script.Parent.MonsterModels)
local PlotService = require(script.Parent.PlotService)

type Monster = MonsterMath.MonsterData
type Visual = { Model: Model, Species: string, GroundOffset: Vector3, Current: CFrame?, LastClock: number?, Moving: boolean? }
-- Follow motion: followers glide toward their slot (each one a little slower than the one in front, so the
-- group trails the player naturally) instead of snapping, and play the Walk animation only while really moving.
local FOLLOW_SHARPNESS = 7 -- higher = tighter follow
local FOLLOW_STAGGER = 0.7 -- each extra follower reacts this much slower
local FOLLOW_MIN_SHARPNESS = 3
local FOLLOW_TELEPORT_DISTANCE = 30 -- farther than this (respawn, zone travel) = snap, no gliding
local WALK_ON_SPEED, WALK_OFF_SPEED = 1.6, 0.6 -- studs/second, with hysteresis so the animation doesn't flicker
local FollowerService = {}
local equipped: { [Player]: { string } } = {}
local visuals: { [Player]: { [string]: Visual } } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local folder: Folder? = nil
local started = false
local isCarried: (Player, string) -> boolean = function() return false end
local changed: (Player) -> () = function() end

function FollowerService.GetMinLevel(): number
	local minimum = Config.Followers.MinLevel
	for _, stage in Config.Stages do
		if stage.Name == "Adult" then minimum = math.max(minimum, stage.MinLevel); break end
	end
	return minimum
end

function FollowerService.IsEligible(player: Player, monster: Monster?): boolean
	return monster ~= nil and Config.Species[monster.Species] ~= nil
		and monster.Level >= FollowerService.GetMinLevel() and not isCarried(player, monster.Id)
end

local function removeVisual(player: Player, id: string)
	local list = visuals[player]
	local visual = list and list[id]
	if visual then visual.Model:Destroy(); list[id] = nil end
end

-- The chosen followers are stored in the profile (Data.Followers), so they survive death, respawn and rejoining.
local function persist(player: Player, ids: { string })
	local profile = DataService.Get(player)
	if profile then
		profile.Data.Followers = table.clone(ids)
	end
end

function FollowerService.GetIds(player: Player): { string }
	local profile = DataService.Get(player)
	if equipped[player] == nil and profile then
		equipped[player] = table.clone(profile.Data.Followers or {})
	end
	local valid: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in equipped[player] or {} do
		local monster = profile and profile.Data.Monsters[id]
		if #valid < Config.Followers.MaxCount and not seen[id] and monster and monster.Id == id and FollowerService.IsEligible(player, monster) then
			table.insert(valid, id)
			seen[id] = true
		else
			removeVisual(player, id)
		end
	end
	local stored = equipped[player] or {}
	equipped[player] = valid
	if #valid ~= #stored then
		persist(player, valid)
	end
	return table.clone(valid)
end

function FollowerService.Remove(player: Player, id: string)
	local ids = equipped[player]
	local index = ids and table.find(ids, id)
	if ids and index then
		table.remove(ids, index)
		persist(player, ids)
	end
	removeVisual(player, id)
end

-- Dying or respawning hides the followers; the selection itself is kept and they come back with the character.
function FollowerService.Hide(player: Player)
	for id in visuals[player] or {} do removeVisual(player, id) end
	visuals[player] = nil
end

-- Leaving the game: drop the session cache (the profile keeps the selection).
function FollowerService.Clear(player: Player)
	FollowerService.Hide(player)
	equipped[player] = nil
end

function FollowerService.Toggle(player: Player, id: unknown): (boolean, string)
	if type(id) ~= "string" or #id == 0 or #id > 128 then return false, "Invalid monster." end
	local profile = DataService.Get(player)
	local monster = profile and profile.Data.Monsters[id]
	if not monster or monster.Id ~= id then return false, "You do not own this monster." end
	local ids = FollowerService.GetIds(player)
	if table.find(ids, id) then
		FollowerService.Remove(player, id)
		return true, "Monster stopped following."
	end
	if not FollowerService.IsEligible(player, monster) then
		return false, string.format("Only available adult monsters (Lv %d+) can follow.", FollowerService.GetMinLevel())
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false, "Respawn before choosing followers." end
	if #ids >= Config.Followers.MaxCount then return false, string.format("You can have up to %d followers.", Config.Followers.MaxCount) end
	table.insert(ids, id)
	equipped[player] = ids
	persist(player, ids)
	return true, "Monster is now following you!"
end

-- Auto Place: بيستبدل الـ followers بأول وحوش مؤهلة في الترتيب (الأعلى دخلاً)، لحد MaxCount. بيرجّع عددهم.
function FollowerService.SetBest(player: Player, ranked: { Monster }): number
	local ids: { string } = {}
	for _, monster in ranked do
		if #ids >= Config.Followers.MaxCount then break end
		if FollowerService.IsEligible(player, monster) and not table.find(ids, monster.Id) then
			table.insert(ids, monster.Id)
		end
	end
	for _, id in FollowerService.GetIds(player) do
		if not table.find(ids, id) then removeVisual(player, id) end
	end
	equipped[player] = ids
	persist(player, ids)
	return #ids
end

function FollowerService.GetDamageBonus(player: Player): number
	local ids = FollowerService.GetIds(player)
	local profile = DataService.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid or humanoid.Health <= 0 then return 0 end
	local total = 0
	for _, id in ids do
		local monster = profile.Data.Monsters[id]
		local species = Config.Species[monster.Species]
		local base = Config.Followers.DamagePerRarity[species.Rarity] or 0
		local levelBonus = math.min(Config.Followers.MaxLevelBonus, math.max(0, monster.Level - FollowerService.GetMinLevel()) * Config.Followers.LevelBonusPerLevel)
		total += base * (1 + levelBonus)
	end
	return math.floor(total)
end

-- الموديلات القديمة ليها رجلين ملحومة؛ نوصلها بالمحرك الموجود عشان تمشي هي كمان.
local function rigLegacyVisual(model: Model)
	local body = model.PrimaryPart :: BasePart
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = body.Size
	root.CFrame = body.CFrame
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "Root"
	rootJoint.Part0 = root
	rootJoint.Part1 = body
	rootJoint:SetAttribute("Role", "Root")
	rootJoint.Parent = root
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "Foot" or part.Name == "Wing") then
			for _, joint in part:GetChildren() do
				if joint:IsA("WeldConstraint") then joint:Destroy() end
			end
			local motor = Instance.new("Motor6D")
			motor.Name = part.Name
			motor.Part0 = body
			motor.Part1 = part
			local hinge = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
			motor.C0 = body.CFrame:ToObjectSpace(hinge)
			motor.C1 = part.CFrame:ToObjectSpace(hinge)
			motor:SetAttribute("Role", if part.Name == "Foot" then "Leg" else "Wing")
			motor:SetAttribute("Side", if body.CFrame:PointToObjectSpace(part.CFrame.Position).X >= 0 then 1 else -1)
			motor.Parent = body
		end
	end
	local controller = Instance.new("AnimationController")
	Instance.new("Animator").Parent = controller
	controller.Parent = model
	model:SetAttribute("RigType", "Biped")
	CollectionService:AddTag(model, "Monster")
end

local function createVisual(player: Player, monster: Monster): Visual?
	local species = Config.Species[monster.Species]
	local info = species and species.Model
	if not species or not folder then return nil end
	local model = if info then MonsterModels.Get(info.Region, info.Index, "Adult") else PlotService.BuildMonsterModel(monster)
	if not model or not model.PrimaryPart then if model then model:Destroy() end; return nil end
	if not info then rigLegacyVisual(model) end
	model.Name = monster.Id
	model:SetAttribute("FollowerOwner", player.UserId)
	model:SetAttribute("FollowerId", monster.Id)
	model:SetAttribute("AnimState", "Idle")
	-- حتى أكبر Rig يفضل جوه خانته، والـ Pivot يتظبط من الحدود الفعلية.
	local _, size = model:GetBoundingBox()
	local scale = math.min(Config.Followers.ModelScale,
		(Config.Followers.Spacing - Config.Followers.VisualPadding) / size.X,
		(Config.Followers.RowDistance - Config.Followers.VisualPadding) / size.Z)
	model:ScaleTo(model:GetScale() * scale)
	model:SetAttribute("Scale", (model:GetAttribute("Scale") or 1) * scale)
	local bounds, scaledSize = model:GetBoundingBox()
	local center = model:GetPivot():PointToObjectSpace(bounds.Position)
	local groundOffset = Vector3.new(-center.X, scaledSize.Y / 2 - center.Y, -center.Z)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = child == model.PrimaryPart
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.Massless = true
		elseif child:IsA("ProximityPrompt") or child:IsA("ClickDetector") or child:IsA("LuaSourceContainer") or child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then model:PivotTo(root.CFrame * CFrame.new(0, 0, Config.Followers.RowDistance)) end
	model.Parent = folder
	return { Model = model, Species = monster.Species, GroundOffset = groundOffset }
end

local function updateVisuals(player: Player, rayParams: RaycastParams)
	local ids = FollowerService.GetIds(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		for id in visuals[player] or {} do removeVisual(player, id) end
		return
	end
	local profile = DataService.Get(player)
	if not profile then return end
	local list = visuals[player] or {}
	visuals[player] = list
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) else flatLook = flatLook.Unit end
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	for index, id in ids do
		local monster = profile.Data.Monsters[id]
		local visual = list[id]
		if visual and (visual.Species ~= monster.Species or not visual.Model.Parent) then removeVisual(player, id); visual = nil end
		if not visual then visual = createVisual(player, monster); list[id] = visual end
		if not visual then continue end
		local row = math.floor((index - 1) / 3)
		local rowCount = math.min(3, #ids - row * 3)
		local column = (index - 1) % 3 - (rowCount - 1) / 2
		local position = root.Position + right * column * Config.Followers.Spacing - flatLook * (row + 1) * Config.Followers.RowDistance
		local hit = workspace:Raycast(position + Vector3.new(0, 24, 0), Vector3.new(0, -120, 0), rayParams)
		local ground = if hit then hit.Position.Y else root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		position = Vector3.new(position.X, ground, position.Z)
		local target = CFrame.lookAt(position, position + flatLook) * CFrame.new(visual.GroundOffset)
		local model = visual.Model
		local now = os.clock()
		local previous = visual.Current
		local current = target
		local speed = 0
		if previous and (previous.Position - target.Position).Magnitude <= FOLLOW_TELEPORT_DISTANCE then
			local dt = math.clamp(now - (visual.LastClock or now), 0.001, 0.25)
			local sharpness = math.max(FOLLOW_MIN_SHARPNESS, FOLLOW_SHARPNESS - (index - 1) * FOLLOW_STAGGER)
			current = previous:Lerp(target, 1 - math.exp(-sharpness * dt))
			speed = (current.Position - previous.Position).Magnitude / dt
		end
		visual.Current, visual.LastClock = current, now
		local walking = visual.Moving == true
		if speed > WALK_ON_SPEED then walking = true elseif speed < WALK_OFF_SPEED then walking = false end
		visual.Moving = walking
		model:SetAttribute("AnimState", if walking then "Walk" else "Idle")
		model:PivotTo(current)
	end
end

function FollowerService.CleanupPlayer(player: Player)
	FollowerService.Clear(player)
	for _, connection in playerConnections[player] or {} do connection:Disconnect() end
	playerConnections[player] = nil
end

function FollowerService.Init(carriedCheck: (Player, string) -> boolean, onChanged: (Player) -> ())
	if started then return end
	started = true
	isCarried = carriedCheck
	changed = onChanged
	local created = Instance.new("Folder")
	created.Name = "MonsterFollowers"
	created.Parent = workspace
	folder = created
	local function setup(player: Player)
		if playerConnections[player] then return end
		local list: { RBXScriptConnection } = {}
		playerConnections[player] = list
		local function clear()
			FollowerService.Hide(player)
			if player.Parent then changed(player) end
		end
		table.insert(list, player.CharacterRemoving:Connect(clear))
		local function onCharacter(character: Model)
			task.spawn(function()
				local humanoid = character:WaitForChild("Humanoid", 5)
				if humanoid and humanoid:IsA("Humanoid") and player.Character == character then
					table.insert(list, humanoid.Died:Connect(clear))
				end
			end)
		end
		table.insert(list, player.CharacterAdded:Connect(onCharacter))
		if player.Character then onCharacter(player.Character) end
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(FollowerService.CleanupPlayer)
	for _, player in Players:GetPlayers() do setup(player) end
	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.IgnoreWater = true
		rayParams.RespectCanCollide = true
		while true do
			local exclude: { Instance } = { created }
			local players = Players:GetPlayers()
			for _, player in players do if player.Character then table.insert(exclude, player.Character) end end
			rayParams.FilterDescendantsInstances = exclude
			for _, player in players do updateVisuals(player, rayParams) end
			task.wait(0.05)
		end
	end)
end

return FollowerService
