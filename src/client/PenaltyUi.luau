--!strict
-- The penalty kick screen (docs/PLAN.md, Step 7), in the look of the other big screens (the shared
-- Panel): a 3D goal in front of a crowd with a goalkeeper built like the players, five round targets
-- on the goal, and the reward chips under it. Tapping a target sends the aim; the server rolls the
-- kick, and when the answer arrives the ball flies to the target while the keeper dives to the zone
-- the server chose. After the last kick the screen closes and a reward card shows what the goals
-- earned. The animation is only the show: with reduced motion it is skipped.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Icons)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local RewardCard = require(script.Parent.RewardCard)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)
local TrophyScene = require(script.Parent.TrophyScene)

local player = Players.LocalPlayer

local PANEL_HEIGHT = 0.94 -- the share of the screen height the panel takes
local CARD_CHROME = 64 + 4 + 20 + 16 -- the panel header, the card padding and the two gaps
local SCENE_RATIO = 2.2 -- width over height of the picture of the goal
local MIN_SCENE_HEIGHT = 110
local CHIPS_HEIGHT = 56
local RESULT_HEIGHT = 28
local BALL_SECONDS = 0.5
local DIVE_SECONDS = 0.4
local RESULT_SECONDS = 1.1 -- how long a kick result shows before the next kick
local REPLY_TIMEOUT = 3 -- the targets come back if the server never answers
local CLOSE_AFTER_LAST_SECONDS = 1.4
local TARGET_SIZE = 40

-- The goal, in studs: the camera stands in front of it and looks straight at it (screen right is +X).
local GOAL_HALF_WIDTH = 8
local GOAL_HEIGHT = 7
local CAMERA_POSITION = Vector3.new(0, 3.6, 13)
local FIELD_OF_VIEW = 40
local BALL_SIZE = 1.1
local BALL_START = Vector3.new(0, 0.7, 3)
local KEEPER_REST = Vector3.new(0, 3, 0) -- the middle of the torso, feet on the ground

-- Where each target is in the goal (x across, y up).
local TARGETS: { [string]: Vector3 } = {
	topLeft = Vector3.new(-5.5, 5.6, 0),
	topRight = Vector3.new(5.5, 5.6, 0),
	bottomLeft = Vector3.new(-5.5, 1.6, 0),
	bottomRight = Vector3.new(5.5, 1.6, 0),
	center = Vector3.new(0, 3.4, 0),
}

local GRASS = Color3.fromRGB(58, 138, 62)
local GRASS_LIGHT = Color3.fromRGB(68, 154, 72)
local WHITE = Color3.fromRGB(245, 245, 245)
local CONCRETE = Color3.fromRGB(168, 168, 174)
local SEAT_A = Color3.fromRGB(32, 72, 150)
local SEAT_B = Color3.fromRGB(150, 32, 62)
local KEEPER_KIT = Color3.fromRGB(240, 200, 50)
local TARGET_IDLE = Color3.fromRGB(255, 255, 255)
local BAD_BANNER = Color3.fromRGB(232, 142, 138) -- the soft red of the banner for a save or a miss
local CHIP_IDLE = Color3.fromRGB(110, 115, 132)
local FANS = {
	Color3.fromRGB(230, 90, 90),
	Color3.fromRGB(90, 140, 230),
	Color3.fromRGB(240, 200, 70),
	Color3.fromRGB(120, 200, 130),
	Color3.fromRGB(230, 230, 235),
	Color3.fromRGB(190, 110, 220),
}

local PenaltyUi = {}

local function isZone(name: string): boolean
	return (TARGETS :: { [string]: Vector3? })[name] ~= nil
end

-- Set by DailyUi: called with (goals, boostSeconds) after the last kick.
PenaltyUi.onFinished = function(_goals: number, _boostSeconds: number) end

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

-- A running animation that can be stopped.
type Animation = { Cancel: () -> () }

local function animate(seconds: number, step: (alpha: number) -> ()): Animation
	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - startedAt) / seconds, 1)
		step(1 - (1 - alpha) * (1 - alpha)) -- quad out
		if alpha >= 1 and connection then
			connection:Disconnect()
			connection = nil
		end
	end)
	return {
		Cancel = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end,
	}
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

-- The 3D scene: turf with stripes, the goal with its net, a crowd behind it, the keeper and the ball.
type Scene = {
	view: ViewportFrame,
	keeper: Model,
	ball: Part,
	setKeeper: (position: Vector3, tilt: number, arms: number) -> (),
	project: (world: Vector3) -> UDim2,
}

local function buildScene(parent: Frame): Scene
	local view = new("ViewportFrame", {
		Name = "Goal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(150, 196, 236),
		Ambient = Color3.fromRGB(200, 200, 212),
		LightColor = Color3.fromRGB(255, 244, 225),
		LightDirection = Vector3.new(-0.3, -1, -0.5),
		ZIndex = 7,
	}, parent)
	rounded(view, 12)
	local camera = new("Camera", {
		FieldOfView = FIELD_OF_VIEW,
		CFrame = CFrame.lookAt(CAMERA_POSITION, Vector3.new(0, CAMERA_POSITION.Y, 0)),
	}, view)
	view.CurrentCamera = camera

	-- The turf, with mown stripes and the lines.
	block(view, Vector3.new(90, 1, 60), Vector3.new(0, -0.5, 6), GRASS)
	for index = 0, 5 do
		block(view, Vector3.new(90, 0.05, 4), Vector3.new(0, 0.02, 14 - index * 8), GRASS_LIGHT)
	end
	block(view, Vector3.new(60, 0.08, 0.4), Vector3.new(0, 0.05, 0), WHITE) -- the goal line
	block(view, Vector3.new(28, 0.08, 0.4), Vector3.new(0, 0.05, 6), WHITE) -- the six-yard box
	block(view, Vector3.new(0.4, 0.08, 6), Vector3.new(-14, 0.05, 3), WHITE)
	block(view, Vector3.new(0.4, 0.08, 6), Vector3.new(14, 0.05, 3), WHITE)

	-- The goal: two posts and a bar, and a net behind the keeper.
	local post = 0.5
	block(
		view,
		Vector3.new(post, GOAL_HEIGHT, post),
		Vector3.new(-GOAL_HALF_WIDTH, GOAL_HEIGHT / 2, 0),
		WHITE
	)
	block(
		view,
		Vector3.new(post, GOAL_HEIGHT, post),
		Vector3.new(GOAL_HALF_WIDTH, GOAL_HEIGHT / 2, 0),
		WHITE
	)
	block(
		view,
		Vector3.new(GOAL_HALF_WIDTH * 2 + post, post, post),
		Vector3.new(0, GOAL_HEIGHT, 0),
		WHITE
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
			WHITE,
			0.45
		)
	end
	for y = 1, GOAL_HEIGHT - 1 do
		block(
			view,
			Vector3.new(GOAL_HALF_WIDTH * 2, 0.06, 0.06),
			Vector3.new(0, y, -2.95),
			WHITE,
			0.45
		)
	end

	-- A crowd in the stands behind the goal.
	for row = 0, 3 do
		local top = 1.5 * (row + 1)
		local z = -7 - row * 3
		block(view, Vector3.new(80, top, 3), Vector3.new(0, top / 2, z), CONCRETE)
		block(
			view,
			Vector3.new(80, 0.25, 2.2),
			Vector3.new(0, top + 0.12, z + 0.3),
			if row % 2 == 0 then SEAT_A else SEAT_B
		)
		local k = 0
		for x = -37, 37, 3.2 do
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

	-- The keeper is a mannequin of a player in a goalkeeper's shirt, turned to face the kicker.
	local def = Config.Players[1]
	local keeper = Mannequin.build(def, KEEPER_KIT, false)
	keeper.Parent = view
	local function setKeeper(position: Vector3, tilt: number, arms: number)
		local base = CFrame.new(position)
			* CFrame.Angles(0, 0, math.rad(tilt))
			* CFrame.Angles(0, math.pi, 0)
		keeper:PivotTo(base)
		TrophyScene.poseArm(keeper, base, 1, arms)
		TrophyScene.poseArm(keeper, base, -1, arms)
	end
	setKeeper(KEEPER_REST, 0, 35)

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

	-- Where a point of the goal plane shows in the picture (a straight-on camera, so plain maths).
	local function project(world: Vector3): UDim2
		local depth = CAMERA_POSITION.Z - world.Z
		local halfHeight = depth * math.tan(math.rad(FIELD_OF_VIEW / 2))
		local nx = world.X / (halfHeight * SCENE_RATIO)
		local ny = (world.Y - CAMERA_POSITION.Y) / halfHeight
		return UDim2.fromScale(0.5 + nx / 2, 0.5 - ny / 2)
	end

	return { view = view, keeper = keeper, ball = ball, setKeeper = setKeeper, project = project }
end

function PenaltyUi.init()
	local gui = new("ScreenGui", {
		Name = "Penalty",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local closeScreen: () -> () = function() end
	local built = Panel.build(gui, "Penalty kicks", PANEL_HEIGHT, function()
		closeScreen()
	end)
	local backdrop, card = built.backdrop, built.card
	local cardLayout = card:FindFirstChildOfClass("UIListLayout")
	if cardLayout then
		cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center -- the picture is narrower than the card
	end

	-- The picture: the 3D goal with the five targets on top -----------------------------------
	local sceneBox = new("Frame", {
		Name = "Scene",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(300, 136),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 7,
	}, card)
	local scene = buildScene(sceneBox)

	local buttons: { [string]: TextButton } = {}
	for zone, world in TARGETS do
		local button = new("TextButton", {
			Name = zone,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = scene.project(world),
			Size = UDim2.fromOffset(TARGET_SIZE, TARGET_SIZE),
			BackgroundColor3 = TARGET_IDLE,
			BackgroundTransparency = 0.55,
			Text = "",
			AutoButtonColor = true,
			ZIndex = 9,
		}, sceneBox)
		rounded(button, TARGET_SIZE // 2)
		new(
			"UIStroke",
			{ Color = TARGET_IDLE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			button
		)
		buttons[zone] = button
	end

	-- The line under the picture: "Pick a target", then what happened.
	local result = new("TextLabel", {
		Name = "Result",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, RESULT_HEIGHT),
		BackgroundTransparency = 1,
		Text = "Pick a target",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Panel.TEXT,
		ZIndex = 7,
	}, card)

	-- The reward ladder: one chip per goal, lighting up as the goals come in, like the dock tiles.
	local chipRow = new("Frame", {
		Name = "Chips",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, CHIPS_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, chipRow)
	local chips: { Frame } = {}
	local chipScales: { UIScale } = {}
	local boostIcon = Icons.id("boost")
	local chipCount = Config.Daily.penaltyKicks
	for goalsNeeded = 1, chipCount do
		local seconds = Config.Daily.penaltyBoostSeconds[goalsNeeded] or 0
		local chip = new("Frame", {
			Name = "Chip" .. goalsNeeded,
			LayoutOrder = goalsNeeded,
			Size = UDim2.new(1 / chipCount, -8, 1, 0),
			BackgroundColor3 = Style.ui.panel,
			ZIndex = 8,
		}, chipRow)
		rounded(chip, 12)
		new("UIStroke", {
			Name = "Outline",
			Color = CHIP_IDLE,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, chip)
		local textLeft = if boostIcon ~= "" then 36 else 4
		if boostIcon ~= "" then
			new("ImageLabel", {
				Position = UDim2.fromOffset(4, 10),
				Size = UDim2.fromOffset(32, 32),
				BackgroundTransparency = 1,
				Image = boostIcon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 9,
			}, chip)
		end
		new("TextLabel", {
			Name = "Goals",
			Position = UDim2.fromOffset(textLeft, 6),
			Size = UDim2.new(1, -textLeft - 4, 0, 20),
			BackgroundTransparency = 1,
			Text = if goalsNeeded == 1 then "1 goal" else goalsNeeded .. " goals",
			Font = Style.font,
			TextSize = 16,
			TextColor3 = Style.ui.text,
			ZIndex = 9,
		}, chip)
		new("TextLabel", {
			Name = "Reward",
			Position = UDim2.fromOffset(textLeft, 28),
			Size = UDim2.new(1, -textLeft - 4, 0, 20),
			BackgroundTransparency = 1,
			Text = string.format(
				"x%g · %d min",
				Config.Daily.penaltyMultiplier,
				math.ceil(seconds / 60)
			),
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Style.ui.idle,
			ZIndex = 9,
		}, chip)
		table.insert(chips, chip)
		table.insert(chipScales, new("UIScale", {}, chip))
	end

	-- Lights the chips up to `goals`; the newest one pops.
	local function showLadder(goals: number, pop: boolean)
		for index, chip in chips do
			local reached = index <= goals
			local outline = chip:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Color = if reached then Style.ui.gold else CHIP_IDLE
			end
			local reward = chip:FindFirstChild("Reward")
			if reward and reward:IsA("TextLabel") then
				reward.TextColor3 = if reached then Style.ui.gold else Style.ui.idle
			end
			chipScales[index].Scale = 1
			if pop and index == goals and not GuiService.ReducedMotionEnabled then
				chipScales[index].Scale = 0.8
				TweenService:Create(
					chipScales[index],
					TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end
		end
	end

	-- The big result banner over the goal: "GOAL!" with the reward, or "SAVED!" / "WIDE!".
	local banner = new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.74, 0.46),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 12,
	}, sceneBox)
	rounded(banner, 14)
	local bannerOutline = new(
		"UIStroke",
		{ Color = Style.ui.gold, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		banner
	)
	local bannerScale = new("UIScale", {}, banner)
	local function bannerLabel(
		name: string,
		position: UDim2,
		size: UDim2,
		maxSize: number
	): TextLabel
		local label = new("TextLabel", {
			Name = name,
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			Text = "",
			Font = Style.font,
			TextScaled = true,
			TextColor3 = Style.ui.text,
			ZIndex = 13,
		}, banner)
		new("UITextSizeConstraint", { MaxTextSize = maxSize }, label)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, label)
		return label
	end
	local bannerTitle =
		bannerLabel("Title", UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.56), 52)
	local bannerSub =
		bannerLabel("Sub", UDim2.fromScale(0.04, 0.64), UDim2.fromScale(0.92, 0.28), 20)

	local function showBanner(title: string, sub: string, color: Color3)
		bannerTitle.Text = title
		bannerTitle.TextColor3 = color
		bannerSub.Text = sub
		bannerOutline.Color = color
		banner.Visible = true
		if GuiService.ReducedMotionEnabled then
			bannerScale.Scale = 1
			return
		end
		bannerScale.Scale = 0.5
		TweenService:Create(
			bannerScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	local function hideBanner()
		banner.Visible = false
	end

	-- State ------------------------------------------------------------------------------------
	local kicksLeft = 0
	local totalBoost = 0
	local waiting = false
	local token = 0
	local animations: { Animation } = {}

	-- The picture takes the width of the panel but never more height than the screen allows, so the
	-- targets, the line and the chips all fit without scrolling.
	local function fitScene()
		-- The screen area the panel sits in (below the Roblox top bar), not the whole viewport.
		local area = gui.AbsoluteSize
		if area.Y < 1 then
			local camera = Workspace.CurrentCamera
			area = if camera then camera.ViewportSize else Vector2.new(640, 360)
		end
		local width = math.min(Panel.MAX_WIDTH, area.X * 0.92) - 40
		local spare = area.Y * PANEL_HEIGHT - CARD_CHROME - RESULT_HEIGHT - CHIPS_HEIGHT
		local height = math.clamp(spare, MIN_SCENE_HEIGHT, width / SCENE_RATIO)
		sceneBox.Size = UDim2.fromOffset(height * SCENE_RATIO, height)
	end

	local function stopAnimations()
		for _, animation in animations do
			animation.Cancel()
		end
		table.clear(animations)
	end

	local function setButtons(enabled: boolean)
		for _, button in buttons do
			button.Active = enabled
			button.AutoButtonColor = enabled
			button.BackgroundTransparency = if enabled then 0.55 else 0.8
		end
	end

	local function resetScene()
		stopAnimations()
		hideBanner()
		scene.ball.Position = BALL_START
		scene.ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
		scene.ball.Transparency = 0
		scene.setKeeper(KEEPER_REST, 0, 35)
		for _, button in buttons do
			button.BackgroundColor3 = TARGET_IDLE
		end
	end

	local function showKicksLeft()
		built.setTitle(string.format("Penalty kicks · %d left", kicksLeft))
	end

	local function setResult(text: string, color: Color3)
		result.Text = text
		result.TextColor3 = color
	end

	closeScreen = function()
		token += 1
		stopAnimations()
		backdrop.Visible = false
		waiting = false
	end

	-- Where the ball ends up: inside the goal for a goal or a save, outside it when it goes wide.
	local function ballEnd(aim: string, wide: boolean): Vector3
		local target = TARGETS[aim]
		if not wide then
			return target
		end
		if aim == "center" then
			return Vector3.new(target.X + 3, GOAL_HEIGHT + 3, 0)
		end
		local side = if target.X < 0 then -1 else 1
		local up = if target.Y > 4 then 1 else 0
		return Vector3.new(target.X + side * 5, target.Y + up * 3 + 1, 0)
	end

	local function dive(zone: string)
		local target = TARGETS[zone]
		local tilt = if zone == "center" then 0 elseif target.X < 0 then 70 else -70
		if zone == "topLeft" or zone == "topRight" then
			tilt = tilt * 0.8
		end
		local from = KEEPER_REST
		local to = Vector3.new(target.X * 0.85, math.max(target.Y - 0.3, 1.4), 0)
		table.insert(
			animations,
			animate(DIVE_SECONDS, function(alpha)
				scene.setKeeper(from:Lerp(to, alpha), tilt * alpha, 35 + 120 * alpha)
			end)
		)
	end

	local function openPanel(kicks: number)
		token += 1
		kicksLeft = kicks
		totalBoost = 0
		waiting = false
		resetScene()
		setButtons(true)
		showLadder(0, false)
		showKicksLeft()
		setResult("Pick a target", Panel.TEXT)
		fitScene()
		backdrop.Visible = true
	end

	local function sendKick(zone: string)
		if waiting or not backdrop.Visible or kicksLeft <= 0 then
			return
		end
		waiting = true
		setButtons(false)
		local myToken = token
		Net.fire("PenaltyKick", zone)
		task.delay(REPLY_TIMEOUT, function()
			if waiting and token == myToken then
				waiting = false
				setButtons(true)
			end
		end)
	end
	for zone, button in buttons do
		button.Activated:Connect(function()
			sendKick(zone)
		end)
	end

	-- The server's answer: fly the ball, dive the keeper, say what happened ---------------------
	local function onResult(info: any)
		if type(info) ~= "table" or type(info.aim) ~= "string" or not isZone(info.aim) then
			return
		end
		if not backdrop.Visible then
			return
		end
		token += 1
		local myToken = token
		waiting = false
		kicksLeft = if type(info.kicksLeft) == "number" then info.kicksLeft else 0
		totalBoost += if type(info.boostSeconds) == "number" then info.boostSeconds else 0
		showKicksLeft()
		resetScene()
		setButtons(false)
		buttons[info.aim].BackgroundColor3 = Style.ui.gold
		setResult("", Panel.TEXT)
		Sounds.play("kick")

		local scored = info.goal == true
		local wide = info.wide == true
		local keeperZone = if type(info.keeper) == "string" and isZone(info.keeper)
			then info.keeper
			else "center"
		local endPoint = ballEnd(info.aim, wide)
		local reduced = GuiService.ReducedMotionEnabled

		local function landed()
			if token ~= myToken then
				return
			end
			if scored then
				local goalsNow = if type(info.goals) == "number" then info.goals else 0
				local seconds = Config.Daily.penaltyBoostSeconds[goalsNow] or 0
				local reward = string.format(
					"x%g · %d min",
					Config.Daily.penaltyMultiplier,
					math.ceil(seconds / 60)
				)
				showBanner(
					"GOAL!",
					string.format(
						"%d / %d goals · %s",
						goalsNow,
						Config.Daily.penaltyKicks,
						reward
					),
					Style.ui.gold
				)
				showLadder(goalsNow, true)
				Sounds.play("goal")
			else
				if wide then
					showBanner("WIDE!", "So close", BAD_BANNER)
					Sounds.play("miss")
				else
					showBanner("SAVED!", "Great save by the keeper", BAD_BANNER)
					Sounds.play("save")
				end
			end
			if kicksLeft > 0 then
				task.delay(RESULT_SECONDS, function()
					if token == myToken then
						resetScene()
						setButtons(true)
						setResult("Pick a target", Panel.TEXT)
					end
				end)
				return
			end
			-- The last kick: close the screen and show the reward.
			local goals = if type(info.goals) == "number" then info.goals else 0
			task.delay(RESULT_SECONDS + CLOSE_AFTER_LAST_SECONDS, function()
				if token == myToken then
					closeScreen()
					PenaltyUi.onFinished(goals, totalBoost)
				end
			end)
		end

		if reduced then
			scene.ball.Position = endPoint
			local target = TARGETS[keeperZone]
			scene.setKeeper(Vector3.new(target.X * 0.85, math.max(target.Y - 0.3, 1.4), 0), 0, 150)
			landed()
			return
		end
		local from = BALL_START
		table.insert(
			animations,
			animate(BALL_SECONDS, function(alpha)
				local arc = math.sin(math.pi * alpha) * 1.2
				scene.ball.Position = from:Lerp(endPoint, alpha) + Vector3.new(0, arc, 0)
			end)
		)
		task.delay(0.12, function()
			if token == myToken then
				dive(keeperZone)
			end
		end)
		task.delay(BALL_SECONDS, landed)
	end

	PenaltyUi.open = openPanel
	PenaltyUi.onResult = onResult
end

PenaltyUi.open = function(_kicks: number) end
PenaltyUi.onResult = function(_info: any) end

-- The reward card after the last kick: the shared card that says what the player got.
PenaltyUi.showReward = function(goals: number, boostSeconds: number)
	RewardCard.show({
		title = "PENALTIES DONE",
		big = string.format("%d / 3 goals", goals),
		detail = if boostSeconds > 0
			then string.format("x1.5 income for %d min", math.ceil(boostSeconds / 60))
			else "No boost this time. New kicks in 20 hours.",
		icon = "kick",
		good = boostSeconds > 0,
	})
end

return PenaltyUi
