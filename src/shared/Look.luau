--!strict
-- How a player looks: skin tone, hair and the pattern of his kit. Picked from the player's id, so
-- it is always the same and needs no data in the player list. Generic variety only: nothing here is
-- meant to look like a real person. Pure (colours are plain {r, g, b} numbers), so it is unit tested.

export type Look = {
	skin: { number },
	hair: string, -- "short", "buzz", "tall", "long", "mohawk" or "bald"
	hairColor: { number },
	pattern: string, -- "stripes", "half", "hem" or "plain"
}

local SKIN_TONES: { { number } } = {
	{ 252, 226, 200 },
	{ 240, 200, 160 },
	{ 222, 170, 120 },
	{ 178, 124, 88 },
	{ 120, 82, 58 },
	{ 84, 58, 44 },
}

local HAIR_STYLES = { "short", "buzz", "tall", "long", "mohawk", "short", "bald", "buzz" }

local HAIR_COLORS: { { number } } = {
	{ 30, 24, 22 },
	{ 70, 48, 34 },
	{ 112, 78, 48 },
	{ 214, 178, 96 },
	{ 170, 82, 40 },
	{ 20, 20, 24 },
}

local PATTERNS = { "stripes", "half", "hem", "stripes", "plain", "hem" }

local Look = {}

Look.skinTones = SKIN_TONES
Look.hairStyles = HAIR_STYLES
Look.hairColors = HAIR_COLORS
Look.patterns = PATTERNS

-- A small stable hash of the id (the same in every session and on every machine).
local function hash(id: string): number
	local value = 5381
	for index = 1, #id do
		value = (value * 33 + string.byte(id, index)) % 2147483647
	end
	return value
end

function Look.of(id: string): Look
	local value = hash(id)
	return {
		skin = SKIN_TONES[value % #SKIN_TONES + 1],
		hair = HAIR_STYLES[(value // 7) % #HAIR_STYLES + 1],
		hairColor = HAIR_COLORS[(value // 53) % #HAIR_COLORS + 1],
		pattern = PATTERNS[(value // 331) % #PATTERNS + 1],
	}
end

return Look
