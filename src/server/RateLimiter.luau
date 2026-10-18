--!strict
-- Per-player rate limits and cooldowns with an injectable clock, so they can be unit tested.

export type Bucket = {
	allow: (self: Bucket, key: number) -> boolean,
	penalize: (self: Bucket, key: number, tokens: number) -> (),
	forget: (self: Bucket, key: number) -> (),
}

export type Cooldown = {
	tryUse: (self: Cooldown, key: number) -> boolean,
	forget: (self: Cooldown, key: number) -> (),
}

local RateLimiter = {}

type BucketState = { tokens: number, last: number }

-- Token bucket: `burst` requests at once, refilling `ratePerSecond` tokens per second.
function RateLimiter.bucket(ratePerSecond: number, burst: number, now: () -> number): Bucket
	local states: { [number]: BucketState } = {}

	local function refill(key: number): BucketState
		local time = now()
		local state = states[key]
		if not state then
			state = { tokens = burst, last = time }
			states[key] = state
		else
			state.tokens = math.min(burst, state.tokens + (time - state.last) * ratePerSecond)
			state.last = time
		end
		return state
	end

	local bucket = {} :: Bucket

	function bucket:allow(key: number): boolean
		local state = refill(key)
		if state.tokens >= 1 then
			state.tokens -= 1
			return true
		end
		return false
	end

	-- Bad requests cost extra, so a player spamming them is refused for a while.
	function bucket:penalize(key: number, tokens: number)
		local state = refill(key)
		state.tokens = math.max(-burst, state.tokens - tokens)
	end

	function bucket:forget(key: number)
		states[key] = nil
	end

	return bucket
end

-- Allows one use per `seconds` for each key.
function RateLimiter.cooldown(seconds: number, now: () -> number): Cooldown
	local lastUse: { [number]: number } = {}
	local cooldown = {} :: Cooldown

	function cooldown:tryUse(key: number): boolean
		local time = now()
		local last = lastUse[key]
		if last and time - last < seconds then
			return false
		end
		lastUse[key] = time
		return true
	end

	function cooldown:forget(key: number)
		lastUse[key] = nil
	end

	return cooldown
end

return RateLimiter
