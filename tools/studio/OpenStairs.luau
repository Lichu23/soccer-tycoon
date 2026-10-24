-- Opens up the stairs of ServerStorage.PlotTemplate: the solid walls along the flights become slim
-- sloped glass handrails, the hole railings turn to glass, the outer walls turn to light glass, and each floor gets an invisible FloorSpot_k
-- (where the HUD floor switcher puts the player). Run through the Studio MCP (execute_luau, Edit
-- mode). Safe to run again. The same geometry is in BuildPlotTemplate.luau for a fresh build.
-- It works in building space (the template is turned a quarter, see ToPlot there) and turns back.

local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("PlotTemplate")
local stairs = template:WaitForChild("Stairs")
local building = template:WaitForChild("Building")

local ToPlot = CFrame.new(-70, 0, 60) * CFrame.Angles(0, math.pi / 2, 0)
local FLOOR, FloorHeight = 0.7, 16
local innerX0, innerZ1 = -98, 198 -- the inner face of the left and back walls (building space)
local Landing, Corner, LaneWidth, Steps = 8, 26, 9, 16
local xLanding, xFar = innerX0 + Landing, innerX0 + Corner
local zBoundary, zFront = innerZ1 - LaneWidth, innerZ1 - 2 * LaneWidth

local function floorTop(k: number): number
	return FLOOR + FloorHeight * (k - 1)
end

-- Remove what an earlier run (or the first build) made.
for _, child in stairs:GetChildren() do
	if child.Name:match("^Wall_F") or child.Name:match("^HandRail") or child.Name:match("^Plate_") or child.Name:match("^FloorSpot_") or child.Name == "StairsSign" then
		child:Destroy()
	end
end

local function place(name: string, size: Vector3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = ToPlot * cf
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = stairs
	return part
end

local GLASS = Color3.fromRGB(190, 225, 240)
local function glassify(part: Part, transparency: number)
	part.Material = Enum.Material.Glass
	part.Color = GLASS
	part.Transparency = transparency
end

-- A slim glass handrail that follows a flight: from the foot to the top, 3 studs above the steps.
local rise, run = FloorHeight / Steps, (xFar - xLanding) / Steps
local flights = { { lane = "A", towardWall = true }, { lane = "B", towardWall = false }, { lane = "A", towardWall = true } }
for index, flight in flights do
	local base = floorTop(index)
	local xFoot = if flight.towardWall then xFar else xLanding
	local xTop = if flight.towardWall then xLanding else xFar
	local from = Vector2.new(xFoot, base + rise + 3)
	local to = Vector2.new(xTop, base + FloorHeight + 3)
	local mid = (from + to) / 2
	local delta = to - from
	local sides = { zBoundary }
	if flight.lane == "B" then
		table.insert(sides, zFront)
	end
	for _, z in sides do
		local rail = place(
			"HandRail_F" .. index .. "_" .. (if z == zBoundary then "Boundary" else "Front"),
			Vector3.new(delta.Magnitude, 0.3, 0.3),
			CFrame.new(mid.X, mid.Y, z) * CFrame.Angles(0, 0, math.atan2(delta.Y, delta.X))
		)
		rail.Color = Color3.fromRGB(235, 235, 240)
		rail.Material = Enum.Material.SmoothPlastic
	end
	-- A glass panel under the handrail, so the side of the stairs reads as a railing, not as a wall.
	for _, z in sides do
		local panel = place(
			"HandRail_F" .. index .. "_Glass" .. (if z == zBoundary then "Boundary" else "Front"),
			Vector3.new(delta.Magnitude, 2.6, 0.15),
			CFrame.new(mid.X, mid.Y - 1.4, z) * CFrame.Angles(0, 0, math.atan2(delta.Y, delta.X))
		)
		glassify(panel, 0.6)
		panel.CanCollide = false
	end
end

-- The railings around the holes of the slabs and the outer walls become glass.
for _, name in { "Rail_Floor2", "Rail_Floor3", "Rail_Floor4" } do
	local rail = stairs:FindFirstChild(name)
	if rail then
		glassify(rail, 0.5)
	end
end
for _, name in { "WallBack", "WallLeft", "WallRight" } do
	local wall = building:FindFirstChild(name)
	if wall then
		glassify(wall, 0.72)
	end
end
-- Dark steps (the Style.ui.panel navy), so the stairs stand out from the light floor.
for _, step in stairs:GetChildren() do
	if step.Name:match("^Step_") then
		step.Color = Color3.fromRGB(32, 38, 56)
	end
end

-- Where the floor switcher puts the player: in the room beside the stairs, on every floor.
for k = 1, 4 do
	local spot = place(
		"FloorSpot_" .. k,
		Vector3.new(2, 1, 2),
		CFrame.new(xFar + 16, floorTop(k) + 0.5, zBoundary)
	)
	spot.Transparency = 1
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot:SetAttribute("SpotFloor", k)
end

return "stairs opened: " .. #stairs:GetChildren() .. " parts in Stairs"
