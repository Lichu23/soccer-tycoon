--!strict
-- What the client knows about the player's progress: the cash attribute and the snapshot the
-- server sends. It is display only: nothing here decides a purchase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(script.Parent.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local listeners: { () -> () } = {}

local State = {}

State.data = {
	cash = 0,
	tp = 0,
	stadiumTier = 1,
	storeLevels = { cashPerMatch = 0, matchSpeed = 0, hatTrick = 0, offline = 0 },
	fieldStarted = false,
	players = {},
	trials = {},
	cosmetics = { owned = {}, chosen = {} },
} :: Types.ProgressData

-- True once the first snapshot from the server has arrived (before it the data is empty).
State.loaded = false

-- Calls `listener` after any change of the cash, the snapshot or the plot.
function State.onChange(listener: () -> ())
	table.insert(listeners, listener)
end

local function notify()
	for _, listener in listeners do
		task.spawn(listener)
	end
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
