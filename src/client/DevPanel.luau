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
	{ label = "Away 1 hour", command = "simulateAway", amount = 1 },
	{ label = "Away 8 hours", command = "simulateAway", amount = 8 },
	{ label = "Reset profile", command = "resetProfile", amount = 0 },
}

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
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 6, 0.5, 0)
	frame.Size = UDim2.fromOffset(122, 8 + #BUTTONS * 26)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	for index, entry in BUTTONS do
		local button = Instance.new("TextButton")
		button.Position = UDim2.fromOffset(4, 4 + (index - 1) * 26)
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
