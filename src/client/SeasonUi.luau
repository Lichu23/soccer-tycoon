--!strict
-- The New Season badge, its screen and the trophy celebration (docs/PLAN.md, Steps 1 and 7). The badge
-- sits under the HUD column: hidden until floor 1 is done, then always shown in gold (it always opens
-- the screen), with a red "1" once the season can start. The screen is a light panel like the Shop's: the trophy being
-- played for turns in a tile (a silhouette until floor 3 is done), beside what is gained, restarted and
-- kept, with the re-climb estimate. The celebration shows that trophy, big, with the lineup cheering
-- around it. The server decides everything; this only asks and shows.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Icons = require(script.Parent.Icons)
local Net = require(script.Parent.Net)
local Edges = require(script.Parent.Edges)
local Panel = require(script.Parent.Panel)
local Season = require(ReplicatedStorage.Shared.Season)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)
local TrophyModels = require(ReplicatedStorage.Shared.TrophyModels)
local TrophyScene = require(script.Parent.TrophyScene)

local player = Players.LocalPlayer

local BADGE_W, BADGE_H = 160, 28
-- Under the boost badge and "+N TP" of the HUD column (client/Hud, their row ends at 187), so a
-- running boost stays readable.
local BADGE_Y = 194
local PANEL_W, PANEL_H = 540, 290
local TILE = 180 -- the trophy tile, square
local COLUMN_X = 18 + TILE + 18 -- the text column right of the tile
local COLUMN_W = PANEL_W - COLUMN_X - 18
local BOX_W, BOX_H = 480, 420 -- the celebration: the scene over the card
local SCENE_H = 250
local PANEL_COLOR = Color3.fromRGB(226, 216, 255) -- the light panel of the Shop
local RED = Color3.fromRGB(232, 64, 96) -- the red X and ribbons of the other panels
local OFF_FILL = Color3.fromRGB(196, 194, 214) -- a button that cannot be pressed yet
local OFF_TEXT = Color3.fromRGB(120, 122, 140)
local CELEBRATION_SECONDS = 6
local CELEBRATION_REDUCED_SECONDS = 2.5
local HIGHLIGHT_SECONDS = 2 -- the badge has a gold edge this long when it first appears
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
		Position = UDim2.new(1, -10, 0, BADGE_Y),
		Size = UDim2.fromOffset(BADGE_W, BADGE_H),
		BackgroundColor3 = Style.ui.panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Style.ui.gold,
		Text = "",
		Visible = false,
	}, gui)
	rounded(badge, 8)
	new("UIPadding", { PaddingLeft = UDim.new(0, 24) }, badge)
	-- Under the HUD column, which moves out to the right and shrinks on a phone (client/Hud,
	-- client/Edges): the badge follows it and shrinks the same way. The column's top is at y 6.
	gui.ClipToDeviceSafeArea = false
	local badgeScale = new("UIScale", {}, badge)
	Edges.watch(function()
		local _, right = Edges.pull()
		local scale = Edges.hudScale()
		badgeScale.Scale = scale
		badge.Position = UDim2.new(1, right - 10, 0, 6 + (BADGE_Y - 6) * scale)
	end)
	-- A small gold cup at the left of the badge: bowl, handles, stem and base.
	local icon = new("Frame", {
		Name = "Icon",
		Position = UDim2.fromOffset(-22, 4),
		Size = UDim2.fromOffset(18, 20),
		BackgroundTransparency = 1,
	}, badge)
	for _, bit in
		{
			{ 4, 0, 10, 9, 3 },
			{ 0, 1, 4, 5, 2 },
			{ 14, 1, 4, 5, 2 },
			{ 8, 9, 2, 6, 0 },
			{ 4, 15, 10, 4, 1 },
		}
	do
		local frame = new("Frame", {
			Position = UDim2.fromOffset(bit[1], bit[2]),
			Size = UDim2.fromOffset(bit[3], bit[4]),
			BackgroundColor3 = Style.ui.gold,
		}, icon)
		rounded(frame, bit[5])
	end
	-- With the uploaded trophy tile the picture takes the place of the drawn cup.
	local trophy = Icons.id("trophy")
	if trophy ~= "" then
		icon:ClearAllChildren()
		new("ImageLabel", {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
			Image = trophy,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		}, icon)
	end
	local dot = new("TextLabel", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Style.ui.bad,
		Text = "1",
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Style.ui.text,
		Visible = false,
		ZIndex = 3,
	}, badge)
	rounded(dot, 10)
	local glow = new("UIStroke", {
		Color = Style.ui.gold,
		Thickness = 2,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, badge)

	-- The screen: the light panel of the Shop and the Free Case, with the red X as the only way out
	-- (a stray tap beside it does nothing). It is scaled down to fit the smallest phone.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, -- no dimming, like the Shop; it only swallows taps
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 5,
	}, gui)
	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = PANEL_COLOR,
		ZIndex = 6,
	}, backdrop)
	rounded(panel, 16)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 4 }, panel)
	local scale = new("UIScale", {}, panel)
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		if size.X < 100 or size.Y < 100 then
			return -- the viewport is not ready yet; the next fit (when the panel opens) corrects it
		end
		scale.Scale = math.min(1, size.X / (PANEL_W + 32), size.Y * 0.9 / PANEL_H)
	end
	backdrop:GetPropertyChangedSignal("Visible"):Connect(fit)

	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(300, 36),
		BackgroundTransparency = 1,
		Text = "New Season",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 26,
		TextColor3 = Panel.TEXT,
		ZIndex = 7,
	}, panel)
	local closeButton = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 36),
		BackgroundColor3 = RED,
		Text = "X",
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.text,
		ZIndex = 7,
	}, panel)
	rounded(closeButton, 8)

	-- The trophy tile: a dark case with gold rays behind the turning trophy, and its plaque under it.
	local tile = new("Frame", {
		Name = "Trophy",
		Position = UDim2.fromOffset(18, 56),
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = Style.ui.panel,
		ZIndex = 7,
	}, panel)
	rounded(tile, 14)
	local tileStroke = new("UIStroke", {
		Color = Style.ui.gold,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, tile)
	local rays = TrophyScene.rays(tile, TILE - 8, GuiService.ReducedMotionEnabled, 8)
	local stage = new("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, tile)
	local plaque = new("TextLabel", {
		Name = "Plaque",
		Position = UDim2.fromOffset(18, 56 + TILE + 8),
		Size = UDim2.fromOffset(TILE, 30),
		BackgroundColor3 = Style.ui.dark,
		Text = "",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.gold,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	}, panel)
	rounded(plaque, 8)

	-- The column: what is won, what restarts, what is kept, how long floor 3 takes again.
	local column = new("Frame", {
		Name = "Column",
		Position = UDim2.fromOffset(COLUMN_X, 56),
		Size = UDim2.fromOffset(COLUMN_W, 164),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, panel)
	new(
		"UIListLayout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
		column
	)
	local function text(order: number, size: number, color: Color3, parent: Instance?): TextLabel
		return new("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = "",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Style.font,
			TextSize = size,
			TextColor3 = color,
			ZIndex = 7,
		}, parent or column)
	end
	local kicker = text(1, 13, Panel.MUTED)
	local reward = new("TextLabel", {
		Name = "Reward",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Style.ui.good,
		Text = "",
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.dark,
		ZIndex = 7,
	}, column)
	rounded(reward, 10)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, reward)
	-- A row: a coloured tag ("RESTARTS", "KEEPS") and the words after it.
	local function row(order: number, tag: string, color: Color3): TextLabel
		local frame = new("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, column)
		local label = new("TextLabel", {
			Position = UDim2.fromOffset(0, 1),
			Size = UDim2.fromOffset(76, 20),
			BackgroundColor3 = color,
			Text = tag,
			Font = Style.font,
			TextSize = 11,
			TextColor3 = Style.ui.text,
			ZIndex = 7,
		}, frame)
		rounded(label, 6)
		local words = text(0, 15, Panel.TEXT, frame)
		words.Position = UDim2.fromOffset(84, 0)
		words.Size = UDim2.new(1, -84, 0, 0)
		return words
	end
	local restarts = row(3, "RESTARTS", RED)
	local keeps = row(4, "KEEPS", Panel.GOOD)
	local estimate = text(5, 14, Panel.MUTED)

	local start = new("TextButton", {
		Name = "Start",
		Position = UDim2.fromOffset(COLUMN_X, 56 + TILE - 10),
		Size = UDim2.fromOffset(COLUMN_W, 48),
		BackgroundColor3 = Style.ui.good,
		Text = "",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.dark,
		AutoButtonColor = false,
		ZIndex = 7,
	}, panel)
	rounded(start, 12)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, start)

	-- The turning trophy lives only while the screen is open.
	local showcase: TrophyScene.Showcase? = nil
	local shownTier = 0
	local function stopShowcase()
		if showcase then
			showcase.stop()
			showcase = nil
		end
		shownTier = 0
	end

	local function close()
		backdrop.Visible = false
		stopShowcase()
	end
	closeButton.Activated:Connect(close)

	local starting = false

	local function render()
		local season = currentSeason()
		local state = Season.state(State.data)
		local ready = state == "ready"
		local tier = TrophyModels.tier(season)
		if shownTier ~= tier then
			stopShowcase()
			showcase = TrophyScene.showcase(stage, tier, GuiService.ReducedMotionEnabled)
			shownTier = tier
		end
		if showcase then
			showcase.setLocked(not ready)
		end
		rays.Visible = ready
		tileStroke.Color = if ready then Style.ui.gold else Style.ui.dark
		plaque.Text = string.upper(Season.trophyName(season))
		kicker.Text = if ready
			then `CLAIM THE TROPHY · START SEASON {season + 1}`
			else "FINISH FLOOR 3 TO CLAIM THE TROPHY"
		reward.Text = `Income {multiplierText(season + 1)} forever`
		restarts.Text = lostText(season)
		keeps.Text = keptText(season)
		if ready then
			estimate.Text = `Floor 3 again: about {durationText(Season.estimateSeconds(season))}`
		elseif state == "locked" then
			local owned, total = Season.lastFloorProgress(State.data)
			estimate.Text = `Floor 3: {total - owned} players left to buy`
		else
			estimate.Text = "Floor 3 is not open yet"
		end
		if not starting then
			start.Text = if ready then "START NEW SEASON" else "LOCKED"
		end
		start.BackgroundColor3 = if ready and not starting then Style.ui.good else OFF_FILL
		start.TextColor3 = if ready and not starting then Style.ui.dark else OFF_TEXT
	end

	start.Activated:Connect(function()
		if starting or Season.state(State.data) ~= "ready" then
			return
		end
		starting = true
		start.Text = "STARTING..."
		render()
		Net.fire("StartNewSeason", currentSeason())
		task.delay(RETRY_SECONDS, function()
			if starting then
				starting = false -- no answer: the button comes back
				render()
			end
		end)
	end)

	local function open()
		render()
		backdrop.Visible = true
	end
	badge.Activated:Connect(open)

	-- The badge follows the progress. It appears once floor 1 is done, always in its gold colours since
	-- it can always be opened, with a gold edge for a moment when it first appears; when the season can
	-- start it carries a red "1".
	local lastState: string? = nil
	local highlightUntil = 0
	local function refresh()
		local season = currentSeason()
		local state = Season.state(State.data)
		if lastState == "hidden" and state == "locked" then
			highlightUntil = os.clock() + HIGHLIGHT_SECONDS
			task.delay(HIGHLIGHT_SECONDS + 0.05, function()
				if os.clock() >= highlightUntil then
					glow.Transparency = 1
				end
			end)
		end
		lastState = state
		if state == "hidden" and season == 1 then
			badge.Visible = false
			return
		end
		badge.Visible = true
		icon.Visible = state ~= "hidden"
		dot.Visible = state == "ready"
		badge.Text = if state == "hidden"
			then `Season {season} · {multiplierText(season)}`
			else "New Season"
		glow.Transparency = if os.clock() < highlightUntil then 0.1 else 1
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
		-- No dimming, like the Shop and the New Season screen: the screen only takes the tap.
		local screen = new("TextButton", {
			Name = "Trophy",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 8,
		}, gui)
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(BOX_W, BOX_H),
			BackgroundTransparency = 1,
			ZIndex = 9,
		}, screen)
		local boxScale = new("UIScale", {}, box)
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			boxScale.Scale = math.min(1, size.X / (BOX_W + 20), size.Y * 0.96 / BOX_H)
		end
		-- The trophy just won turns on its plinth in front of gold rays, the players of the finished
		-- season's lineup cheer around it, and confetti falls over the whole screen.
		local finished = info.season - 1
		local sceneBox = new("Frame", {
			Name = "Scene",
			Size = UDim2.fromOffset(BOX_W, SCENE_H),
			BackgroundTransparency = 1,
			ZIndex = 9,
		}, box)
		local sceneRays = TrophyScene.rays(sceneBox, 300, reduced, 9)
		sceneRays.Position = UDim2.fromScale(0.5, 0.42)
		local stopScene = TrophyScene.build(sceneBox, {
			field = if type(info.field) == "table" then info.field else {},
			tier = TrophyModels.tier(finished),
			still = reduced,
			confetti = screen,
		})

		-- The card under it, like the reward card: a red ribbon on the light panel with a gold edge.
		local cardTop = SCENE_H + 12
		local card = new("Frame", {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(BOX_W / 2, cardTop),
			Size = UDim2.fromOffset(400, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = PANEL_COLOR,
			ZIndex = 11,
		}, box)
		rounded(card, 18)
		new("UIStroke", {
			Color = Style.ui.gold,
			Thickness = 4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, card)
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, card)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 30),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}, card)
		local ribbon = new("TextLabel", {
			Name = "Ribbon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, cardTop),
			Size = UDim2.fromOffset(250, 36),
			BackgroundColor3 = RED,
			Text = `SEASON {finished} COMPLETE`,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Style.ui.text,
			ZIndex = 13,
		}, box)
		rounded(ribbon, 8)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ribbon)
		new("TextLabel", {
			Name = "Trophy",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundTransparency = 1,
			Text = info.trophy,
			Font = Style.font,
			TextSize = 34,
			TextColor3 = Panel.TEXT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 12,
		}, card)
		local chip = new("TextLabel", {
			Name = "Next",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Style.ui.good,
			Text = `Season {info.season} begins · Income {multiplierText(info.season)}`,
			Font = Style.font,
			TextSize = 17,
			TextColor3 = Style.ui.dark,
			ZIndex = 12,
		}, card)
		rounded(chip, 10)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, chip)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, chip)
		new("TextLabel", {
			Name = "Hint",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "Tap to continue",
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Panel.MUTED,
			ZIndex = 12,
		}, card)

		-- The trophy rises in with a little overshoot and the card follows it up.
		if not reduced then
			Sounds.play("goal")
			local sceneScale = new("UIScale", { Scale = 0.6 }, sceneBox)
			TweenService:Create(
				sceneScale,
				TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
			for _, item in { card, ribbon } :: { GuiObject } do
				local goal = item.Position
				item.Position = goal + UDim2.fromOffset(0, 60)
				TweenService:Create(
					item,
					TweenInfo.new(
						0.4,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out,
						0,
						false,
						0.15
					),
					{ Position = goal }
				):Play()
			end
		end

		local done = false
		local function finish()
			if done then
				return
			end
			done = true
			stopScene()
			screen:Destroy()
			celebrating = false
		end
		screen.Activated:Connect(finish)
		task.delay(if reduced then CELEBRATION_REDUCED_SECONDS else CELEBRATION_SECONDS, finish)
	end
	Net.on("SeasonStarted", celebrate)
end

return SeasonUi
