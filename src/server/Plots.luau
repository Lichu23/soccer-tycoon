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
local Daily = require(script.Parent.Daily)
local Mannequin = require(ReplicatedStorage.Shared.Mannequin)
local PadActions = require(script.Parent.PadActions)
local Pads = require(script.Parent.Pads)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Session = require(script.Parent.Session)
local Style = require(ReplicatedStorage.Shared.Style)
local Stadium = require(script.Parent.Stadium)
local Sync = require(script.Parent.Sync)

local SLOT_COUNT = 8
local RING_COLOR = Color3.fromRGB(255, 220, 60)
local PAD_TRANSPARENCY = 0.4 -- the template markers are built with this

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

-- Lights the capsules of owned players (glass tinted by rarity, a figure inside) and clears the
-- ones that are no longer owned.
function Plots.refresh(session: Session.Session)
	local plot = session.runtime.plot
	if plot == nil then
		return
	end
	Stadium.ensure(session)

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

	-- The penalty pad appears with the first stadium upgrade (it is invisible and unusable before).
	local markers = plot:FindFirstChild("Markers")
	local penalty = markers and markers:FindFirstChild("Penalty")
	if penalty and penalty:IsA("BasePart") then
		penalty.Transparency = if Daily.unlocked(session.data) then PAD_TRANSPARENCY else 1
	end

	local capsules = plot:FindFirstChild("Capsules")
	if capsules == nil then
		return
	end
	for _, capsule in capsules:GetChildren() do
		local playerId = capsule:GetAttribute("PlayerId")
		local def = if type(playerId) == "string" then Config.PlayersById[playerId] else nil
		local pedestal = capsule:FindFirstChild("Pedestal")
		local glass = capsule:FindFirstChild("Glass")
		if def and pedestal and pedestal:IsA("BasePart") and glass and glass:IsA("BasePart") then
			local owned = Roster.owns(session.data, def.id)
			local figure = capsule:FindFirstChild("Figure")
			capsule:SetAttribute("Owned", owned)
			if owned and figure == nil then
				local model = Mannequin.build(def, nil, true)
				model.Name = "Figure"
				model:PivotTo(pedestal.CFrame * CFrame.new(0, 0.5 + Mannequin.FEET_TO_TORSO, 0))
				model.Parent = capsule
				glass.Color = Style.rarityColors[def.rarity] or glass.Color
				glass.Transparency = 0.55
			elseif not owned and figure then
				figure:Destroy()
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
	plot:PivotTo(slotAnchor(index).CFrame * CFrame.new(0, 1, 0))
	-- The claim ring part replaced the template's Claim marker while the slot was free.
	local claimMarker = plot.Markers:FindFirstChild("Claim")
	if claimMarker then
		claimMarker:Destroy()
	end
	plot.Parent = plotsFolder

	slotOwner[index] = player
	session.runtime.plot = plot
	session.runtime.slotIndex = index
	player:SetAttribute("plotSlot", index)
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
