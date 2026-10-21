-- Builds the Training Gym in ServerStorage.PlotTemplate: a real gym on the training yard. The yard
-- (x -130 to -50, z 60 to 140, the entrance is the gap in the wall at x -50, z 92 to 108, the path
-- side is +x) is split in two: an indoor GYM HALL next to the entrance (x -90 to -50) with a roof,
-- ceiling lights, a glass front, mirrors, dumbbell racks and benches, holding the two conditioning
-- stations; and an OUTDOOR YARD behind it (x -130 to -90) with striped turf, a fence, floodlights and
-- a small goal, holding the two skill stations. A wide doorway joins the two. Run through the Studio
-- MCP (execute_luau, Edit mode). Safe to run again: it rebuilds the Gym folder and the training
-- markers.
--
--   outdoor yard (open sky)             gym hall (roof)
--   x -110: keepie-uppies (z 80)        x -70: treadmill (z 80)
--           free kicks (z 120)                  bench press (z 120)
--
-- Each station has a 14 x 14 marker (Kind "training", PadId trainingKeepie, trainingFreekick,
-- trainingTreadmill, trainingBench); the server reads the pad key (TrainingActions) and PadInfo names
-- the stations.

local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("PlotTemplate")
local landscape = template:WaitForChild("Landscape")
local markers = template:WaitForChild("Markers")

-- Remove the old fields and anything an earlier run made.
for _, name in { "TrainingFloorAfk", "TrainingFloorActive", "TrainingDivider", "SignAfk", "SignActive", "Cone1", "Cone2", "Cone3", "Cone4" } do
	local old = landscape:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
for _, name in { "TrainingAfk", "TrainingActive", "TrainingTreadmill", "TrainingLadder", "TrainingBench", "TrainingKeepie", "TrainingDribble", "TrainingFreekick" } do
	local old = markers:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
local oldGym = template:FindFirstChild("Gym")
if oldGym then
	oldGym:Destroy()
end

local gym = Instance.new("Folder")
gym.Name = "Gym"
gym.Parent = template

local GROUND = 0.5
local TOP = 0.6 -- the walking height of the yard floor
local H_TOP = 14 -- the height of the hall walls, under the roof
local COLORS = {
	line = Color3.fromRGB(240, 240, 240),
	dark = Color3.fromRGB(45, 48, 60),
	steel = Color3.fromRGB(82, 88, 100),
	yellow = Color3.fromRGB(245, 200, 60),
	cone = Color3.fromRGB(255, 140, 40),
	plaque = Color3.fromRGB(32, 38, 56),
	rubberA = Color3.fromRGB(58, 63, 74),
	rubberB = Color3.fromRGB(68, 74, 86),
	wall = Color3.fromRGB(232, 232, 238),
	band = Color3.fromRGB(40, 110, 200),
	roof = Color3.fromRGB(70, 76, 90),
	glass = Color3.fromRGB(170, 215, 240),
	mirror = Color3.fromRGB(205, 228, 242),
	turfA = Color3.fromRGB(70, 160, 86),
	turfB = Color3.fromRGB(60, 146, 76),
	mat = Color3.fromRGB(44, 116, 62),
	wood = Color3.fromRGB(150, 105, 62),
}

local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	part.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = gym
	return part
end

-- Props you walk through or stand on never block the player.
local function soft(part: Part): Part
	part.CanCollide = false
	return part
end

local function marker(name: string, padId: string, cx: number, cz: number)
	local pad = Instance.new("Part")
	pad.Name = name
	pad.Size = Vector3.new(14, 0.2, 14)
	pad.CFrame = CFrame.new(cx, 0.8, cz)
	pad.Anchored = true
	pad.Color = Color3.fromRGB(60, 220, 220)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.88 -- a faint glow, so the equipment on the floor stays visible
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad:SetAttribute("PadId", padId)
	pad:SetAttribute("Kind", "training")
	pad.Parent = markers
end

-- A dark plaque with white or yellow text on one face of a thin box.
local function sign(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, face: Enum.NormalId, text: string, color: Color3): Part
	local plaque = box(name, x0, x1, y0, y1, z0, z1, COLORS.plaque)
	plaque.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = plaque
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.7)
	label.Position = UDim2.fromScale(0.04, 0.15)
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	return plaque
end

-- Floors: rubber tiles in the hall, mown turf stripes in the yard.
for ix = 0, 3 do
	for iz = 0, 7 do
		local color = if (ix + iz) % 2 == 0 then COLORS.rubberA else COLORS.rubberB
		box("HallTile", -90 + ix * 10, -80 + ix * 10, GROUND, TOP, 60 + iz * 10, 70 + iz * 10, color)
	end
end
for iz = 0, 7 do
	local color = if iz % 2 == 0 then COLORS.turfA else COLORS.turfB
	box("YardStripe", -130, -90, GROUND, TOP, 60 + iz * 10, 70 + iz * 10, color)
end

-- The hall shell: walls with a low band, glass above it and a solid top, a glass front and a roof.
local function wallWithGlass(name: string, x0: number, x1: number, z0: number, z1: number, glassFrom: number, glassTo: number)
	box(name .. "Low", x0, x1, TOP, glassFrom, z0, z1, COLORS.wall)
	box(name .. "Glass", x0, x1, glassFrom, glassTo, z0, z1, COLORS.glass, Enum.Material.Glass, 0.55)
	box(name .. "Top", x0, x1, glassTo, H_TOP, z0, z1, COLORS.wall)
end
-- The wall between the hall and the yard, with a doorway (z 88 to 112).
wallWithGlass("DividerA", -90.5, -89.5, 60, 88, 3.7, 11)
wallWithGlass("DividerB", -90.5, -89.5, 112, 140, 3.7, 11)
box("DoorHeader", -90.5, -89.5, 9, H_TOP, 88, 112, COLORS.wall)
-- The glass front over the low wall at the entrance (the gap stays open).
wallWithGlass("FrontA", -51, -50, 60, 91, 3.7, 11)
wallWithGlass("FrontB", -51, -50, 109, 140, 3.7, 11)
-- The side walls of the hall: solid, a blue band, mirrors and a slogan.
local sides = {
	{ name = "North", z0 = 60, z1 = 61, inner = 61, face = Enum.NormalId.Back, dir = 1 },
	{ name = "South", z0 = 139, z1 = 140, inner = 139, face = Enum.NormalId.Front, dir = -1 },
}
for _, side in sides do
	box(side.name .. "Wall", -90, -50, TOP, H_TOP, side.z0, side.z1, COLORS.wall)
	box(side.name .. "Band", -90, -50, 8.6, 9.2, math.min(side.inner, side.inner + side.dir * 0.12), math.max(side.inner, side.inner + side.dir * 0.12), COLORS.band)
	for _, x in { -88, -74, -60 } do
		local zA, zB = side.inner, side.inner + side.dir * 0.12
		local mirror = box(side.name .. "Mirror", x, x + 12, 4.9, 8.4, math.min(zA, zB), math.max(zA, zB), COLORS.mirror, Enum.Material.Glass)
		mirror.Reflectance = 0.3
		mirror.CanCollide = false
	end
	local zA, zB = side.inner, side.inner + side.dir * 0.1
	sign(side.name .. "Slogan", -80, -60, 9.8, 12.6, math.min(zA, zB), math.max(zA, zB), side.face, "NO PAIN, NO GAIN", Color3.fromRGB(255, 220, 60))
end
-- The roof, a little wider than the walls, and the lights under it.
box("HallRoof", -91.5, -48.5, H_TOP, H_TOP + 1.2, 58.5, 141.5, COLORS.roof, Enum.Material.Metal)
for index, x in { -80, -70, -60 } do
	local strip = box("CeilingLight" .. index, x - 0.6, x + 0.6, H_TOP - 0.3, H_TOP, 64, 136, Color3.fromRGB(250, 248, 238), Enum.Material.SmoothPlastic)
	strip.CanCollide = false
	for _, z in { 70, 90, 110, 130 } do
		local anchor = box("CeilingLamp", x - 0.2, x + 0.2, H_TOP - 0.6, H_TOP - 0.3, z - 0.2, z + 0.2, COLORS.dark)
		anchor.CanCollide = false
		anchor.Transparency = 1
		local light = Instance.new("PointLight")
		light.Range = 24
		light.Brightness = 0.5
		light.Color = Color3.fromRGB(255, 244, 225)
		light.Parent = anchor
	end
end
-- Signs over the doorway, one for each side.
sign("DoorSignHall", -89.5, -89.2, 10, 13, 90, 110, Enum.NormalId.Right, "OUTDOOR YARD", Color3.fromRGB(255, 255, 255))
sign("DoorSignYard", -90.8, -90.5, 10, 13, 90, 110, Enum.NormalId.Left, "GYM HALL", Color3.fromRGB(255, 255, 255))

-- The entrance: two pillars and a board over the gap in the wall, facing the path.
for _, z in { 91, 109 } do
	box("GymPillar", -52, -50, TOP, 12.6, z - 0.7, z + 0.7, COLORS.steel, Enum.Material.Metal)
end
sign("GymSign", -51.6, -50.4, 9.6, 12.6, 90.5, 109.5, Enum.NormalId.Right, "TRAINING GYM", Color3.fromRGB(255, 220, 60))

-- Dumbbell racks against the side walls and benches in front of them.
local PLATES = { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(240, 200, 60), Color3.fromRGB(70, 200, 120) }
local function dumbbell(x: number, y: number, z: number, color: Color3)
	local handle = box("DumbbellBar", x - 0.7, x + 0.7, y - 0.15, y + 0.15, z - 0.15, z + 0.15, COLORS.steel, Enum.Material.Metal)
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(1.4, 0.3, 0.3)
	handle.CFrame = CFrame.new(x, y, z)
	handle.CanCollide = false
	for _, side in { -1, 1 } do
		local plate = box("DumbbellPlate", x, x + 0.1, y, y + 0.1, z, z + 0.1, color)
		plate.Shape = Enum.PartType.Cylinder
		plate.Size = Vector3.new(0.35, 1, 1)
		plate.CFrame = CFrame.new(x + side * 0.6, y, z)
		plate.CanCollide = false
	end
end
local function rack(cx: number, wallZ: number, dir: number)
	local lo, hi = math.min(wallZ, wallZ + dir * 2.2), math.max(wallZ, wallZ + dir * 2.2)
	for _, x in { cx - 4, cx + 4 } do
		soft(box("RackPost", x - 0.2, x + 0.2, TOP, 4.6, lo, hi, COLORS.steel, Enum.Material.Metal))
	end
	for index, shelf in { 1.6, 3.2 } do
		soft(box("RackShelf", cx - 4, cx + 4, shelf, shelf + 0.25, lo, hi, COLORS.steel, Enum.Material.Metal))
		for i = 0, 4 do
			dumbbell(cx - 3 + i * 1.5, shelf + 0.25 + 0.5, (lo + hi) / 2, PLATES[(i + index) % #PLATES + 1])
		end
	end
end
for _, x in { -80, -68, -56 } do
	rack(x, 61, 1)
	rack(x, 139, -1)
end
local function bench(x: number, z: number)
	soft(box("BenchPad", x - 2.5, x + 2.5, 1.6, 2.2, z - 0.9, z + 0.9, Color3.fromRGB(30, 32, 40)))
	for _, dx in { -2, 2 } do
		soft(box("BenchLeg", x + dx - 0.2, x + dx + 0.2, TOP, 1.6, z - 0.7, z + 0.7, COLORS.steel, Enum.Material.Metal))
	end
end
bench(-84, 70)
bench(-56, 70)
bench(-84, 130)
bench(-56, 130)

-- The outdoor yard: a fence (a mesh and a rail on top of the old low wall), floodlights, a small goal.
local function fence(name: string, x0: number, x1: number, z0: number, z1: number)
	soft(box(name .. "Mesh", x0, x1, 3.7, 9, z0, z1, Color3.fromRGB(150, 156, 168), Enum.Material.Metal, 0.7))
	box(name .. "Rail", x0, x1, 8.9, 9.1, z0, z1, COLORS.steel, Enum.Material.Metal)
end
fence("FenceBack", -130, -129.8, 60, 140)
fence("FenceNorth", -130, -90, 60, 60.2)
fence("FenceSouth", -130, -90, 139.8, 140)
for _, z in { 60, 70, 80, 90, 100, 110, 120, 130, 140 } do
	box("FencePost", -130.3, -129.7, TOP, 9.2, z - 0.2, z + 0.2, COLORS.steel, Enum.Material.Metal)
end
for _, x in { -120, -110, -100 } do
	for _, z in { 60, 140 } do
		box("FencePost", x - 0.2, x + 0.2, TOP, 9.2, z - 0.2, z + 0.2, COLORS.steel, Enum.Material.Metal)
	end
end
local function floodlight(x: number, z: number)
	local pole = box("FloodPole", x - 0.4, x + 0.4, TOP, 18, z - 0.4, z + 0.4, COLORS.steel, Enum.Material.Metal)
	pole.CanCollide = false
	local head = box("FloodHead", x - 0.8, x + 0.8, 18, 19.4, z - 2, z + 2, Color3.fromRGB(255, 250, 235), Enum.Material.Neon)
	head.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 0.5
	light.Color = Color3.fromRGB(255, 246, 230)
	light.Parent = head
end
floodlight(-127, 64)
floodlight(-127, 136)
floodlight(-93, 64)
floodlight(-93, 136)
-- A small goal at the back fence, opening towards the hall.
for _, z in { 94, 106 } do
	soft(box("GoalPost", -128.5, -128, TOP, 6.6, z - 0.25, z + 0.25, COLORS.line))
end
soft(box("GoalBar", -128.5, -128, 6.1, 6.6, 94, 106.5, COLORS.line))
soft(box("GoalNet", -129.8, -129.6, TOP, 6.4, 94, 106, COLORS.line, Enum.Material.SmoothPlastic, 0.7))
for _, z in { 94, 106 } do
	soft(box("GoalSide", -129.8, -128.5, TOP, 6.4, z - 0.05, z + 0.05, COLORS.line, Enum.Material.SmoothPlastic, 0.7))
end
-- A wooden bench and a few spare cones at the side of the yard.
soft(box("YardBenchSeat", -104, -96, 1.7, 2.1, 62.2, 63.6, COLORS.wood, Enum.Material.Wood))
soft(box("YardBenchBack", -104, -96, 2.1, 3.5, 61.6, 62, COLORS.wood, Enum.Material.Wood))
for _, x in { -103.5, -96.5 } do
	soft(box("YardBenchLeg", x - 0.2, x + 0.2, TOP, 1.7, 62.4, 63.4, COLORS.steel, Enum.Material.Metal))
end
for index, x in { -126, -124, -122 } do
	soft(box("SpareCone" .. index, x - 0.5, x + 0.5, TOP, 1.3, 132.2, 133.2, COLORS.cone))
end

-- Treadmill (conditioning, x -70, z 80): the cartoon treadmill model (ServerStorage.GymModels.Treadmill,
-- saved in the place): one generated mesh in white with a blue console, a navy belt with blue chevrons
-- to the console (-x), and an invisible Stand on the belt with a Ramp at the back (+x), since the
-- meshes do not collide. Its pivot is the bottom centre of the machine; with the ramp it spans x -5.6
-- to 8.6 of it, so the pivot sits 1.5 studs short of the station centre. The old part-built treadmill
-- is kept in ServerStorage.TreadmillOld.
local treadmill = ServerStorage:WaitForChild("GymModels"):WaitForChild("Treadmill"):Clone()
treadmill:PivotTo(CFrame.new(-71.5, TOP, 80))
treadmill.Parent = gym

-- Bench press (conditioning, x -70, z 120): the cartoon bench model (ServerStorage.GymModels.Bench,
-- saved in the place): generated meshes in white with a blue pad, the rack's uprights at the -x end
-- with the barbell (a white bar, one navy disc a side) on the hooks, and an invisible Seat tagged
-- "BenchSeat" on the pad (server/BenchSeats lays the owner down, client/BenchPress animates the
-- press). Its pivot is the bottom centre. The old agility ladder is kept in ServerStorage.LadderOld.
local bench = ServerStorage:WaitForChild("GymModels"):WaitForChild("Bench"):Clone()
bench:PivotTo(CFrame.new(-70, TOP, 120))
bench.Parent = gym

-- Keepie-uppies (skill, x -110, z 80): a dark turf mat with a painted circle and a ball.
box("KeepieMat", -116, -104, TOP, TOP + 0.1, 74, 86, COLORS.mat)
local ring = box("KeepieRing", -113, -107, TOP + 0.1, TOP + 0.14, 77, 83, COLORS.line)
ring.Shape = Enum.PartType.Cylinder
ring.CFrame = CFrame.new(-110, TOP + 0.12, 80) * CFrame.Angles(0, 0, math.pi / 2)
ring.Size = Vector3.new(0.04, 6, 6)
local ball = box("KeepieBall", -111, -109, TOP + 0.14, TOP + 2.14, 79, 81, COLORS.line)
ball.Shape = Enum.PartType.Ball
ball.CFrame = CFrame.new(-110, TOP + 1.2, 80)
ball.Size = Vector3.new(2, 2, 2)
ball.CanCollide = false

-- Free kicks (skill, x -110, z 120): a white spot with a ball and a dummy wall of three, lined up
-- on the small goal at the back fence (x -128, z 100).
local spot = box("FreekickSpot", -111, -109, TOP + 0.1, TOP + 0.14, 119, 121, COLORS.line)
spot.Shape = Enum.PartType.Cylinder
spot.CFrame = CFrame.new(-110, TOP + 0.12, 120) * CFrame.Angles(0, 0, math.pi / 2)
spot.Size = Vector3.new(0.04, 1.8, 1.8)
spot.CanCollide = false
local kickBall = box("FreekickBall", -111, -109, TOP + 0.14, TOP + 2.14, 119, 121, COLORS.line)
kickBall.Shape = Enum.PartType.Ball
kickBall.CFrame = CFrame.new(-110, TOP + 1.14, 120)
kickBall.Size = Vector3.new(2, 2, 2)
kickBall.CanCollide = false
do
	local from = Vector3.new(-110, 0, 120)
	local toGoal = (Vector3.new(-128, 0, 100) - from).Unit
	local across = Vector3.new(-toGoal.Z, 0, toGoal.X)
	local middle = from + toGoal * 6
	for index = -1, 1 do
		local at = middle + across * (index * 1.6)
		local dummy = soft(box("FreekickDummy", -0.7, 0.7, TOP, TOP + 4.6, -0.2, 0.2, COLORS.yellow))
		dummy.CFrame = CFrame.lookAt(Vector3.new(at.X, TOP + 2.3, at.Z), Vector3.new(from.X, TOP + 2.3, from.Z))
		local head = soft(box("FreekickDummyHead", -0.45, 0.45, 0, 0.9, -0.45, 0.45, COLORS.yellow))
		head.Shape = Enum.PartType.Ball
		head.CFrame = CFrame.new(at.X, TOP + 5.1, at.Z)
	end
end

-- The name of each station is written by the pad label (client/PadRing), so there are no boards here.
marker("TrainingKeepie", "trainingKeepie", -110, 80)
marker("TrainingFreekick", "trainingFreekick", -110, 120)
marker("TrainingTreadmill", "trainingTreadmill", -70, 80)
marker("TrainingBench", "trainingBench", -70, 120)

return "Gym built: " .. #gym:GetChildren() .. " parts, " .. #markers:GetChildren() .. " markers in total"
