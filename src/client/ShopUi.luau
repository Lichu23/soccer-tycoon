--!strict
-- The Robux shop (docs/PLAN.md, Step 3 and the case rules): the Standard and Elite Case with their odds
-- before the purchase, the match boost and, from floor 4, the Legends. One icon under the daily icons
-- opens it. Every purchase takes two taps (open an item, then Buy), shows what it costs and what this
-- visit has spent, and never pushes: no timers, no badges, no popups. The server decides everything;
-- this only asks (RequestPurchase) and shows the answer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local Dock = require(script.Parent.Dock)
local Icons = require(script.Parent.Icons)
local Legends = require(ReplicatedStorage.Shared.Legends)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local WAIT_SECONDS = 4
local CARD_HEIGHT = 186
local RIBBON_HEIGHT = 36
local CARDS_PER_ROW = 3
local CARD_WIDTH = 0.31
local CARD_GAP = 0.035

-- The short line on a closed card (the full sentences are for the answers of the server).
local CARD_REASONS: { [string]: string } = {
	early = "Opens later",
	locked = "Locked",
	full = "Bank full",
	owned = "Yours",
}

local REFUSALS: { [string]: string } = {
	early = "Cases open a little later.",
	locked = "Not unlocked yet.",
	full = "Your boost bank is full.",
	owned = "You already have him.",
	restricted = "Cases are not available for you.",
	off = "Not available right now.",
	unavailable = "Not available right now.",
}

local ShopUi = {}

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

local function rounded(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function percent(share: number): string
	return string.format("%.1f%%", share * 100)
end

local function attribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function ShopUi.init()
	local gui = new("ScreenGui", {
		Name = "Shop",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))

	local tile = Dock.build(gui, "ShopIcon", 3, "SHOP", Style.ui.gold, "shop")
	local icon = tile.button
	local locked = true
	Dock.badge(tile, "shop")

	local close: () -> ()
	local built = Panel.build(gui, "Shop", 0.84, function()
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

	local function button(name: string, text: string, color: Color3, onClick: (() -> ())?)
		order += 1
		local item = new("TextButton", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = color,
			Font = Style.font,
			TextSize = 17,
			TextColor3 = Style.ui.dark,
			Text = text,
			AutoButtonColor = onClick ~= nil,
			ZIndex = 7,
		}, card)
		rounded(item, 8)
		if onClick then
			item.Activated:Connect(onClick)
		end
		return item
	end

	-- The views --------------------------------------------------------------------------------
	local view: string? = nil -- the product key of the open detail, nil = the list
	local message: string? = nil -- the last answer from the server
	local waiting = false
	local render: () -> ()

	function close()
		backdrop.Visible = false
		view = nil
		message = nil
	end

	local function total()
		local cases, robux = attribute("sessionCases"), attribute("sessionRobux")
		if robux > 0 then
			line(
				`This visit: {cases} {if cases == 1 then "case" else "cases"}, {robux} Robux`,
				{ TextColor3 = Panel.MUTED }
			)
		end
	end

	-- Whether the server would offer this product now, and if not, why. It mirrors the server's rules
	-- for greying a card; the server checks again on every request.
	local function offer(key: string): (boolean, string?)
		local product = Config.Products[key]
		if product.kind == "case" then
			if player:GetAttribute("casesOpen") ~= true then
				return false, "early"
			elseif not Cases.unlocked(State.data, product.caseId or "") then
				return false, "locked"
			end
		elseif product.kind == "boost" then
			if
				attribute("bankedMatches") + Config.Boost.matchPackSize > Config.Boost.matchBankMax
			then
				return false, "full"
			end
		elseif State.data.players[product.playerId or ""] ~= nil then
			return false, "owned"
		end
		return true, nil
	end

	-- A coloured ribbon with the name of a group of cards.
	local function ribbon(text: string)
		order += 1
		local holder = new("Frame", {
			Name = "Ribbon",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, RIBBON_HEIGHT),
			BackgroundTransparency = 1,
		}, card)
		local band = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 1),
			BackgroundColor3 = Color3.fromRGB(232, 64, 96),
			Text = text,
			Font = Style.font,
			TextSize = 20,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 7,
		}, holder)
		rounded(band, 8)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, band)
	end

	-- A row that holds up to three cards side by side.
	local function cardRow(): Frame
		order += 1
		local row = new("Frame", {
			Name = "Cards",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
			BackgroundTransparency = 1,
		}, card)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(CARD_GAP, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		return row
	end

	-- One product card: the name on top, the picture, and a price (or the short reason) at the bottom.
	-- Tapping an open card opens its detail (the two-tap purchase); a closed one only says why.
	local function productCard(parent: Frame, key: string, name: string, iconName: string?)
		local ok, reason = offer(key)
		local product = Config.Products[key]
		local item = new("TextButton", {
			Name = "Row_" .. key,
			Size = UDim2.fromScale(CARD_WIDTH, 1),
			BackgroundColor3 = if ok
				then Color3.fromRGB(250, 247, 255)
				else Color3.fromRGB(196, 194, 214),
			Text = "",
			AutoButtonColor = ok,
			ZIndex = 7,
		}, parent)
		rounded(item, 12)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, item)
		new("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundTransparency = 1,
			Text = name,
			TextWrapped = true,
			Font = Style.font,
			TextSize = 15,
			TextColor3 = Panel.TEXT,
			ZIndex = 8,
		}, item)
		local picture = if iconName then Icons.id(iconName) else ""
		if picture ~= "" then
			new("ImageLabel", {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 40),
				Size = UDim2.fromOffset(88, 88),
				BackgroundTransparency = 1,
				Image = picture,
				ImageColor3 = if ok
					then Color3.fromRGB(255, 255, 255)
					else Color3.fromRGB(150, 150, 165),
				ZIndex = 8,
			}, item)
		else
			new("TextLabel", {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 52),
				Size = UDim2.fromOffset(88, 64),
				BackgroundTransparency = 1,
				Text = "*",
				Font = Style.font,
				TextSize = 56,
				TextColor3 = Color3.fromRGB(255, 190, 40),
				ZIndex = 8,
			}, item)
		end
		local pill = new("TextLabel", {
			Name = "Price",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 34),
			BackgroundColor3 = if ok then Style.ui.good else Color3.fromRGB(120, 122, 140),
			Text = if ok then `{product.robux} Robux` else CARD_REASONS[reason or "locked"],
			Font = Style.font,
			TextSize = 16,
			TextColor3 = if ok then Style.ui.dark else Color3.fromRGB(235, 236, 244),
			ZIndex = 8,
		}, item)
		rounded(pill, 8)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, pill)
		if ok then
			item.Activated:Connect(function()
				view = key
				message = nil
				render()
			end)
		end
	end

	local function renderList()
		built.setTitle("Shop")
		if message then
			line(message, { TextColor3 = Panel.GOOD })
		end
		ribbon("Cases")
		if player:GetAttribute("casesRestricted") == true then
			line(REFUSALS.restricted, { TextColor3 = Panel.MUTED })
		else
			local row = cardRow()
			productCard(row, "caseStandard", Config.Cases.standard.name, "case_standard")
			productCard(row, "caseElite", Config.Cases.elite.name, "case_elite")
		end
		ribbon("Boosts")
		productCard(cardRow(), "matchBoost", "Boost x2", "boost")
		if Legends.reached(State.data) then
			ribbon("Legends")
			line("Skips the trials and the cash price", { TextColor3 = Panel.MUTED })
			local row: Frame? = nil
			local count = 0
			for _, def in Config.Players do
				local key = "legend_" .. def.id
				if def.floor >= Config.LegendFloor and Config.Products[key] then
					if row == nil or count % CARDS_PER_ROW == 0 then
						row = cardRow()
					end
					count += 1
					productCard(row :: Frame, key, def.name, nil)
				end
			end
		end
		total()
	end

	local function renderDetail(key: string)
		local product = Config.Products[key]
		local back = function()
			view = nil
			render()
		end
		if product.kind == "case" then
			local def = Config.Cases[product.caseId or ""]
			local _, odds = Cases.odds(State.data, product.caseId or "")
			built.setTitle(def.name)
			line("One random player. The odds below are the real ones.")
			line(`A player from the floors open: {percent(odds.reached)}`)
			if odds.nextFloor > 0 then
				line(`From the next floor: {percent(odds.nextFloor)}`)
			end
			if odds.further > 0 then
				line(`From floors further on: {percent(odds.further)}`)
			end
			line(`A Legend: {percent(odds.legend)}`)
			line(`A player you already own: {percent(odds.duplicate)}`, {
				TextColor3 = Panel.TEXT,
			})
			line(
				`A duplicate adds a star (+{math.floor(Config.Stars.bonusPerStar * 100)}% income, up to {Config.Stars.maxStars}). After that it gives cash.`,
				{ TextColor3 = Panel.MUTED }
			)
		elseif product.kind == "boost" then
			built.setTitle("Match boost")
			line(
				`Your next {Config.Boost.matchPackSize} matches pay x{Config.Boost.matchMultiplier}.`
			)
			line(
				`It stays until used (you have {attribute("bankedMatches")}, up to {Config.Boost.matchBankMax}).`,
				{ TextColor3 = Panel.MUTED }
			)
		else
			local def = Config.PlayersById[product.playerId or ""]
			built.setTitle(if def then def.name else "Legend")
			line("Yours at once, with no trials and no cash price. Legends stay across seasons.")
		end
		total()
		local buy: TextButton
		buy = button("Buy", `Buy for {product.robux} Robux`, Style.ui.good, function()
			if waiting then
				return
			end
			waiting = true
			buy.Text = "Waiting..."
			Net.fire("RequestPurchase", key)
			task.delay(WAIT_SECONDS, function()
				waiting = false
				if buy.Parent then
					buy.Text = `Buy for {product.robux} Robux`
				end
			end)
		end)
		button("Back", "Back", Style.ui.idle, back)
	end

	function render()
		clear()
		if view then
			renderDetail(view)
		else
			renderList()
		end
	end

	local function open()
		view = nil
		message = nil
		render()
		backdrop.Visible = true
	end
	icon.Activated:Connect(function()
		if locked then
			Dock.reason(tile, "Claim your plot first.")
		else
			open()
		end
	end)

	local function refresh()
		-- The shop opens with the plot. The cards still follow the server rules: the cases wait their
		-- turn (with the reason shown), the match boost is there.
		locked = not State.hasPlot()
		Dock.paint(tile, if locked then "locked" else "open")
		if backdrop.Visible then
			render()
		end
	end
	State.onChange(refresh)
	for _, name in { "casesOpen", "bankedMatches", "sessionRobux", "casesRestricted" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end

	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "purchaseRefused" then
			waiting = false
			message = REFUSALS[info.reason] or REFUSALS.unavailable
			view = nil
			if backdrop.Visible then
				render()
			end
		elseif info.kind == "purchaseDone" then
			waiting = false
			local result = info.result
			if type(result) == "table" and result.kind == "case" then
				-- The reveal plays by itself; the shop gets out of its way.
				close()
			else
				message = "Done."
				view = nil
				if backdrop.Visible then
					render()
				end
			end
		end
	end)
	refresh()
end

return ShopUi
