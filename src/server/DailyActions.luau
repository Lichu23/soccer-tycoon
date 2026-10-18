--!strict
-- Connects the daily case and the penalty kicks to the client (docs/PLAN.md, Steps 5 and 7): the
-- two remotes. The rules and the clock live in Daily; this only rolls the dice, applies the result
-- and tells the client. Both are opened from the HUD icons: nobody has to stand anywhere.

local Analytics = require(script.Parent.Analytics)
local Daily = require(script.Parent.Daily)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Sync = require(script.Parent.Sync)

local rng = Random.new()
local started = false

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

local function kick(player: Player, aim: string)
	local session = Session.get(player)
	if session == nil then
		return
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
end

return DailyActions
