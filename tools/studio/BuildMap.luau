-- Builds the shared map in Studio: the plaza, the spawn and the 8 plot slots.
-- Run through the Studio MCP (execute_luau, Edit mode). Safe to run again: it rebuilds Map.
-- All sizes are named in Def (docs/PLAN.md, Step 7, provisional until walked).

local Workspace = game:GetService("Workspace")

local Def = {
	GroundTop = 0.5, -- top of every ground slab
	FloorTop = 0.7, -- top of courts, floors and pads
	Plaza = { Length = 800, Width = 80 },
	Plot = { Width = 200, Depth = 210 },
	SlotX = { -300, -100, 100, 300 },
}

local COLORS = {
	plaza = Color3.fromRGB(160, 160, 165),
	spawn = Color3.fromRGB(240, 200, 80),
	slot = Color3.fromRGB(255, 255, 255),
}

local old = Workspace:FindFirstChild("Map")
if old then
	-- The spawn is kept between rebuilds: move it out before destroying the old map.
	local oldSpawn = old:FindFirstChild("SpawnLocation", true)
	if oldSpawn then
		oldSpawn.Parent = Workspace
	end
	old:Destroy()
end

local map = Instance.new("Folder")
map.Name = "Map"

local function addPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Origin: an invisible anchor at 0,0,0 (building skill: every map has one).
local origin = addPart(map, "Origin", Vector3.new(1, 1, 1), CFrame.new(0, 0, 0), COLORS.slot, Enum.Material.SmoothPlastic)
origin.Transparency = 1
origin.CanCollide = false
origin.CanQuery = false
origin.CanTouch = false

-- Plaza ------------------------------------------------------------------------------------
local plaza = Instance.new("Folder")
plaza.Name = "Plaza"
plaza.Parent = map

addPart(
	plaza,
	"Ground",
	Vector3.new(Def.Plaza.Length, 1, Def.Plaza.Width),
	CFrame.new(0, Def.GroundTop - 0.5, 0),
	COLORS.plaza,
	Enum.Material.Concrete
)

-- The default SpawnLocation becomes a thin pad in the middle of the plaza.
local spawn = Workspace:FindFirstChild("SpawnLocation") :: SpawnLocation?
if not spawn then
	spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
end
assert(spawn, "no spawn")
for _, child in spawn:GetChildren() do
	child:Destroy() -- remove the default decal
end
spawn.Size = Vector3.new(12, 0.2, 12)
spawn.CFrame = CFrame.new(0, Def.FloorTop - 0.1, 0)
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Color = COLORS.spawn
spawn.Material = Enum.Material.SmoothPlastic
spawn.Parent = plaza

-- Plot slots -------------------------------------------------------------------------------
-- Each slot is an invisible anchor at the middle of the plot's gate, with its +Z (LookVector
-- of the CFrame) pointing into the plot. Slots 1 to 4 are on the north side and face south
-- of the plaza's edge; slots 5 to 8 are on the south side.
local slots = Instance.new("Folder")
slots.Name = "PlotSlots"
slots.Parent = map

local edge = Def.Plaza.Width / 2
for index = 1, 8 do
	local north = index <= 4
	local x = Def.SlotX[if north then index else index - 4]
	-- The template's +Z points into the plot: away from the plaza.
	local cframe = if north
		then CFrame.new(x, 0, -edge) * CFrame.Angles(0, math.pi, 0)
		else CFrame.new(x, 0, edge)
	local slot = addPart(slots, "Slot" .. index, Vector3.new(4, 1, 4), cframe, COLORS.slot, Enum.Material.SmoothPlastic)
	slot.Transparency = 1
	slot.CanCollide = false
	slot.CanQuery = false
	slot.CanTouch = false
	slot:SetAttribute("SlotIndex", index)
end

map.Parent = Workspace

local count = 0
for _ in map:GetDescendants() do
	count += 1
end
return string.format("Map built: %d descendants, 8 slots, plaza %dx%d", count, Def.Plaza.Length, Def.Plaza.Width)
