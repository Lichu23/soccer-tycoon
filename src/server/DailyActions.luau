--!strict
-- Connects the daily case and the penalty kicks to the world (docs/PLAN.md, Steps 5 and 7): the
-- two remotes, the penalty pad, and the ready times the HUD icons read from player attributes.
-- The rules and the clock live in Daily; this only rolls the dice, applies the result and tells
-- the client. A kick is accepted only after the player stood on the penalty pad, for a while.

local Players = game:GetService("Players")

local Analytics = require(script.Parent.Analytics)
local Daily = require(script.Parent.Daily)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

-- After standing on the pad, kicks are accepted for this long (it renews with every kick).
local KICK_WINDOW_SECONDS = 90

local rng = Random.new()
local openUntil: { [Player]: number } = {}
local started = false

local DailyActions = {}

-- Whether the penalty pad can be used right now (also the pad's status).
function DailyActions.penaltyStatus(session: Session.Session): string
	if not Daily.unlocked(session.data) then
		return "locked"
	end
	return if Daily.kicksLeft(session.data, os.time()) > 0 then "ready" else "unavailable"
end

-- Standing on the pad opens the kick screen on the player's client.
function DailyActions.openPenalty(session: Session.Session)
	local kicks = Daily.kicksLeft(session.data, os.time())
	if kicks <= 0 then
		return
	end
	openUntil[session.player] = os.clock() + KICK_WINDOW_SECONDS
	Remotes.fireClient("Notice", session.player, { kind = "penaltyOpen", kicksLeft = kicks })
end

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

local function kick(player: Player, aim: string)
	local session = Session.get(player)
	if session == nil then
		return
	end
	local deadline = openUntil[player]
	if deadline == nil or os.clock() > deadline then
		return -- not standing at the penalty spot
	end
	local result = Daily.kick(
		session.data,
		os.time(),
		aim,
		{ miss = rng:NextNumber(), keeper = rng:NextNumber() }
	)
	if result == nil then
		return
	end
	if result.kicksLeft > 0 then
		openUntil[player] = os.clock() + KICK_WINDOW_SECONDS
	else
		openUntil[player] = nil
	end
	Sync.all(session)
	Analytics.event(session, "penalty_kick")
	Remotes.fireClient("Notice", player, { kind = "penaltyResult", result = result })
end

-- Registers the remote handlers. Call once, after Remotes.init.
function DailyActions.start()
	assert(not started, "DailyActions.start called twice")
	started = true
	Remotes.on("ClaimDaily", function(player: Player)
		-- "case" is the only thing to claim for now (the enum is checked by the remote spec).
		claimCase(player)
	end)
	Remotes.on("PenaltyKick", function(player: Player, ...: any)
		local aim = select(1, ...)
		if type(aim) == "string" then
			kick(player, aim)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		openUntil[player] = nil
	end)
end

return DailyActions
