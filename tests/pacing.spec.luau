--!nocheck
-- A player who always buys the next goal as soon as it is affordable, played through the real
-- game logic (Goals, Actions, MatchLogic, Boosts) with a clock. It checks the pacing of the first
-- minutes against docs/PLAN.md, Steps 2 and 3, and it prints the timeline.
local T = require("./framework")
local Actions = T.load("server/Actions")
local Boosts = T.load("server/Boosts")
local Economy = T.load("server/Economy")
local Goals = T.load("shared/Goals")
local MatchLogic = T.load("server/MatchLogic")
local ProfileSchema = T.load("server/ProfileSchema")
local Roster = T.load("shared/Roster")

T.suite("pacing")

-- walkSeconds: time the player needs to walk to a pad and stand on it once it is affordable.
-- The hold itself is 1 second and the server checks ten times a second.
local function simulate(walkSeconds, seconds, luck)
	local data = ProfileSchema.newProfile()
	local session = { data = data }
	Actions.onChange = function() end
	local events = {}
	local function mark(name, t)
		if events[name] == nil then
			events[name] = t
		end
	end

	local rng = function()
		return luck
	end
	local matchesPlayed, matchesInRow = 0, 0
	local nextMatchAt = nil
	local pendingPurchase = nil -- { at, goal }
	local dt = 0.1
	local t = 0
	while t < seconds do
		-- matches
		if data.fieldStarted then
			if nextMatchAt == nil then
				nextMatchAt = t + MatchLogic.interval(data)
			end
			if t >= nextMatchAt then
				local state = { matchesInRow = matchesInRow, matchesPlayed = matchesPlayed }
				local plan = MatchLogic.plan(data, state, rng)
				local result = if plan then MatchLogic.resolve(data, state, plan) else nil
				if result then
					Economy.grant(data, result.payout)
					matchesPlayed += 1
					matchesInRow += 1
					data.flags.milestones.first_match = data.flags.milestones.first_match or 1
					mark("first match", t)
					if result.hatTrick then
						mark("first hat-trick", t)
					end
				end
				nextMatchAt = t + MatchLogic.interval(data)
			end
		end
		Boosts.tick(data, dt)

		-- the player acts on the current goal
		local goal = Goals.next(data, true)
		if pendingPurchase == nil and goal.cost and data.cash >= goal.cost then
			pendingPurchase = { at = t + walkSeconds + 1.2, goal = goal }
		end
		if pendingPurchase and t >= pendingPurchase.at then
			local goalNow = pendingPurchase.goal
			pendingPurchase = nil
			if goalNow.kind == "player" then
				if Actions.buyPlayer(session, goalNow.id) then
					local owned = Roster.ownedCount(data)
					mark("player " .. owned, t)
				end
			elseif goalNow.kind == "store" then
				if Actions.buyStore(session, goalNow.id, nil) then
					mark("first upgrade", t)
				end
			elseif goalNow.kind == "stadium" then
				if Actions.upgradeStadium(session, nil) then
					mark("stadium tier 2", t)
				end
			end
		end
		t += dt
	end
	return events, data
end

local function clock(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function timeline(events)
	local order = {
		"player 1",
		"first match",
		"first upgrade",
		"player 2",
		"player 3",
		"player 4",
		"first hat-trick",
		"stadium tier 2",
	}
	local parts = {}
	for _, name in order do
		table.insert(parts, name .. " " .. (events[name] and clock(events[name]) or "-"))
	end
	return table.concat(parts, " | ")
end

T.test("an instant buyer matches the Step 3 timeline", function()
	local events = simulate(0, 900, 0.5)
	print("[pacing] instant buyer:   " .. timeline(events))
	T.truthy(events["player 1"] and events["player 1"] <= 5, "first purchase at once ($15 start)")
	T.truthy(
		events["first match"] and events["first match"] <= 8,
		"first match about 5 s after the purchase"
	)
end)

T.test("a walking buyer buys the first player within the 30 s target", function()
	local events = simulate(8, 900, 0.5)
	print("[pacing] walking buyer:   " .. timeline(events))
	T.truthy(events["player 1"] <= 30, "time to first purchase")
end)

T.test("the first stadium upgrade comes around minute 5 and not before minute 3", function()
	local events = simulate(8, 1200, 0.5)
	local tier = events["stadium tier 2"]
	T.truthy(tier ~= nil, "the stadium upgrade happens")
	print("[pacing] stadium upgrade at " .. clock(tier))
	T.truthy(tier >= 180 and tier <= 480, "stadium upgrade between minute 3 and minute 8")
end)

T.test("the scripted first hat-trick arrives about minute 4", function()
	local events = simulate(8, 1200, 0.99) -- bad luck: only the scripted one can happen
	local hat = events["first hat-trick"]
	print("[pacing] scripted hat-trick at " .. (hat and clock(hat) or "-"))
	T.truthy(hat ~= nil, "a hat-trick happens")
	T.truthy(hat >= 180 and hat <= 330, "scripted hat-trick between minute 3 and minute 5.5")
end)

T.test("a slow player still gets there, just later", function()
	local fast = simulate(8, 1500, 0.5)
	local slow = simulate(30, 1500, 0.5)
	T.truthy(slow["stadium tier 2"] ~= nil)
	T.truthy(slow["stadium tier 2"] >= fast["stadium tier 2"])
end)
