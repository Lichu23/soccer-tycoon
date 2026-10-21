--!strict
-- The screen of a conditioning station of the Training Gym (docs/PLAN.md, Step 4): while the player
-- is on the treadmill or the bench press with stamina left, a title says which one it is, a
-- calm bar fills towards the next whole TP and a short "+N TP" shows each time one arrives. The
-- keepie-uppies have their own screen (KeepieUi). Display only: the server pays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local BAR_WIDTH = 300
local BAR_HEIGHT = 26
local FEEDBACK_HOLD_SECONDS = 0.65 -- like the VICTORY text
local FEEDBACK_FADE_SECONDS = 0.35

-- What the screen is called at each conditioning station.
local STATION_TITLES: { [any]: string } = {
	treadmill = "TREADMILL",
	bench = "BENCH PRESS",
}

-- The one line over the bar: how to get off the machine (a jump at both).
local STATION_HINTS: { [any]: string } = {
	treadmill = "Jump to get off the treadmill",
	bench = "Jump to get off the bench",
}

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
		Position = UDim2.new(0.5, 0, 1, -86),
		Size = UDim2.fromOffset(BAR_WIDTH + 80, 24),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 16,
		TextColor3 = Style.ui.text,
	}, gui)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, hint)

	local title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(BAR_WIDTH + 40, 28),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 24,
		TextColor3 = Style.ui.gold,
	}, gui)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, title)

	-- The bar fills towards the next whole TP, so the gain is visible.
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -54),
		Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
	}, gui)
	rounded(bar, 8)
	new("UIStroke", { Color = Style.ui.idle, Thickness = 1 }, bar)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.bar,
		BorderSizePixel = 0,
	}, bar)
	rounded(fill, 8)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "Training...",
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.text,
		ZIndex = 3,
	}, bar)

	-- A "+N TP" near the top after each whole TP, like the VICTORY text.
	local feedback = new("TextLabel", {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(460, 54),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 44,
		TextColor3 = Style.ui.bar,
		TextTransparency = 1,
		Active = false,
	}, gui)
	local feedbackStroke = new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, feedback)
	local feedbackToken = 0
	local function popFeedback(text: string)
		feedbackToken += 1
		local myToken = feedbackToken
		feedback.Text = text
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

	local lastTp = 0
	player:GetAttributeChangedSignal("tp"):Connect(function()
		local tp = player:GetAttribute("tp")
		if type(tp) ~= "number" then
			return
		end
		if
			player:GetAttribute("trainingField") == "conditioning"
			and tp > lastTp
			and lastTp > 0
		then
			popFeedback(string.format("+%d TP", tp - lastTp))
		end
		lastTp = tp
	end)

	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingField") == "conditioning"
		gui.Enabled = active
		if not active then
			return
		end
		local station = player:GetAttribute("trainingStation")
		title.Text = STATION_TITLES[station] or "TRAINING"
		hint.Text = STATION_HINTS[station] or ""
		local fraction = player:GetAttribute("tpFraction")
		fill.Size =
			UDim2.fromScale(math.clamp(if type(fraction) == "number" then fraction else 0, 0, 1), 1)
	end)
end

return TrainingUi
