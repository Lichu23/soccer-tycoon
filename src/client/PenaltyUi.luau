--!strict
-- The daily penalty kicks (docs/PLAN.md, Step 7), played like the shot of the 1v1 breakaway: the
-- whole screen becomes the breakaway's stadium in penalty mode (client/BreakawayScene) with the
-- player's own avatar on the penalty spot. Each kick has two inputs, and only the one in play shows:
--   1. the aim: a reticle glides over the goal mouth; tap (click, Space or the A button) to lock it;
--   2. the power: an indicator slides up and down the meter by itself; tap when it is on the green
--      to shoot.
-- Then the kick plays as a film (the run-up, the strike in slow motion, the goal or the save) and the
-- next kick comes, until the day's kicks are used up; then the screen closes and the reward card
-- says what the goals earned. The kick pips at the top show the day's kicks. The server judges every
-- input and pays the boost (shared/Penalty, server/DailyActions); this only shows it. The red X
-- leaves at any time: a kick is only used once it is shot.

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
local Penalty = require(ReplicatedStorage.Shared.Penalty)
local RewardCard = require(script.Parent.RewardCard)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local FEEDBACK_HOLD_SECONDS = 1.3
local FEEDBACK_FADE_SECONDS = 0.3
local CLOSE_FADE_SECONDS = 1 -- every sound fades out this long when the screen closes
local DONE_HOLD_SECONDS = 1.2 -- the last film's last frame stays this long before the reward card
local START_TIMEOUT = 4 -- the screen closes if the server never answers the start
local LETTERBOX = 0.08 -- the share of the screen height of each film bar
local POWER_LINGER = 0.8 -- the meter stays this long into the film, its indicator where it stopped
local PIP_SIZE = 30
local PIP_GAP = 10
local COACH_BOTTOM = 40

-- The film's moments, in the penalty's own film time (it starts at the run-up).
local CONTACT_AT = BreakawayScene.CONTACT_AT - BreakawayScene.PENALTY_SKIP
local ARRIVE_AT = BreakawayScene.ARRIVE_AT - BreakawayScene.PENALTY_SKIP

local BAD = Color3.fromRGB(232, 142, 138)
local WHITE = Color3.fromRGB(255, 255, 255)
local RED_X = Color3.fromRGB(232, 64, 96)
local PIP_IDLE = Color3.fromRGB(150, 155, 170)

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

-- The hint for each step, on the first kick of the day.
local COACH_TEXT: { [string]: string } = {
	waiting = "Penalty time! Get ready...",
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
}
local OUTCOME_SOUND: { [string]: string } = {
	goal = "goal",
	saved = "save",
	post = "post",
	bar = "post",
}

local PenaltyUi = {}

-- Set by DailyUi: called with (goals today, boost seconds this visit) after the day's last kick.
PenaltyUi.onFinished = function(_goals: number, _boostSeconds: number) end

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

local function boostText(goals: number): string
	local seconds = Config.Daily.penaltyBoostSeconds[goals] or 0
	return string.format(
		"x%g income for %d min",
		Config.Daily.penaltyMultiplier,
		math.ceil(seconds / 60)
	)
end

function PenaltyUi.init()
	Sounds.preload()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Two layers: the film's bars and the reticle cover the whole screen; the controls and the
	-- numbers stay inside the safe area.
	local world = new("ScreenGui", {
		Name = "PenaltyWorld",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 4,
		Enabled = false,
	}, playerGui)
	local gui = new("ScreenGui", {
		Name = "Penalty",
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

	-- The day's kicks, top centre: one pip per kick (used earlier, a goal, a miss, still to take),
	-- and what the goals are worth under them.
	local kickCount = Config.Daily.penaltyKicks
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(260, 80),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, gui)
	outlined({
		Size = UDim2.new(1, 0, 0, 16),
		Text = "PENALTY KICKS",
		TextSize = 14,
		ZIndex = 5,
	}, top)
	local pipRow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(kickCount * PIP_SIZE + (kickCount - 1) * PIP_GAP, PIP_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, top)
	type Pip = { tile: Frame, stroke: UIStroke, scale: UIScale }
	local pips: { Pip } = {}
	for index = 1, kickCount do
		local tile = new("Frame", {
			Name = "Kick" .. index,
			Position = UDim2.fromOffset((index - 1) * (PIP_SIZE + PIP_GAP), 0),
			Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE),
			BackgroundColor3 = Style.ui.panel,
			ZIndex = 5,
		}, pipRow)
		rounded(tile, PIP_SIZE // 2)
		local stroke = new("UIStroke", {
			Color = PIP_IDLE,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, tile)
		pips[index] = { tile = tile, stroke = stroke, scale = new("UIScale", {}, tile) }
	end
	local rewardLine = outlined({
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextColor3 = Style.ui.idle,
		ZIndex = 5,
	}, top)
	fitted(rewardLine, 16)

	-- The red X, top left: leaves.
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
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.gold,
		ZIndex = 5,
	}, gui)
	fitted(stepText, 26)

	-- The power meter, on the right.
	local meter = CinemaScreen.powerMeter(gui, Freekick.penaltyZone())
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
	local subText = outlined({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.new(0.6, 0, 0, 30),
		Text = "",
		TextColor3 = Style.ui.good,
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
	local state: Penalty.State = Penalty.new(0, 0)
	local function number(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local function revision(): number
		return number("penaltyRev")
	end
	-- What the player just did, shown at once until the server's answer arrives.
	local lockedX: number? = nil
	local lockedY: number? = nil
	local localStartAt = 0 -- when the meter moves, from our own lock, until the server's arrives
	local releasedPower: number? = nil
	local function readServerState()
		local phase = player:GetAttribute("penaltyState")
		local previous = state.phase
		if phase == "aim" or phase == "power" or phase == "shot" or phase == "done" then
			state.phase = phase
		end
		state.seed = number("penaltySeed")
		state.kick = math.max(number("penaltyKick"), 1)
		state.stageAt = number("penaltyStageAt")
		state.aimX = number("penaltyAimX")
		state.aimY = number("penaltyAimY")
		state.holdAt = number("penaltyHoldAt")
		state.power = number("penaltyPower")
		local outcome = player:GetAttribute("penaltyOutcome")
		state.outcome = if type(outcome) == "string" then outcome else ""
		state.kicksLeft = number("penaltyLeft")
		if state.phase ~= previous then
			lockedX, lockedY = nil, nil
			releasedPower = nil
		end
	end

	-- This visit: the kicks used before it, each kick's result, the boost it earned.
	type KickResult = { goal: boolean, goals: number, kicksLeft: number, boostSeconds: number }
	local scene: BreakawayScene.Scene? = nil
	local takeover = CinemaScreen.takeover()
	local startRev = -1 -- the revision before our start; the visit begins once it changes
	local startedAt = 0
	local usedBefore = 0
	local results: { boolean } = {} -- shown on the pips (each one once its film shows the ball arrive)
	local pending: KickResult? = nil -- the result of the kick in the film, before the ball arrives
	local goalsToday = -1 -- unknown until the first result
	local totalBoost = 0
	local doneAt: number? = nil
	local lastFilm = -1
	local lastStageAt = -1

	local function paintPips(popIndex: number?)
		for index, pip in pips do
			local kick = index - usedBefore
			local result = if kick >= 1 then results[kick] else nil
			-- A filled pip is a kick taken: green a goal, red a miss, grey one taken before this visit.
			if index <= usedBefore then
				pip.stroke.Color = PIP_IDLE
				pip.tile.BackgroundColor3 = PIP_IDLE
			elseif result == true then
				pip.stroke.Color = Style.ui.good
				pip.tile.BackgroundColor3 = Style.ui.good
			elseif result == false then
				pip.stroke.Color = BAD
				pip.tile.BackgroundColor3 = BAD
			else
				local upcoming = kick == #results + 1
				pip.stroke.Color = if upcoming then Style.ui.gold else WHITE
				pip.tile.BackgroundColor3 = Style.ui.panel
			end
			pip.scale.Scale = 1
			if popIndex == index then
				pulse(pip.scale, 0.6)
			end
		end
		rewardLine.Text = if goalsToday > 0
			then string.format(
				"%d goal%s · %s",
				goalsToday,
				if goalsToday == 1 then "" else "s",
				boostText(goalsToday)
			)
			else string.format(
				"Goals earn x%g income: %d / %d / %d min",
				Config.Daily.penaltyMultiplier,
				math.ceil((Config.Daily.penaltyBoostSeconds[1] or 0) / 60),
				math.ceil((Config.Daily.penaltyBoostSeconds[2] or 0) / 60),
				math.ceil((Config.Daily.penaltyBoostSeconds[3] or 0) / 60)
			)
		rewardLine.TextColor3 = if goalsToday > 0 then Style.ui.gold else Style.ui.idle
	end

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

	local function open(kicks: number)
		if scene then
			return
		end
		usedBefore = math.clamp(kickCount - kicks, 0, kickCount)
		table.clear(results)
		pending = nil
		goalsToday = -1
		totalBoost = 0
		doneAt = nil
		lastFilm, lastStageAt = -1, -1
		lockedX, lockedY = nil, nil
		releasedPower = nil
		startRev = revision()
		startedAt = os.clock()
		takeover.take()
		scene = BreakawayScene.new({ penalty = true })
		paintPips(nil)
		hideFeedback()
		world.Enabled = true
		gui.Enabled = true
		Sounds.startAmbience()
		Net.fire("PenaltyStart")
	end

	leave.Activated:Connect(close)

	player:GetAttributeChangedSignal("penaltyRev"):Connect(readServerState)
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
		if state.phase == "aim" and lockedX == nil and now >= state.stageAt then
			lockedX, lockedY = Freekick.aimAt(state, now)
			localStartAt = now + Config.Training.freekickPowerDelay
			pulse(reticleScale, 1.4)
			Net.fire("PenaltyTap", now)
		elseif state.phase == "power" and releasedPower == nil and now >= meterStart() then
			releasedPower = Freekick.powerAt({ holdAt = meterStart() }, now)
			Net.fire("PenaltyTap", now)
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
		end
	end)

	-- The server's answer to a shot: kept until the film shows the ball arrive.
	local function onResult(info: any)
		if scene == nil or type(info) ~= "table" or type(info.goal) ~= "boolean" then
			return
		end
		pending = {
			goal = info.goal,
			goals = if type(info.goals) == "number" then info.goals else 0,
			kicksLeft = if type(info.kicksLeft) == "number" then info.kicksLeft else 0,
			boostSeconds = if type(info.boostSeconds) == "number" then info.boostSeconds else 0,
		}
	end

	-- The ball arrives: the sound, the words and the pip.
	local function arrived()
		local sound = OUTCOME_SOUND[state.outcome]
		if sound then
			Sounds.play(sound)
		end
		local result = pending
		pending = nil
		local goal = state.outcome == "goal"
		local boost = 0
		if result then
			goal = result.goal
			goalsToday = result.goals
			boost = result.boostSeconds
			totalBoost += boost
		end
		table.insert(results, goal)
		paintPips(usedBefore + #results)
		if goal then
			popFeedback(
				OUTCOME_TEXT.goal,
				Style.ui.good,
				if boost > 0 then string.format("+%d min boost", math.ceil(boost / 60)) else ""
			)
		else
			popFeedback(OUTCOME_TEXT[state.outcome] or "MISSED", BAD, "")
		end
	end

	-- The moments of the film: the sounds and the words come when they happen on screen.
	local function filmMoments(t: number)
		local function crossed(at: number): boolean
			return lastFilm < at and t >= at
		end
		if crossed(CONTACT_AT) then
			Sounds.play("kick")
		end
		if crossed(ARRIVE_AT) then
			arrived()
		end
	end

	-- Every frame ------------------------------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		local current = scene
		if current == nil then
			return
		end
		takeover.keep()
		local now = Workspace:GetServerTimeNow()
		local ready = started()
		if not ready and os.clock() - startedAt > START_TIMEOUT then
			close() -- the server never answered
			return
		end
		if ready then
			Penalty.normalize(state, now) -- the next kick comes after the film, without a message
		end
		local phase = if ready then state.phase else "aim"
		local stageAt = if ready then state.stageAt else math.huge

		-- The reticle glides until the tap locks it; the scene draws the rest.
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
				phase = (if phase == "done" then "over" else phase) :: any,
				seed = state.seed,
				kick = state.kick,
				stageAt = stageAt,
				move = Freekick.STEP_OVER,
				aimX = state.aimX,
				aimY = state.aimY,
				holdAt = state.holdAt,
				power = state.power,
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
		local barShare = if filming or phase == "done" then LETTERBOX else 0
		for _, bar in bars do
			bar.Size = UDim2.fromScale(1, barShare)
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

		-- The power meter, and for a moment into the film where the shot stopped it.
		local struck = phase == "shot" and now - state.stageAt < POWER_LINGER
		local power = if phase == "power"
			then releasedPower or Freekick.powerAt({ holdAt = meterStart() }, now)
			elseif struck then state.power
			else 0
		powerBox.Visible = ready and (phase == "power" or struck)
		CinemaScreen.setPower(meter, power, releasedPower ~= nil or struck)
		powerStroke.Color = if releasedPower then Style.ui.good else Style.ui.gold

		-- The texts.
		stepText.Text = if waiting then "GET READY" else (STEP_NAMES[phase] or "")
		local firstOfDay = usedBefore == 0 and #results == 0
		local coachStep = if waiting then "waiting" else phase
		local hint = if firstOfDay then COACH_TEXT[coachStep] else nil
		coachText.Visible = hint ~= nil
		coachText.Text = hint or ""

		-- The day's last kick has played: the reward card (only for kicks taken on this visit).
		if ready and phase == "done" then
			if doneAt == nil then
				doneAt = os.clock()
			elseif os.clock() - doneAt >= DONE_HOLD_SECONDS then
				local took = #results > 0
				local goals = math.max(goalsToday, 0)
				local boost = totalBoost
				close()
				if took then
					PenaltyUi.onFinished(goals, boost)
				end
			end
		end
	end)

	PenaltyUi.open = open
	PenaltyUi.onResult = onResult
end

PenaltyUi.open = function(_kicks: number) end
PenaltyUi.onResult = function(_info: any) end

-- The reward card after the last kick: the shared card that says what the player got.
PenaltyUi.showReward = function(goals: number, boostSeconds: number)
	RewardCard.show({
		title = "PENALTIES DONE",
		big = string.format("%d / %d goals", goals, Config.Daily.penaltyKicks),
		detail = if boostSeconds > 0
			then boostText(goals)
			else string.format(
				"No boost this time. New kicks in %d hours.",
				math.floor(Config.Daily.cooldownSeconds / 3600)
			),
		icon = "kick",
		good = boostSeconds > 0,
	})
end

return PenaltyUi
