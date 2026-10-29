--!strict
-- New Season rules that both sides show (docs/PLAN.md, Step 1): when the button is hidden, locked or
-- ready, what the next season keeps, the trophy names and the re-climb estimate. Pure, so it is unit
-- tested. The reset itself is the server's (NewSeason).

local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Progress = require(script.Parent.Progress)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

local Season = {}

-- The last cash floor: completing it opens the Legends hall and the New Season.
Season.LAST_CASH_FLOOR = Config.LegendFloor - 1

-- "hidden" (floor 1 not complete yet), "locked" (floor 1 done, floor 3 not complete: the preview) or
-- "ready".
function Season.state(data: ProgressData): string
	local complete = Roster.floorsComplete(data)
	if complete >= Season.LAST_CASH_FLOOR then
		return "ready"
	elseif complete >= 1 then
		return "locked"
	end
	return "hidden"
end

-- Players still to buy on floor 3 and how many it has, for the "how much is left" line.
function Season.lastFloorProgress(data: ProgressData): (number, number)
	local owned, total = 0, 0
	for _, def in Config.Players do
		if def.floor == Season.LAST_CASH_FLOOR then
			total += 1
			if data.players[def.id] ~= nil then
				owned += 1
			end
		end
	end
	return owned, total
end

-- The floors the season after `finished` starts with already owned.
function Season.keptFloors(finished: number): number
	return Formulas.headStartFloors(finished + 1)
end

-- Generic names for the trophy of a finished season (kept here so they are easy to swap).
local TROPHIES = { "Street Cup", "City Cup", "National Cup", "Continental Cup", "World Cup" }

function Season.trophyName(finished: number): string
	local number = math.max(finished, 1)
	if number <= #TROPHIES then
		return TROPHIES[number]
	end
	return `{TROPHIES[#TROPHIES]} {number - #TROPHIES + 1}`
end

-- Whether the player can start the season after `finished`: "ok", "locked" (floor 3 not complete).
function Season.canStart(data: ProgressData): (boolean, string?)
	if Season.state(data) ~= "ready" then
		return false, "locked"
	end
	return true, nil
end

-- The roster a season starts with: the players of the head-start floors at level 0, no stars.
function Season.headStartPlayers(finished: number): { string }
	local floors = Season.keptFloors(finished)
	local ids = {}
	for _, def in Config.Players do
		if def.floor <= floors then
			table.insert(ids, def.id)
		end
	end
	return ids
end

type Option = { kind: string, id: string?, cost: number }

-- What a player can buy next in the climb: the next player, the match speed upgrade and
-- the next stadium tier.
local function options(view: ProgressData): { Option }
	local list: { Option } = {}
	local def = Roster.nextUnowned(view)
	if def then
		table.insert(list, { kind = "player", id = def.id, cost = def.price })
	end
	for id in Config.Store do
		if id ~= "matchSpeed" then
			continue
		end
		local status = Progress.storeStatus(view, id)
		local price = Progress.storePrice(view, id)
		if (status == "ready" or status == "cannotAfford") and price then
			local option: Option = { kind = "store", id = id :: string, cost = price }
			table.insert(list, option)
		end
	end
	local tier = Progress.nextTier(view)
	if tier then
		table.insert(list, { kind = "stadium", id = nil, cost = tier.price })
	end
	return list
end

-- About how long floor 3 takes again: a player who always buys the cheapest of the next player, the
-- match speed upgrade and the next stadium tier the moment it is affordable, earning the
-- plain match payout (no boosts, momentum, hat-tricks, levels or stars). Seconds, an estimate.
function Season.estimateSeconds(finished: number): number
	local nextSeason = finished + 1
	local players: { [string]: Types.OwnedPlayer } = {}
	for _, id in Season.headStartPlayers(finished) do
		players[id] = { level = 0, stars = 0 }
	end
	local view: ProgressData = {
		cash = Config.StartingCash,
		tp = 0,
		stadiumTier = 1,
		storeLevels = { matchSpeed = 0, hatTrick = 0, gymRate = 0, gymTier = 0 },
		fieldStarted = true,
		players = players,
		cosmetics = { owned = {}, chosen = {} },
	}
	local seconds = 0
	for _ = 1, 300 do
		if Roster.floorsComplete(view) >= Season.LAST_CASH_FLOOR then
			return seconds
		end
		local pick: Option? = nil
		for _, option in options(view) do
			if pick == nil or option.cost < pick.cost then
				pick = option
			end
		end
		if pick == nil then
			break
		end
		if view.cash < pick.cost then
			local perMatch = Formulas.basePayout({
				fieldIncomes = Roster.fieldIncomes(view),
				stadiumTier = view.stadiumTier,
				season = nextSeason,
			})
			if perMatch <= 0 then
				break
			end
			local matches = math.ceil((pick.cost - view.cash) / perMatch)
			seconds += matches * Progress.matchSeconds(view)
			view.cash += matches * perMatch
		end
		view.cash -= pick.cost
		if pick.kind == "player" and pick.id then
			Roster.add(view, pick.id)
		elseif pick.kind == "store" and pick.id then
			(view.storeLevels :: any)[pick.id] += 1
		else
			view.stadiumTier += 1
		end
	end
	return math.huge
end

return Season
