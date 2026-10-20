--!strict
-- The keepie-uppies screen (docs/PLAN.md, Step 4), in the look of the penalty screen (the shared
-- Panel): your best player keeps a ball up, and you tap when the ball comes back to his foot. A ring
-- closes in on the TAP button on the beat; a tap close to it is a clean touch, the combo grows and each
-- touch pays a little TP, and his foot kicks at the same moment. Rounds last 30 seconds and end in a
-- Bronze, Silver or Gold medal, with your best round kept. Before the first round a short text says
-- how to play. The ball is drawn from the server's state (the same Juggle functions the server judges
-- with); the server pays and keeps the record. The screen shows while the player stands on the mat.

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
local Panel = require(script.Parent.Panel)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_HEIGHT = 0.94 -- the share of the screen height the panel takes, like the penalty screen
local CARD_CHROME = 64 + 4 + 20 + 24 -- the panel header, the card padding and the three gaps
local SCENE_RATIO = 1.8 -- width over height of the picture
local MIN_SCENE_HEIGHT = 90
local CHIPS_HEIGHT = 46
local HINT_HEIGHT = 18
local RING_START = 2.1 -- the ring starts this many times the size of the button
local BALL_RADIUS = 0.55
local BALL_REST = Vector3.new(0.25, 0.7, -1.2) -- on the foot of the player, in front of him
local BALL_PEAK = 6 -- studs above the foot at the top of the flight
local KICK_SECONDS = 0.28
local KICK_ANGLE = 55 -- degrees the kicking leg swings forward
local FEEDBACK_HOLD_SECONDS = 0.55
local FEEDBACK_FADE_SECONDS = 0.3
local GO_SECONDS = 0.7 -- how long "GO!" shows after the round starts

local MEDAL_NAMES = { [0] = "No medal", [1] = "BRONZE", [2] = "SILVER", [3] = "GOLD" }
local MEDAL_COLORS = {
	[0] = Color3.fromRGB(150, 155, 170),
	[1] = Color3.fromRGB(205, 140, 80),
	[2] = Color3.fromRGB(205, 210, 225),
	[3] = Color3.fromRGB(255, 205, 60),
}
local BAD = Color3.fromRGB(232, 142, 138)
local WHITE = Color3.fromRGB(255, 255, 255)

local HOW_TO_PLAY = {
	"Tap TAP when the ring closes.",
	"Keep the ball up until time runs out.",
	"More touches in a row = more TP.",
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
	}, player:WaitForChild("PlayerGui"))

	local built = Panel.build(gui, "Keepie-uppies", PANEL_HEIGHT, function() end)
	local backdrop, card = built.backdrop, built.card
	-- The mat is left by walking off it, so the X has no job here.
	local closeX = backdrop:FindFirstChild("CloseX", true)
	if closeX and closeX:IsA("GuiObject") then
		closeX.Visible = false
	end
	local cardLayout = card:FindFirstChildOfClass("UIListLayout")
	if cardLayout then
		cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	-- The scene: your best player and the ball -----------------------------------------------------
	local sceneBox = new("Frame", {
		Name = "Scene",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(300, 160),
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
		LightDirection = Vector3.new(-0.3, -1, -0.6),
		ZIndex = 7,
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

	-- The player: the best of the owned players. A kick swings one leg (shorts, sock and boot) about
	-- the hip, forwards (the front of the figure is the -Z side).
	local shown: Model? = nil
	local shownId = ""
	local legParts: { [string]: { { part: Part, offset: Vector3 } } } = {}
	local BASE_HEIGHT = Mannequin.FEET_TO_TORSO + 0.15
	local function findLegParts(model: Model)
		table.clear(legParts)
		for _, side in { "Left", "Right" } do
			local list = {}
			for _, kind in { "Shorts", "Sock", "Boot" } do
				local part = model:FindFirstChild(side .. kind)
				if part and part:IsA("Part") then
					-- Where the part is, relative to the torso.
					table.insert(
						list,
						{ part = part, offset = part.Position - model:GetPivot().Position }
					)
				end
			end
			legParts[side] = list
		end
	end
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
		local model = Mannequin.build(def, nil, false, { detailed = true })
		model:PivotTo(CFrame.new(0, BASE_HEIGHT, 0))
		model.Parent = view
		findLegParts(model)
		shown = model
		shownId = id
	end
	-- Swings the leg `side` ("Left" or "Right") by `angle` degrees about the hip.
	local function poseLeg(side: string, angle: number)
		local list = legParts[side]
		if list == nil then
			return
		end
		local sign = if side == "Right" then 1 else -1
		local torso = CFrame.new(0, BASE_HEIGHT, 0)
		local hip = torso * CFrame.new(sign * 0.5, -1, 0)
		local swing = hip * CFrame.Angles(math.rad(angle), 0, 0)
		for _, entry in list do
			local fromHip = entry.offset - Vector3.new(sign * 0.5, -1, 0)
			entry.part.CFrame = swing * CFrame.new(fromHip)
		end
	end

	-- The combo and the medal bar ---------------------------------------------------------------------
	local comboText = outlined({
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(110, 40),
		Text = "",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 9,
	}, sceneBox)
	local comboScale = new("UIScale", {}, comboText)
	local medalBar = new("Frame", {
		Name = "Medals",
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.new(0.34, 0, 0, 10),
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
	local medals = Config.Training.juggleMedals
	for medal, hits in { medals.bronze, medals.silver, medals.gold } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(hits / medals.gold, -0.5),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = MEDAL_COLORS[medal],
			BorderSizePixel = 0,
			ZIndex = 11,
		}, medalBar)
	end

	-- A pop-up over the scene after each tap ----------------------------------------------------------
	local feedback = outlined({
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.new(0.8, 0, 0, 34),
		Text = "",
		TextSize = 28,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		ZIndex = 9,
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

	-- How to play, before the first round -------------------------------------------------------------
	local intro = new("Frame", {
		Name = "HowToPlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.18,
		ZIndex = 12,
	}, sceneBox)
	local introTitle = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "HOW TO PLAY",
		TextColor3 = Style.ui.gold,
		ZIndex = 13,
	}, intro)
	fitted(introTitle, 26)
	for index, line in HOW_TO_PLAY do
		local label = outlined({
			Position = UDim2.fromScale(0.04, 0.27 + (index - 1) * 0.2),
			Size = UDim2.fromScale(0.92, 0.17),
			Text = line,
			ZIndex = 13,
		}, intro)
		fitted(label, 20)
	end
	local introCount = outlined({
		Position = UDim2.fromScale(0.04, 0.87),
		Size = UDim2.fromScale(0.92, 0.11),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 13,
	}, intro)
	fitted(introCount, 16)

	-- The big countdown ("3", "2", "1", "GO!") over the scene.
	local bigText = outlined({
		Name = "Big",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.5),
		Text = "",
		TextColor3 = Style.ui.gold,
		Visible = false,
		ZIndex = 13,
	}, sceneBox)
	fitted(bigText, 80)

	-- The result of a round, over the scene -----------------------------------------------------------
	local resultCard = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 14,
	}, sceneBox)
	rounded(resultCard, 14)
	local resultStroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, resultCard)
	local resultScale = new("UIScale", {}, resultCard)
	local medalText = outlined({
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.4),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 15,
	}, resultCard)
	fitted(medalText, 46)
	local resultLine = outlined({
		Position = UDim2.fromScale(0.04, 0.48),
		Size = UDim2.fromScale(0.92, 0.22),
		Text = "",
		ZIndex = 15,
	}, resultCard)
	fitted(resultLine, 22)
	local bestLine = outlined({
		Position = UDim2.fromScale(0.04, 0.73),
		Size = UDim2.fromScale(0.92, 0.2),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 15,
	}, resultCard)
	fitted(bestLine, 18)

	-- The numbers: time left, touches in this round and the best round -------------------------------
	local chipRow = new("Frame", {
		Name = "Chips",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, CHIPS_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, chipRow)
	local function chip(order: number, name: string): TextLabel
		local box = new("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1 / 3, -6, 1, 0),
			BackgroundColor3 = Style.ui.panel,
			ZIndex = 8,
		}, chipRow)
		rounded(box, 12)
		new("UIStroke", {
			Color = Color3.fromRGB(110, 115, 132),
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, box)
		new("TextLabel", {
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = string.upper(name),
			Font = Style.font,
			TextSize = 13,
			TextColor3 = Style.ui.idle,
			ZIndex = 9,
		}, box)
		return new("TextLabel", {
			Name = "Value",
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 1, -18),
			BackgroundTransparency = 1,
			Text = "-",
			Font = Style.font,
			TextSize = 24,
			TextColor3 = Style.ui.text,
			ZIndex = 9,
		}, box)
	end
	local timeValue = chip(1, "Time")
	local touchesValue = chip(2, "Touches")
	local bestValue = chip(3, "Best")

	-- The TAP button with the closing ring ---------------------------------------------------------------
	local buttonHolder = new("Frame", {
		Name = "ButtonHolder",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, card)
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, buttonHolder)
	rounded(ring, 1000)
	local ringStroke =
		new("UIStroke", { Color = Style.ui.gold, Thickness = 5, Transparency = 1 }, ring)
	local button = new("TextButton", {
		Name = "Tap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Style.ui.good,
		Text = "TAP",
		Font = Style.font,
		TextSize = 26,
		TextColor3 = WHITE,
		AutoButtonColor = false,
		ZIndex = 9,
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
	local buttonSize = 60

	new("TextLabel", {
		Name = "Hint",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, HINT_HEIGHT),
		BackgroundTransparency = 1,
		Text = "Walk off the mat to stop.",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Panel.MUTED,
		ZIndex = 7,
	}, card)

	-- The picture and the button take what the screen allows, so nothing needs scrolling on a normal
	-- window and the button is never cut off.
	local function fit()
		local area = gui.AbsoluteSize
		if area.Y < 1 then
			local current = Workspace.CurrentCamera
			area = if current then current.ViewportSize else Vector2.new(640, 360)
		end
		local width = math.min(Panel.MAX_WIDTH, area.X * 0.92) - 40
		local spare = area.Y * PANEL_HEIGHT - CARD_CHROME - CHIPS_HEIGHT - HINT_HEIGHT
		local buttonArea = math.clamp(spare * 0.4, 84, 150)
		local height = math.clamp(spare - buttonArea, MIN_SCENE_HEIGHT, width / SCENE_RATIO)
		sceneBox.Size = UDim2.fromOffset(height * SCENE_RATIO, height)
		buttonHolder.Size = UDim2.new(1, 0, 0, buttonArea)
		buttonSize = math.clamp(buttonArea / (RING_START + 0.1), 36, 76)
		button.Size = UDim2.fromOffset(buttonSize, buttonSize)
		button.TextSize = math.floor(buttonSize * 0.42)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
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

	-- The kick: the foot swings at the tap, the other foot on the next one.
	local kickStartedAt = -10
	local kickSide = "Right"
	local function press()
		if not backdrop.Visible then
			return
		end
		pulse(buttonScale, 0.88)
		kickSide = if kickSide == "Right" then "Left" else "Right"
		kickStartedAt = os.clock()
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
	local lead = Config.Training.juggleLeadSeconds
	RunService.RenderStepped:Connect(function()
		local active = player:GetAttribute("training") == true
			and player:GetAttribute("trainingStation") == "keepie"
		backdrop.Visible = active
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

		-- The foot: a quick swing forwards and back from the tap.
		local kick = (os.clock() - kickStartedAt) / KICK_SECONDS
		poseLeg(kickSide, if kick < 1 then KICK_ANGLE * math.sin(math.pi * kick) else 0)
		if kick >= 1 then
			poseLeg(if kickSide == "Right" then "Left" else "Right", 0)
		end

		-- The ring closes in on the button on the next beat.
		local ringAlpha = 0
		if running then
			local index = math.max(math.ceil((now - round.startedAt - window) / bounce), 1)
			local untilBeat = Juggle.beatTime(round, index) - now
			ringAlpha = math.clamp(1 - untilBeat / bounce, 0, 1)
		end
		local size = buttonSize * (RING_START + (1 - RING_START) * ringAlpha)
		ring.Size = UDim2.fromOffset(size, size)
		ringStroke.Transparency = if running then 0.45 - 0.45 * ringAlpha else 1

		-- The numbers and the texts over the scene.
		local finished = round.phase == "finished"
		resultCard.Visible = finished and resultCard.Visible
		local untilStart = round.startedAt - now
		local leadIn = running and untilStart > 0
		local showIntro = leadIn and untilStart > lead + 0.05
		intro.Visible = showIntro
		introCount.Text = string.format("Starts in %d", math.ceil(untilStart))
		local showGo = running and not leadIn and -untilStart < GO_SECONDS
		bigText.Visible = (leadIn and not showIntro) or showGo
		bigText.Text = if leadIn then tostring(math.ceil(untilStart)) else "GO!"

		local timeLeft = if leadIn
			then Config.Training.juggleRoundSeconds
			else math.max(round.roundEndsAt - now, 0)
		timeValue.Text = if finished then "0" else string.format("%d s", math.ceil(timeLeft))
		timeValue.TextColor3 = if not finished
				and not leadIn
				and timeLeft <= 5
			then BAD
			else Style.ui.text
		touchesValue.Text = tostring(round.hits)
		local record = player:GetAttribute("keepieBestHits")
		bestValue.Text = tostring(math.max(if type(record) == "number" then record else 0, 0))
		bestValue.TextColor3 = if round.hits > 0
				and type(record) == "number"
				and round.hits >= record
			then Style.ui.gold
			else Style.ui.text
		comboText.Text = if round.combo >= 2 then "x" .. round.combo else ""
		comboText.TextColor3 = if round.combo >= Config.Training.juggleComboMax
			then Style.ui.gold
			else WHITE
		local progress = math.clamp(round.hits / medals.gold, 0, 1)
		medalFill.Size = UDim2.fromScale(progress, 1)
		medalFill.BackgroundColor3 = MEDAL_COLORS[math.max(Juggle.medal(round.hits), 1)]
		-- The button greys while the ball is down or the round is over.
		local waiting = round.phase ~= "running" or leadIn
		button.BackgroundColor3 = if waiting then Color3.fromRGB(95, 100, 115) else Style.ui.good
	end)
end

return KeepieUi
