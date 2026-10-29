--!strict
-- The 8 plots (docs/PLAN.md, Step 1 and 7). A free slot shows a claim ring; standing on it for the
-- hold time clones the plot template there, so two players cannot claim the same slot. When the
-- owner leaves, the plot is removed and the ring comes back.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Analytics = require(script.Parent.Analytics)
local BackPrint = require(ReplicatedStorage.Shared.BackPrint)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local DevFlags = require(script.Parent.DevFlags)
local GymTiers = require(script.Parent.GymTiers)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local PadActions = require(script.Parent.PadActions)
local Remotes = require(script.Parent.Remotes)
local PlotLights = require(script.Parent.PlotLights)
local Pads = require(script.Parent.Pads)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Session = require(script.Parent.Session)
local Style = require(ReplicatedStorage.Shared.Style)
local Stadium = require(script.Parent.Stadium)
local Sync = require(script.Parent.Sync)
local TrophyCase = require(script.Parent.TrophyCase)

local SLOT_COUNT = 8
local RING_COLOR = Color3.fromRGB(255, 220, 60)

local plotsFolder: Folder
local rings: { [number]: Part } = {}
local slotOwner: { [number]: Player? } = {}
local started = false

local Plots = {}

-- Set once at startup: runs when a player claims a plot, before their state is synced (the
-- offline earnings are paid here, so the welcome-back card and the cash arrive together).
Plots.onClaimed = (function(_session: any) end) :: (session: Session.Session) -> ()

local PLAQUE_SIZE = Vector3.new(4.2, 1.1, 0.15)
local PLAQUE_COLOR = Color3.fromRGB(20, 24, 35)

-- A small sign standing on the front edge of the pedestal, facing the way the player faces, with the
-- name as printed on his shirt. `facing` points from the figure into the building.
local function buildPlaque(pedestal: BasePart, facing: Vector3, name: string): Part
	local plaque = Instance.new("Part")
	plaque.Name = "Plaque"
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanQuery = false
	plaque.CanTouch = false
	plaque.CastShadow = false
	plaque.Material = Enum.Material.SmoothPlastic
	plaque.Color = PLAQUE_COLOR
	plaque.Size = PLAQUE_SIZE
	-- The pedestal is a round slab: the shortest side is its thickness, the longest its width.
	local size = pedestal.Size
	local thickness = math.min(size.X, size.Y, size.Z)
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local top = pedestal.Position + Vector3.new(0, thickness / 2 + PLAQUE_SIZE.Y / 2, 0)
	local spot = top + facing * (radius - 0.8)
	-- Leaning back a little, like a plaque in a museum, so it reads from standing height.
	plaque.CFrame = CFrame.lookAt(spot, spot + facing) * CFrame.Angles(math.rad(20), 0, 0)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = plaque
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(0.92, 0.7)
	text.Position = UDim2.fromScale(0.04, 0.15)
	text.Text = BackPrint.surname(name)
	text.TextColor3 = Style.ui.text
	text.Font = Style.font
	text.TextScaled = true
	text.Parent = gui
	return plaque
end

local OWNER_SIGN_HEIGHT = 11
local OWNER_SIGN_MAX_DISTANCE = 160
local OWNER_SIGN_TEXT_SIZE = 30

-- The owner's name floating over the gate, for everyone on the road to read, in the look of the pad
-- labels (client/PadRing): no plate, white text with a thick black outline. A display name is already
-- filtered by Roblox, so it is shown as it is.
local function buildOwnerSign(gate: BasePart, player: Player): BillboardGui
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromOffset(420, 50)
	sign.StudsOffset = Vector3.new(0, OWNER_SIGN_HEIGHT, 0)
	sign.MaxDistance = OWNER_SIGN_MAX_DISTANCE
	sign.LightInfluence = 0
	sign.Adornee = gate
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = string.upper(player.DisplayName .. "'s club")
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Font = Style.font
	text.TextSize = OWNER_SIGN_TEXT_SIZE
	text.Parent = sign
	local outline = Instance.new("UIStroke")
	outline.Thickness = math.max(2, OWNER_SIGN_TEXT_SIZE / 7)
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = text
	sign.Parent = gate
	return sign
end

local function slotAnchor(index: number): BasePart
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("PlotSlots")
	local slot = slots and slots:FindFirstChild("Slot" .. index)
	assert(slot and slot:IsA("BasePart"), "missing Workspace.Map.PlotSlots.Slot" .. index)
	return slot
end

local function createRing(index: number)
	local ring = Instance.new("Part")
	ring.Name = "ClaimRing_" .. index
	ring.Size = Vector3.new(14, 0.2, 14)
	-- Same place as the Claim marker of the template: 8 studs inside the gate.
	ring.CFrame = slotAnchor(index).CFrame * CFrame.new(0, 0.8, 8)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Color = RING_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring:SetAttribute("Kind", "claim")
	ring:SetAttribute("PadId", "claim")
	ring:SetAttribute("SlotIndex", index)
	ring.Parent = plotsFolder
	rings[index] = ring

	Pads.register({
		key = ring.Name,
		part = ring,
		kind = "claim",
		padId = "claim",
		owner = nil,
		repeatable = false,
		status = function(player)
			local session = Session.get(player)
			if session and session.runtime.plot == nil and slotOwner[index] == nil then
				return "ready"
			end
			return "unavailable"
		end,
		complete = function(player)
			local session = Session.get(player)
			if session then
				Plots.assign(session, index)
			end
		end,
	})
end

local OWNED_GLASS_TRANSPARENCY = 0.78
local LOCKED_GLASS_TRANSPARENCY = 0.88
local LOCKED_GLASS_COLOR = Color3.fromRGB(215, 225, 238)
local CAPSULE_LIGHT_COLOR = Color3.fromRGB(255, 247, 232)
local RING_LOCKED_COLOR = Color3.fromRGB(170, 185, 210)

-- Turns a part into a cylinder that stands upright: `height` along the cylinder's axis, `diameter`
-- across, at `position`. (A Roblox cylinder lies along its X axis, so it is turned a quarter turn.)
local function makeUpright(part: BasePart, position: Vector3, height: number, diameter: number)
	if part:IsA("Part") then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
end

-- The glowing ring on the floor of a capsule: a thin neon disc under a slightly smaller dark one, so
-- only a ring of light shows around the player's feet. Soft light, tinted by the rarity once owned.
local function updateFloorRing(capsule: Instance, pedestal: BasePart, color: Color3, owned: boolean)
	local ring = capsule:FindFirstChild("FloorRing")
	if ring == nil then
		local top = pedestal.Position + Vector3.new(0, 0.5, 0)
		local neon = Instance.new("Part")
		neon.Name = "FloorRing"
		neon.Shape = Enum.PartType.Cylinder
		neon.Material = Enum.Material.Neon
		neon.Anchored = true
		neon.CanCollide = false
		neon.CanQuery = false
		neon.CanTouch = false
		neon.CastShadow = false
		neon.Size = Vector3.new(0.1, 4.5, 4.5)
		neon.CFrame = CFrame.new(top + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local glow = Instance.new("PointLight")
		glow.Range = 7
		glow.Brightness = 0.5
		glow.Shadows = false
		glow.Parent = neon
		neon.Parent = capsule
		local inner = Instance.new("Part")
		inner.Name = "FloorInner"
		inner.Shape = Enum.PartType.Cylinder
		inner.Material = Enum.Material.SmoothPlastic
		inner.Color = pedestal.Color
		inner.Anchored = true
		inner.CanCollide = false
		inner.CanQuery = false
		inner.CanTouch = false
		inner.Size = Vector3.new(0.12, 3.7, 3.7)
		inner.CFrame = CFrame.new(top + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		inner.Parent = capsule
		ring = neon
	end
	local neon = ring :: BasePart
	neon.Color = color
	neon.Transparency = if owned then 0.2 else 0.6
	local glow = neon:FindFirstChildOfClass("PointLight")
	if glow then
		glow.Color = color
		glow.Brightness = if owned then 0.5 else 0.2
	end
end

-- A spotlight from the top of the capsule down on the figure, so he is lit and his colours show. It is
-- made once per capsule and goes away with the plot.
local function addCapsuleLight(capsule: Instance, glass: BasePart)
	if capsule:FindFirstChild("Spot") then
		return
	end
	local spot = Instance.new("Part")
	spot.Name = "Spot"
	spot.Size = Vector3.new(0.5, 0.2, 0.5)
	spot.Transparency = 1
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.CastShadow = false
	spot.CFrame = CFrame.new(
		glass.Position
			+ Vector3.new(0, math.max(glass.Size.X, glass.Size.Y, glass.Size.Z) / 2 - 0.4, 0)
	)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 85
	light.Range = 16
	light.Brightness = 1.0
	light.Color = CAPSULE_LIGHT_COLOR
	light.Shadows = false
	light.Parent = spot
	spot.Parent = capsule
end

type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

-- The walls of the building in plot space (x to the right of the gate, z towards the stadium): the
-- extremes of the building parts. nil when the plot has no building parts.
local function buildingBounds(plot: Model, gate: BasePart): Bounds?
	local building = plot:FindFirstChild("Building")
	if building == nil then
		return nil
	end
	local bounds: Bounds =
		{ minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	local any = false
	for _, descendant in building:GetDescendants() do
		if descendant:IsA("BasePart") then
			any = true
			local inPlot = gate.CFrame:PointToObjectSpace(descendant.Position)
			bounds.minX = math.min(bounds.minX, inPlot.X)
			bounds.maxX = math.max(bounds.maxX, inPlot.X)
			bounds.minZ = math.min(bounds.minZ, inPlot.Z)
			bounds.maxZ = math.max(bounds.maxZ, inPlot.Z)
		end
	end
	return if any then bounds else nil
end

-- The way a capsule faces: straight away from the wall it stands against, into the building (a plot
-- space direction, one of the four axes). The wall is the nearest one.
local function inwardDirection(position: Vector3, bounds: Bounds): Vector3
	local nearest = position.X - bounds.minX
	local direction = Vector3.new(1, 0, 0) -- the front glass wall: face the building
	if bounds.maxX - position.X < nearest then
		nearest, direction = bounds.maxX - position.X, Vector3.new(-1, 0, 0)
	end
	if position.Z - bounds.minZ < nearest then
		nearest, direction = position.Z - bounds.minZ, Vector3.new(0, 0, 1)
	end
	if bounds.maxZ - position.Z < nearest then
		direction = Vector3.new(0, 0, -1)
	end
	return direction
end

-- Lights the capsules of owned players (glass tinted by rarity, a figure inside) and clears the
-- ones that are no longer owned.
function Plots.refresh(session: Session.Session)
	local plot = session.runtime.plot
	if plot == nil then
		return
	end
	Stadium.ensure(session)
	-- The kit the owner chose, for everyone who watches the match (the client draws the shirts).
	-- Before a choice the shirts keep their rarity colours.
	local kit = if session.data.cosmetics.chosen["kit"]
		then Cosmetics.chosen(session.data, "kit")
		else nil
	plot:SetAttribute("KitId", if kit then kit.id else "")
	TrophyCase.update(plot, session.data.season.number)
	GymTiers.update(plot, session.data.storeLevels.gymRate)

	-- The stairs are always walkable (the owner wants to see every floor). The gate marker at the
	-- bottom of each flight only carries the label; Open says whether buying there is unlocked.
	local stairs = plot:FindFirstChild("Stairs")
	if stairs then
		for _, gate in stairs:GetChildren() do
			local floor = gate:GetAttribute("Floor")
			if gate:IsA("BasePart") and type(floor) == "number" then
				CollectionService:AddTag(gate, "FloorGate") -- the client labels it
				gate.CanCollide = false
				gate.Transparency = 1
				gate:SetAttribute("Open", Roster.floorUnlocked(session.data, floor))
			end
		end
	end

	local capsules = plot:FindFirstChild("Capsules")
	if capsules == nil then
		return
	end
	local gateInstance = plot:FindFirstChild("Gate")
	local gate: BasePart? = if gateInstance and gateInstance:IsA("BasePart")
		then gateInstance
		else nil
	local bounds = if gate then buildingBounds(plot, gate) else nil
	for _, capsule in capsules:GetChildren() do
		local playerId = capsule:GetAttribute("PlayerId")
		local def = if type(playerId) == "string" then Config.PlayersById[playerId] else nil
		local pedestal = capsule:FindFirstChild("Pedestal")
		local glass = capsule:FindFirstChild("Glass")
		if def and pedestal and pedestal:IsA("BasePart") and glass and glass:IsA("BasePart") then
			local owned = Roster.owns(session.data, def.id)
			capsule:SetAttribute("Owned", owned)
			-- Every player stands in his capsule: in full colour once owned, washed out before.
			-- The Glass material hides the name and number printed on the shirt behind it; a plain
			-- material with the same transparency shows them.
			glass.Material = Enum.Material.SmoothPlastic
			-- The capsule and its floor are round, not boxes (done once; the pedestal is 1 stud thick).
			if capsule:GetAttribute("Round") ~= true then
				capsule:SetAttribute("Round", true)
				makeUpright(
					glass,
					glass.Position,
					glass.Size.Y,
					math.min(glass.Size.X, glass.Size.Z)
				)
				makeUpright(
					pedestal,
					pedestal.Position,
					pedestal.Size.Y,
					math.min(pedestal.Size.X, pedestal.Size.Z)
				)
			end
			local figure = capsule:FindFirstChild("Figure")
			if figure and figure:GetAttribute("Owned") ~= owned then
				figure:Destroy()
				figure = nil
			end
			if figure == nil then
				local model = Mannequin.build(def, nil, false, { locked = not owned })
				model.Name = "Figure"
				model:SetAttribute("Owned", owned)
				local stand =
					CFrame.new(pedestal.Position + Vector3.new(0, 0.5 + Mannequin.FEET_TO_TORSO, 0))
				-- Every figure faces straight away from his wall, into the building, so whoever walks
				-- inside sees his face.
				if gate and bounds then
					local inside =
						inwardDirection(gate.CFrame:PointToObjectSpace(stand.Position), bounds)
					local ahead = stand.Position + gate.CFrame:VectorToWorldSpace(inside)
					model:PivotTo(CFrame.lookAt(stand.Position, ahead))
				else
					model:PivotTo(stand)
				end
				if gate and bounds then
					local inside =
						inwardDirection(gate.CFrame:PointToObjectSpace(stand.Position), bounds)
					local facing = gate.CFrame:VectorToWorldSpace(inside).Unit
					buildPlaque(pedestal, facing, def.name).Parent = model
				end
				model.Parent = capsule
			end
			-- The glass is tinted by the rarity once owned, but clear enough to see the real colours of the
			-- kit; an empty capsule is nearly clear.
			if owned then
				glass.Color = Style.rarityColors[def.rarity] or LOCKED_GLASS_COLOR
				glass.Transparency = OWNED_GLASS_TRANSPARENCY
			else
				glass.Color = LOCKED_GLASS_COLOR
				glass.Transparency = LOCKED_GLASS_TRANSPARENCY
			end
			addCapsuleLight(capsule, glass)
			updateFloorRing(
				capsule,
				pedestal,
				if owned
					then Style.rarityTrim[def.rarity]
						or Style.rarityColors[def.rarity]
						or RING_LOCKED_COLOR
					else RING_LOCKED_COLOR,
				owned
			)
		end
	end
end

-- Gives the player the plot of `slotIndex` (the first free one when nil). False when they
-- already have one or the slot is taken.
function Plots.assign(session: Session.Session, slotIndex: number?): boolean
	local player = session.player
	if session.runtime.plot ~= nil then
		return false
	end
	local index = slotIndex
	if index == nil then
		for candidate = 1, SLOT_COUNT do
			if slotOwner[candidate] == nil then
				index = candidate
				break
			end
		end
	end
	if index == nil or slotOwner[index] ~= nil then
		return false
	end

	local template = ServerStorage:FindFirstChild("PlotTemplate")
	assert(template and template:IsA("Model"), "ServerStorage.PlotTemplate is missing")
	local plot = template:Clone()
	plot.Name = "Plot_" .. index
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("SlotIndex", index)
	-- The template's origin is the middle of the gate, one stud above the ground reference.
	local templatePivot = template:GetPivot()
	plot:PivotTo(slotAnchor(index).CFrame * CFrame.new(0, 1, 0))
	-- The claim ring part replaced the template's Claim marker while the slot was free.
	-- The penalty kicks open from the HUD icon, so the old penalty marker is not needed.
	local penaltyMarker = plot.Markers:FindFirstChild("Penalty")
	if penaltyMarker then
		penaltyMarker:Destroy()
	end
	local claimMarker = plot.Markers:FindFirstChild("Claim")
	if claimMarker then
		claimMarker:Destroy()
	end
	PlotLights.build(plot, templatePivot)
	local gate = plot:FindFirstChild("Gate")
	if gate and gate:IsA("BasePart") then
		buildOwnerSign(gate, player)
	end
	plot.Parent = plotsFolder

	slotOwner[index] = player
	session.runtime.plot = plot
	session.runtime.slotIndex = index
	player:SetAttribute("plotSlot", index)
	local firstClaim = not session.data.flags.hasClaimedPlot
	session.data.flags.hasClaimedPlot = true

	local ring = rings[index]
	if ring then
		Pads.unregister(ring.Name)
		ring:Destroy()
		rings[index] = nil
	end

	PadActions.registerPlot(session, plot)
	Plots.refresh(session)
	Analytics.milestone(session, "claimed_plot")
	Plots.onClaimed(session)
	Sync.all(session)
	if firstClaim and not DevFlags.skipIntros() then
		-- The first claim ever: the client plays the 5 second tour of the building, stadium and training.
		Remotes.fireClient("Notice", player, { kind = "plotTour" })
	end
	return true
end

local function release(player: Player)
	for index, owner in slotOwner do
		if owner == player then
			slotOwner[index] = nil
			Pads.unregisterOwner(player)
			local plot = plotsFolder:FindFirstChild("Plot_" .. index)
			if plot then
				plot:Destroy()
			end
			createRing(index)
		end
	end
end

-- Creates the plots folder and a claim ring on every slot. Call once, after Pads exist.
function Plots.init()
	assert(not started, "Plots.init called twice")
	started = true
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = Workspace
	for index = 1, SLOT_COUNT do
		createRing(index)
	end
	Players.PlayerRemoving:Connect(release)
end

return Plots
