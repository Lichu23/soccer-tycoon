--!strict
-- The training drill on screen (docs/PLAN.md, Step 4): while the player stands on the training pad
-- with stamina left, a bar appears with a marker that sweeps across it once per round and a HIT
-- button (or the E key). The marker is drawn from the server's drill start time, the same clock the
-- server judges the press on. Only one press per round counts; the button dims after a press until
-- the next round. The drill is optional: standing still already earns the base TP.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Drill = require(ReplicatedStorage.Shared.Drill)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local BAR_WIDTH = 300
local BAR_HEIGHT = 26
local MARKER_WIDTH = 6
local FLASH_SECONDS = 0.5
local FEEDBACK_HOLD_SECONDS = 0.65 -- like the VICTORY text
local FEEDBACK_FADE_SECONDS = 0.35

local TrainingUi = {}

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

function TrainingUi.init()
	local gui = new("ScreenGui", {
		Name = "Training",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local hint = new("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(BAR_WIDTH + 40, 24),
		BackgroundTransparency = 1,
		Text = "Standing here earns 10 TP/min. Hit the green for extra!",
		Font = Style.font,
		TextSize = 16,
		TextColor3 = Style.ui.text,
	}, gui)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, hint)

	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
	}, gui)
	rounded(bar, 8)
	new("UIStroke", { Color = Style.ui.idle, Thickness = 1 }, bar)

	local window = Config.Training.drillWindow
	local zone = new("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(window * 2, 1),
		BackgroundColor3 = Style.ui.good,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, bar)

	local marker = new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, MARKER_WIDTH, 1, 8),
		BackgroundColor3 = Style.ui.text,
		BorderSizePixel = 0,
	}, bar)
	rounded(marker, 3)

	local button = new("TextButton", {
		Name = "Hit",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.fromOffset(140, 56),
		BackgroundColor3 = Style.ui.good,
		Text = "HIT",
		Font = Style.font,
		TextSize = 26,
		TextColor3 = Style.ui.dark,
		AutoButtonColor = false,
	}, gui)
	rounded(button, 14)

	-- A pop-up above the bar after each press: PERFECT or MISS.
	local feedback = new("TextLabel", {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(460, 54),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 44,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		Active = false,
	}, gui)
	local feedbackStroke = new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, feedback)

	-- What the player can do right now ---------------------------------------------------------
	local pressedRound = -1
	local flashUntil = 0
	local flashColor = Style.ui.good
	local wasActive = false
	local streak = 0
	local bonusPerHit = (Config.Training.drillTpPerMinuteMax - Config.Training.idleTpPerMinute)
		* Config.Training.drillRoundSeconds
		/ 60

	-- A temporary text near the top, like VICTORY: fully visible for a moment, then it fades.
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

	local function press()
		if not gui.Enabled then
			return
		end
		local startedAt = player:GetAttribute("drillStart")
		if type(startedAt) ~= "number" then
			return
		end
		local round = Drill.position(startedAt, Workspace:GetServerTimeNow())
		if round <= pressedRound then
			return -- one press per round
		end
		pressedRound = round
		Net.fire("TrainingDrillHit")
	end
	button.Activated:Connect(press)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E then
			press()
		end
	end)

	Net.on("Notice", function(info: any)
		if type(info) == "table" and info.kind == "drillResult" then
			flashColor = if info.hit then Style.ui.good else Style.ui.bad
			flashUntil = os.clock() + FLASH_SECONDS
			if info.hit then
				streak += 1
				popFeedback(
					string.format("+%.1f TP", bonusPerHit)
						.. (if streak >= 2 then " x" .. streak else ""),
					Style.ui.good
				)
			else
				streak = 0
				popFeedback("MISS", Style.ui.bad)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local startedAt = player:GetAttribute("drillStart")
		local active = player:GetAttribute("training") == true
			and type(startedAt) == "number"
			and startedAt > 0
		gui.Enabled = active
		if not active then
			pressedRound = -1
			wasActive = false
			return
		end
		if not wasActive then
			wasActive = true
			streak = 0
		end
		local round, position = Drill.position(startedAt :: number, Workspace:GetServerTimeNow())
		marker.Position = UDim2.fromScale(position, 0.5)
		local used = round <= pressedRound
		button.BackgroundTransparency = if used then 0.6 else 0
		if flashUntil > os.clock() then
			zone.BackgroundColor3 = flashColor
			zone.BackgroundTransparency = 0
		else
			zone.BackgroundColor3 = Style.ui.good
			zone.BackgroundTransparency = 0.35
		end
	end)
end

return TrainingUi
