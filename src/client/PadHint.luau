--!strict
-- The short message when the player steps on a pad they cannot use yet ("Need $7 more", "Finish
-- floor 1 first"). Nothing is written under the pads themselves. Display only: the server decides
-- every purchase; this reads the pad the server says the player stands on (the padKey attribute).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(script.Parent.Net)
local PadInfo = require(ReplicatedStorage.Shared.PadInfo)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

-- Why a pack or a boost on a Robux pad was not offered (the server's answer to the pad).
local PACK_REFUSALS: { [string]: string } = {
	full = "This boost already has an hour left.",
	early = "Buy your first player first.",
	unavailable = "Not available right now.",
}

local HINT_KINDS = { player = true, legend = true, store = true, stadium = true }
local SHOW_SECONDS = 2.2
local FADE_SECONDS = 0.4

local PadHint = {}

local function padOf(key: string): BasePart?
	for _, part in CollectionService:GetTagged("Pad") do
		if part:IsA("BasePart") and part:GetAttribute("PadKey") == key then
			return part
		end
	end
	return nil
end

function PadHint.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PadHint"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.74)
	text.Size = UDim2.fromOffset(420, 40)
	text.BackgroundTransparency = 1
	text.Font = Style.font
	text.TextSize = 26
	text.TextColor3 = Color3.fromRGB(232, 142, 138)
	text.TextTransparency = 1
	text.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Thickness = 3
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Transparency = 1
	outline.Parent = text

	local shown = 0
	local lastKey: string? = nil
	local function show(message: string)
		shown += 1
		local mine = shown
		text.Text = message
		text.TextTransparency = 0
		outline.Transparency = 0
		task.delay(SHOW_SECONDS, function()
			if shown ~= mine then
				return
			end
			local info = TweenInfo.new(FADE_SECONDS)
			TweenService:Create(text, info, { TextTransparency = 1 }):Play()
			TweenService:Create(outline, info, { Transparency = 1 }):Play()
		end)
	end

	local function onPad()
		local key = player:GetAttribute("padKey")
		if type(key) ~= "string" then
			lastKey = nil
			return
		end
		if key == lastKey then
			return
		end
		lastKey = key
		local part = padOf(key)
		local kind = if part then part:GetAttribute("Kind") else nil
		local padId = if part then part:GetAttribute("PadId") else nil
		if type(kind) ~= "string" or type(padId) ~= "string" or not HINT_KINDS[kind] then
			return
		end
		local info = PadInfo.describe(kind, padId, State.data)
		if (info.state == "cannotAfford" or info.state == "locked") and info.note ~= "" then
			show(info.note)
		end
		if info.state == "cannotAfford" then
			Sounds.play("cantAfford")
		end
	end
	player:GetAttributeChangedSignal("padKey"):Connect(onPad)
	-- Cash spent: a new player while standing on a pad (a case win is never on a pad) or a Store
	-- upgrade level. Counted from the server's snapshots, so only real purchases make the sound.
	local ownedCount, storeTotal = -1, -1
	State.onChange(function()
		if not State.loaded then
			return
		end
		local count = 0
		for _ in State.data.players do
			count += 1
		end
		local total = 0
		for _, level in State.data.storeLevels :: { [string]: number } do
			total += level
		end
		local bought = ownedCount >= 0
			and (
				(count > ownedCount and player:GetAttribute("padKey") ~= nil)
				or total > storeTotal
			)
		ownedCount, storeTotal = count, total
		if bought then
			Sounds.play("buy")
		end
	end)

	Net.on("Notice", function(info: any)
		if type(info) == "table" and info.kind == "purchaseRefused" then
			local message = PACK_REFUSALS[info.reason]
			if message and player:GetAttribute("padKey") ~= nil then
				show(message)
			end
		end
	end)
end

return PadHint
