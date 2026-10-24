-- Builds the four plaza leaderboards around the spawn (shared/Leaderboards), all facing the spawn:
-- the first board (TOP JUGGLES) straight ahead of a player who joins, the others on the left, the
-- right and behind. Each is a white board on two legs with a cap in its accent colour and a navy
-- Screen part that client/Scoreboards draws on.
-- Run through the Studio MCP (execute_luau, Edit mode). Safe to run again: it rebuilds the folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Boards = require(ReplicatedStorage.Shared.Leaderboards)
local Style = require(ReplicatedStorage.Shared.Style)

local Def = {
	GroundTop = 0.5, -- top of the plaza (BuildMap)
	Offset = 28, -- studs from the spawn centre
	Plinth = Vector3.new(15, 1, 3.4),
	Leg = Vector3.new(1.6, 2.5, 1.6),
	LegX = 5.5,
	Frame = Vector3.new(15, 20.4, 1.4),
	Screen = Vector3.new(13, 18.4, 0.2),
	Cap = Vector3.new(15.8, 1.2, 2),
}

local WHITE = Color3.fromRGB(240, 240, 240)

-- One spot per board, in the order of Boards.boards. The spawn faces -Z, so the first is in front.
local SPOTS = {
	Vector3.new(0, 0, -1),
	Vector3.new(-1, 0, 0),
	Vector3.new(1, 0, 0),
	Vector3.new(0, 0, 1),
}

local plaza = Workspace:WaitForChild("Map"):WaitForChild("Plaza")
local spawnPart = plaza:WaitForChild("SpawnLocation") :: BasePart

local old = plaza:FindFirstChild("Leaderboards")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Leaderboards"

local function addPart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local centre = Vector3.new(spawnPart.Position.X, Def.GroundTop, spawnPart.Position.Z)
for index, board in Boards.boards do
	local model = Instance.new("Model")
	model.Name = board.id

	-- Built at the origin facing -Z (the screen side), then moved into place.
	local y = 0
	addPart(model, "Plinth", Def.Plinth, CFrame.new(0, y + Def.Plinth.Y / 2, 0), WHITE)
	y += Def.Plinth.Y
	for _, side in { -1, 1 } do
		addPart(model, "Leg", Def.Leg, CFrame.new(side * Def.LegX, y + Def.Leg.Y / 2, 0), WHITE)
	end
	y += Def.Leg.Y
	local frameMid = y + Def.Frame.Y / 2
	addPart(model, "Frame", Def.Frame, CFrame.new(0, frameMid, 0), WHITE)
	local screen = addPart(
		model,
		"Screen",
		Def.Screen,
		CFrame.new(0, frameMid, -(Def.Frame.Z + Def.Screen.Z) / 2),
		Style.ui.panel
	)
	screen.CanCollide = false
	screen.CastShadow = false
	y += Def.Frame.Y
	addPart(model, "Cap", Def.Cap, CFrame.new(0, y + Def.Cap.Y / 2, 0), Style.ui[board.accent])

	model.WorldPivot = CFrame.new()
	local at = centre + SPOTS[index] * Def.Offset
	model:PivotTo(CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z)))
	model.Parent = folder
end

folder.Parent = plaza
return "built " .. #folder:GetChildren() .. " leaderboards"
