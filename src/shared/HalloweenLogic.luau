--!strict
-- Pure Halloween event rules (no Roblox services): counts, rewards, scheduling, hints and purchase checks.
-- HalloweenService uses these on the server and tools/test-halloween.luau exercises them directly.

export type Settings = { [string]: any }
export type Tracker = {
	MaxHealth: number,
	Health: number,
	Damage: { [number]: number }, -- by UserId, so a player leaving never leaves a dangling Player reference
	Record: (self: Tracker, userId: number, damage: number) -> number,
	Participants: (self: Tracker, fraction: number) -> { number },
}

local HalloweenLogic = {}

local function sortedKeys(weights: { [any]: number }): { any }
	local keys = {}
	for key, weight in weights do
		if type(weight) == "number" and weight > 0 and weight == weight and weight ~= math.huge then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- roll is a number in [0, 1). Iterates in sorted key order so the result is deterministic for tests.
function HalloweenLogic.WeightedPick(weights: { [any]: number }, roll: number): any?
	local keys = sortedKeys(weights)
	if #keys == 0 then return nil end
	local total = 0
	for _, key in keys do total += weights[key] end
	local target = math.clamp(roll, 0, 0.9999999999) * total
	for _, key in keys do
		target -= weights[key]
		if target < 0 then return key end
	end
	return keys[#keys]
end

function HalloweenLogic.RollInvasionCount(invasion: Settings, roll: number): number
	local weights: { [number]: number } = {}
	for count, weight in invasion.CountWeights do
		if type(count) == "number" and count >= invasion.MinCount then weights[count] = weight end
	end
	local picked = HalloweenLogic.WeightedPick(weights, roll)
	return if type(picked) == "number" then picked else invasion.MinCount
end

local function levelFraction(invasion: Settings, level: number): number
	local span = math.max(1, invasion.MaxLevel - invasion.MinLevel)
	return math.clamp((level - invasion.MinLevel) / span, 0, 1)
end

function HalloweenLogic.HealthForLevel(invasion: Settings, level: number): number
	local low, high = invasion.HealthAtMinLevel, invasion.HealthAtMaxLevel
	return math.floor(low * (high / low) ^ levelFraction(invasion, level) + 0.5)
end

function HalloweenLogic.DamageForLevel(invasion: Settings, level: number): number
	local low, high = invasion.DamageAtMinLevel, invasion.DamageAtMaxLevel
	return math.floor(low + (high - low) * levelFraction(invasion, level) + 0.5)
end

function HalloweenLogic.CandyForMother(invasion: Settings, level: number): number
	return math.max(0, math.floor(level)) * invasion.CandyPerLevel
end

function HalloweenLogic.QualifiesForReward(damage: number, maxHealth: number, fraction: number): boolean
	return maxHealth > 0 and damage >= maxHealth * fraction - 1e-9
end

-- Damage ledger for one Mother. Overkill is clipped to the HP that was really left.
function HalloweenLogic.NewTracker(maxHealth: number): Tracker
	local tracker = { MaxHealth = maxHealth, Health = maxHealth, Damage = {} } :: any
	function tracker.Record(self: Tracker, userId: number, damage: number): number
		if type(userId) ~= "number" or type(damage) ~= "number" or damage ~= damage or damage <= 0 or self.Health <= 0 then
			return 0
		end
		local applied = math.min(damage, self.Health)
		self.Health -= applied
		self.Damage[userId] = (self.Damage[userId] or 0) + applied
		return applied
	end
	function tracker.Participants(self: Tracker, fraction: number): { number }
		local result = {}
		for userId, dealt in self.Damage do
			if HalloweenLogic.QualifiesForReward(dealt, self.MaxHealth, fraction) then table.insert(result, userId) end
		end
		table.sort(result)
		return result
	end
	return tracker :: Tracker
end

function HalloweenLogic.PumpkinCandy(pumpkins: Settings, golden: boolean, roll: number): number
	if golden then return pumpkins.GoldenCandy end
	local span = pumpkins.CandyMax - pumpkins.CandyMin + 1
	return pumpkins.CandyMin + math.min(span - 1, math.floor(math.clamp(roll, 0, 0.9999999999) * span))
end

function HalloweenLogic.ConvertCandy(candy: number, rate: number): number
	if type(candy) ~= "number" or candy ~= candy or candy <= 0 then return 0 end
	return math.floor(candy) * math.max(0, rate)
end

-- Next scheduled time strictly after now. Same wall clock on every server.
function HalloweenLogic.NextOccurrence(now: number, interval: number, offset: number): number
	local cycles = math.floor((now - offset) / interval) + 1
	return cycles * interval + offset
end

-- 8 compass sectors around +X (sector 0), counter-clockwise looking down. Quantised on purpose.
function HalloweenLogic.HintSector(fromX: number, fromZ: number, toX: number, toZ: number): number
	local angle = math.atan2(toZ - fromZ, toX - fromX)
	return math.floor(((angle + math.pi / 8) % (math.pi * 2)) / (math.pi / 4)) % 8
end

function HalloweenLogic.HintBand(distance: number, bands: { number }): number
	for index, limit in bands do
		if distance <= limit then return index end
	end
	return #bands + 1
end

function HalloweenLogic.SectorDirection(sector: number): (number, number)
	local angle = sector * math.pi / 4
	return math.cos(angle), math.sin(angle)
end

-- The nearest pumpkin only, reduced to (sector, band). Nothing here allows recovering the exact spot.
function HalloweenLogic.Hint(fromX: number, fromZ: number, spots: { { X: number, Z: number } }, bands: { number }): (number?, number?)
	local bestDistance, bestSpot = math.huge, nil
	for _, spot in spots do
		local distance = math.sqrt((spot.X - fromX) ^ 2 + (spot.Z - fromZ) ^ 2)
		if distance < bestDistance then bestDistance, bestSpot = distance, spot end
	end
	if not bestSpot then return nil, nil end
	return HalloweenLogic.HintSector(fromX, fromZ, bestSpot.X, bestSpot.Z), HalloweenLogic.HintBand(bestDistance, bands)
end

function HalloweenLogic.BoostLeft(data: { [string]: any }, now: number): number
	local boost = data.BoostUntil
	if type(boost) ~= "number" or boost ~= boost then return 0 end
	return math.max(0, boost - now)
end

function HalloweenLogic.CashMultiplier(data: { [string]: any }, now: number, items: { [string]: any }): number
	if HalloweenLogic.BoostLeft(data, now) <= 0 then return 1 end
	local best = 1
	for _, item in items do
		if item.Kind == "Boost" and type(item.Multiplier) == "number" then best = math.max(best, item.Multiplier) end
	end
	return best
end

-- "ok" or a short reason code. Pure: never mutates data.
function HalloweenLogic.CheckPurchase(data: { [string]: any }, itemId: any, items: { [string]: any }, now: number): (boolean, string)
	if type(itemId) ~= "string" then return false, "Unknown" end
	local item = items[itemId]
	if not item then return false, "Unknown" end
	if type(data.Candy) ~= "number" or data.Candy < item.Cost then return false, "NoCandy" end
	local owned = data.Owned
	if (item.Unique or item.Kind == "Hat" or item.Kind == "Trail" or item.Kind == "Aura" or item.Kind == "Title")
		and type(owned) == "table" and owned[itemId] == true then
		return false, "Owned"
	end
	if item.Kind == "Boost" and HalloweenLogic.BoostLeft(data, now) + item.Duration > item.MaxBoostSeconds then
		return false, "BoostCap"
	end
	return true, "ok"
end

-- Candy ledger ----------------------------------------------------------------------------------

function HalloweenLogic.AwardCandy(data: { [string]: any }, amount: number, cap: number): number
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
	local granted = math.min(math.floor(amount), math.max(0, cap - data.Candy))
	data.Candy += granted
	data.TotalCandy += granted
	return granted
end

-- Everything left becomes coins. Returns the coins to pay; the caller pays them (DataService.AddCoins).
function HalloweenLogic.ConvertAll(data: { [string]: any }, rate: number): (number, number)
	local candy = math.floor(data.Candy)
	local coins = HalloweenLogic.ConvertCandy(candy, rate)
	data.Candy -= candy
	data.Converted += coins
	return coins, candy
end

export type Purchase = { Kind: string, EggType: string?, Species: string?, Undo: () -> () }

-- Charges the Candy and records the purchase in one step. Egg / monster grants are done by the caller,
-- who calls Undo() if the grant fails, so a failed grant never costs the player anything.
function HalloweenLogic.ApplyPurchase(data: { [string]: any }, itemId: any, items: { [string]: any }, now: number, eggRoll: number): (boolean, string, Purchase?)
	local ok, reason = HalloweenLogic.CheckPurchase(data, itemId, items, now)
	if not ok then return false, reason, nil end
	local item = items[itemId]
	local oldCandy, oldBoost = data.Candy, data.BoostUntil
	local oldOwned, oldEquipped = data.Owned[itemId], data.Equipped[item.Kind]
	local purchase: Purchase = { Kind = item.Kind, Undo = function() end }
	if item.Kind == "Egg" then
		local eggType = HalloweenLogic.WeightedPick(item.EggWeights, eggRoll) :: string?
		if not eggType then return false, "Unknown", nil end
		purchase.EggType = eggType
	end
	data.Candy -= item.Cost
	if item.Kind == "Boost" then
		data.BoostUntil = math.max(now, data.BoostUntil) + item.Duration
	elseif item.Kind == "Hat" or item.Kind == "Trail" or item.Kind == "Aura" or item.Kind == "Title" then
		data.Owned[itemId] = true
		data.Equipped[item.Kind] = itemId
	elseif item.Kind == "Monster" then
		purchase.Species = item.Species
		if item.Unique then data.Owned[itemId] = true end
	end
	purchase.Undo = function()
		data.Candy = oldCandy
		data.BoostUntil = oldBoost
		data.Owned[itemId] = oldOwned
		data.Equipped[item.Kind] = oldEquipped
	end
	return true, "ok", purchase
end

-- Equip / unequip an owned cosmetic. Returns false for anything not owned or not equippable.
function HalloweenLogic.SetEquipped(data: { [string]: any }, itemId: any, items: { [string]: any }, equip: boolean): boolean
	if type(itemId) ~= "string" then return false end
	local item = items[itemId]
	if not item or not (item.Kind == "Hat" or item.Kind == "Trail" or item.Kind == "Aura" or item.Kind == "Title") then return false end
	if data.Owned[itemId] ~= true then return false end
	if equip then data.Equipped[item.Kind] = itemId elseif data.Equipped[item.Kind] == itemId then data.Equipped[item.Kind] = nil end
	return true
end

-- Who gets Candy when a Mother dies: every player who dealt >= the fraction of her max HP.
function HalloweenLogic.Settle(tracker: Tracker, invasion: Settings, level: number): { { UserId: number, Candy: number } }
	local reward = HalloweenLogic.CandyForMother(invasion, level)
	local result = {}
	for _, userId in tracker:Participants(invasion.ParticipationFraction) do
		table.insert(result, { UserId = userId, Candy = reward })
	end
	return result
end

return HalloweenLogic
