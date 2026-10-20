--!strict
-- What every pad looks like (docs/PLAN.md, Step 1 and 7). Pads that buy or upgrade something are
-- small round discs coloured by what the player can do: green = can use it now, red = it is open but
-- costs more than the player has, grey = not open yet (a floor or the goals of a Legend). Above each
-- pad sits a label with the name, the price and a short note (the goals, for a Legend), as white and
-- green text with a thick black outline and no box, like the signs of other tycoons. The
-- server times the hold; this only draws it from the player's attributes: padKey, padState, padStart
-- and padHold, as a thin bar at the bottom of the label.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local PadInfo = require(ReplicatedStorage.Shared.PadInfo)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local SHOWN_KINDS = {
	claim = true,
	player = true,
	legend = true,
	store = true,
	stadium = true,
	penalty = true,
	training = true,
}
-- These kinds are drawn as a round disc; the others keep the glowing square of the template.
local DISC_KINDS = { player = true, legend = true, store = true, stadium = true }
local MAX_DISTANCE = 30
local STADIUM_MAX_DISTANCE = 140
local LABEL_WIDTH = 240
local DISC_THICKNESS = 0.5
local MAX_LINES = 3

local COLORS = {
	ready = Color3.fromRGB(70, 200, 105),
	cannotAfford = Color3.fromRGB(225, 70, 70),
	idle = Color3.fromRGB(125, 130, 145),
}
-- Bright text colours; the thick black outline keeps them readable on any floor or sky.
local TITLE_COLOR = Color3.fromRGB(255, 255, 255)
local NOTE_COLOR = Color3.fromRGB(235, 238, 245)
local PRICE_COLOR = Color3.fromRGB(95, 235, 120)
local BAD_COLOR = Color3.fromRGB(255, 110, 110)
local GOAL_DONE_COLOR = Color3.fromRGB(95, 235, 120)
local OUTLINE_COLOR = Color3.fromRGB(0, 0, 0)

type Entry = {
	part: BasePart,
	billboard: BillboardGui,
	disc: BasePart?,
	title: TextLabel,
	price: TextLabel,
	note: TextLabel,
	lines: { TextLabel },
	track: Frame,
	fill: Frame,
	kind: string,
	padId: string,
	key: string,
	fraction: number,
}

local entries: { [BasePart]: Entry } = {}

local PadRing = {}

local function padColor(state: string): Color3
	if state == "ready" then
		return COLORS.ready
	elseif state == "cannotAfford" then
		return COLORS.cannotAfford
	end
	return COLORS.idle
end

local function label(parent: Instance, name: string, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	text.Font = Style.font
	text.TextSize = size
	text.TextColor3 = color
	text.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Thickness = math.max(2, size / 7)
	outline.Color = OUTLINE_COLOR
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = text
	return text
end

-- The text label above the pad. It grows upward from its bottom edge, so a Legend's goal rows sit
-- above the name and the price stays close to the pad.
local function buildBillboard(part: BasePart): (
	BillboardGui,
	TextLabel,
	TextLabel,
	TextLabel,
	{ TextLabel },
	Frame,
	Frame
)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PadBillboard"
	billboard.Size = UDim2.fromOffset(LABEL_WIDTH, 220)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.MaxDistance = MAX_DISTANCE
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Adornee = part

	local frame = Instance.new("Frame")
	frame.Name = "Label"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 1)
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = billboard
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 3)
	layout.Parent = frame

	local title = label(frame, "Title", 24, TITLE_COLOR)
	title.LayoutOrder = 1
	local price = label(frame, "Price", 30, PRICE_COLOR)
	price.LayoutOrder = 2
	local note = label(frame, "Note", 18, NOTE_COLOR)
	note.LayoutOrder = 3
	local lines: { TextLabel } = {}
	for index = 1, MAX_LINES do
		local line = label(frame, "Line" .. index, 18, NOTE_COLOR)
		line.LayoutOrder = 3 + index
		table.insert(lines, line)
	end

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.LayoutOrder = 9
	track.Size = UDim2.new(1, 0, 0, 5)
	track.BackgroundColor3 = Color3.fromRGB(60, 66, 85)
	track.BorderSizePixel = 0
	track.Visible = false
	track.Parent = frame
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLORS.ready
	fill.BorderSizePixel = 0
	fill.Parent = track

	billboard.Parent = part
	return billboard, title, price, note, lines, track, fill
end

-- A flat round disc on top of the pad part, which is hidden for this player.
local function buildDisc(part: BasePart): BasePart
	local disc = Instance.new("Part")
	disc.Name = "PadDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Size = Vector3.new(DISC_THICKNESS, part.Size.X, part.Size.X)
	disc.CFrame = part.CFrame
		* CFrame.new(0, part.Size.Y / 2 + DISC_THICKNESS / 2, 0)
		* CFrame.Angles(0, 0, math.pi / 2)
	disc.Color = COLORS.idle
	disc.Parent = part
	part.Transparency = 1
	return disc
end

-- Updates the text, the colour and the visibility of one pad from the current state.
local function refresh(entry: Entry)
	local info = PadInfo.describe(entry.kind, entry.padId, State.data)
	if entry.kind == "penalty" and info.state == "ready" then
		-- All three kicks used: the pad shows when it is back (the server judges the time).
		local readyAt = player:GetAttribute("penaltyReadyAt")
		local now = Workspace:GetServerTimeNow()
		if type(readyAt) == "number" and DailyInfo.status(true, readyAt, now) == "waiting" then
			info = {
				title = "Penalty kicks",
				price = "WAIT",
				note = DailyInfo.waitText(readyAt - now),
				state = "locked",
			}
		end
	end
	-- A player is named as on the back of the shirt ("ALEXANDER-ARNOLD"), not by the full name.
	local isPlayer = entry.kind == "player" or entry.kind == "legend"
	-- The name of a player is on the plaque of his capsule, so the pad shows only the price.
	entry.title.Text = string.upper(info.title)
	entry.title.Visible = not isPlayer
	entry.price.Text = info.price
	entry.price.Visible = info.price ~= ""
	entry.price.TextColor3 = if info.state == "cannotAfford" then BAD_COLOR else PRICE_COLOR
	-- Why a pad cannot be used is said by PadHint when the player steps on it, not under every pad.
	local blocked = entry.kind ~= "penalty"
		and (info.state == "cannotAfford" or info.state == "locked")
	entry.note.Text = info.note
	entry.note.Visible = info.note ~= "" and not blocked
	entry.note.TextColor3 = NOTE_COLOR
	for index, line in entry.lines do
		local goal = if info.lines then info.lines[index] else nil
		line.Visible = goal ~= nil
		if goal then
			line.Text = goal.text
			line.TextColor3 = if goal.done then GOAL_DONE_COLOR else NOTE_COLOR
		end
	end
	if entry.disc then
		entry.disc.Color = padColor(info.state)
	end
	-- The claim rings of free plots only matter to a player who has no plot yet.
	-- Locked Store pads stay hidden until they unlock, so the middle of the room is not cluttered.
	-- Players on a floor that is not open yet stay visible (price and what to finish first), so
	-- the stairs are worth climbing to see what is coming.
	local hidden = (entry.kind == "claim" and State.hasPlot())
		or (entry.kind == "store" and info.state == "locked")
		or (entry.kind == "penalty" and info.price == "")
	entry.billboard.Enabled = not hidden
	if entry.disc then
		entry.disc.Transparency = if hidden then 1 else 0
	end
end

local function track(part: Instance)
	if not part:IsA("BasePart") or entries[part] then
		return
	end
	local kind = part:GetAttribute("Kind")
	local padId = part:GetAttribute("PadId")
	local key = part:GetAttribute("PadKey")
	local ownerId = part:GetAttribute("OwnerUserId")
	if type(kind) ~= "string" or type(padId) ~= "string" or type(key) ~= "string" then
		return
	end
	if not SHOWN_KINDS[kind] then
		return
	end
	-- Only the owner's pads and the public claim rings get a label.
	if ownerId ~= 0 and ownerId ~= player.UserId then
		return
	end
	local billboard, title, price, note, lines, bar, fill = buildBillboard(part)
	if kind == "stadium" then
		billboard.MaxDistance = STADIUM_MAX_DISTANCE -- it stands far from the pitch, so show it from afar
	end
	local entry: Entry = {
		part = part,
		billboard = billboard,
		disc = if DISC_KINDS[kind] then buildDisc(part) else nil,
		title = title,
		price = price,
		note = note,
		lines = lines,
		track = bar,
		fill = fill,
		kind = kind,
		padId = padId,
		key = key,
		fraction = -1,
	}
	entries[part] = entry
	refresh(entry)
end

local function untrack(part: Instance)
	if part:IsA("BasePart") then
		entries[part] = nil
	end
end

-- Shows the hold on the pad the player stands on: a thin bar that fills while the server times it.
local function paintHold(entry: Entry, fraction: number)
	if entry.fraction == fraction then
		return
	end
	entry.fraction = fraction
	entry.track.Visible = fraction > 0
	entry.fill.Size = UDim2.fromScale(fraction, 1)
end

function PadRing.init()
	CollectionService:GetInstanceAddedSignal("Pad"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Pad"):Connect(untrack)
	for _, part in CollectionService:GetTagged("Pad") do
		track(part)
	end

	local function refreshAll()
		for _, entry in entries do
			refresh(entry)
		end
	end
	State.onChange(refreshAll)
	player:GetAttributeChangedSignal("penaltyReadyAt"):Connect(refreshAll)

	RunService.RenderStepped:Connect(function()
		local activeKey = player:GetAttribute("padKey")
		local state = player:GetAttribute("padState")
		local startedAt = player:GetAttribute("padStart")
		local hold = player:GetAttribute("padHold")
		local fraction = 0
		if
			state == "ready"
			and type(startedAt) == "number"
			and startedAt > 0
			and type(hold) == "number"
			and hold > 0
		then
			fraction = math.clamp((Workspace:GetServerTimeNow() - startedAt) / hold, 0, 1)
		end
		for _, entry in entries do
			paintHold(entry, if entry.key == activeKey then fraction else 0)
		end
	end)
end

return PadRing
