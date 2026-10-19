--!strict
-- Collision group names and fence geometry for the private plots (docs/PLAN.md, Step 7, decision 6).
-- Each plot has one group for its fence (Fence_N) and one for its owner's character (Owner_N); the
-- two never collide, every other pair does. Pure, so the rules are unit tested; PlotAccess applies them.

local PlotGroups = {}

PlotGroups.MAX_GROUPS = 32 -- the engine limit, shared with every other group in the game
PlotGroups.WALL_HEIGHT = 14 -- a fence a visitor cannot jump over, invisible above the low fence

function PlotGroups.fence(index: number): string
	return "Fence_" .. index
end

function PlotGroups.owner(index: number): string
	return "Owner_" .. index
end

-- Every group the plots need, for `count` plots, in a stable order.
function PlotGroups.all(count: number): { string }
	local names = {}
	for index = 1, count do
		table.insert(names, PlotGroups.fence(index))
		table.insert(names, PlotGroups.owner(index))
	end
	return names
end

-- Pairs that must not collide: the owner's group with its own fence.
function PlotGroups.passes(index: number): (string, string)
	return PlotGroups.owner(index), PlotGroups.fence(index)
end

-- Whether a character in `characterGroup` is stopped by the fence of plot `index`.
function PlotGroups.blocked(characterGroup: string, index: number): boolean
	return characterGroup ~= PlotGroups.owner(index)
end

-- The gap in the front fence, from the right edge of the left piece to the left edge of the right
-- piece (both in the plot's x axis). Returns the centre and the width; nil when there is no gap.
function PlotGroups.gap(leftEdge: number, rightEdge: number): (number?, number?)
	if rightEdge <= leftEdge then
		return nil, nil
	end
	return (leftEdge + rightEdge) / 2, rightEdge - leftEdge
end

return PlotGroups
