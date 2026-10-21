--!strict
-- What one match pays and shows (docs/PLAN.md, Step 1). The match is always a win and the opponent
-- is cosmetic. The hat-trick and the score are rolled at kick-off (plan) so the clients can draw the
-- match while it is played; the cash is paid at the whistle (resolve).

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

export type Plan = {
	hatTrick: boolean,
	goalsFor: number,
	goalsAgainst: number,
}

-- The cash the match would pay now (a banked boosted match counts, it is used up in resolve).
local function payoutNow(data: ProfileSchema.Profile, state: State, hatTrick: boolean): number
	-- A banked boosted match (bought with Robux) doubles this match. It stacks with the timed boosts
	-- inside the x4 cap.
	local boosts = Boosts.active(data)
	if data.boosts.bankedMatches > 0 then
		table.insert(boosts, Config.Boost.matchMultiplier)
	end
	return Formulas.payout({
		fieldIncomes = Roster.fieldIncomes(data),
		stadiumTier = data.stadiumTier,
		season = data.season.number,
		momentumMatches = state.matchesInRow,
		boosts = boosts,
		hatTrick = hatTrick,
	})
end

-- Rolls the coming match at kick-off, so every client can draw it while it is played: whether it is a
-- hat-trick, and the score, from the payout as it stands now (the payout itself is worked out at the
-- end, so a purchase during the match still counts). `rng` returns a number from 0 to 1. Changes
-- nothing. Returns nil when nobody is on the field.
function MatchLogic.plan(data: ProfileSchema.Profile, state: State, rng: () -> number): Plan?
	if #Roster.field(data) == 0 then
		return nil
	end
	local scripted = not data.flags.firstHatTrickDone
		and state.matchesPlayed + 1 == Config.Match.scriptedHatTrickMatch
	local hatTrick = scripted or rng() < Progress.hatTrickChance(data)
	local goalsFor, goalsAgainst = MatchLogic.goals(payoutNow(data, state, hatTrick), hatTrick)
	return { hatTrick = hatTrick, goalsFor = goalsFor, goalsAgainst = goalsAgainst }
end

-- Resolves one match at the whistle with the plan rolled at kick-off: pays from the field and the
-- upgrades as they are now, uses up a banked boosted match, and keeps the score that was drawn.
-- Returns nil when nobody is on the field. A hat-trick (scripted or natural) marks the first hat-trick
-- as done.
function MatchLogic.resolve(data: ProfileSchema.Profile, state: State, plan: Plan): Result?
	local fieldIds = Roster.field(data)
	if #fieldIds == 0 then
		return nil
	end
	if plan.hatTrick then
		data.flags.firstHatTrickDone = true
	end
	local payout = payoutNow(data, state, plan.hatTrick)
	if data.boosts.bankedMatches > 0 then
		data.boosts.bankedMatches -= 1
	end
	return {
		payout = payout,
		hatTrick = plan.hatTrick,
		goalsFor = plan.goalsFor,
		goalsAgainst = plan.goalsAgainst,
		fieldIds = fieldIds,
	}
end

return MatchLogic
