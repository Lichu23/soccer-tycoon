--!strict
-- The Locker room (docs/PLAN.md, Step 3): each stadium tier opens one slot of team styles (kit, crest,
-- banners, floodlights, scoreboard) with free styles and a few premium ones. One icon under the shop
-- icon opens it. Defaults look good, so nobody has to use it; a new slot only shows a small note
-- beside the icon that fades by itself. The server checks every choice and every purchase; this only
-- asks (SetCosmetic, RequestPurchase) and shows the answer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Net = require(script.Parent.Net)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local CARD_W = 380
local ICON_SIZE = 52
local ICON_TOP = 8 + 3 * (ICON_SIZE + 8) -- under the case, kick and shop icons
local WAIT_SECONDS = 4
local NOTE_SECONDS = 8
local TEXT_COLOR = Color3.fromRGB(215, 220, 232)

local REFUSALS: { [string]: string } = {
	early = "Premium styles open a little later.",
	tier = "Reach that stadium tier first.",
	owned = "You already have it.",
	unavailable = "Not available right now.",
	unknown = "Not available right now.",
}

local LockerUi = {}

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

local function swatchColor(def: Config.CosmeticDef): Color3
	return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
end

function LockerUi.init()
	local gui = new("ScreenGui", {
		Name = "Locker",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local icon = new("TextButton", {
		Name = "LockerIcon",
		Position = UDim2.fromOffset(8, ICON_TOP),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundColor3 = Style.ui.panel,
		Text = "LOCKER",
		Font = Style.font,
		TextSize = 12,
		TextColor3 = Style.ui.text,
		AutoButtonColor = false,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, icon)

	-- The small note that a new slot opened: beside the icon, never blocking, gone after a few seconds.
	local note = new("TextLabel", {
		Name = "Note",
		Position = UDim2.fromOffset(8 + ICON_SIZE + 6, ICON_TOP + 14),
		Size = UDim2.fromOffset(120, 24),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		Text = "New styles",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.gold,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, note)

	-- A full-screen panel: a solid black backdrop, a scrolling area and a centred column that grows
	-- with its content (so nothing is cut off on a small phone). It closes with its Close button.
	local backdrop = new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		Visible = false,
		Active = true, -- swallows taps so nothing behind it is pressed
		ZIndex = 5,
	}, gui)
	local scroll = new("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
	}, backdrop)
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, scroll)
	new("UISizeConstraint", { MaxSize = Vector2.new(CARD_W + 120, math.huge) }, card)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 24),
	}, card)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	-- Open, the panel sits above every other HUD screen and icon.
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		gui.DisplayOrder = if backdrop.Visible then 6 else 4
	end)

	local order = 0
	local function line(text: string, props: { [string]: any }?)
		order += 1
		local p = {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Style.font,
			TextSize = 15,
			TextColor3 = TEXT_COLOR,
			ZIndex = 7,
		}
		if props then
			for key, value in props do
				p[key] = value
			end
		end
		return new("TextLabel", p, card)
	end

	local function clear()
		order = 0
		for _, child in card:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- A row button with an optional colour swatch on the left.
	local function row(
		name: string,
		text: string,
		color: Color3,
		swatch: Color3?,
		onClick: (() -> ())?
	): TextButton
		order += 1
		local item = new("TextButton", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = color,
			Font = Style.font,
			TextSize = 16,
			TextColor3 = Style.ui.dark,
			Text = text,
			AutoButtonColor = onClick ~= nil,
			ZIndex = 7,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, item)
		if swatch then
			item.TextXAlignment = Enum.TextXAlignment.Left
			new("UIPadding", { PaddingLeft = UDim.new(0, 52) }, item)
			local chip = new("Frame", {
				Name = "Swatch",
				Position = UDim2.fromOffset(-44, 7),
				Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = swatch,
				ZIndex = 8,
			}, item)
			new("UICorner", { CornerRadius = UDim.new(0, 6) }, chip)
			new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, chip)
		end
		if onClick then
			item.Activated:Connect(onClick)
		end
		return item
	end

	-- The views --------------------------------------------------------------------------------
	local slotView: string? = nil -- the slot being browsed, nil = the slot list
	local previewId: string? = nil -- a premium style being looked at
	local message: string? = nil
	local waiting = false
	local render: () -> ()

	local function close()
		backdrop.Visible = false
		slotView, previewId, message = nil, nil, nil
	end

	local function renderSlots()
		line("Locker room", { TextSize = 24, TextColor3 = Style.ui.gold })
		if message then
			line(message, { TextColor3 = Style.ui.good })
		end
		for _, slot in Config.CosmeticSlots do
			if Cosmetics.slotOpen(State.data, slot.id) then
				local chosen = Cosmetics.chosen(State.data, slot.id)
				row(
					"Slot_" .. slot.id,
					`{slot.name}: {if chosen then chosen.name else "-"}`,
					Style.ui.gold,
					if chosen then swatchColor(chosen) else nil,
					function()
						slotView, message = slot.id, nil
						render()
					end
				)
			else
				row(
					"Slot_" .. slot.id,
					`{slot.name}   Stadium tier {slot.tier}`,
					Color3.fromRGB(70, 74, 90),
					nil,
					nil
				).TextColor3 =
					TEXT_COLOR
			end
		end
		row("Close", "Close", Style.ui.idle, nil, close)
	end

	local function renderStyles(slotId: string)
		local slot
		for _, candidate in Config.CosmeticSlots do
			if candidate.id == slotId then
				slot = candidate
			end
		end
		line(if slot then slot.name else "Styles", { TextSize = 24, TextColor3 = Style.ui.gold })
		if message then
			line(message, { TextColor3 = Style.ui.good })
		end
		local chosen = Cosmetics.chosen(State.data, slotId)
		for _, def in Cosmetics.styles(slotId) do
			local using = chosen ~= nil and chosen.id == def.id
			local text = def.name
			local color = Style.ui.gold
			if using then
				text ..= "   In use"
				color = Style.ui.good
			elseif not Cosmetics.owns(State.data, def.id) then
				text ..= `   {def.robux} Robux`
				color = Style.ui.bar
			end
			row("Style_" .. def.id, text, color, swatchColor(def), function()
				message = nil
				if Cosmetics.owns(State.data, def.id) then
					Net.fire("SetCosmetic", slotId, def.id)
				else
					previewId = def.id
					render()
				end
			end)
		end
		row("Back", "Back", Style.ui.idle, nil, function()
			slotView, message = nil, nil
			render()
		end)
	end

	local function renderPreview(id: string)
		local def = Config.CosmeticsById[id]
		line(def.name, { TextSize = 24, TextColor3 = Style.ui.gold })
		line(
			"A premium style. It changes only how your team looks, and it stays after a New Season."
		)
		local chip = new("Frame", {
			Name = "Preview",
			LayoutOrder = order + 1,
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = swatchColor(def),
			ZIndex = 7,
		}, card)
		order += 1
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, chip)
		local buy: TextButton
		buy = row("Buy", `Buy for {def.robux} Robux`, Style.ui.good, nil, function()
			if waiting then
				return
			end
			waiting = true
			buy.Text = "Waiting..."
			Net.fire("RequestPurchase", "cosmetic_" .. id)
			task.delay(WAIT_SECONDS, function()
				waiting = false
				if buy.Parent then
					buy.Text = `Buy for {def.robux} Robux`
				end
			end)
		end)
		row("Back", "Back", Style.ui.idle, nil, function()
			previewId = nil
			render()
		end)
	end

	function render()
		clear()
		if previewId then
			renderPreview(previewId)
		elseif slotView then
			renderStyles(slotView)
		else
			renderSlots()
		end
	end

	icon.Activated:Connect(function()
		slotView, previewId, message = nil, nil, nil
		render()
		backdrop.Visible = true
	end)

	-- The icon shows once the team plays; a slot that opens after the first look shows the small note.
	local lastTier = 0
	local noteToken = 0
	local function refresh()
		icon.Visible = State.data.fieldStarted
		local tier = State.data.stadiumTier
		if lastTier > 0 and tier > lastTier and Cosmetics.slotForTier(tier) then
			noteToken += 1
			local token = noteToken
			note.Visible = true
			task.delay(NOTE_SECONDS, function()
				if token == noteToken then
					note.Visible = false
				end
			end)
		end
		lastTier = tier
		if backdrop.Visible then
			render()
		end
	end
	State.onChange(refresh)

	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "purchaseRefused" then
			waiting = false
			if backdrop.Visible and previewId then
				previewId = nil
				message = REFUSALS[info.reason] or REFUSALS.unavailable
				render()
			end
		elseif info.kind == "purchaseDone" then
			waiting = false
			local result = info.result
			if type(result) == "table" and result.kind == "cosmetic" then
				previewId = nil
				message = "Yours. It is in use."
				if backdrop.Visible then
					render()
				end
			end
		end
	end)
	refresh()
end

return LockerUi
