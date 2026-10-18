--!strict
-- A simple blocky player figure built from anchored parts (no Humanoid, no uploaded assets, no
-- faces or badges). Used for the capsules and the match drawing. Kit colour follows the rarity.

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

-- `kit` overrides the shirt colour (for example the rival kit of the opponents). With `label`,
-- the player's name floats above the head.
function Mannequin.build(def: Config.PlayerDef, kit: Color3?, label: boolean): Model
	local shirt = kit or Style.rarityColors[def.rarity] or Style.rarityColors.Common
	local shorts = Color3.fromRGB(35, 40, 60)
	local model = Instance.new("Model")
	model.Name = "Mannequin_" .. def.id

	local torso = part(model, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), shirt)
	part(model, "Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.7, 0), SKIN, true)
	part(model, "LeftLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0), shorts)
	part(model, "RightLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0), shorts)
	part(model, "LeftArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-1.4, 0.1, 0), SKIN)
	part(model, "RightArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.4, 0.1, 0), SKIN)
	model.PrimaryPart = torso

	-- Shirt number on the back (the +Z side faces away from the front, which looks along -Z).
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = torso
	local number = Instance.new("TextLabel")
	number.BackgroundTransparency = 1
	number.Size = UDim2.fromScale(1, 1)
	number.Text = tostring(def.number)
	number.TextColor3 = Color3.fromRGB(20, 24, 35)
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
