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

T.test("standing on the pad pays 10 TP per minute", function()
	local data, carry = fresh()
	local paid = train(data, carry, 60, true)
	T.eq(paid, 10)
	T.eq(data.tp, 10)
end)

T.test("a bought x2 TP boost doubles the pad and the skill games", function()
	local data, carry = fresh()
	data.boosts.tpBoostLeft = 600
	T.eq(train(data, carry, 60, true), 20)
	local gameData, gameCarry = fresh()
	gameData.boosts.tpBoostLeft = 600
	T.eq(Training.gamePay(gameData, gameCarry, 1, 0), 2)
end)

T.test("one full stamina session is 50 TP and then it stops", function()
	local data, carry = fresh()
	T.eq(train(data, carry, MAX, true), 50)
	T.eq(data.staminaLeft, 0)
	T.eq(train(data, carry, 120, true), 0) -- tired: nothing paid
	T.eq(data.tp, 50)
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
	T.eq(data.tp, 10)
end)

local Juggle = T.load("shared/Juggle")

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

T.test(
	"a clean touch pays the base TP plus a little per step of the streak, up to the cap",
	function()
		local data, carry = fresh()
		local training = Config.Training
		T.near(
			Training.gamePay(data, carry, Juggle.tpFor(1), 0),
			training.juggleBaseTp + training.juggleComboTp,
			1e-9
		)
		local maxPay = training.juggleBaseTp + training.juggleComboTp * training.juggleComboMax
		T.near(Training.gamePay(data, carry, Juggle.tpFor(50), 1), maxPay, 1e-9) -- the streak stops counting at the cap
		T.eq(Training.gamePay(data, carry, 0, 2), 0)
	end
)

T.test("the skill games pay nothing without stamina", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	T.eq(Training.gamePay(data, carry, Juggle.tpFor(5), 0), 0)
end)

T.test("a skill station only pays what the game pays: no idle TP there", function()
	local data, carry = fresh()
	for _ = 1, 240 do -- 60 s in 0.25 s steps
		Training.step(data, carry, 0.25, true, false)
	end
	T.eq(data.tp, 0)
	T.truthy(data.staminaLeft < Config.Training.staminaSeconds, "stamina still drains")
end)

T.test("the game part of the rate is capped per minute, and room comes back later", function()
	local data, carry = fresh()
	local room = Config.Training.juggleTpPerMinuteMax
	local paid = 0
	for index = 1, 200 do
		paid += Training.gamePay(data, carry, Juggle.tpFor(10), index * 0.1) -- 200 touches in 20 seconds
	end
	T.near(paid, room, 1e-9)
	T.eq(Training.gamePay(data, carry, Juggle.tpFor(10), 21), 0)
	T.truthy(
		Training.gamePay(data, carry, Juggle.tpFor(10), 85) > 0,
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

-- Free kicks -------------------------------------------------------------------------------------------

local Freekick = T.load("shared/Freekick")

local FK = Config.Training
-- The wall on the right, the keeper leaning left.
local SETUP = { wallX = 0.3, keeperX = -0.2 }

local function judge(power, contactX, contactY, aim, kick)
	return Freekick.judge(SETUP, kick or 1, power, contactX, contactY, aim)
end

T.test("a free kick: the power bar starts after the lead time and goes up and down", function()
	local state = Freekick.new(100)
	T.eq(state.phase, "power")
	T.near(state.stageAt, 100 + FK.freekickLeadSeconds, 1e-9)
	local start = state.stageAt
	T.near(Freekick.powerAt(state, start), 0, 1e-9)
	T.near(Freekick.powerAt(state, start + FK.freekickPowerSeconds), 1, 1e-9)
	T.near(Freekick.powerAt(state, start + FK.freekickPowerSeconds * 1.5), 0.5, 1e-9)
	T.near(Freekick.powerAt(state, start + FK.freekickPowerSeconds * 2), 0, 1e-9)
	-- The aim marker starts in the middle and sweeps to each side.
	T.near(Freekick.aimAt(state, start), 0, 1e-9)
	T.near(Freekick.aimAt(state, start + FK.freekickAimSeconds / 2), FK.freekickAimRange, 1e-9)
	T.near(Freekick.aimAt(state, start + FK.freekickAimSeconds * 1.5), -FK.freekickAimRange, 1e-9)
end)

T.test("a free kick goes power, contact, aim, then flies", function()
	local state = Freekick.new(100)
	local start = state.stageAt
	T.eq(Freekick.tap(state, start - 0.2, start - 0.2), "ignored") -- the bar has not started yet
	T.eq(Freekick.contact(state, start, 0, 0), false) -- not the contact step yet
	local powerTap = start + FK.freekickPowerSeconds * 0.8
	T.eq(Freekick.tap(state, powerTap, powerTap), "power")
	T.near(state.power, 0.8, 1e-9)
	T.eq(state.phase, "contact")
	T.eq(Freekick.tap(state, powerTap + 0.1, powerTap + 0.1), "ignored") -- the ball needs a tap first
	T.eq(Freekick.contact(state, powerTap + 0.5, 0.72, 0.96), true) -- outside the ball: pulled onto its edge
	T.near(state.contactX, 0.6, 1e-9)
	T.near(state.contactY, 0.8, 1e-9)
	T.eq(state.phase, "aim")
	local aimTap = powerTap + 1
	T.eq(Freekick.tap(state, aimTap, aimTap), "kick")
	T.eq(state.phase, "flight")
	T.truthy(state.outcome ~= "")
end)

T.test("a free kick tap stamped in the past counts only inside the grace time", function()
	local state = Freekick.new(100)
	local start = state.stageAt
	local now = start + 0.7
	Freekick.tap(state, now, now - 5) -- far in the past: clamped to the grace window
	T.near(state.power, Freekick.powerAt({ stageAt = start }, now - FK.freekickGraceSeconds), 1e-9)
	local other = Freekick.new(100)
	Freekick.tap(other, now, now + 5) -- in the future: clamped to now
	T.near(other.power, Freekick.powerAt({ stageAt = start }, now), 1e-9)
	local bad = Freekick.new(100)
	T.eq(Freekick.tap(bad, now, 0 / 0), "power") -- a NaN stamp counts as now
	T.near(bad.power, Freekick.powerAt({ stageAt = start }, now), 1e-9)
end)

T.test("a NaN contact point is refused", function()
	local state = Freekick.new(100)
	Freekick.tap(state, state.stageAt + 0.5, state.stageAt + 0.5)
	T.eq(Freekick.contact(state, state.stageAt + 0.6, 0 / 0, 0), false)
	T.eq(state.phase, "contact")
end)

T.test("a shot through the wall at the middle of the ball is blocked", function()
	T.eq(judge(0.75, 0, 0, 0.85), "wall")
end)

T.test(
	"a hit below the middle lifts the ball over the wall, too low sends it over the bar",
	function()
		T.eq(judge(0.75, 0, -0.3, 0.85), "goal")
		T.eq(judge(0.75, 0, -1, 0.85), "over")
		T.eq(judge(1, 0, -0.6, 0.85), "over") -- full power on top of it
	end
)

T.test("a hit on the side of the ball curls it round the wall", function()
	T.eq(judge(0.75, 0.8, 0, 0.9), "goal")
end)

T.test("a shot away from the wall beats the keeper in the corner, not near him", function()
	T.eq(judge(0.75, 0, 0, -0.85), "goal")
	T.eq(judge(0.75, 0, 0, -0.3), "saved")
	T.eq(judge(0.2, 0, 0, -0.85), "saved") -- too weak: it rolls to the keeper
end)

T.test("a shot past the post is wide, one on the post misses too", function()
	T.eq(judge(0.75, 0, 0, -1.2), "wide")
	T.eq(judge(0.75, 0, 0, -0.98), "post")
end)

T.test("the keeper reaches further with every goal of the streak", function()
	T.eq(judge(0.75, 0, 0, -0.7, 1), "goal")
	T.eq(judge(0.75, 0, 0, -0.7, 11), "saved")
end)

T.test("the wall and the keeper stand on opposite sides, both sides come up", function()
	local left, right = 0, 0
	for kick = 1, 200 do
		local setup = Freekick.setup(1234.5, kick)
		T.truthy(setup.wallX * setup.keeperX < 0, "kick " .. kick)
		T.truthy(math.abs(setup.wallX) <= 0.4 and math.abs(setup.keeperX) <= 0.27)
		if setup.wallX < 0 then
			left += 1
		else
			right += 1
		end
	end
	T.truthy(left > 50 and right > 50, "left " .. left .. ", right " .. right)
	T.eq(Freekick.setup(77, 3).wallX, Freekick.setup(77, 3).wallX)
end)

-- Plays one kick of `state` with these values (the taps land on the exact bar values asked for).
local function kick(state, power, contactX, contactY, aim)
	local start = state.stageAt
	local powerTap = start + FK.freekickPowerSeconds * power
	Freekick.tap(state, powerTap, powerTap)
	Freekick.contact(state, powerTap + 0.3, contactX, contactY)
	-- The aim marker is at `aim` this long after the aim step starts (going right from the middle).
	local stage = state.stageAt
	local toAim = (aim / FK.freekickAimRange) * FK.freekickAimSeconds / 2
	if toAim < 0 then
		toAim += FK.freekickAimSeconds * 2
	end
	Freekick.tap(state, stage + toAim, stage + toAim)
	return state.outcome
end

T.test("a goal brings the next kick, a miss ends the streak and a new one starts", function()
	local state = Freekick.new(100)
	-- Shoot into the corner away from the wall every time.
	local function openCorner()
		local setup = Freekick.setup(state.seed, state.kick)
		return if setup.wallX > 0 then -0.85 else 0.85
	end
	T.eq(kick(state, 0.75, 0, 0, openCorner()), "goal")
	T.eq(state.streak, 1)
	local landed = state.stageAt + FK.freekickFlightSeconds
	Freekick.normalize(state, landed + 0.01)
	T.eq(state.phase, "power")
	T.eq(state.kick, 2)
	T.near(state.stageAt, landed + FK.freekickLeadSeconds, 1e-9)
	T.eq(kick(state, 0.75, 0, 0, openCorner()), "goal")
	T.eq(state.streak, 2)
	Freekick.normalize(state, state.stageAt + FK.freekickFlightSeconds + 0.01)
	T.eq(kick(state, 0.75, 0, 0, openCorner() * 1.45), "wide")
	local missLanded = state.stageAt + FK.freekickFlightSeconds
	local events = Freekick.normalize(state, missLanded + 0.01)
	T.eq(#events, 1)
	T.eq(events[1].kind, "over")
	T.eq(events[1].streak, 2)
	T.eq(state.phase, "over")
	Freekick.normalize(state, missLanded + FK.freekickOverSeconds + 0.01)
	T.eq(state.phase, "power")
	T.eq(state.streak, 0)
	T.eq(state.kick, 1)
	T.near(state.seed, missLanded + FK.freekickOverSeconds, 1e-9)
end)

T.test("free kick medals and pay grow with the streak", function()
	local medals = FK.freekickMedals
	T.eq(Freekick.medal(medals.bronze - 1), 0)
	T.eq(Freekick.medal(medals.bronze), 1)
	T.eq(Freekick.medal(medals.silver), 2)
	T.eq(Freekick.medal(medals.gold), 3)
	T.near(Freekick.tpFor(1), FK.freekickBaseTp + FK.freekickStreakTp, 1e-9)
	T.near(Freekick.tpFor(99), FK.freekickBaseTp + FK.freekickStreakTp * FK.freekickStreakMax, 1e-9)
end)

T.test("a long gap in the free kicks is caught up without looping for ever", function()
	local state = Freekick.new(100)
	state.phase = "flight"
	state.outcome = "wall"
	local events = Freekick.normalize(state, 100 + 100000)
	T.truthy(#events >= 1 and #events <= 16)
end)
