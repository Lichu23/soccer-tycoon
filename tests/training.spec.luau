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

T.suite("training: TP, stamina, drill and level costs")

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

local Drill = T.load("shared/Drill")

local function runningDrill(now)
	local state = Drill.new()
	Drill.press(state, now) -- the first press starts the marker
	return state
end

T.test("the drill starts stopped and the first press starts the marker without paying", function()
	local state = Drill.new()
	T.eq(state.phase, "stopped")
	T.eq(Drill.press(state, 10), "start")
	T.eq(state.phase, "running")
	T.eq(Drill.position(state, 10), 0)
	local data, carry = fresh()
	T.eq(Training.drillPay(data, carry, "start", 10), 0)
end)

T.test("a sweep that reaches the end just starts the next one (no stop)", function()
	local sweep = Config.Training.drillSweepSeconds
	local state = runningDrill(100)
	T.near(Drill.position(state, 100 + sweep / 2), 0.5, 1e-9)
	Drill.normalize(state, 100 + sweep * 2.25)
	T.eq(state.phase, "running")
	T.near(Drill.position(state, 100 + sweep * 2.25), 0.25, 1e-6)
	-- an away player is simply in the middle of some sweep when they come back
	T.truthy(Drill.press(state, 100 + sweep * 50.5) ~= "ignored")
end)

-- A running drill whose marker is at `fraction` of the bar at time `now`.
local function markerAt(now, fraction)
	local state = Drill.new()
	state.phase = "running"
	state.startedAt = now - Config.Training.drillSweepSeconds * fraction
	return state
end

-- A time when the green zone is exactly in the middle of the bar.
local CENTERED = Config.Training.drillZonePeriodSeconds * 4

T.test("a press inside the green zone is a hit and the marker starts again at once", function()
	local state = markerAt(CENTERED, 0.5)
	T.eq(Drill.press(state, CENTERED), "hit")
	T.eq(state.phase, "running")
	T.eq(state.startedAt, CENTERED)
	T.eq(Drill.position(state, CENTERED), 0)
	-- and a second hit half a sweep later, without waiting for the end of the bar
	local later = CENTERED + Config.Training.drillSweepSeconds * 0.5
	T.near(Drill.position(state, later), 0.5, 1e-9)
end)

T.test("the green zone is small and a press outside it is a miss", function()
	local edge = Config.Training.drillWindow
	T.truthy(edge <= 0.1, "the zone is at most 20% of the bar")
	T.eq(Drill.press(markerAt(CENTERED, 0.5 + edge - 0.01), CENTERED), "hit")
	T.eq(Drill.press(markerAt(CENTERED, 0.5 - edge + 0.01), CENTERED), "hit")
	T.eq(Drill.press(markerAt(CENTERED, 0.5 + edge + 0.02), CENTERED), "miss")
	T.eq(Drill.press(markerAt(CENTERED, 0.05), CENTERED), "miss")
end)

T.test("the green zone drifts along the bar and never touches its sides", function()
	local edge = Config.Training.drillWindow
	local period = Config.Training.drillZonePeriodSeconds
	local lowest, highest = 1, 0
	for step = 0, 400 do
		local centre = Drill.zoneCenter(step * period / 100)
		lowest = math.min(lowest, centre - edge)
		highest = math.max(highest, centre + edge)
	end
	T.truthy(lowest > 0.03, "the zone stays off the left side")
	T.truthy(highest < 0.97, "the zone stays off the right side")
	T.truthy(highest - lowest > 0.6, "and it really moves")
	-- a marker in the middle of the bar misses when the zone has drifted away
	local drifted = CENTERED + period / 4 -- the zone is far to one side
	T.eq(Drill.press(markerAt(drifted, 0.5), drifted), "miss")
	-- but the same marker hits when it is where the zone is
	T.eq(Drill.press(markerAt(drifted, Drill.zoneCenter(drifted)), drifted), "hit")
end)

T.test(
	"a miss starts a cooldown: presses are ignored, then the marker restarts by itself",
	function()
		local cooldown = Config.Training.drillCooldownSeconds
		local state = runningDrill(0)
		T.eq(Drill.press(state, 0.1), "miss")
		T.eq(state.phase, "cooldown")
		T.eq(Drill.press(state, 0.1 + cooldown - 0.05), "ignored")
		Drill.normalize(state, 0.1 + cooldown + 0.3)
		T.eq(state.phase, "running")
		T.near(
			Drill.position(state, 0.1 + cooldown + 0.3),
			0.3 / Config.Training.drillSweepSeconds,
			1e-6
		)
	end
)

T.test("a hit pays 1 TP plus 0.3 and a miss pays 1 TP", function()
	local data, carry = fresh()
	T.near(Training.drillPay(data, carry, "hit", 0), 1.3, 1e-9)
	T.near(Training.drillPay(data, carry, "miss", 1), 1, 1e-9)
	T.eq(Training.drillPay(data, carry, "ignored", 2), 0)
	T.eq(data.tp, 2) -- 2.3 TP so far: 2 whole points, 0.3 carried
	T.near(carry.fraction, 0.3, 1e-9)
end)

T.test("the drill pays nothing without stamina", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	T.eq(Training.drillPay(data, carry, "hit", 0), 0)
	T.eq(data.tp, 0)
end)

T.test("the drill part of the rate is capped per minute, and room comes back later", function()
	local data, carry = fresh()
	local room = Config.Training.drillTpPerMinuteMax - Config.Training.idleTpPerMinute
	local paid = 0
	for index = 1, 100 do
		paid += Training.drillPay(data, carry, "hit", index * 0.1) -- 100 hits in 10 seconds
	end
	T.near(paid, room, 1e-9)
	T.eq(Training.drillPay(data, carry, "hit", 11), 0)
	T.truthy(Training.drillPay(data, carry, "hit", 75) > 0, "a minute later the cap has room again")
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
	local ok = Actions.levelUp(session, "rashford", 0)
	T.eq(ok, true)
	T.eq(session.data.players.rashford.level, 1)
	T.eq(session.data.tp, 60)
	local ok2, why = Actions.levelUp(session, "rashford", 1)
	T.eq(ok2, false) -- level 2 costs 80 TP but only 60 are left
	T.eq(why, "cannotAfford")
end)

T.test("a level-up that cannot be afforded or is stale changes nothing", function()
	local session = { data = ProfileSchema.newProfile() }
	ownFloor(session.data, 1)
	session.data.tp = 39
	local ok, why = Actions.levelUp(session, "rashford", 0)
	T.eq(ok, false)
	T.eq(why, "cannotAfford")
	session.data.tp = 500
	local stale, reason = Actions.levelUp(session, "rashford", 3)
	T.eq(stale, false)
	T.eq(reason, "stale")
	T.eq(session.data.tp, 500)
	T.eq(session.data.players.rashford.level, 0)
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
	T.eq(info.price, "40 TP")
	T.truthy(string.find(info.note, "Lv 0/", 1, true) ~= nil)
	-- Rashford earns least, so with 10 owned players he is on the bench at tier 1.
	T.eq(table.find(Roster.field(data), "rashford"), nil)
	T.truthy(string.find(info.note, "on the bench", 1, true) ~= nil)
	local starter = Roster.field(data)[1]
	local starterInfo = PadInfo.describe("player", starter, data)
	T.truthy(string.find(starterInfo.note, "+3%", 1, true) ~= nil)
	data.tp = 5
	T.eq(PadInfo.describe("player", "rashford", data).state, "cannotAfford")
	data.players.rashford.level = Formulas.levelCap(def.rarity)
	T.eq(PadInfo.describe("player", "rashford", data).price, "MAX")
end)

T.test("before floor 1 is complete an owned player's pad still says OWNED", function()
	local data = ProfileSchema.newProfile()
	Roster.add(data, "rashford")
	T.eq(PadInfo.describe("player", "rashford", data).price, "OWNED")
end)
