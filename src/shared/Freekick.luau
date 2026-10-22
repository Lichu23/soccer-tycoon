--!strict
-- The 1v1 breakaway at the free-kick spot of the Training Gym (docs/PLAN.md, Step 4), an endless
-- streak of goals. Every attack starts with a through-ball, then three quick inputs: a skill move
-- (left, right or step-over) shows and must be pressed in time to beat the defender; an aim reticle
-- glides over the goal mouth and a tap locks it; then the power meter fills and empties again by
-- itself and a second tap shoots (too soft rolls to the keeper, too hard lifts it over the bar). Then the client plays the attack as
-- a short film: the dribble, the strike in slow motion, the goal or the save. A goal adds to the
-- streak; a lost dribble or a shot that does not go in ends it, and the longest streak is kept.
-- Every goal makes the next attack harder: a shorter move window, a keeper who reaches further, and
-- a power meter that fills faster with a narrower green zone (a release outside it misses).
-- The moves, the reticle and the meter run on the server clock from the start of their step, so the
-- server and the client agree without a message per frame: the server keeps the state and judges
-- every input (one may be stamped a little in the past for a slow connection), the client reads it
-- from the player's attributes and draws the same reticle and the same shot. Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "dribble" | "aim" | "power" | "shot" | "over"
export type Outcome = "goal" | "saved" | "wide" | "over" | "post" | "bar" | "tackled"
-- The skill moves: 1 cuts left, 2 is a step-over, 3 cuts right.
export type Move = number
export type State = {
	phase: Phase,
	seed: number, -- the start time of the streak: the moves and where the keeper stands come from it
	kick: number, -- the attack of the streak, 1 for the first
	stageAt: number, -- when the current step started (the move shows, the reticle glides from here)
	move: Move, -- the move this attack asks for
	aimX: number, -- the locked reticle, across the goal: the posts are at -1 and 1
	aimY: number, -- and up: the ground is 0, the bar 1
	holdAt: number, -- when the power meter starts to move (a moment after the lock), 0 before
	power: number, -- 0 to 1
	outcome: string, -- the attack's outcome while its film plays, "" before
	streak: number, -- goals in a row
	overAt: number, -- when the streak ended
}

-- Where the keeper stands for one attack, in goal units (the posts are at -1 and 1).
export type Setup = { keeperX: number, move: Move }

export type Event = { kind: "over", streak: number, medal: number }

local Freekick = {}

Freekick.LEFT = 1
Freekick.STEP_OVER = 2
Freekick.RIGHT = 3

-- Where the keeper stands and which move attack `kick` of the streak that started at `seed` asks
-- for. The same on every machine.
function Freekick.setup(seed: number, kick: number): Setup
	local function unit(salt: number): number
		local mixed = math.sin(seed * 12.9898 + kick * 78.233 + salt * 37.719) * 43758.5453
		return mixed - math.floor(mixed)
	end
	return {
		keeperX = Config.Training.freekickKeeperSpread * (2 * unit(1) - 1),
		move = math.clamp(1 + math.floor(unit(2) * 3), 1, 3),
	}
end

-- A new attack `kick` of the streak that started at `seed`: the move shows at `startAt`.
local function attack(state: State, kick: number, startAt: number)
	state.phase = "dribble"
	state.kick = kick
	state.stageAt = startAt
	state.move = Freekick.setup(state.seed, kick).move
	state.aimX = 0
	state.aimY = 0
	state.holdAt = 0
	state.power = 0
	state.outcome = ""
end

-- A fresh streak that starts at `now`; the first move shows after the through-ball.
function Freekick.new(now: number): State
	local state: State = {
		phase = "dribble",
		seed = now,
		kick = 1,
		stageAt = 0,
		move = 1,
		aimX = 0,
		aimY = 0,
		holdAt = 0,
		power = 0,
		outcome = "",
		streak = 0,
		overAt = 0,
	}
	attack(state, 1, now + Config.Training.freekickLeadSeconds)
	return state
end

function Freekick.medal(streak: number): number
	local medals = Config.Training.freekickMedals
	if streak >= medals.gold then
		return 3
	elseif streak >= medals.silver then
		return 2
	elseif streak >= medals.bronze then
		return 1
	end
	return 0
end

-- TP for a goal that brings the streak to `streak`.
function Freekick.tpFor(streak: number): number
	local training = Config.Training
	return training.freekickBaseTp
		+ training.freekickStreakTp * math.min(streak, training.freekickStreakMax)
end

-- How long the move of attack `kick` waits for its key: less with every goal of the streak.
function Freekick.moveWindow(kick: number): number
	local training = Config.Training
	return math.max(
		training.freekickMoveSeconds - (kick - 1) * training.freekickMoveStep,
		training.freekickMoveMin
	)
end

-- How long the film of an attack plays.
function Freekick.filmSeconds(outcome: string): number
	local training = Config.Training
	return if outcome == "tackled"
		then training.freekickTackleSeconds
		else training.freekickFilmSeconds
end

-- Up and down between 0 and 1: 0 at `t` = 0, 1 after `seconds`, 0 again after twice that.
local function sweep(t: number, seconds: number): number
	local u = (math.max(t, 0) / seconds) % 2
	return if u > 1 then 2 - u else u
end

-- The reticle at time `at` (during the aim step): it starts in the middle of the goal and glides
-- across and up and down at different speeds, so it passes every corner.
function Freekick.aimAt(state: { stageAt: number }, at: number): (number, number)
	local training = Config.Training
	local t = at - state.stageAt
	local across = training.freekickAimSeconds
	local up = training.freekickAimUpSeconds
	local x = training.freekickAimRange * (2 * sweep(t + across / 2, across) - 1)
	local y = training.freekickAimLow
		+ (training.freekickAimHigh - training.freekickAimLow) * sweep(t + up / 2, up)
	return x, y
end

-- How long the meter of attack `kick` takes to fill: less with every goal of the streak.
function Freekick.powerSeconds(kick: number): number
	local training = Config.Training
	return math.max(
		training.freekickPowerSeconds - (kick - 1) * training.freekickPowerStep,
		training.freekickPowerMin
	)
end

-- The green zone of the meter on attack `kick`, bottom and top: narrower with every goal.
function Freekick.goodZone(kick: number): (number, number)
	local training = Config.Training
	local low = math.min(
		training.freekickWeakPower + (kick - 1) * training.freekickGoodLowStep,
		training.freekickGoodLowMax
	)
	local high = math.max(
		training.freekickGoodHigh - (kick - 1) * training.freekickGoodHighStep,
		training.freekickGoodHighMin
	)
	return low, high
end

-- The power meter at time `at` once it moves: it fills, then empties again, faster on a later
-- attack `kick` of the streak (the first when left out, as for the daily penalty).
function Freekick.powerAt(state: { holdAt: number }, at: number, kick: number?): number
	return sweep(at - state.holdAt, Freekick.powerSeconds(kick or 1))
end

-- How high the shot is at the goal: the reticle's height, lifted by power above the sweet power.
function Freekick.height(aimY: number, power: number): number
	local training = Config.Training
	return math.max(aimY + (power - training.freekickPowerSweet) * training.freekickPowerLift, 0)
end

-- What a shot does: saved, missed or a goal. The keeper reaches further with every `kick` of the
-- streak, unless `keeperReach` sets his reach (the daily penalty has a keeper of its own).
function Freekick.judge(
	keeperX: number,
	kick: number,
	aimX: number,
	aimY: number,
	power: number,
	keeperReach: number?
): Outcome
	local training = Config.Training
	local r = training.freekickBallRadius
	if power < training.freekickWeakPower then
		return "saved" -- it rolls to the keeper
	end
	local height = Freekick.height(aimY, power)
	if math.abs(aimX) > 1 + r then
		return if height > 1 + r then "over" else "wide"
	end
	if height > 1 + r then
		return "over"
	elseif height > 1 - r then
		return "bar"
	elseif math.abs(aimX) > 1 - r then
		return "post"
	end
	local reach = (
		keeperReach
		or training.freekickKeeperReach
			+ math.min(
				(kick - 1) * training.freekickKeeperReachStep,
				training.freekickKeeperReachMax
			)
	) * (1 + training.freekickPowerSweet - power)
	local distance = math.abs(aimX - keeperX)
		+ math.max(height - 0.6, 0) * training.freekickTopCorner
	if distance < reach then
		return "saved"
	end
	return "goal"
end

-- The film starts: the outcome is known.
local function shoot(state: State, outcome: Outcome, at: number)
	state.outcome = outcome
	if outcome == "goal" then
		state.streak += 1
	end
	state.phase = "shot"
	state.stageAt = at
end

-- Applies what time alone changes: a move left too long loses the ball, a film that has played
-- brings the next attack (after a goal) or ends the streak, and after the result a new streak
-- starts. Returns the events, in order.
function Freekick.normalize(state: State, now: number): { Event }
	local events: { Event } = {}
	local training = Config.Training
	for _ = 1, 16 do -- a bounded loop: a long gap is caught up a step at a time
		if state.phase == "dribble" then
			local deadline = state.stageAt + Freekick.moveWindow(state.kick)
			if now < deadline + training.freekickGraceSeconds then
				break
			end
			shoot(state, "tackled", deadline)
		elseif state.phase == "shot" then
			local ended = state.stageAt + Freekick.filmSeconds(state.outcome)
			if now < ended then
				break
			end
			if state.outcome == "goal" then
				attack(state, state.kick + 1, ended + training.freekickLeadSeconds)
			else
				state.phase = "over"
				state.overAt = ended
				table.insert(
					events,
					{ kind = "over", streak = state.streak, medal = Freekick.medal(state.streak) }
				)
			end
		elseif state.phase == "over" then
			local nextAt = state.overAt + training.freekickOverSeconds
			if now < nextAt then
				break
			end
			local fresh = Freekick.new(nextAt)
			for key, value in fresh do
				(state :: any)[key] = value
			end
		else
			break -- the aim and the power wait for the player
		end
	end
	return events
end

-- When an input stamped `stamp` counts: never in the future, never more than the grace time in the
-- past, and never before `from`.
local function inputTime(now: number, stamp: number, from: number): number
	if stamp ~= stamp then -- NaN
		stamp = now
	end
	return math.max(math.min(stamp, now), now - Config.Training.freekickGraceSeconds, from)
end

-- A skill move pressed at `now` (stamped `stamp`). The right one in time beats the defender; the
-- wrong one, or one too late, loses the ball. Returns "beat", "tackled" or "ignored" (another step,
-- or the move has not shown yet).
function Freekick.move(state: State, now: number, move: number, stamp: number): string
	Freekick.normalize(state, now)
	if state.phase ~= "dribble" or now < state.stageAt then
		return "ignored"
	end
	local at = inputTime(now, stamp, state.stageAt)
	if move == state.move and at <= state.stageAt + Freekick.moveWindow(state.kick) then
		state.phase = "aim"
		state.stageAt = now
		return "beat"
	end
	shoot(state, "tackled", now)
	return "tackled"
end

-- A tap at `now` (stamped `stamp`) during the aim step: locks the reticle, and the power meter
-- starts to move `freekickPowerDelay` later. Returns whether it did.
function Freekick.lock(state: State, now: number, stamp: number): boolean
	Freekick.normalize(state, now)
	if state.phase ~= "aim" then
		return false
	end
	state.aimX, state.aimY = Freekick.aimAt(state, inputTime(now, stamp, state.stageAt))
	state.phase = "power"
	state.stageAt = now
	state.holdAt = now + Config.Training.freekickPowerDelay
	return true
end

-- A tap at `now` (stamped `stamp`) while the power meter moves: the shot. Returns whether it shot
-- (not before the meter moves).
function Freekick.strike(state: State, now: number, stamp: number): boolean
	Freekick.normalize(state, now)
	if state.phase ~= "power" or state.holdAt <= 0 or now < state.holdAt then
		return false
	end
	state.power = Freekick.powerAt(state, inputTime(now, stamp, state.holdAt), state.kick)
	local setup = Freekick.setup(state.seed, state.kick)
	local low, high = Freekick.goodZone(state.kick)
	local outcome: Outcome = if state.power < low
		then "saved" -- too soft: it rolls to the keeper
		elseif state.power > high then "over" -- too hard: over the bar
		else Freekick.judge(setup.keeperX, state.kick, state.aimX, state.aimY, state.power)
	shoot(state, outcome, now)
	return true
end

return Freekick
