--!strict
-- Where the players stand on the court for a match drawing. Pure math in the court's own space:
-- x runs along the length (our team attacks towards +x), z across the width, both measured from
-- the court centre. Our team takes the left half, the opponents the right half.

local Formation = {}

export type Spot = { x: number, z: number }

-- Rows of players for a team of `count` (1 to 11): a back line, middle lines and a front line.
local function rowsFor(count: number): { number }
	if count <= 1 then
		return { 1 }
	elseif count == 2 then
		return { 1, 1 }
	elseif count == 3 then
		return { 1, 2 }
	elseif count == 4 then
		return { 2, 2 }
	elseif count == 5 then
		return { 1, 2, 2 }
	elseif count == 6 then
		return { 2, 2, 2 }
	elseif count == 7 then
		return { 1, 3, 3 }
	elseif count == 8 then
		return { 3, 3, 2 }
	elseif count == 9 then
		return { 3, 3, 3 }
	elseif count == 10 then
		return { 4, 3, 3 }
	end
	return { 4, 4, 3 }
end

-- Spots for `count` players of one team on a court of `length` x `width`. `side` is -1 for our
-- team (left half) and 1 for the opponents (right half).
function Formation.spots(count: number, length: number, width: number, side: number): { Spot }
	local rows = rowsFor(math.clamp(count, 1, 11))
	local spots: { Spot } = {}
	local rowCount = #rows
	for rowIndex, inRow in rows do
		-- Rows go from the goal line (the back) to just before the centre line.
		local fraction = (rowIndex - 0.5) / rowCount
		local x = side * (length / 2 - fraction * (length / 2) * 0.9)
		for slot = 1, inRow do
			local z = (slot - (inRow + 1) / 2) * (width / (inRow + 1)) * 1.5
			table.insert(spots, { x = x, z = z })
		end
	end
	return spots
end

return Formation
