--!strict
-- The server-timed pad hold (docs/PLAN.md, Step 5): standing on a pad for the hold time buys it.
-- Pure, with the clock passed in, so it is unit tested. The server calls `update` about ten times
-- a second for each player with the pad they stand on (or nil) and that pad's status.

export type HoldState = {
	padKey: string,
	startedAt: number?, -- nil while the pad is blocked (cannot afford, locked...) or finished
	status: string,
	done: boolean, -- a one-time pad completed: nothing more until the player steps off
}

export type Tracker = {
	update: (
		self: Tracker,
		key: number,
		padKey: string?,
		status: string,
		repeatable: boolean,
		now: number
	) -> string?,
	get: (self: Tracker, key: number) -> HoldState?,
	forget: (self: Tracker, key: number) -> (),
}

local HoldTracker = {}

function HoldTracker.new(holdSeconds: number): Tracker
	local states: { [number]: HoldState } = {}
	local tracker = {} :: Tracker

	-- Returns "complete" on the update where the hold finishes, otherwise nil. A pad whose status
	-- is not "ready" never fills. Stepping off, or moving to another pad, starts over.
	function tracker:update(
		key: number,
		padKey: string?,
		status: string,
		repeatable: boolean,
		now: number
	): string?
		if padKey == nil then
			states[key] = nil
			return nil
		end
		local state = states[key]
		if state == nil or state.padKey ~= padKey then
			state = { padKey = padKey, startedAt = nil, status = status, done = false }
			states[key] = state
		end
		state.status = status
		if status ~= "ready" then
			state.startedAt = nil
			return nil
		end
		if state.done then
			return nil
		end
		local startedAt = state.startedAt
		if startedAt == nil then
			state.startedAt = now
			return nil
		end
		if now - startedAt >= holdSeconds then
			if repeatable then
				state.startedAt = now
			else
				state.startedAt = nil
				state.done = true
			end
			return "complete"
		end
		return nil
	end

	function tracker:get(key: number): HoldState?
		return states[key]
	end

	function tracker:forget(key: number)
		states[key] = nil
	end

	return tracker
end

return HoldTracker
