--!nocheck
local T = require("./framework")
local MatchLogic = T.load("server/MatchLogic")
local Boosts = T.load("server/Boosts")
local Roster = T.load("shared/Roster")
local Config = T.load("shared/Config")
local ProfileSchema = T.load("server/ProfileSchema")

local function newData()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford") -- $3 per match
	data.fieldStarted = true
	return data
end

local FRESH = { matchesInRow = 0, matchesPlayed = 0 }
local NO_LUCK = function()
	return 0.99
end
local LUCK = function()
	return 0.01
end

-- One match the way the server plays it: rolled at kick-off, paid at the whistle.
local function play(data, state, rng)
	local plan = MatchLogic.plan(data, state, rng)
	return if plan then MatchLogic.resolve(data, state, plan) else nil
end

T.suite("match interval")

T.test("the very first match is 5 seconds, then the match speed applies", function()
	local data = newData()
	T.eq(MatchLogic.interval(data), 5)
	data.flags.milestones.first_match = 1
	T.eq(MatchLogic.interval(data), 10)
	data.storeLevels.matchSpeed = 2
	T.eq(MatchLogic.interval(data), 8)
end)

T.suite("match goals")

T.test("the scoreboard shows more goals for a bigger payout", function()
	T.eq((MatchLogic.goals(3, false)), 1)
	T.eq((MatchLogic.goals(30, false)), 2)
	T.eq((MatchLogic.goals(300, false)), 3)
	T.eq((MatchLogic.goals(3000, false)), 4)
	T.eq((MatchLogic.goals(1e9, false)), 5) -- never more than 5
end)

T.test("a hat-trick always shows at least three goals", function()
	T.eq((MatchLogic.goals(6, true)), 3)
	T.eq((MatchLogic.goals(1e9, true)), 5)
end)

T.test("the match is always a win", function()
	for payout = 1, 3000 do
		local goalsFor, goalsAgainst = MatchLogic.goals(payout, payout % 7 == 0)
		T.truthy(goalsFor > goalsAgainst, "payout " .. payout)
		T.truthy(goalsAgainst >= 0)
	end
end)

T.suite("match resolve")

T.test("nobody on the field means no match", function()
	local data = ProfileSchema.newProfile()
	T.eq(play(data, FRESH, NO_LUCK), nil)
end)

T.test("one Common player pays his income at tier 1 (x1.25)", function()
	local result = play(newData(), FRESH, NO_LUCK)
	T.eq(result.payout, 4) -- 3 x 1.25 = 3.75
	T.eq(result.hatTrick, false)
	T.deepEq(result.fieldIds, { "rashford" })
	T.truthy(result.goalsFor > result.goalsAgainst)
end)

T.test("a lucky roll is a hat-trick: double payout and the flag is set", function()
	local data = newData()
	local result = play(data, FRESH, LUCK)
	T.eq(result.hatTrick, true)
	T.eq(result.payout, 8) -- 7.5
	T.truthy(result.goalsFor >= 3)
	T.eq(data.flags.firstHatTrickDone, true)
end)

T.test("the hat-trick chance upgrade changes the odds", function()
	local data = newData()
	local roll = function()
		return 0.07
	end
	T.eq(play(data, FRESH, roll).hatTrick, false) -- base 5%
	data.storeLevels.hatTrick = 1 -- 10%
	T.eq(play(data, FRESH, roll).hatTrick, true)
end)

T.test("the first hat-trick is scripted on match 22 even with bad luck", function()
	local data = newData()
	local early = play(data, { matchesInRow = 20, matchesPlayed = 20 }, NO_LUCK)
	T.eq(early.hatTrick, false)
	local scripted = play(data, { matchesInRow = 21, matchesPlayed = 21 }, NO_LUCK)
	T.eq(scripted.hatTrick, true)
	T.eq(data.flags.firstHatTrickDone, true)
end)

T.test("the scripted hat-trick only happens once", function()
	local data = newData()
	data.flags.firstHatTrickDone = true
	local result = play(data, { matchesInRow = 21, matchesPlayed = 21 }, NO_LUCK)
	T.eq(result.hatTrick, false)
end)

T.test("a natural hat-trick before match 22 replaces the scripted one", function()
	local data = newData()
	play(data, { matchesInRow = 5, matchesPlayed = 5 }, LUCK)
	local later = play(data, { matchesInRow = 21, matchesPlayed = 21 }, NO_LUCK)
	T.eq(later.hatTrick, false)
end)

T.test("an active stadium boost doubles the payout", function()
	local data = newData()
	Boosts.startStadium(data)
	T.eq(play(data, FRESH, NO_LUCK).payout, 8) -- 7.5
end)

T.test("momentum adds 1% per match in a row", function()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	Roster.add(data, "grealish")
	Roster.add(data, "sterling")
	data.stadiumTier = 1
	-- field: sterling 9 + grealish 5 + rashford 3 = 17, x1.25 for tier 1, momentum 10 -> x1.1
	local result = play(data, { matchesInRow = 10, matchesPlayed = 10 }, NO_LUCK)
	T.eq(result.payout, 23) -- 23.375
end)

T.test("the stadium tier multiplies the payout", function()
	local data = newData()
	data.stadiumTier = 2 -- x2.7: 3 -> 8.1
	T.eq(play(data, FRESH, NO_LUCK).payout, 8)
end)

T.test("a bought x2 cash boost doubles the payout", function()
	local data = newData()
	Boosts.addPaid(data, true, false)
	T.eq(play(data, FRESH, NO_LUCK).payout, 8) -- 7.5
end)

T.test("a later season multiplies the payout", function()
	local data = newData()
	data.season.number = 3 -- x2
	T.eq(play(data, FRESH, NO_LUCK).payout, 8) -- 7.5
end)

T.suite("boosts")

T.test("the stadium boost lasts 300 connected seconds", function()
	local data = ProfileSchema.newProfile()
	T.deepEq(Boosts.active(data), {})
	Boosts.startStadium(data)
	T.deepEq(Boosts.active(data), { 2 })
	Boosts.tick(data, 100)
	T.eq(data.boosts.stadiumBoostLeft, 200)
	Boosts.tick(data, 500)
	T.eq(data.boosts.stadiumBoostLeft, 0)
	T.deepEq(Boosts.active(data), {})
	T.eq(Config.Boost.stadiumSeconds, 300)
end)

T.test("bought boosts add 10 minutes each, run only online and stop at an hour", function()
	local data = ProfileSchema.newProfile()
	T.eq(Boosts.tpMultiplier(data), 1)
	Boosts.addPaid(data, false, true)
	T.eq(data.boosts.tpBoostLeft, 600)
	T.eq(data.boosts.cashBoostLeft, 0)
	T.eq(Boosts.tpMultiplier(data), 2)
	T.deepEq(Boosts.active(data), {}) -- the TP boost does not touch the match cash
	Boosts.addPaid(data, true, true)
	T.eq(data.boosts.tpBoostLeft, 1200)
	T.eq(data.boosts.cashBoostLeft, 600)
	T.deepEq(Boosts.active(data), { 2 })
	T.eq(Boosts.nextEnd(data), 600)
	T.eq(Boosts.tick(data, 600), true) -- the cash boost ended
	T.eq(data.boosts.tpBoostLeft, 600)
	T.eq(Boosts.canAddPaid(data, false, true), true)
	data.boosts.tpBoostLeft = 3001
	T.eq(Boosts.canAddPaid(data, false, true), false)
	T.eq(Boosts.canAddPaid(data, true, false), true)
end)

T.suite("match plan")

T.test("the plan rolled at kick-off is the match that is paid", function()
	local data = newData()
	local plan = MatchLogic.plan(data, FRESH, LUCK)
	T.eq(plan.hatTrick, true)
	T.eq(data.flags.firstHatTrickDone, false) -- rolling changes nothing
	local result = MatchLogic.resolve(data, FRESH, plan)
	T.eq(result.hatTrick, true)
	T.eq(result.goalsFor, plan.goalsFor)
	T.eq(result.goalsAgainst, plan.goalsAgainst)
	T.eq(data.flags.firstHatTrickDone, true)
end)

T.test("a player bought during the match is paid at the whistle", function()
	local data = newData()
	local plan = MatchLogic.plan(data, FRESH, NO_LUCK)
	Roster.add(data, "grealish")
	data.stadiumTier = 1
	T.eq(MatchLogic.resolve(data, FRESH, plan).payout, 10) -- (3 + 5) x 1.25
end)

T.test("a banked boosted match is used up once, at the whistle", function()
	local data = newData()
	data.boosts.bankedMatches = 1
	local plan = MatchLogic.plan(data, FRESH, NO_LUCK)
	T.eq(data.boosts.bankedMatches, 1)
	T.eq(MatchLogic.resolve(data, FRESH, plan).payout, 8) -- 7.5
	T.eq(data.boosts.bankedMatches, 0)
end)
