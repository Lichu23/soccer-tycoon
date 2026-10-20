--!strict
-- The dribble run screen (docs/PLAN.md, Step 4), in the look of the keepie-uppies and the penalty
-- screens (the shared Panel, no title, the numbers as plain text over the picture): three lanes, rows
-- of cones coming down towards your player and two buttons (or A / D, or the arrow keys) to move a
-- lane left or right. A row passed clean grows the combo and pays a little TP; a cone makes the player
-- stumble and breaks the combo. A cone is a little under half a lane wide, so there is always more
-- than a cone of space between two cones, and a cone that has passed keeps rolling off the bottom of
-- the picture instead of vanishing. Rounds last 30 seconds and end in a Bronze, Silver or Gold medal,
-- with your best round kept. Before the first round a short text says how to play. The rows are drawn
-- from the server's state (the same Dribble functions the server judges with); your own move shows at
-- once and the server confirms it. The server pays and keeps the record.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Dribble = require(ReplicatedStorage.Shared.Dribble)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_HEIGHT = 0.94 -- the share of the screen height the panel takes, like the penalty screen
local PANEL_TOP = 10 -- the panel has no title, so the content starts near its top edge
local CARD_CHROME = 4 + 20 + 16 -- the card padding and the two gaps
local MIN_TRACK_HEIGHT = 120
local CHIPS_HEIGHT = 44
local CHIPS_WIDTH = 240
local BUTTON_HEIGHT = 64
local HINT_HEIGHT = 18
local CONE_SHARE = 0.4 -- a cone is this share of a lane wide (turned 45 degrees it is about 0.57)
local CONE_HEIGHT_SHARE = 0.13 -- and never more than this share of the track height, so two rows leave a cone of space
local PLAYER_SHARE = 0.42
local FEEDBACK_HOLD_SECONDS = 0.55
local FEEDBACK_FADE_SECONDS = 0.3
local GO_SECONDS = 0.7 -- how long "GO!" shows after the round starts
local POOL = 8 -- how many rows can be on screen at once

local MEDAL_NAMES = { [0] = "No medal", [1] = "BRONZE", [2] = "SILVER", [3] = "GOLD" }
local MEDAL_COLORS = {
	[0] = Color3.fromRGB(150, 155, 170),
	[1] = Color3.fromRGB(205, 140, 80),
	[2] = Color3.fromRGB(205, 210, 225),
	[3] = Color3.fromRGB(255, 205, 60),
}
local BAD = Color3.fromRGB(232, 142, 138)
local CONE_COLOR = Color3.fromRGB(255, 140, 40)
local WHITE = Color3.fromRGB(255, 255, 255)

local HOW_TO_PLAY = {
	"Press < and > (or A and D) to change lane.",
	"Steer around the cones.",
	"More rows in a row = more TP.",
}

local DribbleUi = {}

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

function DribbleUi.init()
	local gui = new("ScreenGui", {
		Name = "Dribble",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local built = Panel.build(gui, "Dribble run", PANEL_HEIGHT, function() end)
	local backdrop, card = built.backdrop, built.card
	-- The mat is left by walking off it, so the X has no job here, and there is no title.
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

	-- The track: three lanes, the cones and the player --------------------------------------------
	local track = new("Frame", {
		Name = "Track",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(300, 200),
		BackgroundColor3 = Color3.fromRGB(64, 154, 82),
		ClipsDescendants = true,
		ZIndex = 7,
	}, card)
	rounded(track, 12)
	for lane = 1, 3 do
		new("Frame", {
			Position = UDim2.fromScale((lane - 1) / 3, 0),
			Size = UDim2.fromScale(1 / 3, 1),
			BackgroundColor3 = if lane % 2 == 0
				then Color3.fromRGB(68, 164, 88)
				else Color3.fromRGB(58, 144, 76),
			BorderSizePixel = 0,
			ZIndex = 7,
		}, track)
	end
	for lane = 1, 2 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(lane / 3, 0),
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = Color3.fromRGB(240, 240, 240),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, track)
	end

	-- A pool of cones: row r of the pool shows the cones of one row of the run.
	local cones: { { Frame } } = {}
	for _ = 1, POOL do
		local row: { Frame } = {}
		for _ = 1, 3 do
			local cone = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(40, 40),
				Rotation = 45,
				BackgroundColor3 = CONE_COLOR,
				Visible = false,
				ZIndex = 8,
			}, track)
			rounded(cone, 8)
			new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 3 }, cone)
			table.insert(row, cone)
		end
		table.insert(cones, row)
	end

	local runner = new("Frame", {
		Name = "Runner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Style.ui.good,
		ZIndex = 9,
	}, track)
	rounded(runner, 1000)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 4 }, runner)
	local ball = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1.05),
		Size = UDim2.fromScale(0.36, 0.36),
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		ZIndex = 10,
	}, runner)
	rounded(ball, 1000)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, ball)
	local runnerScale = new("UIScale", {}, runner)

	-- The combo and the medal bar ---------------------------------------------------------------------
	local comboText = outlined({
		Name = "Combo",
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.fromOffset(110, 40),
		Text = "",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, track)
	local comboScale = new("UIScale", {}, comboText)
	local medalBar = new("Frame", {
		Name = "Medals",
		Position = UDim2.fromOffset(12, 22),
		Size = UDim2.new(0.3, 0, 0, 10),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.25,
		ZIndex = 12,
	}, track)
	rounded(medalBar, 5)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, medalBar)
	local medalFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = MEDAL_COLORS[1],
		BorderSizePixel = 0,
		ZIndex = 13,
	}, medalBar)
	rounded(medalFill, 5)
	local medals = Config.Training.dribbleMedals
	for medal, passes in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(passes / medals.gold, -0.5),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 14,
		}, medalBar)
	end

	-- A pop-up over the track after each row ---------------------------------------------------
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.8, 0, 0, 34),
		Text = "",
		TextSize = 28,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 12,
	}, track)
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

	-- How to play, before the first round -------------------------------------------------------------
	local intro = new("Frame", {
		Name = "HowToPlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.18,
		ZIndex = 16,
	}, track)
	local introTitle = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "HOW TO PLAY",
		TextColor3 = Style.ui.gold,
		ZIndex = 17,
	}, intro)
	fitted(introTitle, 34)
	for index, line in HOW_TO_PLAY do
		local label = outlined({
			Position = UDim2.fromScale(0.04, 0.27 + (index - 1) * 0.2),
			Size = UDim2.fromScale(0.92, 0.17),
			Text = line,
			ZIndex = 17,
		}, intro)
		fitted(label, 26)
	end
	local introCount = outlined({
		Position = UDim2.fromScale(0.04, 0.87),
		Size = UDim2.fromScale(0.92, 0.11),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 17,
	}, intro)
	fitted(introCount, 16)

	-- The big countdown ("3", "2", "1", "GO!") over the track.
	local bigText = outlined({
		Name = "Big",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.6, 0.4),
		Text = "",
		TextColor3 = Style.ui.gold,
		Visible = false,
		ZIndex = 16,
	}, track)
	fitted(bigText, 80)

	-- The result of a round, over the track -----------------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 18,
	}, track)
	rounded(resultCard, 14)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.4),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 19,
	}, resultCard)
	fitted(medalText, 46)
	local resultLine = outlined({
		Position = UDim2.fromScale(0.04, 0.48),
		Size = UDim2.fromScale(0.92, 0.22),
		Text = "",
		ZIndex = 19,
	}, resultCard)
	fitted(resultLine, 22)
	local bestLine = outlined({
		Position = UDim2.fromScale(0.04, 0.73),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 19,
	}, resultCard)
	fitted(bestLine, 18)

	-- The numbers: time left, rows passed in this round and the best round, as plain text ---------
	local chipRow = new("Frame", {
		Name = "Chips",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(CHIPS_WIDTH, CHIPS_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 12,
	}, track)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, chipRow)
	local function chip(order: number, name: string): TextLabel
		local box = new("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 12,
		}, chipRow)
		outlined({
			Size = UDim2.new(1, 0, 0, 16),
			Text = string.upper(name),
			TextSize = 14,
			ZIndex = 12,
		}, box)
		return outlined({
			Name = "Value",
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 1, -16),
			Text = "-",
			TextSize = 26,
			ZIndex = 12,
		}, box)
	end
	local timeValue = chip(1, "Time")
	local rowsValue = chip(2, "Rows")
	local bestValue = chip(3, "Best")

	-- The two lane buttons under the track ---------------------------------------------------------
	local buttonRow = new("Frame", {
		Name = "Buttons",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, buttonRow)
	local buttons: { TextButton } = {}
	local function arrow(order: number, text: string)
		local button = new("TextButton", {
			Name = "Lane" .. order,
			LayoutOrder = order,
			Size = UDim2.new(0.5, -6, 1, 0),
			BackgroundColor3 = Style.ui.good,
			Text = text,
			Font = Style.font,
			TextSize = 34,
			TextColor3 = WHITE,
			AutoButtonColor = false,
			ZIndex = 8,
		}, buttonRow)
		rounded(button, 16)
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
		table.insert(buttons, button)
		return button
	end
	local leftButton = arrow(1, "<")
	local rightButton = arrow(2, ">")

	new("TextLabel", {
		Name = "Hint",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, HINT_HEIGHT),
		BackgroundTransparency = 1,
		Text = "Walk off the mat to stop.",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Panel.MUTED,
		ZIndex = 7,
	}, card)

	-- The track takes what the screen allows, so nothing needs scrolling on a normal window.
	local trackW, trackH = 300, 200
	local coneSize, playerSize, playerY = 40, 60, 150
	local function fit()
		local size = panel.AbsoluteSize
		if size.Y < 1 then
			return
		end
		trackW = size.X - 40
		trackH = math.max(
			size.Y - PANEL_TOP - CARD_CHROME - BUTTON_HEIGHT - HINT_HEIGHT - 4,
			MIN_TRACK_HEIGHT
		)
		track.Size = UDim2.fromOffset(trackW, trackH)
		local lane = trackW / 3
		coneSize = math.min(lane * CONE_SHARE, trackH * CONE_HEIGHT_SHARE)
		playerSize = math.min(lane * PLAYER_SHARE, trackH * 0.22)
		playerY = trackH - playerSize * 1.2
		for _, row in cones do
			for _, cone in row do
				cone.Size = UDim2.fromOffset(coneSize, coneSize)
			end
		end
		runner.Size = UDim2.fromOffset(playerSize, playerSize)
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
	local run: Dribble.State = Dribble.new(0)
	local localLane = 2 -- where the player shows: his own move at once, the server's lane after it
	local function number(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local function readServerState()
		local phase = player:GetAttribute("dribbleState")
		if phase == "running" or phase == "stumble" or phase == "finished" then
			run.phase = phase
		end
		run.startedAt = number("dribbleStart")
		run.lastRow = number("dribbleLast")
		run.combo = number("dribbleCombo")
		run.passes = number("dribblePasses")
		run.stumbleUntil = number("dribbleStumbleUntil")
		run.roundEndsAt = number("dribbleRoundEnds")
		local lane = number("dribbleLane")
		if lane >= 1 and lane <= 3 then
			run.laneBase = lane
			localLane = lane
		end
	end
	readServerState()
	for _, name in
		{
			"dribbleState",
			"dribbleStart",
			"dribbleLane",
			"dribbleLast",
			"dribbleCombo",
			"dribblePasses",
			"dribbleStumbleUntil",
			"dribbleRoundEnds",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end

	local function move(direction: number)
		if not backdrop.Visible or run.phase == "finished" then
			return
		end
		localLane = math.clamp(localLane + direction, 1, 3)
		pulse(runnerScale, 0.85)
		Net.fire(
			"TrainingMove",
			if direction < 0 then "left" else "right",
			Workspace:GetServerTimeNow()
		)
	end
	leftButton.Activated:Connect(function()
		move(-1)
	end)
	rightButton.Activated:Connect(function()
		move(1)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			move(-1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			move(1)
		end
	end)

	-- What the server tells us ---------------------------------------------------------------------
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "dribbleResult" then
			local paid = if type(info.paid) == "number" then info.paid else 0
			local combo = if type(info.combo) == "number" then info.combo else 0
			if info.outcome == "pass" then
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
			elseif info.outcome == "stumble" then
				popFeedback("OUCH!", BAD)
			end
		elseif info.kind == "dribbleRound" then
			local medal = if type(info.medal) == "number" then info.medal else 0
			local passes = if type(info.passes) == "number" then info.passes else 0
			local best = if type(info.bestCombo) == "number" then info.bestCombo else 0
			medalText.Text = MEDAL_NAMES[medal] or ""
			medalText.TextColor3 = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultStroke.Color = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultLine.Text = string.format("%d rows  ·  best combo %d", passes, best)
			local record = player:GetAttribute("dribbleBestPasses")
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
	local rowSeconds = Config.Training.dribbleRowSeconds
	local approach = Config.Training.dribbleApproachSeconds
	local lead = Config.Training.dribbleLeadSeconds
	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "dribble"
		backdrop.Visible = active
		if not active then
			resultCard.Visible = false
			return
		end
		local now = Workspace:GetServerTimeNow()
		local finished = run.phase == "finished"
		local stumbling = now < run.stumbleUntil

		-- The rows on the way down. A cone keeps rolling after it passes the player, until it is off
		-- the bottom of the picture, so it never vanishes in view.
		local speed = (playerY + coneSize) / approach -- pixels a second
		local exitSeconds = (trackH + coneSize - playerY) / speed
		local used = 0
		if not finished then
			local firstRow =
				math.max(math.floor((now - exitSeconds - run.startedAt) / rowSeconds), 1)
			for row = firstRow, firstRow + POOL + 2 do
				local arrives = Dribble.rowTime(run, row)
				local away = arrives - now
				if
					arrives <= run.roundEndsAt
					and away >= -exitSeconds
					and away <= approach
					and used < POOL
				then
					used += 1
					local blocked = Dribble.blocked(run.startedAt, row)
					local y = playerY - away * speed
					for lane = 1, 3 do
						local cone = cones[used][lane]
						cone.Visible = blocked[lane]
						cone.Position = UDim2.new((lane - 0.5) / 3, 0, 0, y)
					end
				end
			end
		end
		for index = used + 1, POOL do
			for lane = 1, 3 do
				cones[index][lane].Visible = false
			end
		end

		-- The player, in the lane he is shown in; he turns red while he is down.
		local targetX = (localLane - 0.5) / 3
		local currentX = runner.Position.X.Scale
		runner.Position = UDim2.new(currentX + (targetX - currentX) * 0.4, 0, 0, playerY)
		runner.BackgroundColor3 = if stumbling then Color3.fromRGB(190, 70, 70) else Style.ui.good

		-- The numbers and the texts over the track.
		resultCard.Visible = finished and resultCard.Visible
		local untilStart = run.startedAt - now
		local leadIn = run.phase == "running" and untilStart > 0
		local showIntro = leadIn and untilStart > lead + 0.05
		intro.Visible = showIntro
		chipRow.Visible = not showIntro
		medalBar.Visible = not showIntro
		introCount.Text = string.format("Starts in %d", math.ceil(untilStart))
		local showGo = run.phase ~= "finished" and not leadIn and -untilStart < GO_SECONDS
		bigText.Visible = (leadIn and not showIntro) or showGo
		bigText.Text = if leadIn then tostring(math.ceil(untilStart)) else "GO!"

		local timeLeft = if leadIn
			then Config.Training.dribbleRoundSeconds
			else math.max(run.roundEndsAt - now, 0)
		timeValue.Text = if finished then "0" else string.format("%d s", math.ceil(timeLeft))
		timeValue.TextColor3 = if not finished and not leadIn and timeLeft <= 5 then BAD else WHITE
		rowsValue.Text = tostring(run.passes)
		local record = player:GetAttribute("dribbleBestPasses")
		bestValue.Text = tostring(math.max(if type(record) == "number" then record else 0, 0))
		bestValue.TextColor3 = if run.passes > 0
				and type(record) == "number"
				and run.passes >= record
			then Style.ui.gold
			else WHITE
		comboText.Text = if run.combo >= 2 then "x" .. run.combo else ""
		comboText.TextColor3 = if run.combo >= Config.Training.juggleComboMax
			then Style.ui.gold
			else WHITE
		medalFill.Size = UDim2.fromScale(math.clamp(run.passes / medals.gold, 0, 1), 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Dribble.medal(run.passes), 1)]
		for _, button in buttons do
			button.BackgroundColor3 = if finished or leadIn
				then Color3.fromRGB(95, 100, 115)
				else Style.ui.good
		end
	end)
end

return DribbleUi
