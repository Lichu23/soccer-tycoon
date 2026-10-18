--!strict
-- The timing of the training drill (docs/PLAN.md, Step 4): a marker sweeps across a bar from left
-- to right and a press counts when it is inside the green zone, which drifts along the bar. A hit starts the sweep again at once; a
-- miss turns the bar red for a short cooldown and then the marker starts again by itself; a sweep
-- that runs to the end unpressed simply starts the next one. The drill only begins "stopped" until
-- it is first started (the server presses once when the player steps onto the field).
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

-- Applies what time alone changes: a finished cooldown starts the marker again, and a sweep that
-- reached the end starts the next sweep.
function Drill.normalize(state: State, now: number)
	local sweep = Config.Training.drillSweepSeconds
	if state.phase == "cooldown" and now >= state.cooldownUntil then
		state.phase = "running"
		state.startedAt = state.cooldownUntil
	end
	if state.phase == "running" then
		local elapsed = now - state.startedAt
		if elapsed >= sweep - 1e-6 then
			state.startedAt += math.floor((elapsed + 1e-6) / sweep) * sweep
		end
	end
end

-- Where the marker is (0 left, 1 right) while the drill runs, else nil.
function Drill.position(state: State, now: number): number?
	if state.phase ~= "running" then
		return nil
	end
	return math.clamp((now - state.startedAt) / Config.Training.drillSweepSeconds, 0, 1)
end

-- Where the green zone is at `now` (0 left, 1 right): it drifts back and forth on the clock, so the
-- server and the client agree without any message.
function Drill.zoneCenter(now: number): number
	local training = Config.Training
	return 0.5
		+ training.drillZoneAmplitude
			* math.sin(now * 2 * math.pi / training.drillZonePeriodSeconds)
end

-- Whether a marker position counts as a hit: inside the green zone at `now`.
function Drill.isHit(position: number, now: number): boolean
	return math.abs(position - Drill.zoneCenter(now)) <= Config.Training.drillWindow
end

-- A press at `now`. Returns what happened:
--   "start"   the drill was stopped (before its first start): the marker starts, nothing is paid
--   "hit"     the marker was in the green zone: it starts again at once
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
	if Drill.isHit(position, now) then
		state.startedAt = now
		return "hit"
	end
	state.phase = "cooldown"
	state.cooldownUntil = now + Config.Training.drillCooldownSeconds
	return "miss"
end

return Drill
