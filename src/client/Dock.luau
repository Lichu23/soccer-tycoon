--!strict
-- The row of round-cornered buttons at the left edge (Case, Kick, Shop, Locker, Alerts). They are all
-- there from the first second: a closed one is greyed with a small padlock, and tapping it says in
-- one short line when it opens. An open one has a coloured outline and, once an image is uploaded
-- (client/Icons), a picture above its label. The screens behind them are built by their own modules;
-- this only draws the buttons and shows the reasons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icons = require(script.Parent.Icons)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local SIZE = 46
local GAP = 10
local LEFT = 8
local TOP = 8
local REASON_SECONDS = 2.5

local Dock = {}

Dock.SIZE = SIZE

export type Tile = {
	button: TextButton,
	accent: UIStroke,
	label: TextLabel,
	lock: Frame,
	color: Color3,
	picture: ImageLabel?, -- the uploaded tile picture, when there is one
	reasonToken: number,
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

-- Where the button of slot 1 to 5 sits.
function Dock.position(slot: number): UDim2
	return UDim2.fromOffset(LEFT, TOP + (slot - 1) * (SIZE + GAP))
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

	return {
		button = button,
		accent = stroke,
		label = label,
		lock = lock,
		color = accent,
		picture = picture,
		reasonToken = 0,
	}
end

-- The small red "1" at the top-right corner of a button, shown until the open button is tapped for the first
-- time. The server saves the tap (SeenTile) and says through the attribute tile_<id> (0 = not yet).
function Dock.badge(tile: Tile, id: string)
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
	local player = Players.LocalPlayer
	local attributeName = "tile_" .. id
	local function refresh()
		badge.Visible = player:GetAttribute(attributeName) == 0
	end
	refresh()
	player:GetAttributeChangedSignal(attributeName):Connect(refresh)
	tile.button.Activated:Connect(function()
		-- A closed button keeps its "1" until it opens and is tapped.
		if badge.Visible and not tile.lock.Visible then
			badge.Visible = false
			Net.fire("SeenTile", id)
		end
	end)
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
		return
	end
	tile.button.BackgroundTransparency = if state == "waiting" then 0.45 else 0.05
	tile.accent.Color = if locked then Color3.fromRGB(110, 115, 132) else tile.color
	tile.accent.Transparency = if state == "waiting" then 0.5 else 0
	tile.label.TextColor3 = if locked or state == "waiting" then Style.ui.idle else Style.ui.text
	tile.button.BackgroundColor3 = if locked then Color3.fromRGB(52, 56, 70) else Style.ui.panel
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
