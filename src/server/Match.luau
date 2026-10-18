--!strict
-- The match loop (docs/PLAN.md, Step 1). Every player with a started field plays an automatic
-- match every few seconds. The server resolves the match and pays; the client only draws it from
-- the MatchResult event. One loop serves every player.
--
-- Attributes on the player for the HUD bar: matchDuration (seconds) and matchEndsAt (server time).

local Workspace = game:GetService("Workspace")

local Analytics = require(script.Parent.Analytics)
local Boosts = require(script.Parent.Boosts)
local Economy = require(script.Parent.Economy)
local MatchLogic = require(script.Parent.MatchLogic)
local Remotes = require(script.Parent.Remotes)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local TICK_SECONDS = 0.25

local random = Random.new()
local started = false

local Match = {}

local function rng(): number
	return random:NextNumber()
end

local function schedule(session: Session.Session)
	local seconds = MatchLogic.interval(session.data)
	session.runtime.nextMatchAt = os.clock() + seconds
	session.player:SetAttribute("matchDuration", seconds)
	session.player:SetAttribute("matchEndsAt", Workspace:GetServerTimeNow() + seconds)
end

local function finishMatch(session: Session.Session)
	local runtime = session.runtime
	local result = MatchLogic.resolve(session.data, {
		matchesInRow = runtime.matchesInRow,
		matchesPlayed = runtime.matchesPlayed,
	}, rng)
	if result == nil then
		-- Nobody on the field (a reset, for example): wait and look again.
		runtime.nextMatchAt = 0
		session.player:SetAttribute("matchEndsAt", 0)
		return
	end

	Economy.grant(session.data, result.payout)
	runtime.matchesPlayed += 1
	runtime.matchesInRow += 1
	Sync.scalars(session)
	Analytics.milestone(session, "first_match")

	local plot = runtime.plot
	if plot then
		Remotes.fireAllClients("MatchResult", plot, {
			ownerUserId = session.player.UserId,
			payout = result.payout,
			hatTrick = result.hatTrick,
			stadiumTier = session.data.stadiumTier,
			goalsFor = result.goalsFor,
			goalsAgainst = result.goalsAgainst,
			fieldIds = result.fieldIds,
		})
	end
	schedule(session)
end

local function tick(session: Session.Session, seconds: number)
	local data, runtime = session.data, session.runtime
	if Boosts.nextEnd(data) > 0 and Boosts.tick(data, seconds) then
		Sync.scalars(session) -- the boost badge changes or goes away
	end
	if not data.fieldStarted or runtime.plot == nil then
		return
	end
	if runtime.nextMatchAt == 0 then
		schedule(session)
		return
	end
	if os.clock() >= runtime.nextMatchAt then
		finishMatch(session)
	end
end

function Match.start()
	assert(not started, "Match.start called twice")
	started = true
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			local seconds = now - last
			last = now
			for _, session in Session.all() do
				local ok, err = Safe.call(tick, session, seconds)
				if not ok then
					warn(
						string.format(
							"[Match] tick failed for %s: %s",
							session.player.Name,
							tostring(err)
						)
					)
				end
			end
		end
	end)
end

return Match
