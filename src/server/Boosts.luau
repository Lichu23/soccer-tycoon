--!strict
-- Timed income boosts: the stadium upgrade boost (x2), the free daily case boost (also x2, same
-- timer), the daily penalty boost (x1.5) and the x2 cash and x2 TP boosts bought with Robux. They
-- count only while the player is online. A new free x2 boost keeps the longer of the two timers
-- instead of adding up; a bought one adds its time. Different cash boosts multiply, capped by
-- Formulas.boostMultiplier (Step 1). The TP boost doubles the TP of the Training Gym.

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
	if data.boosts.cashBoostLeft > 0 then
		table.insert(list, Config.Boost.paidMultiplier)
	end
	return list
end

-- The multiplier of the TP earned in the Training Gym right now.
function Boosts.tpMultiplier(data: Profile): number
	return if data.boosts.tpBoostLeft > 0 then Config.Boost.paidMultiplier else 1
end

-- Seconds until the next active cash boost ends, or 0 when none is active.
function Boosts.nextEnd(data: Profile): number
	local soonest = 0
	for _, left in
		{ data.boosts.stadiumBoostLeft, data.boosts.penaltyBoostLeft, data.boosts.cashBoostLeft }
	do
		if left > 0 and (soonest == 0 or left < soonest) then
			soonest = left
		end
	end
	return soonest
end

-- Whether another bought boost fits: each timer it adds to stays within Config.Boost.paidMaxSeconds.
function Boosts.canAddPaid(data: Profile, cash: boolean, tp: boolean): boolean
	local max = Config.Boost.paidMaxSeconds
	return not (cash and data.boosts.cashBoostLeft > max - Config.Boost.paidCashSeconds)
		and not (tp and data.boosts.tpBoostLeft > max - Config.Boost.paidTpSeconds)
end

-- A bought x2 boost: adds its time to the cash timer, the TP timer or both. Paid time is never cut,
-- so the maximum is only checked before the prompt (canAddPaid).
function Boosts.addPaid(data: Profile, cash: boolean, tp: boolean)
	if cash then
		data.boosts.cashBoostLeft += Config.Boost.paidCashSeconds
	end
	if tp then
		data.boosts.tpBoostLeft += Config.Boost.paidTpSeconds
	end
end

-- A x2 cash or TP boost won in a Robux case: adds its time to the bought cash or TP timer, never cut
-- (it was paid for, so the paidMaxSeconds cap of the pads does not apply).
function Boosts.addCaseBoost(data: Profile, kind: "cash" | "tp", seconds: number)
	if kind == "tp" then
		data.boosts.tpBoostLeft += seconds
	else
		data.boosts.cashBoostLeft += seconds
	end
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
	local boosts = data.boosts
	local ended = false
	for _, key in { "stadiumBoostLeft", "penaltyBoostLeft", "cashBoostLeft", "tpBoostLeft" } do
		local before = (boosts :: any)[key]
		local after = math.max(0, before - seconds);
		(boosts :: any)[key] = after
		ended = ended or (before > 0 and after <= 0)
	end
	return ended
end

return Boosts
