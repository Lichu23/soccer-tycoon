--!strict
-- Builds the pitch of a plot for its stadium tier (docs/PLAN.md, Step 7) from CourtPlan, and runs
-- the server side of an upgrade: tell the player's client to play the cinematic, build the new
-- pitch once the camera has arrived, and let the fireworks go off at tiers 5 and 6. The server finishes
-- the upgrade even if the player leaves or skips; the cinematic only affects that client. The pitch
-- also wears the owner's Locker room styles (shared/StadiumLook), painted after every build, the
-- floodlight model they chose and, at the roof arena, the name they gave it (filtered first).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local CourtParts = require(ReplicatedStorage.Shared.CourtParts)
local CourtPlan = require(ReplicatedStorage.Shared.CourtPlan)
local DevFlags = require(script.Parent.DevFlags)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local StadiumLogic = require(script.Parent.StadiumLogic)
local StadiumLook = require(ReplicatedStorage.Shared.StadiumLook)
local StadiumName = require(script.Parent.StadiumName)

local FIREWORK_SECONDS = 4

local Stadium = {}

-- The floodlight model of the player's pitch: their choice once the slot is open, else the LED light.
local function lampModel(data: ProfileSchema.Profile): string
	local def = if Cosmetics.slotOpen(data, "lamps") then Cosmetics.chosen(data, "lamps") else nil
	return def and def.model or "led"
end

-- Replaces the pitch of `plot` with the one of `tier`, with floodlights in `model`.
function Stadium.build(plot: Model, tier: number, model: string)
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
	folder:SetAttribute("Lamps", model)
	for index, spec in CourtPlan.parts(tier, model) do
		CourtParts.build(gate, spec, folder, index)
	end
	folder.Parent = plot
end

-- Paints the styles of every open slot on the pitch (the kit is drawn by the match) and writes `name`
-- (already filtered) over the gate of the roof arena. A slot that is not open yet keeps the plan's
-- own colours.
function Stadium.paint(plot: Model, data: ProfileSchema.Profile, name: string?)
	local court = plot:FindFirstChild("Court")
	if court == nil then
		return
	end
	for _, slot in Config.CosmeticSlots do
		if StadiumLook.PARTS[slot.id] and Cosmetics.slotOpen(data, slot.id) then
			local def = Cosmetics.chosen(data, slot.id)
			if def then
				StadiumLook.paint(court, slot.id, def)
			end
		end
	end
	StadiumLook.setName(court, if Cosmetics.slotOpen(data, "stadium") then name else nil)
end

-- Filters the saved name once per visit, then paints it.
local function filterName(session: Session.Session)
	local runtime = session.runtime
	if session.data.stadiumName == "" or runtime.stadiumName ~= nil or runtime.nameFiltering then
		return
	end
	runtime.nameFiltering = true
	task.spawn(function()
		local filtered = StadiumName.filter(session.player, session.data.stadiumName)
		runtime.nameFiltering = false
		-- A name the filter now changes is not shown (the sign keeps its own text).
		if filtered and filtered == session.data.stadiumName then
			runtime.stadiumName = filtered
			session.player:SetAttribute("stadiumName", filtered)
			Stadium.ensure(session)
		end
	end)
end

-- Makes the pitch match the player's tier and styles, unless an upgrade is about to build it.
function Stadium.ensure(session: Session.Session)
	local plot = session.runtime.plot
	if plot == nil or session.runtime.upgrading then
		return
	end
	local court = plot:FindFirstChild("Court")
	local tier = session.data.stadiumTier
	local model = lampModel(session.data)
	if court == nil or court:GetAttribute("Tier") ~= tier then
		Stadium.build(plot, tier, model)
	elseif court:GetAttribute("Lamps") ~= model then
		local gate = plot:FindFirstChild("Gate")
		if gate and gate:IsA("BasePart") then
			CourtParts.setLamps(court, gate, tier, model)
		end
	end
	Stadium.paint(plot, session.data, session.runtime.stadiumName)
	filterName(session)
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
	local unskippable = firstEver and not DevFlags.skipIntros()
	Remotes.fireClient(
		"StadiumUpgraded",
		session.player,
		StadiumLogic.upgradeInfo(tier, unskippable)
	)
	task.delay(Config.Cinematic.buildDelaySeconds, function()
		runtime.upgrading = false
		local plot = runtime.plot
		if plot and plot.Parent then
			Stadium.build(plot, session.data.stadiumTier, lampModel(session.data))
			Stadium.paint(plot, session.data, runtime.stadiumName)
			Stadium.fireworks(plot) -- only the big stadiums have launch points
		end
	end)
end

return Stadium
