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

local Icons = require(script.Parent.Icons)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local COLUMN_WIDTH = 230
local BOX_HEIGHT = 44
local BADGE_SIZE = 30
local TP_GAIN_HOLD_SECONDS = 1.2 -- how long "+N TP" stays after the last gain
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

-- A stat box (money, training points): dark, a coloured outline, a round badge on the left and the
-- value on the right. Both boxes use it, so they look like one family. Returns the box and the value.
local function statBox(
	parent: Instance,
	name: string,
	y: number,
	accent: Color3,
	badgeText: string,
	iconName: string,
	valueName: string
): (any, any)
	local box = new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, BOX_HEIGHT),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.05,
	}, parent)
	rounded(box, 12)
	new("UIStroke", {
		Color = accent,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, box)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(175, 180, 200)),
		Rotation = 90,
	}, box)
	local badge = new("Frame", {
		Name = "Badge",
		Position = UDim2.fromOffset(7, (BOX_HEIGHT - BADGE_SIZE) / 2),
		Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE),
		BackgroundColor3 = accent,
		ZIndex = 2,
	}, box)
	rounded(badge, BADGE_SIZE / 2)
	local imageId = Icons.id(iconName)
	if imageId ~= "" then
		new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = imageId,
			ZIndex = 3,
		}, badge)
	else
		new("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = badgeText,
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Style.ui.dark,
			ZIndex = 3,
		}, badge)
	end
	local value = new("TextLabel", {
		Name = valueName,
		Position = UDim2.fromOffset(BADGE_SIZE + 12, 0),
		Size = UDim2.new(1, -(BADGE_SIZE + 24), 1, 0),
		BackgroundTransparency = 1,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 26,
		TextColor3 = accent,
		ZIndex = 2,
	}, box)
	stroke(value, Style.ui.dark, 2)
	return box, value
end

-- Builds the interface. Returns the root ScreenGui (also used by the layout previews).
function Hud.build(parent: Instance): any
	local gui = new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 1,
	}, parent)

	-- One compact column at the top right: the money box, the match bar, the TP box and the boost
	-- badge. Both boxes share one design; the middle of the screen stays clear.
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 170),
		BackgroundTransparency = 1,
	}, gui)

	local _, money = statBox(top, "MoneyRow", 0, Style.ui.money, "$", "cash", "Money")
	money.Text = "$0"

	local matchBar = new("Frame", {
		Name = "MatchBar",
		Position = UDim2.fromOffset(0, BOX_HEIGHT + 5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
	}, top)
	rounded(matchBar, 4)
	stroke(matchBar, Style.ui.idle, 1)
	local matchFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.ui.bar,
		BorderSizePixel = 0,
	}, matchBar)
	rounded(matchFill, 4)

	-- Training points: same design as the money, always shown (the points are farmed from the start).
	local _, tpValue = statBox(top, "Tp", BOX_HEIGHT + 20, Style.ui.bar, "TP", "tp", "Value")
	tpValue.Text = "0"

	-- "+$N" sits right next to the money amount (its position is set from the money text width).
	local payout = new("TextLabel", {
		Name = "Payout",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(COLUMN_WIDTH - 90, 8),
		Size = UDim2.fromOffset(110, 28),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.gold,
		Visible = false,
		ZIndex = 4,
	}, top)
	stroke(payout, Style.ui.dark, 2)

	-- The boost badge sits under the TP box, at the right edge of the column.
	local boost = new("TextLabel", {
		Name = "BoostBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2 * BOX_HEIGHT + 28),
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

	-- "+N TP" under the TP badge whenever training points come in (like "+$N" next to the money).
	local tpGain = new("TextLabel", {
		Name = "TpGain",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2 * BOX_HEIGHT + 24),
		Size = UDim2.fromOffset(120, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.bar,
		Visible = false,
		ZIndex = 3,
	}, top)
	stroke(tpGain, Style.ui.dark, 2)

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
	local money, matchFill, payout = top.MoneyRow.Money, top.MatchBar.Fill, top.Payout
	local boost, banner = top.BoostBadge, gui.Banner
	local tpValue = top.Tp.Value

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
		payout.Position = UDim2.fromOffset(COLUMN_WIDTH - money.TextBounds.X - 22, 8)
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

	-- Training points coming in: the gains of the last moment add up in one "+N TP" next to the badge.
	local tpGain = top.TpGain
	local lastTp: number? = nil
	local pendingTp = 0
	local tpToken = 0
	State.onChange(function()
		if not State.loaded then
			return
		end
		local now = State.data.tp
		local before = lastTp
		lastTp = now
		if before == nil or now <= before then
			return
		end
		pendingTp += now - before
		tpToken += 1
		local token = tpToken
		tpGain.Text = "+" .. NumberFormat.short(pendingTp) .. " TP"
		fadeIn(tpGain)
		task.delay(TP_GAIN_HOLD_SECONDS, function()
			if token ~= tpToken then
				return -- a newer gain is showing
			end
			pendingTp = 0
			fadeOut(tpGain)
			task.delay(RESULT_FADE_SECONDS + 0.05, function()
				if token == tpToken then
					tpGain.Visible = false
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

		tpValue.Text = NumberFormat.short(State.data.tp)

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
