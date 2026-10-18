--!nocheck
local T = require("./framework")
local HoldTracker = T.load("server/HoldTracker")
local PadGeometry = T.load("server/PadGeometry")

T.suite("hold tracker")

local function tracker()
	return HoldTracker.new(1)
end

T.test("standing on a ready pad for one second completes it", function()
	local t = tracker()
	T.eq(t:update(1, "padA", "ready", false, 0), nil) -- starts the hold
	T.eq(t:update(1, "padA", "ready", false, 0.5), nil)
	T.eq(t:update(1, "padA", "ready", false, 0.9), nil)
	T.eq(t:update(1, "padA", "ready", false, 1.0), "complete")
end)

T.test("a one-time pad completes once until the player steps off", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	T.eq(t:update(1, "padA", "ready", false, 1.0), "complete")
	T.eq(t:update(1, "padA", "ready", false, 2.5), nil)
	T.eq(t:update(1, "padA", "ready", false, 4.0), nil)
	t:update(1, nil, "ready", false, 4.1) -- steps off
	t:update(1, "padA", "ready", false, 5)
	T.eq(t:update(1, "padA", "ready", false, 6), "complete") -- a fresh hold
end)

T.test("a repeatable pad completes every hold while the player stays", function()
	local t = tracker()
	t:update(1, "levelUp", "ready", true, 0)
	T.eq(t:update(1, "levelUp", "ready", true, 1.0), "complete")
	T.eq(t:update(1, "levelUp", "ready", true, 1.5), nil)
	T.eq(t:update(1, "levelUp", "ready", true, 2.0), "complete")
	T.eq(t:update(1, "levelUp", "ready", true, 3.0), "complete")
end)

T.test("stepping off cancels the hold and nothing is bought", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	T.eq(t:update(1, "padA", "ready", false, 0.8), nil)
	T.eq(t:update(1, nil, "ready", false, 0.9), nil) -- off the pad
	T.eq(t:get(1), nil)
	t:update(1, "padA", "ready", false, 1.0) -- back on: the hold starts again
	T.eq(t:update(1, "padA", "ready", false, 1.5), nil)
	T.eq(t:update(1, "padA", "ready", false, 2.0), "complete")
end)

T.test("a blocked pad never fills", function()
	local t = tracker()
	for time = 0, 10 do
		T.eq(t:update(1, "padA", "cannotAfford", false, time), nil)
	end
	T.eq(t:get(1).startedAt, nil)
end)

T.test("when a blocked pad becomes ready the hold starts then", function()
	local t = tracker()
	t:update(1, "padA", "cannotAfford", false, 0)
	t:update(1, "padA", "cannotAfford", false, 5)
	T.eq(t:update(1, "padA", "ready", false, 6), nil) -- starts now
	T.eq(t:update(1, "padA", "ready", false, 6.9), nil)
	T.eq(t:update(1, "padA", "ready", false, 7.0), "complete")
end)

T.test("cash that vanishes mid-hold blocks the pad again", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	T.eq(t:update(1, "padA", "cannotAfford", false, 0.9), nil)
	T.eq(t:update(1, "padA", "ready", false, 1.2), nil) -- restarts at 1.2
	T.eq(t:update(1, "padA", "ready", false, 2.1), nil)
	T.eq(t:update(1, "padA", "ready", false, 2.2), "complete")
end)

T.test("moving to another pad starts over", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	t:update(1, "padA", "ready", false, 0.9)
	T.eq(t:update(1, "padB", "ready", false, 1.0), nil)
	T.eq(t:update(1, "padB", "ready", false, 1.5), nil)
	T.eq(t:update(1, "padB", "ready", false, 2.0), "complete")
end)

T.test("players are independent", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	t:update(2, "padA", "ready", false, 0.5)
	T.eq(t:update(1, "padA", "ready", false, 1.0), "complete")
	T.eq(t:update(2, "padA", "ready", false, 1.0), nil)
	T.eq(t:update(2, "padA", "ready", false, 1.5), "complete")
end)

T.test("forget drops a player's state", function()
	local t = tracker()
	t:update(1, "padA", "ready", false, 0)
	t:forget(1)
	T.eq(t:get(1), nil)
end)

T.test("the hold time is a single number", function()
	local t = HoldTracker.new(2.5)
	t:update(1, "padA", "ready", false, 0)
	T.eq(t:update(1, "padA", "ready", false, 2.4), nil)
	T.eq(t:update(1, "padA", "ready", false, 2.5), "complete")
end)

T.suite("pad geometry")

T.test("the middle of the pad counts", function()
	T.eq(PadGeometry.isOn(0, 3, 0, 6, 6), true)
end)

T.test("the pad edges count and just outside does not", function()
	T.eq(PadGeometry.isOn(3, 3, 3, 6, 6), true)
	T.eq(PadGeometry.isOn(3.1, 3, 0, 6, 6), false)
	T.eq(PadGeometry.isOn(0, 3, -3.1, 6, 6), false)
end)

T.test("height must be near the floor", function()
	T.eq(PadGeometry.isOn(0, -2, 0, 6, 6), false) -- under the pad
	T.eq(PadGeometry.isOn(0, 6.5, 0, 6, 6), true) -- jumping
	T.eq(PadGeometry.isOn(0, 7, 0, 6, 6), false) -- on the next floor above
end)

T.test("a wide claim ring works the same", function()
	T.eq(PadGeometry.isOn(6.9, 3, 0, 14, 14), true)
	T.eq(PadGeometry.isOn(7.1, 3, 0, 14, 14), false)
end)
