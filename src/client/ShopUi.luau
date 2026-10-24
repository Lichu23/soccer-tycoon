--!strict
-- The Robux shop (docs/PLAN.md, Step 3 and the case rules): the Free, Standard and Elite Case in one
-- Chests box, with the odds before a purchase, and the Legends. The boosts are sold on the
-- pads of the building, not here. One icon under the daily icons
-- opens it. Every purchase takes two taps (open an item, then Buy), shows what it costs and what this
-- visit has spent, and never pushes: no timers, no popups, and the icon's red "1" only ever means the
-- free case is ready (never a paid offer). The server decides everything; this only asks
-- (RequestPurchase) and shows the answer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CaseModal = require(script.Parent.CaseModal)
local Cases = require(ReplicatedStorage.Shared.Cases)
local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Dock = require(script.Parent.Dock)
local Icons = require(script.Parent.Icons)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local Roster = require(ReplicatedStorage.Shared.Roster)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)
local Translate = require(script.Parent.Translate)

local player = Players.LocalPlayer

local WAIT_SECONDS = 4
local CARD_HEIGHT = 150
local CHIP_HEIGHT = 30
local BOX_PADDING = 12
local CARDS_PER_ROW = 3
local CARD_WIDTH = 0.31
local CARD_GAP = 0.035
local SECTION_GAP = 14 -- the extra space above every section's chip but the first
-- A picture that is not a tile already (a Legend's card) is framed like the chest tiles: rounded,
-- the dark outline, and a darker base under it.
local TILE_SIZE = 80
local TILE_BASE = 6
local TILE_CORNER = 14
local DISABLED = Color3.fromRGB(196, 194, 214) -- the grey of a button that cannot be pressed yet

-- The short line on a closed card (the full sentences are for the answers of the server).
local CARD_REASONS: { [string]: string } = {
	early = "After floor 1",
	locked = "Locked",
	owned = "Yours",
}

local REFUSALS: { [string]: string } = {
	early = "Chests open once floor 1 is done.",
	locked = "Not unlocked yet.",
	owned = "You already have him.",
	restricted = "Chests are not available for you.",
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

-- "30%" or "36.5%": the decimal only when it is not zero.
local function percent(share: number): string
	return (string.gsub(string.format("%.1f%%", share * 100), "%.0%%$", "%%"))
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

	local tile = Dock.build(gui, "ShopIcon", 2, "SHOP", Style.ui.gold, "shop")
	local icon = tile.button
	local locked = true
	Dock.badge(tile)

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

	-- A box of one kind of prize in a case's odds: its icon, its name and its whole chance on top, and
	-- under it the parts as small pills ("15 min 15%"). `width` is its share of the parent (the two
	-- boosts sit side by side). Returns the pill row.
	local function oddsCard(
		parent: Instance,
		width: number,
		iconName: string,
		title: string,
		share: number
	): Frame
		order += 1
		local box = new("Frame", {
			Name = "OddsCard",
			LayoutOrder = order,
			Size = UDim2.fromScale(width, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(250, 247, 255),
			ZIndex = 7,
		}, parent)
		rounded(box, 14)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, box)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}, box)
		new(
			"UIListLayout",
			{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
			box
		)
		local head = new("Frame", {
			Name = "Head",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, box)
		new("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
			Image = Icons.id(iconName),
			ZIndex = 7,
		}, head)
		new("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.new(1, -44 - 64, 1, 0),
			BackgroundTransparency = 1,
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Panel.TEXT,
			ZIndex = 7,
		}, head)
		new("TextLabel", {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 64, 1, 0),
			BackgroundTransparency = 1,
			Text = percent(share),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Style.font,
			TextSize = 22,
			TextColor3 = Panel.TEXT,
			ZIndex = 7,
		}, head)
		local pills = new("Frame", {
			Name = "Parts",
			LayoutOrder = 2,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, box)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, pills)
		return pills
	end

	-- One part of a prize in its box: a light pill with the name and, darker, its chance.
	local function oddsPill(pills: Frame, text: string, share: number)
		local pill = new("TextLabel", {
			Name = "Part",
			LayoutOrder = #pills:GetChildren(),
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(236, 231, 252),
			RichText = true,
			Text = Translate.format(
				text .. '  <font color="{1}">{2}</font>',
				"#" .. Panel.TEXT:ToHex(),
				percent(share)
			),
			Font = Style.font,
			TextSize = 14,
			TextColor3 = Panel.MUTED,
			ZIndex = 7,
		}, pills)
		rounded(pill, 13)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, pill)
	end

	-- The views --------------------------------------------------------------------------------
	local view: string? = nil -- the product key of the open detail, nil = the list
	local waiting = false
	local render: () -> ()

	-- Asks the server for the product's Robux prompt (Roblox's own window shows the item, the price
	-- and the confirm). Taps while the answer is on its way do nothing.
	local function request(key: string)
		if waiting then
			return
		end
		waiting = true
		Net.fire("RequestPurchase", key)
		task.delay(WAIT_SECONDS, function()
			waiting = false
		end)
	end

	function close()
		backdrop.Visible = false
		view = nil
	end

	local function total()
		local cases, robux = attribute("sessionCases"), attribute("sessionRobux")
		if robux > 0 then
			line(
				`This visit: {cases} {if cases == 1 then "chest" else "chests"}, {robux} Robux`,
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
		elseif State.data.players[product.playerId or ""] ~= nil then
			return false, "owned"
		elseif
			product.kind == "legend"
			and Roster.floorsComplete(State.data) < Config.LegendRobuxFloors
		then
			return false, "locked"
		end
		return true, nil
	end

	-- A group of cards: a small red chip with its name, then one white box that holds the cards in rows
	-- of three. Returns the box; `cardRow` adds the rows to it.
	local function section(text: string): Frame
		if order > 0 then
			order += 1
			new("Frame", {
				Name = "Gap",
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, SECTION_GAP),
				BackgroundTransparency = 1,
			}, card)
		end
		order += 1
		local chip = new("TextLabel", {
			Name = "Chip",
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, CHIP_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(232, 64, 96),
			Text = text,
			Font = Style.font,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 7,
		}, card)
		rounded(chip, 8)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, chip)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, chip)

		order += 1
		local box = new("Frame", {
			Name = "Box",
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(250, 247, 255),
			ZIndex = 7,
		}, card)
		rounded(box, 16)
		new("UIStroke", {
			Color = Style.ui.dark,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, box)
		new("UIPadding", {
			PaddingTop = UDim.new(0, BOX_PADDING),
			PaddingBottom = UDim.new(0, BOX_PADDING),
			PaddingLeft = UDim.new(0, BOX_PADDING),
			PaddingRight = UDim.new(0, BOX_PADDING),
		}, box)
		new("UIListLayout", {
			Padding = UDim.new(0, BOX_PADDING),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, box)
		return box
	end

	-- A row of the box that holds up to three cards side by side.
	local function cardRow(box: Frame): Frame
		local row = new("Frame", {
			Name = "Cards",
			LayoutOrder = #box:GetChildren(),
			Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
			BackgroundTransparency = 1,
		}, box)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(CARD_GAP, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		return row
	end

	-- One card in a box: the name on top, the picture, and under it a green pill (a price or "Free")
	-- when it can be bought, or a short muted reason when it can't (the picture is dimmed then).
	local function card_(
		parent: Frame,
		key: string,
		name: string,
		iconName: string?,
		open: boolean,
		pillText: string,
		onTap: (() -> ())?,
		greyPill: boolean?,
		tileBase: Color3? -- frame a flat picture as a tile, on a base of this colour
	)
		local item = new("TextButton", {
			Name = "Row_" .. key,
			Size = UDim2.fromScale(CARD_WIDTH, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 8,
		}, parent)
		local title = new("TextLabel", {
			Name = "Name",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = name,
			TextScaled = true,
			Font = Style.font,
			TextColor3 = Panel.TEXT,
			ZIndex = 8,
		}, item)
		new("UITextSizeConstraint", { MaxTextSize = 15 }, title)
		local picture = if iconName then Icons.id(iconName) else ""
		local dim = Color3.fromRGB(150, 150, 165)
		if picture ~= "" and tileBase then
			local function framed(instance: GuiObject)
				rounded(instance, TILE_CORNER)
				new("UIStroke", {
					Color = Style.ui.dark,
					Thickness = 3,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}, instance)
			end
			-- The base peeks out under the picture, like the thick foot of the chest tiles.
			framed(new("Frame", {
				Name = "Base",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 30 + TILE_BASE),
				Size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
				BackgroundColor3 = if open then tileBase else tileBase:Lerp(dim, 0.6),
				ZIndex = 8,
			}, item))
			framed(new("ImageLabel", {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 30),
				Size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
				BackgroundTransparency = 1,
				Image = picture,
				ImageColor3 = if open then Color3.fromRGB(255, 255, 255) else dim,
				ZIndex = 9,
			}, item))
		elseif picture ~= "" then
			new("ImageLabel", {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 28),
				Size = UDim2.fromOffset(88, 88),
				BackgroundTransparency = 1,
				Image = picture,
				ImageColor3 = if open then Color3.fromRGB(255, 255, 255) else dim,
				ZIndex = 8,
			}, item)
		else
			new("TextLabel", {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 40),
				Size = UDim2.fromOffset(88, 64),
				BackgroundTransparency = 1,
				Text = "*",
				Font = Style.font,
				TextSize = 56,
				TextColor3 = Color3.fromRGB(255, 190, 40),
				ZIndex = 8,
			}, item)
		end
		-- An open card has a green price button; a card that opens later can show its price on a grey
		-- one (`greyPill`); otherwise a closed card only has a short muted reason.
		local filled = open or greyPill == true
		local pill = new("TextLabel", {
			Name = "Price",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, -8, 0, 30),
			BackgroundColor3 = if open then Style.ui.good else DISABLED,
			BackgroundTransparency = if filled then 0 else 1,
			Text = pillText,
			Font = Style.font,
			TextSize = if filled then 16 else 14,
			TextColor3 = if open then Style.ui.dark else Panel.MUTED,
			ZIndex = 8,
		}, item)
		if filled then
			rounded(pill, 8)
			new("UIStroke", {
				Color = Style.ui.dark,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, pill)
		end
		if onTap then
			item.Activated:Connect(onTap)
		end
	end

	-- What opens a case that is not open yet, for the greyed card.
	local function caseHint(product: Config.ProductDef, reason: string?): string
		local def = Config.Cases[product.caseId or ""]
		if reason == "locked" and def then
			return `Complete floor {def.floorsComplete} to unlock the {def.name}.`
		end
		return REFUSALS.early
	end

	-- A product card. Tapping an open chest opens its odds first (they are shown before a paid random
	-- item); any other open card goes straight to Roblox's purchase window, which shows the item and
	-- the price. A chest or a Legend that opens later keeps its price on a grey button and, tapped,
	-- says what opens it; any other closed card only shows the short reason.
	local function productCard(parent: Frame, key: string, name: string, iconName: string?)
		local ok, reason = offer(key)
		local product = Config.Products[key]
		-- A Legend's picture is a flat card image: framed as a tile on a gold base.
		local tileBase = if product.kind == "legend" then Style.rarityTrim.Legend else nil
		if not ok and product.kind == "case" and (reason == "early" or reason == "locked") then
			card_(parent, key, name, iconName, false, `{product.robux} Robux`, function()
				built.toast(caseHint(product, reason))
			end, true)
			return
		end
		if not ok and product.kind == "legend" and reason == "locked" then
			card_(parent, key, name, iconName, false, `{product.robux} Robux`, function()
				built.toast(`Complete floor {Config.LegendRobuxFloors} to sign Legends with Robux.`)
			end, true, tileBase)
			return
		end
		card_(
			parent,
			key,
			name,
			iconName,
			ok,
			if ok then `{product.robux} Robux` else CARD_REASONS[reason or "locked"],
			if ok
				then function()
					if product.kind == "case" then
						view = key
						render()
					else
						request(key)
					end
				end
				else nil,
			nil,
			tileBase
		)
	end

	-- The free case: opens its own screen (the roulette). Locked until the first player is bought.
	local function freeCaseCard(parent: Frame)
		local unlocked = player:GetAttribute("dailyUnlocked") == true
		local readyAt = attribute("caseReadyAt")
		local status = DailyInfo.status(unlocked, readyAt, Workspace:GetServerTimeNow())
		local pill = if status == "ready"
			then "Free"
			elseif status == "waiting" then DailyInfo.waitText(
				readyAt - Workspace:GetServerTimeNow()
			)
			else "Buy a player"
		card_(
			parent,
			"caseFree",
			"Free Chest",
			"case",
			status == "ready",
			pill,
			if unlocked
				then function()
					close()
					CaseModal.open()
				end
				else nil
		)
	end

	local function renderList()
		built.setTitle("Shop")
		local row = cardRow(section("Chests"))
		freeCaseCard(row)
		if player:GetAttribute("casesRestricted") == true then
			line(REFUSALS.restricted, { TextColor3 = Panel.MUTED })
		else
			productCard(row, "caseStandard", Config.Cases.standard.name, "case_standard")
			productCard(row, "caseElite", Config.Cases.elite.name, "case_elite")
		end
		do
			local box = section("Legends")
			local legendRow: Frame? = nil
			local count = 0
			for _, def in Config.Players do
				local key = "legend_" .. def.id
				if def.floor >= Config.LegendFloor and Config.Products[key] then
					if legendRow == nil or count % CARDS_PER_ROW == 0 then
						legendRow = cardRow(box)
					end
					count += 1
					productCard(legendRow :: Frame, key, def.name, key)
				end
			end
			line(
				"Robux signs a Legend at once: no cash price and no trials.",
				{ TextColor3 = Panel.MUTED }
			)
		end
		total()
	end

	local function renderDetail(key: string)
		local product = Config.Products[key]
		if product.kind == "case" then
			local def = Config.Cases[product.caseId or ""]
			local entries, odds = Cases.odds(State.data, product.caseId or "")
			built.setTitle(def.name)
			-- The real odds, as rolled (Cases.odds): a box per kind of prize with its whole chance, and
			-- its parts as pills. The players first, then the two boosts side by side.
			local players = oddsCard(card, 1, "slot_kit", "Player", 1 - odds.boost)
			oddsPill(players, "Floors you've opened", odds.reached)
			if odds.nextFloor > 0 then
				oddsPill(players, "Next floor", odds.nextFloor)
			end
			if odds.further > 0 then
				oddsPill(players, "Floors further on", odds.further)
			end
			oddsPill(players, "Legend", odds.legend)
			if odds.boost > 0 then
				order += 1
				local boosts = new("Frame", {
					Name = "Boosts",
					LayoutOrder = order,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					ZIndex = 7,
				}, card)
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0.03, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}, boosts)
				for _, kind in { "cash", "tp" } do
					local rows = {}
					local share = 0
					for _, boost in Config.CaseBoosts do
						if boost.kind == kind then
							for _, entry in entries do
								if entry.id == boost.id then
									table.insert(rows, { boost = boost, chance = entry.chance })
									share += entry.chance
								end
							end
						end
					end
					if #rows > 0 then
						local pills = oddsCard(boosts, 0.485, kind, rows[1].boost.label, share)
						for _, row in rows do
							oddsPill(
								pills,
								(string.gsub(row.boost.detail, "minutes", "min")),
								row.chance
							)
						end
					end
				end
			end
			line(
				if def.newOnly and odds.duplicate == 0
					then "Only players you don't have yet."
					else `A player you have: +1 star (+{math.floor(
						Config.Stars.bonusPerStar * 100
					)}% income, max {Config.Stars.maxStars}), then cash.`,
				{ TextColor3 = Panel.MUTED }
			)
		end
		total()
		local buy: TextButton
		buy = button("Buy", `Buy for {product.robux} Robux`, Style.ui.good, function()
			if waiting then
				return
			end
			buy.Text = "Waiting..."
			request(key)
			task.delay(WAIT_SECONDS, function()
				if buy.Parent then
					buy.Text = `Buy for {product.robux} Robux`
				end
			end)
		end)
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
		-- turn (with the reason shown).
		locked = not State.hasPlot()
		Dock.paint(tile, if locked then "locked" else "open")
		if backdrop.Visible then
			render()
		end
	end
	State.onChange(refresh)
	-- The "1" stays while the free case is ready and goes only when it is claimed (opening the Shop
	-- and leaving keeps it). Checked every second, as the case gets ready with time.
	task.spawn(function()
		while true do
			local unlocked = State.hasPlot() and player:GetAttribute("dailyUnlocked") == true
			local readyAt = attribute("caseReadyAt")
			local status = DailyInfo.status(unlocked, readyAt, Workspace:GetServerTimeNow())
			Dock.setPending(tile, status == "ready")
			task.wait(1)
		end
	end)
	for _, name in
		{
			"casesOpen",
			"sessionRobux",
			"casesRestricted",
			"dailyUnlocked",
			"caseReadyAt",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end

	Net.on("Notice", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.kind == "purchaseRefused" then
			waiting = false
			view = nil
			if backdrop.Visible then
				render()
				built.toast(REFUSALS[info.reason] or REFUSALS.unavailable)
			end
		elseif info.kind == "purchaseDone" then
			waiting = false
			local result = info.result
			if type(result) == "table" and result.kind == "case" then
				-- The case's roulette plays, then the reward card or the reveal; the shop gets out of its way.
				close()
				CaseModal.openPaid(result)
			else
				-- The sign (RewardCard) says what was bought.
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
