--!strict
-- The dribble run screen (docs/PLAN.md, Step 4): three lanes, rows of cones coming down towards your
-- player and two buttons (or A / D, or the arrow keys) to move a lane left or right. A row passed
-- clean grows the combo and pays a little TP; a cone makes the player stumble and breaks the combo.
-- Rounds last 30 seconds and end in a Bronze, Silver or Gold medal, with your best round kept. The
-- rows are drawn from the server's state (the same Dribble functions the server judges with); your
-- own move shows at once and the server confirms it. The server pays and keeps the record.

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
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local TRACK_W, TRACK_H = 210, 170
local LANE_W = TRACK_W / 3
local PLAYER_Y = TRACK_H - 34 -- where the player stands (the middle of his circle)
local CONE_SIZE = 30
local PLAYER_SIZE = 34
local BUTTON_W, BUTTON_H = 96, 56
local FEEDBACK_HOLD_SECONDS = 0.55
local FEEDBACK_FADE_SECONDS = 0.3
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

-- A text with a thick dark outline, like the pad labels.
local function outlined(props: { [string]: any }, parent: Instance): TextLabel
	props.BackgroundTransparency = 1
	props.Font = Style.font
	local label = new("TextLabel", props, parent)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	return label
end

function DribbleUi.init()
	local gui = new("ScreenGui", {
		Name = "Dribble",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local rootHeight = TRACK_H + BUTTON_H + 86
	local root = new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(TRACK_W, rootHeight),
		BackgroundTransparency = 1,
	}, gui)
	local rootScale = new("UIScale", {}, root)
	local function fit()
		local area = gui.AbsoluteSize
		if area.Y > 1 then
			rootScale.Scale = math.clamp((area.Y - 60) / rootHeight, 0.55, 1)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	outlined({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 26),
		Text = "DRIBBLE RUN",
		TextSize = 22,
		TextColor3 = Style.ui.gold,
	}, root)
	local roundText = outlined({
		Name = "Round",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextSize = 15,
		TextColor3 = Style.ui.text,
	}, root)

	-- The track: three lanes, the cones and the player --------------------------------------------
	local track = new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(TRACK_W, TRACK_H),
		BackgroundColor3 = Color3.fromRGB(64, 154, 82),
		ClipsDescendants = true,
	}, root)
	rounded(track, 14)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, track)
	for lane = 1, 3 do
		new("Frame", {
			Position = UDim2.fromOffset((lane - 1) * LANE_W, 0),
			Size = UDim2.fromOffset(LANE_W, TRACK_H),
			BackgroundColor3 = if lane % 2 == 0
				then Color3.fromRGB(68, 164, 88)
				else Color3.fromRGB(58, 144, 76),
			BorderSizePixel = 0,
		}, track)
	end
	for lane = 1, 2 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(lane * LANE_W, 0),
			Size = UDim2.fromOffset(2, TRACK_H),
			BackgroundColor3 = Color3.fromRGB(240, 240, 240),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}, track)
	end

	-- A pool of cones: row r of the pool shows the cones of one row of the run.
	local cones: { { Frame } } = {}
	for _ = 1, POOL do
		local row: { Frame } = {}
		for _ = 1, 3 do
			local cone = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(CONE_SIZE, CONE_SIZE),
				Rotation = 45,
				BackgroundColor3 = CONE_COLOR,
				Visible = false,
				ZIndex = 3,
			}, track)
			rounded(cone, 6)
			new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, cone)
			table.insert(row, cone)
		end
		table.insert(cones, row)
	end

	local runner = new("Frame", {
		Name = "Runner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(TRACK_W / 2, PLAYER_Y),
		Size = UDim2.fromOffset(PLAYER_SIZE, PLAYER_SIZE),
		BackgroundColor3 = Style.ui.good,
		ZIndex = 4,
	}, track)
	rounded(runner, 1000)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, runner)
	local ball = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1.05),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		ZIndex = 5,
	}, runner)
	rounded(ball, 1000)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, ball)
	local runnerScale = new("UIScale", {}, runner)

	local passesText = outlined({
		Name = "Passes",
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(120, 20),
		Text = "",
		TextSize = 15,
		TextColor3 = Style.ui.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	}, track)
	local comboText = outlined({
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 4),
		Size = UDim2.fromOffset(100, 34),
		Text = "",
		TextSize = 30,
		TextColor3 = Style.ui.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	}, track)
	local comboScale = new("UIScale", {}, comboText)
	local medalBar = new("Frame", {
		Position = UDim2.fromOffset(8, 28),
		Size = UDim2.fromOffset(100, 8),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.25,
		ZIndex = 6,
	}, track)
	rounded(medalBar, 4)
	local medalFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = MEDAL_COLORS[1],
		BorderSizePixel = 0,
		ZIndex = 7,
	}, medalBar)
	rounded(medalFill, 4)
	local medals = Config.Training.dribbleMedals
	for medal, passes in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(passes / medals.gold, -0.4),
			Size = UDim2.fromOffset(3, 12),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 8,
		}, medalBar)
	end

	-- The result of a round over the track --------------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.62),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 10,
	}, track)
	rounded(resultCard, 14)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0, 0.04),
		Size = UDim2.fromScale(1, 0.38),
		TextScaled = true,
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 11,
	}, resultCard)
	new("UITextSizeConstraint", { MaxTextSize = 40 }, medalText)
	local resultLine = outlined({
		Position = UDim2.fromScale(0, 0.44),
		Size = UDim2.fromScale(1, 0.24),
		TextScaled = true,
		Text = "",
		TextColor3 = Style.ui.text,
		ZIndex = 11,
	}, resultCard)
	new("UITextSizeConstraint", { MaxTextSize = 18 }, resultLine)
	local bestLine = outlined({
		Position = UDim2.fromScale(0, 0.7),
		Size = UDim2.fromScale(1, 0.22),
		TextScaled = true,
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 11,
	}, resultCard)
	new("UITextSizeConstraint", { MaxTextSize = 16 }, bestLine)

	-- A pop-up over the track after each row ---------------------------------------------------
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(TRACK_W, 34),
		Text = "",
		TextSize = 26,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 9,
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
		if not gui.Enabled or run.phase == "finished" then
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

	local function arrow(text: string, x: number, direction: number)
		local button = new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, x, 0, TRACK_H + 58),
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
			BackgroundColor3 = Style.ui.good,
			Text = text,
			Font = Style.font,
			TextSize = 28,
			TextColor3 = Style.ui.dark,
			AutoButtonColor = false,
		}, root)
		rounded(button, 16)
		new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, button)
		button.Activated:Connect(function()
			move(direction)
		end)
	end
	arrow("<", -BUTTON_W / 2 - 6, -1)
	arrow(">", BUTTON_W / 2 + 6, 1)
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
	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "dribble"
		gui.Enabled = active
		if not active then
			resultCard.Visible = false
			return
		end
		local now = Workspace:GetServerTimeNow()
		local finished = run.phase == "finished"
		local stumbling = now < run.stumbleUntil

		-- The rows on the way down.
		local used = 0
		if not finished then
			local firstRow =
				math.max(math.floor((now - run.startedAt) / rowSeconds), run.lastRow, 1)
			for row = firstRow, firstRow + POOL + 2 do
				local arrives = Dribble.rowTime(run, row)
				local away = arrives - now
				if
					arrives <= run.roundEndsAt
					and away >= -0.1
					and away <= approach
					and used < POOL
				then
					used += 1
					local blocked = Dribble.blocked(run.startedAt, row)
					local y = PLAYER_Y - (away / approach) * (PLAYER_Y + CONE_SIZE)
					for lane = 1, 3 do
						local cone = cones[used][lane]
						cone.Visible = blocked[lane]
						cone.Position = UDim2.fromOffset((lane - 0.5) * LANE_W, y)
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
		local x = (localLane - 0.5) * LANE_W
		local current = runner.Position.X.Offset
		runner.Position = UDim2.fromOffset(current + (x - current) * 0.4, PLAYER_Y)
		runner.BackgroundColor3 = if stumbling then Color3.fromRGB(190, 70, 70) else Style.ui.good

		-- The text.
		resultCard.Visible = finished and resultCard.Visible
		local leadIn = run.phase == "running" and now < run.startedAt
		roundText.Text = if finished
			then "Round over"
			elseif leadIn then string.format(
				"Get ready...  %.0f",
				math.ceil(run.startedAt - now)
			)
			else string.format(
				"%d s left  ·  %s",
				math.ceil(math.max(run.roundEndsAt - now, 0)),
				if stumbling then "get up!" else "stay clear!"
			)
		passesText.Text = string.format("%d rows", run.passes)
		comboText.Text = if run.combo >= 2 then "x" .. run.combo else ""
		comboText.TextColor3 = if run.combo >= Config.Training.juggleComboMax
			then Style.ui.gold
			else Style.ui.text
		medalFill.Size = UDim2.fromScale(math.clamp(run.passes / medals.gold, 0, 1), 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Dribble.medal(run.passes), 1)]
		local waiting = finished
		for _, child in root:GetChildren() do
			if child:IsA("TextButton") then
				child.BackgroundColor3 = if waiting
					then Color3.fromRGB(95, 100, 115)
					else Style.ui.good
			end
		end
	end)
end

return DribbleUi
