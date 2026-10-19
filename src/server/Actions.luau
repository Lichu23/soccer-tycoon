--!strict
-- Everything a player can buy or start, validated against the server state and applied in one
-- step (docs/PLAN.md, Steps 1 and 5). Every function returns true, or false and a reason. The
-- caller (a pad or a remote) never sends prices or amounts, only ids from Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(script.Parent.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local Legends = require(ReplicatedStorage.Shared.Legends)
local NewSeason = require(script.Parent.NewSeason)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Reveals = require(script.Parent.Reveals)

export type ActionSession = { data: ProfileSchema.Profile }

local Actions = {}

-- Set once at startup to publish attributes, send the snapshot and log milestones. `what` is
-- "player", "store" or "stadium" and `id` the player or Store upgrade id.
Actions.onChange = (function(_session: any, _what: string, _id: string?) end) :: (
	session: any,
	what: string,
	id: string?
) -> ()

function Actions.buyPlayer(session: ActionSession, id: string): (boolean, string?)
	local data = session.data
	local status = Progress.playerStatus(data, id)
	if status ~= "ready" then
		return false, status
	end
	local def = Config.PlayersById[id]
	if not Economy.spend(data, def.price) then
		return false, "cannotAfford"
	end
	Reveals.grant(data, id, false)
	-- The first player goes straight onto the court and the matches start: there is no extra
	-- button to find (the match loop starts when fieldStarted is true and the plot exists).
	data.fieldStarted = true
	Actions.onChange(session, "player", id)
	return true, nil
end

-- Buys a Legend with cash once floor 4 is reached and every goal of its trial is done.
function Actions.buyLegend(session: ActionSession, id: string): (boolean, string?)
	local data = session.data
	local status = Legends.status(data, id)
	if status ~= "ready" then
		return false, status
	end
	local def = Config.PlayersById[id]
	if not Economy.spend(data, def.price) then
		return false, "cannotAfford"
	end
	Reveals.grant(data, id, false)
	Actions.onChange(session, "player", id)
	return true, nil
end

-- Spends TP on the next level of an owned player (the level-up pad). `levelSeen` (when given) must
-- match the current level, like the Store, so a double tap cannot buy two levels.
function Actions.levelUp(session: ActionSession, id: string, levelSeen: number?): (boolean, string?)
	local data = session.data
	local status = Progress.levelStatus(data, id)
	if status ~= "ready" then
		return false, status
	end
	local owned = data.players[id]
	if levelSeen ~= nil and levelSeen ~= owned.level then
		return false, "stale"
	end
	local cost = Progress.levelCost(data, id)
	if cost == nil or not Economy.spendTp(data, cost) then
		return false, "cannotAfford"
	end
	owned.level += 1
	Actions.onChange(session, "level", id)
	return true, nil
end

-- `levelSeen` (when given) must match the current level, so a double tap cannot buy two levels.
function Actions.buyStore(
	session: ActionSession,
	id: Config.StoreUpgradeId,
	levelSeen: number?
): (boolean, string?)
	local data = session.data
	local status = Progress.storeStatus(data, id)
	if status ~= "ready" then
		return false, status
	end
	if levelSeen ~= nil and levelSeen ~= data.storeLevels[id] then
		return false, "stale"
	end
	local price = Progress.storePrice(data, id)
	if price == nil or not Economy.spend(data, price) then
		return false, "cannotAfford"
	end
	data.storeLevels[id] += 1
	Actions.onChange(session, "store", id)
	return true, nil
end

-- `tierSeen` (when given) is the tier the client saw, so a double tap cannot buy two tiers.
function Actions.upgradeStadium(session: ActionSession, tierSeen: number?): (boolean, string?)
	local data = session.data
	local status = Progress.stadiumStatus(data)
	if status ~= "ready" then
		return false, status
	end
	if tierSeen ~= nil and tierSeen ~= data.stadiumTier then
		return false, "stale"
	end
	local nextTier = Progress.nextTier(data)
	if nextTier == nil or not Economy.spend(data, nextTier.price) then
		return false, "cannotAfford"
	end
	data.stadiumTier = nextTier.tier
	Boosts.startStadium(data) -- every upgrade gives a free x2 for 5 minutes, reset not added
	Actions.onChange(session, "stadium", nil)
	return true, nil
end

-- Starts the next season (floor 3 must be complete). `seasonSeen` is the season the client saw.
function Actions.startSeason(
	session: ActionSession,
	seasonSeen: number?
): (NewSeason.Result?, string?)
	local result, reason = NewSeason.start(session.data, seasonSeen)
	if result == nil then
		return nil, reason
	end
	Actions.onChange(session, "season", nil)
	return result, nil
end

return Actions
