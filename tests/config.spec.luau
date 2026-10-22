--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")

T.suite("config players")

local function countBy(field: string): { [any]: number }
	local counts = {}
	for _, def in Config.Players do
		counts[def[field]] = (counts[def[field]] or 0) + 1
	end
	return counts
end

T.test("there are 35 players with unique ids, names and slots 1 to 35", function()
	T.eq(#Config.Players, 35)
	local ids, names = {}, {}
	for index, def in Config.Players do
		T.falsy(ids[def.id], "duplicate id " .. def.id)
		T.falsy(names[def.name], "duplicate name " .. def.name)
		ids[def.id], names[def.name] = true, true
		T.eq(def.slot, index, "slot of " .. def.id)
		T.eq(Config.PlayersById[def.id], def, "PlayersById " .. def.id)
	end
end)

T.test("rarity counts are 4 / 10 / 10 / 6 / 5", function()
	local counts = countBy("rarity")
	T.eq(counts.Common, 4)
	T.eq(counts.Rare, 10)
	T.eq(counts.VeryRare, 10)
	T.eq(counts.Epic, 6)
	T.eq(counts.Legend, 5)
end)

T.test("floor counts are 10 / 10 / 10 / 5", function()
	local counts = countBy("floor")
	T.eq(counts[1], 10)
	T.eq(counts[2], 10)
	T.eq(counts[3], 10)
	T.eq(counts[4], 5)
end)

T.test("each floor only holds its rarities", function()
	local allowed = {
		[1] = { Common = true, Rare = true },
		[2] = { Rare = true, VeryRare = true },
		[3] = { VeryRare = true, Epic = true },
		[4] = { Legend = true },
	}
	for _, def in Config.Players do
		T.truthy(allowed[def.floor][def.rarity], def.id .. " has a rarity not allowed on its floor")
	end
end)

T.test("floors and rarities never go down as the slot goes up", function()
	for index = 2, #Config.Players do
		local before, after = Config.Players[index - 1], Config.Players[index]
		T.truthy(after.floor >= before.floor, "floor at slot " .. index)
		T.truthy(
			Config.Rarities[after.rarity].order >= Config.Rarities[before.rarity].order,
			"rarity at slot " .. index
		)
	end
end)

T.test("price and income rise strictly with the slot", function()
	for index = 2, #Config.Players do
		local before, after = Config.Players[index - 1], Config.Players[index]
		T.truthy(after.price > before.price, "price at slot " .. index)
		T.truthy(after.income > before.income, "income at slot " .. index)
	end
end)

T.test("Step 3 anchor values", function()
	local function check(id: string, price: number, income: number)
		T.eq(Config.PlayersById[id].price, price, id .. " price")
		T.eq(Config.PlayersById[id].income, income, id .. " income")
	end
	check("rashford", 10, 3) -- slot 1
	check("gavi", 11_100, 268) -- slot 10
	check("lautaro", 21_200, 403) -- slot 11
	check("rodri", 6_800_000, 15_500) -- slot 20
	check("foden", 13_700_000, 22_400) -- slot 21
	check("messi", 6_990_000_000, 636_000) -- slot 30
end)

T.test("Legend prices are 400B / 1T / 2.5T / 6T / 15T", function()
	local prices = {}
	for _, def in Config.Players do
		if def.rarity == "Legend" then
			table.insert(prices, def.price)
		end
	end
	T.deepEq(prices, {
		400_000_000_000,
		1_000_000_000_000,
		2_500_000_000_000,
		6_000_000_000_000,
		15_000_000_000_000,
	})
end)

T.test("every player has a name, nationality and shirt number", function()
	for _, def in Config.Players do
		T.truthy(utf8.len(def.name) and (utf8.len(def.name) :: number) > 0, def.id .. " name")
		T.truthy(#def.nationality > 0, def.id .. " nationality")
		T.truthy(def.number >= 1 and def.number <= 99, def.id .. " number")
	end
end)

T.suite("config economy")

T.test("rarity level caps and cost factors", function()
	local expected = { Common = 5, Rare = 10, VeryRare = 15, Epic = 20, Legend = 25 }
	for rarity, cap in expected do
		T.eq(Config.Rarities[rarity].levelCap, cap, rarity .. " cap")
	end
	T.eq(Config.Rarities.Legend.costFactor, 5)
	T.eq(#Config.RarityOrder, 5)
end)

T.test("basic constants", function()
	T.eq(Config.StartingCash, 15)
	T.eq(Config.Pad.holdSeconds, 1)
	T.eq(Config.Daily.cooldownSeconds, 72_000)
	T.eq(Config.Daily.penaltyKicks, 3)
	T.eq(Config.Offline.capSeconds, 14_400)
	T.eq(Config.Boost.totalCap, 4)
	T.eq(Config.Boost.matchBankMax, 60)
	T.truthy(Config.MaxCash < 2 ^ 53, "MaxCash must stay exact in a double")
end)

T.test("penalty boost minutes are 0 / 3 / 5 / 10", function()
	T.deepEq(Config.Daily.penaltyBoostSeconds, { [0] = 0, [1] = 180, [2] = 300, [3] = 600 })
end)

T.test(
	"the stadium tiers multiply the match cash x1.25 to x8 (the old cash upgrade is gone)",
	function()
		local multipliers = {}
		for _, tier in Config.StadiumTiers do
			table.insert(multipliers, tier.cashMultiplier)
		end
		T.deepEq(multipliers, { 1.25, 2.7, 5.1, 6.7, 6.7, 8 })
		T.eq(Config.Store.cashPerMatch, nil)
	end
)

T.test("the three x2 boost pads cost 39, 39 and 69 Robux for 10 minutes", function()
	T.eq(Config.Products.boost_cash.robux, 39)
	T.eq(Config.Products.boost_tp.robux, 39)
	T.eq(Config.Products.boost_both.robux, 69)
	T.eq(Config.Boost.paidSeconds, 600)
end)

T.test("match speed never goes below 5 seconds and unlocks at tier 2", function()
	local def = Config.Store.matchSpeed
	T.deepEq(def.values, { 9, 8, 7, 6, 5 })
	T.eq(def.minTier, 2)
end)

T.test("the hat-trick upgrade unlocks after floor 1 and has 3 levels up to 25%", function()
	local def = Config.Store.hatTrick
	T.eq(def.floorsComplete, 1)
	T.eq(def.baseValue, 0.05)
	T.deepEq(def.prices, { 2_000, 60_000, 1_500_000 })
	T.deepEq(def.values, { 0.10, 0.20, 0.25 })
end)

T.test("offline earnings are no upgrade: everyone earns 25% while away", function()
	T.eq((Config.Store :: any).offline, nil)
	T.eq(Config.Offline.rate, 0.25)
end)

T.test("store prices rise within every upgrade", function()
	for id, def in Config.Store do
		T.eq(#def.prices, #def.values, id .. " prices and values match")
		for level = 2, #def.prices do
			T.truthy(def.prices[level] > def.prices[level - 1], id .. " price at level " .. level)
		end
	end
end)

T.test("stadium tiers", function()
	local tiers = Config.StadiumTiers
	T.eq(#tiers, 6)
	local prices, fields = {}, {}
	for _, def in tiers do
		table.insert(prices, def.price)
		table.insert(fields, def.field)
	end
	T.deepEq(prices, { 0, 250, 25_000, 750_000, 45_000_000, 1_500_000_000 })
	T.deepEq(fields, { 4, 5, 6, 8, 11, 11 })
	for index, def in tiers do
		T.eq(def.tier, index)
	end
	-- the pitch grows with every tier up to the arena (the roof arena keeps its pitch) and stays
	-- inside the 160 x 112 pitch zone
	T.deepEq({
		tiers[1].courtLength,
		tiers[2].courtLength,
		tiers[3].courtLength,
		tiers[4].courtLength,
		tiers[5].courtLength,
	}, { 60, 70, 84, 100, 120 })
	T.deepEq({
		tiers[1].courtWidth,
		tiers[2].courtWidth,
		tiers[3].courtWidth,
		tiers[4].courtWidth,
		tiers[5].courtWidth,
	}, { 36, 42, 50, 60, 72 })
	for index = 2, 5 do
		T.truthy(tiers[index].courtLength > tiers[index - 1].courtLength)
		T.truthy(tiers[index].courtWidth > tiers[index - 1].courtWidth)
	end
	T.eq(tiers[6].courtLength, tiers[5].courtLength)
	T.eq(tiers[6].courtWidth, tiers[5].courtWidth)
end)

T.test("stars, training and season constants", function()
	T.eq(Config.Stars.bonusPerStar, 0.10)
	T.eq(Config.Stars.maxStars, 5)
	T.eq(Config.Training.bonusPerLevel, 0.03)
	T.eq(Config.Training.levelCostBase, 40)
	T.eq(Config.Training.idleTpPerMinute, 10)
	T.eq(Config.Training.freekickTpPerMinuteMax, 40)
	T.truthy(
		Config.Training.freekickTpPerMinuteMax > Config.Training.idleTpPerMinute,
		"the breakaway must beat the treadmill"
	)
	T.eq(Config.Training.juggleTpTiers[1].tp, 1)
	T.eq(Config.Season.bonusPerSeason, 0.5)
	T.eq(Config.Match.momentumCap, 0.25)
end)
