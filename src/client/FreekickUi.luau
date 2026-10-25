--!strict
-- The 1v1 breakaway screen (docs/PLAN.md, Step 4): while the player stands on the free-kick spot the
-- whole screen becomes a small stadium (client/BreakawayScene) where the player's own avatar takes a
-- through-ball against a defender and a keeper. Each attack has three quick inputs, and only the one
-- in play shows:
--   1. the move: an arrow (cut left, step-over, cut right) and a bar that runs out; press the
--      matching key (the arrows, A/S/D or the D-pad) or tap its button at the bottom to beat the
--      defender;
--   2. the aim: a reticle glides over the goal mouth; tap (click, Space or the A button) to lock it;
--   3. the power: an indicator slides up and down the meter by itself; tap when it is on the green
--      to shoot.
-- The aim and the power share a shot clock, a bar under the step name that runs out (shorter with
-- every goal); when it is empty the keeper smothers the ball ("TOO SLOW!").
-- A beaten defender plays the dribble film before the aim; after the shot the strike plays in slow
-- motion, then the goal or the save. A
-- goal adds to the streak and pays TP; a lost dribble or a shot that does not go in ends it. The
-- medals are streak milestones and the longest streak is kept. Until the first goal ever a short hint
-- guides each step (the tutorial), and the first attack is practice: the move has no bar and waits for
-- its key, and the hint names the key to press. The server judges every input and pays; this only shows it. The
-- red X (or walking off the spot) leaves.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BreakawayScene = require(script.Parent.BreakawayScene)
local CinemaScreen = require(script.Parent.CinemaScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Freekick = require(ReplicatedStorage.Shared.Freekick)
local Net = require(script.Parent.Net)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local FEEDBACK_HOLD_SECONDS = 1.1
local FEEDBACK_FADE_SECONDS = 0.3
local MOVE_BUTTON = 58
local MOVE_GAP = 10
local PROMPT_TOP = 108 -- the move prompt starts under the step name
local PROMPT_HEIGHT = 170
local CLOCK_TOP = 108 -- the shot clock sits under the step name, where the move prompt was
local CLOCK_BAR = 170
local CLOCK_URGENT = 0.3 -- the share of the clock left when it turns red
local COACH_BOTTOM = MOVE_BUTTON + 22 + 14 + 8 -- the hint sits just over the move buttons
local COACH_HEIGHT = 30
local LETTERBOX = 0.08 -- the share of the screen height of each film bar
local SPEED_LINES = 12
local LEAVE_STEP = 5 -- the X walks the character this far past the edge of the spot
local POWER_LINGER = 0.8 -- the meter stays this long into the film, its indicator where it stopped
local MEDAL_NAMES = { [0] = "No medal", [1] = "BRONZE", [2] = "SILVER", [3] = "GOLD" }
local MEDAL_COLORS = {
	[0] = Color3.fromRGB(150, 155, 170),
	[1] = Color3.fromRGB(205, 140, 80),
	[2] = Color3.fromRGB(205, 210, 225),
	[3] = Color3.fromRGB(255, 205, 60),
}
local BAD = Color3.fromRGB(232, 142, 138)
local WHITE = Color3.fromRGB(255, 255, 255)
local RED_X = Color3.fromRGB(232, 64, 96)

-- The three skill moves: the arrow, the name and the keys that make them.
type MoveInfo = { glyph: string, name: string, keyHint: string, keys: { Enum.KeyCode } }
local MOVES: { MoveInfo } = {
	{
		glyph = "◀",
		name = "CUT LEFT",
		keyHint = "A",
		keys = { Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.DPadLeft },
	},
	{
		glyph = "▼",
		name = "STEP-OVER",
		keyHint = "S",
		keys = { Enum.KeyCode.Down, Enum.KeyCode.S, Enum.KeyCode.DPadDown },
	},
	{
		glyph = "▶",
		name = "CUT RIGHT",
		keyHint = "D",
		keys = { Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight },
	},
}
local TAP_KEYS = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonR2] = true,
}

local STEP_NAMES: { [string]: string } = {
	dribble = "BEAT THE DEFENDER",
	aim = "AIM",
	power = "POWER",
}

-- The tutorial's hint for each step.
local COACH_TEXT: { [string]: string } = {
	waiting = "Your first attack! Get ready...",
	dribble = "Press the move shown before its bar runs out!",
	practice = "Press %s or tap %s to %s. Take your time!",
	practiceTouch = "Tap %s to %s. Take your time!",
	aim = "Tap to lock your aim on the goal.",
	power = "Tap when the marker is on the green to shoot!",
}

local OUTCOME_TEXT: { [string]: string } = {
	goal = "GOAL!",
	saved = "SAVED!",
	wide = "WIDE",
	post = "OFF THE POST",
	over = "OVER THE BAR",
	bar = "OFF THE BAR",
	tackled = "TACKLED!",
	late = "TOO SLOW!",
}
local OUTCOME_SOUND: { [string]: string } = {
	goal = "goal",
	saved = "save",
	late = "save",
	post = "post",
	bar = "post",
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

function FreekickUi.init()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Two layers: the film's bars, speed lines and the reticle cover the whole screen; the controls and
	-- the numbers stay inside the safe area.
	local world = new("ScreenGui", {
		Name = "FreekickWorld",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 4,
		Enabled = false,
	}, playerGui)
	local gui = new("ScreenGui", {
		Name = "Freekick",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
		Enabled = false,
	}, playerGui)

	-- The film bars, top and bottom.
	local bars: { Frame } = {}
	for index, anchor in { 0, 1 } do
		bars[index] = new("Frame", {
			AnchorPoint = Vector2.new(0, anchor),
			Position = UDim2.fromScale(0, anchor),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Style.ui.dark,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, world)
	end

	-- The speed lines of the sprint.
	local lines: { Frame } = {}
	for index = 1, SPEED_LINES do
		lines[index] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0.12 + (index % 4) * 0.05, 0, 0, 2 + index % 2),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		}, world)
	end

	-- The aim reticle, on the goal mouth.
	local aimMark = CinemaScreen.reticle(world)
	local reticle, reticleStroke, reticleScale = aimMark.frame, aimMark.stroke, aimMark.scale

	-- The safe area: everything the player reads or presses ------------------------------------------
	local tapArea = new("TextButton", {
		Name = "TapArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, gui)

	-- The streak, the TP it earned and the best, top centre, over the medal bar.
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(300, 62),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, gui)
	local function chip(x: number, name: string): TextLabel
		outlined({
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.new(1 / 3, 0, 0, 16),
			Text = name,
			TextSize = 14,
			ZIndex = 5,
		}, top)
		return outlined({
			Position = UDim2.new(x, 0, 0, 16),
			Size = UDim2.new(1 / 3, 0, 0, 28),
			Text = "0",
			TextSize = 28,
			ZIndex = 5,
		}, top)
	end
	local streakValue = chip(0, "STREAK")
	local earnedValue = chip(1 / 3, "TP EARNED")
	earnedValue.TextColor3 = Style.ui.good
	local bestValue = chip(2 / 3, "BEST")
	local medalBar = new("Frame", {
		Name = "Medals",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(0.6, 0, 0, 10),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.25,
		ZIndex = 5,
	}, top)
	rounded(medalBar, 5)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, medalBar)
	local medalFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = MEDAL_COLORS[1],
		BorderSizePixel = 0,
		ZIndex = 6,
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
			ZIndex = 7,
		}, medalBar)
	end

	-- The red X, top left: leaves the spot.
	local leave = new("TextButton", {
		Name = "Leave",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = RED_X,
		Text = "X",
		Font = Style.font,
		TextSize = 24,
		TextColor3 = WHITE,
		AutoButtonColor = true,
		ZIndex = 8,
	}, gui)
	rounded(leave, 10)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, leave)

	local stepText = outlined({
		Name = "Step",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 5,
	}, gui)
	fitted(stepText, 26)

	-- The shot clock of the aim and the power: a bar that runs out and the seconds left.
	local clock = new("Frame", {
		Name = "ShotClock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CLOCK_TOP),
		Size = UDim2.fromOffset(CLOCK_BAR + 54, 24),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	local clockBar = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(CLOCK_BAR, 12),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		ZIndex = 5,
	}, clock)
	rounded(clockBar, 6)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, clockBar)
	local clockFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.gold,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, clockBar)
	rounded(clockFill, 6)
	local clockText = outlined({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(46, 24),
		Text = "",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	}, clock)
	local clockScale = new("UIScale", {}, clockText)

	-- The move: a big arrow tile, a bar that runs out and the move's name.
	local prompt = new("Frame", {
		Name = "Move",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PROMPT_TOP),
		Size = UDim2.fromOffset(180, PROMPT_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	local promptFit = new("UIScale", {}, prompt)
	local promptTile = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = Style.ui.panel,
		ZIndex = 5,
	}, prompt)
	rounded(promptTile, 18)
	local promptStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 4 }, promptTile)
	local promptScale = new("UIScale", {}, promptTile)
	local promptGlyph = outlined({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 64,
		TextColor3 = Style.ui.gold,
		ZIndex = 6,
	}, promptTile)
	local timer = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(150, 12),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		ZIndex = 5,
	}, prompt)
	rounded(timer, 6)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, timer)
	local timerFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.gold,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, timer)
	rounded(timerFill, 6)
	local promptName = outlined({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 138),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		TextSize = 22,
		ZIndex = 5,
	}, prompt)

	-- The three move buttons at the bottom (they work on every device; the keys work too).
	local buttonRow = new("Frame", {
		Name = "Moves",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(MOVE_BUTTON * 3 + MOVE_GAP * 2, MOVE_BUTTON + 22),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	local moveButtons: { TextButton } = {}
	local moveStrokes: { UIStroke } = {}
	for index, info in MOVES do
		local button = new("TextButton", {
			Name = info.name,
			Position = UDim2.fromOffset((index - 1) * (MOVE_BUTTON + MOVE_GAP), 0),
			Size = UDim2.fromOffset(MOVE_BUTTON, MOVE_BUTTON),
			BackgroundColor3 = Style.ui.panel,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 6,
		}, buttonRow)
		rounded(button, 12)
		moveStrokes[index] = new("UIStroke", {
			Color = Style.ui.bar,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		outlined({
			Size = UDim2.fromScale(1, 0.7),
			Text = info.glyph,
			TextSize = 28,
			ZIndex = 7,
		}, button)
		local keyLabel = outlined({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 0.96),
			Size = UDim2.fromScale(1, 0.3),
			Text = info.keyHint,
			TextSize = 12,
			TextColor3 = Style.ui.idle,
			ZIndex = 7,
		}, button)
		keyLabel.Visible = UserInputService.KeyboardEnabled
		outlined({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.new(1, 16, 0, 16),
			Text = info.name,
			TextSize = 12,
			ZIndex = 6,
		}, button)
		moveButtons[index] = button
	end

	-- The power meter, on the right.
	local meter = CinemaScreen.powerMeter(gui, Freekick.goodZone(1))
	local powerBox, powerStroke = meter.box, meter.stroke

	-- The words of a result, in the middle.
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.8, 0.14),
		Text = "",
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	fitted(feedback, 64)
	local feedbackStroke = feedback:FindFirstChildOfClass("UIStroke") :: UIStroke
	feedbackStroke.Transparency = 1
	local feedbackScale = new("UIScale", {}, feedback)
	local tpText = outlined({
		Name = "Tp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	fitted(tpText, 28)
	local tpStroke = tpText:FindFirstChildOfClass("UIStroke") :: UIStroke
	tpStroke.Transparency = 1

	-- The tutorial's hint, at the bottom.
	local coachText = outlined({
		Name = "Coach",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -COACH_BOTTOM),
		Size = UDim2.new(0.86, 0, 0, COACH_HEIGHT),
		Text = "",
		Visible = false,
		ZIndex = 9,
	}, gui)
	fitted(coachText, 24)

	-- The move prompt shrinks to fit between the step name and the hint on a small screen (a phone).
	local function fit()
		local free = gui.AbsoluteSize.Y - PROMPT_TOP - COACH_BOTTOM - COACH_HEIGHT - 8
		promptFit.Scale = math.clamp(free / PROMPT_HEIGHT, 0.45, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	-- The result of a streak.
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 220),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 12,
	}, gui)
	rounded(resultCard, 14)
	new("UISizeConstraint", { MaxSize = Vector2.new(340, 220) }, resultCard)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.92, 0.34),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 13,
	}, resultCard)
	fitted(medalText, 46)
	local resultLine = outlined({
		Position = UDim2.fromScale(0.04, 0.4),
		Size = UDim2.fromScale(0.92, 0.18),
		Text = "",
		ZIndex = 13,
	}, resultCard)
	fitted(resultLine, 22)
	local earnedLine = outlined({
		Position = UDim2.fromScale(0.04, 0.6),
		Size = UDim2.fromScale(0.92, 0.18),
		Text = "",
		TextColor3 = Style.ui.good,
		ZIndex = 13,
	}, resultCard)
	fitted(earnedLine, 22)
	local bestLine = outlined({
		Position = UDim2.fromScale(0.04, 0.8),
		Size = UDim2.fromScale(0.92, 0.16),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 13,
	}, resultCard)
	fitted(bestLine, 18)

	local function pulse(scale: UIScale, from: number)
		if GuiService.ReducedMotionEnabled then
			scale.Scale = 1
			return
		end
		scale.Scale = from
		TweenService:Create(
			scale,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	local feedbackToken = 0
	local function popFeedback(text: string, color: Color3, tp: string)
		feedbackToken += 1
		local myToken = feedbackToken
		feedback.Text = text
		feedback.TextColor3 = color
		tpText.Text = tp
		feedback.TextTransparency = 0
		tpText.TextTransparency = 0
		feedbackStroke.Transparency = 0
		tpStroke.Transparency = 0
		pulse(feedbackScale, 0.6)
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

	-- The server's state, mirrored from the attributes ---------------------------------------------
	local state: Freekick.State = Freekick.new(0)
	-- What the player just did, shown at once until the server's answer arrives.
	local pressedMove: number? = nil
	local lockedX: number? = nil
	local lockedY: number? = nil
	local localStartAt = 0 -- when the meter moves, from our own lock, until the server's arrives
	local releasedPower: number? = nil
	local frozenClock: number? = nil -- the seconds left when the player shot, held until the film
	local function number(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local function readServerState()
		local phase = player:GetAttribute("freekickState")
		if
			phase == "dribble"
			or phase == "aim"
			or phase == "power"
			or phase == "shot"
			or phase == "over"
		then
			state.phase = phase
		end
		state.seed = number("freekickSeed")
		state.kick = math.max(number("freekickKick"), 1)
		state.stageAt = number("freekickStageAt")
		state.move = math.clamp(number("freekickMove"), 1, 3)
		state.aimX = number("freekickAimX")
		state.aimY = number("freekickAimY")
		state.holdAt = number("freekickHoldAt")
		state.power = number("freekickPower")
		state.shotBy = number("freekickShotBy")
		local outcome = player:GetAttribute("freekickOutcome")
		state.outcome = if type(outcome) == "string" then outcome else ""
		state.streak = number("freekickStreak")
		state.overAt = number("freekickOverAt")
		state.practice = player:GetAttribute("freekickPractice") == true
	end
	readServerState()
	for _, name in
		{
			"freekickSeed",
			"freekickKick",
			"freekickStageAt",
			"freekickMove",
			"freekickAimX",
			"freekickAimY",
			"freekickHoldAt",
			"freekickPower",
			"freekickShotBy",
			"freekickOutcome",
			"freekickStreak",
			"freekickOverAt",
			"freekickPractice",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end
	player:GetAttributeChangedSignal("freekickState"):Connect(function()
		pressedMove = nil
		lockedX, lockedY = nil, nil
		releasedPower = nil
		if player:GetAttribute("freekickState") ~= "power" then
			frozenClock = nil
		end
		readServerState()
	end)

	-- On and off: the stadium, the camera, the controls and the other screens ---------------------------
	local scene: BreakawayScene.Scene? = nil
	local dismissed = false -- the X was pressed; stays off until the player leaves the spot
	local takeover = CinemaScreen.takeover()

	local function open()
		if scene then
			return
		end
		takeover.take()
		scene = BreakawayScene.new()
		world.Enabled = true
		gui.Enabled = true
	end

	local function close()
		if scene == nil then
			return
		end
		scene.destroy()
		scene = nil
		world.Enabled = false
		gui.Enabled = false
		resultCard.Visible = false
		takeover.give()
	end

	-- The X: off the spot, a few steps past its edge (any input of the player takes over).
	leave.Activated:Connect(function()
		dismissed = true
		close()
		CinemaScreen.walkOff("TrainingFreekick", LEAVE_STEP)
	end)

	-- The inputs -------------------------------------------------------------------------------------
	local function pressMove(move: number)
		local now = Workspace:GetServerTimeNow()
		if
			scene == nil
			or state.phase ~= "dribble"
			or pressedMove ~= nil
			or now < state.stageAt
		then
			return
		end
		pressedMove = move
		pulse(promptScale, 0.85)
		if Freekick.untimed(state) and move ~= state.move then
			-- Practice: a wrong key only flashes red, and the move keeps waiting.
			task.delay(0.4, function()
				if pressedMove == move then
					pressedMove = nil
				end
			end)
			return
		end
		Net.fire("FreekickMove", move, now)
	end
	for index, button in moveButtons do
		button.Activated:Connect(function()
			pressMove(index)
		end)
	end

	-- When the power meter moves: the server's time once it is known.
	local function meterStart(): number
		return if state.holdAt > 0 then state.holdAt else localStartAt
	end

	local function press()
		if scene == nil then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if state.shotBy > 0 and now > state.shotBy then
			return -- the clock ran out: the server smothers the ball
		end
		if state.phase == "aim" and lockedX == nil and now >= state.stageAt then
			lockedX, lockedY = Freekick.aimAt(state, now)
			localStartAt = now + Config.Training.freekickPowerDelay
			pulse(reticleScale, 1.4)
			Net.fire("FreekickTap", now)
		elseif state.phase == "power" and releasedPower == nil and now >= meterStart() then
			releasedPower = Freekick.powerAt({ holdAt = meterStart() }, now, state.kick)
			frozenClock = math.max(state.shotBy - now, 0)
			Net.fire("FreekickTap", now)
		end
	end
	tapArea.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			press()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if scene == nil or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if TAP_KEYS[input.KeyCode] then
			press()
			return
		end
		for index, info in MOVES do
			if table.find(info.keys, input.KeyCode) then
				pressMove(index)
				return
			end
		end
	end)

	-- What the server tells us ---------------------------------------------------------------------
	local shotPay = "" -- the "+N TP" of the goal in the film now, shown when the ball goes in
	-- The TP this streak earned (summed from the goals the server paid, only to show it); the TP of
	-- the goal in the film is added when the ball goes in, like the streak.
	local earned = 0
	local shotPaid = 0
	player:GetAttributeChangedSignal("freekickSeed"):Connect(function()
		earned, shotPaid = 0, 0
	end)
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "freekickShot" then
			local paid = if type(info.paid) == "number" then info.paid else 0
			shotPaid = if info.outcome == "goal" then paid else 0
			shotPay = if info.outcome ~= "goal"
				then ""
				elseif info.capped == true then "MAX RATE"
				else string.format("+%.2f TP", paid)
		elseif info.kind == "freekickOver" then
			local medal = if type(info.medal) == "number" then info.medal else 0
			local streak = if type(info.streak) == "number" then info.streak else 0
			if streak <= 0 or scene == nil then
				return -- the miss already said it; no card for a streak that never started
			end
			medalText.Text = MEDAL_NAMES[medal] or ""
			medalText.TextColor3 = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultStroke.Color = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultLine.Text =
				string.format("Streak: %d goal%s", streak, if streak == 1 then "" else "s")
			earnedLine.Text = string.format("TP earned: +%.2f", earned)
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

	-- The moments of the film: the sounds and the words come when they happen on screen.
	local lastFilm = -1
	local lastStageAt = -1
	local function filmMoments(t: number)
		local function crossed(at: number): boolean
			return lastFilm < at and t >= at
		end
		if state.outcome == "tackled" then
			if crossed(BreakawayScene.TACKLE_AT) then
				popFeedback(OUTCOME_TEXT.tackled, BAD, "")
			end
			return
		end
		if crossed(BreakawayScene.CONTACT_AT) then
			Sounds.play("kick")
		end
		if crossed(BreakawayScene.ARRIVE_AT) then
			local sound = OUTCOME_SOUND[state.outcome]
			if sound then
				Sounds.play(sound)
			end
			if state.outcome == "goal" then
				earned += shotPaid
				shotPaid = 0
				popFeedback(OUTCOME_TEXT.goal, Style.ui.good, shotPay)
			else
				popFeedback(OUTCOME_TEXT[state.outcome] or "MISSED", BAD, "")
			end
		end
	end

	-- Every frame ------------------------------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		local onSpot = player:GetAttribute("trainingStation") == "freekick"
		if not onSpot then
			dismissed = false
		end
		local active = onSpot and player:GetAttribute("training") == true and not dismissed
		if active then
			open()
		else
			close()
			return
		end
		local current = scene :: BreakawayScene.Scene
		-- The default camera scripts can switch the camera back (a respawn, a new subject); keep it ours.
		takeover.keep()
		local now = Workspace:GetServerTimeNow()
		local phase = state.phase
		local reduced = GuiService.ReducedMotionEnabled

		-- The reticle glides until the tap locks it; the scene draws the rest.
		local dribbling = Freekick.dribbling(state, now) -- the film of the beaten defender
		local aiming = (phase == "aim" and not dribbling) or phase == "power"
		local reticleX, reticleY = state.aimX, state.aimY
		if phase == "aim" then
			if lockedX and lockedY then
				reticleX, reticleY = lockedX, lockedY
			else
				reticleX, reticleY = Freekick.aimAt(state, now)
			end
		end
		current.frame({ state = state, now = now, reticleX = reticleX, reticleY = reticleY })

		-- The film: its bars, its speed lines and its moments.
		local filming = phase == "shot" or dribbling
		local filmT = if filming then Freekick.filmTime(state, now) or 0 else -1
		if phase == "shot" then
			if state.stageAt ~= lastStageAt then
				lastStageAt = state.stageAt
				lastFilm = -1
			end
			filmMoments(filmT)
			lastFilm = filmT
		end
		local barShare = if filming or phase == "over" then LETTERBOX else 0
		for _, bar in bars do
			bar.Size = UDim2.fromScale(1, barShare)
		end
		local sprinting = filming and filmT < BreakawayScene.CUT_STRIKE - 0.1 and not reduced
		for index, line in lines do
			line.Visible = sprinting
			if sprinting then
				local speed = 1.6 + (index % 3) * 0.5
				local x = 1.2 - ((os.clock() * speed + index * 0.37) % 1.4)
				line.Position = UDim2.fromScale(x, 0.12 + ((index * 0.618) % 1) * 0.76)
			end
		end

		-- The reticle on the goal.
		reticle.Visible = aiming
		if aiming then
			local camera = Workspace.CurrentCamera
			local point = camera:WorldToViewportPoint(current.goalPoint(reticleX, reticleY))
			reticle.Position = UDim2.fromOffset(point.X, point.Y)
			reticleStroke.Color = if phase == "power" or lockedX
				then Style.ui.good
				else Style.ui.gold
		end

		-- The move.
		local window = Freekick.moveWindow(state.kick)
		local moving = phase == "dribble" and now >= state.stageAt
		prompt.Visible = moving
		buttonRow.Visible = phase == "dribble"
		local info = MOVES[state.move] or MOVES[1]
		promptGlyph.Text = info.glyph
		promptName.Text = info.name
		local untimed = Freekick.untimed(state)
		timer.Visible = not untimed -- the practice move has no time limit
		local left = math.clamp(1 - (now - state.stageAt) / window, 0, 1)
		timerFill.Size = UDim2.fromScale(if pressedMove then 1 else left, 1)
		timerFill.BackgroundColor3 = if left < 0.3 then BAD else Style.ui.gold
		promptStroke.Color = if pressedMove == nil
			then Style.ui.gold
			elseif pressedMove == state.move then Style.ui.good
			else BAD
		for index, stroke in moveStrokes do
			stroke.Color = if pressedMove == index
				then (if index == state.move then Style.ui.good else BAD)
				else Style.ui.bar
		end

		-- The shot clock, while the player aims and shoots (the practice attack has none).
		clock.Visible = aiming and state.shotBy > 0
		if clock.Visible then
			local secondsLeft = frozenClock or math.max(state.shotBy - now, 0)
			local share = math.clamp(secondsLeft / Freekick.shotWindow(state.kick), 0, 1)
			local urgent = share < CLOCK_URGENT
			clockFill.Size = UDim2.fromScale(share, 1)
			clockFill.BackgroundColor3 = if urgent then BAD else Style.ui.gold
			local text = string.format("%.1f", secondsLeft)
			if
				urgent
				and frozenClock == nil
				and text ~= clockText.Text
				and string.sub(text, -1) == "0"
			then
				pulse(clockScale, 1.3) -- a beat on each whole second at the end
			end
			clockText.Text = text
			clockText.TextColor3 = if urgent then BAD else WHITE
		end

		-- The power meter, and for a moment into the film where the shot stopped it.
		local struck = phase == "shot"
			and state.outcome ~= "tackled"
			and now - state.stageAt < POWER_LINGER
		local power = if phase == "power"
			then releasedPower or Freekick.powerAt({ holdAt = meterStart() }, now, state.kick)
			elseif struck then state.power
			else 0
		powerBox.Visible = phase == "power" or struck
		CinemaScreen.setPowerZone(meter, Freekick.goodZone(state.kick))
		CinemaScreen.setPower(meter, power, releasedPower ~= nil or struck)
		powerStroke.Color = if releasedPower then Style.ui.good else Style.ui.gold

		-- The texts.
		local waiting = phase == "dribble" and now < state.stageAt
		stepText.Text = if waiting
			then "GET READY"
			elseif dribbling then ""
			else (STEP_NAMES[phase] or "")
		resultCard.Visible = phase == "over" and resultCard.Visible
		local shown = if filming
				and state.outcome == "goal"
				and filmT < BreakawayScene.ARRIVE_AT
			then state.streak - 1
			else state.streak
		streakValue.Text = tostring(math.max(shown, 0))
		earnedValue.Text = string.format("+%.2f", earned)
		local record = player:GetAttribute("freekickBestStreak")
		bestValue.Text = tostring(if type(record) == "number" then record else 0)
		bestValue.TextColor3 = if shown > 0
				and type(record) == "number"
				and shown >= record
			then Style.ui.gold
			else WHITE
		medalFill.Size = UDim2.fromScale(math.clamp(shown / medals.gold, 0, 1), 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Freekick.medal(shown), 1)]

		-- The tutorial, until the first goal ever.
		local tutorial = state.kick == 1 and (type(record) ~= "number" or record <= 0)
		local coachStep = if waiting then "waiting" else phase
		local hint = if not tutorial or dribbling
			then nil
			elseif coachStep == "dribble" and untimed then (if UserInputService.KeyboardEnabled
				then string.format(
					COACH_TEXT.practice,
					info.keyHint,
					info.glyph,
					string.lower(info.name)
				)
				else string.format(
					COACH_TEXT.practiceTouch,
					info.glyph,
					string.lower(info.name)
				))
			else COACH_TEXT[coachStep]
		coachText.Visible = hint ~= nil
		coachText.Text = hint or ""
	end)
end

return FreekickUi
