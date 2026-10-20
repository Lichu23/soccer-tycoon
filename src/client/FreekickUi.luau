--!strict
-- The free kicks screen (docs/PLAN.md, Step 4), in the look of the keepie-uppies and the penalty
-- screens (the shared Panel, no title, the numbers as plain text over the picture): a 3D goal with a
-- keeper and a wall of three defenders, seen from behind the ball. Every kick has three steps, like
-- the place kicks of an old rugby game, and only the step in play shows: tap anywhere on the picture
-- to stop the power bar, tap a point on the big ball (the side curls the shot, below the middle lifts
-- it over the wall), then tap anywhere to stop the aim marker that sweeps across the goal along the
-- curve. The shot flies on the same curve the server judged it with (the same Freekick functions); a
-- goal adds to the streak, anything else ends it. The medals are streak milestones and your longest
-- streak is kept. Until the first goal ever, a pointing hand and a short hint guide each step (the
-- tutorial). The server pays and keeps the record. The screen shows while the player stands on the
-- free-kick spot.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Freekick = require(ReplicatedStorage.Shared.Freekick)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)
local TrophyScene = require(script.Parent.TrophyScene)

local player = Players.LocalPlayer

local PANEL_HEIGHT = 0.94 -- the share of the screen height the panel takes, like the penalty screen
local PANEL_TOP = 10 -- the panel has no title, so the content starts near its top edge
local CARD_CHROME = 4 + 20 + 8 -- the card padding and the gap above the hint
local MIN_SCENE_HEIGHT = 160
local CHIPS_HEIGHT = 44
local CHIPS_WIDTH = 170
local HINT_HEIGHT = 18
local POWER_TOP = 66 -- the top of the power bar, under the medal bar and its label
local POWER_LEFT = 14
local POWER_WIDTH = 30
local POWER_GOOD_MAX = 0.9 -- the top of the green zone of the power bar
local CONTACT_Y = 0.56 -- where the big ball to tap sits, down the picture
local FEEDBACK_HOLD_SECONDS = 0.9
local FEEDBACK_FADE_SECONDS = 0.3

-- The pitch, in studs: the goal line is at z 0 and the camera looks straight at it from behind the
-- ball (screen right is +X). One goal unit of the shot maths is GOAL_HALF_WIDTH across and
-- GOAL_HEIGHT up.
local GOAL_HALF_WIDTH = 8
local GOAL_HEIGHT = 7
local BALL_Z = 24 -- where the ball lies
local CAMERA_POSITION = Vector3.new(0, 3.4, 36)
local FIELD_OF_VIEW = 40
local BALL_SIZE = 1.1
local BALL_START = Vector3.new(0, BALL_SIZE / 2, BALL_Z)
local KEEPER_Z = 0.8
local WALL_SCALE = 0.8 -- three defenders at this scale are as wide and as high as the wall of the maths
local WALL_SPACING = 1.6
local TRAVEL_SECONDS = 0.9 -- how long the ball takes to the goal (the rest of the flight time shows it there)
local REBOUND_SECONDS = 0.4
local KEEPER_DIVE = 3.2 -- how far the keeper gets across, in studs, when the shot is out of his reach

local MEDAL_NAMES = { [0] = "No medal", [1] = "BRONZE", [2] = "SILVER", [3] = "GOLD" }
local MEDAL_COLORS = {
	[0] = Color3.fromRGB(150, 155, 170),
	[1] = Color3.fromRGB(205, 140, 80),
	[2] = Color3.fromRGB(205, 210, 225),
	[3] = Color3.fromRGB(255, 205, 60),
}
local BAD = Color3.fromRGB(232, 142, 138)
local WHITE = Color3.fromRGB(255, 255, 255)
local GRASS = Color3.fromRGB(58, 138, 62)
local GRASS_LIGHT = Color3.fromRGB(68, 154, 72)
local LINE = Color3.fromRGB(245, 245, 245)
local CONCRETE = Color3.fromRGB(168, 168, 174)
local KEEPER_KIT = Color3.fromRGB(240, 200, 50)
local WALL_KIT = Color3.fromRGB(200, 50, 60)
local FANS = {
	Color3.fromRGB(230, 90, 90),
	Color3.fromRGB(90, 140, 230),
	Color3.fromRGB(240, 200, 70),
	Color3.fromRGB(120, 200, 130),
	Color3.fromRGB(230, 230, 235),
}

local STEP_NAMES: { [string]: string } = {
	power = "1  POWER",
	contact = "2  CONTACT",
	aim = "3  AIM",
}

-- The tutorial's hint for each step.
local COACH_TEXT: { [string]: string } = {
	waiting = "Your first free kick! Get ready...",
	power = "Tap anywhere when the bar is green.",
	contact = "Tap the ball: below the middle lifts it over the wall, the side curls it.",
	aim = "Tap anywhere when the ring is where you want to score.",
}

local OUTCOME_TEXT: { [string]: string } = {
	goal = "GOAL!",
	wall = "BLOCKED BY THE WALL",
	saved = "SAVED!",
	wide = "WIDE",
	post = "OFF THE POST",
	over = "OVER THE BAR",
	bar = "OFF THE BAR",
}

-- How far along the flight (0 at the ball, 1 at the goal line) the ball stops for each outcome.
local STOP_AT: { [string]: number } = {
	wall = Config.Training.freekickWallAt - 0.02,
	saved = 1,
	post = 1,
	bar = 1,
	goal = 1.1,
	wide = 1.12,
	over = 1.12,
}

local FreekickUi = {}

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

local function rounded(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- A white text with a thick dark outline, like the pad labels.
local function outlined(props: { [string]: any }, parent: Instance): TextLabel
	props.BackgroundTransparency = 1
	props.Font = Style.font
	if props.TextColor3 == nil then
		props.TextColor3 = WHITE
	end
	local label = new("TextLabel", props, parent)
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	return label
end

-- A label that scales its text down to fit the box, never above `maxSize`.
local function fitted(label: TextLabel, maxSize: number)
	label.TextScaled = true
	new("UITextSizeConstraint", { MaxTextSize = maxSize }, label)
end

local function block(
	parent: Instance,
	size: Vector3,
	position: Vector3,
	color: Color3,
	transparency: number?
): Part
	return new("Part", {
		Anchored = true,
		CanCollide = false,
		Size = size,
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

-- The pitch, the goal with its net, a small stand behind it.
local function buildPitch(view: ViewportFrame)
	block(view, Vector3.new(140, 1, 90), Vector3.new(0, -0.5, 15), GRASS)
	for index = 0, 6 do
		block(view, Vector3.new(140, 0.05, 4), Vector3.new(0, 0.02, 34 - index * 8), GRASS_LIGHT)
	end
	block(view, Vector3.new(80, 0.08, 0.4), Vector3.new(0, 0.05, 0), LINE) -- the goal line
	block(view, Vector3.new(40, 0.08, 0.4), Vector3.new(0, 0.05, 11), LINE) -- the box
	block(view, Vector3.new(0.4, 0.08, 11), Vector3.new(-20, 0.05, 5.5), LINE)
	block(view, Vector3.new(0.4, 0.08, 11), Vector3.new(20, 0.05, 5.5), LINE)
	local spot = block(view, Vector3.new(0.05, 1.6, 1.6), Vector3.new(0, 0.03, BALL_Z), LINE)
	spot.Shape = Enum.PartType.Cylinder
	spot.CFrame = CFrame.new(0, 0.03, BALL_Z) * CFrame.Angles(0, 0, math.pi / 2)

	local post = 0.5
	block(
		view,
		Vector3.new(post, GOAL_HEIGHT, post),
		Vector3.new(-GOAL_HALF_WIDTH, GOAL_HEIGHT / 2, 0),
		LINE
	)
	block(
		view,
		Vector3.new(post, GOAL_HEIGHT, post),
		Vector3.new(GOAL_HALF_WIDTH, GOAL_HEIGHT / 2, 0),
		LINE
	)
	block(
		view,
		Vector3.new(GOAL_HALF_WIDTH * 2 + post, post, post),
		Vector3.new(0, GOAL_HEIGHT, 0),
		LINE
	)
	block(
		view,
		Vector3.new(GOAL_HALF_WIDTH * 2, GOAL_HEIGHT, 0.1),
		Vector3.new(0, GOAL_HEIGHT / 2, -3),
		Color3.fromRGB(30, 60, 45),
		0.55
	)
	for x = -GOAL_HALF_WIDTH + 1, GOAL_HALF_WIDTH - 1 do
		block(
			view,
			Vector3.new(0.06, GOAL_HEIGHT, 0.06),
			Vector3.new(x, GOAL_HEIGHT / 2, -2.95),
			LINE,
			0.45
		)
	end
	for y = 1, GOAL_HEIGHT - 1 do
		block(
			view,
			Vector3.new(GOAL_HALF_WIDTH * 2, 0.06, 0.06),
			Vector3.new(0, y, -2.95),
			LINE,
			0.45
		)
	end

	for row = 0, 2 do
		local top = 1.6 * (row + 1)
		local z = -8 - row * 3
		block(view, Vector3.new(110, top, 3), Vector3.new(0, top / 2, z), CONCRETE)
		local k = 0
		for x = -52, 52, 3.2 do
			k += 1
			if (row * 7 + k * 3) % 5 ~= 0 then
				block(
					view,
					Vector3.new(1.1, 1.7, 1),
					Vector3.new(x, top + 1.1, z + 0.3),
					FANS[(row + k) % #FANS + 1]
				)
			end
		end
	end
end

function FreekickUi.init()
	local gui = new("ScreenGui", {
		Name = "Freekick",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local built = Panel.build(gui, "Free kicks", PANEL_HEIGHT, function() end)
	local backdrop, card = built.backdrop, built.card
	-- The spot is left by walking off it, so the X has no job here, and there is no title.
	local closeX = backdrop:FindFirstChild("CloseX", true)
	if closeX and closeX:IsA("GuiObject") then
		closeX.Visible = false
	end
	local panel = backdrop:FindFirstChild("Panel") :: Frame
	local panelTitle = panel:FindFirstChild("Title")
	if panelTitle and panelTitle:IsA("GuiObject") then
		panelTitle.Visible = false
	end
	local scroll = panel:FindFirstChild("Scroll") :: ScrollingFrame
	scroll.Position = UDim2.fromOffset(0, PANEL_TOP)
	scroll.Size = UDim2.new(1, 0, 1, -PANEL_TOP)
	local cardLayout = card:FindFirstChildOfClass("UIListLayout")
	if cardLayout then
		cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	-- The scene: the goal, the keeper, the wall and the ball ------------------------------------------
	local sceneBox = new("Frame", {
		Name = "Scene",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(300, 200),
		BackgroundColor3 = Color3.fromRGB(150, 196, 236),
		ClipsDescendants = true,
		ZIndex = 7,
	}, card)
	rounded(sceneBox, 12)
	local view = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 212),
		LightColor = Color3.fromRGB(255, 244, 225),
		LightDirection = Vector3.new(-0.3, -1, -0.5),
		ZIndex = 7,
	}, sceneBox)
	local camera = new("Camera", {
		FieldOfView = FIELD_OF_VIEW,
		CFrame = CFrame.lookAt(CAMERA_POSITION, Vector3.new(0, CAMERA_POSITION.Y, 0)),
	}, view)
	view.CurrentCamera = camera
	buildPitch(view)

	-- The keeper, in a goalkeeper's shirt, turned to face the kicker.
	local keeper = Mannequin.build(Config.Players[1], KEEPER_KIT, false)
	keeper.Parent = view
	local function setKeeper(position: Vector3, tilt: number, arms: number)
		local base = CFrame.new(position)
			* CFrame.Angles(0, 0, math.rad(tilt))
			* CFrame.Angles(0, math.pi, 0)
		keeper:PivotTo(base)
		TrophyScene.poseArm(keeper, base, 1, arms)
		TrophyScene.poseArm(keeper, base, -1, arms)
	end
	local keeperRestY = Mannequin.FEET_TO_TORSO

	-- The wall: three defenders shoulder to shoulder.
	local wall: { Model } = {}
	for index = 1, 3 do
		local def = Config.Players[index + 1] or Config.Players[1]
		local model = Mannequin.build(def, WALL_KIT, false)
		model:ScaleTo(WALL_SCALE)
		model.Parent = view
		table.insert(wall, model)
	end
	local wallZ = BALL_Z * (1 - Config.Training.freekickWallAt)
	local function setWall(centerX: number, lift: number)
		for index, model in wall do
			local x = centerX + (index - 2) * WALL_SPACING
			model:PivotTo(
				CFrame.new(x, Mannequin.FEET_TO_TORSO * WALL_SCALE + lift, wallZ)
					* CFrame.Angles(0, math.pi, 0)
			)
		end
	end

	local ball = new("Part", {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE),
		Position = BALL_START,
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	}, view)

	-- Where a point of the pitch shows in the picture (a level camera, so plain maths).
	local function project(world: Vector3): UDim2
		local size = sceneBox.AbsoluteSize
		local aspect = if size.Y > 0 then size.X / size.Y else 1.6
		local depth = math.max(CAMERA_POSITION.Z - world.Z, 0.1)
		local halfHeight = depth * math.tan(math.rad(FIELD_OF_VIEW / 2))
		local nx = world.X / (halfHeight * aspect)
		local ny = (world.Y - CAMERA_POSITION.Y) / halfHeight
		return UDim2.fromScale(0.5 + nx / 2, 0.5 - ny / 2)
	end

	-- The aim: a ring on the goal and a dotted line from the ball to it -----------------------------
	local aimRing = new("Frame", {
		Name = "Aim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 9,
	}, sceneBox)
	rounded(aimRing, 1000)
	new("UIStroke", { Color = Style.ui.gold, Thickness = 4 }, aimRing)
	local aimDot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Style.ui.gold,
		ZIndex = 9,
	}, aimRing)
	rounded(aimDot, 1000)
	local trail: { Frame } = {}
	for _ = 1, 8 do
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.15,
			Visible = false,
			ZIndex = 9,
		}, sceneBox)
		rounded(dot, 1000)
		new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5 }, dot)
		table.insert(trail, dot)
	end

	-- The power bar on the left -------------------------------------------------------------------
	local powerBox = new("Frame", {
		Name = "Power",
		Position = UDim2.fromOffset(POWER_LEFT, POWER_TOP),
		Size = UDim2.fromOffset(POWER_WIDTH, 120),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		ZIndex = 9,
	}, sceneBox)
	rounded(powerBox, 8)
	local powerStroke =
		new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 3 }, powerBox)
	-- A guide: the green zone, where a normal shot is neither too weak nor over the bar. Its edges are
	-- marked over the fill, and the fill turns green inside it.
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1 - Config.Training.freekickWeakPower),
		Size = UDim2.fromScale(1, POWER_GOOD_MAX - Config.Training.freekickWeakPower),
		BackgroundColor3 = Style.ui.good,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, powerBox)
	for _, edge in { Config.Training.freekickWeakPower, POWER_GOOD_MAX } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1 - edge),
			Size = UDim2.new(1, 10, 0, 3),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, powerBox)
	end
	local powerFill = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Style.ui.gold,
		ZIndex = 10,
	}, powerBox)
	rounded(powerFill, 8)
	local powerLabel = outlined({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(-6, -4),
		Size = UDim2.fromOffset(60, 16),
		Text = "POWER",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	}, powerBox)
	powerLabel.Name = "PowerLabel"

	-- The big ball to tap for the contact point, in the middle while that step is in play ---------
	local contactBall = new("TextButton", {
		Name = "ContactBall",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, CONTACT_Y),
		Visible = false,
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Color3.fromRGB(248, 248, 248),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
	}, sceneBox)
	rounded(contactBall, 1000)
	local contactStroke = new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, contactBall)
	local contactScale = new("UIScale", {}, contactBall)
	for _, line in { { 1, 0.02 }, { 0.02, 1 } } do -- a light cross through the middle
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(line[1], line[2]),
			BackgroundColor3 = Color3.fromRGB(170, 175, 190),
			BorderSizePixel = 0,
			ZIndex = 10,
		}, contactBall)
	end
	local patch = new("Frame", { -- the black patch of the ball
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.26, 0.26),
		BackgroundColor3 = Color3.fromRGB(40, 42, 52),
		BackgroundTransparency = 0.35,
		ZIndex = 10,
	}, contactBall)
	rounded(patch, 6)
	local contactDot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.fromRGB(230, 60, 60),
		Visible = false,
		ZIndex = 11,
	}, contactBall)
	rounded(contactDot, 1000)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, contactDot)

	-- The whole picture is the button for the power and the aim (under the big ball, which takes its
	-- own taps).
	local tapArea = new("TextButton", {
		Name = "TapArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
	}, sceneBox)

	-- The texts over the scene ---------------------------------------------------------------------
	local stepText = outlined({
		Name = "Step",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 11,
	}, sceneBox)
	fitted(stepText, 28)
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.16),
		Text = "",
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 12,
	}, sceneBox)
	fitted(feedback, 54)
	local feedbackStroke = feedback:FindFirstChildOfClass("UIStroke") :: UIStroke
	feedbackStroke.Transparency = 1
	local tpText = outlined({
		Name = "Tp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.51),
		Size = UDim2.new(0.6, 0, 0, 28),
		Text = "",
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 12,
	}, sceneBox)
	fitted(tpText, 24)
	local tpStroke = tpText:FindFirstChildOfClass("UIStroke") :: UIStroke
	tpStroke.Transparency = 1
	local feedbackToken = 0
	local function popFeedback(text: string, color: Color3, tp: string)
		feedbackToken += 1
		local myToken = feedbackToken
		feedback.Text = text
		feedback.TextColor3 = color
		tpText.Text = tp
		for _, item in { feedback, tpText } :: { TextLabel } do
			item.TextTransparency = 0
		end
		feedbackStroke.Transparency = 0
		tpStroke.Transparency = 0
		task.delay(FEEDBACK_HOLD_SECONDS, function()
			if feedbackToken ~= myToken then
				return
			end
			local info = TweenInfo.new(FEEDBACK_FADE_SECONDS)
			TweenService:Create(feedback, info, { TextTransparency = 1 }):Play()
			TweenService:Create(feedbackStroke, info, { Transparency = 1 }):Play()
			TweenService:Create(tpText, info, { TextTransparency = 1 }):Play()
			TweenService:Create(tpStroke, info, { Transparency = 1 }):Play()
		end)
	end

	-- The streak and the medal bar ---------------------------------------------------------------------
	local medalBar = new("Frame", {
		Name = "Medals",
		Position = UDim2.fromOffset(12, 22),
		Size = UDim2.new(0.3, 0, 0, 10),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.25,
		ZIndex = 9,
	}, sceneBox)
	rounded(medalBar, 5)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, medalBar)
	local medalFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = MEDAL_COLORS[1],
		BorderSizePixel = 0,
		ZIndex = 10,
	}, medalBar)
	rounded(medalFill, 5)
	local medals = Config.Training.freekickMedals
	for medal, goals in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(goals / medals.gold, -0.5),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 11,
		}, medalBar)
	end

	local chipRow = new("Frame", {
		Name = "Chips",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(CHIPS_WIDTH, CHIPS_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, sceneBox)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, chipRow)
	-- A small name over a big value, as plain text on the picture (no card).
	local function chip(order: number, name: string): TextLabel
		local box = new("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1 / 2, -4, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 9,
		}, chipRow)
		outlined({
			Size = UDim2.new(1, 0, 0, 16),
			Text = string.upper(name),
			TextSize = 14,
			ZIndex = 9,
		}, box)
		return outlined({
			Name = "Value",
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 1, -16),
			Text = "-",
			TextSize = 26,
			ZIndex = 9,
		}, box)
	end
	local streakValue = chip(1, "Streak")
	local bestValue = chip(2, "Best")

	-- The tutorial: a hint at the bottom and a hand that points at what to tap -------------------------
	local coachText = outlined({
		Name = "Coach",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.86, 0, 0, 34),
		Text = "",
		Visible = false,
		ZIndex = 13,
	}, sceneBox)
	fitted(coachText, 24)
	local hand = new("TextLabel", {
		Name = "Hand",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Text = "👆",
		TextSize = 44,
		Visible = false,
		ZIndex = 13,
	}, sceneBox)

	-- The result of a streak, over the scene -----------------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 16,
	}, sceneBox)
	rounded(resultCard, 14)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.4),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 17,
	}, resultCard)
	fitted(medalText, 46)
	local resultLine = outlined({
		Position = UDim2.fromScale(0.04, 0.48),
		Size = UDim2.fromScale(0.92, 0.22),
		Text = "",
		ZIndex = 17,
	}, resultCard)
	fitted(resultLine, 22)
	local bestLine = outlined({
		Position = UDim2.fromScale(0.04, 0.73),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 17,
	}, resultCard)
	fitted(bestLine, 18)

	new("TextLabel", {
		Name = "Hint",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, HINT_HEIGHT),
		BackgroundTransparency = 1,
		Text = "Walk off the spot to stop.",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Panel.MUTED,
		ZIndex = 7,
	}, card)

	-- The picture takes what the screen allows; the big ball grows with it.
	local function fit()
		local size = panel.AbsoluteSize
		if size.Y < 1 then
			return
		end
		local width = size.X - 40
		local height =
			math.max(size.Y - PANEL_TOP - CARD_CHROME - HINT_HEIGHT - 4, MIN_SCENE_HEIGHT)
		sceneBox.Size = UDim2.fromOffset(width, height)
		local ballSize = math.clamp(height * 0.44, 100, 230)
		contactBall.Size = UDim2.fromOffset(ballSize, ballSize)
		-- The power bar runs from under the medal bar down to the bottom of the picture.
		powerBox.Size = UDim2.fromOffset(POWER_WIDTH, math.max(height - POWER_TOP - 24, 60))
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local function pulse(scale: UIScale, from: number)
		if GuiService.ReducedMotionEnabled then
			return
		end
		scale.Scale = from
		TweenService:Create(
			scale,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	-- The server's state, mirrored from the attributes ---------------------------------------------
	local state: Freekick.State = Freekick.new(0)
	-- What the player just set, shown at once until the server's answer arrives.
	local lockedPower: number? = nil
	local lockedAim: number? = nil
	local contactTapped = false -- the ball was tapped and the server has not answered yet
	local function number(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local function readServerState()
		local phase = player:GetAttribute("freekickState")
		if
			phase == "power"
			or phase == "contact"
			or phase == "aim"
			or phase == "flight"
			or phase == "over"
		then
			state.phase = phase
		end
		state.seed = number("freekickSeed")
		state.kick = math.max(number("freekickKick"), 1)
		state.stageAt = number("freekickStageAt")
		state.power = number("freekickPower")
		state.contactX = number("freekickContactX")
		state.contactY = number("freekickContactY")
		state.aim = number("freekickAim")
		local outcome = player:GetAttribute("freekickOutcome")
		state.outcome = if type(outcome) == "string" then outcome else ""
		state.streak = number("freekickStreak")
		state.overAt = number("freekickOverAt")
	end
	readServerState()
	for _, name in
		{
			"freekickSeed",
			"freekickKick",
			"freekickStageAt",
			"freekickPower",
			"freekickContactX",
			"freekickContactY",
			"freekickAim",
			"freekickOutcome",
			"freekickStreak",
			"freekickOverAt",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end
	player:GetAttributeChangedSignal("freekickState"):Connect(function()
		lockedPower = nil
		lockedAim = nil
		contactTapped = false
		readServerState()
	end)

	local function press()
		if not backdrop.Visible then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if state.phase == "power" and lockedPower == nil and now >= state.stageAt then
			lockedPower = Freekick.powerAt(state, now)
		elseif state.phase == "aim" and lockedAim == nil then
			lockedAim = Freekick.aimAt(state, now)
		else
			return
		end
		Net.fire("FreekickTap", now)
	end
	tapArea.Activated:Connect(press)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E then
			press()
		end
	end)

	-- A tap on the ball: where on it, from -1 to 1 across and up.
	contactBall.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if state.phase ~= "contact" or not backdrop.Visible then
			return
		end
		local size = contactBall.AbsoluteSize
		if size.X < 1 then
			return
		end
		local relative = (
			Vector2.new(input.Position.X, input.Position.Y) - contactBall.AbsolutePosition
		) / size
		local x = math.clamp(relative.X * 2 - 1, -1, 1)
		local y = math.clamp(1 - relative.Y * 2, -1, 1)
		state.contactX, state.contactY = x, y -- shown at once
		contactTapped = true
		pulse(contactScale, 0.9)
		Net.fire("FreekickContact", x, y)
	end)

	-- What the server tells us ---------------------------------------------------------------------
	local shotToken = 0
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "freekickShot" then
			Sounds.play("kick")
			local outcome = if type(info.outcome) == "string" then info.outcome else ""
			local paid = if type(info.paid) == "number" then info.paid else 0
			shotToken += 1
			local myToken = shotToken
			-- The words and the sound come when the ball gets there.
			local arrive = TRAVEL_SECONDS * (STOP_AT[outcome] or 1)
			task.delay(arrive, function()
				if shotToken ~= myToken or not backdrop.Visible then
					return
				end
				if outcome == "goal" then
					Sounds.play("net")
					Sounds.play("goal")
					popFeedback(
						"GOAL!",
						Style.ui.good,
						if info.capped == true then "MAX RATE" else string.format("+%.2f TP", paid)
					)
				else
					if outcome == "saved" then
						Sounds.play("save")
					elseif outcome == "post" or outcome == "bar" then
						Sounds.play("post")
					end
					popFeedback(OUTCOME_TEXT[outcome] or "MISSED", BAD, "")
				end
			end)
		elseif info.kind == "freekickOver" then
			local medal = if type(info.medal) == "number" then info.medal else 0
			local streak = if type(info.streak) == "number" then info.streak else 0
			if streak <= 0 then
				return -- the miss banner already said it; no card for a streak that never started
			end
			medalText.Text = MEDAL_NAMES[medal] or ""
			medalText.TextColor3 = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultStroke.Color = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultLine.Text =
				string.format("Streak: %d goal%s", streak, if streak == 1 then "" else "s")
			local record = player:GetAttribute("freekickBestStreak")
			bestLine.Text = if info.newBest == true
				then "NEW PERSONAL BEST!"
				else string.format(
					"Personal best: %d",
					if type(record) == "number" then record else 0
				)
			bestLine.TextColor3 = if info.newBest == true then Style.ui.gold else Style.ui.idle
			resultCard.Visible = true
			pulse(resultScale, 0.6)
		end
	end)

	-- The flight of the shot: across with the curl, up through the height at the wall and at the goal.
	local wallAt = Config.Training.freekickWallAt
	local function flightPoint(t: number): Vector3
		local flight = Freekick.flight(state.power, state.contactX, state.contactY)
		-- h(t) = a t + b t^2 through (wallAt, wallHeight) and (1, goalHeight).
		local b = (wallAt * flight.goalHeight - flight.wallHeight) / (wallAt * wallAt - wallAt)
		local a = flight.goalHeight - b
		local height = a * t + b * t * t
		return Vector3.new(
			Freekick.ballX(state.aim, flight.bend, t) * GOAL_HALF_WIDTH,
			math.max(height * GOAL_HEIGHT, 0) + BALL_SIZE / 2,
			BALL_Z * (1 - t)
		)
	end

	-- Every frame ------------------------------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "freekick"
		backdrop.Visible = active
		if not active then
			resultCard.Visible = false
			return
		end
		local now = Workspace:GetServerTimeNow()
		local phase = state.phase
		local setup = Freekick.setup(state.seed, state.kick)
		local flying = phase == "flight"
		local elapsed = now - state.stageAt

		-- The wall jumps as the ball is struck; the keeper dives.
		local jump = if flying and not GuiService.ReducedMotionEnabled
			then 1.2 * math.sin(math.pi * math.clamp(elapsed / 0.6, 0, 1))
			else 0
		setWall(setup.wallX * GOAL_HALF_WIDTH, jump)
		local keeperX = setup.keeperX * GOAL_HALF_WIDTH
		if flying then
			local stop = STOP_AT[state.outcome] or 1
			local arrive = TRAVEL_SECONDS * stop
			local target = flightPoint(math.min(stop, 1))
			local dive = math.clamp((elapsed - 0.2) / 0.5, 0, 1)
			local goalX = target.X
			local reachX = if state.outcome == "saved"
				then goalX
				else keeperX + math.clamp(goalX - keeperX, -KEEPER_DIVE, KEEPER_DIVE)
			local side = if reachX >= keeperX then 1 else -1
			local reachY = math.clamp(target.Y, keeperRestY, GOAL_HEIGHT - 1)
			setKeeper(
				Vector3.new(
					keeperX + (reachX - keeperX) * dive,
					keeperRestY + (reachY - keeperRestY) * dive,
					KEEPER_Z
				),
				-side * 55 * dive,
				35 + 125 * dive
			)

			-- The ball: along the flight, then a rebound off the wall, the post or the bar.
			if elapsed < arrive then
				ball.Position = flightPoint(stop * elapsed / arrive)
			elseif state.outcome == "wall" or state.outcome == "post" or state.outcome == "bar" then
				local q = math.clamp((elapsed - arrive) / REBOUND_SECONDS, 0, 1)
				local hit = flightPoint(stop)
				ball.Position =
					Vector3.new(hit.X, math.max(hit.Y * (1 - q), BALL_SIZE / 2), hit.Z + 4 * q)
			else
				ball.Position = flightPoint(stop)
			end
		else
			setKeeper(Vector3.new(keeperX, keeperRestY, KEEPER_Z), 0, 35)
			ball.Position = BALL_START
		end

		-- The power bar.
		local power = if phase == "power"
			then (lockedPower or (if now >= state.stageAt then Freekick.powerAt(state, now) else 0))
			elseif phase == "over" then 0
			else state.power
		powerFill.Size = UDim2.fromScale(1, power)
		local good = power >= Config.Training.freekickWeakPower and power <= POWER_GOOD_MAX
		powerFill.BackgroundColor3 = if good then Style.ui.good else BAD
		powerStroke.Color = if phase == "power" then Style.ui.gold else Color3.fromRGB(0, 0, 0)
		powerBox.Visible = phase == "power"

		-- The ball to tap, and the point chosen on it.
		local choosing = phase == "contact"
		contactStroke.Color = if choosing then Style.ui.gold else Color3.fromRGB(0, 0, 0)
		contactStroke.Thickness = if choosing then 5 else 4
		if choosing and not GuiService.ReducedMotionEnabled then
			contactScale.Scale = 1 + 0.05 * math.sin(os.clock() * 6)
		end
		contactBall.Visible = choosing
		contactDot.Visible = choosing and contactTapped
		contactDot.Position = UDim2.fromScale(0.5 + state.contactX / 2, 0.5 - state.contactY / 2)

		-- The aim marker sweeps across the goal; a dotted line runs from the ball to it, bent by the
		-- curl of the contact point (the height is left to the player to judge).
		local aiming = phase == "aim"
		local aim = if aiming then (lockedAim or Freekick.aimAt(state, now)) else 0
		aimRing.Visible = aiming
		local target = Vector3.new(aim * GOAL_HALF_WIDTH, GOAL_HEIGHT * 0.45, 0)
		aimRing.Position = project(target)
		local bend = state.contactX * Config.Training.freekickCurl
		for index, dot in trail do
			dot.Visible = aiming
			local f = index / (#trail + 1)
			dot.Position = project(
				Vector3.new(
					Freekick.ballX(aim, bend, f) * GOAL_HALF_WIDTH,
					BALL_START.Y + (target.Y - BALL_START.Y) * f,
					BALL_Z * (1 - f)
				)
			)
		end

		-- The texts.
		local untilStart = state.stageAt - now
		local waiting = phase == "power" and untilStart > 0
		stepText.Text = if waiting then "GET READY" else (STEP_NAMES[phase] or "")
		resultCard.Visible = phase == "over" and resultCard.Visible
		local shown = if flying
				and state.outcome == "goal"
				and elapsed < TRAVEL_SECONDS
			then state.streak - 1
			else state.streak
		streakValue.Text = tostring(math.max(shown, 0))
		local record = player:GetAttribute("freekickBestStreak")
		bestValue.Text = tostring(if type(record) == "number" then record else 0)
		bestValue.TextColor3 = if shown > 0
				and type(record) == "number"
				and shown >= record
			then Style.ui.gold
			else WHITE
		medalFill.Size = UDim2.fromScale(math.clamp(shown / medals.gold, 0, 1), 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Freekick.medal(shown), 1)]

		-- The tutorial, until the first goal ever: a hint for the step and a hand on what to tap.
		local tutorial = state.kick == 1 and (type(record) ~= "number" or record <= 0)
		local coachStep = if waiting then "waiting" else phase
		local hint = if tutorial then COACH_TEXT[coachStep] else nil
		coachText.Visible = hint ~= nil
		coachText.Text = hint or ""
		local bob = if GuiService.ReducedMotionEnabled then 0 else 6 * math.sin(os.clock() * 7)
		hand.Visible = hint ~= nil and coachStep ~= "waiting"
		if coachStep == "power" then
			-- At the right of the bar, pointing at the green zone.
			local barHeight = powerBox.AbsoluteSize.Y
			hand.Text = "👈"
			hand.Position = UDim2.fromOffset(
				POWER_LEFT + POWER_WIDTH + 34 + bob,
				POWER_TOP + barHeight * (1 - 0.7) - 26
			)
		elseif coachStep == "contact" then
			-- Under a point a little below the middle of the ball.
			local ballSize = contactBall.AbsoluteSize.X
			hand.Text = "👆"
			hand.Position = UDim2.new(0.5, -ballSize * 0.12, CONTACT_Y, ballSize * 0.22 + bob)
		elseif coachStep == "aim" then
			-- Over the aim ring, pointing down, clear of the dotted line.
			hand.Text = "👇"
			hand.Position = aimRing.Position + UDim2.fromOffset(0, -74 + bob)
		end
	end)
end

return FreekickUi
