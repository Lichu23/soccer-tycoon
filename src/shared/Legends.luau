--!strict
-- The Legend Trials (docs/PLAN.md, Step 1): what each Legend asks for, how far the player is, and
-- whether the Legend can be bought. A goal that has been reached is recorded for good in
-- `data.trials`, so a New Season never undoes it. Pure on the data, so it is unit tested; the pad
-- and the capsule panel only show what this says, the server decides the purchase.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

export type GoalView = {
	id: string,
	text: string,
	have: number,
	need: number,
	done: boolean,
}

local Legends = {}

-- Floor 4 is reached when the last cash floor is complete (the same rule as its gate).
function Legends.reached(data: ProgressData): boolean
	return Roster.floorUnlocked(data, Config.LegendFloor)
end

function Legends.isLegend(id: string): boolean
	local def = Config.PlayersById[id]
	return def ~= nil and def.floor >= Config.LegendFloor
end

-- How far the player is on one goal right now: (have, need), `have` never above `need`.
local function measure(data: ProgressData, goal: Config.TrialGoal): (number, number)
	if goal.kind == "ownFloors" then
		local have, need = 0, 0
		for _, def in Config.Players do
			if def.floor <= goal.target then
				need += 1
				if data.players[def.id] ~= nil then
					have += 1
				end
			end
		end
		return have, need
	elseif goal.kind == "trained" then
		local level = goal.level or 1
		local have = 0
		for _, owned in data.players do
			if owned.level >= level then
				have += 1
			end
		end
		return math.min(have, goal.target), goal.target
	end
	return math.min(data.stadiumTier, goal.target), goal.target
end

local function goalText(goal: Config.TrialGoal): string
	if goal.kind == "ownFloors" then
		return if goal.target <= 1 then "Own floor 1" else `Own floors 1-{goal.target}`
	elseif goal.kind == "trained" then
		return `{goal.target} players at level {goal.level or 1}`
	end
	return `Stadium tier {goal.target}`
end

local function flagsOf(data: ProgressData, id: string): { [string]: boolean }
	local trials = data.trials
	return (trials and trials[id]) or {}
end

-- The goals of a Legend with the player's progress, in order. A recorded goal is done for good.
function Legends.goals(data: ProgressData, id: string): { GoalView }
	local views: { GoalView } = {}
	local flags = flagsOf(data, id)
	local goals: { Config.TrialGoal } = Config.LegendTrials[id] or {}
	for _, goal in goals do
		local have, need = measure(data, goal)
		table.insert(views, {
			id = goal.id,
			text = goalText(goal),
			have = have,
			need = need,
			done = flags[goal.id] == true or have >= need,
		})
	end
	return views
end

-- (done, total) goals of a Legend.
function Legends.goalCount(data: ProgressData, id: string): (number, number)
	local done = 0
	local views = Legends.goals(data, id)
	for _, view in views do
		if view.done then
			done += 1
		end
	end
	return done, #views
end

-- Records every goal the player has reached right now, for good. Call after anything that changes
-- the roster, the levels or the stadium, and before a New Season resets them.
function Legends.record(data: ProgressData)
	if data.trials == nil then
		data.trials = {}
	end
	local trials = data.trials :: { [string]: { [string]: boolean } }
	for id, goals in Config.LegendTrials do
		for _, goal in goals do
			local have, need = measure(data, goal)
			if have >= need then
				local flags = trials[id]
				if flags == nil then
					flags = {}
					trials[id] = flags
				end
				flags[goal.id] = true
			end
		end
	end
end

-- "unknown", "owned", "locked" (floor 4 not reached), "goals" (a goal is open), "cannotAfford" or
-- "ready". Legends are bought with cash on top of the goals (or with Robux, a separate path).
function Legends.status(data: ProgressData, id: string): string
	local def = Config.PlayersById[id]
	if def == nil or not Legends.isLegend(id) then
		return "unknown"
	end
	if data.players[id] ~= nil then
		return "owned"
	end
	if not Legends.reached(data) then
		return "locked"
	end
	local done, total = Legends.goalCount(data, id)
	if done < total then
		return "goals"
	end
	if data.cash < def.price then
		return "cannotAfford"
	end
	return "ready"
end

return Legends
