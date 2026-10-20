--!strict
-- Free kicks at the Training Gym (docs/PLAN.md, Step 4), an endless streak of goals. Every kick has
-- three steps, like the place kicks of an old rugby game: a power bar that goes up and down (tap to
-- set the power), a tap on the ball for the contact point (the side curls it, below the middle lifts
-- it over the wall) and an aim marker that sweeps across the goal (tap to set the direction). The
-- shot then flies past or into a wall and a keeper that stand somewhere new every kick. A goal adds
-- to the streak; anything else ends it, and the longest streak is the personal best.
-- The bars move on the server clock from the start of their step, so the server and the client agree
-- without a message per frame: the server keeps the state and judges every tap (a tap may be stamped
-- a little in the past for a slow connection), the client reads it from the player's attributes and
-- draws the same bars and the same flight. Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "power" | "contact" | "aim" | "flight" | "over"
export type Outcome = "goal" | "wall" | "saved" | "wide" | "post" | "over" | "bar"
export type State = {
	phase: Phase,
	seed: number, -- the start time of the streak: where the wall and the keeper stand comes from it
	kick: number, -- the kick of the streak, 1 for the first
	stageAt: number, -- when the current step started (the bars move from here)
	power: number, -- 0 to 1
	contactX: number, -- the contact point on the ball, -1 (left) to 1 (right)
	contactY: number, -- -1 (bottom) to 1 (top)
	aim: number, -- across the goal: the posts are at -1 and 1
	outcome: string, -- the last shot's outcome while it flies, "" before
	streak: number, -- goals in a row
	overAt: number, -- when the streak ended
}

-- Where the wall and the keeper stand for one kick, in goal units (the posts are at -1 and 1).
export type Setup = { wallX: number, keeperX: number }

-- The flight of a shot: its height at the wall and at the goal (the bar is at 1), and how far it
-- bends at the middle of the flight.
export type Flight = { wallHeight: number, goalHeight: number, bend: number }

export type Event = { kind: "over", streak: number, medal: number }

local Freekick = {}

-- A fresh streak that starts at `now`; the power bar of the first kick starts after the lead time.
function Freekick.new(now: number): State
	return {
		phase = "power",
		seed = now,
		kick = 1,
		stageAt = now + Config.Training.freekickLeadSeconds,
		power = 0,
		contactX = 0,
		contactY = 0,
		aim = 0,
		outcome = "",
		streak = 0,
		overAt = 0,
	}
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

-- Where the wall and the keeper stand for kick `kick` of the streak that started at `seed`: the wall
-- covers one side of the goal and the keeper leans to the other. The same on every machine.
function Freekick.setup(seed: number, kick: number): Setup
	local function unit(salt: number): number
		local mixed = math.sin(seed * 12.9898 + kick * 78.233 + salt * 37.719) * 43758.5453
		return mixed - math.floor(mixed)
	end
	local side = if unit(1) < 0.5 then -1 else 1
	return {
		wallX = side * (0.25 + 0.15 * unit(2)),
		keeperX = -side * (0.12 + 0.15 * unit(3)),
	}
end

-- Up and down between 0 and 1: 0 at `t` = 0, 1 after `seconds`, 0 again after twice that.
local function sweep(t: number, seconds: number): number
	local u = (math.max(t, 0) / seconds) % 2
	return if u > 1 then 2 - u else u
end

-- The power bar at time `at` (during the power step).
function Freekick.powerAt(state: State, at: number): number
	return sweep(at - state.stageAt, Config.Training.freekickPowerSeconds)
end

-- The aim marker at time `at` (during the aim step): it starts in the middle of the goal.
function Freekick.aimAt(state: State, at: number): number
	local training = Config.Training
	local seconds = training.freekickAimSeconds
	return training.freekickAimRange * (2 * sweep(at - state.stageAt + seconds / 2, seconds) - 1)
end

-- How the ball flies for a power and a contact point.
function Freekick.flight(power: number, contactX: number, contactY: number): Flight
	local training = Config.Training
	local lift = (1 - contactY) / 2
	local extra = power - training.freekickPowerSweet
	return {
		wallHeight = lift * training.freekickWallLift + extra * training.freekickWallPower,
		goalHeight = lift * training.freekickGoalLift + extra * training.freekickGoalPower,
		bend = contactX * training.freekickCurl,
	}
end

-- Where the ball is across the goal when it has gone `t` of the way (0 at the ball, 1 at the goal).
function Freekick.ballX(aim: number, bend: number, t: number): number
	return aim * t + bend * 4 * t * (1 - t)
end

-- What a shot does: blocked by the wall, saved, missed or a goal.
function Freekick.judge(
	setup: Setup,
	kick: number,
	power: number,
	contactX: number,
	contactY: number,
	aim: number
): Outcome
	local training = Config.Training
	local r = training.freekickBallRadius
	local flight = Freekick.flight(power, contactX, contactY)
	if power < training.freekickWeakPower then
		return "saved" -- it rolls to the keeper
	end
	local atWall = Freekick.ballX(aim, flight.bend, training.freekickWallAt)
	if
		math.abs(atWall - setup.wallX) < training.freekickWallHalf + r
		and flight.wallHeight < training.freekickWallTop
	then
		return "wall"
	end
	local height = flight.goalHeight
	if math.abs(aim) > 1 + r then
		return if height > 1 + r then "over" else "wide"
	end
	if height > 1 + r then
		return "over"
	elseif height > 1 - r then
		return "bar"
	elseif math.abs(aim) > 1 - r then
		return "post"
	end
	local reach = (
		training.freekickKeeperReach
		+ math.min((kick - 1) * training.freekickKeeperReachStep, training.freekickKeeperReachMax)
	) * (1 + training.freekickPowerSweet - power)
	local distance = math.abs(aim - setup.keeperX)
		+ math.max(height - 0.6, 0) * training.freekickTopCorner
	if distance < reach then
		return "saved"
	end
	return "goal"
end

-- Applies what time alone changes: a shot that has landed brings the next kick (after a goal) or
-- ends the streak, and after the result a new streak starts. Returns the events, in order.
function Freekick.normalize(state: State, now: number): { Event }
	local events: { Event } = {}
	local training = Config.Training
	for _ = 1, 16 do -- a bounded loop: a long gap is caught up a step at a time
		if state.phase == "flight" then
			local landed = state.stageAt + training.freekickFlightSeconds
			if now < landed then
				break
			end
			if state.outcome == "goal" then
				state.phase = "power"
				state.kick += 1
				state.stageAt = landed + training.freekickLeadSeconds
				state.outcome = ""
			else
				state.phase = "over"
				state.overAt = landed
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
			break -- the power, contact and aim steps wait for the player
		end
	end
	return events
end

-- When a tap stamped `stamp` counts: never in the future, never more than the grace time in the past,
-- and never before the step started.
local function tapTime(state: State, now: number, stamp: number): number
	if stamp ~= stamp then -- NaN
		stamp = now
	end
	return math.max(math.min(stamp, now), now - Config.Training.freekickGraceSeconds, state.stageAt)
end

-- A tap on the bar at `now` (stamped `stamp`): it sets the power, or the aim and kicks. Returns
-- "power" or "kick" for what it set, or "ignored" (another step, or the power bar not started yet).
function Freekick.tap(state: State, now: number, stamp: number): string
	Freekick.normalize(state, now)
	if now < state.stageAt then
		return "ignored"
	end
	if state.phase == "power" then
		state.power = Freekick.powerAt(state, tapTime(state, now, stamp))
		state.phase = "contact"
		state.stageAt = now
		return "power"
	elseif state.phase == "aim" then
		state.aim = Freekick.aimAt(state, tapTime(state, now, stamp))
		local outcome = Freekick.judge(
			Freekick.setup(state.seed, state.kick),
			state.kick,
			state.power,
			state.contactX,
			state.contactY,
			state.aim
		)
		state.outcome = outcome
		if outcome == "goal" then
			state.streak += 1
		end
		state.phase = "flight"
		state.stageAt = now
		return "kick"
	end
	return "ignored"
end

-- A tap on the ball at (`x`, `y`) (each -1 to 1, a point outside the ball is pulled onto its edge):
-- the contact point. Returns whether it was taken (only during the contact step).
function Freekick.contact(state: State, now: number, x: number, y: number): boolean
	Freekick.normalize(state, now)
	if state.phase ~= "contact" or x ~= x or y ~= y then -- (NaN is not equal to itself)
		return false
	end
	x, y = math.clamp(x, -1, 1), math.clamp(y, -1, 1)
	local length = math.sqrt(x * x + y * y)
	if length > 1 then
		x, y = x / length, y / length
	end
	state.contactX = x
	state.contactY = y
	state.phase = "aim"
	state.stageAt = now
	return true
end

return Freekick
