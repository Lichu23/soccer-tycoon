--!strict
-- The keepie-uppies screen (docs/PLAN.md, Step 4), full screen like the 1v1 breakaway: while the
-- player stands on the mat the whole screen becomes the centre circle of a small stadium
-- (client/KeepieScene) where the player's own avatar keeps a ball up. A ring closes in on the TAP
-- button on the beat; a tap (the button, anywhere on the screen, E, Space or the A button) close to it
-- is a clean touch, the combo grows and each touch pays a little TP, and the foot flicks the ball
-- back up. It is an endless
-- streak: the ball gets a little quicker with every touch, and a tap in the air or a dropped ball ends
-- it. The medals (Bronze, Silver, Gold) are streak milestones and your longest streak is kept. Before
-- the first streak a short text says how to play. The ball is drawn from the server's state (the same
-- Juggle functions the server judges with); the server pays and keeps the record. The red X leaves
-- the mat (the controls are off while the screen shows).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CinemaScreen = require(script.Parent.CinemaScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Juggle = require(ReplicatedStorage.Shared.Juggle)
local KeepieScene = require(script.Parent.KeepieScene)
local Net = require(script.Parent.Net)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local RING_START = 2.1 -- the ring starts this many times the size of the button
local BUTTON_SIZE = 76
local FEEDBACK_HOLD_SECONDS = 0.55
local FEEDBACK_FADE_SECONDS = 0.3
local GO_SECONDS = 0.7 -- how long "GO!" shows after a streak starts
local LEAVE_STEP = 5 -- the X walks the character this far past the edge of the mat

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
local GREY = Color3.fromRGB(95, 100, 115)

local TAP_KEYS = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonR2] = true,
}

local HOW_TO_PLAY = {
	"Tap when the ring closes.",
	"Keep the ball up as long as you can.",
	"It gets faster. Longer streak = more TP.",
}

local KeepieUi = {}

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

function KeepieUi.init()
	local gui = new("ScreenGui", {
		Name = "Keepie",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	-- A tap anywhere on the screen is a touch, like the TAP button.
	local tapArea = new("TextButton", {
		Name = "TapArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, gui)

	-- The streak, the TP it earned and the best, top centre, over the medal bar -------------------------
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
	local medals = Config.Training.juggleMedals
	for medal, hits in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(hits / medals.gold, -0.5),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 7,
		}, medalBar)
	end

	-- The combo, on the left, clear of the ball's flight over the player.
	local comboText = outlined({
		Name = "Combo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.42, 0),
		Size = UDim2.fromOffset(140, 44),
		Text = "",
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, gui)
	local comboScale = new("UIScale", {}, comboText)

	-- The red X, top left: leaves the mat.
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

	-- A pop-up after each tap, under the combo ----------------------------------------------------------
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0.42, 26),
		Size = UDim2.new(0.3, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	fitted(feedback, 34)
	local feedbackStroke = feedback:FindFirstChildOfClass("UIStroke") :: UIStroke
	feedbackStroke.Transparency = 1
	local feedbackToken = 0
	local function popFeedback(text: string, color: Color3)
		feedbackToken += 1
		local myToken = feedbackToken
		feedback.Text = text
		feedback.TextColor3 = color
		feedback.TextTransparency = 0
		feedbackStroke.Transparency = 0
		task.delay(FEEDBACK_HOLD_SECONDS, function()
			if feedbackToken ~= myToken then
				return
			end
			local info = TweenInfo.new(FEEDBACK_FADE_SECONDS)
			TweenService:Create(feedback, info, { TextTransparency = 1 }):Play()
			TweenService:Create(feedbackStroke, info, { Transparency = 1 }):Play()
		end)
	end

	-- How to play, before the first streak -------------------------------------------------------------
	local intro = new("Frame", {
		Name = "HowToPlay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.8, 0.5),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.18,
		Visible = false,
		ZIndex = 12,
	}, gui)
	rounded(intro, 14)
	new("UISizeConstraint", { MaxSize = Vector2.new(460, 240) }, intro)
	new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, intro)
	local introTitle = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "HOW TO PLAY",
		TextColor3 = Style.ui.gold,
		ZIndex = 13,
	}, intro)
	fitted(introTitle, 34)
	for index, line in HOW_TO_PLAY do
		local label = outlined({
			Position = UDim2.fromScale(0.04, 0.27 + (index - 1) * 0.2),
			Size = UDim2.fromScale(0.92, 0.17),
			Text = line,
			ZIndex = 13,
		}, intro)
		fitted(label, 26)
	end
	local introCount = outlined({
		Position = UDim2.fromScale(0.04, 0.87),
		Size = UDim2.fromScale(0.92, 0.11),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 13,
	}, intro)
	fitted(introCount, 16)

	-- The big countdown ("3", "2", "1", "GO!").
	local bigText = outlined({
		Name = "Big",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.3),
		Text = "",
		TextColor3 = Style.ui.gold,
		Visible = false,
		ZIndex = 11,
	}, gui)
	fitted(bigText, 96)

	-- The result of a streak ------------------------------------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(340, 220),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 14,
	}, gui)
	rounded(resultCard, 14)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.92, 0.34),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 15,
	}, resultCard)
	fitted(medalText, 46)
	local resultLine = outlined({
		Position = UDim2.fromScale(0.04, 0.4),
		Size = UDim2.fromScale(0.92, 0.18),
		Text = "",
		ZIndex = 15,
	}, resultCard)
	fitted(resultLine, 22)
	local earnedLine = outlined({
		Position = UDim2.fromScale(0.04, 0.6),
		Size = UDim2.fromScale(0.92, 0.18),
		Text = "",
		TextColor3 = Style.ui.good,
		ZIndex = 15,
	}, resultCard)
	fitted(earnedLine, 22)
	local bestLine = outlined({
		Position = UDim2.fromScale(0.04, 0.8),
		Size = UDim2.fromScale(0.92, 0.16),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 15,
	}, resultCard)
	fitted(bestLine, 18)

	-- The TAP button with the closing ring, bottom centre under the player's feet -----------------------
	local holderSize = BUTTON_SIZE * (RING_START + 0.1)
	local buttonHolder = new("Frame", {
		Name = "ButtonHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(holderSize, holderSize),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, gui)
	local holderFit = new("UIScale", {}, buttonHolder)
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, buttonHolder)
	rounded(ring, 1000)
	local ringStroke =
		new("UIStroke", { Color = Style.ui.gold, Thickness = 5, Transparency = 1 }, ring)
	-- A label, not a button: the tap area under it takes the tap, so one tap is never sent twice.
	local button = new("TextLabel", {
		Name = "Tap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = Style.ui.good,
		Text = "TAP",
		Font = Style.font,
		TextSize = 30,
		TextColor3 = WHITE,
		ZIndex = 6,
	}, buttonHolder)
	rounded(button, 1000)
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, button)
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, button)
	local buttonScale = new("UIScale", {}, button)

	-- On a short screen (a phone held sideways) the button and its ring shrink so the ball stays clear.
	local function fit()
		holderFit.Scale = math.clamp(gui.AbsoluteSize.Y * 0.26 / holderSize, 0.55, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

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

	-- The server's state, mirrored from the attributes and moved on by the same Juggle functions ---
	local round: Juggle.State = Juggle.new(0)
	local function readServerState()
		local phase = player:GetAttribute("juggleState")
		if phase == "running" or phase == "over" then
			round.phase = phase
		end
		local function number(name: string): number
			local value = player:GetAttribute(name)
			return if type(value) == "number" then value else 0
		end
		round.startedAt = number("juggleStart")
		round.combo = number("juggleCombo")
		round.lastIndex = number("juggleLast")
		round.overAt = number("juggleOverAt")
	end
	readServerState()
	-- The TP the current streak has earned: the sum of what the server paid for its touches (display
	-- only), cleared when a new streak starts.
	local earned = 0
	player:GetAttributeChangedSignal("juggleStart"):Connect(function()
		earned = 0
	end)
	for _, name in
		{
			"juggleState",
			"juggleStart",
			"juggleCombo",
			"juggleLast",
			"juggleOverAt",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end

	-- On and off: the gym, the camera, the controls and the other screens ---------------------------------
	local scene: KeepieScene.Scene? = nil
	local dismissed = false -- the X was pressed; stays off until the player leaves the mat
	local takeover = CinemaScreen.takeover()

	local function open()
		if scene then
			return
		end
		takeover.take()
		scene = KeepieScene.new()
		gui.Enabled = true
	end

	local function close()
		if scene == nil then
			return
		end
		scene.destroy()
		scene = nil
		gui.Enabled = false
		resultCard.Visible = false
		takeover.give()
	end

	leave.Activated:Connect(function()
		dismissed = true
		close()
		CinemaScreen.walkOff("TrainingKeepie", LEAVE_STEP)
	end)

	-- A tap. The legs follow the server's beats in the scene, so a touch shows once it is judged.
	local function press()
		if scene == nil then
			return
		end
		pulse(buttonScale, 0.88)
		Net.fire("TrainingTap")
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
		end
	end)

	-- What the server tells us -----------------------------------------------------------------------
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" or scene == nil then
			return
		end
		if info.kind == "juggleResult" then
			local paid = if type(info.paid) == "number" then info.paid else 0
			local combo = if type(info.combo) == "number" then info.combo else 0
			if info.outcome == "hit" then
				earned += paid
				Sounds.play("kick")
				pulse(comboScale, 1.35)
				if info.capped == true then
					popFeedback("MAX RATE", Style.ui.gold)
				else
					popFeedback(
						string.format("+%.2f TP", paid)
							.. (if combo >= 3 then "  x" .. combo else ""),
						Style.ui.good
					)
				end
			elseif info.outcome == "miss" then
				popFeedback("TOO EARLY", BAD)
			end
		elseif info.kind == "juggleOver" then
			local medal = if type(info.medal) == "number" then info.medal else 0
			local streak = if type(info.streak) == "number" then info.streak else 0
			if streak <= 0 then
				popFeedback("DROPPED", BAD) -- no card for a streak that never started
				return
			end
			medalText.Text = MEDAL_NAMES[medal] or ""
			medalText.TextColor3 = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultStroke.Color = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultLine.Text = string.format("Streak: %d touches", streak)
			earnedLine.Text = string.format("TP earned: +%.2f", earned)
			local record = player:GetAttribute("keepieBestStreak")
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

	-- Every frame ------------------------------------------------------------------------------------
	local window = Config.Training.juggleWindow
	local lead = Config.Training.juggleLeadSeconds
	RunService.RenderStepped:Connect(function()
		local onMat = player:GetAttribute("trainingStation") == "keepie"
		if not onMat then
			dismissed = false
		end
		local active = onMat and player:GetAttribute("training") == true and not dismissed
		if active then
			open()
		else
			close()
			return
		end
		-- The default camera scripts can switch the camera back (a respawn, a new subject); keep it ours.
		takeover.keep()
		local now = Workspace:GetServerTimeNow()
		Juggle.normalize(round, now)

		local current = scene :: KeepieScene.Scene
		current.frame({ round = round, now = now })

		-- The ring closes in on the button on the next beat.
		local running = round.phase == "running"
		local ringAlpha = 0
		if running then
			local index = Juggle.beatAt(round, now - window)
			local untilBeat = Juggle.beatTime(round, index) - now
			ringAlpha = math.clamp(1 - untilBeat / Juggle.period(index), 0, 1)
		end
		local size = BUTTON_SIZE * (RING_START + (1 - RING_START) * ringAlpha)
		ring.Size = UDim2.fromOffset(size, size)
		ringStroke.Transparency = if running then 0.45 - 0.45 * ringAlpha else 1

		-- The numbers and the texts.
		local finished = round.phase == "over"
		resultCard.Visible = finished and resultCard.Visible
		local untilStart = round.startedAt - now
		local leadIn = running and untilStart > 0
		local showIntro = leadIn and untilStart > lead + 0.05
		intro.Visible = showIntro
		introCount.Text = string.format("Starts in %d", math.ceil(untilStart))
		local showGo = running and not leadIn and -untilStart < GO_SECONDS
		bigText.Visible = (leadIn and not showIntro) or showGo
		bigText.Text = if leadIn then tostring(math.ceil(untilStart)) else "GO!"

		streakValue.Text = tostring(round.combo)
		earnedValue.Text = string.format("+%.2f", earned)
		local record = player:GetAttribute("keepieBestStreak")
		bestValue.Text = tostring(math.max(if type(record) == "number" then record else 0, 0))
		bestValue.TextColor3 = if round.combo > 0
				and type(record) == "number"
				and round.combo >= record
			then Style.ui.gold
			else WHITE
		comboText.Text = if round.combo >= 2 then "x" .. round.combo else ""
		comboText.TextColor3 = if round.combo >= Config.Training.juggleComboMax
			then Style.ui.gold
			else WHITE
		local progress = math.clamp(round.combo / medals.gold, 0, 1)
		medalFill.Size = UDim2.fromScale(progress, 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Juggle.medal(round.combo), 1)]
		-- The button greys before the first ball and while the result shows.
		local waiting = round.phase ~= "running" or leadIn
		button.BackgroundColor3 = if waiting then GREY else Style.ui.good
	end)
end

return KeepieUi
