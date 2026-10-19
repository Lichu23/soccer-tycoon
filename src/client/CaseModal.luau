--!strict
-- The free case screen (docs/PLAN.md, Steps 3 and 7), opened from the Shop. A title, the roulette strip,
-- one button and, under it, when the next one opens. The server has already rolled and paid the reward
-- when the strip starts; the strip is only a show that slows down and lands on it. When it has landed the
-- screen closes and the reward card says what was won (RewardCard). With reduced motion the strip is
-- skipped and the card shows at once. The Standard and Elite cases are bought in the Shop itself.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Panel = require(script.Parent.Panel)
local RewardCard = require(script.Parent.RewardCard)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 520, 292
local WINDOW_W, WINDOW_H = 480, 92
local TILE_W, TILE_H, TILE_GAP = 96, 74, 6
local TILE_COUNT = 50
local WIN_INDEX = 40
local IDLE_CENTER_INDEX = 3 -- the tile under the marker before a spin
local SPIN_SECONDS = 6
local HOLD_SECONDS = 0.9 -- the landed tile stays in view this long before the screen closes
local REPLY_TIMEOUT = 4

-- Bright flat colours with dark text, like the cards of the Shop.
local KIND_COLORS: { [string]: Color3 } = {
	cash = Color3.fromRGB(96, 205, 128),
	boost = Color3.fromRGB(255, 200, 70),
	tp = Color3.fromRGB(100, 175, 255),
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

-- What a tile says: the label and a detail line. The winning tile shows the real amount.
local function tileTexts(reward: Config.CaseReward, prize: any?): (string, string)
	if prize ~= nil and type(prize.amount) == "number" then
		if prize.kind == "cash" then
			return reward.label, "+" .. NumberFormat.money(prize.amount)
		elseif prize.kind == "tp" then
			return reward.label, "+" .. prize.amount .. " TP"
		end
	end
	return reward.label, reward.detail
end

local function makeTile(parent: Instance, reward: Config.CaseReward, index: number, prize: any?)
	local label, detail = tileTexts(reward, prize)
	local tile = new("Frame", {
		Name = "Tile" .. index,
		Position = UDim2.fromOffset((index - 1) * (TILE_W + TILE_GAP), (WINDOW_H - TILE_H) / 2),
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		BackgroundColor3 = KIND_COLORS[reward.kind],
	}, parent)
	rounded(tile, 10)
	new("UIStroke", {
		Name = "Outline",
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, tile)
	new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(4, 8),
		Size = UDim2.new(1, -8, 0, 30),
		BackgroundTransparency = 1,
		Text = label,
		TextWrapped = true,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.dark,
	}, tile)
	new("TextLabel", {
		Name = "Detail",
		Position = UDim2.fromOffset(4, 40),
		Size = UDim2.new(1, -8, 0, 26),
		BackgroundTransparency = 1,
		Text = detail,
		TextWrapped = true,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Panel.TEXT,
	}, tile)
	return tile
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

	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(300, 36),
		BackgroundTransparency = 1,
		Text = "Free Case",
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
			TextColor3 = Color3.fromRGB(232, 64, 96),
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
			makeTile(strip, rewards[(index - 1) % #rewards + 1], index, nil)
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
	local function deliver()
		local prize = pendingPrize
		pendingPrize = nil
		if prize ~= nil then
			RewardCard.freeCase(prize)
		end
		State.releaseReward()
	end

	local function close_()
		deliver()
		stopSpin()
		gui.Enabled = false
	end
	close.Activated:Connect(close_)
	backdrop.Activated:Connect(close_)

	-- Builds the strip with the won reward on WIN_INDEX and spins it to a stop under the marker.
	local function spin(prize: any)
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
				makeTile(strip, won, index, prize)
			else
				makeTile(strip, randomReward(random), index, nil)
			end
		end

		local jitter = (random:NextNumber() - 0.5) * TILE_W * 0.6
		local landed = WINDOW_W / 2 - ((WIN_INDEX - 1) * step + TILE_W / 2 + jitter)
		mode = "spinning"
		token += 1
		local myToken = token
		-- The strip has landed: the winning tile is outlined in gold, then the screen closes and the
		-- reward card says what was won.
		local function finish()
			local tile = strip:FindFirstChild("Tile" .. WIN_INDEX)
			if tile then
				local outline = tile:FindFirstChild("Outline")
				if outline and outline:IsA("UIStroke") then
					outline.Color = Color3.fromRGB(232, 64, 96)
					outline.Thickness = 5
				end
			end
			strip.Position = UDim2.fromOffset(landed, 0)
			mode = "idle"
			if GuiService.ReducedMotionEnabled then
				close_()
				return
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
		tween.Completed:Connect(function(state)
			if token == myToken and state == Enum.PlaybackState.Completed then
				activeTween = nil
				finish()
			end
		end)
		tween:Play()
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
		stopSpin()
		fitScale()
		lastLayout = ""
		showIdleStrip()
		gui.Enabled = true
	end

	-- The server's answer to a claim. Returns true when the screen took it.
	CaseModal.onResult = function(prize: any): boolean
		if not gui.Enabled or type(prize) ~= "table" then
			return false
		end
		lastLayout = ""
		spin(prize)
		return true
	end
end

-- Replaced by init once the interface is built.
CaseModal.open = function() end
CaseModal.onResult = function(_prize: any): boolean
	return false
end

return CaseModal
