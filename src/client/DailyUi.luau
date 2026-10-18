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
local CaseModal = require(script.Parent.CaseModal)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PenaltyUi = require(script.Parent.PenaltyUi)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local ICON_SIZE = 52
local ICON_GAP = 8
local GLOW_SECONDS = 4 -- how long a newly ready icon pulses
local TOAST_SECONDS = 2.5
local PRIZE_SECONDS = 4
local GUIDE_SECONDS = 15

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

function DailyUi.init()
	local gui = new("ScreenGui", {
		Name = "Daily",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
	}, player:WaitForChild("PlayerGui"))

	local caseIcon = buildIcon(gui, "CaseIcon", "CASE", 1)
	local kickIcon = buildIcon(gui, "KickIcon", "KICK", 2)
	CaseModal.init()
	local toast = buildToast(gui)
	local prize = buildPrize(gui)
	PenaltyUi.init()
	PenaltyUi.initReward()
	PenaltyUi.onFinished = function(goals: number, boostSeconds: number)
		PenaltyUi.showReward(goals, boostSeconds)
	end

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

	-- What the server tells us ----------------------------------------------------------------
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "penaltyOpen" and type(info.kicksLeft) == "number" then
			PenaltyUi.open(info.kicksLeft)
		elseif info.kind == "penaltyResult" then
			PenaltyUi.onResult(info.result)
		elseif info.kind == "caseResult" and type(info.prize) == "table" then
			local won = info.prize
			if CaseModal.onResult(won) then
				return -- the cases screen shows it with its roulette
			end
			if won.kind == "cash" and type(won.amount) == "number" then
				showPrize("Free case: +" .. NumberFormat.money(won.amount))
			elseif won.kind == "tp" and type(won.amount) == "number" then
				showPrize("Free case: +" .. won.amount .. " training points")
			elseif won.kind == "boost" and type(won.seconds) == "number" then
				showPrize(
					string.format("Free case: x2 income for %d min", math.ceil(won.seconds / 60))
				)
			end
		end
	end)

	-- Taps -------------------------------------------------------------------------------------
	caseIcon.button.Activated:Connect(function()
		-- The icon opens the cases screen; it says when the free case is ready and opens it.
		CaseModal.open()
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
