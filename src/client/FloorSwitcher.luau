--!strict
-- Four round buttons at the bottom right (4 3 2 1, the top floor on top) that take the player to a
-- floor of the building, so nobody has to find the stairs. The stairs stay open and walkable, with
-- UP / DOWN plates on the floor. Moving the own character is not game state (floors are never
-- locked, docs/PLAN.md), so this is done on the client; the server decides nothing here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local FLOORS = 4
local SIZE = 36
local GAP = 5
local SIDE = 8
local BOTTOM = 40 -- clears the strip at the bottom of the screen; the right side is free below the money
local ARRIVE_HEIGHT = 3 -- the character stands this far above the spot
local REFRESH_SECONDS = 0.25
local CURRENT_COLOR = Color3.fromRGB(88, 170, 120)
local IDLE_COLOR = Color3.fromRGB(110, 118, 150)

local FloorSwitcher = {}

local buttons: { [number]: TextButton } = {}
local outlines: { [number]: UIStroke } = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- The spots of the player's own plot, by floor (nil until the plot exists).
local function ownSpots(): { [number]: BasePart }?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local stairs = plot:FindFirstChild("Stairs")
			if stairs == nil then
				return nil
			end
			local spots: { [number]: BasePart } = {}
			for _, part in stairs:GetChildren() do
				local floor = part:GetAttribute("SpotFloor")
				if part:IsA("BasePart") and type(floor) == "number" then
					spots[floor] = part
				end
			end
			return spots
		end
	end
	return nil
end

local function root(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function goTo(floor: number)
	local spots = ownSpots()
	local part = root()
	local spot = if spots then spots[floor] else nil
	if part == nil or spot == nil then
		return
	end
	part.AssemblyLinearVelocity = Vector3.zero
	part.CFrame = CFrame.new(spot.Position + Vector3.new(0, ARRIVE_HEIGHT, 0))
		* CFrame.Angles(0, select(2, part.CFrame:ToEulerAnglesYXZ()), 0)
end

function FloorSwitcher.init()
	local gui = new("ScreenGui", {
		Name = "FloorSwitcher",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 1,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local column = new("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -SIDE, 1, -BOTTOM),
		Size = UDim2.fromOffset(SIZE, FLOORS * SIZE + (FLOORS - 1) * GAP),
		BackgroundTransparency = 1,
	}, gui)
	for floor = 1, FLOORS do
		local button = new("TextButton", {
			Name = "Floor" .. floor,
			Position = UDim2.fromOffset(0, (FLOORS - floor) * (SIZE + GAP)),
			Size = UDim2.fromOffset(SIZE, SIZE),
			BackgroundColor3 = Style.ui.panel,
			AutoButtonColor = true,
			Text = tostring(floor),
			Font = Style.font,
			TextSize = 22,
			TextColor3 = Style.ui.text,
		}, column)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
		outlines[floor] = new("UIStroke", {
			Color = IDLE_COLOR,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		button.Activated:Connect(function()
			goTo(floor)
		end)
		buttons[floor] = button
	end

	local sinceRefresh = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceRefresh += dt
		if sinceRefresh < REFRESH_SECONDS then
			return
		end
		sinceRefresh = 0
		local spots = ownSpots()
		gui.Enabled = spots ~= nil
		local part = root()
		if spots == nil or part == nil then
			return
		end
		-- The character is on the highest floor whose spot is not above its feet.
		local current = 1
		for floor = 1, FLOORS do
			local spot = spots[floor]
			if spot and part.Position.Y >= spot.Position.Y - 1 then
				current = floor
			end
		end
		for floor, outline in outlines do
			outline.Color = if floor == current then CURRENT_COLOR else IDLE_COLOR
		end
	end)
end

return FloorSwitcher
