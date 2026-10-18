--!strict
-- The text and the circular ring above every pad (docs/PLAN.md, Step 1 and 7). The server times the
-- hold; this only draws it from the player's attributes: padKey, padState, padStart and padHold.
-- Layout: the name above, the ring with the price inside it, and a short note under the ring.
-- The ring fills clockwise, is fully red when the player cannot afford the pad, and stays empty on
-- pads that cannot be used. Only pads close to the player show, so neighbours never overlap.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PadInfo = require(ReplicatedStorage.Shared.PadInfo)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local SEGMENTS = 36
local BOARD_WIDTH = 170
local BOARD_HEIGHT = 176
local RING_CENTER = Vector2.new(BOARD_WIDTH / 2, 98)
local RING_RADIUS = 40
local SHOWN_KINDS = { claim = true, player = true, store = true, stadium = true }
local MAX_DISTANCE = 30

type Entry = {
	part: BasePart,
	billboard: BillboardGui,
	segments: { Frame },
	title: TextLabel,
	price: TextLabel,
	note: TextLabel,
	kind: string,
	padId: string,
	key: string,
	filled: number,
	color: Color3,
}

local entries: { [BasePart]: Entry } = {}

local PadRing = {}

local DIM = Color3.fromRGB(60, 66, 85)

local function ringColor(state: string): Color3
	if state == "ready" then
		return Style.ui.good
	elseif state == "cannotAfford" then
		return Style.ui.bad
	end
	return Style.ui.idle
end

local function label(
	parent: Instance,
	name: string,
	position: Vector2,
	size: Vector2,
	maxSize: number
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromOffset(position.X, position.Y)
	text.Size = UDim2.fromOffset(size.X, size.Y)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.TextWrapped = true
	text.Font = Style.font
	text.TextColor3 = Style.ui.text
	text.TextStrokeTransparency = 0.25
	text.TextStrokeColor3 = Style.ui.dark
	text.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 9
	limit.Parent = text
	return text
end

local function buildBillboard(
	part: BasePart
): (BillboardGui, { Frame }, TextLabel, TextLabel, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PadBillboard"
	billboard.Size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.MaxDistance = MAX_DISTANCE
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Adornee = part

	local segments: { Frame } = {}
	local arc = math.pi * 2 * RING_RADIUS / SEGMENTS
	for index = 1, SEGMENTS do
		local angle = (index - 0.5) / SEGMENTS * math.pi * 2 -- clockwise from the top
		local segment = Instance.new("Frame")
		segment.Name = "Segment" .. index
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Size = UDim2.fromOffset(arc + 1, 8)
		segment.Position = UDim2.fromOffset(
			RING_CENTER.X + RING_RADIUS * math.sin(angle),
			RING_CENTER.Y - RING_RADIUS * math.cos(angle)
		)
		segment.Rotation = math.deg(angle)
		segment.BackgroundColor3 = DIM
		segment.BackgroundTransparency = 0.3
		segment.BorderSizePixel = 0
		segment.Parent = billboard
		table.insert(segments, segment)
	end

	-- The name above the ring, the price inside it, the note under it.
	local title =
		label(billboard, "Title", Vector2.new(RING_CENTER.X, 16), Vector2.new(BOARD_WIDTH, 30), 17)
	local price = label(billboard, "Price", RING_CENTER, Vector2.new(62, 36), 24)
	price.TextColor3 = Style.ui.money
	local note =
		label(billboard, "Note", Vector2.new(RING_CENTER.X, 156), Vector2.new(BOARD_WIDTH, 26), 15)

	billboard.Parent = part
	return billboard, segments, title, price, note
end

local function paintRing(entry: Entry, filled: number, color: Color3)
	if entry.filled == filled and entry.color == color then
		return
	end
	entry.filled = filled
	entry.color = color
	for index, segment in entry.segments do
		if index <= filled then
			segment.BackgroundColor3 = color
			segment.BackgroundTransparency = 0
		else
			segment.BackgroundColor3 = DIM
			segment.BackgroundTransparency = 0.3
		end
	end
end

-- Updates the text and visibility of one pad from the current state.
local function refresh(entry: Entry)
	local info = PadInfo.describe(entry.kind, entry.padId, State.data)
	entry.title.Text = info.title
	entry.price.Text = info.price
	entry.note.Text = info.note
	entry.price.TextColor3 = if info.state == "cannotAfford" then Style.ui.bad else Style.ui.money
	entry.note.TextColor3 = if info.state == "cannotAfford" then Style.ui.bad else Style.ui.idle
	-- The claim rings of free plots only matter to a player who has no plot yet.
	-- Locked Store pads stay hidden until they unlock, so the middle of the room is not cluttered.
	-- Players on a floor that is not open yet stay hidden too.
	local hidden = (entry.kind == "claim" and State.hasPlot())
		or ((entry.kind == "store" or entry.kind == "player") and info.state == "locked")
	entry.billboard.Enabled = not hidden
	if entry.filled == 0 then
		entry.color = ringColor(info.state)
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
	-- Only the owner's pads and the public claim rings get a ring.
	if ownerId ~= 0 and ownerId ~= player.UserId then
		return
	end
	local billboard, segments, title, price, note = buildBillboard(part)
	local entry: Entry = {
		part = part,
		billboard = billboard,
		segments = segments,
		title = title,
		price = price,
		note = note,
		kind = kind,
		padId = padId,
		key = key,
		filled = -1,
		color = DIM,
	}
	entries[part] = entry
	refresh(entry)
	paintRing(entry, 0, entry.color)
end

local function untrack(part: Instance)
	if part:IsA("BasePart") then
		entries[part] = nil
	end
end

function PadRing.init()
	CollectionService:GetInstanceAddedSignal("Pad"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Pad"):Connect(untrack)
	for _, part in CollectionService:GetTagged("Pad") do
		track(part)
	end

	State.onChange(function()
		for _, entry in entries do
			refresh(entry)
		end
	end)

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
			if entry.key == activeKey and type(state) == "string" then
				if state == "cannotAfford" then
					-- Standing on a pad that costs too much: a full red ring that does not fill.
					paintRing(entry, SEGMENTS, ringColor(state))
				else
					paintRing(entry, math.floor(fraction * SEGMENTS + 0.5), ringColor(state))
				end
			else
				paintRing(entry, 0, entry.color)
			end
		end
	end)
end

return PadRing
