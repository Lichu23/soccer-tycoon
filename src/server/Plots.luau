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
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
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

local SLOT_COUNT = 8
local RING_COLOR = Color3.fromRGB(255, 220, 60)

local plotsFolder: Folder
local rings: { [number]: Part } = {}
local slotOwner: { [number]: Player? } = {}
local started = false

local Plots = {}

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
			if glass:GetAttribute("BaseColor") == nil then
				glass:SetAttribute("BaseColor", glass.Color)
				glass:SetAttribute("BaseTransparency", glass.Transparency)
			end
			-- The Glass material hides the name and number printed on the shirt behind it; a plain
			-- material with the same transparency shows them.
			glass.Material = Enum.Material.SmoothPlastic
			local figure = capsule:FindFirstChild("Figure")
			if figure and figure:GetAttribute("Owned") ~= owned then
				figure:Destroy()
				figure = nil
			end
			if figure == nil then
				local model =
					Mannequin.build(def, nil, false, { detailed = true, locked = not owned })
				model.Name = "Figure"
				model:SetAttribute("Owned", owned)
				local stand = pedestal.CFrame * CFrame.new(0, 0.5 + Mannequin.FEET_TO_TORSO, 0)
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
				model.Parent = capsule
			end
			if owned then
				glass.Color = Style.rarityColors[def.rarity] or glass.Color
				glass.Transparency = 0.55
			else
				local baseColor = glass:GetAttribute("BaseColor")
				local baseTransparency = glass:GetAttribute("BaseTransparency")
				if typeof(baseColor) == "Color3" then
					glass.Color = baseColor
				end
				if type(baseTransparency) == "number" then
					glass.Transparency = baseTransparency
				end
			end
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
	Sync.all(session)
	if firstClaim then
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
