--!strict
-- The shared look of the big screens (Shop, Locker room, Reminders): a light panel in the middle of
-- the screen with a centred title, a red X in the corner and a scrolling column, over the game (no
-- dimming).
-- While a panel is open its ScreenGui sits above every other HUD screen. The X is the only way to
-- close it, so a stray tap outside never loses the player's place. Text colours are dark, for contrast
-- on the light panel.

local Icons = require(script.Parent.Icons)
local Style = require(game:GetService("ReplicatedStorage").Shared.Style)

local PANEL_COLOR = Color3.fromRGB(226, 216, 255)
local EDGE_COLOR = Color3.fromRGB(20, 24, 35)
local HEADER_HEIGHT = 64
local OPEN_ORDER = 6
local CLOSED_ORDER = 4

local Panel = {}

Panel.TEXT = Color3.fromRGB(28, 30, 48) -- body text on the panel
Panel.MUTED = Color3.fromRGB(70, 74, 100) -- secondary text on the panel
Panel.GOOD = Color3.fromRGB(14, 110, 48) -- an answer such as "Yours"
Panel.MAX_WIDTH = 640

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

export type Built = {
	backdrop: Frame,
	card: Frame, -- the column the screen fills with rows (a UIListLayout is already on it)
	setTitle: (text: string) -> (),
}

-- Builds the panel inside `gui`. `heightScale` is the share of the screen height it takes.
function Panel.build(gui: ScreenGui, title: string, heightScale: number, onClose: () -> ()): Built
	local backdrop = new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, -- no dimming; it only swallows taps
		Visible = false,
		Active = true, -- swallows taps so nothing behind it is pressed
		ZIndex = 5,
	}, gui)
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		gui.DisplayOrder = if backdrop.Visible then OPEN_ORDER else CLOSED_ORDER
	end)

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, heightScale),
		BackgroundColor3 = PANEL_COLOR,
		ZIndex = 6,
	}, backdrop)
	new("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	new("UIStroke", { Color = EDGE_COLOR, Thickness = 4 }, panel)
	new("UISizeConstraint", { MaxSize = Vector2.new(Panel.MAX_WIDTH, math.huge) }, panel)

	local titleLabel = new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -112, 0, HEADER_HEIGHT),
		Position = UDim2.fromOffset(56, 0),
		BackgroundTransparency = 1,
		Text = title,
		Font = Style.font,
		TextSize = 30,
		TextColor3 = Panel.TEXT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	}, panel)

	local close = new("TextButton", {
		Name = "CloseX",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Color3.fromRGB(226, 40, 70),
		Text = "X",
		Font = Style.font,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 9,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, close)
	new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 3 }, close)
	close.Activated:Connect(onClose)

	local scroll = new("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
	}, panel)
	local card = new("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, scroll)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
	}, card)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)

	return {
		backdrop = backdrop,
		card = card,
		setTitle = function(text: string)
			titleLabel.Text = text
		end,
	}
end

-- Puts the picture of `iconName` at the left of a 44 px row and moves the text right. No id, no change.
function Panel.rowIcon(item: TextButton, iconName: string)
	local id = Icons.id(iconName)
	if id == "" then
		return
	end
	item.TextXAlignment = Enum.TextXAlignment.Left
	new("UIPadding", { PaddingLeft = UDim.new(0, 52) }, item)
	new("ImageLabel", {
		Name = "Picture",
		Position = UDim2.fromOffset(-48, 4),
		Size = UDim2.fromOffset(36, 36),
		BackgroundTransparency = 1,
		Image = id,
		ZIndex = 8,
	}, item)
end

return Panel
