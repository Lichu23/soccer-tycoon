--!strict
-- A label above each stair marker ("Floor 2": can buy yet or not), drawn on top of walls so the
-- stairs are easy to find from across the building. The stairs are never blocked. The server tags
-- each marker "FloorGate" and keeps its Open attribute up to date (docs/PLAN.md, Step 1: players of
-- a floor can be bought when the one before is complete).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(ReplicatedStorage.Shared.Style)

local MAX_DISTANCE = 140

local GateLabels = {}

local function refresh(gate: BasePart, title: TextLabel, note: TextLabel)
	local floor = gate:GetAttribute("Floor")
	local open = gate:GetAttribute("Open") == true
	local floorNumber = if type(floor) == "number" then floor else 0
	title.Text = "FLOOR " .. floorNumber
	if open then
		note.Text = "Players open to buy"
		note.TextColor3 = Style.ui.good
	else
		note.Text = "Look around. Buy after floor " .. math.max(floorNumber - 1, 1)
		note.TextColor3 = Style.ui.bad
	end
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild("GateLabel") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GateLabel"
	billboard.Size = UDim2.fromOffset(200, 64)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = MAX_DISTANCE
	billboard.ResetOnSpawn = false
	billboard.Adornee = instance

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.fromOffset(200, 34)
	title.BackgroundTransparency = 1
	title.Font = Style.font
	title.TextSize = 26
	title.TextColor3 = Style.ui.text
	title.TextStrokeTransparency = 0.2
	title.TextStrokeColor3 = Style.ui.dark
	title.Parent = billboard

	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.Position = UDim2.fromOffset(0, 34)
	note.Size = UDim2.fromOffset(200, 26)
	note.BackgroundTransparency = 1
	note.Font = Style.font
	note.TextSize = 16
	note.TextStrokeTransparency = 0.2
	note.TextStrokeColor3 = Style.ui.dark
	note.Parent = billboard

	billboard.Parent = instance
	refresh(instance, title, note)
	instance:GetAttributeChangedSignal("Open"):Connect(function()
		refresh(instance, title, note)
	end)
end

function GateLabels.init()
	CollectionService:GetInstanceAddedSignal("FloorGate"):Connect(track)
	for _, gate in CollectionService:GetTagged("FloorGate") do
		track(gate)
	end
end

return GateLabels
