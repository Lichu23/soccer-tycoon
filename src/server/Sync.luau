--!strict
-- Sends a player's state to their client (docs/PLAN.md, Step 5): single values travel as player
-- attributes (no remote), lists as one snapshot. The server never reads these back.

local Workspace = game:GetService("Workspace")

local Economy = require(script.Parent.Economy)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Sync = {}

-- Cash, training points, tier, the field flag and the boost end time.
function Sync.scalars(session: Session.Session)
	local player, data = session.player, session.data
	Economy.publish(player, data)
	player:SetAttribute("stadiumTier", data.stadiumTier)
	player:SetAttribute("fieldStarted", data.fieldStarted)
	local left = data.boosts.stadiumBoostLeft
	player:SetAttribute("boostEndsAt", if left > 0 then Workspace:GetServerTimeNow() + left else 0)
end

-- The progress subset the HUD, the pads and the goal row need.
function Sync.snapshot(session: Session.Session)
	local data = session.data
	local players = {}
	for id, owned in data.players do
		players[id] = { level = owned.level, stars = owned.stars }
	end
	Remotes.fireClient("Snapshot", session.player, {
		cash = data.cash,
		stadiumTier = data.stadiumTier,
		storeLevels = {
			cashPerMatch = data.storeLevels.cashPerMatch,
			matchSpeed = data.storeLevels.matchSpeed,
			hatTrick = data.storeLevels.hatTrick,
			offline = data.storeLevels.offline,
		},
		fieldStarted = data.fieldStarted,
		players = players,
	})
end

function Sync.all(session: Session.Session)
	Sync.scalars(session)
	Sync.snapshot(session)
end

return Sync
