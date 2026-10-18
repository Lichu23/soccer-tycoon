-- Builds the greybox plot template in ServerStorage.PlotTemplate (floor 1 and the tier-1 court).
-- Run through the Studio MCP (execute_luau, Edit mode). Safe to run again: it rebuilds the model.
-- Coordinates are local to the plot: the origin is the middle of the gate on the plaza edge,
-- +Z points into the plot, +X is to the right when looking into it, and y = 0 is the ground
-- reference (ground top 0.5). The server places a clone of this model on a slot (docs/PLAN.md,
-- Step 7). Markers carry PadId attributes from Config, so no script needs a world coordinate.

local ServerStorage = game:GetService("ServerStorage")

local Def = {
	GroundTop = 0.5,
	FloorTop = 0.7,
	Plot = { Width = 160, Depth = 180 },
	Gate = { Width = 16 },
	Fence = { Height = 4, Thickness = 1 },
	Court = { Length = 60, Width = 36, CenterZ = 64 }, -- tier 1, 4 against 4
	Building = { X0 = -80, X1 = 40, Z0 = 120, Z1 = 170, Height = 15.5, Wall = 2, DoorWidth = 12, DoorCenterX = -62 },
	Yard = { X0 = 40, X1 = 80, Z0 = 120, Z1 = 170 },
	Capsule = { Spacing = 12, FirstX = -74, Z = 130, PadZ = 124 },
	Floor1Players = {
		"rashford",
		"grealish",
		"sterling",
		"joao_felix",
		"son",
		"saka",
		"griezmann",
		"pedri",
		"trent",
		"gavi",
	},
}

local COLORS = {
	ground = Color3.fromRGB(106, 150, 84),
	lawn = Color3.fromRGB(125, 175, 100),
	court = Color3.fromRGB(70, 110, 170),
	line = Color3.fromRGB(240, 240, 240),
	wall = Color3.fromRGB(215, 205, 190),
	glass = Color3.fromRGB(170, 210, 230),
	floor = Color3.fromRGB(190, 185, 175),
	fence = Color3.fromRGB(150, 120, 90),
	pedestal = Color3.fromRGB(90, 90, 100),
	counter = Color3.fromRGB(200, 140, 70),
	yard = Color3.fromRGB(150, 190, 120),
	goal = Color3.fromRGB(245, 245, 245),
}

local MARKER_COLORS = {
	claim = Color3.fromRGB(255, 220, 60),
	player = Color3.fromRGB(80, 220, 120),
	field = Color3.fromRGB(70, 150, 255),
	store = Color3.fromRGB(255, 150, 50),
	stadium = Color3.fromRGB(170, 90, 240),
	penalty = Color3.fromRGB(240, 70, 70),
	training = Color3.fromRGB(60, 220, 220),
	spot = Color3.fromRGB(255, 255, 255),
}

local old = ServerStorage:FindFirstChild("PlotTemplate")
if old then
	old:Destroy()
end

local model = Instance.new("Model")
model.Name = "PlotTemplate"

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = model
	return f
end

local function addPart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A box from corner coordinates (x0, x1, z0, z1) and a y range, convenient for walls.
local function addBox(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?): Part
	return addPart(
		parent,
		name,
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		color,
		material
	)
end

local markers = folder("Markers")
local function marker(name: string, padId: string, kind: string, position: Vector3, size: Vector3)
	local part = addPart(markers, name, size, position, MARKER_COLORS[kind] or MARKER_COLORS.spot, Enum.Material.Neon)
	part.Transparency = 0.4
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute("PadId", padId)
	part:SetAttribute("Kind", kind)
	return part
end

local FLOOR = Def.FloorTop
local PAD_Y = FLOOR + 0.1
local PAD = Vector3.new(6, 0.2, 6)

-- Gate anchor (the PrimaryPart) ------------------------------------------------------------
local gate = addPart(model, "Gate", Vector3.new(2, 2, 2), Vector3.new(0, 1, 0), COLORS.line)
gate.Transparency = 1
gate.CanCollide = false
gate.CanQuery = false
gate.CanTouch = false
model.PrimaryPart = gate

-- Ground ------------------------------------------------------------------------------------
local ground = folder("Ground")
addBox(ground, "PlotGround", -Def.Plot.Width / 2, Def.Plot.Width / 2, Def.GroundTop - 1, Def.GroundTop, 0, Def.Plot.Depth, COLORS.ground, Enum.Material.Grass)
-- The pitch zone (between the gate and the building) is a lighter lawn.
addBox(ground, "PitchLawn", -Def.Plot.Width / 2 + 4, Def.Plot.Width / 2 - 4, Def.GroundTop, Def.GroundTop + 0.1, 8, 118, COLORS.lawn, Enum.Material.Grass)
addBox(ground, "YardGround", Def.Yard.X0 + 2, Def.Yard.X1 - 2, Def.GroundTop, FLOOR - 0.1, Def.Yard.Z0 + 2, Def.Yard.Z1 - 2, COLORS.yard, Enum.Material.SmoothPlastic)

-- Fence (low and see-through, with a gap for the gate) ------------------------------------
local fence = folder("Fence")
local half = Def.Plot.Width / 2
local fh, ft = Def.Fence.Height, Def.Fence.Thickness
local top = Def.GroundTop + fh
local gateHalf = Def.Gate.Width / 2
local function fencePart(name: string, x0: number, x1: number, z0: number, z1: number)
	local p = addBox(fence, name, x0, x1, Def.GroundTop, top, z0, z1, COLORS.fence, Enum.Material.Wood)
	p.Transparency = 0.5
	return p
end
fencePart("FrontLeft", -half, -gateHalf, 0, ft)
fencePart("FrontRight", gateHalf, half, 0, ft)
fencePart("Back", -half, half, Def.Plot.Depth - ft, Def.Plot.Depth)
fencePart("Left", -half, -half + ft, 0, Def.Plot.Depth)
fencePart("Right", half - ft, half, 0, Def.Plot.Depth)

-- Tier 1 court ------------------------------------------------------------------------------
local court = folder("Court_T1")
local c = Def.Court
local cx0, cx1 = -c.Length / 2, c.Length / 2
local cz0, cz1 = c.CenterZ - c.Width / 2, c.CenterZ + c.Width / 2
addBox(court, "Surface", cx0, cx1, FLOOR - 0.2, FLOOR, cz0, cz1, COLORS.court, Enum.Material.SmoothPlastic)
local lineY0, lineY1 = FLOOR, FLOOR + 0.05
local lt = 0.5
addBox(court, "LineNear", cx0, cx1, lineY0, lineY1, cz0, cz0 + lt, COLORS.line)
addBox(court, "LineFar", cx0, cx1, lineY0, lineY1, cz1 - lt, cz1, COLORS.line)
addBox(court, "LineLeft", cx0, cx0 + lt, lineY0, lineY1, cz0, cz1, COLORS.line)
addBox(court, "LineRight", cx1 - lt, cx1, lineY0, lineY1, cz0, cz1, COLORS.line)
addBox(court, "LineCenter", -lt / 2, lt / 2, lineY0, lineY1, cz0, cz1, COLORS.line)
-- Goals: two posts and a crossbar at each end.
for _, side in { -1, 1 } do
	local gx = side * (c.Length / 2)
	local gz = c.CenterZ
	local post = 0.5
	local goalHeight = 6
	addBox(court, "GoalPostA", gx - post / 2, gx + post / 2, FLOOR, FLOOR + goalHeight, gz - 5, gz - 5 + post, COLORS.goal)
	addBox(court, "GoalPostB", gx - post / 2, gx + post / 2, FLOOR, FLOOR + goalHeight, gz + 5 - post, gz + 5, COLORS.goal)
	addBox(court, "GoalBar", gx - post / 2, gx + post / 2, FLOOR + goalHeight - post, FLOOR + goalHeight, gz - 5, gz + 5, COLORS.goal)
end

-- Building, floor 1 -------------------------------------------------------------------------
local building = folder("Building")
local b = Def.Building
local top1 = Def.GroundTop + b.Height
addBox(building, "Floor1", b.X0, b.X1, FLOOR - 0.2, FLOOR, b.Z0, b.Z1, COLORS.floor, Enum.Material.SmoothPlastic)
addBox(building, "WallBack", b.X0, b.X1, Def.GroundTop, top1, b.Z1 - b.Wall, b.Z1, COLORS.wall)
addBox(building, "WallLeft", b.X0, b.X0 + b.Wall, Def.GroundTop, top1, b.Z0, b.Z1, COLORS.wall)
addBox(building, "WallRight", b.X1 - b.Wall, b.X1, Def.GroundTop, top1, b.Z0, b.Z1, COLORS.wall)
-- Glass front with a door gap.
local doorL = b.DoorCenterX - b.DoorWidth / 2
local doorR = b.DoorCenterX + b.DoorWidth / 2
local glassA = addBox(building, "GlassFrontLeft", b.X0 + b.Wall, doorL, Def.GroundTop, top1, b.Z0, b.Z0 + b.Wall, COLORS.glass, Enum.Material.Glass)
local glassB = addBox(building, "GlassFrontRight", doorR, b.X1 - b.Wall, Def.GroundTop, top1, b.Z0, b.Z0 + b.Wall, COLORS.glass, Enum.Material.Glass)
glassA.Transparency = 0.6
glassB.Transparency = 0.6
-- The slab above floor 1 (floor 2 is built on it in task 4.1).
addBox(building, "Slab_Floor2", b.X0, b.X1, top1, top1 + 1, b.Z0, b.Z1, COLORS.floor)

-- Capsules and pads (floor 1) ---------------------------------------------------------------
local capsules = folder("Capsules")
for index, playerId in Def.Floor1Players do
	local x = Def.Capsule.FirstX + (index - 1) * Def.Capsule.Spacing
	local capsule = Instance.new("Model")
	capsule.Name = "Capsule_" .. playerId
	local pedestal = addPart(capsule, "Pedestal", Vector3.new(4, 1, 4), Vector3.new(x, FLOOR + 0.5, Def.Capsule.Z), COLORS.pedestal)
	local glass = addPart(capsule, "Glass", Vector3.new(4, 8, 4), Vector3.new(x, FLOOR + 1 + 4, Def.Capsule.Z), COLORS.glass, Enum.Material.Glass)
	glass.Transparency = 0.6
	capsule.PrimaryPart = pedestal
	capsule:SetAttribute("PlayerId", playerId)
	capsule.Parent = capsules
	marker("Player_" .. playerId, playerId, "player", Vector3.new(x, PAD_Y, Def.Capsule.PadZ), PAD)
end

-- Store, locker and trophy spots -----------------------------------------------------------
local fixtures = folder("Fixtures")
addBox(fixtures, "StoreCounter", -68, -28, FLOOR, FLOOR + 3, 164, 167, COLORS.counter)
addBox(fixtures, "LockerSpot", -2, 2, FLOOR, FLOOR + 7, 166, 168, COLORS.counter)
addBox(fixtures, "TrophyShelf", 13, 27, FLOOR, FLOOR + 6, 166, 168, COLORS.counter)
for index, id in { "cashPerMatch", "matchSpeed", "hatTrick", "offline" } do
	marker("Store_" .. id, id, "store", Vector3.new(-62 + (index - 1) * 12, PAD_Y, 156), PAD)
end

-- Pads outside the building ----------------------------------------------------------------
marker("Claim", "claim", "claim", Vector3.new(0, PAD_Y, 8), Vector3.new(14, 0.2, 14))
marker("Field", "field", "field", Vector3.new(Def.Building.DoorCenterX, PAD_Y, 112), PAD)
marker("Stadium", "stadium", "stadium", Vector3.new(44, PAD_Y, c.CenterZ), PAD)
marker("Penalty", "penalty", "penalty", Vector3.new(c.Length / 2 - 9, PAD_Y, c.CenterZ), PAD)
marker("Training", "training", "training", Vector3.new(60, PAD_Y, 145), Vector3.new(10, 0.2, 10))
marker("LockerSpotMarker", "locker", "spot", Vector3.new(0, PAD_Y, 162), Vector3.new(4, 0.2, 4))

-- Tier 1 field slots (4 against 4) and the ball spot ---------------------------------------
local ours = { { -20, 56 }, { -20, 72 }, { -8, 56 }, { -8, 72 } }
local theirs = { { 20, 56 }, { 20, 72 }, { 8, 56 }, { 8, 72 } }
local small = Vector3.new(2, 0.2, 2)
for index, spot in ours do
	local part = marker("FieldSlot_T1_" .. index, "fieldSlot", "spot", Vector3.new(spot[1], PAD_Y, spot[2]), small)
	part:SetAttribute("Tier", 1)
	part:SetAttribute("Index", index)
end
for index, spot in theirs do
	local part = marker("OppSlot_T1_" .. index, "oppSlot", "spot", Vector3.new(spot[1], PAD_Y, spot[2]), small)
	part:SetAttribute("Tier", 1)
	part:SetAttribute("Index", index)
end
marker("BallSpot", "ballSpot", "spot", Vector3.new(0, PAD_Y, c.CenterZ), small)

model.Parent = ServerStorage

local parts, markerCount = 0, 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
for _, m in markers:GetChildren() do
	if m:GetAttribute("PadId") then
		markerCount += 1
	end
end
local cf, size = model:GetBoundingBox()
return string.format("PlotTemplate built: %d parts, %d markers, bounds %s at %s", parts, markerCount, tostring(size), tostring(cf.Position))
