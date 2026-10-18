--!strict
-- M1 بتاع الوحوش: الضربة بتتعلّم على الأرض (Windup)، وبعدها السيرفر بيشوف مين لسه جوه الشكل ويضربه.
-- الكلاينت بيرسم العلامة والـ VFX بس، والضرر كله بيتحسب هنا.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)

local remotes = Remotes.Get()

local PLAYER_RADIUS = 1.5 -- نص عرض اللاعب، عشان طرف الدايرة يحسب

export type Params = {
	Model: Model?, -- عشان الكلاينت يلغي الـ VFX لو الوحش مات
	Root: BasePart,
	BodyRadius: number,
	Target: BasePart,
	Style: Config.MotherStyle,
	Element: string,
	Damage: number,
	IsValid: () -> boolean,
	OnDrain: ((amount: number) -> ())?,
}

local MonsterAttack = {}

local slowTokens: { [Player]: number } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function applyElement(player: Player, humanoid: Humanoid, damage: number, element: any, params: Params)
	if element.Slow then
		local token = (slowTokens[player] or 0) + 1
		slowTokens[player] = token
		CharacterService.SetSpeedFactor(player, "MonsterSlow", element.Slow)
		task.delay(element.SlowTime, function()
			if slowTokens[player] == token then
				slowTokens[player] = nil
				CharacterService.SetSpeedFactor(player, "MonsterSlow", nil)
			end
		end)
	end
	if element.BurnTicks then
		local burn = math.max(1, math.floor(damage * element.BurnFraction + 0.5))
		task.spawn(function()
			for _ = 1, element.BurnTicks do
				task.wait(1)
				if humanoid.Parent == nil or humanoid.Health <= 0 then
					break
				end
				humanoid:TakeDamage(burn)
				remotes.PlayerHurt:FireClient(player, burn, element.Color)
			end
		end)
	end
	if element.Drain and params.OnDrain then
		params.OnDrain(damage * element.Drain)
	end
end

-- ضربة واحدة: بتعلّم الأرض، وبعد windup بتضرب كل اللي جوه الشكل
local function strikeOnce(params: Params, element: any, windup: number)
	local style = params.Style
	local origin = params.Root.Position
	local toTarget = flat(params.Target.Position - origin)
	local direction = if toTarget.Magnitude > 0.01 then toTarget.Unit else flat(params.Root.CFrame.LookVector).Unit

	local center = origin
	local radius = style.Radius
	local range = params.BodyRadius + style.Range
	if style.Shape == "Slam" then
		radius = params.BodyRadius + style.Radius
	elseif style.Shape == "Lob" then
		local distance = math.min(toTarget.Magnitude, style.Range)
		center = origin + direction * distance
	end

	remotes.MonsterAttack:FireAllClients({
		Model = params.Model,
		Shape = style.Shape,
		Style = style.Name,
		Origin = origin,
		Center = center,
		Direction = direction,
		Radius = radius,
		Range = range,
		Angle = style.Angle or 60,
		Windup = windup,
		Color = element.Color,
		Secondary = element.Secondary,
		Element = element.Name,
	})

	task.delay(windup, function()
		if not params.IsValid() then
			return
		end
		local cosHalf = math.cos(math.rad((style.Angle or 60) / 2))
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then
				continue
			end
			local hit = false
			if style.Shape == "Cone" then
				local offset = flat(root.Position - origin)
				local distance = offset.Magnitude
				hit = distance <= range + PLAYER_RADIUS
					and (distance <= params.BodyRadius + PLAYER_RADIUS or offset.Unit:Dot(direction) >= cosHalf)
			else
				hit = flat(root.Position - center).Magnitude <= radius + PLAYER_RADIUS
			end
			if hit then
				humanoid:TakeDamage(params.Damage)
				remotes.PlayerHurt:FireClient(player, params.Damage, element.Color)
				applyElement(player, humanoid, params.Damage, element, params)
			end
		end
	end)
end

-- بتبدأ الضربة (أو الكومبو لو Style.Hits) وبترجع المدة لحد آخر ضربة
function MonsterAttack.Start(params: Params): number
	local style = params.Style
	local element = Config.MotherAttacks.Elements[params.Element] or Config.MotherAttacks.Elements.Void
	local hits = style.Hits or 1
	if hits <= 1 then
		strikeOnce(params, element, style.Windup)
		return style.Windup
	end
	-- كومبو: الضربة i بتنزل عند Windup + (i-1)*Interval، والعلامة بتظهر قبلها بـ ComboTelegraph
	local interval = style.HitInterval or 0.4
	local telegraph = math.min(0.3, interval * 0.8)
	for i = 1, hits do
		local hitAt = style.Windup + (i - 1) * interval
		local fireAt = if i == 1 then 0 else hitAt - telegraph
		task.delay(fireAt, function()
			if params.IsValid() then
				strikeOnce(params, element, if i == 1 then style.Windup else telegraph)
			end
		end)
	end
	return style.Windup + (hits - 1) * interval
end

function MonsterAttack.CleanupPlayer(player: Player)
	slowTokens[player] = nil
end

return MonsterAttack
