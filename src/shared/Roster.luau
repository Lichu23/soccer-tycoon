--!strict
-- Owned players, floors and the field lineup. Pure data rules (docs/PLAN.md, Step 1):
-- the field is always filled with the owned players that earn the most, the top N by tier.

local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Types = require(script.Parent.Types)

type ProgressData = Types.ProgressData
type PlayerDef = Config.PlayerDef

local Roster = {}

function Roster.owns(data: ProgressData, id: string): boolean
	return data.players[id] ~= nil
end

function Roster.ownedCount(data: ProgressData): number
	local count = 0
	for _ in data.players do
		count += 1
	end
	return count
end

-- Adds a player at level 0 with no stars. False when unknown or already owned.
function Roster.add(data: ProgressData, id: string): boolean
	if Config.PlayersById[id] == nil or data.players[id] ~= nil then
		return false
	end
	data.players[id] = { level = 0, stars = 0 }
	return true
end

-- Cash per match this player earns on the field (base income with level and stars).
function Roster.income(data: ProgressData, id: string): number
	local def = Config.PlayersById[id]
	local owned = data.players[id]
	if def == nil or owned == nil then
		return 0
	end
	return Formulas.playerIncome(def.income, owned.level, owned.stars)
end

function Roster.floorComplete(data: ProgressData, floor: number): boolean
	local found = false
	for _, def in Config.Players do
		if def.floor == floor then
			found = true
			if data.players[def.id] == nil then
				return false
			end
		end
	end
	return found
end

-- Floors completed one after another from floor 1. A floor opens when the previous one is
-- complete, so a later complete floor does not count past a gap.
function Roster.floorsComplete(data: ProgressData): number
	local count = 0
	for floor = 1, Config.LegendFloor do
		if not Roster.floorComplete(data, floor) then
			break
		end
		count += 1
	end
	return count
end

-- Whether the stairs and gate to a floor are open: floor 1 always, any later floor once the
-- floor before it is complete (docs/PLAN.md, Step 1).
function Roster.floorUnlocked(data: ProgressData, floor: number): boolean
	if floor <= 1 then
		return true
	end
	return Roster.floorsComplete(data) >= floor - 1
end

-- Why a player cannot be bought from a pad: "unknown", "owned", "legend" (Legends are earned
-- through the Legend Trials) or "locked" (an earlier floor is not complete).
function Roster.canBuy(data: ProgressData, id: string): (boolean, string?)
	local def = Config.PlayersById[id]
	if def == nil then
		return false, "unknown"
	end
	if data.players[id] ~= nil then
		return false, "owned"
	end
	if def.floor >= Config.LegendFloor then
		return false, "legend"
	end
	if def.floor > Roster.floorsComplete(data) + 1 then
		return false, "locked"
	end
	return true, nil
end

-- The cheapest player that can still be bought on an open floor.
function Roster.nextUnowned(data: ProgressData): PlayerDef?
	for _, def in Config.Players do
		if Roster.canBuy(data, def.id) then
			return def
		end
	end
	return nil
end

-- The ids of the players on the field: the owned players that earn the most, up to the
-- stadium tier's capacity. Ties go to the more valuable (higher slot) player.
function Roster.field(data: ProgressData): { string }
	local entries: { { id: string, income: number, slot: number } } = {}
	for id in data.players do
		local def = Config.PlayersById[id]
		if def then
			table.insert(entries, { id = id, income = Roster.income(data, id), slot = def.slot })
		end
	end
	table.sort(entries, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.slot > b.slot
	end)
	local capacity = Formulas.fieldCapacity(data.stadiumTier)
	local ids = {}
	for index = 1, math.min(capacity, #entries) do
		table.insert(ids, entries[index].id)
	end
	return ids
end

function Roster.fieldIncomes(data: ProgressData): { number }
	local incomes = {}
	for _, id in Roster.field(data) do
		table.insert(incomes, Roster.income(data, id))
	end
	return incomes
end

return Roster
