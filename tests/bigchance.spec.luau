--!nocheck
local T = require("./framework")
local Config = T.load("shared/Config")
local Freekick = T.load("shared/Freekick")
local BigChance = T.load("shared/BigChance")

T.suite("big chance (a full-screen shot from one of three spots during the matches)")

local RULES = Config.BigChance
local T0 = 1000

-- A chance taken on `spot`: the reticle glides from its stageAt.
local function aiming(spot: number?)
	local state = BigChance.new()
	T.eq(BigChance.offer(state, T0, spot or 2), true)
	T.eq(BigChance.take(state, T0 + 1), true)
	return state
end

-- The first moment after the reticle starts when it is at about `x` across and `y` up.
local function findAim(state, x: number, y: number): number
	for step = 0, 9000 do -- inside the shot clock
		local at = state.stageAt + step * 0.001
		local ax, ay = Freekick.aimAt(state, at)
		if math.abs(ax - x) < 0.06 and math.abs(ay - y) < 0.08 then
			return at
		end
	end
	error("the reticle never reached the point")
end

-- The first moment after the meter moves when the power is about `power`.
local function findPower(state, power: number): number
	for step = 0, 2000 do
		local at = state.holdAt + step * 0.001
		if math.abs(Freekick.powerAt(state, at) - power) < 0.005 then
			return at
		end
	end
	error("the meter never reached the power")
end

T.test("opens at the stadium tier set in Config", function()
	T.eq(BigChance.unlocked(RULES.minTier - 1), false)
	T.eq(BigChance.unlocked(RULES.minTier), true)
end)

T.test("the gap between chances stays inside minMatches and maxMatches", function()
	T.eq(BigChance.gap(0), RULES.minMatches)
	T.eq(BigChance.gap(1), RULES.maxMatches)
	for i = 0, 20 do
		local gap = BigChance.gap(i / 20)
		T.truthy(gap >= RULES.minMatches and gap <= RULES.maxMatches)
		T.eq(gap, math.floor(gap))
	end
end)

T.test("every roll picks one of the three spots", function()
	T.eq(#RULES.spots, 3)
	T.eq(BigChance.pickSpot(0), 1)
	T.eq(BigChance.pickSpot(0.5), 2)
	T.eq(BigChance.pickSpot(1), 3)
	-- The keeper shades to the near post of an angled spot.
	T.truthy(BigChance.keeperX(1) < 0)
	T.eq(BigChance.keeperX(2), 0)
	T.truthy(BigChance.keeperX(3) > 0)
end)

T.test("an offer left alone ends with nothing taken", function()
	local state = BigChance.new()
	T.eq(BigChance.offer(state, T0, 1), true)
	T.eq(BigChance.offer(state, T0 + 1, 2), false) -- one at a time
	T.eq(state.spot, 1)
	T.eq(BigChance.take(state, T0 + RULES.offerSeconds + RULES.graceSeconds + 0.1), false)
	T.eq(state.phase, "none")
end)

T.test("a take tapped at the offer's end still counts when it arrives a little late", function()
	local state = BigChance.new()
	BigChance.offer(state, T0, 2)
	T.eq(BigChance.take(state, T0 + RULES.offerSeconds + RULES.graceSeconds - 0.05), true)
	T.eq(state.phase, "aim")
end)

T.test("a tap before the reticle glides does not lock it", function()
	local state = aiming()
	T.eq(BigChance.lock(state, T0 + 1, T0 + 1), false)
	T.eq(state.phase, "aim")
end)

T.test("the aim, then the power: a good shot away from the keeper is a goal", function()
	local state = aiming(1) -- the keeper shades to the left post
	local at = findAim(state, 0.7, 0.4) -- the far side
	T.eq(BigChance.lock(state, at, at), true)
	T.eq(state.phase, "power")
	T.eq(BigChance.strike(state, at + 0.1, at + 0.1), nil) -- the meter has not moved yet
	local shot = findPower(state, Config.Training.freekickPowerSweet)
	T.eq(BigChance.strike(state, shot, shot), "goal")
	T.eq(state.phase, "shot")
	T.eq(BigChance.strike(state, shot + 0.1, shot + 0.1), nil) -- one shot only
end)

T.test("a shot at the keeper is saved, a soft one rolls to him", function()
	local state = aiming(3) -- the keeper shades to the right post
	local at = findAim(state, BigChance.keeperX(3), 0.3)
	BigChance.lock(state, at, at)
	local shot = findPower(state, Config.Training.freekickPowerSweet)
	T.eq(BigChance.strike(state, shot, shot), "saved")

	local soft = aiming(2)
	local aimAt = findAim(soft, 0.7, 0.4)
	BigChance.lock(soft, aimAt, aimAt)
	local weak = findPower(soft, Config.Training.freekickWeakPower - 0.1)
	T.eq(BigChance.strike(soft, weak, weak), "saved")
end)

T.test("a stamp is trusted only a little into the past and never in the future", function()
	local state = aiming()
	local glide = { stageAt = state.stageAt } -- the lock moves stageAt on
	local now = state.stageAt + 1
	BigChance.lock(state, now, now - 5)
	local x, y = Freekick.aimAt(glide, now - RULES.graceSeconds)
	T.near(state.aimX, x, 1e-9)
	T.near(state.aimY, y, 1e-9)

	local future = aiming()
	local futureGlide = { stageAt = future.stageAt }
	local at = future.stageAt + 1
	BigChance.lock(future, at, at + 0.5)
	local fx = Freekick.aimAt(futureGlide, at)
	T.near(future.aimX, fx, 1e-9)
end)

T.test(
	"the shot clock running out lets the keeper smother the ball, then the chance ends",
	function()
		local state = aiming()
		local clock = state.endsAt
		T.eq(BigChance.normalize(state, clock + RULES.graceSeconds - 0.01), false)
		T.eq(BigChance.lock(state, clock + 0.1, clock + 0.1), false) -- too late to lock
		T.eq(BigChance.normalize(state, clock + RULES.graceSeconds + 0.01), true)
		T.eq(state.phase, "shot")
		T.eq(state.outcome, "late")
		T.eq(state.stageAt, clock)
		BigChance.normalize(state, BigChance.filmEnd(state) + 0.01)
		T.eq(state.phase, "none")
		-- And the next chance can come.
		T.eq(BigChance.offer(state, BigChance.filmEnd(state) + 1, 2), true)
	end
)
