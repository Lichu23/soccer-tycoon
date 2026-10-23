--!strict
-- The four plaza leaderboards around the spawn: what each one ranks, its title, accent and how its
-- score reads. The server ranks (server/LeaderboardService), the client draws (client/Scoreboards), and
-- tools/studio/BuildLeaderboards builds the boards. Also the pure merge of the stored top 10 with
-- the players in this server, so it is unit tested.

local NumberFormat = require(script.Parent.NumberFormat)

export type Entry = { userId: number, name: string, value: number }

export type Board = {
	id: string, -- the model name in Map.Plaza.Leaderboards and the OrderedDataStore key part
	title: string,
	accent: string, -- a Style.ui colour name (kept as a name so this stays pure for the tests)
	format: (value: number) -> string,
}

local Leaderboards = {}

Leaderboards.SIZE = 10 -- rows on each board

Leaderboards.boards = {
	{
		id = "Juggles",
		title = "TOP JUGGLES",
		accent = "bar",
		format = function(value: number): string
			return tostring(value)
		end,
	},
	{
		id = "Robux",
		title = "TOP ROBUX SPENT",
		accent = "gold",
		format = function(value: number): string
			return "R$ " .. NumberFormat.short(value)
		end,
	},
	{
		id = "Money",
		title = "TOP MONEY EARNED",
		accent = "good",
		format = function(value: number): string
			return NumberFormat.money(value)
		end,
	},
	{
		id = "Seasons",
		title = "TOP SEASONS",
		accent = "purple",
		format = function(value: number): string
			return "Season " .. tostring(value)
		end,
	},
} :: { Board }

-- Joins the stored top list with the live scores of the players here (they can be ahead of the
-- store), keeps each user's best, sorts high to low (ties: lower user id first) and keeps `size`.
function Leaderboards.merge(stored: { Entry }, live: { Entry }, size: number): { Entry }
	local best: { [number]: Entry } = {}
	for _, list in { stored, live } do
		for _, entry in list do
			local current = best[entry.userId]
			if entry.value > 0 and (current == nil or entry.value > current.value) then
				best[entry.userId] = {
					userId = entry.userId,
					name = if entry.name ~= ""
						then entry.name
						elseif current then current.name
						else "",
					value = entry.value,
				}
			elseif current and current.name == "" and entry.name ~= "" then
				current.name = entry.name
			end
		end
	end
	local merged: { Entry } = {}
	for _, entry in best do
		table.insert(merged, entry)
	end
	table.sort(merged, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	for index = #merged, size + 1, -1 do
		merged[index] = nil
	end
	return merged
end

return Leaderboards
