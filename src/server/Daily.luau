--!strict
-- The daily return (docs/PLAN.md, Steps 1, 3 and 7): the free case and the three penalty kicks.
-- Both come back 20 hours after they were used, judged by the server clock (`now` is os.time()).
-- There is no streak and nothing is lost by skipping a day. A kick is played and judged in
-- shared/Penalty; this only counts it and pays the boost, so the rules are unit tested.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Roster = require(ReplicatedStorage.Shared.Roster)

type Profile = ProfileSchema.Profile

export type CasePrize =
	{ id: string, kind: "cash", amount: number }
	| { id: string, kind: "boost", seconds: number }
	| { id: string, kind: "tp", amount: number }

export type KickResult = {
	goal: boolean,
	kicksLeft: number,
	goals: number,
	boostSeconds: number, -- penalty boost seconds this kick added
}

local Daily = {}

-- The free case and the penalty kicks open with the first player bought.
function Daily.unlocked(data: Profile): boolean
	return Roster.ownedCount(data) >= 1
end

-- Starts a new batch of kicks once 20 hours have passed since the first kick of the old one.
local function refreshBatch(data: Profile, now: number)
	local daily = data.daily
	if daily.kicksUsed > 0 and now - daily.penaltyBatchAt >= Config.Daily.cooldownSeconds then
		daily.kicksUsed = 0
		daily.goals = 0
		daily.penaltyBatchAt = 0
	end
end

-- The free case ------------------------------------------------------------------------------

-- os.time() when the case can be claimed (0 or in the past = ready now).
function Daily.caseReadyAt(data: Profile): number
	if data.daily.caseClaimedAt <= 0 then
		return 0
	end
	return data.daily.caseClaimedAt + Config.Daily.cooldownSeconds
end

function Daily.caseReady(data: Profile, now: number): boolean
	return Daily.unlocked(data) and now >= Daily.caseReadyAt(data)
end

-- Cash worth `minutes` of normal income at the current levels (no boosts, no momentum).
function Daily.caseCash(data: Profile, minutes: number): number
	local fieldIncomes = Roster.fieldIncomes(data)
	if #fieldIncomes == 0 then
		return 0
	end
	local base = Formulas.basePayout({
		fieldIncomes = fieldIncomes,
		stadiumTier = data.stadiumTier,
		season = data.season.number,
	})
	local matches = minutes * 60 / Progress.matchSeconds(data)
	return math.max(1, math.floor(base * matches))
end

-- The reward a roll in [0, 1) picks, by the weights of Config.Daily.caseRewards.
function Daily.pickReward(roll: number): Config.CaseReward
	local rewards = Config.Daily.caseRewards
	local total = 0
	for _, reward in rewards do
		total += reward.weight
	end
	local point = math.clamp(roll, 0, 0.999999) * total
	for _, reward in rewards do
		point -= reward.weight
		if point < 0 then
			return reward
		end
	end
	return rewards[#rewards]
end

-- Claims the free case. `roll` is a random number in [0, 1) that picks the reward. Returns the
-- prize (with the reward id the roulette lands on), or nil and why it was refused ("locked" or
-- "notReady"). A cash reward with no income yet turns into the first boost instead.
function Daily.claimCase(data: Profile, now: number, roll: number): (CasePrize?, string?)
	if not Daily.unlocked(data) then
		return nil, "locked"
	end
	if now < Daily.caseReadyAt(data) then
		return nil, "notReady"
	end
	data.daily.caseClaimedAt = now
	local reward = Daily.pickReward(roll)
	if reward.kind == "cash" then
		local cash = Daily.caseCash(data, reward.minutes or 0)
		if cash > 0 then
			return { id = reward.id, kind = "cash", amount = Economy.grant(data, cash) }, nil
		end
		reward = Config.Daily.caseRewards[2]
	end
	if reward.kind == "tp" then
		return { id = reward.id, kind = "tp", amount = Economy.grantTp(data, reward.tp or 0) }, nil
	end
	local seconds = reward.seconds or 0
	Boosts.addDouble(data, seconds)
	return { id = reward.id, kind = "boost", seconds = seconds }, nil
end

-- The penalty kicks --------------------------------------------------------------------------

-- Kicks left now (a batch that is 20 hours old counts as a new one).
function Daily.kicksLeft(data: Profile, now: number): number
	if not Daily.unlocked(data) then
		return 0
	end
	refreshBatch(data, now)
	return Config.Daily.penaltyKicks - data.daily.kicksUsed
end

-- os.time() when kicks are available again (0 = available now).
function Daily.penaltyReadyAt(data: Profile, now: number): number
	if Daily.kicksLeft(data, now) > 0 then
		return 0
	end
	return data.daily.penaltyBatchAt + Config.Daily.cooldownSeconds
end

-- Counts one kick, a goal or not (shared/Penalty judged it). The boost is topped up goal by goal,
-- so the total matches the plan (3 goals 10 min, 2 goals 5 min, 1 goal 3 min) even when the player
-- leaves after one or two kicks. Returns the result, or nil and why it was refused ("locked" or
-- "notReady").
function Daily.recordKick(data: Profile, now: number, goal: boolean): (KickResult?, string?)
	if not Daily.unlocked(data) then
		return nil, "locked"
	end
	if Daily.kicksLeft(data, now) <= 0 then
		return nil, "notReady"
	end
	local daily = data.daily
	if daily.kicksUsed == 0 then
		daily.penaltyBatchAt = now
	end
	daily.kicksUsed += 1

	local added = 0
	if goal then
		local before = Config.Daily.penaltyBoostSeconds[daily.goals] or 0
		daily.goals += 1
		added = (Config.Daily.penaltyBoostSeconds[daily.goals] or 0) - before
		Boosts.addPenalty(data, added)
	end
	local result: KickResult = {
		goal = goal,
		kicksLeft = Config.Daily.penaltyKicks - daily.kicksUsed,
		goals = daily.goals,
		boostSeconds = added,
	}
	return result, nil
end

return Daily
