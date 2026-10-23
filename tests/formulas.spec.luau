--!nocheck
local T = require("./framework")
local Formulas = T.load("shared/Formulas")

T.suite("formulas players")

T.test("star multiplier is +10% per star and stops at 5", function()
	T.near(Formulas.starMultiplier(0), 1)
	T.near(Formulas.starMultiplier(3), 1.3)
	T.near(Formulas.starMultiplier(5), 1.5)
	T.near(Formulas.starMultiplier(9), 1.5)
	T.near(Formulas.starMultiplier(-2), 1)
end)

T.test("level multiplier is +3% per level", function()
	T.near(Formulas.levelMultiplier(0), 1)
	T.near(Formulas.levelMultiplier(10), 1.3)
end)

T.test("player income combines level and stars", function()
	T.near(Formulas.playerIncome(100, 0, 0), 100)
	T.near(Formulas.playerIncome(100, 10, 5), 100 * 1.3 * 1.5)
end)

T.test("level cost is 40 x level x rarity factor", function()
	T.eq(Formulas.levelCost("Common", 1), 40)
	T.eq(Formulas.levelCost("Common", 5), 200)
	T.eq(Formulas.levelCost("Rare", 3), 240)
	T.eq(Formulas.levelCost("Legend", 25), 5000)
end)

T.test("a Common reaches level 5 for 600 TP and a Legend level 25 for 65,000 TP", function()
	T.eq(Formulas.totalLevelCost("Common", 5), 600)
	T.eq(Formulas.totalLevelCost("Legend", 25), 65_000)
	T.eq(Formulas.totalLevelCost("Common", 0), 0)
end)

T.test("level cost rejects levels outside 1 to the cap", function()
	T.throws(function()
		Formulas.levelCost("Common", 0)
	end)
	T.throws(function()
		Formulas.levelCost("Common", 6)
	end)
	T.throws(function()
		Formulas.levelCost("Rare", 2.5)
	end)
end)

T.suite("formulas seasons")

T.test("season multiplier is x1, x1.5, x2.0, x2.5", function()
	T.near(Formulas.seasonMultiplier(1), 1)
	T.near(Formulas.seasonMultiplier(2), 1.5)
	T.near(Formulas.seasonMultiplier(3), 2)
	T.near(Formulas.seasonMultiplier(4), 2.5)
	T.near(Formulas.seasonMultiplier(10), 5.5) -- the last full step
	T.near(Formulas.seasonMultiplier(11), 5.6) -- then 0.1 a season
	T.near(Formulas.seasonMultiplier(20), 6.5)
	T.near(Formulas.seasonMultiplier(0), 1)
end)

T.test("head start is floor 1, then floors 1 and 2, and never floor 3", function()
	T.eq(Formulas.headStartFloors(1), 0)
	T.eq(Formulas.headStartFloors(2), 1)
	T.eq(Formulas.headStartFloors(3), 2)
	T.eq(Formulas.headStartFloors(10), 2)
	T.eq(Formulas.headStartFloors(99), 2)
end)

T.suite("formulas matches")

T.test("momentum is +1% per match in a row, capped at +25%", function()
	T.near(Formulas.momentumMultiplier(0), 1)
	T.near(Formulas.momentumMultiplier(10), 1.1)
	T.near(Formulas.momentumMultiplier(25), 1.25)
	T.near(Formulas.momentumMultiplier(500), 1.25)
end)

T.test("boosts multiply but never pass x4", function()
	T.near(Formulas.boostMultiplier({}), 1)
	T.near(Formulas.boostMultiplier({ 2 }), 2)
	T.near(Formulas.boostMultiplier({ 2, 1.5 }), 3)
	T.near(Formulas.boostMultiplier({ 2, 1.5, 2 }), 4)
	T.near(Formulas.boostMultiplier({ 2, 2, 2, 2 }), 4)
end)

T.test("field capacity follows the stadium tier", function()
	T.eq(Formulas.fieldCapacity(1), 4)
	T.eq(Formulas.fieldCapacity(2), 5)
	T.eq(Formulas.fieldCapacity(3), 6)
	T.eq(Formulas.fieldCapacity(4), 8)
	T.eq(Formulas.fieldCapacity(5), 11)
	T.eq(Formulas.fieldCapacity(99), 11)
	T.eq(Formulas.fieldCapacity(0), 4)
end)

T.test("store values and prices", function()
	T.eq(Formulas.storeValue("matchSpeed", 0), 10)
	T.eq(Formulas.storeValue("matchSpeed", 5), 5)
	T.eq(Formulas.storeValue("matchSpeed", 20), 5)
	T.eq(Formulas.storePrice("matchSpeed", 0), 120)
	T.eq(Formulas.storePrice("matchSpeed", 4), 8_000_000)
	T.eq(Formulas.storePrice("matchSpeed", 5), nil)
	T.eq(Formulas.tierCashMultiplier(1), 1.25)
	T.eq(Formulas.tierCashMultiplier(4), 6.7)
	T.eq(Formulas.tierCashMultiplier(6), 8)
	T.eq(Formulas.tierCashMultiplier(99), 8)
end)

T.suite("formulas payout")

T.test("the very first match pays the first player's income x1.25 (stadium tier 1)", function()
	T.eq(Formulas.payout({ fieldIncomes = { 4 }, stadiumTier = 1, season = 1 }), 5)
end)

T.test("the stadium upgrade makes the payout visibly bigger", function()
	T.eq(Formulas.payout({ fieldIncomes = { 10 }, stadiumTier = 2, season = 1 }), 27)
end)

T.test("hat-trick doubles the payout and a x2 boost doubles it again", function()
	T.eq(
		Formulas.payout({ fieldIncomes = { 4 }, stadiumTier = 1, season = 1, hatTrick = true }),
		10
	)
	T.eq(Formulas.payout({ fieldIncomes = { 4 }, stadiumTier = 1, season = 1, boosts = { 2 } }), 10)
end)

T.test("the payout multiplies every part", function()
	local payout = Formulas.payout({
		fieldIncomes = { 10, 20 },
		stadiumTier = 2,
		season = 2,
		momentumMatches = 10,
		boosts = { 2 },
		hatTrick = true,
	})
	T.eq(payout, 535) -- 30 x 2.7 x 1.5 x 1.1 x 2 x 2 = 534.6
end)

T.test("boosts inside the payout respect the x4 cap", function()
	local capped = Formulas.payout({
		fieldIncomes = { 100 },
		stadiumTier = 1,
		season = 1,
		boosts = { 2, 2, 2 },
	})
	T.eq(capped, 500) -- 100 x 1.25 x 4
end)

T.test("base payout leaves out momentum, boosts and hat-trick", function()
	T.near(
		Formulas.basePayout({
			fieldIncomes = { 10, 20 },
			stadiumTier = 2,
			season = 2,
			momentumMatches = 25,
			boosts = { 4 },
			hatTrick = true,
		}),
		30 * 2.7 * 1.5
	)
end)

T.suite("formulas offline")

T.test("offline earnings count whole matches at the offline rate", function()
	-- 25 s away at 10 s per match is 2 matches
	T.eq(Formulas.offlineEarnings(25, 10, 100, 0.1), 20)
end)

T.test("offline earnings stop at 4 hours", function()
	local capped = Formulas.offlineEarnings(100 * 3600, 10, 100, 0.1)
	T.eq(capped, 1440 * 100 * 0.1)
	T.eq(Formulas.offlineEarnings(4 * 3600, 10, 100, 0.1), capped)
end)

T.test("a negative or zero time away earns nothing", function()
	T.eq(Formulas.offlineEarnings(-500, 10, 100, 0.1), 0)
	T.eq(Formulas.offlineEarnings(0, 10, 100, 0.1), 0)
end)
