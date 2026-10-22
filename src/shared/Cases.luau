--!strict
-- The Robux cases (docs/PLAN.md, Step 3): who can open one, the exact chance of every player (and of
-- every x2 cash or TP boost in a case that has them) and the pick from a roll. The server rolls with this and the screen shows the same numbers before the
-- purchase, so what is shown is what is rolled. Pure, so it is unit tested.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData

export type Entry = { id: string, chance: number }

export type Summary = {
	reached: number, -- the chance of a player of a floor already open
	nextFloor: number,
	further: number,
	legend: number,
	boost: number, -- the chance of a x2 cash or TP boost instead of a player (0 in a case of players only)
	duplicate: number, -- the chance of a player the player already owns
}

local Cases = {}

function Cases.def(caseId: string): Config.CaseDef?
	return Config.Cases[caseId]
end

-- The case unlocks with floors: Standard when floor 2 starts, Elite when floor 2 is complete.
function Cases.unlocked(data: ProgressData, caseId: string): boolean
	local def = Config.Cases[caseId]
	return def ~= nil and Roster.floorsComplete(data) >= def.floorsComplete
end

-- The ids of one floor in slot order.
local function floorIds(floor: number): { string }
	local ids = {}
	for _, def in Config.Players do
		if def.floor == floor then
			table.insert(ids, def.id)
		end
	end
	return ids
end

-- Spreads `share` over players that are listed in slot order: each is `slotDecay` as likely as the
-- one before.
local function spread(into: { [string]: number }, ids: { string }, share: number)
	local total = 0
	local weights = {}
	for index in ids do
		local weight = Config.CaseRules.slotDecay ^ (index - 1)
		weights[index] = weight
		total += weight
	end
	for index, id in ids do
		into[id] = (into[id] or 0) + share * weights[index] / total
	end
end

-- Whether a pick from Cases.pick is a boost (Config.CaseBoosts) rather than a player.
function Cases.isBoost(id: string): boolean
	return Config.CaseBoostsById[id] ~= nil
end

-- The chance of every player in the case for this player's progress, then of every boost, and a
-- summary. The chances add up to 1. The boost and Legend chances are fixed; the rest is split by the
-- odds over the floors already open, the next floor and the floors further on (a share with no floor
-- in it goes to the others).
function Cases.odds(data: ProgressData, caseId: string): ({ Entry }, Summary)
	local def = Config.Cases[caseId]
	assert(def, "unknown case " .. tostring(caseId))
	local openFloor = math.min(Roster.floorsComplete(data) + 1, Config.CashFloors)
	local groups = {
		{ share = def.odds.reached, floors = {} :: { number } },
		{ share = def.odds.nextFloor, floors = {} :: { number } },
		{ share = def.odds.further, floors = {} :: { number } },
	}
	for floor = 1, Config.CashFloors do
		local group = if floor <= openFloor then 1 elseif floor == openFloor + 1 then 2 else 3
		table.insert(groups[group].floors, floor)
	end
	local used = 0
	for _, group in groups do
		if #group.floors > 0 then
			used += group.share
		end
	end

	local chances: { [string]: number } = {}
	local boostChance = def.boostChance or 0
	local rest = 1 - boostChance - def.legendChance
	local shares = { 0, 0, 0 }
	for index, group in groups do
		if #group.floors > 0 then
			local groupShare = rest * group.share / used
			shares[index] = groupShare
			for _, floor in group.floors do
				spread(chances, floorIds(floor), groupShare / #group.floors)
			end
		end
	end
	spread(chances, floorIds(Config.LegendFloor), def.legendChance)
	local summary: Summary = {
		reached = shares[1],
		nextFloor = shares[2],
		further = shares[3],
		legend = def.legendChance,
		boost = boostChance,
		duplicate = 0,
	}

	local entries: { Entry } = {}
	for _, playerDef in Config.Players do
		local chance = chances[playerDef.id]
		if chance then
			table.insert(entries, { id = playerDef.id, chance = chance })
			if data.players[playerDef.id] ~= nil then
				summary.duplicate += chance
			end
		end
	end
	if boostChance > 0 then
		local weights = 0
		for _, boost in Config.CaseBoosts do
			weights += boost.weight
		end
		for _, boost in Config.CaseBoosts do
			table.insert(entries, { id = boost.id, chance = boostChance * boost.weight / weights })
		end
	end
	return entries, summary
end

-- The player or boost a roll in [0, 1) lands on.
function Cases.pick(entries: { Entry }, roll: number): string
	local point = math.clamp(roll, 0, 0.999999999)
	for _, entry in entries do
		point -= entry.chance
		if point < 0 then
			return entry.id
		end
	end
	return entries[#entries].id
end

return Cases
