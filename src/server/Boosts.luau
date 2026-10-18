--!strict
-- Timed income boosts. Only the stadium upgrade boost exists in the first slice. It counts only
-- while the player is online and a new upgrade resets it, it does not add up (Step 1).

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
	return list
end

function Boosts.startStadium(data: Profile)
	data.boosts.stadiumBoostLeft = Config.Boost.stadiumSeconds
end

-- Counts down the connected seconds.
function Boosts.tick(data: Profile, seconds: number)
	data.boosts.stadiumBoostLeft = math.max(0, data.boosts.stadiumBoostLeft - seconds)
end

return Boosts
