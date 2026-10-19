--!strict
-- The reminder opt-in (docs/PLAN.md, Step 3, Notifications): one HUD icon under the Locker icon that
-- opens once the player has bought their first player. Nothing pops up by itself; the player turns
-- reminders on or off here at any time. The server saves the answer; this only asks and shows it.

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dock = require(script.Parent.Dock)
local Net = require(script.Parent.Net)
local Notifications = require(ReplicatedStorage.Shared.Notifications)
local Panel = require(script.Parent.Panel)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

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

	local tile =
		Dock.build(gui, "RemindersIcon", 4, "ALERTS", Color3.fromRGB(200, 130, 255), "alerts")
	local icon = tile.button
	local locked = true

	local backdrop: Frame
	local function hide()
		backdrop.Visible = false
	end
	local built = Panel.build(gui, "Reminders", 0.6, hide)
	backdrop = built.backdrop
	local card = built.card

	local function label(order: number, size: number, color: Color3): TextLabel
		return new("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			TextWrapped = true,
			Font = Style.font,
			TextSize = size,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}, card)
	end
	label(1, 17, Panel.TEXT).Text =
		"Tell me when my offline earnings are full or the free case is ready. At most one a day."
	local status = label(2, 17, Panel.MUTED)

	local toggle = new("TextButton", {
		Name = "Toggle",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Style.ui.good,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Style.ui.dark,
		ZIndex = 7,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, toggle)

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
	icon.Activated:Connect(function()
		if locked then
			Dock.reason(tile, "Buy your first player first.")
			return
		end
		render()
		backdrop.Visible = true
	end)

	local function refresh()
		locked = not Notifications.unlocked(State.data)
		Dock.paint(tile, if locked then "locked" else "open")
		if backdrop.Visible then
			render()
		end
	end
	State.onChange(refresh)
	player:GetAttributeChangedSignal("notificationsOn"):Connect(refresh)
	refresh()
end

return NotifyUi
