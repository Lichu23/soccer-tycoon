--!strict
-- Keepie-uppies at the Training Gym (docs/PLAN.md, Step 4): the ball is kicked up and comes back to the
-- player's foot at a steady beat; a tap close to that moment keeps it up and grows the combo. Rounds
-- last 30 seconds and end in a medal. Everything is worked out from the start time of the ball, so
-- the server and the client agree without a message for each bounce: the server keeps the state and
-- judges every tap, the client reads it from the player's attributes and draws the same ball.
-- Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "running" | "cooldown" | "finished"
export type State = {
	phase: Phase,
	startedAt: number, -- when the ball left the foot (the beat counts from here)
	cooldownUntil: number,
	lastIndex: number, -- the last beat that was resolved (hit or dropped)
	combo: number,
	hits: number, -- clean touches in this round
	bestCombo: number, -- the longest combo of this round
	roundEndsAt: number,
	finishedAt: number,
}

-- What time alone changed in a `normalize` call, for the server to announce.
export type Event =
	{ kind: "drop" }
	| { kind: "round", hits: number, bestCombo: number, medal: number }

local Juggle = {}

-- A fresh round that starts at `now`: the player gets `juggleLeadSeconds` to get ready, then the first
-- ball leaves the foot and the round clock starts.
function Juggle.new(now: number): State
	local start = now + Config.Training.juggleLeadSeconds
	return {
		phase = "running",
		startedAt = start,
		cooldownUntil = 0,
		lastIndex = 0,
		combo = 0,
		hits = 0,
		bestCombo = 0,
		roundEndsAt = start + Config.Training.juggleRoundSeconds,
		finishedAt = 0,
	}
end

-- The medal of a round with `hits` clean touches: 0 none, 1 bronze, 2 silver, 3 gold.
function Juggle.medal(hits: number): number
	local medals = Config.Training.juggleMedals
	if hits >= medals.gold then
		return 3
	elseif hits >= medals.silver then
		return 2
	elseif hits >= medals.bronze then
		return 1
	end
	return 0
end

-- The time the ball is at the foot for beat `index` (1 is the first return).
function Juggle.beatTime(state: State, index: number): number
	return state.startedAt + index * Config.Training.juggleBounceSeconds
end

-- How high the ball is, 0 at the foot and 1 at the top of its flight, between two beats.
function Juggle.height(state: State, now: number): number
	local bounce = Config.Training.juggleBounceSeconds
	local phase = (math.max(now - state.startedAt, 0) / bounce) % 1
	return 4 * phase * (1 - phase)
end

-- TP for a clean touch at `combo` (the combo after the touch).
function Juggle.tpFor(combo: number): number
	local training = Config.Training
	return training.juggleBaseTp + training.juggleComboTp * math.min(combo, training.juggleComboMax)
end

-- Applies what time alone changes: a beat that passed without a tap drops the ball, a finished
-- cooldown starts the ball again, the end of the round ends it and a finished round starts the next
-- one. Returns the events, in order.
function Juggle.normalize(state: State, now: number): { Event }
	local events: { Event } = {}
	local training = Config.Training
	for _ = 1, 64 do -- a bounded loop: a long gap is caught up a step at a time
		if state.phase == "finished" then
			if now < state.finishedAt + training.juggleRoundPauseSeconds then
				break
			end
			local fresh = Juggle.new(state.finishedAt + training.juggleRoundPauseSeconds)
			for key, value in fresh do
				(state :: any)[key] = value
			end
		elseif state.phase == "cooldown" then
			if now >= state.roundEndsAt and state.roundEndsAt <= state.cooldownUntil then
				-- The round ended while the ball was down.
				state.phase = "finished"
				state.finishedAt = state.roundEndsAt
				table.insert(events, {
					kind = "round",
					hits = state.hits,
					bestCombo = state.bestCombo,
					medal = Juggle.medal(state.hits),
				})
			elseif now < state.cooldownUntil then
				break
			else
				state.phase = "running"
				state.startedAt = state.cooldownUntil
				state.lastIndex = 0
			end
		else
			-- Running: the round may end first, then the next beat may have been missed.
			local nextBeat = Juggle.beatTime(state, state.lastIndex + 1)
			local dropAt = nextBeat + training.juggleWindow
			if now >= state.roundEndsAt and state.roundEndsAt <= dropAt then
				state.phase = "finished"
				state.finishedAt = state.roundEndsAt
				table.insert(events, {
					kind = "round",
					hits = state.hits,
					bestCombo = state.bestCombo,
					medal = Juggle.medal(state.hits),
				})
			elseif now > dropAt then
				state.combo = 0
				state.phase = "cooldown"
				state.cooldownUntil = dropAt + training.juggleCooldownSeconds
				table.insert(events, { kind = "drop" })
			else
				break
			end
		end
	end
	return events
end

-- A tap at `now`. Returns what happened:
--   "hit"     the ball was at the foot: it goes up again and the combo grows
--   "miss"    too early (or too late for the beat, with the ball already dropped): the combo is broken
--   "ignored" during a cooldown, after the round, or a second tap on a beat that was already hit
function Juggle.press(state: State, now: number): string
	Juggle.normalize(state, now)
	if state.phase ~= "running" then
		return "ignored"
	end
	local training = Config.Training
	local index = state.lastIndex + 1
	local beat = Juggle.beatTime(state, index)
	if math.abs(now - beat) <= training.juggleWindow then
		state.lastIndex = index
		state.combo += 1
		state.hits += 1
		state.bestCombo = math.max(state.bestCombo, state.combo)
		return "hit"
	end
	if
		now < beat - training.juggleWindow
		and now >= Juggle.beatTime(state, index - 1) + training.juggleWindow
	then
		-- A tap while the ball is in the air: the touch is wasted and the combo is broken.
		state.combo = 0
		state.phase = "cooldown"
		state.cooldownUntil = now + training.juggleCooldownSeconds
		return "miss"
	end
	return "ignored" -- a second tap right after a hit, inside the same beat window
end

return Juggle
