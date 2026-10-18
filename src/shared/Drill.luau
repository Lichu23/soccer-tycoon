--!strict
-- The timing of the training drill on the active farm (docs/PLAN.md, Step 4): a marker moves back
-- and forth across a bar and a press counts when the marker is inside the green zone. A hit starts
-- the marker again at once; a miss turns the bar red for a short cooldown and then the marker
-- starts again by itself. Each time the marker starts, the green zone jumps to a new place, worked
-- out from the start time, so the server and the client agree without any message. The marker never
-- stops until the player presses (an idle player just earns nothing on the active farm).
-- The server keeps the state and judges every press; the client reads it from the player's
-- attributes and runs the same functions, so the bar the player sees is the one judged.
-- Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "running" | "cooldown" | "stopped"
export type State = { phase: Phase, startedAt: number, cooldownUntil: number }

local Drill = {}

function Drill.new(): State
	return { phase = "stopped", startedAt = 0, cooldownUntil = 0 }
end

-- Applies what time alone changes: a finished cooldown starts the marker again.
function Drill.normalize(state: State, now: number)
	if state.phase == "cooldown" and now >= state.cooldownUntil then
		state.phase = "running"
		state.startedAt = state.cooldownUntil
	end
end

-- Where the marker is (0 left, 1 right) while the drill runs, else nil. It goes there and back.
function Drill.position(state: State, now: number): number?
	if state.phase ~= "running" then
		return nil
	end
	local passes = math.max(now - state.startedAt, 0) / Config.Training.drillSweepSeconds
	local phase = passes % 2
	return if phase <= 1 then phase else 2 - phase
end

-- The centre of the green zone of the run that started at `startedAt` (0 left, 1 right): a fixed
-- pseudo-random place between drillZoneMin and drillZoneMax, the same on every machine.
function Drill.zone(startedAt: number): number
	local mixed = math.sin(startedAt * 12.9898) * 43758.5453
	local fraction = mixed - math.floor(mixed)
	local training = Config.Training
	return training.drillZoneMin + fraction * (training.drillZoneMax - training.drillZoneMin)
end

-- Whether the marker at `position` is inside the green zone of the run that started at `startedAt`.
function Drill.isHit(position: number, startedAt: number): boolean
	return math.abs(position - Drill.zone(startedAt)) <= Config.Training.drillWindow
end

-- A press at `now`. Returns what happened:
--   "start"   the drill was stopped (before its first start): the marker starts, nothing is paid
--   "hit"     the marker was in the green zone: a new run starts at once
--   "miss"    anywhere else: cooldown with a red bar
--   "ignored" during the cooldown
function Drill.press(state: State, now: number): string
	Drill.normalize(state, now)
	if state.phase == "cooldown" then
		return "ignored"
	elseif state.phase == "stopped" then
		state.phase = "running"
		state.startedAt = now
		return "start"
	end
	local position = Drill.position(state, now) or 0
	if Drill.isHit(position, state.startedAt) then
		state.startedAt = now
		return "hit"
	end
	state.phase = "cooldown"
	state.cooldownUntil = now + Config.Training.drillCooldownSeconds
	return "miss"
end

return Drill
