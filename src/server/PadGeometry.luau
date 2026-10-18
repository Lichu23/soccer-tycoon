--!strict
-- Whether a player stands on a pad. The position is given in the pad's own space (the pad part's
-- CFrame:PointToObjectSpace of the character's root), so rotated plots work the same way.

local PadGeometry = {}

-- The root part of a standing character is about 3 studs above the floor; allow a little jump.
PadGeometry.MIN_HEIGHT = -1.5
PadGeometry.MAX_HEIGHT = 6.5

function PadGeometry.isOn(
	localX: number,
	localY: number,
	localZ: number,
	sizeX: number,
	sizeZ: number
): boolean
	return math.abs(localX) <= sizeX / 2
		and math.abs(localZ) <= sizeZ / 2
		and localY >= PadGeometry.MIN_HEIGHT
		and localY <= PadGeometry.MAX_HEIGHT
end

return PadGeometry
