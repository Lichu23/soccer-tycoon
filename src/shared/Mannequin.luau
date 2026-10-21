--!strict
-- A player figure: a classic blocky Roblox body (R6 parts and a Humanoid that is switched off) in the
-- kit of his team. The kit is a Shirt and Pants made from the team's colours and design (KitImages, drawn
-- by tools/kits: no real crest, maker logo or sponsor), the face is a decal, the hair a Roblox catalog
-- hair (ReplicatedStorage.Avatar.Hair) in the player's hair colour, and the number is printed on the
-- chest and the surname and number on the back. Used for the capsules, the match drawing, the reveal and
-- the mini games. Every part is anchored and there are no joints: the screens pose the limbs by moving
-- the parts (see the joint positions below), so it also shows in a ViewportFrame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackPrint = require(script.Parent.BackPrint)
local Config = require(script.Parent.Config)
local KitImages = require(script.Parent.KitImages)
local Kits = require(script.Parent.Kits)
local Look = require(script.Parent.Look)
local Style = require(script.Parent.Style)

local Mannequin = {}

local INK = Color3.fromRGB(20, 24, 35)
local HEAD = 1.2 -- the head is a cube
local WHITE = Color3.new(1, 1, 1)

-- Height from the feet to the middle of the torso.
Mannequin.FEET_TO_TORSO = 3
-- The joints, from the middle of the torso (the right side; the left is the mirror in X), and how far
-- the middle of the limb hangs below its joint.
Mannequin.SHOULDER = Vector3.new(1.5, 0.5, 0)
Mannequin.ARM_REACH = 0.5
Mannequin.HIP = Vector3.new(0.5, -1, 0)
Mannequin.LEG_REACH = 1

-- The catalog hair of each hair style of Look; "buzz" is a thin cap of parts and "bald" has none.
local HAIR_MODELS: { [string]: string } = {
	short = "SpikedHair",
	tall = "CharmerHair",
	long = "PalHair",
	mohawk = "DownToEarthHair",
}

export type Options = {
	locked: boolean?, -- a player the owner does not have yet: the colours are washed out
}

local LOCKED_GREY = Color3.fromRGB(105, 110, 125)
local LOCKED_BLEND = 0.7

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

local function brightness(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- Dark text on a light shirt, white text on a dark one.
local function textColor(shirt: Color3): Color3
	return if brightness(shirt) > 0.55 then INK else Color3.fromRGB(255, 255, 255)
end

local function decal(parent: Instance, name: string, texture: string?, color: Color3)
	if texture == nil then
		return
	end
	local face = Instance.new("Decal")
	face.Name = name
	face.Face = Enum.NormalId.Front
	face.Texture = texture
	face.Color3 = color
	face.Parent = parent
end

-- The hair on top of `head`: the catalog hair of the style, its texture taken off so it shows the
-- player's hair colour.
local function addHair(model: Model, head: BasePart, style: string, color: Color3)
	local top = head.Position.Y + HEAD / 2
	if style == "buzz" then
		part(
			model,
			"Hair",
			Vector3.new(HEAD + 0.04, 0.12, HEAD + 0.04),
			Vector3.new(0, top, 0),
			color
		)
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("Avatar")
	local hair = if folder then folder:FindFirstChild("Hair") else nil
	local name = HAIR_MODELS[style]
	local source = if hair and name then hair:FindFirstChild(name) else nil
	if source == nil or not source:IsA("Accessory") then
		return
	end
	local accessory = source:Clone()
	local handle = accessory:FindFirstChild("Handle")
	local attachment = if handle then handle:FindFirstChildWhichIsA("Attachment") else nil
	if handle == nil or not handle:IsA("BasePart") or attachment == nil then
		accessory:Destroy()
		return
	end
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Color = color
	if handle:IsA("MeshPart") then
		handle.TextureID = ""
	end
	-- The hair attachment of a head sits in the middle of its top.
	handle.CFrame = CFrame.new(0, top, 0) * attachment.CFrame:Inverse()
	accessory.Parent = model
end

-- `kit` dresses the player in the plain kit of that colour instead of his team's (the owner's chosen
-- kit, the rival team, the keeper). With `label`, the player's name floats above the head.
function Mannequin.build(
	def: Config.PlayerDef,
	kit: Color3?,
	label: boolean,
	options: Options?
): Model
	local locked = options ~= nil and options.locked == true
	local look = Look.of(def.id)
	local function tone(color: Color3): Color3
		return if locked then color:Lerp(LOCKED_GREY, LOCKED_BLEND) else color
	end
	local team = if kit == nil then Kits.teamOf[def.id] else nil
	local teamKit = if team then Kits.teams[team] else nil
	local teamShirt = if team then KitImages.shirts[team] else nil
	-- The colour the shirt reads as: the team's shirt, or the plain kit's tint.
	local shirtColor = kit
		or (if teamKit then rgb(teamKit.shirt) else nil)
		or Style.rarityColors[def.rarity]
		or Style.rarityColors.Common
	-- A team image is drawn in its own colours (white tint); the plain kit is tinted.
	local shirtImage: string = teamShirt or KitImages.plainShirt
	local pantsImage: string = if teamShirt and team
		then KitImages.pants[team] or KitImages.plainPants
		else KitImages.plainPants
	local shirtTint = if teamShirt then WHITE else shirtColor
	local skin = tone(rgb(look.skin))
	local hair = tone(rgb(look.hairColor))

	local model = Instance.new("Model")
	model.Name = "Mannequin_" .. def.id
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), Vector3.zero, tone(shirtColor))
	local head =
		part(model, "Head", Vector3.new(HEAD, HEAD, HEAD), Vector3.new(0, 1 + HEAD / 2, 0), skin)
	local shoulder, hip = Mannequin.SHOULDER, Mannequin.HIP
	for _, side in { { name = "Right", x = 1 }, { name = "Left", x = -1 } } do
		part(
			model,
			side.name .. " Arm",
			Vector3.new(1, 2, 1),
			Vector3.new(side.x * shoulder.X, shoulder.Y - Mannequin.ARM_REACH, 0),
			skin
		)
		part(
			model,
			side.name .. " Leg",
			Vector3.new(1, 2, 1),
			Vector3.new(side.x * hip.X, hip.Y - Mannequin.LEG_REACH, 0),
			skin
		)
	end
	decal(head, "face", KitImages.faces[look.face], tone(WHITE))
	decal(head, "Brows", KitImages.brows[look.brows], hair)
	addHair(model, head, look.hair, hair)

	-- The Humanoid only carries the clothing: no physics, no states, no name over the head.
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = shirtImage
	shirt.Color3 = tone(shirtTint)
	shirt.Parent = model
	local pants = Instance.new("Pants")
	pants.PantsTemplate = pantsImage
	pants.Color3 = tone(WHITE)
	pants.Parent = model
	model.PrimaryPart = torso

	-- The print: the number on the chest (the -Z side) and the surname and number on the back (+Z).
	local ink = textColor(shirtColor)
	local function printOn(face: Enum.NormalId, withName: boolean)
		-- An invisible plate just in front of the shirt carries the print.
		local z = if face == Enum.NormalId.Back then 0.52 else -0.52
		local plate = part(
			model,
			"Plate" .. face.Name,
			Vector3.new(2, 2, 0.02),
			Vector3.new(0, 0, z),
			shirtColor
		)
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
			surname.Position = UDim2.fromScale(0.04, 0.08)
			surname.Size = UDim2.fromScale(0.92, 0.2)
			surname.Text = BackPrint.surname(def.name)
			surname.TextColor3 = ink
			surname.Font = Style.font
			surname.TextScaled = true
			surname.Parent = gui
		end
		local number = Instance.new("TextLabel")
		number.Name = "Number"
		number.BackgroundTransparency = 1
		-- On the chest the number sits under the collar and the badge.
		number.Position = if withName then UDim2.fromScale(0, 0.3) else UDim2.fromScale(0.3, 0.42)
		number.Size = if withName then UDim2.fromScale(1, 0.62) else UDim2.fromScale(0.4, 0.4)
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
