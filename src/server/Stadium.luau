--!strict
-- Builds the pitch of a plot for its stadium tier (docs/PLAN.md, Step 7) from CourtPlan, and runs
-- the server side of an upgrade: tell the player's client to play the cinematic, build the new
-- pitch once the camera has arrived, and let the fireworks go off at tier 5. The server finishes
-- the upgrade even if the player leaves or skips; the cinematic only affects that client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local StadiumLogic = require(script.Parent.StadiumLogic)

local FIREWORK_SECONDS = 4

local Stadium = {}

-- The materials CourtPlan names.
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Wood = Enum.Material.Wood,
	Neon = Enum.Material.Neon,
}

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function buildPart(gate: BasePart, spec: CourtPlan.PartSpec, parent: Instance)
	local part = Instance.new("Part")
	part.Name = spec.name
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
	if spec.cylinder then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(sy, sx, sz)
		part.CFrame = gate.CFrame * CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	else
		part.Size = Vector3.new(sx, sy, sz)
		part.CFrame = gate.CFrame * CFrame.new(center)
	end

	if spec.text then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Left -- towards the court (-x)
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = spec.text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 220, 60)
		label.Parent = gui
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

-- Replaces the pitch of `plot` with the one of `tier`.
function Stadium.build(plot: Model, tier: number)
	local gate = plot:FindFirstChild("Gate")
	if gate == nil or not gate:IsA("BasePart") then
		return
	end
	for _, name in { "Court", "Court_T1" } do
		local old = plot:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "Court"
	folder:SetAttribute("Tier", tier)
	for _, spec in CourtPlan.parts(tier) do
		buildPart(gate, spec, folder)
	end
	folder.Parent = plot
end

-- Makes the pitch match the player's tier, unless an upgrade is about to build it.
function Stadium.ensure(session: Session.Session)
	local plot = session.runtime.plot
	if plot == nil or session.runtime.upgrading then
		return
	end
	local court = plot:FindFirstChild("Court")
	local tier = session.data.stadiumTier
	if court == nil or court:GetAttribute("Tier") ~= tier then
		Stadium.build(plot, tier)
	end
end

-- Turns the fireworks on for a few seconds.
function Stadium.fireworks(plot: Model)
	local court = plot:FindFirstChild("Court")
	if court == nil then
		return
	end
	local emitters = {}
	for _, descendant in court:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			table.insert(emitters, descendant)
		end
	end
	task.delay(FIREWORK_SECONDS, function()
		for _, emitter in emitters do
			emitter.Enabled = false
		end
	end)
end

-- Called after a stadium upgrade was paid and applied to the profile.
function Stadium.upgraded(session: Session.Session, firstEver: boolean)
	local runtime = session.runtime
	local tier = session.data.stadiumTier
	runtime.upgrading = true
	Remotes.fireClient("StadiumUpgraded", session.player, StadiumLogic.upgradeInfo(tier, firstEver))
	task.delay(Config.Cinematic.buildDelaySeconds, function()
		runtime.upgrading = false
		local plot = runtime.plot
		if plot and plot.Parent then
			Stadium.build(plot, session.data.stadiumTier)
			if session.data.stadiumTier >= #Config.StadiumTiers then
				Stadium.fireworks(plot)
			end
		end
	end)
end

return Stadium
