--!strict
-- The reminder opt-in (docs/PLAN.md, Step 3, Notifications): one HUD icon under the Locker icon that
-- opens once the player has bought their first player. Nothing pops up by itself; the player turns
-- reminders on or off here at any time. The server saves the answer; this only asks and shows it.

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local Notifications = require(ReplicatedStorage.Shared.Notifications)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local CARD_W = 380
local ICON_SIZE = 52
local ICON_TOP = 8 + 4 * (ICON_SIZE + 8) -- under the case, kick, shop and locker icons
local TEXT_COLOR = Color3.fromRGB(215, 220, 232)

local NotifyUi = {}

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

function NotifyUi.init()
	local gui = new("ScreenGui", {
		Name = "Reminders",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local icon = new("TextButton", {
		Name = "RemindersIcon",
		Position = UDim2.fromOffset(8, ICON_TOP),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundColor3 = Style.ui.panel,
		Text = "ALERTS",
		Font = Style.font,
		TextSize = 12,
		TextColor3 = Style.ui.text,
		AutoButtonColor = false,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, icon)

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
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 6,
	}, backdrop)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, card)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	local scale = new("UIScale", {}, card)
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		if size.X < 100 or size.Y < 100 then
			return -- the viewport is not ready yet; the next fit (when the card opens) corrects it
		end
		local naturalHeight = card.AbsoluteSize.Y / scale.Scale
		scale.Scale =
			math.min(1, size.X / (CARD_W + 40), size.Y * 0.92 / math.max(naturalHeight, 1))
	end
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	backdrop:GetPropertyChangedSignal("Visible"):Connect(fit)

	new("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = "Reminders",
		Font = Style.font,
		TextSize = 24,
		TextColor3 = Style.ui.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, card)
	new("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = "Tell me when my offline earnings are full or the free case is ready. At most one a day.",
		TextWrapped = true,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, card)
	local status = new("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Style.font,
		TextSize = 15,
		TextColor3 = TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, card)

	local function button(name: string, order: number, color: Color3): TextButton
		local item = new("TextButton", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = color,
			Font = Style.font,
			TextSize = 17,
			TextColor3 = Style.ui.dark,
			ZIndex = 7,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, item)
		return item
	end
	local toggle = button("Toggle", 4, Style.ui.good)
	local close = button("Close", 5, Style.ui.idle)
	close.Text = "Close"

	local function isOn(): boolean
		return player:GetAttribute("notificationsOn") == true
	end
	local function render()
		status.Text = if isOn() then "Reminders are on." else "Reminders are off."
		toggle.Text = if isOn() then "Turn off" else "Turn on"
	end
	toggle.Activated:Connect(function()
		local turningOn = not isOn()
		Net.fire("SetNotifications", turningOn)
		if turningOn then
			-- Roblox sends notifications only to players who agreed in its own prompt (it shows only
			-- when it is allowed and not asked in the last 30 days).
			task.spawn(function()
				local ok, can = pcall(function()
					return ExperienceNotificationService:CanPromptOptInAsync()
				end)
				if ok and can then
					pcall(function()
						ExperienceNotificationService:PromptOptIn()
					end)
				end
			end)
		end
	end)
	local function hide()
		backdrop.Visible = false
	end
	close.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)
	icon.Activated:Connect(function()
		render()
		backdrop.Visible = true
	end)

	local function refresh()
		icon.Visible = Notifications.unlocked(State.data)
		if backdrop.Visible then
			render()
		end
	end
	State.onChange(refresh)
	player:GetAttributeChangedSignal("notificationsOn"):Connect(refresh)
	refresh()
end

return NotifyUi
