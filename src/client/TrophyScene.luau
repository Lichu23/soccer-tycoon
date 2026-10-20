--!strict
-- The picture of the trophy celebration (client/SeasonUi): the players of the finished season's
-- lineup cheering around the best one, who holds a gold cup up high, with confetti falling. Drawn in
-- a ViewportFrame from the same mannequins as the capsules. Presentation only: the lineup comes from
-- the server's answer, nothing here is saved or decided.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)

local MAX_PLAYERS = 5
local FEET_TO_TORSO = Mannequin.FEET_TO_TORSO
local GOLD = Color3.fromRGB(240, 190, 60)
local CONFETTI_COLORS = {
	Color3.fromRGB(240, 190, 60),
	Color3.fromRGB(235, 80, 90),
	Color3.fromRGB(90, 170, 255),
	Color3.fromRGB(120, 220, 140),
	Color3.fromRGB(255, 255, 255),
}
local CONFETTI_PIECES = 36

local TrophyScene = {}

-- Where each player stands as { x, z }: the first (the best player) in front in the middle, the rest
-- on both sides and a step behind. The camera looks at the chests, from the -Z side.
local STANDS = { { 0, 0 }, { -3.4, 1.4 }, { 3.4, 1.4 }, { -6.4, 2.8 }, { 6.4, 2.8 } }

local ARM_Y = 1.0 -- the shoulder, above the middle of the torso
local ARM_REACH = 0.9 -- from the shoulder to the middle of the arm
local SLEEVE_REACH = 0.45

local function find(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Puts one arm (and its sleeve) up at `angle` degrees: 0 hangs down, 180 is straight up. The right
-- arm leans to +X, the left arm to -X.
local function poseArm(model: Model, base: CFrame, side: number, angle: number)
	local shoulder = base
		* CFrame.new(side * 1.4, ARM_Y, 0)
		* CFrame.Angles(0, 0, side * math.rad(angle))
	local name = if side > 0 then "Right" else "Left"
	local arm = find(model, name .. "Arm")
	local sleeve = find(model, name .. "Sleeve")
	if arm then
		arm.CFrame = shoulder * CFrame.new(0, -ARM_REACH, 0)
	end
	if sleeve then
		sleeve.CFrame = shoulder * CFrame.new(0, -SLEEVE_REACH, 0)
	end
end

-- Shared with the penalty screen: puts one arm up (see poseArm).
TrophyScene.poseArm = poseArm

-- A gold cup standing on `origin`: foot, stem, bowl and two handles.
local function buildCup(origin: Vector3): Model
	local cup = Instance.new("Model")
	cup.Name = "Cup"
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local function piece(size: Vector3, offset: Vector3, shape: Enum.PartType?)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = GOLD
		part.Shape = shape or Enum.PartType.Block
		part.Size = size
		part.CFrame = CFrame.new(origin + offset)
			* (if shape == Enum.PartType.Cylinder then upright else CFrame.new())
		part.Parent = cup
	end
	piece(Vector3.new(0.3, 1.5, 1.5), Vector3.new(0, 0.15, 0), Enum.PartType.Cylinder)
	piece(Vector3.new(1.1, 0.45, 0.45), Vector3.new(0, 0.8, 0), Enum.PartType.Cylinder)
	piece(Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 1.9, 0), Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		piece(Vector3.new(0.25, 0.8, 0.25), Vector3.new(side * 1.0, 2.0, 0))
	end
	-- An upright anchor at the foot, so moving the cup keeps it standing (a model with no primary
	-- part takes its turn from the first part, which is a turned cylinder).
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(origin)
	anchor.Parent = cup
	cup.PrimaryPart = anchor
	return cup
end

local function confetti(parent: GuiObject, running: () -> boolean)
	for _ = 1, CONFETTI_PIECES do
		local size = math.random(6, 11)
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(size, size * 0.6)
		piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 180)
		piece.Position = UDim2.fromScale(math.random(), -0.1)
		piece.ZIndex = 12
		piece.Parent = parent
		task.spawn(function()
			task.wait(math.random() * 2)
			while running() do
				local fall = 2.2 + math.random() * 1.8
				local startX = math.random()
				piece.Position = UDim2.fromScale(startX, -0.1)
				local goal = {
					Position = UDim2.fromScale(startX + (math.random() - 0.5) * 0.2, 1.1),
					Rotation = piece.Rotation + math.random(180, 540),
				}
				local info = TweenInfo.new(fall, Enum.EasingStyle.Linear)
				TweenService:Create(piece, info, goal):Play()
				task.wait(fall)
			end
			piece:Destroy()
		end)
	end
end

-- Builds the scene in `parent` and returns a function that stops it. With `still`, the players hold
-- their pose and there is no motion at all (reduced motion).
function TrophyScene.build(parent: GuiObject, fieldIds: { string }, still: boolean): () -> ()
	local view = Instance.new("ViewportFrame")
	view.Name = "TrophyScene"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(190, 190, 200)
	view.LightColor = Color3.fromRGB(255, 244, 225)
	view.LightDirection = Vector3.new(0.3, -0.6, 0.7)
	view.ZIndex = 10
	view.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 4.6, -17), Vector3.new(0, 3.6, 0))
	view.CurrentCamera = camera
	camera.Parent = view

	type Figure = { model: Model, x: number, z: number, phase: number, leader: boolean }
	local figures: { Figure } = {}
	for index = 1, math.min(#fieldIds, MAX_PLAYERS) do
		local def = Config.PlayersById[fieldIds[index]]
		local stand = STANDS[index]
		if def and stand then
			local model = Mannequin.build(def, nil, false)
			model.Parent = view
			table.insert(figures, {
				model = model,
				x = stand[1],
				z = stand[2],
				phase = index * 1.3,
				leader = index == 1,
			})
		end
	end

	local leaderCup: Model? = nil
	if figures[1] then
		local cup = buildCup(Vector3.zero)
		cup.Parent = view
		leaderCup = cup
	end

	local function pose(time: number)
		for _, figure in figures do
			local hop = if still then 0 else math.abs(math.sin(time * 4 + figure.phase)) * 0.7
			local base = CFrame.new(figure.x, FEET_TO_TORSO + hop, figure.z)
			figure.model:PivotTo(base)
			local wave = if still then 0 else math.sin(time * 6 + figure.phase) * 12
			if figure.leader then
				poseArm(figure.model, base, 1, 168 + wave * 0.3) -- the cup arm, nearly straight up
				poseArm(figure.model, base, -1, 140 + wave)
				if leaderCup then
					-- The hand is at the end of the raised arm; the cup stands on it.
					local hand = base
						* CFrame.new(1.4, ARM_Y, 0)
						* CFrame.Angles(0, 0, math.rad(168 + wave * 0.3))
						* CFrame.new(0, -1.85, 0)
					leaderCup:PivotTo(CFrame.new(hand.Position + Vector3.new(0, 0.1, 0)))
				end
			else
				poseArm(figure.model, base, 1, 150 + wave)
				poseArm(figure.model, base, -1, 150 - wave)
			end
		end
	end
	pose(0)

	local alive = true
	local connection: RBXScriptConnection? = nil
	if not still then
		local started = os.clock()
		connection = RunService.RenderStepped:Connect(function()
			pose(os.clock() - started)
		end)
		confetti(parent, function()
			return alive
		end)
	end

	return function()
		alive = false
		if connection then
			connection:Disconnect()
		end
	end
end

return TrophyScene
