--!strict
-- What one finished match pays and shows (docs/PLAN.md, Step 1). The match is always a win and
-- the opponent is cosmetic, so the goals on the scoreboard are derived from the payout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Roster = require(ReplicatedStorage.Shared.Roster)

export type Result = {
	payout: number,
	hatTrick: boolean,
	goalsFor: number,
	goalsAgainst: number,
	fieldIds: { string },
}

export type State = {
	matchesInRow: number, -- matches this session before this one (momentum)
	matchesPlayed: number, -- matches this session before this one
}

local MatchLogic = {}

-- Seconds until the next match. The very first match a player ever plays is short (Step 2).
function MatchLogic.interval(data: ProfileSchema.Profile): number
	if data.flags.milestones["first_match"] == nil then
		return Config.Match.firstMatchSeconds
	end
	return Progress.matchSeconds(data)
end

-- Goals for the scoreboard from the payout: about one more goal for every ten times the
-- payout, a hat-trick always shows at least 3, and the opponent always scores fewer.
function MatchLogic.goals(payout: number, hatTrick: boolean): (number, number)
	local goalsFor = math.clamp(1 + math.floor(math.log10(math.max(payout, 1))), 1, 5)
	if hatTrick then
		goalsFor = math.max(goalsFor, 3)
	end
	local goalsAgainst = payout % goalsFor -- always below goalsFor
	return goalsFor, goalsAgainst
end

-- Resolves one match. `rng` returns a number from 0 to 1. Returns nil when nobody is on the
-- field. Rolling a hat-trick (scripted or natural) marks the first hat-trick as done.
function MatchLogic.resolve(data: ProfileSchema.Profile, state: State, rng: () -> number): Result?
	local fieldIds = Roster.field(data)
	if #fieldIds == 0 then
		return nil
	end

	local scripted = not data.flags.firstHatTrickDone
		and state.matchesPlayed + 1 == Config.Match.scriptedHatTrickMatch
	local hatTrick = scripted or rng() < Progress.hatTrickChance(data)
	if hatTrick then
		data.flags.firstHatTrickDone = true
	end

	-- A banked boosted match (bought with Robux) doubles this match and is used up. It stacks with the
	-- timed boosts inside the x4 cap.
	local boosts = Boosts.active(data)
	if data.boosts.bankedMatches > 0 then
		data.boosts.bankedMatches -= 1
		table.insert(boosts, Config.Boost.matchMultiplier)
	end

	local payout = Formulas.payout({
		fieldIncomes = Roster.fieldIncomes(data),
		cashUpgradeLevel = data.storeLevels.cashPerMatch,
		season = data.season.number,
		momentumMatches = state.matchesInRow,
		boosts = boosts,
		hatTrick = hatTrick,
	})
	local goalsFor, goalsAgainst = MatchLogic.goals(payout, hatTrick)
	return {
		payout = payout,
		hatTrick = hatTrick,
		goalsFor = goalsFor,
		goalsAgainst = goalsAgainst,
		fieldIds = fieldIds,
	}
end

return MatchLogic
