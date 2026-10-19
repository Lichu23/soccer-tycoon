--!strict
-- The New Season reset (docs/PLAN.md, Steps 1 and 6), as one step on the profile so a crash before
-- the save loses the reset, never progress. Pure on the profile, so it is unit tested.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)
local Season = require(ReplicatedStorage.Shared.Season)

export type Result = { season: number, trophy: string, headStart: { string } }

local NewSeason = {}

-- Resets cash, floors 1 to 3, their players, Store levels, TP and the stadium to the template, then
-- gives the head-start floors at level 0. Legends, cosmetics, trials, receipts, daily state, flags
-- and the collection record stay. `seasonSeen` (when given) is the season number the client saw, so
-- a double tap cannot reset twice. Returns the new season and the trophy of the finished one.
function NewSeason.start(data: ProfileSchema.Profile, seasonSeen: number?): (Result?, string?)
	local ok, reason = Season.canStart(data)
	if not ok then
		return nil, reason
	end
	local finished = data.season.number
	if seasonSeen ~= nil and seasonSeen ~= finished then
		return nil, "stale"
	end

	local template = ProfileSchema.newProfile()
	for id in data.players do
		local def = Config.PlayersById[id]
		if def == nil or def.floor < Config.LegendFloor then
			data.players[id] = nil
		end
	end
	local headStart = Season.headStartPlayers(finished)
	for _, id in headStart do
		Roster.add(data, id)
	end

	data.cash = template.cash
	data.tp = template.tp
	data.staminaLeft = template.staminaLeft
	data.stadiumTier = template.stadiumTier
	data.storeLevels = template.storeLevels
	data.boosts.stadiumBoostLeft = 0
	data.fieldStarted = next(data.players) ~= nil
	data.season.number = finished + 1
	return {
		season = data.season.number,
		trophy = Season.trophyName(finished),
		headStart = headStart,
	},
		nil
end

return NewSeason
