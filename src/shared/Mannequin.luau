--!strict
-- A blocky player figure built from anchored parts (no Humanoid, no uploaded assets, no logos): a
-- face, hair, a skin tone, a kit with a pattern, the number on the chest and the surname and number on
-- the back. Used for the capsules, the match drawing and the reveal. Everything is made of parts, so it
-- also shows in a ViewportFrame; only the printed text uses SurfaceGuis. Kit colour follows the rarity.

local BackPrint = require(script.Parent.BackPrint)
local Config = require(script.Parent.Config)
local Kits = require(script.Parent.Kits)
local Look = require(script.Parent.Look)
local Style = require(script.Parent.Style)

local Mannequin = {}

local INK = Color3.fromRGB(20, 24, 35)

local function part(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

-- Height from the feet to the middle of the torso.
Mannequin.FEET_TO_TORSO = 3

export type Options = {
	detailed: boolean?, -- short sleeves, socks and boots (a still figure: the limbs are no longer one piece)
	locked: boolean?, -- a player the owner does not have yet: the colours are washed out
}

local LOCKED_GREY = Color3.fromRGB(105, 110, 125)
local LOCKED_BLEND = 0.7

local function brightness(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- Dark text on a light shirt, white text on a dark one.
local function textColor(shirt: Color3): Color3
	return if brightness(shirt) > 0.55 then INK else Color3.fromRGB(255, 255, 255)
end

-- The hair: a few blocks on and behind the head (the head is a 1.3 cube centred at y 1.7).
local function addHair(model: Model, style: string, color: Color3)
	if style == "bald" then
		return
	end
	local top = 1.7 + 0.65
	if style == "buzz" then
		part(model, "Hair", Vector3.new(1.36, 0.14, 1.36), Vector3.new(0, top + 0.05, 0), color)
	elseif style == "short" then
		part(model, "Hair", Vector3.new(1.4, 0.3, 1.4), Vector3.new(0, top + 0.1, 0), color)
		part(model, "HairBack", Vector3.new(1.4, 0.7, 0.3), Vector3.new(0, top - 0.3, 0.6), color)
	elseif style == "tall" then
		part(model, "Hair", Vector3.new(1.6, 0.75, 1.6), Vector3.new(0, top + 0.3, 0.05), color)
	elseif style == "long" then
		part(model, "Hair", Vector3.new(1.4, 0.3, 1.4), Vector3.new(0, top + 0.1, 0), color)
		part(model, "HairBack", Vector3.new(1.4, 1.5, 0.3), Vector3.new(0, top - 0.7, 0.6), color)
		part(
			model,
			"HairSide",
			Vector3.new(0.25, 0.9, 1.0),
			Vector3.new(-0.72, top - 0.45, 0.1),
			color
		)
		part(
			model,
			"HairSide",
			Vector3.new(0.25, 0.9, 1.0),
			Vector3.new(0.72, top - 0.45, 0.1),
			color
		)
	elseif style == "mohawk" then
		part(model, "Hair", Vector3.new(0.32, 0.6, 1.2), Vector3.new(0, top + 0.2, 0.05), color)
	end
end

-- The face on the front of the head (the -Z side): eyes with a white and a pupil, brows and a mouth,
-- as thin parts. The mouth is a shade of the skin, so it shows on every skin tone.
local function addFace(model: Model, hairColor: Color3, skin: Color3)
	local z = -0.65 - 0.02
	for _, side in { -1, 1 } do
		part(
			model,
			"EyeWhite",
			Vector3.new(0.26, 0.22, 0.04),
			Vector3.new(side * 0.28, 1.75, z),
			Color3.fromRGB(245, 245, 245)
		)
		part(
			model,
			"Eye",
			Vector3.new(0.12, 0.18, 0.04),
			Vector3.new(side * 0.28, 1.75, z - 0.03),
			INK
		)
		part(
			model,
			"Brow",
			Vector3.new(0.3, 0.07, 0.04),
			Vector3.new(side * 0.28, 1.99, z),
			hairColor
		)
	end
	local mouth = if brightness(skin) < 0.35
		then skin:Lerp(Color3.new(1, 1, 1), 0.5)
		else skin:Lerp(Color3.new(0, 0, 0), 0.5)
	part(model, "Mouth", Vector3.new(0.38, 0.08, 0.04), Vector3.new(0, 1.4, z), mouth)
end

-- The pattern of the kit as flat bars through the torso: stripes at the sides, a band at the hem, or
-- one darker half. The middle stays the shirt colour for the print.
local function addPattern(model: Model, pattern: string, color: Color3)
	if pattern == "stripes" then
		for _, x in { -0.7, 0.7 } do
			part(model, "Stripe", Vector3.new(0.4, 1.98, 1.04), Vector3.new(x, 0, 0), color)
		end
	elseif pattern == "hem" then
		part(model, "Hem", Vector3.new(2.04, 0.24, 1.04), Vector3.new(0, -0.88, 0), color)
	elseif pattern == "half" then
		part(model, "Half", Vector3.new(0.98, 1.98, 1.04), Vector3.new(-0.5, 0, 0), color)
	end
end

-- `kit` overrides the shirt colour (for example the rival kit of the opponents). With `label`,
-- the player's name floats above the head. The number is printed on the chest, the surname and the
-- number on the back.
function Mannequin.build(
	def: Config.PlayerDef,
	kit: Color3?,
	label: boolean,
	options: Options?
): Model
	local detailed = options ~= nil and options.detailed == true
	local locked = options ~= nil and options.locked == true
	local look = Look.of(def.id)
	local function tone(color: Color3): Color3
		return if locked then color:Lerp(LOCKED_GREY, LOCKED_BLEND) else color
	end
	-- With no kit given the player wears the colours of his team (Kits); a kit given (the owner's chosen
	-- kit, the rival team) overrides the shirt only. Without a team the shirt follows the rarity.
	local team = if kit == nil then Kits.of(def.id) else nil
	local shirt = tone(
		kit
			or (if team then rgb(team.shirt) else nil)
			or Style.rarityColors[def.rarity]
			or Style.rarityColors.Common
	)
	local trim = if team
		then tone(rgb(team.trim))
		elseif brightness(shirt) > 0.55 then shirt:Lerp(Color3.new(0, 0, 0), 0.25)
		else shirt:Lerp(Color3.new(1, 1, 1), 0.3)
	local pattern = if team then team.pattern else look.pattern
	local shorts = tone(if team then rgb(team.shorts) else Color3.fromRGB(35, 40, 60))
	local skin = tone(rgb(look.skin))
	local hair = tone(rgb(look.hairColor))
	local socks = if team
		then tone(rgb(team.socks))
		else shirt:Lerp(Color3.fromRGB(255, 255, 255), 0.25)
	local boots = tone(Color3.fromRGB(25, 25, 30))
	local model = Instance.new("Model")
	model.Name = "Mannequin_" .. def.id

	local torso = part(model, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), shirt)
	part(model, "Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.7, 0), skin)
	addFace(model, hair, skin)
	addHair(model, look.hair, hair)
	addPattern(model, pattern, trim)
	if detailed then
		for _, side in { { name = "Left", x = -1 }, { name = "Right", x = 1 } } do
			part(
				model,
				side.name .. "Shorts",
				Vector3.new(0.9, 0.9, 0.9),
				Vector3.new(side.x * 0.5, -1.45, 0),
				shorts
			)
			part(
				model,
				side.name .. "Sock",
				Vector3.new(0.9, 0.8, 0.9),
				Vector3.new(side.x * 0.5, -2.3, 0),
				socks
			)
			part(
				model,
				side.name .. "Boot",
				Vector3.new(0.9, 0.3, 1.1),
				Vector3.new(side.x * 0.5, -2.85, -0.1),
				boots
			)
			part(
				model,
				side.name .. "Sleeve",
				Vector3.new(0.8, 0.8, 0.8),
				Vector3.new(side.x * 1.4, 0.6, 0),
				shirt
			)
			part(
				model,
				side.name .. "Forearm",
				Vector3.new(0.8, 1, 0.8),
				Vector3.new(side.x * 1.4, -0.3, 0),
				skin
			)
		end
	else
		part(model, "LeftLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0), shorts)
		part(model, "RightLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0), shorts)
		part(model, "LeftArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-1.4, 0.1, 0), skin)
		part(model, "RightArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.4, 0.1, 0), skin)
		-- Short sleeves over the top of the arms, so the shoulders are covered by the shirt.
		part(model, "LeftSleeve", Vector3.new(0.9, 0.85, 0.9), Vector3.new(-1.4, 0.55, 0), shirt)
		part(model, "RightSleeve", Vector3.new(0.9, 0.85, 0.9), Vector3.new(1.4, 0.55, 0), shirt)
	end
	model.PrimaryPart = torso

	-- The print: the number on the chest (the -Z side) and the surname and number on the back (+Z).
	local ink = textColor(shirt)
	local function printOn(face: Enum.NormalId, withName: boolean)
		-- An invisible plate just in front of the pattern bars carries the print.
		local z = if face == Enum.NormalId.Back then 0.56 else -0.56
		local plate =
			part(model, "Plate" .. face.Name, Vector3.new(2, 2, 0.02), Vector3.new(0, 0, z), shirt)
		plate.Transparency = 1
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Print" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = plate
		if withName then
			local surname = Instance.new("TextLabel")
			surname.Name = "Surname"
			surname.BackgroundTransparency = 1
			surname.Position = UDim2.fromScale(0.04, 0.05)
			surname.Size = UDim2.fromScale(0.92, 0.22)
			surname.Text = BackPrint.surname(def.name)
			surname.TextColor3 = ink
			surname.Font = Style.font
			surname.TextScaled = true
			surname.Parent = gui
		end
		local number = Instance.new("TextLabel")
		number.Name = "Number"
		number.BackgroundTransparency = 1
		number.Position = if withName then UDim2.fromScale(0, 0.28) else UDim2.fromScale(0.2, 0.18)
		number.Size = if withName then UDim2.fromScale(1, 0.68) else UDim2.fromScale(0.6, 0.5)
		number.Text = tostring(def.number)
		number.TextColor3 = ink
		number.Font = Style.font
		number.TextScaled = true
		number.Parent = gui
	end
	printOn(Enum.NormalId.Back, true)
	printOn(Enum.NormalId.Front, false)

	if label then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "NameLabel"
		billboard.Size = UDim2.fromOffset(170, 26)
		billboard.StudsOffset = Vector3.new(0, 3.3, 0)
		billboard.MaxDistance = 90
		billboard.AlwaysOnTop = false
		billboard.Adornee = torso
		billboard.Parent = model
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = def.name
		text.TextColor3 = Style.ui.text
		text.TextStrokeTransparency = 0.4
		text.Font = Style.font
		text.TextSize = 16
		text.Parent = billboard
	end
	return model
end

return Mannequin
