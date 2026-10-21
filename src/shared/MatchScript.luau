--!strict
-- When things happen in a drawn match (client/MatchView): the score is decided by the server at kick-off
-- (MatchStarted), and this spreads its goals over the match so the ball is in play the whole time and
-- every goal has its own attack. Pure, so it is unit tested. Times are seconds from kick-off.
--
-- A match: the players line up (`kickoff`), open play until the first attack, the attack ends in a goal
-- at `at`, the scorers celebrate until `resetAt`, then play restarts from the middle. The last goal comes
-- just before the whistle, and its celebration runs past it.

local MatchScript = {}

export type Goal = {
	side: number, -- 1 our team scores (towards +x), -1 the rivals score (towards -x)
	attackFrom: number, -- the attack that ends in this goal starts
	at: number, -- the ball crosses the line
	resetAt: number, -- the celebration ends and the ball goes back to the middle
}

export type Script = {
	kickoff: number, -- the line-up is over and the ball is played
	goals: { Goal },
}

local LINE_UP = 1 -- seconds to walk back to the formation (at most 15% of the match)
local BEFORE_WHISTLE = 0.5 -- the last goal goes in this long before the match ends
local ATTACK_MAX = 2.4
local CELEBRATE_MAX = 1

-- The order of the goals: the rivals score first when they score at all, then the goals alternate
-- while they have any left, and ours fill the rest, so the match always ends on our goal.
function MatchScript.order(goalsFor: number, goalsAgainst: number): { number }
	local sequence = {}
	local ours, theirs = goalsFor, goalsAgainst
	local nextSide = if theirs > 0 then -1 else 1
	while ours + theirs > 0 do
		if (nextSide == -1 and theirs > 0 and theirs < ours) or ours == 0 then
			table.insert(sequence, -1)
			theirs -= 1
		else
			table.insert(sequence, 1)
			ours -= 1
		end
		nextSide = -nextSide
	end
	return sequence
end

-- The timeline of a match of `duration` seconds with this score.
function MatchScript.build(duration: number, goalsFor: number, goalsAgainst: number): Script
	local kickoff = math.min(LINE_UP, duration * 0.15)
	local lastGoalAt = math.max(duration - BEFORE_WHISTLE, kickoff + 0.5)
	local sequence = MatchScript.order(goalsFor, goalsAgainst)
	local goals: { Goal } = {}
	local count = #sequence
	if count == 0 then
		return { kickoff = kickoff, goals = goals }
	end
	local slot = (lastGoalAt - kickoff) / count
	local attack = math.min(ATTACK_MAX, slot * 0.7)
	local celebrate = math.min(CELEBRATE_MAX, slot * 0.25)
	for index, side in sequence do
		local at = kickoff + slot * index
		table.insert(goals, {
			side = side,
			attackFrom = at - attack,
			at = at,
			-- The last celebration runs past the whistle into the next match's line-up.
			resetAt = if index == count then at + CELEBRATE_MAX else at + celebrate,
		})
	end
	return { kickoff = kickoff, goals = goals }
end

-- The score after `time` seconds: our goals and theirs.
function MatchScript.score(script: Script, time: number): (number, number)
	local ours, theirs = 0, 0
	for _, goal in script.goals do
		if goal.at <= time then
			if goal.side == 1 then
				ours += 1
			else
				theirs += 1
			end
		end
	end
	return ours, theirs
end

return MatchScript
