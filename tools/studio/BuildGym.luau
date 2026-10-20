-- Builds the Training Gym in ServerStorage.PlotTemplate: it replaces the two old mini fields of the
-- training yard (the AFK farm and the active farm) with four stations in a 2 x 2 grid inside the same
-- walls, under a "TRAINING GYM" arch at the entrance. Run through the Studio MCP (execute_luau, Edit
-- mode). Safe to run again: it rebuilds the Gym folder and the training markers. Plot space, like the
-- rest of the template: the yard is x -130 to -50 and z 60 to 140, the entrance is the gap in the
-- wall at x -50 (z 92 to 108), the path side is +x.
--
--   skill stations (you play)           conditioning stations (they run by themselves)
--   x -110: keepie-uppies (z 80)        x -70: treadmill (z 80)
--           dribble run (z 120)                 agility ladder (z 120)
--
-- Each station has a 14 x 14 marker (Kind "training", PadId trainingKeepie, trainingDribble,
-- trainingTreadmill, trainingLadder); the server reads the pad key (TrainingActions) and PadInfo names
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
for _, name in { "TrainingAfk", "TrainingActive", "TrainingTreadmill", "TrainingLadder", "TrainingKeepie", "TrainingDribble" } do
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
local COLORS = {
	skill = Color3.fromRGB(230, 185, 130),
	conditioning = Color3.fromRGB(140, 185, 215),
	line = Color3.fromRGB(240, 240, 240),
	dark = Color3.fromRGB(45, 48, 60),
	steel = Color3.fromRGB(82, 88, 100),
	yellow = Color3.fromRGB(245, 200, 60),
	turf = Color3.fromRGB(64, 154, 82),
	cone = Color3.fromRGB(255, 140, 40),
	plaque = Color3.fromRGB(32, 38, 56),
}

local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	part.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
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

-- Floors: four 40 x 40 cells, warm for the skill stations, cool for the conditioning ones.
box("FloorSkillA", -130, -90, GROUND, TOP, 60, 99, COLORS.skill)
box("FloorSkillB", -130, -90, GROUND, TOP, 101, 140, COLORS.skill)
box("FloorConditioningA", -90, -50, GROUND, TOP, 60, 99, COLORS.conditioning)
box("FloorConditioningB", -90, -50, GROUND, TOP, 101, 140, COLORS.conditioning)
box("FloorDivider", -130, -50, TOP, TOP + 0.05, 99, 101, COLORS.line)
box("FloorSplit", -91, -89, TOP, TOP + 0.05, 60, 99, COLORS.line)
box("FloorSplit", -91, -89, TOP, TOP + 0.05, 101, 140, COLORS.line)

-- The entrance: two pillars and a board over the gap in the wall, facing the path.
for _, z in { 91, 109 } do
	box("GymPillar", -52, -50, TOP, 12.6, z - 0.7, z + 0.7, COLORS.steel, Enum.Material.Metal)
end
local arch = box("GymSign", -51.6, -50.4, 9.6, 12.6, 90.5, 109.5, COLORS.plaque)
local archGui = Instance.new("SurfaceGui")
archGui.Face = Enum.NormalId.Right
archGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
archGui.PixelsPerStud = 30
archGui.LightInfluence = 0
archGui.Parent = arch
local archText = Instance.new("TextLabel")
archText.BackgroundTransparency = 1
archText.Size = UDim2.fromScale(0.92, 0.8)
archText.Position = UDim2.fromScale(0.04, 0.1)
archText.Text = "TRAINING GYM"
archText.Font = Enum.Font.GothamBold
archText.TextScaled = true
archText.TextColor3 = Color3.fromRGB(255, 220, 60)
archText.Parent = archGui

-- Treadmill (conditioning, x -70, z 80): a dark belt, side rails and a console at the back.
box("TreadmillBelt", -76, -64, TOP, TOP + 0.15, 74, 86, COLORS.dark)
soft(box("TreadmillRail", -77, -76, TOP, 4.4, 73.5, 86.5, COLORS.steel, Enum.Material.Metal))
soft(box("TreadmillRail", -64, -63, TOP, 4.4, 73.5, 86.5, COLORS.steel, Enum.Material.Metal))
soft(box("TreadmillConsole", -78.5, -77.5, 4, 6.4, 76, 84, COLORS.dark))
for i = 0, 5 do
	soft(box("TreadmillStripe", -76 + i * 2, -75.4 + i * 2, TOP + 0.15, TOP + 0.2, 74, 86, COLORS.line))
end

-- Agility ladder (conditioning, x -70, z 120): two rails and nine rungs lying along x.
soft(box("LadderRail", -78, -62, TOP, TOP + 0.25, 117.2, 117.8, COLORS.line))
soft(box("LadderRail", -78, -62, TOP, TOP + 0.25, 122.2, 122.8, COLORS.line))
for i = 0, 8 do
	soft(box("LadderRung", -77 + i * 1.9, -76.6 + i * 1.9, TOP, TOP + 0.2, 117.2, 122.8, COLORS.yellow))
end

-- Keepie-uppies (skill, x -110, z 80): a turf mat with a painted circle and a ball.
box("KeepieMat", -116, -104, TOP, TOP + 0.1, 74, 86, COLORS.turf)
local ring = box("KeepieRing", -113, -107, TOP + 0.1, TOP + 0.14, 77, 83, COLORS.line)
ring.Shape = Enum.PartType.Cylinder
ring.CFrame = CFrame.new(-110, TOP + 0.12, 80) * CFrame.Angles(0, 0, math.pi / 2)
ring.Size = Vector3.new(0.04, 6, 6)
local ball = box("KeepieBall", -111, -109, TOP + 0.14, TOP + 2.14, 79, 81, COLORS.line)
ball.Shape = Enum.PartType.Ball
ball.CFrame = CFrame.new(-110, TOP + 1.2, 80)
ball.Size = Vector3.new(2, 2, 2)
ball.CanCollide = false

-- Dribble run (skill, x -110, z 120): two lane lines and a few cones along the run.
for _, z in { 116, 124 } do
	soft(box("DribbleLine", -118, -102, TOP, TOP + 0.08, z - 0.15, z + 0.15, COLORS.line))
end
for index, spot in { { -116, 112 }, { -112, 120 }, { -108, 128 }, { -104, 112 }, { -102, 120 } } do
	soft(box("DribbleCone" .. index, spot[1] - 0.6, spot[1] + 0.6, TOP, TOP + 1.5, spot[2] - 0.6, spot[2] + 0.6, COLORS.cone))
end

-- The name of each station is written by the pad label (client/PadRing), so there are no boards here.
marker("TrainingKeepie", "trainingKeepie", -110, 80)
marker("TrainingDribble", "trainingDribble", -110, 120)
marker("TrainingTreadmill", "trainingTreadmill", -70, 80)
marker("TrainingLadder", "trainingLadder", -70, 120)

return "Gym built: " .. #gym:GetChildren() .. " parts, " .. #markers:GetChildren() .. " markers in total"
