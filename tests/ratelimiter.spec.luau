--!nocheck
local T = require("./framework")
local RateLimiter = T.load("server/RateLimiter")

T.suite("rate limiter")

local function clock()
	local time = 0
	return {
		now = function()
			return time
		end,
		advance = function(seconds: number)
			time += seconds
		end,
	}
end

T.test("a burst is allowed, then requests are refused", function()
	local c = clock()
	local bucket = RateLimiter.bucket(1, 3, c.now)
	T.eq(bucket:allow(1), true)
	T.eq(bucket:allow(1), true)
	T.eq(bucket:allow(1), true)
	T.eq(bucket:allow(1), false)
end)

T.test("tokens come back over time but never above the burst", function()
	local c = clock()
	local bucket = RateLimiter.bucket(2, 3, c.now)
	for _ = 1, 3 do
		bucket:allow(1)
	end
	T.eq(bucket:allow(1), false)
	c.advance(0.5) -- 1 token
	T.eq(bucket:allow(1), true)
	T.eq(bucket:allow(1), false)
	c.advance(100)
	for _ = 1, 3 do
		T.eq(bucket:allow(1), true)
	end
	T.eq(bucket:allow(1), false)
end)

T.test("players have separate buckets", function()
	local c = clock()
	local bucket = RateLimiter.bucket(1, 1, c.now)
	T.eq(bucket:allow(1), true)
	T.eq(bucket:allow(1), false)
	T.eq(bucket:allow(2), true)
end)

T.test("penalties keep a spammer refused for a while", function()
	local c = clock()
	local bucket = RateLimiter.bucket(1, 4, c.now)
	T.eq(bucket:allow(1), true)
	bucket:penalize(1, 3) -- 3 tokens left, then 3 taken
	T.eq(bucket:allow(1), false)
	c.advance(1)
	T.eq(bucket:allow(1), true) -- 1 token came back
	T.eq(bucket:allow(1), false)
end)

T.test("forget resets a player", function()
	local c = clock()
	local bucket = RateLimiter.bucket(1, 1, c.now)
	bucket:allow(1)
	T.eq(bucket:allow(1), false)
	bucket:forget(1)
	T.eq(bucket:allow(1), true)
end)

T.test("a cooldown allows one use per period for each player", function()
	local c = clock()
	local cooldown = RateLimiter.cooldown(10, c.now)
	T.eq(cooldown:tryUse(1), true)
	T.eq(cooldown:tryUse(1), false)
	T.eq(cooldown:tryUse(2), true)
	c.advance(9.9)
	T.eq(cooldown:tryUse(1), false)
	c.advance(0.2)
	T.eq(cooldown:tryUse(1), true)
	cooldown:forget(1)
	T.eq(cooldown:tryUse(1), true)
end)
