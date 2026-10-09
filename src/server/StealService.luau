--!strict
-- سرقة الوحوش بستايل Steal a Brainrot:
-- تدخل قاعدة لاعب، تدوس مطوّل على وحش، تشيله فوق راسك وتجري بيه لقاعدتك.
-- لو صاحبه لحقك ولمسك، أو مُتّ، أو الوقت خلص → الوحش بيرجع لصاحبه.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterMath = require(ReplicatedStorage.Shared.MonsterMath)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonsterService = require(script.Parent.MonsterService)

type Carry = {
	Thief: Player,
	Owner: Player,
	MonsterId: string,
	Model: Model,
	StartedAt: number,
	OldWalkSpeed: number,
	DiedConnection: RBXScriptConnection?,
}

local StealService = {}

local carries: { [Player]: Carry } = {} -- thief → carry

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setCarried(owner: Player, monsterId: string, value: boolean)
	local set = MonsterService.Carried[owner]
	if not set then
		set = {}
		MonsterService.Carried[owner] = set
	end
	if value then
		set[monsterId] = true
	else
		set[monsterId] = nil
	end
end

local function endCarry(carry: Carry)
	carries[carry.Thief] = nil
	setCarried(carry.Owner, carry.MonsterId, false)
	if carry.DiedConnection then
		carry.DiedConnection:Disconnect()
	end
	carry.Model:Destroy()
	local humanoid = getHumanoid(carry.Thief)
	if humanoid then
		humanoid.WalkSpeed = carry.OldWalkSpeed
	end
end

-- الوحش يرجع لصاحبه
local function failCarry(carry: Carry, thiefMessage: string, ownerMessage: string?)
	endCarry(carry)
	local ownerProfile = DataService.Get(carry.Owner)
	local monster = ownerProfile and ownerProfile.Data.Monsters[carry.MonsterId]
	if monster then
		PlotService.RenderMonster(carry.Owner, monster)
		MonsterService.PushState(carry.Owner)
		if ownerMessage then
			MonsterService.Notify(carry.Owner, ownerMessage, "success")
		end
	end
	if carry.Thief.Parent and thiefMessage ~= "" then
		MonsterService.Notify(carry.Thief, thiefMessage, "error")
		MonsterService.PushState(carry.Thief)
	end
end

local function completeCarry(carry: Carry)
	local ownerProfile = DataService.Get(carry.Owner)
	local thiefProfile = DataService.Get(carry.Thief)
	local monster = ownerProfile and ownerProfile.Data.Monsters[carry.MonsterId]
	local slot = MonsterService.GetFreeSlot(carry.Thief)
	if not ownerProfile or not thiefProfile or not monster or not slot then
		failCarry(carry, "No free slot in your base! The monster went back to its owner.")
		return
	end

	endCarry(carry)

	ownerProfile.Data.Monsters[carry.MonsterId] = nil
	ownerProfile.Data.Stats.TimesRobbed += 1

	local newId = DataService.NewId(carry.Thief)
	local stolen: MonsterMath.MonsterData = table.clone(monster)
	stolen.Id = newId
	stolen.Slot = slot
	thiefProfile.Data.Monsters[newId] = stolen
	thiefProfile.Data.Stats.Steals += 1

	PlotService.RenderMonster(carry.Thief, stolen)

	local name = MonsterMath.GetDisplayName(stolen)
	MonsterService.Notify(carry.Thief, "🦹 You stole " .. name .. "!", "success")
	MonsterService.Notify(carry.Owner, "😱 " .. carry.Thief.DisplayName .. " stole your " .. name .. "!", "error")
	MonsterService.PushState(carry.Thief)
	MonsterService.PushState(carry.Owner)

	-- نحفظ الاتنين على طول عشان مفيش حد يخسر أو يكرر الوحش لو السيرفر وقع.
	task.spawn(DataService.Save, carry.Owner)
	task.spawn(DataService.Save, carry.Thief)
end

local function tryStartSteal(thief: Player, owner: Player, monsterId: string)
	if not Config.Steal.Enabled or thief == owner or carries[thief] then
		return
	end
	local ownerPlot = PlotService.GetPlot(owner)
	local thiefRoot = getRoot(thief)
	local humanoid = getHumanoid(thief)
	local ownerProfile = DataService.Get(owner)
	if not ownerPlot or not thiefRoot or not humanoid or humanoid.Health <= 0 or not ownerProfile then
		return
	end
	if not PlotService.GetPlot(thief) then
		return
	end
	if os.clock() < ownerPlot.LockedUntil then
		MonsterService.Notify(thief, "This base is locked! 🔒", "error")
		return
	end
	if not ownerProfile.Data.Monsters[monsterId] or MonsterService.IsCarried(owner, monsterId) then
		return
	end
	if Config.Steal.ProtectLastMonster and MonsterService.CountMonsters(owner) <= 1 then
		MonsterService.Notify(thief, "You can't steal a player's last monster.", "error")
		return
	end
	if not MonsterService.GetFreeSlot(thief) then
		MonsterService.Notify(thief, "Your base is full! Free up a slot first.", "error")
		return
	end

	local monster = ownerProfile.Data.Monsters[monsterId]
	setCarried(owner, monsterId, true)
	PlotService.RemoveMonster(owner, monsterId)

	-- نسخة من الوحش فوق راس الحرامي
	local model = PlotService.BuildMonsterModel(monster)
	local body = model.PrimaryPart :: BasePart
	local scale = math.min(1, 3 / body.Size.Y) -- الوحوش الكبيرة بتتشال أصغر شوية
	if scale < 1 then
		model:ScaleTo(scale)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	model:PivotTo(thiefRoot.CFrame * CFrame.new(0, 3.5 + body.Size.Y / 2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = thiefRoot
	weld.Part1 = body
	weld.Parent = body
	model.Name = "CarriedMonster"
	model.Parent = thief.Character

	local carry: Carry = {
		Thief = thief,
		Owner = owner,
		MonsterId = monsterId,
		Model = model,
		StartedAt = os.clock(),
		OldWalkSpeed = humanoid.WalkSpeed,
		DiedConnection = nil,
	}
	carry.DiedConnection = humanoid.Died:Connect(function()
		if carries[thief] == carry then
			failCarry(carry, "You dropped the monster! It went back to its owner.", "🛡️ The thief was knocked out. Your monster is back!")
		end
	end)
	carries[thief] = carry
	humanoid.WalkSpeed = Config.Steal.CarryWalkSpeed

	local name = MonsterMath.GetDisplayName(monster)
	MonsterService.Notify(thief, "🏃 You grabbed " .. name .. "! Run back to your base!", "warning")
	MonsterService.Notify(owner, "🚨 " .. thief.DisplayName .. " is stealing your " .. name .. "! Chase them and touch them!", "warning")
	MonsterService.PushState(owner)
end

local function update()
	for _, carry in carries do
		local thiefRoot = getRoot(carry.Thief)
		local thiefPlot = PlotService.GetPlot(carry.Thief)
		if not thiefRoot or not thiefPlot or not carry.Model.Parent then
			failCarry(carry, "You dropped the monster! It went back to its owner.")
			continue
		end
		if os.clock() - carry.StartedAt > Config.Steal.MaxCarryTime then
			failCarry(carry, "Time's up! The monster went back to its owner.")
			continue
		end
		local ownerRoot = getRoot(carry.Owner)
		local ownerHumanoid = getHumanoid(carry.Owner)
		if
			ownerRoot
			and ownerHumanoid
			and ownerHumanoid.Health > 0
			and (ownerRoot.Position - thiefRoot.Position).Magnitude <= Config.Steal.CatchRadius
		then
			failCarry(carry, "🚓 " .. carry.Owner.DisplayName .. " caught you! The monster went back.", "🛡️ You caught the thief and got your monster back!")
			continue
		end
		if PlotService.IsInsidePlot(thiefPlot, thiefRoot.Position) then
			completeCarry(carry)
		end
	end
end

-- لازم تتنادى قبل ما بيانات اللاعب تتمسح.
function StealService.CleanupPlayer(player: Player)
	local own = carries[player]
	if own then
		failCarry(own, "")
	end
	for _, carry in carries do
		if carry.Owner == player then
			-- صاحب الوحش خرج: نلغي السرقة والوحش يفضل في بياناته المحفوظة.
			endCarry(carry)
			MonsterService.Notify(carry.Thief, "The owner left the server, so the monster vanished.", "error")
		end
	end
end

function StealService.Init()
	PlotService.Callbacks.Steal = tryStartSteal
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.15 then
			accumulator = 0
			update()
		end
	end)
end

return StealService
