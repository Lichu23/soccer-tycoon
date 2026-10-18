--!strict
-- The one "Next goal" shown under the money label (docs/PLAN.md, Step 1). It follows the buying
-- path: first player (who starts the matches), first upgrade, next players, stadium upgrade.

local Config = require(script.Parent.Config)
local Progress = require(script.Parent.Progress)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

export type Goal = {
	kind: string, -- "claim", "player", "store", "stadium" or "none"
	id: string?, -- the player id or Store upgrade id
	label: string,
	cost: number?, -- cash needed, nil when nothing is bought
}

local Goals = {}

local function playerGoal(data: ProgressData, label: string?): Goal?
	local def = Roster.nextUnowned(data)
	if def == nil then
		return nil
	end
	return { kind = "player", id = def.id, label = label or ("Buy " .. def.name), cost = def.price }
end

function Goals.next(data: ProgressData, hasPlot: boolean): Goal
	if not hasPlot then
		return { kind = "claim", label = "Claim a plot" }
	end

	local owned = Roster.ownedCount(data)
	if owned == 0 then
		local first = playerGoal(data, "Buy your first player")
		if first then
			return first
		end
	end

	-- The first Store upgrade comes before the second player (Step 2, minute 1).
	if data.storeLevels.cashPerMatch == 0 then
		local price = Progress.storePrice(data, "cashPerMatch")
		if price then
			return {
				kind = "store",
				id = "cashPerMatch",
				label = "More cash per match",
				cost = price,
			}
		end
	end

	-- Fill the field first, then the stadium upgrade makes room for more.
	local capacity = Config.StadiumTiers[data.stadiumTier].field
	if owned < capacity then
		local goal = playerGoal(data, nil)
		if goal then
			return goal
		end
	end

	local nextTier = Progress.nextTier(data)
	if nextTier then
		return { kind = "stadium", label = "Stadium upgrade", cost = nextTier.price }
	end

	local goal = playerGoal(data, nil)
	if goal then
		return goal
	end
	return { kind = "none", label = "Keep playing" }
end

return Goals
