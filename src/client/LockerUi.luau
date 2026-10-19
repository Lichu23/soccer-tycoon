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
local Dock = require(script.Parent.Dock)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

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

	local tile = Dock.build(gui, "LockerIcon", 4, "LOCKER", Style.ui.bar, "locker")
	local icon = tile.button
	local locked = true

	-- The small note that a new slot opened: beside the icon, never blocking, gone after a few seconds.
	local note = new("TextLabel", {
		Name = "Note",
		Position = UDim2.fromOffset(
			Dock.position(4).X.Offset + Dock.SIZE + 10,
			Dock.position(4).Y.Offset + 10
		),
		Size = UDim2.fromOffset(120, 24),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		Text = "New styles",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.gold,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, note)

	local close: () -> ()
	local built = Panel.build(gui, "Locker room", 0.8, function()
		close()
	end)
	local backdrop, card = built.backdrop, built.card

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
			TextColor3 = Panel.TEXT,
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

	function close()
		backdrop.Visible = false
		slotView, previewId, message = nil, nil, nil
	end

	local function renderSlots()
		built.setTitle("Locker room")
		if message then
			line(message, { TextColor3 = Panel.GOOD })
		end
		for _, slot in Config.CosmeticSlots do
			if Cosmetics.slotOpen(State.data, slot.id) then
				local chosen = Cosmetics.chosen(State.data, slot.id)
				local item = row(
					"Slot_" .. slot.id,
					`{slot.name}: {if chosen then chosen.name else "-"}`,
					Style.ui.gold,
					nil,
					function()
						slotView, message = slot.id, nil
						render()
					end
				)
				Panel.rowIcon(item, "slot_" .. slot.id)
			else
				local item = row(
					"Slot_" .. slot.id,
					`{slot.name}   Stadium tier {slot.tier}`,
					Color3.fromRGB(70, 74, 90),
					nil,
					nil
				)
				item.TextColor3 = TEXT_COLOR
				Panel.rowIcon(item, "slot_" .. slot.id)
			end
		end
	end

	local function renderStyles(slotId: string)
		local slot
		for _, candidate in Config.CosmeticSlots do
			if candidate.id == slotId then
				slot = candidate
			end
		end
		built.setTitle(if slot then slot.name else "Styles")
		if message then
			line(message, { TextColor3 = Panel.GOOD })
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
		built.setTitle(def.name)
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
		if locked then
			Dock.reason(tile, "Put a player on the field first.")
			return
		end
		slotView, previewId, message = nil, nil, nil
		render()
		backdrop.Visible = true
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
