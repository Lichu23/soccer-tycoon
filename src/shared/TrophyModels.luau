--!strict
-- The trophy models made in Studio from the trophy drawings (ReplicatedStorage.Trophies, saved in the
-- place: one per tier, standing on their pivot, about 3.5 studs tall). The trophy case shows them on its
-- pedestals (server/TrophyCase) and the New Season screens show the one being played for
-- (client/SeasonUi). Replicated because the client draws them; they hold no scripts or secrets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrophyModels = {}

-- The model of each trophy tier, in Season.trophyName order; the last one stands for every World Cup
-- after it.
TrophyModels.NAMES = { "StreetCup", "CityCup", "NationalCup", "ContinentalCup", "WorldCup" }

-- The tier (1 to 5) of the trophy won by finishing season `finished`.
function TrophyModels.tier(finished: number): number
	return math.clamp(finished, 1, #TrophyModels.NAMES)
end

-- A fresh copy of the model of `tier`, or nil when the place has none.
function TrophyModels.clone(tier: number): Model?
	local folder = ReplicatedStorage:FindFirstChild("Trophies")
	local name = TrophyModels.NAMES[tier]
	local source = if folder and name then folder:FindFirstChild(name) else nil
	if source == nil or not source:IsA("Model") then
		return nil
	end
	return source:Clone()
end

return TrophyModels
