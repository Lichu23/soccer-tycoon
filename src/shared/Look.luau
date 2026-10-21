--!strict
-- How a player looks: skin tone, hair, face and the pattern of his kit. The skin tone and the hair
-- follow the real player where listed below (a rough match from a few blocky styles, not a likeness);
-- the rest is picked from the player's id, so it is always the same. Pure (colours are plain {r, g, b}
-- numbers), so it is unit tested.

export type Look = {
	skin: { number },
	hair: string, -- "short", "buzz", "tall", "long", "mohawk" or "bald"
	hairColor: { number },
	pattern: string, -- "stripes", "half", "hem" or "plain"
	face: string, -- "smile", "grin", "focus" or "smirk" (KitImages.faces)
	brows: string, -- "flat" or "raised" (KitImages.brows)
}

local SKIN_TONES: { { number } } = {
	{ 252, 226, 200 },
	{ 240, 200, 160 },
	{ 222, 170, 120 },
	{ 178, 124, 88 },
	{ 120, 82, 58 },
	{ 84, 58, 44 },
}

-- The skin tone of each real player, as an index into SKIN_TONES (1 the lightest, 6 the deepest). There
-- is no published list of this, so it is the way each one looks in public photos, matched to the
-- nearest of six tones. It is one table: change a number to change a player. A player not listed
-- gets a tone from his id.
local SKIN_OF: { [string]: number } = {
	rashford = 4,
	grealish = 1,
	sterling = 4,
	joao_felix = 2,
	son = 2,
	saka = 5,
	griezmann = 2,
	pedri = 2,
	trent = 4,
	gavi = 2,
	lautaro = 2,
	leao = 5,
	wirtz = 1,
	musiala = 4,
	lewandowski = 1,
	benzema = 3,
	modric = 1,
	kane = 1,
	de_bruyne = 1,
	rodri = 2,
	foden = 1,
	vinicius = 5,
	bellingham = 4,
	yamal = 4,
	salah = 3,
	neymar = 3,
	haaland = 1,
	mbappe = 5,
	cristiano = 2,
	messi = 2,
	ronaldinho = 5,
	zidane = 3,
	ronaldo_nazario = 3,
	maradona = 3,
	pele = 5,
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

-- The hair of each real player as { style, colour index into HAIR_COLORS }, the way he wears it in
-- public photos, matched to the nearest style the figures have ("short" spiky, "tall" swept back,
-- "long", "mohawk" for curls or locks, "buzz", "bald"). Change a line to change a player. A player not
-- listed gets a style and colour from his id.
local HAIR_OF: { [string]: { any } } = {
	rashford = { "buzz", 6 },
	grealish = { "tall", 3 },
	sterling = { "buzz", 6 },
	joao_felix = { "tall", 2 },
	son = { "short", 6 },
	saka = { "mohawk", 6 },
	griezmann = { "tall", 4 },
	pedri = { "long", 2 },
	trent = { "buzz", 6 },
	gavi = { "short", 2 },
	lautaro = { "short", 1 },
	leao = { "mohawk", 6 },
	wirtz = { "short", 3 },
	musiala = { "short", 6 },
	lewandowski = { "short", 2 },
	benzema = { "buzz", 6 },
	modric = { "long", 3 },
	kane = { "short", 3 },
	de_bruyne = { "short", 5 },
	rodri = { "short", 2 },
	foden = { "buzz", 4 },
	vinicius = { "mohawk", 6 },
	bellingham = { "buzz", 6 },
	yamal = { "mohawk", 6 },
	salah = { "mohawk", 6 },
	neymar = { "short", 4 },
	haaland = { "long", 4 },
	mbappe = { "buzz", 6 },
	cristiano = { "short", 6 },
	messi = { "tall", 2 },
	ronaldinho = { "long", 6 },
	zidane = { "bald", 1 },
	ronaldo_nazario = { "bald", 1 },
	maradona = { "mohawk", 6 },
	pele = { "buzz", 6 },
}

local PATTERNS = { "stripes", "half", "hem", "stripes", "plain", "hem" }

local FACES = { "smile", "grin", "focus", "smile", "smirk", "grin" }

local BROWS = { "flat", "raised" }

local Look = {}

Look.skinTones = SKIN_TONES
Look.skinOf = SKIN_OF
Look.hairOf = HAIR_OF
Look.hairStyles = HAIR_STYLES
Look.hairColors = HAIR_COLORS
Look.patterns = PATTERNS
Look.faces = FACES
Look.browStyles = BROWS

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
	local hair = HAIR_OF[id]
	return {
		skin = SKIN_TONES[SKIN_OF[id] or (value % #SKIN_TONES + 1)],
		hair = if hair then hair[1] else HAIR_STYLES[(value // 7) % #HAIR_STYLES + 1],
		hairColor = HAIR_COLORS[if hair then hair[2] else (value // 53) % #HAIR_COLORS + 1],
		pattern = PATTERNS[(value // 331) % #PATTERNS + 1],
		face = FACES[(value // 1013) % #FACES + 1],
		brows = BROWS[(value // 4099) % #BROWS + 1],
	}
end

return Look
