--!strict
-- Connects the rarity reveals to the client (docs/PLAN.md, Steps 5 and 7): sends the pending ones
-- and takes the acknowledgement. The rules live in Reveals; the client only plays what it is sent.

local Remotes = require(script.Parent.Remotes)
local Reveals = require(script.Parent.Reveals)
local Session = require(script.Parent.Session)

local started = false

local RevealActions = {}

-- Sends the pending reveals of this player, or only the ones for `onlyId`.
function RevealActions.send(session: Session.Session, onlyId: string?)
	for _, entry in session.data.pendingReveals do
		if onlyId == nil or entry.playerId == onlyId then
			Remotes.fireClient("Reveal", session.player, table.clone(entry))
		end
	end
end

-- Registers the remote handler. Call once, after Remotes.init.
function RevealActions.start()
	assert(not started, "RevealActions.start called twice")
	started = true
	Remotes.on("AckReveal", function(player: Player, ...: any)
		local id = select(1, ...)
		local session = Session.get(player)
		if session and type(id) == "string" then
			Reveals.acknowledge(session.data, id)
		end
	end)
end

return RevealActions
