--!strict
-- The match loop (docs/PLAN.md, Step 1). Every player with a started field plays an automatic
-- match every few seconds. At kick-off the server rolls the match (MatchLogic.plan) and tells every
-- client (MatchStarted) so they can draw it while it is played; at the whistle it pays with that roll
-- (MatchResult). The clients only draw. One loop serves every player.
--
-- Attributes on the player for the HUD bar: matchDuration (seconds) and matchEndsAt (server time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Analytics = require(script.Parent.Analytics)
local BigChanceActions = require(script.Parent.BigChanceActions)
local Boosts = require(script.Parent.Boosts)
local DevFlags = require(script.Parent.DevFlags)
local Economy = require(script.Parent.Economy)
local MatchLogic = require(script.Parent.MatchLogic)
local Remotes = require(script.Parent.Remotes)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Safe = require(script.Parent.Safe)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local TICK_SECONDS = 0.25
local FIRST_REVEAL_WAIT = 8 -- the first match waits this long at most for the first player's reveal

local random = Random.new()
local started = false

local Match = {}

local function rng(): number
	return random:NextNumber()
end

local function schedule(session: Session.Session)
	local runtime = session.runtime
	local seconds = MatchLogic.interval(session.data)
	local startedAt = Workspace:GetServerTimeNow()
	runtime.nextMatchAt = os.clock() + seconds
	session.player:SetAttribute("matchDuration", seconds)
	session.player:SetAttribute("matchEndsAt", startedAt + seconds)
	local plan = MatchLogic.plan(session.data, {
		matchesInRow = runtime.matchesInRow,
		matchesPlayed = runtime.matchesPlayed,
	}, rng)
	runtime.matchPlan = plan
	if plan and runtime.plot and session.data.flags.milestones["first_match"] == nil then
		-- The first match ever: the camera shows the pitch until it ends (IntroCinematics).
		if not runtime.firstMatchShown then
			runtime.firstMatchShown = true
			if not DevFlags.skipIntros() then
				Remotes.fireClient("Notice", session.player, { kind = "firstMatch" })
			end
		end
	end
	if plan and runtime.plot then
		Remotes.fireAllClients("MatchStarted", runtime.plot, {
			ownerUserId = session.player.UserId,
			startedAt = startedAt,
			duration = seconds,
			goalsFor = plan.goalsFor,
			goalsAgainst = plan.goalsAgainst,
			fieldIds = Roster.field(session.data),
			stadiumTier = session.data.stadiumTier,
		})
		BigChanceActions.kickoff(session) -- every few matches the match makes a Big Chance
	end
end

local function finishMatch(session: Session.Session)
	local runtime = session.runtime
	local state = {
		matchesInRow = runtime.matchesInRow,
		matchesPlayed = runtime.matchesPlayed,
	}
	-- The roll from kick-off; a match scheduled with nobody on the field rolls now.
	local plan = runtime.matchPlan or MatchLogic.plan(session.data, state, rng)
	runtime.matchPlan = nil
	local result = if plan then MatchLogic.resolve(session.data, state, plan) else nil
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
	if Analytics.milestone(session, "first_match") then
		-- The first match opens the training ground: the pads and the guide need the new flag.
		Sync.all(session)
	end

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
	if Boosts.tick(data, seconds) then
		Sync.scalars(session) -- the boost badge changes or goes away
	end
	if not data.fieldStarted or runtime.plot == nil then
		return
	end
	if runtime.nextMatchAt == 0 then
		-- The first match waits until the first player's reveal has been watched (or a few seconds),
		-- so the reveal comes first and then the match.
		if data.flags.milestones["first_match"] == nil and #data.pendingReveals > 0 then
			runtime.firstRevealWait += seconds
			if runtime.firstRevealWait < FIRST_REVEAL_WAIT then
				return
			end
		end
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
