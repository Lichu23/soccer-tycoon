--!strict
-- The small "1" on the Kick and Shop buttons the first time the player is on the map. It goes
-- away when the button is tapped and is saved, so it never comes back. It marks "new", not "buy":
-- it is not tied to any offer, timer or price.

export type Data = { flags: { [string]: any } }

local TileBadges = {}

TileBadges.ids = { "kick", "shop" } :: { string }

function TileBadges.valid(id: string): boolean
	return table.find(TileBadges.ids, id) ~= nil
end

function TileBadges.seen(data: Data, id: string): boolean
	local seen = data.flags.tilesSeen
	return type(seen) == "table" and seen[id] == true
end

-- Records that the button was tapped. False for an unknown id.
function TileBadges.markSeen(data: Data, id: string): boolean
	if not TileBadges.valid(id) then
		return false
	end
	if type(data.flags.tilesSeen) ~= "table" then
		data.flags.tilesSeen = {}
	end
	data.flags.tilesSeen[id] = true
	return true
end

return TileBadges
