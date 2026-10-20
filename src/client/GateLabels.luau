--!strict
-- A label above each stair marker ("Floor 2"), drawn on top of walls so the stairs are easy to find
-- from across the building. The stairs are never blocked. The server tags each marker "FloorGate".
-- Whether the floor can be bought yet is only said when the player tries to buy (PadHint).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(ReplicatedStorage.Shared.Style)

local MAX_DISTANCE = 140

local GateLabels = {}

local function refresh(gate: BasePart, title: TextLabel)
	local floor = gate:GetAttribute("Floor")
	title.Text = "FLOOR " .. (if type(floor) == "number" then floor else 0)
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild("GateLabel") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GateLabel"
	billboard.Size = UDim2.fromOffset(200, 40)
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

	billboard.Parent = instance
	refresh(instance, title)
end

function GateLabels.init()
	CollectionService:GetInstanceAddedSignal("FloorGate"):Connect(track)
	for _, gate in CollectionService:GetTagged("FloorGate") do
		track(gate)
	end
end

return GateLabels
