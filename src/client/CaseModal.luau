--!strict
-- The free case screen (docs/PLAN.md, Steps 3 and 7), opened from the Shop. The Standard and Elite
-- cases are bought in the Shop itself. Opening the free case
-- spins a roulette in the style of a case-opening strip: the server has already rolled and paid
-- the reward, so the strip is only a show that slows down and lands on it. With reduced motion the
-- strip is skipped and the reward shows at once.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local RewardCard = require(script.Parent.RewardCard)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 560, 356
local CARD_W, CARD_H, CARD_GAP = 170, 92, 10
local WINDOW_W, WINDOW_H = 524, 92
local TILE_W, TILE_H, TILE_GAP = 96, 80, 6
local TILE_COUNT = 50
local WIN_INDEX = 40
local SPIN_SECONDS = 6
local REPLY_TIMEOUT = 4

local KIND_COLORS: { [string]: Color3 } = {
	cash = Color3.fromRGB(60, 150, 90),
	boost = Color3.fromRGB(190, 140, 40),
	tp = Color3.fromRGB(60, 120, 200),
}

type CaseCard = { button: TextButton, status: TextLabel, stroke: UIStroke }

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
		BackgroundColor3 = KIND_COLORS[reward.kind]:Lerp(Color3.fromRGB(20, 24, 35), 0.55),
	}, parent)
	rounded(tile, 6)
	new("UIStroke", { Name = "Outline", Color = Style.ui.dark, Thickness = 2 }, tile)
	-- The coloured bar on top says what kind of reward it is (like the rarity bar of a case tile).
	local bar = new("Frame", {
		Name = "KindBar",
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = KIND_COLORS[reward.kind]:Lerp(Color3.new(1, 1, 1), 0.25),
		BorderSizePixel = 0,
	}, tile)
	rounded(bar, 3)
	new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(4, 10),
		Size = UDim2.new(1, -8, 0, 30),
		BackgroundTransparency = 1,
		Text = label,
		TextWrapped = true,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Style.ui.text,
	}, tile)
	new("TextLabel", {
		Name = "Detail",
		Position = UDim2.fromOffset(4, 42),
		Size = UDim2.new(1, -8, 0, 28),
		BackgroundTransparency = 1,
		Text = detail,
		TextWrapped = true,
		Font = Style.font,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(235, 235, 235),
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
		Size = UDim2.fromOffset(300, 32),
		BackgroundTransparency = 1,
		Text = "Free case",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 24,
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

	-- The three cases ----------------------------------------------------------------------------
	local cases = {
		{ id = "free", name = "Free Case", sub = "Every 20 hours" },
	}
	local cards: { [string]: CaseCard } = {}
	for index, def in cases do
		local button = new("TextButton", {
			Name = def.id,
			Position = UDim2.fromOffset(
				(PANEL_W - CARD_W) / 2 + (index - 1) * (CARD_W + CARD_GAP),
				52
			),
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundColor3 = Style.ui.dark,
			BackgroundTransparency = 0.25,
			Text = "",
			AutoButtonColor = false,
		}, panel)
		rounded(button, 12)
		local stroke = new("UIStroke", {
			Color = Style.ui.idle,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		new("TextLabel", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 26),
			BackgroundTransparency = 1,
			Text = def.name,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Style.ui.text,
		}, button)
		new("TextLabel", {
			Position = UDim2.fromOffset(8, 34),
			Size = UDim2.new(1, -16, 0, 20),
			BackgroundTransparency = 1,
			Text = def.sub,
			Font = Style.font,
			TextSize = 13,
			TextColor3 = Style.ui.idle,
		}, button)
		local status = new("TextLabel", {
			Position = UDim2.fromOffset(8, 58),
			Size = UDim2.new(1, -16, 0, 26),
			BackgroundTransparency = 1,
			Text = "",
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Style.ui.good,
		}, button)
		cards[def.id] = { button = button, status = status, stroke = stroke }
	end

	-- The area under the cards: the rewards you can get, or the roulette ----------------------------
	local previewTitle = new("TextLabel", {
		Name = "PreviewTitle",
		Position = UDim2.fromOffset(18, 156),
		Size = UDim2.fromOffset(400, 20),
		BackgroundTransparency = 1,
		Text = "You can win",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = Panel.MUTED,
	}, panel)

	local preview = new("Frame", {
		Name = "Preview",
		Position = UDim2.fromOffset(18, 180),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundTransparency = 1,
	}, panel)
	local chipW = (WINDOW_W - 4 * 6) / 5
	for index, reward in Config.Daily.caseRewards do
		local chip = new("Frame", {
			Position = UDim2.fromOffset((index - 1) * (chipW + 6), 6),
			Size = UDim2.fromOffset(chipW, WINDOW_H - 12),
			BackgroundColor3 = KIND_COLORS[reward.kind],
		}, preview)
		rounded(chip, 8)
		new("TextLabel", {
			Position = UDim2.fromOffset(2, 6),
			Size = UDim2.new(1, -4, 0, 28),
			BackgroundTransparency = 1,
			Text = reward.label,
			TextWrapped = true,
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Style.ui.text,
		}, chip)
		new("TextLabel", {
			Position = UDim2.fromOffset(2, 34),
			Size = UDim2.new(1, -4, 0, 20),
			BackgroundTransparency = 1,
			Text = reward.detail,
			TextWrapped = true,
			Font = Style.font,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(235, 235, 235),
		}, chip)
		new("TextLabel", {
			Position = UDim2.fromOffset(2, 54),
			Size = UDim2.new(1, -4, 0, 18),
			BackgroundTransparency = 1,
			Text = string.format("%d%%", math.floor(reward.weight / totalWeight * 100 + 0.5)),
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Style.ui.gold,
		}, chip)
	end

	local lockedText = new("TextLabel", {
		Name = "LockedText",
		Position = UDim2.fromOffset(18, 180),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		Font = Style.font,
		TextSize = 18,
		TextColor3 = Style.ui.idle,
		Visible = false,
	}, panel)

	-- The roulette window: a clipped strip of tiles with a marker in the middle.
	local window = new("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(18, 180),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = Style.ui.dark,
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		Visible = false,
	}, panel)
	rounded(window, 10)
	local strip = new("Frame", {
		Name = "Strip",
		Size = UDim2.fromOffset(TILE_COUNT * (TILE_W + TILE_GAP), WINDOW_H),
		BackgroundTransparency = 1,
	}, window)
	-- The indicator: a thin line through the middle that reaches above and below the strip, with a
	-- little arrow on top (it is a sibling of the window, because the window clips its children).
	local marker = new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(18 + WINDOW_W / 2, 180 - 12),
		Size = UDim2.fromOffset(3, WINDOW_H + 24),
		BackgroundColor3 = Color3.fromRGB(255, 150, 40),
		BorderSizePixel = 0,
		ZIndex = 6,
		Visible = false,
	}, panel)
	new("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(26, 18),
		BackgroundTransparency = 1,
		Text = "▼",
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(255, 150, 40),
		ZIndex = 6,
	}, marker)

	local resultLabel = new("TextLabel", {
		Name = "Result",
		Position = UDim2.fromOffset(18, 274),
		Size = UDim2.fromOffset(WINDOW_W, 24),
		BackgroundTransparency = 1,
		Text = "",
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.gold,
	}, panel)

	local openButton = new("TextButton", {
		Name = "Open",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(240, 40),
		BackgroundColor3 = Style.ui.good,
		Text = "OPEN",
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.dark,
		AutoButtonColor = false,
	}, panel)
	rounded(openButton, 12)

	-- State --------------------------------------------------------------------------------------
	local selected = "free"
	local mode: string = "idle" -- "idle", "waiting" (sent, no answer yet) or "spinning"
	local token = 0
	local function modeNow(): string
		return mode
	end
	local activeTween: Tween? = nil
	local random = Random.new()

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

	local function stopSpin()
		token += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		mode = "idle"
	end

	local function showArea(which: string)
		preview.Visible = which == "preview"
		window.Visible = which == "window"
		lockedText.Visible = which == "locked"
		marker.Visible = which == "window"
		previewTitle.Visible = which ~= "window"
	end

	local function selectCase(id: string)
		if mode ~= "idle" then
			return
		end
		selected = id
		resultLabel.Text = ""
		if id == "free" then
			showArea("preview")
		else
			showArea("locked")
			lockedText.Text =
				"Coming soon. This case will give players, with the odds shown before you open it."
		end
	end
	for id, card in cards do
		card.button.Activated:Connect(function()
			selectCase(id)
		end)
	end

	local function close_()
		stopSpin()
		gui.Enabled = false
	end
	close.Activated:Connect(close_)
	backdrop.Activated:Connect(close_)

	-- Builds the strip with the won reward on WIN_INDEX and spins it to a stop under the marker.
	local function spin(prize: any)
		local won = rewardById(prize.id)
		if won == nil then
			RewardCard.freeCase(prize)
			mode = "idle"
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
		showArea("window")
		resultLabel.Text = ""

		local step = TILE_W + TILE_GAP
		local jitter = (random:NextNumber() - 0.5) * TILE_W * 0.6
		local landed = WINDOW_W / 2 - ((WIN_INDEX - 1) * step + TILE_W / 2 + jitter)
		local function finish()
			local tile = strip:FindFirstChild("Tile" .. WIN_INDEX)
			if tile then
				local outline = tile:FindFirstChild("Outline")
				if outline and outline:IsA("UIStroke") then
					outline.Color = Style.ui.gold
					outline.Thickness = 4
				end
			end
			strip.Position = UDim2.fromOffset(landed, 0)
			marker.Visible = false -- the line would cross the reward card's place
			RewardCard.freeCase(prize)
			mode = "idle"
		end

		mode = "spinning"
		token += 1
		local myToken = token
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
		if mode ~= "idle" or selected ~= "free" or freeStatus() ~= "ready" then
			return
		end
		mode = "waiting"
		resultLabel.Text = ""
		token += 1
		local myToken = token
		Net.fire("ClaimDaily", "case")
		task.delay(REPLY_TIMEOUT, function()
			if modeNow() == "waiting" and token == myToken then
				mode = "idle" -- the server never answered: let the player try again
			end
		end)
	end)

	-- Keeps the cards and the button in step with the server's ready time.
	local lastLayout = ""
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local status = freeStatus()
		local now = Workspace:GetServerTimeNow()
		local freeText = if status == "ready"
			then "Ready"
			elseif status == "waiting" then DailyInfo.waitText(readyAt() - now)
			else "Locked"
		local buttonText = "LOCKED"
		local buttonOn = false
		if selected == "free" then
			if mode ~= "idle" then
				buttonText = if mode == "waiting" then "OPENING..." else "SPINNING..."
			elseif status == "ready" then
				buttonText, buttonOn = "OPEN", true
			elseif status == "waiting" then
				buttonText = DailyInfo.waitText(readyAt() - now)
			end
		end
		local layout = freeText .. "|" .. buttonText .. "|" .. selected
		if layout == lastLayout then
			return
		end
		lastLayout = layout
		cards.free.status.Text = freeText
		cards.free.status.TextColor3 = if status == "ready" then Style.ui.good else Style.ui.idle
		for id, card in cards do
			card.stroke.Color = if id == selected then Style.ui.gold else Style.ui.idle
		end
		openButton.Text = buttonText
		openButton.BackgroundColor3 = if buttonOn then Style.ui.good else Style.ui.idle
		openButton.BackgroundTransparency = if buttonOn then 0 else 0.4
	end)

	CaseModal.open = function()
		stopSpin()
		fitScale()
		lastLayout = ""
		selected = "free"
		showArea("preview")
		resultLabel.Text = ""
		gui.Enabled = true
	end

	-- The server's answer to a claim. Returns true when the modal showed it.
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
