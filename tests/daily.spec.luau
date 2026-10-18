--!nocheck
local T = require("./framework")
local Boosts = T.load("server/Boosts")
local Config = T.load("shared/Config")
local Daily = T.load("server/Daily")
local DailyInfo = T.load("shared/DailyInfo")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")

T.suite("daily case and penalty kicks")

local HOUR = 3600
local COOLDOWN = Config.Daily.cooldownSeconds
local T0 = 1_000_000

-- A player past the first stadium upgrade, with a player on the field.
local function playing()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	data.fieldStarted = true
	data.stadiumTier = Config.Daily.unlockTier
	return data
end

-- Rolls that make a kick score: no miss, and the keeper dives to the first zone.
local GOAL_ROLLS = { miss = 0.99, keeper = 0 }
local SAVE_ROLLS = { miss = 0.99, keeper = 0.99 }

T.test("nothing is open before the first stadium upgrade", function()
	local data = ProfileSchema.newProfile()
	T.eq(Daily.unlocked(data), false)
	local prize, why = Daily.claimCase(data, T0, 0.9)
	T.eq(prize, nil)
	T.eq(why, "locked")
	local result, reason = Daily.kick(data, T0, "topRight", GOAL_ROLLS)
	T.eq(result, nil)
	T.eq(reason, "locked")
	T.eq(Daily.kicksLeft(data, T0), 0)
end)

T.test("the case is ready once, then again exactly 20 hours after the claim", function()
	local data = playing()
	T.eq(Daily.caseReady(data, T0), true)
	local prize = Daily.claimCase(data, T0, 0.9)
	T.truthy(prize ~= nil)
	T.eq(Daily.caseReady(data, T0), false)
	T.eq(Daily.caseReady(data, T0 + COOLDOWN - 1), false)
	local again, why = Daily.claimCase(data, T0 + HOUR, 0.9)
	T.eq(again, nil)
	T.eq(why, "notReady")
	T.eq(Daily.caseReady(data, T0 + COOLDOWN), true)
	T.truthy(Daily.claimCase(data, T0 + COOLDOWN, 0.9) ~= nil)
end)

T.test("a refused claim changes nothing", function()
	local data = playing()
	Daily.claimCase(data, T0, 0.9)
	local cash, claimedAt = data.cash, data.daily.caseClaimedAt
	Daily.claimCase(data, T0 + 10, 0.9)
	T.eq(data.cash, cash)
	T.eq(data.daily.caseClaimedAt, claimedAt)
end)

-- Rolls that land on each reward of Config.Daily.caseRewards (weights 35 / 25 / 20 / 12 / 8).
local ROLL = { cashSmall = 0, boostShort = 0.4, tpSmall = 0.7, boostLong = 0.85, cashBig = 0.99 }

T.test("the free case has five different small rewards and never a player", function()
	T.eq(#Config.Daily.caseRewards, 5)
	local kinds, ids = {}, {}
	for _, reward in Config.Daily.caseRewards do
		T.falsy(ids[reward.id], "duplicate id " .. reward.id)
		ids[reward.id] = true
		kinds[reward.kind] = true
		T.truthy(reward.kind == "cash" or reward.kind == "boost" or reward.kind == "tp")
	end
	T.truthy(kinds.cash and kinds.boost and kinds.tp, "cash, boosts and training points")
end)

T.test("each roll lands on its reward, by weight", function()
	for id, roll in ROLL do
		T.eq(Daily.pickReward(roll).id, id)
	end
	T.eq(Daily.pickReward(0.999999999).id, "cashBig")
	T.eq(Daily.pickReward(-1).id, "cashSmall")
end)

T.test("cash rewards pay minutes of income, the big one pays more", function()
	local small, big = playing(), playing()
	local smallPrize = Daily.claimCase(small, T0, ROLL.cashSmall)
	local bigPrize = Daily.claimCase(big, T0, ROLL.cashBig)
	T.eq(smallPrize.kind, "cash")
	T.eq(small.cash - Config.StartingCash, smallPrize.amount)
	T.eq(smallPrize.amount, Daily.caseCash(playing(), 3))
	T.truthy(bigPrize.amount > smallPrize.amount * 2)
end)

T.test("boost rewards set the x2 timer, tp reward adds training points", function()
	local data = playing()
	local boost = Daily.claimCase(data, T0, ROLL.boostShort)
	T.eq(boost.kind, "boost")
	T.eq(data.boosts.stadiumBoostLeft, 180)
	local long = playing()
	Daily.claimCase(long, T0, ROLL.boostLong)
	T.eq(long.boosts.stadiumBoostLeft, 480)
	local tp = playing()
	local prize = Daily.claimCase(tp, T0, ROLL.tpSmall)
	T.eq(prize.kind, "tp")
	T.eq(tp.tp, 40)
	T.eq(tp.cash, Config.StartingCash)
end)

T.test("a case boost keeps the longer timer instead of adding", function()
	local data = playing()
	data.boosts.stadiumBoostLeft = 1000
	Daily.claimCase(data, T0, ROLL.boostShort)
	T.eq(data.boosts.stadiumBoostLeft, 1000)
	data.boosts.stadiumBoostLeft = 10
	data.daily.caseClaimedAt = 0
	Daily.claimCase(data, T0, ROLL.boostShort)
	T.eq(data.boosts.stadiumBoostLeft, 180)
end)

T.test("a cash reward with no income yet becomes a boost", function()
	local data = ProfileSchema.newProfile()
	data.stadiumTier = Config.Daily.unlockTier
	local prize = Daily.claimCase(data, T0, ROLL.cashSmall)
	T.eq(prize.kind, "boost")
end)

T.test("three kicks, then nothing until 20 hours after the first kick", function()
	local data = playing()
	T.eq(Daily.kicksLeft(data, T0), 3)
	T.eq(Daily.penaltyReadyAt(data, T0), 0)
	for _ = 1, 3 do
		T.truthy(Daily.kick(data, T0 + 100, "topLeft", SAVE_ROLLS) ~= nil)
	end
	T.eq(Daily.kicksLeft(data, T0 + 200), 0)
	local result, why = Daily.kick(data, T0 + 200, "topLeft", GOAL_ROLLS)
	T.eq(result, nil)
	T.eq(why, "notReady")
	-- The cooldown counts from the first kick (T0 + 100), not from the last.
	T.eq(Daily.penaltyReadyAt(data, T0 + 200), T0 + 100 + COOLDOWN)
	T.eq(Daily.kicksLeft(data, T0 + 100 + COOLDOWN - 1), 0)
	T.eq(Daily.kicksLeft(data, T0 + 100 + COOLDOWN), 3)
	T.eq(data.daily.goals, 0)
end)

T.test(
	"kicks left after leaving mid batch are still there, until the batch is 20 hours old",
	function()
		local data = playing()
		Daily.kick(data, T0, "topLeft", SAVE_ROLLS)
		T.eq(Daily.kicksLeft(data, T0 + 5 * HOUR), 2)
		T.truthy(Daily.kick(data, T0 + 5 * HOUR, "topLeft", SAVE_ROLLS) ~= nil)
		T.eq(Daily.kicksLeft(data, T0 + COOLDOWN), 3)
	end
)

T.test("a kick is a goal unless the keeper dives to the same zone or the shot goes wide", function()
	local data = playing()
	-- keeper roll 0 = first zone (topLeft)
	local saved = Daily.kick(data, T0, "topLeft", GOAL_ROLLS)
	T.eq(saved.keeper, "topLeft")
	T.eq(saved.goal, false)
	T.eq(saved.wide, false)
	local scored = Daily.kick(data, T0, "center", GOAL_ROLLS)
	T.eq(scored.goal, true)
	local wide = Daily.kick(data, T0, "topRight", { miss = 0, keeper = 0 })
	T.eq(wide.goal, false)
	T.eq(wide.wide, true)
end)

T.test("the penalty boost totals 3 / 5 / 10 minutes for 1 / 2 / 3 goals", function()
	for goals = 0, 3 do
		local data = playing()
		for kick = 1, 3 do
			-- The keeper always dives topLeft: center scores, topLeft is saved.
			Daily.kick(data, T0, if kick <= goals then "center" else "topLeft", GOAL_ROLLS)
		end
		T.eq(data.daily.goals, goals)
		T.eq(data.boosts.penaltyBoostLeft, Config.Daily.penaltyBoostSeconds[goals])
	end
end)

T.test("the boost is paid goal by goal, so leaving after one kick keeps what was scored", function()
	local data = playing()
	local first = Daily.kick(data, T0, "center", GOAL_ROLLS)
	T.eq(first.boostSeconds, 180)
	T.eq(data.boosts.penaltyBoostLeft, 180)
	local second = Daily.kick(data, T0, "center", GOAL_ROLLS)
	T.eq(second.boostSeconds, 120)
	local third = Daily.kick(data, T0, "center", GOAL_ROLLS)
	T.eq(third.boostSeconds, 300)
	T.eq(third.kicksLeft, 0)
end)

T.test("an unknown aim zone is refused and does not use a kick", function()
	local data = playing()
	local result, why = Daily.kick(data, T0, "middle", GOAL_ROLLS)
	T.eq(result, nil)
	T.eq(why, "badAim")
	T.eq(Daily.kicksLeft(data, T0), 3)
end)

T.test("the penalty boost multiplies with the stadium boost and is capped by the total", function()
	local data = playing()
	T.deepEq(Boosts.active(data), {})
	data.boosts.penaltyBoostLeft = 100
	T.deepEq(Boosts.active(data), { Config.Daily.penaltyMultiplier })
	data.boosts.stadiumBoostLeft = 50
	T.deepEq(
		Boosts.active(data),
		{ Config.Boost.stadiumMultiplier, Config.Daily.penaltyMultiplier }
	)
	T.eq(Boosts.nextEnd(data), 50)
	T.eq(Boosts.tick(data, 60), true) -- the stadium boost ended
	T.eq(Boosts.nextEnd(data), 40)
	T.eq(Boosts.tick(data, 10), false)
	T.eq(Boosts.tick(data, 40), true)
	T.eq(Boosts.nextEnd(data), 0)
end)

T.test("a saved profile with a wrong goal count is invalid", function()
	local data = playing()
	data.daily.kicksUsed = 1
	data.daily.goals = 2
	local valid = ProfileSchema.validate(data)
	T.eq(valid, false)
end)

T.test("wait text is plain and never a countdown clock", function()
	T.eq(DailyInfo.waitText(3 * HOUR + 20 * 60), "Ready in 3 h 20 min")
	T.eq(DailyInfo.waitText(2 * HOUR), "Ready in 2 h")
	T.eq(DailyInfo.waitText(45 * 60), "Ready in 45 min")
	T.eq(DailyInfo.waitText(30), "Ready in under a minute")
	T.eq(DailyInfo.waitText(-5), "Ready in under a minute")
end)

T.test("icon status: locked, waiting, ready", function()
	T.eq(DailyInfo.status(false, 0, 100), "locked")
	T.eq(DailyInfo.status(true, 200, 100), "waiting")
	T.eq(DailyInfo.status(true, 100, 100), "ready")
	T.eq(DailyInfo.status(true, 0, 100), "ready")
end)
