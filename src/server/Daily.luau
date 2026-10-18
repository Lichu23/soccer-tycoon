--!strict
-- The daily return (docs/PLAN.md, Steps 1, 3 and 7): the free case and the three penalty kicks.
-- Both come back 20 hours after they were used, judged by the server clock (`now` is os.time()).
-- There is no streak and nothing is lost by skipping a day. The kick result is rolled here from
-- numbers the caller passes in, so the rules are unit tested with fixed rolls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Progress = require(ReplicatedStorage.Shared.Progress)
local RemoteSpec = require(ReplicatedStorage.Shared.RemoteSpec)
local Roster = require(ReplicatedStorage.Shared.Roster)

type Profile = ProfileSchema.Profile

export type CasePrize = { kind: "cash", amount: number } | { kind: "boost", seconds: number }

export type KickResult = {
	aim: string,
	keeper: string, -- the zone the keeper dived to
	goal: boolean,
	wide: boolean, -- the kick missed the target on its own (not a save)
	kicksLeft: number,
	goals: number,
	boostSeconds: number, -- penalty boost seconds this kick added
}

local Daily = {}

function Daily.unlocked(data: Profile): boolean
	return data.stadiumTier >= Config.Daily.unlockTier
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

-- Cash worth `caseCashMinutes` of normal income at the current levels (no boosts, no momentum).
function Daily.caseCash(data: Profile): number
	local fieldIncomes = Roster.fieldIncomes(data)
	if #fieldIncomes == 0 then
		return 0
	end
	local base = Formulas.basePayout({
		fieldIncomes = fieldIncomes,
		cashUpgradeLevel = data.storeLevels.cashPerMatch,
		season = data.season.number,
	})
	local matches = Config.Daily.caseCashMinutes * 60 / Progress.matchSeconds(data)
	return math.max(1, math.floor(base * matches))
end

-- Claims the free case. `roll` is a random number in [0, 1) that picks cash or the boost.
-- Returns the prize, or nil and why it was refused ("locked" or "notReady").
function Daily.claimCase(data: Profile, now: number, roll: number): (CasePrize?, string?)
	if not Daily.unlocked(data) then
		return nil, "locked"
	end
	if now < Daily.caseReadyAt(data) then
		return nil, "notReady"
	end
	data.daily.caseClaimedAt = now
	local cash = Daily.caseCash(data)
	if cash <= 0 or roll < Config.Daily.caseBoostChance then
		Boosts.addDouble(data, Config.Daily.caseBoostSeconds)
		return { kind = "boost", seconds = Config.Daily.caseBoostSeconds }, nil
	end
	return { kind = "cash", amount = Economy.grant(data, cash) }, nil
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

local function isZone(aim: string): boolean
	return table.find(RemoteSpec.aimZones, aim) ~= nil
end

-- One kick. `rolls.miss` decides whether the kick goes wide, `rolls.keeper` picks the zone the
-- keeper dives to (both in [0, 1)). The boost is topped up goal by goal, so the total matches the
-- plan (3 goals 10 min, 2 goals 5 min, 1 goal 3 min) even when the player leaves after one or two
-- kicks. Returns the result, or nil and why it was refused ("locked", "badAim" or "notReady").
function Daily.kick(
	data: Profile,
	now: number,
	aim: string,
	rolls: { miss: number, keeper: number }
): (KickResult?, string?)
	if not Daily.unlocked(data) then
		return nil, "locked"
	end
	if not isZone(aim) then
		return nil, "badAim"
	end
	if Daily.kicksLeft(data, now) <= 0 then
		return nil, "notReady"
	end
	local daily = data.daily
	if daily.kicksUsed == 0 then
		daily.penaltyBatchAt = now
	end
	daily.kicksUsed += 1

	local zones = RemoteSpec.aimZones
	local keeper = zones[math.clamp(math.floor(rolls.keeper * #zones) + 1, 1, #zones)]
	local wide = rolls.miss < (Config.Daily.zoneMissChance[aim] or 0)
	local goal = not wide and keeper ~= aim

	local added = 0
	if goal then
		local before = Config.Daily.penaltyBoostSeconds[daily.goals] or 0
		daily.goals += 1
		added = (Config.Daily.penaltyBoostSeconds[daily.goals] or 0) - before
		Boosts.addPenalty(data, added)
	end
	local result: KickResult = {
		aim = aim,
		keeper = keeper,
		goal = goal,
		wide = wide,
		kicksLeft = Config.Daily.penaltyKicks - daily.kicksUsed,
		goals = daily.goals,
		boostSeconds = added,
	}
	return result, nil
end

return Daily
