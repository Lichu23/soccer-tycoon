--!strict
-- The case screen (docs/PLAN.md, Steps 3 and 7). The free case opens it from the Shop: a title, the
-- roulette strip, one button and, under it, when the next one opens. A bought Standard or Elite case
-- opens it by itself when the purchase is done, with the same strip of its own players and boosts and
-- no button. The server has already rolled and paid the reward when the strip starts; the strip is only
-- a show that slows down and lands on it. When it has landed the screen closes and the reward card says
-- what was won (RewardCard), or a player's rarity reveal plays (Reveal, held until then). With reduced
-- motion the strip is skipped and the result shows at once.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Icons = require(script.Parent.Icons)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Panel = require(script.Parent.Panel)
local Reveal = require(script.Parent.Reveal)
local RewardCard = require(script.Parent.RewardCard)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 520, 342
local PAID_PANEL_H = 246 -- a bought case has no button or time under the strip
local WINDOW_W, WINDOW_H = 480, 156
local TILE_W, TILE_H, TILE_GAP = 114, 136, 8
local BAND_H = 34 -- the navy name band at the foot of a tile
local TILE_COUNT = 40 -- fewer than before: a player tile is a ViewportFrame
local WIN_INDEX = 32
local IDLE_CENTER_INDEX = 3 -- the tile under the marker before a spin
local SPIN_SECONDS = 6
local TICK_GAP = 0.05 -- the shortest time between two roulette ticks (the fast start passes many cards)
local HOLD_SECONDS = 0.9 -- the landed tile stays in view this long before the screen closes
local WIN_ZOOM, WIN_ZOOM_SECONDS = 1.08, 0.25 -- the landed tile grows to this (it still fits the window)
local REPLY_TIMEOUT = 4
local FIGURE_FOV = 30

-- Each reward kind is its icon on a tile of the icon's own colour (the boost arrows are green too).
local KIND_COLORS: { [string]: Color3 } = {
	cash = Style.ui.good,
	boost = Style.ui.good,
	tp = Style.ui.bar,
}
local KIND_ICONS: { [string]: string } = {
	cash = "cash",
	boost = "boost",
	tp = "tp",
}

local CaseModal = {}

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

local function rewardById(id: string): Config.CaseReward?
	for _, reward in Config.Daily.caseRewards do
		if reward.id == id then
			return reward
		end
	end
	return nil
end

local totalWeight = 0
for _, reward in Config.Daily.caseRewards do
	totalWeight += reward.weight
end

-- A weighted random reward for a filler tile (the real one is placed by the server's result).
local function randomReward(random: Random): Config.CaseReward
	local point = random:NextNumber() * totalWeight
	for _, reward in Config.Daily.caseRewards do
		point -= reward.weight
		if point < 0 then
			return reward
		end
	end
	return Config.Daily.caseRewards[1]
end

-- The line in a tile's band. The winning tile of the free case shows the real amount.
local function bandText(reward: Config.CaseReward, prize: any?): string
	if prize ~= nil and type(prize.amount) == "number" then
		if prize.kind == "cash" then
			return "+" .. NumberFormat.money(prize.amount)
		elseif prize.kind == "tp" then
			return "+" .. prize.amount .. " TP"
		end
	end
	return reward.detail
end

-- One figure per player, built the first time a tile shows him and cloned for every other tile.
local figures: { [string]: Model } = {}
local function figureOf(def: Config.PlayerDef): Model
	local figure = figures[def.id]
	if figure == nil then
		figure = Mannequin.build(def, nil, false)
		figures[def.id] = figure
	end
	return (figure :: Model):Clone()
end

-- A rounded tile in `color`, a little lighter at the top, with a navy band at its foot that holds
-- `bandLine`. Returns the tile and the area above the band.
local function makeTile(
	parent: Instance,
	index: number,
	color: Color3,
	bandLine: string,
	trim: Color3?
): (Frame, Frame)
	local tile = new("Frame", {
		Name = "Tile" .. index,
		Position = UDim2.fromOffset((index - 1) * (TILE_W + TILE_GAP), (WINDOW_H - TILE_H) / 2),
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, parent)
	rounded(tile, 12)
	new("UIGradient", {
		-- A rarity with lines shades towards them (a Legend goes from white to a light gold).
		Color = if trim
			then ColorSequence.new(color, color:Lerp(trim, 0.3))
			else ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color),
		Rotation = 90,
	}, tile)
	if trim then
		local line = new("Frame", {
			Name = "Trim",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, tile)
		rounded(line, 9)
		new("UIStroke", {
			Color = trim,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, line)
	end
	new("UIStroke", {
		Name = "Outline",
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, tile)
	local band = new("Frame", {
		Name = "Band",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, BAND_H),
		BackgroundColor3 = Style.ui.panel,
		ZIndex = 3,
	}, tile)
	rounded(band, 10)
	-- Squares off the band's top corners, so only the tile's own corners are round.
	new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Style.ui.panel,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, band)
	local text = new("TextLabel", {
		Name = "Line",
		Position = UDim2.fromOffset(5, 2),
		Size = UDim2.new(1, -10, 1, -4),
		BackgroundTransparency = 1,
		Text = bandLine,
		TextWrapped = true,
		TextScaled = true,
		Font = Style.font,
		TextColor3 = Style.ui.text,
		ZIndex = 4,
	}, band)
	new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9 }, text)
	local area = new("Frame", {
		Name = "Area",
		Size = UDim2.new(1, 0, 1, -BAND_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, tile)
	return tile, area
end

-- The kind's icon in the middle of the area. A boost puts "x2" in front of it.
-- `times` puts "x2" beside the picture (the boost, or a cash or TP boost of a bought case).
local function addIcon(area: Frame, kind: string, times: boolean?)
	local picture = Icons.id(KIND_ICONS[kind] or "")
	local boost = kind == "boost" or times == true
	local iconSize = if boost then 62 else 74
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if boost then UDim2.new(0.5, 20, 0.5, 2) else UDim2.new(0.5, 0, 0.5, 2),
		Size = UDim2.fromOffset(iconSize, iconSize),
		BackgroundTransparency = 1,
		Image = picture,
		ZIndex = 2,
	}, area)
	if boost then
		local x2 = new("TextLabel", {
			Name = "Times",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -30, 0.5, 2),
			Size = UDim2.fromOffset(52, 40),
			BackgroundTransparency = 1,
			Text = "x2",
			Font = Style.font,
			TextSize = 32,
			TextColor3 = Style.ui.text,
			ZIndex = 3,
		}, area)
		new("UIStroke", { Color = Style.ui.dark, Thickness = 3 }, x2)
	end
end

-- The player from the chest up, turned a little, in the area.
local function addFigure(area: Frame, def: Config.PlayerDef)
	local view = new("ViewportFrame", {
		Name = "Figure",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 244, 225),
		LightDirection = Vector3.new(0.4, -0.7, 0.6),
		ZIndex = 2,
	}, area)
	local figure = figureOf(def)
	figure:PivotTo(CFrame.Angles(0, math.rad(-20), 0))
	figure.Parent = view
	-- The torso's middle is the model's origin; the frame runs from the belt to just over the hair.
	local middle = Vector3.new(0, 1.1, 0)
	local distance = 2.2 / math.tan(math.rad(FIGURE_FOV / 2))
	local camera = new("Camera", {
		FieldOfView = FIGURE_FOV,
		CFrame = CFrame.lookAt(middle + Vector3.new(0, 0.3, -distance), middle),
	}, view)
	view.CurrentCamera = camera
end

local function freeTile(parent: Instance, reward: Config.CaseReward, index: number, prize: any?)
	local _, area = makeTile(parent, index, KIND_COLORS[reward.kind], bandText(reward, prize))
	addIcon(area, reward.kind)
end

-- A tile of a bought case: the player on his rarity colour with his full name, or a boost.
local function paidTile(parent: Instance, index: number, id: string)
	local boost = Config.CaseBoostsById[id]
	if boost then
		local _, area = makeTile(parent, index, KIND_COLORS[boost.kind], boost.detail)
		addIcon(area, boost.kind, true)
		return
	end
	local def = Config.PlayersById[id]
	if def == nil then
		makeTile(parent, index, Style.rarityColors.Common, "?")
		return
	end
	local color = Style.rarityColors[def.rarity] or Style.rarityColors.Common
	local _, area = makeTile(parent, index, color, def.name, Style.rarityTrim[def.rarity])
	addFigure(area, def)
end

function CaseModal.init()
	local gui = new("ScreenGui", {
		Name = "Cases",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		IgnoreGuiInset = true,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))

	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, -- no dimming, like the Shop and the Locker room
		Text = "",
		AutoButtonColor = false,
	}, gui)

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = Color3.fromRGB(226, 216, 255), -- the light panel of the Shop
	}, gui)
	rounded(panel, 16)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 4 }, panel)
	local scale = new("UIScale", {}, panel)

	local title = new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(300, 36),
		BackgroundTransparency = 1,
		Text = "Free Chest",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 26,
		TextColor3 = Panel.TEXT,
	}, panel)
	local close = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 36),
		BackgroundColor3 = Color3.fromRGB(232, 64, 96), -- the red X of the other panels
		Text = "X",
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 255, 255),
	}, panel)
	rounded(close, 8)

	-- The roulette: a clipped strip of tiles with a marker through the middle ---------------------
	local windowX = (PANEL_W - WINDOW_W) / 2
	local windowY = 66
	local window = new("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(windowX, windowY),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = Color3.fromRGB(250, 247, 255),
		ClipsDescendants = true,
	}, panel)
	rounded(window, 12)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, window)
	local strip = new("Frame", {
		Name = "Strip",
		Size = UDim2.fromOffset(TILE_COUNT * (TILE_W + TILE_GAP), WINDOW_H),
		BackgroundTransparency = 1,
	}, window)
	-- The indicator: a thin line through the middle with a little arrow on top (a sibling of the window,
	-- because the window clips its children).
	local marker = new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(PANEL_W / 2, windowY - 8),
		Size = UDim2.fromOffset(4, WINDOW_H + 16),
		BackgroundTransparency = 1, -- two arrows only, so the tile under them stays readable
		ZIndex = 6,
	}, panel)
	for _, arrow in
		{
			{ name = "Top", y = 0, anchor = 1, text = "▼" },
			{ name = "Bottom", y = 1, anchor = 0, text = "▲" },
		}
	do
		new("TextLabel", {
			Name = arrow.name,
			AnchorPoint = Vector2.new(0.5, arrow.anchor),
			Position = UDim2.fromScale(0.5, arrow.y),
			Size = UDim2.fromOffset(26, 18),
			BackgroundTransparency = 1,
			Text = arrow.text,
			Font = Enum.Font.GothamBold,
			TextSize = 24,
			TextColor3 = Panel.MUTED, -- grey, so the only red on the screen stays the X
			ZIndex = 6,
		}, marker)
	end

	local openButton = new("TextButton", {
		Name = "Open",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, windowY + WINDOW_H + 24),
		Size = UDim2.fromOffset(240, 46),
		BackgroundColor3 = Style.ui.good,
		Text = "OPEN",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.dark,
		AutoButtonColor = false,
	}, panel)
	rounded(openButton, 12)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, openButton)
	local timeLabel = new("TextLabel", {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, windowY + WINDOW_H + 24 + 46 + 8),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 18,
		TextColor3 = Panel.MUTED,
	}, panel)

	-- State --------------------------------------------------------------------------------------
	local mode: string = "idle" -- "idle", "waiting" (sent, no answer yet) or "spinning"
	local token = 0
	local activeTween: Tween? = nil
	local random = Random.new()
	local step = TILE_W + TILE_GAP

	local function modeNow(): string
		return mode
	end
	local function readyAt(): number
		local value = player:GetAttribute("caseReadyAt")
		return if type(value) == "number" then value else 0
	end
	local function freeStatus(): string
		local unlocked = player:GetAttribute("dailyUnlocked") == true
		return DailyInfo.status(unlocked, readyAt(), Workspace:GetServerTimeNow())
	end

	local function fitScale()
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			scale.Scale = math.min(1, size.X / (PANEL_W + 40), size.Y / (PANEL_H + 20))
		end
	end

	-- Before a spin the strip shows the rewards in turn, with one tile under the marker.
	local function showIdleStrip()
		for _, child in strip:GetChildren() do
			child:Destroy()
		end
		local rewards = Config.Daily.caseRewards
		for index = 1, TILE_COUNT do
			freeTile(strip, rewards[(index - 1) % #rewards + 1], index, nil)
		end
		strip.Position =
			UDim2.fromOffset(WINDOW_W / 2 - ((IDLE_CENTER_INDEX - 1) * step + TILE_W / 2), 0)
	end

	local function stopSpin()
		token += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		mode = "idle"
	end

	-- The prize of the spin that is running (already paid by the server). It is shown once, when the
	-- strip has landed, or at once when the screen is closed early; the HUD shows it from then on.
	local pendingPrize: any = nil
	local pendingPaid: any = nil -- the result of a bought case
	local function deliver()
		local prize = pendingPrize
		pendingPrize = nil
		if prize ~= nil then
			RewardCard.freeCase(prize)
		end
		State.releaseReward()
		local paid = pendingPaid
		pendingPaid = nil
		if paid ~= nil then
			local boost = Config.CaseBoostsById[paid.boostId or ""]
			local def = Config.Cases[paid.caseId or ""]
			if boost then
				RewardCard.show({
					title = string.upper(if def then def.name else "Chest"),
					big = boost.label .. " · " .. boost.detail,
					detail = if boost.kind == "tp"
						then "Double TP, added to your boost time"
						else "Double cash, added to your boost time",
					icon = boost.kind,
				})
			end
			Reveal.release() -- a player won: his reveal plays now
		end
	end

	local function close_()
		deliver()
		stopSpin()
		gui.Enabled = false
	end
	close.Activated:Connect(close_)
	backdrop.Activated:Connect(close_)

	-- Spins the strip (already built, with the win on WIN_INDEX) to a stop under the marker.
	local function spin()
		local jitter = (random:NextNumber() - 0.5) * TILE_W * 0.6
		local landed = WINDOW_W / 2 - ((WIN_INDEX - 1) * step + TILE_W / 2 + jitter)
		mode = "spinning"
		token += 1
		local myToken = token
		-- The strip has landed: the winning tile grows a little (a short zoom over its neighbours),
		-- then the screen closes and the reward card says what was won.
		local function finish()
			strip.Position = UDim2.fromOffset(landed, 0)
			mode = "idle"
			if GuiService.ReducedMotionEnabled then
				close_()
				return
			end
			local tile = strip:FindFirstChild("Tile" .. WIN_INDEX)
			if tile and tile:IsA("GuiObject") then
				tile.ZIndex = 2
				-- A UIScale grows around the anchor: from the centre, so it stays inside the window.
				tile.AnchorPoint = Vector2.new(0.5, 0.5)
				tile.Position += UDim2.fromOffset(TILE_W / 2, TILE_H / 2)
				local zoom = new("UIScale", { Name = "Zoom" }, tile)
				TweenService
					:Create(
						zoom,
						TweenInfo.new(
							WIN_ZOOM_SECONDS,
							Enum.EasingStyle.Back,
							Enum.EasingDirection.Out
						),
						{ Scale = WIN_ZOOM }
					)
					:Play()
			end
			task.delay(HOLD_SECONDS, function()
				if token == myToken and gui.Enabled then
					close_()
				end
			end)
		end

		strip.Position = UDim2.fromOffset(0, 0)
		if GuiService.ReducedMotionEnabled then
			finish()
			return
		end
		local tween = TweenService:Create(
			strip,
			TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(landed, 0) }
		)
		activeTween = tween
		-- A tick each time a card passes the marker in the middle of the window.
		local lastCard, lastTickAt = 0, 0
		local ticking: RBXScriptConnection
		ticking = RunService.RenderStepped:Connect(function()
			if token ~= myToken then
				ticking:Disconnect()
				return
			end
			local card = math.floor((WINDOW_W / 2 - strip.Position.X.Offset) / step)
			local now = os.clock()
			if card ~= lastCard and now - lastTickAt >= TICK_GAP then
				lastCard, lastTickAt = card, now
				Sounds.play("tick")
			end
		end)
		tween.Completed:Connect(function(state)
			ticking:Disconnect()
			if token == myToken and state == Enum.PlaybackState.Completed then
				activeTween = nil
				finish()
			end
		end)
		tween:Play()
	end

	-- The free case: the strip of its rewards with the won one on WIN_INDEX.
	local function spinFree(prize: any)
		pendingPrize = prize
		State.setHeldPrize(prize)
		local won = rewardById(prize.id)
		if won == nil then
			close_()
			return
		end
		for _, child in strip:GetChildren() do
			child:Destroy()
		end
		for index = 1, TILE_COUNT do
			if index == WIN_INDEX then
				freeTile(strip, won, index, prize)
			else
				freeTile(strip, randomReward(random), index, nil)
			end
		end
		spin()
	end

	-- A bought case: the strip of its players and boosts, drawn by the odds shown in the Shop, with
	-- the won one on WIN_INDEX.
	local function spinPaid(result: any)
		pendingPaid = result
		local entries = Cases.odds(State.data, result.caseId)
		for _, child in strip:GetChildren() do
			child:Destroy()
		end
		local wonId = result.boostId or result.playerId
		for index = 1, TILE_COUNT do
			local id = if index == WIN_INDEX
				then wonId
				else Cases.pick(entries, random:NextNumber())
			paidTile(strip, index, id)
		end
		spin()
	end

	openButton.Activated:Connect(function()
		if mode ~= "idle" or freeStatus() ~= "ready" then
			return
		end
		mode = "waiting"
		token += 1
		local myToken = token
		State.holdReward() -- the HUD keeps its numbers until the roulette has landed
		Net.fire("ClaimDaily", "case")
		task.delay(REPLY_TIMEOUT, function()
			if modeNow() == "waiting" and token == myToken then
				mode = "idle" -- the server never answered: let the player try again
				State.releaseReward()
			end
		end)
	end)

	-- Keeps the button and the time in step with the server's ready time.
	local lastLayout = ""
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local status = freeStatus()
		local now = Workspace:GetServerTimeNow()
		local on = status == "ready" and mode == "idle"
		local timeText = if mode ~= "idle"
			then ""
			elseif status == "waiting" then DailyInfo.waitText(readyAt() - now)
			elseif status == "ready" then "Free every 20 hours"
			else "Buy your first player first"
		local layout = tostring(on) .. "|" .. timeText
		if layout == lastLayout then
			return
		end
		lastLayout = layout
		openButton.BackgroundColor3 = if on then Style.ui.good else Color3.fromRGB(196, 194, 214)
		openButton.TextColor3 = if on then Style.ui.dark else Color3.fromRGB(120, 122, 140)
		timeLabel.Text = timeText
	end)

	CaseModal.open = function()
		if pendingPaid ~= nil then
			return -- a bought case is on screen
		end
		stopSpin()
		fitScale()
		lastLayout = ""
		title.Text = "Free Chest"
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
		openButton.Visible = true
		timeLabel.Visible = true
		showIdleStrip()
		gui.Enabled = true
	end

	-- A bought case is done (the purchase notice): opens the screen on its roulette. A player's
	-- reveal waits until the strip lands.
	CaseModal.openPaid = function(result: any)
		local def = Config.Cases[if type(result.caseId) == "string" then result.caseId else ""]
		local wonId = result.boostId or result.playerId
		if def == nil or type(wonId) ~= "string" then
			return
		end
		if gui.Enabled then
			close_() -- a case still on screen gives its prize now
		end
		if result.playerId ~= nil then
			Reveal.hold()
		end
		RewardCard.hide()
		fitScale()
		title.Text = def.name
		panel.Size = UDim2.fromOffset(PANEL_W, PAID_PANEL_H)
		openButton.Visible = false
		timeLabel.Visible = false
		gui.Enabled = true
		spinPaid(result)
	end

	-- The server's answer to a claim. Returns true when the screen took it.
	CaseModal.onResult = function(prize: any): boolean
		if not gui.Enabled or type(prize) ~= "table" then
			return false
		end
		lastLayout = ""
		spinFree(prize)
		return true
	end
end

-- Replaced by init once the interface is built.
CaseModal.open = function() end
CaseModal.openPaid = function(_result: any) end
CaseModal.onResult = function(_prize: any): boolean
	return false
end

return CaseModal
