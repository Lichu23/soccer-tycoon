--!strict
-- The trophy pictures of the New Season screens (client/SeasonUi). The showcase is the trophy being
-- played for, turning slowly in a tile (a dark silhouette while it is locked). The celebration is the
-- trophy just won, big on a plinth in the middle, with the players of the finished season's lineup
-- cheering around it and confetti falling. Both are drawn in ViewportFrames from the trophy models
-- (shared/TrophyModels) and the same mannequins as the capsules. Presentation only: the lineup and the
-- season come from the server, nothing here is saved or decided.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local TrophyModels = require(ReplicatedStorage.Shared.TrophyModels)

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

-- Where each player stands as { x, z }: around the trophy, the first (the best player) on its left,
-- the rest on both sides and a step behind, the last one right behind it. The camera looks at the
-- chests, from the -Z side.
local STANDS = { { -4, 0.8 }, { 4, 0.8 }, { -7.2, 2.4 }, { 7.2, 2.4 }, { 0, 3.6 } }
-- The trophy stands on a plinth in front of the players.
local TROPHY_AT = Vector3.new(0, 0, -2.6)
local PLINTH_HEIGHT = 0.9
local TROPHY_HEIGHT = 5
local TURN_SPEED = 0.6 -- radians a second
local SHOWCASE_FOV = 30

-- Puts one arm up at `angle` degrees: 0 hangs down, 180 is straight up. The right arm leans to +X,
-- the left arm to -X.
local function poseArm(model: Model, base: CFrame, side: number, angle: number)
	local joint = Mannequin.SHOULDER
	local shoulder = base
		* CFrame.new(side * joint.X, joint.Y, joint.Z)
		* CFrame.Angles(0, 0, side * math.rad(angle))
	local arm = model:FindFirstChild(if side > 0 then "Right Arm" else "Left Arm")
	if arm and arm:IsA("BasePart") then
		arm.CFrame = shoulder * CFrame.new(0, -Mannequin.ARM_REACH, 0)
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

-- The trophy of `tier`, scaled to `height` studs and standing on the origin, or the plain cup when
-- the place has no model for it.
local function trophyModel(tier: number, height: number): Model
	local model = TrophyModels.clone(tier) or buildCup(Vector3.zero)
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	if size.Y > 0 then
		model:ScaleTo(model:GetScale() * height / size.Y)
	end
	model:PivotTo(CFrame.new())
	return model
end

-- Gold rays turning slowly behind a picture: thin bars through the middle of `parent` that fade at
-- both ends. Returns the holder.
function TrophyScene.rays(parent: GuiObject, size: number, still: boolean, zIndex: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = zIndex
	holder.Parent = parent
	local bars = 8
	for index = 1, bars do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, math.max(6, math.floor(size * 0.07)), 1, 0)
		bar.BackgroundColor3 = GOLD
		bar.BorderSizePixel = 0
		bar.Rotation = (index - 1) * 180 / bars
		bar.ZIndex = zIndex
		bar.Parent = holder
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = bar
	end
	if not still then
		TweenService:Create(
			holder,
			TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 }
		):Play()
	end
	return holder
end

export type Showcase = {
	setLocked: (locked: boolean) -> (),
	stop: () -> (),
}

-- The trophy of `tier` turning slowly in `parent`, which it fills. Locked, it is a dark silhouette.
-- With `still` it stands at a three-quarter turn and does not move (reduced motion).
function TrophyScene.showcase(parent: GuiObject, tier: number, still: boolean): Showcase
	local view = Instance.new("ViewportFrame")
	view.Name = "Showcase"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(200, 200, 210)
	view.LightColor = Color3.fromRGB(255, 244, 225)
	view.LightDirection = Vector3.new(0.4, -0.7, 0.6)
	view.ZIndex = parent.ZIndex + 2
	view.Parent = parent

	local model = trophyModel(tier, 4)
	model.Parent = view
	local _, size = model:GetBoundingBox()
	local reach = math.max(size.Y, math.sqrt(size.X * size.X + size.Z * size.Z)) / 2
	local distance = reach * 1.2 / math.tan(math.rad(SHOWCASE_FOV / 2))
	local middle = Vector3.new(0, size.Y / 2, 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = SHOWCASE_FOV
	camera.CFrame = CFrame.lookAt(middle + Vector3.new(0, reach * 0.35, -distance), middle)
	view.CurrentCamera = camera
	camera.Parent = view

	local turn = math.rad(-30)
	model:PivotTo(CFrame.Angles(0, turn, 0))
	local connection: RBXScriptConnection? = nil
	if not still then
		connection = RunService.RenderStepped:Connect(function(dt: number)
			turn += dt * TURN_SPEED
			model:PivotTo(CFrame.Angles(0, turn, 0))
		end)
	end

	return {
		setLocked = function(locked: boolean)
			view.ImageColor3 = if locked then Color3.fromRGB(14, 16, 26) else Color3.new(1, 1, 1)
		end,
		stop = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			view:Destroy()
		end,
	}
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

export type SceneOptions = {
	field: { string }, -- the lineup of the finished season, best player first
	tier: number, -- the trophy won (TrophyModels.tier)
	still: boolean, -- reduced motion: the players hold their pose and nothing moves
	confetti: GuiObject?, -- where the confetti falls (the scene itself if nil)
}

-- Builds the celebration in `parent` and returns a function that stops it.
function TrophyScene.build(parent: GuiObject, options: SceneOptions): () -> ()
	local still = options.still
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
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 5.4, -19), Vector3.new(0, 2.6, 0))
	view.CurrentCamera = camera
	camera.Parent = view

	type Figure = { model: Model, x: number, z: number, phase: number }
	local figures: { Figure } = {}
	for index = 1, math.min(#options.field, MAX_PLAYERS) do
		local def = Config.PlayersById[options.field[index]]
		local stand = STANDS[index]
		if def and stand then
			local model = Mannequin.build(def, nil, false)
			model.Parent = view
			table.insert(
				figures,
				{ model = model, x = stand[1], z = stand[2], phase = index * 1.3 }
			)
		end
	end

	-- A white plinth with a gold rim, like the pedestals of the trophy case, and the trophy on it.
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local plinth = Instance.new("Part")
	plinth.Anchored = true
	plinth.Shape = Enum.PartType.Cylinder
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Color = Color3.fromRGB(240, 240, 240)
	plinth.Size = Vector3.new(PLINTH_HEIGHT, 3.6, 3.6)
	plinth.CFrame = CFrame.new(TROPHY_AT + Vector3.new(0, PLINTH_HEIGHT / 2, 0)) * upright
	plinth.Parent = view
	local rim = plinth:Clone()
	rim.Color = GOLD
	rim.Size = Vector3.new(0.2, 3.8, 3.8)
	rim.CFrame = CFrame.new(TROPHY_AT + Vector3.new(0, PLINTH_HEIGHT - 0.1, 0)) * upright
	rim.Parent = view
	local trophy = trophyModel(options.tier, TROPHY_HEIGHT)
	trophy.Parent = view
	local trophyBase = TROPHY_AT + Vector3.new(0, PLINTH_HEIGHT, 0)

	local function pose(time: number)
		for _, figure in figures do
			local hop = if still then 0 else math.abs(math.sin(time * 4 + figure.phase)) * 0.7
			local base = CFrame.new(figure.x, FEET_TO_TORSO + hop, figure.z)
			figure.model:PivotTo(base)
			local wave = if still then 0 else math.sin(time * 6 + figure.phase) * 12
			poseArm(figure.model, base, 1, 150 + wave)
			poseArm(figure.model, base, -1, 150 - wave)
		end
		-- The trophy turns slowly and floats a little over the plinth.
		local float = if still then 0.1 else 0.15 + math.sin(time * 2) * 0.12
		local turn = if still then math.rad(-25) else time * TURN_SPEED
		trophy:PivotTo(
			CFrame.new(trophyBase + Vector3.new(0, float, 0)) * CFrame.Angles(0, turn, 0)
		)
	end
	pose(0)

	local alive = true
	local connection: RBXScriptConnection? = nil
	if not still then
		local started = os.clock()
		connection = RunService.RenderStepped:Connect(function()
			pose(os.clock() - started)
		end)
		confetti(options.confetti or parent, function()
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
