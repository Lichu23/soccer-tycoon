--!strict
-- The row of round-cornered buttons at the left edge (Case, Kick, Shop, Locker, Alerts). They are all
-- there from the first second: a closed one is greyed with a small padlock, and tapping it says in
-- one short line when it opens. An open one has a coloured outline and, once an image is uploaded
-- (client/Icons), a picture above its label. The screens behind them are built by their own modules;
-- this only draws the buttons and shows the reasons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Edges = require(script.Parent.Edges)
local Icons = require(script.Parent.Icons)
local Style = require(ReplicatedStorage.Shared.Style)

local SIZE = 46 -- on the smallest landscape phone; bigger screens scale the buttons up
local GAP = 10
local LEFT = 8 -- inside the safe area, less the part of its strip the buttons move over (client/Edges)
local TOP = 20 -- clear of the Roblox menu, chat and voice buttons above the safe area
local REASON_SECONDS = 2.5
-- The buttons grow with the screen height: 1x up to a phone (about 500 px tall), up to MAX_SCALE on
-- a desktop or tablet, where 46 px tiles look tiny.
local SCALE_REFERENCE_HEIGHT = 500
local MAX_SCALE = 1.4
local BESIDE_GAP = 10

local Dock = {}

Dock.SIZE = SIZE

local scale = 1
local edgeLeft = 0 -- how far the buttons move out over the strip left of the safe area
local placedTiles: { { button: GuiObject, slot: number, scaler: UIScale } } = {}
local placedBeside: { { object: GuiObject, slot: number, dy: number } } = {}
local watching = false

export type Tile = {
	button: TextButton,
	accent: UIStroke,
	label: TextLabel,
	lock: Frame,
	color: Color3,
	picture: ImageLabel?, -- the uploaded tile picture, when there is one
	reasonToken: number,
	pending: boolean, -- something free waits behind the button (its red "1", see Dock.badge)
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Where the button of slot 1 to 5 sits, at the current scale, in its safe-area ScreenGui.
function Dock.position(slot: number): UDim2
	return UDim2.fromOffset(LEFT - edgeLeft, TOP + (slot - 1) * (SIZE + GAP) * scale)
end

local function layout()
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 0
	scale = math.clamp(height / SCALE_REFERENCE_HEIGHT, 1, MAX_SCALE)
	edgeLeft = Edges.pull()
	for _, tile in placedTiles do
		tile.button.Position = Dock.position(tile.slot)
		tile.scaler.Scale = scale
	end
	for _, beside in placedBeside do
		local tileTop = Dock.position(beside.slot).Y.Offset
		beside.object.Position =
			UDim2.fromOffset(LEFT - edgeLeft + SIZE * scale + BESIDE_GAP, tileTop + beside.dy * scale)
	end
end

-- Re-lays the buttons when the window or the device turns (the camera can also be replaced).
local function watchViewport()
	if watching then
		return
	end
	watching = true
	local sizeConnection: RBXScriptConnection? = nil
	local function follow()
		if sizeConnection then
			sizeConnection:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			sizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		layout()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(follow)
	follow()
	Edges.watch(layout)
end

-- Keeps a note or toast just right of the button in `slot`, `dy` pixels below its top (at 1x), so it
-- follows the buttons when they scale.
function Dock.placeBeside(object: GuiObject, slot: number, dy: number)
	table.insert(placedBeside, { object = object, slot = slot, dy = dy })
	watchViewport()
	layout()
end

-- Builds a button. `iconName` picks the uploaded image in client/Icons, if any.
function Dock.build(
	parent: Instance,
	name: string,
	slot: number,
	text: string,
	accent: Color3,
	iconName: string
): Tile
	local button = new("TextButton", {
		Name = name,
		Position = Dock.position(slot),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Style.ui.panel,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
	}, parent)
	-- The button sits over the strip left of the safe area, which the ScreenGui would otherwise cut.
	local screen = button:FindFirstAncestorOfClass("ScreenGui")
	if screen then
		screen.ClipToDeviceSafeArea = false
	end
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, button)
	local gradient = new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 175, 195)),
		Rotation = 90,
	}, button)
	local stroke = new("UIStroke", {
		Name = "Outline",
		Color = accent,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, button)

	local label = new("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, -4, 0, SIZE),
		BackgroundTransparency = 1,
		Text = text,
		Font = Style.font,
		TextSize = 12,
		TextColor3 = Style.ui.text,
		ZIndex = 3,
	}, button)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	-- With an uploaded tile picture the picture is the whole button: no dark tile, outline or text.
	local imageId = Icons.id(iconName)
	local picture: ImageLabel? = nil
	if imageId ~= "" then
		picture = new("ImageLabel", {
			Name = "Picture",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = imageId,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}, button)
		button.BackgroundTransparency = 1
		gradient.Enabled = false
		label.Visible = false
	end

	-- The padlock of a closed button: a body and a shackle.
	local lock = new("Frame", {
		Name = "Lock",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -1, 1, -4),
		Size = UDim2.fromOffset(16, 18),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, button)
	local shackle = new("Frame", {
		Position = UDim2.fromOffset(3, 0),
		Size = UDim2.fromOffset(10, 12),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, lock)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, shackle)
	new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2.5 }, shackle)
	local body = new("Frame", {
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.fromOffset(16, 11),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 5,
	}, lock)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, body)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 1.5 }, body)

	-- The whole button (padlock, badge and reason line included) grows from its top-left corner.
	local scaler = new("UIScale", {}, button)
	table.insert(placedTiles, { button = button, slot = slot, scaler = scaler })
	watchViewport()
	layout()

	return {
		button = button,
		accent = stroke,
		label = label,
		lock = lock,
		color = accent,
		picture = picture,
		reasonToken = 0,
		pending = false,
	}
end

-- Shows or hides the "1" of a button: while the button is open and something free waits behind it.
local function refreshBadge(tile: Tile)
	local badge: any = tile.button:FindFirstChild("Badge")
	if badge == nil then
		return
	end
	badge.Visible = tile.pending and not tile.lock.Visible
end

-- The small red "1" at the top-right corner of a button. It shows while something free waits behind
-- the button (the daily penalties, the free case) and goes only when that is claimed, never on a tap:
-- opening the button and leaving it unclaimed keeps it. The owner says when with Dock.setPending.
function Dock.badge(tile: Tile)
	local badge = new("TextLabel", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Color3.fromRGB(235, 60, 70),
		Text = "1",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Visible = false,
		ZIndex = 7,
	}, tile.button)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, badge)
	refreshBadge(tile)
end

-- Whether something free waits behind the button (its "1"). Cheap to call every frame.
function Dock.setPending(tile: Tile, pending: boolean)
	if tile.pending ~= pending then
		tile.pending = pending
		refreshBadge(tile)
	end
end

-- Paints a button: "open" (normal), "ready" (open and something is waiting), "waiting" (open but
-- dimmed until a time) or "locked" (greyed with a padlock).
function Dock.paint(tile: Tile, state: string)
	local locked = state == "locked"
	tile.lock.Visible = locked
	local picture = tile.picture
	if picture then
		-- The picture is the button: a closed one is greyed, a waiting one a little dimmed.
		picture.ImageColor3 = if locked
			then Color3.fromRGB(105, 108, 120)
			elseif state == "waiting" then Color3.fromRGB(190, 190, 200)
			else Color3.fromRGB(255, 255, 255)
		picture.ImageTransparency = if locked then 0.1 elseif state == "waiting" then 0.15 else 0
		tile.accent.Transparency = 1 -- the pulse of a ready button sets this itself
		refreshBadge(tile)
		return
	end
	tile.button.BackgroundTransparency = if state == "waiting" then 0.45 else 0.05
	tile.accent.Color = if locked then Color3.fromRGB(110, 115, 132) else tile.color
	tile.accent.Transparency = if state == "waiting" then 0.5 else 0
	tile.label.TextColor3 = if locked or state == "waiting" then Style.ui.idle else Style.ui.text
	tile.button.BackgroundColor3 = if locked then Color3.fromRGB(52, 56, 70) else Style.ui.panel
	refreshBadge(tile)
end

-- Shows one short line beside the button for a couple of seconds ("Opens at stadium tier 2.").
function Dock.reason(tile: Tile, text: string)
	tile.reasonToken += 1
	local token = tile.reasonToken
	local note: any = tile.button:FindFirstChild("Reason")
	if note == nil then
		note = new("TextLabel", {
			Name = "Reason",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 10, 0.5, 0),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Style.ui.text,
			ZIndex = 6,
		}, tile.button)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, note)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, note)
	end
	note.Text = text
	note.Visible = true
	task.delay(REASON_SECONDS, function()
		if token == tile.reasonToken and note.Parent then
			note.Visible = false
		end
	end)
end

return Dock
