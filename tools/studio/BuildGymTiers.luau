-- Builds the equipment of the gym tiers in ServerStorage.PlotTemplate.Gym.GymTiers: one model for
-- each level of the Gym tier upgrade (Config.Store.gymTier), with a GymLevel attribute, and places
-- the two gym upgrade pads side by side in the middle of the hall, between the treadmill and the
-- bench, as a player coming in at the door sees them: Faster training (Markers.Store_gymRate) at
-- z 83 and the Gym tier (Markers.Store_gymTier) at z 97, both at x -70, with a walkway between them
-- from the door to the yard. server/GymTiers
-- shows a model once the owner's level reaches it. Chunky cartoon shapes in SmoothPlastic, white
-- bodies with one accent from shared/Style, navy for the dark parts. Run through the Studio MCP
-- (execute_luau, Edit mode) after BuildGym. Safe to run again: it rebuilds the GymTiers folder.
--
-- The spots, in the template's coordinates (the gym hall is x -90 to -50, z 50 to 130, its door at
-- x -50, z 82 to 98; the outdoor yard is x -130 to -90):
--   level 1 (gym tier 2): exercise balls (hall, -57, 70) and a kettlebell row (hall, -83, 70)
--   level 2 (gym tier 3): a punching bag (hall, -57, 110) and agility hurdles (yard, -97, 64)
--   level 3 (gym tier 4): a squat rack (hall, -83, 110) and a tyre run (yard, -97, 116)
--   level 4 (gym tier 5): a giant gold dumbbell on a plinth (yard corner, -121, 61)

local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("PlotTemplate")
local gym = template:WaitForChild("Gym")

local old = gym:FindFirstChild("GymTiers")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GymTiers"

local WHITE = Color3.fromRGB(240, 240, 240)
local NAVY = Color3.fromRGB(32, 38, 56)
local BLUE = Color3.fromRGB(90, 170, 255)
local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(80, 220, 120)

-- The top of the hall floor and of the yard turf.
local function topOf(name: string): number
	local part = gym:FindFirstChild(name) :: BasePart
	return part.Position.Y + part.Size.Y / 2
end
local HALL = topOf("HallTile")
local YARD = topOf("YardStripe")

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.CastShadow = true
	p.Parent = model
	return p
end

-- A cylinder standing up (Roblox cylinders lie along X).
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local function upright(
	model: Model,
	name: string,
	height: number,
	diameter: number,
	at: Vector3,
	color: Color3
): Part
	return part(
		model,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(at + Vector3.new(0, height / 2, 0)) * UPRIGHT,
		color,
		Enum.PartType.Cylinder
	)
end

local function level(n: number, name: string): Model
	local model = Instance.new("Model")
	model.Name = string.format("Level%d_%s", n, name)
	model:SetAttribute("GymLevel", n)
	model.Parent = folder
	return model
end

-- Level 1 ------------------------------------------------------------------------------------------
do
	local balls = level(1, "ExerciseBalls")
	local mat = part(balls, "Mat", Vector3.new(8, 0.2, 9), CFrame.new(-57, HALL + 0.1, 70), NAVY)
	mat.CanCollide = false
	for i, spot in
		{ { -58.5, 67.5, 3.4, BLUE }, { -55.5, 70, 3, GREEN }, { -58.5, 72.8, 2.6, GOLD } }
	do
		local d = spot[3] :: number
		part(
			balls,
			"Ball" .. i,
			Vector3.new(d, d, d),
			CFrame.new(spot[1] :: number, HALL + 0.2 + d / 2, spot[2] :: number),
			spot[4] :: Color3,
			Enum.PartType.Ball
		)
	end

	local bells = level(1, "Kettlebells")
	part(bells, "Mat", Vector3.new(4, 0.2, 10), CFrame.new(-83, HALL + 0.1, 70), NAVY).CanCollide =
		false
	for i = 1, 4 do
		local z = 66 + (i - 1) * 2.7
		local d = 1.3 + i * 0.15
		part(
			bells,
			"Bell",
			Vector3.new(d, d, d),
			CFrame.new(-83, HALL + 0.2 + d / 2, z),
			if i == 4 then GOLD else WHITE,
			Enum.PartType.Ball
		)
		-- The handle: a flat navy loop over the bell.
		part(
			bells,
			"Handle",
			Vector3.new(0.35, 0.9, d * 0.8),
			CFrame.new(-83, HALL + 0.2 + d + 0.3, z),
			NAVY
		)
	end
end

-- Level 2 ------------------------------------------------------------------------------------------
do
	local bag = level(2, "PunchingBag")
	local base = Vector3.new(-57, HALL, 110)
	part(bag, "Base", Vector3.new(5, 0.6, 5), CFrame.new(base + Vector3.new(0, 0.3, 0)), NAVY)
	upright(bag, "Post", 10, 0.9, base + Vector3.new(1.8, 0.6, 0), NAVY)
	part(bag, "Arm", Vector3.new(3.4, 0.7, 0.7), CFrame.new(base + Vector3.new(0.4, 10.2, 0)), NAVY)
	part(
		bag,
		"Chain",
		Vector3.new(0.2, 1.4, 0.2),
		CFrame.new(base + Vector3.new(-1, 9.3, 0)),
		WHITE
	)
	upright(bag, "Bag", 4.6, 2.6, base + Vector3.new(-1, 3.9, 0), BLUE)
	upright(bag, "BagTop", 0.4, 2.7, base + Vector3.new(-1, 8.3, 0), WHITE)
	upright(bag, "BagBottom", 0.4, 2.7, base + Vector3.new(-1, 3.8, 0), WHITE)

	local hurdles = level(2, "Hurdles")
	for i = 1, 4 do
		local z = 58 + (i - 1) * 4
		for _, side in { -1.6, 1.6 } do
			part(
				hurdles,
				"Leg",
				Vector3.new(0.3, 1.8, 0.3),
				CFrame.new(-97 + side, YARD + 0.9, z),
				WHITE
			)
			part(
				hurdles,
				"Foot",
				Vector3.new(0.3, 0.2, 1.2),
				CFrame.new(-97 + side, YARD + 0.1, z),
				WHITE
			)
		end
		part(hurdles, "Bar", Vector3.new(3.6, 0.4, 0.4), CFrame.new(-97, YARD + 1.9, z), GOLD)
	end
end

-- Level 3 ------------------------------------------------------------------------------------------
do
	local rack = level(3, "SquatRack")
	local base = Vector3.new(-83, HALL, 110)
	part(rack, "Platform", Vector3.new(5, 0.4, 9), CFrame.new(base + Vector3.new(0, 0.2, 0)), NAVY)
	for _, z in { -3.4, 3.4 } do
		part(
			rack,
			"Post",
			Vector3.new(0.7, 8, 0.7),
			CFrame.new(base + Vector3.new(1.4, 4.4, z)),
			NAVY
		)
		part(
			rack,
			"Post",
			Vector3.new(0.7, 8, 0.7),
			CFrame.new(base + Vector3.new(-1.4, 4.4, z)),
			NAVY
		)
		part(
			rack,
			"Hook",
			Vector3.new(1.2, 0.4, 0.4),
			CFrame.new(base + Vector3.new(0.6, 5.2, z)),
			WHITE
		)
	end
	part(
		rack,
		"TopBar",
		Vector3.new(0.6, 0.6, 7.4),
		CFrame.new(base + Vector3.new(1.4, 8.6, 0)),
		NAVY
	)
	part(
		rack,
		"TopBar",
		Vector3.new(0.6, 0.6, 7.4),
		CFrame.new(base + Vector3.new(-1.4, 8.6, 0)),
		NAVY
	)
	-- The barbell on the hooks, a big blue plate at each end.
	part(
		rack,
		"Barbell",
		Vector3.new(0.35, 0.35, 10),
		CFrame.new(base + Vector3.new(0.6, 5.6, 0)),
		WHITE
	)
	for _, z in { -4.4, 4.4 } do
		part(
			rack,
			"Plate",
			Vector3.new(0.6, 2.8, 2.8),
			CFrame.new(base + Vector3.new(0.6, 5.6, z)) * CFrame.Angles(0, math.rad(90), 0),
			BLUE,
			Enum.PartType.Cylinder
		)
	end

	local tyres = level(3, "TyreRun")
	for i = 1, 6 do
		local row, col = (i - 1) // 2, (i - 1) % 2
		local at = Vector3.new(-98.5 + col * 3.2, YARD, 110 + row * 3.4)
		upright(tyres, "Tyre", 0.9, 3, at, NAVY)
		upright(tyres, "Rim", 0.95, 1.4, at, if i % 2 == 0 then GOLD else WHITE)
	end
end

-- Level 4 ------------------------------------------------------------------------------------------
do
	local statue = level(4, "GoldDumbbell")
	local base = Vector3.new(-121, YARD, 61)
	part(statue, "Plinth", Vector3.new(8, 2, 8), CFrame.new(base + Vector3.new(0, 1, 0)), NAVY)
	part(
		statue,
		"PlinthTop",
		Vector3.new(8.4, 0.4, 8.4),
		CFrame.new(base + Vector3.new(0, 2.2, 0)),
		GOLD
	)
	-- The dumbbell turned to face the gym (along z), resting on two small gold cradles.
	local barY = 5.4
	part(statue, "Bar", Vector3.new(0.9, 0.9, 7), CFrame.new(base + Vector3.new(0, barY, 0)), GOLD)
	for _, z in { -3.6, 3.6 } do
		part(
			statue,
			"Weight",
			Vector3.new(1.8, 4.6, 4.6),
			CFrame.new(base + Vector3.new(0, barY, z)) * CFrame.Angles(0, math.rad(90), 0),
			GOLD,
			Enum.PartType.Cylinder
		)
		part(
			statue,
			"Cradle",
			Vector3.new(1.2, 2.8, 1.2),
			CFrame.new(base + Vector3.new(0, 3.8, z * 0.45)),
			GOLD
		)
	end
	statue.PrimaryPart = statue:FindFirstChild("Plinth") :: BasePart
end

folder.Parent = gym

-- The two pads: Faster training moves to one side of the walkway, the Gym tier is a copy of it on
-- the other side with its own PadId.
local markers = template:WaitForChild("Markers")
local rate = markers:WaitForChild("Store_gymRate") :: BasePart
rate.Position = Vector3.new(-70, rate.Position.Y, 83)
local tierPad = markers:FindFirstChild("Store_gymTier") :: BasePart?
if tierPad == nil then
	local copy = rate:Clone()
	copy.Name = "Store_gymTier"
	copy.Parent = markers
	tierPad = copy
end
local pad = tierPad :: BasePart
pad:SetAttribute("PadId", "gymTier")
pad:SetAttribute("Kind", "store")
pad.Position = Vector3.new(-70, rate.Position.Y, 97)

local count = 0
for _, model in folder:GetChildren() do
	count += #model:GetChildren()
end
return string.format(
	"GymTiers built: %d models, %d parts (hall floor %.2f, yard %.2f)",
	#folder:GetChildren(),
	count,
	HALL,
	YARD
)
