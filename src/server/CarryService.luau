--!strict
-- لما تاخد وحش (من عش، من Monster Rain، أو بيضة الـ Big Boss) بيتشال على ضهرك،
-- ولازم ترجع بيه لقاعدتك عشان يبقى بتاعك. لو حد ضربك وموّتك بياخده منك
-- ولازم يرجع بيه هو كمان. لو موتّ من حاجة تانية بيقع على الأرض وأي حد يقدر ياخده.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local Build = require(script.Parent.Build)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)
local CombatService = require(script.Parent.CombatService)
local CharacterService = require(script.Parent.CharacterService)

export type Cargo = {
	Kind: string, -- "Monster" أو "Egg"
	Species: string?,
	Mutation: string?,
	EggType: string?,
}

type Carry = {
	Cargo: Cargo,
	Model: Model,
	DiedConnection: RBXScriptConnection?,
	LastFullWarning: number,
}

local CarryService = {}

local carries: { [Player]: Carry } = {}
local pickupsFolder: Folder

function CarryService.CargoName(cargo: Cargo): string
	if cargo.Kind == "Egg" then
		local egg = Config.Eggs[cargo.EggType :: string]
		return if egg then egg.DisplayName else "Egg"
	end
	local species = Config.Species[cargo.Species :: string]
	local name = if species then species.DisplayName else "Monster"
	return if cargo.Mutation then cargo.Mutation .. " " .. name else name
end

local function cargoColor(cargo: Cargo): string
	if cargo.Kind == "Egg" then
		return "#FFFFFF"
	end
	local species = Config.Species[cargo.Species :: string]
	local rarity = species and Config.Rarities[species.Rarity]
	return if rarity then "#" .. rarity.Color:ToHex() else "#FFFFFF"
end

-- شكل الحاجة اللي بتتشال (وحش صغير أو بيضة)
local function buildCargoModel(cargo: Cargo): Model
	if cargo.Kind == "Monster" then
		local fake: MonsterMath.MonsterData = {
			Id = "Carried",
			Species = cargo.Species :: string,
			Mutation = cargo.Mutation,
			Level = 1,
			Xp = 0,
			Hunger = 100,
			Happiness = 100,
			Slot = 0,
		}
		local model = PlotService.BuildMonsterModel(fake)
		local info = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Info")
		if info then
			info:Destroy()
		end
		return model
	end
	local egg = Config.Eggs[cargo.EggType :: string]
	local model = Instance.new("Model")
	local part = Build.MakePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Color = if egg then egg.Color else Color3.new(1, 1, 1),
		Material = if cargo.EggType == "Secret" then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	if cargo.EggType == "Secret" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(200, 120, 255)
		sparkles.Parent = part
	end
	model.PrimaryPart = part
	return model
end

function CarryService.IsCarrying(player: Player): boolean
	return carries[player] ~= nil
end

local function speedFor(cargo: Cargo): number
	return if cargo.Kind == "Egg" and cargo.EggType == "Secret"
		then Config.Carry.SecretEggSpeedMultiplier
		else Config.Carry.WalkSpeedMultiplier
end

local function stopCarry(player: Player): Cargo?
	local carry = carries[player]
	if not carry then
		return nil
	end
	carries[player] = nil
	if carry.DiedConnection then
		carry.DiedConnection:Disconnect()
	end
	carry.Model:Destroy()
	CharacterService.SetSpeedFactor(player, "Carry", nil)
	return carry.Cargo
end

-- بيحط حاجة على الأرض وأي حد يقدر ياخدها (بيستخدمها الـ Monster Rain وبيضة الـ Boss والوقعات)
function CarryService.SpawnPickup(cargo: Cargo, position: Vector3, lifetime: number, title: string?, fallHeight: number?): Model
	local model = buildCargoModel(cargo)
	model.Name = "Pickup"
	local body = model.PrimaryPart :: BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	local ground = position + Vector3.new(0, body.Size.Y / 2 + 0.5, 0)
	model:PivotTo(CFrame.new(ground + Vector3.new(0, fallHeight or 0, 0)))
	model.Parent = pickupsFolder

	local gui, label = Build.MakeBillboard(body, UDim2.fromOffset(240, 60), Vector3.new(0, body.Size.Y / 2 + 3, 0), 250)
	gui.Name = "Info"
	label.Text = string.format('<font color="%s">%s</font>\n%s', cargoColor(cargo), CarryService.CargoName(cargo), title or "✋ Take it to your base!")

	local prompt = Build.MakePrompt(body, "PickupPrompt", "Take", Enum.KeyCode.E, Config.Combat.TakeHoldDuration)
	prompt.ObjectText = CarryService.CargoName(cargo)
	prompt.MaxActivationDistance = 12
	prompt.Enabled = fallHeight == nil
	prompt.Triggered:Connect(function(player)
		if model.Parent and CarryService.StartCarry(player, cargo) then
			model:Destroy()
		end
	end)

	-- بيقع من السما
	if fallHeight then
		task.spawn(function()
			local steps = 40
			for i = 1, steps do
				if not model.Parent then
					return
				end
				model:PivotTo(CFrame.new(ground + Vector3.new(0, fallHeight * (1 - i / steps), 0)))
				task.wait(0.05)
			end
			prompt.Enabled = true
		end)
	end

	task.delay(lifetime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
	return model
end

local function onCarrierDied(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local position = if root then root.Position else nil
	local cargo = stopCarry(player)
	if not cargo then
		return
	end
	local name = CarryService.CargoName(cargo)

	-- اللي قتلك بياخده منك
	local killer = CombatService.GetKiller(player)
	if killer and not CarryService.IsCarrying(killer) and CarryService.StartCarry(killer, cargo) then
		local profile = DataService.Get(killer)
		if profile then
			profile.Data.Stats.Steals += 1
		end
		MonsterService.Notify(killer, "🦹 You took " .. name .. " from " .. player.DisplayName .. "! Run home!", "warning")
		MonsterService.Notify(player, "😱 " .. killer.DisplayName .. " knocked you out and took your " .. name .. "!", "error")
		return
	end

	if position then
		CarryService.SpawnPickup(cargo, position - Vector3.new(0, 3, 0), Config.Carry.DropLifetime, "💥 Dropped! Grab it!")
		MonsterService.Notify(player, "You dropped " .. name .. "! Go back and grab it.", "error")
	end
end

-- بيشيّل اللاعب حاجة على ضهره. بيرجع false لو مش هينفع (شايل حاجة أو قاعدته مليانة).
function CarryService.StartCarry(player: Player, cargo: Cargo): boolean
	if carries[player] then
		MonsterService.Notify(player, "You are already carrying something! Take it home first.", "error")
		return false
	end
	if not MonsterService.GetFreeSlot(player) then
		MonsterService.Notify(player, "Your base is full! Sell a monster or buy a new slot.", "error")
		return false
	end
	local character = player.Character
	local torso = character and (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not torso or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local model = buildCargoModel(cargo)
	model.Name = "CarriedCargo"
	local body = model.PrimaryPart :: BasePart
	local scale = math.min(1, 2.6 / math.max(body.Size.Y, 0.1))
	if scale < 1 then
		model:ScaleTo(scale)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	model:PivotTo(torso.CFrame * CFrame.new(0, 0.4, 0.6 + body.Size.Y / 2))
	local weldConstraint = Instance.new("WeldConstraint")
	weldConstraint.Part0 = torso
	weldConstraint.Part1 = body
	weldConstraint.Parent = body
	model.Parent = character

	local carry: Carry = { Cargo = cargo, Model = model, DiedConnection = nil, LastFullWarning = 0 }
	carry.DiedConnection = humanoid.Died:Connect(function()
		if carries[player] == carry then
			onCarrierDied(player)
		end
	end)
	carries[player] = carry
	CharacterService.SetSpeedFactor(player, "Carry", speedFor(cargo))
	MonsterService.Notify(player, "🎒 You picked up " .. CarryService.CargoName(cargo) .. "! Carry it back to your base!", "warning")
	return true
end

local function deliver(player: Player, carry: Carry)
	local cargo = carry.Cargo
	local ok = if cargo.Kind == "Egg"
		then MonsterService.AddEgg(player, cargo.EggType :: string)
		else MonsterService.AddMonster(player, cargo.Species :: string, cargo.Mutation)
	if ok then
		stopCarry(player)
	elseif os.clock() - carry.LastFullWarning > 5 then
		carry.LastFullWarning = os.clock()
		MonsterService.Notify(player, "Your base is full! Free up a slot to keep it.", "error")
	end
end

local function update()
	for player, carry in carries do
		local plot = PlotService.GetPlot(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not carry.Model.Parent then
			-- الشخصية اتشالت (Respawn مثلاً) من غير Died
			onCarrierDied(player)
		elseif plot and root and PlotService.IsInsidePlot(plot, root.Position) then
			deliver(player, carry)
		end
	end
end

function CarryService.CleanupPlayer(player: Player)
	if carries[player] then
		onCarrierDied(player)
	end
end

function CarryService.Init()
	pickupsFolder = Instance.new("Folder")
	pickupsFolder.Name = "Pickups"
	pickupsFolder.Parent = workspace

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.2 then
			accumulator = 0
			update()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		CarryService.CleanupPlayer(player)
	end)
end

return CarryService
