--!strict
-- Connects the daily case and the penalty kicks to the client (docs/PLAN.md, Steps 5 and 7). The
-- rules and the clock live in Daily; the kicks are played like the breakaway's shot (shared/Penalty):
-- this keeps each player's visit to the spot, judges the tap and the release on the server clock,
-- counts the kick and tells the client. Both are opened from the HUD: nobody has to stand anywhere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Analytics = require(script.Parent.Analytics)
local Daily = require(script.Parent.Daily)
local Penalty = require(ReplicatedStorage.Shared.Penalty)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local rng = Random.new()
local started = false
local visits: { [Player]: Penalty.State } = {} -- the penalty kicks a player is taking
local revisions: { [Player]: number } = {}

local DailyActions = {}

local function claimCase(player: Player)
	local session = Session.get(player)
	if session == nil then
		return
	end
	local prize = Daily.claimCase(session.data, os.time(), rng:NextNumber())
	if prize == nil then
		return
	end
	Sync.all(session)
	Analytics.event(session, "daily_case")
	Remotes.fireClient("Notice", player, { kind = "caseResult", prize = prize })
end

-- The visit as player attributes, so the client draws the reticle, the meter and the film the server
-- judged. `penaltyRev` changes on every publish, so the client knows its start was answered.
local function publish(player: Player, state: Penalty.State)
	revisions[player] = (revisions[player] or 0) + 1
	player:SetAttribute("penaltyState", state.phase)
	player:SetAttribute("penaltySeed", state.seed)
	player:SetAttribute("penaltyKick", state.kick)
	player:SetAttribute("penaltyStageAt", state.stageAt)
	player:SetAttribute("penaltyAimX", state.aimX)
	player:SetAttribute("penaltyAimY", state.aimY)
	player:SetAttribute("penaltyHoldAt", state.holdAt)
	player:SetAttribute("penaltyPower", state.power)
	player:SetAttribute("penaltyOutcome", state.outcome)
	player:SetAttribute("penaltyLeft", state.kicksLeft)
	player:SetAttribute("penaltyRev", revisions[player])
end

-- The screen opened: a new visit with the kicks left today, unless a kick's film is still playing
-- (the screen was closed and opened again), which goes on. Aiming starts over: nothing is used up
-- before the release.
local function start(player: Player)
	local session = Session.get(player)
	if session == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local state = visits[player]
	if state then
		Penalty.normalize(state, now)
	end
	if state == nil or state.phase ~= "shot" then
		state = Penalty.new(now, Daily.kicksLeft(session.data, os.time()))
		visits[player] = state
	end
	publish(player, state)
end

-- The visit for an input of `player`, caught up to now, or nil when it does not count.
local function input(player: Player, stamp: any): (Session.Session?, Penalty.State?, number)
	local session = Session.get(player)
	local state = visits[player]
	if session == nil or state == nil or type(stamp) ~= "number" then
		return nil, nil, 0
	end
	local now = Workspace:GetServerTimeNow()
	Penalty.normalize(state, now)
	return session, state, now
end

-- A tap: locks the reticle, or begins the power hold.
local function tap(player: Player, ...: any)
	local stamp = select(1, ...)
	local _, state, now = input(player, stamp)
	if state == nil then
		return
	end
	if not Penalty.lock(state, now, stamp) then
		Penalty.hold(state, now, stamp)
	end
	publish(player, state)
end

-- The release of the power hold: the shot, judged and counted at once (the film shows it afterwards).
local function release(player: Player, ...: any)
	local stamp = select(1, ...)
	local session, state, now = input(player, stamp)
	if session == nil or state == nil then
		return
	end
	if Daily.kicksLeft(session.data, os.time()) <= 0 then
		-- The day's kicks were used up elsewhere (another server): nothing to shoot.
		state.kicksLeft = 0
		state.phase = "done"
		publish(player, state)
		return
	end
	if not Penalty.release(state, now, stamp) then
		publish(player, state)
		return
	end
	local result = Daily.recordKick(session.data, os.time(), state.outcome == "goal")
	if result == nil then
		return
	end
	state.kicksLeft = result.kicksLeft
	Sync.all(session)
	Analytics.event(session, "penalty_kick")
	publish(player, state)
	Remotes.fireClient("Notice", player, {
		kind = "penaltyResult",
		result = {
			outcome = state.outcome,
			goal = result.goal,
			goals = result.goals,
			kicksLeft = result.kicksLeft,
			boostSeconds = result.boostSeconds,
		},
	})
end

-- Registers the remote handlers. Call once, after Remotes.init.
function DailyActions.start()
	assert(not started, "DailyActions.start called twice")
	started = true
	Remotes.on("ClaimDaily", function(player: Player)
		-- "case" is the only thing to claim for now (the enum is checked by the remote spec).
		claimCase(player)
	end)
	Remotes.on("PenaltyStart", start)
	Remotes.on("PenaltyTap", tap)
	Remotes.on("PenaltyRelease", release)
	Players.PlayerRemoving:Connect(function(player)
		visits[player] = nil
		revisions[player] = nil
	end)
end

return DailyActions
