-- Builds the greybox plot template in ServerStorage.PlotTemplate: the court, the building with its
-- four floors, stairs and gates. Run through the Studio MCP (execute_luau, Edit mode). Safe to run
-- again: it rebuilds the model.
-- Coordinates are local to the plot: the origin is the middle of the gate on the plaza edge,
-- +Z points into the plot, +X is to the right when looking into it, and y = 0 is the ground
-- reference (ground top 0.5). The server places a clone of this model on a slot (docs/PLAN.md,
-- Step 7). Markers carry PadId attributes from Config, so no script needs a world coordinate.
--
-- Building (floors 1 to 3 hold the cash players, floor 4 the Legends hall), seen from above:
--   * floor 1 has the entrance, a clear gap in the middle of the front wall; the upper floors have
--     a full glass front;
--   * capsules stand against the walls facing the open middle, in buying order: the first player
--     just left of the entrance, then around the left wall, the back wall and the right wall,
--     ending next to the entrance again;
--   * the stairs in the back-left corner are three flights going up and back (a switchback): flight 1
--     (floor 1 to 2) rises along lane A toward the wall, a landing joins both lanes, flight 2 (floor 2
--     to 3) rises along lane B away from the wall, flight 3 (floor 3 to 4) rises along lane A again.
--   * a glass gate (Gate_Floor2, Gate_Floor3, Gate_Floor4) closes the bottom of each flight until the
--     floor before is complete; the server opens it.

local ServerStorage = game:GetService("ServerStorage")

local Def = {
	GroundTop = 0.5,
	FloorTop = 0.7,
	FloorHeight = 16,
	Plot = { Width = 200, Depth = 210 },
	Gate = { Width = 16 },
	Fence = { Height = 4, Thickness = 1 },
	Court = { Length = 60, Width = 36, CenterZ = 64 }, -- tier 1, 4 against 4
	Building = { X0 = -100, X1 = 40, Z0 = 120, Z1 = 200, Wall = 2, DoorWidth = 14, DoorCenterX = -30 },
	Yard = { X0 = 40, X1 = 100, Z0 = 120, Z1 = 200 },
	-- A capsule stands against a wall (CapsuleInset from the wall's inner face to its middle) and
	-- its pad is PadOffset further into the room.
	CapsuleInset = 4,
	CapsuleSize = 5,
	PadOffset = 8,
	-- The stairs: a corner of 26 x 18 studs. The landing is the first 8 studs from the wall and the
	-- flights are the other 18 studs, 16 steps each (rise 1, run 1.125).
	Stairs = { Corner = 26, Landing = 8, Steps = 16, LaneWidth = 9, GateHeight = 9, Railing = 3 },
	-- Wall slots in buying order: { wall, position along the wall }.
	-- front/back: position is x; left/right: position is z.
	WallSlots = {
		{ "front", -48 },
		{ "front", -66 },
		{ "left", 146 },
		{ "left", 166 },
		{ "back", -60 },
		{ "back", -32 },
		{ "back", -4 },
		{ "right", 172 },
		{ "right", 148 },
		{ "front", -8 },
	},
	Floors = {
		{ "rashford", "grealish", "sterling", "joao_felix", "son", "saka", "griezmann", "pedri", "trent", "gavi" },
		{ "lautaro", "leao", "wirtz", "musiala", "lewandowski", "benzema", "modric", "kane", "de_bruyne", "rodri" },
		{ "foden", "vinicius", "bellingham", "yamal", "salah", "neymar", "haaland", "mbappe", "cristiano", "messi" },
	},
	-- Floor 4, the Legends hall: five capsules along the back wall.
	Legends = { { "ronaldinho", -52 }, { "zidane", -31 }, { "ronaldo_nazario", -10 }, { "maradona", 11 }, { "pele", 30 } },
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
	stairs = Color3.fromRGB(150, 120, 200),
	gate = Color3.fromRGB(120, 190, 240),
}

local MARKER_COLORS = {
	claim = Color3.fromRGB(255, 220, 60),
	player = Color3.fromRGB(80, 220, 120),
	legend = Color3.fromRGB(240, 90, 90),
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

local function addPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
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

local function addBox(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?): Part
	return addPart(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material)
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
local PAD = Vector3.new(7, 0.2, 7)

-- The walkable top of floor k (k = 1 is the ground floor, 5 is the roof).
local function floorTop(k: number): number
	return FLOOR + Def.FloorHeight * (k - 1)
end

local gate = addPart(model, "Gate", Vector3.new(2, 2, 2), Vector3.new(0, 1, 0), COLORS.line)
gate.Transparency = 1
gate.CanCollide = false
gate.CanQuery = false
gate.CanTouch = false
model.PrimaryPart = gate

local ground = folder("Ground")
addBox(ground, "PlotGround", -Def.Plot.Width / 2, Def.Plot.Width / 2, Def.GroundTop - 1, Def.GroundTop, 0, Def.Plot.Depth, COLORS.ground, Enum.Material.Grass)
addBox(ground, "PitchLawn", -Def.Plot.Width / 2 + 4, Def.Plot.Width / 2 - 4, Def.GroundTop, Def.GroundTop + 0.1, 8, 118, COLORS.lawn, Enum.Material.Grass)
addBox(ground, "YardGround", Def.Yard.X0 + 2, Def.Yard.X1 - 2, Def.GroundTop, FLOOR - 0.1, Def.Yard.Z0 + 2, Def.Yard.Z1 - 2, COLORS.yard, Enum.Material.SmoothPlastic)

local fence = folder("Fence")
local half = Def.Plot.Width / 2
local fh, ft = Def.Fence.Height, Def.Fence.Thickness
local fenceTop = Def.GroundTop + fh
local gateHalf = Def.Gate.Width / 2
local function fencePart(name: string, x0: number, x1: number, z0: number, z1: number)
	local p = addBox(fence, name, x0, x1, Def.GroundTop, fenceTop, z0, z1, COLORS.fence, Enum.Material.Wood)
	p.Transparency = 0.5
	return p
end
fencePart("FrontLeft", -half, -gateHalf, 0, ft)
fencePart("FrontRight", gateHalf, half, 0, ft)
fencePart("Back", -half, half, Def.Plot.Depth - ft, Def.Plot.Depth)
fencePart("Left", -half, -half + ft, 0, Def.Plot.Depth)
fencePart("Right", half - ft, half, 0, Def.Plot.Depth)

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
for _, side in { -1, 1 } do
	local gx = side * (c.Length / 2)
	local gz = c.CenterZ
	local post = 0.5
	local goalHeight = 6
	addBox(court, "GoalPostA", gx - post / 2, gx + post / 2, FLOOR, FLOOR + goalHeight, gz - 5, gz - 5 + post, COLORS.goal)
	addBox(court, "GoalPostB", gx - post / 2, gx + post / 2, FLOOR, FLOOR + goalHeight, gz + 5 - post, gz + 5, COLORS.goal)
	addBox(court, "GoalBar", gx - post / 2, gx + post / 2, FLOOR + goalHeight - post, FLOOR + goalHeight, gz - 5, gz + 5, COLORS.goal)
end

-- Building shell -----------------------------------------------------------------------------
local building = folder("Building")
local b = Def.Building
local roofTop = floorTop(5)
local innerX0, innerX1 = b.X0 + b.Wall, b.X1 - b.Wall
local innerZ0, innerZ1 = b.Z0 + b.Wall, b.Z1 - b.Wall
addBox(building, "Floor1", b.X0, b.X1, FLOOR - 0.2, FLOOR, b.Z0, b.Z1, COLORS.floor, Enum.Material.SmoothPlastic)
addBox(building, "WallBack", b.X0, b.X1, Def.GroundTop, roofTop, b.Z1 - b.Wall, b.Z1, COLORS.wall)
addBox(building, "WallLeft", b.X0, b.X0 + b.Wall, Def.GroundTop, roofTop, b.Z0, b.Z1, COLORS.wall)
addBox(building, "WallRight", b.X1 - b.Wall, b.X1, Def.GroundTop, roofTop, b.Z0, b.Z1, COLORS.wall)

-- Glass front: floor 1 has the entrance gap, the upper floors a full pane each.
local doorL = b.DoorCenterX - b.DoorWidth / 2
local doorR = b.DoorCenterX + b.DoorWidth / 2
local function glass(name: string, x0: number, x1: number, y0: number, y1: number)
	local p = addBox(building, name, x0, x1, y0, y1, b.Z0, b.Z0 + b.Wall, COLORS.glass, Enum.Material.Glass)
	p.Transparency = 0.6
	return p
end
glass("GlassFront1Left", innerX0, doorL, Def.GroundTop, floorTop(2) - 1)
glass("GlassFront1Right", doorR, innerX1, Def.GroundTop, floorTop(2) - 1)
for k = 2, 4 do
	glass("GlassFront" .. k, innerX0, innerX1, floorTop(k), floorTop(k + 1) - 1)
end

-- Stairs geometry ------------------------------------------------------------------------------
local St = Def.Stairs
local xLanding = innerX0 + St.Landing -- the landing is x from innerX0 to xLanding
local xFar = innerX0 + St.Corner -- the far end of the flights, toward the room
local zBoundary = innerZ1 - St.LaneWidth -- between lane A (back) and lane B
local zFront = innerZ1 - 2 * St.LaneWidth -- the front edge of lane B
local lanes = { A = { z0 = zBoundary, z1 = innerZ1 }, B = { z0 = zFront, z1 = zBoundary } }
local run = (xFar - xLanding) / St.Steps
local rise = Def.FloorHeight / St.Steps
-- Flight f goes from floor f to floor f + 1. The lane and the direction alternate.
local flights = { { lane = "A", towardWall = true }, { lane = "B", towardWall = false }, { lane = "A", towardWall = true } }

-- Slabs: floors 2 to 4 and the roof. A slab has a hole over the flight that arrives on it.
for k = 2, 5 do
	local y0, y1 = floorTop(k) - 1, floorTop(k)
	local holeLane = if k == 2 or k == 4 then "A" elseif k == 3 then "B" else nil
	local name = if k == 5 then "Roof" else "Slab_Floor" .. k
	addBox(building, name .. "_Main", xFar, innerX1, y0, y1, innerZ0, innerZ1, COLORS.floor)
	addBox(building, name .. "_Front", innerX0, xFar, y0, y1, innerZ0, zFront, COLORS.floor)
	addBox(building, name .. "_Landing", innerX0, xLanding, y0, y1, zFront, innerZ1, COLORS.floor)
	for laneName, lane in lanes do
		if laneName ~= holeLane then
			addBox(building, name .. "_Lane" .. laneName, xLanding, xFar, y0, y1, lane.z0, lane.z1, COLORS.floor)
		end
	end
end

local stairs = folder("Stairs")
for index, flight in flights do
	local lane = lanes[flight.lane]
	local base = floorTop(index)
	for step = 1, St.Steps do
		local x0, x1
		if flight.towardWall then
			x1 = xFar - (step - 1) * run
			x0 = x1 - run
		else
			x0 = xLanding + (step - 1) * run
			x1 = x0 + run
		end
		addBox(stairs, "Step_F" .. index .. "_" .. step, x0, x1, base, base + rise * step, lane.z0, lane.z1, COLORS.stairs)
	end
	-- Side walls: the boundary between the lanes along the flight (up to a railing over the hole
	-- above), and for lane B also its front side.
	local wallTop = floorTop(index + 1) + St.Railing
	addBox(stairs, "Wall_F" .. index .. "_Boundary", xLanding, xFar, base, wallTop, zBoundary - 0.3, zBoundary + 0.3, COLORS.wall)
	if flight.lane == "B" then
		addBox(stairs, "Wall_F" .. index .. "_Front", xLanding, xFar, base, wallTop, zFront - 0.3, zFront + 0.3, COLORS.wall)
	end
end
-- Railings on the slabs around the holes (the open side of each hole faces the room or the landing).
addBox(stairs, "Rail_Floor2", xFar - 0.3, xFar + 0.3, floorTop(2), floorTop(2) + St.Railing, lanes.A.z0, lanes.A.z1, COLORS.wall)
addBox(stairs, "Rail_Floor3", xLanding - 0.3, xLanding + 0.3, floorTop(3), floorTop(3) + St.Railing, lanes.B.z0, lanes.B.z1, COLORS.wall)
addBox(stairs, "Rail_Floor4", xFar - 0.3, xFar + 0.3, floorTop(4), floorTop(4) + St.Railing, lanes.A.z0, lanes.A.z1, COLORS.wall)

-- Gates: a glass pane across the bottom of each flight, opened by the server.
local function gatePane(floorNumber: number, laneName: string, x0: number, x1: number, y0: number)
	local lane = lanes[laneName]
	local pane = addBox(stairs, "Gate_Floor" .. floorNumber, x0, x1, y0, y0 + St.GateHeight, lane.z0, lane.z1, COLORS.gate, Enum.Material.Glass)
	pane.Transparency = 0.45
	pane:SetAttribute("Floor", floorNumber)
	return pane
end
gatePane(2, "A", xFar, xFar + 0.6, floorTop(1))
gatePane(3, "B", xLanding - 0.6, xLanding, floorTop(2))
gatePane(4, "A", xFar, xFar + 0.6, floorTop(3))

-- A sign on the floor in front of the first flight.
local sign = addBox(stairs, "StairsSign", xFar + 2, xFar + 14, FLOOR, FLOOR + 0.12, lanes.A.z0 + 1, lanes.A.z1 - 1, COLORS.stairs)
local signGui = Instance.new("SurfaceGui")
signGui.Face = Enum.NormalId.Top
signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
signGui.PixelsPerStud = 20
signGui.Parent = sign
local signText = Instance.new("TextLabel")
signText.BackgroundTransparency = 1
signText.Size = UDim2.fromScale(1, 1)
signText.Text = "UPSTAIRS"
signText.TextColor3 = Color3.fromRGB(255, 255, 255)
signText.Font = Enum.Font.GothamBold
signText.TextScaled = true
signText.Rotation = 90
signText.Parent = signGui

-- Capsules and pads -----------------------------------------------------------------------------
local function capsuleSpot(wall: string, along: number): (Vector3, Vector3)
	local inset, offset = Def.CapsuleInset, Def.PadOffset
	if wall == "front" then
		return Vector3.new(along, 0, innerZ0 + inset), Vector3.new(along, 0, innerZ0 + inset + offset)
	elseif wall == "back" then
		return Vector3.new(along, 0, innerZ1 - inset), Vector3.new(along, 0, innerZ1 - inset - offset)
	elseif wall == "left" then
		return Vector3.new(innerX0 + inset, 0, along), Vector3.new(innerX0 + inset + offset, 0, along)
	end
	return Vector3.new(innerX1 - inset, 0, along), Vector3.new(innerX1 - inset - offset, 0, along)
end

local capsules = folder("Capsules")
local function addCapsule(floorNumber: number, playerId: string, wall: string, along: number, kind: string)
	local capsulePos, padPos = capsuleSpot(wall, along)
	local top = floorTop(floorNumber)
	local capsule = Instance.new("Model")
	capsule.Name = "Capsule_" .. playerId
	local size = Def.CapsuleSize
	local pedestal = addPart(capsule, "Pedestal", Vector3.new(size, 1, size), Vector3.new(capsulePos.X, top + 0.5, capsulePos.Z), COLORS.pedestal)
	local glassPart = addPart(capsule, "Glass", Vector3.new(size, 9, size), Vector3.new(capsulePos.X, top + 1 + 4.5, capsulePos.Z), COLORS.glass, Enum.Material.Glass)
	glassPart.Transparency = 0.6
	capsule.PrimaryPart = pedestal
	capsule:SetAttribute("PlayerId", playerId)
	capsule:SetAttribute("Floor", floorNumber)
	capsule.Parent = capsules
	marker("Player_" .. playerId, playerId, kind, Vector3.new(padPos.X, top + 0.1, padPos.Z), PAD):SetAttribute("Floor", floorNumber)
end
for floorNumber, ids in Def.Floors do
	for index, playerId in ids do
		local slot = Def.WallSlots[index]
		addCapsule(floorNumber, playerId, slot[1], slot[2], "player")
	end
end
for _, entry in Def.Legends do
	addCapsule(4, entry[1], "back", entry[2], "legend")
end

-- Store pads in the open middle of floor 1 with the counter behind them, locker and trophy shelf on
-- the back wall.
local fixtures = folder("Fixtures")
addBox(fixtures, "StoreCounter", -70, -2, FLOOR, FLOOR + 3, 168, 171, COLORS.counter)
addBox(fixtures, "LockerSpot", 30, 36, FLOOR, FLOOR + 7, innerZ1 - 2, innerZ1, COLORS.counter)
addBox(fixtures, "TrophyShelf", 8, 26, FLOOR, FLOOR + 6, innerZ1 - 2, innerZ1, COLORS.counter)
for index, id in { "cashPerMatch", "matchSpeed", "hatTrick", "offline" } do
	marker("Store_" .. id, id, "store", Vector3.new(-60 + (index - 1) * 18, FLOOR + 0.1, 158), PAD)
end

-- Pads outside the building ---------------------------------------------------------------------
local PAD_Y = FLOOR + 0.1
marker("Claim", "claim", "claim", Vector3.new(0, PAD_Y, 8), Vector3.new(14, 0.2, 14))
marker("Stadium", "stadium", "stadium", Vector3.new(86, PAD_Y, c.CenterZ), PAD)
marker("Penalty", "penalty", "penalty", Vector3.new(c.Length / 2 - 9, PAD_Y, c.CenterZ), PAD)
marker("Training", "training", "training", Vector3.new(70, PAD_Y, 160), Vector3.new(12, 0.2, 12))
marker("LockerSpotMarker", "locker", "spot", Vector3.new(33, PAD_Y, innerZ1 - 10), Vector3.new(4, 0.2, 4))

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

-- Layout checks ----------------------------------------------------------------------------------
local problems = {}
local doorCenter = Vector2.new(b.DoorCenterX, b.Z0 + b.Wall / 2)
local pads, minDoor, minPair = {}, math.huge, math.huge
for _, m in markers:GetChildren() do
	local kind = m:GetAttribute("Kind")
	if kind == "player" or kind == "store" or kind == "legend" then
		table.insert(pads, { name = m.Name, pos = Vector2.new(m.Position.X, m.Position.Z), y = m.Position.Y })
	end
end
for i, a in pads do
	if a.y < floorTop(2) then
		minDoor = math.min(minDoor, (a.pos - doorCenter).Magnitude)
	end
	if a.pos.X < innerX0 + 4 or a.pos.X > innerX1 - 4 or a.pos.Y < innerZ0 + 4 or a.pos.Y > innerZ1 - 4 then
		table.insert(problems, a.name .. " too close to a wall")
	end
	-- no pad inside the stair corner
	if a.pos.X < xFar + 2 and a.pos.Y > zFront - 2 then
		table.insert(problems, a.name .. " inside the stair corner")
	end
	for j = i + 1, #pads do
		if math.abs(a.y - pads[j].y) < 1 then
			minPair = math.min(minPair, (a.pos - pads[j].pos).Magnitude)
		end
	end
end
-- the top of each flight meets the floor above
for index = 1, 3 do
	local lastStep = stairs:FindFirstChild("Step_F" .. index .. "_" .. St.Steps)
	local top = lastStep.Position.Y + lastStep.Size.Y / 2
	if math.abs(top - floorTop(index + 1)) > 0.01 then
		table.insert(problems, "flight " .. index .. " top is " .. top .. ", floor " .. (index + 1) .. " is " .. floorTop(index + 1))
	end
end

local parts, markerCount, byKind = 0, 0, {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then parts += 1 end
end
for _, m in markers:GetChildren() do
	if m:GetAttribute("PadId") then
		markerCount += 1
		local kind = m:GetAttribute("Kind")
		byKind[kind] = (byKind[kind] or 0) + 1
	end
end
local kinds = {}
for kind, n in byKind do table.insert(kinds, kind .. "=" .. n) end
table.sort(kinds)
local _, size = model:GetBoundingBox()
return string.format("PlotTemplate built: %d parts, %d markers (%s), bounds %s | nearest floor 1/2/3 pad to the doorway %.1f studs, nearest pair of pads on one floor %.1f studs | problems: %s", parts, markerCount, table.concat(kinds, " "), tostring(size), minDoor, minPair, #problems == 0 and "none" or table.concat(problems, "; "))
