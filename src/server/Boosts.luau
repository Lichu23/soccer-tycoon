--!strict
-- Timed income boosts: the stadium upgrade boost (x2), the free daily case boost (also x2, same
-- timer) and the daily penalty boost (x1.5). They count only while the player is online. A new x2
-- boost keeps the longer of the two timers instead of adding up. Different boosts multiply,
-- capped by Formulas.boostMultiplier (Step 1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Profile = ProfileSchema.Profile

local Boosts = {}

-- The multipliers that apply to the next match (combine them with Formulas.boostMultiplier).
function Boosts.active(data: Profile): { number }
	local list = {}
	if data.boosts.stadiumBoostLeft > 0 then
		table.insert(list, Config.Boost.stadiumMultiplier)
	end
	if data.boosts.penaltyBoostLeft > 0 then
		table.insert(list, Config.Daily.penaltyMultiplier)
	end
	return list
end

-- Seconds until the next active boost ends, or 0 when none is active.
function Boosts.nextEnd(data: Profile): number
	local stadium, penalty = data.boosts.stadiumBoostLeft, data.boosts.penaltyBoostLeft
	if stadium > 0 and penalty > 0 then
		return math.min(stadium, penalty)
	end
	return math.max(stadium, penalty)
end

function Boosts.startStadium(data: Profile)
	data.boosts.stadiumBoostLeft = Config.Boost.stadiumSeconds
end

-- A x2 boost from the free case: keeps the longer of the running boost and the new one.
function Boosts.addDouble(data: Profile, seconds: number)
	data.boosts.stadiumBoostLeft = math.max(data.boosts.stadiumBoostLeft, seconds)
end

-- Penalty boost seconds add up within one batch of kicks (each goal tops up the total).
function Boosts.addPenalty(data: Profile, seconds: number)
	data.boosts.penaltyBoostLeft += seconds
end

-- Counts down the connected seconds. True when a boost ended during this step.
function Boosts.tick(data: Profile, seconds: number): boolean
	local stadium, penalty = data.boosts.stadiumBoostLeft, data.boosts.penaltyBoostLeft
	data.boosts.stadiumBoostLeft = math.max(0, stadium - seconds)
	data.boosts.penaltyBoostLeft = math.max(0, penalty - seconds)
	return (stadium > 0 and data.boosts.stadiumBoostLeft <= 0)
		or (penalty > 0 and data.boosts.penaltyBoostLeft <= 0)
end

return Boosts
