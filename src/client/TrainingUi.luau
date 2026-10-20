--!strict
-- The training drill on screen (docs/PLAN.md, Step 4): while the player stands on the training pad
-- with stamina left, a bar shows a marker that sweeps across it and a HIT button (or the E key). A
-- hit in the green starts the marker again at once; a miss turns the bar red for a short cooldown;
-- a marker that reaches the end, or an idle player, leaves the bar red until the next press starts
-- it. The state comes from the server's attributes and runs on the same Drill functions the server
-- judges with. The drill is optional: standing still already earns the base TP.

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

-- What the screen is called at each station of the Training Gym.
local STATION_TITLES: { [any]: string } = {
	treadmill = "TREADMILL",
	ladder = "AGILITY LADDER",
	keepie = "KEEPIE-UPPIES",
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
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(BAR_WIDTH + 40, 24),
		BackgroundTransparency = 1,
		Text = "Standing here earns 10 TP/min. Hit the green for extra!",
		Font = Style.font,
		TextSize = 16,
		TextColor3 = Style.ui.text,
	}, gui)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, hint)

	-- The title says which field this is.
	local title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -176),
		Size = UDim2.fromOffset(BAR_WIDTH + 40, 28),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 24,
		TextColor3 = Style.ui.gold,
	}, gui)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, title)

	-- The conditioning bar: it fills towards the next whole TP, so the passive gain is visible.
	local afkBar = new("Frame", {
		Name = "AfkBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		Visible = false,
	}, gui)
	rounded(afkBar, 8)
	new("UIStroke", { Color = Style.ui.idle, Thickness = 1 }, afkBar)
	local afkFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.bar,
		BorderSizePixel = 0,
	}, afkBar)
	rounded(afkFill, 8)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "Training...",
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.text,
		ZIndex = 3,
	}, afkBar)

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

	-- The text inside the bar while the marker is not running.
	local barText = new("TextLabel", {
		Name = "BarText",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.text,
		ZIndex = 3,
	}, bar)
	local barStroke = bar:FindFirstChildOfClass("UIStroke")

	-- State: the server's, mirrored from the attributes and moved on by the same Drill functions ----
	local drill = Drill.new()
	local flashUntil = 0
	local wasActive = false
	local streak = 0
	local RED = Color3.fromRGB(120, 35, 40)

	local function readServerState()
		local phase = player:GetAttribute("drillPhase")
		if phase == "running" or phase == "cooldown" or phase == "stopped" then
			drill.phase = phase
		else
			drill.phase = "stopped"
		end
		local startedAt = player:GetAttribute("drillStart")
		local cooldownUntil = player:GetAttribute("drillCooldownUntil")
		drill.startedAt = if type(startedAt) == "number" then startedAt else 0
		drill.cooldownUntil = if type(cooldownUntil) == "number" then cooldownUntil else 0
	end
	readServerState()
	for _, name in { "drillPhase", "drillStart", "drillCooldownUntil" } do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end

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
		local now = Workspace:GetServerTimeNow()
		-- Only the server moves the drill (a hit starts a new run with a new green zone).
		Drill.normalize(drill, now)
		if drill.phase == "cooldown" then
			return
		end
		Net.fire("TrainingDrillHit")
	end
	button.Activated:Connect(press)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E then
			press()
		end
	end)

	-- At a conditioning station each whole TP that arrives shows as a temporary "+N TP".
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
			popFeedback(string.format("+%d TP", tp - lastTp), Style.ui.bar)
		end
		lastTp = tp
	end)

	Net.on("Notice", function(info: any)
		if type(info) ~= "table" or info.kind ~= "drillResult" then
			return
		end
		local paid = if type(info.paid) == "number" then info.paid else 0
		if info.capped == true then
			popFeedback("MAX RATE", Style.ui.gold)
		elseif info.outcome == "hit" then
			streak += 1
			flashUntil = os.clock() + FLASH_SECONDS
			popFeedback(
				string.format("+%.1f TP", paid) .. (if streak >= 2 then " x" .. streak else ""),
				Style.ui.good
			)
		elseif info.outcome == "miss" then
			streak = 0
			popFeedback(string.format("+%g TP", paid), Style.ui.bad)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local field = player:GetAttribute("trainingField")
		local active = player:GetAttribute("training") == true
			and (field == "conditioning" or field == "skill")
		gui.Enabled = active
		if not active then
			wasActive = false
			return
		end
		if not wasActive then
			wasActive = true
			streak = 0
		end
		local isActive = field == "skill"
		title.Text = STATION_TITLES[player:GetAttribute("trainingStation")] or "TRAINING"
		hint.Text = if isActive
			then "Hit the green: every press gives +1 TP, a hit gives extra!"
			else "Just keep going: 10 TP per minute. Want more? Try the keepie-uppies!"
		afkBar.Visible = not isActive
		bar.Visible = isActive
		button.Visible = isActive
		if not isActive then
			local fraction = player:GetAttribute("tpFraction")
			afkFill.Size = UDim2.fromScale(
				math.clamp(if type(fraction) == "number" then fraction else 0, 0, 1),
				1
			)
			return
		end
		local now = Workspace:GetServerTimeNow()
		Drill.normalize(drill, now)
		local position = Drill.position(drill, now)
		marker.Visible = position ~= nil
		if position then
			marker.Position = UDim2.fromScale(position, 0.5)
		end
		local running = drill.phase == "running"
		bar.BackgroundColor3 = if running then Style.ui.dark else RED
		bar.BackgroundTransparency = if running then 0.2 else 0.05
		if barStroke then
			barStroke.Color = if running then Style.ui.idle else Style.ui.bad
		end
		barText.Text = if drill.phase == "running" then "" else "Wait..."
		-- The button always says HIT; it goes grey while the bar waits to start again.
		local waiting = drill.phase ~= "running"
		button.Text = "HIT"
		button.BackgroundColor3 = if waiting then Color3.fromRGB(95, 100, 115) else Style.ui.good
		button.TextColor3 = if waiting then Color3.fromRGB(170, 175, 190) else Style.ui.dark
		zone.Visible = running
		-- The green zone stays where it is until a new run starts, then it jumps.
		zone.Position = UDim2.fromScale(Drill.zone(drill.startedAt), 0)
		if flashUntil > os.clock() then
			zone.BackgroundColor3 = Style.ui.good
			zone.BackgroundTransparency = 0
		else
			zone.BackgroundColor3 = Style.ui.good
			zone.BackgroundTransparency = 0.35
		end
	end)
end

return TrainingUi
