--!strict
-- A small panel of test buttons, shown only while running in Studio (docs/PLAN.md, Step 6). It
-- asks the server for floors and cash; the server ignores the request outside Studio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)

local player = Players.LocalPlayer

local DevPanel = {}

type DevButton = { label: string, command: string, amount: number }

local BUTTONS: { DevButton } = {
	{ label = "Floor 1 done", command = "grantFloor", amount = 1 },
	{ label = "Floor 2 done", command = "grantFloor", amount = 2 },
	{ label = "Floor 3 done", command = "grantFloor", amount = 3 },
	{ label = "Cash $1M", command = "setCash", amount = 1_000_000 },
	{ label = "Cash $1B", command = "setCash", amount = 1_000_000_000 },
	{ label = "Cash $1T", command = "setCash", amount = 1_000_000_000_000 },
	{ label = "Stadium tier +1", command = "stadiumUp", amount = 0 },
	{ label = "Away 1 hour", command = "simulateAway", amount = 1 },
	{ label = "Away 8 hours", command = "simulateAway", amount = 8 },
	{ label = "+1000 TP", command = "grantTp", amount = 1000 },
	{ label = "Daily ready again", command = "resetDaily", amount = 0 },
	{ label = "Reveal Common", command = "revealRarity", amount = 1 },
	{ label = "Reveal Rare", command = "revealRarity", amount = 2 },
	{ label = "Reveal Very Rare", command = "revealRarity", amount = 3 },
	{ label = "Reveal Epic", command = "revealRarity", amount = 4 },
	{ label = "Reveal Legend", command = "revealRarity", amount = 5 },
	{ label = "Cases open", command = "offerWait", amount = 0 },
	{ label = "Reset profile", command = "resetProfile", amount = 0 },
}

local BAR_HEIGHT = 32
local BUTTON_WIDTH = 124

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	-- One row of buttons along the bottom edge, scrolling sideways when the screen is narrow.
	local frame = Instance.new("ScrollingFrame")
	frame.Name = "Row"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.fromScale(0, 1)
	frame.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.ScrollingDirection = Enum.ScrollingDirection.X
	frame.AutomaticCanvasSize = Enum.AutomaticSize.X
	frame.CanvasSize = UDim2.fromOffset(0, 0)
	frame.ScrollBarThickness = 3
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = frame

	for index, entry in BUTTONS do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(BUTTON_WIDTH, 22)
		button.BackgroundColor3 = Color3.fromRGB(60, 66, 90)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 12
		button.Text = entry.label
		button.Parent = frame
		button.Activated:Connect(function()
			Net.fire("DevCommand", entry.command, entry.amount)
		end)
	end
end

return DevPanel
