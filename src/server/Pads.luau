--!strict
-- The server-timed pads (docs/PLAN.md, Step 5): the player just stands on a pad. The server finds
-- who stands on which pad about ten times a second and times the hold with its own clock; the
-- client only draws the ring from the attributes below. Every buy, level-up, claim and upgrade
-- goes through here, so it is the base of the loop.
--
-- Attributes set on each player: padKey (nil off a pad), padState, padStart (server time the
-- hold began, 0 when it is not filling) and padHold (seconds).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HoldTracker = require(script.Parent.HoldTracker)
local PadGeometry = require(script.Parent.PadGeometry)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)

export type Pad = {
	key: string,
	part: BasePart,
	kind: string,
	padId: string,
	owner: Player?, -- only this player can use it; nil = any player
	repeatable: boolean, -- keeps buying every hold while the player stays (level-up pads)
	status: (player: Player) -> string, -- "ready", or anything else to block the pad
	complete: (player: Player) -> (),
}

local TICK_SECONDS = 0.1

local byKey: { [string]: Pad } = {}
local byOwner: { [Player]: { Pad } } = {}
local publicPads: { Pad } = {}
local tracker = HoldTracker.new(Config.Pad.holdSeconds)
local published: { [Player]: string } = {}
local started = false

local Pads = {}

local function removeFrom(list: { Pad }, key: string)
	for index = #list, 1, -1 do
		if list[index].key == key then
			table.remove(list, index)
		end
	end
end

-- Adds a pad. The pad part is tagged "Pad" and gets PadKey and OwnerUserId attributes so the
-- client can find it and draw its text and ring.
function Pads.register(pad: Pad)
	assert(byKey[pad.key] == nil, "duplicate pad key " .. pad.key)
	byKey[pad.key] = pad
	pad.part:SetAttribute("PadKey", pad.key)
	pad.part:SetAttribute("OwnerUserId", if pad.owner then pad.owner.UserId else 0)
	CollectionService:AddTag(pad.part, "Pad")
	if pad.owner then
		local list = byOwner[pad.owner]
		if list == nil then
			list = {}
			byOwner[pad.owner] = list
		end
		table.insert(list, pad)
	else
		table.insert(publicPads, pad)
	end
end

function Pads.unregister(key: string)
	local pad = byKey[key]
	if pad == nil then
		return
	end
	byKey[key] = nil
	if pad.owner then
		local list = byOwner[pad.owner]
		if list then
			removeFrom(list, key)
		end
	else
		removeFrom(publicPads, key)
	end
end

-- Removes every pad that belongs to this player (their plot is gone).
function Pads.unregisterOwner(player: Player)
	local list = byOwner[player]
	if list == nil then
		return
	end
	for index = #list, 1, -1 do
		byKey[list[index].key] = nil
	end
	byOwner[player] = nil
end

local function padUnder(player: Player, position: Vector3): Pad?
	local function test(pad: Pad): boolean
		local localPosition = pad.part.CFrame:PointToObjectSpace(position)
		return PadGeometry.isOn(
			localPosition.X,
			localPosition.Y,
			localPosition.Z,
			pad.part.Size.X,
			pad.part.Size.Z
		)
	end
	local own = byOwner[player]
	if own then
		for _, pad in own do
			if test(pad) then
				return pad
			end
		end
	end
	for _, pad in publicPads do
		if test(pad) then
			return pad
		end
	end
	return nil
end

local function statusOf(pad: Pad, player: Player): string
	local ok, status = pcall(pad.status, player)
	if ok and type(status) == "string" then
		return status
	end
	return "error"
end

-- Writes the pad attributes, only when something changed.
local function publish(player: Player, pad: Pad?, status: string)
	local state = tracker:get(player.UserId)
	local startedAt = if state then state.startedAt else nil
	local signature =
		string.format("%s|%s|%s", if pad then pad.key else "-", status, tostring(startedAt))
	if published[player] == signature then
		return
	end
	published[player] = signature

	player:SetAttribute("padKey", if pad then pad.key else nil)
	player:SetAttribute("padState", if pad then status else nil)
	player:SetAttribute("padHold", Config.Pad.holdSeconds)
	if startedAt then
		-- startedAt is os.clock() time; the client works in server time.
		player:SetAttribute("padStart", Workspace:GetServerTimeNow() - (os.clock() - startedAt))
	else
		player:SetAttribute("padStart", 0)
	end
end

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local session = Session.get(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local pad: Pad? = nil
		local status = "ready"
		if session and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			pad = padUnder(player, root.Position)
		end
		if pad then
			status = statusOf(pad, player)
		end

		local event = tracker:update(
			player.UserId,
			if pad then pad.key else nil,
			status,
			if pad then pad.repeatable else false,
			now
		)
		if event == "complete" and pad then
			local ok, err = Safe.call(pad.complete, player)
			if not ok then
				warn(
					string.format(
						"[Pads] %s failed for %s: %s",
						pad.key,
						player.Name,
						tostring(err)
					)
				)
			end
			status = statusOf(pad, player)
		end
		publish(player, pad, status)
	end
end

-- Starts the loop that watches the pads. Call once.
function Pads.start()
	assert(not started, "Pads.start called twice")
	started = true
	Players.PlayerRemoving:Connect(function(player)
		tracker:forget(player.UserId)
		published[player] = nil
		Pads.unregisterOwner(player)
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = Safe.call(step)
			if not ok then
				warn("[Pads] step failed: " .. tostring(err))
			end
		end
	end)
end

return Pads
