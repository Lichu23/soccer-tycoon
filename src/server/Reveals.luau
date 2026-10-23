--!strict
-- Rarity reveals (docs/PLAN.md, Step 3 and 7): which grants play a reveal and what it shows. Pure on
-- the profile, so it is unit tested. A reveal is saved as pending when the player is granted, and
-- removed when the client says it has played, so a disconnect mid-reveal shows it on the next join.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Roster = require(ReplicatedStorage.Shared.Roster)

local Reveals = {}

-- The newest reveals are kept if a client never acknowledges them.
Reveals.MAX_PENDING = 20

local function push(data: ProfileSchema.Profile, entry: ProfileSchema.PendingReveal)
	table.insert(data.pendingReveals, entry)
	while #data.pendingReveals > Reveals.MAX_PENDING do
		table.remove(data.pendingReveals, 1)
	end
end

-- Gives a player (a new one at level 0, or +1 star when it is a duplicate from a case) and records
-- the reveal that goes with it. Returns the pending reveal, or nil when nothing is shown:
--   * a new player of a rarity the player has seen before, bought from a pad (the small reveal of
--     Step 2 is separate), and
--   * a duplicate from anywhere but a case.
-- `fromCase` is true for case wins: every one of them gets a reveal.
function Reveals.grant(
	data: ProfileSchema.Profile,
	id: string,
	fromCase: boolean
): ProfileSchema.PendingReveal?
	local def = Config.PlayersById[id]
	if def == nil then
		return nil
	end
	local owned = data.players[id]
	if owned == nil then
		Roster.add(data, id)
		local first = not data.seenRarities[def.rarity]
		data.seenRarities[def.rarity] = true
		if not first and not fromCase then
			return nil
		end
		-- The very first purchase gets the full reveal too; the first match waits for it (Match).
		local entry: ProfileSchema.PendingReveal = {
			playerId = id,
			isNew = true,
			firstOfRarity = first,
			short = false,
		}
		push(data, entry)
		return entry
	end
	if not fromCase then
		return nil
	end
	local gained = if owned.stars < Config.Stars.maxStars then 1 else 0
	owned.stars += gained
	local entry: ProfileSchema.PendingReveal = {
		playerId = id,
		isNew = false,
		firstOfRarity = false,
		short = false,
		starsGained = gained,
		stars = owned.stars,
	}
	push(data, entry)
	return entry
end

-- Removes the oldest pending reveal of this player. False when there was none.
function Reveals.acknowledge(data: ProfileSchema.Profile, id: string): boolean
	for index, entry in data.pendingReveals do
		if entry.playerId == id then
			table.remove(data.pendingReveals, index)
			return true
		end
	end
	return false
end

return Reveals
