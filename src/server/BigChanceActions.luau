--!strict
-- Big Chance on the server (shared/BigChance, Config.BigChance): counts the matches of each player,
-- offers a chance at a kick-off every few matches (its spot and its reward set then), judges the aim
-- and the shot on the server clock and pays a goal. The client only draws the state it gets as player
-- attributes; a chance left alone costs nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Analytics = require(script.Parent.Analytics)
local BigChance = require(ReplicatedStorage.Shared.BigChance)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local MatchLogic = require(script.Parent.MatchLogic)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local rng = Random.new()
local started = false
local states: { [Player]: BigChance.State } = {}
local matchesLeft: { [Player]: number } = {} -- kick-offs until the next chance
local revisions: { [Player]: number } = {}
local rewards: { [Player]: number } = {} -- what a goal of the chance on offer pays

local BigChanceActions = {}

local function stateOf(player: Player): BigChance.State
	local state = states[player]
	if state == nil then
		state = BigChance.new()
		states[player] = state
	end
	return state
end

-- The chance as player attributes. `bigChanceRev` changes on every publish, so the client redraws
-- even when only the time changed.
local function publish(player: Player, state: BigChance.State, bonus: number)
	revisions[player] = (revisions[player] or 0) + 1
	player:SetAttribute("bigChanceState", state.phase)
	player:SetAttribute("bigChanceSpot", state.spot)
	player:SetAttribute("bigChanceEndsAt", state.endsAt)
	player:SetAttribute("bigChanceStageAt", state.stageAt)
	player:SetAttribute("bigChanceAimX", state.aimX)
	player:SetAttribute("bigChanceAimY", state.aimY)
	player:SetAttribute("bigChanceHoldAt", state.holdAt)
	player:SetAttribute("bigChancePower", state.power)
	player:SetAttribute("bigChanceOutcome", state.outcome)
	player:SetAttribute("bigChanceReward", rewards[player] or 0)
	player:SetAttribute("bigChanceBonus", bonus)
	player:SetAttribute("bigChanceRev", revisions[player])
end

-- Called at every kick-off on a player's pitch: once enough matches have gone by, a chance is offered.
function BigChanceActions.kickoff(session: Session.Session)
	local player = session.player
	if not BigChance.unlocked(session.data.stadiumTier) then
		matchesLeft[player] = nil -- the first chance comes `firstMatches` after the tier opens
		return
	end
	local left = (matchesLeft[player] or Config.BigChance.firstMatches) - 1
	if left > 0 then
		matchesLeft[player] = left
		return
	end
	local state = stateOf(player)
	if
		BigChance.offer(state, Workspace:GetServerTimeNow(), BigChance.pickSpot(rng:NextNumber()))
	then
		matchesLeft[player] = BigChance.gap(rng:NextNumber())
		local runtime = session.runtime
		local payout = MatchLogic.matchPayout(session.data, {
			matchesInRow = runtime.matchesInRow,
			matchesPlayed = runtime.matchesPlayed,
		})
		rewards[player] = payout * Config.BigChance.rewardMatches
		Analytics.event(session, "big_chance_offer")
		publish(player, state, 0)
	else
		matchesLeft[player] = 1 -- one is still going: try again at the next kick-off
	end
end

local function tap(player: Player, ...: any)
	local action, stamp = ...
	local session = Session.get(player)
	local state = states[player]
	if session == nil or state == nil or type(stamp) ~= "number" then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if action == "take" then
		if BigChance.take(state, now) then
			publish(player, state, 0)
		end
		return
	end
	-- "shoot": the tap locks the aim, then the next one strikes.
	if BigChance.lock(state, now, stamp) then
		publish(player, state, 0)
		return
	end
	local outcome = BigChance.strike(state, now, stamp)
	if outcome == nil then
		if BigChance.normalize(state, now) then
			publish(player, state, 0) -- the clock ran out: the client shows the keeper smother it
		end
		return
	end
	local bonus = 0
	if outcome == "goal" then
		bonus = Economy.grant(session.data, rewards[player] or 0)
		Sync.scalars(session)
		Analytics.event(session, "big_chance_goal")
	end
	publish(player, state, bonus)
end

-- Registers the remote handler. Call once, after Remotes.init.
function BigChanceActions.start()
	assert(not started, "BigChanceActions.start called twice")
	started = true
	Remotes.on("BigChanceTap", tap)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		matchesLeft[player] = nil
		revisions[player] = nil
		rewards[player] = nil
	end)
end

return BigChanceActions
