--!strict
-- What the client knows about the player's progress: the cash attribute and the snapshot the
-- server sends. It is display only: nothing here decides a purchase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local listeners: { () -> () } = {}

local State = {}

State.data = {
	cash = 0,
	tp = 0,
	stadiumTier = 1,
	storeLevels = { matchSpeed = 0, hatTrick = 0, gymRate = 0 },
	fieldStarted = false,
	players = {},
	trials = {},
	cosmetics = { owned = {}, chosen = {} },
} :: Types.ProgressData

-- True once the first snapshot from the server has arrived (before it the data is empty).
State.loaded = false

-- Calls `listener` after any change of the cash, the snapshot or the plot. Returns a function that
-- stops it.
function State.onChange(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

local function notify()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

-- The reward hold: while the free case spins, the HUD keeps showing what the player had before it, so
-- the prize is not given away before the roulette lands. The server pays at once; this only delays
-- what the screen shows, and always ends (the roulette ends it, or a timeout).
local HOLD_TIMEOUT_SECONDS = 15
local hold: { cash: number, tp: number, boostWasActive: boolean, prize: any? }? = nil

function State.holdReward()
	local boostEnds = player:GetAttribute("boostEndsAt")
	local active = type(boostEnds) == "number" and boostEnds > Workspace:GetServerTimeNow()
	local mine =
		{ cash = State.data.cash, tp = State.data.tp, boostWasActive = active, prize = nil }
	hold = mine
	task.delay(HOLD_TIMEOUT_SECONDS, function()
		if hold == mine then
			State.releaseReward()
		end
	end)
end

-- The prize the server rolled: from now the HUD shows the real values minus this prize.
function State.setHeldPrize(prize: any)
	if hold then
		hold.prize = prize
	end
end

function State.releaseReward()
	if hold == nil then
		return
	end
	hold = nil
	notify()
end

-- The cash and the training points the HUD shows.
function State.shownCash(): number
	local held = hold
	if held == nil then
		return State.data.cash
	end
	local prize = held.prize
	if prize == nil then
		return held.cash
	end
	return if prize.kind == "cash" and type(prize.amount) == "number"
		then math.max(State.data.cash - prize.amount, 0)
		else State.data.cash
end

function State.shownTp(): number
	local held = hold
	if held == nil then
		return State.data.tp
	end
	local prize = held.prize
	if prize == nil then
		return held.tp
	end
	return if prize.kind == "tp" and type(prize.amount) == "number"
		then math.max(State.data.tp - prize.amount, 0)
		else State.data.tp
end

-- True while a boost that only the held prize can have started should stay off the badge.
function State.boostHeld(): boolean
	local held = hold
	if held == nil or held.boostWasActive then
		return false
	end
	return held.prize == nil or held.prize.kind == "boost"
end

function State.hasPlot(): boolean
	return player:GetAttribute("plotSlot") ~= nil
end

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	local data = State.data
	if type(snapshot.cash) == "number" then
		data.cash = snapshot.cash
	end
	if type(snapshot.tp) == "number" then
		data.tp = snapshot.tp
	end
	if type(snapshot.stadiumTier) == "number" then
		data.stadiumTier = snapshot.stadiumTier
	end
	if type(snapshot.fieldStarted) == "boolean" then
		data.fieldStarted = snapshot.fieldStarted
	end
	if type(snapshot.storeLevels) == "table" then
		for id, level in snapshot.storeLevels do
			if type(level) == "number" and (data.storeLevels :: any)[id] ~= nil then
				(data.storeLevels :: any)[id] = level
			end
		end
	end
	if type(snapshot.players) == "table" then
		data.players = snapshot.players
	end
	if type(snapshot.trials) == "table" then
		data.trials = snapshot.trials
	end
	if type(snapshot.cosmetics) == "table" then
		data.cosmetics = snapshot.cosmetics
	end
	if type(snapshot.flags) == "table" and type(snapshot.flags.milestones) == "table" then
		(data :: any).flags = { milestones = snapshot.flags.milestones } -- read by Progress.firstMatchPlayed
	end
	State.loaded = true
end

-- Starts listening, then asks the server for the first snapshot.
function State.init()
	Net.on("Snapshot", function(snapshot: any)
		applySnapshot(snapshot)
		notify()
	end)
	player:GetAttributeChangedSignal("cash"):Connect(function()
		local cash = player:GetAttribute("cash")
		if type(cash) == "number" then
			State.data.cash = cash
			notify()
		end
	end)
	player:GetAttributeChangedSignal("tp"):Connect(function()
		local tp = player:GetAttribute("tp")
		if type(tp) == "number" then
			State.data.tp = tp
			notify()
		end
	end)
	player:GetAttributeChangedSignal("plotSlot"):Connect(notify)
	Net.fire("ClientReady")
end

return State
