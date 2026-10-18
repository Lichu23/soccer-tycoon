--!strict
-- The timing of the training drill (docs/PLAN.md, Step 4): a marker sweeps across a bar once per
-- round, and a press counts when it is near the middle. The server and the client both work out the
-- marker from the drill's start time on the server clock, so the bar the player sees is the one the
-- server judges. Pure, so it is unit tested.

local Config = require(script.Parent.Config)

local Drill = {}

-- The round the drill is in at `now` and where the marker is (0 left, 1 right, 0.5 the middle).
function Drill.position(startedAt: number, now: number): (number, number)
	local length = Config.Training.drillRoundSeconds
	local elapsed = math.max(now - startedAt, 0)
	local round = math.floor(elapsed / length)
	return round, (elapsed - round * length) / length
end

-- Whether a marker position counts as a hit.
function Drill.isHit(position: number): boolean
	return math.abs(position - 0.5) <= Config.Training.drillWindow
end

-- Judges a press at `now`. One press per round counts, hit or miss: the first value is nil when
-- this round was already used (or the clock is before the first round), else whether it was a hit.
function Drill.judge(startedAt: number, now: number, lastRound: number): (boolean?, number)
	local round, position = Drill.position(startedAt, now)
	if round <= lastRound then
		return nil, round
	end
	return Drill.isHit(position), round
end

return Drill
