--!strict
-- The Legend Trial panel above each Legend capsule in the Legends hall (docs/PLAN.md, Step 1): the
-- name, the cash price and the goals with how far the player is. Greyed until floor 4 is reached.
-- Display only: the pad decides the purchase. The server tags each capsule "LegendCapsule".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Legends = require(ReplicatedStorage.Shared.Legends)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local PANEL_WIDTH = 240
local TITLE_HEIGHT = 50
local ROW_HEIGHT = 24
local MAX_DISTANCE = 70
local ROW_COUNT = 3

type Row = { dot: Frame, text: TextLabel, count: TextLabel }
type Panel = {
	capsule: Instance,
	playerId: string,
	billboard: BillboardGui,
	frame: Frame,
	name: TextLabel,
	price: TextLabel,
	rows: { Row },
}

local panels: { Panel } = {}

local LegendPanels = {}

local function text(parent: Instance, size: number, alignment: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Style.font
	label.TextSize = size
	label.TextXAlignment = alignment
	label.TextColor3 = Style.ui.text
	label.Parent = parent
	return label
end

local function buildRow(parent: Instance, index: number): Row
	local top = TITLE_HEIGHT + (index - 1) * ROW_HEIGHT
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. index
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromOffset(12, top + ROW_HEIGHT / 2)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.BorderSizePixel = 0
	dot.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local label = text(parent, 15, Enum.TextXAlignment.Left)
	label.Name = "Goal" .. index
	label.Position = UDim2.fromOffset(32, top)
	label.Size = UDim2.fromOffset(PANEL_WIDTH - 80, ROW_HEIGHT)

	local count = text(parent, 15, Enum.TextXAlignment.Right)
	count.Name = "Count" .. index
	count.Position = UDim2.fromOffset(PANEL_WIDTH - 52, top)
	count.Size = UDim2.fromOffset(40, ROW_HEIGHT)
	return { dot = dot, text = label, count = count }
end

local function build(capsule: Instance, playerId: string): Panel?
	local glass = capsule:FindFirstChild("Glass")
	if glass == nil or not glass:IsA("BasePart") then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LegendPanel"
	billboard.Size = UDim2.fromOffset(PANEL_WIDTH, TITLE_HEIGHT + ROW_COUNT * ROW_HEIGHT + 8)
	billboard.StudsOffset = Vector3.new(0, glass.Size.Y / 2 + 4, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = MAX_DISTANCE
	billboard.ResetOnSpawn = false
	billboard.Adornee = glass

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Style.ui.dark
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local name = text(frame, 22, Enum.TextXAlignment.Left)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(12, 4)
	name.Size = UDim2.fromOffset(PANEL_WIDTH - 24, 26)
	local price = text(frame, 16, Enum.TextXAlignment.Left)
	price.Name = "Price"
	price.Position = UDim2.fromOffset(12, 28)
	price.Size = UDim2.fromOffset(PANEL_WIDTH - 24, 20)

	local rows: { Row } = {}
	for index = 1, ROW_COUNT do
		table.insert(rows, buildRow(frame, index))
	end
	billboard.Parent = capsule
	return {
		capsule = capsule,
		playerId = playerId,
		billboard = billboard,
		frame = frame,
		name = name,
		price = price,
		rows = rows,
	}
end

local function refresh(panel: Panel)
	local def = Config.PlayersById[panel.playerId]
	if def == nil then
		return
	end
	local data = State.data
	local status = Legends.status(data, panel.playerId)
	local owned = status == "owned"
	local reached = Legends.reached(data)
	panel.name.Text = def.name
	panel.name.TextColor3 = if reached or owned then Style.ui.gold else Style.ui.idle
	panel.price.Text = if owned then "Yours" else NumberFormat.money(def.price)
	panel.price.TextColor3 = if reached or owned then Style.ui.money else Style.ui.idle

	local goals = Legends.goals(data, panel.playerId)
	for index, row in panel.rows do
		local goal = goals[index]
		local visible = goal ~= nil and not owned
		row.dot.Visible = visible
		row.text.Visible = visible
		row.count.Visible = visible
		if goal and visible then
			local color = if goal.done and reached
				then Style.ui.good
				elseif goal.done then Style.ui.idle
				else Style.ui.text
			row.dot.BackgroundColor3 = if goal.done then color else Color3.fromRGB(70, 76, 96)
			row.text.Text = goal.text
			row.text.TextColor3 = if reached or goal.done then color else Style.ui.idle
			row.count.Text = `{goal.have}/{goal.need}`
			row.count.TextColor3 = row.text.TextColor3
		end
	end
	local rowsShown = if owned then 0 else #goals
	panel.billboard.Size = UDim2.fromOffset(PANEL_WIDTH, TITLE_HEIGHT + rowsShown * ROW_HEIGHT + 8)
end

local function track(capsule: Instance)
	local playerId = capsule:GetAttribute("PlayerId")
	if type(playerId) ~= "string" or capsule:FindFirstChild("LegendPanel") then
		return
	end
	local panel = build(capsule, playerId)
	if panel then
		table.insert(panels, panel)
		refresh(panel)
	end
end

function LegendPanels.init()
	CollectionService:GetInstanceAddedSignal("LegendCapsule"):Connect(track)
	for _, capsule in CollectionService:GetTagged("LegendCapsule") do
		track(capsule)
	end
	State.onChange(function()
		for index = #panels, 1, -1 do
			local panel = panels[index]
			if panel.capsule.Parent == nil then
				table.remove(panels, index) -- the plot was removed
			else
				refresh(panel)
			end
		end
	end)
end

return LegendPanels
