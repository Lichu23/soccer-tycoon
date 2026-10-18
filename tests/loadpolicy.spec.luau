--!nocheck
local T = require("./framework")
local LoadPolicy = T.load("server/LoadPolicy")

T.suite("load policy")

T.test("retries while the player is in the game and time remains", function()
	T.eq(LoadPolicy.shouldCancel(0, 20, true), false)
	T.eq(LoadPolicy.shouldCancel(19.9, 20, true), false)
	T.eq(LoadPolicy.shouldCancel(20, 20, true), false) -- exactly the timeout still retries
end)

T.test("gives up after the timeout so the lock is never stolen", function()
	T.eq(LoadPolicy.shouldCancel(20.1, 20, true), true)
end)

T.test("stops at once when the player left", function()
	T.eq(LoadPolicy.shouldCancel(0, 20, false), true)
end)

T.test("a loaded profile plays", function()
	T.eq(LoadPolicy.outcome(true, true), "play")
end)

T.test("a profile that could not load kicks the player, never a blank profile", function()
	T.eq(LoadPolicy.outcome(false, true), "kick")
end)

T.test("a profile that could not load for a player who already left is ignored", function()
	T.eq(LoadPolicy.outcome(false, false), "ignore")
end)
