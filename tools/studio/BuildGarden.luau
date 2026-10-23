-- Builds the garden in ServerStorage.PlotTemplate: cartoon trees, bushes and flower beds on the plot
-- grass that nothing else uses (around the path, in front of and behind the building and the gym).
-- Run through the Studio MCP (execute_luau, Edit mode) after BuildPlotTemplate and BuildGym. Safe to
-- run again: it rebuilds the Garden folder. The layout comes from a fixed seed, so every run (and
-- every plot) gets the same garden.
-- Coordinates are local to the plot (see BuildPlotTemplate): the gate is at the origin, +Z points
-- into the plot, the building is on +X (x 50 to 130, z 20 to 160) and the gym on -X (x -130 to -48,
-- z 48 to 132). The pitch and its stands reach z 175 at the biggest tier, so the garden stays in
-- front of that. The strip between the path and the building (the Robux pads, the trophy case)
-- stays clear.
-- Flowers are clones of ServerStorage.GardenModels.Flower: one generate_mesh flower split into
-- Petals, Center, Stem and Leaves MeshParts (no texture), pivot at the bottom centre, recoloured here.

local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("PlotTemplate")
local flowerModel = ServerStorage:WaitForChild("GardenModels"):WaitForChild("Flower") :: Model

local Def = {
	GroundTop = 0.5,
	Seed = 20261021,
	Gap = 1, -- studs kept clear between two plants
	-- The free grass, as { x0, x1, z0, z1 }: 2 studs off the path, the fence and the buildings.
	Zones = {
		{ -138, -22, 3, 46 }, -- in front of the gym
		{ -46, -22, 50, 80 }, -- between the path and the gym, before its walkway
		{ -46, -22, 100, 170 }, -- between the path and the gym, after its walkway
		{ -138, -50, 134, 172 }, -- behind the gym
		{ 52, 138, 3, 18 }, -- in front of the building
		{ 50, 138, 162, 172 }, -- behind the building
		{ 132, 138, 20, 160 }, -- behind the building's side wall
		{ -138, -132, 50, 132 }, -- behind the gym's back wall
	},
	-- Placement tries per 100 square studs of zone, so bigger zones get more plants.
	Density = 2.6,
	Tree = { Radius = 5, TrunkWidth = 1.8, TrunkHeight = 6 },
	Bush = { Radius = 3 },
	Bed = { Radius = 4.5, Flowers = 7 },
	Flower = { MinScale = 1.1, MaxScale = 1.4 }, -- the model is 2.1 studs tall
}

-- Bright cartoon foliage, a warm soil and the petal colours (the Style accents plus pink and red).
local COLORS = {
	leaves = {
		Color3.fromRGB(76, 175, 80),
		Color3.fromRGB(102, 196, 90),
		Color3.fromRGB(60, 150, 75),
	},
	trunk = Color3.fromRGB(140, 95, 60),
	soil = Color3.fromRGB(120, 82, 56),
	center = Color3.fromRGB(255, 205, 60), -- Style.ui.gold
	centerOnGold = Color3.fromRGB(255, 150, 50), -- an orange heart on the yellow flowers
	petals = {
		Color3.fromRGB(255, 205, 60), -- Style.ui.gold
		Color3.fromRGB(150, 90, 220), -- Style.ui.purple
		Color3.fromRGB(240, 240, 240), -- white
		Color3.fromRGB(255, 120, 190), -- pink
		Color3.fromRGB(232, 64, 96), -- red
		Color3.fromRGB(255, 150, 50), -- orange
	},
}

local old = template:FindFirstChild("Garden")
if old then
	old:Destroy()
end
local garden = Instance.new("Folder")
garden.Name = "Garden"

local rng = Random.new(Def.Seed)
local ground = Def.GroundTop

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function addPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	solid: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- A cylinder part's axis is its X; this stands it upright.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function model(name: string, at: Vector3): Model
	local m = Instance.new("Model")
	m.Name = name
	m.WorldPivot = CFrame.new(at.X, ground, at.Z)
	m.Parent = garden
	return m
end

local function tree(at: Vector3)
	local m = model("Tree", at)
	local t = Def.Tree
	addPart(
		m,
		"Trunk",
		Enum.PartType.Cylinder,
		Vector3.new(t.TrunkHeight, t.TrunkWidth, t.TrunkWidth),
		CFrame.new(at.X, ground + t.TrunkHeight / 2, at.Z) * UPRIGHT,
		COLORS.trunk,
		true
	)
	local top = ground + t.TrunkHeight
	local leaves = pick(COLORS.leaves)
	addPart(
		m,
		"Canopy",
		Enum.PartType.Ball,
		Vector3.one * 9,
		CFrame.new(at.X, top + 2.5, at.Z),
		leaves,
		true
	)
	for i = 1, 2 do
		local angle = rng:NextNumber(0, 2 * math.pi) + i * math.pi
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 2.6
		addPart(
			m,
			"Canopy",
			Enum.PartType.Ball,
			Vector3.one * rng:NextNumber(5.5, 6.5),
			CFrame.new(at.X + offset.X, top + rng:NextNumber(0.5, 3.5), at.Z + offset.Z),
			leaves,
			false
		)
	end
end

local function bush(at: Vector3)
	local m = model("Bush", at)
	local leaves = pick(COLORS.leaves)
	local size = rng:NextNumber(3.6, 4.6)
	addPart(
		m,
		"Leaves",
		Enum.PartType.Ball,
		Vector3.one * size,
		CFrame.new(at.X, ground + size * 0.35, at.Z),
		leaves,
		true
	)
	for _ = 1, 2 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local small = size * rng:NextNumber(0.6, 0.75)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * size * 0.4
		local part = addPart(
			m,
			"Leaves",
			Enum.PartType.Ball,
			Vector3.one * small,
			CFrame.new(at.X + offset.X, ground + small * 0.35, at.Z + offset.Z),
			leaves,
			false
		)
		part.CastShadow = false
	end
end

local function flower(parent: Instance, x: number, z: number, color: Color3)
	local f = Def.Flower
	local clone = flowerModel:Clone()
	clone:ScaleTo(rng:NextNumber(f.MinScale, f.MaxScale))
	clone:PivotTo(CFrame.new(x, ground, z) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0))
	local petals = clone:FindFirstChild("Petals") :: BasePart
	local center = clone:FindFirstChild("Center") :: BasePart
	petals.Color = color
	center.Color = if color == COLORS.center then COLORS.centerOnGold else COLORS.center
	-- The flowers sit in the bed or patch model, not in a model of their own.
	for _, part in clone:GetChildren() do
		part.Parent = parent
	end
	clone:Destroy()
end

local function bed(at: Vector3)
	local m = model("FlowerBed", at)
	local b = Def.Bed
	local soil = addPart(
		m,
		"Soil",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, b.Radius * 2, b.Radius * 2),
		CFrame.new(at.X, ground + 0.1, at.Z) * UPRIGHT,
		COLORS.soil,
		false
	)
	soil.CastShadow = false
	-- One or two colours per bed, in a ring with one in the middle.
	local first, second = pick(COLORS.petals), pick(COLORS.petals)
	flower(m, at.X, at.Z, first)
	for i = 1, b.Flowers - 1 do
		local angle = (i / (b.Flowers - 1)) * 2 * math.pi
		local r = b.Radius * 0.6
		flower(
			m,
			at.X + math.cos(angle) * r,
			at.Z + math.sin(angle) * r,
			if i % 2 == 0 then first else second
		)
	end
end

-- A loose patch of single flowers, for the narrow strips.
local function patch(at: Vector3)
	local m = model("Flowers", at)
	local color = pick(COLORS.petals)
	for _ = 1, 3 do
		flower(m, at.X + rng:NextNumber(-1.5, 1.5), at.Z + rng:NextNumber(-1.5, 1.5), color)
	end
end

local KINDS = {
	{ build = tree, radius = Def.Tree.Radius, weight = 2 },
	{ build = bed, radius = Def.Bed.Radius, weight = 3 },
	{ build = bush, radius = Def.Bush.Radius, weight = 4 },
	{ build = patch, radius = 2, weight = 3 },
}

local placed: { { at: Vector3, radius: number } } = {}

local function fits(at: Vector3, radius: number, zone: { number }): boolean
	if
		at.X - radius < zone[1]
		or at.X + radius > zone[2]
		or at.Z - radius < zone[3]
		or at.Z + radius > zone[4]
	then
		return false
	end
	for _, other in placed do
		if (other.at - at).Magnitude < other.radius + radius + Def.Gap then
			return false
		end
	end
	return true
end

local function chooseKind(): typeof(KINDS[1])
	local total = 0
	for _, kind in KINDS do
		total += kind.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, kind in KINDS do
		roll -= kind.weight
		if roll <= 0 then
			return kind
		end
	end
	return KINDS[#KINDS]
end

for _, zone in Def.Zones do
	local area = (zone[2] - zone[1]) * (zone[4] - zone[3])
	for _ = 1, math.ceil(area / 100 * Def.Density) do
		local kind = chooseKind()
		-- Too narrow for this one: try the smaller kinds instead.
		local at =
			Vector3.new(rng:NextNumber(zone[1], zone[2]), 0, rng:NextNumber(zone[3], zone[4]))
		if not fits(at, kind.radius, zone) then
			kind = KINDS[if rng:NextNumber() < 0.5 then 3 else 4]
			if not fits(at, kind.radius, zone) then
				continue
			end
		end
		table.insert(placed, { at = at, radius = kind.radius })
		kind.build(at)
	end
end

garden.Parent = template
local parts = 0
for _, d in garden:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
return `built {#garden:GetChildren()} plants ({parts} parts)`
