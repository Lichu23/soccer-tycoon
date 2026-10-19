--!strict
-- The rarity reveal (docs/PLAN.md, Step 7): the first player of each rarity and every case win. A
-- full screen card in the rarity colour with the name, number, nationality and a mannequin doing a
-- ball trick, about 3 seconds, a tap skips it. The very first purchase gets a short banner instead
-- that does not catch touches, so the player can keep walking. Only slow fades, no flashes. With
-- reduced motion the card is still and shorter. The server already granted the player: this only
-- shows it, then tells the server it was seen (AckReveal) so it is not replayed after a rejoin.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local Net = require(script.Parent.Net)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local CARD_W, CARD_H = 420, 320
local VIEW_W, VIEW_H = 200, 150
local FULL_SECONDS = 3
local REDUCED_SECONDS = 2
local SHORT_SECONDS = 2
local SKIP_AFTER = 0.6 -- a skip tap is ignored right after the start (a leftover tap)
local FADE = 0.3

-- The ball trick, in studs and seconds, in the mannequin's own space (it looks along -Z).
local JUGGLE_SECONDS = 1.1 -- from one kick to the next
local JUGGLE_HEIGHT = 3.2 -- how high the ball goes above the foot
local BALL_X, BALL_Z = 0.7, -1.6
local BALL_REST_Y = -2.3 -- the ball at the foot
local HIP_RIGHT = Vector3.new(0.5, -1, 0)
local SHOULDER_LEFT = Vector3.new(-1.4, 1, 0)
local SHOULDER_RIGHT = Vector3.new(1.4, 1, 0)
local KICK_BACK = 0.5 -- radians
local KICK_FORWARD = 0.9

type Entry = {
	playerId: string,
	isNew: boolean,
	firstOfRarity: boolean?,
	short: boolean?,
	starsGained: number?,
	stars: number?,
}

local Reveal = {}

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

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = Style.font
	props.TextColor3 = props.TextColor3 or Style.ui.text
	local text = new("TextLabel", props, parent)
	new("UIStroke", { Thickness = 2, Color = Style.ui.dark }, text)
	return text
end

-- The kick angle (radians, positive swings the foot forward) around the moment the foot meets the
-- ball, `offset` in cycles from that moment: a slow wind-up backwards, a quick swing through, then
-- the leg settles.
local function legAngle(offset: number): number
	if offset < -0.3 or offset > 0.2 then
		return 0
	elseif offset < -0.14 then
		return -KICK_BACK * (offset + 0.3) / 0.16
	elseif offset < 0 then
		return -KICK_BACK + (KICK_FORWARD + KICK_BACK) * (offset + 0.14) / 0.14
	end
	return KICK_FORWARD * (1 - offset / 0.2)
end

-- Turns a limb about its joint (a pivot on the X axis); `reach` is the distance from the joint to
-- the middle of the limb, along its length.
local function swingLimb(limb: BasePart, joint: Vector3, angle: number, reach: number)
	limb.CFrame = CFrame.new(joint) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, reach, 0)
end

-- Two small dark eyes on the front of the head (the front is the -Z side), so the way it faces is
-- clear. The head is a ball centred at (0, 1.7, 0).
local function addEyes(model: Model)
	for _, side in { -1, 1 } do
		new("Part", {
			Name = "Eye",
			Size = Vector3.new(0.18, 0.24, 0.06),
			Color = Style.ui.dark,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CFrame = CFrame.new(side * 0.28, 1.8, -0.62),
		}, model)
	end
end

-- The player juggling in a small 3D view, facing the camera: the right foot kicks the ball up and
-- catches it on the way down. Returns the update function to call every frame (nil when still).
local function buildTrick(parent: Instance, def: Config.PlayerDef, animated: boolean): (() -> ())?
	local view = new("ViewportFrame", {
		Name = "Trick",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.fromOffset(VIEW_W, VIEW_H),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 190, 190),
		LightColor = Color3.fromRGB(255, 255, 255),
	}, parent)
	local model = Mannequin.build(def, nil, false)
	addEyes(model)
	model.Parent = view
	local ball = new("Part", {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.3, 1.3, 1.3),
		Color = Color3.fromRGB(245, 245, 245),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CFrame = CFrame.new(BALL_X, BALL_REST_Y, BALL_Z),
	}, view)
	local camera = new("Camera", {
		-- The mannequin looks along -Z, so the camera stands on that side, with the ball in front.
		CFrame = CFrame.lookAt(Vector3.new(0, 0.8, -11), Vector3.new(0, 0.8, 0)),
		FieldOfView = 50,
	}, view)
	view.CurrentCamera = camera
	if not animated then
		return nil
	end
	local rightLeg = model:FindFirstChild("RightLeg") :: BasePart?
	local leftArm = model:FindFirstChild("LeftArm") :: BasePart?
	local rightArm = model:FindFirstChild("RightArm") :: BasePart?
	if rightLeg == nil or leftArm == nil or rightArm == nil then
		return nil
	end
	-- One clock drives both: the ball leaves the foot at phase 0 and comes back at phase 1, and the
	-- leg swings through the ball exactly at that moment. The figure itself never turns.
	local startedAt = os.clock()
	return function()
		local phase = ((os.clock() - startedAt) / JUGGLE_SECONDS) % 1
		ball.CFrame =
			CFrame.new(BALL_X, BALL_REST_Y + JUGGLE_HEIGHT * 4 * phase * (1 - phase), BALL_Z)
		local swing = legAngle(if phase > 0.5 then phase - 1 else phase)
		swingLimb(rightLeg, HIP_RIGHT, swing, -1)
		swingLimb(leftArm, SHOULDER_LEFT, -swing * 0.4, -0.9)
		swingLimb(rightArm, SHOULDER_RIGHT, swing * 0.4, -0.9)
	end
end

local function starsText(entry: Entry): string?
	if entry.isNew or entry.stars == nil then
		return nil
	end
	local max = Config.Stars.maxStars
	if (entry.starsGained or 0) > 0 then
		return string.format("+%d star · %d/%d", entry.starsGained :: number, entry.stars, max)
	end
	return string.format("Max stars · %d/%d", entry.stars, max)
end

function Reveal.init()
	local gui = new("ScreenGui", {
		Name = "Reveal",
		ResetOnSpawn = false,
		DisplayOrder = 7,
		IgnoreGuiInset = true,
	}, player:WaitForChild("PlayerGui"))

	local queue: { Entry } = {}
	local current: Entry? = nil
	local token = 0

	-- The same reveal can arrive twice (sent on purchase and again when the client reports ready).
	local function same(a: Entry, b: Entry): boolean
		return a.playerId == b.playerId and a.isNew == b.isNew
	end
	local function known(entry: Entry): boolean
		if current and same(current, entry) then
			return true
		end
		for _, queued in queue do
			if same(queued, entry) then
				return true
			end
		end
		return false
	end

	local playNext: () -> ()

	local function fadeTo(root: GuiObject, transparency: number)
		TweenService:Create(root, TweenInfo.new(FADE), { BackgroundTransparency = transparency })
			:Play()
	end

	local function play(entry: Entry)
		local def = Config.PlayersById[entry.playerId]
		if def == nil then
			current = nil
			Net.fire("AckReveal", entry.playerId)
			playNext()
			return
		end
		current = entry
		token += 1
		local myToken = token
		local startedAt = os.clock()
		local reduced = GuiService.ReducedMotionEnabled
		local color = Style.rarityColors[def.rarity] or Style.rarityColors.Common
		local rarityName = Style.rarityNames[def.rarity] or def.rarity
		local detail = string.format("#%d · %s", def.number, def.nationality)

		local root = new(
			"Frame",
			{ Name = "Run", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 },
			gui
		)
		local update: (() -> ())? = nil
		local connection: RBXScriptConnection? = nil

		local function finish()
			if token ~= myToken then
				return
			end
			token += 1 -- stops every timer of this run
			if connection then
				connection:Disconnect()
			end
			root:Destroy()
			current = nil
			Net.fire("AckReveal", entry.playerId)
			playNext()
		end

		if entry.short == true then
			-- The first purchase: a banner at the bottom that never catches a touch.
			local banner = new("Frame", {
				Name = "Banner",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, if reduced then -24 else 20),
				Size = UDim2.fromOffset(340, 66),
				BackgroundColor3 = color:Lerp(Style.ui.dark, 0.7),
				BackgroundTransparency = 0.1,
			}, root)
			new("UICorner", { CornerRadius = UDim.new(0, 12) }, banner)
			new("UIStroke", { Color = color, Thickness = 3 }, banner)
			label(banner, {
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 34),
				Text = string.upper(rarityName) .. " · " .. def.name,
				TextScaled = true,
				TextColor3 = color,
			})
			label(banner, {
				Position = UDim2.fromOffset(8, 38),
				Size = UDim2.new(1, -16, 0, 22),
				Text = detail,
				TextSize = 16,
			})
			if not reduced then
				TweenService:Create(
					banner,
					TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = UDim2.new(0.5, 0, 1, -24) }
				):Play()
			end
			task.delay(SHORT_SECONDS, finish)
		else
			local backdrop = new("TextButton", {
				Name = "Backdrop",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = color:Lerp(Style.ui.dark, 0.75),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
			}, root)
			fadeTo(backdrop, 0.15)

			local card = new("Frame", {
				Name = "Card",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(CARD_W, CARD_H),
				BackgroundTransparency = 1,
			}, backdrop)
			local scale = new("UIScale", {}, card)
			local camera = Workspace.CurrentCamera
			if camera then
				local size = camera.ViewportSize
				scale.Scale = math.min(1, size.X / (CARD_W + 40), size.Y / (CARD_H + 20))
			end

			-- The tag says why this is special; the rarity is always written, not only coloured.
			local tag = if entry.firstOfRarity == true
				then "FIRST " .. string.upper(rarityName)
				elseif entry.isNew then "NEW PLAYER"
				else "DUPLICATE"
			label(card, {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 34),
				Text = tag,
				TextSize = 28,
				TextColor3 = color,
			})
			label(card, {
				Position = UDim2.fromOffset(0, 36),
				Size = UDim2.new(1, 0, 0, 26),
				Text = rarityName,
				TextSize = 20,
			})
			update = buildTrick(card, def, not reduced)
			label(card, {
				Position = UDim2.fromOffset(0, 232),
				Size = UDim2.new(1, 0, 0, 34),
				Text = def.name,
				TextScaled = true,
			})
			label(card, {
				Position = UDim2.fromOffset(0, 268),
				Size = UDim2.new(1, 0, 0, 22),
				Text = detail,
				TextSize = 18,
			})
			local stars = starsText(entry)
			if stars then
				label(card, {
					Position = UDim2.fromOffset(0, 292),
					Size = UDim2.new(1, 0, 0, 24),
					Text = stars,
					TextSize = 20,
					TextColor3 = Style.ui.gold,
				})
			else
				label(card, {
					Position = UDim2.fromOffset(0, 296),
					Size = UDim2.new(1, 0, 0, 20),
					Text = "Tap to continue",
					TextSize = 14,
					TextColor3 = Style.ui.idle,
				})
			end

			backdrop.Activated:Connect(function()
				if os.clock() - startedAt > SKIP_AFTER then
					finish()
				end
			end)
			task.delay(if reduced then REDUCED_SECONDS else FULL_SECONDS, finish)
		end

		if update then
			local step = update
			connection = RunService.RenderStepped:Connect(function()
				step()
			end)
		end
	end

	playNext = function()
		if current ~= nil then
			return
		end
		local nextEntry = table.remove(queue, 1)
		if nextEntry then
			play(nextEntry)
		end
	end

	Net.on("Reveal", function(entry: any)
		if type(entry) ~= "table" or type(entry.playerId) ~= "string" then
			return
		end
		if known(entry :: Entry) then
			return
		end
		table.insert(queue, entry :: Entry)
		playNext()
	end)
end

return Reveal
