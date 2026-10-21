--!strict
-- The daily penalty kicks (docs/PLAN.md, Step 7), played like the shot of the 1v1 breakaway
-- (shared/Freekick) without the defender: an aim reticle glides over the goal mouth and a tap locks
-- it, a hold fills the power meter and the release shoots. The server judges the shot at once with
-- the breakaway's maths and a calmer keeper of its own, then the client plays the kick as a film
-- (the run-up, the strike in slow motion, the goal or the save). After the film the next kick's
-- reticle comes, until the kicks of the day are used up. Like the breakaway everything runs on the
-- server clock from the start of its step, so the client draws the same reticle and the same shot
-- from the player's attributes. Pure, so it is unit tested.

local Config = require(script.Parent.Config)
local Freekick = require(script.Parent.Freekick)

export type Phase = "aim" | "power" | "shot" | "done"
export type State = {
	phase: Phase,
	seed: number, -- when the visit started
	kick: number, -- the kick of this visit, 1 for the first
	stageAt: number, -- when the current step started (the reticle glides from here, the film plays from here)
	aimX: number, -- the locked reticle, across the goal: the posts are at -1 and 1
	aimY: number, -- and up: the ground is 0, the bar 1
	holdAt: number, -- when the power hold began, 0 before
	power: number, -- 0 to 1
	outcome: string, -- the kick's outcome while its film plays, "" before
	kicksLeft: number, -- kicks left today (after the kick in the film)
}

local Penalty = {}

-- Where the keeper stands before every kick, in goal units: always the middle of the goal.
Penalty.KEEPER_X = 0

-- Kick `kick`: the reticle starts gliding at `startAt`.
local function nextKick(state: State, kick: number, startAt: number)
	state.phase = "aim"
	state.kick = kick
	state.stageAt = startAt
	state.aimX = 0
	state.aimY = 0
	state.holdAt = 0
	state.power = 0
	state.outcome = ""
end

-- A visit to the penalty spot that starts at `now` with `kicksLeft` kicks to take.
function Penalty.new(now: number, kicksLeft: number): State
	local state: State = {
		phase = "aim",
		seed = now,
		kick = 1,
		stageAt = 0,
		aimX = 0,
		aimY = 0,
		holdAt = 0,
		power = 0,
		outcome = "",
		kicksLeft = kicksLeft,
	}
	nextKick(state, 1, now + Config.Daily.penaltyLeadSeconds)
	if kicksLeft <= 0 then
		state.phase = "done"
	end
	return state
end

-- When the film of a kick ends.
function Penalty.filmEnd(state: State): number
	return state.stageAt + Config.Daily.penaltyFilmSeconds
end

-- Applies what time alone changes: a film that has played brings the next kick, or ends the visit
-- when no kick is left. The aim and the power wait for the player.
function Penalty.normalize(state: State, now: number)
	if state.phase ~= "shot" then
		return
	end
	local ended = Penalty.filmEnd(state)
	if now < ended then
		return
	end
	if state.kicksLeft > 0 then
		nextKick(state, state.kick + 1, ended + Config.Daily.penaltyLeadSeconds)
	else
		state.phase = "done"
		state.stageAt = ended
	end
end

-- When an input stamped `stamp` counts: never in the future, never more than the grace time in the
-- past, and never before `from`.
local function inputTime(now: number, stamp: number, from: number): number
	if stamp ~= stamp then -- NaN
		stamp = now
	end
	return math.max(math.min(stamp, now), now - Config.Training.freekickGraceSeconds, from)
end

-- A tap at `now` (stamped `stamp`) while the reticle glides: locks it. Returns whether it did.
function Penalty.lock(state: State, now: number, stamp: number): boolean
	Penalty.normalize(state, now)
	if state.phase ~= "aim" or now < state.stageAt then
		return false
	end
	state.aimX, state.aimY = Freekick.aimAt(state, inputTime(now, stamp, state.stageAt))
	state.phase = "power"
	state.stageAt = now
	state.holdAt = 0
	return true
end

-- The power hold begins at `now` (stamped `stamp`). Returns whether it did.
function Penalty.hold(state: State, now: number, stamp: number): boolean
	Penalty.normalize(state, now)
	if state.phase ~= "power" or state.holdAt > 0 then
		return false
	end
	state.holdAt = inputTime(now, stamp, state.stageAt)
	return true
end

-- The hold is released at `now` (stamped `stamp`): the shot, judged at once. Returns whether it
-- shot. The caller then counts the kick and sets `kicksLeft`.
function Penalty.release(state: State, now: number, stamp: number): boolean
	Penalty.normalize(state, now)
	if state.phase ~= "power" or state.holdAt <= 0 then
		return false
	end
	state.power = Freekick.powerAt(state, inputTime(now, stamp, state.holdAt))
	state.outcome = Freekick.judge(
		Penalty.KEEPER_X,
		1,
		state.aimX,
		state.aimY,
		state.power,
		Config.Daily.penaltyKeeperReach
	)
	state.phase = "shot"
	state.stageAt = now
	return true
end

return Penalty
