--!strict
-- The HUD (docs/PLAN.md, Step 7): the money label with the match loading bar, the one-line "Next
-- goal" row, the boost badge, and the VICTORY text with "+$N" after each match. Built in code for
-- the smallest landscape phone first, inside the safe area below the Roblox top bar. It only
-- shows what the server sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Goals = require(ReplicatedStorage.Shared.Goals)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local Hud = {}

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

local function stroke(
	parent: Instance,
	color: Color3,
	thickness: number,
	transparency: number?
): any
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function clockText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Builds the interface. Returns the root ScreenGui (also used by the layout previews).
function Hud.build(parent: Instance): any
	local gui = new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 1,
	}, parent)

	-- Top column: money row, then the goal row.
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(300, 100),
		BackgroundTransparency = 1,
	}, gui)

	local moneyRow = new("Frame", {
		Name = "MoneyRow",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	}, top)
	local money = new("TextLabel", {
		Name = "Money",
		Size = UDim2.new(0, 172, 1, 0),
		BackgroundTransparency = 1,
		Text = "$0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 32,
		TextColor3 = Style.ui.money,
	}, moneyRow)
	stroke(money, Style.ui.dark, 2)

	local matchBar = new("Frame", {
		Name = "MatchBar",
		Position = UDim2.new(0, 178, 0.5, -6),
		Size = UDim2.fromOffset(118, 12),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
	}, moneyRow)
	rounded(matchBar, 6)
	stroke(matchBar, Style.ui.idle, 1)
	local matchFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.bar,
		BorderSizePixel = 0,
	}, matchBar)
	rounded(matchFill, 6)

	local payout = new("TextLabel", {
		Name = "Payout",
		Position = UDim2.fromOffset(4, 36),
		Size = UDim2.fromOffset(170, 26),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.gold,
		TextTransparency = 1,
		ZIndex = 3,
	}, top)
	stroke(payout, Style.ui.dark, 2)

	local goalRow = new("Frame", {
		Name = "GoalRow",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.15,
	}, top)
	rounded(goalRow, 8)
	stroke(goalRow, Style.ui.idle, 1)
	new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.text,
	}, goalRow)
	local goalBar = new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(10, 31),
		Size = UDim2.new(1, -104, 0, 10),
		BackgroundColor3 = Style.ui.dark,
		BorderSizePixel = 0,
	}, goalRow)
	rounded(goalBar, 5)
	local goalFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.money,
		BorderSizePixel = 0,
	}, goalBar)
	rounded(goalFill, 5)
	new("TextLabel", {
		Name = "Amount",
		Position = UDim2.new(1, -90, 0, 26),
		Size = UDim2.fromOffset(80, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Style.ui.idle,
	}, goalRow)

	-- The boost badge sits at the right edge under the top bar.
	local boost = new("TextLabel", {
		Name = "BoostBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(96, 28),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.15,
		Text = "x2 · 5:00",
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.gold,
		Visible = false,
	}, gui)
	rounded(boost, 8)

	-- The big result text sits in the middle of the screen and does not take clicks.
	local banner = new("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 80),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 56,
		TextColor3 = Style.ui.good,
		TextTransparency = 1,
		Active = false,
	}, gui)
	stroke(banner, Style.ui.dark, 3)

	return gui
end

-- Wires a built HUD to the live state.
function Hud.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Hud.build(playerGui)
	local top = gui.Top
	local money, matchFill, payout = top.MoneyRow.Money, top.MoneyRow.MatchBar.Fill, top.Payout
	local goalRow = top.GoalRow
	local goalLabel, goalFill, goalAmount = goalRow.Label, goalRow.Bar.Fill, goalRow.Amount
	local goalStroke = goalRow.UIStroke
	local boost, banner = gui.BoostBadge, gui.Banner

	-- Money counts up towards the real value; the real value is never delayed.
	local shownCash = State.data.cash
	local function setMoney()
		money.Text = NumberFormat.money(math.floor(shownCash + 0.5))
	end
	setMoney()

	-- The goal row ----------------------------------------------------------------------
	local wasAffordable = false
	local pulseToken = 0
	local function refreshGoal()
		local goal = Goals.next(State.data, State.hasPlot())
		local affordable = goal.cost ~= nil and State.data.cash >= goal.cost
		if goal.kind == "stadium" and affordable then
			goalLabel.Text = "Stadium upgrade available!"
		elseif affordable then
			goalLabel.Text = "Next goal: " .. goal.label .. " - ready!"
		else
			goalLabel.Text = "Next goal: " .. goal.label
		end
		if goal.cost then
			goalFill.Size = UDim2.fromScale(math.clamp(State.data.cash / goal.cost, 0, 1), 1)
			goalAmount.Text = NumberFormat.money(State.data.cash)
				.. " / "
				.. NumberFormat.money(goal.cost)
		else
			goalFill.Size = UDim2.fromScale(0, 1)
			goalAmount.Text = ""
		end
		goalFill.BackgroundColor3 = if affordable then Style.ui.good else Style.ui.money

		-- It glows brightly when it becomes affordable: a few pulses, then steady, no sound.
		if affordable and not wasAffordable then
			pulseToken += 1
			local token = pulseToken
			goalStroke.Color = Style.ui.good
			task.spawn(function()
				for _ = 1, 3 do
					if token ~= pulseToken then
						return
					end
					TweenService:Create(goalStroke, TweenInfo.new(0.35), { Thickness = 5 }):Play()
					task.wait(0.4)
					TweenService:Create(goalStroke, TweenInfo.new(0.35), { Thickness = 2 }):Play()
					task.wait(0.4)
				end
				goalStroke.Thickness = 3
			end)
		elseif not affordable then
			pulseToken += 1
			goalStroke.Color = Style.ui.idle
			goalStroke.Thickness = 1
		end
		wasAffordable = affordable
	end
	State.onChange(function()
		refreshGoal()
	end)
	refreshGoal()

	-- The result: VICTORY or HAT-TRICK, and +$N under the money label ---------------------
	Net.on("MatchResult", function(_plot: any, info: any)
		if type(info) ~= "table" or info.ownerUserId ~= player.UserId then
			return
		end
		banner.Text = if info.hatTrick then "HAT-TRICK x2" else "VICTORY"
		banner.TextColor3 = if info.hatTrick then Style.ui.gold else Style.ui.good
		banner.TextTransparency = 0
		banner.Position = UDim2.fromScale(0.5, 0.36)
		TweenService
			:Create(banner, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.3),
			})
			:Play()

		payout.Text = "+" .. NumberFormat.money(info.payout)
		payout.TextTransparency = 0
		payout.Position = UDim2.fromOffset(4, 36)
		TweenService
			:Create(payout, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				Position = UDim2.fromOffset(4, 24),
			})
			:Play()
	end)

	-- Every frame: the money counter, the match bar and the boost badge ------------------
	RunService.RenderStepped:Connect(function(dt: number)
		local target = State.data.cash
		if shownCash ~= target then
			local difference = target - shownCash
			if math.abs(difference) < 0.5 then
				shownCash = target
			else
				shownCash += difference * math.min(1, dt * 7)
			end
			setMoney()
		end

		local now = Workspace:GetServerTimeNow()
		local endsAt = player:GetAttribute("matchEndsAt")
		local duration = player:GetAttribute("matchDuration")
		if
			type(endsAt) == "number"
			and type(duration) == "number"
			and endsAt > 0
			and duration > 0
		then
			matchFill.Size = UDim2.fromScale(math.clamp(1 - (endsAt - now) / duration, 0, 1), 1)
		else
			matchFill.Size = UDim2.fromScale(0, 1)
		end

		local boostEnds = player:GetAttribute("boostEndsAt")
		if type(boostEnds) == "number" and boostEnds > now then
			boost.Visible = true
			boost.Text = "x2 · " .. clockText(boostEnds - now)
		else
			boost.Visible = false
		end
	end)
end

return Hud
