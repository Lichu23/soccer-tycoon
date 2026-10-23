--!nocheck
local T = require("./framework")
local Boards = T.load("shared/Leaderboards")
local Economy = T.load("server/Economy")
local Grants = T.load("server/Grants")
local ProfileSchema = T.load("server/ProfileSchema")
local Config = T.load("shared/Config")

T.suite("leaderboards")

local function entry(userId, value, name)
	return { userId = userId, name = name or ("u" .. userId), value = value }
end

T.test("the merge keeps each user's best score, sorted high to low", function()
	local stored = { entry(1, 50), entry(2, 40), entry(3, 30) }
	local live = { entry(2, 70), entry(4, 10) }
	local merged = Boards.merge(stored, live, 10)
	T.eq(#merged, 4)
	T.eq(merged[1].userId, 2)
	T.eq(merged[1].value, 70)
	T.eq(merged[2].userId, 1)
	T.eq(merged[4].userId, 4)
end)

T.test("the merge keeps only the top size, ties go to the lower user id", function()
	local merged = Boards.merge({ entry(9, 5), entry(3, 5), entry(5, 1) }, {}, 2)
	T.eq(#merged, 2)
	T.eq(merged[1].userId, 3)
	T.eq(merged[2].userId, 9)
end)

T.test(
	"a live score below the stored one keeps the stored score, zero scores are left out",
	function()
		local merged = Boards.merge({ entry(1, 80, "") }, { entry(1, 20, "Lisa"), entry(2, 0) }, 10)
		T.eq(#merged, 1)
		T.eq(merged[1].value, 80)
		T.eq(merged[1].name, "Lisa")
	end
)

T.test("every board formats its score", function()
	local byId = {}
	for _, board in Boards.boards do
		byId[board.id] = board
	end
	T.eq(byId.Juggles.format(42), "42")
	T.eq(byId.Seasons.format(3), "Season 3")
	T.eq(byId.Robux.format(1500), "R$ 1.5K")
	T.eq(#Boards.boards, 4)
end)

T.test("cash grants add to the lifetime cash earned, spending does not lower it", function()
	local data = ProfileSchema.newProfile()
	local start = data.stats.cashEarned
	Economy.grant(data, 500)
	T.eq(data.stats.cashEarned, start + 500)
	Economy.spend(data, 300)
	T.eq(data.stats.cashEarned, start + 500)
end)

T.test("a purchase adds the Robux charged once, a resent receipt adds nothing", function()
	local data = ProfileSchema.newProfile()
	Grants.apply(data, Config.Products.boost_cash, "r1", 1, 0, 25)
	T.eq(data.stats.robuxSpent, 25)
	Grants.apply(data, Config.Products.boost_cash, "r1", 2, 0, 25)
	T.eq(data.stats.robuxSpent, 25)
	Grants.apply(data, Config.Products.boost_cash, "r2", 3, 0)
	T.eq(data.stats.robuxSpent, 25 + Config.Products.boost_cash.robux)
end)

T.test("a profile with broken leaderboard totals does not save", function()
	local data = ProfileSchema.newProfile()
	T.eq((ProfileSchema.validate(data)), true)
	data.stats.robuxSpent = -1
	T.eq((ProfileSchema.validate(data)), false)
end)
