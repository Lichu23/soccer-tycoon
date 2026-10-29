--!strict
-- Big Chance on the screen (shared/BigChance, server/BigChanceActions). Every few matches a green
-- "BIG CHANCE!" button shows at the bottom for a few seconds, its bar running out. Tapping it (or E)
-- turns the whole screen into the breakaway's stadium, like the daily penalty kicks
-- (client/BreakawayScene), with the player's avatar behind the ball on one of three spots in front
-- of the goal: the left of the box, the middle or the right. The shot is the penalty's: the reticle
-- glides over the goal mouth and a tap locks it, then a tap when the power meter's indicator is on
-- the green shoots, all inside a shot clock. The kick plays as a film and the words say what
-- happened ("GOAL!" and the cash it paid), then the screen closes. The server offers, judges and
-- pays; this only draws the state from the player's attributes. The red X leaves at any time: the
-- chance is lost, nothing else.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BigChance = require(ReplicatedStorage.Shared.BigChance)
local BreakawayScene = require(script.Parent.BreakawayScene)
local CinemaScreen = require(script.Parent.CinemaScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Freekick = require(ReplicatedStorage.Shared.Freekick)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local RULES = Config.BigChance
local OFFER_WIDTH = 230
local OFFER_HEIGHT = 58
local BOTTOM = 96 -- the offer button sits this far up from the bottom, over the thumbstick and jump row
local FEEDBACK_HOLD_SECONDS = 1.6
local FEEDBACK_FADE_SECONDS = 0.3
local CLOSE_FADE_SECONDS = 1 -- every sound fades out this long when the screen closes
local DONE_HOLD_SECONDS = 1.4 -- the film's last frame stays this long before the screen closes
local START_TIMEOUT = 4 -- the screen closes if the server never answers the take
local LETTERBOX = 0.08 -- the share of the screen height of each film bar
local POWER_LINGER = 0.8 -- the meter stays this long into the film, its indicator where it stopped
local CLOCK_TOP = 84 -- the shot clock sits under the step name
local CLOCK_BAR = 170
local CLOCK_URGENT = 0.3 -- the share of the clock left when it turns red
local COACH_BOTTOM = 40

-- The film's moments, in the kick's own film time (it starts at the run-up).
local CONTACT_AT = BreakawayScene.CONTACT_AT - BreakawayScene.PENALTY_SKIP
local ARRIVE_AT = BreakawayScene.ARRIVE_AT - BreakawayScene.PENALTY_SKIP

local BAD = Color3.fromRGB(232, 142, 138)
local WHITE = Color3.fromRGB(255, 255, 255)
local RED_X = Color3.fromRGB(232, 64, 96)

local OFFER_KEYS = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.ButtonX] = true,
}
local TAP_KEYS = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonR2] = true,
}

local STEP_NAMES: { [string]: string } = {
	aim = "AIM",
	power = "POWER",
}

local COACH_TEXT: { [string]: string } = {
	waiting = "Big chance! Get ready...",
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
	late = "TOO LATE",
}
local OUTCOME_SOUND: { [string]: string } = {
	goal = "goal",
	saved = "save",
	late = "save",
	post = "post",
	bar = "post",
}

local BigChanceUi = {}

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

local function pulse(scale: UIScale, from: number)
	if GuiService.ReducedMotionEnabled then
		scale.Scale = 1
		return
	end
	scale.Scale = from
	TweenService
		:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()
end

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function revision(): number
	return number("bigChanceRev")
end

function BigChanceUi.init()
	Sounds.preload()
	local playerGui = player:WaitForChild("PlayerGui")

	-- The offer, over the world: a green button with a bar that runs out. Its screen is in
	-- CinemaScreen's hidden list, so no other full-screen game shows it.
	local offerGui = new("ScreenGui", {
		Name = "BigChance",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 5,
	}, playerGui)
	local offer = new("TextButton", {
		Name = "Offer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		Size = UDim2.fromOffset(OFFER_WIDTH, OFFER_HEIGHT),
		BackgroundColor3 = Style.ui.good,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
	}, offerGui)
	rounded(offer, 14)
	new(
		"UIStroke",
		{ Color = Style.ui.dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		offer
	)
	local offerScale = new("UIScale", {}, offer)
	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = "BIG CHANCE!",
		Font = Style.font,
		TextSize = 26,
		TextColor3 = Style.ui.dark,
	}, offer)
	new("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = `Tap to shoot for {RULES.rewardMatches}x match cash`,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Style.ui.dark,
	}, offer)
	local offerTrack = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, offer)
	rounded(offerTrack, 2)
	local offerBar = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.dark,
		BorderSizePixel = 0,
	}, offerTrack)
	rounded(offerBar, 2)

	-- The shot: two layers like the penalty kicks. The film's bars and the reticle cover the whole
	-- screen; the controls and the numbers stay inside the safe area.
	local world = new("ScreenGui", {
		Name = "BigChanceWorld",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 4,
		Enabled = false,
	}, playerGui)
	local gui = new("ScreenGui", {
		Name = "BigChanceShot",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
		Enabled = false,
	}, playerGui)

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
	local aimMark = CinemaScreen.reticle(world)
	local reticle, reticleStroke, reticleScale = aimMark.frame, aimMark.stroke, aimMark.scale

	local tapArea = new("TextButton", {
		Name = "TapArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, gui)

	-- The title and what a goal pays, top centre.
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(260, 48),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, gui)
	outlined({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "BIG CHANCE",
		TextSize = 22,
		TextColor3 = Style.ui.good,
		ZIndex = 5,
	}, top)
	local rewardLine = outlined({
		Name = "Reward",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 5,
	}, top)
	fitted(rewardLine, 16)

	-- The red X, top left: leaves (the chance is lost).
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
		Position = UDim2.new(0.5, 0, 0, 54),
		Size = UDim2.new(0.6, 0, 0, 28),
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

	-- The power meter, on the right: the penalty's green zone.
	local meter = CinemaScreen.powerMeter(gui, Freekick.penaltyZone())
	local powerBox, powerStroke = meter.box, meter.stroke

	-- The words of the result, in the middle.
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
	local subText = outlined({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.money,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	fitted(subText, 28)
	local subStroke = subText:FindFirstChildOfClass("UIStroke") :: UIStroke
	subStroke.Transparency = 1

	-- The hint, at the bottom.
	local coachText = outlined({
		Name = "Coach",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -COACH_BOTTOM),
		Size = UDim2.new(0.86, 0, 0, 30),
		Text = "",
		Visible = false,
		ZIndex = 9,
	}, gui)
	fitted(coachText, 24)

	local feedbackToken = 0
	local function popFeedback(text: string, color: Color3, sub: string)
		feedbackToken += 1
		local myToken = feedbackToken
		feedback.Text = text
		feedback.TextColor3 = color
		subText.Text = sub
		feedback.TextTransparency = 0
		subText.TextTransparency = 0
		feedbackStroke.Transparency = 0
		subStroke.Transparency = 0
		pulse(feedbackScale, 0.6)
		task.delay(FEEDBACK_HOLD_SECONDS, function()
			if feedbackToken ~= myToken then
				return
			end
			local info = TweenInfo.new(FEEDBACK_FADE_SECONDS)
			TweenService:Create(feedback, info, { TextTransparency = 1 }):Play()
			TweenService:Create(feedbackStroke, info, { Transparency = 1 }):Play()
			TweenService:Create(subText, info, { TextTransparency = 1 }):Play()
			TweenService:Create(subStroke, info, { Transparency = 1 }):Play()
		end)
	end
	local function hideFeedback()
		feedbackToken += 1
		feedback.TextTransparency = 1
		feedbackStroke.Transparency = 1
		subText.TextTransparency = 1
		subStroke.Transparency = 1
	end

	-- The server's state, mirrored from the attributes ---------------------------------------------
	local state: BigChance.State = BigChance.new()
	-- What the player just did, shown at once until the server's answer arrives.
	local lockedX: number? = nil
	local lockedY: number? = nil
	local localStartAt = 0 -- when the meter moves, from our own lock, until the server's arrives
	local releasedPower: number? = nil
	local frozenClock: number? = nil -- the seconds left when the player shot, held into the film
	local offerAnim: Tween? = nil
	local tookAt = -1 -- the end of the offer the player took, so it never shows again

	local function showOffer(shown: boolean)
		if shown == offer.Visible then
			return
		end
		offer.Visible = shown
		if offerAnim then
			offerAnim:Cancel()
			offerAnim = nil
		end
		if shown then
			pulse(offerScale, 0.6)
			-- A slow, gentle grow and shrink while it waits.
			if not GuiService.ReducedMotionEnabled then
				local anim = TweenService:Create(
					offerScale,
					TweenInfo.new(
						0.6,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.InOut,
						-1,
						true,
						0.25
					),
					{ Scale = 1.06 }
				)
				task.delay(0.25, function()
					if offerAnim == anim then
						anim:Play()
					end
				end)
				offerAnim = anim
			end
		end
	end

	local function readServerState()
		local phase = player:GetAttribute("bigChanceState")
		local previous = state.phase
		if
			phase == "none"
			or phase == "offer"
			or phase == "aim"
			or phase == "power"
			or phase == "shot"
		then
			state.phase = phase
		end
		state.spot = math.max(number("bigChanceSpot"), 1)
		state.endsAt = number("bigChanceEndsAt")
		state.stageAt = number("bigChanceStageAt")
		state.aimX = number("bigChanceAimX")
		state.aimY = number("bigChanceAimY")
		state.holdAt = number("bigChanceHoldAt")
		state.power = number("bigChancePower")
		local outcome = player:GetAttribute("bigChanceOutcome")
		state.outcome = if type(outcome) == "string" then outcome else ""
		if state.phase ~= previous then
			lockedX, lockedY = nil, nil
			releasedPower = nil
		end
	end

	-- The screen --------------------------------------------------------------------------------------
	local scene: BreakawayScene.Scene? = nil
	local takeover = CinemaScreen.takeover()
	local startRev = -1 -- the revision before our take; the shot starts once it changes
	local openedAt = 0
	local doneAt: number? = nil
	local lastFilm = -1
	local lastStageAt = -1

	local function close()
		if scene == nil then
			return
		end
		scene.destroy()
		scene = nil
		world.Enabled = false
		gui.Enabled = false
		hideFeedback()
		takeover.give()
		Sounds.fadeOutAll(CLOSE_FADE_SECONDS)
	end

	local function open()
		if scene then
			return
		end
		local spot = RULES.spots[state.spot] or RULES.spots[2]
		doneAt = nil
		lastFilm, lastStageAt = -1, -1
		lockedX, lockedY = nil, nil
		releasedPower = nil
		frozenClock = nil
		startRev = revision()
		openedAt = os.clock()
		takeover.take()
		scene = BreakawayScene.new({
			penalty = true,
			spotX = spot.x,
			spotZ = spot.z,
			keeperX = spot.keeperX,
			filmSeconds = RULES.filmSeconds,
		})
		hideFeedback()
		local reward = number("bigChanceReward")
		rewardLine.Text = if reward > 0 then `A goal pays {NumberFormat.money(reward)}` else ""
		world.Enabled = true
		gui.Enabled = true
		Sounds.startAmbience()
	end

	local function take()
		if
			state.phase ~= "offer"
			or tookAt == state.endsAt
			or scene ~= nil
			or Workspace:GetServerTimeNow() >= state.endsAt
		then
			return
		end
		tookAt = state.endsAt
		showOffer(false)
		open()
		Net.fire("BigChanceTap", "take", Workspace:GetServerTimeNow())
	end
	offer.Activated:Connect(take)
	leave.Activated:Connect(close)

	player:GetAttributeChangedSignal("bigChanceRev"):Connect(readServerState)
	readServerState()

	-- The inputs -------------------------------------------------------------------------------------
	local function started(): boolean
		return scene ~= nil and revision() ~= startRev
	end

	-- When the power meter moves: the server's time once it is known.
	local function meterStart(): number
		return if state.holdAt > 0 then state.holdAt else localStartAt
	end

	local function press()
		if not started() then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if now > state.endsAt then
			return -- the clock ran out: the keeper smothers the ball
		end
		if state.phase == "aim" and lockedX == nil and now >= state.stageAt then
			lockedX, lockedY = Freekick.aimAt(state, now)
			localStartAt = now + Config.Training.freekickPowerDelay
			pulse(reticleScale, 1.4)
			Net.fire("BigChanceTap", "shoot", now)
		elseif state.phase == "power" and releasedPower == nil and now >= meterStart() then
			releasedPower = Freekick.powerAt({ holdAt = meterStart() }, now)
			frozenClock = math.max(state.endsAt - now, 0)
			Net.fire("BigChanceTap", "shoot", now)
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
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if scene ~= nil then
			if TAP_KEYS[input.KeyCode] then
				press()
			end
		elseif OFFER_KEYS[input.KeyCode] and offer.Visible and offerGui.Enabled then
			take()
		end
	end)

	-- The ball arrives: the sound and the words.
	local function arrived()
		local sound = OUTCOME_SOUND[state.outcome]
		if sound then
			Sounds.play(sound)
		end
		if state.outcome == "goal" then
			local bonus = number("bigChanceBonus")
			popFeedback(
				OUTCOME_TEXT.goal,
				Style.ui.good,
				if bonus > 0 then `+{NumberFormat.money(bonus)}` else ""
			)
		else
			popFeedback(OUTCOME_TEXT[state.outcome] or "MISSED", BAD, "")
		end
	end

	local function filmMoments(t: number)
		local function crossed(at: number): boolean
			return lastFilm < at and t >= at
		end
		if crossed(CONTACT_AT) and state.outcome ~= "late" then
			Sounds.play("kick")
		end
		if crossed(ARRIVE_AT) then
			arrived()
		end
	end

	-- Every frame ------------------------------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		-- The offer: shown while it lasts, unless it was taken.
		local offering = scene == nil
			and state.phase == "offer"
			and now < state.endsAt
			and tookAt ~= state.endsAt
		showOffer(offering)
		if offering then
			offerBar.Size =
				UDim2.fromScale(math.clamp((state.endsAt - now) / RULES.offerSeconds, 0, 1), 1)
		end

		local current = scene
		if current == nil then
			return
		end
		takeover.keep()
		local ready = started()
		if not ready and os.clock() - openedAt > START_TIMEOUT then
			close() -- the server never answered
			return
		end
		if ready and (state.phase == "aim" or state.phase == "power") then
			BigChance.normalize(state, now) -- the clock running out plays the keeper's smother
		end
		if ready and (state.phase == "none" or state.phase == "offer") then
			close() -- the chance went away (the take came too late)
			return
		end
		local phase = if ready then state.phase else "aim"
		local stageAt = if ready then state.stageAt else math.huge

		local aiming = ready and (phase == "aim" or phase == "power")
		local reticleX, reticleY = state.aimX, state.aimY
		if phase == "aim" then
			if lockedX and lockedY then
				reticleX, reticleY = lockedX, lockedY
			else
				reticleX, reticleY = Freekick.aimAt({ stageAt = stageAt }, now)
			end
		end
		current.frame({
			state = {
				phase = phase :: any,
				seed = 0,
				kick = 1,
				stageAt = stageAt,
				move = Freekick.STEP_OVER,
				aimX = state.aimX,
				aimY = state.aimY,
				holdAt = state.holdAt,
				power = state.power,
				shotBy = 0,
				outcome = state.outcome,
				streak = 0,
				overAt = 0,
				practice = false,
			},
			now = now,
			reticleX = reticleX,
			reticleY = reticleY,
		})

		-- The film: its bars and its moments.
		local filming = ready and phase == "shot"
		if filming then
			if state.stageAt ~= lastStageAt then
				lastStageAt = state.stageAt
				lastFilm = -1
			end
			local filmT = now - state.stageAt
			filmMoments(filmT)
			lastFilm = filmT
		end
		for _, bar in bars do
			bar.Size = UDim2.fromScale(1, if filming then LETTERBOX else 0)
		end

		-- The reticle on the goal.
		local waiting = not ready or (phase == "aim" and now < stageAt)
		reticle.Visible = aiming and not waiting
		if reticle.Visible then
			local camera = Workspace.CurrentCamera
			local point = camera:WorldToViewportPoint(current.goalPoint(reticleX, reticleY))
			reticle.Position = UDim2.fromOffset(point.X, point.Y)
			reticleStroke.Color = if phase == "power" or lockedX
				then Style.ui.good
				else Style.ui.gold
		end

		-- The shot clock.
		clock.Visible = aiming and not waiting
		if clock.Visible then
			local secondsLeft = frozenClock or math.max(state.endsAt - now, 0)
			local share = math.clamp(secondsLeft / RULES.shotSeconds, 0, 1)
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
			and state.outcome ~= "late"
			and now - state.stageAt < POWER_LINGER
		local power = if phase == "power"
			then releasedPower or Freekick.powerAt({ holdAt = meterStart() }, now)
			elseif struck then state.power
			else 0
		powerBox.Visible = ready and (phase == "power" or struck)
		CinemaScreen.setPower(meter, power, releasedPower ~= nil or struck)
		powerStroke.Color = if releasedPower then Style.ui.good else Style.ui.gold

		-- The texts.
		stepText.Text = if waiting then "GET READY" else (STEP_NAMES[phase] or "")
		local hint = COACH_TEXT[if waiting then "waiting" else phase]
		coachText.Visible = hint ~= nil
		coachText.Text = hint or ""

		-- The film has played: its last frame holds a moment, then the screen closes.
		if filming and now >= BigChance.filmEnd(state) then
			if doneAt == nil then
				doneAt = os.clock()
			elseif os.clock() - doneAt >= DONE_HOLD_SECONDS then
				close()
			end
		end
	end)
end

return BigChanceUi
