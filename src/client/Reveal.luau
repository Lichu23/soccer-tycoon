--!strict
-- The rarity reveal (docs/PLAN.md, Step 7): the first player of each rarity and every case win. It
-- opens on a bright screen in the rarity colour with turning light rays and the rarity name, then cuts
-- to the keepie-uppy stadium (client/KeepieScene) where the footballer just won, in his own kit, keeps
-- a ball up, with his name, number and nationality over bands of the rarity colour. About 5 seconds, a
-- tap skips it. The very first purchase gets a short banner instead that does not catch touches, so
-- the player can keep walking. Only slow fades, no flashes. With reduced motion the rays stand still,
-- the player stands with the ball at his feet and it is shorter. A Robux case holds its reveal until
-- its roulette has landed (Reveal.hold, client/CaseModal). The server already granted the player:
-- this only shows it, then tells the server it was seen (AckReveal) so it is not replayed after a
-- rejoin.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CinemaScreen = require(script.Parent.CinemaScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Juggle = require(ReplicatedStorage.Shared.Juggle)
local KeepieScene = require(script.Parent.KeepieScene)
local Net = require(script.Parent.Net)
local Sounds = require(script.Parent.Sounds)
local Style = require(ReplicatedStorage.Shared.Style)

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local INTRO_SECONDS = 1.3 -- the rarity screen before the stadium
local SCENE_SECONDS = 3.6
local REDUCED_INTRO_SECONDS = 0.8
local REDUCED_SCENE_SECONDS = 2
local SHORT_SECONDS = 2
local SKIP_AFTER = 0.6 -- a skip tap is ignored right after the start (a leftover tap)
local FADE = 0.35
local RAY_COUNT = 8 -- each ray crosses the middle, so twice as many beams show
local RAY_WIDTH = 0.07 -- of the screen's longer side
local RAY_TURN = 0.25 -- radians a second
local KICK_UP_AFTER = 0.3 -- the first ball leaves the foot this long after the cut to the stadium
local HOLD_TIMEOUT = 20 -- a hold always ends, even if the roulette never lands

type Entry = {
	playerId: string,
	isNew: boolean,
	firstOfRarity: boolean?,
	short: boolean?,
	starsGained: number?,
	stars: number?,
}

local Reveal = {}

-- The hold of a Robux case: the reveal waits in the queue until the roulette has landed.
local held = false
local holdToken = 0
local resume: () -> () = function() end

function Reveal.hold()
	held = true
	holdToken += 1
	local myToken = holdToken
	task.delay(HOLD_TIMEOUT, function()
		if held and holdToken == myToken then
			Reveal.release()
		end
	end)
end

function Reveal.release()
	if held then
		held = false
		resume()
	end
end

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

-- A band of the rarity colour along the top or the bottom of the screen, fading out towards the
-- middle, so the colour frames the stadium without hiding the player. A rarity with lines gets one
-- along the screen's edge.
local function band(parent: Instance, color: Color3, atTop: boolean, height: number, trim: Color3?)
	local frame = new("Frame", {
		Name = if atTop then "TopBand" else "BottomBand",
		AnchorPoint = Vector2.new(0, if atTop then 0 else 1),
		Position = UDim2.fromScale(0, if atTop then 0 else 1),
		Size = UDim2.fromScale(1, height),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	new("UIGradient", {
		Rotation = 90, -- top to bottom
		Transparency = if atTop
			then NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.55, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			else NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.35),
				NumberSequenceKeypoint.new(1, 0.05),
			}),
	}, frame)
	if trim then
		new("Frame", {
			Name = "Trim",
			AnchorPoint = Vector2.new(0, if atTop then 0 else 1),
			Position = UDim2.new(0, 0, if atTop then 0 else 1, if atTop then 6 else -6),
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = trim,
			BorderSizePixel = 0,
		}, parent)
	end
end

-- The rarity name on a chip of its colour with the dark outline of the game's chips (and a line
-- inside it for a rarity with lines).
local function chip(parent: Instance, color: Color3, text: string, y: number, trim: Color3?)
	local frame = new("Frame", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	new("UIStroke", {
		Color = Style.ui.dark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, frame)
	if trim then
		local line = new("Frame", {
			Name = "Trim",
			-- 3px inside the chip's edge; the offsets undo the chip's 16px side padding.
			Position = UDim2.fromOffset(-13, 3),
			Size = UDim2.new(1, 26, 1, -6),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, frame)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, line)
		new("UIStroke", {
			Color = trim,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, line)
	end
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, frame)
	new("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = string.upper(text),
		Font = Style.font,
		TextSize = 22,
		TextColor3 = Style.ui.dark,
	}, frame)
end

-- The opening screen: a bright gradient of the rarity colour with light rays turning out of the
-- middle, the tag and the rarity name popping in. Returns the group (to fade out) and the frame step.
local function buildBurst(
	parent: Instance,
	color: Color3,
	tag: string,
	rarityName: string,
	reduced: boolean,
	trim: Color3?
): (CanvasGroup, (seconds: number) -> ())
	local group = new("CanvasGroup", {
		Name = "Burst",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, parent)
	-- The gradient sits on its own fill: on the group it would tint the rays and the words too.
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, group)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.45)),
			ColorSequenceKeypoint.new(0.5, color),
			-- A rarity with lines shades into them (a Legend from white into gold).
			ColorSequenceKeypoint.new(1, if trim then trim else color:Lerp(Style.ui.dark, 0.3)),
		}),
	}, fill)
	local rays: { Frame } = {}
	for index = 1, RAY_COUNT do
		local ray = new("Frame", {
			Name = "Ray" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			Size = UDim2.fromScale(RAY_WIDTH, 2.4),
			BackgroundColor3 = trim or WHITE, -- white rays would vanish on a white Legend

			BorderSizePixel = 0,
		}, group)
		-- Bright in the middle, gone at the ends.
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(rays, ray)
	end
	local words = new("Frame", {
		Name = "Words",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 150),
		BackgroundTransparency = 1,
	}, group)
	new("UISizeConstraint", { MaxSize = Vector2.new(560, 150) }, words)
	local pop = new("UIScale", { Scale = if reduced then 1 else 0.5 }, words)
	label(words, {
		Size = UDim2.new(1, 0, 0, 40),
		Text = tag,
		TextSize = 32,
	})
	local big = label(words, {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 96),
		Text = string.upper(rarityName),
		TextScaled = true,
	})
	local stroke = big:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	if not reduced then
		TweenService:Create(
			pop,
			TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
	local function step(seconds: number)
		local turn = if reduced then 0 else math.deg(seconds * RAY_TURN)
		for index, ray in rays do
			ray.Rotation = turn + (index - 1) * 180 / RAY_COUNT
		end
	end
	step(0)
	return group, step
end

-- The full reveal under `root`: the burst, then the stadium with the footballer juggling and his
-- details. `skip` is called on a tap. Returns what puts everything back (the camera, the scene).
local function buildFull(
	root: Frame,
	entry: Entry,
	def: Config.PlayerDef,
	reduced: boolean,
	skip: () -> ()
): () -> ()
	local color = Style.rarityColors[def.rarity] or Style.rarityColors.Common
	local trim = Style.rarityTrim[def.rarity]
	local rarityName = Style.rarityNames[def.rarity] or def.rarity
	-- The tag says why this is special, over the rarity (always written, not only coloured).
	local tag = if entry.firstOfRarity == true
		then "YOUR FIRST"
		elseif entry.isNew then "NEW PLAYER"
		else "DUPLICATE"

	local catcher = new("TextButton", {
		Name = "Skip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
	}, root)
	catcher.Activated:Connect(skip)

	-- Over the stadium: the rarity bands, the tag and the chip at the top, the name at the bottom.
	local overlay = new("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, root)
	band(overlay, color, true, 0.24, trim)
	band(overlay, color, false, 0.36, trim)
	label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.new(1, -32, 0, 34),
		Text = tag,
		TextSize = 28,
	})
	chip(overlay, color, rarityName, 58, trim)
	local bottom = new("Frame", {
		Name = "Details",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -32, 0, 112),
		BackgroundTransparency = 1,
	}, overlay)
	local name = label(bottom, {
		Size = UDim2.new(1, 0, 0, 48),
		Text = def.name,
		TextScaled = true,
	})
	new("UITextSizeConstraint", { MaxTextSize = 44 }, name)
	label(bottom, {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 24),
		Text = string.format("#%d · %s", def.number, def.nationality),
		TextSize = 20,
	})
	local stars = starsText(entry)
	label(bottom, {
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 26),
		Text = stars or "Tap to continue",
		TextSize = if stars then 22 else 15,
		TextColor3 = if stars then Style.ui.gold else WHITE,
	})

	local burst, burstStep = buildBurst(root, color, tag, rarityName, reduced, trim)
	Sounds.play(if def.rarity == "Epic" or def.rarity == "Legend" then "revealBig" else "reveal")
	local scene = KeepieScene.new(def)
	local takeover = CinemaScreen.takeover()
	local inScene = false
	local startedAt = os.clock()
	local round: Juggle.State = {
		phase = "running",
		startedAt = math.huge, -- set at the cut to the stadium
		lastIndex = 0,
		combo = 0, -- stays 0: the camera holds still instead of creeping in with a streak
		overAt = 0,
	}

	local connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if burst.Parent then
			burstStep(now - startedAt)
		end
		if not inScene then
			return
		end
		takeover.keep()
		if now > round.startedAt then
			round.lastIndex = Juggle.beatAt(round, now) - 1 -- every touch is clean
		end
		scene.frame({ round = round, now = now })
	end)

	-- The cut: the camera goes to the stadium and the rarity screen fades away over it.
	task.delay(if reduced then REDUCED_INTRO_SECONDS else INTRO_SECONDS, function()
		if not root.Parent then
			return
		end
		inScene = true
		takeover.take()
		-- With reduced motion the ball stays at his feet (the kick-up never comes).
		round.startedAt = if reduced then math.huge else os.clock() + KICK_UP_AFTER
		scene.frame({ round = round, now = os.clock() })
		overlay.Visible = true
		local fade = TweenService:Create(burst, TweenInfo.new(FADE), { GroupTransparency = 1 })
		fade.Completed:Connect(function()
			burst:Destroy()
		end)
		fade:Play()
	end)

	return function()
		connection:Disconnect()
		scene.destroy()
		if inScene then
			takeover.give()
		end
	end
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
		local trim = Style.rarityTrim[def.rarity]
		local rarityName = Style.rarityNames[def.rarity] or def.rarity
		local detail = string.format("#%d · %s", def.number, def.nationality)

		local root = new(
			"Frame",
			{ Name = "Run", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 },
			gui
		)
		local cleanup: (() -> ())? = nil

		local function finish()
			if token ~= myToken then
				return
			end
			token += 1 -- stops every timer of this run
			if cleanup then
				cleanup()
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
			new("UIStroke", { Color = trim or color, Thickness = 3 }, banner)
			label(banner, {
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 34),
				Text = string.upper(rarityName) .. " · " .. def.name,
				TextScaled = true,
				TextColor3 = trim or color,
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
			cleanup = buildFull(root, entry, def, reduced, function()
				if os.clock() - startedAt > SKIP_AFTER then
					finish()
				end
			end)
			task.delay(
				if reduced
					then REDUCED_INTRO_SECONDS + REDUCED_SCENE_SECONDS
					else INTRO_SECONDS + SCENE_SECONDS,
				finish
			)
		end
	end

	playNext = function()
		if current ~= nil or held then
			return
		end
		local nextEntry = table.remove(queue, 1)
		if nextEntry then
			play(nextEntry)
		end
	end

	resume = playNext

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
