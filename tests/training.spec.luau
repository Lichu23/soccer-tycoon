--!nocheck
local T = require("./framework")
local Actions = T.load("server/Actions")
local Config = T.load("shared/Config")
local Formulas = T.load("shared/Formulas")
local PadInfo = T.load("shared/PadInfo")
local ProfileSchema = T.load("server/ProfileSchema")
local Progress = T.load("shared/Progress")
local Roster = T.load("shared/Roster")
local Training = T.load("server/Training")

T.suite("training: TP, stamina, keepie-uppies, free kicks and level costs")

local MAX = Config.Training.staminaSeconds

local function fresh()
	local data = ProfileSchema.newProfile()
	return data, Training.newCarry()
end

local function ownFloor(data, floor)
	for _, def in Config.Players do
		if def.floor == floor then
			Roster.add(data, def.id)
		end
	end
end

-- Runs `seconds` of training in 0.25 s steps like the server loop does.
local function train(data, carry, seconds, training)
	local paid = 0
	for _ = 1, math.floor(seconds / 0.25 + 0.5) do
		paid += Training.step(data, carry, 0.25, training)
	end
	return paid
end

T.test("standing on the pad pays 20 TP per minute", function()
	local data, carry = fresh()
	local paid = train(data, carry, 60, true)
	T.eq(paid, 20)
	T.eq(data.tp, 20)
end)

T.test("Faster training raises the pad to 25, 30, 35 and 40 TP per minute", function()
	for level, rate in { 25, 30, 35, 40 } do
		local data, carry = fresh()
		data.storeLevels.gymRate = level
		T.eq(train(data, carry, 60, true), rate)
	end
	local boosted, carry = fresh()
	boosted.storeLevels.gymRate = 4
	boosted.boosts.tpBoostLeft = 600
	T.eq(train(boosted, carry, 60, true), 80) -- the x2 TP boost doubles the upgraded rate
	T.truthy(Config.Store.gymRate.values[4] < 50, "the skill games stay better than the machines")
end)

T.test(
	"Faster training is a cash upgrade from stadium tier 2, its pad says what comes next",
	function()
		local session = { data = ProfileSchema.newProfile() }
		local data = session.data
		data.cash = 10_000_000
		T.eq(Progress.storeStatus(data, "gymRate"), "locked")
		T.eq(PadInfo.describe("store", "gymRate", data).note, "Stadium Tier 2 needed")
		data.stadiumTier = 2
		T.eq(PadInfo.describe("store", "gymRate", data).note, "Next: 25 TP a minute")
		T.eq(Actions.buyStore(session, "gymRate", 0), true)
		T.eq(data.cash, 10_000_000 - 5_000)
		T.eq(Progress.idleTpPerMinute(data), 25)
		data.flags.milestones.first_match = 1 -- the gym opens after the first match
		T.eq(
			PadInfo.describe("training", "trainingTreadmill", data).note,
			"Stand here: 25 TP per minute"
		)
		T.eq(Actions.buyStore(session, "gymRate", 1), true)
		T.eq(Progress.idleTpPerMinute(data), 30)
		T.eq(select(2, Actions.buyStore(session, "gymRate", 2)), "cannotAfford") -- $50M
		data.storeLevels.gymRate = 4
		T.eq(PadInfo.describe("store", "gymRate", data).price, "MAX")
	end
)

T.test("a bought x2 TP boost doubles the pad and the skill games", function()
	local data, carry = fresh()
	data.boosts.tpBoostLeft = 600
	T.eq(train(data, carry, 60, true), 40)
	local gameData, gameCarry = fresh()
	gameData.boosts.tpBoostLeft = 600
	T.eq(Training.gamePay(gameData, gameCarry, 1, 0, false), 2)
	T.eq(Training.gamePay(gameData, gameCarry, 1, 0, true), 2)
end)

T.test("one full stamina session is 100 TP and then it stops", function()
	local data, carry = fresh()
	T.eq(train(data, carry, MAX, true), 100)
	T.eq(data.staminaLeft, 0)
	T.eq(train(data, carry, 120, true), 0) -- tired: nothing paid
	T.eq(data.tp, 100)
	T.eq(Training.hasStamina(data), false)
end)

T.test("a tired player does not refill while still standing on the pad", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	train(data, carry, 60, true)
	T.eq(data.staminaLeft, 0)
end)

T.test("away from the pad the stamina refills in about 5 minutes and never pays TP", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	T.eq(train(data, carry, 150, false), 0)
	T.near(data.staminaLeft, MAX / 2, 0.01)
	train(data, carry, 400, false)
	T.eq(data.staminaLeft, MAX) -- capped at the full bar
	T.eq(data.tp, 0)
end)

T.test("time offline refills the stamina but pays no TP", function()
	local data = fresh()
	data.staminaLeft = 0
	Training.refillAway(data, 60)
	T.near(data.staminaLeft, 60, 0.01)
	Training.refillAway(data, 3600)
	T.eq(data.staminaLeft, MAX)
	Training.refillAway(data, -50)
	T.eq(data.staminaLeft, MAX)
	T.eq(data.tp, 0)
end)

T.test("a step of zero or negative time does nothing", function()
	local data, carry = fresh()
	data.staminaLeft = 100
	T.eq(Training.step(data, carry, 0, true), 0)
	T.eq(Training.step(data, carry, -1, true), 0)
	T.eq(data.staminaLeft, 100)
end)

T.test("the fraction of a TP is carried, so slow steps lose nothing", function()
	local data, carry = fresh()
	for _ = 1, 600 do -- 60 s in 0.1 s steps
		Training.step(data, carry, 0.1, true)
	end
	T.eq(data.tp, 20)
end)

local Juggle = T.load("shared/Juggle")
local Freekick = T.load("shared/Freekick")

local WINDOW = Config.Training.juggleWindow

-- A streak whose first ball leaves the foot at 100: it was created `juggleLeadSeconds` earlier, for
-- the "get ready" time.
local function streak()
	return Juggle.new(100 - Config.Training.juggleLeadSeconds)
end

T.test("a tap on the beat keeps the ball up and grows the streak", function()
	local state = streak()
	T.eq(Juggle.press(state, Juggle.beatTime(state, 1)), "hit")
	T.eq(state.combo, 1)
	T.eq(Juggle.press(state, Juggle.beatTime(state, 2) + WINDOW * 0.9), "hit")
	T.eq(state.combo, 2)
	T.eq(state.phase, "running")
end)

T.test("the edges of the window count, a tap just before it ends the streak", function()
	local first = streak()
	T.eq(Juggle.press(first, Juggle.beatTime(first, 1) - WINDOW + 1e-6), "hit")
	local late = streak()
	T.eq(Juggle.press(late, Juggle.beatTime(late, 1) + WINDOW - 1e-6), "hit")
	local early = streak()
	local outcome, event = Juggle.press(early, Juggle.beatTime(early, 1) - WINDOW - 0.02)
	T.eq(outcome, "miss")
	T.eq(event.kind, "over")
	T.eq(early.phase, "over")
end)

T.test("a tap while the ball is in the air ends the streak with its length", function()
	local state = streak()
	Juggle.press(state, Juggle.beatTime(state, 1))
	Juggle.press(state, Juggle.beatTime(state, 2))
	local outcome, event = Juggle.press(state, Juggle.beatTime(state, 2) + Juggle.period(3) * 0.5)
	T.eq(outcome, "miss")
	T.eq(event.streak, 2)
	T.eq(event.medal, 0)
	T.eq(Juggle.press(state, state.overAt + 0.1), "ignored") -- nothing while the result shows
end)

T.test("a second tap on the same beat, or one in the get-ready time, is ignored", function()
	local state = streak()
	T.eq(Juggle.press(state, 99.5), "ignored")
	T.eq(Juggle.press(state, Juggle.beatTime(state, 1)), "hit")
	T.eq(Juggle.press(state, Juggle.beatTime(state, 1) + 0.03), "ignored")
	T.eq(state.combo, 1)
	T.eq(state.phase, "running")
end)

T.test(
	"a ball that is not touched ends the streak, and a new one starts after the result",
	function()
		local state = streak()
		Juggle.press(state, Juggle.beatTime(state, 1))
		local dropAt = Juggle.beatTime(state, 2) + WINDOW
		local events = Juggle.normalize(state, dropAt + 0.01)
		T.eq(#events, 1)
		T.eq(events[1].kind, "over")
		T.eq(events[1].streak, 1)
		T.eq(state.phase, "over")
		T.near(state.overAt, dropAt, 1e-9)
		local nextStart = dropAt
			+ Config.Training.juggleOverSeconds
			+ Config.Training.juggleLeadSeconds
		Juggle.normalize(state, nextStart - 0.5)
		T.eq(state.phase, "running")
		T.eq(state.combo, 0)
		T.near(state.startedAt, nextStart, 1e-9)
		T.eq(Juggle.press(state, Juggle.beatTime(state, 1)), "hit") -- the beats count from the new start
	end
)

T.test("the beat gets quicker with every touch, down to the floor", function()
	local training = Config.Training
	T.near(Juggle.period(1), training.juggleBounceSeconds, 1e-9)
	T.near(Juggle.period(2), training.juggleBounceSeconds - training.juggleBounceStep, 1e-9)
	T.near(Juggle.period(500), training.juggleBounceMin, 1e-9)
	local state = streak()
	for n = 1, 150 do
		local gap = Juggle.beatTime(state, n) - Juggle.beatTime(state, n - 1)
		T.near(gap, Juggle.period(n), 1e-9)
	end
end)

T.test("a perfect player keeps a long streak going and earns the gold medal", function()
	local state = streak()
	for n = 1, 120 do
		T.eq(Juggle.press(state, Juggle.beatTime(state, n)), "hit")
	end
	T.eq(state.combo, 120)
	T.eq(Juggle.medal(state.combo), 3)
end)

T.test("medals: none, bronze, silver, gold", function()
	local medals = Config.Training.juggleMedals
	T.eq(Juggle.medal(medals.bronze - 1), 0)
	T.eq(Juggle.medal(medals.bronze), 1)
	T.eq(Juggle.medal(medals.silver), 2)
	T.eq(Juggle.medal(medals.gold), 3)
	T.eq(Juggle.medal(medals.gold + 5), 3)
end)

T.test("the ball is at the foot on the beat and highest halfway between", function()
	local state = streak()
	for _, n in { 1, 2, 30, 80 } do
		local beat = Juggle.beatTime(state, n)
		T.near(Juggle.height(state, beat), 0, 1e-6)
		T.eq(Juggle.beatAt(state, beat - 0.01), n)
		T.eq(Juggle.beatAt(state, beat + 0.01), n + 1)
		T.near(Juggle.height(state, beat - Juggle.period(n) / 2), 1, 1e-6)
	end
	T.eq(Juggle.height(state, 99), 0) -- resting on the foot before the first ball
end)

T.test("a long gap is caught up without looping for ever", function()
	local state = streak()
	local events = Juggle.normalize(state, 100 + 100000)
	T.truthy(#events >= 1 and #events <= 64)
end)

T.test("a clean touch pays by its place in the streak: 1 TP, then less in long streaks", function()
	T.eq(Juggle.tpFor(1), 1)
	T.eq(Juggle.tpFor(40), 1)
	T.eq(Juggle.tpFor(41), 0.5)
	T.eq(Juggle.tpFor(110), 0.5)
	T.eq(Juggle.tpFor(111), 0.3)
	T.eq(Juggle.tpFor(210), 0.3)
	T.eq(Juggle.tpFor(211), 0.2)
	T.eq(Juggle.tpFor(340), 0.2)
	T.eq(Juggle.tpFor(341), Config.Training.juggleTpFloor)
	T.eq(Juggle.tpFor(100000), Config.Training.juggleTpFloor)
	local total = 0
	for combo = 1, 40 do
		total += Juggle.tpFor(combo)
	end
	T.eq(total, 40)
	local last = math.huge
	for _, tier in Config.Training.juggleTpTiers do
		T.truthy(tier.tp < last, "every tier pays less than the one before")
		last = tier.tp
	end
	T.truthy(Config.Training.juggleTpFloor > 0 and Config.Training.juggleTpFloor < last)
end)

T.test("the keepie-uppies pay every touch with no cap per minute", function()
	local data, carry = fresh()
	local paid = 0
	for combo = 1, 120 do
		paid += Training.gamePay(data, carry, Juggle.tpFor(combo), combo * 0.5, false) -- one minute
	end
	T.near(paid, 40 + 70 * 0.5 + 10 * 0.3, 1e-9)
	T.eq(#carry.payLog, 0, "the keepie-uppies leave the breakaway's cap alone")
	T.eq(Training.gamePay(data, carry, 0, 61, false), 0)
end)

T.test("the skill games pay nothing without stamina", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	T.eq(Training.gamePay(data, carry, Juggle.tpFor(5), 0, false), 0)
	T.eq(Training.gamePay(data, carry, Freekick.tpFor(1), 0, true), 0)
end)

T.test("a skill station only pays what the game pays: no idle TP there", function()
	local data, carry = fresh()
	for _ = 1, 240 do -- 60 s in 0.25 s steps
		Training.step(data, carry, 0.25, true, false)
	end
	T.eq(data.tp, 0)
	T.truthy(data.staminaLeft < Config.Training.staminaSeconds, "stamina still drains")
end)

T.test("the breakaway's pay is capped per minute, and room comes back later", function()
	local data, carry = fresh()
	local room = Config.Training.freekickTpPerMinuteMax
	local paid = 0
	for index = 1, 200 do
		paid += Training.gamePay(data, carry, Freekick.tpFor(10), index * 0.1, true) -- 200 goals in 20 seconds
	end
	T.near(paid, room, 1e-9)
	T.eq(Training.gamePay(data, carry, Freekick.tpFor(10), 21, true), 0)
	T.truthy(
		Training.gamePay(data, carry, Freekick.tpFor(10), 85, true) > 0,
		"a minute later the cap has room again"
	)
end)

T.test("level costs: base x level x rarity factor, 600 TP for a Common to level 5", function()
	T.eq(Formulas.totalLevelCost("Common", 5), 600)
	T.eq(Formulas.levelCost("Legend", 25), 40 * 25 * 5)
end)

T.test("training and the level-up pads open when floor 1 is complete", function()
	local data = ProfileSchema.newProfile()
	T.eq(Progress.trainingUnlocked(data), false)
	ownFloor(data, 1)
	T.eq(Progress.trainingUnlocked(data), true)
end)

T.test("training also opens with the very first match", function()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	T.eq(Progress.trainingUnlocked(data), false) -- a player is not enough
	data.flags.milestones["first_match"] = 1000
	T.eq(Progress.trainingUnlocked(data), true)
	-- The snapshot the client gets carries only the milestone, and that is enough too.
	local snapshot = { players = {}, flags = { milestones = { first_match = 1000 } } }
	T.eq(Progress.trainingUnlocked(snapshot), true)
end)

T.test("level status: not owned, locked, cannot afford, ready, maxed", function()
	local data = ProfileSchema.newProfile()
	T.eq(Progress.levelStatus(data, "rashford"), "notOwned")
	Roster.add(data, "rashford")
	T.eq(Progress.levelStatus(data, "rashford"), "locked") -- floor 1 not complete yet
	ownFloor(data, 1)
	T.eq(Progress.levelStatus(data, "rashford"), "cannotAfford")
	data.tp = 40
	T.eq(Progress.levelStatus(data, "rashford"), "ready")
	data.players.rashford.level = Formulas.levelCap(Config.PlayersById.rashford.rarity)
	T.eq(Progress.levelStatus(data, "rashford"), "maxed")
	T.eq(Progress.levelCost(data, "rashford"), nil)
end)

T.test("levelling up spends the exact TP and adds one level", function()
	local session = { data = ProfileSchema.newProfile() }
	ownFloor(session.data, 1)
	session.data.tp = 100
	local ok = Actions.levelUp(session, "grealish", 0)
	T.eq(ok, true)
	T.eq(session.data.players.grealish.level, 1)
	T.eq(session.data.tp, 60)
	local ok2, why = Actions.levelUp(session, "grealish", 1)
	T.eq(ok2, false) -- level 2 costs 80 TP but only 60 are left
	T.eq(why, "cannotAfford")
end)

T.test("the first player's levels are cheap: the level-up tutorial", function()
	local data = ProfileSchema.newProfile()
	ownFloor(data, 1)
	local costs = {}
	for level = 0, 4 do
		data.players.rashford.level = level
		table.insert(costs, Progress.levelCost(data, "rashford"))
	end
	T.deepEq(costs, { 5, 10, 20, 40, 50 })
	data.players.rashford.level = 0
	data.tp = 5
	T.eq(Progress.levelStatus(data, "rashford"), "ready")
end)

T.test("a level-up that cannot be afforded or is stale changes nothing", function()
	local session = { data = ProfileSchema.newProfile() }
	ownFloor(session.data, 1)
	session.data.tp = 39
	local ok, why = Actions.levelUp(session, "grealish", 0)
	T.eq(ok, false)
	T.eq(why, "cannotAfford")
	session.data.tp = 500
	local stale, reason = Actions.levelUp(session, "grealish", 3)
	T.eq(stale, false)
	T.eq(reason, "stale")
	T.eq(session.data.tp, 500)
	T.eq(session.data.players.grealish.level, 0)
	local notOwned, why3 = Actions.levelUp(session, "pele", 0)
	T.eq(notOwned, false)
	T.eq(why3, "notOwned")
end)

T.test("a level raises the income by 3% of the base", function()
	local data = ProfileSchema.newProfile()
	ownFloor(data, 1)
	local before = Roster.income(data, "rashford")
	data.players.rashford.level = 1
	T.near(Roster.income(data, "rashford"), before * 1.03, 1e-9)
end)

T.test("the level-up pad shows the TP cost, the level and the bench", function()
	local data = ProfileSchema.newProfile()
	ownFloor(data, 1)
	data.tp = 1000
	local def = Config.PlayersById.rashford
	local info = PadInfo.describe("player", "rashford", data)
	T.eq(info.state, "ready")
	T.eq(info.price, "5 TP") -- the tutorial player (Config.Training.levelCostOverrides)
	T.truthy(string.find(info.note, "Lv 0/", 1, true) ~= nil)
	-- Rashford earns least, so with 10 owned players he is on the bench at tier 1.
	T.eq(table.find(Roster.field(data), "rashford"), nil)
	T.truthy(string.find(info.note, "on the bench", 1, true) ~= nil)
	local starter = Roster.field(data)[1]
	local starterInfo = PadInfo.describe("player", starter, data)
	T.truthy(string.find(starterInfo.note, "+3%", 1, true) ~= nil)
	data.tp = 4
	T.eq(PadInfo.describe("player", "rashford", data).state, "cannotAfford")
	data.players.rashford.level = Formulas.levelCap(def.rarity)
	T.eq(PadInfo.describe("player", "rashford", data).price, "MAX")
end)

T.test("before floor 1 is complete an owned player's pad still says OWNED", function()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	T.eq(PadInfo.describe("player", "rashford", data).price, "OWNED")
end)

-- The 1v1 breakaway (the free-kick spot) ----------------------------------------------------------------

local FK = Config.Training
local KEEPER = -0.2 -- the keeper leaning left

local function judge(aimX, aimY, power, kick)
	return Freekick.judge(KEEPER, kick or 1, aimX, aimY, power)
end

-- The time after the aim step starts when the reticle is at `x` going right from the middle.
local function aimTime(x)
	local t = (x / FK.freekickAimRange) * FK.freekickAimSeconds / 2
	return if t < 0 then t + FK.freekickAimSeconds * 2 else t
end

T.test(
	"a breakaway: the move shows after the through-ball, the reticle and the meter sweep",
	function()
		local state = Freekick.new(100)
		T.eq(state.phase, "dribble")
		T.near(state.stageAt, 100 + FK.freekickLeadSeconds, 1e-9)
		T.eq(state.move, Freekick.setup(100, 1).move)
		-- The reticle starts in the middle of the goal at half height and glides to each side.
		local x, y = Freekick.aimAt(state, state.stageAt)
		T.near(x, 0, 1e-9)
		T.near(y, (FK.freekickAimLow + FK.freekickAimHigh) / 2, 1e-9)
		x = Freekick.aimAt(state, state.stageAt + FK.freekickAimSeconds / 2)
		T.near(x, FK.freekickAimRange, 1e-9)
		x = Freekick.aimAt(state, state.stageAt + FK.freekickAimSeconds * 1.5)
		T.near(x, -FK.freekickAimRange, 1e-9)
		-- The meter fills from the hold, then empties.
		state.holdAt = 50
		T.near(Freekick.powerAt(state, 50), 0, 1e-9)
		T.near(Freekick.powerAt(state, 50 + FK.freekickPowerSeconds), 1, 1e-9)
		T.near(Freekick.powerAt(state, 50 + FK.freekickPowerSeconds * 1.5), 0.5, 1e-9)
	end
)

T.test("a breakaway goes move, aim, hold and release, then the film plays", function()
	local state = Freekick.new(100)
	local start = state.stageAt
	T.eq(Freekick.move(state, start - 0.3, state.move, start - 0.3), "ignored") -- not shown yet
	T.eq(Freekick.lock(state, start, start), false) -- not the aim step yet
	T.eq(Freekick.move(state, start + 0.4, state.move, start + 0.4), "beat")
	T.eq(state.phase, "aim")
	-- The dribble film plays first: the aim starts when it ends, and a tap during it is ignored.
	local dribble = FK.freekickDribbleSeconds
	T.near(state.stageAt, start + 0.4 + dribble, 1e-9)
	T.eq(Freekick.dribbling(state, start + 0.5), true)
	T.near(Freekick.filmTime(state, start + 0.5) :: number, 0.1, 1e-9)
	T.eq(Freekick.lock(state, start + 1, start + 1), false)
	T.eq(Freekick.dribbling(state, state.stageAt), false)
	T.eq(Freekick.filmTime(state, state.stageAt), nil)
	T.eq(Freekick.strike(state, start + 0.5, start + 0.5), false) -- not the power step yet
	local lockAt = state.stageAt + aimTime(-0.8)
	T.eq(Freekick.lock(state, lockAt, lockAt), true)
	T.near(state.aimX, -0.8, 1e-9)
	T.eq(state.phase, "power")
	T.near(state.holdAt, lockAt + FK.freekickPowerDelay, 1e-9) -- the meter moves a moment later
	T.eq(Freekick.strike(state, lockAt + 0.1, lockAt + 0.1), false) -- a double tap does not shoot
	T.eq(state.phase, "power")
	local strikeAt = state.holdAt + FK.freekickPowerSeconds * 0.7
	T.eq(Freekick.strike(state, strikeAt, strikeAt), true)
	T.near(state.power, 0.7, 1e-9)
	T.eq(state.phase, "shot")
	T.truthy(state.outcome ~= "")
	-- The film after the shot starts past the dribble, at the strike.
	T.near(Freekick.filmTime(state, strikeAt) :: number, dribble, 1e-9)
end)

T.test("the wrong move, or the right one too late, loses the ball", function()
	local state = Freekick.new(100)
	local wrong = state.move % 3 + 1
	T.eq(Freekick.move(state, state.stageAt + 0.2, wrong, state.stageAt + 0.2), "tackled")
	T.eq(state.phase, "shot")
	T.eq(state.outcome, "tackled")
	T.eq(state.streak, 0)

	local late = Freekick.new(100)
	local deadline = late.stageAt + Freekick.moveWindow(1)
	T.eq(Freekick.move(late, deadline + 0.1, late.move, deadline + 0.1), "tackled")

	-- Pressed just in time on a slow connection: the stamp counts inside the grace time.
	local slow = Freekick.new(100)
	local slowDeadline = slow.stageAt + Freekick.moveWindow(1)
	T.eq(Freekick.move(slow, slowDeadline + 0.15, slow.move, slowDeadline - 0.01), "beat")

	-- Never pressed: the defender wins it once the window and the grace time are gone.
	local idle = Freekick.new(100)
	local idleDeadline = idle.stageAt + Freekick.moveWindow(1)
	Freekick.normalize(idle, idleDeadline + FK.freekickGraceSeconds - 0.01)
	T.eq(idle.phase, "dribble")
	Freekick.normalize(idle, idleDeadline + FK.freekickGraceSeconds + 0.01)
	T.eq(idle.phase, "shot")
	T.eq(idle.outcome, "tackled")
	T.near(idle.stageAt, idleDeadline, 1e-9)
end)

T.test(
	"the shot clock starts with the aim; when it runs out the keeper smothers the ball",
	function()
		local state = Freekick.new(100)
		Freekick.move(state, state.stageAt + 0.2, state.move, state.stageAt + 0.2)
		T.near(state.shotBy, state.stageAt + Freekick.shotWindow(1), 1e-9)
		-- A lock after the clock (even inside the grace time) does not count.
		T.eq(Freekick.lock(state, state.shotBy + 0.1, state.shotBy + 0.1), false)
		Freekick.normalize(state, state.shotBy + FK.freekickGraceSeconds - 0.01)
		T.eq(state.phase, "aim")
		local shotBy = state.shotBy
		Freekick.normalize(state, shotBy + FK.freekickGraceSeconds + 0.01)
		T.eq(state.phase, "shot")
		T.eq(state.outcome, "late")
		T.eq(state.streak, 0)
		T.near(state.stageAt, shotBy, 1e-9)
		T.near(
			state.aimX,
			(Freekick.aimAt({ stageAt = shotBy - Freekick.shotWindow(1) }, shotBy)),
			1e-9
		)

		-- Locked in time but never shot: the clock still runs through the power step.
		local slow = Freekick.new(100)
		Freekick.move(slow, slow.stageAt + 0.2, slow.move, slow.stageAt + 0.2)
		T.eq(Freekick.lock(slow, slow.stageAt + 1, slow.stageAt + 1), true)
		T.eq(Freekick.strike(slow, slow.shotBy + 0.1, slow.shotBy + 0.1), false)
		Freekick.normalize(slow, slow.shotBy + 1)
		T.eq(slow.outcome, "late")

		-- A shot just before the clock on a slow connection counts.
		local just = Freekick.new(100)
		Freekick.move(just, just.stageAt + 0.2, just.move, just.stageAt + 0.2)
		Freekick.lock(just, just.stageAt + 1, just.stageAt + 1)
		T.eq(Freekick.strike(just, just.shotBy + 0.15, just.shotBy - 0.01), true)
		T.truthy(just.outcome ~= "late")
	end
)

T.test("the practice attack has no shot clock", function()
	local state = Freekick.new(100, true)
	Freekick.move(state, state.stageAt + 30, state.move, state.stageAt + 30)
	T.eq(state.shotBy, 0)
	Freekick.normalize(state, state.stageAt + 60)
	T.eq(state.phase, "aim")
end)

T.test("the shot clock shrinks with the streak to its floor at the gold medal", function()
	T.near(Freekick.shotWindow(1), FK.freekickShotSeconds, 1e-9)
	T.truthy(Freekick.shotWindow(5) < Freekick.shotWindow(1))
	T.near(Freekick.shotWindow(FK.freekickMedals.gold + 1), FK.freekickShotMin, 1e-9)
	T.near(Freekick.shotWindow(500), FK.freekickShotMin, 1e-9)
	-- The floor still leaves time to sweep the reticle across the goal and fill the meter once.
	T.truthy(
		FK.freekickShotMin
			>= FK.freekickAimSeconds + FK.freekickPowerDelay + FK.freekickPowerSeconds
	)
end)

T.test("the move window shrinks with the streak, never below the minimum", function()
	T.near(Freekick.moveWindow(1), FK.freekickMoveSeconds, 1e-9)
	T.truthy(Freekick.moveWindow(5) < Freekick.moveWindow(1))
	T.near(Freekick.moveWindow(500), FK.freekickMoveMin, 1e-9)
end)

T.test("an input stamped in the past counts only inside the grace time", function()
	local state = Freekick.new(100)
	Freekick.move(state, state.stageAt + 0.2, state.move, state.stageAt + 0.2)
	local start = state.stageAt
	local now = start + 0.9
	Freekick.lock(state, now, now - 5) -- far in the past: clamped to the grace window
	local x = Freekick.aimAt({ stageAt = start }, now - FK.freekickGraceSeconds)
	T.near(state.aimX, x, 1e-9)
	local bad = Freekick.new(100)
	Freekick.move(bad, bad.stageAt + 0.2, bad.move, bad.stageAt + 0.2)
	local badStart = bad.stageAt
	T.eq(Freekick.lock(bad, badStart + 0.5, 0 / 0), true) -- a NaN stamp counts as now
	T.near(bad.aimX, (Freekick.aimAt({ stageAt = badStart }, badStart + 0.5)), 1e-9)
end)

T.test(
	"a shot away from the keeper scores, one near him is saved, a soft one rolls to him",
	function()
		T.eq(judge(0.8, 0.4, 0.7), "goal")
		T.eq(judge(-0.25, 0.4, 0.7), "saved")
		T.eq(judge(0.8, 0.4, 0.2), "saved")
	end
)

T.test("too much power lifts the shot over the bar", function()
	T.eq(judge(0.8, 0.5, 0.7), "goal")
	T.eq(judge(0.8, 0.5, 1), "goal") -- 0.5 + 0.3 * 1.2 = 0.86: still under the bar
	T.eq(judge(0.8, 0.9, 1), "over")
	T.eq(judge(0.8, 0.75, 0.9), "bar")
end)

T.test("a shot past the post is wide, one on the post misses too", function()
	T.eq(judge(1.2, 0.4, 0.7), "wide")
	T.eq(judge(-0.98, 0.4, 0.7), "post")
end)

T.test("the keeper reaches further with every goal of the streak", function()
	T.eq(judge(0.3, 0.3, 0.7, 1), "goal")
	T.eq(judge(0.3, 0.3, 0.7, 11), "saved")
end)

T.test("the keeper stands on both sides and every move comes up", function()
	local left, right = 0, 0
	local moves = { 0, 0, 0 }
	for kick = 1, 300 do
		local setup = Freekick.setup(1234.5, kick)
		T.truthy(math.abs(setup.keeperX) <= FK.freekickKeeperSpread)
		if setup.keeperX < 0 then
			left += 1
		else
			right += 1
		end
		moves[setup.move] += 1
	end
	T.truthy(left > 80 and right > 80, "left " .. left .. ", right " .. right)
	for move = 1, 3 do
		T.truthy(moves[move] > 60, "move " .. move .. ": " .. moves[move])
	end
	T.eq(Freekick.setup(77, 3).keeperX, Freekick.setup(77, 3).keeperX)
end)

-- Plays one attack of `state`: the right move, the reticle locked at `aimX` and the meter stopped
-- at `power`.
local function attack(state, aimX, power)
	local start = state.stageAt
	Freekick.move(state, start + 0.2, state.move, start + 0.2)
	local lockAt = state.stageAt + aimTime(aimX)
	Freekick.lock(state, lockAt, lockAt)
	local strikeAt = state.holdAt + Freekick.powerSeconds(state.kick) * power
	Freekick.strike(state, strikeAt, strikeAt)
	return state.outcome
end

T.test("the power meter fills faster and its green zone narrows with every goal", function()
	T.near(Freekick.powerSeconds(1), FK.freekickPowerSeconds, 1e-9)
	T.near(Freekick.powerSeconds(2), FK.freekickPowerSeconds - FK.freekickPowerStep, 1e-9)
	T.near(Freekick.powerSeconds(200), FK.freekickPowerMin, 1e-9)
	local low, high = Freekick.goodZone(1)
	T.near(low, FK.freekickGoodLow, 1e-9)
	T.near(high, FK.freekickGoodHigh, 1e-9)
	-- The daily penalty's zone is its own, wider than the 1v1's first one.
	local penaltyLow, penaltyHigh = Freekick.penaltyZone()
	T.truthy(penaltyLow < low and penaltyHigh > high)
	local low2, high2 = Freekick.goodZone(2)
	T.truthy(low2 > low and high2 < high)
	local lowMax, highMin = Freekick.goodZone(200)
	T.near(lowMax, FK.freekickGoodLowMax, 1e-9)
	T.near(highMin, FK.freekickGoodHighMin, 1e-9)
	-- The sweet power stays green however long the streak.
	T.truthy(lowMax < FK.freekickPowerSweet and FK.freekickPowerSweet < highMin)
	-- The daily penalty (no kick given) keeps the first meter.
	T.near(Freekick.powerAt({ holdAt = 0 }, FK.freekickPowerSeconds), 1, 1e-9)
	T.near(Freekick.powerAt({ holdAt = 0 }, Freekick.powerSeconds(5), 5), 1, 1e-9)
end)

T.test("a free kick stopped outside the green zone misses", function()
	-- Late in a streak: a tap the first attack would take as green is now outside it.
	local function at(kick: number, power: number): string
		local state = Freekick.new(100)
		state.kick = kick
		state.stageAt = 100
		state.phase = "power"
		state.aimX, state.aimY = 0.85, 0.3
		state.holdAt = 100
		local strikeAt = 100 + Freekick.powerSeconds(kick) * power
		Freekick.strike(state, strikeAt, strikeAt)
		return state.outcome
	end
	local low, high = Freekick.goodZone(11)
	T.eq(at(11, low - 0.05), "saved") -- too soft: it rolls to the keeper
	T.eq(at(11, high + 0.02), "over") -- too hard: over the bar, though the reticle was low
	local firstLow = Freekick.goodZone(1)
	T.eq(at(1, firstLow + 0.15), "goal") -- the same aim, stopped on the first attack's green
end)

T.test("a goal brings the next attack, a miss ends the streak and a new one starts", function()
	local state = Freekick.new(100)
	-- Shoot into the corner away from the keeper every time.
	local function openCorner()
		return if Freekick.setup(state.seed, state.kick).keeperX > 0 then -0.85 else 0.85
	end
	T.eq(attack(state, openCorner(), 0.7), "goal")
	T.eq(state.streak, 1)
	local ended = state.stageAt + FK.freekickFilmSeconds
	Freekick.normalize(state, ended + 0.01)
	T.eq(state.phase, "dribble")
	T.eq(state.kick, 2)
	T.near(state.stageAt, ended + FK.freekickLeadSeconds, 1e-9)
	T.eq(state.move, Freekick.setup(state.seed, 2).move)
	T.eq(attack(state, openCorner(), 0.7), "goal")
	T.eq(state.streak, 2)
	Freekick.normalize(state, state.stageAt + FK.freekickFilmSeconds + 0.01)
	T.eq(attack(state, 1.2, 0.7), "wide")
	local missEnded = state.stageAt + FK.freekickFilmSeconds
	local events = Freekick.normalize(state, missEnded + 0.01)
	T.eq(#events, 1)
	T.eq(events[1].kind, "over")
	T.eq(events[1].streak, 2)
	T.eq(state.phase, "over")
	Freekick.normalize(state, missEnded + FK.freekickOverSeconds + 0.01)
	T.eq(state.phase, "dribble")
	T.eq(state.streak, 0)
	T.eq(state.kick, 1)
	T.near(state.seed, missEnded + FK.freekickOverSeconds, 1e-9)
end)

T.test("a lost dribble plays the short film", function()
	local state = Freekick.new(100)
	Freekick.move(state, state.stageAt + 0.2, state.move % 3 + 1, state.stageAt + 0.2)
	local ended = state.stageAt + FK.freekickTackleSeconds
	Freekick.normalize(state, ended - 0.01)
	T.eq(state.phase, "shot")
	Freekick.normalize(state, ended + 0.01)
	T.eq(state.phase, "over")
end)

T.test("breakaway medals and pay grow with the streak", function()
	local medals = FK.freekickMedals
	T.eq(Freekick.medal(medals.bronze - 1), 0)
	T.eq(Freekick.medal(medals.bronze), 1)
	T.eq(Freekick.medal(medals.silver), 2)
	T.eq(Freekick.medal(medals.gold), 3)
	T.near(Freekick.tpFor(1), FK.freekickBaseTp + FK.freekickStreakTp, 1e-9)
	T.near(Freekick.tpFor(99), FK.freekickBaseTp + FK.freekickStreakTp * FK.freekickStreakMax, 1e-9)
end)

T.test("a long gap in the breakaway is caught up without looping for ever", function()
	local state = Freekick.new(100)
	local events = Freekick.normalize(state, 100 + 100000)
	T.truthy(#events >= 1 and #events <= 16)
end)

T.test(
	"the level-up tutorial: the treadmill pays its first TP faster, only until the first level",
	function()
		local data, carry = fresh()
		data.flags.milestones.first_match = 1 -- training is open
		Roster.add(data, "rashford")
		T.eq(Progress.tutorialTraining(data), true)
		local seconds = Config.Training.tutorialTp / Config.Training.tutorialTpPerMinute * 60
		train(data, carry, seconds + 0.25, true)
		T.eq(data.tp, Config.Training.tutorialTp)
		T.eq(Progress.tutorialTraining(data), false) -- the TP are in: back to the usual rate
		local before = data.tp
		train(data, carry, 60, true)
		T.eq(data.tp - before, Config.Training.idleTpPerMinute)
	end
)

T.test(
	"the other stations open with the first level ever, and a New Season does not close them",
	function()
		local data = fresh()
		data.flags.milestones.first_match = 1
		Roster.add(data, "rashford")
		T.eq(PadInfo.describe("training", "trainingTreadmill", data).state, "info")
		T.eq(PadInfo.describe("training", "trainingKeepie", data).state, "locked")
		T.eq(PadInfo.describe("training", "trainingBench", data).state, "locked")
		data.players.rashford.level = 1
		T.eq(PadInfo.describe("training", "trainingKeepie", data).state, "info")
		data.players.rashford.level = 0 -- a New Season takes the level away; the milestone stays
		data.flags.milestones.first_level = 1
		T.eq(Progress.firstLevelDone(data), true)
		T.eq(PadInfo.describe("training", "trainingFreekick", data).state, "info")
	end
)

T.test("a tap during how-to-play skips it: the countdown starts at once", function()
	local state = Juggle.new(100 + Config.Training.juggleIntroSeconds)
	local lead = Config.Training.juggleLeadSeconds
	T.eq(Juggle.skipIntro(state, 100), true)
	T.eq(state.startedAt, 100 + lead)
	T.eq(Juggle.skipIntro(state, 100.5), false) -- the countdown itself is not skipped
	T.eq(state.startedAt, 100 + lead)
end)

T.test("the practice attack waits for its move and ignores a wrong key, until a goal", function()
	local state = Freekick.new(100, true)
	local start = state.stageAt
	local late = start + 30 -- far past any move window
	Freekick.normalize(state, late)
	T.eq(state.phase, "dribble") -- no tackle by time
	local wrong = state.move % 3 + 1
	T.eq(Freekick.move(state, late, wrong, late), "ignored")
	T.eq(state.phase, "dribble")
	T.eq(Freekick.move(state, late, state.move, late), "beat")

	-- A practice streak that scored nothing stays practice; the normal one keeps its window.
	local missed = Freekick.new(100, true)
	missed.phase, missed.outcome, missed.stageAt, missed.streak = "shot", "saved", 200, 0
	Freekick.normalize(missed, 200 + Freekick.filmSeconds("saved") + FK.freekickOverSeconds)
	T.eq(missed.practice, true)
	local scored = Freekick.new(100, true)
	scored.phase, scored.outcome, scored.stageAt, scored.kick, scored.streak =
		"shot", "saved", 200, 2, 1
	Freekick.normalize(scored, 200 + Freekick.filmSeconds("saved") + FK.freekickOverSeconds)
	T.eq(scored.practice, false)
	local normal = Freekick.new(100)
	Freekick.normalize(
		normal,
		normal.stageAt + Freekick.moveWindow(1) + FK.freekickGraceSeconds + 0.1
	)
	T.eq(normal.outcome, "tackled")
end)
