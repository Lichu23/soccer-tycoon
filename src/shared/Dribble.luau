--!strict
-- The dribble run at the Training Gym (docs/PLAN.md, Step 4): the player dribbles down three lanes and
-- rows of cones come towards him; he moves one lane left or right to stay clear of them. Every row is
-- passed clean or the player stumbles over a cone. Rounds last 30 seconds and end in a medal. The
-- rows come at a steady beat and which lanes they block comes from the start time of the round, so
-- the server and the client agree without a message per row. The server keeps the lane and judges
-- every row; to be fair to a slow connection a move may be stamped a little in the past, and a row
-- is judged only after that grace time has passed. Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "running" | "stumble" | "finished"
export type Move = { at: number, lane: number }
export type State = {
	phase: Phase,
	startedAt: number, -- row 1 comes at startedAt + one row time
	stumbleUntil: number,
	laneBase: number, -- the lane before the first of `moves` (1 left, 2 middle, 3 right)
	moves: { Move }, -- the lane changes not judged yet, oldest first
	lastRow: number, -- the last row that was judged (or skipped during a stumble)
	combo: number,
	passes: number, -- rows passed clean in this round
	bestCombo: number,
	roundEndsAt: number,
	finishedAt: number,
}

export type Event =
	{ kind: "pass", combo: number }
	| { kind: "stumble" }
	| { kind: "round", passes: number, bestCombo: number, medal: number }

local Dribble = {}

-- A fresh round that starts at `now`, after the "get ready" time.
function Dribble.new(now: number): State
	local start = now + Config.Training.dribbleLeadSeconds
	return {
		phase = "running",
		startedAt = start,
		stumbleUntil = 0,
		laneBase = 2,
		moves = {},
		lastRow = 0,
		combo = 0,
		passes = 0,
		bestCombo = 0,
		roundEndsAt = start + Config.Training.dribbleRoundSeconds,
		finishedAt = 0,
	}
end

function Dribble.medal(passes: number): number
	local medals = Config.Training.dribbleMedals
	if passes >= medals.gold then
		return 3
	elseif passes >= medals.silver then
		return 2
	elseif passes >= medals.bronze then
		return 1
	end
	return 0
end

-- The time row `index` (1, 2, 3...) reaches the player.
function Dribble.rowTime(state: State, index: number): number
	return state.startedAt + index * Config.Training.dribbleRowSeconds
end

-- Which lanes row `index` of the round that started at `startedAt` blocks: three booleans. One row in
-- three is wide (two lanes blocked, one way through); the others block one lane. Worked out from a
-- fixed pseudo-random place, the same on every machine.
function Dribble.blocked(startedAt: number, index: number): { boolean }
	local function unit(salt: number): number
		local mixed = math.sin(startedAt * 12.9898 + index * 78.233 + salt * 37.719) * 43758.5453
		return mixed - math.floor(mixed)
	end
	if unit(2) < 1 / 3 then
		local safe = math.min(math.floor(unit(1) * 3) + 1, 3)
		local wide = { true, true, true }
		wide[safe] = false
		return wide
	end
	local one = math.min(math.floor(unit(3) * 3) + 1, 3)
	local narrow = { false, false, false }
	narrow[one] = true
	return narrow
end

-- The lane the player is in now (the newest move, or the base lane).
function Dribble.lane(state: State): number
	local moves = state.moves
	return if #moves > 0 then moves[#moves].lane else state.laneBase
end

-- The lane the player was in at time `at`.
function Dribble.laneAt(state: State, at: number): number
	local lane = state.laneBase
	for _, move in state.moves do
		if move.at > at then
			break
		end
		lane = move.lane
	end
	return lane
end

-- Moves the lane one step (`direction` -1 left, 1 right) at `stamp`, a time at or a little before
-- `now`. Returns whether the lane changed. Moves are only allowed while running.
function Dribble.move(state: State, now: number, direction: number, stamp: number): boolean
	Dribble.normalize(state, now)
	if state.phase ~= "running" then
		return false
	end
	local current = Dribble.lane(state)
	local target = math.clamp(current + direction, 1, 3)
	if target == current then
		return false
	end
	local grace = Config.Training.dribbleGraceSeconds
	local last = if #state.moves > 0 then state.moves[#state.moves].at else -math.huge
	-- Not before the grace window (rows older than it are already judged), not in the future, and
	-- never before the move before it.
	local at = math.max(math.min(stamp, now), now - grace, last)
	table.insert(state.moves, { at = at, lane = target })
	return true
end

-- Judges what time alone has settled: every row older than the grace time passed clean or not, the
-- end of the round, the end of a stumble and the next round after the pause. Returns the events.
function Dribble.normalize(state: State, now: number): { Event }
	local events: { Event } = {}
	local training = Config.Training
	for _ = 1, 96 do -- a bounded loop: a long gap is caught up a step at a time
		local frontier = now - training.dribbleGraceSeconds
		if state.phase == "finished" then
			if now < state.finishedAt + training.dribbleRoundPauseSeconds then
				break
			end
			local fresh = Dribble.new(state.finishedAt + training.dribbleRoundPauseSeconds)
			for key, value in fresh do
				(state :: any)[key] = value
			end
		else
			local row = state.lastRow + 1
			local time = Dribble.rowTime(state, row)
			if time > state.roundEndsAt then
				-- No more rows: the round ends once the grace has passed.
				if frontier < state.roundEndsAt then
					break
				end
				state.phase = "finished"
				state.finishedAt = state.roundEndsAt
				table.insert(events, {
					kind = "round",
					passes = state.passes,
					bestCombo = state.bestCombo,
					medal = Dribble.medal(state.passes),
				})
			elseif frontier < time then
				break
			elseif state.phase == "stumble" and time <= state.stumbleUntil then
				state.lastRow = row -- the player is getting up: this row is skipped
			else
				state.phase = "running"
				local lane = Dribble.laneAt(state, time)
				if Dribble.blocked(state.startedAt, row)[lane] then
					state.combo = 0
					state.phase = "stumble"
					state.stumbleUntil = time + training.dribbleStumbleSeconds
					table.insert(events, { kind = "stumble" })
				else
					state.passes += 1
					state.combo += 1
					state.bestCombo = math.max(state.bestCombo, state.combo)
					table.insert(events, { kind = "pass", combo = state.combo })
				end
				state.lastRow = row
				-- The moves that were before this row are settled: fold them into the base lane.
				while #state.moves > 0 and state.moves[1].at <= time do
					state.laneBase = state.moves[1].lane
					table.remove(state.moves, 1)
				end
			end
		end
	end
	return events
end

return Dribble
