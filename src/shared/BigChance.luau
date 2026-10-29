--!strict
-- Big Chance (Config.BigChance): every few matches the match on the player's pitch makes a chance.
-- A button offers it for a few seconds; taking it turns the whole screen into the breakaway's
-- stadium (like the daily penalty kicks) with the ball on one of three spots in front of the goal:
-- the left of the box, the middle or the right. The shot is the penalty's: an aim reticle glides over
-- the goal mouth and a tap locks it, then the power meter's indicator slides up and down and a second
-- tap shoots. The keeper shades to the near post of an angled spot. The server judges the shot at
-- once with the breakaway's maths, then the client plays it as a film; a goal pays a few matches of
-- cash. The aim and the power share a shot clock: with no shot by then the keeper smothers the ball
-- ("late"). Everything runs on the server clock from the start of its step, so the client draws the
-- same reticle and the same shot from the player's attributes. Pure, so it is unit tested.

local Config = require(script.Parent.Config)
local Freekick = require(script.Parent.Freekick)

export type Phase = "none" | "offer" | "aim" | "power" | "shot"
export type State = {
	phase: Phase,
	spot: number, -- the spot of Config.BigChance.spots the ball waits on
	endsAt: number, -- the offer ends then; in the aim and the power the shot clock runs out then
	stageAt: number, -- when the current step started (the reticle glides from here, the film plays from here)
	aimX: number, -- the locked reticle, across the goal: the posts are at -1 and 1
	aimY: number, -- and up: the ground is 0, the bar 1
	holdAt: number, -- when the power meter starts to move (a moment after the lock), 0 before
	power: number, -- 0 to 1
	outcome: string, -- the shot's outcome while its film plays, "" before
}

local BigChance = {}

function BigChance.new(): State
	return {
		phase = "none",
		spot = 2,
		endsAt = 0,
		stageAt = 0,
		aimX = 0,
		aimY = 0,
		holdAt = 0,
		power = 0,
		outcome = "",
	}
end

-- Whether chances are open for this player.
function BigChance.unlocked(stadiumTier: number): boolean
	return stadiumTier >= Config.BigChance.minTier
end

-- Matches until the next chance: a whole number from minMatches to maxMatches. `roll` is 0 to 1.
function BigChance.gap(roll: number): number
	local rules = Config.BigChance
	return rules.minMatches
		+ math.floor(math.clamp(roll, 0, 0.999999) * (rules.maxMatches - rules.minMatches + 1))
end

-- The spot for a chance: 1 to the number of spots. `roll` is 0 to 1.
function BigChance.pickSpot(roll: number): number
	local count = #Config.BigChance.spots
	return 1 + math.floor(math.clamp(roll, 0, 0.999999) * count)
end

-- Where the keeper stands for a shot from `spot`, in goal units.
function BigChance.keeperX(spot: number): number
	local where = Config.BigChance.spots[spot]
	return if where then where.keeperX else 0
end

-- When the film of the shot ends.
function BigChance.filmEnd(state: State): number
	return state.stageAt + Config.BigChance.filmSeconds
end

local function reset(state: State)
	state.phase = "none"
	state.outcome = ""
end

-- Applies what time alone changes: an offer left alone goes away, the shot clock running out lets
-- the keeper smother the ball ("late"), and a film that has played ends the chance. Returns whether
-- it changed anything.
function BigChance.normalize(state: State, now: number): boolean
	local rules = Config.BigChance
	if state.phase == "offer" then
		-- A take tapped in the offer's last moment may arrive a little after it (a slow connection).
		if now < state.endsAt + rules.graceSeconds then
			return false
		end
		reset(state)
		return true
	elseif state.phase == "aim" or state.phase == "power" then
		if now < state.endsAt + rules.graceSeconds then
			return false
		end
		-- Too slow: the reticle stays where the clock caught it and the keeper smothers the ball.
		if state.phase == "aim" then
			state.aimX, state.aimY = Freekick.aimAt(state, state.endsAt)
		end
		state.power = 0
		state.outcome = "late"
		state.phase = "shot"
		state.stageAt = state.endsAt
		return true
	elseif state.phase == "shot" then
		if now < BigChance.filmEnd(state) then
			return false
		end
		reset(state)
		return true
	end
	return false
end

-- A new chance offered at `now`, its ball on `spot`. Returns false while another is still going.
function BigChance.offer(state: State, now: number, spot: number): boolean
	BigChance.normalize(state, now)
	if state.phase ~= "none" then
		return false
	end
	state.phase = "offer"
	state.spot = math.clamp(spot, 1, #Config.BigChance.spots)
	state.endsAt = now + Config.BigChance.offerSeconds
	state.stageAt = 0
	state.aimX = 0
	state.aimY = 0
	state.holdAt = 0
	state.power = 0
	state.outcome = ""
	return true
end

-- The player takes the offered chance at `now`: the screen opens and the reticle glides after the
-- lead; the shot clock starts with it.
function BigChance.take(state: State, now: number): boolean
	BigChance.normalize(state, now)
	if state.phase ~= "offer" then
		return false
	end
	local rules = Config.BigChance
	state.phase = "aim"
	state.stageAt = now + rules.leadSeconds
	state.endsAt = state.stageAt + rules.shotSeconds
	return true
end

-- When an input stamped `stamp` counts: never in the future, never more than the grace time in the
-- past, and never before `from`.
local function inputTime(now: number, stamp: number, from: number): number
	if stamp ~= stamp then -- NaN
		stamp = now
	end
	return math.max(math.min(stamp, now), now - Config.BigChance.graceSeconds, from)
end

-- A tap at `now` (stamped `stamp`) while the reticle glides: locks it. Returns whether it did.
function BigChance.lock(state: State, now: number, stamp: number): boolean
	BigChance.normalize(state, now)
	if state.phase ~= "aim" or now < state.stageAt then
		return false
	end
	local at = inputTime(now, stamp, state.stageAt)
	if at > state.endsAt then
		return false -- too late: the clock takes it at the next normalize
	end
	state.aimX, state.aimY = Freekick.aimAt(state, at)
	state.phase = "power"
	state.stageAt = now
	state.holdAt = now + Config.Training.freekickPowerDelay -- the meter moves a moment after the lock
	return true
end

-- A tap at `now` (stamped `stamp`) while the power meter moves: the shot, judged at once. Returns
-- the outcome, or nil when it does not count (not before the meter moves, nor after the clock).
function BigChance.strike(state: State, now: number, stamp: number): string?
	BigChance.normalize(state, now)
	if state.phase ~= "power" or state.holdAt <= 0 or now < state.holdAt then
		return nil
	end
	local at = inputTime(now, stamp, state.holdAt)
	if at > state.endsAt then
		return nil
	end
	state.power = Freekick.powerAt(state, at)
	local low, high = Freekick.penaltyZone()
	state.outcome = Freekick.judgeShot(
		BigChance.keeperX(state.spot),
		1,
		state.aimX,
		state.aimY,
		state.power,
		low,
		high,
		Config.BigChance.keeperReach
	)
	state.phase = "shot"
	state.stageAt = now
	return state.outcome
end

return BigChance
