--!strict
-- Draws the four plaza leaderboards around the spawn (shared/Leaderboards). The server publishes
-- each board's top 10 as JSON on ReplicatedStorage.Leaderboards; this only shows it on the Screen
-- part of the matching board model (built by tools/studio/BuildLeaderboards). The local player's
-- row has an accent border.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Boards = require(ReplicatedStorage.Shared.Leaderboards)
local Style = require(ReplicatedStorage.Shared.Style)

local PIXELS_PER_STUD = 50
local MAX_DISTANCE = 220 -- studs; past this the screen is not drawn
local TITLE_HEIGHT = 96
local ROW_HEIGHT = 70
local ROW_GAP = 8
local PAD = 18
local OUTLINE = Color3.fromRGB(20, 24, 35) -- the dark outline of the world text (PadRing)
local ROW_COLOR = Color3.fromRGB(44, 52, 76) -- a row on the navy screen
local MEDALS = {
	Style.ui.gold,
	Color3.fromRGB(205, 210, 222), -- silver
	Color3.fromRGB(214, 140, 72), -- bronze
}

type Row = {
	frame: Frame,
	stroke: UIStroke,
	rank: TextLabel,
	head: ImageLabel,
	name: TextLabel,
	value: TextLabel,
}

local Scoreboards = {}

local function text(parent: Instance, name: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Style.font
	label.TextSize = size
	label.TextColor3 = color
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Thickness = math.max(2, size / 9)
	outline.Color = OUTLINE
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = label
	return label
end

local function corner(parent: Instance, radius: number)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, radius)
	round.Parent = parent
end

local function buildRow(parent: Instance, index: number, width: number): Row
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. index
	frame.Size = UDim2.fromOffset(width, ROW_HEIGHT)
	frame.Position =
		UDim2.fromOffset(PAD, TITLE_HEIGHT + PAD + (index - 1) * (ROW_HEIGHT + ROW_GAP))
	frame.BackgroundColor3 = ROW_COLOR
	frame.Visible = false
	frame.Parent = parent
	corner(frame, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Enabled = false
	stroke.Parent = frame

	local rank = text(frame, "Rank", 32, Style.ui.text)
	rank.Size = UDim2.fromOffset(54, 54)
	rank.Position = UDim2.fromOffset(8, 8)
	rank.Text = tostring(index)
	rank.BackgroundColor3 = MEDALS[index] or ROW_COLOR
	rank.BackgroundTransparency = if MEDALS[index] then 0 else 1
	corner(rank, 27)

	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.Size = UDim2.fromOffset(54, 54)
	head.Position = UDim2.fromOffset(70, 8)
	head.BackgroundColor3 = Style.ui.panel
	head.Parent = frame
	corner(head, 27)

	local name = text(frame, "PlayerName", 34, Style.ui.text)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Size = UDim2.new(1, -350, 1, 0)
	name.Position = UDim2.fromOffset(136, 0)

	local value = text(frame, "Value", 34, Style.ui.text)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Size = UDim2.new(0, 200, 1, 0)
	value.Position = UDim2.new(1, -16, 0, 0)

	return { frame = frame, stroke = stroke, rank = rank, head = head, name = name, value = value }
end

-- Reads the board's published list; a missing or broken value reads as empty.
local function entriesOf(source: Instance, boardId: string): { Boards.Entry }
	local raw = source:GetAttribute(boardId)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(decoded) == "table" then decoded else {}
end

local function showBoard(board: Boards.Board, screen: BasePart, source: Instance)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Scoreboard_" .. board.id
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local width = screen.Size.X * PIXELS_PER_STUD

	-- The title on a chip in the board's accent colour, with the dark stroke of the modal chips.
	local chip = Instance.new("Frame")
	chip.Name = "TitleChip"
	chip.Size = UDim2.new(1, -2 * PAD, 0, TITLE_HEIGHT - PAD)
	chip.Position = UDim2.fromOffset(PAD, PAD)
	chip.BackgroundColor3 = Style.ui[board.accent]
	chip.Parent = gui
	corner(chip, 18)
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Thickness = 3
	chipStroke.Color = OUTLINE
	chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chipStroke.Parent = chip
	local title = text(chip, "Title", 44, Style.ui.text)
	title.Size = UDim2.fromScale(1, 1)
	title.Text = board.title

	local empty = text(gui, "Empty", 32, Style.ui.idle)
	empty.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	empty.Position = UDim2.fromOffset(0, TITLE_HEIGHT + PAD)
	empty.Text = "No scores yet"

	local rows: { Row } = {}
	for index = 1, Boards.SIZE do
		rows[index] = buildRow(gui, index, width - 2 * PAD)
	end

	local function refresh()
		local entries = entriesOf(source, board.id)
		local me = Players.LocalPlayer.UserId
		empty.Visible = #entries == 0
		for index, row in rows do
			local entry = entries[index]
			row.frame.Visible = entry ~= nil
			if entry then
				row.name.Text = if entry.name ~= "" then entry.name else "Player"
				row.value.Text = board.format(entry.value)
				row.value.TextColor3 = Style.ui[board.accent]
				row.head.Image = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=150&h=150`
				row.stroke.Enabled = entry.userId == me
				row.stroke.Color = Style.ui[board.accent]
			end
		end
	end
	source:GetAttributeChangedSignal(board.id):Connect(refresh)
	refresh()
end

function Scoreboards.init()
	task.spawn(function()
		local source = ReplicatedStorage:WaitForChild("Leaderboards")
		local map = Workspace:WaitForChild("Map")
		local plaza = map:WaitForChild("Plaza")
		local models = plaza:WaitForChild("Leaderboards")
		for _, board in Boards.boards do
			task.spawn(function()
				local model = models:WaitForChild(board.id)
				local screen = model:WaitForChild("Screen")
				if screen:IsA("BasePart") then
					showBoard(board, screen, source)
				end
			end)
		end
	end)
end

return Scoreboards
