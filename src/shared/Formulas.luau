--!strict
-- Pure game math (docs/PLAN.md, Steps 1 and 3). No Roblox objects, no state, so the server
-- and the client use the same numbers and the unit tests can check them.

local Config = require(script.Parent.Config)

type Rarity = Config.Rarity
type StoreUpgradeId = Config.StoreUpgradeId

local Formulas = {}

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function clamp(value: number, low: number, high: number): number
	return math.max(low, math.min(high, value))
end

-- Players ----------------------------------------------------------------------------------

-- +10% income per star, up to the star cap.
function Formulas.starMultiplier(stars: number): number
	return 1 + clamp(stars, 0, Config.Stars.maxStars) * Config.Stars.bonusPerStar
end

-- +3% income per training level.
function Formulas.levelMultiplier(level: number): number
	return 1 + math.max(level, 0) * Config.Training.bonusPerLevel
end

-- Cash per match for one player on the field, before upgrades, boosts and season.
function Formulas.playerIncome(baseIncome: number, level: number, stars: number): number
	return baseIncome * Formulas.levelMultiplier(level) * Formulas.starMultiplier(stars)
end

function Formulas.levelCap(rarity: Rarity): number
	return Config.Rarities[rarity].levelCap
end

-- Training points to buy level `level` (1 to the cap): base x level x rarity factor.
function Formulas.levelCost(rarity: Rarity, level: number): number
	if level < 1 or level > Formulas.levelCap(rarity) or level ~= math.floor(level) then
		error(string.format("level %s is out of range for %s", tostring(level), rarity), 2)
	end
	return Config.Training.levelCostBase * level * Config.Rarities[rarity].costFactor
end

-- Training points to go from level 0 to `toLevel`.
function Formulas.totalLevelCost(rarity: Rarity, toLevel: number): number
	local total = 0
	for level = 1, toLevel do
		total += Formulas.levelCost(rarity, level)
	end
	return total
end

-- Seasons ----------------------------------------------------------------------------------

-- Permanent income multiplier: season 1 = x1, season 2 = x1.5, season 3 = x2.0.
function Formulas.seasonMultiplier(season: number): number
	return 1 + (math.max(season, 1) - 1) * Config.Season.bonusPerSeason
end

-- Floors a new season starts with already owned. Floor 3 is never granted, because
-- completing it opens floor 4 and the next New Season.
function Formulas.headStartFloors(season: number): number
	if season <= 1 then
		return 0
	elseif season == 2 then
		return 1
	end
	return 2
end

-- Matches -----------------------------------------------------------------------------------

-- +1% per match in a row this session, capped.
function Formulas.momentumMultiplier(matchesInRow: number): number
	return 1 + clamp(matchesInRow * Config.Match.momentumPerMatch, 0, Config.Match.momentumCap)
end

-- Timed and banked boosts multiply together but never pass the total cap.
function Formulas.boostMultiplier(boosts: { number }): number
	local product = 1
	for _, multiplier in boosts do
		product *= multiplier
	end
	return math.min(product, Config.Boost.totalCap)
end

function Formulas.fieldCapacity(tier: number): number
	local def = Config.StadiumTiers[clamp(tier, 1, #Config.StadiumTiers)]
	return def.field
end

-- The match cash multiplier of a stadium tier.
function Formulas.tierCashMultiplier(tier: number): number
	return Config.StadiumTiers[clamp(tier, 1, #Config.StadiumTiers)].cashMultiplier
end

-- Level 0 is the base value; levels beyond the last upgrade return the last value.
function Formulas.storeValue(id: StoreUpgradeId, level: number): number
	local def = Config.Store[id]
	if level <= 0 then
		return def.baseValue
	end
	return def.values[math.min(level, #def.values)]
end

-- Price of the next level (level + 1), or nil at the maximum.
function Formulas.storePrice(id: StoreUpgradeId, level: number): number?
	return Config.Store[id].prices[level + 1]
end

export type PayoutInput = {
	fieldIncomes: { number }, -- income of each player on the field, already with levels and stars
	stadiumTier: number,
	season: number,
	momentumMatches: number?,
	boosts: { number }?,
	hatTrick: boolean?,
}

-- Normal income per match, with the stadium tier and season, without momentum, boosts or hat-trick.
-- This is also the base for offline earnings.
function Formulas.basePayout(input: PayoutInput): number
	local sum = 0
	for _, income in input.fieldIncomes do
		sum += income
	end
	local value = sum
		* Formulas.tierCashMultiplier(input.stadiumTier)
		* Formulas.seasonMultiplier(input.season)
	return value
end

-- Cash a finished match pays: base x field income x stadium tier x season x momentum x boosts
-- x hat-trick.
function Formulas.payout(input: PayoutInput): number
	local value = Formulas.basePayout(input)
		* Formulas.momentumMultiplier(input.momentumMatches or 0)
		* Formulas.boostMultiplier(input.boosts or {})
	if input.hatTrick then
		value *= Config.Match.hatTrickMultiplier
	end
	return round(value)
end

-- Offline -----------------------------------------------------------------------------------

-- Cash earned while away: time is clamped to the cap, only whole matches count, and the
-- offline rate (a share of normal income) applies.
function Formulas.offlineEarnings(
	secondsAway: number,
	matchSeconds: number,
	basePayout: number,
	offlineRate: number
): number
	local seconds = clamp(secondsAway, 0, Config.Offline.capSeconds)
	local matches = math.floor(seconds / matchSeconds)
	return round(matches * basePayout * offlineRate)
end

return Formulas
