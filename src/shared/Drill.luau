--!strict
-- The timing of the training drill (docs/PLAN.md, Step 4): a marker sweeps across a bar from left
-- to right and a press counts when it is near the middle. A hit starts the sweep again at once; a
-- miss starts a short cooldown; a sweep that runs to the end unpressed (the player is away) stops
-- the drill. In both cases the bar stays red ("stopped") until the next press starts the marker.
-- The server keeps the state and judges every press; the client runs the same functions on the
-- state it reads from the player's attributes, so the bar the player sees is the one judged.
-- Pure, so it is unit tested.

local Config = require(script.Parent.Config)

export type Phase = "running" | "cooldown" | "stopped"
export type State = { phase: Phase, startedAt: number, cooldownUntil: number }

local Drill = {}

function Drill.new(): State
	return { phase = "stopped", startedAt = 0, cooldownUntil = 0 }
end

-- Applies what time alone changes: a sweep that reached the end, or a finished cooldown, leaves the
-- drill stopped.
function Drill.normalize(state: State, now: number)
	local sweepOver = state.phase == "running"
		and now - state.startedAt >= Config.Training.drillSweepSeconds - 1e-6
	local cooldownOver = state.phase == "cooldown" and now >= state.cooldownUntil
	if sweepOver or cooldownOver then
		state.phase = "stopped"
	end
end

-- Where the marker is (0 left, 1 right) while the drill runs, else nil.
function Drill.position(state: State, now: number): number?
	if state.phase ~= "running" then
		return nil
	end
	return math.clamp((now - state.startedAt) / Config.Training.drillSweepSeconds, 0, 1)
end

-- Whether a marker position counts as a hit (the middle of the bar).
function Drill.isHit(position: number): boolean
	return math.abs(position - 0.5) <= Config.Training.drillWindow
end

-- A press at `now`. Returns what happened:
--   "start"   the drill was stopped: the marker starts, nothing is paid
--   "hit"     the marker was in the middle: it starts again at once
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
	if Drill.isHit(position) then
		state.startedAt = now
		return "hit"
	end
	state.phase = "cooldown"
	state.cooldownUntil = now + Config.Training.drillCooldownSeconds
	return "miss"
end

return Drill
