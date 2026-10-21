--!nocheck
local T = require("./framework")
local MatchScript = T.load("shared/MatchScript")

T.suite("match script")

T.test("the first match (5 s, 1-0) is one attack that scores just before the whistle", function()
	local script = MatchScript.build(5, 1, 0)
	T.eq(#script.goals, 1)
	local goal = script.goals[1]
	T.eq(goal.side, 1)
	T.eq(goal.at, 4.5)
	T.truthy(goal.attackFrom > script.kickoff, "open play before the attack")
	T.truthy(goal.at - goal.attackFrom >= 2, "a long enough attack for the duel")
end)

T.test("the rivals score first and the match always ends on our goal", function()
	T.deepEq(MatchScript.order(3, 1), { -1, 1, 1, 1 })
	T.deepEq(MatchScript.order(3, 2), { -1, 1, -1, 1, 1 })
	T.deepEq(MatchScript.order(2, 0), { 1, 1 })
	for ours = 1, 5 do
		for theirs = 0, ours - 1 do
			local order = MatchScript.order(ours, theirs)
			T.eq(#order, ours + theirs)
			T.eq(order[#order], 1, ours .. "-" .. theirs)
		end
	end
end)

T.test("goals are spread over the match, in order, without overlapping", function()
	for _, duration in { 5, 8, 10 } do
		local script = MatchScript.build(duration, 5, 4)
		local last = script.kickoff
		for index, goal in script.goals do
			T.truthy(
				goal.attackFrom >= last - 1e-9,
				duration .. "s goal " .. index .. " starts after the reset"
			)
			T.truthy(goal.at > goal.attackFrom)
			T.truthy(goal.at <= duration)
			last = goal.resetAt
		end
	end
end)

T.test("the score counts the goals that went in", function()
	local script = MatchScript.build(10, 2, 1)
	T.deepEq({ MatchScript.score(script, 0) }, { 0, 0 })
	T.deepEq({ MatchScript.score(script, script.goals[1].at) }, { 0, 1 })
	T.deepEq({ MatchScript.score(script, 10) }, { 2, 1 })
end)
