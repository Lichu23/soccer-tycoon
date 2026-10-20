--!strict
-- The keepie-uppies screen (docs/PLAN.md, Step 4): your best player keeps a ball up, and you tap when
-- the ball comes back to his foot. A ring closes in on the TAP button on the beat; a tap close to it
-- is a clean touch, the combo grows and each touch pays a little TP. Rounds last 30 seconds and end in
-- a Bronze, Silver or Gold medal, with your best round kept. The ball is drawn from the server's
-- state (the same Juggle functions the server judges with); the server pays and keeps the record.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Juggle = require(ReplicatedStorage.Shared.Juggle)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local SCENE_W, SCENE_H = 220, 160
local BUTTON_SIZE = 72
local RING_START = 2.6 -- the ring starts this many times the size of the button
local BALL_RADIUS = 0.55
local BALL_REST = Vector3.new(0.25, 0.7, -1.2) -- on the foot of the player, in front of him
local BALL_PEAK = 6 -- studs above the foot at the top of the flight
local FEEDBACK_HOLD_SECONDS = 0.55
local FEEDBACK_FADE_SECONDS = 0.3

local MEDAL_NAMES = { [0] = "No medal", [1] = "BRONZE", [2] = "SILVER", [3] = "GOLD" }
local MEDAL_COLORS = {
	[0] = Color3.fromRGB(150, 155, 170),
	[1] = Color3.fromRGB(205, 140, 80),
	[2] = Color3.fromRGB(205, 210, 225),
	[3] = Color3.fromRGB(255, 205, 60),
}
local BAD = Color3.fromRGB(232, 142, 138)

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

function KeepieUi.init()
	local gui = new("ScreenGui", {
		Name = "Keepie",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local rootHeight = SCENE_H + BUTTON_SIZE + 76
	local root = new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(SCENE_W, rootHeight),
		BackgroundTransparency = 1,
	}, gui)
	-- Smaller on a small screen, so the button is never cut off.
	local rootScale = new("UIScale", {}, root)
	local function fit()
		local area = gui.AbsoluteSize
		if area.Y > 1 then
			rootScale.Scale = math.clamp((area.Y - 60) / rootHeight, 0.55, 1)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	-- The title and the round at the top ---------------------------------------------------------
	outlined({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 26),
		Text = "KEEPIE-UPPIES",
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

	-- The scene: your best player and the ball ------------------------------------------------------
	local sceneBox = new("Frame", {
		Name = "Scene",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(SCENE_W, SCENE_H),
		BackgroundColor3 = Color3.fromRGB(150, 196, 236),
		ClipsDescendants = true,
	}, root)
	rounded(sceneBox, 14)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, sceneBox)
	local view = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 212),
		LightColor = Color3.fromRGB(255, 244, 225),
		LightDirection = Vector3.new(-0.3, -1, -0.6),
	}, sceneBox)
	local camera = new("Camera", {
		FieldOfView = 42,
		CFrame = CFrame.lookAt(Vector3.new(0, 4.6, -15), Vector3.new(0, 3.9, 0)),
	}, view)
	view.CurrentCamera = camera
	new("Part", {
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(60, 1, 60),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(64, 154, 82),
		Material = Enum.Material.SmoothPlastic,
	}, view)
	local ball = new("Part", {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(BALL_RADIUS * 2, BALL_RADIUS * 2, BALL_RADIUS * 2),
		Position = BALL_REST,
		Color = Color3.fromRGB(245, 245, 245),
		Material = Enum.Material.SmoothPlastic,
	}, view)
	local shown: Model? = nil
	local shownId = ""
	local function showPlayer()
		local ids = Roster.field(State.data)
		local id = ids[1]
		if id == nil or id == shownId then
			return
		end
		local def = Config.PlayersById[id]
		if def == nil then
			return
		end
		if shown then
			shown:Destroy()
		end
		-- He faces the camera (the front of the shirt is on the -Z side).
		local model = Mannequin.build(def, nil, false, { detailed = true })
		model:PivotTo(CFrame.new(0, Mannequin.FEET_TO_TORSO + 0.15, 0))
		model.Parent = view
		shown = model
		shownId = id
	end

	-- The combo and the medal thresholds --------------------------------------------------------
	local comboText = outlined({
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(110, 40),
		Text = "",
		TextSize = 34,
		TextColor3 = Style.ui.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	}, sceneBox)
	local comboScale = new("UIScale", {}, comboText)
	local hitsText = outlined({
		Name = "Hits",
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(120, 22),
		Text = "",
		TextSize = 16,
		TextColor3 = Style.ui.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, sceneBox)
	local medalBar = new("Frame", {
		Name = "Medals",
		Position = UDim2.fromOffset(8, 30),
		Size = UDim2.fromOffset(110, 8),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.25,
		ZIndex = 4,
	}, sceneBox)
	rounded(medalBar, 4)
	local medalFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = MEDAL_COLORS[1],
		BorderSizePixel = 0,
		ZIndex = 5,
	}, medalBar)
	rounded(medalFill, 4)
	local medals = Config.Training.juggleMedals
	for medal, hits in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(hits / medals.gold, -0.4),
			Size = UDim2.fromOffset(3, 12),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 6,
		}, medalBar)
	end

	-- The result of a round, over the scene ----------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.62),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 10,
	}, sceneBox)
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
	new("UITextSizeConstraint", { MaxTextSize = 44 }, medalText)
	local resultLine = outlined({
		Position = UDim2.fromScale(0, 0.44),
		Size = UDim2.fromScale(1, 0.24),
		TextScaled = true,
		Text = "",
		TextColor3 = Style.ui.text,
		ZIndex = 11,
	}, resultCard)
	new("UITextSizeConstraint", { MaxTextSize = 20 }, resultLine)
	local bestLine = outlined({
		Position = UDim2.fromScale(0, 0.7),
		Size = UDim2.fromScale(1, 0.22),
		TextScaled = true,
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 11,
	}, resultCard)
	new("UITextSizeConstraint", { MaxTextSize = 17 }, bestLine)

	-- The TAP button with the closing ring ---------------------------------------------------------
	local buttonHolder = new("Frame", {
		Name = "ButtonHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, SCENE_H + 56),
		Size = UDim2.fromOffset(BUTTON_SIZE * RING_START, BUTTON_SIZE + 14),
		ClipsDescendants = false,
		BackgroundTransparency = 1,
	}, root)
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BUTTON_SIZE * RING_START, BUTTON_SIZE * RING_START),
		BackgroundTransparency = 1,
	}, buttonHolder)
	rounded(ring, 1000)
	local ringStroke =
		new("UIStroke", { Color = Style.ui.gold, Thickness = 4, Transparency = 1 }, ring)
	local button = new("TextButton", {
		Name = "Tap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = Style.ui.good,
		Text = "TAP",
		Font = Style.font,
		TextSize = 26,
		TextColor3 = Style.ui.dark,
		AutoButtonColor = false,
	}, buttonHolder)
	rounded(button, 1000)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, button)
	local buttonScale = new("UIScale", {}, button)

	-- A pop-up above the scene after each tap ---------------------------------------------------------
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(240, 36),
		Text = "",
		TextSize = 30,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 8,
	}, sceneBox)
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

	-- The server's state, mirrored from the attributes and moved on by the same Juggle functions ---
	local round: Juggle.State = Juggle.new(0)
	local function readServerState()
		local phase = player:GetAttribute("juggleState")
		if phase == "running" or phase == "cooldown" or phase == "finished" then
			round.phase = phase
		end
		local function number(name: string): number
			local value = player:GetAttribute(name)
			return if type(value) == "number" then value else 0
		end
		round.startedAt = number("juggleStart")
		round.cooldownUntil = number("juggleCooldownUntil")
		round.combo = number("juggleCombo")
		round.hits = number("juggleHits")
		round.lastIndex = number("juggleLast")
		round.roundEndsAt = number("juggleRoundEnds")
	end
	readServerState()
	for _, name in
		{
			"juggleState",
			"juggleStart",
			"juggleCooldownUntil",
			"juggleCombo",
			"juggleHits",
			"juggleLast",
			"juggleRoundEnds",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(readServerState)
	end

	local function press()
		if not gui.Enabled then
			return
		end
		pulse(buttonScale, 0.88)
		Net.fire("TrainingTap")
	end
	button.Activated:Connect(press)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E then
			press()
		end
	end)

	-- What the server tells us -----------------------------------------------------------------------
	local lastCombo = 0
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "juggleResult" then
			local paid = if type(info.paid) == "number" then info.paid else 0
			local combo = if type(info.combo) == "number" then info.combo else 0
			if info.outcome == "hit" then
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
			lastCombo = combo
		elseif info.kind == "juggleDrop" then
			if lastCombo >= 3 then
				popFeedback("DROPPED", BAD)
			end
			lastCombo = 0
		elseif info.kind == "juggleRound" then
			local medal = if type(info.medal) == "number" then info.medal else 0
			local hits = if type(info.hits) == "number" then info.hits else 0
			local best = if type(info.bestCombo) == "number" then info.bestCombo else 0
			medalText.Text = MEDAL_NAMES[medal] or ""
			medalText.TextColor3 = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultStroke.Color = MEDAL_COLORS[medal] or MEDAL_COLORS[0]
			resultLine.Text = string.format("%d touches  ·  best combo %d", hits, best)
			local record = player:GetAttribute("keepieBestHits")
			bestLine.Text = if info.newBest == true
				then "NEW PERSONAL BEST!"
				else string.format(
					"Personal best: %d",
					if type(record) == "number" then record else 0
				)
			bestLine.TextColor3 = if info.newBest == true then Style.ui.gold else Style.ui.idle
			resultCard.Visible = true
			pulse(resultScale, 0.6)
			lastCombo = 0
		end
	end)

	-- Every frame ------------------------------------------------------------------------------------
	local bounce = Config.Training.juggleBounceSeconds
	local window = Config.Training.juggleWindow
	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "keepie"
		gui.Enabled = active
		if not active then
			resultCard.Visible = false
			return
		end
		showPlayer()
		local now = Workspace:GetServerTimeNow()
		Juggle.normalize(round, now)

		-- The ball: up and down on the beat while it runs, resting on the foot otherwise.
		local running = round.phase == "running"
		if running then
			ball.Position = BALL_REST + Vector3.new(0, Juggle.height(round, now) * BALL_PEAK, 0)
		else
			ball.Position = BALL_REST
		end

		-- The ring closes in on the button on the next beat.
		local ringAlpha = 0
		if running then
			local index = math.max(math.ceil((now - round.startedAt - window) / bounce), 1)
			local untilBeat = Juggle.beatTime(round, index) - now
			ringAlpha = math.clamp(1 - untilBeat / bounce, 0, 1)
		end
		local size = BUTTON_SIZE * (RING_START + (1 - RING_START) * ringAlpha)
		ring.Size = UDim2.fromOffset(size, size)
		ringStroke.Transparency = if running then 0.55 - 0.55 * ringAlpha else 1

		-- The text.
		local finished = round.phase == "finished"
		resultCard.Visible = finished and resultCard.Visible
		local timeLeft = math.max(round.roundEndsAt - now, 0)
		local leadIn = running and now < round.startedAt
		roundText.Text = if finished
			then "Round over"
			elseif leadIn then string.format(
				"Get ready...  %.0f",
				math.ceil(round.startedAt - now)
			)
			else string.format(
				"%d s left  ·  %s",
				math.ceil(timeLeft),
				if round.phase == "cooldown" then "ball down..." else "keep it up!"
			)
		hitsText.Text = string.format("%d touches", round.hits)
		comboText.Text = if round.combo >= 2 then "x" .. round.combo else ""
		comboText.TextColor3 = if round.combo >= Config.Training.juggleComboMax
			then Style.ui.gold
			else Style.ui.text
		local progress = math.clamp(round.hits / medals.gold, 0, 1)
		medalFill.Size = UDim2.fromScale(progress, 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Juggle.medal(round.hits), 1)]
		-- The button greys while the ball is down or the round is over.
		local waiting = round.phase ~= "running"
		button.BackgroundColor3 = if waiting then Color3.fromRGB(95, 100, 115) else Style.ui.good
		button.TextColor3 = if waiting then Color3.fromRGB(170, 175, 190) else Style.ui.dark
	end)
end

return KeepieUi
