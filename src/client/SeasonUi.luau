--!strict
-- The New Season badge, its screen and the trophy celebration (docs/PLAN.md, Steps 1 and 7). The badge
-- sits under the HUD column: hidden before floor 3 opens, a locked preview while floor 3 is open,
-- glowing once the season can start. The screen explains what is gained, lost and kept, with the
-- re-climb estimate. The server decides everything; this only asks and shows.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local Season = require(ReplicatedStorage.Shared.Season)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local BADGE_W, BADGE_H = 160, 28
local CARD_W = 400
local CELEBRATION_SECONDS = 3.5
local CELEBRATION_REDUCED_SECONDS = 2.5
local RETRY_SECONDS = 4 -- the button comes back if the server never answered

local SeasonUi = {}

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

local function multiplierText(season: number): string
	return string.format("x%.1f", Formulas.seasonMultiplier(season))
end

local function durationText(seconds: number): string
	if seconds == math.huge then
		return "a long time"
	elseif seconds < 3600 then
		return string.format("%d min", math.max(1, math.floor(seconds / 60 + 0.5)))
	end
	return string.format("%.1f h", seconds / 3600)
end

-- The floors a season restarts, and what stays, in a few words.
local function lostText(finished: number): string
	local kept = Season.keptFloors(finished)
	local floors = if kept == 0 then "floors 1-3" elseif kept == 1 then "floors 2-3" else "floor 3"
	return `cash, upgrades, {floors}`
end

local function keptText(finished: number): string
	local kept = Season.keptFloors(finished)
	local head = if kept == 0 then "" elseif kept == 1 then "floor 1, " else "floors 1-2, "
	return head .. "Legends, Robux items, trophies"
end

local function currentSeason(): number
	local value = player:GetAttribute("seasonNumber")
	return if type(value) == "number" then value else 1
end

function SeasonUi.init()
	local gui = new("ScreenGui", {
		Name = "Season",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))

	local badge = new("TextButton", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 160),
		Size = UDim2.fromOffset(BADGE_W, BADGE_H),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Style.ui.idle,
		Text = "",
		Visible = false,
	}, gui)
	rounded(badge, 8)
	local glow = new("UIStroke", {
		Color = Style.ui.gold,
		Thickness = 2,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, badge)

	-- The screen: a dimmed backdrop that closes it, and a card that fits the smallest phone.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 5,
	}, gui)
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Style.ui.panel,
		ZIndex = 6,
	}, backdrop)
	rounded(card, 12)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, card)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	local scale = new("UIScale", {}, card)
	-- Fit the card to the screen: the natural height is the shown height over the current scale.
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		local naturalHeight = card.AbsoluteSize.Y / scale.Scale
		scale.Scale =
			math.min(1, size.X / (CARD_W + 40), size.Y * 0.92 / math.max(naturalHeight, 1))
	end
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local order = 0
	local function line(text: string, props: { [string]: any }?)
		order += 1
		local p = {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Style.ui.text,
			ZIndex = 7,
		}
		if props then
			for key, value in props do
				p[key] = value
			end
		end
		return new("TextLabel", p, card)
	end

	local function clear()
		order = 0
		for _, child in card:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function close()
		backdrop.Visible = false
	end
	backdrop.Activated:Connect(close)

	local starting = false

	local function addButton(text: string, color: Color3, onClick: () -> ())
		order += 1
		local button = new("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = color,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Style.ui.dark,
			Text = text,
			ZIndex = 7,
		}, card)
		rounded(button, 8)
		button.Activated:Connect(onClick)
		return button
	end

	local function render()
		clear()
		local season = currentSeason()
		local state = Season.state(State.data)
		line("New Season", { TextSize = 24, TextColor3 = Style.ui.gold })
		if state == "hidden" then
			line("Finish floor 3 to unlock it.", { TextColor3 = Style.ui.idle })
			addButton("Close", Style.ui.idle, close)
			return
		end
		line(`Income {multiplierText(season + 1)} forever · {Season.trophyName(season)}`, {
			TextColor3 = Style.ui.good,
		})
		line(`Restarts: {lostText(season)}`)
		line(`Kept: {keptText(season)}`)
		if state == "locked" then
			local owned, total = Season.lastFloorProgress(State.data)
			line(
				`Unlocks when floor 3 is done ({total - owned} left).`,
				{ TextColor3 = Style.ui.idle }
			)
			addButton("Close", Style.ui.idle, close)
			return
		end
		line(`Floor 3 again: about {durationText(Season.estimateSeconds(season))}`, {
			TextColor3 = Style.ui.idle,
		})
		local start: TextButton
		start = addButton("Start New Season", Style.ui.good, function()
			if starting then
				return
			end
			starting = true
			start.Text = "Starting..."
			Net.fire("StartNewSeason", season)
			task.delay(RETRY_SECONDS, function()
				starting = false
				if start.Parent then
					start.Text = "Start New Season"
				end
			end)
		end)
		addButton("Not now", Style.ui.idle, close)
	end

	local function open()
		render()
		backdrop.Visible = true
	end
	badge.Activated:Connect(open)

	-- The badge follows the progress.
	local pulse: Tween? = nil
	local function refresh()
		local season = currentSeason()
		local state = Season.state(State.data)
		if state == "hidden" and season == 1 then
			badge.Visible = false
			return
		end
		badge.Visible = true
		if state == "ready" then
			badge.Text = "New Season available"
			badge.TextColor3 = Style.ui.gold
		elseif state == "locked" then
			badge.Text = "New Season · locked"
			badge.TextColor3 = Style.ui.idle
		else
			badge.Text = `Season {season} · {multiplierText(season)}`
			badge.TextColor3 = Style.ui.idle
		end
		if state == "ready" then
			if GuiService.ReducedMotionEnabled then
				glow.Transparency = 0.2
			elseif pulse == nil then
				glow.Transparency = 0.7
				local tween = TweenService:Create(
					glow,
					TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0 }
				)
				pulse = tween
				tween:Play()
			end
		else
			local running = pulse
			if running then
				running:Cancel()
				pulse = nil
			end
			glow.Transparency = 1
		end
		if backdrop.Visible and not starting then
			render() -- the screen follows a change under it (a purchase, a new season)
		end
	end
	State.onChange(refresh)
	player:GetAttributeChangedSignal("seasonNumber"):Connect(refresh)
	refresh()

	-- The trophy celebration after a season starts: a tap skips it, nothing is locked.
	local celebrating = false
	local function celebrate(info: any)
		if
			type(info) ~= "table"
			or type(info.trophy) ~= "string"
			or type(info.season) ~= "number"
		then
			return
		end
		close()
		starting = false
		if celebrating then
			return
		end
		celebrating = true
		local reduced = GuiService.ReducedMotionEnabled
		local screen = new("TextButton", {
			Name = "Trophy",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Style.ui.dark,
			BackgroundTransparency = if reduced then 0.35 else 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 8,
		}, gui)
		if not reduced then
			TweenService:Create(screen, TweenInfo.new(0.3), { BackgroundTransparency = 0.35 })
				:Play()
		end
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(300, 230),
			BackgroundTransparency = 1,
			ZIndex = 9,
		}, screen)
		local boxScale = new("UIScale", {}, box)
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			boxScale.Scale = math.min(1, size.X / 340, size.Y / 250)
		end
		-- A plain gold cup: bowl, stem and base.
		local function part(x: number, y: number, w: number, h: number, radius: number)
			local frame = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, x, 0, y),
				Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = Style.ui.gold,
				ZIndex = 9,
			}, box)
			rounded(frame, radius)
		end
		part(0, 0, 90, 70, 22)
		part(-52, 10, 22, 30, 11)
		part(52, 10, 22, 30, 11)
		part(0, 66, 22, 38, 4)
		part(0, 100, 70, 14, 5)
		new("TextLabel", {
			Position = UDim2.fromOffset(0, 122),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = info.trophy,
			Font = Style.font,
			TextSize = 32,
			TextColor3 = Style.ui.gold,
			ZIndex = 9,
		}, box)
		new("TextLabel", {
			Position = UDim2.fromOffset(0, 164),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Text = `Season {info.season} begins · {multiplierText(info.season)}`,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Style.ui.text,
			ZIndex = 9,
		}, box)
		new("TextLabel", {
			Position = UDim2.fromOffset(0, 194),
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = "Tap to continue",
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Style.ui.idle,
			ZIndex = 9,
		}, box)

		local done = false
		local function finish()
			if done then
				return
			end
			done = true
			screen:Destroy()
			celebrating = false
		end
		screen.Activated:Connect(finish)
		task.delay(if reduced then CELEBRATION_REDUCED_SECONDS else CELEBRATION_SECONDS, finish)
	end
	Net.on("SeasonStarted", celebrate)
end

return SeasonUi
