--!strict
-- The HUD (docs/PLAN.md, Step 7): one compact column at the top right with the money, the match
-- loading bar and the boost badge, plus the VICTORY text near the top and "+$N" next to the money
-- after each match. There is no goal card: the guide covers the first steps and the player decides
-- the rest. The middle of the screen stays clear. Built in code for the smallest landscape phone
-- first, inside the safe area below the Roblox top bar. It only shows what the server sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local COLUMN_WIDTH = 230
local AWAY_HOLD_SECONDS = 5 -- how long "+$N while you were away" stays
local RESULT_HOLD_SECONDS = 0.65 -- the result texts are fully visible for this long...
local RESULT_FADE_SECONDS = 0.35 -- ...then fade out: 1 second in total, then they are hidden

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

local function stroke(parent: Instance, color: Color3, thickness: number): any
	return new("UIStroke", {
		Name = "Outline",
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function clockText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- A text label with an outline that can be faded out completely. A label's outline (UIStroke) is
-- a separate object: fading only the text leaves the outline on screen, so both are driven here.
local function fadeIn(label: any)
	label.Visible = true
	label.TextTransparency = 0
	label.Outline.Transparency = 0
end

local function fadeOut(label: any)
	local info = TweenInfo.new(RESULT_FADE_SECONDS)
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(label.Outline, info, { Transparency = 1 }):Play()
end

-- Builds the interface. Returns the root ScreenGui (also used by the layout previews).
function Hud.build(parent: Instance): any
	local gui = new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 1,
	}, parent)

	-- One compact column at the top right: the money with the match bar under it, then the boost
	-- badge.
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 92),
		BackgroundTransparency = 1,
	}, gui)

	local moneyRow = new("Frame", {
		Name = "MoneyRow",
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundTransparency = 1,
	}, top)
	local money = new("TextLabel", {
		Name = "Money",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "$0",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 32,
		TextColor3 = Style.ui.money,
	}, moneyRow)
	stroke(money, Style.ui.dark, 2)

	local matchBar = new("Frame", {
		Name = "MatchBar",
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
	}, moneyRow)
	rounded(matchBar, 5)
	stroke(matchBar, Style.ui.idle, 1)
	local matchFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.bar,
		BorderSizePixel = 0,
	}, matchBar)
	rounded(matchFill, 5)

	-- "+$N" sits right next to the money amount (its position is set from the money text width).
	local payout = new("TextLabel", {
		Name = "Payout",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(COLUMN_WIDTH - 90, 6),
		Size = UDim2.fromOffset(110, 28),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.gold,
		Visible = false,
		ZIndex = 3,
	}, top)
	stroke(payout, Style.ui.dark, 2)

	-- The boost badge sits under the match bar, at the right edge of the column.
	local boost = new("TextLabel", {
		Name = "BoostBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 60),
		Size = UDim2.fromOffset(96, 26),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.15,
		Text = "x2 · 5:00",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.gold,
		Visible = false,
	}, top)
	rounded(boost, 8)

	-- The result text sits near the top of the screen, in the middle, and does not take clicks.
	local banner = new("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(420, 54),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 44,
		TextColor3 = Style.ui.good,
		Visible = false,
		Active = false,
	}, gui)
	stroke(banner, Style.ui.dark, 3)

	-- "+$N while you were away", shown once after joining.
	local away = new("TextLabel", {
		Name = "Away",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(420, 32),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 24,
		TextColor3 = Style.ui.gold,
		Visible = false,
		Active = false,
	}, gui)
	stroke(away, Style.ui.dark, 2)

	return gui
end

-- Wires a built HUD to the live state.
function Hud.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Hud.build(playerGui)
	local top = gui.Top
	local money, matchFill, payout = top.MoneyRow.Money, top.MoneyRow.MatchBar.Fill, top.Payout
	local boost, banner = top.BoostBadge, gui.Banner

	-- Money counts up towards the real value; the real value is never delayed.
	local shownCash = State.data.cash
	local function setMoney()
		money.Text = NumberFormat.money(math.floor(shownCash + 0.5))
	end
	setMoney()

	-- The result: VICTORY near the top and +$N next to the money, shown for 1 second ----------
	local resultToken = 0
	Net.on("MatchResult", function(_plot: any, info: any)
		if type(info) ~= "table" or info.ownerUserId ~= player.UserId then
			return
		end
		resultToken += 1
		local token = resultToken

		banner.Text = if info.hatTrick then "HAT-TRICK x2" else "VICTORY"
		banner.TextColor3 = if info.hatTrick then Style.ui.gold else Style.ui.good
		fadeIn(banner)

		payout.Text = "+" .. NumberFormat.money(info.payout)
		-- Right next to the money text, which is right aligned in the column.
		payout.Position = UDim2.fromOffset(COLUMN_WIDTH - money.TextBounds.X - 8, 6)
		fadeIn(payout)

		task.delay(RESULT_HOLD_SECONDS, function()
			if token ~= resultToken then
				return -- a newer result is showing
			end
			fadeOut(banner)
			fadeOut(payout)
			task.delay(RESULT_FADE_SECONDS + 0.05, function()
				if token == resultToken then
					banner.Visible = false
					payout.Visible = false
				end
			end)
		end)
	end)

	-- Offline earnings: the server sets the attributes before the profile counts as loaded.
	local awayLabel = gui.Away
	local function showAway()
		local earned = player:GetAttribute("offlineEarned")
		local seconds = player:GetAttribute("offlineSeconds")
		if type(earned) ~= "number" or type(seconds) ~= "number" or earned <= 0 then
			return
		end
		player:SetAttribute("offlineEarned", nil) -- shown once
		local hours, minutes = seconds // 3600, (seconds % 3600) // 60
		local span = if hours > 0 then string.format("%dh %dm", hours, minutes) else minutes .. "m"
		awayLabel.Text = "+"
			.. NumberFormat.money(earned)
			.. " while you were away ("
			.. span
			.. ")"
		fadeIn(awayLabel)
		task.delay(AWAY_HOLD_SECONDS, function()
			fadeOut(awayLabel)
			task.delay(RESULT_FADE_SECONDS + 0.05, function()
				awayLabel.Visible = false
			end)
		end)
	end
	showAway()
	player:GetAttributeChangedSignal("offlineEarned"):Connect(showAway)

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
			local multiplier = player:GetAttribute("boostMultiplier")
			local shown = if type(multiplier) == "number" then multiplier else 2
			boost.Text = string.format("x%g · %s", shown, clockText(boostEnds - now))
		else
			boost.Visible = false
		end
	end)
end

return Hud
