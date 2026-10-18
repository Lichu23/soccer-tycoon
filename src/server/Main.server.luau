--!strict
-- Server bootstrap: starts each module in an explicit order and fails visibly.

local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

Remotes.init()
Session.init()

Session.onLoaded(function(session)
	local owned = 0
	for _ in session.data.players do
		owned += 1
	end
	print(
		string.format(
			"[Server] %s loaded: $%d, tier %d, %d players owned",
			session.player.Name,
			session.data.cash,
			session.data.stadiumTier,
			owned
		)
	)
end)

print("soccer-tycoon server started")
