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
local Legends = require(ReplicatedStorage.Shared.Legends)
local Net = require(script.Parent.Net)
local Panel = require(script.Parent.Panel)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local ICON_SIZE = 52
local ICON_TOP = 8 + 2 * (ICON_SIZE + 8) -- under the case and kick icons
local WAIT_SECONDS = 4

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

	local icon = new("TextButton", {
		Name = "ShopIcon",
		Position = UDim2.fromOffset(8, ICON_TOP),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundColor3 = Style.ui.panel,
		Text = "SHOP",
		Font = Style.font,
		TextSize = 14,
		TextColor3 = Style.ui.text,
		AutoButtonColor = false,
		Visible = false,
	}, gui)
	rounded(icon, 12)

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

	local function listRow(key: string, text: string)
		local ok, reason = true, nil
		-- Mirrors the server's rules for greying a row; the server checks again on every request.
		local product = Config.Products[key]
		if product.kind == "case" then
			local def = Config.Cases[product.caseId or ""]
			if player:GetAttribute("casesOpen") ~= true then
				ok, reason = false, "early"
			elseif not Cases.unlocked(State.data, product.caseId or "") then
				ok, reason = false, "locked"
			end
			text = if def then def.name else text
		elseif product.kind == "boost" then
			if
				attribute("bankedMatches") + Config.Boost.matchPackSize > Config.Boost.matchBankMax
			then
				ok, reason = false, "full"
			end
		elseif State.data.players[product.playerId or ""] ~= nil then
			ok, reason = false, "owned"
		end
		if ok then
			button("Row_" .. key, `{text}   {product.robux} Robux`, Style.ui.gold, function()
				view = key
				message = nil
				render()
			end)
		else
			button(
				"Row_" .. key,
				`{text}   {REFUSALS[reason or "locked"]}`,
				Color3.fromRGB(70, 74, 90),
				nil
			).TextColor3 =
				Color3.fromRGB(215, 220, 232)
		end
	end

	local function renderList()
		built.setTitle("Shop")
		if message then
			line(message, { TextColor3 = Panel.GOOD })
		end
		if player:GetAttribute("casesRestricted") == true then
			line(REFUSALS.restricted, { TextColor3 = Panel.MUTED })
		else
			listRow("caseStandard", "Standard Case")
			listRow("caseElite", "Elite Case")
		end
		listRow("matchBoost", "Boost: next 30 matches x2")
		if Legends.reached(State.data) then
			line("Legends: skips the trials and the cash price", { TextColor3 = Panel.MUTED })
			for _, def in Config.Players do
				local key = "legend_" .. def.id
				if def.floor >= Config.LegendFloor and Config.Products[key] then
					listRow(key, def.name)
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
	icon.Activated:Connect(open)

	local function refresh()
		local shown = player:GetAttribute("casesOpen") == true or Legends.reached(State.data)
		icon.Visible = shown
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
