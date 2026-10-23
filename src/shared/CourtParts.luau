--!strict
-- Turns CourtPlan's plain part list into parts (docs/PLAN.md, Step 7). The server builds every plot's
-- pitch with it (server/Stadium), and the Locker room rebuilds the floodlights of its copy of the
-- stadium with it to preview another model (client/LockerView).

local CourtPlan = require(script.Parent.CourtPlan)
local StadiumLook = require(script.Parent.StadiumLook)

local LAMP_INDEX = 10_000 -- the floodlights are numbered after every other part of the plan

local CourtParts = {}

-- The materials CourtPlan names.
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Wood = Enum.Material.Wood,
	Neon = Enum.Material.Neon,
	Concrete = Enum.Material.Concrete,
	Metal = Enum.Material.Metal,
}

-- The face of a part its text is drawn on (the default is the one towards the court, -x).
local FACES: { [string]: Enum.NormalId } = {
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
	Front = Enum.NormalId.Front,
}

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- The part names a Locker room slot paints; they carry their place in the plan (StadiumLook).
local PAINTED: { [string]: boolean } = {}
for _, names in StadiumLook.PARTS do
	for name in names do
		PAINTED[name] = true
	end
end

-- Builds one part of the plan under `parent`, placed from the plot's `gate`; `index` is its place in
-- the plan (painted parts keep it, StadiumLook).
function CourtParts.build(gate: BasePart, spec: CourtPlan.PartSpec, parent: Instance, index: number)
	local part: BasePart = if spec.shape == "wedge"
		then Instance.new("WedgePart")
		else Instance.new("Part")
	part.Name = spec.name
	if PAINTED[spec.name] then
		part:SetAttribute("PlanIndex", index)
	end
	if spec.lamp then
		part:SetAttribute("Lamp", true)
	end
	part.Anchored = true
	part.CanCollide = false -- the pitch is for looking at; nobody gets stuck in a wall
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = not spec.emitter
	part.Color = toColor(spec.color)
	part.Material = MATERIALS[spec.material] or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local sx, sy, sz = spec.x1 - spec.x0, spec.y1 - spec.y0, spec.z1 - spec.z0
	local center =
		Vector3.new((spec.x0 + spec.x1) / 2, (spec.y0 + spec.y1) / 2 - 1, (spec.z0 + spec.z1) / 2)
	-- The gate sits 1 stud above the ground reference, at the middle of the plot front.
	local turn = CFrame.Angles(0, math.rad(spec.yaw or 0), 0)
		* CFrame.Angles(math.rad(spec.tilt or 0), 0, 0)
	if spec.cylinder and part:IsA("Part") then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(sy, sx, sz)
		part.CFrame = gate.CFrame * CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	elseif spec.shape == "disc" and part:IsA("Part") then
		-- A cylinder lies along its x; turned a quarter, its round face looks to the part's front.
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(sz, sy, sx)
		part.CFrame = gate.CFrame * CFrame.new(center) * turn * CFrame.Angles(0, math.pi / 2, 0)
	else
		part.Size = Vector3.new(sx, sy, sz)
		part.CFrame = gate.CFrame * CFrame.new(center) * turn
	end
	local slide = spec.slide
	if slide then
		part:SetAttribute(
			"Slide",
			gate.CFrame:VectorToWorldSpace(Vector3.new(slide[1], slide[2], slide[3]))
		)
	end

	if spec.text then
		local gui = Instance.new("SurfaceGui")
		gui.Face = FACES[spec.face or "Left"] or Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = spec.text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		local textColor = spec.textColor or { 255, 220, 60 }
		label.TextColor3 = toColor(textColor)
		label.Parent = gui
		part:SetAttribute("BaseText", spec.text) -- a scoreboard design redraws its own text
	end
	if spec.image then
		local gui = Instance.new("SurfaceGui")
		gui.Face = FACES[spec.face or "Left"] or Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = part
		local picture = Instance.new("ImageLabel")
		picture.Size = UDim2.fromScale(1, 1)
		picture.BackgroundTransparency = 1
		picture.ScaleType = Enum.ScaleType.Fit
		picture.Image = spec.image
		picture.Parent = gui
	end
	if spec.emitter then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Firework"
		emitter.Enabled = false
		emitter.Rate = 40
		emitter.Lifetime = NumberRange.new(1.2, 2)
		emitter.Speed = NumberRange.new(30, 45)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Acceleration = Vector3.new(0, -25, 0)
		emitter.Size = NumberSequence.new(0.8, 0)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 90, 90))
		emitter.LightEmission = 1
		emitter.Parent = part
	end
	part.Parent = parent
end

-- Replaces the floodlights of `court` (tier `tier`) with `model`, and records the model on the court.
function CourtParts.setLamps(court: Instance, gate: BasePart, tier: number, model: string)
	for _, child in court:GetChildren() do
		if child:GetAttribute("Lamp") == true then
			child:Destroy()
		end
	end
	for index, spec in CourtPlan.lamps(tier, model) do
		CourtParts.build(gate, spec, court, LAMP_INDEX + index)
	end
	court:SetAttribute("Lamps", model)
end

return CourtParts
