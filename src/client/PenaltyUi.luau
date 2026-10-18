--!strict
-- The penalty kick screen (docs/PLAN.md, Step 7): a goal with a keeper at the top and five targets
-- at the bottom (the four corners and the middle). Tapping a target sends the aim; the server rolls
-- the kick, and when the answer arrives the ball flies to the target while the keeper dives to the
-- zone the server chose. After the last kick the screen closes and a reward card shows what the
-- goals earned. The animation is only the show: with reduced motion it is skipped.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 360, 330
local FIELD_W, FIELD_H = 340, 140
local BALL_START = Vector2.new(170, 124)
local KEEPER_REST = Vector2.new(170, 70)
local BALL_SECONDS = 0.5
local DIVE_SECONDS = 0.4
local RESULT_SECONDS = 1.1 -- how long a kick result shows before the next kick
local REPLY_TIMEOUT = 3 -- the targets come back if the server never answers
local CLOSE_AFTER_LAST_SECONDS = 1.4
local REWARD_SECONDS = 5

-- Where each target is inside the field frame (the goal is x 40 to 300, y 6 to 100).
local TARGETS: { [string]: Vector2 } = {
	topLeft = Vector2.new(80, 26),
	topRight = Vector2.new(260, 26),
	bottomLeft = Vector2.new(80, 80),
	bottomRight = Vector2.new(260, 80),
	center = Vector2.new(170, 54),
}

local PenaltyUi = {}

local function isZone(name: string): boolean
	return (TARGETS :: { [string]: Vector2? })[name] ~= nil
end

-- Set by DailyUi: called with (goals, boostSeconds) after the last kick.
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

local function at(position: Vector2): UDim2
	return UDim2.fromOffset(position.X, position.Y)
end

-- A blocky goalkeeper made of frames; its pivot is the middle of the body.
local function buildKeeper(parent: Instance): Frame
	local keeper = new("Frame", {
		Name = "Keeper",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(KEEPER_REST),
		Size = UDim2.fromOffset(44, 56),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, parent)
	local kit = Color3.fromRGB(240, 200, 50)
	local skin = Color3.fromRGB(235, 200, 160)
	local function part(x: number, y: number, w: number, h: number, color: Color3)
		local frame = new("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, keeper)
		rounded(frame, 3)
	end
	part(15, 0, 14, 14, skin) -- head
	part(12, 15, 20, 22, kit) -- body
	part(0, 17, 44, 7, kit) -- arms
	part(12, 38, 8, 18, Color3.fromRGB(40, 50, 90)) -- legs
	part(24, 38, 8, 18, Color3.fromRGB(40, 50, 90))
	return keeper
end

function PenaltyUi.init()
	local gui = new("ScreenGui", {
		Name = "Penalty",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		IgnoreGuiInset = true,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local panel = new("Frame", {
		Name = "PenaltyPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.05,
	}, gui)
	rounded(panel, 16)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, panel)
	local scale = new("UIScale", {}, panel)

	local title = new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -70, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.text,
	}, panel)
	local close = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(44, 34),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.3,
		Text = "X",
		Font = Style.font,
		TextSize = 18,
		TextColor3 = Style.ui.text,
	}, panel)
	rounded(close, 8)

	-- The goal, the keeper and the ball ------------------------------------------------------
	local field = new("Frame", {
		Name = "Field",
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.fromOffset(FIELD_W, FIELD_H),
		BackgroundColor3 = Color3.fromRGB(60, 130, 80),
		ClipsDescendants = true,
	}, panel)
	rounded(field, 10)
	local white = Color3.fromRGB(245, 245, 245)
	new("Frame", {
		Name = "Net",
		Position = UDim2.fromOffset(40, 6),
		Size = UDim2.fromOffset(260, 94),
		BackgroundColor3 = Color3.fromRGB(30, 60, 45),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, field)
	new("Frame", {
		Position = UDim2.fromOffset(38, 4),
		Size = UDim2.fromOffset(264, 4),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, field)
	new("Frame", {
		Position = UDim2.fromOffset(38, 4),
		Size = UDim2.fromOffset(4, 98),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, field)
	new("Frame", {
		Position = UDim2.fromOffset(298, 4),
		Size = UDim2.fromOffset(4, 98),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, field)
	local keeper = buildKeeper(field)
	local ball = new("Frame", {
		Name = "Ball",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(BALL_START),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = white,
		ZIndex = 4,
	}, field)
	rounded(ball, 11)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, ball)

	local result = new("TextLabel", {
		Name = "Result",
		Position = UDim2.fromOffset(10, 190),
		Size = UDim2.fromOffset(FIELD_W, 28),
		BackgroundTransparency = 1,
		Text = "Pick a target",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.gold,
	}, panel)
	new(
		"UIStroke",
		{ Color = Style.ui.dark, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual },
		result
	)

	-- The target pad: four corners and the middle, like the goal in front of the player.
	local pad = new("Frame", {
		Name = "Pad",
		Position = UDim2.fromOffset(30, 222),
		Size = UDim2.fromOffset(300, 98),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.3,
	}, panel)
	rounded(pad, 30)
	local buttons: { [string]: TextButton } = {}
	local layout: { [string]: { number } } = {
		topLeft = { 14, 8, 88, 40 },
		topRight = { 198, 8, 88, 40 },
		bottomLeft = { 14, 50, 88, 40 },
		bottomRight = { 198, 50, 88, 40 },
		center = { 110, 29, 80, 40 },
	}
	for zone, box in layout do
		local button = new("TextButton", {
			Name = zone,
			Position = UDim2.fromOffset(box[1], box[2]),
			Size = UDim2.fromOffset(box[3], box[4]),
			BackgroundColor3 = Color3.fromRGB(70, 80, 115),
			Text = "",
			AutoButtonColor = true,
		}, pad)
		rounded(button, 10)
		new(
			"UIStroke",
			{ Color = white, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			button
		)
		buttons[zone] = button
	end

	-- State ------------------------------------------------------------------------------------
	local kicksLeft = 0
	local totalBoost = 0
	local waiting = false
	local token = 0
	local tweens: { Tween } = {}

	local function fitScale()
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			scale.Scale = math.min(1, size.X / (PANEL_W + 30), size.Y / (PANEL_H + 20))
		end
	end

	local function stopTweens()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
	end

	local function setButtons(enabled: boolean)
		for _, button in buttons do
			button.Active = enabled
			button.AutoButtonColor = enabled
			button.BackgroundTransparency = if enabled then 0 else 0.5
		end
	end

	local function resetScene()
		stopTweens()
		ball.Position = at(BALL_START)
		ball.Size = UDim2.fromOffset(22, 22)
		ball.Visible = true
		keeper.Position = at(KEEPER_REST)
		keeper.Rotation = 0
		for _, button in buttons do
			button.BackgroundColor3 = Color3.fromRGB(70, 80, 115)
		end
	end

	local function showKicksLeft()
		title.Text = string.format("Penalty kicks · %d left", kicksLeft)
	end

	local function closePanel()
		token += 1
		stopTweens()
		gui.Enabled = false
		waiting = false
	end
	close.Activated:Connect(closePanel)

	local function play(
		tweenObject: Instance,
		seconds: number,
		goal: { [string]: any },
		style: Enum.EasingStyle
	)
		local tween = TweenService:Create(
			tweenObject,
			TweenInfo.new(seconds, style, Enum.EasingDirection.Out),
			goal
		)
		table.insert(tweens, tween)
		tween:Play()
	end

	-- Where the ball ends up: inside the goal for a goal or a save, outside it when it goes wide.
	local function ballEnd(aim: string, wide: boolean): Vector2
		local target = TARGETS[aim]
		if not wide then
			return target
		end
		if aim == "center" then
			return Vector2.new(target.X + 30, -30)
		end
		local side = if target.X < 170 then -1 else 1
		local up = if target.Y < 50 then -1 else 0
		return Vector2.new(target.X + side * 70, target.Y + up * 55 + 10)
	end

	local function dive(zone: string)
		local target = TARGETS[zone]
		local tilt = if zone == "center" then 0 elseif target.X < 170 then -65 else 65
		if zone == "topLeft" or zone == "topRight" then
			tilt = tilt * 1.2
		end
		play(
			keeper,
			DIVE_SECONDS,
			{ Position = at(target), Rotation = tilt },
			Enum.EasingStyle.Quad
		)
	end

	local function openPanel(kicks: number)
		token += 1
		kicksLeft = kicks
		totalBoost = 0
		waiting = false
		resetScene()
		setButtons(true)
		showKicksLeft()
		result.Text = "Pick a target"
		result.TextColor3 = Style.ui.gold
		fitScale()
		gui.Enabled = true
	end

	local function sendKick(zone: string)
		if waiting or not gui.Enabled or kicksLeft <= 0 then
			return
		end
		waiting = true
		setButtons(false)
		local myToken = token
		Net.fire("PenaltyKick", zone)
		task.delay(REPLY_TIMEOUT, function()
			if waiting and token == myToken then
				waiting = false
				setButtons(true)
			end
		end)
	end
	for zone, button in buttons do
		button.Activated:Connect(function()
			sendKick(zone)
		end)
	end

	-- The server's answer: fly the ball, dive the keeper, say what happened ---------------------
	local function onResult(info: any)
		if type(info) ~= "table" or type(info.aim) ~= "string" or not isZone(info.aim) then
			return
		end
		if not gui.Enabled then
			return
		end
		token += 1
		local myToken = token
		waiting = false
		kicksLeft = if type(info.kicksLeft) == "number" then info.kicksLeft else 0
		totalBoost += if type(info.boostSeconds) == "number" then info.boostSeconds else 0
		showKicksLeft()
		resetScene()
		setButtons(false)
		buttons[info.aim].BackgroundColor3 = Style.ui.gold
		result.Text = ""

		local scored = info.goal == true
		local wide = info.wide == true
		local keeperZone = if type(info.keeper) == "string" and TARGETS[info.keeper]
			then info.keeper
			else "center"
		local endPoint = ballEnd(info.aim, wide)
		local reduced = GuiService.ReducedMotionEnabled

		local function landed()
			if token ~= myToken then
				return
			end
			if scored then
				result.Text = "GOAL!"
				result.TextColor3 = Style.ui.good
			else
				result.Text = if wide then "Just wide!" else "Saved!"
				result.TextColor3 = Style.ui.bad
			end
			if kicksLeft > 0 then
				task.delay(RESULT_SECONDS, function()
					if token == myToken then
						resetScene()
						setButtons(true)
						result.Text = "Pick a target"
						result.TextColor3 = Style.ui.gold
					end
				end)
				return
			end
			-- The last kick: close the screen and show the reward.
			local goals = if type(info.goals) == "number" then info.goals else 0
			task.delay(RESULT_SECONDS + CLOSE_AFTER_LAST_SECONDS, function()
				if token == myToken then
					closePanel()
					PenaltyUi.onFinished(goals, totalBoost)
				end
			end)
		end

		if reduced then
			ball.Position = at(endPoint)
			keeper.Position = at(TARGETS[keeperZone])
			landed()
			return
		end
		play(
			ball,
			BALL_SECONDS,
			{ Position = at(endPoint), Size = UDim2.fromOffset(15, 15) },
			Enum.EasingStyle.Quad
		)
		task.delay(0.12, function()
			if token == myToken then
				dive(keeperZone)
			end
		end)
		task.delay(BALL_SECONDS, landed)
	end

	PenaltyUi.open = openPanel
	PenaltyUi.onResult = onResult
end

PenaltyUi.open = function(_kicks: number) end
PenaltyUi.onResult = function(_info: any) end

-- The reward card after the last kick ---------------------------------------------------------
function PenaltyUi.initReward()
	local gui = new("ScreenGui", {
		Name = "PenaltyReward",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = true,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(340, 160),
		BackgroundColor3 = Style.ui.panel,
	}, gui)
	rounded(card, 18)
	local stroke = new("UIStroke", { Color = Style.ui.gold, Thickness = 3 }, card)
	local cardScale = new("UIScale", {}, card)
	new("TextLabel", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundTransparency = 1,
		Text = "PENALTIES DONE",
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.idle,
	}, card)
	local big = new("TextLabel", {
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 0, 48),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 40,
		TextColor3 = Style.ui.gold,
	}, card)
	local detail = new("TextLabel", {
		Position = UDim2.fromOffset(10, 94),
		Size = UDim2.new(1, -20, 0, 56),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.text,
	}, card)

	local token = 0
	PenaltyUi.showReward = function(goals: number, boostSeconds: number)
		token += 1
		local myToken = token
		big.Text = string.format("%d / 3 goals", goals)
		if boostSeconds > 0 then
			detail.Text =
				string.format("Reward: x1.5 income for %d min", math.ceil(boostSeconds / 60))
			stroke.Color = Style.ui.gold
		else
			detail.Text = "No boost this time. New kicks in 20 hours."
			stroke.Color = Style.ui.idle
		end
		local camera = Workspace.CurrentCamera
		local fit = 1
		if camera then
			fit = math.min(1, camera.ViewportSize.X / 380, camera.ViewportSize.Y / 200)
		end
		gui.Enabled = true
		if GuiService.ReducedMotionEnabled then
			cardScale.Scale = fit
		else
			cardScale.Scale = fit * 0.6
			TweenService:Create(
				cardScale,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = fit }
			):Play()
		end
		task.delay(REWARD_SECONDS, function()
			if token == myToken then
				gui.Enabled = false
			end
		end)
	end
	card.Active = true
	local tap = new(
		"TextButton",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 10 },
		card
	)
	tap.Activated:Connect(function()
		token += 1
		gui.Enabled = false
	end)
end

PenaltyUi.showReward = function(_goals: number, _boostSeconds: number) end

return PenaltyUi
