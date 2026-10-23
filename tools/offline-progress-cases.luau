-- Dependency-injected regression cases: runnable in Studio and from Lune.
return function(Config, MonsterMath)
	local checks = 0
	local function check(value, message) checks += 1; assert(value, message) end
	local function near(a, b) return math.abs(a - b) < 0.001 end
	local start = 1700000000
	local species = next(Config.Species)
	local function monster(level, hunger)
		return { Id = "test", Species = species, Level = level or 1, Xp = 0,
			Hunger = hunger or 0, Happiness = hunger or 0, Slot = 1, LastProgressAt = start }
	end
	check(Config.AdultGrowthSeconds == 9000, "Natural Baby -> Adult duration must be 9000 seconds")
	local baby = monster()
	MonsterMath.AdvanceProgress(baby, start + 8999, true, 1)
	check(baby.Level < 25, "Natural growth must not reach Adult a second early")
	MonsterMath.AdvanceProgress(baby, start + 9000, true, 1)
	check(baby.Level == 25 and near(baby.Xp, 0), "Hungry offline baby reaches Adult at exactly 2h 30m")
	local healthy = monster(1, 100)
	MonsterMath.AdvanceProgress(healthy, start + 9000, true, 1)
	check(healthy.Level == 25, "Initial needs do not change the natural Adult deadline")
	local online, offline = monster(1, 100), monster(1, 100)
	local onlineCoins = 0
	for second = 1, 9000 do onlineCoins += MonsterMath.AdvanceProgress(online, start + second, true, 2) end
	local offlineCoins = MonsterMath.AdvanceProgress(offline, start + 9000, true, 2)
	check(near(onlineCoins, offlineCoins) and online.Level == offline.Level and near(online.Xp, offline.Xp), "Online ticks and one offline interval produce equal growth and income")
	check(near(online.Hunger, offline.Hunger) and near(online.Happiness, offline.Happiness), "Online and offline needs use the same decay")
	check(MonsterMath.AdvanceProgress(offline, start + 9000, true, 2) == 0, "Repeating the same timestamp cannot award income twice")
	local saved = table.clone(offline)
	check(MonsterMath.AdvanceProgress(saved, start + 9000, true, 2) == 0, "Persisted timestamp prevents replay after a reload")
	local noBonus = monster()
	local single = MonsterMath.AdvanceProgress(noBonus, start + 9000, true, 1)
	local doubled = monster()
	check(near(MonsterMath.AdvanceProgress(doubled, start + 9000, true, 2), single * 2), "Saved coin multiplier is applied exactly once")
	local bench = monster(1, 100)
	check(MonsterMath.AdvanceProgress(bench, start + 9000, false, 1) == 0 and bench.Level == 25 and bench.Hunger == 100, "Bench/carried monsters age without generating income or decaying needs")
	local legacy = monster(12, 60)
	legacy.LastProgressAt = nil
	check(MonsterMath.AdvanceProgress(legacy, start + 50000, true, 1) == 0 and legacy.Level == 12 and legacy.Hunger == 60, "Legacy migration preserves progress and does not invent old earnings")
	check(legacy.LastProgressAt == start + 50000, "Legacy migration starts a persistent server clock")
	for _, invalid in { 0 / 0, math.huge, -math.huge, start + 100000, -1 } do
		local damaged = monster()
		damaged.LastProgressAt = invalid
		check(MonsterMath.AdvanceProgress(damaged, start, true, 1) == 0 and damaged.LastProgressAt == start, "Invalid/future timestamps are reset without awarding phantom income")
	end
	local fed = monster()
	MonsterMath.AddXp(fed, Config.Food.Xp)
	MonsterMath.AdvanceProgress(fed, start + 8999, true, 1)
	check(fed.Level >= 25, "Manual care XP accelerates the natural Adult deadline")
	local legendary = monster(45, 100)
	MonsterMath.AdvanceProgress(legendary, start + 9000, true, 1)
	check(legendary.Level >= 45, "Existing Legendary monsters never regress")
	local maximum = monster(Config.MaxLevel)
	local rate = MonsterMath.GetProduction(maximum)
	local years = 10 * 365 * 24 * 60 * 60
	check(near(MonsterMath.AdvanceProgress(maximum, start + years, true, 1), rate * years), "Long absences have no arbitrary income cap")
	check(maximum.Level == Config.MaxLevel and maximum.Xp == 0, "Long absences respect the maximum level")
	local boundary = monster(25, 100)
	local base = MonsterMath.GetProduction(boundary)
	local untilLow = (100 - Config.LowNeedsThreshold) / Config.HungerDecayPerSecond
	local actual = MonsterMath.AdvanceProgress(boundary, start + untilLow + 1, true, 1)
	-- Healthy passive XP cannot level this Adult within this short interval.
	check(near(actual, base * untilLow + base * Config.LowNeedsProductionMultiplier), "Income integrates the exact low-needs boundary instead of using the final rate for the entire absence")
	return string.format("PASS: %d offline growth/income checks", checks)
end
