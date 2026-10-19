--!strict
-- A simple blocky player figure built from anchored parts (no Humanoid, no uploaded assets, no
-- faces or badges). Used for the capsules and the match drawing. Kit colour follows the rarity.

local BackPrint = require(script.Parent.BackPrint)
local Config = require(script.Parent.Config)
local Style = require(script.Parent.Style)

local Mannequin = {}

local SKIN = Color3.fromRGB(235, 190, 150)

local function part(
	model: Model,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	ball: boolean?
): Part
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
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

-- Height from the feet to the middle of the torso.
Mannequin.FEET_TO_TORSO = 3

export type Options = {
	detailed: boolean?, -- short sleeves, socks and boots (a still figure: the limbs are no longer one piece)
	locked: boolean?, -- a player the owner does not have yet: the colours are washed out
}

local LOCKED_GREY = Color3.fromRGB(105, 110, 125)
local LOCKED_BLEND = 0.7

-- Dark text on a light shirt, white text on a dark one.
local function textColor(shirt: Color3): Color3
	local brightness = 0.299 * shirt.R + 0.587 * shirt.G + 0.114 * shirt.B
	return if brightness > 0.55 then Color3.fromRGB(20, 24, 35) else Color3.fromRGB(255, 255, 255)
end

-- `kit` overrides the shirt colour (for example the rival kit of the opponents). With `label`,
-- the player's name floats above the head. The surname and the number are always printed on the back.
function Mannequin.build(
	def: Config.PlayerDef,
	kit: Color3?,
	label: boolean,
	options: Options?
): Model
	local detailed = options ~= nil and options.detailed == true
	local locked = options ~= nil and options.locked == true
	local function tone(color: Color3): Color3
		return if locked then color:Lerp(LOCKED_GREY, LOCKED_BLEND) else color
	end
	local shirt = tone(kit or Style.rarityColors[def.rarity] or Style.rarityColors.Common)
	local shorts = tone(Color3.fromRGB(35, 40, 60))
	local skin = tone(SKIN)
	local socks = shirt:Lerp(Color3.fromRGB(255, 255, 255), 0.25)
	local boots = tone(Color3.fromRGB(25, 25, 30))
	local model = Instance.new("Model")
	model.Name = "Mannequin_" .. def.id

	local torso = part(model, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), shirt)
	part(model, "Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.7, 0), skin, true)
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
	end
	model.PrimaryPart = torso

	-- The surname and the number on the back (the +Z side faces away from the front, which looks
	-- along -Z), like a real shirt: the name above, the number big below.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = torso
	local ink = textColor(shirt)
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
	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.BackgroundTransparency = 1
	number.Position = UDim2.fromScale(0, 0.28)
	number.Size = UDim2.fromScale(1, 0.68)
	number.Text = tostring(def.number)
	number.TextColor3 = ink
	number.Font = Style.font
	number.TextScaled = true
	number.Parent = gui

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
