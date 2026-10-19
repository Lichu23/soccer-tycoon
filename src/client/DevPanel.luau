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
	{ label = "Reset profile", command = "resetProfile", amount = 0 },
}

-- Two columns, so the panel stays low and never covers the daily icons at the top left.
local COLUMNS = 2
local ROWS = math.ceil(#BUTTONS / COLUMNS)

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

	local frame = Instance.new("Frame")
	-- Bottom left: below the daily icons at the top left, clear of the HUD column on the right.
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 6, 1, -6)
	frame.Size = UDim2.fromOffset(8 + COLUMNS * 118, 8 + ROWS * 26)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	for index, entry in BUTTONS do
		local button = Instance.new("TextButton")
		local column, row = (index - 1) // ROWS, (index - 1) % ROWS
		button.Position = UDim2.fromOffset(4 + column * 118, 4 + row * 26)
		button.Size = UDim2.fromOffset(114, 22)
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
