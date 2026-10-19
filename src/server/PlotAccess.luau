--!strict
-- Private plots (docs/PLAN.md, Step 7, decision 6): the plot is fenced, and only its owner's character
-- can walk through the gate. One collision group for the fence and one for the owner's character per
-- plot. This is convenience and anti-griefing only; every pad still checks the owner on the server.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotGroups = require(ReplicatedStorage.Shared.PlotGroups)

local DEFAULT = "Default"

local registered = false
local ownerConnections: { [Player]: { RBXScriptConnection } } = {}

local PlotAccess = {}

-- Registers the groups and the one rule between them. Call once at start.
function PlotAccess.init(count: number)
	if registered then
		return
	end
	registered = true
	for _, name in PlotGroups.all(count) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for index = 1, count do
		local owner, fence = PlotGroups.passes(index)
		PhysicsService:CollisionGroupSetCollidable(owner, fence, false)
	end
end

local function setGroup(part: BasePart, group: string)
	part.CollisionGroup = group
end

-- Puts a character (and what it wears, now and later) in a group.
local function setCharacterGroup(character: Model, group: string): RBXScriptConnection
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			setGroup(part, group)
		end
	end
	return character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			setGroup(part, group)
		end
	end)
end

-- Fences the plot: the low fence pieces join the plot's fence group, taller invisible walls stand on
-- them so nobody can jump over, and a door fills the gap of the gate. Everything uses the plot's own
-- markers, so no world coordinate lives here.
function PlotAccess.build(plot: Model, index: number)
	local fenceFolder = plot:FindFirstChild("Fence")
	if fenceFolder == nil then
		return
	end
	local group = PlotGroups.fence(index)
	local pieces: { BasePart } = {}
	for _, child in fenceFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(pieces, child)
		end
	end
	for _, piece in pieces do
		setGroup(piece, group)
		local extra = PlotGroups.WALL_HEIGHT - piece.Size.Y
		if extra > 0 then
			local wall = Instance.new("Part")
			wall.Name = piece.Name .. "Wall"
			wall.Size = Vector3.new(piece.Size.X, extra, piece.Size.Z)
			wall.CFrame = piece.CFrame * CFrame.new(0, (piece.Size.Y + extra) / 2, 0)
			wall.Anchored = true
			wall.CanCollide = true
			wall.CanQuery = false
			wall.CanTouch = false
			wall.Transparency = 1
			wall.CollisionGroup = group
			wall.Parent = fenceFolder
		end
	end

	-- The door: between the two front pieces, closed to everyone but the owner.
	local left, right =
		fenceFolder:FindFirstChild("FrontLeft"), fenceFolder:FindFirstChild("FrontRight")
	if left and right and left:IsA("BasePart") and right:IsA("BasePart") then
		local plotSpace = plot:GetPivot()
		local leftEdge = plotSpace:PointToObjectSpace(left.Position).X + left.Size.X / 2
		local rightEdge = plotSpace:PointToObjectSpace(right.Position).X - right.Size.X / 2
		local centre, width = PlotGroups.gap(leftEdge, rightEdge)
		if centre and width then
			local door = Instance.new("Part")
			door.Name = "Door"
			door.Size = Vector3.new(width, PlotGroups.WALL_HEIGHT, left.Size.Z)
			local mid = plotSpace:PointToObjectSpace(left.Position)
			door.CFrame = plotSpace * CFrame.new(centre, PlotGroups.WALL_HEIGHT / 2, mid.Z)
			door.Anchored = true
			door.CanCollide = true
			door.CanQuery = false
			door.CanTouch = false
			door.Transparency = 1
			door.CollisionGroup = group
			door.Parent = fenceFolder
		end
	end
end

-- Moves everyone but the owner who stands inside the fence out to the plaza side, so a claim never
-- traps a visitor in a plot that just closed. The box is the plot's bounding box.
function PlotAccess.clearVisitors(plot: Model, owner: Player)
	local pivot = plot:GetPivot()
	local size = plot:GetExtentsSize()
	local centre = plot:GetBoundingBox()
	for _, other in Players:GetPlayers() do
		local root = if other ~= owner and other.Character
			then other.Character:FindFirstChild("HumanoidRootPart")
			else nil
		if root and root:IsA("BasePart") then
			local offset = centre:PointToObjectSpace(root.Position)
			if math.abs(offset.X) < size.X / 2 and math.abs(offset.Z) < size.Z / 2 then
				-- Just outside the gate (the plot's origin is the middle of the gate).
				root.CFrame = pivot * CFrame.new(0, 3, -12)
			end
		end
	end
end

-- The owner's character, now and after every respawn, is in the owner group of that plot.
function PlotAccess.setOwner(player: Player, index: number)
	PlotAccess.clearOwner(player)
	local group = PlotGroups.owner(index)
	local connections: { RBXScriptConnection } = {}
	local function apply(character: Model)
		table.insert(connections, setCharacterGroup(character, group))
	end
	if player.Character then
		apply(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(apply))
	ownerConnections[player] = connections
end

-- Back to the default group (the plot was released).
function PlotAccess.clearOwner(player: Player)
	local connections = ownerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		ownerConnections[player] = nil
	end
	local character = player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				setGroup(part, DEFAULT)
			end
		end
	end
end

return PlotAccess
