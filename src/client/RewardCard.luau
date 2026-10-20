--!strict
-- The one card that says what the player just got: a bought item (the sign after a Robux purchase), the
-- prize of the free case and the result of the penalty kicks. It shares the look of the Shop and the
-- Locker room (light lavender, dark outline, a red ribbon with the title), pops in, goes away by itself
-- after a few seconds and on a tap. It never asks for anything and never blocks the game.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Icons)
local Net = require(script.Parent.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Panel = require(script.Parent.Panel)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local SHOW_SECONDS = 4.5
local CARD_WIDTH = 360
local DISPLAY_ORDER = 8 -- above the Shop, the Locker room and the cases screen

export type Content = {
	title: string, -- the ribbon: "PURCHASE", "FREE CASE", "PENALTIES DONE"
	big: string, -- the main line: what it is
	detail: string?, -- one short line under it
	icon: string?, -- a name in client/Icons
	good: boolean?, -- false = a plain result (no gold stroke); default true
}

local RewardCard = {}

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

local gui: ScreenGui? = nil
local token = 0

local function build(): ScreenGui
	local built = new("ScreenGui", {
		Name = "RewardCard",
		ResetOnSpawn = false,
		DisplayOrder = DISPLAY_ORDER,
		IgnoreGuiInset = true,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	return built
end

-- Shows the card. A newer one replaces the one on screen.
function RewardCard.show(content: Content)
	if gui == nil then
		gui = build()
	end
	local root = gui :: ScreenGui
	for _, child in root:GetChildren() do
		child:Destroy()
	end
	token += 1
	local myToken = token

	local card = new("TextButton", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(226, 216, 255),
		Text = "",
		AutoButtonColor = false,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, card)
	new("UIStroke", {
		Color = if content.good == false then Style.ui.dark else Style.ui.gold,
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	local scale = new("UIScale", {}, card)
	-- The lines go in a body with the list layout; the ribbon is not part of the list.
	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 36),
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}, body)

	-- The ribbon sits on the top edge of the card.
	local ribbon = new("TextLabel", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(240, 36),
		BackgroundColor3 = Color3.fromRGB(232, 64, 96),
		Text = content.title,
		Font = Style.font,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 3,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, ribbon)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, ribbon)

	local order = 0
	local picture = if content.icon then Icons.id(content.icon) else ""
	if picture ~= "" then
		order += 1
		new("ImageLabel", {
			Name = "Picture",
			LayoutOrder = order,
			Size = UDim2.fromOffset(84, 84),
			BackgroundTransparency = 1,
			Image = picture,
			ZIndex = 2,
		}, body)
	end
	order += 1
	new("TextLabel", {
		Name = "Big",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = content.big,
		TextWrapped = true,
		Font = Style.font,
		TextSize = 34,
		TextColor3 = Panel.TEXT,
		ZIndex = 2,
	}, body)
	if content.detail and content.detail ~= "" then
		order += 1
		new("TextLabel", {
			Name = "Detail",
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = content.detail,
			TextWrapped = true,
			Font = Style.font,
			TextSize = 18,
			TextColor3 = Panel.MUTED,
			ZIndex = 2,
		}, body)
	end

	local camera = Workspace.CurrentCamera
	local fit = 1
	if camera then
		fit = math.min(1, camera.ViewportSize.X / (CARD_WIDTH + 40), camera.ViewportSize.Y / 320)
	end
	root.Enabled = true
	if GuiService.ReducedMotionEnabled then
		scale.Scale = fit
	else
		scale.Scale = fit * 0.6
		TweenService:Create(
			scale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = fit }
		):Play()
	end

	local function hide()
		if token == myToken then
			root.Enabled = false
		end
	end
	card.Activated:Connect(hide)
	task.delay(SHOW_SECONDS, hide)
end

-- What the free case gave, as the card's text.
function RewardCard.freeCase(prize: any)
	if type(prize) ~= "table" then
		return
	end
	if prize.kind == "cash" and type(prize.amount) == "number" then
		RewardCard.show({
			title = "FREE CASE",
			big = "+" .. NumberFormat.money(prize.amount),
			detail = "Added to your cash",
			icon = "cash",
		})
	elseif prize.kind == "tp" and type(prize.amount) == "number" then
		RewardCard.show({
			title = "FREE CASE",
			big = "+" .. prize.amount .. " TP",
			detail = "Added to your training points",
			icon = "tp",
		})
	elseif prize.kind == "boost" and type(prize.seconds) == "number" then
		RewardCard.show({
			title = "FREE CASE",
			big = "x2 boost",
			detail = string.format("Double income for %d min", math.ceil(prize.seconds / 60)),
			icon = "boost",
		})
	end
end

-- The sign after a Robux purchase: what was bought (the server's answer says what it was).
local function purchaseCard(result: any): Content?
	if type(result) ~= "table" then
		return nil
	end
	if result.kind == "boost" then
		return {
			title = "PURCHASE",
			big = "Match boost",
			detail = `Your next {result.matches or Config.Boost.matchPackSize} matches pay x{Config.Boost.matchMultiplier}`,
			icon = "boost",
		}
	elseif result.kind == "cash" and type(result.amount) == "number" then
		return {
			title = "PURCHASE",
			big = "+" .. NumberFormat.money(result.amount),
			detail = "Added to your cash",
			icon = "cash",
		}
	elseif result.kind == "tp" and type(result.amount) == "number" then
		return {
			title = "PURCHASE",
			big = "+" .. NumberFormat.short(result.amount) .. " TP",
			detail = "Added to your training points",
			icon = "tp",
		}
	elseif result.kind == "cosmetic" then
		local def = Config.CosmeticsById[result.cosmeticId or ""]
		if def == nil then
			return nil
		end
		local slotName = ""
		for _, slot in Config.CosmeticSlots do
			if slot.id == def.slot then
				slotName = " " .. slot.name
			end
		end
		return {
			title = "PURCHASE",
			big = def.name .. slotName,
			detail = "Yours now, and already in use",
			icon = "slot_" .. def.slot,
		}
	elseif result.kind == "legend" then
		local def = Config.PlayersById[result.playerId or ""]
		return {
			title = "PURCHASE",
			big = if def then def.name else "A Legend",
			detail = if result.isNew == false
				then "You already had him"
				else "A Legend joins your team",
		}
	end
	return nil -- the cases show their reveal
end

function RewardCard.init()
	Net.on("Notice", function(info: any)
		if type(info) ~= "table" or info.kind ~= "purchaseDone" then
			return
		end
		local content = purchaseCard(info.result)
		if content then
			RewardCard.show(content)
		end
	end)
end

return RewardCard
