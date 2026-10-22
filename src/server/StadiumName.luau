--!strict
-- The name a player types for their roof arena (docs/PLAN.md, Step 3). The text is tidied and checked
-- here (pure, unit tested), then filtered by Roblox before anyone sees it: a name the filter changes
-- at all is refused, so a sign never shows hashes. The typed text is saved and filtered again on every
-- join, because the filter's answer can change; only the filtered text is ever shown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Data = { cash: number, stadiumTier: number, stadiumName: string }

local StadiumName = {}

-- Letters, digits, spaces and a little punctuation; runs of spaces become one; no space at the ends.
function StadiumName.clean(raw: string): string
	local kept = string.gsub(raw, "[^%w %-'&%.!]", "")
	kept = string.gsub(kept, "%s+", " ")
	kept = string.gsub(kept, "^ ", "")
	kept = string.gsub(kept, " $", "")
	return kept
end

-- Whether `text` (already clean) may become the name: true, or false and the reason ("tier",
-- "length", "same", "cannotAfford").
function StadiumName.check(data: Data, text: string): (boolean, string?)
	local rules = Config.StadiumName
	if data.stadiumTier < #Config.StadiumTiers then
		return false, "tier"
	end
	local length = utf8.len(text) or #text
	if length < rules.minLength or length > rules.maxLength then
		return false, "length"
	end
	if text == data.stadiumName then
		return false, "same"
	end
	if data.cash < rules.price then
		return false, "cannotAfford"
	end
	return true, nil
end

-- The text as everyone may see it, or nil when the filter could not be reached. Yields.
function StadiumName.filter(player: Player, text: string): string?
	local ok, result = pcall(function()
		local TextService = game:GetService("TextService") -- here, so the unit tests can load this
		local filtered =
			TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

return StadiumName
