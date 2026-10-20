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

T.suite("training: TP, stamina, keepie-uppies and level costs")

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

local Juggle = T.load("shared/Juggle")

local BOUNCE = Config.Training.juggleBounceSeconds
local WINDOW = Config.Training.juggleWindow

-- A round whose first ball leaves the foot at 100 (the ball is at the foot at 100 + n x BOUNCE): it was
-- created `juggleLeadSeconds` earlier, for the "get ready" time.
local function round()
	return Juggle.new(100 - Config.Training.juggleLeadSeconds)
end

local function beat(n)
	return 100 + n * BOUNCE
end

T.test("a tap on the beat keeps the ball up and grows the combo", function()
	local state = round()
	T.eq(Juggle.press(state, beat(1)), "hit")
	T.eq(state.combo, 1)
	T.eq(Juggle.press(state, beat(2) + WINDOW * 0.9), "hit")
	T.eq(state.combo, 2)
	T.eq(state.hits, 2)
	T.eq(state.bestCombo, 2)
end)

T.test("the edges of the window count, just outside it does not", function()
	T.eq(Juggle.press(round(), beat(1) - WINDOW + 1e-6), "hit")
	T.eq(Juggle.press(round(), beat(1) + WINDOW - 1e-6), "hit")
	T.eq(Juggle.press(round(), beat(1) - WINDOW - 0.02), "miss")
end)

T.test("a tap while the ball is in the air breaks the combo and drops the ball", function()
	local state = round()
	Juggle.press(state, beat(1))
	Juggle.press(state, beat(2))
	T.eq(state.combo, 2)
	T.eq(Juggle.press(state, beat(2) + BOUNCE * 0.5), "miss")
	T.eq(state.combo, 0)
	T.eq(state.phase, "cooldown")
	T.eq(Juggle.press(state, beat(2) + BOUNCE * 0.5 + 0.1), "ignored") -- nothing while the ball is down
	T.eq(state.hits, 2) -- the touches before it still count
end)

T.test("a second tap on the same beat is ignored, not a miss", function()
	local state = round()
	T.eq(Juggle.press(state, beat(1)), "hit")
	T.eq(Juggle.press(state, beat(1) + 0.03), "ignored")
	T.eq(state.combo, 1)
	T.eq(state.phase, "running")
end)

T.test("a ball that is not touched drops, and the ball starts again after the cooldown", function()
	local state = round()
	Juggle.press(state, beat(1))
	local events = Juggle.normalize(state, beat(2) + WINDOW + 0.01)
	T.eq(#events, 1)
	T.eq(events[1].kind, "drop")
	T.eq(state.combo, 0)
	T.eq(state.phase, "cooldown")
	local back = beat(2) + WINDOW + Config.Training.juggleCooldownSeconds
	Juggle.normalize(state, back + 0.01)
	T.eq(state.phase, "running")
	T.near(state.startedAt, back, 1e-9)
	T.eq(state.lastIndex, 0)
	T.eq(Juggle.press(state, back + BOUNCE), "hit") -- the beat counts from the new start
end)

T.test(
	"the round ends after its time with a medal, and the next one starts after the pause",
	function()
		local state = round()
		for n = 1, 25 do
			T.eq(Juggle.press(state, beat(n)), "hit")
		end
		local events = Juggle.normalize(state, 100 + Config.Training.juggleRoundSeconds + 0.01)
		-- The player stopped tapping after 25 touches: the ball dropped (more than once) before the end.
		local last = events[#events]
		T.eq(events[1].kind, "drop")
		T.eq(last.kind, "round")
		T.eq(last.hits, 25)
		T.eq(last.bestCombo, 25)
		T.eq(last.medal, 2) -- silver from 22 touches
		T.eq(state.phase, "finished")
		T.eq(Juggle.press(state, 100 + Config.Training.juggleRoundSeconds + 1), "ignored")
		local nextStart = 100
			+ Config.Training.juggleRoundSeconds
			+ Config.Training.juggleRoundPauseSeconds
			+ Config.Training.juggleLeadSeconds
		Juggle.normalize(state, nextStart + 0.1)
		T.eq(state.phase, "running")
		T.eq(state.hits, 0)
		T.eq(state.combo, 0)
		T.near(state.startedAt, nextStart, 1e-9)
	end
)

T.test("medals: none, bronze, silver, gold", function()
	local medals = Config.Training.juggleMedals
	T.eq(Juggle.medal(medals.bronze - 1), 0)
	T.eq(Juggle.medal(medals.bronze), 1)
	T.eq(Juggle.medal(medals.silver), 2)
	T.eq(Juggle.medal(medals.gold), 3)
	T.eq(Juggle.medal(medals.gold + 5), 3)
end)

T.test("the ball is at the foot on the beat and highest halfway between", function()
	local state = round()
	T.near(Juggle.height(state, beat(1)), 0, 1e-9)
	T.near(Juggle.height(state, 100 + BOUNCE * 0.5), 1, 1e-9)
	T.near(Juggle.height(state, 100 + BOUNCE * 1.5), 1, 1e-9)
end)

T.test("a long gap is caught up: drops, then rounds, without looping for ever", function()
	local state = round()
	local events = Juggle.normalize(state, 100 + 100000)
	T.truthy(#events >= 1 and #events <= 64)
end)

T.test(
	"a clean touch pays the base TP plus a little per combo step, up to the combo cap",
	function()
		local data, carry = fresh()
		local training = Config.Training
		T.near(
			Training.gamePay(data, carry, 1, 0),
			training.juggleBaseTp + training.juggleComboTp,
			1e-9
		)
		local maxPay = training.juggleBaseTp + training.juggleComboTp * training.juggleComboMax
		T.near(Training.gamePay(data, carry, 50, 1), maxPay, 1e-9) -- the combo stops counting at the cap
		T.eq(Training.gamePay(data, carry, 0, 2), 0)
	end
)

T.test("the keepie-uppies pay nothing without stamina", function()
	local data, carry = fresh()
	data.staminaLeft = 0
	T.eq(Training.gamePay(data, carry, 5, 0), 0)
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
		paid += Training.gamePay(data, carry, 10, index * 0.1) -- 200 touches in 20 seconds
	end
	T.near(paid, room, 1e-9)
	T.eq(Training.gamePay(data, carry, 10, 21), 0)
	T.truthy(Training.gamePay(data, carry, 10, 85) > 0, "a minute later the cap has room again")
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

-- The dribble run ---------------------------------------------------------------------------------

local Dribble = T.load("shared/Dribble")

local ROW = Config.Training.dribbleRowSeconds
local GRACE = Config.Training.dribbleGraceSeconds

-- A run whose first row reaches the player at 100 + ROW (it was created `dribbleLeadSeconds` earlier).
local function run()
	return Dribble.new(100 - Config.Training.dribbleLeadSeconds)
end

local function rowAt(n)
	return 100 + n * ROW
end

-- The rows of a run that start at 100, and the lane that is free in every one of them.
local function freeLane(row)
	local blocked = Dribble.blocked(100, row)
	for lane = 1, 3 do
		if not blocked[lane] then
			return lane
		end
	end
	return 2
end

T.test("every row leaves at least one way through, and some rows are wide", function()
	local wide = 0
	for index = 1, 300 do
		local blocked = Dribble.blocked(100, index)
		local count = 0
		for lane = 1, 3 do
			if blocked[lane] then
				count += 1
			end
		end
		T.truthy(count == 1 or count == 2, "row " .. index .. " blocks " .. count)
		if count == 2 then
			wide += 1
		end
	end
	T.truthy(wide > 60 and wide < 140, "about one row in three is wide, got " .. wide)
	-- The rows come from the start time alone.
	local function show(blocked)
		return tostring(blocked[1]) .. tostring(blocked[2]) .. tostring(blocked[3])
	end
	T.eq(show(Dribble.blocked(500, 7)), show(Dribble.blocked(500, 7)))
end)

T.test("standing in a free lane passes the row and grows the combo", function()
	local state = run()
	local lane = freeLane(1)
	local now = rowAt(1) - 0.5
	-- Go to the free lane in time (one or two steps from the middle).
	while Dribble.lane(state) ~= lane do
		T.eq(Dribble.move(state, now, if lane < Dribble.lane(state) then -1 else 1, now), true)
	end
	local events = Dribble.normalize(state, rowAt(1) + GRACE + 0.01)
	T.eq(#events, 1)
	T.eq(events[1].kind, "pass")
	T.eq(state.passes, 1)
	T.eq(state.combo, 1)
end)

T.test("a cone breaks the combo, the player stumbles and the rows during it are skipped", function()
	local state = run()
	-- Find a row that blocks the middle lane (where the player stands).
	local blockedRow = 0
	for index = 2, 40 do
		if Dribble.blocked(state.startedAt, index)[2] then
			blockedRow = index
			break
		end
	end
	T.truthy(blockedRow > 0)
	state.combo = 4
	state.lastRow = blockedRow - 1 -- the rows before were judged
	local events = Dribble.normalize(state, rowAt(blockedRow) + GRACE + 0.01)
	T.eq(events[#events].kind, "stumble")
	T.eq(state.combo, 0)
	T.eq(state.phase, "stumble")
	-- The next row comes inside the stumble: it is skipped, not judged.
	local passesBefore = state.passes
	Dribble.normalize(state, rowAt(blockedRow + 1) + GRACE + 0.01)
	T.eq(state.passes, passesBefore)
	T.eq(state.lastRow, blockedRow + 1)
end)

T.test(
	"a move stamped a little in the past still counts for the next row, a late one does not",
	function()
		local state = run()
		local now = rowAt(3) + 0.05 -- row 3 just passed, still inside the grace window
		local lane = Dribble.lane(state)
		T.eq(Dribble.move(state, now, 1, now - 0.5), true) -- the stamp is clamped to the grace window
		local move = state.moves[#state.moves]
		T.near(move.at, now - GRACE, 1e-9)
		T.eq(Dribble.laneAt(state, now - GRACE - 0.01), lane) -- rows before the window keep the old lane
		T.eq(Dribble.laneAt(state, now), lane + 1)
	end
)

T.test(
	"a move cannot change the lane past the edges, nor while stumbling or after the round",
	function()
		local state = run()
		T.eq(Dribble.move(state, 100, -1, 100), true) -- middle to left
		T.eq(Dribble.move(state, 100, -1, 100), false) -- already at the left edge
		state.phase = "finished"
		state.finishedAt = 1e9
		T.eq(Dribble.move(state, 101, 1, 101), false)
	end
)

T.test("the round ends with a medal and the next round starts after the pause", function()
	local state = run()
	-- Play it perfectly: stand in a free lane before every row.
	for row = 1, 33 do
		local lane = freeLane(row)
		while Dribble.lane(state) ~= lane do
			Dribble.move(
				state,
				rowAt(row) - 0.4,
				if lane < Dribble.lane(state) then -1 else 1,
				rowAt(row) - 0.4
			)
		end
		Dribble.normalize(state, rowAt(row) + GRACE + 0.001)
	end
	local events =
		Dribble.normalize(state, 100 + Config.Training.dribbleRoundSeconds + GRACE + 0.01)
	local last = events[#events]
	T.eq(last.kind, "round")
	T.eq(last.passes, state.passes)
	T.truthy(
		state.passes >= 29,
		"a perfect round should pass nearly every row, got " .. state.passes
	)
	T.eq(last.medal, Dribble.medal(state.passes))
	T.eq(state.phase, "finished")
	local nextStart = 100
		+ Config.Training.dribbleRoundSeconds
		+ Config.Training.dribbleRoundPauseSeconds
		+ Config.Training.dribbleLeadSeconds
	Dribble.normalize(state, nextStart + 0.1)
	T.eq(state.phase, "running")
	T.eq(state.passes, 0)
	T.near(state.startedAt, nextStart, 1e-9)
end)

T.test("dribble medals: none, bronze, silver, gold", function()
	local medals = Config.Training.dribbleMedals
	T.eq(Dribble.medal(medals.bronze - 1), 0)
	T.eq(Dribble.medal(medals.bronze), 1)
	T.eq(Dribble.medal(medals.silver), 2)
	T.eq(Dribble.medal(medals.gold), 3)
end)

T.test("a long gap in the dribble run is caught up without looping for ever", function()
	local state = run()
	local events = Dribble.normalize(state, 100 + 100000)
	T.truthy(#events >= 1 and #events <= 96)
end)
