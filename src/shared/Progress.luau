--!strict
-- What can be bought next, and whether it can be bought now: players, Store upgrades and
-- stadium tiers (docs/PLAN.md, Steps 1 and 3). Pure data rules shared by server and client.

local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData
type StoreUpgradeId = Config.StoreUpgradeId

local Progress = {}

-- Players ---------------------------------------------------------------------------------

-- "owned", "unknown", "legend", "locked", "cannotAfford" or "ready".
function Progress.playerStatus(data: ProgressData, id: string): string
	local ok, reason = Roster.canBuy(data, id)
	if not ok then
		return reason or "unknown"
	end
	local def = Config.PlayersById[id]
	if data.cash < def.price then
		return "cannotAfford"
	end
	return "ready"
end

-- Store ---------------------------------------------------------------------------------

function Progress.storeLevel(data: ProgressData, id: StoreUpgradeId): number
	return data.storeLevels[id]
end

function Progress.storeUnlocked(data: ProgressData, id: StoreUpgradeId): boolean
	local def = Config.Store[id]
	if def.minTier and data.stadiumTier < def.minTier then
		return false
	end
	if def.floorsComplete and Roster.floorsComplete(data) < def.floorsComplete then
		return false
	end
	return true
end

-- Price of the next level, or nil at the maximum.
function Progress.storePrice(data: ProgressData, id: StoreUpgradeId): number?
	return Formulas.storePrice(id, Progress.storeLevel(data, id))
end

-- "locked", "maxed", "cannotAfford" or "ready".
function Progress.storeStatus(data: ProgressData, id: StoreUpgradeId): string
	if not Progress.storeUnlocked(data, id) then
		return "locked"
	end
	local price = Progress.storePrice(data, id)
	if price == nil then
		return "maxed"
	end
	if data.cash < price then
		return "cannotAfford"
	end
	return "ready"
end

-- Seconds between matches after the match speed upgrade.
function Progress.matchSeconds(data: ProgressData): number
	return Formulas.storeValue("matchSpeed", data.storeLevels.matchSpeed)
end

function Progress.hatTrickChance(data: ProgressData): number
	return Formulas.storeValue("hatTrick", data.storeLevels.hatTrick)
end

function Progress.offlineRate(data: ProgressData): number
	return Formulas.storeValue("offline", data.storeLevels.offline)
end

-- Training ----------------------------------------------------------------------------------

-- The training ground and the level-up pads open when floor 1 is complete (Step 4).
function Progress.trainingUnlocked(data: ProgressData): boolean
	return Roster.floorsComplete(data) >= 1
end

-- TP for the next level of an owned player, or nil at the cap (or when not owned).
function Progress.levelCost(data: ProgressData, id: string): number?
	local def = Config.PlayersById[id]
	local owned = data.players[id]
	if def == nil or owned == nil or owned.level >= Formulas.levelCap(def.rarity) then
		return nil
	end
	return Formulas.levelCost(def.rarity, owned.level + 1)
end

-- "notOwned", "locked" (training not open yet), "maxed", "cannotAfford" or "ready".
function Progress.levelStatus(data: ProgressData, id: string): string
	if data.players[id] == nil or Config.PlayersById[id] == nil then
		return "notOwned"
	end
	if not Progress.trainingUnlocked(data) then
		return "locked"
	end
	local cost = Progress.levelCost(data, id)
	if cost == nil then
		return "maxed"
	end
	if data.tp < cost then
		return "cannotAfford"
	end
	return "ready"
end

-- Stadium ---------------------------------------------------------------------------------

-- The next stadium tier, or nil at the top tier.
function Progress.nextTier(data: ProgressData): Config.StadiumTierDef?
	return Config.StadiumTiers[data.stadiumTier + 1]
end

-- "maxed", "cannotAfford" or "ready".
function Progress.stadiumStatus(data: ProgressData): string
	local nextTier = Progress.nextTier(data)
	if nextTier == nil then
		return "maxed"
	end
	if data.cash < nextTier.price then
		return "cannotAfford"
	end
	return "ready"
end

return Progress
