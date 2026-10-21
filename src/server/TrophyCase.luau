--!strict
-- The trophy case outside the door of a plot (template folder Entrance, built by
-- tools/studio/BuildEntrance.luau). It starts empty, with the name of each trophy on its plaque; the
-- trophy of a tier appears on its pedestal for every season the owner has finished. The trophies are
-- models made in Studio from the trophy drawings (shared/TrophyModels); a plain gold cup stands in if one
-- is missing.
-- Derived from the season number, never stored (docs/PLAN.md, Step 6): a finished season is every
-- season before the current.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Season = require(ReplicatedStorage.Shared.Season)
local TrophyModels = require(ReplicatedStorage.Shared.TrophyModels)

local SLOTS = 5
local GOLD = Color3.fromRGB(240, 190, 60)
-- The models face -Z; the case faces the path (-X of the plot), so they turn a quarter to look out of
-- the glass.
local FACING = CFrame.Angles(0, math.rad(90), 0)

local TrophyCase = {}

local function piece(parent: Instance, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = GOLD
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A plain gold cup standing on the top of `pedestal`: foot, stem, bowl and two handles.
local function buildCup(pedestal: BasePart, name: string): Model
	local cup = Instance.new("Model")
	cup.Name = name
	local top = pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2, 0)
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lies along X; stand it up
	piece(
		cup,
		Vector3.new(0.4, 1.8, 1.8),
		CFrame.new(top + Vector3.new(0, 0.2, 0)) * upright,
		Enum.PartType.Cylinder
	)
	piece(
		cup,
		Vector3.new(1.2, 0.5, 0.5),
		CFrame.new(top + Vector3.new(0, 0.85, 0)) * upright,
		Enum.PartType.Cylinder
	)
	piece(
		cup,
		Vector3.new(1.5, 1.6, 1.6),
		CFrame.new(top + Vector3.new(0, 2.1, 0)) * upright,
		Enum.PartType.Cylinder
	)
	for _, side in { -1, 1 } do
		piece(cup, Vector3.new(0.3, 0.9, 0.3), CFrame.new(top + Vector3.new(0, 2.3, side * 1.05)))
	end
	cup.Parent = pedestal.Parent
	return cup
end

-- The trophy model of `slot` standing on the top of `pedestal`, or the plain cup without a model.
local function placeTrophy(pedestal: BasePart, name: string, slot: number): Model
	local trophy = TrophyModels.clone(slot)
	if trophy == nil then
		return buildCup(pedestal, name)
	end
	trophy.Name = name
	-- The pedestal turns with the plot, so the trophy takes its turn from the pedestal.
	trophy:PivotTo(pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2, 0) * FACING)
	trophy.Parent = pedestal.Parent
	return trophy
end

-- Writes the names on the plaques and puts a cup on every pedestal of a finished season.
-- `season` is the owner's current season number.
function TrophyCase.update(plot: Model, season: number)
	local entrance = plot:FindFirstChild("Entrance")
	if entrance == nil then
		return
	end
	local finished = math.max(season - 1, 0)
	for slot = 1, SLOTS do
		-- The last pedestal keeps the newest trophy once the five names are used up.
		local number = if slot == SLOTS and finished > SLOTS then finished else slot
		local pedestal = entrance:FindFirstChild("TrophySlot_" .. slot)
		local plaque = entrance:FindFirstChild("TrophyPlaque_" .. slot)
		local gui = if plaque then plaque:FindFirstChildWhichIsA("SurfaceGui") else nil
		local label = if gui then gui:FindFirstChild("Name") else nil
		if label and label:IsA("TextLabel") then
			label.Text = string.upper(Season.trophyName(number))
		end
		local cupName = "Cup_" .. slot
		local earned = finished >= slot
		local cup = entrance:FindFirstChild(cupName)
		if earned and cup == nil and pedestal and pedestal:IsA("BasePart") then
			placeTrophy(pedestal, cupName, slot)
		elseif not earned and cup then
			cup:Destroy()
		end
	end
end

return TrophyCase
