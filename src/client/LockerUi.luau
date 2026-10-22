--!strict
-- The Locker room (docs/PLAN.md, Step 3): the stadium tiers open slots of team styles (kit, crest,
-- banners, floodlight models and colour, scoreboard, the roof arena's colour and name), with free
-- styles, a few bought with cash and a few with Robux. A slot that is not open yet shows its tier on
-- every card, never "In use".
-- One icon in the dock opens it. The panel docks at the left and the camera shows the player's own
-- stadium on the right (client/LockerView); tapping a style paints it there at once, for free, and the
-- one button under the cards uses or buys it. Defaults look good, so nobody has to use it; a new slot
-- only shows a small note beside the icon that fades by itself. The server checks every choice and
-- every purchase; this only asks (SetCosmetic, BuyCosmetic, RequestPurchase, RenameStadium) and
-- shows the answer. The name typed for the stadium is shown only once the server has filtered it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Dock = require(script.Parent.Dock)
local Icons = require(script.Parent.Icons)
local LockerView = require(script.Parent.LockerView)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Panel = require(script.Parent.Panel)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local WAIT_SECONDS = 4
local NOTE_SECONDS = 8
local PANEL_WIDTH = 0.46 -- share of the screen width
local PANEL_MAX = 400
local TAB_SIZE = 46
local CARD_HEIGHT = 64
local FOOTER_HEIGHT = 68
local CARD_COLOR = Color3.fromRGB(246, 243, 255)
local DISABLED = Color3.fromRGB(196, 194, 214)
local TIER_NAMES = { "Street cage", "F5 hall", "Stadium", "Big stadium", "Arena", "Roof arena" }

local REFUSALS: { [string]: string } = {
	tier = "Reach that stadium tier first.",
	owned = "You already have it.",
	locked = "Buy it first.",
	cannotAfford = "Not enough cash yet.",
	unavailable = "Not available right now.",
	unknown = "Not available right now.",
	length = `Use {Config.StadiumName.minLength} to {Config.StadiumName.maxLength} letters.`,
	same = "That is already the name.",
	filtered = "That name is not allowed. Try another one.",
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

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function slotDef(slotId: string): Config.CosmeticSlotDef?
	for _, slot in Config.CosmeticSlots do
		if slot.id == slotId then
			return slot
		end
	end
	return nil
end

-- A swatch: the crest's picture, or the style's colours side by side (the banner sets show their
-- pattern).
local function swatch(parent: Instance, def: Config.CosmeticDef, size: number)
	local frame = new("Frame", {
		Name = "Swatch",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = rgb(def.color),
		ClipsDescendants = true,
		ZIndex = 8,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	new("UIStroke", { Color = Style.ui.dark, Thickness = 2 }, frame)
	local pattern = def.pattern
	if def.image then
		frame.BackgroundColor3 = Panel.BACKGROUND
		new("ImageLabel", {
			Name = "Crest",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = def.image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 9,
		}, frame)
	elseif pattern and #pattern > 1 then
		local count = math.min(#pattern, 3)
		for index = 1, count do
			new("Frame", {
				Position = UDim2.fromScale((index - 1) / count, 0),
				Size = UDim2.fromScale(1 / count, 1),
				BackgroundColor3 = rgb(pattern[index]),
				BorderSizePixel = 0,
				ZIndex = 8,
			}, frame)
		end
	elseif def.accent then
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.4, 0.4),
			BackgroundColor3 = rgb(def.accent),
			ZIndex = 9,
		}, frame)
	end
	return frame
end

function LockerUi.init()
	local gui = new("ScreenGui", {
		Name = "Locker",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local tile = Dock.build(gui, "LockerIcon", 3, "LOCKER", Style.ui.bar, "locker")
	local icon = tile.button
	local locked = true

	-- The small note that a new slot opened: beside the icon, never blocking, gone after a few seconds.
	local note = new("TextLabel", {
		Name = "Note",
		Position = UDim2.fromOffset(
			Dock.position(3).X.Offset + Dock.SIZE + 10,
			Dock.position(3).Y.Offset + 10
		),
		Size = UDim2.fromOffset(120, 26),
		BackgroundColor3 = Style.ui.panel,
		Text = "New styles",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.text,
		TextStrokeTransparency = 0.4,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, note)
	new("UIStroke", {
		Color = Style.ui.gold,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, note)

	local close: () -> ()
	local built = Panel.build(gui, "Locker room", 0.92, function()
		close()
	end)
	local backdrop, card = built.backdrop, built.card

	-- Docked at the left, so the stadium shows on the right; the button stays under the scroll.
	local panel = built.panel
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.5, 0)
	panel.Size = UDim2.fromScale(PANEL_WIDTH, 0.92)
	local limit = panel:FindFirstChildOfClass("UISizeConstraint")
	if limit then
		limit.MaxSize = Vector2.new(PANEL_MAX, math.huge)
	end
	built.scroll.Size = UDim2.new(1, 0, 1, -Panel.HEADER_HEIGHT - FOOTER_HEIGHT)
	-- The backdrop lets the stadium be seen and keeps taps off the world behind it.
	backdrop.BackgroundTransparency = 1

	local action = new("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -40, 0, 48),
		BackgroundColor3 = Style.ui.good,
		Font = Style.font,
		TextSize = 18,
		TextColor3 = Style.ui.dark,
		Text = "",
		ZIndex = 8,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, action)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, action)

	-- The state of the screen ---------------------------------------------------------------------
	local open = false
	local slotView = Config.CosmeticSlots[1].id -- the slot being browsed
	local selected: string? = nil -- the style being looked at (painted on the player's screen)
	local message: string? = nil
	local waitingFor: string? = nil -- a purchase sent, until the answer or a few seconds
	local onAction: (() -> ())? = nil
	local render: () -> ()

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function clear()
		order = 0
		for _, child in card:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function line(text: string, color: Color3, size: number?)
		return new("TextLabel", {
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Style.font,
			TextSize = size or 15,
			TextColor3 = color,
			ZIndex = 7,
		}, card)
	end

	-- The stadium tier and the cash, on one line.
	local function header()
		local tier = State.data.stadiumTier
		local row = new("Frame", {
			Name = "Header",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, card)
		new("TextLabel", {
			Size = UDim2.fromScale(0.6, 1),
			BackgroundTransparency = 1,
			Text = `Tier {tier} · {TIER_NAMES[tier] or "Stadium"}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Panel.MUTED,
			ZIndex = 7,
		}, row)
		new("TextLabel", {
			Name = "Cash",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.4, 1),
			BackgroundTransparency = 1,
			Text = NumberFormat.money(State.shownCash()),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Style.font,
			TextSize = 16,
			TextColor3 = Panel.GOOD,
			ZIndex = 7,
		}, row)
	end

	-- The slots as icon tabs; a closed one is greyed with its tier under it.
	local function tabs()
		local row = new("Frame", {
			Name = "Tabs",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, TAB_SIZE),
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, card)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		for index, slot in Config.CosmeticSlots do
			local isOpen = Cosmetics.slotOpen(State.data, slot.id)
			local current = slot.id == slotView
			local tab = new("ImageButton", {
				Name = "Tab_" .. slot.id,
				LayoutOrder = index,
				-- All the tabs share the row; on a narrow panel they shrink and stay square.
				Size = UDim2.new(1 / #Config.CosmeticSlots, -6, 0, TAB_SIZE),
				BackgroundColor3 = if isOpen then Style.ui.panel else DISABLED,
				Image = Icons.id("slot_" .. slot.id),
				ImageTransparency = if isOpen then 0 else 0.5,
				ZIndex = 8,
			}, row)
			new("UIAspectRatioConstraint", {
				AspectRatio = 1,
				DominantAxis = Enum.DominantAxis.Width,
			}, tab)
			new("UISizeConstraint", { MaxSize = Vector2.new(TAB_SIZE, TAB_SIZE) }, tab)
			new("UICorner", { CornerRadius = UDim.new(0, 10) }, tab)
			new("UIStroke", {
				Color = if current then Style.ui.good else Style.ui.dark,
				Thickness = if current then 4 else 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, tab)
			if not isOpen then
				new("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -2),
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = `T{slot.tier}`,
					Font = Style.font,
					TextSize = 14,
					TextColor3 = Style.ui.text,
					TextStrokeTransparency = 0,
					ZIndex = 9,
				}, tab)
			end
			tab.Activated:Connect(function()
				if slotView ~= slot.id then
					LockerView.restore()
					slotView, selected, message = slot.id, nil, nil
					render()
				end
			end)
		end
	end

	-- What a card says under the style's name. In a slot that is not open yet nothing is in use.
	local function status(
		def: Config.CosmeticDef,
		using: boolean,
		isOpen: boolean,
		tier: number
	): (string, Color3, Color3?)
		if not isOpen then
			return `Tier {tier}`, Panel.MUTED, nil
		elseif using then
			return "In use", Panel.GOOD, nil
		elseif Cosmetics.owns(State.data, def.id) then
			return if Cosmetics.isFree(def) then "Free" else "Owned", Panel.MUTED, nil
		elseif def.cash then
			return NumberFormat.money(def.cash), Style.ui.dark, Style.ui.gold
		else
			return `R$ {def.robux}`, Style.ui.dark, Style.ui.bar
		end
	end

	local function cards(slotId: string, isOpen: boolean)
		local grid = new("Frame", {
			Name = "Styles",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, card)
		new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		local chosen = if isOpen then Cosmetics.chosen(State.data, slotId) else nil
		local slot = slotDef(slotId)
		for index, def in Cosmetics.styles(slotId) do
			local using = chosen ~= nil and chosen.id == def.id
			local looking = def.id == selected
			local item = new("TextButton", {
				Name = "Style_" .. def.id,
				LayoutOrder = index,
				BackgroundColor3 = if isOpen then CARD_COLOR else DISABLED,
				AutoButtonColor = isOpen,
				Text = "",
				ZIndex = 7,
			}, grid)
			new("UICorner", { CornerRadius = UDim.new(0, 10) }, item)
			new("UIStroke", {
				Color = if looking or (selected == nil and using)
					then Style.ui.good
					else Style.ui.dark,
				Thickness = if looking or (selected == nil and using) then 4 else 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, item)
			local chip = swatch(item, def, 40)
			chip.Position = UDim2.fromOffset(10, (CARD_HEIGHT - 40) / 2)
			new("TextLabel", {
				Name = "StyleName",
				Position = UDim2.fromOffset(58, 8),
				Size = UDim2.new(1, -64, 0, 22),
				BackgroundTransparency = 1,
				Text = def.name,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = Style.font,
				TextSize = 15,
				TextColor3 = Panel.TEXT,
				ZIndex = 8,
			}, item)
			local text, textColor, chipColor =
				status(def, using, isOpen, if slot then slot.tier else 0)
			local price = new("TextLabel", {
				Name = "Price",
				Position = UDim2.fromOffset(58, 34),
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = chipColor or CARD_COLOR,
				BackgroundTransparency = if chipColor then 0 else 1,
				Text = text,
				Font = Style.font,
				TextSize = 13,
				TextColor3 = textColor,
				ZIndex = 8,
			}, item)
			if chipColor then
				new("UICorner", { CornerRadius = UDim.new(0, 6) }, price)
				new("UIPadding", {
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}, price)
			end
			if isOpen then
				item.Activated:Connect(function()
					selected, message = def.id, nil
					LockerView.preview(def)
					render()
				end)
			end
		end
	end

	-- The roof arena's name: a box to type it and a button that pays for it. While the box has the
	-- focus the screen is not redrawn, so the typing is never lost.
	local draft = ""
	local typing = false
	local renaming = false
	local function nameEditor()
		local current = player:GetAttribute("stadiumName")
		local shown = if type(current) == "string" and current ~= "" then current else "No name yet"
		line(`Stadium name: {shown}`, Panel.TEXT, 15)
		local row = new("Frame", {
			Name = "NameRow",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, card)
		local box = new("TextBox", {
			Name = "NameBox",
			Size = UDim2.new(0.62, -6, 1, 0),
			BackgroundColor3 = CARD_COLOR,
			Text = draft,
			PlaceholderText = "Type a name",
			PlaceholderColor3 = Panel.MUTED,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Style.font,
			TextSize = 16,
			TextColor3 = Panel.TEXT,
			ZIndex = 8,
		}, row)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, box)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
		local price = Config.StadiumName.price
		local button = new("TextButton", {
			Name = "Rename",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.38, 1),
			TextScaled = true,
			Font = Style.font,
			TextColor3 = Style.ui.dark,
			ZIndex = 8,
		}, row)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}, button)
		-- The button follows the typing (the screen is not redrawn while the box has the focus).
		local function ready(): boolean
			return not renaming
				and State.data.cash >= price
				and #draft >= Config.StadiumName.minLength
		end
		local function paintButton()
			local short = price - State.data.cash
			local enabled = ready()
			button.BackgroundColor3 = if enabled then Style.ui.good else DISABLED
			button.AutoButtonColor = enabled
			button.Text = if renaming
				then "Checking..."
				elseif short > 0 then `Need {NumberFormat.money(short)}`
				else `Rename {NumberFormat.money(price)}`
		end
		paintButton()
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local text = box.Text
			if #text > Config.StadiumName.maxLength then
				text = string.sub(text, 1, Config.StadiumName.maxLength)
				box.Text = text
			end
			draft = text
			paintButton()
		end)
		box.Focused:Connect(function()
			typing = true
		end)
		box.FocusLost:Connect(function()
			typing = false
		end)
		button.Activated:Connect(function()
			if not ready() then
				return
			end
			renaming, message = true, nil
			Net.fire("RenameStadium", draft)
			render()
			task.delay(WAIT_SECONDS * 2, function()
				if renaming then
					renaming = false
					if open then
						render()
					end
				end
			end)
		end)
		line("Everyone sees the name over your gate. Roblox checks it first.", Panel.MUTED, 13)
	end

	-- The one button under the cards, for the style being looked at (or the one in use).
	local function paintAction(slotId: string, isOpen: boolean)
		local slot = slotDef(slotId)
		local chosen = Cosmetics.chosen(State.data, slotId)
		local id = selected or (chosen and chosen.id)
		local def = if id then Config.CosmeticsById[id] else nil
		local enabled, text, run = false, "", nil :: (() -> ())?
		if not isOpen then
			text = if slot then `Stadium tier {slot.tier}` else ""
		elseif def == nil or (chosen and chosen.id == def.id) then
			text = "In use"
		elseif waitingFor == def.id then
			text = "Waiting..."
		elseif Cosmetics.owns(State.data, def.id) then
			enabled, text = true, "Use"
			local useId = def.id
			run = function()
				Net.fire("SetCosmetic", slotId, useId)
			end
		elseif def.cash then
			local short = def.cash - State.data.cash
			if short > 0 then
				text = `Need {NumberFormat.money(short)} more`
			else
				enabled, text = true, `Buy for {NumberFormat.money(def.cash)}`
				local buyId = def.id
				run = function()
					waitingFor = buyId
					Net.fire("BuyCosmetic", buyId)
				end
			end
		else
			enabled, text = true, `Buy for R$ {def.robux}`
			local buyId = def.id
			run = function()
				waitingFor = buyId
				Net.fire("RequestPurchase", "cosmetic_" .. buyId)
			end
		end
		action.Text = text
		action.BackgroundColor3 = if enabled then Style.ui.good else DISABLED
		action.AutoButtonColor = enabled
		onAction = run
	end

	function render()
		clear()
		local slot = slotDef(slotView)
		local isOpen = Cosmetics.slotOpen(State.data, slotView)
		built.setTitle(if slot then slot.name else "Locker room")
		header()
		tabs()
		if message then
			line(message, Panel.TEXT)
		elseif not isOpen and slot then
			line(`Unlocks at stadium tier {slot.tier}.`, Panel.MUTED)
		else
			line("Tap a style to see it on your stadium.", Panel.MUTED, 14)
		end
		if slotView == "stadium" and isOpen then
			nameEditor()
		end
		cards(slotView, isOpen)
		line(
			"Styles only change how your team looks. Bought ones stay after a New Season.",
			Panel.MUTED,
			13
		)
		paintAction(slotView, isOpen)
		LockerView.focus(slotView)
	end

	action.Activated:Connect(function()
		local run = onAction
		if run == nil then
			return
		end
		run()
		local sent = waitingFor
		render()
		if sent then
			task.delay(WAIT_SECONDS, function()
				if waitingFor == sent then
					waitingFor = nil
					if open then
						render()
					end
				end
			end)
		end
	end)

	-- Controller: the shoulder buttons change slot, B closes.
	local function step(direction: number)
		for index, slot in Config.CosmeticSlots do
			if slot.id == slotView then
				local nextSlot = Config.CosmeticSlots[index + direction]
				if nextSlot then
					LockerView.restore()
					slotView, selected, message = nextSlot.id, nil, nil
					render()
				end
				return
			end
		end
	end
	local function onPad(name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if name == "LockerPrev" then
			step(-1)
		elseif name == "LockerNext" then
			step(1)
		else
			close()
		end
		return Enum.ContextActionResult.Sink
	end

	function close()
		if not open then
			return
		end
		open = false
		backdrop.Visible = false
		selected, message, waitingFor = nil, nil, nil
		ContextActionService:UnbindAction("LockerPrev")
		ContextActionService:UnbindAction("LockerNext")
		ContextActionService:UnbindAction("LockerClose")
		LockerView.leave()
	end

	icon.Activated:Connect(function()
		if locked then
			Dock.reason(tile, "Put a player on the field first.")
			return
		end
		if open then
			return
		end
		open = true
		slotView, selected, message, waitingFor = Config.CosmeticSlots[1].id, nil, nil, nil
		LockerView.enter(gui, panel)
		render()
		backdrop.Visible = true
		ContextActionService:BindAction("LockerPrev", onPad, false, Enum.KeyCode.ButtonL1)
		ContextActionService:BindAction("LockerNext", onPad, false, Enum.KeyCode.ButtonR1)
		ContextActionService:BindAction("LockerClose", onPad, false, Enum.KeyCode.ButtonB)
	end)

	-- The icon shows once the team plays; a slot that opens after the first look shows the small note.
	local lastTier = 0
	local noteToken = 0
	local function refresh()
		locked = not State.data.fieldStarted
		Dock.paint(tile, if locked then "locked" else "open")
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
		if open and not typing then
			-- A style just bought or put on is the one in use now.
			local chosen = Cosmetics.chosen(State.data, slotView)
			if waitingFor and Cosmetics.owns(State.data, waitingFor) then
				waitingFor = nil
			end
			if selected and chosen and chosen.id == selected then
				selected = nil
			end
			render()
		end
	end
	State.onChange(refresh)
	-- The new name arrives filtered from the server: show it on the Locker room's stadium too.
	player:GetAttributeChangedSignal("stadiumName"):Connect(function()
		local name = player:GetAttribute("stadiumName")
		if renaming then
			renaming, draft = false, ""
		end
		if open then
			LockerView.showName(if type(name) == "string" then name else "")
			if not typing then
				render()
			end
		end
	end)

	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "renameRefused" then
			renaming = false
			message = REFUSALS[info.reason] or REFUSALS.unavailable
			if open and not typing then
				render()
			end
		elseif info.kind == "purchaseRefused" then
			if waitingFor then
				waitingFor = nil
				message = REFUSALS[info.reason] or REFUSALS.unavailable
				if open then
					render()
				end
			end
		elseif info.kind == "purchaseDone" then
			local result = info.result
			if type(result) == "table" and result.kind == "cosmetic" then
				waitingFor = nil
				message = nil -- the sign (RewardCard) says what was bought
				if open then
					render()
				end
			end
		end
	end)
	refresh()
end

return LockerUi
