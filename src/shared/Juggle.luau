--!strict
-- Keepie-uppies at the Training Gym (docs/PLAN.md, Step 4), an endless streak: the ball is kicked up
-- and comes back to the player's foot on a beat that gets a little quicker with every touch; a tap
-- close to that moment keeps it up and grows the streak, a tap while the ball is in the air or a ball
-- left to drop ends it. The longest streak is the personal best. Everything is worked out from the
-- start time of the ball, so the server and the client agree without a message for each bounce: the
-- server keeps the state and judges every tap, the client reads it from the player's attributes and
-- draws the same ball. Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "running" | "over"
export type State = {
	phase: Phase,
	startedAt: number, -- when the ball left the foot (the beats count from here)
	lastIndex: number, -- the last beat that was hit
	combo: number, -- the streak: clean touches in a row
	overAt: number, -- when the streak ended
}

-- What time alone changed in a `normalize` call, for the server to announce.
export type Event = { kind: "over", streak: number, medal: number }

local Juggle = {}

-- A fresh streak that starts at `now`: the player gets `juggleLeadSeconds` to get ready, then the
-- first ball leaves the foot.
function Juggle.new(now: number): State
	return {
		phase = "running",
		startedAt = now + Config.Training.juggleLeadSeconds,
		lastIndex = 0,
		combo = 0,
		overAt = 0,
	}
end

-- Skips the "how to play" time before the first streak: the ball then leaves the foot after the
-- usual `juggleLeadSeconds` countdown from `now`. True when there was intro time left to skip.
function Juggle.skipIntro(state: State, now: number): boolean
	local start = now + Config.Training.juggleLeadSeconds
	if state.phase ~= "running" or state.lastIndex ~= 0 or state.startedAt <= start then
		return false
	end
	state.startedAt = start
	return true
end

-- The medal of a streak of `streak` touches: 0 none, 1 bronze, 2 silver, 3 gold.
function Juggle.medal(streak: number): number
	local medals = Config.Training.juggleMedals
	if streak >= medals.gold then
		return 3
	elseif streak >= medals.silver then
		return 2
	elseif streak >= medals.bronze then
		return 1
	end
	return 0
end

-- How long the flight before beat `index` takes: a little shorter for every beat, down to the floor.
function Juggle.period(index: number): number
	local training = Config.Training
	return math.max(
		training.juggleBounceSeconds - training.juggleBounceStep * (index - 1),
		training.juggleBounceMin
	)
end

-- The beats that still get quicker (from the next one on they all take `juggleBounceMin`).
local function slowingBeats(): number
	local training = Config.Training
	return math.floor(
		(training.juggleBounceSeconds - training.juggleBounceMin) / training.juggleBounceStep + 1e-9
	) + 1
end

-- The time from the start to beat `index` (0 for index 0).
local function elapsedTo(index: number): number
	local training = Config.Training
	local m = slowingBeats()
	local slowing = math.min(index, m)
	local total = slowing * training.juggleBounceSeconds
		- training.juggleBounceStep * slowing * (slowing - 1) / 2
	if index > m then
		total += (index - m) * training.juggleBounceMin
	end
	return total
end

-- The time the ball is at the foot for beat `index` (1 is the first return).
function Juggle.beatTime(state: State, index: number): number
	return state.startedAt + elapsedTo(index)
end

-- The beat the ball is on its way to at `now` (1 before the first return).
function Juggle.beatAt(state: State, now: number): number
	local t = now - state.startedAt
	if t < 0 then
		return 1
	end
	-- The first beat whose time is after `t`, by halving.
	local low, high = 1, slowingBeats() + math.ceil(t / Config.Training.juggleBounceMin) + 1
	while low < high do
		local middle = (low + high) // 2
		if elapsedTo(middle) > t then
			high = middle
		else
			low = middle + 1
		end
	end
	return low
end

-- How high the ball is, 0 at the foot and 1 at the top of its flight, between two beats.
function Juggle.height(state: State, now: number): number
	if now <= state.startedAt then
		return 0
	end
	local index = Juggle.beatAt(state, now)
	local from = elapsedTo(index - 1)
	local phase = math.clamp((now - state.startedAt - from) / Juggle.period(index), 0, 1)
	return 4 * phase * (1 - phase)
end

-- TP for a clean touch at `combo` (the streak after the touch).
function Juggle.tpFor(combo: number): number
	local training = Config.Training
	for _, tier in training.juggleTpTiers do
		if combo <= tier.upTo then
			return tier.tp
		end
	end
	return training.juggleTpFloor
end

local function finish(state: State, at: number): Event
	state.phase = "over"
	state.overAt = at
	return { kind = "over", streak = state.combo, medal = Juggle.medal(state.combo) }
end

-- Applies what time alone changes: a beat that passed without a tap drops the ball and ends the
-- streak, and after the result a new streak starts. Returns the events, in order.
function Juggle.normalize(state: State, now: number): { Event }
	local events: { Event } = {}
	local training = Config.Training
	for _ = 1, 64 do -- a bounded loop: a long gap is caught up a step at a time
		if state.phase == "over" then
			local nextAt = state.overAt + training.juggleOverSeconds
			if now < nextAt then
				break
			end
			local fresh = Juggle.new(nextAt)
			for key, value in fresh do
				(state :: any)[key] = value
			end
		else
			local dropAt = Juggle.beatTime(state, state.lastIndex + 1) + training.juggleWindow
			if now <= dropAt then
				break
			end
			table.insert(events, finish(state, dropAt))
		end
	end
	return events
end

-- A tap at `now`. Returns what happened and, when the streak ended, its event:
--   "hit"     the ball was at the foot: it goes up again and the streak grows
--   "miss"    a tap while the ball was in the air: the streak ends
--   "ignored" before the first ball, after the streak, or a second tap on a beat already hit
function Juggle.press(state: State, now: number): (string, Event?)
	Juggle.normalize(state, now)
	if state.phase ~= "running" then
		return "ignored", nil
	end
	local window = Config.Training.juggleWindow
	local index = state.lastIndex + 1
	local beat = Juggle.beatTime(state, index)
	if math.abs(now - beat) <= window then
		state.lastIndex = index
		state.combo += 1
		return "hit", nil
	end
	if now < beat - window and now >= Juggle.beatTime(state, index - 1) + window then
		return "miss", finish(state, now)
	end
	return "ignored", nil -- the get-ready time, or a second tap right after a hit
end

return Juggle
