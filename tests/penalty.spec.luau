--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Freekick = T.load("shared/Freekick")
local Penalty = T.load("shared/Penalty")

T.suite("daily penalty kicks (played like the breakaway's shot)")

local DAILY = Config.Daily
local FK = Config.Training
local T0 = 1000

-- The time after the start of the aim step when the reticle is at `x` across the goal.
local function timeAt(x: number): number
	local t = (x / FK.freekickAimRange) * FK.freekickAimSeconds / 2
	return if t < 0 then t + FK.freekickAimSeconds * 2 else t
end

-- Locks the reticle at `x`, then holds and releases at the sweet power. Returns the state.
local function shootAt(state, x: number)
	local lockAt = state.stageAt + timeAt(x)
	T.eq(Penalty.lock(state, lockAt, lockAt), true)
	local holdAt = lockAt + 0.2
	T.eq(Penalty.hold(state, holdAt, holdAt), true)
	local releaseAt = holdAt + FK.freekickPowerSweet * FK.freekickPowerSeconds
	T.eq(Penalty.release(state, releaseAt, releaseAt), true)
	return state
end

T.test("a visit starts with the reticle after the lead, or is done with no kicks left", function()
	local state = Penalty.new(T0, 3)
	T.eq(state.phase, "aim")
	T.eq(state.kick, 1)
	T.eq(state.kicksLeft, 3)
	T.near(state.stageAt, T0 + DAILY.penaltyLeadSeconds, 1e-9)
	T.eq(Penalty.new(T0, 0).phase, "done")
end)

T.test("a tap before the reticle moves is ignored; after, it locks the reticle", function()
	local state = Penalty.new(T0, 3)
	T.eq(Penalty.lock(state, T0, T0), false)
	local at = state.stageAt + 0.3
	local x, y = Freekick.aimAt(state, at)
	T.eq(Penalty.lock(state, at, at), true)
	T.eq(state.phase, "power")
	T.near(state.aimX, x, 1e-9)
	T.near(state.aimY, y, 1e-9)
end)

T.test("the release shoots, judged with the penalty keeper", function()
	local state = Penalty.new(T0, 3)
	shootAt(state, -0.7)
	T.eq(state.phase, "shot")
	T.eq(state.outcome, "goal")
	T.near(state.power, FK.freekickPowerSweet, 1e-6)

	local saved = Penalty.new(T0, 3)
	shootAt(saved, Penalty.KEEPER_X) -- straight at the keeper
	T.eq(saved.outcome, "saved")
end)

T.test("a release without a hold, or a tap during the film, does nothing", function()
	local state = Penalty.new(T0, 3)
	local at = state.stageAt + 0.1
	Penalty.lock(state, at, at)
	T.eq(Penalty.release(state, at + 0.1, at + 0.1), false)
	shootAt(Penalty.new(T0, 3), 0.5)
	local filming = shootAt(Penalty.new(T0, 3), 0.5)
	local during = filming.stageAt + 1
	T.eq(Penalty.lock(filming, during, during), false)
	T.eq(Penalty.hold(filming, during, during), false)
	T.eq(filming.phase, "shot")
end)

T.test("after the film the next kick comes, or the visit ends with no kick left", function()
	local state = shootAt(Penalty.new(T0, 3), 0.5)
	state.kicksLeft = 2
	local ended = Penalty.filmEnd(state)
	Penalty.normalize(state, ended - 0.01)
	T.eq(state.phase, "shot")
	Penalty.normalize(state, ended)
	T.eq(state.phase, "aim")
	T.eq(state.kick, 2)
	T.eq(state.outcome, "")
	T.near(state.stageAt, ended + DAILY.penaltyLeadSeconds, 1e-9)

	local last = shootAt(Penalty.new(T0, 1), 0.5)
	last.kicksLeft = 0
	Penalty.normalize(last, Penalty.filmEnd(last) + 5)
	T.eq(last.phase, "done")
end)

T.test("a stamp is never trusted in the future or more than the grace time in the past", function()
	local state = Penalty.new(T0, 3)
	local now = state.stageAt + 1
	Penalty.lock(state, now, now + 5) -- from the future: counts as now
	local x = Freekick.aimAt({ stageAt = now - 1 }, now)
	T.near(state.aimX, x, 1e-9)

	local old = Penalty.new(T0, 3)
	local later = old.stageAt + 1
	Penalty.lock(old, later, later - 10) -- far in the past: counts as the grace time ago
	T.near(
		old.aimX,
		(Freekick.aimAt({ stageAt = later - 1 }, later - FK.freekickGraceSeconds)),
		1e-9
	)

	local nan = Penalty.new(T0, 3)
	T.eq(Penalty.lock(nan, nan.stageAt + 0.5, 0 / 0), true)
end)

T.test("the keeper always stands in the middle of the goal", function()
	T.eq(Penalty.KEEPER_X, 0)
	-- A calm kick into either side scores; one at the middle is saved.
	for _, aimX in { -0.7, 0.7 } do
		T.eq(shootAt(Penalty.new(T0, 3), aimX).outcome, "goal")
	end
	T.eq(shootAt(Penalty.new(T0, 3), 0).outcome, "saved")
end)

T.test("a calm low kick is saved inside the keeper's reach and scores just outside it", function()
	local reach = DAILY.penaltyKeeperReach
	local function judge(aimX: number): string
		return Freekick.judge(Penalty.KEEPER_X, 1, aimX, 0.4, FK.freekickPowerSweet, reach)
	end
	for _, side in { -1, 1 } do
		T.eq(judge(side * (reach - 0.05)), "saved")
		T.eq(judge(side * (reach + 0.05)), "goal")
	end
end)
