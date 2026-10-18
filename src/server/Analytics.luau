--!strict
-- Funnel events for the first session (docs/PLAN.md, Step 4 "How to verify"): joined, claimed a
-- plot, first purchase, first match, first upgrade, first stadium upgrade. A milestone is logged
-- once per player ever, with the seconds since they joined this server, so the time to the first
-- purchase can be read from the data. Each event is also kept in `history` for tests.

local AnalyticsService = game:GetService("AnalyticsService")

local Session = require(script.Parent.Session)

export type Entry = { userId: number, name: string, seconds: number, milestone: boolean }

local Analytics = {}

Analytics.history = {} :: { Entry }

local function record(session: Session.Session, name: string, milestone: boolean)
	local seconds = os.time() - session.joinedAt
	table.insert(
		Analytics.history,
		{ userId = session.player.UserId, name = name, seconds = seconds, milestone = milestone }
	)
	print(string.format("[Analytics] %s %s (+%ds)", session.player.Name, name, seconds))
	-- The custom event API can be unavailable (Studio, API changes): never let it break the game.
	pcall(function()
		AnalyticsService:LogCustomEvent(session.player, name, seconds)
	end)
end

-- An event that can happen every session, for example joining.
function Analytics.event(session: Session.Session, name: string)
	record(session, name, false)
end

-- Logs `name` the first time it ever happens to this player. Returns true when it was new.
function Analytics.milestone(session: Session.Session, name: string): boolean
	local milestones = session.data.flags.milestones
	if milestones[name] ~= nil then
		return false
	end
	milestones[name] = os.time()
	record(session, name, true)
	return true
end

return Analytics
