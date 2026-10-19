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

-- Sized in studs (not pixels) so neighbouring panels never overlap: the capsules are about 21 studs
-- apart. Every position inside is a fraction of the panel.
local PANEL_STUDS = Vector2.new(19, 8)
local OWNED_STUDS = Vector2.new(19, 4)
local LIFT_STUDS = 10.5 -- above the middle of the glass, clear of the pad name and ring
local MAX_DISTANCE = 60
local ROW_COUNT = 3
local ROW_TOP = 0.36
local ROW_HEIGHT = 0.2

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
local tracked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local LegendPanels = {}

local function text(
	parent: Instance,
	maxSize: number,
	alignment: Enum.TextXAlignment,
	position: UDim2,
	size: UDim2
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Style.font
	label.TextScaled = true
	label.TextXAlignment = alignment
	label.TextColor3 = Style.ui.text
	label.Position = position
	label.Size = size
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	return label
end

local function buildRow(parent: Instance, index: number): Row
	local top = ROW_TOP + (index - 1) * ROW_HEIGHT
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. index
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromScale(0.05, top + ROW_HEIGHT / 2)
	dot.Size = UDim2.fromScale(0.04, 0.09)
	dot.BorderSizePixel = 0
	dot.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = dot

	local label = text(
		parent,
		40,
		Enum.TextXAlignment.Left,
		UDim2.fromScale(0.13, top),
		UDim2.fromScale(0.61, ROW_HEIGHT)
	)
	label.Name = "Goal" .. index
	local count = text(
		parent,
		40,
		Enum.TextXAlignment.Right,
		UDim2.fromScale(0.75, top),
		UDim2.fromScale(0.2, ROW_HEIGHT)
	)
	count.Name = "Count" .. index
	return { dot = dot, text = label, count = count }
end

local function build(capsule: Instance, playerId: string): Panel?
	-- With streaming a capsule can arrive before its parts, so wait for the glass (bounded).
	local glass = capsule:WaitForChild("Glass", 10)
	if glass == nil or not glass:IsA("BasePart") then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LegendPanel"
	billboard.Size = UDim2.fromScale(PANEL_STUDS.X, PANEL_STUDS.Y)
	billboard.StudsOffset = Vector3.new(0, LIFT_STUDS, 0)
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

	local name = text(
		frame,
		60,
		Enum.TextXAlignment.Left,
		UDim2.fromScale(0.05, 0.04),
		UDim2.fromScale(0.9, 0.18)
	)
	name.Name = "Name"
	local price = text(
		frame,
		40,
		Enum.TextXAlignment.Left,
		UDim2.fromScale(0.05, 0.22),
		UDim2.fromScale(0.9, 0.12)
	)
	price.Name = "Price"

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
	local studs = if owned then OWNED_STUDS else PANEL_STUDS
	panel.billboard.Size = UDim2.fromScale(studs.X, studs.Y)
	-- The title keeps its size in studs: a shorter panel needs a taller share for it.
	panel.name.Size = UDim2.fromScale(0.9, if owned then 0.4 else 0.18)
	panel.price.Position = UDim2.fromScale(0.05, if owned then 0.46 else 0.22)
	panel.price.Size = UDim2.fromScale(0.9, if owned then 0.3 else 0.12)
end

local function track(capsule: Instance)
	local playerId = capsule:GetAttribute("PlayerId")
	if type(playerId) ~= "string" or tracked[capsule] then
		return
	end
	tracked[capsule] = true
	task.spawn(function()
		local panel = build(capsule, playerId)
		if panel then
			table.insert(panels, panel)
			refresh(panel)
		end
	end)
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
