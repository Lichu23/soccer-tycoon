--!strict
-- The daily return on screen (docs/PLAN.md, Step 7): the penalty kick icon at the left edge below the
-- top bar (the free case moved into the Shop), and the penalty kick screen. A ready icon gets a small gold
-- dot and a soft glow that stops pulsing after a few seconds; no sound, no red counter. A waiting
-- icon is dimmed and a tap says how long is left. The server judges every claim and kick; this
-- only sends the tap and shows the answer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CaseModal = require(script.Parent.CaseModal)
local Dock = require(script.Parent.Dock)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PenaltyUi = require(script.Parent.PenaltyUi)
local Net = require(script.Parent.Net)
local RewardCard = require(script.Parent.RewardCard)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local GLOW_SECONDS = 4 -- how long a newly ready icon pulses
local TOAST_SECONDS = 2.5
local PRIZE_SECONDS = 4
local AUTO_OPEN_SECONDS = 5 -- after the level-up that ends the tutorial

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
	tile: Dock.Tile,
	button: TextButton,
	glow: UIStroke,
	status: string,
	glowUntil: number,
}

local function buildIcon(
	parent: Instance,
	name: string,
	text: string,
	slot: number,
	accent: Color3,
	iconName: string
): Icon
	local tile = Dock.build(parent, name, slot, text, accent, iconName)
	Dock.paint(tile, "locked")
	return {
		tile = tile,
		button = tile.button,
		glow = tile.accent,
		status = "locked",
		glowUntil = 0,
	}
end

-- Paints an icon for its status. A newly ready icon pulses for a few seconds, then stays still.
local function paintIcon(icon: Icon, status: string)
	if icon.status == status then
		return
	end
	local becameReady = status == "ready" and icon.status ~= "ready"
	icon.status = status
	Dock.paint(icon.tile, status)
	if becameReady then
		icon.glowUntil = os.clock() + GLOW_SECONDS
	elseif status ~= "ready" then
		icon.glowUntil = 0
	end
end

-- The short line of a closed icon: the plot comes first, then the first player.
local function closedReason(): string
	if not State.hasPlot() then
		return "Claim your plot first."
	end
	return "Buy your first player first."
end

local function readyAt(attribute: string): number
	local value = player:GetAttribute(attribute)
	return if type(value) == "number" then value else 0
end

local function iconStatus(attribute: string): string
	-- Nothing opens before the plot is claimed: the icons belong to the player's own plot.
	local unlocked = State.hasPlot() and player:GetAttribute("dailyUnlocked") == true
	return DailyInfo.status(unlocked, readyAt(attribute), Workspace:GetServerTimeNow())
end

-- A short line under the icons ("Ready in 3 h 20 min").
local function buildToast(parent: Instance): TextLabel
	local toast = new("TextLabel", {
		Name = "Toast",
		Position = UDim2.fromOffset(8 + Dock.SIZE + 10, 14),
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

	-- The free case lives in the Shop now; only the kick icon stays here.
	local kickIcon = buildIcon(gui, "KickIcon", "KICK", 1, Color3.fromRGB(110, 225, 130), "kick")
	Dock.badge(kickIcon.tile, "kick")
	CaseModal.init()
	local toast = buildToast(gui)
	local prize = buildPrize(gui)
	PenaltyUi.init()
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
		if info.kind == "penaltyResult" then
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
	-- Opens the kick screen with the kicks left today.
	local function openKick()
		local kicks = player:GetAttribute("penaltyKicksLeft")
		PenaltyUi.open(if type(kicks) == "number" and kicks > 0 then kicks else 3)
	end
	kickIcon.button.Activated:Connect(function()
		if kickIcon.status == "locked" then
			Dock.reason(kickIcon.tile, closedReason())
			return
		end
		if kickIcon.status == "ready" then
			openKick()
		elseif kickIcon.status == "waiting" then
			showToast(DailyInfo.waitText(readyAt("penaltyReadyAt") - Workspace:GetServerTimeNow()))
		end
	end)

	-- When the level-up tutorial ends (the first level any player gets), the kick screen opens by
	-- itself five seconds later, once, in place of the level-up card. Sending SeenTile marks the Kick
	-- button as seen for good, so it never opens by itself again.
	local autoOpened = false
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" or info.kind ~= "levelUp" or info.tutorialDone ~= true then
			return
		end
		if autoOpened or kickIcon.status ~= "ready" or player:GetAttribute("tile_kick") ~= 0 then
			return
		end
		autoOpened = true
		task.delay(AUTO_OPEN_SECONDS, function()
			if kickIcon.status == "ready" then
				Net.fire("SeenTile", "kick")
				RewardCard.hide()
				openKick()
			end
		end)
	end)

	-- Every frame: the icon status follows the server's ready times, the glow fades after a while.
	RunService.RenderStepped:Connect(function()
		paintIcon(kickIcon, iconStatus("penaltyReadyAt"))
		for _, icon in { kickIcon } do
			if icon.glowUntil > os.clock() then
				local wave = (math.sin(os.clock() * 6) + 1) / 2
				icon.glow.Transparency = 0.6 - wave * 0.6
			elseif icon.status == "ready" then
				icon.glow.Transparency = 0 -- steady, no more pulsing
			end
		end
	end)
end

return DailyUi
