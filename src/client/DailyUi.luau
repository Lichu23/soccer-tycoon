--!strict
-- The daily return on screen (docs/PLAN.md, Step 7): two icons at the left edge below the top bar
-- (the free case and the penalty kicks), and the penalty kick screen. A ready icon gets a small gold
-- dot and a soft glow that stops pulsing after a few seconds; no sound, no red counter. A waiting
-- icon is dimmed and a tap says how long is left. The server judges every claim and kick; this
-- only sends the tap and shows the answer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Arrow = require(script.Parent.Arrow)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local ICON_SIZE = 52
local ICON_GAP = 8
local GLOW_SECONDS = 4 -- how long a newly ready icon pulses
local TOAST_SECONDS = 2.5
local PRIZE_SECONDS = 4
local GUIDE_SECONDS = 15
local RESULT_SECONDS = 1.4 -- how long a kick result shows before the next kick
local REPLY_TIMEOUT = 3 -- the kick buttons come back if the server never answers
local CLOSE_AFTER_LAST_SECONDS = 4

local ZONE_LABELS: { [string]: string } = {
	topLeft = "Top left",
	topCenter = "Top middle",
	topRight = "Top right",
	bottomLeft = "Low left",
	bottomCenter = "Low middle",
	bottomRight = "Low right",
}

local DailyUi = {}

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

local function outline(parent: Instance, color: Color3, thickness: number): any
	return new("UIStroke", {
		Name = "Outline",
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

type Icon = {
	button: TextButton,
	dot: Frame,
	glow: UIStroke,
	status: string,
	glowUntil: number,
}

local function buildIcon(parent: Instance, name: string, text: string, order: number): Icon
	local button = new("TextButton", {
		Name = name,
		Position = UDim2.fromOffset(8, 8 + (order - 1) * (ICON_SIZE + ICON_GAP)),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundColor3 = Style.ui.panel,
		Text = text,
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.text,
		AutoButtonColor = false,
		Visible = false,
	}, parent)
	rounded(button, 12)
	local glow = outline(button, Style.ui.gold, 2)
	glow.Transparency = 1
	local dot = new("Frame", {
		Name = "ReadyDot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Style.ui.gold,
		Visible = false,
	}, button)
	rounded(dot, 7)
	outline(dot, Style.ui.dark, 2)
	return { button = button, dot = dot, glow = glow, status = "locked", glowUntil = 0 }
end

-- Paints an icon for its status. A newly ready icon pulses for a few seconds, then stays still.
local function paintIcon(icon: Icon, status: string)
	if icon.status == status then
		return
	end
	local becameReady = status == "ready" and icon.status ~= "ready"
	icon.status = status
	icon.button.Visible = status ~= "locked"
	icon.dot.Visible = status == "ready"
	icon.button.BackgroundTransparency = if status == "ready" then 0.1 else 0.55
	icon.button.TextColor3 = if status == "ready" then Style.ui.text else Style.ui.idle
	if becameReady then
		icon.glowUntil = os.clock() + GLOW_SECONDS
	elseif status ~= "ready" then
		icon.glowUntil = 0
		icon.glow.Transparency = 1
	end
end

local function readyAt(attribute: string): number
	local value = player:GetAttribute(attribute)
	return if type(value) == "number" then value else 0
end

local function iconStatus(attribute: string): string
	local unlocked = player:GetAttribute("dailyUnlocked") == true
	return DailyInfo.status(unlocked, readyAt(attribute), Workspace:GetServerTimeNow())
end

-- A short line under the icons ("Ready in 3 h 20 min").
local function buildToast(parent: Instance): TextLabel
	local toast = new("TextLabel", {
		Name = "Toast",
		Position = UDim2.fromOffset(8 + ICON_SIZE + 8, 8),
		Size = UDim2.fromOffset(230, 30),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		Text = "",
		Font = Style.font,
		TextSize = 16,
		TextColor3 = Style.ui.text,
		Visible = false,
		Active = false,
	}, parent)
	rounded(toast, 8)
	return toast
end

-- The result of the free case, near the top in the middle (the HUD banners use the same area).
local function buildPrize(parent: Instance): TextLabel
	local prize = new("TextLabel", {
		Name = "Prize",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(460, 40),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 30,
		TextColor3 = Style.ui.gold,
		Visible = false,
		Active = false,
	}, parent)
	outline(prize, Style.ui.dark, 2.5)
	return prize
end

type Panel = {
	frame: Frame,
	title: TextLabel,
	result: TextLabel,
	zones: { [string]: TextButton },
	close: TextButton,
}

local ZONE_ORDER = {
	{ "topLeft", "topCenter", "topRight" },
	{ "bottomLeft", "bottomCenter", "bottomRight" },
}
local ZONE_W, ZONE_H, ZONE_GAP = 96, 56, 6

local function buildPanel(parent: Instance): Panel
	local width = ZONE_W * 3 + ZONE_GAP * 4 + 12 -- the goal frame has a 6 px margin
	local frame = new("Frame", {
		Name = "PenaltyPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 214),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, parent)
	rounded(frame, 14)
	outline(frame, Style.ui.dark, 2)

	local title = new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -64, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.text,
	}, frame)

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
	}, frame)
	rounded(close, 8)

	-- The goal: a white frame with the six aim zones inside it.
	local goal = new("Frame", {
		Name = "Goal",
		Position = UDim2.fromOffset(6, 44),
		Size = UDim2.fromOffset(width - 12, ZONE_H * 2 + ZONE_GAP * 3),
		BackgroundColor3 = Color3.fromRGB(70, 110, 170),
		BackgroundTransparency = 0.5,
	}, frame)
	outline(goal, Color3.fromRGB(245, 245, 245), 3)

	local zones: { [string]: TextButton } = {}
	for row, names in ZONE_ORDER do
		for column, zone in names do
			local button = new("TextButton", {
				Name = zone,
				Position = UDim2.fromOffset(
					ZONE_GAP + (column - 1) * (ZONE_W + ZONE_GAP),
					ZONE_GAP + (row - 1) * (ZONE_H + ZONE_GAP)
				),
				Size = UDim2.fromOffset(ZONE_W, ZONE_H),
				BackgroundColor3 = Style.ui.dark,
				BackgroundTransparency = 0.35,
				Text = ZONE_LABELS[zone],
				Font = Style.font,
				TextSize = 15,
				TextColor3 = Style.ui.text,
				AutoButtonColor = true,
			}, goal)
			rounded(button, 8)
			zones[zone] = button
		end
	end

	local result = new("TextLabel", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 34),
		BackgroundTransparency = 1,
		Text = "Pick a corner",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.gold,
	}, frame)
	outline(result, Style.ui.dark, 2)
	return { frame = frame, title = title, result = result, zones = zones, close = close }
end

-- "x1.5 income for 10 min" for the boost the kicks earned.
local function boostText(seconds: number): string
	return string.format("x1.5 income for %d min", math.ceil(seconds / 60))
end

function DailyUi.init()
	local gui = new("ScreenGui", {
		Name = "Daily",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
	}, player:WaitForChild("PlayerGui"))

	local caseIcon = buildIcon(gui, "CaseIcon", "CASE", 1)
	local kickIcon = buildIcon(gui, "KickIcon", "KICK", 2)
	local toast = buildToast(gui)
	local prize = buildPrize(gui)
	local panel = buildPanel(gui)

	-- A line next to the icons, replaced by the next one -------------------------------------
	local toastToken = 0
	local function showToast(text: string)
		toastToken += 1
		local token = toastToken
		toast.Text = text
		toast.Visible = true
		task.delay(TOAST_SECONDS, function()
			if token == toastToken then
				toast.Visible = false
			end
		end)
	end

	local prizeToken = 0
	local function showPrize(text: string)
		prizeToken += 1
		local token = prizeToken
		prize.Text = text
		prize.Visible = true
		task.delay(PRIZE_SECONDS, function()
			if token == prizeToken then
				prize.Visible = false
			end
		end)
	end

	-- The penalty screen ---------------------------------------------------------------------
	local kicksLeft = 0
	local totalBoost = 0
	local waiting = false -- a kick was sent and the answer has not come yet
	local panelToken = 0

	local function setZonesEnabled(enabled: boolean)
		for _, button in panel.zones do
			button.Active = enabled
			button.AutoButtonColor = enabled
		end
	end

	local function resetZones()
		for _, button in panel.zones do
			button.BackgroundColor3 = Style.ui.dark
			button.BackgroundTransparency = 0.35
			button.Text = ZONE_LABELS[button.Name]
		end
	end

	local function closePanel()
		panelToken += 1
		panel.frame.Visible = false
		waiting = false
	end

	local function showKicksLeft()
		panel.title.Text = string.format("Penalty kicks · %d left", kicksLeft)
	end

	local function openPanel(kicks: number)
		panelToken += 1
		kicksLeft = kicks
		totalBoost = 0
		waiting = false
		resetZones()
		setZonesEnabled(true)
		showKicksLeft()
		panel.result.Text = "Pick a corner"
		panel.result.TextColor3 = Style.ui.gold
		panel.frame.Visible = true
	end

	local function sendKick(zone: string)
		if waiting or not panel.frame.Visible or kicksLeft <= 0 then
			return
		end
		waiting = true
		setZonesEnabled(false)
		local token = panelToken
		Net.fire("PenaltyKick", zone)
		task.delay(REPLY_TIMEOUT, function()
			if waiting and token == panelToken then
				waiting = false
				setZonesEnabled(true)
			end
		end)
	end

	for zone, button in panel.zones do
		button.Activated:Connect(function()
			sendKick(zone)
		end)
	end
	panel.close.Activated:Connect(closePanel)

	local function showKickResult(result: any)
		if type(result) ~= "table" or type(result.aim) ~= "string" then
			return
		end
		local aimed: TextButton? = panel.zones[result.aim]
		local keeper: TextButton? = if type(result.keeper) == "string"
			then panel.zones[result.keeper]
			else nil
		if aimed == nil then
			return
		end
		panelToken += 1
		local token = panelToken
		waiting = false
		kicksLeft = if type(result.kicksLeft) == "number" then result.kicksLeft else 0
		totalBoost += if type(result.boostSeconds) == "number" then result.boostSeconds else 0
		showKicksLeft()

		resetZones()
		if keeper then
			keeper.Text = "KEEPER"
			keeper.BackgroundColor3 = Style.ui.bad
			keeper.BackgroundTransparency = 0.2
		end
		if result.goal then
			aimed.Text = "GOAL"
			aimed.BackgroundColor3 = Style.ui.good
			aimed.BackgroundTransparency = 0.1
			panel.result.Text = "GOAL!"
			panel.result.TextColor3 = Style.ui.good
		else
			aimed.BackgroundColor3 = Style.ui.idle
			aimed.BackgroundTransparency = 0.3
			panel.result.Text = if result.wide then "Just wide!" else "Saved!"
			panel.result.TextColor3 = Style.ui.bad
		end

		if kicksLeft > 0 then
			task.delay(RESULT_SECONDS, function()
				if token == panelToken then
					resetZones()
					setZonesEnabled(true)
					panel.result.Text = "Pick a corner"
					panel.result.TextColor3 = Style.ui.gold
				end
			end)
			return
		end
		-- The last kick: say what the goals earned, then close by itself.
		task.delay(RESULT_SECONDS, function()
			if token ~= panelToken then
				return
			end
			local goals = if type(result.goals) == "number" then result.goals else 0
			panel.result.Text = if totalBoost > 0
				then string.format("%d/3 goals · %s", goals, boostText(totalBoost))
				else "No goals this time. Back tomorrow!"
			panel.result.TextColor3 = Style.ui.gold
		end)
		task.delay(RESULT_SECONDS + CLOSE_AFTER_LAST_SECONDS, function()
			if token == panelToken then
				closePanel()
			end
		end)
	end

	-- What the server tells us ----------------------------------------------------------------
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "penaltyOpen" and type(info.kicksLeft) == "number" then
			openPanel(info.kicksLeft)
		elseif info.kind == "penaltyResult" then
			showKickResult(info.result)
		elseif info.kind == "caseResult" and type(info.prize) == "table" then
			local won = info.prize
			if won.kind == "cash" and type(won.amount) == "number" then
				showPrize("Free case: +" .. NumberFormat.money(won.amount))
			elseif won.kind == "boost" and type(won.seconds) == "number" then
				showPrize(
					string.format("Free case: x2 income for %d min", math.ceil(won.seconds / 60))
				)
			end
		end
	end)

	-- Taps -------------------------------------------------------------------------------------
	local lastClaim = 0
	caseIcon.button.Activated:Connect(function()
		if caseIcon.status == "ready" then
			if os.clock() - lastClaim > 1 then
				lastClaim = os.clock()
				Net.fire("ClaimDaily", "case")
			end
		elseif caseIcon.status == "waiting" then
			showToast(DailyInfo.waitText(readyAt("caseReadyAt") - Workspace:GetServerTimeNow()))
		end
	end)
	kickIcon.button.Activated:Connect(function()
		if kickIcon.status == "ready" then
			Arrow.guide("penalty", GUIDE_SECONDS, "Penalty kicks")
			showToast("Walk to the red spot on the pitch")
		elseif kickIcon.status == "waiting" then
			showToast(DailyInfo.waitText(readyAt("penaltyReadyAt") - Workspace:GetServerTimeNow()))
		end
	end)

	-- Every frame: the icon status follows the server's ready times, the glow fades after a while.
	RunService.RenderStepped:Connect(function()
		paintIcon(caseIcon, iconStatus("caseReadyAt"))
		paintIcon(kickIcon, iconStatus("penaltyReadyAt"))
		for _, icon in { caseIcon, kickIcon } do
			if icon.glowUntil > os.clock() then
				local wave = (math.sin(os.clock() * 6) + 1) / 2
				icon.glow.Transparency = 0.6 - wave * 0.6
			elseif icon.status == "ready" then
				icon.glow.Transparency = 0.5 -- a soft steady outline, no more pulsing
			end
		end
	end)
end

return DailyUi
